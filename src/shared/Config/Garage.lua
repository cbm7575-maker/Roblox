-- Garage (ModuleScript, ReplicatedStorage.Shared.Config.Garage)
-- Car ownership and customising prices (Game Design Spec). Cars are bought from the phone's
-- "AutoNeon" app and delivered to your garage; the phone's Garage app spawns and customises them.
-- Paint and rims are owned per car: a colour costs PaintPrice (a rim style RimPrice) once for that
-- car, then switching back to it is free. A car's stock paint (index 0) and stock rims (StockRim)
-- are always owned; pass and unlock entries cost nothing once allowed. Underglow is installed once
-- per car (UnderglowPrice), then every allowed glow colour is free. GarageService charges by
-- Garage.StyleCost on the server; the phone shows the same numbers.
-- Saved customisations store indices into Paints / Glows / Rims: these lists are append-only.

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
Garage.StockRim = 1 -- Chrome: the rims every car is built with (CarBuilder), always owned

-- Short "what unlocks this" words for a locked swatch on the phone (pass key or unlock key).
Garage.NeedText = {
	VIP = "VIP", NeonGarage = "NEON",
	Streak7 = "7 DAYS", CivRank10 = "RANK 10", CopRank10 = "COP 10", GusHunter = "ALL GUS", Rank20 = "RANK 20",
}

function Garage.Needs(entry)
	local key = entry.Pass or entry.Unlock
	return key and (Garage.NeedText[key] or "LOCKED") or nil
end

-- What picking entry `index` of Garage[kind] ("Paints" or "Rims") costs on a car whose owned set is
-- `owned` ({ ["3"] = true }; string keys so DataStores save it as a dictionary). 0 = free, nil = no
-- such entry. Pass / unlock gating is separate (Garage.Allowed).
function Garage.StyleCost(kind, index, owned)
	if kind ~= "Paints" and kind ~= "Rims" then
		return nil
	end
	if (kind == "Paints" and index == 0) or (kind == "Rims" and index == Garage.StockRim) then
		return 0
	end
	local entry = Garage[kind][index]
	if not entry then
		return nil
	end
	if entry.Pass or entry.Unlock or (owned and owned[tostring(index)]) then
		return 0
	end
	return kind == "Paints" and Garage.PaintPrice or Garage.RimPrice
end

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
	-- Earned: find all hidden Gus figurines (CollectibleService). Saved customisations store paint
	-- indices, so new paints always go at the end of this list.
	{ Name = "Gator Green", Color = Color3.fromRGB(46, 180, 90), Unlock = "GusHunter" },
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

return Garage
