-- VehicleVisuals (ModuleScript, StarterPlayerScripts.Controllers.VehicleVisuals)
-- Spins and bounces the wheels of cars this player is NOT driving (DriveController animates your own).
-- Cheap on purpose: only cars within 350 studs, updated at most 30 times a second.
-- Also shows each car's Drive / Ride prompt only to someone the server would seat (never while
-- tasered or knocked over), and lets passengers get out with F or gamepad B (RequestExitCar, the
-- same as DriveUI's EXIT button and the driver's keys).
-- Tyre smoke and skid marks: any car (yours too, never boats) that slides sideways (over 25 studs/s,
-- about 12 degrees or more off its nose) within 220 studs puffs smoke from its rear tyres and leaves
-- dark marks that fade after 5 s. Local-only instances on the car's chassis: two emitters and two
-- trails per car, for at most 6 cars at once; a car that hasn't slid for 8 s gives its set back, and
-- a destroyed car takes them with it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local VehicleVisuals = {}

local WHEELS = { "FL", "FR", "RL", "RR" }
local REAR = { "RL", "RR" }
local RANGE = 350
local STEP = 1 / 30

local SKID_RANGE = 220 -- studs from the camera
local SKID_CARS = 6 -- cars that can smoke at once
local SKID_IDLE = 8 -- seconds without sliding before a car's emitters are removed (marks last 5)
local SLIDE_SPEED = 25 -- studs/s
local SLIDE_SIN = 0.2 -- sideways share of the speed: about 12 degrees off the nose
local TYRE_HALF = 0.45 -- half the width of a skid mark

local spin = setmetatable({}, { __mode = "k" }) -- [car] = angle
local accum = 0

local skids = {} -- [car] = { on, last, RL = { a, b, trail, smoke }, RR = {...} }
local skidCount = 0
local lastPrune = 0
local rearHit = {} -- the rear wheels' ground hits of the car being animated (scratch)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

------------------------------------------------------------------ tyre smoke and skid marks

local function newSkid(car, chassis)
	local fx = { on = false, last = os.clock() }
	for _, name in ipairs(REAR) do
		-- The two ends of the tyre's footprint; moved onto the road under the wheel while it slides.
		local a = Instance.new("Attachment")
		a.Name = "Skid" .. name .. "A"
		a.Parent = chassis
		local b = Instance.new("Attachment")
		b.Name = "Skid" .. name .. "B"
		b.Parent = chassis
		local trail = Instance.new("Trail")
		trail.Name = "SkidMark" .. name
		trail.Attachment0, trail.Attachment1 = a, b
		trail.FaceCamera = false -- flat on the road
		trail.Color = ColorSequence.new(Color3.fromRGB(14, 14, 16))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = 5
		trail.MinLength = 1.5 -- few segments: a 5 s mark at speed is a few hundred, not thousands
		trail.LightEmission = 0
		trail.LightInfluence = 1
		trail.Enabled = false
		trail.Parent = chassis
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "TyreSmoke"
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(226, 226, 232))
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.78),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 6) })
		smoke.Lifetime = NumberRange.new(0.6, 1.1)
		smoke.Speed = NumberRange.new(2, 5)
		smoke.SpreadAngle = Vector2.new(35, 35)
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Acceleration = Vector3.new(0, 4, 0)
		smoke.Drag = 2
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-40, 40)
		smoke.LightEmission = 0
		smoke.LightInfluence = 1
		smoke.Rate = 25
		smoke.Enabled = false
		smoke.Parent = a
		fx[name] = { a = a, b = b, trail = trail, smoke = smoke }
	end
	skids[car] = fx
	skidCount += 1
	return fx
end

local function skidOff(fx)
	fx.on = false
	for _, name in ipairs(REAR) do
		local w = fx[name]
		w.trail.Enabled = false
		w.smoke.Enabled = false
	end
end

local function dropSkid(car, fx)
	for _, name in ipairs(REAR) do
		local w = fx[name]
		w.trail:Destroy()
		w.smoke:Destroy()
		w.a:Destroy()
		w.b:Destroy()
	end
	skids[car] = nil
	skidCount -= 1
end

-- Give back the sets of cars that are gone or have stopped sliding for a while (once a second).
local function pruneSkids(now)
	for car, fx in pairs(skids) do
		-- (a destroyed car has already taken its emitters and trails with it; destroying them again is harmless)
		if not car.Parent or not car.PrimaryPart or now - fx.last > SKID_IDLE then
			dropSkid(car, fx)
		end
	end
end

-- How fast the car slides sideways (studs/s), or 0 when that isn't a slide worth smoke.
local function slideSpeed(chassis, cf)
	local vel = chassis.AssemblyLinearVelocity
	local speed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	if speed < SLIDE_SPEED then
		return 0
	end
	local lat = math.abs(vel:Dot(cf.RightVector))
	return lat >= speed * SLIDE_SIN and lat or 0
end

-- lat: sideways speed (0 = not sliding). ray: cast for the rear wheels here (our own car, whose
-- wheels DriveController animates); otherwise rearHit holds this step's hits from the wheel loop.
local function updateSkid(car, chassis, cf, lat, down, ray)
	local fx = skids[car]
	if lat <= 0 then
		if fx and fx.on then
			skidOff(fx)
		end
		return
	end
	if not fx then
		if skidCount >= SKID_CARS then
			return
		end
		fx = newSkid(car, chassis)
	end
	fx.on = true
	fx.last = os.clock()
	local half = cf.RightVector * TYRE_HALF
	local rate = math.clamp(lat * 0.8, 12, 40)
	for _, name in ipairs(REAR) do
		local w = fx[name]
		local hit = rearHit[name]
		if ray then
			local att = chassis:FindFirstChild("Wheel" .. name)
			hit = att and Workspace:Raycast(att.WorldPosition, down, params) or nil
		end
		if hit then
			-- On the ground: lay the mark a hair above the road and puff from the same spot.
			local p = hit.Position + hit.Normal * 0.08
			w.a.WorldPosition = p - half
			w.b.WorldPosition = p + half
			w.smoke.Rate = rate
		end
		local touching = hit ~= nil
		if w.trail.Enabled ~= touching then
			w.trail.Enabled = touching
			w.smoke.Enabled = touching
		end
	end
end

------------------------------------------------------------------ wheels and prompts

-- downed: this player is tasered or knocked over (no prompts then; the server refuses them too).
local function animate(car, dt, camPos, downed)
	local chassis = car.PrimaryPart
	local seat = car:FindFirstChild("DriverSeat")
	local occupant = seat and seat.Occupant
	-- "Drive" prompt: only on your own car, only while it's empty (local-only toggle).
	local prompt = seat and seat:FindFirstChild("DrivePrompt")
	if prompt then
		local show = not downed and occupant == nil and car:GetAttribute("OwnerUserId") == player.UserId
		if prompt.Enabled ~= show then
			prompt.Enabled = show
		end
	end
	-- "Ride" prompt: only for the owner's crewmates on the same side (never prisoners), only while the
	-- passenger seat is free (the server's rules).
	local pseat = car:FindFirstChild("PassengerSeat")
	local ride = pseat and pseat:FindFirstChild("RidePrompt")
	if ride then
		local owner = Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
		local crew = player:GetAttribute("Crew")
		local side = player:GetAttribute("Side")
		local show = not downed and pseat.Occupant == nil and owner ~= nil and owner ~= player and crew ~= nil
			and owner:GetAttribute("Crew") == crew and side ~= "Prisoner" and owner:GetAttribute("Side") == side
		if ride.Enabled ~= show then
			ride.Enabled = show
		end
	end
	if not chassis then
		return
	end
	local away = (chassis.Position - camPos).Magnitude
	if away > RANGE then
		local fx = skids[car]
		if fx and fx.on then
			skidOff(fx)
		end
		return
	end
	local rest = car:GetAttribute("RestLength") or 1.4
	local radius = car:GetAttribute("WheelRadius") or 1.2
	local cf = chassis.CFrame
	local down = -cf.UpVector * (rest + radius)
	-- Sliding sideways? (Boats don't smoke, and far-off cars aren't worth it.)
	local lat = 0
	if away < SKID_RANGE and car:GetAttribute("Boat") ~= true then
		lat = slideSpeed(chassis, cf)
	end
	local own = occupant ~= nil and occupant.Parent == player.Character
	if lat > 0 or not own then
		params.FilterDescendantsInstances = { car, Workspace:FindFirstChild("Smoke") }
	end
	if own then
		-- DriveController handles the wheels of the car we drive; only the smoke is done here.
		if lat > 0 or skids[car] then
			updateSkid(car, chassis, cf, lat, down, true)
		end
		return
	end
	local fwd = chassis.AssemblyLinearVelocity:Dot(cf.LookVector)
	local a = ((spin[car] or 0) + fwd / radius * dt) % (math.pi * 2)
	spin[car] = a
	rearHit.RL, rearHit.RR = nil, nil
	for _, name in ipairs(WHEELS) do
		local att = chassis:FindFirstChild("Wheel" .. name)
		local wheel = car:FindFirstChild("Wheel" .. name)
		local hub = wheel and wheel:FindFirstChild("Hub")
		local rear = name == "RL" or name == "RR"
		-- (a car with no wheel parts still gets its rear rays while it slides, for the smoke)
		if att and (hub or (rear and lat > 0)) then
			local hit = Workspace:Raycast(att.WorldPosition, down, params)
			if rear then
				rearHit[name] = hit
			end
			if hub then
				local r = wheel.Size.Y / 2 -- the visual wheel's own radius (mesh bodies differ from the physics one)
				local drop = hit and (hit.Distance - r) or (rest + radius - r)
				local base = wheel:GetAttribute("Offset") or hub.C0.Position
				hub.Transform = CFrame.new(0, (att.Position.Y - drop) - base.Y, 0) * CFrame.Angles(-a, 0, 0)
			end
		end
	end
	if lat > 0 or skids[car] then
		updateSkid(car, chassis, cf, lat, down, false)
	end
end

function VehicleVisuals.Init()
	-- (Getting out with F / B / E, for drivers and passengers alike, is DriveController's job.)
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
		local t = Workspace:GetServerTimeNow()
		local downed = (player:GetAttribute("StunnedUntil") or 0) > t or (player:GetAttribute("KnockedUntil") or 0) > t
		for _, car in ipairs(folder:GetChildren()) do
			local ok, err = pcall(animate, car, step, camPos, downed)
			if not ok then
				warn("[VehicleVisuals] " .. tostring(err))
			end
		end
		local now = os.clock()
		if now - lastPrune > 1 then
			lastPrune = now
			pruneSkids(now)
		end
	end)
end

return VehicleVisuals
