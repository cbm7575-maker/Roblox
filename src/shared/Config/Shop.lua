-- Shop (ModuleScript, ReplicatedStorage.Shared.Config.Shop)
-- Game passes and developer products from the PRD (Monetization). IDs come from the Creator Hub
-- (Monetization > Passes / Developer Products) once the game is published; 0 = not created yet, and
-- the phone shows "Coming soon". Prices are NEVER written here: the game reads them live with
-- MarketplaceService:GetProductInfo, so Managed Pricing and price changes just work.
-- Owning a pass sets the player attribute "Pass_<Key>" (ShopService).
-- Offers: at the moments the game already knows a player wants a pass (Shop.Offers), OfferClient shows
-- a small one-tap card that opens the normal Roblox purchase prompt. No pass makes a car faster or
-- tougher than ones you can earn: the Vortex is a convenience, not the top car.

local Shop = {}

Shop.Passes = {
	{ Key = "VIP", Id = 0, Name = "VIP", Icon = "👑",
		Perk = "+25% heist and bounty cash, VIP neon paints, a gold [VIP] chat tag" },
	{ Key = "BigDuffel", Id = 0, Name = "Big Duffel Bag", Icon = "💰",
		Perk = "Carry 50% more cash before you have to bank" },
	{ Key = "SWATUnit", Id = 0, Name = "SWAT Unit", Icon = "🚓",
		Perk = "The Riot Truck for the police team: shoves cars, blocks roads" },
	{ Key = "NeonGarage", Id = 0, Name = "Neon Garage", Icon = "✨",
		Perk = "Extra underglow colors for every car" },
	{ Key = "Hypercar", Id = 0, Name = "Hypercar", Icon = "🏎️",
		-- Honest text: the Riptide R and Storm Petrel are faster, and its stats must never be raised
		-- above them (that would be pay-to-win).
		Perk = "The Vortex hypercar (125 mph), yours right away with no saving up" },
}

-- Cash packs (developer products). Cash is the in-game amount granted.
Shop.Products = {
	{ Key = "Cash1", Id = 0, Cash = 5000 },
	{ Key = "Cash2", Id = 0, Cash = 18000 },
	{ Key = "Cash3", Id = 0, Cash = 55000 },
	{ Key = "Cash4", Id = 0, Cash = 120000 },
	{ Key = "Cash5", Id = 0, Cash = 250000 },
}

-- Perk numbers (read by the services that pay out).
Shop.VIPCashBonus = 0.25
Shop.DuffelCarryBonus = 0.5

-- Right-moment offers (OfferClient). The key is what just happened: "BagFull" (a heist or hot car
-- didn't fit in the bag; HeistClient passes it on) or the Notify key the server sent when it refused
-- something that needs a pass (GarageService). Pass = the Shop.Passes key offered; Title / Line = the
-- card's words (BagFull's title gets the amount left behind added).
-- Rules (OfferClient): one card per OfferGap seconds at most, never while wanted, never above
-- OfferMaxMph, never before the tutorial is done, never for a pass the player owns, and each can be
-- hidden for good ("Don't show again" saves the setting HideOffer_<key>, SettingsService).
-- A pass whose Id is still 0 is never offered in a live game (Studio still shows the card, for testing).
Shop.Offers = {
	BagFull = { Pass = "BigDuffel", Title = "BAG FULL", Line = "The Big Duffel Bag carries 50% more cash." },
	NeedsPass_VIP = { Pass = "VIP", Title = "VIP PAINTS", Line = "3 VIP neon paints, +25% heist cash and a gold [VIP] tag." },
	NeedsPass_NeonGarage = { Pass = "NeonGarage", Title = "NEON GARAGE", Line = "6 extra underglow colors for every car you own." },
	CarNeedsPass = { Pass = "Hypercar", Title = "THE VORTEX", Line = "A 125 mph hypercar, yours right away: no saving up." },
}
Shop.OfferGap = 600 -- seconds: at most one offer card every 10 minutes
Shop.OfferMaxMph = 40 -- no offer card while moving faster than this

function Shop.PassByKey(key)
	for _, p in ipairs(Shop.Passes) do
		if p.Key == key then
			return p
		end
	end
	return nil
end

function Shop.PassById(id)
	for _, p in ipairs(Shop.Passes) do
		if p.Id == id and id ~= 0 then
			return p
		end
	end
	return nil
end

function Shop.ProductById(id)
	for _, p in ipairs(Shop.Products) do
		if p.Id == id and id ~= 0 then
			return p
		end
	end
	return nil
end

return Shop
