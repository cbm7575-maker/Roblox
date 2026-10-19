-- TrafficClient (ModuleScript, StarterPlayerScripts.Controllers.TrafficClient)
-- Ambient traffic, simulated on each player's own device (it costs the server nothing):
--   * Up to MAX_CARS pastel cars (fewer in Performance mode) drive the RoadGraph around the camera,
--     keeping right, two lanes each way on Highway 1 (the lane is re-picked on every stretch). They
--     slow for corners, follow the car ahead, give way at junctions, show brake lights, pull over and
--     stop for sirens coming up behind, and honk at players who block them.
--   * What they see (squared-distance filtered, scanned ~10 times a second per car): other traffic on
--     this stretch and the next, every car in Workspace.Vehicles (parked, AI police, hot cars), players
--     on foot, pedestrians (PedClient), police roadblocks (Models in Workspace.Roadblocks), stunt
--     ramps and wandering event props (Models in Workspace.Events with attribute Obstacle = true). Parked things get steered around when there's room; otherwise the car stops, and after a
--     while it quietly fades away.
--   * Stunt ramps that sit in a lane (Config.Activities.Stunts) are mapped at start-up: cars take the
--     clear lane or ease around them. The prison bridge (a dead end onto Saltmarsh Island) is off-limits.
--   * Anchored, collision group "Traffic" (doesn't collide with players' "Vehicles"), so a car never hits
--     an immovable wall: when any car ploughs into one above RAM_SPEED it gets knocked flying (scripted
--     arc) and fades away. Your own car loses a little speed.
--   * Cars far from the camera are recycled into fresh spots out of sight (the real spawn spot is
--     checked against the camera). Bodies are pooled. Cars beyond FAR_RANGE update at a lower rate.
--   * Headlights glow at night.
-- If ReplicatedStorage.TrafficModels has models (pivot at the bottom centre, front facing -Z), bodies
-- are cloned from those; otherwise simple greybox cars are built here.
--   TrafficClient.Count() -> number of cars.
--   TrafficClient.Cars() -> the live car records (read-only: .pos, .heading, .speed, .half, .wrecked);
--     PedClient uses it to dodge traffic.
--   TrafficClient.EdgeAllowed(i, j) -> false for road graph edges nobody should use (prison bridge).
--   TrafficClient.PedSource = fn() -> { BasePart }: set by PedClient, the walkers' root parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Activities = require(ReplicatedStorage.Shared.Config.Activities)

local player = Players.LocalPlayer

local TrafficClient = {}
TrafficClient.PedSource = nil :: (() -> { BasePart })?

local MAX_CARS, PERF_CARS = 14, 6
local SPAWN_MIN, SPAWN_MAX = 160, 380 -- studs from the camera focus
local DESPAWN = 480
local STREET_SPEED, HIGHWAY_SPEED = 42, 68 -- studs/s
local RAM_SPEED = 25
local ROAD_TOP = 0.1
local FAR_RANGE = 250 -- beyond this many studs, cars update FAR_HZ times a second
local FAR_STEP = 1 / 6
local SCAN_STEP = 0.1 -- seconds between obstacle scans (per car, staggered)
local PLAN_DECEL = 30 -- studs/s^2 used to plan stops (cars can brake at 40)
local SIREN_RANGE = 90
local HONK_AFTER = 2.5 -- seconds blocked by a player before honking
-- Seconds stuck behind something that won't move before the car quietly fades away (by what blocks it).
local GIVE_UP = { car = 8, block = 8, ramp = 8, walker = 16, traffic = 20, ped = 20 }
local POOL_MAX = MAX_CARS + 4
local CAR_HALF_W = 3.6 -- lateral half-width used when mapping ramps
-- Prison bridge + prison road (x, z box): a dead end onto Saltmarsh Island, closed to traffic and walkers.
local PRISON_MIN, PRISON_MAX = Vector2.new(-1470, 870), Vector2.new(-1380, 1400)

local PASTELS = {
	Color3.fromRGB(255, 180, 210), Color3.fromRGB(150, 230, 210), Color3.fromRGB(255, 214, 150),
	Color3.fromRGB(190, 170, 255), Color3.fromRGB(245, 245, 250), Color3.fromRGB(150, 200, 255),
	Color3.fromRGB(255, 150, 130), Color3.fromRGB(60, 60, 75), Color3.fromRGB(200, 60, 80),
}
local TAIL_DIM, TAIL_BRAKE = Color3.fromRGB(150, 20, 35), Color3.fromRGB(255, 45, 60)

local folder
local cars = {} -- list of car records
local pool = {} -- spare car bodies
local ready = false
local night = false
local nextId = 0
local nextGlobalHonk = 0

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

-- A body: { model, parts = { { part, offset } } (for BulkMoveTo), half (Vector3), paint = { parts },
-- brakes = { { part, kind } } }. Bodies are pooled and repainted on reuse.
local function buildCar()
	local W, H, L = 6.6, 1.8, 13
	local model = Instance.new("Model")
	model.Name = "TrafficCar"
	local parts, paint, brakes = {}, {}, {}
	local function add(part, offset)
		part.Parent = model
		table.insert(parts, { part = part, offset = offset })
		return part
	end
	local templates = ReplicatedStorage:FindFirstChild("TrafficModels")
	local list = templates and templates:GetChildren() or {}
	if #list > 0 then
		local body = list[math.random(#list)]:Clone()
		local _, ext = body:GetBoundingBox()
		W, H, L = ext.X, ext.Y * 0.45, ext.Z
		local pivot = body:GetPivot()
		local hasTail = false
		for _, d in ipairs(body:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.CastShadow = false
				d.CollisionGroup = "Traffic"
				if d:GetAttribute("BodyPaint") then
					table.insert(paint, d)
				end
				if d.Name == "Taillight" then
					hasTail = true
					table.insert(brakes, { part = d, kind = "glow", color = d.Color, material = d.Material })
				end
				local rel = pivot:ToObjectSpace(d.CFrame)
				d.Parent = model
				table.insert(parts, { part = d, offset = rel })
			end
		end
		body:Destroy()
		if not hasTail then
			-- Textured bodies have no light parts: two small lamps on the back that light up when braking.
			for _, sx in ipairs({ -1, 1 }) do
				local lamp = add(newPart("BrakeLight", Vector3.new(1.1, 0.4, 0.12), TAIL_BRAKE, Enum.Material.Neon),
					CFrame.new(sx * (W / 2 - 1), ext.Y * 0.45, L / 2 + 0.03))
				lamp.Transparency = 1
				table.insert(brakes, { part = lamp, kind = "show" })
			end
		end
	else
		table.insert(paint, add(newPart("Body", Vector3.new(W, H, L), Color3.new(1, 1, 1)), CFrame.new(0, H / 2 + 1.1, 0)))
		add(newPart("Cabin", Vector3.new(W - 1.2, 2.2, L * 0.45), Color3.fromRGB(40, 50, 70), Enum.Material.Glass),
			CFrame.new(0, H + 1.1 + 1.1, L * 0.05)).Transparency = 0.3
		table.insert(paint, add(newPart("Roof", Vector3.new(W - 1.3, 0.25, L * 0.4), Color3.new(1, 1, 1)), CFrame.new(0, H + 1.1 + 2.3, L * 0.05)))
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				add(newPart("Wheel", Vector3.new(1, 2.4, 2.4), Color3.fromRGB(28, 28, 32), nil, Enum.PartType.Cylinder),
					CFrame.new(sx * (W / 2 - 0.3), 1.2, sz * (L / 2 - 2.4)))
			end
			add(newPart("Headlight", Vector3.new(1.3, 0.5, 0.2), Color3.fromRGB(255, 250, 220), Enum.Material.SmoothPlastic),
				CFrame.new(sx * (W / 2 - 1.1), H / 2 + 1.2, -L / 2 - 0.05))
			local tail = add(newPart("Taillight", Vector3.new(1.3, 0.5, 0.2), TAIL_DIM, Enum.Material.Neon),
				CFrame.new(sx * (W / 2 - 1.1), H / 2 + 1.2, L / 2 + 0.05))
			table.insert(brakes, { part = tail, kind = "dim" })
		end
	end
	return { model = model, parts = parts, half = Vector3.new(W / 2, H, L / 2), paint = paint, brakes = brakes }
end

local function setBrakes(car, on)
	if car.braking == on then
		return
	end
	car.braking = on
	for _, b in ipairs(car.body.brakes) do
		local part = b.part
		if b.kind == "show" then
			part.Transparency = on and 0 or 1
		elseif b.kind == "dim" then
			part.Color = on and TAIL_BRAKE or TAIL_DIM
		else -- a mesh taillight: glow while braking
			part.Material = on and Enum.Material.Neon or b.material
			part.Color = on and TAIL_BRAKE or b.color
		end
	end
end

local WARM = Color3.fromRGB(255, 244, 210)
local function setLights(car)
	for _, rec in ipairs(car.body.parts) do
		local part = rec.part
		if part.Name == "Headlight" then
			rec.baseColor = rec.baseColor or part.Color
			rec.baseMat = rec.baseMat or part.Material
			part.Material = night and Enum.Material.Neon or rec.baseMat
			part.Color = night and WARM or rec.baseColor
		end
	end
end

local function acquireBody()
	local body = table.remove(pool) or buildCar()
	local color = PASTELS[math.random(#PASTELS)]
	for _, p in ipairs(body.paint) do
		p.Color = color
	end
	for _, rec in ipairs(body.parts) do
		rec.part.LocalTransparencyModifier = 0
	end
	body.model.Parent = folder
	return body
end

local function releaseBody(body)
	body.model.Parent = nil
	if #pool < POOL_MAX then
		table.insert(pool, body)
	else
		body.model:Destroy()
	end
end

------------------------------------------------------------------ the road graph

local adj = {} -- [i] = { j, ... } usable neighbours
local nodeHalf = {} -- [i] = half the widest road at node i (where to stop before a junction)
local edgeCache = {}
local rampObstacles = {}

local function inPrison(p)
	return p.X > PRISON_MIN.X and p.X < PRISON_MAX.X and p.Z > PRISON_MIN.Y and p.Z < PRISON_MAX.Y
end

function TrafficClient.EdgeAllowed(i, j)
	local a, b = RoadGraph.Nodes[i], RoadGraph.Nodes[j]
	return a ~= nil and b ~= nil and not inPrison(a) and not inPrison(b)
end

-- Directed stretch a -> b: geometry, lane offsets (to the right of travel) and ramp detours.
local function edge(a, b)
	local key = a * 100000 + b
	local e = edgeCache[key]
	if not e then
		local na, nb = RoadGraph.Nodes[a], RoadGraph.Nodes[b]
		local d = nb - na
		local len = d.Magnitude
		local dir = len > 0 and d / len or Vector3.new(0, 0, 1)
		local width = RoadGraph.Width(a, b)
		e = {
			a = a, b = b, na = na, nb = nb, dir = dir, right = Vector3.new(-dir.Z, 0, dir.X), len = len,
			width = width,
			lanes = width >= 50 and { width * 0.13, width * 0.36 } or { width * 0.24 },
			detours = {}, -- [lane] = { t0, t1, off } (off nil: no way past)
			impassable = false,
		}
		edgeCache[key] = e
	end
	return e
end

-- Lateral offset for a lane at distance t along a stretch, easing around a ramp in that lane.
local function laneOff(e, lane, t)
	local off = e.lanes[lane] or e.lanes[1]
	local d = e.detours[lane]
	if d and d.off then
		local k = 1
		if t < d.t0 then
			k = 1 - math.clamp((d.t0 - t) / 25, 0, 1)
		elseif t > d.t1 then
			k = 1 - math.clamp((t - d.t1) / 15, 0, 1)
		end
		off += (d.off - off) * k
	end
	return off
end

-- Stunt ramps: which lanes they block and how to get past (start-up, once).
local function mapRamps()
	local ramps = {}
	table.clear(rampObstacles)
	for _, s in ipairs(Activities.Stunts or {}) do
		if typeof(s.Ramp) == "Vector3" and typeof(s.Travel) == "Vector3" then
			local u = Vector3.new(s.Travel.X, 0, s.Travel.Z)
			u = u.Magnitude > 0 and u.Unit or Vector3.new(0, 0, 1)
			local v = Vector3.new(-u.Z, 0, u.X)
			local c = Vector3.new(s.Ramp.X, 0, s.Ramp.Z)
			-- CityGen: 16 wide across the travel direction, 20 long along it.
			table.insert(ramps, { c + u * 10 + v * 8, c + u * 10 - v * 8, c - u * 10 + v * 8, c - u * 10 - v * 8 })
			table.insert(rampObstacles, {
				pos = c, look = u, hx = 8, hz = 10, vel = Vector3.zero, static = true, player = false, kind = "ramp",
			})
		end
	end
	for i, list in pairs(RoadGraph.Edges) do
		for j in pairs(list) do
			local e = edge(i, j)
			for _, corners in ipairs(ramps) do
				local aMin, aMax, lMin, lMax = math.huge, -math.huge, math.huge, -math.huge
				for _, p in ipairs(corners) do
					local rel = p - e.na
					local al, la = rel:Dot(e.dir), rel:Dot(e.right)
					aMin, aMax = math.min(aMin, al), math.max(aMax, al)
					lMin, lMax = math.min(lMin, la), math.max(lMax, la)
				end
				if aMax > -12 and aMin < e.len + 12 and lMax > -e.width / 2 and lMin < e.width / 2 then
					-- A car's centre must stay outside [lo, hi] while passing the ramp.
					local lo, hi = lMin - CAR_HALF_W - 1.2, lMax + CAR_HALF_W + 1.2
					local limitR = e.width / 2 - CAR_HALF_W - 0.6 -- the kerb
					local limitL = -e.width * 0.12 -- just over the centre line
					for k, off in ipairs(e.lanes) do
						if off > lo and off < hi and not e.detours[k] then
							local best
							for _, cand in ipairs({ lo, hi }) do
								if cand >= limitL and cand <= limitR and (not best or math.abs(cand - off) < math.abs(best - off)) then
									best = cand
								end
							end
							e.detours[k] = { t0 = aMin - 6, t1 = aMax + 6, off = best }
						end
					end
				end
			end
			local passable = false
			for k in ipairs(e.lanes) do
				local d = e.detours[k]
				if not d or d.off then
					passable = true
				end
			end
			e.impassable = not passable
		end
	end
end

local function buildGraph()
	table.clear(adj)
	table.clear(nodeHalf)
	table.clear(edgeCache)
	for i in ipairs(RoadGraph.Nodes) do
		local list = {}
		local half = 0
		for j in pairs(RoadGraph.Edges[i] or {}) do
			half = math.max(half, RoadGraph.Width(i, j) / 2)
			if TrafficClient.EdgeAllowed(i, j) then
				table.insert(list, j)
			end
		end
		adj[i] = list
		nodeHalf[i] = half
	end
	mapRamps()
end

-- A clear lane on this stretch: keep the previous one most of the time, avoid lanes a ramp blocks.
local function pickLane(e, prev)
	local clean, passable = {}, {}
	for k in ipairs(e.lanes) do
		local d = e.detours[k]
		if not d then
			table.insert(clean, k)
		end
		if not d or d.off then
			table.insert(passable, k)
		end
	end
	if #clean == 0 then
		-- Every lane passes a ramp: take the one that has to move over the least.
		local best, bestShift = 1, math.huge
		for _, k in ipairs(passable) do
			local shift = math.abs(e.detours[k].off - e.lanes[k])
			if shift < bestShift then
				best, bestShift = k, shift
			end
		end
		return best
	end
	local list = clean
	if prev and table.find(list, prev) and math.random() < 0.75 then
		return prev
	end
	return list[math.random(#list)]
end

local function chooseNext(b, a)
	local options = {}
	for _, k in ipairs(adj[b] or {}) do
		if k ~= a and not edge(b, k).impassable then
			table.insert(options, k)
		end
	end
	return #options > 0 and options[math.random(#options)] or a
end

------------------------------------------------------------------ driving on the graph

local function enterEdge(car, a, b, t)
	local e = edge(a, b)
	car.a, car.b, car.t, car.edge, car.len = a, b, t or 0, e, e.len
	car.lane = car.nextLane or pickLane(e, car.lane)
	car.cruise = (e.width >= 50 and HIGHWAY_SPEED or STREET_SPEED) * (0.85 + math.random() * 0.3)
	car.swerve = nil
	car.obs = nil
	car.nextScan = 0
	-- Choose the next stretch now, so we know how hard the turn at the end is.
	car.nextB = chooseNext(b, a)
	local n = edge(b, car.nextB)
	car.nextEdge = n
	car.nextLane = pickLane(n, car.lane)
	car.nextOff = laneOff(n, car.nextLane, 0)
	car.turnDot = e.dir:Dot(n.dir) -- 1 straight, 0 right angle, -1 U-turn
end

local function focus()
	local cam = Workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or cam.Focus.Position
end

local function onScreen(pos)
	local cam = Workspace.CurrentCamera
	local _, visible = cam:WorldToViewportPoint(pos + Vector3.new(0, 3, 0))
	return visible and (pos - cam.CFrame.Position).Magnitude < SPAWN_MAX + 60
end

local obstacles = {} -- rebuilt every SCAN_STEP: { pos, look, hx, hz, vel, static, player, kind, part? }
local sirens = {}

local function spawnCar()
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	local nodes = RoadGraph.Nodes
	for _ = 1, 12 do
		local i = math.random(#nodes)
		local nb = adj[i]
		if nb and #nb > 0 then
			local j = nb[math.random(#nb)]
			local e = edge(i, j)
			if not e.impassable and e.len > 24 then
				-- The real spot first (lane and distance along the stretch), then the tests.
				local t = (0.1 + math.random() * 0.8) * e.len
				local lane = pickLane(e, nil)
				local off = laneOff(e, lane, t)
				local pos = e.na + e.dir * t + e.right * off
				local d = (pos - flat).Magnitude
				local clear = d > SPAWN_MIN and d < SPAWN_MAX and not onScreen(pos)
				if clear then
					for _, other in ipairs(cars) do
						if (other.pos - pos).Magnitude < 20 then
							clear = false
							break
						end
					end
				end
				if clear then
					local body = acquireBody()
					nextId += 1
					local car = { id = nextId, body = body, half = body.half, speed = 0, acc = FAR_STEP }
					car.nextLane = lane
					enterEdge(car, i, j, t)
					car.offNow = off
					car.pos = pos
					car.heading = e.dir
					car.nextScan = math.random() * SCAN_STEP
					setLights(car)
					setBrakes(car, false)
					table.insert(cars, car)
					return
				end
			end
		end
	end
end

local function removeCar(index)
	local car = cars[index]
	releaseBody(car.body)
	table.remove(cars, index)
end

------------------------------------------------------------------ seeing things

local roadblockBoxes = setmetatable({}, { __mode = "k" }) -- [model] = { cf, size, at }

local function flatUnit(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
end

local function addBox(cf, size, kind)
	table.insert(obstacles, {
		pos = cf.Position, look = flatUnit(cf.LookVector), hx = size.X / 2, hz = size.Z / 2, vel = Vector3.zero,
		static = true, player = false, kind = kind,
	})
end

local function gatherObstacles(now)
	table.clear(obstacles)
	table.clear(sirens)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, v in ipairs(vehicles:GetChildren()) do
			local chassis = v:IsA("Model") and v.PrimaryPart
			if chassis and not v:GetAttribute("Boat") then
				local cf = chassis.CFrame
				local vel = chassis.AssemblyLinearVelocity
				local ai = v:GetAttribute("AIPolice") == true
				local o = {
					pos = cf.Position, look = flatUnit(cf.LookVector), hx = chassis.Size.X / 2, hz = chassis.Size.Z / 2,
					vel = vel, static = vel.Magnitude < 1.5, player = v:GetAttribute("DriverUserId") ~= nil and not ai,
					kind = "car", part = chassis, model = v,
				}
				table.insert(obstacles, o)
				if v:GetAttribute("Siren") == true or (ai and v:GetAttribute("AITarget") ~= nil) then
					table.insert(sirens, o)
				end
			end
		end
	end
	-- Players on foot (seated players are inside a car above).
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and not (hum and hum.SeatPart) then
			local vel = root.AssemblyLinearVelocity
			table.insert(obstacles, {
				pos = root.Position, look = flatUnit(root.CFrame.LookVector), hx = 1.5, hz = 1.5, vel = vel,
				static = vel.Magnitude < 1.5, player = true, kind = "walker",
			})
		end
	end
	-- Pedestrians (PedClient).
	if TrafficClient.PedSource then
		local ok, roots = pcall(TrafficClient.PedSource)
		if ok and type(roots) == "table" then
			for _, root in ipairs(roots) do
				if typeof(root) == "Instance" and root:IsA("BasePart") and root.Parent then
					table.insert(obstacles, {
						pos = root.Position, look = Vector3.new(0, 0, -1), hx = 1.4, hz = 1.4, vel = Vector3.zero,
						static = false, player = false, kind = "ped",
					})
				end
			end
		end
	end
	-- Police roadblocks.
	local blocks = Workspace:FindFirstChild("Roadblocks")
	if blocks then
		for _, b in ipairs(blocks:GetChildren()) do
			if b:IsA("Model") then
				local box = roadblockBoxes[b]
				if not box or now - box.at > 2 then
					local ok, cf, size = pcall(b.GetBoundingBox, b)
					if ok then
						box = { cf = cf, size = size, at = now }
						roadblockBoxes[b] = box
					end
				end
				if box then
					addBox(box.cf, box.size, "block")
				end
			elseif b:IsA("BasePart") then
				addBox(b.CFrame, b.Size, "block")
			end
		end
	end
	-- Florida moments that wander about (EventService marks them with attribute Obstacle = true).
	local events = Workspace:FindFirstChild("Events")
	if events then
		for _, m in ipairs(events:GetChildren()) do
			local root = m:IsA("Model") and m:GetAttribute("Obstacle") == true and m.PrimaryPart
			if root then
				table.insert(obstacles, {
					pos = root.Position, look = Vector3.new(0, 0, -1), hx = 1.5, hz = 1.5, vel = Vector3.zero,
					static = false, player = false, kind = "ped",
				})
			end
		end
	end
	for _, r in ipairs(rampObstacles) do
		table.insert(obstacles, r)
	end
end

-- How far an obstacle reaches across (lat) and along (lon) a stretch's directions.
local function extents(o, dir, right)
	local oRight = Vector3.new(-o.look.Z, 0, o.look.X)
	local lat = math.abs(right:Dot(o.look)) * o.hz + math.abs(right:Dot(oRight)) * o.hx
	local lon = math.abs(dir:Dot(o.look)) * o.hz + math.abs(dir:Dot(oRight)) * o.hx
	return lat, lon
end

-- The nearest thing in this car's path: sets car.obs = { gap, v, static, player, kind, lat, w, lon, at, t0 }.
local function scan(car, now)
	local e = car.edge
	local n = car.nextEdge
	local lookahead = 30 + car.speed * 0.9
	local toEnd = e.len - car.t
	local off = car.offTarget or car.offNow
	local best
	local function consider(gap, v, static, isPlayer, kind, lat, w, lon)
		if not best or gap < best.gap then
			best = { gap = gap, v = v, static = static, player = isPlayer, kind = kind, lat = lat, w = w, lon = lon }
		end
	end
	-- Other traffic: this stretch and the next one.
	for _, o in ipairs(cars) do
		if o ~= car and not o.wrecked and not o.fading then
			if o.a == car.a and o.b == car.b then
				if o.t > car.t and math.abs(o.offNow - off) < car.half.X + o.half.X then
					consider(math.max(o.t - car.t - car.half.Z - o.half.Z, 0), o.speed, false, false, "traffic")
				end
			elseif o.a == car.b and o.b == car.nextB and toEnd < lookahead then
				if math.abs(o.offNow - car.nextOff) < car.half.X + o.half.X then
					consider(math.max(toEnd + o.t - car.half.Z - o.half.Z, 0), o.speed, false, false, "traffic")
				end
			end
		end
	end
	-- Give way at junctions: traffic on the bigger road goes first; on equal roads, whoever is closer
	-- to the crossing. Nobody waits more than 4 s.
	local deg = adj[car.b] and #adj[car.b] or 0
	local stopGap = toEnd - (nodeHalf[car.b] or 16) - 2 - car.half.Z
	if deg >= 3 and toEnd < 34 + car.half.Z and stopGap > 0.5 and now - (car.yieldSince or now) < 4 then
		local yield = false
		for _, o in ipairs(cars) do
			if o ~= car and not o.wrecked and not o.fading and o.b == car.b and o.a ~= car.a
				and not (o.a == car.nextB and o.nextB == car.a) then -- straight past each other: no conflict
				local oEnd = o.len - o.t
				local ow = o.edge.width
				if ow > e.width + 2 then
					yield = oEnd < 60 + o.half.Z
				elseif ow >= e.width - 2 then
					yield = oEnd < 34 + o.half.Z and (oEnd < toEnd - 0.5 or (math.abs(oEnd - toEnd) <= 0.5 and o.id < car.id))
				end
				if yield then
					break
				end
			end
		end
		if yield then
			car.yieldSince = car.yieldSince or now
			consider(stopGap, 0, false, false, "yield")
		else
			car.yieldSince = nil
		end
	elseif toEnd >= 34 + car.half.Z then
		car.yieldSince = nil
	end
	-- Everything else: cars, players, pedestrians, roadblocks, ramps (a ramp this lane already eases
	-- round is left out).
	local detour = e.detours[car.lane]
	local skipRamp = detour ~= nil and detour.off ~= nil
	local nextDetour = n.detours[car.nextLane]
	local skipRampNext = nextDetour ~= nil and nextDetour.off ~= nil
	local reach = lookahead + 25
	local reach2 = reach * reach
	local cx, cz = car.pos.X, car.pos.Z
	for _, o in ipairs(obstacles) do
		local dx, dz = o.pos.X - cx, o.pos.Z - cz
		if dx * dx + dz * dz < reach2 and math.abs(o.pos.Y - car.pos.Y) < 14 then
			local rel = o.pos - e.na
			local along = rel:Dot(e.dir) - car.t
			if o.kind == "ramp" and (skipRamp or skipRampNext) then
				-- handled by the lane's detour
			elseif along > 0 and along < toEnd + 6 then
				local w, lon = extents(o, e.dir, e.right)
				local lat = rel:Dot(e.right)
				if along - lon < lookahead and math.abs(lat - off) < car.half.X + w + 0.8 then
					consider(math.max(along - lon - car.half.Z, 0), math.max(o.vel:Dot(e.dir), 0), o.static, o.player,
						o.kind, lat, w, lon)
				end
			elseif along >= toEnd + 6 and toEnd < lookahead then
				-- Past the junction: test against the next stretch.
				local rel2 = o.pos - n.na
				local along2 = rel2:Dot(n.dir)
				local w, lon = extents(o, n.dir, n.right)
				if along2 > -6 and along2 - lon < lookahead - toEnd and math.abs(rel2:Dot(n.right) - car.nextOff) < car.half.X + w + 0.8 then
					consider(math.max(toEnd + along2 - lon - car.half.Z, 0), math.max(o.vel:Dot(n.dir), 0), o.static, o.player,
						o.kind)
				end
			end
		end
	end
	-- Sirens coming up behind: pull over.
	for _, s in ipairs(sirens) do
		local rel = s.pos - car.pos
		if rel.X * rel.X + rel.Z * rel.Z < SIREN_RANGE * SIREN_RANGE and rel:Dot(car.heading) < -car.half.Z
			and s.vel:Dot(car.heading) > math.max(car.speed, 4) + 4 then
			car.pullUntil = now + 1.5
		end
	end
	if best then
		best.at, best.t0 = now, car.t
	end
	car.obs = best
end

-- A way around a parked obstacle (lateral offset of the car's centre), or nil.
local function swerveOffset(car, lat, w)
	local e = car.edge
	local lo = lat - w - car.half.X - 1.2
	local hi = lat + w + car.half.X + 1.2
	local maxR = e.width / 2 - car.half.X - 0.5
	local maxL = -e.width / 2 + car.half.X + 0.5
	local base = laneOff(e, car.lane, car.t)
	local best
	for _, cand in ipairs({ lo, hi }) do
		if cand <= maxR and cand >= maxL and (not best or math.abs(cand - base) < math.abs(best - base)) then
			best = cand
		end
	end
	if best and best < car.half.X then
		-- Using the oncoming lane: only when nothing is coming the other way.
		for _, o in ipairs(cars) do
			if o.a == car.b and o.b == car.a and not o.wrecked then
				local ahead = (e.len - o.t) - car.t
				if ahead > -10 and ahead < 120 then
					return nil
				end
			end
		end
	end
	return best
end

-- A car (player or AI) ploughing into this one? Knock it flying.
local function checkRam(car, cf, fast)
	for _, o in ipairs(fast) do
		local chassis = o.part
		local p = chassis.Position
		local dx, dz = p.X - cf.X, p.Z - cf.Z
		local r = car.half.Z + o.hz + 2
		if dx * dx + dz * dz < r * r then
			local rel = cf:PointToObjectSpace(p)
			local size = chassis.Size
			if math.abs(rel.X) < car.half.X + size.X / 2 - 0.5 and math.abs(rel.Z) < car.half.Z + size.Z / 2 - 0.5
				and math.abs(rel.Y) < 6 then
				local vel = chassis.AssemblyLinearVelocity
				if vel.Magnitude > RAM_SPEED then
					car.wrecked = os.clock()
					setBrakes(car, false)
					local sound = script.Parent:FindFirstChild("SoundClient")
					if sound then
						require(sound).Play("Crash", cf.Position)
					end
					-- A scripted tumble (no loose physics parts to fling anyone): a ballistic arc away
					-- from the hit with a spin, then a fade (see step()).
					local away = (cf.Position - p) * Vector3.new(1, 0, 1)
					away = away.Magnitude > 0 and away.Unit or vel.Unit
					car.fly = {
						from = cf,
						vel = vel * 0.6 + away * 22 + Vector3.new(0, 32, 0),
						spin = Vector3.new(math.random(-5, 5), math.random(-7, 7), math.random(-5, 5)),
					}
					-- Our own car pays a little for it.
					if o.model and o.model:GetAttribute("DriverUserId") == player.UserId then
						chassis.AssemblyLinearVelocity = vel * 0.8
					end
					return
				end
			end
		end
	end
end

local function honk(car)
	local sound = script.Parent:FindFirstChild("SoundClient")
	local part = car.body.parts[1] and car.body.parts[1].part
	if sound and part then
		require(sound).Play("Horn", part, 0.8)
	end
end

------------------------------------------------------------------ the loop

local moveParts, moveCFrames = {}, {}
local fastList = {}
local lastGather = 0

local function drive(car, dt, now)
	local e = car.edge
	-- Where across the road: lane (easing round ramps), swerving round parked things, pulling over.
	local offT = laneOff(e, car.lane, car.t)
	if car.swerve then
		if car.t > car.swerve.untilT then
			car.swerve = nil
		else
			offT = car.swerve.off
		end
	end
	local pulling = car.pullUntil ~= nil and now < car.pullUntil
	if pulling then
		offT = e.width / 2 - car.half.X - 0.6
	end
	car.offTarget = offT
	if now >= car.nextScan then
		car.nextScan = now + SCAN_STEP
		scan(car, now)
	end
	-- Target speed: cruise, slower into sharp turns, stop behind obstacles.
	local target = car.cruise
	local toEnd = e.len - car.t
	if toEnd < 40 and car.turnDot < 0.7 then
		target = math.min(target, 16 + 20 * math.max(car.turnDot, 0))
	end
	local obs = car.obs
	local stuck = false
	if obs then
		-- Gap now = gap at the scan, minus how far we've come, plus how far it went.
		local gap = obs.gap - (car.t - obs.t0) + obs.v * (now - obs.at)
		if obs.static and obs.lat and not car.swerve and not pulling and obs.kind ~= "ped" and obs.kind ~= "walker"
			and gap < 60 and (not obs.player or now - (car.blockedSince or now) > 6) then
			local s = swerveOffset(car, obs.lat, obs.w)
			if s then
				car.swerve = { off = s, untilT = car.t + gap + car.half.Z * 2 + obs.lon * 2 + 8 }
				car.obs = nil
				car.nextScan = now + 0.05
			end
		end
		if car.obs then
			target = math.min(target, obs.v + math.sqrt(2 * PLAN_DECEL * math.max(gap - 5, 0)))
			if gap < 2.5 then
				target = 0
			end
			stuck = obs.v < 1 and car.speed < 1 and obs.kind ~= "yield"
		end
	end
	if car.swerve then
		target = math.min(target, 22)
	end
	if pulling then
		target = math.min(target, math.abs(car.offNow - offT) < 1.2 and 0 or 14)
	end
	-- Blocked: honk at players, give up on things that won't move.
	if stuck then
		car.blockedSince = car.blockedSince or now
		local waited = now - car.blockedSince
		if obs and obs.player and waited > HONK_AFTER and now > (car.nextHonk or 0) and now > nextGlobalHonk then
			car.nextHonk = now + 5 + math.random() * 3
			nextGlobalHonk = now + 1.5
			honk(car)
		end
		if obs and waited > (GIVE_UP[obs.kind] or 10) then
			car.fading = now
		end
	else
		car.blockedSince = nil
	end
	local accel = target > car.speed and 14 or 40
	local before = car.speed
	car.speed += math.clamp(target - car.speed, -accel * dt, accel * dt)
	setBrakes(car, car.speed < before - 0.05 or (car.speed < 0.5 and target < 0.5))
	-- Sideways moves need forward motion (no crab-walking).
	local maxLat = (car.speed * 0.35 + 1.2) * dt
	car.offNow += math.clamp(offT - car.offNow, -maxLat, maxLat)
	car.t += car.speed * dt
	if car.t >= car.len then
		enterEdge(car, car.b, car.nextB, car.t - car.len)
		e = car.edge
	end
	-- Blend smoothly into the new lane position after a turn.
	local want = e.na + e.dir * car.t + e.right * car.offNow
	local newPos = car.pos:Lerp(want, math.clamp(dt * 8, 0, 1))
	local moved = newPos - car.pos
	if moved.Magnitude > 0.01 then
		car.heading = car.heading:Lerp(moved.Unit, math.clamp(dt * 10, 0, 1)).Unit
	end
	car.pos = newPos
end

local function step(dt)
	if not ready then
		return
	end
	local now = os.clock()
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	-- Recycle far, long-wrecked or faded cars; top up.
	for i = #cars, 1, -1 do
		local car = cars[i]
		local far = (Vector3.new(car.pos.X, 0, car.pos.Z) - flat).Magnitude > DESPAWN
		if far or (car.wrecked and now - car.wrecked > 2.8) or (car.fading and (now - car.fading > 0.9 or not onScreen(car.pos))) then
			removeCar(i)
		end
	end
	-- Performance mode (phone SETTINGS) keeps fewer cars around.
	local settings = script.Parent:FindFirstChild("SettingsClient")
	local perf = settings and require(settings).Get("Performance")
	local cap = perf and PERF_CARS or MAX_CARS
	if #cars < cap then
		spawnCar()
	elseif #cars > cap then
		-- Drop the farthest one.
		local worst, worstD = nil, -1
		for i, car in ipairs(cars) do
			local d = (car.pos - flat).Magnitude
			if d > worstD then
				worst, worstD = i, d
			end
		end
		if worst then
			removeCar(worst)
		end
	end

	if now - lastGather >= SCAN_STEP then
		lastGather = now
		gatherObstacles(now)
	end
	-- Fast player/AI cars this frame (the only ones that can ram).
	table.clear(fastList)
	for _, o in ipairs(obstacles) do
		if o.part and o.part.Parent and (o.vel.Magnitude > RAM_SPEED * 0.7 or o.part.AssemblyLinearVelocity.Magnitude > RAM_SPEED) then
			table.insert(fastList, o)
		end
	end

	table.clear(moveParts)
	table.clear(moveCFrames)
	local farSq = FAR_RANGE * FAR_RANGE
	for _, car in ipairs(cars) do
		if car.wrecked then
			local f = car.fly
			if f then
				local t = now - car.wrecked
				local pos = f.from.Position + f.vel * t + Vector3.new(0, -60, 0) * t * t
				pos = Vector3.new(pos.X, math.max(pos.Y, ROAD_TOP + 1), pos.Z)
				local rot = CFrame.Angles(f.spin.X * t, f.spin.Y * t, f.spin.Z * t)
				local cfw = CFrame.new(pos) * (f.from - f.from.Position) * rot
				local fade = math.clamp((t - 1.6) / 1, 0, 1)
				for _, rec in ipairs(car.body.parts) do
					table.insert(moveParts, rec.part)
					table.insert(moveCFrames, cfw * rec.offset)
					if fade > 0 then
						rec.part.LocalTransparencyModifier = fade
					end
				end
			end
			continue
		end
		if car.fading then
			local fade = math.clamp((now - car.fading) / 0.8, 0, 1)
			for _, rec in ipairs(car.body.parts) do
				rec.part.LocalTransparencyModifier = fade
			end
			continue
		end
		-- Far cars update at a lower rate.
		car.acc += dt
		local dx, dz = car.pos.X - flat.X, car.pos.Z - flat.Z
		if dx * dx + dz * dz > farSq and car.acc < FAR_STEP then
			continue
		end
		local stepDt = math.min(car.acc, 0.25)
		car.acc = 0
		drive(car, stepDt, now)
		local cf = CFrame.lookAt(car.pos, car.pos + car.heading) + Vector3.new(0, ROAD_TOP, 0)
		if #fastList > 0 then
			checkRam(car, cf + Vector3.new(0, 2, 0), fastList)
		end
		if not car.wrecked then
			for _, rec in ipairs(car.body.parts) do
				table.insert(moveParts, rec.part)
				table.insert(moveCFrames, cf * rec.offset)
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function TrafficClient.Count()
	return #cars
end

function TrafficClient.Cars()
	return cars
end

function TrafficClient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Traffic"
	folder.Parent = Workspace
	night = Workspace:GetAttribute("IsNight") == true
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		night = Workspace:GetAttribute("IsNight") == true
		for _, car in ipairs(cars) do
			setLights(car)
		end
	end)
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				local ok, err = pcall(buildGraph)
				if not ok then
					warn("[TrafficClient] " .. tostring(err))
				end
				ready = true
				return
			end
			task.wait(1)
		end
	end)
	local lastWarn = 0
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and os.clock() - lastWarn > 10 then
			lastWarn = os.clock()
			warn("[TrafficClient] " .. tostring(err))
		end
	end)
end

return TrafficClient
