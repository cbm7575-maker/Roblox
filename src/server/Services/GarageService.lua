-- GarageService (ModuleScript, ServerScriptService.Services.GarageService)
-- Owning and customising cars. Saved in the player's profile (DataService):
--   data.owned[carId] = true
--   data.custom[carId] = { paint = Garage.Paints index, glow = Garage.Glows index, rim = Garage.Rims index,
--                          glowUnlocked = true once underglow is installed,
--                          paints = { ["3"] = true, ... }, rims = { ["2"] = true, ... } }  -- bought for this car
--   (owned sets use string keys so DataStores save them as dictionaries, not sparse arrays)
-- Remotes (all validated here):
--   RequestBuyCar(id)                   -> costs Config.Vehicles price; pass cars need their game pass
--   RequestPaint(id, paintIndex)        -> Garage.PaintPrice ($500) the first time a colour goes on this
--                                          car, then free to switch back to; 0 = the car's stock colour
--                                          (always owned); pass / unlock paints are free once allowed
--   RequestRims(id, rimIndex)           -> Garage.RimPrice ($1,500) once per rim style per car, same rules;
--                                          Garage.StockRim (Chrome) is always owned; not on boats (no wheels)
--   RequestUnderglow(id, glowIndex)     -> Garage.UnderglowPrice ($3,000) the first time on a car, then
--                                          colour changes are free; never on boats (it can't show)
-- Picking the paint, rims or glow a car already has does nothing (and costs nothing). Every price is
-- Garage.StyleCost, the same function the phone uses to label the swatches.
-- Saves from before owned sets: the paint / rims a car wears when its save loads count as owned.
-- Pass cars count as owned while the player has attribute "Pass_<PassName>" (set by ShopService);
-- cop-rank cars while "CopRank" >= UnlockCopRank.
-- Mirrored for the phone UI: "OwnedCars" (comma list of bought + starter cars), "Custom_<id>"
-- ("paint,glow,rim", 0 = stock / none) and "Style_<id>" ("paints;rims", the owned indices, e.g. "3,5;2").
-- GarageResult(player) <- { Kind = "Bought" | "Painted" | "Rims" | "Glow", Id, Name = entry name,
--   Bought = true when this pick cost money (a new colour / rim style / the underglow install) }.
-- GarageService.ApplyCustom(car, player) paints a freshly spawned car (VehicleService calls it).

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

-- The owned set c[field] ("paints" / "rims"), created on first use. `current` (what the car wears
-- now) always counts as owned: that is the migration for saves from before owned sets existed.
local function ownedSet(c, field, current)
	local set = c[field]
	if type(set) ~= "table" then
		set = {}
		c[field] = set
	end
	if type(current) == "number" and current > 0 then
		set[tostring(current)] = true
	end
	return set
end

local function setText(set)
	local list = {}
	for k in pairs(set) do
		local n = tonumber(k)
		if n then
			table.insert(list, n)
		end
	end
	table.sort(list)
	return table.concat(list, ",")
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
		if type(c) == "table" then
			local paints, rims = ownedSet(c, "paints", c.paint), ownedSet(c, "rims", c.rim)
			player:SetAttribute("Custom_" .. id, string.format("%d,%d,%d", c.paint or 0, c.glow or 0, c.rim or 0))
			player:SetAttribute("Style_" .. id, setText(paints) .. ";" .. setText(rims))
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

-- Paint a spawned car with its owner's customisation (called by VehicleService). `restore` = "Paints"
-- or "Rims" when that was just changed on a car that's already out: going back to stock then puts
-- the stock colour back (a fresh car already has it; other changes keep a Spray & Go respray).
function GarageService.ApplyCustom(car, player, restore)
	local id = car:GetAttribute("VehicleId")
	local def = Vehicles.ById[id]
	local c = GarageService.CustomOf(player, id)
	local paint = c and c.paint and Garage.Paints[c.paint]
	local rim = c and c.rim and Garage.Rims[c.rim]
	local paintColor = paint and paint.Color or (restore == "Paints" and def and def.Color) or nil
	local rimColor = rim and rim.Color or (restore == "Rims" and Garage.Rims[Garage.StockRim].Color) or nil
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Body panels: the chassis, the roof and any part a car body marks with attribute BodyPaint.
			if paintColor and (d == car.PrimaryPart or d.Name == "Roof" or d:GetAttribute("BodyPaint")) then
				d.Color = paintColor
			elseif rimColor and d.Name == "Rim" then
				d.Color = rimColor
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

-- After a change: update the phone's mirror, repaint the car if it's out, tell the client.
-- restore = the style kind that changed ("Paints" / "Rims"), see ApplyCustom.
local function changed(player, id, kind, name, bought, restore)
	mirror(player)
	local car = carById(player, id)
	if car then
		GarageService.ApplyCustom(car, player, restore)
	end
	Remotes.Event("GarageResult"):FireClient(player, { Kind = kind, Id = id, Name = name, Bought = bought })
end

local function needs(player, entry)
	notify:FireClient(player, entry.Pass and ("NeedsPass_" .. entry.Pass) or ("NeedsUnlock_" .. entry.Unlock))
end

-- Paint and rims share the rules: kind = "Paints" or "Rims".
local STYLE = {
	Paints = { field = "paint", owned = "paints", reason = "paint:", result = "Painted", stock = 0 },
	Rims = { field = "rim", owned = "rims", reason = "rims:", result = "Rims", stock = Garage.StockRim },
}

local function onStyle(kind, player, id, index)
	local style = STYLE[kind]
	local data = profile(player)
	index = math.floor(index)
	if not data or not GarageService.Owns(player, id) then
		return
	end
	if kind == "Rims" and Vehicles.ById[id].Boat then
		return -- boats have no wheels (the phone doesn't offer rims for them)
	end
	local entry = Garage[kind][index]
	if not entry and index == 0 and kind == "Paints" then
		entry = { Name = "Stock" } -- the car's own colour (Config.Vehicles Color)
	end
	if not entry then
		return
	end
	if not Garage.Allowed(player, entry) then
		needs(player, entry)
		return
	end
	local c = data.custom[id] or {}
	local wearing = c[style.field] or style.stock
	if wearing == index then
		return -- already on the car: no charge
	end
	local owned = ownedSet(c, style.owned, c[style.field])
	local cost = Garage.StyleCost(kind, index, owned)
	if not cost then
		return
	end
	if cost > 0 then
		if not EconomyService.Spend(player, cost, style.reason .. id) then
			notify:FireClient(player, "NotEnoughCash")
			return
		end
		owned[tostring(index)] = true -- this car keeps it for good
	end
	c[style.field] = index ~= style.stock and index or nil
	data.custom[id] = c
	changed(player, id, style.result, entry.Name, cost > 0, kind)
end

local function onPaint(player, id, index)
	if not RateLimit.Allow(player, "Paint", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	onStyle("Paints", player, id, index)
end

local function onRims(player, id, index)
	if not RateLimit.Allow(player, "Rims", 2, 3) or type(id) ~= "string" or type(index) ~= "number" then
		return
	end
	onStyle("Rims", player, id, index)
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
		needs(player, entry)
		return
	end
	local c = data.custom[id] or {}
	if c.glowUnlocked and c.glow == index then
		return -- already this colour
	end
	local installing = not c.glowUnlocked
	if installing then
		if not EconomyService.Spend(player, Garage.UnderglowPrice, "underglow:" .. id) then
			notify:FireClient(player, "NotEnoughCash")
			return
		end
		c.glowUnlocked = true
	end
	c.glow = index
	data.custom[id] = c
	changed(player, id, "Glow", entry.Name, installing)
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
		-- The first car often spawns just before the save loads: give it its owned paint and rims now.
		local car = require(ServerScriptService.Services.VehicleService).GetCar(player)
		if car and car.Parent then
			GarageService.ApplyCustom(car, player)
		end
	end)
end

return GarageService
