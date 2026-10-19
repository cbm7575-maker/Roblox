-- DebugService (ModuleScript, ServerScriptService.Services.DebugService)
-- STUDIO ONLY. A BindableFunction ServerStorage.NCDebug that test scripts can call to drive the live
-- services (the same module instances the game uses). Never created in live servers.
--   NCDebug:Invoke("heat", player, amount)          add heat
--   NCDebug:Invoke("arrest", player)                arrest by "an AI patrol"
--   NCDebug:Invoke("eye", position)                 a fake cop eye (anchored part) at position
--   NCDebug:Invoke("clearEyes")
--   NCDebug:Invoke("side", player, side)            set role without the usual rules
--   NCDebug:Invoke("cash", player, amount)
--   NCDebug:Invoke("state", player)                 returns a summary string
--   NCDebug:Invoke("event", player, kind, amount)   a ProgressService event (XP / challenges)

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local DebugService = {}

local fakeEyes = {}

function DebugService.Init()
	if not RunService:IsStudio() then
		return
	end
	local Services = ServerScriptService.Services
	local HeatService = require(Services.HeatService)
	local ArrestService = require(Services.ArrestService)
	local TeamService = require(Services.TeamService)
	local EconomyService = require(Services.EconomyService)

	local fn = ServerStorage:FindFirstChild("NCDebug") or Instance.new("BindableFunction")
	fn.Name = "NCDebug"
	fn.OnInvoke = function(cmd, a, b, ...)
		if cmd == "heat" then
			HeatService.Add(a, b or 1, "debug")
		elseif cmd == "arrest" then
			ArrestService.Arrest(a, nil)
		elseif cmd == "eye" then
			local p = Instance.new("Part")
			p.Name = "DebugEye"
			p.Anchored = true
			p.CanCollide = false
			p.Size = Vector3.new(2, 2, 2)
			p.Color = Color3.fromRGB(34, 225, 255)
			p.Position = a
			p.Parent = Workspace
			HeatService.RegisterEye(p)
			table.insert(fakeEyes, p)
		elseif cmd == "clearEyes" then
			for _, p in ipairs(fakeEyes) do
				HeatService.UnregisterEye(p)
				p:Destroy()
			end
			fakeEyes = {}
		elseif cmd == "side" then
			TeamService.SetSide(a, b, true)
		elseif cmd == "cash" then
			EconomyService.AddCash(a, b, "debug")
		elseif cmd == "clock" then
			require(Services.WorldService).Override.Clock = a -- hour 0-24, or nil
		elseif cmd == "rain" then
			require(Services.WorldService).Override.Rain = a -- true/false, or nil
		elseif cmd == "ai" then
			local AIPolice = require(Services.AIPoliceService)
			local RoadGraph = require(game:GetService("ReplicatedStorage").Shared.Util.RoadGraph)
			local edges = 0
			for _, e in pairs(RoadGraph.Edges) do
				for _ in pairs(e) do
					edges += 1
				end
			end
			return string.format("ai units=%d roadNodes=%d roadEdges=%d", AIPolice.Count(), #RoadGraph.Nodes, edges / 2)
		elseif cmd == "carmeet" then
			require(Services.CarMeetService).StartNow()
		elseif cmd == "moment" then
			require(Services.EventService).RunRandom()
		elseif cmd == "event" then
			require(Services.ProgressService).Event(a, b, select(1, ...) or 1)
		elseif cmd == "state" then
			return string.format("side=%s heat=%s spotted=%s carried=%s cash=%s releaseAt=%s stunnedUntil=%s",
				tostring(a:GetAttribute("Side")), tostring(a:GetAttribute("Heat")), tostring(a:GetAttribute("HeatSpotted")),
				tostring(a:GetAttribute("Carried")), tostring(a:GetAttribute("Cash")), tostring(a:GetAttribute("ReleaseAt")),
				tostring(a:GetAttribute("StunnedUntil")))
		end
		return "ok"
	end
	fn.Parent = ServerStorage
end

return DebugService
