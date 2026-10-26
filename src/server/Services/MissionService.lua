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

local active = {} -- [player] = { m, step, deadline, got = {}, holdSince, from, fromRadius, stepAt }
local lastEnd = {} -- [player] = os.clock()
local missionEvent, notify

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

local function finish(player, ok, reason)
	local s = active[player]
	if not s then
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

local function tick()
	local t = now()
	for player, s in pairs(active) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not player.Parent then
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
	if not m then
		return
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

function MissionService.Init()
	missionEvent = Remotes.Event("MissionEvent")
	notify = Remotes.Event("Notify")
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
