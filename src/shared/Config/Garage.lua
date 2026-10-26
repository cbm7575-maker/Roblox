-- Garage (ModuleScript, ReplicatedStorage.Shared.Config.Garage)
-- Car ownership and customising prices (Game Design Spec). Cars are bought in person at AutoNeon Motors
-- (boats at Marina Boat Sales, DealershipService); the phone's AUTONEON app only browses and routes you
-- there. The phone's Garage app spawns, customises and tunes the cars you own.
--
-- TUNING (Garage.Tune, Garage.Exhausts): upgrades for land cars you own (never boats, police cars or
-- street cars: Garage.CanTune). GarageService sells them, PhoneUI's TUNE page shows them, and both use
-- the helpers at the end of this file so prices and numbers can't drift apart.
--   * Five tracks (Engine, Turbo, Brakes, Tyres, Nitro), stages bought in order, per car. A stage
--     costs its Base price x the car's tier (Garage.TuneTier, from its dealer price).
--   * Exhausts change the engine's sound only: bought once per car, then swapping is free. The key
--     of the fitted one is the car attribute "Exhaust" (the same keys as Config.Sounds.Exhausts).
--   * AUTO TUNE (Garage.AutoTunePlan): buys every stage the player can afford, best value first.
--     It never touches the exhaust (a sound is a matter of taste, not of value).
--   * Saved in data.custom[carId]: tune = { Engine = 0-3, Turbo, Brakes, Tyres, Nitro },
--     exhaust = fitted key (nil = Stock), exhausts = { [key] = true } bought.
--   * Mirrored to the player attribute "Tune_<carId>", three fields split by "|":
--         "E2,T1,B0,G1,N2|Muscle|Sport,Muscle"
--     1) every track's Code and stage, 2) the fitted exhaust, 3) the exhausts bought for this car
--     (Stock is always owned and never listed). No attribute = a stock car. Garage.ParseTune reads
--     it, Garage.FormatTune writes it.
--   * A tune table (Garage.NewTune / ParseTune, and GarageService's saved copy) looks like:
--         { Stages = { Engine = 2, ... }, Exhaust = "Muscle", Owned = { Stock = true, ... }, Total = 6 }
--   * Garage.MaxGain(field) is the most a full tune adds to one car attribute ("MaxSpeed" -> 0.15),
--     for server checks that need "the fastest any car can go". Checks that look at a car read its own
--     MaxSpeed attribute and need nothing. The two with no car to look at are the anti-teleport timers
--     in MissionService and EventService (their MAX_TRAVEL): a tuned car out-runs every stock one, so
--     that limit must be at least Vehicles.TopSpeed x (1 + MaxGain("MaxSpeed")) x NitroSpeed
--     (215 x 1.15 x 1.2 = 297 studs/s; the fastest STOCK car on nitro only does 258). Raise Engine's
--     Gain below and check that both still clear it.

local Garage = {}

-- Entries with Pass = "<Key>" need that game pass (player attribute Pass_<Key>); entries with
-- Unlock = "<Key>" are earned in play (player attribute Unlock_<Key>).

-- Can this player use a paint / glow entry?
function Garage.Allowed(player, entry)
	if entry.Pass and not player:GetAttribute("Pass_" .. entry.Pass) then
		return false
	end
	if entry.Unlock and not player:GetAttribute("Unlock_" .. entry.Unlock) then
		return false
	end
	return true
end

-- Everyone owns these from the start.
Garage.StarterCars = { "Palmetto", "SunrayPatrol", "Splash", "HarborPatrol" } -- jet ski = free marina rental

Garage.PaintPrice = 500
Garage.UnderglowPrice = 3000
Garage.RimPrice = 1500

Garage.Paints = {
	{ Name = "Flamingo", Color = Color3.fromRGB(255, 120, 190) },
	{ Name = "Seafoam", Color = Color3.fromRGB(110, 242, 196) },
	{ Name = "Sunset", Color = Color3.fromRGB(255, 138, 61) },
	{ Name = "Grape", Color = Color3.fromRGB(123, 47, 255) },
	{ Name = "Electric", Color = Color3.fromRGB(34, 225, 255) },
	{ Name = "Lemon", Color = Color3.fromRGB(255, 214, 10) },
	{ Name = "Pearl", Color = Color3.fromRGB(245, 245, 250) },
	{ Name = "Midnight", Color = Color3.fromRGB(22, 22, 34) },
	{ Name = "Cherry", Color = Color3.fromRGB(220, 30, 60) },
	{ Name = "Ocean", Color = Color3.fromRGB(30, 90, 200) },
	{ Name = "Lime", Color = Color3.fromRGB(120, 220, 60) },
	{ Name = "Blush", Color = Color3.fromRGB(255, 200, 215) },
	-- VIP pass paints
	{ Name = "VIP Gold", Color = Color3.fromRGB(255, 196, 40), Pass = "VIP" },
	{ Name = "VIP Hot Pink", Color = Color3.fromRGB(255, 20, 147), Pass = "VIP" },
	{ Name = "VIP Aqua", Color = Color3.fromRGB(0, 255, 220), Pass = "VIP" },
	-- Earned: 7-day login streak
	{ Name = "Streak Sunset", Color = Color3.fromRGB(255, 94, 58), Unlock = "Streak7" },
	-- Earned: rank 10
	{ Name = "Neon Legend", Color = Color3.fromRGB(255, 0, 170), Unlock = "CivRank10" },
	{ Name = "Midnight Blue", Color = Color3.fromRGB(16, 30, 90), Unlock = "CopRank10" },
	-- Earned: play with Roblox friends on 3 different days (FriendsService). Always append new paints
	-- at the end: saved cars store their paint by list position.
	{ Name = "Squad", Color = Color3.fromRGB(0, 170, 150), Unlock = "Squad" },
}

Garage.Glows = {
	{ Name = "Hot Pink", Color = Color3.fromRGB(255, 62, 165) },
	{ Name = "Cyan", Color = Color3.fromRGB(34, 225, 255) },
	{ Name = "Purple", Color = Color3.fromRGB(123, 47, 255) },
	{ Name = "Orange", Color = Color3.fromRGB(255, 138, 61) },
	{ Name = "Lime", Color = Color3.fromRGB(110, 242, 120) },
	{ Name = "White", Color = Color3.fromRGB(240, 240, 255) },
	-- Neon Garage pass colours
	{ Name = "Red", Color = Color3.fromRGB(255, 30, 60), Pass = "NeonGarage" },
	{ Name = "Gold", Color = Color3.fromRGB(255, 200, 40), Pass = "NeonGarage" },
	{ Name = "Blue", Color = Color3.fromRGB(40, 90, 255), Pass = "NeonGarage" },
	{ Name = "Magenta", Color = Color3.fromRGB(255, 0, 255), Pass = "NeonGarage" },
	{ Name = "Teal", Color = Color3.fromRGB(0, 200, 170), Pass = "NeonGarage" },
	{ Name = "Violet", Color = Color3.fromRGB(170, 90, 255), Pass = "NeonGarage" },
}

Garage.Rims = {
	{ Name = "Chrome", Color = Color3.fromRGB(200, 205, 215) },
	{ Name = "Gold", Color = Color3.fromRGB(255, 200, 60) },
	{ Name = "Black", Color = Color3.fromRGB(25, 25, 30) },
	{ Name = "Pink", Color = Color3.fromRGB(255, 62, 165) },
	{ Name = "Cyan", Color = Color3.fromRGB(34, 225, 255) },
	{ Name = "White", Color = Color3.fromRGB(245, 245, 250) },
	{ Name = "Gold (rank 20)", Color = Color3.fromRGB(255, 190, 40), Unlock = "Rank20" },
}

------------------------------------------------------------------ tuning

-- Each track:
--   Key     saved name and remote argument; also its name on screen ("Engine")
--   Code    one letter in the "Tune_<carId>" attribute
--   Stat    its bar's label on the TUNE page (display only; short, phones draw it big)
--   What    what a stage adds, after the percentage ("+10% top speed")
--   Fields  the car attributes it multiplies (Config.Vehicles fields CarPhysics reads)
--   Gain    total gain over stock at each stage (not added up: stage 2 = +10%, not +5% more)
--   Base    price of each stage for a tier 1 car
--   Worth   how much one stage is felt by the driver. AUTO TUNE buys the best Worth per dollar first.
-- Engine tops out at +15%. What that does to the line-up (Config.Vehicles top speeds, studs/s):
--   * Tier 1 stays under tier 2: the best tier 1 cars (Mangrove, Sandpiper: 130) reach 149.5, just
--     under the stock Flamingo (150).
--   * Tier 2 stays under the Solana GT (190): the Night Heron (165) reaches 189.75. It does pass the
--     stock Silver Egret (185, the slow heavy luxury car); keeping it under would need Engine at +12%.
--   * Inside tier 3 it does NOT hold: fully tuned, the cash cars and the game-pass Vortex out-run the
--     STOCK heist-locked cars (Riptide R 205, Storm Petrel 215): Solana GT 218.5, Albatross GT 227.7
--     and Vortex 230 pass both, Silver Egret 212.75 passes the Riptide R. Tuned against tuned the heist
--     cars are still the fastest in the game (Riptide R 235.75, Storm Petrel 247.25), so the crime game
--     keeps the top spot. (To keep cash and pass cars under the STOCK heist cars too, Garage.TunedStats
--     would have to cap their MaxSpeed at 204, which makes their last Engine stages buy nothing.)
-- Tyres leave DriftGrip alone, so the handbrake still slides the same.
-- Prices: all five tracks cost $47,250 on a tier 1 car, $94,500 on tier 2 and $141,750 on tier 3, about
-- the step up to the next cars, so tuning what you have or saving for the next one is a real choice.
Garage.Tune = {
	-- Dealer price where tier 2 and tier 3 start. Game-pass cars (no cash price) are top tier.
	TierPrices = { 25000, 95000 },
	Tracks = {
		{ Key = "Engine", Code = "E", Stat = "TOP SPEED", What = "top speed", Fields = { "MaxSpeed" },
			Gain = { 0.05, 0.10, 0.15 }, Base = { 2000, 5000, 11000 }, Worth = 10 },
		{ Key = "Turbo", Code = "T", Stat = "ACCEL", What = "acceleration", Fields = { "Accel" },
			Gain = { 0.10, 0.20, 0.30 }, Base = { 1500, 4000, 9000 }, Worth = 7 },
		{ Key = "Brakes", Code = "B", Stat = "BRAKING", What = "braking", Fields = { "Brake" },
			Gain = { 0.15, 0.30 }, Base = { 1000, 3000 }, Worth = 3 },
		{ Key = "Tyres", Code = "G", Stat = "GRIP", What = "grip", Fields = { "Grip", "TireFriction" },
			Gain = { 0.08, 0.16 }, Base = { 1250, 3500 }, Worth = 4 },
		{ Key = "Nitro", Code = "N", Stat = "NITRO", What = "nitro tank", Fields = { "NitroSeconds" },
			Gain = { 0.25, 0.50 }, Base = { 1500, 4500 }, Worth = 5 },
	},
}

-- Exhausts, in menu order. Sound only (SoundClient reads the car attribute "Exhaust"), so the price is
-- the same for every car. Keys must match Config.Sounds.Exhausts exactly.
Garage.Exhausts = {
	{ Key = "Stock", Name = "STOCK", Price = 0 },
	{ Key = "Sport", Name = "SPORT", Price = 2000 },
	{ Key = "Muscle", Name = "MUSCLE", Price = 5000 },
	{ Key = "Race", Name = "RACE", Price = 8000 },
	{ Key = "Whisper", Name = "WHISPER", Price = 4000 },
}

local TRACKS = Garage.Tune.Tracks
local trackByCode = {}
Garage.TrackByKey = {}
Garage.MaxStages = {} -- [track key] = its last stage (a fully tuned car)
Garage.MaxTuneTotal = 0 -- stages on a fully tuned car, all tracks together
for _, track in ipairs(TRACKS) do
	Garage.TrackByKey[track.Key] = track
	trackByCode[track.Code] = track
	Garage.MaxStages[track.Key] = #track.Gain
	Garage.MaxTuneTotal += #track.Gain
end

Garage.ExhaustByKey = {}
for _, exhaust in ipairs(Garage.Exhausts) do
	Garage.ExhaustByKey[exhaust.Key] = exhaust
end

-- Can this vehicle (a Config.Vehicles entry) be tuned at all? Land cars a player can own: no boats,
-- no police cars, no street-only cars.
function Garage.CanTune(def)
	return def ~= nil and not def.Boat and not def.Police and not def.Hidden
end

-- Price tier of a car: 1 for starter and cheap cars, 2 for mid, 3 for supercars and game-pass cars.
function Garage.TuneTier(def)
	local steps = Garage.Tune.TierPrices
	if def.Pass then
		return #steps + 1
	end
	local tier = 1
	for _, price in ipairs(steps) do
		if (def.Price or 0) >= price then
			tier += 1
		end
	end
	return tier
end

-- What `stage` of a track costs on this car, or nil when the track has no such stage (already maxed).
function Garage.StagePrice(def, trackKey, stage)
	local track = Garage.TrackByKey[trackKey]
	local base = track and track.Base[stage]
	if not base then
		return nil
	end
	return base * Garage.TuneTier(def)
end

function Garage.TuneTotal(stages)
	local total = 0
	for _, track in ipairs(TRACKS) do
		total += stages[track.Key] or 0
	end
	return total
end

-- A stock car's tune.
function Garage.NewTune()
	local tune = { Stages = {}, Exhaust = "Stock", Owned = { Stock = true }, Total = 0 }
	for _, track in ipairs(TRACKS) do
		tune.Stages[track.Key] = 0
	end
	return tune
end

-- The "Tune_<carId>" attribute text for a tune (see the top of the file).
function Garage.FormatTune(tune)
	local stages = {}
	for i, track in ipairs(TRACKS) do
		stages[i] = track.Code .. tostring(tune.Stages[track.Key] or 0)
	end
	local bought = {}
	for _, exhaust in ipairs(Garage.Exhausts) do
		if exhaust.Key ~= "Stock" and tune.Owned[exhaust.Key] then
			table.insert(bought, exhaust.Key)
		end
	end
	return table.concat(stages, ",") .. "|" .. tune.Exhaust .. "|" .. table.concat(bought, ",")
end

-- Read that text back into a tune table. Anything missing or odd reads as stock, so nil (no attribute
-- yet) is fine. Plain splits only: no string patterns.
function Garage.ParseTune(text)
	local tune = Garage.NewTune()
	if type(text) ~= "string" then
		return tune
	end
	local fields = string.split(text, "|")
	for _, item in ipairs(string.split(fields[1], ",")) do
		local track = trackByCode[string.sub(item, 1, 1)]
		local stage = tonumber(string.sub(item, 2))
		if track and stage and stage == stage then
			tune.Stages[track.Key] = math.clamp(math.floor(stage), 0, #track.Gain)
		end
	end
	for _, key in ipairs(string.split(fields[3] or "", ",")) do
		if Garage.ExhaustByKey[key] then
			tune.Owned[key] = true
		end
	end
	if fields[2] and tune.Owned[fields[2]] then
		tune.Exhaust = fields[2]
	end
	tune.Total = Garage.TuneTotal(tune.Stages)
	return tune
end

-- The tuned value of every field the tracks touch, worked out from `base`: the car's STOCK numbers (a
-- Config.Vehicles entry or Vehicles.Resolve's table), so gains never pile up on an already tuned car.
function Garage.TunedStats(base, stages)
	local out = {}
	for _, track in ipairs(TRACKS) do
		local gain = track.Gain[stages[track.Key] or 0] or 0
		for _, field in ipairs(track.Fields) do
			out[field] = (base[field] or 0) * (1 + gain)
		end
	end
	return out
end

-- The most a full tune adds to one car attribute, as a share of stock ("MaxSpeed" -> 0.15); 0 for a
-- field no track touches. For checks that must allow the fastest car there can be and have no car to
-- read a MaxSpeed attribute from (MissionService's and EventService's MAX_TRAVEL: see the header).
function Garage.MaxGain(field)
	local best = 0
	for _, track in ipairs(TRACKS) do
		if table.find(track.Fields, field) then
			best = math.max(best, track.Gain[#track.Gain])
		end
	end
	return best
end

-- AUTO TUNE: the stages `cash` buys for this car, in buying order. Each step takes the affordable next
-- stage with the best Worth per dollar (the earlier track wins a tie), so cheap early stages come before
-- pricey late ones and nothing affordable is left over.
-- Returns plan = { { Track = key, Stage = n, Price = dollars }, ... }, its total, and the price of the
-- cheapest stage still to buy (nil on a fully tuned car), for "you need $X" when the plan is empty.
function Garage.AutoTunePlan(def, stages, cash)
	local have = {}
	local cheapest
	for _, track in ipairs(TRACKS) do
		have[track.Key] = stages[track.Key] or 0
		local price = Garage.StagePrice(def, track.Key, have[track.Key] + 1)
		if price and (not cheapest or price < cheapest) then
			cheapest = price
		end
	end
	local plan, total = {}, 0
	-- At most one pass per stage there is to buy (12).
	for _ = 1, Garage.MaxTuneTotal do
		local best, bestPrice, bestValue
		for _, track in ipairs(TRACKS) do
			local price = Garage.StagePrice(def, track.Key, have[track.Key] + 1)
			if price and price <= cash - total then
				local value = track.Worth / math.max(price, 1)
				if not bestValue or value > bestValue then
					best, bestPrice, bestValue = track, price, value
				end
			end
		end
		if not best then
			break
		end
		have[best.Key] += 1
		total += bestPrice
		table.insert(plan, { Track = best.Key, Stage = have[best.Key], Price = bestPrice })
	end
	return plan, total, cheapest
end

-- "Engine 2, Turbo 2, Brakes 1": the stage each track ends on after a plan, in track order.
function Garage.PlanText(plan)
	local reached = {}
	for _, step in ipairs(plan) do
		reached[step.Track] = math.max(reached[step.Track] or 0, step.Stage)
	end
	local parts = {}
	for _, track in ipairs(TRACKS) do
		if reached[track.Key] then
			table.insert(parts, track.Key .. " " .. reached[track.Key])
		end
	end
	return table.concat(parts, ", ")
end

return Garage
