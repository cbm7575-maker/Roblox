-- Shop (ModuleScript, ReplicatedStorage.Shared.Config.Shop)
-- Game passes and developer products from the PRD (Monetization). IDs come from the Creator Hub
-- (Monetization > Passes / Developer Products) once the game is published; 0 = not created yet.
-- Price (Robux) is for display only, the starting price in launch/2-CREATOR-HUB-SHOP.md: once an
-- Id is real the phone shows the live price (MarketplaceService:GetProductInfo), so Managed Pricing
-- and price changes just work. Roblox always charges its own price, never this number.
-- Owning a pass sets the player attribute "Pass_<Key>" (ShopService).
-- Who pays (ShopService): in Studio everything is free and instant; the game's owner gets every pass
-- free in live servers and can claim cash packs free; everyone else buys through Roblox, and an Id
-- of 0 shows "Coming soon".

local Shop = {}

Shop.Passes = {
	{ Key = "VIP", Id = 0, Price = 499, Name = "VIP", Icon = "👑",
		Perk = "+25% heist and bounty cash, VIP neon paints, a gold [VIP] chat tag" },
	{ Key = "BigDuffel", Id = 0, Price = 299, Name = "Big Duffel Bag", Icon = "💰",
		Perk = "Carry 50% more cash before you have to bank" },
	{ Key = "SWATUnit", Id = 0, Price = 399, Name = "SWAT Unit", Icon = "🚓",
		Perk = "The Riot Truck for the police team: shoves cars, blocks roads" },
	{ Key = "NeonGarage", Id = 0, Price = 249, Name = "Neon Garage", Icon = "✨",
		Perk = "Extra underglow colors for every car" },
	{ Key = "Hypercar", Id = 0, Price = 599, Name = "Hypercar", Icon = "🏎️",
		Perk = "The Vortex: 200 top speed, the fastest car on the coast" },
}

-- Cash packs (developer products). Cash is the in-game amount granted; Price is Robux (display).
Shop.Products = {
	{ Key = "Cash1", Id = 0, Price = 49, Cash = 5000 },
	{ Key = "Cash2", Id = 0, Price = 149, Cash = 18000 },
	{ Key = "Cash3", Id = 0, Price = 399, Cash = 55000 },
	{ Key = "Cash4", Id = 0, Price = 799, Cash = 120000 },
	{ Key = "Cash5", Id = 0, Price = 1499, Cash = 250000 },
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

function Shop.PassByKey(key)
	for _, p in ipairs(Shop.Passes) do
		if p.Key == key then
			return p
		end
	end
	return nil
end

function Shop.ProductByKey(key)
	for _, p in ipairs(Shop.Products) do
		if p.Key == key then
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
