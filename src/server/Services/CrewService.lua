-- CrewService (ModuleScript, ServerScriptService.Services.CrewService)
-- Crews: up to 4 players who play together (PRD "Crew" phone app + crew bonus).
--   * Invite from the phone's CREW app; the other player gets an ACCEPT / NO card (60 s to answer).
--   * Crewmates see each other's name tags through walls and on the minimap (CrewClient).
--   * Crew bonus: +20% heist cash when a crewmate is within 150 studs (HeistService asks CrewBonus).
--   * Friend bonus: +10% heist cash while any Roblox friend is in the server (attribute FriendBonus).
--     Who is friends with whom is asked from Roblox once per pair when the later one joins and a yes is
--     kept for the session (CrewService.AreFriends; FriendsService's co-op bonus uses it too). Every
--     SWEEP seconds the pairs not known to be friends are asked again: that catches a check that failed
--     and players who became friends while playing.
--   * Crewmates can ride in each other's cars (VehicleService passenger seat checks SameCrew).
--   * CrewService.Invite(from, target) sends the same invite card as the phone's INVITE button
--     (FriendsService uses it when a friend arrives through a Roblox invite).
-- State: player attribute "Crew" = crew id (string), ReplicatedStorage attribute "Crews" = JSON
-- { [crewId] = { userIds } } so every client can draw tags.
-- Remotes: RequestCrew(action, targetUserId) with action "Invite" | "Accept" | "Decline" | "Leave";
--          CrewInvite (server -> client) { FromUserId, FromName }.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local CrewService = {}

local MAX_CREW = 4
local INVITE_SECONDS = 60
local BONUS_RANGE = 150
local SWEEP = 300 -- seconds between asks about the pairs not known to be friends
local SWEEP_GAP = 0.2 -- seconds between two of those asks (spreads the web calls out)
CrewService.CrewBonus = 0.2
CrewService.FriendBonus = 0.1

local crews = {} -- [crewId] = { members = { player, ... } }
local invites = {} -- [targetPlayer] = { from = player, crewId = id or nil, at = os.clock() }
local friendsOf = {} -- [player] = { [userId] = true } for each Roblox friend in this server
local nextId = 0
local notify, inviteEvent

local function publish()
	local out = {}
	for id, crew in pairs(crews) do
		local ids = {}
		for _, p in ipairs(crew.members) do
			table.insert(ids, p.UserId)
		end
		out[id] = ids
	end
	ReplicatedStorage:SetAttribute("Crews", HttpService:JSONEncode(out))
end

function CrewService.CrewOf(player)
	local id = player:GetAttribute("Crew")
	return id and crews[id] or nil
end

function CrewService.SameCrew(a, b)
	local id = a:GetAttribute("Crew")
	return id ~= nil and id == b:GetAttribute("Crew")
end

local function leave(player)
	local id = player:GetAttribute("Crew")
	local crew = id and crews[id]
	player:SetAttribute("Crew", nil)
	player:SetAttribute("CrewPos", nil)
	if not crew then
		return
	end
	local i = table.find(crew.members, player)
	if i then
		table.remove(crew.members, i)
	end
	for _, p in ipairs(crew.members) do
		notify:FireClient(p, "CrewLeft")
	end
	if #crew.members <= 1 then
		for _, p in ipairs(crew.members) do
			p:SetAttribute("Crew", nil)
		end
		crews[id] = nil
	end
	publish()
end

local function join(player, crewId)
	local crew = crews[crewId]
	if player:GetAttribute("Crew") == crewId then
		return true
	end
	if not crew or #crew.members >= MAX_CREW then
		return false
	end
	if player:GetAttribute("Crew") then
		leave(player)
	end
	table.insert(crew.members, player)
	player:SetAttribute("Crew", crewId)
	for _, p in ipairs(crew.members) do
		notify:FireClient(p, "CrewJoined")
	end
	publish()
	Telemetry.Custom(player, "CrewJoined", #crew.members)
	return true
end

local function create(leader)
	nextId += 1
	local id = "c" .. nextId
	crews[id] = { members = { leader } }
	leader:SetAttribute("Crew", id)
	return id
end

-- Heist bonus multiplier for this player right now (crew nearby, friend in server).
function CrewService.BonusFor(player)
	local bonus = 0
	local crew = CrewService.CrewOf(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if crew and root then
		for _, p in ipairs(crew.members) do
			local r = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if r and (r.Position - root.Position).Magnitude <= BONUS_RANGE then
				bonus += CrewService.CrewBonus
				break
			end
		end
	end
	if player:GetAttribute("FriendBonus") then
		bonus += CrewService.FriendBonus
	end
	return bonus
end

-- Send `from`'s crew invite card to `target`. Returns true when sent, else false and the Notify key
-- that tells `from` why (nil when there's nothing to say: no such player, or already crewmates).
function CrewService.Invite(from, target)
	if not target or target == from or target.Parent ~= Players or CrewService.SameCrew(from, target) then
		return false, nil
	end
	local crew = CrewService.CrewOf(from)
	if crew and #crew.members >= MAX_CREW then
		return false, "CrewFull"
	end
	local pending = invites[target]
	if pending and os.clock() - pending.at < INVITE_SECONDS then
		return false, "CrewInvitePending"
	end
	invites[target] = { from = from, at = os.clock() }
	inviteEvent:FireClient(target, { FromUserId = from.UserId, FromName = from.DisplayName })
	return true
end

local function onRequest(player, action, targetUserId)
	if not RateLimit.Allow(player, "Crew", 2, 4) or type(action) ~= "string" then
		return
	end
	if action == "Invite" then
		local target = type(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId) or nil
		local sent, why = CrewService.Invite(player, target)
		if sent then
			notify:FireClient(player, "CrewInviteSent")
		elseif why then
			notify:FireClient(player, why)
		end
	elseif action == "Accept" or action == "Decline" then
		local pending = invites[player]
		invites[player] = nil
		if not pending or os.clock() - pending.at > INVITE_SECONDS or not pending.from.Parent then
			return
		end
		if action == "Decline" then
			notify:FireClient(pending.from, "CrewDeclined")
			return
		end
		if CrewService.SameCrew(player, pending.from) then
			return -- crossed invites: already together
		end
		local id = pending.from:GetAttribute("Crew") or create(pending.from)
		if not join(player, id) then
			notify:FireClient(player, "CrewFull")
		end
	elseif action == "Leave" then
		leave(player)
	end
end

-- Are these two players Roblox friends? (From the cache: asked when the later one joined, then by the sweep.)
function CrewService.AreFriends(a, b)
	local set = friendsOf[a]
	return set ~= nil and set[b.UserId] == true
end

-- Ask Roblox whether a and b are friends and remember a yes (both get the friend bonus). It's a web
-- call that can fail: a failed answer counts as not friends until the next sweep asks again.
local function askPair(a, b)
	local ok, isFriend = pcall(a.IsFriendsWith, a, b.UserId)
	-- Either one may have left while Roblox answered.
	if ok and isFriend and a.Parent == Players and b.Parent == Players then
		friendsOf[a] = friendsOf[a] or {}
		friendsOf[b] = friendsOf[b] or {}
		friendsOf[a][b.UserId] = true
		friendsOf[b][a.UserId] = true
		a:SetAttribute("FriendBonus", true)
		b:SetAttribute("FriendBonus", true)
	end
end

-- Friend bonus: any Roblox friend in the same server. A newcomer is asked about everyone here.
local function checkFriends(player)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not CrewService.AreFriends(player, other) then
			askPair(player, other)
		end
	end
end

-- Every pair still not known to be friends, asked once more (far fewer calls than asking every pair
-- whenever someone leaves).
local function sweep()
	local list = Players:GetPlayers()
	for i, a in ipairs(list) do
		for j = i + 1, #list do
			local b = list[j]
			if a.Parent == Players and b.Parent == Players and not CrewService.AreFriends(a, b) then
				askPair(a, b)
				task.wait(SWEEP_GAP)
			end
		end
	end
end

local function recheckFriendBonus()
	for _, p in ipairs(Players:GetPlayers()) do
		local any = false
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= p and CrewService.AreFriends(p, other) then
				any = true
				break
			end
		end
		p:SetAttribute("FriendBonus", any or nil)
	end
end

function CrewService.Init()
	notify = Remotes.Event("Notify")
	inviteEvent = Remotes.Event("CrewInvite")
	Remotes.Event("RequestCrew").OnServerEvent:Connect(onRequest)
	Players.PlayerAdded:Connect(function(p)
		task.spawn(checkFriends, p)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(checkFriends, p) -- anyone who joined before this service started (Studio)
	end
	Players.PlayerRemoving:Connect(function(p)
		leave(p)
		invites[p] = nil
		for target, inv in pairs(invites) do
			if inv.from == p then
				invites[target] = nil
			end
		end
		friendsOf[p] = nil
		for _, set in pairs(friendsOf) do
			set[p.UserId] = nil
		end
		task.defer(recheckFriendBonus)
	end)
	task.spawn(function()
		while true do
			task.wait(SWEEP)
			local ok, err = pcall(sweep)
			if not ok then
				warn("[CrewService] friend sweep failed: " .. tostring(err))
			end
		end
	end)
	publish()
	-- Crewmates stream out when far away, so publish each crew member's position (player attribute
	-- "CrewPos" = "x,z") for the minimap.
	task.spawn(function()
		while true do
			task.wait(1.5)
			for _, crew in pairs(crews) do
				for _, p in ipairs(crew.members) do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					p:SetAttribute("CrewPos", root and string.format("%d,%d", root.Position.X, root.Position.Z) or nil)
				end
			end
		end
	end)
end

return CrewService
