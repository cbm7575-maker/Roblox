-- StuntService (ModuleScript, ServerScriptService.Services.StuntService)
-- Stunt jumps (Config.Activities.Stunts).
--   1. Drive up a ramp fast (over 50 studs/s, heading along the ramp).
--   2. The server sees the car leave the ramp and go airborne (4+ studs above the ground).
--   3. Land upright at least MinDist studs from the ramp's lip: STUNT JUMP! First time per ramp
--      pays $250 (saved, counts toward 8/8), repeats $50 (20 s cooldown per ramp).
-- While airborne the player's attribute InStunt = true (the client plays a slow-motion camera).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local DataService = require(ServerScriptService.Services.DataService)

local StuntService = {}

local MIN_SPEED = 50
local AIR_HEIGHT = 4
local LAND_HEIGHT = 3.5
local REPEAT_COOLDOWN = 20

local ramps = {} -- { part, stunt }
local state = {} -- [player] = { phase, ramp, lip, leftAt, airAt }
local lastReward = {} -- [player] = { [stuntId] = os.clock() }
local stuntEvent

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false

local function heightAboveGround(chassis, car, char)
	groundParams.FilterDescendantsInstances = { car, char, Workspace:FindFirstChild("Smoke") }
	local hit = Workspace:Raycast(chassis.Position, Vector3.new(0, -60, 0), groundParams)
	return hit and (chassis.Position.Y - hit.Position.Y) or 60
end

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function reward(player, stunt, distance)
	local data = DataService.Get(player)
	local first = false
	if data then
		data.stunts = data.stunts or {}
		first = not data.stunts[stunt.Id]
		data.stunts[stunt.Id] = true
	end
	lastReward[player] = lastReward[player] or {}
	local t = os.clock()
	local pay = 0
	if first then
		pay = Activities.StuntFirstReward
	elseif not lastReward[player][stunt.Id] or t - lastReward[player][stunt.Id] > REPEAT_COOLDOWN then
		pay = Activities.StuntRepeatReward
	end
	lastReward[player][stunt.Id] = t
	if pay > 0 then
		EconomyService.AddCash(player, pay, "stunt:" .. stunt.Id)
		require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "Stunt")
	end
	local done = 0
	if data then
		for _ in pairs(data.stunts) do
			done += 1
		end
	end
	player:SetAttribute("StuntsDone", done)
	stuntEvent:FireClient(player, { Name = stunt.Name, Distance = math.floor(distance), Pay = pay, First = first, Done = done, Total = #Activities.Stunts })
end

local function tick()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local car = hum and hum.SeatPart and hum.SeatPart.Name == "DriverSeat" and hum.SeatPart.Parent -- drivers only (not passengers)
		local chassis = car and car.PrimaryPart
		local s = state[player]
		if not chassis or not car:GetAttribute("NCVehicle") then
			if s and s.phase ~= "idle" then
				player:SetAttribute("InStunt", false)
			end
			state[player] = { phase = "idle" }
		else
			s = s or { phase = "idle" }
			state[player] = s
			local vel = chassis.AssemblyLinearVelocity
			local t = os.clock()
			-- The driver's device owns the car's physics, so its velocity can be faked: never trust more
			-- than the car really moved since the last tick (plus slack), or its top speed.
			local measured
			if s.lastPos and t - s.lastT > 0.05 then
				local moved = chassis.Position - s.lastPos
				measured = Vector3.new(moved.X, 0, moved.Z).Magnitude / (t - s.lastT)
			end
			s.lastPos, s.lastT = chassis.Position, t
			if s.phase == "idle" or s.phase == "armed" then
				-- On a ramp, fast, heading the right way?
				local onRamp
				for _, r in ipairs(ramps) do
					local rel = r.part.CFrame:PointToObjectSpace(chassis.Position)
					if math.abs(rel.X) < 10 and math.abs(rel.Z) < 13 and rel.Y > -4 and rel.Y < 14 then
						local along = vel:Dot(r.stunt.Travel.Unit)
						local cap = (car:GetAttribute("MaxSpeed") or 150) * (car:GetAttribute("NitroSpeed") or 1.2)
						along = math.min(along, cap, measured and (measured * 1.25 + 8) or math.huge)
						if along == along and along > MIN_SPEED and along > math.min(vel.Magnitude, cap) * 0.7 then
							onRamp = r
						end
					end
				end
				if onRamp then
					s.phase = "armed"
					s.ramp = onRamp
					-- The lip: the high edge of the wedge (the back face, +Z local).
					s.lip = (onRamp.part.CFrame * CFrame.new(0, 0, onRamp.part.Size.Z / 2)).Position
					s.leftAt = t
				elseif s.phase == "armed" then
					if t - s.leftAt > 1.0 then
						s.phase = "idle"
					elseif heightAboveGround(chassis, car, char) > AIR_HEIGHT then
						s.phase = "air"
						s.airAt = t
						player:SetAttribute("InStunt", true)
					end
				end
			elseif s.phase == "air" then
				local h = heightAboveGround(chassis, car, char)
				if t - s.airAt > 6 then
					s.phase = "idle"
					player:SetAttribute("InStunt", false)
				elseif h < LAND_HEIGHT and t - s.airAt > 0.2 then
					s.phase = "idle"
					player:SetAttribute("InStunt", false)
					local distance = flatDist(chassis.Position, s.lip)
					local upright = chassis.CFrame.UpVector.Y > 0.6
					if upright and distance >= s.ramp.stunt.MinDist then
						reward(player, s.ramp.stunt, distance)
					else
						stuntEvent:FireClient(player, { Name = s.ramp.stunt.Name, Failed = true, Distance = math.floor(distance), Need = s.ramp.stunt.MinDist, Crashed = not upright })
					end
				end
			end
		end
	end
end

function StuntService.Init()
	stuntEvent = Remotes.Event("StuntEvent")
	local byId = {}
	for _, s in ipairs(Activities.Stunts) do
		byId[s.Id] = s
	end
	for _, part in ipairs(Workspace.Activities:GetChildren()) do
		local id = part:GetAttribute("StuntId")
		if id and byId[id] then
			table.insert(ramps, { part = part, stunt = byId[id] })
		end
	end
	-- Restore the "8/8" counter from saves when players load.
	local function onPlayer(player)
		task.spawn(function()
			for _ = 1, 20 do
				local data = DataService.Get(player)
				if data then
					local done = 0
					for _ in pairs(data.stunts or {}) do
						done += 1
					end
					player:SetAttribute("StuntsDone", done)
					return
				end
				task.wait(1)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	task.spawn(function()
		while true do
			task.wait(0.05)
			local ok, err = pcall(tick)
			if not ok then
				warn("[StuntService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		state[p] = nil
		lastReward[p] = nil
	end)
end

return StuntService
