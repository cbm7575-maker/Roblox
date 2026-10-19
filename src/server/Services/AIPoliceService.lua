-- AIPoliceService (ModuleScript, ServerScriptService.Services.AIPoliceService)
-- The AI police: pursuit units for wanted players, ambient patrol cars and roadblocks. Tunables live
-- in Config.Police.
--   * Dispatch: per wanted player, UnitsByHeat[heat] units minus the player cops already engaged (near
--     them or saw them in the last 20 s; HeatService.EngagedCops), at least 1 at 3+ stars when no cop is
--     engaged. MaxTotal caps every AI car in the server, patrols included; pursuits come first. A free
--     patrol nearby answers the call; otherwise a car spawns on a road 250-450 studs from the last-seen
--     spot, out of the suspect's sight and with room for it.
--   * They only know what the police know (HeatService): while any eye sees the suspect they chase the
--     real position, each unit with its own approach (lead / flank / cut-off), so no single-file convoy;
--     while unseen they drive to the last-seen spot, then search the roads inside the search circle.
--   * Patrols: up to Config.Police.Patrols cars cruise the roads near players at 60% speed, no siren, no
--     AITarget. They are cop eyes; one that sees a wanted player joins the chase instead of a new car.
--     Patrols exist only within ~700 studs of a player and spawn out of sight, away from spawn points.
--   * Roadblocks at 4+ stars (seen recently, about every 25 s): two parked police cars angled across a
--     road 350-500 studs ahead, out of the suspect's sight, a 10-stud gap with a spike strip. Each is a
--     Model with a PrimaryPart ("Zone", covers the block) in Workspace.Roadblocks; they are eyes; gone
--     after 30 s, or when the suspect is far away or no longer wanted. At most 2 per server.
--   * Driving: road paths with braking before corners (one waypoint of look-ahead); never faster than
--     95% of the suspect's car; stuck -> reverse and turn; upside down -> flipped back.
--   * Arrest: a wanted player who stays (nearly) stopped within 22 studs, within 6 studs of height and in
--     the unit's own sight, for about 3 seconds. They park a car length away instead of shoving.
--   * Tutorial chaser (player attribute TutorialChase = true): exactly one gentle unit, even with cops
--     online: spawns 150-250 studs away out of sight, 85% of the player's top speed, no arrest for its
--     first 25 s, no roadblocks.
--   * Wrecked (car Health 0, VehicleDamageService): the unit drops the chase and limps off; dispatch
--     sends a fresh car from out of sight if one is still needed. Ramming a cruiser buys real time.
--   * Cars leave only when no player can see them (or nobody is near).
-- Server-owned physics (CarPhysics) so VehicleGuard never checks them.
-- API: AIPoliceService.Count() -> number of AI police cars.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage.Shared.Util.CarPhysics)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Police = require(ReplicatedStorage.Shared.Config.Police)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)
local HeatService = require(ServerScriptService.Services.HeatService)

local AIPoliceService = {}

local CAR_ID = "SunrayPatrol"
local CAR_SIZE = (Vehicles.ById[CAR_ID] and Vehicles.ById[CAR_ID].Size) or Vector3.new(7.2, 1.8, 13.5)
local SPAWN_Y = 3.2 -- chassis height above the road for a fresh car
local SAMPLE_SPACING = 60 -- road sample spacing for spawn and search spots
local SLOT_LEAD = { 0, 1.5, 3, 5 } -- seconds of lead per approach slot (road chase)
local SLOT_SIDE = { 0, -9, 9, 0 } -- studs of flank per approach slot (close chase)
local CONVERT_CHECK = 0.3 -- seconds between a patrol's "do I see a wanted player?" checks
local RB = Police.Roadblock

local units = {} -- list of unit tables (see newUnit)
local lastSpawnFor = {} -- [player] = os.clock()
local lastPatrolSpawn = 0
local wantCache = {} -- [player] = units wanted (from the last manage)
local roadblocks = {} -- list of { model, zone, strip, target, expires, pos }
local lastRoadblockFor = {} -- [player] = os.clock()
local avoidPoints = {} -- spawn points, pads, the hideout: no patrol spawns or roadblocks near them
local playerSpots = {} -- refreshed every manage: { { player, pos, side } } for living players
local roadblockFolder
local rng = Random.new()

-- Sight lines (walls block; cars, characters and roadblocks don't) and spawn room checks.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true
local spaceParams = OverlapParams.new()
spaceParams.FilterType = Enum.RaycastFilterType.Include
local busyParams = OverlapParams.new() -- cars and people only (roadblock spots)
busyParams.FilterType = Enum.RaycastFilterType.Include
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function wanted(p)
	return p.Parent == Players and p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) > 0
end

local function isTutorial(p)
	return p:GetAttribute("TutorialChase") == true
end

local function targetInfo(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	local seat = hum.SeatPart
	local car = seat and seat.Parent
	local chassis = car and car:IsA("Model") and car.PrimaryPart
	if chassis then
		return { pos = chassis.Position, vel = chassis.AssemblyLinearVelocity, maxSpeed = car:GetAttribute("MaxSpeed") or 120, inCar = true,
			boat = car:GetAttribute("Boat") == true, head = root.Position }
	end
	return { pos = root.Position, vel = root.AssemblyLinearVelocity, maxSpeed = 120, inCar = false, boat = false, head = root.Position }
end

-- Corner speed (studs/s) for a turn of `turn` radians between the road in and the road out.
local function cornerSpeed(turn)
	local deg = math.deg(turn)
	if deg < 15 then
		return math.huge
	elseif deg <= 90 then
		return 40 + (90 - deg) * 1.2
	end
	return math.max(22, 40 - (deg - 90) * 0.2)
end

-- The fastest we may go now and still slow to `vc` within `dist` studs, braking at `decel`.
local function allowedSpeed(vc, dist, decel)
	if vc == math.huge then
		return math.huge
	end
	return math.sqrt(vc * vc + 2 * decel * math.max(0, dist))
end

local function turnAngle(a, b)
	local fa, fb = flat(a), flat(b)
	if fa.Magnitude < 1 or fb.Magnitude < 1 then
		return 0
	end
	return math.acos(math.clamp(fa.Unit:Dot(fb.Unit), -1, 1))
end

-- Skip waypoints we've reached, or already passed: a car between two nodes doesn't go back to a node
-- behind it (`look` = its flat heading) when the route carries on along the road it's on.
local function advance(path, idx, pos, reach, look)
	while path[idx] do
		local w = path[idx]
		if flatDist(w, pos) < reach then
			idx += 1
			continue
		end
		local nxt = path[idx + 1]
		if nxt and look and (w.X - pos.X) * look.X + (w.Z - pos.Z) * look.Z < 0 then
			local sx, sz = nxt.X - w.X, nxt.Z - w.Z
			local len2 = sx * sx + sz * sz
			if len2 > 1 then
				local t = ((pos.X - w.X) * sx + (pos.Z - w.Z) * sz) / len2
				if t > 0 and t < 1 then
					local qx, qz = w.X + sx * t, w.Z + sz * t
					if (pos.X - qx) ^ 2 + (pos.Z - qz) ^ 2 < 900 then
						idx += 1
						continue
					end
				end
			end
		end
		break
	end
	return idx
end

-- How close to a waypoint counts as reached (where the car turns in): later for slow, sharp corners.
local function reachFor(pos, wp, wi, speed)
	local w, nxt = wp[wi], wp[wi + 1]
	local v = math.abs(speed)
	if w and nxt then
		v = math.min(v, cornerSpeed(turnAngle(w - pos, nxt - w)))
	end
	return math.clamp(v * 0.6, 14, 40)
end

-- Speed limit from the next two corners on the way (one waypoint of look-ahead), plus the final goal.
local function cornerLimit(pos, wp, wi, goal, decel)
	local pts = {}
	for k = wi, wi + 2 do
		if wp[k] then
			table.insert(pts, wp[k])
		end
	end
	if goal and #pts < 3 and (#pts == 0 or flatDist(pts[#pts], goal) > 5) then
		table.insert(pts, goal)
	end
	local limit = math.huge
	local travelled = 0
	local from = pos
	for k = 1, math.min(#pts - 1, 2) do
		travelled += flatDist(from, pts[k])
		local vc = cornerSpeed(turnAngle(pts[k] - from, pts[k + 1] - pts[k]))
		if vc < math.huge then
			-- Be at corner speed where the car turns in (see advance's reach), not at the crossing.
			limit = math.min(limit, allowedSpeed(vc, travelled - math.clamp(vc * 0.6, 14, 40) - 4, decel))
		end
		from = pts[k]
	end
	return limit
end

------------------------------------------------------------------------------------------------------
-- World checks

local function addIf(list, x)
	if x then
		table.insert(list, x)
	end
end

local function refreshWorld()
	local vehicles = Workspace:FindFirstChild("Vehicles")
	local exclude, include, busy = {}, {}, {}
	addIf(exclude, vehicles)
	addIf(exclude, roadblockFolder)
	addIf(include, vehicles)
	addIf(include, roadblockFolder)
	addIf(busy, vehicles)
	local city = Workspace:FindFirstChild("City")
	for _, name in ipairs({ "Buildings", "Art", "Landmarks" }) do
		addIf(include, city and city:FindFirstChild(name))
	end
	table.clear(playerSpots)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			table.insert(exclude, char)
			table.insert(include, char)
			table.insert(busy, char)
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				table.insert(playerSpots, { player = p, pos = root.Position, side = p:GetAttribute("Side") })
			end
		end
	end
	sightParams.FilterDescendantsInstances = exclude
	spaceParams.FilterDescendantsInstances = include
	busyParams.FilterDescendantsInstances = busy
	local ground = {}
	addIf(ground, city and city:FindFirstChild("Roads"))
	addIf(ground, city and city:FindFirstChild("Ground"))
	groundParams.FilterDescendantsInstances = ground
end

-- VehicleDamageService (optional): told about our own server moves so they don't read as crashes.
local function damageSkip(car, seconds)
	local module = ServerScriptService.Services:FindFirstChild("VehicleDamageService")
	if module then
		local ok, service = pcall(require, module)
		if ok and type(service) == "table" and service.Skip then
			service.Skip(car, seconds)
		end
	end
end

local function lineClear(from, to)
	return Workspace:Raycast(from, to - from, sightParams) == nil
end

-- Can any player within `range` see this spot?
local function seenByPlayers(pos, range)
	for _, s in ipairs(playerSpots) do
		if (s.pos - pos).Magnitude < range and lineClear(s.pos + Vector3.new(0, 2, 0), pos + Vector3.new(0, 2, 0)) then
			return true
		end
	end
	return false
end

-- Distance to the nearest player who isn't in prison.
local function nearestPlayerDist(pos)
	local best = math.huge
	for _, s in ipairs(playerSpots) do
		if s.side ~= "Prisoner" then
			best = math.min(best, flatDist(s.pos, pos))
		end
	end
	return best
end

local function nearAvoid(pos)
	for _, a in ipairs(avoidPoints) do
		if flatDist(a, pos) < Police.PatrolSpawnAvoid then
			return true
		end
	end
	return false
end

-- Room for a car here? (other cars, people, buildings; flat things under the wheels don't count)
local function spaceClear(cf)
	local box = CAR_SIZE + Vector3.new(2, 4, 3)
	local bottom = cf.Position.Y - CAR_SIZE.Y / 2
	for _, part in ipairs(Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 1.5, 0), box, spaceParams)) do
		if part.Position.Y + part.Size.Y / 2 > bottom + 0.8 or part.Size.Y > 3 then
			return false
		end
	end
	return true
end

-- A road spot minR..maxR studs from `ref`: out of `target`'s sight (any range) and of every player
-- within VanishSight, with room for a car, in the right-hand lane facing along the road (toward
-- `faceToward` if given). Returns a CFrame or nil.
local function findSpot(ref, minR, maxR, target, faceToward, avoid)
	local list = RoadGraph.Within(ref, maxR, minR, SAMPLE_SPACING)
	if #list == 0 then
		return nil
	end
	local info = target and targetInfo(target)
	local eye = info and info.head + Vector3.new(0, 2, 0)
	for _ = 1, math.min(14, #list) do
		local s = list[rng:NextInteger(1, #list)]
		local dir = flat(s.dir)
		if dir.Magnitude > 0.1 then
			dir = dir.Unit
			if faceToward then
				if (faceToward - s.pos):Dot(dir) < 0 then
					dir = -dir
				end
			elseif rng:NextNumber() < 0.5 then
				dir = -dir
			end
			local right = dir:Cross(Vector3.yAxis)
			local pos = Vector3.new(s.pos.X, SPAWN_Y, s.pos.Z) + right * math.min(8, (s.width or 30) * 0.22)
			if not (avoid and nearAvoid(pos))
				and not (eye and lineClear(eye, pos + Vector3.new(0, 1, 0)))
				and not seenByPlayers(pos, Police.VanishSight) then
				local cf = CFrame.lookAt(pos, pos + dir)
				if spaceClear(cf) then
					return cf
				end
			end
		end
	end
	return nil
end

------------------------------------------------------------------------------------------------------
-- Units

local function unitsOf(p)
	local list = {}
	for _, u in ipairs(units) do
		if u.target == p then
			table.insert(list, u)
		end
	end
	return list
end

local function despawn(u)
	for i, x in ipairs(units) do
		if x == u then
			table.remove(units, i)
			break
		end
	end
	HeatService.UnregisterEye(u.chassis)
	if u.car.Parent then
		u.car:Destroy()
	end
end

local function canVanish(u)
	return not seenByPlayers(u.chassis.Position, Police.VanishSight)
end

-- Patrols wander the road graph: mostly straight on, drifting back toward players when far from all.
local function pickNext(prev, cur)
	local nodes = RoadGraph.Nodes
	local edges = RoadGraph.Edges[cur]
	if not edges then
		return cur
	end
	local inDir = prev and prev ~= cur and flat(nodes[cur] - nodes[prev])
	inDir = inDir and inDir.Magnitude > 1 and inDir.Unit or nil
	local options, total = {}, 0
	for nb in pairs(edges) do
		if nb ~= prev then
			local w = 1
			if inDir then
				local d = flat(nodes[nb] - nodes[cur])
				if d.Magnitude > 1 then
					w += math.max(0, d.Unit:Dot(inDir)) * 1.5
				end
			end
			if nearestPlayerDist(nodes[nb]) > Police.PatrolRange * 0.7 then
				w *= 0.25
			end
			table.insert(options, { nb, w })
			total += w
		end
	end
	if #options == 0 then
		return prev or cur -- dead end: turn around
	end
	local roll = rng:NextNumber() * total
	for _, o in ipairs(options) do
		roll -= o[2]
		if roll <= 0 then
			return o[1]
		end
	end
	return options[#options][1]
end

local function extendPatrol(u)
	local pr = u.patrol
	if not pr then
		return
	end
	if #pr.route == 0 then
		if not pr.prev then
			return
		end
		table.insert(pr.route, pickNext(nil, pr.prev)) -- passed every waypoint at once: carry on from here
	end
	while #pr.route < 3 do
		local last = pr.route[#pr.route]
		local before = pr.route[#pr.route - 1] or pr.prev
		table.insert(pr.route, pickNext(before, last))
	end
	local wp = {}
	for k, n in ipairs(pr.route) do
		wp[k] = RoadGraph.Nodes[n]
	end
	u.wp, u.wi, u.goal = wp, 1, nil
end

local function startPatrol(u)
	u.patrol = { route = {} }
	u.wp, u.wi, u.goal = nil, 1, nil
	local pos = u.chassis.Position
	local look = flat(u.chassis.CFrame.LookVector)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local i, j = RoadGraph.NearestEdge(pos, look)
	if not i or not j then
		return
	end
	local nodes = RoadGraph.Nodes
	local ahead, behind = j, i
	if (nodes[j] - nodes[i]):Dot(look) < 0 then
		ahead, behind = i, j
	end
	u.patrol = { prev = behind, route = { ahead } }
	extendPatrol(u)
end

local function freeSlot(p, except)
	local used = {}
	for _, x in ipairs(units) do
		if x ~= except and x.target == p and x.slot then
			used[x.slot] = true
		end
	end
	for s = 1, #SLOT_LEAD do
		if not used[s] then
			return s
		end
	end
	return 1
end

local function assign(u, p)
	u.slot = freeSlot(p, u)
	u.target = p
	u.leaving = nil
	u.patrol = nil
	u.stage, u.searchCenter, u.searchUntil = nil, nil, nil
	u.wp, u.wi, u.goal, u.plannedGoal = nil, 1, nil, nil
	u.repathAt = 0
	u.arrestFor = 0
	u.graceUntil = isTutorial(p) and os.clock() + Police.Tutorial.NoArrestSeconds or 0
	u.car:SetAttribute("AITarget", p.UserId)
end

local function release(u)
	u.target, u.slot = nil, nil
	u.car:SetAttribute("AITarget", nil)
	startPatrol(u)
end

local function newCar(cf)
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return nil
	end
	local car = CarBuilder.Build(CAR_ID)
	car.Name = "AIPatrol"
	car:SetAttribute("AIPolice", true)
	car:PivotTo(cf)
	for _, name in ipairs({ "DrivePrompt", "RidePrompt" }) do
		local prompt = car:FindFirstChild(name, true)
		if prompt then
			prompt:Destroy()
		end
	end
	car.Parent = folder
	car.PrimaryPart:SetNetworkOwner(nil)
	HeatService.RegisterEye(car.PrimaryPart)
	return car
end

local function newUnit(car, target)
	local now = os.clock()
	local u = {
		car = car,
		chassis = car.PrimaryPart,
		phys = CarPhysics.New(car, {}),
		spawnedAt = now,
		stuckFor = 0,
		reverseUntil = 0,
		reverseSteer = 0,
		upsideFor = 0,
		arrestFor = 0,
		graceUntil = 0,
		wi = 1,
		repathAt = 0,
		checkAt = 0,
		progressAt = now + 8,
		progressPos = car.PrimaryPart.Position,
		strikes = 0,
	}
	table.insert(units, u)
	if target then
		assign(u, target)
	else
		startPatrol(u)
	end
	return u
end

-- Plan a road route to `goal` (the last stretch to a goal beside the road goes straight at it).
local function planTo(u, goal, now)
	u.goal = goal
	u.plannedGoal = goal
	u.plannedAt = now
	u.repathAt = now + 1.5
	local path = RoadGraph.Path(u.chassis.Position, goal)
	if path and #path >= 2 then
		local a, b = path[#path - 1], path[#path]
		local sx, sz = b.X - a.X, b.Z - a.Z
		local len2 = sx * sx + sz * sz
		if len2 > 1 then
			local t = ((goal.X - a.X) * sx + (goal.Z - a.Z) * sz) / len2
			if t > 0 and t < 1 and (goal.X - (a.X + sx * t)) ^ 2 + (goal.Z - (a.Z + sz * t)) ^ 2 < 1600 then
				path[#path] = nil -- the goal is on the last road: don't drive past it to the far crossing
			end
		end
	end
	u.wp, u.wi = path, 1
end

-- Where a chasing unit heads on the roads: the suspect, or a point ahead of them (cut-off slots).
local function chaseGoal(u, info)
	local lead = flat(info.vel) * (SLOT_LEAD[u.slot or 1] or 0)
	if lead.Magnitude > 300 then
		lead = lead.Unit * 300
	end
	return flat(info.pos) + lead
end

-- Close-in aim: lead a moving target, each slot from its own side.
local function directAim(u, info, pos, dist)
	local v = flat(info.vel)
	local aim = info.pos + v * math.clamp(dist / 150, 0, 0.8)
	local side = SLOT_SIDE[u.slot or 1] or 0
	if side ~= 0 then
		local basis = v.Magnitude > 5 and v.Unit or flat(info.pos - pos)
		if basis.Magnitude > 0.1 then
			basis = basis.Unit
			aim += Vector3.new(-basis.Z, 0, basis.X) * side * math.clamp((dist - 25) / 80, 0, 1)
		end
	end
	if u.slot == 4 then
		aim += v * 0.6
	end
	return aim
end

-- A road spot inside the search circle, not right here and not where another unit is going.
local function searchPoint(u, center, radius, pos)
	local list = RoadGraph.Within(center, radius, 0, SAMPLE_SPACING)
	if #list == 0 then
		return center
	end
	local best, bestScore
	for _ = 1, math.min(6, #list) do
		local s = list[rng:NextInteger(1, #list)]
		local score = math.abs(flatDist(s.pos, pos) - 160)
		for _, x in ipairs(units) do
			if x ~= u and x.target == u.target and x.goal and flatDist(x.goal, s.pos) < 90 then
				score += 250
			end
		end
		if not bestScore or score < bestScore then
			best, bestScore = s.pos, score
		end
	end
	return best or center
end

-- A patrol that sees a wanted player joins the chase (or takes over from a unit much farther away).
local function tryJoin(u, q)
	local info = targetInfo(q)
	if not info or info.boat then
		return false
	end
	local mine = unitsOf(q)
	if #mine < (wantCache[q] or 0) then
		assign(u, q)
		return true
	end
	local myD = flatDist(info.pos, u.chassis.Position)
	local far, farD
	for _, x in ipairs(mine) do
		local d = flatDist(info.pos, x.chassis.Position)
		if not farD or d > farD then
			far, farD = x, d
		end
	end
	if far and farD > math.max(300, myD * 2) then
		release(far)
		assign(u, q)
		return true
	end
	return false
end

local function update(u, dt, now)
	local car, chassis = u.car, u.chassis
	if not car.Parent or not chassis.Parent then
		despawn(u)
		return
	end
	local pos = chassis.Position
	if pos.Y < 0.2 then
		despawn(u) -- drove into water or fell out of the world
		return
	end
	local cf = chassis.CFrame
	local look = flat(cf.LookVector)
	local right = flat(cf.RightVector)
	local speed = chassis.AssemblyLinearVelocity:Dot(cf.LookVector)
	local carMax = car:GetAttribute("MaxSpeed") or 135
	local decel = (car:GetAttribute("Brake") or 120) * 0.7

	-- Wrecked? Drop the chase and limp away (a fresh car comes if one is still needed).
	if (car:GetAttribute("Health") or 100) <= 0 and not u.leaving then
		if u.target then
			release(u)
		end
		u.leaving = now
	end

	-- Still a valid target?
	local p = u.target
	local info
	if p then
		info = wanted(p) and targetInfo(p)
		if not info or info.boat then
			-- Gone, caught, escaped, dead, or out to sea (player cops have the Harbor Patrol boat).
			release(u)
			p, info = nil, nil
		end
	end

	local aim
	local limit = math.huge
	local scale = Police.PatrolSpeed
	local direct = false
	local dist = math.huge
	if p and info then
		local gentle = isTutorial(p)
		scale = math.min(1, info.maxSpeed * (gentle and Police.Tutorial.SpeedCap or Police.SpeedVsTarget) / carMax)
		dist = flatDist(info.pos, pos)
		if HeatService.IsSeen(p) then
			-- Seen by someone: the police know where they are.
			u.stage, u.searchCenter = nil, nil
			if dist < Police.DirectRange and HeatService.SeenAgo(p, chassis) < 0.8 then
				direct = true
				aim = directAim(u, info, pos, dist)
				u.wp = nil
			else
				local goal = chaseGoal(u, info)
				local moved = not u.plannedGoal or flatDist(goal, u.plannedGoal) > 60
				if not u.wp or now > u.repathAt or (moved and now - (u.plannedAt or 0) > 0.5) then
					planTo(u, goal, now)
				end
				u.goal = goal
			end
		else
			-- Unseen: only the last-seen spot, then a search of the circle. Never the real position.
			local center = HeatService.LastSeenPos(p)
			if center then
				if not u.searchCenter or flatDist(center, u.searchCenter) > 30 then
					u.searchCenter = center
					u.stage = "goto"
					planTo(u, flat(center), now)
				end
				-- Arrived (or the roads end short of it: a beach, a roof): start searching.
				local roadsEnd = u.wp and u.wi > #u.wp and flatDist(center, pos) < 160
				if u.stage == "goto" and (flatDist(center, pos) < 45 or roadsEnd) then
					u.stage = "search"
					u.searchUntil = 0
				end
				if u.stage == "search" then
					scale *= Police.SearchSpeed
					if not u.goal or flatDist(u.goal, pos) < 35 or now > (u.searchUntil or 0) then
						local _, radius = HeatService.SearchArea(p)
						planTo(u, searchPoint(u, center, radius or Police.SearchRadius(p:GetAttribute("Heat") or 1), pos), now)
						u.searchUntil = now + 25
					end
				end
			else
				u.wp, u.goal = nil, nil -- nothing known yet: hold
			end
		end

		-- Arrest a target who stays (nearly) stopped right next to us, at our level and in our sight.
		-- Brief wiggles don't reset the timer, they only slow it down; driving off properly does.
		local slow = info.inCar and info.vel.Magnitude < 8 or (not info.inCar and info.vel.Magnitude < 10)
		local close = dist < Police.ArrestRange and math.abs(info.pos.Y - pos.Y) < Police.ArrestHeight
			and HeatService.SeenAgo(p, chassis) < 1
		if close and slow and now >= u.graceUntil then
			u.arrestFor += dt
			if u.arrestFor >= Police.ArrestSeconds then
				u.arrestFor = 0
				require(ServerScriptService.Services.ArrestService).Arrest(p, nil)
			end
		else
			u.arrestFor = math.max(0, u.arrestFor - dt * (close and 0.5 or 2))
		end
	else
		-- Patrol (or on the way out): cruise, and join the chase on seeing a wanted player.
		if not u.patrol then
			startPatrol(u)
		end
		if not u.leaving and now >= u.checkAt then
			u.checkAt = now + CONVERT_CHECK
			for _, q in ipairs(Players:GetPlayers()) do
				if wanted(q) and not isTutorial(q) and HeatService.SeenAgo(q, chassis) < 1 and tryJoin(u, q) then
					break
				end
			end
		end
	end

	-- Follow the route.
	if not direct then
		local wp = u.wp
		if wp then
			u.wi = advance(wp, u.wi, pos, reachFor(pos, wp, u.wi, speed), look)
			local pr = u.patrol
			if pr and u.wi > 1 and not u.target then
				for _ = 1, u.wi - 1 do
					pr.prev = table.remove(pr.route, 1)
				end
				extendPatrol(u)
				wp = u.wp
			end
			if wp then
				aim = wp[u.wi] or u.goal
				limit = cornerLimit(pos, wp, u.wi, u.goal, decel)
			end
		else
			aim = aim or u.goal
		end
	end

	-- Steering and speed.
	local angle = 0
	if aim then
		local dir = flat(aim - pos)
		if dir.Magnitude > 0.1 and look.Magnitude > 0.1 and right.Magnitude > 0.1 then
			dir, look, right = dir.Unit, look.Unit, right.Unit
			angle = math.atan2(dir:Dot(right), dir:Dot(look))
		end
	end
	local throttle, steer = aim and 1 or 0, math.clamp(angle * 2.2, -1, 1)
	local absAngle = math.abs(angle)
	if absAngle > 0.35 then
		limit = math.min(limit, cornerSpeed(absAngle)) -- pointing the wrong way: slow for the turn
	end
	if direct and info and dist < 90 then
		-- Close in smoothly: the nearer the target, the slower we want to be (no overshooting).
		limit = math.min(limit, math.max(12, dist * 1.3 + flat(info.vel).Magnitude))
	end
	if aim then
		if speed > limit + 2 then
			throttle = -math.clamp(0.4 + (speed - limit) / 10, 0.4, 1) -- brake (CarPhysics brakes on negative throttle)
		elseif speed > limit - 3 then
			throttle = 0
		end
	end
	if absAngle > 2.4 and speed < 20 then
		throttle, steer = -0.8, -steer -- target behind us: back up while turning
	end
	if direct and dist < 18 then
		throttle = speed > 4 and -1 or 0 -- park a car length away; never shove the target around
	end

	-- Stuck? Back up for a moment.
	if now < u.reverseUntil then
		throttle, steer = -1, u.reverseSteer
	elseif throttle > 0.5 and math.abs(speed) < 3 then
		u.stuckFor += dt
		if u.stuckFor > 2 then
			u.stuckFor = 0
			u.reverseUntil = now + 1.3
			u.reverseSteer = angle > 0 and -1 or 1
		end
	else
		u.stuckFor = 0
	end
	-- Really stuck (no progress for 16 s while trying to drive)? Remove it once nobody can see it;
	-- dispatch sends a fresh car if one is still needed.
	if now >= u.progressAt then
		local parked = direct and dist < 30
		if (pos - u.progressPos).Magnitude < 12 and aim and not parked then
			u.strikes += 1
		else
			u.strikes = 0
		end
		u.progressAt, u.progressPos = now + 8, pos
		if u.strikes >= 2 and canVanish(u) then
			despawn(u)
			return
		end
	end

	-- Upside down? Put it back.
	if cf.UpVector.Y < 0.3 then
		u.upsideFor += dt
		if u.upsideFor > 3 then
			u.upsideFor = 0
			local fwd = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
			damageSkip(car, 1.5)
			car:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 4, 0), pos + Vector3.new(0, 4, 0) + fwd))
			chassis.AssemblyLinearVelocity = Vector3.zero
			chassis.AssemblyAngularVelocity = Vector3.zero
		end
	else
		u.upsideFor = 0
	end

	CarPhysics.Step(u.phys, dt, { Throttle = throttle, Steer = steer, SpeedScale = scale })
end

------------------------------------------------------------------------------------------------------
-- Dispatch

-- How many units this player should have, and whether they get the gentle tutorial chaser.
local function wantFor(p)
	if not wanted(p) then
		return 0
	end
	local info = targetInfo(p)
	if not info or info.boat then
		return 0
	end
	if isTutorial(p) then
		return 1
	end
	local heat = math.clamp(math.floor(p:GetAttribute("Heat") or 1), 1, 5)
	local engaged = HeatService.EngagedCops(p)
	local want = math.max(0, (Police.UnitsByHeat[heat] or 1) - engaged)
	if heat >= Police.FloorStars and engaged == 0 then
		want = math.max(want, 1)
	end
	return want
end

local function freePatrols()
	local list = {}
	for _, u in ipairs(units) do
		if not u.target and not u.leaving then
			table.insert(list, u)
		end
	end
	return list
end

-- The free patrol farthest from every player (the cheapest one to send home).
local function loneliestPatrol()
	local best, bestD
	for _, u in ipairs(freePatrols()) do
		local d = nearestPlayerDist(u.chassis.Position)
		if not bestD or d > bestD then
			best, bestD = u, d
		end
	end
	return best
end

-- One more unit for this player: a free patrol (one that sees them, else the nearest), or a new car.
local function fillOne(p, now)
	local info = targetInfo(p)
	local ref = HeatService.LastSeenPos(p)
	if not info or not ref then
		return
	end
	ref = flat(ref)
	local tutorial = isTutorial(p)
	local full = #units >= Police.MaxTotal
	if not tutorial then
		local best, bestD
		for _, u in ipairs(freePatrols()) do
			local d = flatDist(u.chassis.Position, ref)
			if HeatService.SeenAgo(p, u.chassis) < 2 then
				d = -1
			end
			if (d < Police.PatrolDispatch or full) and (not bestD or d < bestD) then
				best, bestD = u, d
			end
		end
		if best then
			assign(best, p)
			return
		end
	end
	if now - (lastSpawnFor[p] or -math.huge) < Police.SpawnGap then
		return
	end
	if full then
		-- Make room for the tutorial chaser: a patrol goes home (or the busiest chase gives one up).
		if tutorial then
			local victim = loneliestPatrol()
			if not victim then
				local most
				for _, u in ipairs(units) do
					if u.target and u.target ~= p and not isTutorial(u.target) and not u.leaving then
						if not most or #unitsOf(u.target) > #unitsOf(most.target) then
							most = u
						end
					end
				end
				if most then
					release(most)
					victim = most
				end
			end
			if victim then
				victim.leaving = victim.leaving or now
			end
		end
		return
	end
	lastSpawnFor[p] = now
	local cf
	if tutorial then
		cf = findSpot(ref, Police.Tutorial.SpawnMin, Police.Tutorial.SpawnMax, p, ref, false)
			or findSpot(ref, Police.Tutorial.SpawnMax, Police.Tutorial.SpawnMax + 100, p, ref, false)
	else
		cf = findSpot(ref, Police.SpawnMin, Police.SpawnMax, p, ref, false)
			or findSpot(ref, Police.SpawnMax, Police.SpawnMax + 200, p, ref, false)
	end
	local car = cf and newCar(cf)
	if car then
		newUnit(car, p)
	end
end

local function spawnPatrol(now)
	-- Near a citizen with no patrol around yet (random among them).
	local anchors = {}
	for _, s in ipairs(playerSpots) do
		if s.side == "Civilian" then
			local covered = false
			for _, u in ipairs(units) do
				if not u.target and flatDist(u.chassis.Position, s.pos) < Police.PatrolRange * 0.8 then
					covered = true
					break
				end
			end
			if not covered then
				table.insert(anchors, s.pos)
			end
		end
	end
	if #anchors == 0 then
		return
	end
	lastPatrolSpawn = now
	local at = anchors[rng:NextInteger(1, #anchors)]
	local cf = findSpot(flat(at), Police.PatrolSpawnMin, Police.PatrolSpawnMax, nil, nil, true)
	local car = cf and newCar(cf)
	if car then
		newUnit(car, nil)
	end
end

local function managePatrols(now)
	local pursuing, leaving = 0, 0
	for _, u in ipairs(units) do
		if u.leaving then
			leaving += 1
		elseif u.target then
			pursuing += 1
		end
	end
	local unmet = 0
	for _, p in ipairs(Players:GetPlayers()) do
		unmet += math.max(0, (wantCache[p] or 0) - #unitsOf(p))
	end
	local free = freePatrols()
	local budget = math.max(0, math.min(Police.Patrols, Police.MaxTotal - pursuing - leaving - unmet))
	if #free > budget then
		local victim = loneliestPatrol()
		if victim then
			victim.leaving = now
		end
	elseif #free < budget and #units < Police.MaxTotal and now - lastPatrolSpawn > 3 then
		spawnPatrol(now)
	end
end

------------------------------------------------------------------------------------------------------
-- Roadblocks

local function removeRoadblock(i)
	local rb = table.remove(roadblocks, i)
	if rb then
		HeatService.UnregisterEye(rb.zone)
		if rb.strip then
			rb.strip:Destroy()
		end
		rb.model:Destroy()
	end
end

local function roadTop(at)
	local hit = Workspace:Raycast(Vector3.new(at.X, 40, at.Z), Vector3.new(0, -80, 0), groundParams)
	return hit and hit.Position.Y or 0.1
end

-- A parked, anchored police car shell (no seats, prompts or forces) with its wheels on the road.
local function buildShell(cf, groundY)
	local car = CarBuilder.Build(CAR_ID)
	car.Name = "RoadblockCar"
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("Seat") or d:IsA("VehicleSeat") or d:IsA("ProximityPrompt") or d:IsA("VectorForce") or d:IsA("Torque") then
			d:Destroy()
		end
	end
	car:SetAttribute("NCVehicle", nil)
	car:SetAttribute("Siren", true)
	car:PivotTo(cf)
	local low = math.huge
	for _, d in ipairs(car:GetChildren()) do
		if d:IsA("BasePart") and string.match(d.Name, "^Wheel") then
			low = math.min(low, d.Position.Y - d.Size.Y / 2)
		end
	end
	if low < math.huge then
		car:PivotTo(cf + Vector3.new(0, groundY - low, 0))
	end
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return car
end

local function buildRoadblock(spot, target)
	local dir = flat(spot.dir)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, -1)
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local groundY = roadTop(spot.pos)
	local center = Vector3.new(spot.pos.X, groundY, spot.pos.Z)
	local gap = RB.Gap
	local angle = math.rad(55)
	local extent = CAR_SIZE.Z * math.sin(angle) + CAR_SIZE.X * math.cos(angle) -- one car's width across the road

	local model = Instance.new("Model")
	model.Name = "Roadblock"
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Size = Vector3.new(math.max(spot.width or 30, gap + extent * 2 + 2), 6, 18)
	zone.CFrame = CFrame.lookAt(center + Vector3.new(0, 3, 0), center + Vector3.new(0, 3, 0) + dir)
	zone.Parent = model
	model.PrimaryPart = zone
	for _, side in ipairs({ -1, 1 }) do
		local c = center + across * side * (gap / 2 + extent / 2) + Vector3.new(0, 3, 0)
		local face = dir * math.cos(angle) - across * side * math.sin(angle)
		buildShell(CFrame.lookAt(c, c + face), groundY).Parent = model
	end
	model:SetAttribute("TargetUserId", target.UserId)
	model:SetAttribute("Pos", center)
	model:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + RB.Life)
	-- Default (non-atomic) streaming: the Model and its attributes reach every client (minimap icons),
	-- the parts stream in by distance.
	model.Parent = roadblockFolder
	local stripAt = center + Vector3.new(0, 0.2, 0)
	local ok, strip = pcall(function()
		return require(ServerScriptService.Services.ArrestService).PlaceSpike(CFrame.lookAt(stripAt, stripAt + dir), gap + 1, nil, RB.Life)
	end)
	HeatService.RegisterEye(zone)
	table.insert(roadblocks, { model = model, zone = zone, strip = ok and strip or nil, target = target,
		expires = os.clock() + RB.Life, pos = center })
	Remotes.Event("Notify"):FireClient(target, "RoadblockAhead")
end

-- A spot 350-500 studs ahead along the roads, out of the suspect's sight, clear of cars and people.
local function roadblockSpot(info, heading)
	local eye = info.head + Vector3.new(0, 2, 0)
	local candidates = RoadGraph.Ahead(info.pos, heading, RB.AheadMin, RB.AheadMax)
	for k = 1, math.min(#candidates, 8) do
		local c = candidates[k]
		local at = Vector3.new(c.pos.X, 3, c.pos.Z)
		local clash = nearAvoid(at)
		for _, rb in ipairs(roadblocks) do
			if flatDist(rb.pos, at) < 200 then
				clash = true
			end
		end
		if not clash and not lineClear(eye, at) then
			local dir = flat(c.dir)
			if dir.Magnitude > 0.1 then
				local box = CFrame.lookAt(at, at + dir.Unit)
				if #Workspace:GetPartBoundsInBox(box, Vector3.new(math.max(c.width or 30, 42), 10, 26), busyParams) == 0 then
					return c
				end
			end
		end
	end
	return nil
end

local function roadblockTick(now)
	for i = #roadblocks, 1, -1 do
		local rb = roadblocks[i]
		local p = rb.target
		local info = wanted(p) and targetInfo(p)
		local far = info and flatDist(info.pos, rb.pos) > RB.FarRange
		if now > rb.expires or not rb.model.Parent or not wanted(p) or far then
			removeRoadblock(i)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if #roadblocks >= RB.MaxActive then
			return
		end
		if wanted(p) and (p:GetAttribute("Heat") or 0) >= RB.MinStars and not isTutorial(p)
			and HeatService.LastSeenAgo(p) <= RB.SeenWithin and now - (lastRoadblockFor[p] or -math.huge) >= RB.Every then
			local info = targetInfo(p)
			local v = info and flat(info.vel)
			if info and v and info.inCar and not info.boat and v.Magnitude > 25 then
				lastRoadblockFor[p] = now - RB.Every + 4 -- no good spot: try again in 4 s
				local spot = roadblockSpot(info, v.Unit)
				if spot then
					buildRoadblock(spot, p)
					lastRoadblockFor[p] = now
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------

local function manage()
	local now = os.clock()
	refreshWorld()
	-- Cars on their way out go once nobody can see them; patrols far from everyone just go.
	for i = #units, 1, -1 do
		local u = units[i]
		if u and u.chassis.Parent then
			if u.leaving and (now - u.leaving > Police.LeaveTimeout or canVanish(u)) then
				despawn(u)
			elseif not u.target and nearestPlayerDist(u.chassis.Position) > Police.PatrolRange and canVanish(u) then
				despawn(u)
			end
		end
	end
	-- Demand per wanted player; surplus units become patrols (or go home).
	local demand = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local want = wantFor(p)
		wantCache[p] = want
		local mine = unitsOf(p)
		if #mine > want then
			local ref = HeatService.LastSeenPos(p) or Vector3.zero
			table.sort(mine, function(a, b)
				return flatDist(a.chassis.Position, ref) > flatDist(b.chassis.Position, ref)
			end)
			for k = 1, #mine - want do
				release(mine[k])
			end
		elseif #mine < want then
			table.insert(demand, { p = p, tutorial = isTutorial(p), heat = p:GetAttribute("Heat") or 0 })
		end
	end
	table.sort(demand, function(a, b)
		if a.tutorial ~= b.tutorial then
			return a.tutorial
		end
		return a.heat > b.heat
	end)
	for _, d in ipairs(demand) do
		fillOne(d.p, now)
	end
	managePatrols(now)
	roadblockTick(now)
end

function AIPoliceService.Count()
	return #units
end

function AIPoliceService.Init()
	RoadGraph.BuildFromWorld()
	RoadGraph.Publish()
	roadblockFolder = Workspace:FindFirstChild("Roadblocks") or Instance.new("Folder")
	roadblockFolder.Name = "Roadblocks"
	roadblockFolder.Parent = Workspace
	local spawns = Workspace:FindFirstChild("Spawns")
	for _, d in ipairs(spawns and spawns:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			table.insert(avoidPoints, d.Position)
		end
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(manage)
			if not ok then
				warn("[AIPolice] " .. tostring(err))
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for i = #units, 1, -1 do
			local u = units[i]
			if u then
				local ok, err = pcall(update, u, dt, now)
				if not ok then
					warn("[AIPolice] " .. tostring(err))
					pcall(despawn, u)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastSpawnFor[p] = nil
		wantCache[p] = nil
		lastRoadblockFor[p] = nil
	end)
end

return AIPoliceService
