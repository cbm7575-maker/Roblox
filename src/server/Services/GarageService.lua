-- GarageService (ModuleScript, ServerScriptService.Services.GarageService)
-- Owning, customising and tuning cars. Saved in the player's profile (DataService):
--   data.owned[carId] = true
--   data.custom[carId] = { paint = Garage.Paints index, glow = Garage.Glows index, rim = Garage.Rims index,
--                          tune = { Engine = 0-3, Turbo = 0-3, Brakes = 0-2, Tyres = 0-2, Nitro = 0-2 },
--                          exhaust = fitted exhaust key (nil = Stock), exhausts = { [key] = true } bought }
--   (data.custom already defaults to {} in DataService; the tune fields appear with the first purchase.)
-- Remotes (all validated here):
--   RequestBuyCar(id)                   -> costs Config.Vehicles price, only next to the car at a dealership
--                                          (DealershipService.IsNear); pass cars need their game pass;
--                                          heist-locked cars (UnlockHeists) need that many big heists
--                                          first (player attribute "BigHeists", HeistService)
--   RequestPaint(id, paintIndex)        -> $500
--   RequestUnderglow(id, glowIndex)     -> $3,000 the first time on a car, then colour changes are free
--   RequestRims(id, rimIndex)           -> $1,500
--   RequestTune(id, trackKey, stage?)   -> buys that track's next stage (Config.Garage.Tune: the price
--                                          scales with the car's tier). stage: the stage the phone's
--                                          button showed; if that isn't the next one any more, nothing
--                                          is bought (see "Asking twice" below).
--   RequestExhaust(id, exhaustKey)      -> buys that exhaust for the car (once), or fits one already
--                                          bought for free
--   RequestAutoTune(id, budget?, have?) -> buys every stage the player can afford, best value first
--                                          (Garage.AutoTunePlan), in one payment. budget: the total the
--                                          phone's confirm line showed, so it never spends more than that.
--                                          have: the stages the car had when the phone worked out its
--                                          plan; if the car has moved on, nothing is bought.
--   Asking twice: on a slow connection the phone gives up waiting (PhoneUI's FITTING...) and the player
--   confirms again; then both requests arrive. The second must not buy the NEXT, dearer thing nobody saw
--   a price for, so the phone says what it expects (stage / have) and a request that no longer matches
--   is dropped without a word. Both are optional (the Studio test hook fires without them). An exhaust
--   asked for twice is safe as it is: the second finds it fitted.
--   Tuning is for land cars you own: never boats, police cars or street cars (Garage.CanTune), not in
--   prison, and not while wanted and seen ("TuneWanted").
-- Picking the paint or rims a car already has costs nothing (ignored). Boats can't be customised: the
-- hull keeps its own textured colours (CarBuilder.attachBoatBody), has no wheels for rims and never shows
-- underglow, so all three requests are ignored for boats (the phone has no STYLE button for them).
-- Pass cars count as owned while the player has attribute "Pass_<PassName>" (set by the shop, step 4.5);
-- cop-rank cars while "CopRank" >= UnlockCopRank.
-- The saved owned list is mirrored to the player attribute "OwnedCars" (comma list) for the phone UI, and
-- customisations to "Custom_<id>" attributes ("paint,glow,rim", 0 = default). Pass and cop-rank cars are
-- not in OwnedCars: the phone and the dealer card add them from the Pass_ / CopRank attributes.
-- A car's tune is mirrored to "Tune_<id>" ("E2,T1,B0,G1,N2|Muscle|Sport,Muscle": Config.Garage explains
-- it and has the parser), only for cars that have one.
-- Answers go back on GarageResult: { Kind = "Bought" | "Painted" | "Rims" | "Glow", Id }, and for tuning
--   { Kind = "Tuned", Id, Track, Stage, Price }, { Kind = "Exhaust", Id, Key, Bought = bool, Price },
--   { Kind = "AutoTuned", Id, Total, Count, Text = "Engine 2, Turbo 1", Tracks = { [trackKey] = stage } }.
-- GarageService.ApplyCustom(car, player) dresses a freshly spawned car (VehicleService calls it): paint,
-- rims, underglow, and the tune. Tuned numbers go onto the car's attributes MaxSpeed, Accel, Brake, Grip,
-- TireFriction and NitroSeconds, always worked out from Config.Vehicles' stock values (so they never pile
-- up) and only for tracks with a stage bought (a stock car keeps exactly what its template has).
-- Tunable cars also get "Exhaust" (the fitted key, "Stock" by default; SoundClient turns it into sound)
-- and "TuneStage" (stages bought, 0-12, for other players' UI). After a tune purchase the player's live
-- car gets the new numbers at once. A car delivered before its owner's save had loaded (VehicleService
-- waits JoinWait seconds at most) is dressed again the moment the save arrives.
-- Speed checks that look at a car (VehicleGuard, RaceService, DriftService, StuntService, AIPoliceService)
-- read its MaxSpeed attribute, so they follow a tune by themselves. MissionService and EventService have
-- no car to look at: their anti-teleport timers (MAX_TRAVEL) must allow the fastest car there can be,
-- fully tuned and on nitro. Config.Garage.MaxGain("MaxSpeed") is the tune's share of that (its header
-- has the sum: 297 studs/s today, where the fastest stock car on nitro does 258).
-- GarageService.TuneOf(player, id) -> the saved tune as a Config.Garage tune table.
-- Goal events (ProgressService.Event): "BuyCar" after a car or boat is bought, "Paint" after a paint job,
-- "Tune" after any tune purchase (amount = stages bought: 1, or more for AUTO TUNE; 1 for an exhaust).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Garage = require(ReplicatedStorage.Shared.Config.Garage)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local GarageService = {}

local notify

local function profile(player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	data.owned = data.owned or {}
	data.custom = data.custom or {}
	for _, id in ipairs(Garage.StarterCars) do
		data.owned[id] = true
	end
	return data
end

-- A saved customisation's tune as a Config.Garage tune table. Saves are read with care (stages clamped
-- to what exists today, unknown exhausts dropped), so an old or odd record can't give a car numbers
-- the config doesn't have.
local function tuneOf(c)
	local tune = Garage.NewTune()
	if type(c) ~= "table" then
		return tune
	end
	if type(c.tune) == "table" then
		for _, track in ipairs(Garage.Tune.Tracks) do
			local stage = c.tune[track.Key]
			if type(stage) == "number" and stage == stage then
				tune.Stages[track.Key] = math.clamp(math.floor(stage), 0, #track.Gain)
			end
		end
	end
	if type(c.exhausts) == "table" then
		for key, bought in pairs(c.exhausts) do
			if bought == true and Garage.ExhaustByKey[key] then
				tune.Owned[key] = true
			end
		end
	end
	if type(c.exhaust) == "string" and tune.Owned[c.exhaust] then
		tune.Exhaust = c.exhaust
	end
	tune.Total = Garage.TuneTotal(tune.Stages)
	return tune
end

local function mirror(player)
	local data = profile(player)
	if not data then
		return
	end
	local list = {}
	for id in pairs(data.owned) do
		table.insert(list, id)
	end
	table.sort(list)
	player:SetAttribute("OwnedCars", table.concat(list, ","))
	for id, c in pairs(data.custom) do
		player:SetAttribute("Custom_" .. id, string.format("%d,%d,%d", c.paint or 0, c.glow or 0, c.rim or 0))
		if c.tune or c.exhaust or c.exhausts then
			player:SetAttribute("Tune_" .. id, Garage.FormatTune(tuneOf(c)))
		end
	end
end

function GarageService.Owns(player, id)
	local def = Vehicles.ById[id]
	if not def then
		return false
	end
	if def.Pass and player:GetAttribute("Pass_" .. def.Pass) then
		return true
	end
	if def.UnlockCopRank and (player:GetAttribute("CopRank") or 0) >= def.UnlockCopRank then
		return true
	end
	local data = profile(player)
	return data ~= nil and data.owned[id] == true
end

function GarageService.CustomOf(player, id)
	local data = profile(player)
	return data and data.custom[id] or nil
end

function GarageService.TuneOf(player, id)
	return tuneOf(GarageService.CustomOf(player, id))
end

-- Write the owner's tune onto a car's attributes. The numbers always start from Config.Vehicles' stock
-- values, so applying twice (a purchase while the car is out) never adds a gain on top of a gain. Only
-- tracks with a stage bought are written: a stock car keeps exactly what its template came with.
local function applyTune(car, player)
	local id = car:GetAttribute("VehicleId")
	if not Garage.CanTune(Vehicles.ById[id]) then
		return -- boats, police cars and street cars are never tuned (and carry no Exhaust / TuneStage)
	end
	local tune = GarageService.TuneOf(player, id)
	local stats = Garage.TunedStats(Vehicles.Resolve(id), tune.Stages)
	for _, track in ipairs(Garage.Tune.Tracks) do
		if tune.Stages[track.Key] > 0 then
			for _, field in ipairs(track.Fields) do
				car:SetAttribute(field, stats[field])
			end
		end
	end
	car:SetAttribute("Exhaust", tune.Exhaust)
	car:SetAttribute("TuneStage", tune.Total)
end

-- Dress a spawned car with its owner's customisation: paint, rims, underglow and tune (called by
-- VehicleService, and by HousingService for the cars parked in a home's garage).
function GarageService.ApplyCustom(car, player)
	local id = car:GetAttribute("VehicleId")
	local def = Vehicles.ById[id]
	local c = GarageService.CustomOf(player, id)
	local paint = c and c.paint and Garage.Paints[c.paint]
	local rim = c and c.rim and Garage.Rims[c.rim]
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Body panels: the chassis, the roof and any part a car body marks with attribute BodyPaint.
			if paint and (d == car.PrimaryPart or d.Name == "Roof" or d:GetAttribute("BodyPaint")) then
				d.Color = paint.Color
			elseif rim and d.Name == "Rim" then
				d.Color = rim.Color
			end
		end
	end
	local under = car:FindFirstChild("Underglow")
	if under and not car:GetAttribute("Boat") then -- boats have no underglow (it would show through the hull)
		local glow = c and c.glow and Garage.Glows[c.glow]
		if glow then
			under.Color = glow.Color
			under.Transparency = 0
		elseif not (def and def.Police) then
			under.Transparency = 1 -- underglow is an upgrade (police cars keep their cyan strip)
		end
	end
	applyTune(car, player)
end

-- Tell ProgressService (the goal chain listens for "BuyCar" / "Paint" / "Tune"). It starts after us, so
-- it's looked up when needed; a failure there must never undo a purchase.
local function goalEvent(player, kind, amount)
	local ok, err = pcall(function()
		require(ServerScriptService.Services.ProgressService).Event(player, kind, amount or 1)
	end)
	if not ok then
		warn("[GarageService] ProgressService." .. kind .. ": " .. tostring(err))
	end
end

-- The car the player has out right now, or nil. (VehicleService and this service call each other, so
-- each looks the other up when needed instead of requiring it at the top.)
local function liveCar(player)
	return require(ServerScriptService.Services.VehicleService).GetCar(player)
end

local function carById(player, id)
	-- The player's current car, if it's this model (so changes show instantly).
	local car = liveCar(player)
	if car and car:GetAttribute("VehicleId") == id then
		return car
	end
	return nil
end

-- Owned and not a boat (a boat's hull shows no paint, rims or underglow, so don't sell them).
local function canStyle(player, id)
	return GarageService.Owns(player, id) and not Vehicles.ById[id].Boat -- Owns already checked the def exists
end

local function onRims(player, id, index)
	if not RateLimit.Allow(player, "Rims", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	local data = profile(player)
	index = math.floor(index)
	if not data or not canStyle(player, id) or not Garage.Rims[index] then
		return
	end
	local entry = Garage.Rims[index]
	if not Garage.Allowed(player, entry) then
		notify:FireClient(player, entry.Pass and ("NeedsPass_" .. entry.Pass) or ("NeedsUnlock_" .. entry.Unlock))
		return
	end
	local cur = data.custom[id]
	if cur and cur.rim == index then
		return -- already this colour: don't charge twice for a double tap
	end
	if not EconomyService.Spend(player, Garage.RimPrice, "rims:" .. id) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	data.custom[id] = data.custom[id] or {}
	data.custom[id].rim = index
	mirror(player)
	local car = carById(player, id)
	if car then
		GarageService.ApplyCustom(car, player)
	end
	Remotes.Event("GarageResult"):FireClient(player, { Kind = "Rims", Id = id })
end

local function onBuy(player, id)
	if not RateLimit.Allow(player, "BuyCar", 1, 2) or type(id) ~= "string" then
		return
	end
	local def = Vehicles.ById[id]
	local data = profile(player)
	if not def or not data or GarageService.Owns(player, id) then
		return
	end
	if def.Pass then
		notify:FireClient(player, "CarNeedsPass")
		return
	end
	if def.UnlockCopRank then
		notify:FireClient(player, "CarNeedsRank")
		return
	end
	if def.UnlockHeists and (player:GetAttribute("BigHeists") or 0) < def.UnlockHeists then
		notify:FireClient(player, "CarNeedsHeists")
		return
	end
	-- Cars and boats are bought in person: at AutoNeon Motors / Marina Boat Sales, next to the display.
	local okDealer, near = pcall(function()
		return require(ServerScriptService.Services.DealershipService).IsNear(player, id)
	end)
	if okDealer and not near then
		notify:FireClient(player, "BuyAtDealer")
		return
	end
	if not EconomyService.Spend(player, def.Price or 0, "buycar:" .. id) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	data.owned[id] = true
	mirror(player)
	Remotes.Event("GarageResult"):FireClient(player, { Kind = "Bought", Id = id })
	goalEvent(player, "BuyCar")
end

local function onPaint(player, id, index)
	if not RateLimit.Allow(player, "Paint", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	local data = profile(player)
	index = math.floor(index)
	if not data or not canStyle(player, id) or not Garage.Paints[index] then
		return
	end
	local entry = Garage.Paints[index]
	if not Garage.Allowed(player, entry) then
		notify:FireClient(player, entry.Pass and ("NeedsPass_" .. entry.Pass) or ("NeedsUnlock_" .. entry.Unlock))
		return
	end
	local cur = data.custom[id]
	if cur and cur.paint == index then
		return -- already this colour: don't charge twice for a double tap
	end
	if not EconomyService.Spend(player, Garage.PaintPrice, "paint:" .. id) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	data.custom[id] = data.custom[id] or {}
	data.custom[id].paint = index
	mirror(player)
	local car = carById(player, id)
	if car then
		GarageService.ApplyCustom(car, player)
	end
	Remotes.Event("GarageResult"):FireClient(player, { Kind = "Painted", Id = id })
	goalEvent(player, "Paint")
end

local function onGlow(player, id, index)
	if not RateLimit.Allow(player, "Glow", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	local data = profile(player)
	index = math.floor(index)
	if not data or not canStyle(player, id) or not Garage.Glows[index] then
		return
	end
	local entry = Garage.Glows[index]
	if not Garage.Allowed(player, entry) then
		notify:FireClient(player, entry.Pass and ("NeedsPass_" .. entry.Pass) or ("NeedsUnlock_" .. entry.Unlock))
		return
	end
	data.custom[id] = data.custom[id] or {}
	local c = data.custom[id]
	if not c.glowUnlocked then
		if not EconomyService.Spend(player, Garage.UnderglowPrice, "underglow:" .. id) then
			notify:FireClient(player, "NotEnoughCash")
			return
		end
		c.glowUnlocked = true
	end
	c.glow = index
	mirror(player)
	local car = carById(player, id)
	if car then
		GarageService.ApplyCustom(car, player)
	end
	Remotes.Event("GarageResult"):FireClient(player, { Kind = "Glow", Id = id })
end

------------------------------------------------------------------ tuning

-- May this player tune car `id` right now? Land cars they own only, and not with the cops watching (the
-- same rule as calling a car, VehicleService).
local function canTune(player, id)
	if not GarageService.Owns(player, id) or not Garage.CanTune(Vehicles.ById[id]) then
		return false
	end
	if player:GetAttribute("Side") == "Prisoner" then
		return false -- no phone in prison
	end
	if (player:GetAttribute("Heat") or 0) > 0 and player:GetAttribute("HeatSpotted") then
		notify:FireClient(player, "TuneWanted")
		return false
	end
	return true
end

-- Save a changed tune, show it on the phone and put it on the player's car if it's out.
local function storeTune(player, data, id, tune)
	data.custom[id] = data.custom[id] or {}
	local c = data.custom[id]
	c.tune = tune.Stages
	c.exhaust = tune.Exhaust ~= "Stock" and tune.Exhaust or nil
	local bought = {}
	for key in pairs(tune.Owned) do
		if key ~= "Stock" then
			bought[key] = true
		end
	end
	c.exhausts = next(bought) and bought or nil
	mirror(player)
	local car = carById(player, id)
	if car then
		applyTune(car, player)
	end
end

-- want (optional): the stage the phone's button offered.
local function onTune(player, id, key, want)
	if not RateLimit.Allow(player, "Tune", 2, 3) or type(id) ~= "string" or type(key) ~= "string" then
		return
	end
	local data = profile(player)
	if not data or not Garage.TrackByKey[key] or not canTune(player, id) then
		return
	end
	local tune = tuneOf(data.custom[id])
	local stage = tune.Stages[key] + 1
	if want ~= nil and want ~= stage then
		-- The phone offered another stage than the next one: its first request was slow, the player
		-- confirmed again, and that stage is fitted by now. Never sell the dearer one after it unseen.
		return
	end
	local price = Garage.StagePrice(Vehicles.ById[id], key, stage)
	if not price then
		return -- already on its last stage (the phone shows MAX there)
	end
	if not EconomyService.Spend(player, price, "tune:" .. id .. ":" .. key .. stage) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	tune.Stages[key] = stage
	storeTune(player, data, id, tune)
	Remotes.Event("GarageResult"):FireClient(player, { Kind = "Tuned", Id = id, Track = key, Stage = stage, Price = price })
	goalEvent(player, "Tune")
end

local function onExhaust(player, id, key)
	if not RateLimit.Allow(player, "Exhaust", 2, 3) or type(id) ~= "string" or type(key) ~= "string" then
		return
	end
	local data = profile(player)
	local entry = Garage.ExhaustByKey[key]
	if not data or not entry or not canTune(player, id) then
		return
	end
	local tune = tuneOf(data.custom[id])
	if tune.Exhaust == key then
		return -- already fitted: nothing to do for a double tap
	end
	-- Bought once per car; after that, swapping between the ones you own is free.
	local buying = not tune.Owned[key]
	if buying and not EconomyService.Spend(player, entry.Price, "exhaust:" .. id .. ":" .. key) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	tune.Owned[key] = true
	tune.Exhaust = key
	storeTune(player, data, id, tune)
	Remotes.Event("GarageResult"):FireClient(player, {
		Kind = "Exhaust", Id = id, Key = key, Bought = buying, Price = buying and entry.Price or 0,
	})
	if buying then
		goalEvent(player, "Tune")
	end
end

-- budget (optional): the total the phone's confirm line showed. have (optional): the stages the car
-- had when the phone worked out that plan.
local function onAutoTune(player, id, budget, have)
	if not RateLimit.Allow(player, "AutoTune", 1, 2) or type(id) ~= "string" then
		return
	end
	local data = profile(player)
	if not data or not canTune(player, id) then
		return
	end
	local tune = tuneOf(data.custom[id])
	if have ~= nil and have ~= tune.Total then
		-- The phone's plan was for a tune the car has moved on from (a slow first request, then a second
		-- confirm): that plan is bought already, and a new one would be stages nobody was shown.
		return
	end
	-- The plan is worked out here, from the server's own cash and stages. The phone's budget (the total
	-- its confirm line showed) can only make it smaller: cash earned since never buys more than was agreed.
	local cash = EconomyService.GetCash(player)
	if type(budget) == "number" and budget == budget then
		cash = math.min(cash, math.max(0, math.floor(budget)))
	end
	local plan, total = Garage.AutoTunePlan(Vehicles.ById[id], tune.Stages, cash)
	if #plan == 0 then
		if tune.Total < Garage.MaxTuneTotal then
			notify:FireClient(player, "NotEnoughCash") -- (a fully tuned car has nothing left to buy: say nothing)
		end
		return
	end
	if not EconomyService.Spend(player, total, "autotune:" .. id) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	local reached = {}
	for _, step in ipairs(plan) do
		tune.Stages[step.Track] = step.Stage
		reached[step.Track] = step.Stage
	end
	storeTune(player, data, id, tune)
	Remotes.Event("GarageResult"):FireClient(player, {
		Kind = "AutoTuned", Id = id, Total = total, Count = #plan, Text = Garage.PlanText(plan), Tracks = reached,
	})
	goalEvent(player, "Tune", #plan)
end

function GarageService.Init()
	notify = Remotes.Event("Notify")
	Remotes.Event("RequestBuyCar").OnServerEvent:Connect(onBuy)
	Remotes.Event("RequestPaint").OnServerEvent:Connect(onPaint)
	Remotes.Event("RequestUnderglow").OnServerEvent:Connect(onGlow)
	Remotes.Event("RequestRims").OnServerEvent:Connect(onRims)
	Remotes.Event("RequestTune").OnServerEvent:Connect(onTune)
	Remotes.Event("RequestExhaust").OnServerEvent:Connect(onExhaust)
	Remotes.Event("RequestAutoTune").OnServerEvent:Connect(onAutoTune)
	Remotes.Event("GarageResult")
	DataService.OnLoaded(function(player)
		mirror(player)
		-- A car delivered before the save arrived (a slow load: VehicleService only waits JoinWait seconds)
		-- was dressed from nothing, so it's stock and unpainted while the phone shows the real tune. Dress
		-- it now. (A stock car had no tuned numbers written, so nothing has to be taken back first.)
		local car = liveCar(player)
		if car and car.Parent then
			GarageService.ApplyCustom(car, player)
		end
	end)
end

return GarageService
