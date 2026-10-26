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
-- texture stripped), Windows, Headlight, Taillight, Trim (kept as generated) and Wheels (hidden:
-- our own wheels spin). The chassis box then turns invisible but keeps the car's colour (the
-- Suspect Card reads it). The driver and passenger seats are then fitted into the body's cabin,
-- worked out from its glass (fitSeats): lowered, and leaned back in very low cars, so heads stay
-- under the roof (open tops from Config.Vehicles OpenTop keep their old height). Cars checked by eye
-- override that with SeatDrop / SeatZ / SeatTilt (template attributes, else their Config.Vehicles copy).
-- Greybox cars and boats keep their fixed seat spots (boats: template attributes SeatY / SeatZ).
--
-- Street cars (Config.Vehicles TrafficModel, the carjack cars): the body is a textured traffic car from
-- ReplicatedStorage.TrafficModels (or a given copy, e.g. a parked one: Build's opts.Body), kept at its own
-- size so a jacked car looks exactly like the one taken; the chassis is sized to it instead. Its bottom
-- sits on the road at rest. A separate wheel part is hidden and our spinning wheels go into its arches
-- (centred on that part, not on the body); bodies with the wheels baked into one mesh keep theirs and
-- ours are hidden. The seat fit takes the cabin floor at sill height (a wheel radius above the road), not
-- at the tyres' bottom. No underglow.
-- Every car gets attribute RideHeight: studs from the chassis centre down to the road at rest.
--
-- Body joint (CarBuilder.AddBodyJoint(model), land cars only; Build calls it, and VehicleService calls it
-- again on every car it spawns, because the saved ServerStorage.VehicleTemplates were built before it
-- existed; calling it twice changes nothing):
--   BodyRoot   an invisible, massless, non-colliding part sitting exactly on the chassis, joined to it by
--              the Motor6D "BodyJoint" (in BodyRoot; Part0 = Chassis). Everything you only LOOK at (body
--              mesh, glass, lights, trim, greybox shell, underglow, light bar) is welded to BodyRoot
--              instead of the chassis. Seats, bump stops, the wheels' Hub joints (rims ride on the wheels)
--              and every force attachment stay on the chassis.
--              Each device then leans the body on its springs by setting BodyJoint.Transform (VehicleFeel
--              on the client: roll in corners, nose-dive, squat, one rebound over a kerb). Transform never
--              replicates and never touches the physics: the chassis, the camera and the wheels stay put.
--              The joint's C0 / C1 put the pivot at axle height, so a Transform of plain angles rolls the
--              body about its axles.
--   BodyLean   model attribute, 0-1: how much of that lean this body gets. 1 normally; less for a street
--              body with its tyres baked into the mesh (they would dip into the road), and its pivot is
--              then at road level.
--   DriverDoor / PassengerDoor   Attachments on the Chassis: where someone stands to open that door (a
--              standing character's root height above the road, beside the seat, clear of the body's side)
--              looking at the car (the attachment looks along its -Z). InteractClient walks you there
--              before you get in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)

local CarBuilder = {}

-- Tuning fields copied onto the model as attributes so the driving client can read them. (A field the
-- car's config doesn't have is simply not set: CarPhysics then uses its own default for it.)
CarBuilder.TuningKeys = {
	"MaxSpeed", "ReverseSpeed", "Accel", "Brake", "Coast", "TireFriction", "Grip", "DriftGrip",
	"DriftSteer", "DriftPower",
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

-- Seat fitting for mesh bodies (studs, measured on a seated R15 character).
local HEAD_ABOVE_SEAT = 3.4 -- a seated character's head top above the seat's top surface
local HAIR_ROOM = 0.9 -- extra room for big hair and hats
local HEAD_MID = 2.7 -- seat top to the middle of a seated character's head
local FLOOR_GAP = 0.4 -- the cabin floor sits this far above the body's lowest point
local OLD_SINK = 0.8 -- how far mesh-body seats used to be sunk below the greybox spot
local MAX_RECLINE = 30 -- degrees a seat may lean back to get a head under a low roof
local OPEN_GLASS = 0.22 -- glass shorter than this share of the body length is only a windscreen

local reported = {} -- car id + overrides whose seat fit was already printed / warned about (see fitSeats)

-- Axis-aligned box (lo, hi corners) around the template parts that pass `keep`, in the template's own
-- frame (pivot between the wheel centres, front -Z). A rotated part reaches along each axis by the sum
-- of its three half-sizes times how much each of its own axes points that way. nil if nothing matched.
local function boundsOf(template, keep)
	local frame = template:GetPivot()
	local lo, hi
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") and keep(d) then
			local cf = frame:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
			local reach = Vector3.new(
				math.abs(rx.X) * h.X + math.abs(ry.X) * h.Y + math.abs(rz.X) * h.Z,
				math.abs(rx.Y) * h.X + math.abs(ry.Y) * h.Y + math.abs(rz.Y) * h.Z,
				math.abs(rx.Z) * h.X + math.abs(ry.Z) * h.Y + math.abs(rz.Z) * h.Z
			)
			local a, b = cf.Position - reach, cf.Position + reach
			lo = lo and lo:Min(a) or a
			hi = hi and hi:Max(b) or b
		end
	end
	return lo, hi
end

-- CarBuilder.Bounds(model, keep) -> lo, hi: the same box, for other services (CarjackService finds a
-- parked car's driver door with it).
CarBuilder.Bounds = boundsOf

-- Put the driver and passenger seats inside a mesh body's cabin, measured on the template (before it
-- is cloned and welded). `centreY` is the body pivot's height above the chassis centre, so a template
-- point p ends up at (p.X, centreY + p.Y, p.Z) on the chassis.
--   Along the car (Z): the Windows (glass) box runs from the windscreen's foot to the back window, so
--     its middle is mid-cabin (on a pickup, mid-cab, not the bed). The driver sits 6% of the glass
--     length forward of that (front is -Z, so minus), keeping the head under the roof and not under
--     the sloping windscreen. If the glass is only a windscreen (shorter than 22% of the body) the old
--     spot is kept, pushed back behind the windscreen if needed. No glass: the old spot.
--     Open tops (Config.Vehicles OpenTop, e.g. convertibles) are never treated as a closed cabin,
--     whatever their glass looks like, and have no roof to fit under.
--   Across (X): driver at -15.5% of the body's width, passenger mirrored (hands stay inside the doors).
--   Height: a seated head top is 3.4 studs above the seat's top, plus up to 0.9 for hair.
--     Closed cabins: the head goes in the middle of the side windows (seat top = glass middle - 2.7),
--     as long as the head still fits under the roof with the seat leaned back; otherwise lower.
--     Everything else: seat top = min(old height, roof - 4.3), where roof = the glass top (else the
--     body's top), never below the cabin floor (body bottom + 0.4) and never above the old height.
--     Open tops are best hand-tuned with SeatDrop (the driver's shoulders above the doors).
--     The invisible chassis box may overlap the seat.
--   Recline: low bodies often have no room for a sitting R15 between floor and roof, so if the head
--     still pokes through, the seat leans back (up to MAX_RECLINE degrees) until it fits, and slides
--     forward a little so the head stays under the roof, not the rear glass. If even that is not
--     enough, a warning names the car (scale its body or hand-tune it).
-- Hand-tuned overrides saved on the template by BodyPrep: SeatDrop (seat top = greybox top - SeatDrop,
-- the old rule; turns the automatic recline off), SeatZ (driver/passenger Z) and SeatTilt (recline in
-- degrees). The same three fields on the car's Config.Vehicles entry count when the template has none (as
-- a number): the config keeps a copy of every template's values, so a re-prepared body, which loses its
-- attributes, keeps its fix; street cars' traffic bodies aren't prepared by BodyPrep, so theirs live only
-- there. The template wins when both are set. In Studio each car's fit is printed once, with every
-- override and where it came from, so every body can be checked (a template value the config lacks or has
-- differently gets a warning); the "head clips roof" warning is only for automatic fits (any override,
-- template or config, counts as hand-tuned). Both happen again when a car's overrides change (a template
-- attribute edited during a Studio Play session): the dealership builds every car at startup, so a
-- once-per-car print would never show the edit.
-- `minFloor` (optional, chassis space): the lowest the cabin floor can be. Street bodies reach down to the
-- road (their tyres are part of the body), so they pass the sill height instead.
local function fitSeats(model, chassis, cfg, template, centreY, minFloor)
	local W, H, L = cfg.Size.X, cfg.Size.Y, cfg.Size.Z
	local x, z = W / 2 - 2.1, L * 0.12 -- the greybox spot (driver at -x, passenger at +x)
	local greyTop = H / 2 - 1.1 -- greybox seat top (centre H/2 - 1.3, 0.4 thick)
	local oldTop = greyTop - OLD_SINK -- where mesh-body seats used to sit; never go higher than this
	local top = oldTop
	local tilt = 0 -- recline in radians (positive leans the seat's back towards the car's back, +Z)
	local reach = HEAD_ABOVE_SEAT + HAIR_ROOM
	local roofY, floorY -- roof and cabin floor heights on the chassis (nil: none / unknown)
	local kind, glassShare = "no body parts", 0
	local bodyLo, bodyHi = boundsOf(template, function(d)
		return d.Name == "Body"
	end)
	if not bodyLo then
		bodyLo, bodyHi = boundsOf(template, function(d)
			return d.Name ~= "Wheels"
		end)
	end
	if bodyLo then
		-- 0.155 of the body width keeps hands and elbows inside the doors; 1.1+ so the two seats never overlap.
		x = math.max(0.155 * (bodyHi.X - bodyLo.X), 1.1)
		local roof = (not cfg.OpenTop) and bodyHi.Y or nil
		kind = cfg.OpenTop and "open top, no glass" or "no glass"
		local glassLo, glassHi = boundsOf(template, function(d)
			return d.Name == "Windows"
		end)
		if glassLo then
			local glassLen = glassHi.Z - glassLo.Z
			glassShare = glassLen / math.max(bodyHi.Z - bodyLo.Z, 0.1)
			if roof then
				roof = glassHi.Y
			end
			if glassShare > OPEN_GLASS and not cfg.OpenTop then
				kind = "closed cabin"
				z = (glassLo.Z + glassHi.Z) / 2 - 0.06 * glassLen
			elseif glassShare <= OPEN_GLASS then
				kind = cfg.OpenTop and "open top, windscreen" or "windscreen only"
				z = math.max(z, glassHi.Z + 1.5)
			else
				-- An open top whose glass runs long (door glass counted too): keep the old spot.
				kind = "open top, long glass"
			end
		end
		-- Stay within the middle of the car whatever the glass looks like.
		z = math.max(bodyLo.Z * 0.6, math.min(z, bodyHi.Z * 0.6))
		floorY = centreY + bodyLo.Y + FLOOR_GAP
		if minFloor then
			floorY = math.max(floorY, minFloor)
		end
		if roof then
			roofY = centreY + roof
			top = math.min(top, roofY - reach)
		end
		-- Not below the floor, unless the floor is above the old spot: then the old spot (a deep body
		-- would otherwise lift the seat and push the head further out).
		top = math.max(top, math.min(oldTop, floorY))
		if kind == "closed cabin" and roofY then
			-- Head in the middle of the side windows, like a real driver, but only as high as a head
			-- (plus hair) can go under the roof with the seat leaned back all the way.
			local mid = centreY + (glassLo.Y + glassHi.Y) / 2
			local maxTop = roofY - reach * math.cos(math.rad(MAX_RECLINE))
			top = math.max(top, math.min(mid - HEAD_MID, maxTop))
		end
	end
	-- Hand-tuned overrides (see above): the template's attribute wins, else the Config.Vehicles copy. Only
	-- numbers count, so a mistyped attribute (e.g. a string) falls back to the config instead of hiding it.
	local source = {} -- key -> "template" / "config", for the Studio print
	local function override(key)
		local v = template:GetAttribute(key)
		if type(v) == "number" then
			source[key] = "template"
			return v
		end
		v = cfg[key]
		if type(v) == "number" then
			source[key] = "config"
			return v
		end
		return nil
	end
	local drop = override("SeatDrop")
	local seatZ = override("SeatZ")
	local seatTilt = override("SeatTilt")
	if drop then
		top = greyTop - drop
	end
	if seatTilt then
		tilt = math.rad(math.clamp(seatTilt, 0, 45))
	elseif roofY and not drop then
		-- Leaning back by `tilt` lowers the head top from `reach` to reach * cos(tilt) above the seat.
		local short = (top + reach) - roofY
		if short > 0 then
			tilt = math.acos(math.clamp((reach - short) / reach, math.cos(math.rad(MAX_RECLINE)), 1))
		end
	end
	if seatZ then
		z = seatZ
	else
		-- Leaning back swings the head sin(tilt) * reach towards the back; slide the seat forward by
		-- half of that so the head stays under the roof and not under the sloping rear glass.
		z -= math.sin(tilt) * reach * 0.5
	end
	-- Head (plus hair room) above the roof after all that: > 0 means it still pokes through.
	local clip = roofY and (top + reach * math.cos(tilt)) - roofY or nil
	-- Once per car and set of overrides (values and sources), e.g. "SolanaGT|nil nil|nil nil|40 template".
	local reportKey = string.format("%s|%s %s|%s %s|%s %s", cfg.Id, tostring(drop), tostring(source.SeatDrop),
		tostring(seatZ), tostring(source.SeatZ), tostring(seatTilt), tostring(source.SeatTilt))
	if not reported[reportKey] then
		reported[reportKey] = true
		-- Hand-tuned cars were checked by eye, so only warn about automatic fits. Any override counts, from the
		-- template or from the config alike (a config copy must behave exactly like the attribute it mirrors).
		local tuned = drop ~= nil or seatZ ~= nil or seatTilt ~= nil
		if clip and clip > 0.15 and not tuned then
			warn(string.format("[CarBuilder] %s head clips roof by %.2f studs (recline %.0f deg); scale the body or set SeatDrop / SeatZ / SeatTilt",
				cfg.Id, clip, math.deg(tilt)))
		end
		if RunService:IsStudio() then
			-- Each override with its value and where it came from. A template value the config lacks (or has
			-- differently) is listed too: a re-prepared body would lose it, so copy it to Config.Vehicles.
			local overrides, unsaved = "", {}
			for _, pair in ipairs({ { "SeatDrop", drop }, { "SeatZ", seatZ }, { "SeatTilt", seatTilt } }) do
				local key, v = pair[1], pair[2]
				if v then
					overrides ..= string.format(", %s %g (%s)", key, v, source[key])
					local copy = cfg[key]
					if source[key] == "template" and (type(copy) ~= "number" or math.abs(copy - v) > 0.001) then
						table.insert(unsaved, string.format("%s %g (config: %s)", key, v,
							type(copy) == "number" and string.format("%g", copy) or "none"))
					end
				end
			end
			print(string.format("[CarBuilder] seats %s: %s, glass %.0f%% of length, z %.2f, top %.2f (old %.2f, floor %s), recline %.0f deg, %s%s",
				cfg.Id, kind, glassShare * 100, z, top, oldTop, floorY and string.format("%.2f", floorY) or "-",
				math.deg(tilt), clip and string.format("head clip %.2f", clip) or "no roof", overrides))
			if #unsaved > 0 then
				warn(string.format("[CarBuilder] %s seat overrides on its body template differ from Config.Vehicles: %s; the template wins now, but copy them to the config or a re-prepared body loses them",
					cfg.Id, table.concat(unsaved, ", ")))
			end
		end
	end
	for _, pair in ipairs({ { "DriverSeat", -x }, { "PassengerSeat", x } }) do
		local seat = model:FindFirstChild(pair[1])
		if seat then
			local w = seat:FindFirstChildOfClass("WeldConstraint")
			if w then
				w.Enabled = false
			end
			-- A positive X angle tips the seat's up axis towards +Z (the back), so the rider leans back.
			seat.CFrame = chassis.CFrame * CFrame.new(pair[2], top - seat.Size.Y / 2, z) * CFrame.Angles(tilt, 0, 0)
			if w then
				w.Enabled = true
			end
		end
	end
end

-- Move the spinning visual wheels (and rims) into a mesh body's wheel arches: wheel centres at
-- (xc +- wx, y, zc +- wz) from the chassis centre, radius wr (xc, zc: where the four wheels' middle is,
-- default the chassis centre; a body's wheelbase is rarely centred in it). They're cosmetic: the
-- suspension rays stay at the chassis corners.
local function fitWheels(model, chassis, wx, wz, wr, y, xc, zc)
	xc, zc = xc or 0, zc or 0
	for _, w in ipairs(WHEELS) do
		local wheel = model:FindFirstChild("Wheel" .. w[1])
		local hub = wheel and wheel:FindFirstChild("Hub")
		if hub then
			local offset = Vector3.new(xc + w[2] * wx, y, zc + w[3] * wz)
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

-- Swap the greybox shell for a mesh body (see the header). `wheelY` is the wheels' rest height
-- relative to the chassis centre.
local function attachBody(model, chassis, cfg, template, wheelY)
	local body = template:Clone()
	-- Bigger (or smaller) mesh wheels than the physics wheel radius: lift everything so the tyres
	-- still touch the road at rest.
	local wx, wz, wr = template:GetAttribute("WheelX"), template:GetAttribute("WheelZ"), template:GetAttribute("WheelRadius")
	local centreY = wheelY + (wr and (wr - cfg.WheelRadius) or 0)
	body:PivotTo(chassis.CFrame * CFrame.new(0, centreY, 0))
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.CastShadow = true
			if d.Name == "Body" then
				d:SetAttribute("BodyPaint", true)
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
				d.Material = Enum.Material.SmoothPlastic
				d.Color = cfg.Color
				d.Reflectance = 0.15 -- glossy paint: the sky and the street lights slide over it (Look 4.0)
			elseif d.Name == "Wheels" then
				d.Transparency = 1
				d.CastShadow = false
			elseif d.Name == "Headlight" then
				d.Material = Enum.Material.Neon
				d.Color = Color3.fromRGB(255, 244, 210)
			elseif d.Name == "Windows" and not cfg.OpenTop then
				-- Dark tinted glass on every closed car: looks real and hides anyone's elbows in the cabin.
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
				d.Material = Enum.Material.Glass
				d.Color = Color3.fromRGB(26, 32, 44)
				d.Reflectance = 0.12
				d.Transparency = 0.18
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
	for _, name in ipairs({ "Cabin", "Roof", "Headlight", "Taillight" }) do
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == name and d:IsA("Part") then
				d.Transparency = 1
			end
		end
	end
	chassis.Transparency = 1
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
	-- The spinning visual wheels (and rims) go into the mesh's wheel arches.
	if wx and wz and wr then
		fitWheels(model, chassis, wx, wz, wr, centreY)
	end
	-- Seats into the body's cabin, heads under its roof (see fitSeats).
	fitSeats(model, chassis, cfg, template, centreY)
end

------------------------------------------------------------------ street cars (traffic bodies)

local function isWheelPart(d)
	return string.find(string.lower(d.Name), "wheel") ~= nil
end

local function allParts()
	return true
end

-- The body for a street car (Config.Vehicles TrafficModel): `given` (a ready copy, e.g. a parked car,
-- colours kept) or a fresh ReplicatedStorage.TrafficModels clone. Re-pivoted to the bottom centre of its
-- box, so it lines up with the chassis whatever the model's own pivot. Kept at its traffic size (only a
-- wildly off body is scaled to the config length). Returns { body, size = the chassis size that fits it }
-- or nil when there's no body (the car stays a greybox of the config size).
local function trafficBody(cfg, given)
	local body = given
	if not body then
		local models = ReplicatedStorage:FindFirstChild("TrafficModels")
		local template = models and models:FindFirstChild(cfg.TrafficModel)
		if not template then
			return nil
		end
		body = template:Clone()
	end
	local lo, hi = boundsOf(body, allParts)
	if not lo then
		body:Destroy()
		return nil
	end
	local len = hi.Z - lo.Z
	if len < 8 or len > 24 then
		body:ScaleTo(body:GetScale() * (cfg.Size.Z + 1) / math.max(len, 0.1))
		lo, hi = boundsOf(body, allParts)
	end
	body.WorldPivot = body:GetPivot() * CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local ext = hi - lo
	-- The collision box sits a little inside the body's outline (mirrors and bumpers stick out).
	local size = Vector3.new(math.clamp(ext.X - 0.6, 4.5, 9), cfg.Size.Y, math.clamp(ext.Z - 1.2, 8, 20))
	return { body = body, size = size }
end

-- Put a street car's traffic body on the chassis (see the header). `wheelY` is the wheels' rest height
-- relative to the chassis centre; the road is a wheel radius below that. `paint`: colour the parts the
-- traffic cars colour (attribute BodyPaint, as TrafficClient does), or keep the body's own colours.
local function attachTrafficBody(model, chassis, cfg, street, wheelY, paint)
	local body = street.body
	local groundY = wheelY - cfg.WheelRadius
	body:PivotTo(chassis.CFrame * CFrame.new(0, groundY, 0))
	-- The greybox shell and its underglow go (hidden before the body's own lights arrive, whatever
	-- their names).
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("Part") and (d.Name == "Cabin" or d.Name == "Roof" or d.Name == "Headlight" or d.Name == "Taillight"
			or d.Name == "Underglow") then
			d.Transparency = 1
		end
	end
	chassis.Transparency = 1
	-- A separate wheel part: measured like BodyPrep does (its box spans all four tyres), then hidden so
	-- our spinning wheels can take its place.
	local wlo, whi = boundsOf(body, isWheelPart)
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then
			d:Destroy() -- a copied model never brings scripts or prompts along
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			if paint and d:GetAttribute("BodyPaint") then
				d.Color = cfg.Color
			end
			if wlo and isWheelPart(d) then
				d.Transparency = 1
				d.CastShadow = false
			end
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = d
		end
	end
	if wlo then
		local w, h, len = whi.X - wlo.X, whi.Y - wlo.Y, whi.Z - wlo.Z
		local wr = h / 2
		-- Around the wheel box's own middle (the body box's middle is the chassis centre).
		fitWheels(model, chassis, w / 2 - math.min(wr * 0.45, w * 0.1), len / 2 - wr, wr, groundY + (wlo.Y + whi.Y) / 2,
			(wlo.X + whi.X) / 2, (wlo.Z + whi.Z) / 2)
	else
		-- Wheels baked into the body mesh: they stay put, and our own would poke through them.
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") and (d.Name == "Rim" or string.match(d.Name, "^Wheel%u%u$")) then
				d.Transparency = 1
				d.CastShadow = false
			end
		end
	end
	-- Seats into the cabin (Windows glass when the body has it, else under the roof; see fitSeats). The body
	-- reaches down to the road (its tyres), so the cabin floor is taken at sill height, a wheel radius up.
	fitSeats(model, chassis, cfg, body, groundY, groundY + cfg.WheelRadius + FLOOR_GAP)
	for _, d in ipairs(body:GetChildren()) do
		d.Parent = model
	end
	body:Destroy()
end

-- Boats: a textured hull mesh (pivot at the bottom centre, front -Z). It hangs below the chassis so the
-- hull sits in the water while the water rays hold the chassis up. Keeps its own colours.
local function attachBoatBody(model, chassis, cfg, template)
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
	for _, name in ipairs({ "Cabin", "Roof", "Headlight", "Taillight", "Underglow" }) do
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == name and d:IsA("Part") then
				d.Transparency = 1
			end
		end
	end
	chassis.Transparency = 1
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
	for _, name in ipairs({ "Vehicles", "Traffic", "Ghost" }) do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable("Vehicles", "Traffic", false)
	-- "Ghost": a car you just drove into, briefly, on your own device only (ImpactClient). It lets your
	-- car and walkers pass, but still stands on the road and against walls.
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Vehicles", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Traffic", false)
end

------------------------------------------------------------------ body joint and door spots

local DOOR_OUT = 1.9 -- studs from the body's side to where someone stands to open a door
local DOOR_FORWARD = 0.6 -- ...and this far ahead of the seat's middle (the door opening, not the seat back)
local STAND_HEIGHT = 3 -- a standing character's root part above the road (R15: hip height 2 + half the root)
local BAKED_LEAN = 0.45 -- share of the body lean for a body with its tyres baked in (they would dip into the road)

-- Half the width of what you see of a car, in the chassis' frame: never under the chassis' own half
-- width, and never trusted past 1.5 x it (in case something odd is welded on).
local function visibleHalfWidth(model, chassis)
	local frame = chassis.CFrame
	local half = chassis.Size.X / 2
	local reach = half
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf = frame:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			reach = math.max(reach, math.abs(cf.Position.X) + math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y
				+ math.abs(cf.ZVector.X) * h.Z)
		end
	end
	return math.min(reach, half * 1.5)
end

-- An Attachment on the chassis at `pos` (chassis space), looking along `toward`. Made once, moved after.
local function doorSpot(chassis, name, pos, toward)
	local att = chassis:FindFirstChild(name)
	if not (att and att:IsA("Attachment")) then
		att = Instance.new("Attachment")
		att.Name = name
		att.CFrame = CFrame.lookAt(pos, pos + toward)
		att.Parent = chassis
	else
		att.CFrame = CFrame.lookAt(pos, pos + toward)
	end
	return att
end

-- Is this part only there to be looked at (so it may lean with the body)? Seats carry people and anything
-- that collides holds the car up (the bump stops): those stay rigid on the chassis.
local function leansWithBody(p)
	return p ~= nil and p:IsA("BasePart") and not p:IsA("Seat") and not p:IsA("VehicleSeat") and not p.CanCollide
end

-- Give a land car its body joint and door spots (see the header). Safe to call on a car that already has
-- them (a second call only re-places the door spots and moves any visual weld still on the chassis), on a
-- fresh Build and on a clone of an older template alike. Call it before the car is parented and after
-- anything that welds more body parts on. Returns BodyRoot, or nil for boats and broken models.
function CarBuilder.AddBodyJoint(model)
	local chassis = model and model.PrimaryPart
	if not chassis or model:GetAttribute("Boat") == true then
		return nil
	end
	local ride = model:GetAttribute("RideHeight")
	if type(ride) ~= "number" then
		ride = chassis.Size.Y / 2 + 1.6 -- (a model from before RideHeight: about right for every car)
	end

	-- Door spots: beside the driver's seat on the left, mirrored on the right.
	local seat = model:FindFirstChild("DriverSeat")
	if seat and seat:IsA("BasePart") then
		local x = visibleHalfWidth(model, chassis) + DOOR_OUT
		local y = -ride + STAND_HEIGHT
		local z = chassis.CFrame:PointToObjectSpace(seat.Position).Z - DOOR_FORWARD
		doorSpot(chassis, "DriverDoor", Vector3.new(-x, y, z), Vector3.xAxis)
		doorSpot(chassis, "PassengerDoor", Vector3.new(x, y, z), -Vector3.xAxis)
	end

	local root = model:FindFirstChild("BodyRoot")
	if not (root and root:IsA("BasePart")) then
		root = Instance.new("Part")
		root.Name = "BodyRoot"
		root.Size = Vector3.new(1, 1, 1)
		root.Transparency = 1
		root.Anchored = false
		root.Massless = true
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
		root.CastShadow = false
		root.CollisionGroup = chassis.CollisionGroup
		root.CFrame = chassis.CFrame
		root.Parent = model
	end
	-- Our own wheels hidden = the tyres are part of the body mesh (some street bodies): lean less, about
	-- the road, so they don't sink into it. Otherwise the body rolls about its axles.
	local wheel = model:FindFirstChild("WheelFL")
	local baked = wheel ~= nil and wheel:IsA("BasePart") and wheel.Transparency >= 1
	local radius = model:GetAttribute("WheelRadius")
	local pivot = CFrame.new(0, -ride + ((not baked and type(radius) == "number") and radius or 0), 0)
	local joint = root:FindFirstChild("BodyJoint")
	if not (joint and joint:IsA("Motor6D")) then
		joint = Instance.new("Motor6D")
		joint.Name = "BodyJoint"
		joint.Part0 = chassis
		joint.Part1 = root
		joint.C0 = pivot
		joint.C1 = pivot
		joint.Parent = root
	else
		joint.C0 = pivot
		joint.C1 = pivot
	end
	model:SetAttribute("BodyLean", baked and BAKED_LEAN or 1)

	-- Every visual part hanging on the chassis now hangs on BodyRoot. BodyRoot sits exactly on the chassis,
	-- so nothing moves; the weld is switched off and on around the change so it keeps the parts where
	-- they are (the same trick fitSeats uses).
	for _, d in ipairs(model:GetDescendants()) do
		local isWeld = d:IsA("WeldConstraint") or (d:IsA("JointInstance") and not d:IsA("Motor6D"))
		if isWeld and d.Part0 == chassis and d.Part1 ~= root and leansWithBody(d.Part1) then
			local was = d.Enabled
			d.Enabled = false
			d.Part0 = root
			d.Enabled = was
		end
	end
	return root
end

-- opts (optional): Paint = Color3 (instead of the config colour), Body = Model (street cars: wear this
-- copy, e.g. a parked car with its own colours, instead of a fresh TrafficModels clone; it's used up).
function CarBuilder.Build(id, opts)
	opts = opts or {}
	local cfg = Vehicles.Resolve(id)
	assert(cfg, "Unknown vehicle " .. tostring(id))
	if typeof(opts.Paint) == "Color3" then
		cfg.Color = opts.Paint
	end
	-- Street cars keep their traffic body's size: the chassis (and everything below) is fitted to it.
	local street = cfg.TrafficModel and trafficBody(cfg, opts.Body)
	if street then
		cfg.Size = street.size
	elseif opts.Body then
		opts.Body:Destroy()
	end
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
	if street then
		-- Street bodies are short (10-12 studs): the usual inset leaves a tiny wheelbase that tips over
		-- when braking or cornering. Put the wheel rays near the body's corners (their tyres are baked
		-- into the mesh, so nothing visible moves).
		wx, wz = W / 2 - 0.3, L / 2 - 1.4
	end
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

	-- Driver seat on the left, sunk into the body so the driver sits inside the cabin (a mesh body
	-- moves both seats again to fit its cabin: fitSeats).
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2.2)
	seat.CFrame = cfg.Boat and CFrame.new(0, H / 2 + 0.2, L * 0.1) or CFrame.new(-W / 2 + 2.1, H / 2 - 1.3, L * 0.12)
	seat.Color = Color3.fromRGB(30, 30, 36)
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
	for _, k in ipairs(CarBuilder.TuningKeys) do
		model:SetAttribute(k, cfg[k])
	end
	-- Chassis centre to the road at rest: wheel centres sit 60% of the travel below the ray origins.
	model:SetAttribute("RideHeight", -(wy - cfg.RestLength * 0.6 - cfg.WheelRadius))
	local bodies = ServerStorage:FindFirstChild("CarBodies")
	local template = bodies and bodies:FindFirstChild(id)
	if street then
		attachTrafficBody(model, chassis, cfg, street, wy - cfg.RestLength * 0.6, opts.Body == nil)
	elseif template and cfg.Boat then
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
	-- Last, once every body part is welded on: the body joint and the door spots (land cars). It's only
	-- looks, so a failure there must never cost anyone their car.
	local okJoint, errJoint = pcall(CarBuilder.AddBodyJoint, model)
	if not okJoint then
		warn("[CarBuilder] " .. tostring(id) .. " body joint: " .. tostring(errJoint))
	end
	return model
end

return CarBuilder
