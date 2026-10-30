-- RaceAIService (ModuleScript, ServerScriptService.Services.RaceAIService)
-- NPC racers for RaceService's street races. RaceService decides who races, counts their checkpoints
-- and ends the race; this file only builds the cars and drives them.
--   * One server-owned car each (ServerStorage.Tools.CarBuilder, parented to Workspace.Vehicles with the
--     network owner set to the server, like AIPoliceService's patrols: VehicleGuard never checks them).
--     Every prompt is taken out and the seats switched off, so nobody can get in. Attribute RaceBot.
--     Its name stands over the roof (BillboardGui "RacerName", always on top, out to NAME_DIST studs).
--   * The car is picked from K.CARS among those fast enough for the speed RaceService asks for (Top), a
--     different model for each NPC of a race while there are enough. CarPhysics.Step drives it on every
--     Heartbeat (the same arcade car the players drive) with SpeedScale holding it to Top (x the pace
--     RaceService sets for catching up / easing off).
--   * The way: RaceAIService.Plan works out each leg of the race once (start to checkpoint 1, 1 to 2,
--     ...) along the road graph, from the nearest POINT of the nearest road (not a crossing, so a leg
--     never starts with a trip back to a crossing), kept per race. The car follows the leg to its next
--     checkpoint and the one after it, moved Lane studs right of the line (each NPC its own lane, so they
--     don't all fight over one line). It steers at a point a little way along the line (further the
--     faster it goes) and brakes in time for every bend in the next SLOW_AHEAD studs (sharper = slower).
--   * Trouble: stuck (slow for STUCK_AFTER s on the throttle) -> reverse and turn; stuck RECOVER_STUCKS
--     times in RECOVER_WINDOW s, sunk, or off the line for OFF_FOR s twice in a row -> put back on its
--     line at the last point it reached (never ahead of where it was); upside down -> flipped back.
--   * A car that errors stops (RaceService sees Position() return nil and takes it out of the race).
-- API (RaceService):
--   RaceAIService.Plan(key, start, checkpoints) -> legs   (cached by key)
--   RaceAIService.Spawn{ CFrame, Name, Legs, Lane, Top, Avoid } -> bot { car, ... } (held still)
--   RaceAIService.Release(bot)       GO
--   RaceAIService.Target(bot, index) the next checkpoint is `index` (RaceService counted the last one)
--   RaceAIService.SetPace(bot, f)    x Top (catching up / easing off)
--   RaceAIService.Done(bot)          across the line: roll to a stop
--   RaceAIService.Position(bot) -> Vector3, or nil once it is gone or broken
--   RaceAIService.Remove(bot)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage.Shared.Util.CarPhysics)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)

local RaceAIService = {}

local K = {
	-- Looks and speeds vary (all quick enough for most players' cars; Top picks among them).
	CARS = { "Voltline", "NightHeron", "Flamingo", "SolanaGT", "SilverEgret", "AlbatrossGT", "Riptide", "StormPetrel" },
	ROAD_SNAP = 20, -- studs: a leg's end this close to the road line is taken onto it (lane-offset checkpoints)
	REACH = 18, -- studs: a point of the line this close counts as reached
	LOOK_MIN = 14, -- studs ahead along the line the car steers at...
	LOOK_MAX = 48,
	LOOK_TIME = 0.35, -- ...seconds of travel, between those two
	STEER_GAIN = 2.2,
	BRAKE_SHARE = 0.75, -- share of the car's Brake counted on when slowing for a bend
	CORNER_FREE = 14, -- degrees: gentler bends are taken flat out
	CORNER_SLOW = 28, -- studs/s through a hairpin (a right angle comes out near 47)
	SLOW_AHEAD = 320, -- studs of line looked at for bends
	STUCK_AFTER = 1.5,
	REVERSE_FOR = 1.2,
	RECOVER_STUCKS = 4,
	RECOVER_WINDOW = 20,
	UPSIDE_AFTER = 2,
	OFF_PATH = 90, -- studs off the line...
	OFF_FOR = 3, -- ...for this long: plan again from where it is
	SINK_Y = -4, -- below this it is in the water (or falling out of the world)
	SPAWN_Y = 3.2,
	NAME_DIST = 450,
	NAME_FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
}

local S = {
	bots = {},
	legs = {}, -- [key] = legs (RaceAIService.Plan)
	rng = Random.new(),
	started = false,
	CarBuilder = nil, -- required on the first spawn
}

local GOAL = 0 -- a made-up node id for the goal point in roadPath (real ids start at 1)

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Every point moved `by` studs to the right of the way the line runs (point for point).
local function offset(points, by)
	if not by or by == 0 then
		return points
	end
	local out = {}
	for i, p in ipairs(points) do
		local d = (points[i + 1] or p) - (points[i - 1] or p)
		-- (-dz, 0, dx) is the right-hand side of travel along d.
		out[i] = d.Magnitude > 0.01 and (p + Vector3.new(-d.Z, 0, d.X).Unit * by) or p
	end
	return out
end

-- The road stretch (two linked crossings) nearest `pos`, the nearest point on it and how far that is.
local function nearestEdge(pos)
	local nodes = RoadGraph.Nodes
	local bi, bj, bp, bd
	for i, links in pairs(RoadGraph.Edges) do
		local a = nodes[i]
		if a then
			for j in pairs(links) do
				local b = nodes[j]
				if b and j > i then
					local ab = b - a
					local len2 = ab:Dot(ab)
					local t = len2 > 0 and math.clamp((pos - a):Dot(ab) / len2, 0, 1) or 0
					local p = a + ab * t
					local d = (pos - p).Magnitude
					if not bd or d < bd then
						bi, bj, bp, bd = i, j, p, d
					end
				end
			end
		end
	end
	return bi, bj, bp, bd
end

-- A* along the roads between two flat positions, from the nearest point of the nearest road to the one
-- by the goal (the way GPSClient.RoadRoute does it on the client). Returns the line, or nil.
local function roadPath(from, to)
	local si, sj, sp, startOff = nearestEdge(from)
	local gi, gj, gp, goalOff = nearestEdge(to)
	if not si or not gi then
		return nil
	end
	local nodes, edges = RoadGraph.Nodes, RoadGraph.Edges
	local open, came, g, f = {}, {}, {}, {}
	for _, n in ipairs({ si, sj }) do
		g[n] = (nodes[n] - sp).Magnitude
		f[n] = g[n] + (nodes[n] - gp).Magnitude
		open[n] = true
	end
	if (si == gi and sj == gj) or (si == gj and sj == gi) then
		g[GOAL] = (sp - gp).Magnitude -- start and goal on one stretch: straight along it
		f[GOAL] = g[GOAL]
		open[GOAL] = true
	end
	local steps = 0
	while next(open) do
		steps += 1
		if steps > 5000 then
			return nil
		end
		local current, bestF
		for n in pairs(open) do
			if not bestF or f[n] < bestF then
				current, bestF = n, f[n]
			end
		end
		if current == GOAL then
			local out = {}
			local function push(p)
				if not out[#out] or (p - out[#out]).Magnitude > 3 then
					table.insert(out, p)
				end
			end
			if startOff > K.ROAD_SNAP then
				push(from)
			end
			push(sp)
			local chain = {}
			local n = came[GOAL]
			while n do
				table.insert(chain, n)
				n = came[n]
			end
			for i = #chain, 1, -1 do
				push(nodes[chain[i]])
			end
			push(gp)
			if goalOff > K.ROAD_SNAP then
				push(to)
			end
			return out
		end
		open[current] = nil
		if current == gi or current == gj then
			local tentative = g[current] + (nodes[current] - gp).Magnitude
			if not g[GOAL] or tentative < g[GOAL] then
				came[GOAL] = current
				g[GOAL] = tentative
				f[GOAL] = tentative
				open[GOAL] = true
			end
		end
		for nb, len in pairs(edges[current] or {}) do
			local tentative = g[current] + len
			if nodes[nb] and (not g[nb] or tentative < g[nb]) then
				came[nb] = current
				g[nb] = tentative
				f[nb] = tentative + (nodes[nb] - gp).Magnitude
				open[nb] = true
			end
		end
	end
	return nil
end

-- The car's line from its next checkpoint's leg on through the one after it (see the header).
local function loadPath(bot)
	local raw = {}
	for k = bot.index, math.min(bot.index + 1, #bot.legs) do
		for _, p in ipairs(bot.legs[k]) do
			if not raw[#raw] or (p - raw[#raw]).Magnitude > 3 then
				table.insert(raw, p)
			end
		end
	end
	bot.path = offset(raw, bot.lane)
	bot.seg = 1
	bot.offFor = 0
end

-- Pick a model fast enough for `top` (not one in `avoid` while there is another); the fastest else.
local function pickCar(top, avoid)
	local fits, any = {}, {}
	local fastest, fastestSpeed = nil, -1
	for _, id in ipairs(K.CARS) do
		local cfg = Vehicles.ById[id]
		if cfg then
			local v = cfg.MaxSpeed or 0
			if v >= top then
				table.insert(any, id)
				if not (avoid and avoid[id]) then
					table.insert(fits, id)
				end
			end
			if v > fastestSpeed then
				fastest, fastestSpeed = id, v
			end
		end
	end
	-- The slowest that still reaches `top` (a faster one would out-accelerate and out-corner the
	-- players it's meant to race a little under); among equals, any.
	local list = #fits > 0 and fits or any
	local slowest, slowSpeed, same = nil, math.huge, {}
	for _, id in ipairs(list) do
		local v = Vehicles.ById[id].MaxSpeed or 0
		if v < slowSpeed then
			slowest, slowSpeed, same = id, v, { id }
		elseif v == slowSpeed then
			table.insert(same, id)
		end
	end
	if slowest then
		return same[S.rng:NextInteger(1, #same)]
	end
	return fastest or "Palmetto"
end

local function addName(chassis, name)
	local board = Instance.new("BillboardGui")
	board.Name = "RacerName"
	board.Size = UDim2.fromOffset(140, 28)
	board.StudsOffset = Vector3.new(0, 6, 0)
	board.AlwaysOnTop = true
	board.MaxDistance = K.NAME_DIST
	board.LightInfluence = 0
	board.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = K.NAME_FONT
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.Text = name
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.new(0, 0, 0)
	edge.Thickness = 1.5
	edge.Transparency = 0.45
	edge.Parent = label
	label.Parent = board
	board.Adornee = chassis
	board.Parent = chassis
end

local function stopStill(chassis)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
end

-- Is there room for a car at `cf` (only what a car would hit counts)?
local function roomAt(bot, cf)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.car }
	pcall(function()
		params.RespectCanCollide = true
	end)
	pcall(function()
		params.CollisionGroup = "Vehicles"
	end)
	return #Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.6, 0), Vector3.new(8, 4, 17), params) == 0
end

-- Back on its line at the last point it reached, facing along it (see the header). Waits (does nothing)
-- while somebody stands on that spot: it is tried again on the next frame.
local function recover(bot)
	local path = bot.path
	local i = math.clamp(bot.seg - 1, 1, math.max(1, #path))
	local p = path[i]
	if not p then
		return
	end
	local q = path[i + 1] or (path[i - 1] and (p + (p - path[i - 1]))) or (p + Vector3.zAxis)
	local at = Vector3.new(p.X, K.SPAWN_Y, p.Z)
	local look = Vector3.new(q.X, K.SPAWN_Y, q.Z)
	if (look - at).Magnitude < 0.1 then
		look = at + Vector3.zAxis
	end
	local cf = CFrame.lookAt(at, look)
	if not roomAt(bot, cf) then
		return
	end
	bot.car:PivotTo(cf)
	stopStill(bot.chassis)
	bot.seg = i
	bot.stuckFor, bot.upsideFor, bot.offFor, bot.reverseUntil = 0, 0, 0, 0
	table.clear(bot.stucks)
end

-- Plan the way again from where the car is (it left its line): to its next checkpoint, then on.
local function replan(bot, here)
	local leg = bot.legs[bot.index]
	local goal = leg and leg[#leg]
	if not goal then
		return
	end
	local way = roadPath(here, goal)
	if not way or #way < 2 then
		bot.offTwice = true
		return
	end
	local raw = way
	local nextLeg = bot.legs[bot.index + 1]
	if nextLeg then
		raw = table.clone(way)
		for _, p in ipairs(nextLeg) do
			if (p - raw[#raw]).Magnitude > 3 then
				table.insert(raw, p)
			end
		end
	end
	bot.path = offset(raw, bot.lane)
	bot.seg = 1
end

-- The point `dist` studs along the line from the car (it steers at it).
local function aimPoint(path, seg, here, dist)
	local p = path[seg]
	if not p then
		-- Past the end of its line (RaceService is about to count the checkpoint): straight on.
		local a, b = path[#path - 1], path[#path]
		if a and b and (b - a).Magnitude > 0.1 then
			return b + (b - a).Unit * 60
		end
		return b or here
	end
	local left = dist - (p - here).Magnitude
	local j = seg
	while left > 0 and path[j + 1] do
		local stretch = (path[j + 1] - path[j]).Magnitude
		if stretch >= left then
			return path[j] + (path[j + 1] - path[j]) * (left / stretch)
		end
		left -= stretch
		j += 1
	end
	return path[j]
end

-- How fast a bend of `deg` degrees can be taken (vmax: the car's top speed).
local function cornerSpeed(deg, vmax)
	local f = math.clamp((180 - deg) / (180 - K.CORNER_FREE), 0, 1)
	return K.CORNER_SLOW + math.max(0, vmax - K.CORNER_SLOW) * f * f * f
end

-- The fastest the car may go now and still slow down in time for every bend ahead.
local function cornerLimit(bot, path, here)
	local limit = math.huge
	local decel = (bot.car:GetAttribute("Brake") or 120) * K.BRAKE_SHARE
	local travelled = 0
	local prev = here
	for j = bot.seg, #path - 1 do
		local p = path[j]
		travelled += (p - prev).Magnitude
		if travelled > K.SLOW_AHEAD then
			break
		end
		local a = p - (path[j - 1] or here)
		local b = path[j + 1] - p
		if a.Magnitude > 1 and b.Magnitude > 1 then
			local deg = math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
			if deg > K.CORNER_FREE then
				local v = cornerSpeed(deg, bot.maxSpeed)
				limit = math.min(limit, math.sqrt(v * v + 2 * decel * travelled))
			end
		end
		prev = p
	end
	return limit
end

-- Studs from the car to its line around where it is on it.
local function offLine(path, seg, here)
	local best = math.huge
	for j = math.max(1, seg - 1), math.min(#path - 1, seg + 1) do
		local a, b = path[j], path[j + 1]
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = len2 > 0 and math.clamp((here - a):Dot(ab) / len2, 0, 1) or 0
		best = math.min(best, (here - (a + ab * t)).Magnitude)
	end
	if best == math.huge then
		local p = path[seg] or path[#path]
		best = p and (here - p).Magnitude or 0
	end
	return best
end

local function drive(bot, dt, now)
	if bot.held or bot.removed or bot.failed then
		return
	end
	local car, chassis = bot.car, bot.chassis
	if not car.Parent or not chassis.Parent then
		bot.failed = true
		return
	end
	local pos = chassis.Position
	if pos.Y < K.SINK_Y then
		recover(bot)
		return
	end
	local cf = chassis.CFrame
	local here = flat(pos)
	local speed = chassis.AssemblyLinearVelocity:Dot(cf.LookVector)
	if bot.done then
		CarPhysics.Step(bot.phys, dt, { Throttle = speed > 2 and -0.7 or 0, Steer = 0, SpeedScale = 1 })
		return
	end

	-- Along the line: past every point reached or driven by (projected onto the stretch leading to it).
	local path = bot.path
	while path[bot.seg] do
		local p = path[bot.seg]
		local q = path[bot.seg - 1]
		local passed
		if q then
			local d = p - q
			local len2 = d:Dot(d)
			passed = len2 > 1 and (here - q):Dot(d) >= len2
		else
			local n = path[bot.seg + 1]
			passed = n ~= nil and (here - p):Dot(n - p) > 0
		end
		if passed or (here - p).Magnitude < K.REACH then
			bot.seg += 1
		else
			break
		end
	end

	-- Speed: the pace asked for, held down for the bends ahead.
	local top = bot.top * bot.pace
	local target = math.min(top, cornerLimit(bot, path, here))
	local throttle = 1
	if speed > target + 6 then
		throttle = -1
	elseif speed > target then
		throttle = 0
	end

	-- Steering, the way AIPoliceService steers.
	local aim = aimPoint(path, bot.seg, here, math.clamp(math.abs(speed) * K.LOOK_TIME, K.LOOK_MIN, K.LOOK_MAX))
	local dir = aim - here
	local look = flat(cf.LookVector)
	local right = flat(cf.RightVector)
	local angle = 0
	if dir.Magnitude > 0.1 and look.Magnitude > 0.1 and right.Magnitude > 0.1 then
		dir, look, right = dir.Unit, look.Unit, right.Unit
		angle = math.atan2(dir:Dot(right), dir:Dot(look))
	end
	local steer = math.clamp(angle * K.STEER_GAIN, -1, 1)
	if math.abs(angle) > 1.2 and speed > 45 then
		throttle = math.min(throttle, -0.4) -- way off its heading at speed: slow for the turn
	end
	if math.abs(angle) > 2.4 and speed < 20 then
		throttle, steer = -0.8, -steer -- the line is behind it: back up while turning
	end

	-- Stuck? Back up for a moment; stuck again and again: put it back on its line.
	if now < bot.reverseUntil then
		throttle, steer = -1, bot.reverseSteer
	elseif throttle > 0.5 and math.abs(speed) < 3 then
		bot.stuckFor += dt
		if bot.stuckFor > K.STUCK_AFTER then
			bot.stuckFor = 0
			bot.reverseUntil = now + K.REVERSE_FOR
			bot.reverseSteer = angle > 0 and -1 or 1
			table.insert(bot.stucks, now)
			while bot.stucks[1] and now - bot.stucks[1] > K.RECOVER_WINDOW do
				table.remove(bot.stucks, 1)
			end
			if #bot.stucks >= K.RECOVER_STUCKS then
				recover(bot)
				return
			end
		end
	else
		bot.stuckFor = 0
	end

	-- Upside down? Put it back on its wheels.
	if cf.UpVector.Y < 0.3 then
		bot.upsideFor += dt
		if bot.upsideFor > K.UPSIDE_AFTER then
			bot.upsideFor = 0
			local fwd = flat(cf.LookVector)
			fwd = fwd.Magnitude > 0.1 and fwd.Unit or Vector3.new(0, 0, -1)
			local up = pos + Vector3.new(0, 4, 0)
			car:PivotTo(CFrame.lookAt(up, up + fwd))
			stopStill(chassis)
			return
		end
	else
		bot.upsideFor = 0
	end

	-- Off its line for a while (shoved off, a missed turn): plan again from here, or put it back.
	if offLine(path, bot.seg, here) > K.OFF_PATH then
		bot.offFor += dt
		if bot.offFor > K.OFF_FOR then
			bot.offFor = 0
			if bot.offTwice then
				bot.offTwice = false
				recover(bot)
				return
			end
			bot.offTwice = true
			replan(bot, here)
		end
	else
		bot.offFor = 0
		bot.offTwice = false
	end

	CarPhysics.Step(bot.phys, dt, { Throttle = throttle, Steer = steer, SpeedScale = math.min(1, top / bot.maxSpeed) })
end

------------------------------------------------------------------ API

function RaceAIService.Plan(key, start, checkpoints)
	if key and S.legs[key] then
		return S.legs[key]
	end
	local legs = {}
	local prev = flat(start)
	for k, cp in ipairs(checkpoints) do
		local to = flat(cp)
		local leg = roadPath(prev, to)
		if not leg or #leg < 2 then
			leg = { prev, to } -- no road graph (or no way): straight there
		end
		legs[k] = leg
		prev = to
	end
	if key then
		S.legs[key] = legs
	end
	return legs
end

function RaceAIService.Spawn(spec)
	if not S.started then
		RaceAIService.Init() -- (normally Main starts us; never drive nobody)
	end
	S.CarBuilder = S.CarBuilder or require(ServerStorage.Tools.CarBuilder)
	local id = pickCar(spec.Top or 120, spec.Avoid)
	if spec.Avoid then
		spec.Avoid[id] = true
	end
	local ok, car = pcall(S.CarBuilder.Build, id)
	if not ok or typeof(car) ~= "Instance" or not car.PrimaryPart then
		warn("[RaceAIService] couldn't build " .. tostring(id) .. ": " .. tostring(car))
		return nil
	end
	local made, bot = pcall(function()
		car.Name = "RaceBot"
		car:SetAttribute("RaceBot", true)
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				d:Destroy()
			elseif d:IsA("Seat") or d:IsA("VehicleSeat") then
				d.Disabled = true
			end
		end
		local chassis = car.PrimaryPart
		car:PivotTo(spec.CFrame)
		addName(chassis, spec.Name or "RACER")
		car.Parent = Workspace:FindFirstChild("Vehicles") or Workspace
		pcall(function()
			chassis:SetNetworkOwner(nil)
		end)
		chassis.Anchored = true -- held for the countdown (Release)
		local maxSpeed = car:GetAttribute("MaxSpeed") or 120
		local fresh = {
			car = car,
			chassis = chassis,
			phys = CarPhysics.New(car, {}),
			name = spec.Name,
			legs = spec.Legs,
			index = 1,
			lane = spec.Lane or 0,
			maxSpeed = maxSpeed,
			top = math.min(spec.Top or maxSpeed, maxSpeed),
			pace = 1,
			held = true,
			done = false,
			stuckFor = 0,
			reverseUntil = 0,
			reverseSteer = 0,
			upsideFor = 0,
			offFor = 0,
			offTwice = false,
			stucks = {},
		}
		loadPath(fresh)
		return fresh
	end)
	if not made then
		warn("[RaceAIService] couldn't set up " .. tostring(id) .. ": " .. tostring(bot))
		car:Destroy() -- (never leave a half-made car standing on the grid)
		return nil
	end
	table.insert(S.bots, bot)
	return bot
end

function RaceAIService.Release(bot)
	if bot.removed then
		return
	end
	bot.held = false
	local chassis = bot.chassis
	if chassis.Parent then
		chassis.Anchored = false
		pcall(function()
			chassis:SetNetworkOwner(nil)
		end)
	end
end

function RaceAIService.Target(bot, index)
	if bot.removed or index == bot.index or not bot.legs[index] then
		return
	end
	bot.index = index
	loadPath(bot)
end

function RaceAIService.SetPace(bot, f)
	bot.pace = math.clamp(tonumber(f) or 1, 0.5, 1.5)
end

function RaceAIService.Done(bot)
	bot.done = true
end

function RaceAIService.Position(bot)
	if bot.removed or bot.failed then
		return nil
	end
	local chassis = bot.chassis
	if not chassis or not chassis.Parent or not bot.car.Parent then
		return nil
	end
	return chassis.Position
end

function RaceAIService.Remove(bot)
	if bot.removed then
		return
	end
	bot.removed = true
	local i = table.find(S.bots, bot)
	if i then
		table.remove(S.bots, i)
	end
	pcall(CarPhysics.Zero, bot.phys)
	if bot.car then
		bot.car:Destroy()
	end
end

function RaceAIService.Count()
	return #S.bots
end

function RaceAIService.Init()
	if S.started then
		return
	end
	S.started = true
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for i = #S.bots, 1, -1 do
			local bot = S.bots[i]
			if bot and not bot.failed then
				local ok, err = pcall(drive, bot, dt, now)
				if not ok then
					bot.failed = true -- (RaceService sees Position() go nil and takes it out)
					warn("[RaceAIService] " .. tostring(bot.name) .. ": " .. tostring(err))
					pcall(CarPhysics.Zero, bot.phys)
				end
			end
		end
	end)
end

return RaceAIService
