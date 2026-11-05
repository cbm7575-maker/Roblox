-- MissionService (ModuleScript, ServerScriptService.Services.MissionService)
-- Phone missions (Config.Missions). The server runs the steps, the timer and the pay.
--   Remote RequestMission("Start", id) / ("Quit")
--   Player attribute "Mission" = JSON { id, step, deadline (server time), got = { collected point indices } }
--   Player attribute "MissionsDone" = comma list of mission ids already finished today (full pay once a day)
--   Remote MissionEvent(kind, info) to the client: "Step", "Done" { Cash, XP }, "Failed" { Reason }
-- Only free-roam players who aren't wanted, racing or on a job shift can start one, and a mission fails
-- the moment its player stops being a free-roam player (joins the police, goes to prison).
-- Anti-teleport: a goal only counts once enough time has passed to drive there from the last goal
-- at MAX_TRAVEL (faster than any car with nitro). Early arrivals are ignored, not failed.
-- Crew preps (Missions.CrewPreps, the crew job behind The Big Score): MissionService.StartCrew(players,
-- id, crewId, onDone) puts a whole crew on one shared mission (CrewService checks who's free first). Each
-- of them gets the usual "Mission" attribute and events, so MissionClient draws it as it draws any
-- mission. The steps are shared: a goal counts once Missions.CrewJob.Together of them (not wanted) are at
-- it at the same time (fewer on a smaller crew: Studio's crew of one); a Collect point the same. While
-- only some of them have made it, or a wanted one is at the goal, the crew hears so (remote "CrewJob"
-- "Toast" Together / Wanted, every CREW_TOAST_GAP s at most). Being wanted doesn't fail a prep, it just
-- doesn't count. It fails for all of them on the clock, a QUIT from any of them, or one of them leaving
-- the game, the crew or free roam. A step with WithinSpeed pulls the clock down as it starts (a timed
-- getaway). Passed: each one gets the prep's Cash and XP; then onDone(passed, players).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Missions = require(ReplicatedStorage.Shared.Config.Missions)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local MissionService = {}

local MAX_TRAVEL = 300 -- studs/s: a bit above the fastest car, fully tuned, on nitro (297: Config.Garage)

local CREW_TOAST_GAP = 6 -- seconds between two "wait for your crew" / "lose the cops" toasts on a crew prep

-- [player] = { m, step, deadline, got = {}, holdSince, from, fromRadius, stepAt }; a crew prep's members
-- all point at one shared table that also has crew = { players }, crewId, need, onDone, tooSlow, toastAt.
local active = {}
local lastEnd = {} -- [player] = os.clock()
local missionEvent, notify, crewJob

local function now()
	return Workspace:GetServerTimeNow()
end

local function today()
	return math.floor(os.time() / 86400)
end

local function doneToday(player)
	local data = DataService.Get(player)
	if not data then
		return {}
	end
	data.flags = data.flags or {}
	local rec = data.flags.missions
	if not rec or (rec.day or 0) < today() then
		rec = { day = today(), done = {} }
		data.flags.missions = rec
	end
	return rec.done
end

local function publishDone(player)
	local list = {}
	for id in pairs(doneToday(player)) do
		table.insert(list, id)
	end
	player:SetAttribute("MissionsDone", table.concat(list, ","))
end

local function publish(player)
	local s = active[player]
	if not s then
		player:SetAttribute("Mission", nil)
		return
	end
	local got = {}
	for i in pairs(s.got) do
		table.insert(got, i)
	end
	player:SetAttribute("Mission", HttpService:JSONEncode({ id = s.m.Id, step = s.step, deadline = s.deadline, got = got }))
end

-- A crew prep is over, for every one of them (see the header).
local function finishCrew(s, ok, reason)
	if s.over then
		return
	end
	s.over = true
	for _, p in ipairs(s.crew) do
		if active[p] == s then
			active[p] = nil
		end
		lastEnd[p] = os.clock()
		if p.Parent == Players then
			publish(p)
			if ok then
				EconomyService.AddCash(p, s.m.Cash, "crewprep:" .. s.m.Id)
				local okXP, err = pcall(require(ServerScriptService.Services.ProgressService).Event, p, "Mission", s.m.XP)
				if not okXP then
					warn("[MissionService] crew prep XP: " .. tostring(err))
				end
				Telemetry.Custom(p, "CrewPrep_" .. s.m.Id, s.m.Cash)
				missionEvent:FireClient(p, "Done", { Name = s.m.Name, Cash = s.m.Cash, XP = s.m.XP, First = true, Crew = true })
			else
				missionEvent:FireClient(p, "Failed", { Name = s.m.Name, Reason = reason, Crew = true })
			end
		end
	end
	if s.onDone then
		task.spawn(s.onDone, ok == true, s.crew)
	end
end

local function finish(player, ok, reason)
	local s = active[player]
	if not s then
		return
	end
	if s.crew then
		finishCrew(s, ok, reason == "Quit" and (player.DisplayName .. " quit the prep") or reason)
		return
	end
	active[player] = nil
	lastEnd[player] = os.clock()
	publish(player)
	if not ok then
		missionEvent:FireClient(player, "Failed", { Name = s.m.Name, Reason = reason })
		return
	end
	local done = doneToday(player)
	local first = not done[s.m.Id]
	done[s.m.Id] = true
	local cash = math.floor(s.m.Cash * (first and 1 or Missions.RepeatShare))
	local xp = math.floor(s.m.XP * (first and 1 or Missions.RepeatShare))
	EconomyService.AddCash(player, cash, "mission:" .. s.m.Id)
	require(ServerScriptService.Services.ProgressService).Event(player, "Mission", xp)
	Telemetry.Custom(player, "Mission_" .. s.m.Id, cash)
	publishDone(player)
	missionEvent:FireClient(player, "Done", { Name = s.m.Name, Cash = cash, XP = xp, First = first })
end

local function inBoat(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	return seat ~= nil and seat.Parent:GetAttribute("Boat") == true
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Too soon to be here? Arriving sooner than the straight-line gap from the last goal (or the start
-- spot) at MAX_TRAVEL means a teleport, so the arrival doesn't count yet.
local function tooSoon(s, target, radius)
	if not s.from then
		-- Started inside a home and still indoors (tick sets the start spot at the door): nothing counts yet.
		return true
	end
	local gap = math.max(0, (flat(target) - s.from).Magnitude - s.fromRadius - radius)
	return os.clock() - s.stepAt < gap / MAX_TRAVEL
end

-- Tell the whole crew something about the goal (CrewClient has the words), not too often.
local function crewToast(s, key)
	if os.clock() - (s.toastAt or 0) < CREW_TOAST_GAP then
		return
	end
	s.toastAt = os.clock()
	for _, p in ipairs(s.crew) do
		if p.Parent == Players then
			crewJob:FireClient(p, "Toast", { Key = key })
		end
	end
end

-- How many of `list` ({ pos, slow }) are within `radius` of `target` (only the slow ones, for a Hold).
local function countNear(list, target, radius, slowOnly)
	local n = 0
	for _, sp in ipairs(list) do
		if (sp.pos - flat(target)).Magnitude <= radius and (not slowOnly or sp.slow) then
			n += 1
		end
	end
	return n
end

-- One crew prep (see the header). Runs once per tick for the shared state, whoever's entry finds it.
local function tickCrew(s)
	for _, p in ipairs(s.crew) do
		local why
		if p.Parent ~= Players then
			why = p.DisplayName .. " left the game"
		elseif p:GetAttribute("Side") ~= "Civilian" then
			why = p.DisplayName .. (p:GetAttribute("Side") == "Cop" and " joined the police" or " got locked up")
		elseif p:GetAttribute("Crew") ~= s.crewId then
			why = p.DisplayName .. " left the crew"
		end
		if why then
			finishCrew(s, false, why)
			return
		end
	end
	if now() > s.deadline then
		finishCrew(s, false, s.tooSlow or "Time's up")
		return
	end
	-- Where the crew is: the ones who aren't wanted count, the wanted ones only get a "lose the cops" toast.
	local spots, wanted = {}, {}
	for _, p in ipairs(s.crew) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and not p:GetAttribute("InHome") then
			local spot = { pos = flat(root.Position), slow = root.AssemblyLinearVelocity.Magnitude < 10 }
			table.insert((p:GetAttribute("Heat") or 0) > 0 and wanted or spots, spot)
		end
	end
	if not s.from then
		-- (nobody had a body outside a home at the start: travel is timed from the first one out)
		local first = spots[1] or wanted[1]
		if not first then
			return
		end
		s.from, s.fromRadius, s.stepAt = first.pos, 0, os.clock()
	end
	local step = s.m.Steps[s.step]
	local advance, short, wantedThere = false, false, false
	if step.Kind == "Goto" or step.Kind == "Hold" then
		local hold = step.Kind == "Hold"
		local n = countNear(spots, step.Pos, step.Radius, hold)
		local ready = n >= s.need and not tooSoon(s, step.Pos, step.Radius)
		short = n > 0 and n < s.need
		wantedThere = countNear(wanted, step.Pos, step.Radius, false) > 0
		if hold then
			if ready then
				s.holdSince = s.holdSince or os.clock()
				advance = os.clock() - s.holdSince >= step.Seconds
			else
				s.holdSince = nil
			end
		else
			advance = ready
		end
	elseif step.Kind == "Collect" then
		local changed, all = false, true
		for i, point in ipairs(step.Points) do
			if not s.got[i] then
				local n = countNear(spots, point, step.Radius, false)
				if n >= s.need and not tooSoon(s, point, step.Radius) then
					s.got[i] = true
					changed = true
					s.from, s.fromRadius, s.stepAt = flat(point), step.Radius, os.clock()
				else
					short = short or (n > 0 and n < s.need)
					wantedThere = wantedThere or countNear(wanted, point, step.Radius, false) > 0
					all = false
				end
			end
		end
		advance = all
		if changed and not all then
			for _, p in ipairs(s.crew) do
				publish(p)
				missionEvent:FireClient(p, "Collected", {})
			end
		end
	end
	if advance then
		s.step += 1
		s.holdSince = nil
		s.got = {}
		if step.Pos then
			s.from, s.fromRadius = flat(step.Pos), step.Radius
		end
		s.stepAt = os.clock()
		local nextStep = s.m.Steps[s.step]
		if not nextStep then
			finishCrew(s, true)
			return
		end
		if nextStep.WithinSpeed and nextStep.Pos then
			-- A timed leg: the clock jumps down to what this trip allows (straight-line, from the last goal).
			local gap = math.max(0, (flat(nextStep.Pos) - s.from).Magnitude - s.fromRadius - nextStep.Radius)
			s.deadline = math.min(s.deadline, now() + math.ceil(gap / nextStep.WithinSpeed + (nextStep.WithinSlack or 0)))
			s.tooSlow = nextStep.TooSlow
		end
		for _, p in ipairs(s.crew) do
			publish(p)
			missionEvent:FireClient(p, "Step", { Text = nextStep.Text })
		end
	elseif short then
		crewToast(s, "Together")
	elseif wantedThere then
		crewToast(s, "Wanted")
	end
end

local function tick()
	local t = now()
	local seen = {}
	for player, s in pairs(active) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if s.crew then
			if not seen[s] then
				seen[s] = true
				tickCrew(s)
			end
		elseif not player.Parent then
			active[player] = nil
		elseif t > s.deadline then
			finish(player, false, "Time's up")
		elseif player:GetAttribute("Side") ~= "Civilian" then
			-- Switching to police mid-mission left the banner, timer and markers up, and the new cop could
			-- finish it for a free-roam player's pay. Missions are free-roam only, so it ends here (prison too).
			finish(player, false, player:GetAttribute("Side") == "Cop" and "You joined the police" or "You're in prison")
		elseif (player:GetAttribute("Heat") or 0) > 0 then
			finish(player, false, "You're wanted")
		elseif root then
			local step = s.m.Steps[s.step]
			local here = flat(root.Position)
			local advance = false
			if not s.from and not player:GetAttribute("InHome") then
				-- No character when the mission started, or it started inside a home (which sits far off the
				-- map, so we wait for the player to step out of the door): travel is timed from here.
				s.from, s.fromRadius, s.stepAt = here, 0, os.clock()
			end
			if step.Kind == "Goto" then
				advance = (here - flat(step.Pos)).Magnitude <= step.Radius and (not s.m.NeedsBoat or inBoat(player))
					and not tooSoon(s, step.Pos, step.Radius)
			elseif step.Kind == "Hold" then
				local inside = (here - flat(step.Pos)).Magnitude <= step.Radius and root.AssemblyLinearVelocity.Magnitude < 10
					and not tooSoon(s, step.Pos, step.Radius)
				if inside then
					s.holdSince = s.holdSince or os.clock()
					advance = os.clock() - s.holdSince >= step.Seconds
				else
					s.holdSince = nil
				end
			elseif step.Kind == "Collect" then
				local changed = false
				for i, p in ipairs(step.Points) do
					if not s.got[i] and (here - flat(p)).Magnitude <= step.Radius and not tooSoon(s, p, step.Radius) then
						s.got[i] = true
						changed = true
						-- The next point is timed from this one.
						s.from, s.fromRadius, s.stepAt = flat(p), step.Radius, os.clock()
					end
				end
				local all = true
				for i in ipairs(step.Points) do
					all = all and s.got[i] == true
				end
				advance = all
				if changed and not all then
					publish(player)
					missionEvent:FireClient(player, "Collected", {})
				end
			end
			if advance then
				s.step += 1
				s.holdSince = nil
				s.got = {}
				-- The next goal is timed from this one (a Collect step already set its last point).
				if step.Pos then
					s.from, s.fromRadius = flat(step.Pos), step.Radius
				end
				s.stepAt = os.clock()
				if s.step > #s.m.Steps then
					finish(player, true)
				else
					publish(player)
					missionEvent:FireClient(player, "Step", { Text = s.m.Steps[s.step].Text })
				end
			end
		end
	end
end

local function onRequest(player, action, id)
	if not RateLimit.Allow(player, "Mission", 1, 2) or type(action) ~= "string" then
		return
	end
	if action == "Quit" then
		finish(player, false, "Quit")
		return
	end
	if action ~= "Start" or type(id) ~= "string" then
		return
	end
	local m = Missions.ById[id]
	if not m or m.Crew then
		return -- (crew preps start from the CREW app, through CrewService)
	end
	if active[player] then
		-- START on the phone during a mission closed the phone and nothing happened: say why.
		notify:FireClient(player, "MissionBusy")
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" then
		-- Police were told to "finish what you're doing and lose any heat", which they can't do: missions
		-- are free-roam only, so say that instead.
		notify:FireClient(player, "MissionCivOnly")
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 or player:GetAttribute("RacingId") or player:GetAttribute("JobKind")
		or player:GetAttribute("BigScore") then -- (on a Big Score crew: BigScoreService)
		notify:FireClient(player, "MissionBusy")
		return
	end
	if lastEnd[player] and os.clock() - lastEnd[player] < Missions.Cooldown then
		notify:FireClient(player, "MissionCooldown")
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- A home's inside sits far off the map: a mission started there timed the first trip from out there,
	-- so the first goal didn't count for half a minute or more. Indoors the start spot is unknown instead
	-- (tick sets it at the door once the player steps out).
	local known = root and not player:GetAttribute("InHome")
	active[player] = { m = m, step = 1, deadline = now() + m.TimeLimit, got = {},
		from = known and flat(root.Position) or nil, fromRadius = 0, stepAt = os.clock() }
	publish(player)
	missionEvent:FireClient(player, "Started", { Name = m.Name, Text = m.Steps[1].Text })
end

function MissionService.Active(player)
	return active[player] ~= nil
end

-- (see the header) Crew prep `id` for these players, who CrewService has checked are one crew (crewId),
-- here, in free roam and free. onDone(passed, players) runs as it ends. True when it started.
function MissionService.StartCrew(players, id, crewId, onDone)
	local m = Missions.ById[id]
	if not m or not m.Crew or type(players) ~= "table" or #players == 0 then
		return false
	end
	for _, p in ipairs(players) do
		if active[p] or p.Parent ~= Players then
			return false
		end
	end
	Missions.Resolve(m)
	local from
	for _, p in ipairs(players) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and not p:GetAttribute("InHome") then
			from = flat(root.Position)
			break
		end
	end
	local s = {
		m = m, step = 1, deadline = now() + m.TimeLimit, got = {}, from = from, fromRadius = 0, stepAt = os.clock(),
		crew = table.clone(players), crewId = crewId, onDone = onDone,
		need = math.min(#players, (Missions.CrewJob and Missions.CrewJob.Together) or 2),
	}
	for _, p in ipairs(players) do
		active[p] = s
		publish(p)
		missionEvent:FireClient(p, "Started", { Name = m.Name, Text = m.Steps[1].Text })
	end
	return true
end

function MissionService.Init()
	missionEvent = Remotes.Event("MissionEvent")
	notify = Remotes.Event("Notify")
	crewJob = Remotes.Event("CrewJob")
	Remotes.Event("RequestMission").OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(p)
		active[p] = nil
		lastEnd[p] = nil
	end)
	DataService.OnLoaded(function(p)
		publishDone(p)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			tick()
		end
	end)
end

return MissionService
