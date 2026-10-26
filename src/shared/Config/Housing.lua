-- Housing (ModuleScript, ReplicatedStorage.Shared.Config.Housing)
-- Homes you can buy at their front door (HousingService on the server, HouseClient on the client).
-- One home at a time: buying another sells the old one back for half its price. Your home is where
-- you spawn in free roam, your starter car waits on its driveway, and inside (a private copy for each
-- owner, so many players can own the same property) the garage shows the cars you own.
--
-- Position = the lot centre on the ground (y = 0). Facing = the direction from the house to the
-- street it faces. Every lot uses the same layout, in "lot space": origin at the lot centre, -Z
-- toward the street, +X to the right as you look at the street from the house. The lot is 110 wide
-- (x -55..55) and 70 deep (z -35..35): the house on the left, the garage and driveway on the right.
--
-- Style = how the outside looks (HousingService builds each one from plain parts on that same layout):
--   "Classic" (the default) a pastel block with balconies upstairs; 3+ storeys get a neon crown.
--   "Loft"    a brick dock warehouse: factory windows, a sawtooth roof, a water tank, a neon sign.
--   "Ranch"   a single storey in wooden siding with a wide front porch and a pitched roof.
--   "Mansion" white stacked volumes with glass walls, a roof terrace and a neon flamingo (3 storeys).
-- Roof = the roof colour (white when left out). GarageSlots can be up to 8 (the garage inside widens).
-- The list is kept cheapest first: the phone's HOME page and the map list homes in this order.
--
-- Picking a new lot: a 120 x 80 box around the centre must be empty, including the CanQuery = false
-- gameplay pads (car pads, heist and service pads) a Studio bounds query can't see, and clear of the
-- art modules' keep-out lists (the hideout block, the Palm Hills car pads' pull-out...). Keep the
-- centre 72+ studs from the street's centre line, so the verge parking spot stays off the road.

local Housing = {}

Housing.RefundShare = 0.5 -- buying a new home sells the old one back for this share of its price
Housing.DoorRange = 18 -- studs: how close to the front door you must be to buy or go in

Housing.List = {
	{
		Id = "RustwaterLoft",
		Name = "Rustwater Loft",
		Price = 25000,
		Position = Vector3.new(165, 0, 1574),
		Facing = Vector3.new(0, 0, 1), -- south, to the docks street at z = 1650 (by the ATM kiosk off Solana Ave)
		GarageSlots = 2,
		Blurb = "Your first place in Port Solana: a brick dock loft under a neon sign.",
		Style = "Loft",
		Stories = 2,
		Wall = Color3.fromRGB(156, 66, 52), -- brick red
		Accent = Color3.fromRGB(184, 98, 50), -- rust: the beam between the floors, the door canopy
		Roof = Color3.fromRGB(58, 56, 66), -- dark steel: parapet, sawtooth roof, window bars
		Trim = Color3.fromRGB(255, 62, 165),
		Theme = Color3.fromRGB(34, 225, 255),
		InsideWall = Color3.fromRGB(236, 214, 200),
		Palms = 2,
	},
	{
		Id = "PalmHillsBungalow",
		Name = "Palm Hills Bungalow",
		Price = 60000,
		Position = Vector3.new(-450, 0, -1550),
		Facing = Vector3.new(0, 0, -1), -- north, to the street at z = -1650
		GarageSlots = 2,
		Blurb = "A cosy seafoam bungalow under the palms.",
		Stories = 1,
		Wall = Color3.fromRGB(170, 232, 222), -- outside walls
		Accent = Color3.fromRGB(255, 190, 214), -- bands, awning
		Trim = Color3.fromRGB(255, 62, 165), -- neon trim and door frame
		Theme = Color3.fromRGB(110, 242, 196), -- neon colour inside
		InsideWall = Color3.fromRGB(255, 226, 234),
		Palms = 2,
	},
	{
		Id = "PalmHillsRanch",
		Name = "Palm Hills Ranch",
		Price = 110000,
		Position = Vector3.new(260, 0, -1578),
		Facing = Vector3.new(0, 0, -1), -- north, to the street at z = -1650 (behind Palm Plaza)
		GarageSlots = 3,
		Blurb = "A sunny ranch house with a wide front porch and a three-car garage.",
		Style = "Ranch",
		Stories = 1,
		Wall = Color3.fromRGB(255, 228, 160), -- butter-yellow wooden siding
		Accent = Color3.fromRGB(252, 250, 244), -- white porch posts, rails and eaves
		Roof = Color3.fromRGB(204, 108, 78), -- terracotta
		Trim = Color3.fromRGB(34, 225, 255),
		Theme = Color3.fromRGB(255, 62, 165),
		InsideWall = Color3.fromRGB(255, 240, 214),
		Palms = 3,
	},
	{
		Id = "SolanaHeightsPenthouse",
		Name = "Solana Heights Penthouse",
		Price = 180000,
		Position = Vector3.new(500, 0, 50),
		Facing = Vector3.new(0, 0, 1), -- south, to the street at z = 150
		GarageSlots = 4,
		Blurb = "A lavender tower in the middle of downtown, with a view of the whole city.",
		Stories = 5,
		Wall = Color3.fromRGB(206, 190, 255),
		Accent = Color3.fromRGB(250, 250, 255),
		Trim = Color3.fromRGB(34, 225, 255),
		Theme = Color3.fromRGB(34, 225, 255),
		InsideWall = Color3.fromRGB(228, 222, 255),
		Palms = 2,
	},
	{
		Id = "MarinaRowVilla",
		Name = "Marina Row Villa",
		Price = 400000,
		Position = Vector3.new(675, 0, 1400),
		Facing = Vector3.new(0, 0, 1), -- south, to Marina Row at z = 1500
		GarageSlots = 6,
		Blurb = "A peach seaside villa with its own pool and a six-car garage.",
		Stories = 2,
		Wall = Color3.fromRGB(255, 214, 170),
		Accent = Color3.fromRGB(255, 255, 255),
		Trim = Color3.fromRGB(255, 214, 10),
		Theme = Color3.fromRGB(255, 62, 165),
		InsideWall = Color3.fromRGB(255, 236, 214),
		Palms = 3,
		Pool = true,
	},
	{
		Id = "FlamingoBeachMansion",
		Name = "Flamingo Beach Mansion",
		Price = 1200000,
		Position = Vector3.new(1340, 0, -1270),
		Facing = Vector3.new(0, 0, -1), -- north, toward the causeway road at z = -1350
		GarageSlots = 8,
		Blurb = "The big one: a white glass mansion with a pool, pink neon and an 8-car garage.",
		Style = "Mansion",
		Stories = 3,
		Wall = Color3.fromRGB(250, 250, 252),
		Accent = Color3.fromRGB(255, 255, 255),
		Roof = Color3.fromRGB(255, 255, 255),
		Trim = Color3.fromRGB(255, 62, 165),
		Theme = Color3.fromRGB(255, 62, 165),
		InsideWall = Color3.fromRGB(255, 238, 246),
		Palms = 5,
		Pool = true,
	},
}

-- Cheapest first, whatever order the entries above are written in.
table.sort(Housing.List, function(a, b)
	if a.Price ~= b.Price then
		return a.Price < b.Price
	end
	return a.Id < b.Id
end)

Housing.ById = {}
for _, home in ipairs(Housing.List) do
	Housing.ById[home.Id] = home
end

-- Lot-space spots shared by the server (building) and the client (GPS, prompts).
Housing.Layout = {
	Door = Vector3.new(-18, 0, -10), -- bottom middle of the front door, on the house's front wall
	DoorStep = Vector3.new(-18, 0, -17), -- where you stand when you come out of the door
	-- Driveway parking spots (car centres on the ground, noses to the street). The last one is on the
	-- verge in front of the lot, for when two owners' cars are already parked.
	Driveway = { Vector3.new(26, 0.3, -21), Vector3.new(40, 0.3, -21), Vector3.new(33, 0, -46) },
}

-- The lot's frame: origin at the lot centre on the ground, looking at the street.
function Housing.Frame(home)
	return CFrame.lookAt(home.Position, home.Position + home.Facing)
end

-- World position of the bottom of the front door (the GPS target).
function Housing.DoorPosition(home)
	return (Housing.Frame(home) * CFrame.new(Housing.Layout.Door)).Position
end

-- Where a character appears outside the front door, facing the street.
function Housing.DoorCFrame(home)
	return Housing.Frame(home) * CFrame.new(Housing.Layout.DoorStep + Vector3.new(0, 3.5, 0))
end

-- Car spawn spots on the driveway (chassis height, like the city car pads).
function Housing.DrivewayCFrames(home)
	local frame = Housing.Frame(home)
	local list = {}
	for _, p in ipairs(Housing.Layout.Driveway) do
		table.insert(list, frame * CFrame.new(p + Vector3.new(0, 3.2, 0)))
	end
	return list
end

-- What the old home sells back for when you buy a new one.
function Housing.Refund(home)
	return home and math.floor(home.Price * Housing.RefundShare) or 0
end

-- A short price for tight labels (the map's places list): "$25k", "$400k", "$1.2M".
function Housing.ShortPrice(price)
	if price >= 1000000 then
		return string.format("$%gM", math.floor(price / 100000) / 10)
	end
	return string.format("$%dk", math.floor(price / 1000))
end

return Housing
