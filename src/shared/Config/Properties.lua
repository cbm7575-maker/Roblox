-- Properties (ModuleScript, ReplicatedStorage.Shared.Config.Properties)
-- Safehouses players can buy (PropertyService). Ownership is per player and never exclusive: any
-- number of players can own the same property. Bought in person at the door.
-- Each entry:
--   Id, Name, District
--   Price     dollars (EconomyService.Spend)
--   MinRank   free-roam rank needed to buy (nil = any)
--   Rent      dollars per hour, accruing up to RentCapHours, collected in person at the door
--   Pos       door position on the ground (y is ignored: the server finds the floor by raycast)
--   Face      flat direction the door faces (out toward the road); the pad and spawn spot are in front
--   Color     neon accent for the door frame and pad
-- Perks: civilians respawn at their home; standing on the pad of a property you own with no heat
-- banks your bag; rent.

local Properties = {}

Properties.RentCapHours = 12
Properties.DoorReach = 14 -- studs: the server's in-person distance check at the door

Properties.List = {
	{
		Id = "DocksLoft", Name = "Rustwater Loft", District = "Rustwater Docks",
		Price = 25000, Rent = 300,
		Pos = Vector3.new(-531, 0, 1619), Face = Vector3.new(0, 0, 1), -- beside the warehouse roller door
		Color = Color3.fromRGB(255, 138, 61),
	},
	{
		Id = "HillsBungalow", Name = "Palm Hills Bungalow", District = "Palm Hills",
		Price = 60000, Rent = 700,
		Pos = Vector3.new(13, 0, -1150), Face = Vector3.new(1, 0, 0), -- on the driveway, Solana Ave in front
		Color = Color3.fromRGB(110, 242, 196),
	},
	{
		Id = "HeightsPenthouse", Name = "Solana Heights Penthouse", District = "Solana Heights",
		Price = 150000, MinRank = 5, Rent = 1800,
		Pos = Vector3.new(-327, 0, -540), Face = Vector3.new(1, 0, 0), -- the deco tower's street door
		Color = Color3.fromRGB(34, 225, 255),
	},
	{
		Id = "MarinaVilla", Name = "Marina Row Villa", District = "Marina Row",
		Price = 300000, MinRank = 10, Rent = 3600,
		Pos = Vector3.new(670, 0, 951), Face = Vector3.new(0, 0, 1), -- the promenade gate, Marina Row in front
		Color = Color3.fromRGB(255, 62, 165),
	},
}

Properties.ById = {}
for _, p in ipairs(Properties.List) do
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
