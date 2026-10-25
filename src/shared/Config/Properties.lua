-- Properties (ModuleScript, ReplicatedStorage.Shared.Config.Properties)
-- Houses players can buy (PropertyService builds them at server start with HouseBuilder). Ownership
-- is per player and never exclusive: any number of players can own the same house. Bought in person
-- at the FOR SALE sign on the driveway; saves keep the Ids below, so never rename an Id.
-- Each entry:
--   Id, Name, District
--   Price     dollars (EconomyService.Spend)
--   MinRank   free-roam rank needed to buy (nil = any)
--   Rent      dollars per hour, accruing up to RentCapHours, collected in person at the front door
--   Pos       the front door on the ground (for the GPS and the phone; the house is built from Lot)
--   Face      flat direction the front of the house faces (out toward the road), from Yaw
--   Color     neon accent for the house, the sign and the pad
--   Garage    garage bays: owners' cars show up in them (up to this many)
--   Floors    storeys (a roof terrace doesn't count)
--   Pool      true when the house has a swimming pool
--   Features  short display text for the phone's HOMES app and the sale sign
--   Style     the builder module (ServerScriptService.Services.Houses.<Style>)
--   Size      lot size class, for the part budget (S, M, L, XL, Mansion)
--   Lot, Yaw  lot centre (on the 4-stud grid, so pools line up with terrain voxels) and its turn in
--             degrees (0 = the front faces -Z)
-- Perks: civilians respawn inside their home; a garage pad banks your bag with no heat; rent.

local Properties = {}

Properties.RentCapHours = 12
Properties.DoorReach = 14 -- studs: the server's in-person distance check at the door and the sign

Properties.List = {
	{
		Id = "GladesCabin", Name = "Bayou Stilt Cabin", District = "Gator Glades",
		Price = 15000, Rent = 90, Garage = 1, Floors = 1, Pool = false,
		Features = "Stilts, porch, fire pit, 1-car carport",
		Style = "StiltCabin", Size = "S", Lot = Vector3.new(-1384, 0, -636), Yaw = 270,
		Pos = Vector3.new(-1378, 0, -636),
		Color = Color3.fromRGB(110, 242, 120),
	},
	{
		Id = "DocksLoft", Name = "Rustwater Loft", District = "Rustwater Docks",
		Price = 25000, Rent = 300, Garage = 1, Floors = 2, Pool = false,
		Features = "Brick warehouse loft, 1-car garage",
		Style = "BrickLoft", Size = "S", Lot = Vector3.new(-396, 0, 940), Yaw = 0,
		Pos = Vector3.new(-402, 0, 926),
		Color = Color3.fromRGB(255, 138, 61),
	},
	{
		Id = "HillsBungalow", Name = "Palm Hills Bungalow", District = "Palm Hills",
		Price = 60000, Rent = 700, Garage = 2, Floors = 1, Pool = false,
		Features = "2 bedrooms, backyard BBQ, 2-car garage",
		Style = "Bungalow", Size = "M", Lot = Vector3.new(-8, 0, -1392), Yaw = 270,
		Pos = Vector3.new(4, 0, -1412.5),
		Color = Color3.fromRGB(110, 242, 196),
	},
	{
		Id = "HeightsPenthouse", Name = "Solana Heights Townhouse", District = "Solana Heights",
		Price = 150000, MinRank = 5, Rent = 1800, Garage = 2, Floors = 2, Pool = false,
		Features = "Modern 2 floors, rooftop hot tub, 2-car garage",
		Style = "Townhouse", Size = "M", Lot = Vector3.new(-248, 0, -508), Yaw = 90,
		Pos = Vector3.new(-262, 0, -500),
		Color = Color3.fromRGB(34, 225, 255),
	},
	{
		Id = "HillsFamilyHome", Name = "Palm Hills Family Home", District = "Palm Hills",
		Price = 180000, MinRank = 5, Rent = 1080, Garage = 3, Floors = 2, Pool = true,
		Features = "2 floors, 3 bedrooms, pool deck, 3-car garage",
		Style = "FamilyHome", Size = "L", Lot = Vector3.new(-168, 0, -1312), Yaw = 180,
		Pos = Vector3.new(-146, 0, -1296),
		Color = Color3.fromRGB(255, 214, 10),
	},
	{
		Id = "MarinaVilla", Name = "Marina Row Villa", District = "Marina Row",
		Price = 300000, MinRank = 10, Rent = 3600, Garage = 3, Floors = 2, Pool = true,
		Features = "Waterfront villa, pool terrace, 3-car garage",
		Style = "Villa", Size = "L", Lot = Vector3.new(1384, 0, 1060), Yaw = 0,
		Pos = Vector3.new(1398, 0, 1048),
		Color = Color3.fromRGB(255, 62, 165),
	},
	{
		Id = "BeachHouse", Name = "Flamingo Beach House", District = "Flamingo Beach",
		Price = 600000, MinRank = 10, Rent = 3600, Garage = 4, Floors = 2, Pool = true,
		Features = "Beachfront, lagoon pool, tiki bar, 4-car garage",
		Style = "BeachHouse", Size = "XL", Lot = Vector3.new(1328, 0, -1280), Yaw = 0,
		Pos = Vector3.new(1342, 0, -1300),
		Color = Color3.fromRGB(255, 120, 200),
	},
	{
		Id = "CoastalMansion", Name = "Coastal Mansion", District = "Marina Row",
		Price = 1200000, MinRank = 15, Rent = 7200, Garage = 6, Floors = 2, Pool = true,
		Features = "Gated estate, fountain, big pool, 6-car garage",
		Style = "Mansion", Size = "Mansion", Lot = Vector3.new(1400, 0, 1576), Yaw = 0,
		Pos = Vector3.new(1398.5, 0, 1560),
		Color = Color3.fromRGB(255, 214, 120),
	},
}

Properties.ById = {}
for _, p in ipairs(Properties.List) do
	local yaw = math.rad(p.Yaw or 0)
	p.Face = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	Properties.ById[p.Id] = p
end

-- Uncollected rent for a property bought / last collected at `since` (os.time), at time `t`.
-- Clock-skew safe: a `since` in the future (another server's clock ran ahead) accrues nothing.
function Properties.RentDue(def, since, t)
	if type(since) ~= "number" then
		return 0
	end
	local seconds = math.clamp(t - since, 0, Properties.RentCapHours * 3600)
	return math.floor(def.Rent * seconds / 3600)
end

return Properties
