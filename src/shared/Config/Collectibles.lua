-- Collectibles (ModuleScript, ReplicatedStorage.Shared.Config.Collectibles)
-- Hidden Gus the Gator figurines around Port Solana (CollectibleService). Spots were picked from the
-- place's geometry: on land, at least 22 studs off any road, clear of props, tucked in among buildings
-- or scenery, 160+ studs apart. The server re-checks each spot with a raycast at start-up and nudges
-- it to the nearest clear ground if something's in the way. Ids are saved: never reuse or renumber one.

local Collectibles = {}

Collectibles.Cash = 250 -- per figurine
Collectibles.DistrictBonus = 1000 -- for finding every figurine in a district
Collectibles.Unlock = "GusHunter" -- all of them: the Gator Green paint (Config.Garage) and a title

Collectibles.Spots = {
	{ Id = "G01", District = "Solana Heights", X = 216, Z = 240, Hint = "behind the Coastal Bank" },
	{ Id = "G02", District = "Solana Heights", X = 4, Z = -230, Hint = "around Solana Plaza" },
	{ Id = "G03", District = "Solana Heights", X = 572, Z = -727, Hint = "tucked between the deco towers" },
	{ Id = "G04", District = "Solana Heights", X = -471, Z = -1, Hint = "tucked between the deco towers" },
	{ Id = "G05", District = "Solana Heights", X = 877, Z = -105, Hint = "tucked between the deco towers" },
	{ Id = "G06", District = "Solana Heights", X = 876, Z = -686, Hint = "tucked between the deco towers" },
	{ Id = "G07", District = "Solana Heights", X = -775, Z = -717, Hint = "tucked between the deco towers" },
	{ Id = "G08", District = "Palm Hills", X = -90, Z = -1490, Hint = "in Palm Hills Park" },
	{ Id = "G09", District = "Palm Hills", X = -91, Z = -1144, Hint = "by the pool loungers" },
	{ Id = "G10", District = "Palm Hills", X = -163, Z = -1802, Hint = "in a backyard" },
	{ Id = "G11", District = "Palm Hills", X = 443, Z = -1560, Hint = "in the backyards" },
	{ Id = "G12", District = "Palm Hills", X = 791, Z = -1003, Hint = "in the backyards" },
	{ Id = "G13", District = "Palm Hills", X = -777, Z = -1898, Hint = "in a backyard" },
	{ Id = "G14", District = "Flamingo Beach", X = 1097, Z = 242, Hint = "near a beach bench" },
	{ Id = "G15", District = "Flamingo Beach", X = 1093, Z = -485, Hint = "out on the sand" },
	{ Id = "G16", District = "Flamingo Beach", X = 1471, Z = -373, Hint = "behind a beach booth" },
	{ Id = "G17", District = "Flamingo Beach", X = 1080, Z = -1427, Hint = "by the boardwalk" },
	{ Id = "G18", District = "Flamingo Beach", X = 1058, Z = -154, Hint = "behind Club Nova" },
	{ Id = "G19", District = "Flamingo Beach", X = 1088, Z = -1725, Hint = "near a beach bench" },
	{ Id = "G20", District = "Gator Glades", X = -1612, Z = 446, Hint = "by the airboats" },
	{ Id = "G21", District = "Gator Glades", X = -1568, Z = -609, Hint = "by the boardwalk" },
	{ Id = "G22", District = "Gator Glades", X = -1777, Z = -256, Hint = "near the Gator Glades sign" },
	{ Id = "G23", District = "Gator Glades", X = -1483, Z = -1499, Hint = "by a stilt shack" },
	{ Id = "G24", District = "Gator Glades", X = -1059, Z = -890, Hint = "by a stilt shack" },
	{ Id = "G25", District = "Gator Glades", X = -1928, Z = -889, Hint = "at the edge of a pond" },
	{ Id = "G26", District = "Rustwater Docks", X = -436, Z = 1163, Hint = "near the hideout" },
	{ Id = "G27", District = "Rustwater Docks", X = 220, Z = 1407, Hint = "by the Solana Terminal" },
	{ Id = "G28", District = "Rustwater Docks", X = -753, Z = 1771, Hint = "in the container lot" },
	{ Id = "G29", District = "Rustwater Docks", X = -773, Z = 1501, Hint = "behind the Chop Shop" },
	{ Id = "G30", District = "Rustwater Docks", X = 223, Z = 1740, Hint = "by the forklifts" },
	{ Id = "G31", District = "Marina Row", X = 586, Z = 1252, Hint = "by the boat slips" },
	{ Id = "G32", District = "Marina Row", X = 1327, Z = 1771, Hint = "on the cargo quay" },
	{ Id = "G33", District = "Marina Row", X = 1480, Z = 1428, Hint = "on the waterfront" },
	{ Id = "G34", District = "Marina Row", X = 1484, Z = 1266, Hint = "on the waterfront" },
	{ Id = "G35", District = "Marina Row", X = 822, Z = 983, Hint = "along the promenade" },
	{ Id = "G36", District = "Saltmarsh Island", X = -1504, Z = 1345, Hint = "outside the prison" },
	{ Id = "G37", District = "Saltmarsh Island", X = -1736, Z = 1506, Hint = "along the prison fence" },
	{ Id = "G38", District = "Saltmarsh Island", X = -1111, Z = 1242, Hint = "along the prison fence" },
	{ Id = "G39", District = "Lighthouse Key", X = 2364, Z = -1187, Hint = "near the lighthouse" },
	{ Id = "G40", District = "Lighthouse Key", X = 2430, Z = -1420, Hint = "near the lighthouse" },
}

Collectibles.ById = {}
Collectibles.ByDistrict = {}
for _, s in ipairs(Collectibles.Spots) do
	Collectibles.ById[s.Id] = s
	Collectibles.ByDistrict[s.District] = Collectibles.ByDistrict[s.District] or {}
	table.insert(Collectibles.ByDistrict[s.District], s)
end

return Collectibles
