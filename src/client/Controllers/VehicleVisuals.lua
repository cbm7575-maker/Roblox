-- VehicleVisuals (ModuleScript, StarterPlayerScripts.Controllers.VehicleVisuals)
-- Spins and bounces the wheels of cars this player is NOT driving (DriveController animates your own).
-- Cheap on purpose: only cars within 350 studs, updated at most 30 times a second.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local VehicleVisuals = {}

local WHEELS = { "FL", "FR", "RL", "RR" }
local RANGE = 350
local STEP = 1 / 30

local spin = setmetatable({}, { __mode = "k" }) -- [car] = angle
local accum = 0

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function animate(car, dt, camPos)
	local chassis = car.PrimaryPart
	local seat = car:FindFirstChild("DriverSeat")
	local occupant = seat and seat.Occupant
	-- "Drive" prompt: only on your own car, only while it's empty (local-only toggle).
	local prompt = seat and seat:FindFirstChild("DrivePrompt")
	if prompt then
		local show = occupant == nil and car:GetAttribute("OwnerUserId") == player.UserId
		if prompt.Enabled ~= show then
			prompt.Enabled = show
		end
	end
	-- "Ride" prompt: only for the owner's crewmates, only while the passenger seat is free.
	local pseat = car:FindFirstChild("PassengerSeat")
	local ride = pseat and pseat:FindFirstChild("RidePrompt")
	if ride then
		local owner = Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
		local crew = player:GetAttribute("Crew")
		local show = pseat.Occupant == nil and owner ~= nil and owner ~= player and crew ~= nil and owner:GetAttribute("Crew") == crew
		if ride.Enabled ~= show then
			ride.Enabled = show
		end
	end
	if not chassis or (chassis.Position - camPos).Magnitude > RANGE then
		return
	end
	if occupant and occupant.Parent == player.Character then
		return -- DriveController handles the car we drive
	end
	local rest = car:GetAttribute("RestLength") or 1.4
	local radius = car:GetAttribute("WheelRadius") or 1.2
	local cf = chassis.CFrame
	local fwd = chassis.AssemblyLinearVelocity:Dot(cf.LookVector)
	local a = ((spin[car] or 0) + fwd / radius * dt) % (math.pi * 2)
	spin[car] = a
	params.FilterDescendantsInstances = { car, Workspace:FindFirstChild("Smoke") }
	local down = -cf.UpVector * (rest + radius)
	for _, name in ipairs(WHEELS) do
		local att = chassis:FindFirstChild("Wheel" .. name)
		local wheel = car:FindFirstChild("Wheel" .. name)
		local hub = wheel and wheel:FindFirstChild("Hub")
		if att and hub then
			local hit = Workspace:Raycast(att.WorldPosition, down, params)
			local r = wheel.Size.Y / 2 -- the visual wheel's own radius (mesh bodies differ from the physics one)
			local drop = hit and (hit.Distance - r) or (rest + radius - r)
			local base = wheel:GetAttribute("Offset") or hub.C0.Position
			hub.Transform = CFrame.new(0, (att.Position.Y - drop) - base.Y, 0) * CFrame.Angles(-a, 0, 0)
		end
	end
end

function VehicleVisuals.Init()
	-- Passengers get out with F (drivers use DriveController's own binding); jumping works too.
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.F then
			return
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart and hum.SeatPart.Name == "PassengerSeat" then
			require(game:GetService("ReplicatedStorage").Shared.Util.Remotes).Event("RequestExitCar"):FireServer()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		accum += dt
		if accum < STEP then
			return
		end
		local step = accum
		accum = 0
		local folder = Workspace:FindFirstChild("Vehicles")
		if not folder then
			return
		end
		local camPos = Workspace.CurrentCamera.CFrame.Position
		for _, car in ipairs(folder:GetChildren()) do
			local ok, err = pcall(animate, car, step, camPos)
			if not ok then
				warn("[VehicleVisuals] " .. tostring(err))
			end
		end
	end)
end

return VehicleVisuals
