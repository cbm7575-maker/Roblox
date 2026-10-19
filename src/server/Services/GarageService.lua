-- GarageService (ModuleScript, ServerScriptService.Services.GarageService)
-- Owning and customising cars. Saved in the player's profile (DataService):
--   data.owned[carId] = true
--   data.custom[carId] = { paint = Garage.Paints index, glow = Garage.Glows index, rim = Garage.Rims index }
-- Remotes (all validated here):
--   RequestBuyCar(id)                   -> costs Config.Vehicles price; pass cars need their game pass
--   RequestPaint(id, paintIndex)        -> Garage.PaintPrice ($500)
--   RequestUnderglow(id, glowIndex)     -> Garage.UnderglowPrice ($3,000) the first time on a car, then
--                                          colour changes are free; never on boats (it can't show)
--   RequestRims(id, rimIndex)           -> Garage.RimPrice ($1,500)
-- Picking the paint, rims or glow a car already has does nothing (and costs nothing).
-- Pass cars count as owned while the player has attribute "Pass_<PassName>" (set by the shop, step 4.5);
-- cop-rank cars while "CopRank" >= UnlockCopRank.
-- The owned list is mirrored to the player attribute "OwnedCars" (comma list) for the phone UI, and
-- customisations to "Custom_<id>" attributes ("paint,glow,rim", 0 = default).
-- GarageService.ApplyCustom(car, player) paints a freshly spawned car (VehicleService calls it).

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

-- Paint a spawned car with its owner's customisation (called by VehicleService).
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
end

local function carById(player, id)
	-- The player's current car, if it's this model (so changes show instantly).
	local VehicleService = require(ServerScriptService.Services.VehicleService)
	local car = VehicleService.GetCar(player)
	if car and car:GetAttribute("VehicleId") == id then
		return car
	end
	return nil
end

local function onRims(player, id, index)
	if not RateLimit.Allow(player, "Rims", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	local data = profile(player)
	index = math.floor(index)
	if not data or not GarageService.Owns(player, id) or not Garage.Rims[index] then
		return
	end
	local entry = Garage.Rims[index]
	if not Garage.Allowed(player, entry) then
		notify:FireClient(player, entry.Pass and ("NeedsPass_" .. entry.Pass) or ("NeedsUnlock_" .. entry.Unlock))
		return
	end
	if data.custom[id] and data.custom[id].rim == index then
		return -- already on the car: no charge
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
	if not EconomyService.Spend(player, def.Price or 0, "buycar:" .. id) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	data.owned[id] = true
	mirror(player)
	Remotes.Event("GarageResult"):FireClient(player, { Kind = "Bought", Id = id })
end

local function onPaint(player, id, index)
	if not RateLimit.Allow(player, "Paint", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	local data = profile(player)
	index = math.floor(index)
	if not data or not GarageService.Owns(player, id) or not Garage.Paints[index] then
		return
	end
	local entry = Garage.Paints[index]
	if not Garage.Allowed(player, entry) then
		notify:FireClient(player, entry.Pass and ("NeedsPass_" .. entry.Pass) or ("NeedsUnlock_" .. entry.Unlock))
		return
	end
	if data.custom[id] and data.custom[id].paint == index then
		return -- already this colour: no charge
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
end

local function onGlow(player, id, index)
	if not RateLimit.Allow(player, "Glow", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	local data = profile(player)
	index = math.floor(index)
	if not data or not GarageService.Owns(player, id) or not Garage.Glows[index] then
		return
	end
	if Vehicles.ById[id].Boat then
		notify:FireClient(player, "NoGlowOnBoats") -- the hull hides it (ApplyCustom skips boats)
		return
	end
	local entry = Garage.Glows[index]
	if not Garage.Allowed(player, entry) then
		notify:FireClient(player, entry.Pass and ("NeedsPass_" .. entry.Pass) or ("NeedsUnlock_" .. entry.Unlock))
		return
	end
	data.custom[id] = data.custom[id] or {}
	local c = data.custom[id]
	if c.glowUnlocked and c.glow == index then
		return -- already this colour
	end
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

function GarageService.Init()
	notify = Remotes.Event("Notify")
	Remotes.Event("RequestBuyCar").OnServerEvent:Connect(onBuy)
	Remotes.Event("RequestPaint").OnServerEvent:Connect(onPaint)
	Remotes.Event("RequestUnderglow").OnServerEvent:Connect(onGlow)
	Remotes.Event("RequestRims").OnServerEvent:Connect(onRims)
	Remotes.Event("GarageResult")
	DataService.OnLoaded(function(player)
		mirror(player)
	end)
end

return GarageService
