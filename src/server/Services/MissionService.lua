-- MissionService (ModuleScript, ServerScriptService.Services.MissionService)
-- Phone missions (Config.Missions). The server runs the steps, the timer and the pay.
--   Remote RequestMission("Start", id) / ("Quit")
--   Player attribute "Mission" = JSON { id, step, deadline (server time), got = { collected point indices } }
--   Player attribute "MissionsDone" = comma list of mission ids already finished today (full pay once a day)
--   Remote MissionEvent(kind, info) to the client: "Step", "Done" { Cash, XP }, "Failed" { Reason }
-- Only free-roam players who aren't wanted, racing or on a job shift can start one.

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

local active = {} -- [player] = { m, step, deadline, got = {}, holdSince }
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

local function tick()
	local t = now()
	for player, s in pairs(active) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not player.Parent then
			active[player] = nil
		elseif t > s.deadline then
			finish(player, false, "Time's up")
		elseif (player:GetAttribute("Heat") or 0) > 0 then
			finish(player, false, "You're wanted")
		elseif root then
			local step = s.m.Steps[s.step]
			local here = flat(root.Position)
			local advance = false
			if step.Kind == "Goto" then
				advance = (here - flat(step.Pos)).Magnitude <= step.Radius and (not s.m.NeedsBoat or inBoat(player))
			elseif step.Kind == "Hold" then
				local inside = (here - flat(step.Pos)).Magnitude <= step.Radius and root.AssemblyLinearVelocity.Magnitude < 10
				if inside then
					s.holdSince = s.holdSince or os.clock()
					advance = os.clock() - s.holdSince >= step.Seconds
				else
					s.holdSince = nil
				end
			elseif step.Kind == "Collect" then
				local changed = false
				for i, p in ipairs(step.Points) do
					if not s.got[i] and (here - flat(p)).Magnitude <= step.Radius then
						s.got[i] = true
						changed = true
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
	if not m or active[player] then
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" or (player:GetAttribute("Heat") or 0) > 0
		or player:GetAttribute("RacingId") or player:GetAttribute("JobKind") then
		notify:FireClient(player, "MissionBusy")
		return
	end
	if lastEnd[player] and os.clock() - lastEnd[player] < Missions.Cooldown then
		notify:FireClient(player, "MissionCooldown")
		return
	end
	active[player] = { m = m, step = 1, deadline = now() + m.TimeLimit, got = {} }
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
