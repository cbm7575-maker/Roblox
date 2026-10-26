-- FriendsService (ModuleScript, ServerScriptService.Services.FriendsService)
-- Playing with Roblox friends (the phone's CREW app shows all of this).
--   * Arriving with a friend: the phone's INVITE FRIENDS button opens Roblox's invite pop-up with the
--     inviter's UserId as LaunchData (it can show up a few seconds after the join, so it's asked again
--     for up to LAUNCH_TRIES seconds); the phone's JOIN button (below) teleports with TeleportData
--     { Follow = friend's UserId }. When a player arrives either way while that friend is in this server
--     and Roblox says they really are friends, the friend is told once the newcomer has picked a side
--     and their save has loaded (or after READY_WAIT anyway). Anyone can put a UserId in a join link's
--     launchData, so an invite only speaks for the inviter when they opened INVITE FRIENDS in this
--     server within INVITE_WINDOW: then the newcomer gets the inviter's crew invite card
--     (CrewService.Invite). An invited or JOINing newcomer who is ready is moved to stand beside the
--     friend and their parked car is brought to the road in front of them (if there's room). The move
--     only happens when both roam free (TeamService.IsFreeRoaming: Civilian, not wanted, not inside a
--     home), the friend is standing (or stopped) on open city ground off the prison island, and there's
--     a clear spot in sight of them; otherwise the normal spawn stands. While that move may still come
--     (player attribute MeetPending), HousingService doesn't take a home owner inside their home.
--   * JOIN: RequestFriends("Join", friendUserId, jobId) teleports to a friend's other server of this game.
--     The server checks the friendship itself and goes only where Roblox says the friend is right now
--     (the client's jobId, from a list that may be old, is ignored). Not from prison, not while wanted,
--     not with bag cash (it would be lost). Teleports never work in Studio, so there it only says so.
--   * Co-op bonus (Roblox rules: nothing is ever paid for sending an invite, only for playing together):
--     every minute, a player who moved around while an active Roblox friend (CrewService.AreFriends)
--     did too counts one minute with a friend. COPLAY_MINUTES of them in a UTC day pay COPLAY_CASH once
--     that day and count one co-op day; SQUAD_DAYS co-op days unlock the Squad paint (Unlock_Squad).
--     In Studio the test players (negative UserIds) count as friends and 2 minutes are enough.
-- Saved: data.coplay = { days = co-op days, last = UTC day last paid, day = UTC day of mins, mins },
-- data.flags.squad = true once unlocked.
-- Player attributes: CoplayMins (minutes with a friend today), CoplayDone (today's bonus paid),
-- CoplayDays, Unlock_Squad. ReplicatedStorage attributes CoplayMinutes, CoplayCash, CoplaySquadDays
-- hold the rules so the phone quotes them.
-- Remote: RequestFriends(action, ...) with action "Join" (userId, jobId) | "InvitePrompt" (analytics, and
-- marks when this player last opened the invite pop-up; it never pays).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local CrewService = require(ServerScriptService.Services.CrewService)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local GarageService = require(ServerScriptService.Services.GarageService)
local TeamService = require(ServerScriptService.Services.TeamService)
local VehicleService = require(ServerScriptService.Services.VehicleService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local FriendsService = {}

local STUDIO = RunService:IsStudio()
local TICK = 60 -- seconds per co-op minute check
local COPLAY_MINUTES = STUDIO and 2 or 10
local COPLAY_CASH = 2000
local SQUAD_DAYS = 3
local MOVE_MIN = 20 -- studs a player must move in a minute to count as playing (not away from keys)
local SETTLE = 4 -- seconds after the save loads before moving a newcomer (the starter car finishes first)
local READY_WAIT = 120 -- seconds to wait for a newcomer to pick a side before giving up on the meet-up
local HOST_MAX_SPEED = 25 -- studs/s: a friend driving faster than this is mid-drive, so no meet-up
local JOIN_GUARD = 20 -- seconds a JOIN request blocks another (the teleport is under way)
local LAUNCH_TRIES = 10 -- seconds to keep asking for an invite's LaunchData (Roblox's own sample does the same)
local INVITE_WINDOW = 3600 -- seconds after opening INVITE FRIENDS that an arrival with our UserId counts as invited
-- Saltmarsh Prison's island (the same box as PrisonService's ISLAND): never a meet-up spot.
local ISLAND = { xMin = -1760, xMax = -1090, zMin = 990, zMax = 1710 }

local notify
local loadedAt = {} -- [player] = os.clock() when their save loaded
local lastPos = {} -- [player] = root position at the last co-op check
local joining = {} -- [player] = os.clock() of their last JOIN teleport
local invitedAt = {} -- [player] = os.clock() when they last opened the INVITE FRIENDS pop-up

local function today()
	return math.floor(os.time() / 86400)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ co-op bonus

local function coplayOf(data)
	if type(data.coplay) ~= "table" then
		data.coplay = {}
	end
	local c = data.coplay
	c.days = tonumber(c.days) or 0
	c.mins = tonumber(c.mins) or 0
	return c
end

local function friends(a, b)
	if STUDIO and a.UserId < 0 and b.UserId < 0 then
		return true -- Studio's test players (Player1, Player2...) so co-op play can be tested
	end
	return CrewService.AreFriends(a, b)
end

-- One more minute with a friend today; the COPLAY_MINUTES-th pays the daily bonus.
local function credit(player, data, c, day)
	c.mins += 1
	player:SetAttribute("CoplayMins", c.mins)
	if c.mins == 1 then
		Telemetry.Custom(player, "CoPlayFirstMinute", 1)
	end
	if c.mins < COPLAY_MINUTES then
		return
	end
	c.last = day
	c.days += 1
	player:SetAttribute("CoplayDone", true)
	player:SetAttribute("CoplayDays", c.days)
	EconomyService.AddCash(player, COPLAY_CASH, "coplay:daily")
	notify:FireClient(player, "CoplayBonus")
	Telemetry.Custom(player, "CoPlayDay", c.days)
	data.flags = data.flags or {}
	if c.days >= SQUAD_DAYS and not data.flags.squad then
		data.flags.squad = true
		player:SetAttribute("Unlock_Squad", true)
		notify:FireClient(player, "SquadUnlocked")
		Telemetry.Custom(player, "SquadUnlocked", 1)
	end
	task.spawn(DataService.SaveNow, player)
end

local function tick()
	local day = today()
	local list = Players:GetPlayers()
	local active = {}
	for _, p in ipairs(list) do
		local root = rootOf(p)
		local pos = root and root.Position
		local was = lastPos[p]
		lastPos[p] = pos
		active[p] = pos ~= nil and was ~= nil and (pos - was).Magnitude >= MOVE_MIN
	end
	for _, p in ipairs(list) do
		local data = DataService.Get(p)
		if data then
			local c = coplayOf(data)
			if c.day ~= day then -- a new UTC day: count from zero again
				c.day, c.mins = day, 0
				p:SetAttribute("CoplayMins", 0)
				p:SetAttribute("CoplayDone", nil)
			end
			if active[p] and c.last ~= day then
				for _, other in ipairs(list) do
					if other ~= p and active[other] and friends(p, other) then
						credit(p, data, c, day)
						break
					end
				end
			end
		end
	end
end

local function onLoaded(player, data)
	loadedAt[player] = os.clock()
	data.flags = data.flags or {}
	local c = coplayOf(data)
	local day = today()
	if c.day ~= day then
		c.day, c.mins = day, 0
	end
	player:SetAttribute("CoplayMins", c.mins)
	player:SetAttribute("CoplayDone", c.last == day or nil)
	player:SetAttribute("CoplayDays", c.days)
	if c.days >= SQUAD_DAYS then
		data.flags.squad = true
	end
	if data.flags.squad then
		player:SetAttribute("Unlock_Squad", true)
	end
end

------------------------------------------------------------------ meeting a friend who brought you here

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true
local roomParams = OverlapParams.new()
roomParams.FilterType = Enum.RaycastFilterType.Exclude
roomParams.RespectCanCollide = true

-- A clear spot on the ground a few studs beside `root` (the friend), facing them, or nil.
local function spotBeside(root)
	local city = Workspace:FindFirstChild("City")
	local ground = {}
	for _, name in ipairs({ "Roads", "Ground" }) do
		local f = city and city:FindFirstChild(name)
		if f then
			table.insert(ground, f)
		end
	end
	if #ground == 0 then
		return nil
	end
	groundParams.FilterDescendantsInstances = ground
	local pos = root.Position
	if pos.X > ISLAND.xMin and pos.X < ISLAND.xMax and pos.Z > ISLAND.zMin and pos.Z < ISLAND.zMax then
		return nil
	end
	-- The friend must be on the open city: not up a building, in a home's inside far off the map, or at sea.
	local under = Workspace:Raycast(pos, Vector3.new(0, -12, 0), groundParams)
	if not under then
		return nil
	end
	-- People and cars don't block the line of sight (the friend may be sitting in theirs); anything
	-- solid standing on the spot does, cars included.
	local people = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(people, p.Character)
		end
	end
	local see = table.clone(people)
	local cars = Workspace:FindFirstChild("Vehicles")
	if cars then
		table.insert(see, cars)
	end
	sightParams.FilterDescendantsInstances = see
	roomParams.FilterDescendantsInstances = people
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis)
	for _, offset in ipairs({ right * 6, -right * 6, -look * 6, look * 7, right * 10, -right * 10 }) do
		local probe = pos + offset
		local hit = Workspace:Raycast(probe + Vector3.new(0, 6, 0), Vector3.new(0, -18, 0), groundParams)
		if hit and hit.Normal.Y > 0.8 and math.abs(hit.Position.Y - under.Position.Y) < 3 then
			local stand = hit.Position + Vector3.new(0, 3, 0)
			-- The box starts a stud above the ground, so kerbs and the road itself don't count.
			if not Workspace:Raycast(pos, stand - pos, sightParams)
				and #Workspace:GetPartBoundsInBox(CFrame.new(stand + Vector3.new(0, 0.5, 0)), Vector3.new(3, 5, 3), roomParams) == 0 then
				return CFrame.lookAt(stand, Vector3.new(pos.X, stand.Y, pos.Z))
			end
		end
	end
	return nil
end

-- The newcomer's starter car went to a pad (or their driveway) before the move: park it on the road in
-- front of them instead (VehicleService finds the spot; no room there and it stays where it was).
local function bringCar(player)
	local car = VehicleService.GetCar(player)
	local id = player:GetAttribute("LastCar")
	local def = type(id) == "string" and Vehicles.ById[id]
	if not car or not def or def.Boat or not VehicleService.CanDrive("Civilian", id) or not GarageService.Owns(player, id) then
		return
	end
	for _, seat in ipairs(car:GetDescendants()) do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			if seat.Occupant then
				return
			end
		end
	end
	VehicleService.Spawn(player, id, { IgnoreCooldown = true, Auto = true })
end

-- Move `player` beside `host` when it's safe. Returns true if they were moved.
local function placeBeside(player, host)
	local function ok()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local hostRoot = rootOf(host)
		return hum ~= nil and hum.Health > 0 and hum.SeatPart == nil and hostRoot ~= nil
			and host.Parent == Players and player.Parent == Players
			and TeamService.IsFreeRoaming(player) and TeamService.IsFreeRoaming(host)
			and hostRoot.AssemblyLinearVelocity.Magnitude <= HOST_MAX_SPEED
	end
	if not ok() then
		return false
	end
	local cf = spotBeside(rootOf(host))
	if not cf then
		return false
	end
	local char = player.Character
	pcall(player.RequestStreamAroundAsync, player, cf.Position, 3)
	-- Loading the area can take a few seconds: check everything again.
	if player.Character ~= char or not ok() then
		return false
	end
	char:PivotTo(cf)
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	bringCar(player)
	return true
end

-- fn(true) once the newcomer is ready: they've picked a side (a returning prisoner never sees the
-- picker) and their save loaded SETTLE seconds ago. Still not ready after READY_WAIT: fn(false).
local function whenReady(player, fn)
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < READY_WAIT do
			if player.Parent ~= Players then
				return
			end
			local picked = player:GetAttribute("HasPicked") == true or player:GetAttribute("Side") == "Prisoner"
			local at = loadedAt[player]
			if picked and at and os.clock() - at >= SETTLE then
				fn(true)
				return
			end
			task.wait(0.5)
		end
		if player.Parent == Players then
			fn(false) -- still on the side picker (or away): tell the friend anyway, just no move
		end
	end)
end

-- `player` arrived through `hostId`'s invite (via "Invite") or by following them (via "Join").
local function meet(player, hostId, via)
	local host = Players:GetPlayerByUserId(hostId)
	if not host or player.Parent ~= Players then
		return
	end
	local okFriend, isFriend = pcall(player.IsFriendsWith, player, hostId)
	if not okFriend or not isFriend or host.Parent ~= Players then
		return
	end
	-- Counted on arrival, so a newcomer who never picks a side still shows in the invite funnel.
	Telemetry.Custom(player, via == "Invite" and "ArrivedByInvite" or "ArrivedByJoin", 1)
	Telemetry.Custom(host, "FriendArrived", 1)
	-- A move beside the friend may follow: until it's done (or off), HousingService doesn't take a home
	-- owner inside their home, which would win over the meet-up.
	local sent = invitedAt[host]
	if via == "Join" or (sent ~= nil and os.clock() - sent < INVITE_WINDOW) then
		player:SetAttribute("MeetPending", true)
	end
	whenReady(player, function(ready)
		if host.Parent ~= Players then
			player:SetAttribute("MeetPending", nil)
			return
		end
		-- Anyone can put a UserId in a join link's launchData: only an invite the host really opened here
		-- lately sends their crew card (the host never agreed to anything else).
		local at = invitedAt[host]
		local invited = via == "Invite" and at ~= nil and os.clock() - at < INVITE_WINDOW
		local carded = invited and CrewService.Invite(host, player)
		notify:FireClient(host, carded and "FriendArrivedCrew" or "FriendArrived")
		-- A JOIN is the newcomer's own choice to follow the friend, so it gets the move as well.
		local moved = ready and (invited or via == "Join") and placeBeside(player, host)
		player:SetAttribute("MeetPending", nil)
		notify:FireClient(player, moved and "FriendMeetup" or "FriendInServer")
	end)
end

local function hasLaunchData(join)
	local launch = join.LaunchData
	return (type(launch) == "string" and launch ~= "") or type(launch) == "number"
end

local function onPlayerAdded(player)
	local ok, join = pcall(player.GetJoinData, player)
	if not ok or type(join) ~= "table" then
		return
	end
	-- An invite's LaunchData can take a few seconds to show up after the join, so ask again once a
	-- second for a while (a teleported player's join data is complete from the start).
	if join.SourcePlaceId == nil and not hasLaunchData(join) then
		for _ = 1, LAUNCH_TRIES do
			task.wait(1)
			if player.Parent ~= Players then
				return
			end
			local ok2, join2 = pcall(player.GetJoinData, player)
			if ok2 and type(join2) == "table" and hasLaunchData(join2) then
				join = join2
				break
			end
		end
	end
	local hostId, via
	-- LaunchData comes from the invite (a string): the inviter's UserId.
	local launch = join.LaunchData
	if type(launch) == "string" or type(launch) == "number" then
		hostId, via = tonumber(launch), "Invite"
	end
	-- TeleportData only counts from our own place (the JOIN button's teleport).
	local data = join.TeleportData
	if not hostId and type(data) == "table" and join.SourcePlaceId == game.PlaceId then
		hostId, via = tonumber(data.Follow), "Join"
	end
	if not hostId or hostId ~= math.floor(hostId) or hostId <= 0 or hostId > 1e15 or hostId == player.UserId then
		return
	end
	meet(player, hostId, via)
end

------------------------------------------------------------------ JOIN a friend's other server

-- The client also sends the friend's jobId from its list; it's ignored (the list may be old, and a
-- client could name any server).
local function onJoin(player, userId)
	if type(userId) ~= "number" or userId ~= math.floor(userId) or userId <= 0 or userId > 1e15 then
		return
	end
	if Players:GetPlayerByUserId(userId) then
		return notify:FireClient(player, "FriendInServer") -- they came here since the phone's list was fetched
	end
	if joining[player] and os.clock() - joining[player] < JOIN_GUARD then
		return
	end
	if TeamService.GetSide(player) == "Prisoner" then
		return notify:FireClient(player, "FriendJoinPrison")
	end
	if (player:GetAttribute("Heat") or 0) > 0 then
		return notify:FireClient(player, "FriendJoinWanted")
	end
	if EconomyService.GetCarried(player) > 0 then
		return notify:FireClient(player, "FriendJoinBag")
	end
	if STUDIO then
		return notify:FireClient(player, "FriendJoinStudio")
	end
	joining[player] = os.clock()
	local okFriend, isFriend = pcall(player.IsFriendsWith, player, userId)
	if not okFriend or not isFriend then
		joining[player] = nil
		return notify:FireClient(player, "FriendJoinFailed")
	end
	-- Where the friend is right now, asked on the server: only a server of this game Roblox confirms counts
	-- (a friend who has left the game or gone offline can't be followed).
	local okWhere, _, _, placeId, instanceId = pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, userId)
	if not (okWhere and placeId == game.PlaceId and type(instanceId) == "string" and instanceId ~= ""
		and instanceId ~= game.JobId) then
		joining[player] = nil
		return notify:FireClient(player, "FriendJoinFailed")
	end
	Telemetry.Custom(player, "FriendJoinTried", 1)
	local okTeleport = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = instanceId
		options:SetTeleportData({ Follow = userId })
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not okTeleport then
		joining[player] = nil
		notify:FireClient(player, "FriendJoinFailed")
	end
end

local function onRequest(player, action, ...)
	-- Separate buckets, so opening the invite pop-up can never use up a JOIN.
	if not RateLimit.Allow(player, action == "Join" and "FriendsJoin" or "FriendsMisc", 0.5, 2) or type(action) ~= "string" then
		return
	end
	if action == "Join" then
		onJoin(player, ...)
	elseif action == "InvitePrompt" then
		invitedAt[player] = os.clock() -- a friend arriving with our UserId soon was really invited by us
		Telemetry.Custom(player, "InvitePromptOpened", 1) -- sending invites never pays
	end
end

function FriendsService.Init()
	notify = Remotes.Event("Notify")
	Remotes.Event("RequestFriends").OnServerEvent:Connect(onRequest)
	ReplicatedStorage:SetAttribute("CoplayMinutes", COPLAY_MINUTES)
	ReplicatedStorage:SetAttribute("CoplayCash", COPLAY_CASH)
	ReplicatedStorage:SetAttribute("CoplaySquadDays", SQUAD_DAYS)

	-- A teleport that fails after it started (full server, server gone) reports here.
	pcall(function()
		TeleportService.TeleportInitFailed:Connect(function(player, result)
			if typeof(player) ~= "Instance" or not player:IsA("Player") or not joining[player] then
				return
			end
			joining[player] = nil
			notify:FireClient(player, result == Enum.TeleportResult.GameFull and "FriendServerFull" or "FriendJoinFailed")
		end)
	end)

	DataService.OnLoaded(onLoaded)
	Players.PlayerAdded:Connect(function(p)
		task.spawn(onPlayerAdded, p) -- it waits (LaunchData, friendship check)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		loadedAt[p] = nil
		lastPos[p] = nil
		joining[p] = nil
		invitedAt[p] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[FriendsService] co-op check failed: " .. tostring(err))
			end
		end
	end)
end

return FriendsService
