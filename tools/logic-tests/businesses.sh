#!/bin/bash
# Empire (player businesses) logic tests: prelude + Roblox type stubs + Config.Businesses (and Config.Vehicles,
# to check the delivery car pool) as functions + scenarios. Covers the economy maths and rules that
# BusinessService and BusinessClient both use: the trickle, the register cap, the busy-shop bonus, upgrade
# prices, job pay (wash and detail delivery, tips and dents), Empire rank, the customer split, the crew cut,
# the break-in loss, unlocks, bays per level, and the M1 config (every layout spot is inside its lot). M2 (Palm
# Grind Coffee, with Config.Housing for the VIP homes and the home lots): the Coffee lot inside and clear of the
# road, the runtime lots, the homes and the other businesses; its levels; the rush-order clock, tip and pay
# (and the ~$1,250 a minute calibration); the cold brew's split, stamina and the customer-XP cap. M3 (the Backlot
# Print Shop): its lot (inside, in Rustwater Docks, clear of the road, the pads, the runtime lots, the homes and the
# other businesses), its levels, the print timing grades, the streak and the press-run maths, the launder pay and
# the clean-run bonus, the ~$1,600 a minute calibration with the risk (a seeded simulation of the timing game), the
# heat meter and the tip-off odds, the raid warrant odds, timing, seizure and rewards, and break-ins never picking
# a shady business. THE FUN PASS (launch/18-BUSINESS-FUN-PASS.md): the wash gauges PERFECT windows (and how often a
# new player lands one), the stars, the tip thirds, the streak multipliers and caps, the special customers odds and
# pay, the dirt odds and taps, the delivery sports cars, stars and no-dent streak, the rush medals by time, the gold
# streak, rush hour and the perfect run, seeded simulations of all three jobs (each within 5% of its $/min target
# with every bonus inside), and the Nov 4 trickle raise (payback 7.5-8 h at Palm Grind and the Print Shop). M4
# (Coastline Boat Rentals, Empire 2): its lot on the water (inside, clear of Marina Boat Sales' runtime lot, the boat
# pads, the homes and the other businesses; the gangway lands on the marina pier's end; the hulls fit their slips),
# its levels and the Nov 4 treatment of its trickle, the boats and tourists by level, the tour routes (stops at sea,
# rings apart, legs clear of the Ferris pier, longer routes at higher levels), the ring test along a fast boat's
# stretch, the photo-stop grading, the tourists' mood, the tour pay (stars, tip shares, streak, the specials), the
# special-tour odds by day and night, a seeded ~$1,400 a minute simulation, the jet ski rental (split, timer, the
# honest label) and the Empire 2 gate. M5 (the Afterglow Nightclub, Empire 3): its lot on the beach by the boardwalk
# (inside, clear of the road, Club Nova, the pads, the runtime lots, the homes and the other businesses), the map
# letters, its levels and the night x2 (the night share worked out from WorldService own day), the Nov 4 treatment of
# its trickle (payback ~7.8 h on the day-and-night average, registers 36-60 min to fill), the VIP pickup maths (par,
# the stop grades, the stars, the comfort, the pay, the night pay, the specials), a seeded ~$1,500 a minute simulation,
# the paparazzi (odds, cars, losing them), the cover charge and the VIP booth (splits, times, the club off the map),
# the back room (the night card game, the cap, WASH, the raid odds on its stock) and the Empire 3 gate.
# Run: LUAU=<path to luau.exe> bash tools/logic-tests/businesses.sh
H="$(cd "$(dirname "$0")" && pwd)"
L="${LUAU:-luau}" # the Luau CLI (github.com/luau-lang/luau releases); set LUAU to its path
SRC="${1:-$H/../../src/shared/Config/Businesses.lua}" # another copy of Config/Businesses.lua to test, if given
VEH="$H/../../src/shared/Config/Vehicles.lua"
HOU="$H/../../src/shared/Config/Housing.lua"
WORLD="$H/../../src/server/Services/WorldService.lua"
OUT="${TMPDIR:-${TEMP:-/tmp}}/theft-logic-tests"
# (M5) The game day, as WorldService has it: its ACTS table and its nightness rule, for the night-share check.
WORLD_DAY="$(sed -n '/^local ACTS = {/,/^}/p' "$WORLD"; sed -n '/^local function nightnessAt/,/^end/p' "$WORLD")"
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
		echo "local PS = Businesses.ById.PrintShop"
		echo "local BR = Businesses.ById.BoatRentals"
	echo "local NC = Businesses.ById.Nightclub"
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
check("RateScale halves job pay too", Businesses.WashPay(CW, 1, {}) == 215, Businesses.WashPay(CW, 1, {}))
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
local best = { spray = "Perfect", rinse = "Perfect", quick = true }
local p, t, stars = Businesses.WashPay(CW, 1, best)
check("a ★★★ wash at level 1: $430 + the whole $165 tip", p == 430 and t == 165 and stars == 3, p .. "+" .. t .. " " .. stars)
p, t, stars = Businesses.WashPay(CW, 1, {})
check("no grades, not quick: the pay only, ★", p == 430 and t == 0 and stars == 1, p .. "+" .. t)
p, t = Businesses.WashPay(CW, 5, best)
check("level 5 ★★★ wash: $538 + $206 (x1.25)", p == 538 and t == 206, p .. "+" .. t)
-- (The ~$1,150 a minute calibration is the seeded simulation in wash_calibration below.)
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
-- The least the server can take for a wash: both gauges let go at Min (less the slack), the quickest car taps
-- (4 spots of bugs: 8 taps, 7 gaps), and the 0.5 s a hold may start before "car ready".
local least = (W.Gauge.spray.Min - W.Slack) + (W.Gauge.rinse.Min - W.Slack) + 7 * W.ScrubGap - 0.5
check("MinTime never refuses an honest wash (under the least the gauges allow) but is not 0", W.MinTime <= least and W.MinTime >= 5,
	W.MinTime .. " vs " .. least)
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
check("M5: all five businesses are enabled, in the PRD order", #enabled == 5 and enabled[1] == "CarWash"
	and enabled[2] == "PalmGrind" and enabled[3] == "PrintShop" and enabled[4] == "BoatRentals" and enabled[5] == "Nightclub", table.concat(enabled, ","))
check("the launch switch is on (the owner said go, Nov 6 2026)", Businesses.Live == true)
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
check("Coffee register $3.6k -> $14.4k (Nov 4 raise), Nightclub trickle $375 -> $875 (M5: the Nov 4 treatment)", Businesses.ById.PalmGrind.Levels[1].Cap == 3600
	and Businesses.ById.PalmGrind.Levels[5].Cap == 14400 and Businesses.ById.Nightclub.Levels[1].Trickle == 375
	and Businesses.ById.Nightclub.Levels[5].Trickle == 875)
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
check("trickle 96 132 168 204 240 a minute (the PRD first numbers x1.2, Nov 4)", table.concat(t, " ") == "96 132 168 204 240", table.concat(t, " "))
check("registers 3600 6300 9000 11700 14400", table.concat(c, " ") == "3600 6300 9000 11700 14400", table.concat(c, " "))
check("upgrades 18,000 / 27,000 / 36,000 / 45,000", Businesses.UpgradePrice(PG, 1) == 18000 and Businesses.UpgradePrice(PG, 2) == 27000
	and Businesses.UpgradePrice(PG, 3) == 36000 and Businesses.UpgradePrice(PG, 4) == 45000 and Businesses.UpgradePrice(PG, 5) == nil)
check("$45,000, legit, no Empire rank needed, enabled", PG.Price == 45000 and PG.Kind == "Legit" and Businesses.Unlocked(PG, 1) and PG.Enabled == true)
check("trickle alone pays it back in 7.5-8 h (was ~9.4 h)", Businesses.PaybackHours(PG) >= 7.5 and Businesses.PaybackHours(PG) <= 8,
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
check("full tip with 22% of the clock left (a GOLD)", NEAR(Businesses.RushTipShare(T * 0.78, T), 1) and Ru.TipFull == 0.22)
check("half the tip with 11% left", NEAR(Businesses.RushTipShare(T * 0.89, T), 0.5), Businesses.RushTipShare(T * 0.89, T))
check("no tip at 0:00", Businesses.RushTipShare(T, T) == 0)
check("no tip late", Businesses.RushTipShare(T * 2, T) == 0)
check("a bad time is never an error", Businesses.RushTipShare(0 / 0, T) == 1 and Businesses.RushTipShare(5, 0 / 0) >= 0)
-- One address, the first and last of its order, on time.
local p, tip = Businesses.RushPay(PG, 1, 910, 910, true, 0, 40, false)
check("order pay + drop pay + 40c a stud there and back", p == math.floor(320 + 60 + 0.4 * 910 + 0.4 * 910 + 0.5), p)
check("the full tip is $150 at level 1", tip == 150, tip)
local lp, ltip = Businesses.RushPay(PG, 1, 910, 910, true, 41, 40, false)
check("late still pays the base, just no tip", lp == p and ltip == 0, lp .. "+" .. ltip)
local mp = Businesses.RushPay(PG, 1, 650, 0, false, 0, 22, false)
check("a middle address: drop pay + 40c a stud only", mp == math.floor(60 + 0.4 * 650 + 0.5), mp)
local vp, vtip = Businesses.RushPay(PG, 1, 650, 1000, false, 0, 22, true)
check("VIP: x1.5 on its drop pay, road and tip (not the drive back)", vp == math.floor((60 + 0.4 * 650) * 1.5 + 0.4 * 1000 + 0.5) and vtip == 225,
	vp .. "+" .. vtip)
local p5, t5 = Businesses.RushPay(PG, 5, 910, 910, true, 0, 40, false)
check("level 5 x1.25 on pay and tip", p5 == math.floor((320 + 60 + 0.4 * 1820) * 1.25 + 0.5) and t5 == 188, p5 .. "+" .. t5)
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
check("the typical driver of this fixed-speed model just makes a GOLD on the first address (~24% left)",
	Businesses.RushMedal(6 + 910 / 45 + 3, Businesses.RushTimer(910, true)) == "Gold")
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

# ---------------------------------------------------------------- M3: the Backlot Print Shop

scenario printshop_lot '
-- Every Print Shop layout spot inside the 56 x 50 lot.
local inside = true
local Lo = PS.Layout
local spots = { Door = Lo.Door, Register = Lo.Register, Search = Lo.Search, Bay = Lo.Bay, Load = Lo.Load, RaidCar = Lo.RaidCar,
	Tray = Lo.Tray, Cash = Lo.Cash }
for i, v in ipairs(Lo.Stations) do spots["Station" .. i] = v end
for i, v in ipairs(Lo.RaidStand) do spots["RaidStand" .. i] = v end
for name, v in pairs(spots) do
	if math.abs(v.X) > 28 or math.abs(v.Z) > 25 then
		inside = false
		print("  outside the lot: " .. name)
	end
end
check("every Print Shop spot is inside its lot", inside)
check("three print stations, the press last", #Lo.Stations == 3 and #Businesses.Print.Stations == 3)
check("the stations sit inside the building, the bay and the cart on the forecourt", Lo.Stations[1].Z > 0 and Lo.Stations[3].Z > 0
	and Lo.Bay.Z < -2 and Lo.Load.Z < -2)
check("the stations are 10+ studs apart (you walk between them)", (Lo.Stations[2] - Lo.Stations[1]).Magnitude >= 10
	and (Lo.Stations[3] - Lo.Stations[2]).Magnitude >= 10)
local function box(def)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs({ { -28, -25 }, { 28, -25 }, { -28, 25 }, { 28, 25 } }) do
		local p = Businesses.At(def, Vector3.new(c[1], 0, c[2]))
		x0, x1, z0, z1 = math.min(x0, p.X), math.max(x1, p.X), math.min(z0, p.Z), math.max(z1, p.Z)
	end
	return x0, x1, z0, z1
end
local x0, x1, z0, z1 = box(PS)
check("the Print Shop lot spans x -424..-368, z 1562..1612 (the box checked against the place file)", NEAR(x0, -424, 0.01)
	and NEAR(x1, -368, 0.01) and NEAR(z0, 1562, 0.01) and NEAR(z1, 1612, 0.01), string.format("%.1f..%.1f, %.1f..%.1f", x0, x1, z0, z1))
check("it is on Rustwater Docks ground (x -900..450, z 600..2000)", x0 >= -900 and x1 <= 450 and z0 >= 600 and z1 <= 2000)
local street = Businesses.At(PS, Vector3.new(0, 0, -25))
check("lot-space -Z faces the street (south, toward the z = 1650 street)", street.Z > PS.Position.Z + 20, street.Z)
check("its street edge is 12+ studs from the road (z 1634..1666)", 1634 - z1 >= 12, 1634 - z1)
check("clear of the x = -650 and x = -300 streets (x -666..-634, -316..-284) by 12+", x0 - (-634) >= 12 and (-316) - x1 >= 12)
local function clear(ax0, ax1, az0, az1, bx0, bx1, bz0, bz1, margin)
	return ax1 + margin <= bx0 or bx1 + margin <= ax0 or az1 + margin <= bz0 or bz1 + margin <= az0
end
local ok = true
for _, r in ipairs({ { -210, -90, -543, -457, "AutoNeon" }, { 1668, 1700, 975, 1110, "Marina Boat Sales" }, { -278, -218, -354, -306, "Zap Shack" },
	{ 545, 695, 725, 835, "Car Meet" }, { 537, 583, 617, 663, "Courier Depot" }, { -549, -401, 1164, 1276, "Big Score depot" },
	{ -272, -50, -986, -894, "Big Score reserve" },
	-- the gameplay pads near the Docks (the place file), with Restyle s 20-stud margin
	{ -520, -430, 1055, 1145, "Hideout pad" }, { -805, -755, 1555, 1605, "Chop Shop pad" }, { -572, -548, 1008, 1032, "Fence pad" },
	{ -527, -423, 1049, 1071, "Hideout car pads" }, { 192, 208, 1472, 1488, "ATM3" }, { 54, 70, 1390, 1410, "Solana Ave ramp" },
	{ -210, -190, 1854, 1870, "Docks Drop ramp" }, { 230, 270, 800, 840, "Spray and Go" } }) do
	if not clear(x0, x1, z0, z1, r[1], r[2], r[3], r[4], 20) then
		ok = false
		print("  too close to the " .. r[5])
	end
end
check("clear of every runtime lot and gameplay pad near the Docks (20+ studs)", ok)
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
ok = true
for _, other in ipairs({ CW, PG }) do
	local bx0, bx1, bz0, bz1 = box(other)
	if not clear(x0, x1, z0, z1, bx0, bx1, bz0, bz1, 200) then
		ok = false
		print("  near " .. other.Id)
	end
end
check("200+ studs from the Car Wash and Palm Grind", ok)
-- Inside the building (hold the door) vs the forecourt.
local function world(x, z) return Businesses.At(PS, Vector3.new(x, 2, z)) end
check("the presses are inside, the forecourt and the door step are not", Businesses.Inside(PS, world(0, 10)) and Businesses.Inside(PS, world(-20, 2))
	and not Businesses.Inside(PS, world(4, -14)) and not Businesses.Inside(PS, world(-19, -4)) and not Businesses.Inside(PS, world(22, 10)))
check("on the roof is not inside", not Businesses.Inside(PS, Businesses.At(PS, Vector3.new(0, 20, 10))))
check("the Car Wash has no inside box (only the shady shop uses it)", Businesses.Inside(CW, CW.Position) == false)'

scenario printshop_levels '
local t, c, st, ca = {}, {}, {}, {}
for l = 1, 5 do
	t[l] = Businesses.Trickle(PS, l, false)
	c[l] = Businesses.Cap(PS, l)
	st[l] = Businesses.Stock(l)
	ca[l] = Businesses.Carry(l)
end
check("trickle 192 257 321 386 450 a minute (the PRD first numbers x~1.75, Nov 4)", table.concat(t, " ") == "192 257 321 386 450", table.concat(t, " "))
check("registers 7000 11750 16500 21250 26000", table.concat(c, " ") == "7000 11750 16500 21250 26000", table.concat(c, " "))
check("upgrades 36,000 / 54,000 / 72,000 / 90,000", Businesses.UpgradePrice(PS, 1) == 36000 and Businesses.UpgradePrice(PS, 2) == 54000
	and Businesses.UpgradePrice(PS, 3) == 72000 and Businesses.UpgradePrice(PS, 4) == 90000 and Businesses.UpgradePrice(PS, 5) == nil)
check("$90,000, shady, no rank needed, enabled, map letter X", PS.Price == 90000 and PS.Kind == "Shady" and Businesses.Unlocked(PS, 1)
	and PS.Enabled == true and PS.MapLetter == "X" and PS.Style == "PrintShop")
check("its own map colour", PS.MapColor ~= nil and PS.MapColor ~= CW.MapColor and PS.MapColor ~= PG.MapColor)
local grows = true
for l = 2, 5 do grows = grows and st[l] > st[l - 1] and ca[l] > ca[l - 1] end
check("the stock and the load both grow every level", grows, table.concat(st, " ") .. " | " .. table.concat(ca, " "))
check("the back room holds 2.5+ loads at every level", (function()
	for l = 1, 5 do if st[l] < ca[l] * 2.5 then return false end end
	return true
end)())
check("START JOB offers PRINT and LAUNDER", Businesses.HasJob(PS, "Print") and Businesses.HasJob(PS, "Launder") and #PS.Jobs == 2
	and PS.Jobs[1].Label == "PRINT" and PS.Jobs[2].Label == "LAUNDER")
check("no player service at the Print Shop (PRD section 6)", PS.Service == nil)
check("every level says what it adds (5: the full counterfeit floor)", PS.Levels[1].Adds ~= nil and string.find(PS.Levels[5].Adds, "counterfeit") ~= nil)
local h = Businesses.PaybackHours(PS)
check("trickle alone pays it back in 7.5-8 h (was ~13.6 h)", h >= 7.5 and h <= 8, h)
check("Empire XP for printing, laundering and holding off a raid", Businesses.Empire.XP.Print > 0 and Businesses.Empire.XP.Launder > 0
	and Businesses.Empire.XP.RaidHeld > 0)'

scenario print_grades_and_streak '
local P = Businesses.Print
local s1 = P.Stations[1]
check("let go before Min: EARLY (it does not count)", Businesses.PrintGrade(1, s1.Min - 0.5) == "Early")
check("after Min, before the band: OK", Businesses.PrintGrade(1, s1.Sweet[1] - 0.5) == "Ok")
check("in the green band: PERFECT", Businesses.PrintGrade(1, (s1.Sweet[1] + s1.Sweet[2]) / 2) == "Perfect")
check("the band edges get the lag slack", Businesses.PrintGrade(1, s1.Sweet[1] - P.Slack + 0.01) == "Perfect"
	and Businesses.PrintGrade(1, s1.Sweet[2] + P.Slack - 0.01) == "Perfect" and Businesses.PrintGrade(1, s1.Sweet[2] + P.Slack + 0.05) == "Ok")
check("past the band, up to the full gauge: OK", Businesses.PrintGrade(1, s1.Full) == "Ok" and Businesses.PrintGrade(1, s1.Full + 5) == "Ok")
check("a bad number is never PERFECT", Businesses.PrintGrade(1, 0 / 0) == "Early" and Businesses.PrintGrade(9, 5) ~= nil)
local bandsOk, gap = true, true
for i, st in ipairs(P.Stations) do
	bandsOk = bandsOk and st.Min < st.Sweet[1] and st.Sweet[1] < st.Sweet[2] and st.Sweet[2] < st.Full
	gap = gap and (st.Sweet[2] - st.Sweet[1]) >= 0.6
	local _ = i
end
check("every station: Min < the band < Full", bandsOk)
check("every band is 0.6 s+ wide (fair on a phone), 0.9 s+ with the slack", gap)
check("the bands sit at different places on each gauge (a rhythm)", P.Stations[1].Sweet[1] / P.Stations[1].Full ~= P.Stations[2].Sweet[1] / P.Stations[2].Full
	and P.Stations[2].Sweet[1] / P.Stations[2].Full ~= P.Stations[3].Sweet[1] / P.Stations[3].Full)
local holds = 0
for _, st in ipairs(P.Stations) do holds += (st.Sweet[1] + st.Sweet[2]) / 2 end
check("holding to the bands: ~15.6 s of a ~30 s press run", NEAR(holds, 15.6, 0.3), holds)
-- The streak.
check("streak x1.0 with no PERFECT, +0.05 each", Businesses.StreakMult(0) == 1 and NEAR(Businesses.StreakMult(1), 1.05) and NEAR(Businesses.StreakMult(3), 1.15))
check("the streak caps at x1.3 (6 in a row)", NEAR(Businesses.StreakMult(6), 1.3) and NEAR(Businesses.StreakMult(50), 1.3) and Businesses.StreakMult(-3) == 1)
-- The press run.
check("an all-OK press run prints $1,250 at level 1", Businesses.PrintBatch(PS, 1, 0, 0) == 1250, Businesses.PrintBatch(PS, 1, 0, 0))
check("3 PERFECT from a cold start: +15% and x1.15", Businesses.PrintBatch(PS, 1, 3, 3) == math.floor(1250 * 1.15 * 1.15 + 0.5),
	Businesses.PrintBatch(PS, 1, 3, 3))
check("a perfect run deep in a streak: ~$1,870", Businesses.PrintBatch(PS, 1, 3, 9) == math.floor(1250 * 1.15 * 1.3 + 0.5), Businesses.PrintBatch(PS, 1, 3, 9))
check("PERFECTs are capped at the 3 stations", Businesses.PrintBatch(PS, 1, 7, 0) == Businesses.PrintBatch(PS, 1, 3, 0))
check("level 5 prints x1.25", Businesses.PrintBatch(PS, 5, 0, 0) == math.floor(1250 * 1.25 + 0.5))
local old = Businesses.RateScale
Businesses.RateScale = 0.5
check("RateScale halves the dirty cash printed", Businesses.PrintBatch(PS, 1, 0, 0) == 625)
Businesses.RateScale = old
-- The stock cap.
local d, added = Businesses.AddDirty(13000, 1600, 14000)
check("a press run stops at the stock cap", d == 14000 and added == 1000, d .. " +" .. added)
d, added = Businesses.AddDirty(15000, 1600, 14000)
check("a stock over its cap keeps it and takes nothing", d == 15000 and added == 0)
d, added = Businesses.AddDirty(0 / 0, 1600, 14000)
check("a broken stock counts as empty", d == 1600 and added == 1600)'

scenario print_launder_pay '
local P, L = Businesses.Print, Businesses.Launder
local pay, bonus = Businesses.LaunderPay(5600, true)
check("a clean run: 1:1 plus a 10% bonus", pay == 5600 and bonus == 560, pay .. "+" .. bonus)
pay, bonus = Businesses.LaunderPay(5600, false)
check("a spotted run: 1:1, no bonus", pay == 5600 and bonus == 0)
check("nothing for nothing", Businesses.LaunderPay(-50, true) == 0 and select(2, Businesses.LaunderPay(0 / 0, true)) == 0)
-- A seeded simulation of the timing game: a player who hits the band with chance p at each station.
local function avgBatch(level, p, runs)
	math.randomseed(7)
	local streak, total = 0, 0
	for _ = 1, runs do
		local perfects = 0
		for _ = 1, 3 do
			if math.random() < p then
				streak += 1
				perfects += 1
			else
				streak = 0
			end
		end
		total += Businesses.PrintBatch(PS, level, perfects, streak)
	end
	return total / runs
end
local typical = avgBatch(1, 0.5, 20000)
check("a typical player (half the bands) prints x~1.13: ~$1,410 a press run", typical > 1380 and typical < 1440, math.floor(typical))
check("a perfect player prints up to ~$1,870 a run, an all-OK one $1,250", NEAR(avgBatch(1, 1, 200), 1250 * 1.15 * 1.3, 15) and avgBatch(1, 0, 50) == 1250)
check("a typical load is ~4 press runs (3.8-4.2)", L.Carry[1] / typical >= 3.8 and L.Carry[1] / typical <= 4.2, L.Carry[1] / typical)
-- The loop (BALANCE in the config): ~30 s a press run, ~89 s a launder run, ~20% of runs spotted, a quarter of
-- those arrested (the bags lost), the rest ~50 s escaping; clean runs pay the bonus.
local function perMinute(level, p, spot)
	local batch = avgBatch(level, p, 4000)
	local carry = Businesses.Carry(level)
	local prints = carry / batch
	local secs = prints * 30 + 89 + spot * 0.75 * 50
	local cleanShare = 1 - spot
	local money = carry * (cleanShare * (1 + L.CleanBonus) + spot * 0.75)
	return money * 60 / secs
end
local m = perMinute(1, 0.5, 0.2)
check("~$1,600 a minute of work at level 1 WITH the risk ($1,550-1,650)", m >= 1550 and m <= 1650, math.floor(m))
local safe = perMinute(1, 0.5, 0)
check("with no risk at all it would be ~$1,780 (the risk costs ~10%)", safe > 1720 and safe < 1840, math.floor(safe))
local okOnly, perfect = perMinute(1, 0, 0.2), perMinute(1, 1, 0.2)
check("skill matters but stays honest: all-OK ~$1,500, perfect ~$1,850", okOnly > 1440 and okOnly < 1560 and perfect > 1780 and perfect < 1920,
	math.floor(okOnly) .. " / " .. math.floor(perfect))
local m5 = perMinute(5, 0.5, 0.2)
check("level 5 pays ~1.28x level 1 (1.2-1.36)", m5 / m >= 1.2 and m5 / m <= 1.36, m5 / m)
check("the Print Shop out-earns the café and the wash (the PRD order)", m > 1250 and m > 1150)
check("the drop is 800-1,600 studs away; the speed check as a taxi", L.DistMin == 800 and L.DistMax == 1600 and L.FastSlack == 1.15
	and L.StopRadius == 32)
check("20 s to get back in the car with the bags", L.LeaveGrace == 20)'

scenario launder_spotting '
local L = Businesses.Launder
-- Tip-offs: ~3 rolls on a ~38 s drive.
local rolls = 38 / ((L.SpotEvery[1] + L.SpotEvery[2]) / 2)
local tip = 1 - (1 - Businesses.SpotChance(1)) ^ rolls
check("~3 tip-off rolls a run, ~14% of runs tipped off at level 1 (10-18%)", rolls > 2.5 and rolls < 3.5 and tip > 0.10 and tip < 0.18, tip)
check("tip-offs get rarer with the levels (never more likely)", Businesses.SpotChance(3) < Businesses.SpotChance(1)
	and Businesses.SpotChance(5) <= Businesses.SpotChance(4) and Businesses.SpotChance(9) == Businesses.SpotChance(5))
-- The heat meter.
local function fill(dist, seen)
	local h, t = 0, 0
	while h < 1 and t < 120 do
		h = Businesses.HeatStep(h, 0.25, dist, seen)
		t += 0.25
	end
	return t
end
local t100 = fill(100, true)
check("a cop 100 studs off with a clear line fills it in ~6.5 s", t100 >= 5.5 and t100 <= 7.5, t100)
check("closer is faster (30 studs: under 5 s)", fill(30, true) < 5, fill(30, true))
check("a wall between you slows it right down (100 studs: 15 s+)", fill(100, false) >= 15, fill(100, false))
check("police past HeatRange never fill it", Businesses.HeatStep(0.5, 1, L.HeatRange + 1, true) < 0.5 and Businesses.HeatStep(0, 1, nil, true) == 0)
check("it drains 0.08 a second with no police in range (full to empty in 12.5 s)", NEAR(Businesses.HeatStep(1, 1, nil, true), 0.92)
	and NEAR(1 / L.HeatFall, 12.5))
check("driving past at 200 studs for 3 s adds ~0.17 (a near miss, not a bust)", NEAR(Businesses.HeatStep(0, 3, 200, true), 0.25 * (60 / 260) * 3, 0.01))
check("it never leaves 0..1", Businesses.HeatStep(5, 1, 10, true) == 1 and Businesses.HeatStep(-3, 1, nil, true) == 0)
check("1 star for a tip-off, 2 with the police close (PatrolNear < HeatRange)", L.Stars == 1 and L.PatrolStars == 2 and L.PatrolNear < L.HeatRange)
check("a cop sees 250 studs; the meter starts at 260", L.HeatRange >= 250)'

scenario raids '
local R = Businesses.Raid
-- The warrant odds.
check("no warrant below MinDirty", Businesses.WarrantChance(R.MinDirty - 1, 1) == 0 and Businesses.WarrantChance(0, 1) == 0)
check("10% a roll at MinDirty, 40% at a full stock", NEAR(Businesses.WarrantChance(R.MinDirty, 1), 0.10)
	and NEAR(Businesses.WarrantChance(Businesses.Stock(1), 1), 0.40) and NEAR(Businesses.WarrantChance(1e9, 1), 0.40))
local half = (R.MinDirty + Businesses.Stock(1)) / 2
check("halfway: 25%", NEAR(Businesses.WarrantChance(half, 1), 0.25), Businesses.WarrantChance(half, 1))
check("MinDirty is about one launder load", R.MinDirty >= Businesses.Carry(1) * 0.9 and R.MinDirty <= Businesses.Carry(1) * 1.1)
check("a hoarder at a full stock waits ~2.5 rolls for a warrant", NEAR(1 / Businesses.WarrantChance(Businesses.Stock(1), 1), 2.5))
-- Timing.
check("never in the first 10 minutes, a roll a minute, 15 minutes between raids", R.MinPlay == 600 and R.Check == 60 and R.Gap == 900)
check("a warrant runs 3 minutes (PRD)", R.Warrant == 180)
check("the AI raid can finish inside a warrant when nobody holds the door", R.AIArrive + R.AIBreach + R.AISearch + 10 < R.Warrant,
	R.AIArrive + R.AIBreach + R.AISearch)
check("the AI is slower than a player cop (breach and search)", R.AIBreach > R.ArmoredHold and R.AISearch > R.SearchHold)
check("holding the door: HeldMin is a third of the warrant", R.HeldMin < R.Warrant and NEAR(R.HeldMin / R.Warrant, 1 / 3, 0.01))
check("after a breach the cops get at least a minute to search", R.SearchMin >= 60 and R.SearchMin > R.SearchHold)
check("breach 6 s, 9 s behind the armored door (level 4+)", Businesses.BreachHold(1) == 6 and Businesses.BreachHold(3) == 6
	and Businesses.BreachHold(4) == 9 and Businesses.BreachHold(5) == 9)
-- Seizure and rewards.
local each, total = Businesses.RaidReward(10000, 1)
check("one cop seizing $10,000: $300 + 25% = $2,800", each == 2800 and total == 2800, each)
each, total = Businesses.RaidReward(10000, 2)
check("two cops split the share, each keeps the base", each == 300 + 1250 and total == 2 * each, each)
each = Businesses.RaidReward(40000, 1)
check("the share caps at $6,000 in all", each == 300 + 6000, each)
each = Businesses.RaidReward(0, 3)
check("the stock moved out: the cops still get the base", each == 300)
check("a raid never pays the cops more than it took (from MinDirty)", Businesses.RaidReward(R.MinDirty, 1) < R.MinDirty)
local old = Businesses.RateScale
Businesses.RateScale = 0.5
check("RateScale halves the raid reward", Businesses.RaidReward(10000, 1) == 150 + 1250, Businesses.RaidReward(10000, 1))
Businesses.RateScale = old
check("an AI raid takes half the stock", Businesses.AISeizeAmount(10000) == 5000 and Businesses.AISeizeAmount(7) == 3
	and Businesses.AISeizeAmount(0 / 0) == 0)
check("holding the door pays the owner $1,000, each crewmate $500", R.HeldBonus == 1000 and R.CrewHeldBonus == 500)
check("raids cost the owner more than a crewmate cop could gain (no farming)", Businesses.RaidReward(R.MinDirty, 1) * 2 < R.MinDirty)'

scenario breakins_skip_shady '
check("break-ins only pick legit businesses", Businesses.BreakInEligible(CW) and Businesses.BreakInEligible(PG)
	and not Businesses.BreakInEligible(PS) and not Businesses.BreakInEligible(nil))
check("the Nightclub (legit, with a shady back room) still gets NPC break-ins at its legit till", Businesses.BreakInEligible(Businesses.ById.Nightclub)
	and Businesses.ById.Nightclub.Layout.Robbers ~= nil and #Businesses.ById.Nightclub.Layout.Robbers == 2)
check("the Print Shop has no robber spots (it never needs them)", PS.Layout.Robbers == nil)
local shady = 0
for _, d in ipairs(Businesses.List) do
	if d.Kind == "Shady" then shady += 1 end
end
check("exactly one shady business so far", shady == 1)'

# ---------------------------------------------------------------- the fun pass (launch/18-BUSINESS-FUN-PASS.md)

scenario wash_gauges '
local W = Businesses.Wash
for _, step in ipairs({ "spray", "rinse" }) do
	local g = W.Gauge[step]
	local mid = (g.Sweet[1] + g.Sweet[2]) / 2
	check(step .. ": Min < the green band < Full, the band 0.6 s+ wide", g.Min < g.Sweet[1] and g.Sweet[1] < g.Sweet[2] and g.Sweet[2] < g.Full
		and g.Sweet[2] - g.Sweet[1] >= 0.6)
	check(step .. ": let go in the band = PERFECT", Businesses.WashGrade(step, mid) == "Perfect")
	check(step .. ": the band edges get the lag slack", Businesses.WashGrade(step, g.Sweet[1] - W.Slack + 0.01) == "Perfect"
		and Businesses.WashGrade(step, g.Sweet[2] + W.Slack - 0.01) == "Perfect" and Businesses.WashGrade(step, g.Sweet[2] + W.Slack + 0.05) == "Ok"
		and Businesses.WashGrade(step, g.Sweet[1] - W.Slack - 0.05) == "Ok")
	check(step .. ": before Min = EARLY (hold it again), after Min = OK", Businesses.WashGrade(step, g.Min - W.Slack - 0.05) == "Early"
		and Businesses.WashGrade(step, g.Min) == "Ok")
	check(step .. ": the gauge letting go by itself at Full is an OK, never a PERFECT", Businesses.WashGrade(step, g.Full) == "Ok"
		and g.Full > g.Sweet[2] + W.Slack)
	-- A new player who does not know where to let go yet: anywhere from Min to Full, evenly.
	local window = (g.Sweet[2] - g.Sweet[1]) + 2 * W.Slack
	local newbie = window / (g.Full - g.Min)
	check(step .. ": a new player lands PERFECT about half the time (40-55%)", newbie >= 0.40 and newbie <= 0.55, newbie)
	-- A player aiming at the green, letting go within about 0.45 s of its middle (a human plus phone lag), seeded.
	math.randomseed(21)
	local hits = 0
	for _ = 1, 20000 do
		local u1, u2 = math.max(math.random(), 1e-9), math.random()
		local err = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2) * 0.45
		if Businesses.WashGrade(step, mid + err) == "Perfect" then hits += 1 end
	end
	check(step .. ": aiming at the green hits it most of the time (70-90%)", hits / 20000 >= 0.70 and hits / 20000 <= 0.90, hits / 20000)
end
check("a bad number is never PERFECT", Businesses.WashGrade("spray", 0 / 0) == "Early" and Businesses.WashGrade("nope", 5) ~= nil)
check("the Print Shop grades through the same gauge maths", Businesses.PrintGrade(1, 5.0) == Businesses.GaugeGrade(Businesses.Print.Stations[1], 5.0, Businesses.Print.Slack))
check("the two gauges sit at different places (a rhythm)", W.Gauge.spray.Sweet[1] / W.Gauge.spray.Full ~= W.Gauge.rinse.Sweet[1] / W.Gauge.rinse.Full)
check("an OK still earns part of its third of the tip", W.OkShare > 0 and W.OkShare < 1)'

scenario wash_rating_streak_specials '
local W = Businesses.Wash
-- The stars: one a PERFECT hold, one for a quick wash, at least one.
check("2 PERFECT + quick = 3 stars", Businesses.WashStars(2, true) == 3)
check("2 PERFECT, slow = 2 stars; 1 PERFECT + quick = 2 stars", Businesses.WashStars(2, false) == 2 and Businesses.WashStars(1, true) == 2)
check("1 PERFECT slow, or quick only = 1 star; nothing = 1 star (never 0)", Businesses.WashStars(1, false) == 1 and Businesses.WashStars(0, true) == 1
	and Businesses.WashStars(0, false) == 1 and Businesses.WashStars(9, true) == 3)
check("the quick-wash time grows with the taps", Businesses.WashStarTime(8) < Businesses.WashStarTime(14) and NEAR(Businesses.WashStarTime(10), W.StarTime.Base + 10 * W.StarTime.PerTap))
-- The tip thirds.
local function tip(w) return select(2, Businesses.WashPay(CW, 1, w)) end
check("all PERFECT + quick: the whole $165", tip({ spray = "Perfect", rinse = "Perfect", quick = true }) == 165)
check("OK, OK, quick: $165 x (0.4 + 0.4 + 1) / 3 = $99", tip({ spray = "Ok", rinse = "Ok", quick = true }) == 99, tip({ spray = "Ok", rinse = "Ok", quick = true }))
check("PERFECT, OK, slow: $165 x 1.4 / 3 = $77", tip({ spray = "Perfect", rinse = "Ok", quick = false }) == 77)
check("a bad wash still pays the base (only the tip is at stake)", (Businesses.WashPay(CW, 1, { spray = "Ok", rinse = "Ok" })) == W.Pay)
check("bird mess pays $30 a spot on top", (Businesses.WashPay(CW, 1, { birds = 2 })) == W.Pay + 60)
-- The streak (Businesses.Streak): 3-star washes in a row raise the tip x1.1, x1.2, up to x1.3.
local S = Businesses.Streak
check("the job streak: x1.0 for the first, then +0.1 each, capped at x1.3", NEAR(Businesses.StreakMult(1, S), 1) and NEAR(Businesses.StreakMult(2, S), 1.1)
	and NEAR(Businesses.StreakMult(3, S), 1.2) and NEAR(Businesses.StreakMult(4, S), 1.3) and NEAR(Businesses.StreakMult(40, S), 1.3)
	and Businesses.StreakMult(0, S) == 1 and Businesses.StreakMult(-5, S) == 1 and Businesses.StreakMult(0 / 0, S) == 1)
check("the Print Shop keeps its own streak (one argument: +0.05 from the first)", NEAR(Businesses.StreakMult(1), 1.05) and NEAR(Businesses.StreakMult(6), 1.3))
local best = { spray = "Perfect", rinse = "Perfect", quick = true }
local streak, tips = 0, {}
for i = 1, 6 do
	best.streak = streak
	local _, t, stars, s = Businesses.WashPay(CW, 1, best)
	streak = s
	tips[i] = t
	check("3-star wash number " .. i .. " is streak " .. i, stars == 3 and s == i)
end
check("the 3-star tips climb 165, 182, 198, 215 and stay there", tips[1] == 165 and tips[2] == 182 and tips[3] == 198 and tips[4] == 215
	and tips[6] == 215, table.concat(tips, " "))
local _, t2, s2, k2 = Businesses.WashPay(CW, 1, { spray = "Perfect", rinse = "Ok", quick = true, streak = 5 })
check("a 2-star wash puts the streak back to 0 and gets no streak bonus", s2 == 2 and k2 == 0 and t2 == math.floor(165 * 2.4 / 3 + 0.5), t2)
-- The special customers.
local muddy = Businesses.WashPay(CW, 1, { special = "Muddy" })
local _, muddyTip = Businesses.WashPay(CW, 1, { special = "Muddy", spray = "Perfect", rinse = "Perfect", quick = true })
check("MUDDY TRUCK: x1.5 the whole wash (pay and tip)", muddy == math.floor(W.Pay * 1.5 + 0.5) and muddyTip == math.floor(165 * 1.5 + 0.5), muddy .. " " .. muddyTip)
check("MUDDY TRUCK: more spots (6-7) than a normal car (4-6)", W.Specials.Muddy.Spots[1] > W.Spots[1] and W.Specials.Muddy.Spots[2] > W.Spots[2])
check("WEDDING CAR: double tip", tip({ special = "Wedding", spray = "Ok", rinse = "Ok", quick = true }) == 198)
check("CLASSIC CAR: x3 the tip on a 3-star wash only", tip({ special = "Classic", spray = "Perfect", rinse = "Perfect", quick = true }) == 495
	and tip({ special = "Classic", spray = "Perfect", rinse = "Ok", quick = true }) == tip({ spray = "Perfect", rinse = "Ok", quick = true }))
local old = Businesses.RateScale
Businesses.RateScale = 0.5
check("RateScale halves the wash tip too", tip({ spray = "Perfect", rinse = "Perfect", quick = true }) == 83)
Businesses.RateScale = old
check("level 5: x1.25 on the pay and the tip", (Businesses.WashPay(CW, 5, {})) == 538)'

scenario wash_customers '
local W = Businesses.Wash
-- The special customer odds: about 1 in 8, the three kinds equally.
check("1 in 8 customers is special", NEAR(W.SpecialChance, 1 / 8) and Businesses.RollSpecial(0.124, 0.5) ~= nil and Businesses.RollSpecial(0.126, 0.5) == nil)
check("the roll picks each special a third of the time", Businesses.RollSpecial(0, 0.1) == "Muddy" and Businesses.RollSpecial(0, 0.5) == "Classic"
	and Businesses.RollSpecial(0, 0.9) == "Wedding" and Businesses.RollSpecial(0, 0.999999) == "Wedding")
math.randomseed(5)
local counts, n = { Muddy = 0, Classic = 0, Wedding = 0, none = 0 }, 80000
for _ = 1, n do
	local s = Businesses.RollSpecial(math.random(), math.random()) or "none"
	counts[s] += 1
end
check("seeded: about 12.5% special, about 4.2% each kind", NEAR(1 - counts.none / n, 0.125, 0.005) and NEAR(counts.Muddy / n, 1 / 24, 0.003)
	and NEAR(counts.Classic / n, 1 / 24, 0.003) and NEAR(counts.Wedding / n, 1 / 24, 0.003))
-- The dirt odds.
local odds = 0
for _, id in ipairs(W.DirtOrder) do odds += W.Dirt[id].Odds end
check("the dirt odds add up to 1", NEAR(odds, 1))
check("mud 3 taps, bugs 2, bird mess 4 (and pays more)", Businesses.WashTaps("Mud") == 3 and Businesses.WashTaps("Bugs") == 2
	and Businesses.WashTaps("Bird") == 4 and (W.Dirt.Bird.Pay or 0) > 0 and Businesses.WashTaps("nonsense") == 3)
check("the roll: mud below 0.5, bugs to 0.8, bird above", Businesses.RollDirt(0.49) == "Mud" and Businesses.RollDirt(0.51) == "Bugs"
	and Businesses.RollDirt(0.79) == "Bugs" and Businesses.RollDirt(0.81) == "Bird" and Businesses.RollDirt(2) == "Mud")
check("a muddy truck: no bugs, 30% bird mess", Businesses.RollDirt(0.69, "Muddy") == "Mud" and Businesses.RollDirt(0.71, "Muddy") == "Bird")
local taps = 0
for _, id in ipairs(W.DirtOrder) do taps += W.Dirt[id].Odds * W.Dirt[id].Taps end
check("about 2.9 taps a spot on average (the old 3 taps, a little quicker)", NEAR(taps, 2.9, 0.01), taps)
check("BusinessClient has 9 places for spots: enough for the muddy truck", W.Specials.Muddy.Spots[2] <= 9)
for id, sp in pairs(W.Specials) do
	check(id .. " has a tag name and words that fit the strip line", type(sp.Name) == "string" and type(sp.Words) == "string"
		and utf8.len(sp.Name .. " · " .. sp.Words) <= 30)
end'

scenario wash_calibration '
-- The seeded simulation (BALANCE in the config): a typical player lets go in the green about half the time.
-- A car: 6 s in + 4 s out of the last + 2 s to pick NEXT CAR; the gauges let go in their bands (5.0 + 4.4 s) and
-- about 1 s to start them; 0.35 s a tap + 0.5 s from spot to spot; 0-4 s of looking around (quick if inside StarTime).
local W = Businesses.Wash
local function sim(level, p, n, bonuses)
	math.randomseed(11)
	local money, secs, streak, three, tips = 0, 0, 0, 0, 0
	for _ = 1, n do
		local special = bonuses and Businesses.RollSpecial(math.random(), math.random()) or nil
		local sp = special and W.Specials[special]
		local range = sp and sp.Spots or W.Spots
		local spots = math.random(range[1], range[2])
		local taps, birds = 0, 0
		for _ = 1, spots do
			local d = Businesses.RollDirt(math.random(), special)
			taps += Businesses.WashTaps(d)
			if d == "Bird" then birds += 1 end
		end
		local g1 = math.random() < p and "Perfect" or "Ok"
		local g2 = math.random() < p and "Perfect" or "Ok"
		local holds = (W.Gauge.spray.Sweet[1] + W.Gauge.spray.Sweet[2]) / 2 + (W.Gauge.rinse.Sweet[1] + W.Gauge.rinse.Sweet[2]) / 2 + 1
		local t = holds + taps * 0.35 + (spots - 1) * 0.5 + math.random() * 4
		local quick = t <= Businesses.WashStarTime(taps)
		local pay, tip, stars, s = Businesses.WashPay(CW, level, { spray = g1, rinse = g2, quick = quick, birds = bonuses and birds or 0,
			special = special, streak = bonuses and streak or 0 })
		streak = s
		if stars == 3 then three += 1 end
		money += pay + tip
		tips += tip
		secs += W.ArriveTime + W.DepartTime + 2 + t
	end
	return money * 60 / secs, three / n, secs / n, tips / n
end
local typical, three, cycle, avgTip = sim(1, 0.5, 40000, true)
check("a typical washer: about $1,150 a minute at level 1, every bonus included (+-5%)", typical >= 1150 * 0.95 and typical <= 1150 * 1.05,
	math.floor(typical) .. "/min, " .. math.floor(three * 100) .. "% 3-star, " .. string.format("%.1f", cycle) .. " s a car, tip $" .. math.floor(avgTip))
check("a typical wash is a 30-33 s cycle", cycle >= 30 and cycle <= 33, cycle)
check("about 1 wash in 5 is 3-star for a typical player (15-25%)", three >= 0.15 and three <= 0.25, three)
local okOnly, perfect = sim(1, 0, 20000, true), sim(1, 1, 20000, true)
check("skill shows but stays honest: all-OK about -7%, all-PERFECT about +11%", okOnly < typical and okOnly > typical * 0.88 and perfect > typical
	and perfect < typical * 1.16, math.floor(okOnly) .. " / " .. math.floor(perfect))
local plain = sim(1, 0.5, 40000, false)
check("the bird mess, the specials and the streak are part of the average (worth 7-12%)", typical > plain * 1.07 and typical < plain * 1.12,
	math.floor(plain) .. " without them")
local five = sim(5, 0.5, 20000, true)
check("level 5 pays x1.25", NEAR(five / typical, 1.25, 0.01), five / typical)
-- The old rules on the same model, for the record: $420 + $140 for 85% of washes (both holds in one go).
local oldRules = (420 + 0.85 * 140) * 60 / cycle
check("the old rules made about $1,020 a minute on this model (under the $1,150 target)", oldRules > 980 and oldRules < 1060, math.floor(oldRules))'

scenario detail_fun '
local D, S = Businesses.Detail, Businesses.Streak
local est = Businesses.DetailEstimate(1365)
local p, t, stars, streak = Businesses.DetailPay(CW, 1, 1365, est, est, 0)
check("on time, no dents: 3 stars, the full $300, the streak starts", t == 300 and stars == 3 and streak == 1)
local _, ts = Businesses.DetailPay(CW, 1, 1365, est, est, 0, true)
check("a sports car: x1.5 tip", ts == 450, ts)
local _, td, sd, kd = Businesses.DetailPay(CW, 1, 1365, est, est, 2, true)
check("a sports car: $100 a dent (2 dents = $250 left), 1 star, the streak back to 0", td == 250 and sd == 1 and kd == 0, td)
check("an ordinary car: still $60 a dent", select(2, Businesses.DetailPay(CW, 1, 1365, est, est, 2)) == 180)
check("the stars: late with no dents 2, on time with 1 dent 2, late with 1 dent 1", Businesses.DetailStars(est + 5, est, 0) == 2
	and Businesses.DetailStars(est, est, 1) == 2 and Businesses.DetailStars(est + 5, est, 1) == 1 and Businesses.DetailStars(est, est, 4) == 1)
local tipsIn, k = {}, 0
for i = 1, 5 do
	local _, tip, _, s = Businesses.DetailPay(CW, 1, 1365, est, est, 0, false, k)
	k = s
	tipsIn[i] = tip
end
check("clean deliveries in a row: tips 300, 330, 360, 390, 390 (the streak, capped x1.3)", table.concat(tipsIn, " ") == "300 330 360 390 390", table.concat(tipsIn, " "))
check("one dent puts the no-dent streak back to 0", select(4, Businesses.DetailPay(CW, 1, 1365, est, est, 1, false, 4)) == 0)
check("the pay itself never depends on dents (only the tip is at stake)", p == select(1, Businesses.DetailPay(CW, 1, 1365, est * 3, est, 9, true, 3)))
local okCars = true
for _, id in ipairs(D.Sports.Cars) do
	local v = Vehicles.ById[id]
	if not v or v.Police or v.Boat or v.Hidden or v.Pass or v.UnlockHeists then
		okCars = false
		print("  bad sports car " .. tostring(id))
	end
end
check("sports cars: real, ordinary cars (no pass, police or heist-locked ones)", okCars and #D.Sports.Cars >= 2)
check("about one delivery in five is a sports car", NEAR(D.Sports.Chance, 0.2))
check("the customer takes the car within a few seconds; the next car within 4 minutes", D.HandOver >= 2 and D.HandOver <= 5 and D.IdleTime >= 120)
-- The seeded simulation (BALANCE): 85 s a delivery of 1,365 studs of road; the trip takes 0.85-1.35x the
-- estimate; 0.5 dents a trip on average (Poisson); one in five a sports car; clean ones in a row build the streak.
local function sim(level, lambda, n, bonuses)
	math.randomseed(5)
	local money, secs, k2 = 0, 0, 0
	for _ = 1, n do
		local e = Businesses.DetailEstimate(1365)
		local took = e * (0.85 + math.random() * 0.5)
		local L, dents, q = math.exp(-lambda), 0, math.random()
		while q > L do
			dents += 1
			q *= math.random()
		end
		local sports = bonuses and math.random() < D.Sports.Chance
		local pay, tip, _, s = Businesses.DetailPay(CW, level, 1365, took, e, dents, sports, bonuses and k2 or 0)
		k2 = s
		money += pay + tip
		secs += 85
	end
	return money * 60 / secs
end
local typical = sim(1, 0.5, 40000, true)
check("a typical delivery: about $1,150 a minute at level 1, sports cars and the streak included (+-5%)", typical >= 1150 * 0.95
	and typical <= 1150 * 1.05, math.floor(typical))
local plain = sim(1, 0.5, 40000, false)
check("the sports cars and the streak are worth 1-4% (part of the average)", typical > plain and typical < plain * 1.04, math.floor(plain))
local careful, crashy = sim(1, 0.1, 20000, true), sim(1, 1.5, 20000, true)
check("careful drivers earn more, crashers less (never below the base)", careful > typical and crashy < typical and crashy > typical * 0.9,
	math.floor(careful) .. " / " .. math.floor(crashy))'

scenario rush_medals_and_bonuses '
local Ru, S = Businesses.Rush, Businesses.Streak
local T = 40
check("GOLD with 22%+ of the clock left (the full tip)", Businesses.RushMedal(0, T) == "Gold" and Businesses.RushMedal(T * 0.775, T) == "Gold")
check("SILVER while the tip fades, BRONZE at 0:00 and late", Businesses.RushMedal(T * 0.79, T) == "Silver" and Businesses.RushMedal(T - 0.01, T) == "Silver"
	and Businesses.RushMedal(T, T) == "Bronze" and Businesses.RushMedal(T * 3, T) == "Bronze")
check("a broken time is never an error", Businesses.RushMedal(0 / 0, T) == "Gold" and Businesses.RushMedal(5, 0 / 0) ~= nil)
-- The medal and the pay agree: GOLD = the full tip, BRONZE = none.
local _, gt, gm = Businesses.RushPay(PG, 1, 600, 0, false, T * 0.5, T, false)
local _, st, sm = Businesses.RushPay(PG, 1, 600, 0, false, T * 0.9, T, false)
local _, bt, bm = Businesses.RushPay(PG, 1, 600, 0, false, T + 1, T, false)
check("GOLD pays the full tip, SILVER part of it, BRONZE none", gm == "Gold" and gt == Ru.TipMax and sm == "Silver" and st > 0 and st < gt
	and bm == "Bronze" and bt == 0, gt .. " " .. st .. " " .. bt)
-- The gold streak.
local k, tips = 0, {}
for i = 1, 5 do
	local _, tip, _, s = Businesses.RushPay(PG, 1, 600, 0, false, 1, T, false, k)
	k = s
	tips[i] = tip
end
check("GOLDs in a row: tips 150, 165, 180, 195, 195 (x1.1 to x1.3)", table.concat(tips, " ") == "150 165 180 195 195", table.concat(tips, " "))
check("a SILVER ends the gold streak", select(4, Businesses.RushPay(PG, 1, 600, 0, false, T * 0.9, T, false, 7)) == 0)
-- Rush hour.
local _, rh = Businesses.RushPay(PG, 1, 600, 0, false, 1, T, false, 0, true)
local pNo = Businesses.RushPay(PG, 1, 600, 0, false, 1, T, false, 0, false)
local pYes = Businesses.RushPay(PG, 1, 600, 0, false, 1, T, false, 0, true)
check("RUSH HOUR: +25% on the tip, the base pay unchanged", rh == math.floor(150 * 1.25 + 0.5) and pNo == pYes, rh)
check("the strip shows the same tip as the server, rush hour and streak included",
	Businesses.RushTip(PG, 2, 10, T, false, 2, true) == select(2, Businesses.RushPay(PG, 2, 999, 0, false, 10, T, false, 2, true)))
check("rush hour is on until its time", Businesses.RushHourOn(100, 99) and not Businesses.RushHourOn(100, 100)
	and not Businesses.RushHourOn(nil, 5) and not Businesses.RushHourOn("x", 5))
local RH = Ru.RushHour
local cycle = RH.Length + (RH.Gap[1] + RH.Gap[2]) / 2
check("a rush hour about every 10 minutes of play, 2 minutes long (about 20% of the time)", NEAR(cycle, 600, 60) and RH.Length == 120
	and NEAR(RH.Length / cycle, 0.2, 0.03), cycle)
-- The perfect run.
check("PERFECT RUN: $150 on a 2+ stop order with every stop GOLD", Businesses.PerfectRunBonus(PG, 1, 2, 2) == 150
	and Businesses.PerfectRunBonus(PG, 1, 3, 3) == 150 and Businesses.PerfectRunBonus(PG, 5, 3, 3) == 188)
check("no perfect run for a single stop or a missed GOLD", Businesses.PerfectRunBonus(PG, 1, 1, 1) == 0 and Businesses.PerfectRunBonus(PG, 1, 3, 2) == 0)
-- The seeded simulation (BALANCE): the drive takes 0.8-1.2x the typical time (45 studs/s on a road 1.3x the
-- straight line), 3 s to stop at each address, 17 s at the cafe, 6 s to the car after the grab (in the clock).
local function sim(drops, kmin, kmax, n, bonuses)
	math.randomseed(3)
	local money, secs, streak, clockT = 0, 0, 0, 0
	local golds, legs = 0, 0
	for _ = 1, n do
		local back = math.sqrt(700 ^ 2 + (drops - 1) * 500 ^ 2) * 1.3
		local orderSecs, orderGolds, orderPay = 17 + back / 45, 0, 0
		for i = 1, drops do
			local road = (i == 1 and 700 or 500) * 1.3
			local timer = Businesses.RushTimer(road, i == 1)
			local drive = road / 45 * (kmin + math.random() * (kmax - kmin)) + 3
			local took = (i == 1 and 6 or 0) + drive
			local rushHour = bonuses and (clockT % cycle) < RH.Length
			local pay, tip, medal, s = Businesses.RushPay(PG, 1, road, i == drops and back or 0, i == 1, took, timer, false,
				bonuses and streak or 0, rushHour)
			streak = s
			legs += 1
			if medal == "Gold" then
				golds += 1
				orderGolds += 1
			end
			orderPay += pay + tip
			orderSecs += drive
		end
		if bonuses then
			orderPay += Businesses.PerfectRunBonus(PG, 1, drops, orderGolds)
		end
		money += orderPay
		secs += orderSecs
		clockT += orderSecs
	end
	return money * 60 / secs, golds / legs
end
local one, gold = sim(1, 0.8, 1.2, 30000, true)
check("one address: about $1,250 a minute at level 1, every bonus included (+-5%)", one >= 1250 * 0.95 and one <= 1250 * 1.05, math.floor(one))
check("a typical driver gets a GOLD about half the time (45-65%)", gold >= 0.45 and gold <= 0.65, gold)
local two, three = sim(2, 0.8, 1.2, 30000, true), sim(3, 0.8, 1.2, 30000, true)
check("two and three addresses: more a minute, no more than +10% (perfect runs included)", two > one and three > two and three <= one * 1.1,
	math.floor(two) .. " / " .. math.floor(three))
local plain = sim(1, 0.8, 1.2, 30000, false)
check("the gold streak and rush hour are part of the average (worth 1-3%)", one > plain and one < plain * 1.03, math.floor(plain))
local slow, fast = sim(1, 1.0, 1.4, 20000, true), sim(1, 0.7, 0.9, 20000, true)
check("fast drivers earn more, slow ones less (the base is always paid)", fast > one and slow < one and slow > one * 0.85,
	math.floor(slow) .. " / " .. math.floor(fast))'

scenario trickle_paybacks '
-- Nov 4: the owner wants businesses to really make money: trickle-only payback at level 1 of about 7.5-8 h.
local cw, pg, ps = Businesses.PaybackHours(CW), Businesses.PaybackHours(PG), Businesses.PaybackHours(PS)
check("the Car Wash as it was: about 6.9 h", NEAR(cw, 6.94, 0.05), cw)
check("Palm Grind: 7.5-8 h (was about 9.4)", pg >= 7.5 and pg <= 8, pg)
check("the Print Shop: 7.5-8 h (was about 13.6)", ps >= 7.5 and ps <= 8, ps)
for _, def in ipairs({ CW, PG, PS }) do
	local up, fills = true, true
	for l = 1, 5 do
		local lv = def.Levels[l]
		if l > 1 and (lv.Trickle <= def.Levels[l - 1].Trickle or lv.Cap <= def.Levels[l - 1].Cap) then up = false end
		local minutes = lv.Cap / lv.Trickle
		if minutes < 30 or minutes > 65 then
			fills = false
			print(string.format("  %s level %d fills in %.0f min", def.Id, l, minutes))
		end
	end
	check(def.Id .. ": trickle and register grow every level", up)
	check(def.Id .. ": every register takes 30-65 minutes to fill (collect a couple of times an hour)", fills)
	-- The whole investment (price + every upgrade) at level 5, on the level-5 trickle alone.
	local total = def.Price
	for l = 1, 4 do total += Businesses.UpgradePrice(def, l) end
	local h = total / def.Levels[5].Trickle / 60
	check(def.Id .. ": everything paid in, at level 5, pays back on the trickle in 10-14 h", h >= 10 and h <= 14, h)
end
local stack, nightStack = 0, 0
for _, def in ipairs(Businesses.List) do
	stack += def.Levels[5].Trickle
	nightStack += Businesses.Trickle(def, 5, false, true)
end
check("owning all five at level 5 trickles $2,305 a minute by day (was $1,330, $1,560 before M4, $1,850 with the club placeholder)", stack == 2305, stack)
check("...and $3,180 at night, when the club doubles", nightStack == 3180, nightStack)
check("the shady shop still trickles the most of the three", Businesses.Trickle(PS, 1) > Businesses.Trickle(PG, 1) and Businesses.Trickle(PG, 1) > Businesses.Trickle(CW, 1))'

# ---------------------------------------------------------------- M4: Coastline Boat Rentals

scenario boat_lot '
local Lo = BR.Layout
-- Every spot the buildings and the robbers use is inside the 56 x 50 lot; the dock ring and the slip mouth are
-- just outside it on purpose (open water past the slip).
local inside = true
local function inLot(v, what)
	if math.abs(v.X) > 28 or math.abs(v.Z) > 25 then
		inside = false
		print("  outside the lot: " .. what)
	end
end
inLot(Lo.Door, "Door") inLot(Lo.Register, "Register") inLot(Lo.Exit, "Exit") inLot(Lo.Service, "Service") inLot(Lo.Berth, "Berth")
for i, v in ipairs(Lo.Robbers) do inLot(v, "Robber " .. i) end
for i, v in ipairs(Lo.Rentals) do inLot(v, "Rental " .. i) end
for i, v in ipairs(Lo.Queue) do inLot(v, "Queue " .. i) end
check("every Boat Rentals spot is inside its lot", inside)
check("the slip mouth and the dock ring are past the slip, on open water", Lo.SlipMouth.Z > 25 and Lo.Dock.Z > Lo.SlipMouth.Z
	and Lo.Dock.X == Lo.Berth.X and Lo.SlipMouth.X == Lo.Berth.X)
local function box(def)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs({ { -28, -25 }, { 28, -25 }, { -28, 25 }, { 28, 25 } }) do
		local p = Businesses.At(def, Vector3.new(c[1], 0, c[2]))
		x0, x1, z0, z1 = math.min(x0, p.X), math.max(x1, p.X), math.min(z0, p.Z), math.max(z1, p.Z)
	end
	return x0, x1, z0, z1
end
local x0, x1, z0, z1 = box(BR)
check("the lot spans x 1706..1756, z 1072..1128 (the box checked against the place file)", NEAR(x0, 1706, 0.01) and NEAR(x1, 1756, 0.01)
	and NEAR(z0, 1072, 0.01) and NEAR(z1, 1128, 0.01), string.format("%.1f..%.1f, %.1f..%.1f", x0, x1, z0, z1))
local street = Businesses.At(BR, Vector3.new(0, 0, -25))
check("lot-space -Z faces the marina pier (west), +Z the open sea", street.X < BR.Position.X - 20 and Businesses.At(BR, Vector3.new(0, 0, 25)).X > BR.Position.X + 20)
local function clear(ax0, ax1, az0, az1, bx0, bx1, bz0, bz1, margin)
	return ax1 + margin <= bx0 or bx1 + margin <= ax0 or az1 + margin <= bz0 or bz1 + margin <= az0
end
check("5+ studs clear of Marina Boat Sales (its kiosk, showcase dock and berths: x 1668..1700, z 975..1110)", clear(x0, x1, z0, z1, 1668, 1700, 975, 1110, 5))
check("5+ studs clear of the civilian boat pads (x 1692..1718, z 1134..1186) and the boats they launch", clear(x0, x1, z0, z1, 1692, 1718, 1134, 1186, 5))
check("clear of the Sea Dream deck and its yacht (x 1675..1761, z 1270..1365)", clear(x0, x1, z0, z1, 1675, 1761, 1270, 1365, 20))
-- The gangway (x 0.5..6.5, z -47.3..-25 in lot space) lands on the marina pier (x 1436..1684, z 1091..1109) between
-- the showcase dock (up to z 1092) and the kiosk (from z 1100.5).
local g1, g2 = Businesses.At(BR, Vector3.new(0.5, 0, -47.3)), Businesses.At(BR, Vector3.new(6.5, 0, -47.3))
local gz0, gz1 = math.min(g1.Z, g2.Z), math.max(g1.Z, g2.Z)
check("the gangway reaches the pier end (x 1684)", g1.X <= 1684 and g1.X >= 1683, g1.X)
check("it lands between the showcase dock (z 1092) and the kiosk (z 1100.5)", gz0 >= 1092.5 and gz1 <= 1100, gz0 .. ".." .. gz1)
local ok = true
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
-- The hulls fit their slips: the solid decks are the front deck (z -25..-13), the main pier (x -3..3, z -13..23), the
-- fingers (x -20..-17.5 to z 8, x 16..18.5 to z 20); a boat moored at its spot, nose to +Z, must miss them all.
local solid = { { -27, 27, -25, -13 }, { -3, 3, -13, 23 }, { -20, -17.5, -13, 8 }, { 16, 18.5, -13, 20 } }
local function fits(spot, id, what)
	local v = Vehicles.ById[id]
	local w, l = v.Size.X / 2, v.Size.Z / 2
	for _, s in ipairs(solid) do
		if spot.X + w > s[1] and spot.X - w < s[2] and spot.Z + l > s[3] and spot.Z - l < s[4] then
			print("  " .. what .. " (" .. id .. ") hits a deck")
			return false
		end
	end
	return true
end
local fitAll = true
for _, id in ipairs(Businesses.Tour.Boats) do fitAll = fits(Lo.Berth, id, "the tour boat") and fitAll end
for i, spot in ipairs(Lo.Rentals) do fitAll = fits(spot, Businesses.Rental.Vehicle, "rental " .. i) and fitAll end
check("every level of tour boat and both rental jet skis fit their slips without touching a deck", fitAll)
check("the two rental slots are a jet ski apart (no overlap)", math.abs(Lo.Rentals[1].X - Lo.Rentals[2].X) >= Vehicles.ById[Businesses.Rental.Vehicle].Size.X + 1)
-- The ticket booth (x 8..19, z -22..-15): the door in its front, the robbers inside facing the till on the counter,
-- and their way out straight through the doorway (x 12..15).
check("the door is in the booth front, the till on the back counter", Lo.Door.Z == -22 and Lo.Door.X > 12 and Lo.Door.X < 15
	and Lo.Register.Z > -17.2 and Lo.Register.Z < -15.6)
check("two robbers inside the booth, in front of the counter", #Lo.Robbers == 2 and Lo.Robbers[1].Z > -21.4 and Lo.Robbers[1].Z < -17.2
	and Lo.Robbers[2].Z < -17.2 and Lo.Robbers[1].X > 8.6 and Lo.Robbers[2].X < 18.4)
local from = Lo.Door + Vector3.new(0, 0, 2)
local t = (-22 - from.Z) / (Lo.Exit.Z - from.Z)
local xAtWall = from.X + (Lo.Exit.X - from.X) * t
check("robbers leave through the doorway (x 12..15) onto the front deck", xAtWall > 12 and xAtWall < 15 and Lo.Exit.Z > -25, xAtWall)
check("the JET SKI RENTALS stand is on the front deck at the head of the rental slip", Lo.Service.Z > -25 and Lo.Service.Z < -13
	and Lo.Service.X > -17.5 and Lo.Service.X < -3)
check("the tourists queue on the main pier (x -3..3), beside the berth", (function()
	for _, q in ipairs(Lo.Queue) do
		if math.abs(q.X) > 3 or q.Z < -13 or q.Z > 23 then return false end
	end
	return #Lo.Queue >= 6
end)())'

scenario boat_levels '
local t, c = {}, {}
for l = 1, 5 do
	t[l] = Businesses.Trickle(BR, l, false)
	c[l] = Businesses.Cap(BR, l)
end
check("trickle 256 340 423 507 590 a minute (the PRD first $130 -> $300 x~1.97, the Nov 4 treatment)", table.concat(t, " ") == "256 340 423 507 590",
	table.concat(t, " "))
check("registers 9600 16050 22500 28950 35400", table.concat(c, " ") == "9600 16050 22500 28950 35400", table.concat(c, " "))
check("upgrades 48,000 / 72,000 / 96,000 / 120,000", Businesses.UpgradePrice(BR, 1) == 48000 and Businesses.UpgradePrice(BR, 2) == 72000
	and Businesses.UpgradePrice(BR, 3) == 96000 and Businesses.UpgradePrice(BR, 4) == 120000 and Businesses.UpgradePrice(BR, 5) == nil)
check("$120,000, legit, enabled, its own job module", BR.Price == 120000 and BR.Kind == "Legit" and BR.Enabled == true and BR.Style == "BoatRentals")
local h = Businesses.PaybackHours(BR)
check("trickle alone pays it back in 7.5-8 h (was ~15.4 h on the first numbers)", h >= 7.5 and h <= 8, h)
local fills, up = true, true
for l = 1, 5 do
	local lv = BR.Levels[l]
	if l > 1 and (lv.Trickle <= BR.Levels[l - 1].Trickle or lv.Cap <= BR.Levels[l - 1].Cap) then up = false end
	local minutes = lv.Cap / lv.Trickle
	if minutes < 30 or minutes > 65 then
		fills = false
		print(string.format("  level %d fills in %.0f min", l, minutes))
	end
end
check("trickle and register grow every level", up)
check("every register takes 30-65 minutes to fill", fills)
local total = BR.Price
for l = 1, 4 do total += Businesses.UpgradePrice(BR, l) end
local h5 = total / BR.Levels[5].Trickle / 60
check("everything paid in, at level 5, pays back on the trickle in 10-14 h", h5 >= 10 and h5 <= 14, h5)
check("START JOB offers only BOAT TOURS", Businesses.HasJob(BR, "Tour") and #BR.Jobs == 1 and BR.Jobs[1].Label == "BOAT TOURS")
check("the player service is the jet ski rental, $150", BR.Service.Kind == "Rental" and BR.Service.Price == 150 and BR.Service.Name == "Jet ski rental")
check("every level says what it adds (level 5: luxury yacht tours)", BR.Levels[1].Adds ~= nil and string.find(BR.Levels[5].Adds, "acht") ~= nil)
check("its own map letter Y and colour", BR.MapLetter == "Y" and BR.MapColor ~= nil and BR.MapColor ~= PG.MapColor and BR.MapColor ~= CW.MapColor)
-- The boats and the tourists by level.
local T = Businesses.Tour
local boats, tourists = {}, {}
for l = 1, 5 do
	boats[l] = Businesses.TourBoat(l)
	tourists[l] = Businesses.TourTourists(l)
end
check("boats: Marlin to level 3, the Moonstone hull from 4", table.concat(boats, " ") == "Marlin Marlin Marlin Moonstone Moonstone", table.concat(boats, " "))
check("tourists 2 3 4 5 6", table.concat(tourists, " ") == "2 3 4 5 6", table.concat(tourists, " "))
check("fit-outs: plain, plain, canopy, canopy, luxury", Businesses.TourFitout(1) == "Plain" and Businesses.TourFitout(3) == "Canopy"
	and Businesses.TourFitout(5) == "Luxury")
local real = true
for l = 1, 5 do
	local v = Vehicles.ById[boats[l]]
	if not v or not v.Boat or v.Police then real = false end
	local seats = T.Seats[boats[l]]
	if not seats or #seats < tourists[l] then
		real = false
		print("  not enough seats on the " .. tostring(boats[l]) .. " for level " .. l)
	end
end
check("every tour boat is a real civilian boat with a seat for each tourist", real)
check("bigger boats at higher levels", Vehicles.ById[boats[5]].Size.Z > Vehicles.ById[boats[1]].Size.Z)'

scenario tour_routes '
local T = Businesses.Tour
local all = true
for _, r in ipairs(T.Routes) do
	local stops = Businesses.TourStops(r)
	if #stops ~= #r.Stops then
		all = false
		print("  " .. r.Id .. " names a landmark that is not in Tour.Stops")
	end
	if Businesses.TourStopCount(r) < 1 then
		all = false
		print("  " .. r.Id .. " has no photo or fishing stop")
	end
end
check("every route stop is a real landmark and every route has a photo or fishing stop", all)
local lens = {}
for _, r in ipairs(T.Routes) do lens[r.Id] = Businesses.TourLength(BR, r) end
check("route lengths as documented (Marina ~1,490, Boardwalk ~2,290, Ferris ~2,980, Flamingo ~4,720, Lighthouse ~4,890, Grand ~5,500, Fishing ~750)",
	NEAR(lens.Marina, 1490, 15) and NEAR(lens.Boardwalk, 2290, 15) and NEAR(lens.Ferris, 2980, 15) and NEAR(lens.Flamingo, 4720, 15)
	and NEAR(lens.Lighthouse, 4890, 15) and NEAR(lens.Grand, 5500, 15) and NEAR(lens.Fishing, 750, 15),
	string.format("%d %d %d %d %d %d %d", lens.Marina, lens.Boardwalk, lens.Ferris, lens.Flamingo, lens.Lighthouse, lens.Grand, lens.Fishing))
local counts = {}
for l = 1, 5 do
	local list, newest = Businesses.TourRoutes(l)
	counts[l] = #list
	local longest = 0
	for _, r in ipairs(list) do
		if r.MinLevel > l then all = false end
		if r.MinLevel == newest then longest = math.max(longest, lens[r.Id]) end
	end
	lens["new" .. l] = longest
end
check("routes offered by level: 2 3 4 5 6 (the Fishing Party route only as a special)", table.concat(counts, " ") == "2 3 4 5 6", table.concat(counts, " "))
check("each level brings a longer newest route than the level before", lens.new2 > lens.new1 and lens.new3 > lens.new2 and lens.new4 > lens.new3
	and lens.new5 > lens.new4)
check("the Fishing route belongs to the Fishing Party (never picked otherwise)", Businesses.TourRoute("Fishing").MinLevel > 5
	and T.Specials.Fishing.Route == "Fishing")
-- PickRoute: OwnShare of the time the level newest routes, else any it offers; never one it does not offer.
local seen, newestPicks, n = {}, 0, 4000
for i = 1, n do
	local r = Businesses.PickRoute(3, (i % 100) / 100, ((i * 37) % 100) / 100)
	seen[r.Id] = (seen[r.Id] or 0) + 1
	if r.MinLevel == 3 then newestPicks += 1 end
end
check("level 3 picks only Marina, Boardwalk, Ferris and Flamingo", seen.Lighthouse == nil and seen.Grand == nil and seen.Fishing == nil
	and (seen.Marina or 0) > 0 and (seen.Boardwalk or 0) > 0 and (seen.Ferris or 0) > 0)
check("about OwnShare + a quarter of the rest are its newest route (Flamingo: ~62%)", NEAR(newestPicks / n, T.OwnShare + (1 - T.OwnShare) / 4, 0.03),
	newestPicks / n)
-- The water: every stop out past the shore slope (x 1620), the rings never overlap, every leg keeps 40+ studs off the
-- Ferris pier (x 1505..1786, z -458..-342) and the causeway (z -1370..-1330), and stays inside the sea the Surf
-- Sprint uses (x up to 2450).
local stopsOk, ringsOk, legsOk = true, true, true
local ids = {}
for id, s in pairs(T.Stops) do
	table.insert(ids, id)
	if s.Pos.X < 1640 or s.Pos.X > 2450 then
		stopsOk = false
		print("  " .. id .. " is not out at sea")
	end
end
for i = 1, #ids do
	for j = i + 1, #ids do
		local a, b = T.Stops[ids[i]].Pos, T.Stops[ids[j]].Pos
		if (a - b).Magnitude < T.Radius * 2 + 20 then
			ringsOk = false
			print("  rings overlap: " .. ids[i] .. " " .. ids[j])
		end
	end
end
local function segBox(a, b, bx0, bx1, bz0, bz1)
	local best = math.huge
	for k = 0, 200 do
		local f = k / 200
		local px, pz = a.X + (b.X - a.X) * f, a.Z + (b.Z - a.Z) * f
		local dx, dz = math.max(bx0 - px, 0, px - bx1), math.max(bz0 - pz, 0, pz - bz1)
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	return best
end
for _, r in ipairs(T.Routes) do
	local prev = Businesses.At(BR, BR.Layout.Berth)
	local stops = Businesses.TourStops(r)
	table.insert(stops, { Pos = Businesses.At(BR, BR.Layout.Dock), Name = "DOCK" })
	for _, s in ipairs(stops) do
		local d1 = segBox(prev, s.Pos, 1505, 1786, -458, -342)
		local d2 = segBox(prev, s.Pos, 990, 2110, -1370, -1330)
		if d1 < 40 or d2 < 40 then
			legsOk = false
			print(string.format("  %s: the leg to %s passes %.0f studs from the Ferris pier, %.0f from the causeway", r.Id, s.Name, d1, d2))
		end
		prev = s.Pos
	end
end
check("every landmark is out at sea (x 1640..2450, past the shore slope)", stopsOk)
check("no two rings overlap", ringsOk)
check("no leg passes within 40 studs of the Ferris pier or the causeway", legsOk)
local short = true
for _, s in pairs(T.Stops) do
	if utf8.len(s.Line) > 40 or utf8.len("NEXT: " .. s.Name) > 30 then
		short = false
		print("  too long: " .. s.Name)
	end
end
check("guide lines fit their bubble (40) and NEXT: <landmark> fits the strip (30)", short)'

scenario tour_rings_and_photos '
local T = Businesses.Tour
local cp = Vector3.new(100, 0, 0)
check("a boat inside the ring counts", Businesses.TourReached(nil, Vector3.new(120, 0, 10), cp, T.Radius))
check("one outside does not", not Businesses.TourReached(nil, Vector3.new(140, 0, 0), cp, T.Radius))
check("a fast boat right through it between two checks counts (80 studs a quarter second)",
	Businesses.TourReached(Vector3.new(60, 0, 0), Vector3.new(140, 0, 0), cp, T.Radius))
check("a step that passes beside it, outside the radius, does not", not Businesses.TourReached(Vector3.new(60, 0, 40), Vector3.new(140, 0, 40), cp, T.Radius))
check("a jump longer than MaxStep is not driving (a teleport past it does not count)",
	not Businesses.TourReached(Vector3.new(-100, 0, 0), Vector3.new(300, 0, 0), cp, T.Radius))
-- Photo stops (Businesses.PhotoStep, 4 checks a second).
local function run(speeds, kind, insideFrom)
	local st, res
	for i, v in ipairs(speeds) do
		st, res = Businesses.PhotoStep(st, 0.25, i >= (insideFrom or 1), v, kind)
		if res then return res, i, st end
	end
	return nil, #speeds, st
end
local function rep(v, n) local out = {} for i = 1, n do out[i] = v end return out end
check("outside the ring before it: nothing yet", run({ 30, 30 }, "Photo", 3) == nil)
local g, at = run(rep(4, 20), "Photo")
check("gliding nearly still for the hold: PERFECT after 2.5 s", g == "Perfect" and at == 10, tostring(g) .. " at " .. at)
g = run(rep(12, 20), "Photo")
check("slow but not still the whole hold: OK", g == "Ok", g)
local mix = rep(12, 4)
for _ = 1, 6 do table.insert(mix, 5) end
g = run(mix, "Photo")
check("1.5 s nearly still inside the hold: PERFECT", g == "Perfect", g)
local mix2 = rep(12, 5)
for _ = 1, 5 do table.insert(mix2, 5) end
g = run(mix2, "Photo")
check("only 1.25 s still: OK", g == "Ok", g)
local fast = { 4, 4, 4, 4, 4, 4, 4, 30 }
for _ = 1, 10 do table.insert(fast, 4) end
g, at = run(fast, "Photo")
check("going over the photo speed inside starts the hold again", g == "Perfect" and at == 18, tostring(g) .. " at " .. at)
local st = { hold = 1, steady = 1, entered = true }
local _, res = Businesses.PhotoStep(st, 0.25, false, 40, "Photo")
check("leaving the ring before it is done: MISSED", res == "Missed")
local _, res2 = Businesses.PhotoStep(nil, 0.25, true, 0 / 0, "Photo")
check("a NaN speed is never an error", res2 == nil)
g, at = run(rep(3, 30), "Fish")
check("a fishing stop: 4.5 s dead still = PERFECT (a longer, stiller hold)", g == "Perfect" and at == 18, tostring(g) .. " at " .. at)
g = run(rep(8, 30), "Fish")
check("fishing at 8 studs/s: OK", g == "Ok", g)
check("photo shares: PERFECT 1, OK 0.4, MISSED 0", Businesses.PhotoShare("Perfect") == 1 and Businesses.PhotoShare("Ok") == T.OkShare
	and Businesses.PhotoShare("Missed") == 0)
-- A new player: they slow to somewhere between 2 and 15 studs/s inside the ring and wobble a little; how often PERFECT?
local seed = 7
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
local perfect, n = 0, 4000
for _ = 1, n do
	local base = 2 + 13 * rnd()
	local speeds = {}
	for i = 1, 40 do speeds[i] = math.max(0, base + (rnd() - 0.5) * 6) end
	if run(speeds, "Photo") == "Perfect" then perfect += 1 end
end
check("a new player who slows down anywhere from 2 to 15 lands PERFECT about 1 in 2 (35-60%)", perfect / n >= 0.35 and perfect / n <= 0.6, perfect / n)'

scenario tour_mood_and_pay '
local T, M = Businesses.Tour, Businesses.Tour.Mood
local m, d = Businesses.TourMood(0.5, 1, 30, false, false, false)
check("calm driving lifts the mood slowly", NEAR(m, 0.5 + M.Recover) and d == 0, m)
m = Businesses.TourMood(1, 1, 0, false, false, false)
check("never over 100%", m == 1)
m, d = Businesses.TourMood(1, 1, M.TurnLimit * 2, false, false, false)
check("a hard turn (twice the limit) for a second costs 5%", NEAR(m, 1 - M.TurnDrain) and NEAR(d, M.TurnDrain), m)
m = Businesses.TourMood(1, 1, 10000, false, false, false)
check("the worst turn costs 10% a second at most", NEAR(m, 1 - M.TurnDrain * M.TurnCap), m)
m = Businesses.TourMood(1, 0.25, 0, true, false, false)
check("a ram costs 15%", NEAR(m, 1 - M.RamHit), m)
m = Businesses.TourMood(1, 0.5, 0, false, true, true)
check("running aground costs 20% at once and 5% a second", NEAR(m, 1 - M.BeachHit - M.BeachDrain * 0.5), m)
m = Businesses.TourMood(0.05, 1, 0, true, true, true)
check("never under 0", m == 0)
m = Businesses.TourMood(0 / 0, 1, 0 / 0, false, false, false)
check("bad numbers are never an error", m >= 0 and m <= 1)
-- The stars.
check("stars: on time + all PERFECT + happy = 3; none = 1", Businesses.TourStars(true, true, 0.9) == 3 and Businesses.TourStars(false, false, 0.1) == 1
	and Businesses.TourStars(true, false, 0.85) == 2 and Businesses.TourStars(true, true, 0.79) == 2)
-- The pay.
local L = 1500
local par = Businesses.TourPar(L, 1)
check("par = 4 + the route / 85 + 7 a stop", NEAR(par, 4 + L / 85 + 7), par)
local best = { length = L, grades = { "Perfect" }, took = par - 1, par = par, mood = 1, streak = 0 }
local p, t, s, k, b, share = Businesses.TourPay(BR, 1, best)
local base = 240 + 0.185 * L + 95
check("a perfect tour at level 1: the pay + the whole 40% tip, ★★★", p == math.floor(base + 0.5) and t == math.floor(base * 0.4 + 0.5) and s == 3 and k == 1
	and b == 0 and share == 1, p .. "+" .. t .. " " .. s)
local p0, t0, s0, k0 = Businesses.TourPay(BR, 1, { length = L, grades = { "Missed" }, took = par * 2, par = par, mood = 0.1, streak = 3 })
check("a bad tour still pays the base (no tip), ★, and ends the streak", p0 == p and t0 == 0 and s0 == 1 and k0 == 0, p0 .. "+" .. t0)
local _, tOk = Businesses.TourPay(BR, 1, { length = L, grades = { "Ok" }, took = par, par = par, mood = 1, streak = 0 })
check("an OK photo: its third of the tip at 40%", tOk == math.floor(base * 0.4 * (1 + 0.4 + 1) / 3 + 0.5), tOk)
local _, tLate = Businesses.TourPay(BR, 1, { length = L, grades = { "Perfect" }, took = par * 1.25, par = par, mood = 1, streak = 0 })
check("25% over par: half the time third", tLate == math.floor(base * 0.4 * (1 + 0.5 + 1) / 3 + 0.5), tLate)
local _, tMood = Businesses.TourPay(BR, 1, { length = L, grades = { "Perfect" }, took = par, par = par, mood = 0.6, streak = 0 })
check("60% happy: half the mood third (0 at 20%)", tMood == math.floor(base * 0.4 * (1 + 1 + 0.5) / 3 + 0.5), tMood)
local p5, t5 = Businesses.TourPay(BR, 5, best)
check("level 5 x1.25 on pay and tip", p5 == math.floor(base * 1.25 + 0.5) and t5 == math.floor(base * 0.4 * 1.25 + 0.5), p5 .. "+" .. t5)
-- The streak: ★★★ tours in a row raise the tip x1.1, x1.2, x1.3.
local mults = {}
local streak = 0
for i = 1, 5 do
	local _, tip, _, s2 = Businesses.TourPay(BR, 1, { length = L, grades = { "Perfect" }, took = 1, par = par, mood = 1, streak = streak })
	streak = s2
	mults[i] = string.format("%.2f", tip / t)
end
check("streak tips x1.0 x1.1 x1.2 x1.3 x1.3", table.concat(mults, " ") == "1.00 1.10 1.20 1.30 1.30", table.concat(mults, " "))
-- The specials.
local _, tc, sc = Businesses.TourPay(BR, 1, { length = L, grades = { "Perfect" }, took = 1, par = par, mood = 1, special = "Celebrity", streak = 0 })
check("a celebrity on a ★★★ tour: the tip x3", sc == 3 and math.abs(tc - t * 3) <= 1, tc)
local _, tc2 = Businesses.TourPay(BR, 1, { length = L, grades = { "Ok" }, took = 1, par = par, mood = 1, special = "Celebrity", streak = 0 })
check("...on a ★★ tour: no extra", tc2 == tOk, tc2)
local ps, ts = Businesses.TourPay(BR, 1, { length = L, grades = { "Perfect" }, took = 1, par = par, mood = 1, special = "Sunset", streak = 0 })
check("a sunset tour pays x1.3 (pay and tip)", ps == math.floor(base * 1.3 + 0.5) and ts == math.floor(base * 1.3 * 0.4 + 0.5), ps .. "+" .. ts)
local fr = Businesses.TourRoute("Fishing")
local fl = Businesses.TourLength(BR, fr)
local _, _, _, _, bonus = Businesses.TourPay(BR, 2, { length = fl, grades = { "Perfect", "Ok" }, took = 1, par = 100, mood = 1, special = "Fishing" })
check("a fishing party pays its bonus on top (x JobMult)", bonus == math.floor(250 * 1.06 + 0.5), bonus)
check("its par is x1.5", NEAR(Businesses.TourPar(fl, 2, T.Specials.Fishing.ParMult), Businesses.TourPar(fl, 2) * 1.5))
local old = Businesses.RateScale
Businesses.RateScale = 0.5
local ph = Businesses.TourPay(BR, 1, best)
check("RateScale halves tour pay too", math.abs(ph - p * 0.5) <= 1, ph)
Businesses.RateScale = old'

scenario tour_specials_odds '
local T = Businesses.Tour
check("about 1 in 8 tours is special", T.SpecialChance == 1 / 8)
check("dusk: from 17:12; night; until 5:30; not at noon", Businesses.SunsetTime(17.5, false) and Businesses.SunsetTime(2, false)
	and not Businesses.SunsetTime(12, false) and not Businesses.SunsetTime(16.9, false) and Businesses.SunsetTime(12, true))
local function odds(night)
	local c, n = {}, 0
	for i = 0, 7999 do
		local r1 = (i % 80) / 80
		local r2 = math.floor(i / 80) / 100
		local sp = Businesses.RollTourSpecial(r1, r2, night)
		if sp then c[sp] = (c[sp] or 0) + 1 end
		n += 1
	end
	return c, n
end
local day, n = odds(false)
check("by day: no sunset tours; celebrity and fishing 1 in 16 each", day.Sunset == nil and NEAR(day.Celebrity / n, 1 / 16, 0.006)
	and NEAR(day.Fishing / n, 1 / 16, 0.006), (day.Celebrity or 0) / n)
local night = odds(true)
check("at night: all three, 1 in 24 each", NEAR(night.Sunset / n, 1 / 24, 0.006) and NEAR(night.Celebrity / n, 1 / 24, 0.006)
	and NEAR(night.Fishing / n, 1 / 24, 0.006), (night.Sunset or 0) / n)
check("a roll over the chance is never special", Businesses.RollTourSpecial(0.2, 0.1, true) == nil and Businesses.RollTourSpecial(0 / 0, 0.5, false) ~= "Sunset")'

scenario tour_calibration '
-- The seeded simulation (BALANCE): ~90 studs/s on the water (0.8-1.2x a typical driver), every photo stop 2.5 s of
-- holding + 2-4 s slowing and speeding up, ~3 s to stop in the dock ring; the cycle adds the boarding (0.45 s a
-- tourist + 1.2 s), the glide (1.2 s), the tourists stepping off (2.5 s), NEXT TOUR (2 s) and the first walk (2 s).
-- A typical player: half the photo stops PERFECT (else OK, a few missed), the tourists end 60-100% happy (a ram in
-- one tour in five), night a third of the time; routes, specials and the streak as the server rolls them.
local T = Businesses.Tour
local seed = 12345
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
local function U(a, b) return a + (b - a) * rnd() end
local function sim(level, n, o)
	o = o or {}
	local money, secs, stars3, streak = 0, 0, 0, 0
	for _ = 1, n do
		local night = rnd() < 0.3
		local special = Businesses.RollTourSpecial(rnd(), rnd(), night)
		if o.plain then special = nil end
		local route = Businesses.PickRoute(level, rnd(), rnd())
		local sp = special and T.Specials[special]
		if sp and sp.Route then route = Businesses.TourRoute(sp.Route) end
		local L = Businesses.TourLength(BR, route)
		local v = 90 * U(o.vlo or 0.8, o.vhi or 1.2) * (special == "Fishing" and 0.8 or 1)
		local took = L / v + 3
		local grades = {}
		for _, s in ipairs(Businesses.TourStops(route)) do
			if s.Kind ~= "Pass" then
				took += (s.Kind == "Fish" and T.Fish.Hold or T.Photo.Hold) + U(2, 4)
				local r = rnd()
				local pp = o.pPerfect or 0.5
				table.insert(grades, r < pp and "Perfect" or (r < pp + (1 - pp) * 0.85 and "Ok" or "Missed"))
			end
		end
		local mood = math.clamp(U(o.mlo or 0.6, o.mhi or 1.0) - ((rnd() < (o.ram or 0.2)) and 0.15 or 0), 0, 1)
		local par = Businesses.TourPar(L, Businesses.TourStopCount(route), sp and sp.ParMult)
		local pay, tip, stars, s2, bonus = Businesses.TourPay(BR, level, { length = L, grades = grades, took = took, par = par, mood = mood,
			special = special, streak = o.plain and 0 or streak })
		streak = s2
		if stars == 3 then stars3 += 1 end
		money += pay + tip + bonus
		secs += took + T.BoardEach * Businesses.TourTourists(level) + T.BoardExtra + T.GlideTime + T.UnboardTime + 2 + 2
	end
	return money * 60 / secs, stars3 / n
end
local typical, s3 = sim(1, 40000)
check("a typical player makes about $1,400 a minute at level 1, every bonus included (+-5%)", typical >= 1400 * 0.95 and typical <= 1400 * 1.05,
	math.floor(typical))
check("about one tour in five is ★★★ for them (12-30%)", s3 >= 0.12 and s3 <= 0.3, s3)
local plain = sim(1, 40000, { plain = true })
check("the streak and the specials are inside the average (worth 0-5%)", typical >= plain * 0.995 and typical <= plain * 1.05, math.floor(plain))
local careless = sim(1, 20000, { pPerfect = 0.2, mlo = 0.3, mhi = 0.8, ram = 0.5 })
local smooth = sim(1, 20000, { pPerfect = 0.8, mlo = 0.85, mhi = 1.0, ram = 0.05 })
check("skill shows: careless < typical < smooth at the same speed (the base is always paid)", careless < typical and smooth > typical
	and careless > typical * 0.85, math.floor(careless) .. " / " .. math.floor(smooth))
local slow, fast = sim(1, 20000, { vlo = 0.65, vhi = 0.9 }), sim(1, 20000, { vlo = 1.05, vhi = 1.35 })
check("faster drivers earn more, slower ones less", fast > typical and slow < typical, math.floor(slow) .. " / " .. math.floor(fast))
local ok = true
for l = 2, 5 do
	local per = sim(l, 15000) / Businesses.JobMult(BR, l)
	if per < typical * 0.93 or per > typical * 1.07 then
		ok = false
		print(string.format("  level %d: $%d a minute before JobMult", l, math.floor(per)))
	end
end
check("every level, longer routes and all, pays about the same a minute before its JobMult (+-7%)", ok)
check("the job beats normal work ($900) by 1.3-1.7x, like the PRD job table", typical / 900 >= 1.3 and typical / 900 <= 1.7, typical / 900)'

scenario boat_rental_and_gate '
local R = Businesses.Rental
local owner, sink = Businesses.Split(BR.Service.Price)
check("a $150 rental: $105 to the featured owner, $45 sink", owner == 105 and sink == 45)
check("10 minutes, a warning at 1 minute, 60 s off it before it goes back", R.Seconds == 600 and R.Warn == 60 and R.LeaveGrace == 60)
local v = Vehicles.ById[R.Vehicle]
check("the rental is a real jet ski, and the label says so", v ~= nil and v.Boat == true and v.Class == "Jet Ski" and R.Label == "Jet ski"
	and string.find(string.lower(BR.Service.Name), "jet ski") ~= nil)
check("it is nobody premium boat (no police, pass or heist lock)", not v.Police and not v.Pass and not v.UnlockHeists)
local smallest = true
for _, w in ipairs(Vehicles.List) do
	if w.Boat and not w.Police and w.Size.Z < v.Size.Z then smallest = false end
end
check("it is the smallest boat in the game", smallest)
check("time left counts down to 0, never below", Businesses.RentalLeft(1000, 400) == 600 and Businesses.RentalLeft(1000, 1200) == 0
	and Businesses.RentalLeft(nil, 5) == 0 and Businesses.RentalLeft(0 / 0, 5) == 0)
local warnAt = R.Seconds - R.Warn
check("the warning comes 9 minutes in", Businesses.RentalLeft(R.Seconds, warnAt) == R.Warn)
-- The customer-XP cap is the shared one (2 a buyer an hour per owner): a renter can not farm the owner rank.
local rec, counted = nil, 0
for i = 1, 5 do
	local yes
	yes, rec = Businesses.CustomerXP(rec, i * 60)
	if yes then counted += 1 end
end
check("five rentals in an hour by one buyer: Empire XP twice", counted == 2)
-- The Empire 2 gate.
check("Boat Rentals needs Empire rank 2 (rank 1 can not buy it)", BR.Unlock == 2 and not Businesses.Unlocked(BR, 1) and Businesses.Unlocked(BR, 2)
	and Businesses.Unlocked(BR, 10))
check("rank 2 is 300 Empire XP, and it says it unlocks Boat Rentals", Businesses.RankFor(299) == 1 and Businesses.RankFor(300) == 2
	and string.find(Businesses.Empire.Unlocks[2], "Boat Rentals") ~= nil)
local X = Businesses.Empire.XP
check("a tour gives 10 Empire XP (like a delivery)", X.Tour == 10)
local first = X.Buy + X.UpgradePerLevel * 2 + 20 * X.Wash
check("the gate opens early: the Car Wash, its first upgrade and 20 washes (~15 minutes of work) reach rank 2", Businesses.RankFor(first) == 2, first)
check("...and 10 boat tours give as much Empire XP as 20 washes", 10 * X.Tour == 20 * X.Wash)'

# ---------------------------------------------------------------- M5: the Afterglow Nightclub

scenario nightclub_lot '
local Lo = NC.Layout
-- Every spot the building, the job and the robbers use is inside the 56 x 50 lot.
local inside = true
local function inLot(v, what)
	if math.abs(v.X) > 28 or math.abs(v.Z) > 25 then
		inside = false
		print("  outside the lot: " .. what)
	end
end
for _, k in ipairs({ "Door", "Register", "Exit", "Service", "LimoBay", "Carpet", "Safe", "Search", "BackDoor", "RaidCar" }) do inLot(Lo[k], k) end
for _, list in ipairs({ "Robbers", "Flashes", "RaidStand", "RaidWayIn", "RaidPathIn" }) do
	for i, v in ipairs(Lo[list]) do inLot(v, list .. i) end
end
check("every Nightclub spot is inside its lot", inside)
local function box(def)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs({ { -28, -25 }, { 28, -25 }, { -28, 25 }, { 28, 25 } }) do
		local p = Businesses.At(def, Vector3.new(c[1], 0, c[2]))
		x0, x1, z0, z1 = math.min(x0, p.X), math.max(x1, p.X), math.min(z0, p.Z), math.max(z1, p.Z)
	end
	return x0, x1, z0, z1
end
local x0, x1, z0, z1 = box(NC)
check("the lot spans x 1125..1175, z 327..383 (the box checked against the place file on Nov 5)", NEAR(x0, 1125, 0.01) and NEAR(x1, 1175, 0.01)
	and NEAR(z0, 327, 0.01) and NEAR(z1, 383, 0.01), string.format("%.1f..%.1f, %.1f..%.1f", x0, x1, z0, z1))
check("lot-space -Z faces west, over the boardwalk to Highway 1", Businesses.At(NC, Vector3.new(0, 0, -25)).X < NC.Position.X - 20)
check("it is on the beach strip east of the boardwalk (x 1076) and the palm row (fronds to x 1116)", x0 >= 1120)
check("its front is 12+ studs from Highway 1 (its east edge x 1030)", x0 - 1030 >= 12, x0 - 1030)
check("on Flamingo Beach ground (x 1000..1500), clear of the shore slope (x 1500+)", x0 >= 1000 and x1 <= 1490)
local function clear(ax0, ax1, az0, az1, bx0, bx1, bz0, bz1, margin)
	return ax1 + margin <= bx0 or bx1 + margin <= ax0 or az1 + margin <= bz0 or bz1 + margin <= az0
end
check("NOT at Club Nova, the heist: 300+ studs from its building (x 1031..1147, z -201..-99)", clear(x0, x1, z0, z1, 1031, 1147, -201, -99, 300))
check("clear of the beach snack shack (x 1092..1124, z 250..270) by 40+", clear(x0, x1, z0, z1, 1092, 1124, 250, 270, 40))
local ok = true
for _, r in ipairs({ { -210, -90, -543, -457, "AutoNeon" }, { 1668, 1700, 975, 1110, "Marina Boat Sales" }, { -278, -218, -354, -306, "Zap Shack" },
	{ 545, 695, 725, 835, "Car Meet" }, { 537, 583, 617, 663, "Courier Depot" }, { -549, -401, 1164, 1276, "Big Score depot" },
	{ -272, -50, -986, -894, "Big Score reserve" },
	-- the gameplay pads near the beach (the place file), with a 20-stud margin
	{ 1052, 1068, -708, -692, "ATM2" }, { 1095, 1145, -175, -125, "Club Nova pad" }, { 1312, 1328, -260, -240, "Boardwalk Hop ramp" },
	{ 1049, 1071, -1017, -883, "beach car pads" }, { 1625, 1655, -555, -525, "Surf Sprint start" }, { 1547, 1573, -465, -431, "beach boat pads" },
	{ 205, 255, 275, 325, "Coastal Bank" }, { 1695, 1745, 1275, 1325, "Sea Dream" }, { -265, -215, 15, 65, "Taxi Stand" } }) do
	if not clear(x0, x1, z0, z1, r[1], r[2], r[3], r[4], 20) then
		ok = false
		print("  too close to the " .. r[5])
	end
end
check("clear of every runtime lot and gameplay pad (20+ studs)", ok)
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
ok = true
for _, other in ipairs({ CW, PG, PS, BR }) do
	local bx0, bx1, bz0, bz1 = box(other)
	if not clear(x0, x1, z0, z1, bx0, bx1, bz0, bz1, 200) then
		ok = false
		print("  near " .. other.Id)
	end
end
check("200+ studs from the other four businesses", ok)
-- The forecourt: the limo fits its bay and the VIP box, both clear of the red carpet (x -2.2..2.2) and of each other.
local limo = Vehicles.ById[Businesses.Vip.Limo]
local w, l = limo.Size.X / 2, limo.Size.Z / 2
local function fits(c, what)
	local okFit = c.X - w > 2.2 or c.X + w < -2.2
	okFit = okFit and math.abs(c.X) + w <= 28 and c.Z - l >= -25 and c.Z + l <= -4
	if not okFit then print("  " .. what .. " does not fit") end
	return okFit
end
check("the limo fits its bay and the VIP mark, off the carpet, in front of the club", fits(Lo.LimoBay, "the bay") and fits(Lo.Carpet, "the mark"))
check("the bay and the mark are on opposite sides of the carpet", Lo.LimoBay.X * Lo.Carpet.X < 0)
check("parking back in the limo bay is not an arrival (the bay is outside the red-carpet ring)",
	(Lo.LimoBay - Lo.Carpet).Magnitude > Businesses.Vip.CarpetRadius, (Lo.LimoBay - Lo.Carpet).Magnitude)
-- Inside the club building (hold the door) vs the forecourt.
local function world(x, z) return Businesses.At(NC, Vector3.new(x, 2, z)) end
check("the lobby and the back room are inside; the carpet, the bay and the roof are not", Businesses.Inside(NC, world(0, 5))
	and Businesses.Inside(NC, world(16, 19)) and not Businesses.Inside(NC, world(0, -10)) and not Businesses.Inside(NC, world(-12, -15))
	and not Businesses.Inside(NC, Businesses.At(NC, Vector3.new(0, 20, 5))))
check("the safe, the search spot and the back door are in the back room (x 5.5..21, z 10..23)", Lo.Safe.X > 5.5 and Lo.Safe.Z > 11 and Lo.Search.X > 5.5
	and Lo.Search.Z > 11 and Lo.BackDoor.X > 8 and Lo.BackDoor.X < 11 and Lo.BackDoor.Z == 10)
check("two robbers in the lobby in front of the ticket counter (front face z 4), facing the till", #Lo.Robbers == 2 and Lo.Robbers[1].Z < 4
	and Lo.Robbers[2].Z < 4 and Lo.Register.Z > 4 and Lo.Register.Z < 6)
local from = Lo.Door + Vector3.new(0, 0, 2)
local t = (-4 - from.Z) / (Lo.Exit.Z - from.Z)
local xAtWall = from.X + (Lo.Exit.X - from.X) * t
check("robbers run out through the doorway (x -3..3)", xAtWall > -3 and xAtWall < 3, xAtWall)'

scenario map_letters '
-- Every business has its own letter, and none is a letter the maps already use for something else: H hideout, P police,
-- S spray, C chop shop / courier, A AutoNeon, B boats, G guns, D drift, T taxi / penthouse, M car meet, R races, J jumps,
-- N the minimap north marker (a round N on its edge, as an owned business blip pinned to the edge would be), $ heists.
local taken = { H = true, P = true, S = true, C = true, A = true, B = true, G = true, D = true, T = true, M = true, R = true, J = true, N = true, ["$"] = true }
local seen, ok = {}, true
for _, def in ipairs(Businesses.List) do
	local l = def.MapLetter
	if not l or taken[l] or seen[l] then
		ok = false
		print("  " .. def.Id .. " letter " .. tostring(l))
	end
	seen[l or "?"] = true
end
check("five different letters, none already on the maps", ok)
check("the Nightclub is a pink V (not N: the north marker)", NC.MapLetter == "V" and NC.MapColor.R > 0.9 and NC.MapColor.B > 0.5)
local colours = true
for _, def in ipairs(Businesses.List) do
	if def ~= NC and def.MapColor and math.abs(def.MapColor.R - NC.MapColor.R) + math.abs(def.MapColor.G - NC.MapColor.G) + math.abs(def.MapColor.B - NC.MapColor.B) < 0.25 then
		colours = false
	end
end
check("its pink is not another business colour", colours)'

scenario nightclub_levels_and_night '
-- The game day, from WorldService own lines (ACTS and nightnessAt):
'"$WORLD_DAY"'
local cycle = 0
for _, act in ipairs(ACTS) do cycle += act[3] end
local function clockAt(s)
	s = s % cycle
	for _, act in ipairs(ACTS) do
		if s <= act[3] then return (act[1] + (act[2] - act[1]) * (s / act[3])) % 24 end
		s -= act[3]
	end
	return 6
end
local night, n = 0, 0
for s = 0, cycle - 0.01, 0.05 do
	n += 1
	if nightnessAt(clockAt(s)) > 0.5 then night += 1 end
end
check("the day is 14 minutes (840 s)", cycle == 840, cycle)
check("IsNight is on 42.4% of the time, as Businesses.NightShare says", NEAR(night / n, Businesses.NightShare, 0.002), night / n)
-- The levels.
local t, c = {}, {}
for l = 1, 5 do
	t[l] = Businesses.Trickle(NC, l, false)
	c[l] = Businesses.Cap(NC, l)
end
check("trickle 375 500 625 750 875 a minute by day (the PRD first $180 -> $420 x~2.08)", table.concat(t, " ") == "375 500 625 750 875", table.concat(t, " "))
check("x2 at night: $750 a minute at level 1", Businesses.Trickle(NC, 1, false, true) == 750 and Businesses.Trickle(NC, 1, true, true) == 937.5)
check("only the club doubles at night", Businesses.Trickle(CW, 1, false, true) == 60 and Businesses.Trickle(BR, 1, false, true) == 256)
check("registers 20000 33750 47500 61250 75000", table.concat(c, " ") == "20000 33750 47500 61250 75000", table.concat(c, " "))
check("upgrades 100,000 / 150,000 / 200,000 / 250,000", Businesses.UpgradePrice(NC, 1) == 100000 and Businesses.UpgradePrice(NC, 2) == 150000
	and Businesses.UpgradePrice(NC, 3) == 200000 and Businesses.UpgradePrice(NC, 4) == 250000 and Businesses.UpgradePrice(NC, 5) == nil)
check("$250,000, legit with a back room, Empire 3, enabled, its own job module", NC.Price == 250000 and NC.Kind == "Legit" and NC.BackRoom == true
	and NC.Unlock == 3 and NC.Enabled == true and NC.Style == "Nightclub")
local h = Businesses.PaybackHours(NC)
check("trickle alone pays it back in 7.5-8 h online on the day-and-night average (the Nov 4 treatment)", h >= 7.5 and h <= 8, h)
check("(on the PRD first numbers it was ~16 h)", 250000 / (180 * (1 + Businesses.NightShare)) / 60 > 15)
local fills, up = true, true
for l = 1, 5 do
	local lv = NC.Levels[l]
	if l > 1 and (lv.Trickle <= NC.Levels[l - 1].Trickle or lv.Cap <= NC.Levels[l - 1].Cap) then up = false end
	local minutes = lv.Cap / Businesses.AvgTrickle(NC, l)
	if minutes < 36 or minutes > 61 then
		fills = false
		print(string.format("  level %d fills in %.0f min on average", l, minutes))
	end
end
check("trickle and register grow every level", up)
check("every register takes 36-60 minutes to fill on the day-and-night average", fills)
check("level 1 fills in ~53 min by day and ~27 at night", NEAR(NC.Levels[1].Cap / 375, 53.3, 0.1) and NEAR(NC.Levels[1].Cap / 750, 26.7, 0.1))
local total = NC.Price
for l = 1, 4 do total += Businesses.UpgradePrice(NC, l) end
local h5 = total / Businesses.AvgTrickle(NC, 5) / 60
check("everything paid in, at level 5, pays back on the average trickle in 10-14 h", h5 >= 10 and h5 <= 14, h5)
local r, e = Businesses.Accrue(NC, 0, 1, 60, false, true)
check("a minute at night earns $750", NEAR(r, 750) and NEAR(e, 750), r)
r = Businesses.Accrue(NC, 0, 1, 60, false, false)
check("a minute by day earns $375", NEAR(r, 375), r)
check("the night switch: IsNight, or the Studio override (a boolean) wins", Businesses.NightNow(true, nil) and not Businesses.NightNow(false, nil)
	and not Businesses.NightNow(true, false) and Businesses.NightNow(false, true) and not Businesses.NightNow(nil, nil))
check("START JOB offers only VIP PICKUPS", Businesses.HasJob(NC, "Vip") and #NC.Jobs == 1 and NC.Jobs[1].Label == "VIP PICKUPS")
check("every level says what it adds (5: the rooftop pool party)", NC.Levels[1].Adds ~= nil and string.find(NC.Levels[5].Adds, "pool") ~= nil
	and string.find(NC.Levels[3].Adds, "DJ") ~= nil and string.find(NC.Levels[4].Adds, "balcony") ~= nil)'

scenario vip_pay '
local V = Businesses.Vip
-- Par, the stop, the stars.
check("par = 6 s + the road back / 42", NEAR(Businesses.VipPar(1400), 6 + 1400 / 42), Businesses.VipPar(1400))
check("a Late VIP: par x0.8", NEAR(Businesses.VipPar(1400, V.Specials.Late.ParMult), (6 + 1400 / 42) * 0.8))
check("stops: PERFECT within 3 studs, GOOD within 7, else OK", Businesses.VipStop(0) == "Perfect" and Businesses.VipStop(3) == "Perfect"
	and Businesses.VipStop(3.1) == "Good" and Businesses.VipStop(7) == "Good" and Businesses.VipStop(7.5) == "Ok" and Businesses.VipStop(0 / 0) == "Ok")
check("the mark is inside the red-carpet ring", V.Stop.Good < V.CarpetRadius)
check("stars: on time + smooth + PERFECT = 3; none = 1", Businesses.VipStars(true, 0.9, "Perfect") == 3 and Businesses.VipStars(false, 0.1, "Ok") == 1
	and Businesses.VipStars(true, 0.85, "Good") == 2 and Businesses.VipStars(true, 0.79, "Perfect") == 2)
-- The comfort.
local M = V.Comfort
local c, d = Businesses.VipComfort(0.5, 1, 30, false, false, false)
check("calm driving lifts the comfort slowly", NEAR(c, 0.5 + M.Recover) and d == 0, c)
c = Businesses.VipComfort(1, 1, M.TurnLimit * 2, false, false, false)
check("a hard turn (twice the limit) for a second costs 5%", NEAR(c, 1 - M.TurnDrain), c)
c = Businesses.VipComfort(1, 1, 10000, false, false, false)
check("the worst turn costs 10% a second at most", NEAR(c, 1 - M.TurnDrain * M.TurnCap), c)
c = Businesses.VipComfort(1, 0.25, 0, true, false, false)
check("a crash costs 15%", NEAR(c, 1 - M.RamHit), c)
c = Businesses.VipComfort(1, 0.25, 0, false, true, false)
check("a jump costs 12%", NEAR(c, 1 - M.AirHit), c)
c = Businesses.VipComfort(1, 1, 0, false, false, true)
check("paparazzi flashing close by cost 2% a second", NEAR(c, 1 - M.FlashDrain), c)
c = Businesses.VipComfort(0 / 0, 1, 0 / 0, false, false, false)
check("bad numbers are never an error", c >= 0 and c <= 1)
check("a street corner at 40 studs/s (~50 lateral) costs nothing", Businesses.VipComfort(1, 1, 50, false, false, false) == 1)
-- The pay.
local road = 2800
local par = Businesses.VipPar(1400)
local best = { road = road, took = par - 1, par = par, comfort = 1, stop = "Perfect", streak = 0 }
local p, t, s, k, b, share = Businesses.VipPay(NC, 1, best)
local base = V.Base + V.PerStud * road
check("a perfect arrival at level 1: the pay + the whole tip, ★★★", p == math.floor(base + 0.5) and t == math.floor(base * V.TipRate + 0.5) and s == 3
	and k == 1 and b == 0 and share == 1, p .. "+" .. t .. " " .. s)
local p0, t0, s0, k0 = Businesses.VipPay(NC, 1, { road = road, took = par * 2, par = par, comfort = 0.1, stop = "Ok", streak = 3 })
check("a bad one still pays the base, a quarter third of the tip (the OK stop), ★, and ends the streak", p0 == p and s0 == 1 and k0 == 0
	and t0 == math.floor(base * V.TipRate * V.StopShare.Ok / 3 + 0.5), p0 .. "+" .. t0)
local _, tGood = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Good" })
check("a GOOD stop: its third at 60%", tGood == math.floor(base * V.TipRate * (1 + 1 + 0.6) / 3 + 0.5), tGood)
local _, tLate = Businesses.VipPay(NC, 1, { road = road, took = par * 1.25, par = par, comfort = 1, stop = "Perfect" })
check("25% over par: half the time third", tLate == math.floor(base * V.TipRate * (0.5 + 1 + 1) / 3 + 0.5), tLate)
local _, tC = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 0.6, stop = "Perfect" })
check("60% comfort: half the comfort third (0 at 20%)", tC == math.floor(base * V.TipRate * (1 + 0.5 + 1) / 3 + 0.5), tC)
local pn, tn = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Perfect", night = true })
check("at night: x1.25 on pay and tip", pn == math.floor(base * 1.25 + 0.5) and tn == math.floor(base * 1.25 * V.TipRate + 0.5), pn .. "+" .. tn)
local p5, t5 = Businesses.VipPay(NC, 5, best)
check("level 5 x1.25 on pay and tip", p5 == math.floor(base * 1.25 + 0.5) and t5 == math.floor(base * V.TipRate * 1.25 + 0.5), p5 .. "+" .. t5)
local mults, streak = {}, 0
for i = 1, 5 do
	local _, tip, _, s2 = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Perfect", streak = streak })
	streak = s2
	mults[i] = string.format("%.2f", tip / t)
end
check("streak tips x1.0 x1.1 x1.2 x1.3 x1.3", table.concat(mults, " ") == "1.00 1.10 1.20 1.30 1.30", table.concat(mults, " "))
local _, tS, sS = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Perfect", special = "Superstar" })
check("a superstar on a ★★★ arrival: the tip x3", sS == 3 and math.abs(tS - t * 3) <= 1, tS)
local _, tS2 = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Good", special = "Superstar" })
check("...on a ★★ one: no extra", tS2 == tGood, tS2)
local _, tL = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Perfect", special = "Late" })
check("late for the show: the tip x2", math.abs(tL - t * 2) <= 1, tL)
local _, _, _, _, bonus = Businesses.VipPay(NC, 2, { road = road, took = 1, par = par, comfort = 1, stop = "Ok", lost = true })
check("losing the paparazzi pays $250 x JobMult", bonus == math.floor(250 * 1.06 + 0.5), bonus)
local _, _, _, _, bonusT = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Ok", lost = true, special = "Tabloid" })
check("...double for a tabloid star", bonusT == 500, bonusT)
local _, _, _, _, none = Businesses.VipPay(NC, 1, { road = road, took = 1, par = par, comfort = 1, stop = "Ok", lost = false })
check("still on your tail at the club: no bonus (and no penalty)", none == 0)
local old = Businesses.RateScale
Businesses.RateScale = 0.5
local ph = Businesses.VipPay(NC, 1, best)
check("RateScale halves VIP pay too", math.abs(ph - p * 0.5) <= 1, ph)
Businesses.RateScale = old
-- The specials.
local counts, total = {}, 0
for i = 0, 7999 do
	local sp = Businesses.RollVipSpecial((i % 80) / 80, math.floor(i / 80) / 100)
	if sp then counts[sp] = (counts[sp] or 0) + 1 end
	total += 1
end
check("about 1 in 8 VIPs is special, equal odds among the three", NEAR((counts.Superstar or 0) / total, 1 / 24, 0.006) and NEAR((counts.Tabloid or 0) / total, 1 / 24, 0.006)
	and NEAR((counts.Late or 0) / total, 1 / 24, 0.006))
check("a roll over the chance is never special", Businesses.RollVipSpecial(0.2, 0.1) == nil and Businesses.RollVipSpecial(0.99, 0.5) == nil)
check("a VIP gives 12 Empire XP (a ~80 s cycle: ~9 a minute, like the other jobs)", Businesses.Empire.XP.Vip == 12)'

scenario vip_calibration '
-- The seeded simulation (BALANCE): a pickup 600-1,700 studs straight from the club (1.3x that by road, both ways),
-- ~45 studs/s on the road (0.8-1.2x a typical driver), 3 s to stop at the pickup, the VIP getting in (BoardTime + ~0.8
-- s), 4 s to stop on the mark, the carpet (CarpetTime), NEXT VIP (2 s) and ~1 s of the first walk to the limo. A typical
-- player: comfort ending 55-100% (a crash one ride in five), stops PERFECT 45% / GOOD 35% / OK 20%, the paparazzi
-- lost half the time; night as often as the game has it; specials and the streak as the server rolls them.
local V = Businesses.Vip
local seed = 4242
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
local function U(a, b) return a + (b - a) * rnd() end
local function sim(level, n, o)
	o = o or {}
	local money, secs, stars3, streak = 0, 0, 0, 0
	for _ = 1, n do
		local night = rnd() < Businesses.NightShare
		if o.day then night = false end
		local special = Businesses.RollVipSpecial(rnd(), rnd())
		if o.plain then special = nil end
		local sp = special and V.Specials[special]
		local road = U(V.DistMin, V.DistMax) * 1.3
		local v = 45 * U(o.vlo or 0.8, o.vhi or 1.2)
		local ride = road / v + 4
		local par = Businesses.VipPar(road, sp and sp.ParMult)
		local comfort = math.clamp(U(o.clo or 0.55, o.chi or 1) - ((rnd() < (o.ram or 0.2)) and 0.15 or 0), 0, 1)
		local r = rnd()
		local pp, pg = o.pPerfect or 0.45, o.pGood or 0.35
		local stop = r < pp and "Perfect" or (r < pp + pg and "Good" or "Ok")
		local pap = Businesses.PapRoll(rnd(), special)
		local lost = pap and rnd() < (o.lose or 0.5)
		if o.plain then lost = false end
		local pay, tip, stars, s2, bonus = Businesses.VipPay(NC, level, { road = road * 2, took = ride, par = par, comfort = comfort, stop = stop,
			lost = lost, special = special, streak = o.plain and 0 or streak, night = night })
		streak = s2
		if stars == 3 then stars3 += 1 end
		money += pay + tip + bonus
		secs += road / v + 3 + V.BoardTime + 0.8 + ride + V.CarpetTime + 2 + 1
	end
	return money * 60 / secs, stars3 / n
end
local typical, s3 = sim(1, 40000)
check("a typical player makes about $1,500 a minute at level 1, every bonus and the night included (+-5%)", typical >= 1500 * 0.95 and typical <= 1500 * 1.05,
	math.floor(typical))
check("about one arrival in eight is ★★★ for them (8-25%)", s3 >= 0.08 and s3 <= 0.25, s3)
local plain = sim(1, 40000, { plain = true })
check("the streak, the specials and the paparazzi bonus are inside the average (worth 0-8%)", typical >= plain * 0.995 and typical <= plain * 1.08,
	math.floor(plain))
local day = sim(1, 40000, { day = true })
check("night pay is inside it too: the day-only average is ~10% lower (6-14%)", typical / day >= 1.06 and typical / day <= 1.14, typical / day)
local careless = sim(1, 20000, { pPerfect = 0.15, pGood = 0.35, clo = 0.3, chi = 0.8, ram = 0.5, lose = 0.2 })
local smooth = sim(1, 20000, { pPerfect = 0.8, pGood = 0.15, clo = 0.85, chi = 1, ram = 0.05, lose = 0.7 })
check("skill shows: careless < typical < smooth at the same speed (the base is always paid)", careless < typical and smooth > typical
	and careless > typical * 0.85, math.floor(careless) .. " / " .. math.floor(smooth))
local slow, fast = sim(1, 20000, { vlo = 0.65, vhi = 0.9 }), sim(1, 20000, { vlo = 1.05, vhi = 1.35 })
check("faster drivers earn more, slower ones less", fast > typical and slow < typical, math.floor(slow) .. " / " .. math.floor(fast))
local ok = true
for l = 2, 5 do
	local per = sim(l, 15000) / Businesses.JobMult(NC, l)
	if per < typical * 0.97 or per > typical * 1.03 then
		ok = false
		print(string.format("  level %d: $%d a minute before JobMult", l, math.floor(per)))
	end
end
check("every level pays the same a minute before its JobMult (+-3%)", ok)
check("the job beats normal work ($900) by 1.4-1.9x, the PRD order (above the boat tours, under the risky Print Shop)", typical / 900 >= 1.4 and typical / 900 <= 1.9
	and typical > 1400 and typical < 1600, typical / 900)'

scenario paparazzi '
local P = Businesses.Vip.Pap
local yes = 0
for i = 0, 999 do
	if Businesses.PapRoll(i / 1000, nil) then yes += 1 end
end
check("paparazzi follow about 3 rides in 10", NEAR(yes / 1000, P.Chance, 0.002), yes / 1000)
check("a tabloid star always brings them", Businesses.PapRoll(0.99, "Tabloid") and not Businesses.PapRoll(0.99, "Superstar"))
check("1 car at levels 1-2, 2 from level 3", Businesses.PapCars(1) == 1 and Businesses.PapCars(2) == 1 and Businesses.PapCars(3) == 2 and Businesses.PapCars(5) == 2
	and Businesses.PapCars(0) == 1 and Businesses.PapCars(9) == 2)
local held, lost = 0, false
for _ = 1, 11 do held, lost = Businesses.PapStep(P.LoseDist + 10, held, 0.25) end
check("2.75 s far away: not yet", not lost and NEAR(held, 2.75), held)
held, lost = Businesses.PapStep(P.LoseDist + 10, held, 0.25)
check("3 s far away: LOST THEM", lost)
held, lost = Businesses.PapStep(P.LoseDist - 10, 2.9, 0.25)
check("back within reach: the count starts again", held == 0 and not lost)
held, lost = Businesses.PapStep(nil, 2.9, 0.25)
check("no paparazzi left (a broken NPC): they count as lost", lost)
check("they flash before you could lose them, and ease off well inside that", P.Near < P.FlashRange and P.FlashRange < P.LoseDist)
local limo = Vehicles.ById[Businesses.Vip.Limo]
check("the limo is a real civilian car (no police, boat, pass or heist lock)", limo ~= nil and not limo.Police and not limo.Boat and not limo.Pass
	and not limo.UnlockHeists)
check("they are slower than the limo (a driver who goes for it loses them)", P.Top < limo.MaxSpeed * 0.7, P.Top / limo.MaxSpeed)
local pc = Vehicles.ById[P.Car]
check("their car is a real car that can reach their speed", pc ~= nil and not pc.Boat and pc.MaxSpeed >= P.Top)'

scenario club_services '
local CL = Businesses.Club
local owner, sink = Businesses.Split(NC.Service.Price)
check("the cover charge is $50: $35 to the featured owner, $15 sink", NC.Service.Price == 50 and owner == 35 and sink == 15 and NC.Service.Kind == "Cover")
owner, sink = Businesses.Split(NC.Booth.Price)
check("the VIP booth is $250: $175 to the featured owner, $75 sink", NC.Booth.Price == 250 and owner == 175 and sink == 75)
check("the owner toast words", NC.Service.Words == "a cover charge" and NC.Booth.Words == "a VIP booth")
check("a booth lasts 15 minutes, a warning at 1, a cover pass 30", CL.BoothSeconds == 900 and CL.BoothWarn == 60 and CL.CoverValid == 1800)
-- The club inside is far off the map and away from the homes insides (x 12000+, z 0+, 2500 apart): further than any
-- streaming radius (1024), so it never loads for anyone outside.
local o = CL.Origin
check("the club inside is 10,000+ studs off the map (the land is x -2000..2900, z -2400..2400)", o.X <= -2000 - 10000 or o.Z <= -2400 - 9000)
check("...and 20,000+ from the nearest home inside", (Vector3.new(12000, o.Y, 0) - o).Magnitude > 20000)
check("high above nothing (y 120: the floor is the club own)", o.Y >= 100)
check("the booth: inside counts, the dance floor does not", Businesses.InBooth(o + Vector3.new(-30, 2, -4)) and not Businesses.InBooth(o + Vector3.new(0, 2, 0))
	and not Businesses.InBooth(o + Vector3.new(-30, 30, -4)) and not Businesses.InBooth(nil))
check("the booth rope and the place people are shown out to are outside the booth", not Businesses.InBooth(o + CL.BoothRope) and not Businesses.InBooth(o + CL.BoothOut))
check("time left counts down to 0, never below", Businesses.TimeLeft(1000, 400) == 600 and Businesses.TimeLeft(1000, 1200) == 0
	and Businesses.TimeLeft(nil, 5) == 0 and Businesses.TimeLeft(0 / 0, 5) == 0)
local rec, counted = nil, 0
for i = 1, 6 do
	local yes
	yes, rec = Businesses.CustomerXP(rec, i * 60)
	if yes then counted += 1 end
end
check("six covers in an hour by one buyer: Empire XP twice (the shared cap)", counted == 2)
check("dancers grow with the level, at most 6 (light on phones)", CL.Dancers[1] < CL.Dancers[5] and CL.Dancers[5] <= 6)'

scenario back_room '
local BRm = Businesses.BackRoom
check("the back room can be raided, the café can not", Businesses.HasRaids(NC) and Businesses.HasRaids(PS) and not Businesses.HasRaids(PG) and not Businesses.HasRaids(nil))
local s, r, w = {}, {}, {}
for l = 1, 5 do
	s[l], r[l], w[l] = Businesses.BackRoomStock(l), Businesses.BackRoomRate(l), Businesses.BackRoomWash(l)
end
check("stock, rate and wash grow every level", s[5] > s[1] and r[5] > r[1] and w[5] > w[1] and s[3] > s[2] and r[3] > r[2])
check("a wash never clears more than a third of a full safe (several trips)", (function()
	for l = 1, 5 do if w[l] * 3 > s[l] + 1 then return false end end
	return true
end)())
check("DirtyCap: the club back room, the Print Shop presses", Businesses.DirtyCap(NC, 2) == s[2] and Businesses.DirtyCap(PS, 2) == Businesses.Stock(2))
local d, add = Businesses.BackRoomAccrue(0, 1, 60, true)
check("a minute at night: $80 at level 1", NEAR(d, 80) and NEAR(add, 80), d)
d, add = Businesses.BackRoomAccrue(0, 1, 60, false)
check("nothing by day (the card game runs after dark)", d == 0 and add == 0)
d = Businesses.BackRoomAccrue(1.5, 1, 1, true)
check("cents add up (1 s at night: +$1.33)", NEAR(d, 1.5 + 80 / 60, 1e-6), d)
d, add = Businesses.BackRoomAccrue(s[1] - 10, 1, 600, true)
check("it stops at the safe size", d == s[1] and NEAR(add, 10), d)
d, add = Businesses.BackRoomAccrue(s[1] + 50, 1, 60, true)
check("a safe over its size keeps it and takes nothing", d == s[1] + 50 and add == 0)
check("about $34 a minute on average at level 1 (night only), a small shady extra", NEAR(r[1] * Businesses.NightShare, 34, 1), r[1] * Businesses.NightShare)
local amt, left = Businesses.BackRoomWashAmount(6000.75, 1)
check("a WASH moves up to $2,500 at level 1, whole dollars", amt == 2500 and NEAR(left, 3500.75), amt)
amt, left = Businesses.BackRoomWashAmount(700.4, 1)
check("...or what there is", amt == 700 and NEAR(left, 0.4), amt)
check("a 4 s hold, every 5 minutes", BRm.WashHold == 4 and BRm.WashGap == 300)
-- Raids on the back room (the Print Shop rules, the back room numbers).
local R = Businesses.Raid
check("no warrant below $4,000 in the safe", Businesses.WarrantChance(3999, 1, s[1], BRm.MinDirty) == 0)
check("10% a roll at $4,000, 40% with the safe full", NEAR(Businesses.WarrantChance(4000, 1, s[1], BRm.MinDirty), R.Chance[1])
	and NEAR(Businesses.WarrantChance(s[1], 1, s[1], BRm.MinDirty), R.Chance[2]))
check("the Print Shop odds are unchanged (no cap given)", NEAR(Businesses.WarrantChance(R.MinDirty, 1), 0.10) and NEAR(Businesses.WarrantChance(Businesses.Stock(1), 1), 0.40))
local nightMin = BRm.MinDirty / r[1]
check("hoarding: ~50 night minutes (~2 h of play) of card games before a warrant can come", nightMin >= 45 and nightMin <= 55, nightMin)
check("a raid on the back room can pay the cops less than it takes (no farming)", Businesses.RaidReward(BRm.MinDirty, 1) * 1.2 < BRm.MinDirty)
check("an owner gets 10 Empire XP a wash", Businesses.Empire.XP.BackRoom == 10)'

scenario empire3_gate '
local X = Businesses.Empire.XP
check("the Nightclub needs Empire rank 3: 2 can not, 3 and up can", NC.Unlock == 3 and not Businesses.Unlocked(NC, 2) and Businesses.Unlocked(NC, 3)
	and Businesses.Unlocked(NC, 10))
check("rank 3 is 900 Empire XP, and it says it unlocks the Nightclub", Businesses.RankFor(899) == 2 and Businesses.RankFor(900) == 3
	and string.find(Businesses.Empire.Unlocks[3], "Nightclub") ~= nil)
-- A sensible time to get there: the Car Wash bought and taken to level 3 (350), Palm Grind bought (100), then about
-- 45 minutes of business jobs at ~10 Empire XP a minute (a wash 5 every ~30 s, a delivery 10, a rush stop 6, a tour
-- 10, a press run 5 + a launder 15).
local path = X.Buy + X.UpgradePerLevel * 2 + X.UpgradePerLevel * 3 + X.Buy + 45 * 10
check("the Car Wash to level 3, the café and ~45 minutes of jobs reach rank 3 (~1-1.5 h of business play in all)", Businesses.RankFor(path) == 3, path)
local jobsOnly = (900 - X.Buy) / 10
check("buying only the Car Wash: ~80 minutes of jobs (60-100)", jobsOnly >= 60 and jobsOnly <= 100, jobsOnly)
check("buying the club gives 100 XP, its upgrades 700 in all", X.Buy == 100 and X.UpgradePerLevel * (2 + 3 + 4 + 5) == 700)'
