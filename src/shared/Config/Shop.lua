-- Shop (ModuleScript, ReplicatedStorage.Shared.Config.Shop)
-- Game passes and developer products from the PRD (Monetization). IDs come from the Creator Hub
-- (Monetization > Passes / Developer Products) once the game is published; 0 = not created yet, and
-- the phone shows "Coming soon". Prices are NEVER written here: the game reads them live with
-- MarketplaceService:GetProductInfo, so Managed Pricing and price changes just work.
-- Owning a pass sets the player attribute "Pass_<Key>" (ShopService).

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
		Perk = "The Vortex: 200 top speed, the fastest car on the coast" },
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
