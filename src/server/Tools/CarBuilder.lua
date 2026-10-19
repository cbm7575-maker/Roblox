-- CarBuilder (ModuleScript, ServerStorage.Tools.CarBuilder)
-- Builds a greybox car model for any vehicle in Config.Vehicles. Used at runtime by VehicleService
-- (when no hand-made template exists) and in Studio to preview cars.
--
-- Model layout (the raycast car, see Tech Spec):
--   Chassis (PrimaryPart): the only part with mass; collides with the world.
--     WheelFL/FR/RL/RR attachments: ray origins; ForceFL.. VectorForces push the body up (suspension).
--     Center attachment + DriveForce (at centre of mass) + BodyTorque (steering + keeping upright).
--   DriverSeat (VehicleSeat, touch-sitting off), WheelXX visuals (welded, moved by the client),
--   BumpXX invisible spheres that hold the car up when nobody drives it, body shell, lights, underglow.
--
-- Mesh bodies: if ServerStorage.CarBodies has a model named after the car, it replaces the greybox
-- shell. Body models are prepared once in Studio (see tools/CAR_BODIES.md): front facing -Z, pivot at
-- the point between the four wheel centres, already scaled to the car. Parts are named Body (painted,
-- texture stripped), Windows, Headlight, Taillight, Trim (kept as generated) and Wheels (dropped:
-- our own wheels spin). The chassis box then turns invisible but keeps the car's colour (the
-- Suspect Card reads it); the greybox shell it replaces (Cabin, Roof, Headlight, Taillight parts) is
-- destroyed. Only the Body and Windows cast shadows.
-- Every car starts with attribute Health = 100 (VehicleDamageService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)

local CarBuilder = {}

-- Tuning fields copied onto the model as attributes so the driving client can read them.
CarBuilder.TuningKeys = {
	"MaxSpeed", "ReverseSpeed", "Accel", "Brake", "Coast", "TireFriction", "Grip", "DriftGrip",
	"SteerRate", "YawResponse", "HighSpeedSteer", "UprightStrength", "UprightDamp",
	"RestLength", "WheelRadius", "SpringHz", "DampingRatio",
	"NitroAccel", "NitroSpeed", "NitroSeconds", "NitroRecharge", "Toughness",
}

local WHEELS = {
	{ "FL", -1, -1 },
	{ "FR", 1, -1 },
	{ "RL", -1, 1 },
	{ "RR", 1, 1 },
}

local function part(model, name, size, offset, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	p.Parent = model
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
	return w
end

-- Paint a car: chassis (the reference colour), the greybox roof and any mesh part marked BodyPaint.
function CarBuilder.Paint(car, color)
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") and (d == car.PrimaryPart or d.Name == "Roof" or d:GetAttribute("BodyPaint")) then
			d.Color = color
		end
	end
end

-- Swap the greybox shell for a mesh body (see the header). `wheelY` is the wheels' rest height
-- relative to the chassis centre.
local function attachBody(model, chassis, cfg, template, wheelY)
	local body = template:Clone()
	-- Bigger (or smaller) mesh wheels than the physics wheel radius: lift everything so the tyres
	-- still touch the road at rest.
	local wx, wz, wr = template:GetAttribute("WheelX"), template:GetAttribute("WheelZ"), template:GetAttribute("WheelRadius")
	local centreY = wheelY + (wr and (wr - cfg.WheelRadius) or 0)
	body:PivotTo(chassis.CFrame * CFrame.new(0, centreY, 0))
	-- The greybox shell goes before the mesh parts (some share its names) move in.
	for _, name in ipairs({ "Cabin", "Roof", "Headlight", "Taillight" }) do
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == name and d:IsA("Part") then
				d:Destroy()
			end
		end
	end
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Wheels" then
			d:Destroy() -- the mesh's own wheels never show (ours spin)
		end
	end
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			-- Lights and trim are small: their shadows sit inside the body's anyway.
			d.CastShadow = d.Name == "Body" or d.Name == "Windows"
			if d.Name == "Body" then
				d:SetAttribute("BodyPaint", true)
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
				d.Material = Enum.Material.SmoothPlastic
				d.Color = cfg.Color
			elseif d.Name == "Headlight" then
				d.Material = Enum.Material.Neon
				d.Color = Color3.fromRGB(255, 244, 210)
			elseif d.Name == "Taillight" then
				d.Material = Enum.Material.Neon
				d.Color = Color3.fromRGB(255, 40, 60)
			end
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = d
		end
	end
	for _, d in ipairs(body:GetChildren()) do
		d.Parent = model
	end
	body:Destroy()
	chassis.Transparency = 1
	chassis.CastShadow = false
	-- Underglow sized to the body, just under it.
	local under = model:FindFirstChild("Underglow")
	local _, ext = template:GetBoundingBox()
	if under and ext then
		local weld = under:FindFirstChildOfClass("WeldConstraint")
		if weld then
			weld.Enabled = false
		end
		under.Size = Vector3.new(math.max(ext.X - 1.4, 2), 0.2, math.max(ext.Z - 2.4, 4))
		if weld then
			weld.Enabled = true
		end
	end
	-- Move the spinning visual wheels (and rims) into the mesh's wheel arches. They're cosmetic: the
	-- suspension rays stay at the chassis corners.
	if wx and wz and wr then
		for _, w in ipairs(WHEELS) do
			local wheel = model:FindFirstChild("Wheel" .. w[1])
			local hub = wheel and wheel:FindFirstChild("Hub")
			if hub then
				local offset = Vector3.new(w[2] * wx, centreY, w[3] * wz)
				hub.C0 = CFrame.new(offset)
				wheel:SetAttribute("Offset", offset)
				wheel.Size = Vector3.new(wheel.Size.X, wr * 2, wr * 2)
				wheel.CFrame = chassis.CFrame * CFrame.new(offset)
				for _, rim in ipairs(model:GetChildren()) do
					local weld = rim.Name == "Rim" and rim:FindFirstChildOfClass("WeldConstraint")
					if weld and weld.Part0 == wheel then
						weld.Enabled = false
						rim.Size = Vector3.new(rim.Size.X, wr * 1.15, wr * 1.15)
						rim.CFrame = wheel.CFrame
						weld.Enabled = true
					end
				end
			end
		end
	end
	-- Mesh roofs sit lower than the greybox cabin: sink the driver a little (template attribute
	-- SeatDrop, default 0.8 studs) so heads stay inside.
	local drop = template:GetAttribute("SeatDrop") or 0.8
	for _, seatName in ipairs({ "DriverSeat", "PassengerSeat" }) do
		local seat = model:FindFirstChild(seatName)
		if seat and drop ~= 0 then
			for _, w in ipairs(seat:GetChildren()) do
				if w:IsA("WeldConstraint") then
					w.Enabled = false
					seat.CFrame = seat.CFrame * CFrame.new(0, -drop, 0)
					w.Enabled = true
				end
			end
		end
	end
end

-- Boats: a textured hull mesh (pivot at the bottom centre, front -Z). It hangs below the chassis so the
-- hull sits in the water while the water rays hold the chassis up. Keeps its own colours.
local function attachBoatBody(model, chassis, cfg, template)
	-- The greybox shell (and underglow, which would show through the hull) goes.
	for _, name in ipairs({ "Cabin", "Roof", "Headlight", "Taillight", "Underglow" }) do
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == name and d:IsA("Part") then
				d:Destroy()
			end
		end
	end
	local body = template:Clone()
	body:PivotTo(chassis.CFrame * CFrame.new(0, -cfg.Size.Y / 2 - (template:GetAttribute("Draft") or 0.9), 0))
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = d
			d.Parent = model
		end
	end
	body:Destroy()
	chassis.Transparency = 1
	chassis.CastShadow = false
	-- Rider height on the deck (template attribute SeatY, studs above the chassis centre).
	-- The passenger sits 2.4 studs behind the driver, at the same height.
	local seatY = template:GetAttribute("SeatY")
	if seatY then
		local z = template:GetAttribute("SeatZ") or cfg.Size.Z * 0.1
		for _, pair in ipairs({ { "DriverSeat", z }, { "PassengerSeat", z + 2.4 } }) do
			local seat = model:FindFirstChild(pair[1])
			if seat then
				local weld = seat:FindFirstChildOfClass("WeldConstraint")
				if weld then
					weld.Enabled = false
				end
				seat.CFrame = chassis.CFrame * CFrame.new(0, seatY, pair[2])
				if weld then
					weld.Enabled = true
				end
			end
		end
	end
end

-- Collision groups: "Vehicles" (every CarBuilder car) never collides with "Traffic" (TrafficClient).
function CarBuilder.EnsureGroups()
	local PhysicsService = game:GetService("PhysicsService")
	for _, name in ipairs({ "Vehicles", "Traffic" }) do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable("Vehicles", "Traffic", false)
end

function CarBuilder.Build(id)
	local cfg = Vehicles.Resolve(id)
	assert(cfg, "Unknown vehicle " .. tostring(id))
	local size = cfg.Size
	local W, H, L = size.X, size.Y, size.Z

	local model = Instance.new("Model")
	model.Name = id

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = size
	chassis.CFrame = CFrame.new()
	chassis.Color = cfg.Color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	-- Low friction so scraping walls or kerbs never grabs the car; the springs do all the work.
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.1, 0, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = chassis

	local drive = Instance.new("VectorForce")
	drive.Name = "DriveForce"
	drive.Attachment0 = center
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.ApplyAtCenterOfMass = true
	drive.Force = Vector3.zero
	drive.Parent = chassis

	local torque = Instance.new("Torque")
	torque.Name = "BodyTorque"
	torque.Attachment0 = center
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = chassis

	local wx, wy, wz = W / 2 - 0.6, -H / 2 + 0.6, L / 2 - 2.6
	local tire = Color3.fromRGB(28, 28, 32)
	for _, w in ipairs(WHEELS) do
		local name, sx, sz = w[1], w[2], w[3]
		local att = Instance.new("Attachment")
		att.Name = "Wheel" .. name
		att.Position = Vector3.new(sx * wx, wy, sz * wz)
		att.Parent = chassis

		local vf = Instance.new("VectorForce")
		vf.Name = "Force" .. name
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = false
		vf.Force = Vector3.zero
		vf.Parent = chassis

		-- Visual wheel: cylinder axis runs along X. The client slides it with the suspension and spins it.
		-- (Boats have none: their "wheels" are just the four water rays.)
		if cfg.Boat then
			continue
		end
		local offset = Vector3.new(sx * (W / 2 - 0.3), wy - cfg.RestLength * 0.6, sz * wz)
		local wheel = part(model, "Wheel" .. name, Vector3.new(1.1, cfg.WheelRadius * 2, cfg.WheelRadius * 2),
			CFrame.new(offset), tire, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		wheel:SetAttribute("Offset", offset)
		-- Rim: a bright disc on the wheel's face (colour is a Garage upgrade).
		local rim = part(model, "Rim", Vector3.new(1.2, cfg.WheelRadius * 1.15, cfg.WheelRadius * 1.15), CFrame.new(offset),
			Color3.fromRGB(200, 205, 215), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		weld(wheel, rim)
		-- Motor6D: clients move the wheel through Hub.Transform, which is cheap (no physics rebuild).
		local hub = Instance.new("Motor6D")
		hub.Name = "Hub"
		hub.Part0 = chassis
		hub.Part1 = wheel
		hub.C0 = CFrame.new(offset)
		hub.Parent = wheel

		-- Bump stop: its bottom sits WheelRadius + 20% of the travel below the ray origin, so it only
		-- touches the ground when the car is parked (no springs) or the suspension is 80% compressed.
		local bumpDrop = cfg.WheelRadius + cfg.RestLength * 0.2 - 0.6
		local bump = part(model, "Bump" .. name, Vector3.new(1.2, 1.2, 1.2), CFrame.new(att.Position + Vector3.new(0, -bumpDrop, 0)),
			Color3.new(1, 1, 1), nil, { Shape = Enum.PartType.Ball, Transparency = 1, CanCollide = true,
				CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.2, 0, 1, 1) })
		weld(chassis, bump)
	end

	-- Body shell (visual only)
	local glass = Color3.fromRGB(40, 50, 70)
	-- The seated driver's head reaches about 3.4 studs above the chassis centre, so the cabin is 2.5 tall.
	local cabin = part(model, "Cabin", Vector3.new(W - 1.2, 2.5, L * 0.42), CFrame.new(0, H / 2 + 1.25, L * 0.06),
		glass, Enum.Material.Glass, { Transparency = 0.35 })
	weld(chassis, cabin)
	local roof = part(model, "Roof", Vector3.new(W - 1.3, 0.25, L * 0.36), CFrame.new(0, H / 2 + 2.55, L * 0.08), cfg.Color)
	weld(chassis, roof)
	local lampY = 0.1
	for _, sx in ipairs({ -1, 1 }) do
		weld(chassis, part(model, "Headlight", Vector3.new(1.4, 0.5, 0.2), CFrame.new(sx * (W / 2 - 1.1), lampY, -L / 2 - 0.05),
			Color3.fromRGB(255, 250, 220), Enum.Material.Neon))
		weld(chassis, part(model, "Taillight", Vector3.new(1.4, 0.5, 0.2), CFrame.new(sx * (W / 2 - 1.1), lampY, L / 2 + 0.05),
			Color3.fromRGB(255, 40, 60), Enum.Material.Neon))
	end
	local glow = cfg.Police and Color3.fromRGB(34, 225, 255) or Color3.fromRGB(255, 62, 165)
	local under = part(model, "Underglow", Vector3.new(W - 1, 0.2, L - 1.6), CFrame.new(0, -H / 2 - 0.12, 0), glow, Enum.Material.Neon)
	weld(chassis, under)
	if cfg.Police then
		weld(chassis, part(model, "LightBarRed", Vector3.new(1.6, 0.4, 0.8), CFrame.new(-0.9, H / 2 + 2.85, L * 0.08),
			Color3.fromRGB(255, 40, 60), Enum.Material.Neon))
		weld(chassis, part(model, "LightBarBlue", Vector3.new(1.6, 0.4, 0.8), CFrame.new(0.9, H / 2 + 2.85, L * 0.08),
			Color3.fromRGB(40, 120, 255), Enum.Material.Neon))
	end

	-- Driver seat on the left, sunk into the body so the driver sits inside the cabin.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2.2)
	seat.CFrame = cfg.Boat and CFrame.new(0, H / 2 + 0.2, L * 0.1) or CFrame.new(-W / 2 + 2.1, H / 2 - 1.3, L * 0.12)
	seat.Color = Color3.fromRGB(30, 30, 36)
	seat.CastShadow = false
	seat.Massless = true
	seat.CanCollide = false
	seat.CanTouch = false -- no sitting by bumping into it; VehicleService seats the driver
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.HeadsUpDisplay = false
	seat.Parent = model
	weld(chassis, seat)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = cfg.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	-- Passenger seat: crewmates ride along (VehicleService checks the crew; CanTouch off so nobody
	-- sits by bumping into it).
	local pseat = Instance.new("Seat")
	pseat.Name = "PassengerSeat"
	pseat.Size = seat.Size
	pseat.CFrame = cfg.Boat and CFrame.new(0, H / 2 + 0.2, L * 0.1 + 2.4) or CFrame.new(W / 2 - 2.1, H / 2 - 1.3, L * 0.12)
	pseat.Color = seat.Color
	pseat.CastShadow = false
	pseat.Massless = true
	pseat.CanCollide = false
	pseat.CanTouch = false
	pseat.Parent = model
	weld(chassis, pseat)
	local ride = Instance.new("ProximityPrompt")
	ride.Name = "RidePrompt"
	ride.ActionText = "Ride"
	ride.ObjectText = cfg.DisplayName
	ride.KeyboardKeyCode = Enum.KeyCode.E
	ride.GamepadKeyCode = Enum.KeyCode.ButtonX
	ride.HoldDuration = 0
	ride.MaxActivationDistance = 14
	ride.RequiresLineOfSight = false
	-- Enabled on the server (a server-disabled prompt can't fire); each client hides it unless it's
	-- the owner's crewmate (VehicleVisuals), and VehicleService checks the crew again.
	ride.Parent = pseat

	model:SetAttribute("NCVehicle", true)
	model:SetAttribute("VehicleId", id)
	model:SetAttribute("DisplayName", cfg.DisplayName)
	model:SetAttribute("Police", cfg.Police == true)
	model:SetAttribute("Boat", cfg.Boat == true)
	model:SetAttribute("Health", 100)
	for _, k in ipairs(CarBuilder.TuningKeys) do
		model:SetAttribute(k, cfg[k])
	end
	local bodies = ServerStorage:FindFirstChild("CarBodies")
	local template = bodies and bodies:FindFirstChild(id)
	if template and cfg.Boat then
		attachBoatBody(model, chassis, cfg, template)
	elseif template then
		attachBody(model, chassis, cfg, template, wy - cfg.RestLength * 0.6)
	end
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	-- Players' and AI cars pass through client-side ambient traffic (TrafficClient knocks it away).
	CarBuilder.EnsureGroups()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Vehicles"
		end
	end
	return model
end

return CarBuilder
