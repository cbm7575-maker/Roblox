-- AIPoliceService (ModuleScript, ServerScriptService.Services.AIPoliceService)
-- AI patrol cars keep crime exciting when few players are cops.
--   * Only while fewer than 2 player cops are online. Per wanted player: 1 car at 1-2 stars (only if
--     there are no player cops at all), heat - 1 cars at 3+ stars (max 3). At most 6 in the server.
--   * Head start: no patrol comes until the player has been wanted (WantedSince, set by HeatService)
--     for 20 s at 1 star, 14 s at 2, 8 s at 3, 4 s at 4+ (well inside HeatService's 30 + 10 x heat s
--     escape timer, so patrols get time to search). While waiting, the player attribute
--     PoliceETA (server time) says when they'll come, so the objective banner can count down.
--   * They spawn on a road 350-600 studs away (600-900 if there's none), out of the target's sight
--     when possible, follow the RoadGraph toward the target, and switch to direct pursuit once they
--     are close or can see the target. Where no road is in either ring (e.g. out on Lighthouse Key)
--     they use the road node nearest 350 studs that is at least 150 away, so no spot is a free escape.
--   * They never go faster than 95% of the target's car, so a good driver can always escape.
--   * Stuck (slow for 2 s) -> reverse and turn; upside down -> flipped back.
--   * They are cop "eyes" for HeatService, and arrest a wanted player who stays stopped (car under
--     8 studs/s, or on foot under 10) within 22 studs for about 3 seconds. They park a car length
--     away instead of shoving the target.
--   * They leave when the target is no longer wanted, leaves, or they fall 900+ studs behind for 15 s.
--   * Reset Character is no way out: a target whose body goes down by itself with a patrol close by is
--     arrested (ArrestService.GaveUp). Further away the patrols leave and new ones find the new body.
-- Server-owned physics (CarPhysics) so VehicleGuard never checks them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage.Shared.Util.CarPhysics)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)
local HeatService = require(ServerScriptService.Services.HeatService)

local AIPoliceService = {}

local MAX_TOTAL = 6
local SPAWN_MIN, SPAWN_MAX = 350, 600 -- preferred spawn distance from the target
local SPAWN_FAR = 900 -- fallback ring when no road is in the preferred band
local SPAWN_LAST = 150 -- last resort when neither ring has a road: never spawn closer than this
local GRACE = { 20, 14, 8, 4, 4 } -- head start in seconds, by stars (owner: "more time to think" after an ATM)
local LOS_TRIES = 10 -- raycasts spent looking for a spawn the target can't see
local DIRECT_RANGE = 140
local ARREST_RANGE = 22
local ARREST_SECONDS = 3
local LOST_RANGE = 900
local LOST_SECONDS = 15
local SPAWN_GAP = 6 -- seconds between spawns for the same target

local units = {} -- list of AI unit tables
local lastSpawnFor = {} -- [player] = os.clock()
local wantedAt = {} -- [player] = server time we first saw them wanted (only used if WantedSince is missing)
local rng = Random.new()

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

local function copCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Side") == "Cop" then
			n += 1
		end
	end
	return n
end

local function wanted(p)
	return p.Parent == Players and p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) > 0
end

local function targetInfo(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then
		return nil
	end
	local seat = hum.SeatPart
	local car = seat and seat.Parent
	local chassis = car and car.PrimaryPart
	if chassis then
		return { pos = chassis.Position, vel = chassis.AssemblyLinearVelocity, maxSpeed = car:GetAttribute("MaxSpeed") or 120, inCar = true,
			boat = car:GetAttribute("Boat") == true }
	end
	return { pos = root.Position, vel = root.AssemblyLinearVelocity, maxSpeed = 120, inCar = false }
end

local function desiredFor(p, cops)
	if cops >= 2 then
		return 0
	end
	local heat = p:GetAttribute("Heat") or 0
	if heat >= 3 then
		return math.min(3, heat - 1)
	end
	return cops == 0 and 1 or 0
end

local function unitsFor(p)
	local n = 0
	for _, u in ipairs(units) do
		if u.target == p then
			n += 1
		end
	end
	return n
end

local function despawn(u)
	for i, x in ipairs(units) do
		if x == u then
			table.remove(units, i)
			break
		end
	end
	if u.car.Parent then
		HeatService.UnregisterEye(u.car.PrimaryPart)
		u.car:Destroy()
	end
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

-- Server time when patrols may start coming for this wanted player (their head start ends).
local function arrivalTime(p)
	local since = p:GetAttribute("WantedSince")
	if typeof(since) ~= "number" then
		wantedAt[p] = wantedAt[p] or serverNow()
		since = wantedAt[p]
	end
	local stars = math.clamp(math.floor(p:GetAttribute("Heat") or 1), 1, #GRACE)
	return since + GRACE[stars]
end

local function setETA(p, value)
	if p:GetAttribute("PoliceETA") ~= value then
		p:SetAttribute("PoliceETA", value)
	end
end

-- A road node far enough away that the player has time to react (350-600 studs, or 600-900 if no
-- road is in that band), preferring one the target can't see from where they are.
local function pickSpawnNode(p, info)
	local flat = Vector3.new(info.pos.X, 0, info.pos.Z)
	local near, far = {}, {}
	local last, lastGap -- last resort: the node whose distance is nearest SPAWN_MIN (>= SPAWN_LAST away)
	for _, n in ipairs(RoadGraph.Nodes) do
		local d = (n - flat).Magnitude
		if d >= SPAWN_MIN and d <= SPAWN_MAX then
			table.insert(near, n)
		elseif d > SPAWN_MAX and d <= SPAWN_FAR then
			table.insert(far, n)
		end
		local gap = math.abs(d - SPAWN_MIN)
		if d >= SPAWN_LAST and (not lastGap or gap < lastGap) then
			last, lastGap = n, gap
		end
	end
	local choices = #near > 0 and near or far
	if #choices == 0 then
		-- Road nodes only sit at road ends and crossings, so a small island (Lighthouse Key) can have
		-- none in either ring. Still send a patrol, or that spot would be a guaranteed escape.
		return last
	end
	local fallback = choices[rng:NextInteger(1, #choices)]
	losParams.FilterDescendantsInstances = { Workspace.Vehicles, p.Character }
	for _ = 1, math.min(LOS_TRIES, #choices) do
		local i = rng:NextInteger(1, #choices)
		local n = table.remove(choices, i)
		local from = n + Vector3.new(0, 6, 0) -- roughly a patrol car's roof
		if Workspace:Raycast(from, info.pos - from, losParams) ~= nil then
			return n -- something blocks the view: the target won't see it appear
		end
	end
	return fallback
end

local function spawnFor(p, info)
	local node = pickSpawnNode(p, info)
	if not node then
		return
	end
	local path = RoadGraph.Path(node, info.pos)
	local nextPoint = (path and path[2]) or info.pos
	local pos = node + Vector3.new(0, 3.2, 0)
	local car = CarBuilder.Build("SunrayPatrol")
	car.Name = "AIPatrol"
	car:SetAttribute("AIPolice", true)
	car:SetAttribute("AITarget", p.UserId)
	local look = Vector3.new(nextPoint.X, pos.Y, nextPoint.Z)
	car:PivotTo(CFrame.lookAt(pos, (look - pos).Magnitude > 1 and look or pos + Vector3.new(0, 0, -1)))
	local prompt = car:FindFirstChild("DrivePrompt", true)
	if prompt then
		prompt:Destroy()
	end
	car.Parent = Workspace.Vehicles
	car.PrimaryPart:SetNetworkOwner(nil)
	HeatService.RegisterEye(car.PrimaryPart)
	local u = {
		car = car,
		target = p,
		phys = CarPhysics.New(car, {}),
		path = path,
		pathIndex = 2,
		repathAt = 0,
		stuckFor = 0,
		reverseUntil = 0,
		upsideFor = 0,
		arrestFor = 0,
		lostFor = 0,
	}
	table.insert(units, u)
	lastSpawnFor[p] = os.clock()
end

local function drive(u, dt, now)
	local car = u.car
	local chassis = car.PrimaryPart
	if not chassis or not car.Parent then
		return despawn(u)
	end
	local p = u.target
	if not wanted(p) then
		return despawn(u)
	end
	local info = targetInfo(p)
	if not info then
		-- No live body: they pressed Reset Character (or went down by themselves some other way). That
		-- used to be a free way out: every patrol vanished and the bag went home with them. So before
		-- this car goes, ArrestService gets to count it as giving up if police were close (GaveUp).
		-- Too far for that, the patrols still leave and new ones go after the new body.
		require(ServerScriptService.Services.ArrestService).GaveUp(p)
		return despawn(u)
	end
	if info.boat then
		-- Road patrols can't follow a boat out to sea (player cops have the Harbor Patrol boat).
		return despawn(u)
	end
	local pos = chassis.Position
	local cf = chassis.CFrame
	local toTarget = info.pos - pos
	local dist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude

	-- Gone missing?
	if dist > LOST_RANGE then
		u.lostFor += dt
		if u.lostFor > LOST_SECONDS then
			return despawn(u)
		end
	else
		u.lostFor = 0
	end
	if pos.Y < 0.2 or pos.Y < -60 then
		return despawn(u) -- drove into water or fell out of the world
	end

	-- Where to aim: straight at the target when close or in sight, otherwise along the roads.
	losParams.FilterDescendantsInstances = { car, p.Character, Workspace.Vehicles }
	local canSee = dist < 250 and Workspace:Raycast(pos + Vector3.new(0, 2, 0), toTarget, losParams) == nil
	local aim
	if dist < DIRECT_RANGE or canSee then
		aim = info.pos + info.vel * math.clamp(dist / 150, 0, 0.8) -- lead a moving target
	else
		if now > u.repathAt or not u.path then
			u.path = RoadGraph.Path(pos, info.pos)
			u.pathIndex = 2
			u.repathAt = now + 2
		end
		local path = u.path
		if path then
			while path[u.pathIndex] and (Vector3.new(pos.X, 0, pos.Z) - path[u.pathIndex]).Magnitude < 25 do
				u.pathIndex += 1
			end
			aim = path[u.pathIndex] or info.pos
		else
			aim = info.pos
		end
	end
	local dir = Vector3.new(aim.X - pos.X, 0, aim.Z - pos.Z)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	local angle = 0
	if dir.Magnitude > 0.1 and look.Magnitude > 0.1 then
		dir, look, right = dir.Unit, look.Unit, right.Unit
		angle = math.atan2(dir:Dot(right), dir:Dot(look))
	end
	local speed = chassis.AssemblyLinearVelocity:Dot(cf.LookVector)
	local throttle, steer = 1, math.clamp(angle * 2.2, -1, 1)
	if math.abs(angle) > 1.2 and speed > 45 then
		throttle = 0.15 -- slow down for sharp turns
	end
	if math.abs(angle) > 2.4 and speed < 20 then
		throttle, steer = -0.8, -steer -- target behind us: back up while turning
	end
	-- Close in smoothly: the nearer the target, the slower we want to be (no overshooting).
	local desired = math.max(12, dist * 1.3 + info.vel.Magnitude)
	if dist < 90 and speed > desired then
		throttle = -0.6
	end
	if dist < 18 then
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

	-- Upside down? Put it back.
	if cf.UpVector.Y < 0.3 then
		u.upsideFor += dt
		if u.upsideFor > 3 then
			u.upsideFor = 0
			car:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 4, 0), pos + Vector3.new(0, 4, 0) + (look.Magnitude > 0 and look or Vector3.new(0, 0, -1))))
			chassis.AssemblyLinearVelocity = Vector3.zero
			chassis.AssemblyAngularVelocity = Vector3.zero
		end
	else
		u.upsideFor = 0
	end

	-- Never faster than 95% of the target's car.
	local scale = math.min(1, (info.maxSpeed * 0.95) / (car:GetAttribute("MaxSpeed") or 135))
	CarPhysics.Step(u.phys, dt, { Throttle = throttle, Steer = steer, SpeedScale = scale })

	-- Arrest a target who stays (nearly) stopped right next to us. Brief wiggles don't reset the
	-- timer, they only slow it down; driving off properly does.
	local slow = info.inCar and info.vel.Magnitude < 8 or (not info.inCar and info.vel.Magnitude < 10)
	if dist < ARREST_RANGE and slow then
		u.arrestFor += dt
		if u.arrestFor >= ARREST_SECONDS then
			u.arrestFor = 0
			require(ServerScriptService.Services.ArrestService).Arrest(p, nil)
		end
	else
		u.arrestFor = math.max(0, u.arrestFor - dt * (dist < ARREST_RANGE and 0.5 or 2))
	end
end

local function manage()
	local cops = copCount()
	local t = serverNow()
	for _, p in ipairs(Players:GetPlayers()) do
		if wanted(p) then
			local want = desiredFor(p, cops)
			local have = unitsFor(p)
			local info = targetInfo(p)
			if info and info.boat then
				want = 0
			end
			-- Head start: nobody comes until the grace time for this many stars is over.
			local arriveAt = arrivalTime(p)
			local waiting = t < arriveAt
			setETA(p, (waiting and want > 0 and have == 0) and arriveAt or nil)
			if info and have < want and not waiting and #units < MAX_TOTAL and os.clock() - (lastSpawnFor[p] or 0) > SPAWN_GAP then
				spawnFor(p, info)
			elseif have > want then
				for _, u in ipairs(units) do
					if u.target == p then
						despawn(u)
						break
					end
				end
			end
		else
			wantedAt[p] = nil
			setETA(p, nil)
		end
	end
end

function AIPoliceService.Count()
	return #units
end

function AIPoliceService.Init()
	RoadGraph.BuildFromWorld()
	RoadGraph.Publish()
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
				local ok, err = pcall(drive, u, dt, now)
				if not ok then
					warn("[AIPolice] " .. tostring(err))
					despawn(u)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastSpawnFor[p] = nil
		wantedAt[p] = nil
	end)
end

return AIPoliceService
