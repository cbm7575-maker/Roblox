-- ImpactService (ModuleScript, ServerScriptService.Services.ImpactService)
-- Cars hitting people on foot, plus getting into your car with the F key / GET IN button.
-- Every car hit also costs health by its speed (owner, Oct 30: a bump hurts a little, a fast hit a lot,
-- running someone over again and again can kill): CombatService.CarHit does the damage, the death and
-- the protections (safe zones, spawn protection, passive mode and crewmates for a player's car).
--   * ImpactHit (driver's device -> server): "my car just hit this player on foot, this fast". The
--     driver's device owns its car's physics, so it spots the hit (ImpactClient). We check it: rate
--     limit, the hitter really is driving, the victim is on foot and touching the car's box (its path a
--     moment ahead) with nothing solid between. The speed for the damage is the device's, but never more
--     than what we saw the car doing before the bump slowed it (the device takes a quarter off the moment
--     it hits). Someone already down is only hurt (run over again: Combat.CarHit.Downed of the damage).
--     Nobody CarHit protects from that driver's car (safe zone, spawn protection, passive, crewmates, a
--     cop's car and someone not wanted) is knocked over (shielded). Anyone else is knocked over:
--       - "Knockdown" (direction, speed, seconds) goes to the victim's device, which owns their
--         character and does the fall, the dizzy stars and getting up (ImpactClient).
--       - Player attribute KnockedUntil (server time) lets every device show the dizzy stars.
--     After getting up you can't be knocked again for a couple of seconds (no chain knock-downs).
--   * AI patrol cars are server cars, so we check them here 5 times a second: one moving fast that
--     drives into someone on foot knocks them over (and hurts them). Never a player any patrol is
--     chasing (their unit parks beside them; a knock-down there would turn straight into an arrest,
--     which isn't fair).
--   * TrafficHit (victim's device -> server): street traffic lives on each device alone, so a traffic car
--     that knocks you over is reported by your own device, with its speed (ImpactClient.KnockLocal).
--     It can only ever hurt the one who sends it; at most one every 1.5 s.
--   * CarBump (driver's device -> server): "my car just drove into this car, closing this fast, along this
--     direction". Each car is run by its own machine (its driver's device, or the server for race bots,
--     patrols and parked cars), so to the hitter the other car was a wall that never moved, and nothing
--     ever pushed it on the machine that runs it either (owner play-test, Nov 2: "he didn't budge at all").
--     ImpactClient does the hitter's own side of the bump and asks us for the other car's side. We check
--     it: rate limit (K.BUMP_RATE a second, one per car per driver every K.PAIR_GAP s, one per car every
--     K.TARGET_GAP s), the hitter really is driving, the other is a car in Workspace.Vehicles (not theirs,
--     not held still for a race start), the two boxes touch as we see them (slack: the other car's speed
--     x the hitter's round trip, at most K.TOUCH_MAX studs), the direction points away from the hitter, and
--     the closing speed is no more than the fastest we saw the hitter drive in the last second (x
--     K.CLAIM_SLACK + K.CLAIM_EXTRA, plus the other car's speed toward it). The push is what a real bump
--     gives: closing speed x (1 + K.RESTITUTION) x hitter's mass / both masses, at most K.MAX_PUSH studs/s
--     and never past that car's own top speed, plus a little yaw from a hit off its middle (K.MAX_SPIN).
--       - A car the server runs: its velocity changes here.
--       - A car a player's device runs: "CarShove" (car, push, spin, want, hitter's car) goes to that
--         device, which applies it to its own car (ImpactClient), topping its speed that way up to `want`
--         (as we saw it, plus the push), so a shove its own physics already gave isn't given twice.
--       - Either way the car gets attribute BumpedAt (server time): RaceAIService's bots roll with the
--         shove for a moment instead of braking it away.
--   * RequestEnterCar (F / GET IN / gamepad X): sits you in your own empty car, or (civilians only) in
--     the hot car you stole (its Drive prompt is gone once stolen, so this is the only way back in),
--     when you're close and not knocked over or tasered. The E prompt (VehicleService) has the same
--     knocked-over / tasered rule. Asked while sitting in another car (or another seat of that one), the
--     "GetOutFirst" toast says why nothing happened (at most one every 3 s, shared with CarjackService and
--     CarBoostService).
-- Nobody sitting in a car is ever knocked down.
-- (The body also goes limp for everyone through RagdollService.KnockDown, inside a pcall: without it the
-- fall is the stiff tip-over.)
-- Public: ImpactService.KnockDown(victim, dir, speed, seconds, reason?) -> bool. The same checks and fall as a
-- car hit, for `seconds` on the ground (CombatService knockouts use it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local VehicleService = require(ServerScriptService.Services.VehicleService)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)

-- CombatService requires this module, so it is looked up when first needed (it has started by then).
local CombatService
local function combat()
	if CombatService == nil then
		local module = ServerScriptService.Services:FindFirstChild("CombatService")
		local ok, result = pcall(function()
			return module and require(module)
		end)
		CombatService = (ok and type(result) == "table") and result or false
	end
	return CombatService or nil
end

-- Limp bodies (RagdollService). Optional on purpose: if that module is missing or fails to load, a
-- knock-down is still the stiff tip-over ImpactClient does by itself.
local RagdollService
do
	local module = ServerScriptService.Services:FindFirstChild("RagdollService")
	local ok, result = pcall(function()
		return module and require(module)
	end)
	RagdollService = (ok and type(result) == "table") and result or nil
end

local ImpactService = {}

local KNOCK_TIME = 2.5 -- seconds on the ground
local IMMUNE_AFTER = 2 -- seconds after getting up before you can be knocked again
local HIT_RANGE = 20 -- studs between the hitter's car and the victim...
local LAG_RANGE = 10 -- ...plus up to this much for fast cars (the two devices see slightly old positions)
local MIN_CAR_SPEED = 10 -- a parked car can't "hit" anyone
local AI_INTERVAL = 0.2
local AI_MIN_SPEED = 20
local AI_MARGIN = 1.5
local ENTER_RANGE = 16 -- the client offers GET IN at 12 studs; a little slack for lag
local BUMP_KEEP = 0.7 -- the driver's device cuts its speed to 75% on hitting someone: we may see that already
local CONTACT_SLACK = 4 -- studs past the car's box a victim may be and still count as hit (for the damage)...
local CONTACT_LAG = 0.12 -- ...plus this many per stud/s of speed (what we see is a little behind the driver)
-- ...and anywhere along the car's own path this many seconds ahead: we see a driver's car up to that far
-- behind their device (physics buffering plus ping; 0.2 s, 10 studs at 50, in a two-player test).
local CONTACT_AHEAD = 0.35
local contactParams = RaycastParams.new()
contactParams.FilterType = Enum.RaycastFilterType.Exclude
contactParams.IgnoreWater = true

-- Car-to-car bumps (CarBump, see the header).
local K = {
	-- Share of the closing speed the two cars spring apart with (1 would be a perfect bounce). The same
	-- number as ImpactClient's K.RESTITUTION, which does the hitter's side of the same bump.
	RESTITUTION = 0.25,
	MIN_CLOSING = 12, -- studs/s: a gentler touch is left to plain physics
	MAX_CLOSING = 220, -- studs/s, whatever anyone claims (two cars flat out into each other)
	MAX_PUSH = 70, -- studs/s: the most speed one bump may give a car
	MIN_PUSH = 2, -- less is not worth a message
	MAX_SPIN = 1.5, -- rad/s of yaw one bump may give (VehicleGuard's spin limit is 25)
	SPIN_SHARE = 0.6, -- of the yaw a hit off the car's middle would give a free box: the tyres take the rest
	TOUCH_SLACK = 6, -- studs between the two boxes, as we see them, that still count as touching...
	TOUCH_LAG = 0.15, -- ...plus the other car's speed x (the hitter's round trip + this many seconds)...
	TOUCH_MAX = 30, -- ...never more than this in all
	NORMAL_DOT = 0.25, -- the device's push direction must lean at least this much away from the hitter
	CLAIM_SLACK = 1.15, -- closing speed at most (the fastest we saw the hitter lately) x this...
	CLAIM_EXTRA = 10, -- ...+ this (+ the other car's speed toward the hitter)
	PEAK_HOLD = 1, -- seconds that fastest speed is remembered
	BUMP_RATE = 4, -- bumps a second per player (burst as many)
	PAIR_GAP = 0.6, -- seconds before the same driver may bump the same car again (the device waits 1 s)
	TARGET_GAP = 0.2, -- seconds before the same car can be shoved again by anyone (two at once: one shove)
}

local safeUntil = {} -- [player] = os.clock() until which they can't be knocked down again
local downUntil = {} -- [player] = os.clock() until which they're on the ground
local knockRemote, notify
local shoveRemote -- CarShove: a bump for a car that player's device runs
local peakSpeed = {} -- [player] = { speed, at }: the fastest we saw them drive in the last K.PEAK_HOLD s
local bumpedBy = setmetatable({}, { __mode = "k" }) -- [car] = { [userId] = os.clock() they last bumped it }
local shovedAt = setmetatable({}, { __mode = "k" }) -- [car] = os.clock() it was last shoved

local function onFoot(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 or hum.SeatPart then
		return nil
	end
	return hum, root
end

-- The car this player is driving right now (driver's seat), or nil.
local function drivenCar(p)
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.Health > 0 and hum.SeatPart
	if not seat or seat.Name ~= "DriverSeat" then
		return nil
	end
	local car = seat.Parent
	local folder = Workspace:FindFirstChild("Vehicles")
	if not car or not folder or car.Parent ~= folder or car:GetAttribute("DriverUserId") ~= p.UserId then
		return nil
	end
	return car, car.PrimaryPart
end

-- Knock a player on foot over. dir: flat unit vector to push them along; speed: the car's speed;
-- seconds: time on the ground (KNOCK_TIME when left out).
local function knockDown(victim, dir, speed, seconds, reason)
	seconds = seconds or KNOCK_TIME
	local now = os.clock()
	if (safeUntil[victim] or 0) > now then
		return false
	end
	local hum = onFoot(victim)
	if not hum then
		return false
	end
	-- Tasered players are already down (LawClient keeps them there).
	if (victim:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
		return false
	end
	downUntil[victim] = now + seconds
	safeUntil[victim] = now + seconds + IMMUNE_AFTER
	victim:SetAttribute("KnockedUntil", Workspace:GetServerTimeNow() + seconds)
	knockRemote:FireClient(victim, dir, speed, seconds)
	if RagdollService then
		-- The same hop ImpactClient gives the stiff body (10-22 along dir, 14 up), so the loose limbs leave with it.
		-- (6: ImpactClient stands the body up after at most that long, and the joints must be whole by then)
		local ok, err = pcall(RagdollService.KnockDown, victim, math.min(seconds, 6),
			dir * math.clamp(speed * 0.25, 10, 22) + Vector3.new(0, 14, 0), reason or "car")
		if not ok then
			warn("[ImpactService] ragdoll: " .. tostring(err))
		end
	end
	return true
end

-- Public knock-down for other services (CombatService knockouts). Same checks as a car hit: on foot,
-- not tasered, not just back up from another fall. Returns true if they went down.
function ImpactService.KnockDown(victim, dir, speed, seconds, reason)
	if not knockRemote or typeof(victim) ~= "Instance" or not victim:IsA("Player") or victim.Parent ~= Players then
		return false
	end
	local flatDir = typeof(dir) == "Vector3" and Vector3.new(dir.X, 0, dir.Z) or Vector3.zero
	-- (a NaN direction fails these comparisons too)
	local len = flatDir.Magnitude
	flatDir = (len > 0.05 and len < math.huge) and flatDir.Unit or Vector3.new(0, 0, -1)
	speed = tonumber(speed) or 30
	if speed ~= speed then
		speed = 30
	end
	seconds = tonumber(seconds) or KNOCK_TIME
	if seconds ~= seconds then
		seconds = KNOCK_TIME
	end
	return knockDown(victim, flatDir, math.clamp(speed, 0, 200), math.clamp(seconds, 0.5, 10), type(reason) == "string" and reason or "ko")
end

-- The car's name for the death screen ("Hit by <name>"): its Config.Vehicles display name.
local function carName(car)
	local def = car and Vehicles.ById[car:GetAttribute("VehicleId") or car.Name]
	return def and def.DisplayName or "a car"
end

-- Health off for a car hit (CombatService.CarHit), inside a pcall: a fault there never stops the knock-down.
local function hurt(victim, speed, dir, driver, car, downAlready, selfReported)
	local cs = combat()
	if cs and type(cs.CarHit) == "function" then
		local ok, err = pcall(cs.CarHit, victim, speed, dir, driver, car and carName(car) or nil, downAlready, selfReported)
		if not ok then
			warn("[ImpactService] car hit: " .. tostring(err))
		end
	end
end

-- Is `victim` out of reach of `driver`'s car? The protections CombatService.CarHit gives against the
-- damage keep them on their feet too: a safe zone, home or prisoner (CombatService.IsSafe), not a citizen
-- or a cop, spawn protection, passive mode on either side, crewmates, and a cop's car against anyone but a
-- wanted citizen. (Without this a driver could knock new players over at a spawn again and again.)
local function shielded(victim, driver)
	local side = victim:GetAttribute("Side")
	if side ~= "Civilian" and side ~= "Cop" then
		return true
	end
	local spawnSafe = victim:GetAttribute("SpawnSafeUntil")
	if type(spawnSafe) == "number" and spawnSafe > Workspace:GetServerTimeNow() then
		return true
	end
	if victim:GetAttribute("Passive") == true or driver:GetAttribute("Passive") == true then
		return true
	end
	local crew = driver:GetAttribute("Crew")
	if crew ~= nil and crew == victim:GetAttribute("Crew") then
		return true
	end
	if driver:GetAttribute("Side") == "Cop" and (side ~= "Civilian" or (victim:GetAttribute("Heat") or 0) < 1) then
		return true
	end
	local cs = combat()
	if cs and type(cs.IsSafe) == "function" then
		local ok, safe = pcall(cs.IsSafe, victim)
		return ok and safe == true
	end
	return false
end

local function isDown(p)
	local t = Workspace:GetServerTimeNow()
	return (downUntil[p] or 0) > os.clock() or (p:GetAttribute("KnockedUntil") or 0) > t or (p:GetAttribute("StunnedUntil") or 0) > t
end

-- Push direction: mostly along the car's travel, a bit away from the car's centre.
local function pushDir(chassis, root, flatVel)
	local away = (root.Position - chassis.Position) * Vector3.new(1, 0, 1)
	local along = flatVel.Magnitude > 0.1 and flatVel.Unit or Vector3.zero
	local dir = along * 0.6 + (away.Magnitude > 0.1 and away.Unit or Vector3.zero) * 0.4
	if dir.Magnitude < 0.1 then
		dir = along.Magnitude > 0 and along or Vector3.new(0, 0, -1)
	end
	return dir.Unit
end

-- Does a box of half-size hx by hz (flat, car space), moving at v (car space), cover the point rel at some
-- moment in the next `ahead` seconds? Each axis allows a span of time; the spans have to overlap.
local function sweptTouch(rel, v, hx, hz, ahead)
	local lo, hi = 0, ahead
	for _, a in ipairs({ { rel.X, v.X, hx }, { rel.Z, v.Z, hz } }) do
		local p, w, h = a[1], a[2], a[3]
		if math.abs(w) < 1e-3 then
			if math.abs(p) > h then
				return false
			end
		else
			local t1, t2 = (p - h) / w, (p + h) / w
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			lo, hi = math.max(lo, t1), math.min(hi, t2)
			if not (lo <= hi) then -- (and NaN)
				return false
			end
		end
	end
	return true
end

local function onHit(player, victim, reported)
	if not RateLimit.Allow(player, "ImpactHit", 3, 4) then
		return
	end
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") or victim == player or victim.Parent ~= Players then
		return
	end
	local car, chassis = drivenCar(player)
	if not car or not chassis or car:GetAttribute("Boat") then
		return -- boats don't knock swimmers over
	end
	local _, root = onFoot(victim)
	if not root then
		return
	end
	local vel = chassis.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = flatVel.Magnitude
	if speed ~= speed or speed < MIN_CAR_SPEED then
		return
	end
	local dist = (root.Position - chassis.Position).Magnitude
	if dist > HIT_RANGE + math.min(speed * 0.12, LAG_RANGE) then
		return
	end
	-- How hard: the device's number, within what we saw (it may already be the slowed-down speed).
	local hitSpeed = speed
	reported = tonumber(reported)
	if reported and reported == reported then
		hitSpeed = math.clamp(reported, speed, speed / BUMP_KEEP + 5)
	end
	local dir = pushDir(chassis, root, flatVel)
	local wasDown = isDown(victim)
	-- The knock-down and the damage both need real contact, not just "near": the victim inside the car's
	-- box (plus what the two devices' lag can account for), and nothing solid between the car and them. A
	-- report from a tampered device about someone round a corner knocks nobody out of a building. (The
	-- knock-down used to come before these checks, so anyone within 30 studs went down.)
	local rel = chassis.CFrame:PointToObjectSpace(root.Position)
	local half = chassis.Size / 2
	local slack = CONTACT_SLACK + speed * CONTACT_LAG
	if rel.Y < -half.Y - 3 or rel.Y > half.Y + 7
		or not sweptTouch(rel, chassis.CFrame:VectorToObjectSpace(flatVel), half.X + slack, half.Z + slack, CONTACT_AHEAD) then
		return
	end
	-- (Everyone sitting in the car too: the ray starts inside it, and the driver's own hand used to count
	-- as "something solid between", so no player's car ever hurt anyone.)
	local ignore = { car, victim.Character, Workspace:FindFirstChild("Vehicles") or car }
	for _, p in ipairs(Players:GetPlayers()) do
		local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if h and h.SeatPart and h.SeatPart:IsDescendantOf(car) then
			table.insert(ignore, p.Character)
		end
	end
	contactParams.FilterDescendantsInstances = ignore
	local from = chassis.Position + Vector3.new(0, 1, 0)
	if Workspace:Raycast(from, root.Position - from, contactParams) then
		return
	end
	if not wasDown and not shielded(victim, player) then
		knockDown(victim, dir, speed)
	end
	hurt(victim, hitSpeed, dir, player, car, wasDown)
end

-- A traffic car knocked this player over on their own device (ImpactClient.KnockLocal).
local function onTrafficHit(player, speed, dir)
	if not RateLimit.Allow(player, "TrafficHit", 1 / 1.5, 1) then
		return
	end
	speed = tonumber(speed)
	if not speed or speed ~= speed or typeof(dir) ~= "Vector3" or dir.X ~= dir.X or dir.Z ~= dir.Z then
		return
	end
	if not onFoot(player) then
		return
	end
	hurt(player, math.clamp(speed, 0, 90), dir, nil, nil, false, true) -- (traffic never drives faster than that)
end

------------------------------------------------------------------ cars bumping cars (CarBump)

local function flatV(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- How far a car box (cf, half = half its size) reaches from its centre along flat direction n.
local function extent(cf, half, n)
	return math.abs(flatV(cf.RightVector):Dot(n)) * half.X + math.abs(flatV(cf.LookVector):Dot(n)) * half.Z
end

-- How two car boxes sit on the ground plane (ImpactClient's test): the side direction from A toward B with
-- the widest gap (for touching boxes, the face they meet on; nil if every axis is degenerate) and that gap
-- in studs (negative: overlapping that deep).
local function boxGap(cfA, halfA, cfB, halfB)
	local d = flatV(cfB.Position - cfA.Position)
	local bestAxis, bestGap = nil, -math.huge
	for _, v in ipairs({ cfA.RightVector, cfA.LookVector, cfB.RightVector, cfB.LookVector }) do
		local axis = flatV(v)
		if axis.Magnitude > 0.05 then
			axis = axis.Unit
			local along = d:Dot(axis)
			local gap = math.abs(along) - extent(cfA, halfA, axis) - extent(cfB, halfB, axis)
			if gap > bestGap then
				bestAxis, bestGap = along < 0 and -axis or axis, gap
			end
		end
	end
	return bestAxis, bestGap
end

-- 5 times a second: the fastest each driver went lately, to judge the closing speed a device claims (its
-- car is already slowed by the bump when the claim arrives, so the speed we see then is too low).
local function sampleDrivers()
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local _, chassis = drivenCar(p)
		local speed = chassis and flatV(chassis.AssemblyLinearVelocity).Magnitude
		if speed and speed == speed then
			local peak = peakSpeed[p]
			if not peak then
				peakSpeed[p] = { speed = speed, at = now }
			elseif speed >= peak.speed or now - peak.at > K.PEAK_HOLD then
				peak.speed, peak.at = speed, now
			end
		else
			peakSpeed[p] = nil
		end
	end
end

-- A number that is one (not NaN, not infinite), else nil.
local function finite(x)
	x = tonumber(x)
	return (x and x == x and x > -math.huge and x < math.huge) and x or nil
end

-- The car's top speed with nitro (Config.Vehicles, copied onto the car), for the cap on a push.
local function topSpeed(car)
	local top, nitro = finite(car:GetAttribute("MaxSpeed")) or 120, finite(car:GetAttribute("NitroSpeed")) or 1
	return math.max(top, 1) * math.max(nitro, 1)
end

-- The yaw (rad/s, about world up) that pushing `oc` by `push` at the point of its box nearest `from` gives
-- it: a free box's spin x K.SPIN_SHARE, within K.MAX_SPIN. Nothing for a hit square on its middle.
local function bumpSpin(oc, from, push)
	local cf, half = oc.CFrame, oc.Size / 2
	local rel = cf:PointToObjectSpace(from)
	local contact = cf:PointToWorldSpace(Vector3.new(math.clamp(rel.X, -half.X, half.X), 0, math.clamp(rel.Z, -half.Z, half.Z)))
	local r = flatV(contact - oc.Position)
	-- (r x push).Y over a box's yaw inertia per unit mass, (L^2 + W^2) / 12
	local spin = (r.Z * push.X - r.X * push.Z) * 12 / math.max(oc.Size.X ^ 2 + oc.Size.Z ^ 2, 1)
	return math.clamp(spin * K.SPIN_SHARE, -K.MAX_SPIN, K.MAX_SPIN)
end

-- The hitter's device: "my car drove into `other`, closing at `claimed` studs/s along `normal`".
local function onBump(player, other, claimed, normal)
	if not RateLimit.Allow(player, "CarBump", K.BUMP_RATE, K.BUMP_RATE) then
		return
	end
	local folder = Workspace:FindFirstChild("Vehicles")
	if typeof(other) ~= "Instance" or not other:IsA("Model") or not folder or other.Parent ~= folder
		or other:GetAttribute("NCVehicle") ~= true then
		return
	end
	local car, chassis = drivenCar(player)
	local oc = other.PrimaryPart
	if not car or not chassis or car == other or not oc or not oc:IsDescendantOf(Workspace) then
		return
	end
	-- Held still (a race grid's countdown): no shoving a car off the line, and it has no owner to ask.
	if oc.Anchored or chassis.Anchored then
		return
	end
	claimed = finite(claimed)
	if not claimed or claimed < K.MIN_CLOSING then
		return
	end
	local now = os.clock()
	local mine = bumpedBy[other]
	if (mine and now - (mine[player.UserId] or -math.huge) < K.PAIR_GAP) or now - (shovedAt[other] or -math.huge) < K.TARGET_GAP then
		return
	end
	local v1, v2 = flatV(chassis.AssemblyLinearVelocity), flatV(oc.AssemblyLinearVelocity)
	local s1, s2 = v1.Magnitude, v2.Magnitude
	if s1 ~= s1 or s2 ~= s2 or s1 == math.huge or s2 == math.huge then
		return
	end

	-- Touching, as we see them. The hitter saw the other car a round trip ago (it reached them through us
	-- and their report came back through us), so it may have moved on since by its speed x that.
	local okPing, ping = pcall(player.GetNetworkPing, player)
	ping = (okPing and finite(ping)) and math.clamp(ping, 0, 0.5) or 0.1
	local cfA, halfA, cfB, halfB = chassis.CFrame, chassis.Size / 2, oc.CFrame, oc.Size / 2
	if math.abs(cfA.Position.Y - cfB.Position.Y) > halfA.Y + halfB.Y + 4 then
		return
	end
	local axis, gap = boxGap(cfA, halfA, cfB, halfB)
	local slack = math.min(K.TOUCH_SLACK + (s2 + s1 * 0.25) * (2 * ping + K.TOUCH_LAG), K.TOUCH_MAX)
	if not axis or gap > slack then
		return
	end

	-- Which way: the device's direction (it saw the touch as it happened) if it leans away from the
	-- hitter, else the face the boxes meet on as we see them.
	local centre = flatV(cfB.Position - cfA.Position)
	if centre.Magnitude < 0.1 then
		return
	end
	centre = centre.Unit
	local n = axis
	if typeof(normal) == "Vector3" then
		local f = flatV(normal)
		local len = f.Magnitude
		if len == len and len > 0.5 and len < 1.5 and (f / len):Dot(centre) >= K.NORMAL_DOT then
			n = f / len
		end
	end

	-- How hard: never more than the hitter could have been doing (see sampleDrivers) plus the other car
	-- coming at it.
	local peak = peakSpeed[player]
	local seen = math.max(s1, peak and now - peak.at <= K.PEAK_HOLD + 0.5 and peak.speed or 0)
	local bound = math.min(seen * K.CLAIM_SLACK + K.CLAIM_EXTRA + math.max(-v2:Dot(n), 0), K.MAX_CLOSING)
	local closing = math.min(claimed, bound)
	if closing < K.MIN_CLOSING then
		return
	end
	local m1, m2 = finite(chassis.AssemblyMass), finite(oc.AssemblyMass)
	if not m1 or not m2 or m1 <= 0 or m2 <= 0 then
		return
	end
	-- A real bump (momentum kept, a little bounce): the other car gains (1 + e) x m1 / (m1 + m2) of the
	-- closing speed. Within K.MAX_PUSH, and never past its own top speed (a player's car would trip
	-- VehicleGuard's speed check).
	local dv = math.min((1 + K.RESTITUTION) * m1 / (m1 + m2) * closing, K.MAX_PUSH)
	local over = (v2 + n * dv).Magnitude - topSpeed(other)
	if over > 0 then
		dv = math.max(0, dv - over)
	end
	if dv < K.MIN_PUSH then
		return
	end
	local push = n * dv
	local spin = bumpSpin(oc, cfA.Position, push)

	-- Who runs that car's physics. (Asking is an error on an anchored part: checked above.)
	local okOwner, owner = pcall(oc.GetNetworkOwner, oc)
	if not okOwner then
		return
	end
	if not mine then
		mine = {}
		bumpedBy[other] = mine
	end
	mine[player.UserId] = now
	shovedAt[other] = now
	other:SetAttribute("BumpedAt", Workspace:GetServerTimeNow())
	if owner == nil then
		-- Ours: race bots and patrols (their services keep them server-owned), parked and empty cars.
		oc.AssemblyLinearVelocity += push
		oc.AssemblyAngularVelocity += Vector3.new(0, spin, 0)
	elseif typeof(owner) == "Instance" and owner:IsA("Player") and owner.Parent == Players then
		-- A player's device runs it (its driver, or whoever just got out of it): that device applies it.
		shoveRemote:FireClient(owner, other, push, spin, v2:Dot(n) + dv, car)
	end
end

-- AI patrols driving into people on foot (5 times a second).
local function checkAI()
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	local now = os.clock()
	-- Everyone a patrol is chasing. None of them is knocked over by any patrol: with two wanted
	-- players close together, one's unit mustn't knock down the other right beside their own unit.
	local chased = {}
	for _, car in ipairs(folder:GetChildren()) do
		local t = car:GetAttribute("AIPolice") and car:GetAttribute("AITarget")
		if t then
			chased[t] = true
		end
	end
	local walkers = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local _, root = onFoot(p)
		if root and not chased[p.UserId] and (safeUntil[p] or 0) <= now then
			table.insert(walkers, { p, root })
		end
	end
	if #walkers == 0 then
		return
	end
	for _, car in ipairs(folder:GetChildren()) do
		local chassis = car:GetAttribute("AIPolice") and car.PrimaryPart
		if chassis then
			local vel = chassis.AssemblyLinearVelocity
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			local speed = flatVel.Magnitude
			if speed > AI_MIN_SPEED then
				local cf = chassis.CFrame
				local half = chassis.Size / 2
				local fwd = vel:Dot(cf.LookVector)
				-- Grow the box back over the road covered since the last check, so a fast car can't
				-- skip over someone between two checks. Forward is -Z, so "behind" is +Z.
				local sweep = math.abs(fwd) * AI_INTERVAL
				local shift = fwd >= 0 and sweep / 2 or -sweep / 2
				for _, w in ipairs(walkers) do
					local p, root = w[1], w[2]
					if (safeUntil[p] or 0) <= now then -- (someone knocked by an earlier car this check)
						local rel = cf:PointToObjectSpace(root.Position)
						local z = rel.Z - shift
						if math.abs(rel.X) < half.X + AI_MARGIN and math.abs(z) < half.Z + sweep / 2 + AI_MARGIN
							and rel.Y > -half.Y - 2 and rel.Y < half.Y + 6 then
							local dir = pushDir(chassis, root, flatVel)
							if knockDown(p, dir, speed) then
								hurt(p, speed, dir, nil, car, false)
							end
						end
					end
				end
			end
		end
	end
end

-- Sitting down (alive): "Get out of your car first", at most one toast every 3 s per player. The RateLimit
-- key is shared with CarjackService and CarBoostService, so trying all three at once still gives one toast.
local function getOutFirst(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and hum.SeatPart and RateLimit.Allow(player, "GetOutFirstToast", 1 / 3, 1) then
		notify:FireClient(player, "GetOutFirst")
	end
end

local function onEnter(player, car)
	if not RateLimit.Allow(player, "EnterCar", 2, 3) then
		return
	end
	local folder = Workspace:FindFirstChild("Vehicles")
	if typeof(car) ~= "Instance" or not car:IsA("Model") or not folder or car.Parent ~= folder then
		return
	end
	local side = player:GetAttribute("Side") or "Civilian"
	if side == "Prisoner" then
		return
	end
	if (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
		return -- tasered: the cop gets their chance to cuff
	end
	local mine = car:GetAttribute("OwnerUserId") == player.UserId and VehicleService.GetCar(player) == car
		and VehicleService.CanDrive(side, car:GetAttribute("VehicleId"))
	-- Back into a stolen hot car: civilians only, like picking the lock (not after switching to cop).
	local stolen = side == "Civilian" and car:GetAttribute("HotCar") == true and car:GetAttribute("ThiefUserId") == player.UserId
	if not mine and not stolen then
		return
	end
	local seat = car:FindFirstChild("DriverSeat")
	if not seat or not seat:IsA("VehicleSeat") or seat.Occupant then
		return
	end
	local hum, root = onFoot(player)
	if not hum then
		getOutFirst(player) -- sitting in a car already: say so (nothing to say when dead)
		return
	end
	if (downUntil[player] or 0) > os.clock() then
		return -- still dizzy on the ground
	end
	if (root.Position - seat.Position).Magnitude > ENTER_RANGE then
		return
	end
	seat:Sit(hum)
end

function ImpactService.Init()
	knockRemote = Remotes.Event("Knockdown")
	notify = Remotes.Event("Notify")
	Remotes.Event("ImpactHit").OnServerEvent:Connect(onHit)
	Remotes.Event("TrafficHit").OnServerEvent:Connect(onTrafficHit)
	Remotes.Event("RequestEnterCar").OnServerEvent:Connect(onEnter)
	shoveRemote = Remotes.Event("CarShove")
	Remotes.Event("CarBump").OnServerEvent:Connect(onBump)
	Players.PlayerRemoving:Connect(function(p)
		safeUntil[p] = nil
		downUntil[p] = nil
		peakSpeed[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(AI_INTERVAL)
			local ok, err = pcall(checkAI)
			if not ok then
				warn("[ImpactService] " .. tostring(err))
			end
			ok, err = pcall(sampleDrivers)
			if not ok then
				warn("[ImpactService] " .. tostring(err))
			end
		end
	end)
end

return ImpactService
