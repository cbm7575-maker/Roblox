-- DebugService (ModuleScript, ServerScriptService.Services.DebugService)
-- STUDIO ONLY. A BindableFunction ServerStorage.NCDebug that test scripts can call to drive the live
-- services (the same module instances the game uses). Never created in live servers.
--   NCDebug:Invoke("heat", player, amount)          add heat
--   NCDebug:Invoke("arrest", player)                arrest by "an AI patrol"
--   NCDebug:Invoke("eye", position)                 a fake cop eye (anchored part) at position
--   NCDebug:Invoke("clearEyes")
--   NCDebug:Invoke("side", player, side)            set role without the usual rules
--   NCDebug:Invoke("cash", player, amount)
--   NCDebug:Invoke("car", player, vehicleId)       spawn any vehicle and sit in it (no ownership check)
--   NCDebug:Invoke("state", player)                 returns a summary string
--   NCDebug:Invoke("event", player, kind, amount)   a ProgressService event (XP / challenges)
--   NCDebug:Invoke("call", "VehicleService", "Spawn", ...)   any function of any service
-- The Studio MCP runs sandboxed (it can't invoke bindables, fire remotes or require modules), so the
-- same commands also come in through an attribute: set Workspace's "NCCmd" to a JSON array, e.g.
--   ["cash","$me",5000]   ["car","$me","Vortex"]   ["call","HeatService","Add","$me",2,"debug"]
-- ("$me" = the first player, {"v3":[x,y,z]} = a Vector3, {"inst":"Workspace.Vehicles.Gatorback"} = an
-- Instance by path); the answer lands in Workspace's "NCResult".

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
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
	local function handle(cmd, a, b, ...)
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
		elseif cmd == "car" then
			-- Spawn any vehicle for a player and sit them in it (skips ownership, for testing seats/bodies).
			require(Services.VehicleService).Spawn(a, b, { Sit = true, IgnoreCooldown = true })
		elseif cmd == "carmeet" then
			require(Services.CarMeetService).StartNow()
		elseif cmd == "moment" then
			require(Services.EventService).RunRandom()
		elseif cmd == "event" then
			require(Services.ProgressService).Event(a, b, select(1, ...) or 1)
		elseif cmd == "call" then
			local out = table.pack(require(Services[a])[b](...))
			for i = 1, out.n do
				out[i] = tostring(out[i])
			end
			return table.concat(out, ", ", 1, out.n)
		elseif cmd == "state" then
			return string.format("side=%s heat=%s spotted=%s carried=%s cash=%s releaseAt=%s stunnedUntil=%s",
				tostring(a:GetAttribute("Side")), tostring(a:GetAttribute("Heat")), tostring(a:GetAttribute("HeatSpotted")),
				tostring(a:GetAttribute("Carried")), tostring(a:GetAttribute("Cash")), tostring(a:GetAttribute("ReleaseAt")),
				tostring(a:GetAttribute("StunnedUntil")))
		end
		return "ok"
	end
	fn.OnInvoke = handle
	fn.Parent = ServerStorage

	-- The attribute door (see the header).
	local serial = 0
	Workspace:GetAttributeChangedSignal("NCCmd"):Connect(function()
		local raw = Workspace:GetAttribute("NCCmd")
		if type(raw) ~= "string" or raw == "" then
			return
		end
		Workspace:SetAttribute("NCCmd", nil)
		serial += 1
		local ok, res = pcall(function()
			local args = HttpService:JSONDecode(raw)
			for i, v in ipairs(args) do
				if v == "$me" then
					args[i] = Players:GetPlayers()[1]
				elseif type(v) == "table" and v.v3 then
					args[i] = Vector3.new(v.v3[1], v.v3[2], v.v3[3])
				elseif type(v) == "table" and v.inst then
					-- { "inst": "Workspace.Vehicles.Gatorback" }: an Instance by its path from game
					local at = game
					for part in string.gmatch(v.inst, "[^%.]+") do
						at = at and (at:FindFirstChild(part) or (at == game and game:GetService(part)) or nil)
					end
					args[i] = at
				end
			end
			return handle(table.unpack(args))
		end)
		Workspace:SetAttribute("NCResult", serial .. (ok and " ok " or " ERR ") .. tostring(res))
	end)
end

return DebugService
