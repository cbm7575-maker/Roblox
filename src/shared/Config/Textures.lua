-- Textures (ModuleScript, ReplicatedStorage.Shared.Config.Textures)
-- Image ids for the city's facade and street textures (Look 2.0). They were drawn by tools/textures.py
-- (transparent around each window, so a wall's own colour and material show through) and uploaded to
-- the owner's account. The Restyle tool puts them on buildings; at night SkyClient lays the matching
-- "night" overlay on every facade (a 4 x 3 bay tile where about 40% of the windows glow).

local Textures = {}

Textures.Apartment = "rbxassetid://135444621008283" -- one bay: 8 studs wide x 10 tall, white-framed window
Textures.ApartmentLit = "rbxassetid://91061040099069" -- same window, warm light inside
Textures.Office = "rbxassetid://134803344602269" -- one bay: 8 x 10, tinted curtain-wall glass
Textures.OfficeLit = "rbxassetid://113038974219944" -- same glass, cool office light inside
Textures.Storefront = "rbxassetid://79765500148799" -- ground floor shop glass: 16 wide x 12 tall
Textures.Slabs = "rbxassetid://132704532619444" -- sidewalk slab joints (tile about 6 studs)
Textures.Grime = "rbxassetid://130615035919126" -- soft rain streaks for walls (tile 16 x 32)
Textures.Zebra = "rbxassetid://136294324687893" -- one crosswalk stripe + gap (tile 2.4 studs across the road)
Textures.Corrugated = "rbxassetid://79276947924605" -- corrugated metal ribs, translucent (tile 2 studs)
Textures.RollUpDoor = "rbxassetid://125204637250058" -- warehouse roll-up door (one per door part)

-- Night overlays: 4 bays x 3 floors per tile (32 x 30 studs); unlit windows are transparent.
Textures.ApartmentNight = "rbxassetid://112032542234818"
Textures.OfficeNight = "rbxassetid://80869226301815"
Textures.NightFor = {
	[Textures.Apartment] = Textures.ApartmentNight,
	[Textures.Office] = Textures.OfficeNight,
}

Textures.BayWidth = 8 -- studs per window bay (StudsPerTileU of the day facade)
Textures.FloorHeight = 10 -- studs per floor (StudsPerTileV)

-- Look 4.0 city dressing (CityDressingService runs ServerStorage.Tools.Look4 with these). The images are made
-- by tools/make_look4_art.py into art/look4/ (README there: every brand and slogan is our own invention) and
-- uploaded through Studio on 2026-10-15.
Textures.Billboards = { -- 1024 x 512 ads
	"rbxassetid://89012974012705", -- Sunset Soda
	"rbxassetid://96200152129852", -- Flamingo Burger
	"rbxassetid://90274380528743", -- Coast FM 104.2
	"rbxassetid://130195929543883", -- Sal Breeze, attorney at law
	"rbxassetid://115746718192027", -- Solana Smiles dental
	"rbxassetid://122521704723947", -- Palm Hills Realty
	"rbxassetid://93983085865700", -- Gator Glades swamp tours
	"rbxassetid://96921738312577", -- AutoNeon Motors
	"rbxassetid://81792397903270", -- Zap Shack
	"rbxassetid://121798932102331", -- Club Nova (all-ages roller disco)
	"rbxassetid://105983062218638", -- Coastal Bank
	"rbxassetid://105774240596759", -- Marina Row Yacht Club
}
Textures.RoadWear = { -- 512 x 512 RGBA decals seen from above
	Crack = { "rbxassetid://123887588326249", "rbxassetid://77711420151029", "rbxassetid://128625114148235" },
	Oil = { "rbxassetid://82198186119026", "rbxassetid://112285092407365", "rbxassetid://99796908823059" },
	Patch = { "rbxassetid://120663224632137" },
	Manhole = { "rbxassetid://114838464578974" },
	Drain = { "rbxassetid://81039235915423" },
	Skid = { "rbxassetid://128771868520857" },
}

return Textures
