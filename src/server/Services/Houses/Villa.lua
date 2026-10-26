-- Villa (ModuleScript, ServerScriptService.Services.Houses.Villa)
-- Marina Row Villa ($400k, 6 cars): a two-storey Mediterranean villa by the marina. Peach stucco on a
-- stone base, a terracotta roof on carved corbels, arched windows with stone surrounds, green shutters,
-- wrought-iron Juliet balconies, an arcaded loggia on the front, an arched front door under a stone
-- frame, and a belvedere tower with open arches on top. A six-car garage wing (three arched doors, two
-- cars deep) behind a paved motor court; a fountain in the front garden; out back a travertine pool
-- terrace with a spa, an outdoor kitchen under a pergola, loungers and a stone balustrade on the water.
-- Inside: a foyer with a grand stair up to a gallery, a living room with arched French doors to the
-- loggia and the pool, a dining room, a kitchen, and upstairs the master suite (wardrobe, a balcony
-- over the pool), a guest room and a library. Drawn by HouseBuilder (lot space: front = -Z).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local P, M, rgb = HouseBuilder.P, HouseBuilder.M, HouseBuilder.rgb
local DETAIL = HouseBuilder.DETAIL

local X0, X1, Z0, Z1 = -54, 6, -12, 20 -- the house
local GX0, GX1, GZ0, GZ1 = 10, 54, -16, 24 -- the garage wing
local T = 1
local F1, F2 = 1.2, 15.2 -- floor tops
local H = 29 -- eaves
local GH = 13 -- garage eaves
local TW = { -6, 6, -12, 0, 46 } -- the tower (x0, x1, z0, z1, top)

return function(K, home)
	local stucco = home.Wall:Lerp(rgb(238, 220, 200), 0.35)
	local stone = rgb(214, 200, 176)
	local tile = P.Tile:Lerp(rgb(196, 98, 62), 0.4)
	local green = rgb(56, 92, 70)
	local iron = rgb(30, 30, 34)
	local walnut = P.Walnut
	local trim, theme = home.Trim, home.Theme
	local door = K.door -- (-24, 1.2, -12)
	local travertine = rgb(226, 214, 192)

	local pools = K.inside and { { -36, -12, 24, 36 }, { -48, -40, 28, 36 } } or nil
	-- Ground: lawn, the front walk, the motor court in pavers, the pool terrace in travertine.
	K.out.ground = K:Slab("Lawn", -55, 55, 0, 0.2, -35, 40, P.Lawn, M.Grass, pools) or K.model:FindFirstChild("Lawn", true)
	if K.inside then
		K:Slab("Base", -60, 60, -2, 0, -40, 40, rgb(110, 96, 80), M.Ground, pools)
	end
	K:Box("Walk", door.X - 4, door.X + 4, 0.2, 0.3, -35, -19, stone, M.Cobblestone)
	K:Box("MotorCourt", GX0 - 2, 55, 0.2, 0.3, -35, GZ0, rgb(200, 186, 160), M.Cobblestone)
	K:Slab("Terrace", -55, GX0 - 2, 0.2, 0.6, Z1, 40, travertine, M.Limestone, pools)

	-- The house: a stone base, peach stucco, arched windows (glass, a stone surround, an arched top),
	-- green shutters, the loggia, the front door, Juliet balconies.
	local S = K
	S:Box("Foundation", X0, X1, 0.2, F1, Z0, Z1, stone, M.Limestone)
	local wo = { sill = stone, sillMat = M.Limestone, frame = walnut, bars = 1 }
	local function arch(x0, x1, top, z, face)
		-- An arched top over an opening in the front (face -1) or back (+1) wall at z (its outer face): a
		-- glass disc set in the wall's own plane, a touch thicker than the wall, so only its top half shows
		-- (the bottom half is the window's own glass), a stone ring round it and stone jambs down the sides.
		local w = x1 - x0
		local cx = (x0 + x1) / 2
		local mid = z - face * T / 2
		local turn = CFrame.Angles(0, math.rad(90), 0)
		S:Part("Part", "ArchStone", Vector3.new(T + 0.06, w + 1.6, w + 1.6), S.cf * CFrame.new(cx, top, mid) * turn, stone, M.Limestone,
			HouseBuilder.Merge(DETAIL, { Shape = Enum.PartType.Cylinder }))
		S:Part("Part", "ArchGlass", Vector3.new(T + 0.12, w, w), S.cf * CFrame.new(cx, top, mid) * turn,
			K.inside and P.ClearGlass or P.Glass, M.Glass, HouseBuilder.Merge(DETAIL, { Shape = Enum.PartType.Cylinder, Reflectance = 0.1 }))
	end
	-- Front wall: the loggia's three French doors (ground, left), the front door, the dining windows
	-- (right); upstairs French doors on Juliet balconies and windows.
	local front = {
		{ -50, -45, F1, F1 + 9, "exit", color = walnut }, { -42, -37, F1, F1 + 9, "win" }, { -34, -30, F1, F1 + 9, "win" },
		{ door.X - 3.5, door.X + 3.5, F1, F1 + 10, "none" },
		{ -14, -9, F1 + 2.5, F1 + 9, "win" },
		{ -50, -45, F2 + 2, F2 + 9, "win" }, { -40, -35, F2 + 2, F2 + 9, "win" }, { -28, -20, F2 + 1, F2 + 9, "win", bars = 2 }, { -4, 1, F2 + 2, F2 + 9, "win" },
	}
	S:WallX(Z0 + T / 2, X0, X1, F1, H, T, stucco, M.Plaster, front, HouseBuilder.Merge(wo, { out = "-Z", shutters = green }))
	S:WallX(Z1 - T / 2, X0, X1, F1, H, T, stucco, M.Plaster, {
		{ -48, -40, F1, F1 + 9.5, "exit", color = walnut }, { -34, -30, F1 + 2.5, F1 + 9, "win" }, { 0.5, 4.5, F1, F1 + 9, "exit", color = walnut },
		{ -48, -40, F2, F2 + 9.5, "exit", color = walnut }, { -34, -28, F2 + 2, F2 + 9, "win" }, { -14, -8, F2 + 2, F2 + 9, "win" },
	}, HouseBuilder.Merge(wo, { out = "+Z" }))
	S:WallZ(X0 + T / 2, Z0 + T, Z1 - T, F1, H, T, stucco, M.Plaster, {
		{ -9, -4, F1 + 2.5, F1 + 9, "win" }, { 12, 17, F1 + 2.5, F1 + 9, "win" },
	}, HouseBuilder.Merge(wo, { out = "-X", shutters = green }))
	S:WallZ(X1 - T / 2, Z0 + T, Z1 - T, F1, H, T, stucco, M.Plaster, {
		{ 4, 8, F1, F1 + 9, "exit", color = walnut }, { 10, 16, F2 + 2, F2 + 9, "win" },
	}, HouseBuilder.Merge(wo, { out = "+X" }))
	for _, a in ipairs({ { -50, -45 }, { -42, -37 }, { -34, -30 }, { -14, -9 } }) do
		arch(a[1], a[2], a[1] == -14 and F1 + 9 or F1 + 9, Z0, -1)
	end
	for _, a in ipairs({ { -50, -45 }, { -40, -35 }, { -4, 1 } }) do
		arch(a[1], a[2], F2 + 9, Z0, -1)
	end
	arch(-48, -40, F1 + 9.5, Z1, 1)
	arch(-48, -40, F2 + 9.5, Z1, 1)
	S:Ring(X0, X1, Z0, Z1, F2 - 0.6, F2 + 0.4, 0.3, stone, M.Limestone)
	S:Ring(X0, X1, Z0, Z1, H - 1, H, 0.4, stone, M.Limestone)
	-- Juliet balconies: a stone ledge and an iron railing under the upstairs French doors and window.
	for _, b in ipairs({ { -28, -20 } }) do
		S:Box("Ledge", b[1] - 1, b[2] + 1, F2 - 0.4, F2 + 0.2, Z0 - 2.4, Z0, stone, M.Limestone)
		K:Rail(b[1] - 1, Z0 - 2.2, b[2] + 1, Z0 - 2.2, F2 + 0.2, 3.2, "posts", { color = iron, every = 0.8 })
	end
	-- The roof: terracotta on deep eaves with carved corbels, a neon line under the eaves after dark.
	S:Gable(X0 - 3, X1 + 3, H, Z0 - 3, Z1 + 3, 8, tile, { eave = walnut })
	for x = X0, X1, 4 do
		S:Deco("Corbel", x - 0.5, x + 0.5, H - 1.6, H, Z0 - 2.6, Z0, walnut, M.Wood)
		S:Deco("Corbel", x - 0.5, x + 0.5, H - 1.6, H, Z1, Z1 + 2.6, walnut, M.Wood)
	end
	S:Neon(X0 - 3, X1 + 3, H - 0.4, H - 0.1, Z0 - 3, Z0 - 2.7, trim)
	S:Box("Chimney", -50, -46, H, H + 12, 12, 16, stucco, M.Plaster)
	S:Deco("ChimneyCap", -50.6, -45.4, H + 12, H + 13, 11.4, 16.6, tile, M.ClayRoofTiles)

	-- The belvedere tower over the right end: stucco, a band at each floor, open arches on top, its own
	-- little tile roof and a lantern after dark.
	local tx0, tx1, tz0, tz1, ttop = TW[1], TW[2], TW[3], TW[4], TW[5]
	S:WallX(tz0 + 0.5, tx0, tx1, H, ttop - 8, T, stucco, M.Plaster, { { -2, 2, H + 3, H + 8, "win" } }, { out = "-Z", sill = stone, frame = walnut })
	S:WallX(tz1 - 0.5, tx0, tx1, H, ttop - 8, T, stucco, M.Plaster, {}, { out = "+Z" })
	S:WallZ(tx0 + 0.5, tz0 + T, tz1 - T, H, ttop - 8, T, stucco, M.Plaster, {}, { out = "-X" })
	S:WallZ(tx1 - 0.5, tz0 + T, tz1 - T, H, ttop - 8, T, stucco, M.Plaster, {}, { out = "+X" })
	S:Box("BelvedereFloor", tx0, tx1, ttop - 8.6, ttop - 8, tz0, tz1, stone, M.Limestone)
	for _, c in ipairs({ { tx0, tz0 }, { tx1, tz0 }, { tx0, tz1 }, { tx1, tz1 } }) do
		S:Box("Pier", c[1] - 1, c[1] + 1, ttop - 8, ttop, c[2] - 1, c[2] + 1, stucco, M.Plaster)
	end
	S:Box("BelvedereTop", tx0 - 1, tx1 + 1, ttop - 1.4, ttop, tz0 - 1, tz1 + 1, stucco, M.Plaster)
	S:Ring(tx0, tx1, tz0, tz1, ttop - 8.6, ttop - 7.6, 0.3, stone, M.Limestone)
	S:Gable(tx0 - 2, tx1 + 2, ttop, tz0 - 2, tz1 + 2, 4, tile, {})
	S:Lamp("Lantern", -0.8, 0.8, ttop - 6, ttop - 4, -6.8, -5.2, P.Warm, 24, 1)

	-- The loggia across the front-left: stone columns, arches, a tiled floor, a wooden ceiling.
	S:Box("LoggiaFloor", -54, -28, F1 - 0.4, F1, -20, Z0, stone, M.Limestone)
	for _, x in ipairs({ -53.5, -45, -36.5, -28.5 }) do
		S:Cyl("Column", x, -19, F1, F1 + 9.4, 1.6, stone, M.Limestone)
		S:Box("Capital", x - 1.2, x + 1.2, F1 + 9.4, F1 + 10, -20.2, -17.8, stone, M.Limestone)
	end
	S:Box("LoggiaBeam", -54.5, -28, F1 + 10, F1 + 11.2, -20.4, -17.6, stucco, M.Plaster)
	S:Wedge("LoggiaRoof", -55, -27.5, F1 + 11.2, F1 + 13.4, -21.5, Z0, tile, M.ClayRoofTiles, "-Z")
	S:Box("LoggiaCeiling", -54, -28.5, F1 + 10.6, F1 + 11, -17.8, Z0, walnut, M.WoodPlanks, DETAIL)
	-- The front door: a carved double door in a stone frame with an arched top, lanterns either side.
	K:FrontDoor(7, 10, T, walnut, M.WoodPlanks, stone, M.Limestone, { glass = false })
	S:Deco("DoorSplit", door.X - 0.1, door.X + 0.1, F1, F1 + 10, Z0 - 0.4, Z0 - 0.3, iron, M.Metal)
	arch(door.X - 3.5, door.X + 3.5, F1 + 10, Z0, -1)
	S:Box("Stoop", door.X - 5, door.X + 5, 0.2, 0.7, -17.5, -15, stone, M.Limestone)
	S:Box("Stoop", door.X - 5, door.X + 5, 0.2, F1, -15, Z0, stone, M.Limestone)
	S:WallLamp(door.X - 5.4, F1 + 8, Z0, P.Warm, 18)
	S:WallLamp(door.X + 5.4, F1 + 8, Z0, P.Warm)

	-- The garage wing: three arched doors in a stone base, stucco, a tile roof, lamps, a door to the
	-- side passage.
	S:Box("GarageSlab", GX0, GX1, 0.2, 0.4, GZ0, GZ1, P.Concrete, M.Concrete)
	local gdoors = { { 12, 24 }, { 26, 38 }, { 40, 52 } }
	local gh = {}
	for _, d in ipairs(gdoors) do
		table.insert(gh, { d[1], d[2], 0.4, 10, "none" })
	end
	S:WallX(GZ0 + 0.5, GX0, GX1, 0.4, GH, T, stucco, M.Plaster, gh, { out = "-Z" })
	S:WallX(GZ1 - 0.5, GX0, GX1, 0.4, GH, T, stucco, M.Plaster, { { 20, 28, 5, 10, "win" }, { 36, 44, 5, 10, "win" } }, { out = "+Z", sill = stone, frame = walnut })
	S:WallZ(GX0 + 0.5, GZ0 + T, GZ1 - T, 0.4, GH, T, stucco, M.Plaster, { { 4, 8, 0.4, 8.6, "exit", color = walnut } }, { out = "-X" })
	S:WallZ(GX1 - 0.5, GZ0 + T, GZ1 - T, 0.4, GH, T, stucco, M.Plaster, { { -4, 4, 5, 10, "win" }, { 10, 18, 5, 10, "win" } }, { out = "+X", sill = stone, frame = walnut })
	S:Ring(GX0, GX1, GZ0, GZ1, 0.4, 2.4, 0.3, stone, M.Limestone, { front = { { 11.4, 52.6 } }, left = { { 3.6, 8.4 } } })
	S:Gable(GX0 - 2, GX1 + 2, GH, GZ0 - 2, GZ1 + 2, 6, tile, { eave = walnut })
	S:Neon(GX0 - 2, GX1 + 2, GH - 0.4, GH - 0.1, GZ0 - 2, GZ0 - 1.7, trim)
	for i, d in ipairs(gdoors) do
		S:Box("GarageDoor", d[1], d[2], 0.4, 10, GZ0, GZ0 + 0.4, walnut, M.WoodPlanks)
		for v = 1, 3 do
			local x = d[1] + v * (d[2] - d[1]) / 4
			S:Deco("Plank", x - 0.1, x + 0.1, 0.4, 10, GZ0 - 0.15, GZ0, rgb(70, 48, 34), M.WoodPlanks)
		end
		S:Deco("Lintel", d[1] - 0.8, d[2] + 0.8, 10, 11.2, GZ0 - 0.5, GZ0, stone, M.Limestone)
		S:WallLamp(d[1] - 0.2, 8, GZ0, P.Warm, i == 2 and 18 or nil)
	end
	-- The side passage between the house and the garage: a pergola over it.
	S:Box("Passage", X1, GX0, 0.2, 0.4, Z0, Z1, stone, M.Limestone)
	for z = Z0 + 2, Z1 - 2, 4 do
		S:Deco("PassageBeam", X1, GX0, 11, 11.6, z - 0.3, z + 0.3, walnut, M.Wood)
	end

	-- Front garden: a round stone fountain, box hedges, palms, bollards, the sign.
	local Y = K:In("Yard")
	local fx, fz = -40, -27.5
	Y:Cyl("FountainRim", fx, fz, 0.2, 2.2, 12, stone, M.Limestone)
	Y:Cyl("FountainWater", fx, fz, 2.2, 2.3, 10.6, P.PoolWater, M.Glass, HouseBuilder.Merge(DETAIL, { Transparency = 0.25 }))
	Y:Cyl("FountainColumn", fx, fz, 2.2, 6, 1.6, stone, M.Limestone)
	Y:Cyl("FountainBowl", fx, fz, 6, 6.6, 5, stone, M.Limestone, DETAIL)
	Y:Cyl("FountainJet", fx, fz, 6.6, 8.6, 0.5, rgb(200, 236, 255), M.Glass, HouseBuilder.Merge(DETAIL, { Transparency = 0.4 }))
	Y:Hedge(-55, door.X - 5, -34.6, -33.4, 2.4)
	Y:Hedge(door.X + 5, GX0 - 2, -34.6, -33.4, 2.4)
	Y:Hedge(-54, -32, -22.6, -21.4, 2)
	Y:Palm(-51, -30, 22, math.rad(40))
	Y:Palm(-6, -28, 20, math.rad(190))
	Y:Palm(51, -30, 20, math.rad(300))
	Y:Bollards({ { GX0 - 1, -34.4 }, { 54, -34.4 } })
	K:StreetSign(-10, -31.5, stone, M.Limestone)

	-- The pool terrace out back: the pool and a spa (real water in your copy), loungers and umbrellas, an
	-- outdoor kitchen under a pergola behind the garage, potted palms, a stone balustrade on the water.
	K:Pool(-36, -12, 24, 36, 8, { tile = rgb(60, 140, 190), light = theme })
	K:Pool(-48, -40, 28, 36, 4, { tile = rgb(60, 140, 190), light = P.Gold, step = false })
	for i, z in ipairs({ 26, 30.5, 35 }) do
		Y:Lounger(-5, 0.6, z, 90, i % 2 == 0 and P.White or theme:Lerp(P.Cream, 0.5))
	end
	Y:Umbrella(2, 0.6, 30.5, theme:Lerp(P.White, 0.3))
	Y:Umbrella(-52, 0.6, 25, P.Cream)
	local ok = Y:Sub(18, 0.4, 30, 0)
	for _, c in ipairs({ { -8, -5 }, { 8, -5 }, { -8, 8 }, { 8, 8 } }) do
		ok:Box("PergolaPost", c[1] - 0.6, c[1] + 0.6, 0, 10, c[2] - 0.6, c[2] + 0.6, stucco, M.Plaster)
	end
	for i = 0, 6 do
		ok:Deco("PergolaSlat", -8.6, 8.6, 10, 10.6, -5.6 + i * 2.2, -5 + i * 2.2, walnut, M.Wood)
	end
	ok:Box("OutdoorKitchen", -7, 7, 0, 3.6, 4.6, 7.4, stone, M.Limestone)
	ok:Deco("Counter", -7.3, 7.3, 3.6, 4, 4.3, 7.6, rgb(120, 100, 80), M.Granite)
	ok:Box("Grill", -2, 2, 4, 5, 5, 7, P.Steel, M.Metal)
	ok:Lamp("PergolaLight", -1, 1, 9, 9.6, -1, 1, P.Warm, 22, 0.8)
	ok:Table(0, 0, -1, 0, 8, 4, 3.2, walnut)
	for _, p in ipairs({ { -53, 37.5 }, { 6.5, 22.5 }, { -24, 38 } }) do
		Y:Cyl("Urn", p[1], p[2], 0.6, 3, 2.8, rgb(176, 110, 80), M.Concrete)
		Y:Palm(p[1], p[2], 12, nil, 3)
	end
	-- The balustrade on the water's edge (low: the marina view), a wall round the sides.
	for _, seg in ipairs({ { -55, 55 } }) do
		Y:Box("Balustrade", seg[1], seg[2], 0.6, 1.2, 39.4, 40, stone, M.Limestone)
		Y:Box("BalustradeTop", seg[1], seg[2], 3.6, 4.2, 39.2, 40.2, stone, M.Limestone)
		for x = seg[1] + 1, seg[2] - 1, 1.6 do
			Y:Deco("Baluster", x - 0.3, x + 0.3, 1.2, 3.6, 39.5, 39.9, stone, M.Limestone)
		end
		Y:Box("BalustradeGuard", seg[1], seg[2], 1.2, 3.6, 39.5, 39.9, stone, M.Limestone, HouseBuilder.GHOST)
	end
	Y:Box("SideWall", -55, -54.4, 0.2, 6, Z1, 39.4, stucco, M.Plaster)
	Y:Box("SideWall", 54.4, 55, 0.2, 6, GZ1, 39.4, stucco, M.Plaster)

	if not K.inside then
		return
	end

	-- Inside ------------------------------------------------------------------------------------------------
	local R = K:In("Rooms")
	local I = K:In("Decor")
	local G = K:In("Garage")
	local IX0, IX1, IZ0, IZ1 = X0 + T, X1 - T, Z0 + T, Z1 - T
	local plaster = home.InsideWall:Lerp(rgb(246, 238, 226), 0.55)
	local marble = rgb(236, 232, 226)
	-- Floors: marble downstairs, oak upstairs with the stairwell open over the grand stair.
	R:Box("Floor", IX0, IX1, F1 - 0.4, F1, IZ0, IZ1, marble, M.Marble)
	local SX = -26 -- the stair's middle (x -29..-23)
	R:Slab("UpperFloor", IX0, IX1, F2 - 1, F2, IZ0, IZ1, rgb(170, 128, 88), M.WoodPlanks, { { SX - 3.2, SX + 3.2, -6, 15 } })
	R:Box("Ceiling", IX0, IX1, H - 0.8, H, IZ0, IZ1, P.WarmWhite, M.Plaster)
	R:Box("GroundCeiling", IX0, IX1, F2 - 1.2, F2 - 1, IZ0, IZ1, P.WarmWhite, M.Plaster, HouseBuilder.Merge(DETAIL, { Transparency = 1 }))
	local run = K:Stairs(SX, -6, "+Z", 6, F1, F2, marble, M.Marble)
	K:Rail(SX - 3.2, -6, SX - 3.2, 15, F2, 3.4, "posts", { color = iron, every = 1 })
	K:Rail(SX + 3.2, -6, SX + 3.2, 15, F2, 3.4, "posts", { color = iron, every = 1 })
	K:Rail(SX - 3.2, -6, SX + 3.2, -6, F2, 3.4, "posts", { color = iron, every = 1 })
	R:Bar("Handrail", SX - 3.1, F1 + 3.4, -6, SX - 3.1, F2 + 3.4, -6 + run, 0.3, walnut, M.Wood)
	R:Bar("Handrail", SX + 3.1, F1 + 3.4, -6, SX + 3.1, F2 + 3.4, -6 + run, 0.3, walnut, M.Wood)
	-- Ground floor partitions: the living room (left) | foyer | dining (front right) and kitchen (back right).
	R:WallZ(-36, IZ0, IZ1, F1, F2 - 1, 0.5, plaster, M.Plaster, { { -10, -4, F1, F1 + 10, "door" }, { 12, 17, F1, F1 + 10, "door" } }, { out = "-X" })
	R:WallZ(-16, IZ0, IZ1, F1, F2 - 1, 0.5, plaster, M.Plaster, { { -9, -2, F1, F1 + 10, "door" }, { 8, 14, F1, F1 + 10, "door" } }, { out = "+X" })
	R:WallX(4, -16, IX1, F1, F2 - 1, 0.5, plaster, M.Plaster, { { -8, -3, F1, F1 + 9, "door" } }, { out = "-Z" })
	-- Upstairs: the master suite (left), the guest room and bath (right), the library in the tower.
	R:WallZ(-36, IZ0, IZ1, F2, H - 0.8, 0.5, plaster, M.Plaster, { { 15.5, 19, F2, F2 + 9, "door" } }, { out = "-X" })
	R:WallZ(-16, IZ0, IZ1, F2, H - 0.8, 0.5, plaster, M.Plaster, { { 15.5, 19, F2, F2 + 9, "door" } }, { out = "+X" })
	R:WallX(4, -16, IX1, F2, H - 0.8, 0.5, plaster, M.Plaster, { { -14, -10, F2, F2 + 9, "door" }, { -3, 1, F2, F2 + 9, "door" } }, { out = "-Z" })
	for _, p in ipairs({ { -45, 4 }, { -26, -9 }, { -6, -4 }, { -6, 12 }, { -45, 4, F2 }, { -6, -4, F2 }, { -6, 12, F2 } }) do
		local base = p[3] or F1
		K:Sub(0, base, 0, 0):CeilingLight(p[1], p[2], (p[3] and H - 0.8 or F2 - 1) - base, 2.4, 24, 0.4)
	end
	-- The chandelier over the stair (lit always).
	I:Bar("ChandelierRod", SX, H - 0.8, 4, SX, H - 5, 4, 0.2, P.Brass, M.Metal)
	local chand = I:Ball("Chandelier", SX, H - 6, 4, 2.6, rgb(255, 236, 200), M.Neon, DETAIL)
	K:Light(chand, P.Warm, 30, 0.5)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		I:Ball("Crystal", SX + math.cos(a) * 2.4, H - 6.8, 4 + math.sin(a) * 2.4, 0.8, rgb(255, 246, 220), M.Neon, DETAIL)
	end

	-- Living room: two sofas facing each other by the fireplace, a coffee table, a rug, the piano,
	-- bookcases, plants.
	I:Fireplace(IX0 + 1, F1, 4, -90, stone, { mat = M.Limestone, mantel = stone, h = 11 })
	I:Rug(-45, F1, 4, 0, 14, 12, rgb(150, 60, 50))
	I:Sofa(-45, F1, -3.5, 180, 10, rgb(236, 226, 206), { pillows = rgb(150, 60, 50), seats = 2 })
	I:Sofa(-45, F1, 11.5, 0, 10, rgb(236, 226, 206), { pillows = rgb(150, 60, 50), seats = 2 })
	I:Table(-45, F1, 4, 0, 6, 4, 1.8, walnut)
	I:TV(-37.6, F1, 3.5, 90, 8, { glow = theme })
	I:Plant(-52, F1, -9, rgb(176, 110, 80), { tall = true })
	I:Plant(-52, F1, 17, rgb(176, 110, 80), { tall = true })
	-- Dining room (front right): a long table for eight, a sideboard, art.
	I:Dining(-5, F1, -4, 0, 12, 4.5, 4, walnut, rgb(236, 226, 206), { lamp = true, ends = true })
	-- Kitchen (back right): a run on the back wall, an island, the door out to the terrace.
	I:Kitchen(-4, F1, IZ1 - 1.4, 0, 8, rgb(236, 226, 206), rgb(120, 100, 80), { upper = rgb(236, 226, 206), hood = P.Brass, splash = rgb(200, 150, 100) })
	I:Fridge(IX1 - 2, F1, 10, 90, P.Steel)
	I:Island(-6, F1, 11, 0, 8, green, marble, walnut, 3)
	K:Spawn(-40, F1, 4, 90)

	-- Upstairs: the master suite (bed, nightstands, the wardrobe, a sofa, French doors to the balcony
	-- over the pool), the guest room, the library with a desk and a reading chair.
	local up = F2
	I:Bed(-47.5, up, -4, -90, 10, 10, walnut, P.White, theme:Lerp(rgb(120, 60, 50), 0.6), { headColor = rgb(214, 200, 176), headMat = M.Fabric, head = 7 })
	I:Nightstand(-51.6, up, -10.2, -90, walnut)
	K:Closet(IX0 + 1.5, up, 8, -90)
	I:Rug(-44, up, 6, 0, 10, 8, rgb(214, 200, 176))
	I:Armchair(-40, up, 14, 135, rgb(150, 60, 50))
	S:Box("BackBalcony", -50, -38, F2 - 0.6, F2, Z1, Z1 + 4, stone, M.Limestone)
	K:Rail(-50, Z1 + 3.8, -38, Z1 + 3.8, F2, 3.4, "posts", { color = iron, every = 0.8 })
	K:Rail(-50, Z1, -50, Z1 + 3.8, F2, 3.4, "posts", { color = iron, every = 0.8 })
	K:Rail(-38, Z1, -38, Z1 + 3.8, F2, 3.4, "posts", { color = iron, every = 0.8 })
	I:Bed(-5, up, IZ1 - 5.4, 0, 8, 9, walnut, P.White, rgb(60, 110, 160), { headColor = walnut })
	I:Nightstand(-11, up, IZ1 - 1.4, 0, walnut)
	I:Bath(-10.6, up, 2.1, 0, { shower = true, tile = rgb(220, 232, 236), vanity = walnut })
	R:WallZ(-6, IZ0, 4, F2, H - 0.8, 0.5, plaster, M.Plaster, {}, { out = "+X" })
	I:Bookshelf(-35.2, up, -2, -90, 10, 12, walnut)
	I:Bookshelf(-16.8, up, -2, 90, 10, 12, walnut)
	I:Armchair(-33, up, -8.5, 45, rgb(96, 60, 44), M.Leather, false) -- (no seat: getting up would land in the wall or on the gallery rail)
	-- The library under the tower: shelves, a desk, a globe.
	I:Bookshelf(IX1 - 0.8, up, -4, 90, 12, 12, walnut)
	I:Desk(0, up, -9, 0, walnut, rgb(96, 60, 44), theme)
	I:Ball("Globe", -4, up + 4, 1, 2.4, rgb(70, 120, 170), M.SmoothPlastic, DETAIL)

	-- Garage: six bays (three doors, two deep), a tool wall, a classic-car poster, strip lights.
	for _, x in ipairs({ 18, 32, 46 }) do
		K:Bay(x, 0.4, -6, 0)
		K:Bay(x, 0.4, 13.4, 0)
	end
	G:Box("ToolWall", GX1 - 1.4, GX1 - 1, 2, 10, -12, -2, rgb(150, 120, 90), M.Wood, DETAIL)
	G:Box("GarageCeiling", GX0 + T, GX1 - T, GH - 0.3, GH, GZ0 + T, GZ1 - T, rgb(200, 194, 184), M.WoodPlanks)
	K:GarageSign(32, 9, GZ1 - 1.3, 0, 16, 3.6)
	for _, z in ipairs({ -6, 13.4 }) do
		local strip = G:Deco("StripLight", 14, 50, GH - 0.6, GH - 0.3, z - 0.5, z + 0.5, rgb(240, 248, 255), M.Neon)
		K:Light(strip, rgb(235, 242, 255), 30, 0.5)
	end

	K:SaleStand(-31, F1, 8, -24, -12)
	K:ParkStand(32, 0.4, 3.7, 32, -16)
	K:Backdrop("marina")
	K:Bounds(-56, 56, -36, 41, -2, 60)
end
