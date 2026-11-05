#!/bin/bash
# Empire (player businesses) logic tests: prelude + Roblox type stubs + Config.Businesses (and Config.Vehicles,
# to check the delivery car pool) as functions + scenarios. Covers the economy maths and rules that
# BusinessService and BusinessClient both use: the trickle, the register cap, the busy-shop bonus, upgrade
# prices, job pay (wash and detail delivery, tips and dents), Empire rank, the customer split, the crew cut,
# the break-in loss, unlocks, bays per level, and the M1 config (every layout spot is inside its lot). M2 (Palm
# Grind Coffee, with Config.Housing for the VIP homes and the home lots): the Coffee lot inside and clear of the
# road, the runtime lots, the homes and the other businesses; its levels; the rush-order clock, tip and pay
# (and the ~$1,250 a minute calibration); the cold brew's split, stamina and the customer-XP cap.
# Run: LUAU=<path to luau.exe> bash tools/logic-tests/businesses.sh
H="$(cd "$(dirname "$0")" && pwd)"
L="${LUAU:-luau}" # the Luau CLI (github.com/luau-lang/luau releases); set LUAU to its path
SRC="${1:-$H/../../src/shared/Config/Businesses.lua}" # another copy of Config/Businesses.lua to test, if given
VEH="$H/../../src/shared/Config/Vehicles.lua"
HOU="$H/../../src/shared/Config/Housing.lua"
OUT="${TMPDIR:-${TEMP:-/tmp}}/theft-logic-tests"
mkdir -p "$OUT"

# Just enough of Vector3 / CFrame / Color3 for the configs to load and for Businesses.At to place points.
STUBS='
local V3 = {}
V3.__index = V3
Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
Vector3.zero = Vector3.new(0, 0, 0)
V3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end
	return rawget(V3, k)
end
-- A CFrame here is a position plus a yaw-only rotation (all the lots need): right = (cos, 0, -sin), back = (sin, 0, cos).
local CF = {}
CF.__index = CF
CFrame = {}
local function cf(p, yaw)
	return setmetatable({ Position = p, yaw = yaw or 0 }, CF)
end
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return cf(x, 0)
	end
	return cf(Vector3.new(x, y, z), 0)
end
function CFrame.Angles(_, y, _)
	return cf(Vector3.zero, y or 0)
end
function CFrame.lookAt(at, target)
	local d = target - at
	-- the yaw whose look (-Z turned by yaw) is d: look = (-sin, 0, -cos)
	return cf(at, math.atan2(-d.X, -d.Z))
end
CF.__mul = function(a, b)
	local c, s = math.cos(a.yaw), math.sin(a.yaw)
	local p = b.Position
	local world = Vector3.new(a.Position.X + p.X * c + p.Z * s, a.Position.Y + p.Y, a.Position.Z - p.X * s + p.Z * c)
	return cf(world, a.yaw + b.yaw)
end
Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
Color3.new = function(r, g, b) return { R = r, G = g, B = b } end
workspace = { Gravity = 196.2 }
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
NEAR = near
'

scenario() {
	local name="$1" body="$2"
	local f="$OUT/biz_$name.luau"
	{
		cat "$H/prelude.luau"
		echo "$STUBS"
		echo "local Vehicles = (function()"
		cat "$VEH"
		echo "end)()"
		echo "local Housing = (function()"
		cat "$HOU"
		echo "end)()"
		echo "local Businesses = (function()"
		cat "$SRC"
		echo "end)()"
		echo "local CW = Businesses.ById.CarWash"
		echo "local PG = Businesses.ById.PalmGrind"
		echo "$body"
		echo 'if ERRORS then print("FAIL coroutine errors: " .. ERRORS) end'
		echo 'print(FAILS and ("== " .. FAILS .. " FAILED") or "== all passed")'
	} > "$f"
	echo "== $name"
	"$L" "$f" 2>&1
}

scenario trickle_cap_and_busy_bonus '
check("level 1 trickles $60/min", Businesses.Trickle(CW, 1, false) == 60)
check("level 5 trickles $150/min", Businesses.Trickle(CW, 5, false) == 150)
check("levels step evenly 60 83 105 128 150", CW.Levels[2].Trickle == 83 and CW.Levels[3].Trickle == 105 and CW.Levels[4].Trickle == 128)
check("busy bonus is +25%", Businesses.Trickle(CW, 1, true) == 75, Businesses.Trickle(CW, 1, true))
local caps = {}
for l = 1, 5 do caps[l] = Businesses.Cap(CW, l) end
check("register sizes 2000 3750 5500 7250 9000", caps[1] == 2000 and caps[2] == 3750 and caps[3] == 5500 and caps[4] == 7250 and caps[5] == 9000,
	table.concat(caps, " "))
local r, e = Businesses.Accrue(CW, 0, 1, 30, false)
check("30 s at level 1 earns $30", NEAR(r, 30) and NEAR(e, 30), r)
r, e = Businesses.Accrue(CW, 0, 1, 30, true)
check("30 s busy earns $37.50", NEAR(r, 37.5), r)
r, e = Businesses.Accrue(CW, 1990, 1, 60, false)
check("stops at the cap", r == 2000 and NEAR(e, 10), r)
r, e = Businesses.Accrue(CW, 2500, 1, 60, false)
check("over the cap: keeps it, earns nothing", r == 2500 and e == 0)
r, e = Businesses.Accrue(CW, 0, 1, -5, false)
check("negative time earns nothing", r == 0 and e == 0)
r, e = Businesses.Accrue(CW, 0 / 0, 1, 30, false)
check("a NaN register is treated as 0", NEAR(r, 30), r)
check("fills from empty in ~33 min at level 1", NEAR(Businesses.Cap(CW, 1) / Businesses.Trickle(CW, 1), 33.33, 0.01))
check("level clamps (0 -> 1, 9 -> 5)", Businesses.Cap(CW, 0) == 2000 and Businesses.Cap(CW, 9) == 9000)
local old = Businesses.RateScale
Businesses.RateScale = 0.5
check("RateScale halves the trickle", Businesses.Trickle(CW, 1) == 30)
check("RateScale halves job pay too", Businesses.WashPay(CW, 1, false) == 210, Businesses.WashPay(CW, 1, false))
Businesses.RateScale = old
check("trickle alone pays the price back in 6-8 h", Businesses.PaybackHours(CW) >= 6 and Businesses.PaybackHours(CW) <= 8, Businesses.PaybackHours(CW))'

scenario upgrades_and_bays '
check("level 2 costs 40% ($10,000)", Businesses.UpgradePrice(CW, 1) == 10000)
check("level 3 costs 60% ($15,000)", Businesses.UpgradePrice(CW, 2) == 15000)
check("level 4 costs 80% ($20,000)", Businesses.UpgradePrice(CW, 3) == 20000)
check("level 5 costs 100% ($25,000)", Businesses.UpgradePrice(CW, 4) == 25000)
check("nothing past level 5", Businesses.UpgradePrice(CW, 5) == nil)
local nc = Businesses.ById.Nightclub
check("Nightclub level 2 = $100,000", Businesses.UpgradePrice(nc, 1) == 100000)
local bays = {}
for l = 1, 5 do bays[l] = Businesses.BayCount(CW, l) end
check("bays 1 2 3 3 3", table.concat(bays, " ") == "1 2 3 3 3", table.concat(bays, " "))
check("job pay +6% a level, +25% at 5", Businesses.JobMult(CW, 2) == 1.06 and Businesses.JobMult(CW, 5) == 1.25)'

scenario job_pay '
local W, D = Businesses.Wash, Businesses.Detail
local p, t = Businesses.WashPay(CW, 1, true)
check("clean wash at level 1: $420 + $140", p == 420 and t == 140, p .. "+" .. t)
p, t = Businesses.WashPay(CW, 1, false)
check("not clean: no tip", p == 420 and t == 0)
p, t = Businesses.WashPay(CW, 5, true)
check("level 5 wash: $525 + $175", p == 525 and t == 175, p .. "+" .. t)
-- The calibration in the config header: ~$1,150 a minute of work at level 1.
-- (Re-tuned Nov 4 after the code review: a typical wash is a ~30 s cycle, not 32.)
local washPerMin = (W.Pay + 0.85 * W.Tip) * 60 / 30
check("wash averages $1,050-1,200 a minute (30 s cycle, 85% clean)", washPerMin >= 1050 and washPerMin <= 1200, washPerMin)
local est = Businesses.DetailEstimate(1365)
check("estimate for 1,365 studs ~30 s", NEAR(est, 1365 / 75 + 12), est)
local dp, dt = Businesses.DetailPay(CW, 1, 1365, est, est, 0)
check("on time, no dents: full $300 tip", dt == 300, dt)
check("delivery base $500 + 65c a stud", dp == math.floor(500 + 0.65 * 1365 + 0.5), dp)
local perMin = (dp + 220) * 60 / 85
check("delivery averages $1,100-1,200 a minute (85 s cycle, $220 avg tip)", perMin >= 1100 and perMin <= 1200, perMin)
local _, late = Businesses.DetailPay(CW, 1, 1365, est * 1.25, est, 0)
check("25% over the estimate: half the tip", late == 150, late)
local _, veryLate = Businesses.DetailPay(CW, 1, 1365, est * 2, est, 0)
check("50%+ over: no tip", veryLate == 0, veryLate)
local _, dented = Businesses.DetailPay(CW, 1, 1365, est, est, 2)
check("two dents cost $120 of the tip", dented == 180, dented)
local _, wrecked = Businesses.DetailPay(CW, 1, 1365, est, est, 99)
check("the tip never goes negative", wrecked == 0)
local p5, t5 = Businesses.DetailPay(CW, 5, 1365, est, est, 0)
check("level 5 x1.25 on pay and tip", p5 == math.floor((500 + 0.65 * 1365) * 1.25 + 0.5) and t5 == 375, p5 .. "+" .. t5)
check("min wash time below a human (~20 s) and above the holds", W.MinTime < 20 and W.MinTime > W.SprayHold + W.RinseHold)
check("speed check: the delivery FastSlack matches taxis", D.FastSlack == 1.15)
-- Every customer car is a real, ordinary civilian car.
local okCars = true
for l, list in ipairs(D.Cars) do
	for _, id in ipairs(list) do
		local v = Vehicles.ById[id]
		if not v or v.Police or v.Boat or v.Hidden or v.Pass or v.UnlockHeists then
			okCars = false
			print("  bad car " .. tostring(id) .. " at level " .. l)
		end
	end
end
check("delivery cars: no police, boats, pass or heist-locked cars", okCars)'

scenario empire_rank '
check("0 XP = rank 1", Businesses.RankFor(0) == 1)
check("299 XP = rank 1", Businesses.RankFor(299) == 1)
check("300 XP = rank 2", Businesses.RankFor(300) == 2)
check("899 XP = rank 2, 900 = rank 3", Businesses.RankFor(899) == 2 and Businesses.RankFor(900) == 3)
check("3,500 XP = rank 5 (remote collect)", Businesses.RankFor(3500) == 5 and Businesses.Empire.RemoteCollect == 5)
check("20,000 XP = rank 10, and it stops there", Businesses.RankFor(20000) == 10 and Businesses.RankFor(1e9) == 10)
local r, share, into, need = Businesses.RankProgress(600)
check("600 XP: rank 2, halfway to 3", r == 2 and NEAR(share, 0.5) and into == 300 and need == 600, r .. " " .. share)
r, share, into, need = Businesses.RankProgress(25000)
check("past the top: full bar", r == 10 and share == 1 and need == 0)
check("titles: none at 6, Mogul at 7, Kingpin at 10", Businesses.TitleFor(6) == nil and Businesses.TitleFor(7) == "Mogul"
	and Businesses.TitleFor(10) == "Kingpin of the Coast")
local X = Businesses.Empire.XP
local first = X.Buy + X.UpgradePerLevel * 2 + 20 * X.Wash
check("buy + level 2 + 20 washes reaches rank 2", Businesses.RankFor(first) == 2, first)
check("Boat Rentals needs rank 2, the Nightclub rank 3", Businesses.Unlocked(Businesses.ById.BoatRentals, 1) == false
	and Businesses.Unlocked(Businesses.ById.BoatRentals, 2) and Businesses.Unlocked(Businesses.ById.Nightclub, 2) == false
	and Businesses.Unlocked(Businesses.ById.Nightclub, 3))
check("the Car Wash needs no rank", Businesses.Unlocked(CW, 1))'

scenario customers_crew_breakins '
local owner, sink = Businesses.Split(100)
check("a $100 shine: $70 to the owner, $30 sink", owner == 70 and sink == 30)
owner, sink = Businesses.Split(55)
check("odd prices still add up", owner + sink == 55 and owner == 38, owner .. "+" .. sink)
owner, sink = Businesses.Split(-5)
check("nothing for a negative price", owner == 0 and sink == 0)
check("crew cut is 20% of the crewmate pay", Businesses.CrewCutFor(635) == 127 and Businesses.CrewCutFor(0) == 0)
check("crew cut of a bad number is 0", Businesses.CrewCutFor(0 / 0) == 0)
check("break-in takes 10% of the register", Businesses.BreakInLoss(2000) == 200)
check("break-in loss rounds down", Businesses.BreakInLoss(1999) == 199)
check("break-in never takes more than there is", Businesses.BreakInLoss(5) == 0 and Businesses.BreakInLoss(0) == 0)
local B = Businesses.BreakIn
check("break-ins: 10 min in, 20 min apart, 2 minutes to stop", B.MinPlay == 600 and B.Gap == 1200 and B.Time == 120)
check("1-2 robbers, the register must hold $800+", B.Robbers[1] == 1 and B.Robbers[2] == 2 and B.MinRegister == 800)
check("busy bonus 25%, crew cut 20%, customer share 70%", Businesses.BusyBonus == 0.25 and Businesses.CrewCut == 0.2
	and Businesses.CustomerShare == 0.7)
check("the shine costs $100 and lasts 30 minutes", CW.Service.Price == 100 and Businesses.Shine.Seconds == 1800)'

scenario m1_m2_config '
local enabled = {}
for _, def in ipairs(Businesses.List) do
	if def.Enabled then table.insert(enabled, def.Id) end
end
check("M2: the Car Wash and Palm Grind are enabled, nothing else", #enabled == 2 and enabled[1] == "CarWash" and enabled[2] == "PalmGrind",
	table.concat(enabled, ","))
check("the launch switch is off for live servers", Businesses.Live == false)
local want = { CarWash = { 25000, 1, "Legit" }, PalmGrind = { 45000, 1, "Legit" }, PrintShop = { 90000, 1, "Shady" },
	BoatRentals = { 120000, 2, "Legit" }, Nightclub = { 250000, 3, "Legit" } }
local ok = true
for id, w in pairs(want) do
	local d = Businesses.ById[id]
	if not d or d.Price ~= w[1] or (d.Unlock or 1) ~= w[2] or d.Kind ~= w[3] or not d.Levels or #d.Levels ~= 5 then
		ok = false
		print("  wrong: " .. id)
	end
end
check("names, prices, unlocks and kinds as the PRD says", ok)
check("Coffee register $3k -> $12k, Nightclub trickle $180 -> $420", Businesses.ById.PalmGrind.Levels[1].Cap == 3000
	and Businesses.ById.PalmGrind.Levels[5].Cap == 12000 and Businesses.ById.Nightclub.Levels[1].Trickle == 180
	and Businesses.ById.Nightclub.Levels[5].Trickle == 420)
-- Every layout spot inside the 56 x 50 lot.
local inside = true
local function inLot(v, what)
	if math.abs(v.X) > 28 or math.abs(v.Z) > 25 then
		inside = false
		print("  outside the lot: " .. what)
	end
end
local Lo = CW.Layout
inLot(Lo.Door, "Door") inLot(Lo.Register, "Register") inLot(Lo.Exit, "Exit") inLot(Lo.Shine, "Shine") inLot(Lo.Pickup, "Pickup")
for i, v in ipairs(Lo.Robbers) do inLot(v, "Robber " .. i) end
for i, v in ipairs(Lo.Bays) do inLot(v, "Bay " .. i) end
check("every Car Wash spot is inside its lot", inside)
check("as many bay spots as level 5 opens", #Lo.Bays >= Businesses.BayCount(CW, 5))
-- Lot space: -Z is the street side, and the Car Wash faces Solana Avenue to its west.
local door = Businesses.DoorPosition(CW)
local centre = CW.Position
check("the door is in the world near the lot (within 35 studs)", (door - centre).Magnitude <= 35, (door - centre).Magnitude)
local street = Businesses.At(CW, Vector3.new(0, 0, -25))
check("lot-space -Z faces the street (west, toward Solana Ave)", street.X < centre.X - 20, street.X)'

# ---------------------------------------------------------------- M2: Palm Grind Coffee

scenario coffee_lot '
-- Every Coffee layout spot inside the 56 x 50 lot (the café, the counter spots, where robbers run to).
local inside = true
local Lo = PG.Layout
for name, v in pairs({ Door = Lo.Door, Register = Lo.Register, Exit = Lo.Exit, Service = Lo.Service, Orders = Lo.Orders,
	Robber1 = Lo.Robbers[1], Robber2 = Lo.Robbers[2] }) do
	if math.abs(v.X) > 28 or math.abs(v.Z) > 25 then
		inside = false
		print("  outside the lot: " .. name)
	end
end
check("every Coffee spot is inside its lot", inside)
check("two robber spots, in front of the counter (z < 9) and facing the register", #Lo.Robbers == 2 and Lo.Robbers[1].Z < 9
	and Lo.Robbers[2].Z < 9 and Lo.Register.Z > 9)
check("the door is in the world near the lot (within 35 studs)", (Businesses.DoorPosition(PG) - PG.Position).Magnitude <= 35)
-- The world box of a lot (x0, x1, z0, z1) from its four corners.
local function box(def)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs({ { -28, -25 }, { 28, -25 }, { -28, 25 }, { 28, 25 } }) do
		local p = Businesses.At(def, Vector3.new(c[1], 0, c[2]))
		x0, x1, z0, z1 = math.min(x0, p.X), math.max(x1, p.X), math.min(z0, p.Z), math.max(z1, p.Z)
	end
	return x0, x1, z0, z1
end
local x0, x1, z0, z1 = box(PG)
check("the Coffee lot spans x 480..530, z 877..933 (the box checked against the place file)", NEAR(x0, 480, 0.01) and NEAR(x1, 530, 0.01)
	and NEAR(z0, 877, 0.01) and NEAR(z1, 933, 0.01), string.format("%.1f..%.1f, %.1f..%.1f", x0, x1, z0, z1))
local street = Businesses.At(PG, Vector3.new(0, 0, -25))
check("lot-space -Z faces the street (west, toward Marina Link at x = 450)", street.X < PG.Position.X - 20, street.X)
check("its street edge is 12+ studs from Marina Link (x 434..466)", x0 - 466 >= 12, x0 - 466)
local function clear(ax0, ax1, az0, az1, bx0, bx1, bz0, bz1, margin)
	return ax1 + margin <= bx0 or bx1 + margin <= ax0 or az1 + margin <= bz0 or bz1 + margin <= az0
end
-- The runtime lots (Restyle.RUNTIME_LOTS and the services that build at start-up), as checked on Nov 4.
local ok = true
for _, r in ipairs({ { -210, -90, -543, -457, "Hideout" }, { 1668, 1700, 975, 1110, "east" }, { -278, -218, -354, -306, "downtown" },
	{ 545, 695, 725, 835, "Car Meet" }, { 537, 583, 617, 663, "Courier Depot" }, { -549, -401, 1164, 1276, "Big Score depot" },
	{ -272, -50, -986, -894, "Big Score reserve" } }) do
	if not clear(x0, x1, z0, z1, r[1], r[2], r[3], r[4], 10) then
		ok = false
		print("  overlaps the " .. r[5] .. " lot")
	end
end
check("clear of every runtime lot (10+ studs)", ok)
-- Every home lot (Config.Housing: x -62..62, z -100 (the street) ..42 in its own lot space).
ok = true
for _, home in ipairs(Housing.List) do
	local hx0, hx1, hz0, hz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs({ { -62, -100 }, { 62, -100 }, { -62, 42 }, { 62, 42 } }) do
		local p = (Housing.Frame(home) * CFrame.new(c[1], 0, c[2])).Position
		hx0, hx1, hz0, hz1 = math.min(hx0, p.X), math.max(hx1, p.X), math.min(hz0, p.Z), math.max(hz1, p.Z)
	end
	if not clear(x0, x1, z0, z1, hx0, hx1, hz0, hz1, 10) then
		ok = false
		print("  overlaps " .. home.Id)
	end
end
check("clear of every home lot (10+ studs)", ok)
-- No two enabled businesses share ground.
ok = true
for _, a in ipairs(Businesses.List) do
	for _, b in ipairs(Businesses.List) do
		if a ~= b and a.Enabled and b.Enabled and a.Position and b.Position then
			local ax0, ax1, az0, az1 = box(a)
			local bx0, bx1, bz0, bz1 = box(b)
			if not clear(ax0, ax1, az0, az1, bx0, bx1, bz0, bz1, 20) then
				ok = false
				print("  " .. a.Id .. " overlaps " .. b.Id)
			end
		end
	end
end
check("no two business lots within 20 studs of each other", ok)'

scenario coffee_levels '
local t, c = {}, {}
for l = 1, 5 do
	t[l] = Businesses.Trickle(PG, l, false)
	c[l] = Businesses.Cap(PG, l)
end
check("trickle 80 110 140 170 200 a minute", table.concat(t, " ") == "80 110 140 170 200", table.concat(t, " "))
check("registers 3000 5250 7500 9750 12000", table.concat(c, " ") == "3000 5250 7500 9750 12000", table.concat(c, " "))
check("upgrades 18,000 / 27,000 / 36,000 / 45,000", Businesses.UpgradePrice(PG, 1) == 18000 and Businesses.UpgradePrice(PG, 2) == 27000
	and Businesses.UpgradePrice(PG, 3) == 36000 and Businesses.UpgradePrice(PG, 4) == 45000 and Businesses.UpgradePrice(PG, 5) == nil)
check("$45,000, legit, no Empire rank needed, enabled", PG.Price == 45000 and PG.Kind == "Legit" and Businesses.Unlocked(PG, 1) and PG.Enabled == true)
check("trickle alone pays it back in 9-10 h (the PRD numbers)", Businesses.PaybackHours(PG) >= 9 and Businesses.PaybackHours(PG) <= 10,
	Businesses.PaybackHours(PG))
local d = {}
for l = 1, 5 do d[l] = Businesses.RushDrops(l) end
check("addresses an order: 1 2 2 3 3", table.concat(d, " ") == "1 2 2 3 3", table.concat(d, " "))
check("level clamps for drops (0 -> 1, 9 -> 3)", Businesses.RushDrops(0) == 1 and Businesses.RushDrops(9) == 3)
local Ru = Businesses.Rush
check("VIP orders only from level 4", Ru.VIPLevel == 4 and (Ru.VIPChance[3] or 0) == 0 and Ru.VIPChance[4] > 0 and Ru.VIPChance[5] >= Ru.VIPChance[4])
local homes = true
for _, id in ipairs(Ru.VIPHomes) do
	local home = Housing.ById[id]
	if not home or home.Price < 150000 then
		homes = false
		print("  not a big home: " .. tostring(id))
	end
end
check("every VIP home is a real big home in Config.Housing ($150k+)", homes and #Ru.VIPHomes >= 2)
check("START JOB at Palm Grind offers only RUSH ORDERS", Businesses.HasJob(PG, "Rush") and not Businesses.HasJob(PG, "Wash")
	and #PG.Jobs == 1 and PG.Jobs[1].Label == "RUSH ORDERS")
check("the Car Wash keeps WASH A CAR and DELIVER A CAR", Businesses.HasJob(CW, "Wash") and Businesses.HasJob(CW, "Detail")
	and not Businesses.HasJob(CW, "Rush"))
check("every level says what it adds", PG.Levels[1].Adds ~= nil and PG.Levels[5].Adds ~= nil and string.find(PG.Levels[5].Adds, "ooftop") ~= nil)
check("its own map letter and colour", PG.MapLetter == "E" and PG.MapColor ~= nil and PG.MapColor ~= CW.MapColor)'

scenario rush_pay '
local Ru = Businesses.Rush
check("the first address clock: road / 45 + 18 s", NEAR(Businesses.RushTimer(910, true), 910 / 45 + 18), Businesses.RushTimer(910, true))
check("the next address clock: road / 45 + 8 s", NEAR(Businesses.RushTimer(650, false), 650 / 45 + 8), Businesses.RushTimer(650, false))
local T = 40
check("full tip straight away", Businesses.RushTipShare(0, T) == 1)
check("full tip with 35% of the clock left", NEAR(Businesses.RushTipShare(T * 0.65, T), 1))
check("half the tip with 17.5% left", NEAR(Businesses.RushTipShare(T * 0.825, T), 0.5), Businesses.RushTipShare(T * 0.825, T))
check("no tip at 0:00", Businesses.RushTipShare(T, T) == 0)
check("no tip late", Businesses.RushTipShare(T * 2, T) == 0)
check("a bad time is never an error", Businesses.RushTipShare(0 / 0, T) == 1 and Businesses.RushTipShare(5, 0 / 0) >= 0)
-- One address, the first and last of its order, on time.
local p, tip = Businesses.RushPay(PG, 1, 910, 910, true, 0, 40, false)
check("order pay + drop pay + 40c a stud there and back", p == math.floor(330 + 60 + 0.4 * 910 + 0.4 * 910 + 0.5), p)
check("the full tip is $200 at level 1", tip == 200, tip)
local lp, ltip = Businesses.RushPay(PG, 1, 910, 910, true, 41, 40, false)
check("late still pays the base, just no tip", lp == p and ltip == 0, lp .. "+" .. ltip)
local mp = Businesses.RushPay(PG, 1, 650, 0, false, 0, 22, false)
check("a middle address: drop pay + 40c a stud only", mp == math.floor(60 + 0.4 * 650 + 0.5), mp)
local vp, vtip = Businesses.RushPay(PG, 1, 650, 1000, false, 0, 22, true)
check("VIP: x1.5 on its drop pay, road and tip (not the drive back)", vp == math.floor((60 + 0.4 * 650) * 1.5 + 0.4 * 1000 + 0.5) and vtip == 300,
	vp .. "+" .. vtip)
local p5, t5 = Businesses.RushPay(PG, 5, 910, 910, true, 0, 40, false)
check("level 5 x1.25 on pay and tip", p5 == math.floor((330 + 60 + 0.4 * 1820) * 1.25 + 0.5) and t5 == 250, p5 .. "+" .. t5)
check("the strip shows the tip the server pays", Businesses.RushTip(PG, 3, 30, 40, true) == select(2, Businesses.RushPay(PG, 3, 500, 0, false, 30, 40, true)))
local old = Businesses.RateScale
Businesses.RateScale = 0.5
local hp = Businesses.RushPay(PG, 1, 910, 910, true, 0, 40, false)
check("RateScale halves rush pay too", math.abs(hp - p * 0.5) <= 1, hp)
Businesses.RateScale = old
-- The calibration in the config header: ~45 studs/s on the road (1.3x the straight line), ~17 s at the café
-- an order, 3 s to stop at each address, 6 s to walk to the car after the grab; a 700-stud first leg, 500-stud
-- next legs, the drive back from where the order ends.
local function order(n)
	local SPEED, STOP, CAFE, F = 45, 3, 17, 1.3
	local back = math.sqrt(700 ^ 2 + (n - 1) * 500 ^ 2) * F
	local secs, pay = CAFE + back / SPEED, 0
	for i = 1, n do
		local road = (i == 1 and 700 or 500) * F
		local timer = Businesses.RushTimer(road, i == 1)
		local took = (i == 1 and 6 or 0) + road / SPEED + STOP
		local a, b = Businesses.RushPay(PG, 1, road, i == n and back or 0, i == 1, took, timer, false)
		pay += a + b
		secs += road / SPEED + STOP
	end
	return pay * 60 / secs, secs
end
local one, s1 = order(1)
local two = order(2)
local three = order(3)
check("one address: ~$1,250 a minute of work at level 1 ($1,150-1,350)", one >= 1150 and one <= 1350, math.floor(one) .. " (" .. math.floor(s1) .. " s)")
check("two addresses: no more than +10%", two >= one and two <= one * 1.1, math.floor(two))
check("three addresses: no more than +10%", three >= one and three <= one * 1.1, math.floor(three))
check("a typical driver keeps about 2/3 of the tip on the first address",
	NEAR(Businesses.RushTipShare(6 + 910 / 45 + 3, Businesses.RushTimer(910, true)), 0.67, 0.05))
check("speed check and ring as a taxi", Ru.FastSlack == 1.15 and Ru.StopRadius == 32 and Ru.StopSpeed == 6)
check("grab hold 2 s, a little lag allowed", Ru.GrabHold == 2 and Ru.HoldSlack < Ru.GrabHold)
check("Empire XP for every address", Businesses.Empire.XP.Rush > 0)'

scenario cold_brew_customers '
local CB = Businesses.ColdBrew
check("a cold brew is $60 for 5 minutes", PG.Service.Price == 60 and PG.Service.Kind == "ColdBrew" and CB.Seconds == 300)
local owner, sink = Businesses.Split(PG.Service.Price)
check("$42 to the featured owner, $18 sink (70/30, as the shine)", owner == 42 and sink == 18, owner .. "+" .. sink)
check("+25% sprint stamina: the sprint drains at 0.8x", NEAR(Businesses.ColdBrewDrain(1000, 900), 0.8), Businesses.ColdBrewDrain(1000, 900))
check("worn off: the normal drain", Businesses.ColdBrewDrain(900, 1000) == 1 and Businesses.ColdBrewDrain(nil, 1000) == 1
	and Businesses.ColdBrewDrain("x", 1000) == 1)
check("a full sprint lasts 25% longer (100 / 8 = 12.5 s -> 15.6 s)", NEAR(100 / (8 * Businesses.ColdBrewDrain(1, 0)), 15.625))
check("no double-buying: refused while more than 4 of the 5 minutes are left", CB.RebuyLeft == 240 and CB.RebuyLeft < CB.Seconds)
-- The customer-XP cap (the same path for the shine and the cold brew): 2 a buyer an hour.
local yes1, rec = Businesses.CustomerXP(nil, 100)
local yes2
yes2, rec = Businesses.CustomerXP(rec, 200)
local yes3
yes3, rec = Businesses.CustomerXP(rec, 300)
check("the first two buys in an hour earn the owner Empire XP", yes1 and yes2)
check("the third in the same hour does not", yes3 == false and rec.count == 2)
local yes4
yes4, rec = Businesses.CustomerXP(rec, 100 + 3600)
check("an hour after the first, it counts again", yes4 and rec.count == 1)
local yes5 = Businesses.CustomerXP({ since = "x" }, 50)
check("a broken record starts over (and counts)", yes5 == true)
check("the owner toast words", CW.Service.Words == "a shine" and PG.Service.Words == "a cold brew")'
