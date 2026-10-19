-- MissionService (ModuleScript, ServerScriptService.Services.MissionService)
-- Phone missions (Config.Missions). The server runs the steps, the timer and the pay.
--   Remote RequestMission("Start", id) / ("Quit")
--   Player attribute "Mission" = JSON { id, step, deadline (server time), got = { collected point indices } }
--   Player attribute "MissionsDone" = comma list of mission ids already finished today (full pay once a
--     day; refreshed at UTC midnight for players who stay online)
--   Player attribute "MissionHeat" = true while the player's heat came from a mission's Escape step
--     (until it's back to 0, even if the mission ended): ProgressService and HideoutService give that
--     escape no XP, challenge or stat credit.
--   Remote MissionEvent(kind, info) to the client: "Started", "Step", "Collected", "Done" { Cash, XP },
--     "Failed" { Reason }
-- Each mission has a Side ("Civilian" default, or "Cop"); only that side can start it, and switching
-- side (or getting arrested) ends it. Civilians can't start one while wanted, racing or on a job shift,
-- and being wanted fails a civilian mission except during an Escape step.
-- Step kinds: Goto, Hold, Collect, Escape (server adds heat via HeatService.Add; done when Heat is 0;
-- getting caught fails it) and Fragile (reach the spot driving; a crash fails it). See Config.Missions.

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

local TICK = 0.1 -- Fragile steps compare speeds a tenth of a second apart (hard braking stays legal)

local active = {} -- [player] = { m, step, deadline, got = {}, holdSince, caught, fragileCar, lastSpeed, startHealth }
local lastEnd = {} -- [player] = os.clock()
local missionHeat = {} -- [player] = true while their heat came from an Escape step
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
	table.sort(list)
	local s = table.concat(list, ",")
	if player:GetAttribute("MissionsDone") ~= s then
		player:SetAttribute("MissionsDone", s)
	end
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

local function setMissionHeat(player, on)
	missionHeat[player] = on or nil
	if player.Parent then
		player:SetAttribute("MissionHeat", on or nil)
	end
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
	local share = first and 1 or Missions.RepeatShareFor(s.m)
	local cash = math.floor(s.m.Cash * share)
	local xp = math.floor(s.m.XP * share)
	EconomyService.AddCash(player, cash, "mission:" .. s.m.Id)
	-- "Mission" XP goes to the side the player is on: cop missions level the police rank.
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

-- The car this player is driving (driver's seat), if any.
local function drivenCar(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local car = seat and seat.Name == "DriverSeat" and seat.Parent
	if car and car:IsA("Model") and car.PrimaryPart then
		return car
	end
	return nil
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Set up the step the mission just moved to.
local function beginStep(player, s)
	s.holdSince = nil
	s.got = {}
	s.fragileCar, s.lastSpeed, s.startHealth = nil, nil, nil
	local step = s.m.Steps[s.step]
	if step.Kind == "Escape" then
		-- The cops get a tip. TimesCaught tells an arrest (which also clears heat) from a real escape.
		s.caught = player:GetAttribute("TimesCaught") or 0
		setMissionHeat(player, true)
		local ok, err = pcall(function()
			require(ServerScriptService.Services.HeatService).Add(player, step.Stars or 2, "mission")
		end)
		if not ok then
			warn("[MissionService] couldn't add mission heat: " .. tostring(err))
		end
	end
end

local function advance(player, s)
	s.step += 1
	if s.step > #s.m.Steps then
		finish(player, true)
	else
		beginStep(player, s)
		publish(player)
		missionEvent:FireClient(player, "Step", { Text = s.m.Steps[s.step].Text })
	end
end

-- Fragile cargo: a crash (sudden big speed loss from above FragileMinSpeed, or a big Health drop on
-- the car) fails it. Returns true if the cargo broke.
local function fragileBroke(s, car)
	local v = car.PrimaryPart.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local hp = car:GetAttribute("Health")
	if s.fragileCar ~= car then
		s.fragileCar = car
		s.startHealth = type(hp) == "number" and hp or nil
		s.lastSpeed = speed
		return false
	end
	local last = s.lastSpeed
	s.lastSpeed = speed
	if last and last > Missions.FragileMinSpeed and speed < last * (1 - Missions.FragileDrop) then
		return true
	end
	return type(hp) == "number" and s.startHealth ~= nil and s.startHealth - hp >= Missions.FragileDamage
end

-- One mission's update. Returns a failure reason, true to advance a step, or nil.
local function step(player, s, t)
	local side = player:GetAttribute("Side")
	local def = s.m.Steps[s.step]
	local escaping = def.Kind == "Escape"
	local heat = player:GetAttribute("Heat") or 0
	if side ~= s.m.Side then
		return side == "Prisoner" and "Busted!" or "You switched sides"
	elseif escaping and (player:GetAttribute("TimesCaught") or 0) > (s.caught or 0) then
		return "Busted!"
	elseif t > s.deadline then
		return "Time's up"
	elseif escaping then
		return heat <= 0 or nil
	elseif heat > 0 then
		return "You're wanted"
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local here = flat(root.Position)
	if def.Kind == "Goto" then
		return ((here - flat(def.Pos)).Magnitude <= def.Radius and (not s.m.NeedsBoat or inBoat(player))) or nil
	elseif def.Kind == "Fragile" then
		local car = drivenCar(player)
		if not car then
			s.lastSpeed = nil -- out of the car: compare afresh when back in
			return nil
		end
		if fragileBroke(s, car) then
			return "Crashed! The cargo broke"
		end
		return (flat(car.PrimaryPart.Position) - flat(def.Pos)).Magnitude <= def.Radius or nil
	elseif def.Kind == "Hold" then
		local inside = (here - flat(def.Pos)).Magnitude <= def.Radius and root.AssemblyLinearVelocity.Magnitude < 10
		if inside then
			s.holdSince = s.holdSince or os.clock()
			return os.clock() - s.holdSince >= def.Seconds or nil
		end
		s.holdSince = nil
	elseif def.Kind == "Collect" then
		local changed = false
		for i, p in ipairs(def.Points) do
			if not s.got[i] and (here - flat(p)).Magnitude <= def.Radius then
				s.got[i] = true
				changed = true
			end
		end
		local all = true
		for i in ipairs(def.Points) do
			all = all and s.got[i] == true
		end
		if changed and not all then
			publish(player)
			missionEvent:FireClient(player, "Collected", {})
		end
		return all or nil
	end
	return nil
end

local function tick()
	local t = now()
	for player, s in pairs(active) do
		if not player.Parent then
			active[player] = nil
		else
			local result = step(player, s, t)
			if type(result) == "string" then
				finish(player, false, result)
			elseif result == true then
				advance(player, s)
			end
		end
	end
	-- Mission heat is over once the heat is gone (escaped, laid low or arrested) or they left the side.
	for player in pairs(missionHeat) do
		if player.Parent ~= Players or (player:GetAttribute("Heat") or 0) <= 0 or player:GetAttribute("Side") ~= "Civilian" then
			setMissionHeat(player, nil)
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
	if not m or active[player] then
		return
	end
	if player:GetAttribute("Side") ~= m.Side then
		notify:FireClient(player, "MissionWrongSide")
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 or player:GetAttribute("RacingId") or player:GetAttribute("JobKind") then
		notify:FireClient(player, "MissionBusy")
		return
	end
	if lastEnd[player] and os.clock() - lastEnd[player] < Missions.Cooldown then
		notify:FireClient(player, "MissionCooldown")
		return
	end
	local s = { m = m, step = 1, deadline = now() + m.TimeLimit, got = {} }
	active[player] = s
	beginStep(player, s)
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
		missionHeat[p] = nil
	end)
	DataService.OnLoaded(function(p)
		publishDone(p)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= TICK then
			acc = 0
			local ok, err = pcall(tick)
			if not ok then
				warn("[MissionService] " .. tostring(err))
			end
		end
	end)
	-- A new UTC day: everyone online gets full pay again, so refresh their MissionsDone.
	task.spawn(function()
		local lastDay = today()
		while true do
			task.wait(60)
			if today() > lastDay then
				lastDay = today()
				for _, p in ipairs(Players:GetPlayers()) do
					if DataService.IsLoaded(p) then
						pcall(publishDone, p)
					end
				end
			end
		end
	end)
end

return MissionService
