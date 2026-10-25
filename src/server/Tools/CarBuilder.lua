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
-- destroyed. Only the Body and Windows cast shadows. Config BodyScale enlarges a body whose cabin is too
-- low for a seated avatar (wheels and arches scale with it); boats can have their hull turned and refitted
-- (Config Hull). Police light bars sit on the mesh roof.
-- Seats (Config Seats / Cabin, see Config.Vehicles): DriverSeat (VehicleSeat), PassengerSeat and, for
-- Seats = 4, RearSeatL / RearSeatR (Seats). Every passenger seat has attribute Passenger = true; one
-- RidePrompt on the PassengerSeat serves them all (VehicleService picks a free one). Low cars recline.
--   CarBuilder.BoatReach: Drive/Ride prompt range on boats (they float off the end of the docks).
--   CarBuilder.PlayPose(model, "sit" | "walk"): Roblox's stock R15 animation on a rig (Humanoid or
--     AnimationController), played on the server so everyone sees it (taxi passengers, showroom).
--   CarBuilder.Showroom(origin): Studio check (Play, server command bar): every vehicle in a row with
--     R15 dummies (1.05 height scale) in every seat, in Workspace.CarShowroom. Showroom(nil) clears it.
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

local SEAT_SIZE = Vector3.new(2, 0.4, 2.2)
local CAR_REACH = 14
CarBuilder.BoatReach = 60 -- boats wait past the dock ends (25-55 studs out), so their prompts reach far

-- Roblox's stock R15 animations (the default Animate script's).
local POSES = { sit = "rbxassetid://2506281703", walk = "rbxassetid://507777826" }

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

-- Turn a body about its pivot (degrees, around the vertical) and stretch it by (fx, fy, fz) along the
-- pivot's axes. Parts keep their own rotations; sizes scale along each part's own axes, so 90-degree
-- turned parts are handled (BodyPrep.FixBoat's maths).
local function reshape(body, turn, fx, fy, fz)
	local pivot = body:GetPivot()
	local spin = CFrame.Angles(0, math.rad(turn or 0), 0)
	local function k(v)
		return math.abs(v.X) * fx + math.abs(v.Y) * fy + math.abs(v.Z) * fz
	end
	for _, p in ipairs(body:GetDescendants()) do
		if p:IsA("BasePart") then
			local rel = spin * pivot:ToObjectSpace(p.CFrame)
			local rot = rel.Rotation
			p.Size = Vector3.new(p.Size.X * k(rot.RightVector), p.Size.Y * k(rot.UpVector), p.Size.Z * k(rot.LookVector))
			local at = rel.Position
			p.CFrame = pivot * CFrame.new(at.X * fx, at.Y * fy, at.Z * fz) * rot
		end
	end
end

-- The box (relative to the pivot, pivot axes) that a body would fill after turning it by `turn` degrees.
local function turnedBounds(body, turn)
	local pivot = body:GetPivot()
	local spin = CFrame.Angles(0, math.rad(turn or 0), 0)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in ipairs(body:GetDescendants()) do
		if p:IsA("BasePart") then
			local rel = spin * pivot:ToObjectSpace(p.CFrame)
			local r, u, l = rel.RightVector, rel.UpVector, rel.LookVector
			local h = p.Size / 2
			local ext = Vector3.new(
				math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
				math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
				math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z)
			lo = lo:Min(rel.Position - ext)
			hi = hi:Max(rel.Position + ext)
		end
	end
	return lo, hi
end

-- Where each seat goes, in chassis space: { name, CFrame, passenger }. The CFrame puts the seat's top
-- centre at the Cabin point, reclined by Tilt degrees (the rider leans back with the seat).
local function seatCFrame(x, top, z, tilt)
	return CFrame.new(x, top, z) * CFrame.Angles(math.rad(tilt or 0), 0, 0) * CFrame.new(0, -SEAT_SIZE.Y / 2, 0)
end

local function seatLayout(cfg)
	local W, H, L = cfg.Size.X, cfg.Size.Y, cfg.Size.Z
	local c = cfg.Cabin
	local list = {}
	if c then
		local x = c.X or 0
		table.insert(list, { "DriverSeat", seatCFrame(-x, c.Y, c.Z, c.Tilt), false })
		if x == 0 then
			table.insert(list, { "PassengerSeat", seatCFrame(0, c.Y, c.Z + (c.Inline or 2.4), c.Tilt), true })
		else
			table.insert(list, { "PassengerSeat", seatCFrame(x, c.Y, c.Z, c.Tilt), true })
		end
		local r = c.Rear
		if r and (cfg.Seats or 2) >= 4 then
			table.insert(list, { "RearSeatL", seatCFrame(-(r.X or x), r.Y, r.Z, r.Tilt), true })
			table.insert(list, { "RearSeatR", seatCFrame(r.X or x, r.Y, r.Z, r.Tilt), true })
		end
	else
		-- Greybox layout (no cabin data): driver on the left, sunk into the body.
		local y = cfg.Boat and H / 2 + 0.2 or H / 2 - 1.3
		local driver = cfg.Boat and CFrame.new(0, y, L * 0.1) or CFrame.new(-W / 2 + 2.1, y, L * 0.12)
		table.insert(list, { "DriverSeat", driver, false })
		table.insert(list, { "PassengerSeat", cfg.Boat and CFrame.new(0, y, L * 0.1 + 2.4) or CFrame.new(W / 2 - 2.1, y, L * 0.12), true })
		if (cfg.Seats or 2) >= 4 and not cfg.Boat then
			table.insert(list, { "RearSeatL", CFrame.new(-W / 2 + 2.1, y, L * 0.12 + 2.4), true })
			table.insert(list, { "RearSeatR", CFrame.new(W / 2 - 2.1, y, L * 0.12 + 2.4), true })
		end
	end
	return list
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
	-- A body scaled up for headroom: everything (wheels and arches too) grows about the wheel-centre pivot.
	local scale = cfg.BodyScale or 1
	if scale ~= 1 then
		reshape(body, 0, scale, scale, scale)
	end
	-- Bigger (or smaller) mesh wheels than the physics wheel radius: lift everything so the tyres
	-- still touch the road at rest.
	local wx, wz, wr = template:GetAttribute("WheelX"), template:GetAttribute("WheelZ"), template:GetAttribute("WheelRadius")
	if wx and wz and wr then
		wx, wz, wr = wx * scale, wz * scale, wr * scale
	end
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
	ext = ext and ext * scale
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
	-- Police light bars on the mesh roof (the greybox height floats over low roofs and hides in tall ones).
	-- A roof-mounted Trim taller than the body (a mesh light bar) carries them instead.
	local bodyPart = template:FindFirstChild("Body")
	local trim = template:FindFirstChild("Trim")
	if bodyPart and bodyPart:IsA("BasePart") then
		local pivot = template:GetPivot()
		local function top(p)
			local rel = pivot:ToObjectSpace(p.CFrame)
			local u = rel.UpVector
			local r, l = rel.RightVector, rel.LookVector
			local h = p.Size / 2
			return rel.Position.Y + math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
		end
		local roof = top(bodyPart)
		if trim and trim:IsA("BasePart") and top(trim) > roof + 0.3 then
			roof = top(trim) - 0.25
		end
		local windows = template:FindFirstChild("Windows")
		local barZ = windows and windows:IsA("BasePart") and pivot:ToObjectSpace(windows.CFrame).Position.Z * scale or nil
		for _, bar in ipairs(model:GetChildren()) do
			if bar:IsA("BasePart") and (bar.Name == "LightBarRed" or bar.Name == "LightBarBlue") then
				local w = bar:FindFirstChildOfClass("WeldConstraint")
				if w then
					w.Enabled = false
				end
				local at = chassis.CFrame:PointToObjectSpace(bar.Position)
				bar.CFrame = chassis.CFrame * CFrame.new(at.X, centreY + roof * scale + bar.Size.Y / 2, barZ or at.Z)
				if w then
					w.Enabled = true
				end
			end
		end
	end
	-- No cabin data: mesh roofs sit lower than the greybox cabin, so sink the seats a little (template
	-- attribute SeatDrop, default 0.8 studs).
	if cfg.Cabin then
		return
	end
	local drop = template:GetAttribute("SeatDrop") or 0.8
	for _, seat in ipairs(model:GetChildren()) do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local w = seat:FindFirstChildOfClass("WeldConstraint")
			if w and drop ~= 0 then
				w.Enabled = false
				seat.CFrame = seat.CFrame * CFrame.new(0, -drop, 0)
				w.Enabled = true
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
	-- Config Hull: turn the stored hull about its pivot (bottom centre) and refit it to Hull.Size.
	local hull = cfg.Hull
	if hull and hull.Size then
		local lo, hi = turnedBounds(body, hull.Turn)
		local size = hi - lo
		if size.X > 0 and size.Y > 0 and size.Z > 0 then
			reshape(body, hull.Turn, hull.Size.X / size.X, hull.Size.Y / size.Y, hull.Size.Z / size.Z)
		end
	end
	body:PivotTo(chassis.CFrame * CFrame.new(0, -cfg.Size.Y / 2 - (template:GetAttribute("Draft") or 0.9), 0))
	-- Police boats: the light bars go on top of the hull (inside it, nobody would see them flash).
	local hullCf, hullSize = body:GetBoundingBox()
	local hullTop = chassis.CFrame:PointToObjectSpace(hullCf.Position).Y + hullSize.Y / 2
	for _, bar in ipairs(model:GetChildren()) do
		if bar:IsA("BasePart") and (bar.Name == "LightBarRed" or bar.Name == "LightBarBlue") then
			local w = bar:FindFirstChildOfClass("WeldConstraint")
			if w then
				w.Enabled = false
			end
			local at = chassis.CFrame:PointToObjectSpace(bar.Position)
			bar.CFrame = chassis.CFrame * CFrame.new(at.X, hullTop + bar.Size.Y / 2 - 0.1, at.Z)
			if w then
				w.Enabled = true
			end
		end
	end
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
	-- No cabin data: rider height on the deck from template attribute SeatY (studs above the chassis
	-- centre); the passenger sits 2.4 studs behind the driver, at the same height.
	local seatY = template:GetAttribute("SeatY")
	if seatY and not cfg.Cabin then
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

	-- Seats (Config Cabin; CanTouch off: nobody sits by bumping into one, VehicleService seats people).
	local reach = cfg.Boat and CarBuilder.BoatReach or CAR_REACH
	local seat, pseat
	for _, entry in ipairs(seatLayout(cfg)) do
		local name, cf, passenger = entry[1], entry[2], entry[3]
		local s = Instance.new(passenger and "Seat" or "VehicleSeat")
		s.Name = name
		s.Size = SEAT_SIZE
		s.CFrame = cf
		s.Color = Color3.fromRGB(30, 30, 36)
		s.Transparency = cfg.Cabin and 1 or 0 -- mesh cabins have their own seats
		s.CastShadow = false
		s.Massless = true
		s.CanCollide = false
		s.CanTouch = false
		if s:IsA("VehicleSeat") then
			s.MaxSpeed = 0
			s.Torque = 0
			s.TurnSpeed = 0
			s.HeadsUpDisplay = false
			seat = s
		else
			s:SetAttribute("Passenger", true)
			if name == "PassengerSeat" then
				pseat = s
			end
		end
		s.Parent = model
		weld(chassis, s)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = cfg.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = reach
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	-- One Ride prompt for every passenger seat (VehicleService picks the free seat nearest the rider).
	local ride = Instance.new("ProximityPrompt")
	ride.Name = "RidePrompt"
	ride.ActionText = "Ride"
	ride.ObjectText = cfg.DisplayName
	ride.KeyboardKeyCode = Enum.KeyCode.E
	ride.GamepadKeyCode = Enum.KeyCode.ButtonX
	ride.HoldDuration = 0
	ride.MaxActivationDistance = reach
	ride.RequiresLineOfSight = false
	-- Enabled on the server (a server-disabled prompt can't fire); each client hides it unless it may
	-- ride with the owner (VehicleVisuals), and VehicleService checks again.
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

-- Play one of Roblox's stock R15 animations ("sit", "walk") on a rig with a Humanoid or an
-- AnimationController. Server-side, so every player sees it. Returns the track (or nil).
function CarBuilder.PlayPose(model, name)
	local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not host or not POSES[name] then
		return nil
	end
	local animator = host:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = host
	end
	local ok, track = pcall(function()
		local anim = Instance.new("Animation")
		anim.AnimationId = POSES[name]
		local t = animator:LoadAnimation(anim)
		t.Looped = true
		t.Priority = Enum.AnimationPriority.Action
		t:Play(0)
		return t
	end)
	return ok and track or nil
end

-- Studio fit check (Play mode, server command bar):
--   require(game.ServerStorage.Tools.CarBuilder).Showroom(Vector3.new(0, 0, 0))
-- Builds every vehicle in a row (anchored, 16 studs apart) with an R15 dummy at 1.05 height scale in every
-- seat, sitting like a player does, in Workspace.CarShowroom. Showroom(nil) removes it.
function CarBuilder.Showroom(origin)
	local Players = game:GetService("Players")
	local old = workspace:FindFirstChild("CarShowroom")
	if old then
		old:Destroy()
	end
	if not origin then
		return "cleared"
	end
	local folder = Instance.new("Folder")
	folder.Name = "CarShowroom"
	folder.Parent = workspace
	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale = 1.05
	for i, def in ipairs(Vehicles.List) do
		local car = CarBuilder.Build(def.Id)
		local cfg = Vehicles.Resolve(def.Id)
		-- Resting ride height: springs 45% compressed (boats: the same over the water line).
		local floor = cfg.RestLength * 0.55 + cfg.WheelRadius + cfg.Size.Y / 2 - 0.6
		car:PivotTo(CFrame.new(origin + Vector3.new((i - 1) * 16, floor, 0)))
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			elseif d:IsA("ProximityPrompt") then
				d.Enabled = false
			end
		end
		car.Parent = folder
		for _, seat in ipairs(car:GetChildren()) do
			if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
				local ok, dummy = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
				if ok and dummy then
					dummy.Name = def.Id .. "_" .. seat.Name
					for _, d in ipairs(dummy:GetDescendants()) do
						if d:IsA("BaseScript") then
							d:Destroy()
						elseif d:IsA("BasePart") then
							d.Massless = true
						end
					end
					dummy:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
					dummy.Parent = folder
					local hum = dummy:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
						seat:Sit(hum)
						CarBuilder.PlayPose(dummy, "sit")
					end
				end
			end
		end
	end
	return string.format("%d vehicles in Workspace.CarShowroom", #Vehicles.List)
end

return CarBuilder
