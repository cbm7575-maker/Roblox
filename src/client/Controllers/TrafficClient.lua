-- TrafficClient (ModuleScript, StarterPlayerScripts.Controllers.TrafficClient)
-- Ambient traffic, simulated on each player's own device (it costs the server nothing):
--   * Up to MAX_CARS cars in street paint (mostly whites, silvers, blacks) drive the RoadGraph around the camera, keeping right, two lanes
--     each way on Highway 1. They slow for corners and for the car ahead, and stop for anyone in
--     their lane (players, and PedClient's walkers on the crossings): they look far enough ahead to
--     stop from their speed (highway cars too) and brake along a steady stopping curve, ending 8 studs
--     short of a person, or 4 short of you on foot (close enough to JACK it).
--   * They obey the traffic signals (the shared cycle in Util.Signals): on red, or on amber when
--     there's room, they stop before the crosswalk. A car that can't stop in time carries on, so
--     nobody waits inside a junction and every queue clears on the next green.
--   * They steer around the stunt ramps (Config.Activities.Stunts) that sit in some lanes, and around an
--     empty car left standing in their lane (yours, a hot car at the roadside): they pull out past it
--     where the road has room, and wait behind it where it hasn't (parkedAhead).
--   * They're anchored and in collision group "Traffic", which doesn't collide with "Vehicles"
--     (players' cars), so a player's car never hits an immovable wall: when any car ploughs into one
--     above RAM_SPEED it gets knocked flying (unanchored, local physics) and fades away. Your own car
--     loses a little speed.
--   * A traffic car that clips YOU on foot at speed knocks you over (ImpactClient: you tip over, see
--     stars and get up after ~2.5 s, no damage). Only on this device, like the traffic itself.
--   * Cars far from the camera are recycled into fresh spots out of sight.
--   * Lights (parts named Headlight / Taillight): headlights glow at night and in rain; taillights glow
--     dim red then, and bright red whenever the car brakes or stands waiting (day or night). No real
--     light sources here: VehicleFeel gives those to the players' cars only.
--   * A braking car dips its nose a little and squats pulling away (drawn only: car.cf stays level).
--   * Carjacking (CarjackService): a slow car (under JACK_SPEED) waits while you stand on foot at its
--     driver's side (the road side, not the kerb side), so you can walk up to the door.
--       TrafficClient.FindJackable(pos, doorRange, boxRange) finds the car InteractClient offers to JACK.
--       TrafficClient.Jack(car) stops it dead and returns { Kind, CFrame, Color } for RequestCarjack.
--       TrafficClient.JackSpots(car) -> origin (world CFrame of the car's pivot, on the road), then three
--         CFrames in that frame: where to stand at the driver's door and at the passenger's door (both
--         looking at the car) and where the driver sits; then half the body's length (a number: the
--         body is no wall on this device, so InteractClient needs it to walk you round the car and not
--         through it). InteractClient walks you there and hops you in.
--       TrafficClient.PullDriver(car, thiefPosition) -> bool: the driver comes out. Kid-friendly: they
--         stumble out of the driver's door a few steps (away from where you stand), a small "HEY!" bubble
--         over their head, then run off and fade away: to the nearer pavement (straight across the road,
--         or round the end of their car to the kerb behind it) and along it, never down the middle of
--         the road; traffic stops for them as it does for any walker. The driver is one of PedService's
--         looks, made and moved here; at most MAX_DRIVERS at once. The car's wait for the server starts
--         over from here.
--       TrafficClient.Release(car): the jack was called off before it was asked for: the car drives on.
--       TrafficClient.IsHeld(car) -> bool: still stopped and waiting for a jack to finish?
--     When the server's "Carjacked" says the real car is there, the traffic car vanishes (and if nobody
--     pulled the driver out yet, a door slams and they come out then); "CarjackRefused" (or nothing
--     within HOLD_TIMEOUT) lets it drive on.
-- If ReplicatedStorage.TrafficModels has models (pivot at the bottom centre, front facing -Z), bodies
-- are cloned from those (the model's name is the car's kind); otherwise simple greybox cars are built here.
-- ReplicatedStorage.TrafficVariants (Look 4.0) holds the same three bodies re-textured in street paint
-- (white, silver, black, navy, red, grey): each has attributes Kind (the TrafficModels name it stands for,
-- so jacking one works exactly like the original) and Paint (the colour reported with a jack). A car is
-- picked from both folders alike, so most of the traffic wears real street colours.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Signals = require(ReplicatedStorage.Shared.Util.Signals)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local TrafficClient = {}

local MAX_CARS = 22 -- (Look 4.0: busier streets; performance mode keeps 6)
local SPAWN_MIN, SPAWN_MAX = 160, 380 -- studs from the camera focus
local DESPAWN = 480
local STREET_SPEED, HIGHWAY_SPEED = 42, 68 -- studs/s
local RAM_SPEED = 25
local KNOCK_SPEED = 15 -- a traffic car at least this fast knocks you over if it clips you
local ROAD_TOP = 0.1
local MAX_BRAKE = 40 -- studs/s^2: the hardest a traffic car brakes (see step)
local SIGNAL_BRAKE = 30 -- studs/s^2: the gentler stop used for signals (under MAX_BRAKE, so it's always met)
local STOP_BRAKE = 34 -- studs/s^2: the stopping curve for obstacles ahead (under MAX_BRAKE, so it's always met)
local LOOK_AHEAD = 26 -- studs past the front bumper a person is always seen from (more at speed)
local STOP_GAP = 8 -- studs a car stops short of a person...
local MY_STOP_GAP = 4 -- ...or of you on foot (then its bumper is within InteractClient's JACK range)
local RAMP_HALF_W, RAMP_HALF_L = 8, 10 -- CityGen's stunt wedges are 16 wide, 20 long
local JACK_SPEED = 25 -- studs/s: slower than this, a car can be jacked (and waits for someone at its side)
local JACK_REACH = 16 -- studs from you to the car's pivot (CarjackService allows 20, for lag)
local BESIDE = 3.5 -- studs from a car's side that count as standing at its door
local HOLD_TIMEOUT = 4 -- seconds a car being jacked waits (for you to reach its door, then for the server) before driving on
local JACK_KINDS = { Hatchback = true, Sedan = true, Pickup = true } -- the kinds CarjackService turns into street cars
local BRAKE_DECEL = 6 -- studs/s^2: losing speed faster than this shows the brake lights
local BRAKE_HOLD = 0.3 -- seconds the brake lights stay on after that (no flicker)
local PITCH_PER_ACCEL = 0.0007 -- radians of nose dip per stud/s^2 of braking (and of squat pulling away)
local PITCH_DIVE, PITCH_SQUAT = 0.022, 0.012 -- radians at most (the tyres are part of the body: keep it small)
-- The driver who is pulled out of a jacked car (see PullDriver).
local MAX_DRIVERS = 3
local STAND_HEIGHT = 3 -- a standing walker's root part above the road
local SEAT_HEIGHT = 3 -- a seated driver's root part above the road, roughly (the server's seat has the last word)
local DOOR_OUT = 1.9 -- studs from the body's side to where someone stands to open a door (as CarBuilder)
local STUMBLE_TIME = 0.65 -- seconds the driver staggers out before they find their feet
local STUMBLE_ALONG = 4.2 -- studs along the car they end up, away from the thief
local FLEE_TIME = 4 -- seconds they then run before fading away
local FLEE_FADE = 0.5
local FLEE_SPEED = 20
local FLEE_LEG = 1.5 -- seconds at most on one stretch of their way before they turn for the next
local KERB_IN = 4 -- studs past the road's edge: where they run, on the pavement
local RUN_ANIM = "rbxassetid://507767714" -- Roblox's default R15 run (Config.Animations' "Default" set, if it's there)

-- Street paint, picked evenly from this list (repeats = how common: Look 4.0 swapped the all-pastel
-- traffic for a real street's mix): mostly white, silver, grey and black, then deep blues and reds, with a
-- few coastal pastels (turquoise, coral, pink) so it still feels like the beach city.
local PASTELS = {
	Color3.fromRGB(236, 236, 240), Color3.fromRGB(236, 236, 240), Color3.fromRGB(226, 228, 232), -- whites
	Color3.fromRGB(176, 180, 186), Color3.fromRGB(150, 154, 160), Color3.fromRGB(176, 180, 186), -- silvers
	Color3.fromRGB(96, 100, 108), Color3.fromRGB(74, 78, 86), -- greys
	Color3.fromRGB(28, 28, 32), Color3.fromRGB(36, 36, 42), Color3.fromRGB(28, 28, 32), -- blacks
	Color3.fromRGB(30, 54, 110), Color3.fromRGB(46, 84, 150), -- blues
	Color3.fromRGB(150, 24, 34), Color3.fromRGB(190, 40, 46), -- reds
	Color3.fromRGB(40, 72, 56), Color3.fromRGB(196, 176, 140), -- dark green, beige
	Color3.fromRGB(110, 210, 196), Color3.fromRGB(255, 150, 130), Color3.fromRGB(255, 180, 210), -- coastal pastels
}

local folder
local cars = {} -- list of car records
local ready = false
local night = false
local raining = false
local signalNodes = {} -- [road node] = true: junctions with traffic signals (seen as they stream in)
local NO_WALKERS = {}
local drivers = {} -- oldest first: drivers pulled out of jacked cars (see PullDriver)
local runAnim -- the run cycle those drivers use (made in Init)

------------------------------------------------------------------ car bodies

local function newPart(name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false -- traffic stops for people instead; nothing can bump into it and get jolted
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.CollisionGroup = "Traffic"
	if shape then
		p.Shape = shape
	end
	return p
end

-- Returns model, list of { part, offset CFrame } for BulkMoveTo, half-size (Vector3), kind (the
-- TrafficModels name; "Sedan" for a greybox car) and paint colour.
local function buildCar()
	local W, H, L = 6.6, 1.8, 13
	local model = Instance.new("Model")
	model.Name = "TrafficCar"
	local color = PASTELS[math.random(#PASTELS)]
	local kind = "Sedan"
	local parts = {}
	local function add(part, offset)
		part.Parent = model
		table.insert(parts, { part = part, offset = offset })
		return part
	end
	local templates = ReplicatedStorage:FindFirstChild("TrafficModels")
	local list = templates and templates:GetChildren() or {}
	local variants = #list > 0 and ReplicatedStorage:FindFirstChild("TrafficVariants")
	for _, v in ipairs(variants and variants:GetChildren() or {}) do
		if v:IsA("Model") and type(v:GetAttribute("Kind")) == "string" then
			table.insert(list, v)
		end
	end
	if #list > 0 then
		local template = list[math.random(#list)]
		kind = template:GetAttribute("Kind") or template.Name
		local paint = template:GetAttribute("Paint")
		if typeof(paint) == "Color3" then
			color = paint
		end
		local body = template:Clone()
		local _, ext = body:GetBoundingBox()
		W, H, L = ext.X, ext.Y * 0.45, ext.Z
		local pivot = body:GetPivot()
		for _, d in ipairs(body:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.CollisionGroup = "Traffic"
				if d:GetAttribute("BodyPaint") then
					d.Color = color
					d.Reflectance = 0.15 -- glossy paint, like the players' cars (CarBuilder)
				end
				local rel = pivot:ToObjectSpace(d.CFrame)
				d.Parent = model
				table.insert(parts, { part = d, offset = rel })
			end
		end
		body:Destroy()
	else
		add(newPart("Body", Vector3.new(W, H, L), color), CFrame.new(0, H / 2 + 1.1, 0))
		add(newPart("Cabin", Vector3.new(W - 1.2, 2.2, L * 0.45), Color3.fromRGB(40, 50, 70), Enum.Material.Glass),
			CFrame.new(0, H + 1.1 + 1.1, L * 0.05)).Transparency = 0.3
		add(newPart("Roof", Vector3.new(W - 1.3, 0.25, L * 0.4), color), CFrame.new(0, H + 1.1 + 2.3, L * 0.05))
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				add(newPart("Wheel", Vector3.new(1, 2.4, 2.4), Color3.fromRGB(28, 28, 32), nil, Enum.PartType.Cylinder),
					CFrame.new(sx * (W / 2 - 0.3), 1.2, sz * (L / 2 - 2.4)))
			end
			add(newPart("Headlight", Vector3.new(1.3, 0.5, 0.2), Color3.fromRGB(255, 250, 220), Enum.Material.SmoothPlastic),
				CFrame.new(sx * (W / 2 - 1.1), H / 2 + 1.2, -L / 2 - 0.05))
			-- (unlit red plastic by day; setLights makes it glow at night and when the car brakes)
			add(newPart("Taillight", Vector3.new(1.3, 0.5, 0.2), Color3.fromRGB(150, 24, 34), Enum.Material.SmoothPlastic),
				CFrame.new(sx * (W / 2 - 1.1), H / 2 + 1.2, L / 2 + 0.05))
		end
	end
	model.Parent = folder
	return model, parts, Vector3.new(W / 2, H, L / 2), kind, color
end

local WARM = Color3.fromRGB(255, 244, 210)
local TAIL_DIM = Color3.fromRGB(135, 16, 26) -- running lights at night: a faint red glow
local TAIL_BRAKE = Color3.fromRGB(255, 30, 42)

-- A car's lamps, found once: lists of { part, color, material } (the look the body came with).
local function findLamps(car)
	local heads, tails = {}, {}
	for _, rec in ipairs(car.parts) do
		local part = rec.part
		if part.Name == "Headlight" then
			table.insert(heads, { part = part, color = part.Color, material = part.Material })
		elseif part.Name == "Taillight" then
			table.insert(tails, { part = part, color = part.Color, material = part.Material })
		end
	end
	car.heads, car.tails = heads, tails
end

-- Headlights on in the dark (night or rain); taillights dim then, bright while braking, else as built.
-- Only called when one of those changes, never every frame.
local function setLights(car)
	if not car.heads then
		findLamps(car)
	end
	local dark = night or raining
	for _, lamp in ipairs(car.heads) do
		lamp.part.Material = dark and Enum.Material.Neon or lamp.material
		lamp.part.Color = dark and WARM or lamp.color
	end
	local braking = car.brakeOn == true
	for _, lamp in ipairs(car.tails) do
		if braking then
			lamp.part.Material = Enum.Material.Neon
			lamp.part.Color = TAIL_BRAKE
		elseif dark then
			lamp.part.Material = Enum.Material.Neon
			lamp.part.Color = TAIL_DIM
		else
			lamp.part.Material = lamp.material
			lamp.part.Color = lamp.color
		end
	end
end

------------------------------------------------------------------ driving on the graph

local function neighbours(i)
	local list = {}
	for j in pairs(RoadGraph.Edges[i] or {}) do
		table.insert(list, j)
	end
	return list
end

local function degree(i)
	local n = 0
	for _ in pairs(RoadGraph.Edges[i] or {}) do
		n += 1
	end
	return n
end

-- Lateral offset from the road centre (to the right of travel) for a lane.
local function laneOffset(width, lane)
	if width >= 50 then
		return lane == 2 and width * 0.36 or width * 0.13
	end
	return width * 0.24
end

local function edgeInfo(a, b)
	local na, nb = RoadGraph.Nodes[a], RoadGraph.Nodes[b]
	local dir = nb - na
	local len = dir.Magnitude
	dir = len > 0 and dir / len or Vector3.new(0, 0, 1)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	return na, nb, dir, right, len
end

local function lanePos(car, t)
	local na, _, dir, right = edgeInfo(car.a, car.b)
	local off = car.off
	local dodge = car.dodge
	if dodge and t > dodge.t0 and t < dodge.t1 then
		off = dodge.off -- steering round a stunt ramp
	end
	-- Round an empty car left in the lane (parkedAhead): eased out and back over park.run studs of road,
	-- not on the spot, so a car setting off beside it never slides sideways.
	local park = car.park
	if park then
		local k = math.min((t - park.t0) / park.run, (park.t1 - t) / park.run, 1)
		if k > 0 then
			off += (park.off - off) * k
		end
	end
	return na + dir * t + right * off
end

-- A stunt ramp in this lane of a->b? Returns { t0, t1, off }: from t0 to t1 along the edge the car
-- drives at lateral offset `off` instead, the nearest spot beside the ramp that stays on the road.
local function rampDodge(a, b, width, off, halfW)
	local na, _, dir, right, len = edgeInfo(a, b)
	for _, st in ipairs(Activities.Stunts) do
		local rel = Vector3.new(st.Ramp.X - na.X, 0, st.Ramp.Z - na.Z)
		local along, lat = rel:Dot(dir), rel:Dot(right)
		-- Half the ramp's footprint along and across this edge.
		local tr = Vector3.new(st.Travel.X, 0, st.Travel.Z).Unit
		local side = Vector3.new(-tr.Z, 0, tr.X)
		local hAlong = math.abs(tr:Dot(dir)) * RAMP_HALF_L + math.abs(side:Dot(dir)) * RAMP_HALF_W
		local hLat = math.abs(tr:Dot(right)) * RAMP_HALF_L + math.abs(side:Dot(right)) * RAMP_HALF_W
		if along > -hAlong and along < len + hAlong and math.abs(lat - off) < hLat + halfW + 0.5 then
			local limit = width / 2 - halfW
			local rightOff = lat + hLat + halfW + 1
			local leftOff = lat - hLat - halfW - 1
			local useRight = rightOff <= limit and (leftOff < -limit or math.abs(rightOff - off) <= math.abs(leftOff - off))
			-- Start moving over 25 studs early (the lane blend in step() takes a moment).
			return { t0 = along - hAlong - 25, t1 = along + hAlong + 6, off = useRight and rightOff or leftOff }
		end
	end
	return nil
end

local function enterEdge(car, a, b, t)
	car.a, car.b, car.t = a, b, t or 0
	local width = RoadGraph.Width(a, b)
	if width < 50 then
		car.lane = 1
	elseif not car.lane then
		car.lane = math.random(2)
	end
	car.off = laneOffset(width, car.lane)
	local _, _, _, _, len = edgeInfo(a, b)
	car.len = len
	car.cruise = (width >= 50 and HIGHWAY_SPEED or STREET_SPEED) * (0.85 + math.random() * 0.3)
	-- Choose the next edge now, so we know how hard the turn at the end is.
	local options = {}
	local widest = width
	for _, j in ipairs(neighbours(b)) do
		widest = math.max(widest, RoadGraph.Width(b, j))
		if j ~= a then
			table.insert(options, j)
		end
	end
	car.nextB = #options > 0 and options[math.random(#options)] or a
	local _, _, d1 = edgeInfo(a, b)
	local _, _, d2 = edgeInfo(b, car.nextB)
	car.turnDot = d1:Dot(d2) -- 1 straight, 0 right angle, -1 U-turn
	-- Signal stop line: Restyle lays each crosswalk 1-7 studs beyond the junction box (widest road / 2).
	car.stopLine = widest / 2 + 9
	car.axis = Signals.AxisOf(d1)
	car.dodge = rampDodge(a, b, width, car.off, car.half.X)
	-- Empty cars in the lane were measured along the old edge: look again on this one (see step).
	car.park, car.stopT, car.parkAt = nil, nil, nil
end

local function focus()
	local cam = Workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or cam.Focus.Position
end

local function spawnCar()
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	local look = Workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0 and look.Unit or Vector3.new(0, 0, -1)
	local nodes = RoadGraph.Nodes
	for _ = 1, 12 do
		local i = math.random(#nodes)
		local toNode = nodes[i] - flat
		local d = toNode.Magnitude
		-- Don't pop cars in right in front of the camera.
		local inView = d < 300 and toNode.Unit:Dot(look) > 0.4
		if d > SPAWN_MIN and d < SPAWN_MAX and not inView then
			local nb = neighbours(i)
			if #nb > 0 then
				local j = nb[math.random(#nb)]
				-- The car starts part-way along the edge, so that spot must be in range and out of view
				-- too, not only the node: cars used to pop in standing still on the road ahead of you
				-- (sometimes on top of your car, a crash you couldn't avoid).
				local na, _, dir, _, len = edgeInfo(i, j)
				local t = math.random() * len * 0.6
				local toSpot = na + dir * t - flat
				local ds = toSpot.Magnitude
				local spotInView = ds < 300 and toSpot.Unit:Dot(look) > 0.4
				if ds > SPAWN_MIN and ds < SPAWN_MAX and not spotInView then
					local model, parts, half, kind, color = buildCar()
					local car = { model = model, parts = parts, half = half, kind = kind, color = color, speed = 0 }
					enterEdge(car, i, j, 0)
					car.t = t
					car.pos = lanePos(car, car.t)
					car.heading = dir
					setLights(car)
					table.insert(cars, car)
					return
				end
			end
		end
	end
end

local function removeCar(index)
	local car = cars[index]
	car.model:Destroy()
	table.remove(cars, index)
end

-- A person (player or walker) in a box ahead of this car? The box reaches at least LOOK_AHEAD studs past
-- the bumper, and at speed far enough to stop along the STOP_BRAKE curve (a highway car at 78 studs/s
-- sees about 100 studs ahead). Returns how far the car may still drive (`gap` studs short of them), or nil.
local function personAhead(car, cf, pos, gap)
	local rel = cf:PointToObjectSpace(pos)
	local ahead = math.max(LOOK_AHEAD, car.speed * car.speed / (2 * STOP_BRAKE) + gap + 6)
	if rel.Z < -car.half.Z and rel.Z > -car.half.Z - ahead and math.abs(rel.X) < car.half.X + 3 and math.abs(rel.Y) < 12 then
		return -rel.Z - car.half.Z - gap
	end
	-- Pulling out round an empty car (parkedAhead) the nose swings off the road's line, and the box above
	-- swings with it: the car lost sight of you standing at your own car's door, or in the lane just past
	-- it, and knocked you over where it used to stop. So while it has an empty car to pass it also looks
	-- straight along the road: across its lane and, as far as the pass goes, the line it takes round the car.
	local park = car.park
	if park then
		local na, _, dir, right = edgeInfo(car.a, car.b)
		local dx, dz = pos.X - na.X, pos.Z - na.Z
		local s = dx * dir.X + dz * dir.Z -- how far along the edge they stand
		local lat = dx * right.X + dz * right.Z
		local lo, hi = car.off, car.off
		if s < park.t1 + car.half.Z then
			lo, hi = math.min(lo, park.off), math.max(hi, park.off)
		end
		local along = s - car.t
		if s > park.t0 and along > car.half.Z and along < car.half.Z + ahead
			and lat > lo - car.half.X - 3 and lat < hi + car.half.X + 3 and math.abs(rel.Y) < 12 then
			return along - car.half.Z - gap
		end
	end
	return nil
end

-- You (on foot, `root`) standing right at this car's driver's side (-X, the road side with keep-right
-- lanes), from bumper to bumper? A slow car then waits, so you can walk round from its front to the
-- driver's door and jack it. Someone on the kerb side (the pavement) never holds it up.
local function besideMe(car, cf, root)
	if not root then
		return false
	end
	local rel = cf:PointToObjectSpace(root.Position)
	return rel.X < 0 and -rel.X < car.half.X + BESIDE and math.abs(rel.Z) < car.half.Z + 1 and math.abs(rel.Y) < 8
end

-- An empty car standing in this car's lane further along its edge (yours while you're in a shop, a hot
-- car waiting at the roadside)? Nobody sits in it for obstacleGap to see, so traffic drove straight
-- through it. Looked for a few times a second (see step), never every frame. Sets
--   car.park = { t0, t1, off, run }: the car pulls out round it like round a stunt ramp, but eased out
--     and back over `run` studs of road (lanePos); or, where the road has no room to pass,
--   car.stopT: how far along the edge the car may drive (it waits behind: obstacleGap).
local function parkedAhead(car)
	local old = car.park
	if old and car.t > old.t0 and car.t < old.t1 + 30 then
		-- Already on its way round one: it keeps that line to the end, even when the car it's passing
		-- has just driven off (swinging straight back into the lane would cut in on it). And for 30 studs
		-- after it's back in its lane, while its nose swings straight: personAhead looks along the road
		-- for it until then, or it knocked over someone standing in the lane just past the empty car.
		-- (Past t1 the record no longer moves the car: lanePos.)
		return
	end
	car.park, car.stopT = nil, nil
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	local na, _, dir, right, len = edgeInfo(car.a, car.b)
	local halfW, halfL = car.half.X, car.half.Z
	local nearAlong, nearLat, nearHalfAlong, nearHalfLat -- the nearest one ahead
	for _, v in ipairs(vehicles:GetChildren()) do
		local chassis = v.PrimaryPart
		-- Standing, with nobody at the wheel (a driven car is seen by its driver's root part: obstacleGap).
		if chassis and v:GetAttribute("DriverUserId") == nil and chassis.AssemblyLinearVelocity.Magnitude < 3 then
			local p = chassis.Position
			local rel = Vector3.new(p.X - na.X, 0, p.Z - na.Z)
			local along, lat = rel:Dot(dir), rel:Dot(right)
			-- Half its footprint along and across this edge (as rampDodge).
			local look, size = chassis.CFrame.LookVector, chassis.Size
			local fwd, side = math.abs(look:Dot(dir)), math.abs(look:Dot(right))
			local hAlong = fwd * size.Z / 2 + side * size.X / 2
			local hLat = side * size.Z / 2 + fwd * size.X / 2
			-- On this edge with its tail still ahead of this car's middle, in this lane, and on the
			-- road (not a boat under a bridge).
			if along - hAlong > car.t and along < len and (not nearAlong or along < nearAlong)
				and math.abs(lat - car.off) < hLat + halfW + 0.5
				and p.Y > 0.5 and p.Y < 9 and not v:GetAttribute("Boat") then
				nearAlong, nearLat, nearHalfAlong, nearHalfLat = along, lat, hAlong, hLat
			end
		end
	end
	if not nearAlong then
		return
	end
	local width = RoadGraph.Width(car.a, car.b)
	local rightOff = nearLat + nearHalfLat + halfW + 1
	local leftOff = nearLat - nearHalfLat - halfW - 1
	-- Room to pass: on the right while this car stays on the road (as rampDodge), on the left while it
	-- stays clear of the lane coming the other way (the nearer of those two). Failing both it borrows
	-- the oncoming lane, so one badly parked car never jams a street; only a road blocked right across
	-- (nowhere left on the tarmac) makes traffic wait.
	local limit = width / 2 - halfW
	local rightOk = rightOff <= limit
	local leftOk = leftOff >= 2 * halfW - laneOffset(width, 1)
	local touch = nearAlong - nearHalfAlong - halfL -- where this car's front bumper would meet its tail
	if rightOk or leftOk or leftOff >= -limit then
		local goRight = rightOk and (not leftOk or rightOff - car.off <= car.off - leftOff)
		local t0, run = touch - 22, 18
		if car.t > t0 then
			-- Seen late (it was parked, or its driver got out, right in front of this car): pull out from here.
			t0 = car.t
			run = math.clamp(touch - t0, 6, 18)
		end
		car.park = { t0 = t0, t1 = nearAlong + nearHalfAlong + halfL + run, off = goRight and rightOff or leftOff, run = run }
	elseif car.t <= touch then
		car.stopT = touch - 4 -- no room: wait behind it, bumper to bumper as in a queue
	end
end

-- Something in this car's lane ahead? Returns how far it may still drive before it must stop (4 studs
-- short of the next car's bumper or of an empty car it can't pass, STOP_GAP short of a person,
-- MY_STOP_GAP short of you on foot: `me` is your root part while you're on foot, else nil), or nil.
local function obstacleGap(car, cf, walkers, me)
	local best = car.stopT and car.stopT - car.t or nil -- an empty car blocking the lane (parkedAhead)
	-- Other traffic on the same edge and lane.
	for _, other in ipairs(cars) do
		if other ~= car and not other.wrecked and other.a == car.a and other.b == car.b and other.lane == car.lane then
			local ahead = other.t - car.t
			if ahead > 0 then
				local room = ahead - other.half.Z - car.half.Z - 4 -- bumper to bumper, so a queue never overlaps
				if not best or room < best then
					best = room
				end
			end
		end
	end
	-- Players (on foot or in cars) and walkers in a box ahead.
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local room = root and personAhead(car, cf, root.Position, root == me and MY_STOP_GAP or STOP_GAP)
		if room and (not best or room < best) then
			best = room
		end
	end
	for _, pos in ipairs(walkers) do
		local room = personAhead(car, cf, pos, STOP_GAP)
		if room and (not best or room < best) then
			best = room
		end
	end
	-- A driver somebody just pulled out of their car, running across the road to the pavement.
	for _, d in ipairs(drivers) do
		local room = personAhead(car, cf, d.root.Position, STOP_GAP)
		if room and (not best or room < best) then
			best = room
		end
	end
	return best
end

-- Where PedClient's walkers are right now (none until it's running).
local function walkerPositions()
	local mod = script.Parent:FindFirstChild("PedClient")
	if not mod then
		return NO_WALKERS
	end
	local ok, PedClient = pcall(require, mod)
	return ok and PedClient.Positions and PedClient.Positions() or NO_WALKERS
end

-- A car (player or AI) ploughing into this one? Knock it flying.
local function checkRam(car, cf)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	for _, v in ipairs(vehicles:GetChildren()) do
		local chassis = v.PrimaryPart
		if chassis then
			local rel = cf:PointToObjectSpace(chassis.Position)
			local size = chassis.Size
			if math.abs(rel.X) < car.half.X + size.X / 2 - 0.5 and math.abs(rel.Z) < car.half.Z + size.Z / 2 - 0.5
				and math.abs(rel.Y) < 6 then
				local vel = chassis.AssemblyLinearVelocity
				if vel.Magnitude > RAM_SPEED then
					car.wrecked = os.clock()
					require(script.Parent:WaitForChild("SoundClient")).Play("Crash", cf.Position)
					-- A scripted tumble (no loose physics parts to fling anyone): a ballistic arc away
					-- from the hit with a spin, then a fade (see step()).
					local away = (cf.Position - chassis.Position) * Vector3.new(1, 0, 1)
					away = away.Magnitude > 0 and away.Unit or vel.Unit
					car.fly = {
						from = cf,
						vel = vel * 0.6 + away * 22 + Vector3.new(0, 32, 0),
						spin = Vector3.new(math.random(-5, 5), math.random(-7, 7), math.random(-5, 5)),
					}
					-- Our own car pays a little for it.
					if v:GetAttribute("DriverUserId") == player.UserId then
						chassis.AssemblyLinearVelocity = vel * 0.8
					end
					return
				end
			end
		end
	end
end

-- This traffic car clipping us on foot at speed? Knock us over (ImpactClient does the fall).
-- It stops for people in its lane, so this is someone stepping out right in front of it or into its side.
local function checkKnock(car, cf)
	if car.speed < KNOCK_SPEED or (car.knockAt and os.clock() - car.knockAt < 2) then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 or hum.SeatPart then
		return
	end
	local rel = cf:PointToObjectSpace(root.Position)
	-- Anywhere from the front bumper to just past the middle (not someone the car already passed).
	if math.abs(rel.X) < car.half.X + 1 and rel.Z > -car.half.Z - 1 and rel.Z < car.half.Z * 0.6
		and rel.Y > -2 and rel.Y < car.half.Y + 7 then
		car.knockAt = os.clock()
		local mod = script.Parent:FindFirstChild("ImpactClient")
		if not mod then
			return
		end
		local ok, knocked = pcall(function()
			return require(mod).KnockLocal(car.heading, car.speed)
		end)
		if ok and knocked then
			car.speed *= 0.4 -- the driver hits the brakes
		end
	end
end

------------------------------------------------------------------ the driver of a jacked car

local function removeDriver(index)
	local d = drivers[index]
	table.remove(drivers, index)
	if d.model.Parent then
		d.model:Destroy()
	end
end

-- A small white speech bubble over a head (the key-cap look: white, dark Display text), gone after
-- `seconds` or with the head.
local function speak(head, text, seconds)
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "Speech"
	bubble.Size = UDim2.fromOffset(66, 30)
	bubble.StudsOffset = Vector3.new(0, 2.2, 0)
	bubble.MaxDistance = 90
	bubble.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Words"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	label.BackgroundTransparency = 0.05
	label.BorderSizePixel = 0
	label.FontFace = Theme.Font.Display
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(12, 14, 18)
	label.Text = text
	Theme.Corners(label, 8)
	label.Parent = bubble
	bubble.Adornee = head
	bubble.Parent = head
	task.delay(seconds, function()
		bubble:Destroy()
	end)
end

-- The driver comes out of this (stopped) car's driver's door: one of PedService's looks, placed in the
-- doorway and moved by stepDrivers. `thiefPos`: where the thief stands, so the driver stumbles the other
-- way along the car. Returns true if a driver appeared.
local function pullOut(car, thiefPos)
	local cf = car.cf
	local templates = ReplicatedStorage:FindFirstChild("PedTemplates")
	local list = templates and templates:GetChildren() or {}
	if not cf or #list == 0 or not runAnim or not folder then
		return false
	end
	local model = list[math.random(#list)]:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		model:Destroy()
		return false
	end
	local parts = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.CastShadow = false
			part.CollisionGroup = "Traffic" -- (like PedClient's walkers: cars pass through)
			table.insert(parts, part)
		end
	end
	local hx, hz = car.half.X, car.half.Z
	local doorZ = -hz * 0.1
	-- Along the car, away from the thief: toward the back, unless they stand behind the door on this side.
	local along = 1
	if typeof(thiefPos) == "Vector3" then
		local rel = cf:PointToObjectSpace(thiefPos)
		if rel.X < 0 and rel.Z > doorZ then
			along = -1
		end
	end
	local from = Vector3.new(-hx * 0.45, STAND_HEIGHT, doorZ)
	local to = Vector3.new(-(hx + 1.7), STAND_HEIGHT, doorZ + along * STUMBLE_ALONG)
	-- Where they run once they have their feet: to the pavement and along it, away from the thief, never
	-- down the road. The far kerb, straight across (traffic stops for them: obstacleGap), unless that is
	-- a long way or much the longer one (a highway lane): then round the end of their own car to the kerb
	-- behind it. In the car's frame the road's middle is car.off to the left (-X) of the car.
	local okWidth, width = pcall(RoadGraph.Width, car.a, car.b)
	if not okWidth or type(width) ~= "number" then
		width = 28
	end
	local off = type(car.off) == "number" and car.off or 0
	local farX = -(off + width / 2 + KERB_IN)
	local nearX = width / 2 - off + KERB_IN
	local farWay = -farX + to.X -- studs across to the far kerb from where the stagger ends (to.X is negative)
	local nearWay = nearX - to.X
	local path = {} -- world points, run to one after the other (stepDrivers)
	if farWay <= 30 and farWay <= nearWay + 8 then
		table.insert(path, cf:PointToWorldSpace(Vector3.new(farX, STAND_HEIGHT, to.Z + along * 14)))
		table.insert(path, cf:PointToWorldSpace(Vector3.new(farX, STAND_HEIGHT, to.Z + along * 74)))
	else
		local zEnd = along * (hz + 3)
		table.insert(path, cf:PointToWorldSpace(Vector3.new(to.X, STAND_HEIGHT, zEnd))) -- past the car's end first: never through it
		table.insert(path, cf:PointToWorldSpace(Vector3.new(nearX, STAND_HEIGHT, zEnd + along * 6)))
		table.insert(path, cf:PointToWorldSpace(Vector3.new(nearX, STAND_HEIGHT, zEnd + along * 66)))
	end
	-- Held by its root while it staggers (stepDrivers moves it); let go when it runs.
	root.Anchored = true
	model.Name = "TrafficDriver"
	model:PivotTo(cf * CFrame.new(from) * CFrame.Angles(0, math.rad(90), 0)) -- in the doorway, facing out (-X)
	model.Parent = folder
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local track = animator:LoadAnimation(runAnim)
	track.Looped = true
	track:Play(0.1, 1, 0.6) -- slow, scrambling steps
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		speak(head, "HEY!", 1.4)
	end
	while #drivers >= MAX_DRIVERS do
		removeDriver(1)
	end
	table.insert(drivers, {
		model = model, hum = hum, root = root, track = track, parts = parts,
		origin = cf, from = from, to = to, along = along, at = os.clock(), running = false,
		path = path, leg = 1,
	})
	return true
end

-- Every frame: staggering drivers are moved along their few steps (off balance: leaning forward, swaying,
-- a couple of little hops), then find their feet and run their way (d.path, one stretch after the other:
-- on to the next when they are nearly there, or after FLEE_LEG seconds); running ones fade away after
-- FLEE_TIME.
local function stepDrivers(now)
	for i = #drivers, 1, -1 do
		local d = drivers[i]
		if not d.model.Parent then
			table.remove(drivers, i)
		elseif not d.running then
			local s = math.clamp((now - d.at) / STUMBLE_TIME, 0, 1)
			local k = 1 - (1 - s) * (1 - s) -- quick out of the door, slowing as they catch themselves
			local off = 1 - s
			local pos = d.from:Lerp(d.to, k) + Vector3.new(0, math.abs(math.sin(s * math.pi * 3)) * 0.2 * off, 0)
			-- Facing out of the car at first (a heading of 90 degrees is -X), turning to where they'll run.
			local yaw = math.rad(90) + d.along * math.rad(70) * s
			d.root.CFrame = d.origin * CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(-0.35 * math.sin(s * math.pi), 0, math.sin(s * math.pi * 4) * 0.22 * off)
			if s >= 1 then
				d.running = true
				d.runAt = now
				d.legAt = now
				d.root.Anchored = false
				d.hum.WalkSpeed = FLEE_SPEED
				d.track:AdjustSpeed(1.25)
				d.hum:MoveTo(d.path[d.leg])
			end
		else
			local goal, nextGoal = d.path[d.leg], d.path[d.leg + 1]
			if goal and nextGoal then
				local p = d.root.Position
				local dx, dz = goal.X - p.X, goal.Z - p.Z
				if dx * dx + dz * dz < 9 or now - d.legAt > FLEE_LEG then
					d.leg += 1
					d.legAt = now
					d.hum:MoveTo(nextGoal)
				end
			end
			local left = FLEE_TIME + FLEE_FADE - (now - d.runAt)
			if left <= 0 then
				removeDriver(i)
			elseif left < FLEE_FADE then
				local fade = 1 - left / FLEE_FADE
				for _, part in ipairs(d.parts) do
					part.LocalTransparencyModifier = fade
				end
			end
		end
	end
end

local moveParts, moveCFrames = {}, {}

local function step(dt)
	if not ready then
		return
	end
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	-- Recycle far or long-wrecked cars; top up.
	for i = #cars, 1, -1 do
		local car = cars[i]
		local far = (Vector3.new(car.pos.X, 0, car.pos.Z) - flat).Magnitude > DESPAWN
		if far or (car.wrecked and os.clock() - car.wrecked > 2.8) then
			removeCar(i)
		end
	end
	-- Performance mode (phone SETTINGS) keeps fewer cars around.
	local perf = require(script.Parent:WaitForChild("SettingsClient")).Get("Performance")
	if #cars < (perf and 6 or MAX_CARS) then
		spawnCar()
	elseif perf and #cars > 6 then
		removeCar(#cars)
	end

	table.clear(moveParts)
	table.clear(moveCFrames)
	local walkers = walkerPositions()
	local greenAxis, amber = Signals.Phase()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local myRoot = hum and hum.Health > 0 and not hum.SeatPart and char:FindFirstChild("HumanoidRootPart") or nil
	local clock = os.clock()
	for _, car in ipairs(cars) do
		if car.held and clock - car.held > HOLD_TIMEOUT then
			car.held = nil -- the server never answered: drive on
		end
		if car.wrecked then
			local f = car.fly
			if f then
				local t = os.clock() - car.wrecked
				local pos = f.from.Position + f.vel * t + Vector3.new(0, -60, 0) * t * t
				pos = Vector3.new(pos.X, math.max(pos.Y, ROAD_TOP + 1), pos.Z)
				local rot = CFrame.Angles(f.spin.X * t, f.spin.Y * t, f.spin.Z * t)
				local cfw = CFrame.new(pos) * (f.from - f.from.Position) * rot
				local fade = math.clamp((t - 1.6) / 1, 0, 1)
				for _, rec in ipairs(car.parts) do
					table.insert(moveParts, rec.part)
					table.insert(moveCFrames, cfw * rec.offset)
					if fade > 0 then
						rec.part.LocalTransparencyModifier = fade
					end
				end
			end
			continue
		end
		-- Target speed: cruise, slower into sharp turns, stop behind obstacles.
		local target = car.cruise
		local toEnd = car.len - car.t
		if toEnd < 40 and car.turnDot < 0.7 then
			target = math.min(target, 16 + 20 * math.max(car.turnDot, 0))
		end
		-- Signals: red (or amber) for this road's axis at the junction ahead. Stop with the front bumper
		-- at the line if the car can stop in time (d = room left before the line; a car stopped up to
		-- 2 studs past it stays put). Otherwise it's committed and drives on through.
		if signalNodes[car.b] and (car.axis ~= greenAxis or amber) then
			local d = toEnd - car.half.Z - car.stopLine
			if d > -2 and car.speed * car.speed / (2 * MAX_BRAKE) <= d + 2 then
				target = math.min(target, math.sqrt(2 * SIGNAL_BRAKE * math.max(d, 0)))
			end
		end
		-- Empty cars standing in the lane: looked for four times a second, not every frame (phones).
		if clock >= (car.parkAt or 0) then
			car.parkAt = clock + 0.25
			parkedAhead(car)
		end
		local cf = CFrame.lookAt(car.pos, car.pos + car.heading)
		local room = obstacleGap(car, cf + Vector3.new(0, ROAD_TOP + 2, 0), walkers, myRoot)
		if room then
			-- Close in gently (room x 1.5), but never faster than the car can still stop from along the
			-- STOP_BRAKE curve (that part only bites above about 45 studs/s, e.g. on the highway).
			local r = math.max(room, 0)
			target = math.min(target, r * 1.5, math.sqrt(2 * STOP_BRAKE * r))
		end
		-- Being jacked, or you're standing at its side while it's slow: it waits right here.
		if car.held or (car.speed < JACK_SPEED and besideMe(car, cf + Vector3.new(0, ROAD_TOP + 2, 0), myRoot)) then
			target = 0
		end
		local accel = target > car.speed and 14 or MAX_BRAKE
		local before = car.speed
		car.speed += math.clamp(target - car.speed, -accel * dt, accel * dt)
		-- Brake lights: losing speed, or standing with nowhere to go (a red light, a queue, a jack).
		local gain = dt > 0 and (car.speed - before) / dt or 0
		if gain < -BRAKE_DECEL or (car.speed < 0.5 and target < 0.5) then
			car.brakeUntil = clock + BRAKE_HOLD
		end
		local brakeOn = clock < (car.brakeUntil or 0)
		if brakeOn ~= car.brakeOn then
			car.brakeOn = brakeOn
			setLights(car)
		end
		-- The nose dips under braking and lifts a little pulling away (only in how it's drawn, below).
		local pitch = car.pitch or 0
		pitch += (math.clamp(gain * PITCH_PER_ACCEL, -PITCH_DIVE, PITCH_SQUAT) - pitch) * math.clamp(dt * 7, 0, 1)
		car.pitch = pitch
		car.t += car.speed * dt
		if car.t >= car.len then
			local over = car.t - car.len
			local a, b = car.b, car.nextB
			enterEdge(car, a, b, over)
		end
		-- Blend smoothly into the new lane position after a turn.
		local want = lanePos(car, car.t)
		local newPos = car.pos:Lerp(want, math.clamp(dt * 8, 0, 1))
		local moved = newPos - car.pos
		if moved.Magnitude > 0.01 then
			car.heading = car.heading:Lerp(moved.Unit, math.clamp(dt * 10, 0, 1)).Unit
		end
		car.pos = newPos
		cf = CFrame.lookAt(car.pos, car.pos + car.heading) + Vector3.new(0, ROAD_TOP, 0)
		car.cf = cf -- where its body is drawn (the model's pivot), for FindJackable / Jack
		checkRam(car, cf + Vector3.new(0, 2, 0))
		if not car.wrecked then
			checkKnock(car, cf)
			-- Tipped about the pivot (the road under the car's middle): a positive angle lifts the nose.
			local draw = cf
			if math.abs(pitch) > 0.002 then
				draw = cf * CFrame.Angles(pitch, 0, 0)
			end
			for _, rec in ipairs(car.parts) do
				table.insert(moveParts, rec.part)
				table.insert(moveCFrames, draw * rec.offset)
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	stepDrivers(clock)
end

function TrafficClient.Count()
	return #cars
end

------------------------------------------------------------------ carjacking

-- The traffic car you (on foot at `pos`) could jack: slower than JACK_SPEED, not wrecked or already being
-- taken, its pivot within JACK_REACH, and you within doorRange of its driver's door (front-left, -X) or
-- within boxRange of its body anywhere around it. Returns the nearest such car (by its door) and that
-- distance, or nil.
function TrafficClient.FindJackable(pos, doorRange, boxRange)
	local best, bestD
	for _, car in ipairs(cars) do
		local cf = car.cf
		if cf and JACK_KINDS[car.kind] and not car.wrecked and not car.held and car.speed < JACK_SPEED
			and (cf.Position - pos).Magnitude <= JACK_REACH then
			local rel = cf:PointToObjectSpace(pos)
			if rel.Y > -2 and rel.Y < 9 then
				local hx, hz = car.half.X, car.half.Z
				local dDoor = Vector2.new(rel.X + hx + 0.5, rel.Z + hz * 0.1).Magnitude
				local gx, gz = math.max(math.abs(rel.X) - hx, 0), math.max(math.abs(rel.Z) - hz, 0)
				local dBox = math.sqrt(gx * gx + gz * gz)
				if (dDoor <= doorRange or dBox <= boxRange) and (not bestD or dDoor < bestD) then
					best, bestD = car, dDoor
				end
			end
		end
	end
	return best, bestD
end

-- Take this traffic car (InteractClient's JACK): it stops dead and waits for the server. Returns
-- { Kind, CFrame (its pivot, on the road), Color } for RequestCarjack, or nil if it can't be taken any
-- more. It stays put until "Carjacked" (the real car is there), "CarjackRefused" or HOLD_TIMEOUT.
function TrafficClient.Jack(car)
	local cf = car and car.cf
	if not cf or not table.find(cars, car) or car.wrecked or car.held then
		return nil
	end
	car.held = os.clock()
	car.speed = 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	car.jackFrom = root and root.Position or nil -- the driver stumbles away from here
	return { Kind = car.kind, CFrame = cf, Color = car.color }
end

-- Is this car still stopped and waiting for a jack to finish?
function TrafficClient.IsHeld(car)
	return car ~= nil and car.held ~= nil and table.find(cars, car) ~= nil
end

-- Where the thief goes at a held car. Returns its pivot (world CFrame, on the road, front -Z) and, in
-- that frame: where to stand at the driver's door (-X) and at the passenger's door (both a standing
-- character's root, looking at the car), and where the driver sits (a seated root, facing forward; a
-- guess from the body's size, the server's real seat has the last word). Then, as a fifth value, half
-- the body's length in studs (for walking round the car: its body is no wall here). nil if the car is gone.
function TrafficClient.JackSpots(car)
	local cf = car and car.cf
	if not cf or not table.find(cars, car) then
		return nil
	end
	local hx, hz = car.half.X, car.half.Z
	local z = -hz * 0.1 -- the driver's door (FindJackable measures to the same spot)
	local out = hx + DOOR_OUT
	local driverDoor = CFrame.lookAt(Vector3.new(-out, STAND_HEIGHT, z), Vector3.new(0, STAND_HEIGHT, z))
	local passengerDoor = CFrame.lookAt(Vector3.new(out, STAND_HEIGHT, z), Vector3.new(0, STAND_HEIGHT, z))
	local seat = CFrame.new(-math.max(hx * 0.31, 1.1), SEAT_HEIGHT, z + 0.6)
	return cf, driverDoor, passengerDoor, seat, hz
end

-- The driver of a held car comes out (see the header). Once per car. The car's wait for the server
-- starts over from here, since the thief only asks for the car after this.
function TrafficClient.PullDriver(car, thiefPos)
	if not car or not car.cf or car.driverOut or not table.find(cars, car) then
		return false
	end
	car.driverOut = true
	if car.held then
		car.held = os.clock()
	end
	local ok, out = pcall(pullOut, car, typeof(thiefPos) == "Vector3" and thiefPos or car.jackFrom)
	if not ok then
		warn("[TrafficClient] driver: " .. tostring(out))
	end
	return ok and out == true
end

-- The jack was called off before the server was asked (the thief walked away): the car drives on.
function TrafficClient.Release(car)
	if car then
		car.held = nil
		car.jackFrom = nil
	end
end

-- The jack went through and nobody had pulled the driver out (an instant jack): a door slams and they
-- come out now, stumbling away from where the thief stood.
local function driverLeaves(car)
	if car.driverOut or not car.cf then
		return
	end
	local sounds = script.Parent:FindFirstChild("SoundClient")
	if sounds then
		pcall(function()
			require(sounds).Play("Door", car.cf.Position + Vector3.new(0, 3, 0))
		end)
	end
	TrafficClient.PullDriver(car, car.jackFrom)
end

-- Junctions with signals: each TrafficSignal pole (Restyle) marks the nearest junction (3+ roads).
-- Poles stream in around you; a junction stays marked once seen, since signals never move.
local function trackSignal(inst)
	if not (inst:IsA("BasePart") and inst.Name == "Pole" and inst.Parent and inst.Parent.Name == "TrafficSignal") then
		return
	end
	local p = Vector3.new(inst.Position.X, 0, inst.Position.Z)
	local best, bestD
	for i, n in ipairs(RoadGraph.Nodes) do
		local d = (n - p).Magnitude
		if d < 90 and (not bestD or d < bestD) and degree(i) >= 3 then
			best, bestD = i, d
		end
	end
	if best then
		signalNodes[best] = true
	end
end

local function watchSignals()
	local city = Workspace:WaitForChild("City", 30)
	if not city then
		return
	end
	city.DescendantAdded:Connect(trackSignal)
	for _, d in ipairs(city:GetDescendants()) do
		trackSignal(d)
	end
end

function TrafficClient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Traffic"
	folder.Parent = Workspace
	-- The run cycle of a driver pulled out of their car: Config.Animations' default set when that module
	-- is there, else Roblox's default R15 run directly.
	local runId = RUN_ANIM
	local config = ReplicatedStorage.Shared.Config:FindFirstChild("Animations")
	if config then
		local ok, id = pcall(function()
			return require(config).Asset("Default", "run")
		end)
		if ok and type(id) == "string" then
			runId = id
		end
	end
	runAnim = Instance.new("Animation")
	runAnim.AnimationId = runId
	-- Lights follow the dark: night, or a rain storm.
	local function relight()
		night = Workspace:GetAttribute("IsNight") == true
		raining = Workspace:GetAttribute("Raining") == true
		for _, car in ipairs(cars) do
			setLights(car)
		end
	end
	relight()
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(relight)
	Workspace:GetAttributeChangedSignal("Raining"):Connect(relight)
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				ready = true
				watchSignals()
				return
			end
			task.wait(1)
		end
	end)
	RunService.Heartbeat:Connect(step)
	-- The real car is here (CarjackService): the traffic car we handed over loses its driver and goes.
	-- (A parked car break-in has no traffic car.)
	Remotes.OnClient("Carjacked", function(info)
		if type(info) == "table" and info.Parked then
			return
		end
		for i = #cars, 1, -1 do
			if cars[i].held then
				driverLeaves(cars[i]) -- (only if PullDriver hasn't already sent them running)
				removeCar(i)
			end
		end
	end)
	-- The server said no: the traffic car drives on right away.
	Remotes.OnClient("CarjackRefused", function()
		for _, car in ipairs(cars) do
			car.held = nil
			car.jackFrom = nil
		end
	end)
end

return TrafficClient
