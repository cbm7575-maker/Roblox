-- VehicleDamageService (ModuleScript, ServerScriptService.Services.VehicleDamageService)
-- Server-authoritative car damage: crashes matter, so cops can ram a getaway car into limp mode.
-- Every car in Workspace.Vehicles has attribute Health (0-100, 100 when built).
--   * About 12 times a second the server samples every chassis's velocity. A crash is a sudden loss
--     of horizontal speed that the car's own brakes and tyres can't explain (CarPhysics.ImpactExcess).
--   * Each device simulates only its own car, so car-on-car hits are also found in pairs: footprints
--     touching, closing fast along the contact axis, and at least one of the two really jolted. The
--     hit counts for both cars, even if only one side's physics shows it.
--   * Damage scales with the impact and the other car's mass over our Toughness (CarPhysics.CrashDamage).
--     Walls and other world geometry: any car. Traffic (client-side, so only an unexplained speed
--     loss with no wall nearby): lightly. Another car: only if this car's driver is wanted (Heat > 0)
--     or it is a police car (player cop or AI). Innocent civilians are never damaged by other players.
--   * Health < 35: smoke (VehicleVisuals) and x0.7 speed. Health 0: the engine stalls for 4 s (car
--     attribute StallUntil, server time; the driver can be cuffed), then limp mode until repaired
--     (CarPhysics reads both live, also for AI police cars).
--   * Repair: VehicleDamageService.Repair(car) (Spray & Go); a newly spawned car starts at 100.
--   * Not judged: boats, anchored cars, cars a server move just placed (VehicleGuard.Allow covers
--     both modules) and cars on VehicleDamageService.Skip(car, seconds).
--   VehicleDamageService.CarHit (signal): (car, otherCar, impact studs/s, damage) once per car for every
--   car-on-car hit; damage is 0 when the rules protect that car (e.g. for a "rammed a cop" crime).
-- Nothing here ever harms a player: no explosions, no fire.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage.Shared.Util.CarPhysics)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local VehicleGuard = require(ServerScriptService.Services.VehicleGuard)

local VehicleDamageService = {}

local SAMPLE = 1 / 12
local MAX_GAP = 0.4 -- longer than this between fresh samples (hitch, network stall): re-sample, don't judge
local TELEPORT_ERR = 15 -- studs off the path its velocity predicts -> moved by a script, not a crash
local MIN_LOSS = 6 -- studs/s of slack per sample (replication noise)
local SOLO_DEADZONE = 4
local WORLD_RATE = 0.25 -- Health per studs/s of impact (Toughness 2, equal mass)
local TRAFFIC_RATE = 0.1
local CAR_RATE = 0.6
local PAIR_MIN = 20 -- closing speed (studs/s) below which a touch is only a nudge
local JOLT_MIN = 4
local PAIR_COOLDOWN = 0.75
local TOUCH_GRACE = 0.3 -- a speed loss this soon after touching another car is that car's doing
local SHOVE_GRACE = 1.5 -- the same for cars other cars may not damage (shoved into a wall: no damage)
local BOX_MARGIN = 0.75 -- studs added around each chassis footprint
local MAX_HIT = 55 -- one crash never takes more than this
local STALL_SECONDS = 4

-- Per-car sample state. Records never reference their car (weak keys stay collectable).
local records = setmetatable({}, { __mode = "k" }) -- [car] = record
local skipUntil = setmetatable({}, { __mode = "k" }) -- [car] = os.clock()
local activeCars, activeRecs = {}, {} -- this tick's cars (reused arrays)
local hitEvent = Instance.new("BindableEvent")
VehicleDamageService.CarHit = hitEvent.Event

local notify
local studio = RunService:IsStudio() -- log every hit to the output (tuning)

-- Don't judge this car for a while (server moves that don't go through VehicleGuard.Allow).
function VehicleDamageService.Skip(car, seconds)
	skipUntil[car] = os.clock() + (seconds or 1)
end

-- Back to full health (Spray & Go).
function VehicleDamageService.Repair(car)
	if not car then
		return
	end
	car:SetAttribute("Health", 100)
	car:SetAttribute("StallUntil", nil)
	local rec = records[car]
	if rec then
		rec.pending = 0
	end
end

local function flatHeading(cf)
	local look = cf.LookVector
	local h = Vector3.new(look.X, 0, look.Z)
	if h.Magnitude < 0.2 then
		return nil -- on its nose or tail
	end
	return h.Unit
end

local function reset(rec, pos, vel, now)
	rec.pos, rec.vel, rec.prevVel, rec.t = pos, vel, vel, now
end

-- Update one car's samples; returns its record (nil = not a damageable car).
local function sample(car, now, serverNow)
	local chassis = car.PrimaryPart
	if not chassis or car:GetAttribute("Boat") == true or not car:GetAttribute("NCVehicle") then
		return nil
	end
	if car:GetAttribute("Health") == nil then
		car:SetAttribute("Health", 100)
	end
	local cf = chassis.CFrame
	local pos = cf.Position
	local vel = chassis.AssemblyLinearVelocity
	local size = chassis.Size
	local rec = records[car]
	local fresh = rec == nil
	if not rec then
		rec = { pairT = setmetatable({}, { __mode = "k" }), touchT = -math.huge, pending = 0, joltLast = 0, dvLast = 0 }
		records[car] = rec
		reset(rec, pos, vel, now)
	end
	rec.chassis, rec.cf = chassis, cf
	rec.fwdNow = flatHeading(cf)
	rec.halfW, rec.halfL = size.X / 2 + BOX_MARGIN, size.Z / 2 + BOX_MARGIN
	rec.radius = math.sqrt(rec.halfW * rec.halfW + rec.halfL * rec.halfL)
	rec.solo, rec.carImpact, rec.carOther = 0, 0, nil
	rec.skip = false
	local jolt, dv = 0, 0
	local guarded = VehicleGuard.Allowed and VehicleGuard.Allowed(car)
	if fresh or chassis.Anchored or (skipUntil[car] or 0) > now or guarded then
		reset(rec, pos, vel, now)
		rec.skip = true
	elseif pos == rec.pos and vel == rec.vel and vel.Magnitude > 1 then
		-- Nothing new arrived from the driver's device (a network stall): keep the old reference, so
		-- the next fresh sample is judged over the whole gap (more time = more braking allowed).
		rec.prevVel = rec.vel
	else
		local dt = now - rec.t
		local predicted = rec.pos + (rec.vel + vel) * (dt / 2)
		if dt <= 0 or dt > MAX_GAP or (pos - predicted).Magnitude > TELEPORT_ERR then
			reset(rec, pos, vel, now)
		else
			local v0 = rec.vel
			local h0 = Vector3.new(v0.X, 0, v0.Z)
			local h1 = Vector3.new(vel.X, 0, vel.Z)
			-- Sideways slide before, against either heading (the car may be spinning).
			local slide = 0
			if rec.fwd then
				slide = math.abs(h0:Dot(rec.fwd:Cross(Vector3.yAxis)))
			end
			if rec.fwdNow then
				slide = math.max(slide, math.abs(h0:Dot(rec.fwdNow:Cross(Vector3.yAxis))))
			end
			local flat = (car:GetAttribute("FlatUntil") or 0) > serverNow
			local brake = car:GetAttribute("Brake") or 120
			local friction = car:GetAttribute("TireFriction") or 1.7
			rec.solo = CarPhysics.ImpactExcess(h0.Magnitude, h1.Magnitude, v0.Magnitude, vel.Magnitude, slide, dt,
				brake, friction, flat, MIN_LOSS)
			local f = rec.fwd or rec.fwdNow
			if f then
				local d = h1 - h0
				local accelMax = (car:GetAttribute("Accel") or 60) * (car:GetAttribute("NitroAccel") or 1.6)
				jolt = CarPhysics.JoltExcess(d.X, d.Z, f.X, f.Z, dt, brake, accelMax, friction, JOLT_MIN)
				dv = d.Magnitude
			end
			rec.prevVel = v0
			rec.pos, rec.vel, rec.t = pos, vel, now
		end
	end
	rec.fwd = rec.fwdNow or rec.fwd
	-- A hit can show in either of two samples (replication), so keep the larger of the last two.
	rec.jolt, rec.joltLast = math.max(jolt, rec.joltLast), jolt
	rec.dv, rec.dvLast = math.max(dv, rec.dvLast), dv
	return rec
end

-- Two cars touching and closing fast: a hit for both.
local function pairCheck(i, j, now)
	local a, b = activeRecs[i], activeRecs[j]
	if a.skip or b.skip or not a.fwdNow or not b.fwdNow then
		return
	end
	local pa, pb = a.cf.Position, b.cf.Position
	local dx, dz = pb.X - pa.X, pb.Z - pa.Z
	local reach = a.radius + b.radius
	if math.abs(pb.Y - pa.Y) > 8 or dx * dx + dz * dz > reach * reach then
		return
	end
	local depth, nx, nz = CarPhysics.BoxContact(dx, dz, a.fwdNow.X, a.fwdNow.Z, a.halfW, a.halfL,
		b.fwdNow.X, b.fwdNow.Z, b.halfW, b.halfL)
	if not depth then
		return
	end
	a.touchT, b.touchT = now, now
	local rel = a.prevVel - b.prevVel
	local closing = rel.X * nx + rel.Z * nz
	local impact = CarPhysics.PairImpact(closing, math.max(a.jolt, b.jolt), math.max(a.dv, b.dv), PAIR_MIN)
	if impact <= 0 then
		return
	end
	local carA, carB = activeCars[i], activeCars[j]
	if now - (a.pairT[carB] or -math.huge) < PAIR_COOLDOWN then
		return
	end
	a.pairT[carB], b.pairT[carA] = now, now
	if impact > a.carImpact then
		a.carImpact, a.carOther = impact, j
	end
	if impact > b.carImpact then
		b.carImpact, b.carOther = impact, i
	end
end

-- Other cars may damage this one only if its driver is wanted, or it's a police car.
local function hurtByCars(car)
	if car:GetAttribute("Police") == true then
		return true
	end
	local driver = Players:GetPlayerByUserId(car:GetAttribute("DriverUserId") or 0)
	return driver ~= nil and (driver:GetAttribute("Heat") or 0) > 0
end

-- Is there solid world (not cars or people) around the car above wheel height? No -> it was traffic.
local worldParams = OverlapParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true
local function nearWorld(rec)
	local ignore = { Workspace:FindFirstChild("Vehicles") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	worldParams.FilterDescendantsInstances = ignore
	local size = rec.chassis.Size
	-- From just above the chassis bottom (the road and low kerbs don't count) to 1.5 over its top,
	-- 2 studs wider on every side.
	local box = Vector3.new(size.X + 4, size.Y + 1.2, size.Z + 4)
	local centre = rec.cf * CFrame.new(0, 0.9, 0)
	local floor = rec.cf.Position.Y - size.Y / 2 + 0.3
	for _, p in ipairs(Workspace:GetPartBoundsInBox(centre, box, worldParams)) do
		if p.Position.Y + p.ExtentsSize.Y / 2 > floor + 0.5 then
			return true
		end
	end
	return false
end

local function applyDamage(car, rec, damage, serverNow, why)
	rec.pending += damage
	if rec.pending < 1 then
		return
	end
	local whole = math.floor(rec.pending)
	rec.pending -= whole
	local old = car:GetAttribute("Health") or 100
	local new = math.max(0, old - whole)
	car:SetAttribute("Health", new)
	if studio then
		print(string.format("[VehicleDamage] %s %s: -%d -> %d", car.Name, why, whole, new))
	end
	local driver = Players:GetPlayerByUserId(car:GetAttribute("DriverUserId") or 0)
	if new <= 0 then
		rec.pending = 0
		car:SetAttribute("StallUntil", serverNow + STALL_SECONDS)
		if driver then
			notify:FireClient(driver, "CarStalled")
		end
	elseif old >= CarPhysics.SMOKE_HEALTH and new < CarPhysics.SMOKE_HEALTH and driver then
		notify:FireClient(driver, "CarSmoking")
	end
end

-- Damage that isn't a crash (bullets: WeaponService). Fractions add up (shotgun pellets).
function VehicleDamageService.Damage(car, amount, why)
	local rec = car and records[car]
	if not rec or type(amount) ~= "number" or amount <= 0 or (car:GetAttribute("Health") or 100) <= 0 then
		return
	end
	applyDamage(car, rec, amount, Workspace:GetServerTimeNow(), why or "shot")
end

local function resolve(i, now, serverNow)
	local rec, car = activeRecs[i], activeCars[i]
	if rec.skip or (not rec.carOther and rec.solo <= 0) then
		return -- nothing happened (almost every car, almost every tick)
	end
	local alive = (car:GetAttribute("Health") or 100) > 0
	local toughness = car:GetAttribute("Toughness") or 2
	local fair = hurtByCars(car)
	if rec.carOther then
		local other, otherCar = activeRecs[rec.carOther], activeCars[rec.carOther]
		local damage = 0
		if alive and fair then
			local ratio = other.chassis.AssemblyMass / math.max(rec.chassis.AssemblyMass, 1)
			damage = CarPhysics.CrashDamage(rec.carImpact, PAIR_MIN, ratio, toughness, CAR_RATE, MAX_HIT)
		end
		hitEvent:Fire(car, otherCar, rec.carImpact, damage)
		if damage > 0 then
			applyDamage(car, rec, damage, serverNow, string.format("hit by %s at %.0f", otherCar.Name, rec.carImpact))
		end
	elseif alive and now - rec.touchT > (fair and TOUCH_GRACE or SHOVE_GRACE) then
		local world = nearWorld(rec)
		local damage = CarPhysics.CrashDamage(rec.solo, SOLO_DEADZONE, 1, toughness, world and WORLD_RATE or TRAFFIC_RATE, MAX_HIT)
		if damage > 0 then
			applyDamage(car, rec, damage, serverNow, string.format("%s crash %.0f", world and "wall" or "traffic", rec.solo))
		end
	end
end

local function tick()
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	table.clear(activeCars)
	table.clear(activeRecs)
	for _, car in ipairs(folder:GetChildren()) do
		local ok, rec = pcall(sample, car, now, serverNow)
		if not ok then
			warn("[VehicleDamage] " .. tostring(rec))
		elseif rec then
			table.insert(activeCars, car)
			table.insert(activeRecs, rec)
		end
	end
	local n = #activeRecs
	for i = 1, n - 1 do
		for j = i + 1, n do
			pairCheck(i, j, now)
		end
	end
	for i = 1, n do
		local ok, err = pcall(resolve, i, now, serverNow)
		if not ok then
			warn("[VehicleDamage] " .. tostring(err))
		end
	end
	-- Don't hold on to cars between ticks.
	table.clear(activeCars)
	table.clear(activeRecs)
end

function VehicleDamageService.Init()
	notify = Remotes.Event("Notify")
	task.spawn(function()
		while true do
			task.wait(SAMPLE)
			local ok, err = pcall(tick)
			if not ok then
				warn("[VehicleDamage] " .. tostring(err))
			end
		end
	end)
end

return VehicleDamageService
