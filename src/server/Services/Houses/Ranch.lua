-- Ranch (ModuleScript, ServerScriptService.Services.Houses.Ranch)
-- Palm Hills Ranch ($110k, 3 cars): a long, low 1960s Florida ranch in an L. Butter-yellow board-and-
-- batten siding over a brick wainscot, white trim, teal Bahama shutters, a low terracotta roof with a
-- brick chimney, a wide front porch with white posts and rockers, and a three-car garage wing stepped
-- forward with its own front gable. Out back, behind a cedar privacy fence: a pergola over the patio with
-- a built-in grill and a picnic table, a hot tub on a deck, a swing set, a trampoline and a fire pit.
-- Inside: a family room round a stone fireplace with the TV over the mantel, an open kitchen with an
-- island and a dining table, the master bedroom with the wardrobe, a kids' room with bunk beds and a
-- den with a pool table, a jukebox and French doors to the patio; a door from the kitchen to the garage.
-- Drawn by HouseBuilder (lot space: front = -Z).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local P, M, rgb = HouseBuilder.P, HouseBuilder.M, HouseBuilder.rgb
local DETAIL = HouseBuilder.DETAIL

local X0, X1, Z0, Z1 = -54, 8, -10, 22 -- the house
local GX0, GX1, GZ0, GZ1 = 8, 54, -16, 14 -- the garage wing (shares the house's x = 8 wall)
local T = 1
local F = 1 -- floor top
local H = 12.6 -- eaves
local GH = 12

return function(K, home)
	local siding = home.Wall:Lerp(rgb(238, 226, 196), 0.3)
	local brick = rgb(150, 86, 66)
	local white = P.White
	local teal = rgb(52, 112, 116)
	local tile = home.Roof and home.Roof:Lerp(P.Tile, 0.5) or P.Tile
	local trim, theme = home.Trim, home.Theme
	local door = K.door -- (-20, 1, -10)
	local deck = rgb(150, 112, 78)

	-- Ground: the lawn, the front walk, the wide driveway, the patio slab out back.
	local pools = K.inside and { { -52, -40, 28, 36 } } or nil -- (the hot tub's hole through the copy's ground)
	K.out.ground = K:Slab("Lawn", -55, 55, 0, 0.2, -35, 40, P.Lawn, M.Grass, pools) or K.model:FindFirstChild("Lawn", true)
	K:Box("Walk", door.X - 3, door.X + 3, 0.2, 0.3, -34, -21, P.Paving, M.Pavement)
	K:Box("Walk", door.X + 3, GX0 + 1, 0.2, 0.3, -24, -21, P.Paving, M.Pavement)
	K:Box("Driveway", GX0 + 1, GX1 - 1, 0.2, 0.3, -35, GZ0, P.Concrete, M.Concrete)
	for _, z in ipairs({ -29, -22 }) do
		K:Deco("Joint", GX0 + 1, GX1 - 1, 0.3, 0.32, z - 0.1, z + 0.1, rgb(138, 134, 126), M.Concrete)
	end
	if K.inside then
		K:Slab("Base", -60, 60, -2, 0, -40, 40, rgb(110, 96, 80), M.Ground, pools)
	end

	-- The house: a brick wainscot, board-and-batten siding above it, white trim, shuttered windows, a
	-- big picture window in the family room, French doors from the den to the patio.
	local S = K
	S:Box("Foundation", X0, X1, 0.2, F, Z0, Z1, rgb(168, 164, 156), M.Concrete)
	local wo = { sill = white, sillMat = M.WoodPlanks, frame = white, bars = 1, transom = true, shutters = teal }
	local front = {
		{ door.X - 3, door.X + 3, F, F + 9.5, "none" },
		{ -50, -36, F + 2.6, F + 9, "win", bars = 3 },
		{ -31, -25, F + 3, F + 9, "win" }, { -12, -6, F + 3.6, F + 9, "win" }, { -2, 4, F + 3.6, F + 9, "win" },
	}
	S:WallX(Z0 + T / 2, X0, X1, F, H, T, siding, M.WoodPlanks, front, HouseBuilder.Merge(wo, { out = "-Z" }))
	S:WallX(Z1 - T / 2, X0, X1, F, H, T, siding, M.WoodPlanks, {
		{ -48, -42, F + 3, F + 9, "win" }, { -31, -25, F + 3, F + 9, "win" }, { -16, -12, F + 5, F + 9, "win" },
		{ -5, 3, F, F + 9.5, "exit", color = white },
	}, HouseBuilder.Merge(wo, { out = "+Z", shutters = false }))
	S:WallZ(X0 + T / 2, Z0 + T, Z1 - T, F, H, T, siding, M.WoodPlanks, {
		{ -6, -2, F + 3, F + 9, "win" }, { 13, 18, F + 3, F + 9, "win" },
	}, HouseBuilder.Merge(wo, { out = "-X" }))
	S:WallZ(X1 - T / 2, GZ1, Z1 - T, F, H, T, siding, M.WoodPlanks, { { 16, 20, F + 3, F + 9, "win" } }, HouseBuilder.Merge(wo, { out = "+X" }))
	-- Brick wainscot (looks only, on the outside faces) and the battens.
	S:Ring(X0, X1, Z0, Z1, F, F + 3, 0.3, brick, M.Brick, { front = { { door.X - 3.6, door.X + 3.6 } }, back = { { -5.6, 3.6 } }, right = { { -10, GZ1 } } })
	for x = X0 + 2, X1 - 2, 2.4 do
		S:Deco("Batten", x - 0.15, x + 0.15, F + 3, H - 0.8, Z0 - 0.15, Z0, siding:Lerp(P.White, 0.25), M.WoodPlanks)
	end
	S:Ring(X0, X1, Z0, Z1, H - 0.8, H, 0.35, white, M.WoodPlanks, { right = { { -10, GZ1 } } })
	-- The roof: a low clay-tile gable (ridge along X) with white eaves and a neon line after dark, the
	-- brick chimney.
	S:Gable(X0 - 2.5, X1, H, Z0 - 2.5, Z1 + 2.5, 7, tile, { eave = white })
	S:Neon(X0 - 2.5, X1, H + 0.1, H + 0.5, Z0 - 2.9, Z0 - 2.5, trim)
	S:Box("Chimney", -46, -41, H, H + 11, 6, 11, brick, M.Brick)
	S:Deco("ChimneyCap", -46.4, -40.6, H + 11, H + 11.5, 5.6, 11.4, rgb(150, 146, 140), M.Concrete)

	-- The porch: a plank deck a step up across most of the front, white posts, a tile shed roof, rockers.
	local PZ0 = -18
	S:Box("Porch", -52, 4, F - 0.4, F, PZ0, Z0, deck, M.WoodPlanks)
	S:Box("Step", door.X - 4, door.X + 4, 0.2, 0.6, PZ0 - 2, PZ0, deck, M.WoodPlanks)
	for _, x in ipairs({ -51.5, -38, -26, -14, 3.5 }) do
		S:Box("PorchPost", x - 0.5, x + 0.5, F, H - 0.6, PZ0 + 0.3, PZ0 + 1.3, white, M.WoodPlanks)
	end
	S:Box("PorchBeam", -52.5, 4.5, H - 0.6, H, PZ0, PZ0 + 1.6, white, M.WoodPlanks)
	S:Wedge("PorchRoof", -53, 5, H, H + 2.4, PZ0 - 1, Z0 - 2.5, tile, M.ClayRoofTiles, "-Z")
	S:Box("PorchCeiling", -52, 4, H - 1.2, H - 0.6, PZ0 + 1.6, Z0, white, M.WoodPlanks, DETAIL)
	K:Rail(-51.5, PZ0 + 0.8, -38, PZ0 + 0.8, F, 3.2, "posts", { color = white, mat = M.WoodPlanks, every = 1.6 })
	K:Rail(-14, PZ0 + 0.8, 3.5, PZ0 + 0.8, F, 3.2, "posts", { color = white, mat = M.WoodPlanks, every = 1.6 })
	S:Lamp("PorchLight", door.X - 0.6, door.X + 0.6, H - 2.4, H - 1.2, PZ0 + 4, PZ0 + 5.2, P.Warm, 18, 1)
	K:FrontDoor(5.6, 9.5, T, teal, M.WoodPlanks, white, M.WoodPlanks)
	local Y = K:In("Yard")
	for _, x in ipairs({ -32, -28 }) do
		local r = Y:Sub(x, F, PZ0 + 4, 15)
		r:Box("Rocker", -1.3, 1.3, 1.4, 1.8, -1.3, 1.3, white, M.WoodPlanks)
		r:Deco("RockerBack", -1.3, 1.3, 1.8, 5.2, 1.1, 1.3, white, M.WoodPlanks)
	end
	Y:Box("PorchTable", -30.8, -29.2, F, F + 2, PZ0 + 3.2, PZ0 + 4.8, white, M.WoodPlanks, DETAIL)

	-- The garage wing: brick wainscot and siding, a front gable with a round vent, three white
	-- sectional doors under lamps, a door to the back yard.
	S:Box("GarageSlab", GX0, GX1, 0.2, 0.4, GZ0, GZ1, P.Concrete, M.Concrete)
	local doors = { { 11, 23 }, { 24, 36 }, { 37, 49 } }
	local gholes = {}
	for _, d in ipairs(doors) do
		table.insert(gholes, { d[1], d[2], 0.4, 10, "none" })
	end
	S:WallX(GZ0 + T / 2, GX0, GX1, 0.4, GH, T, siding, M.WoodPlanks, gholes, { out = "-Z" })
	S:WallX(GZ1 - T / 2, X1, GX1, 0.4, GH, T, siding, M.WoodPlanks, { { 40, 44, 0.4, 8.6, "exit", color = white }, { 22, 30, 5, 9, "win" } },
		{ out = "+Z", sill = white, frame = white, bars = 1 })
	S:WallZ(GX1 - T / 2, GZ0 + T, GZ1 - T, 0.4, GH, T, siding, M.WoodPlanks, { { -6, 4, 5, 9, "win" } }, { out = "+X", sill = white, frame = white, bars = 1 })
	S:WallZ(GX0 + T / 2, GZ0 + T, Z0, 0.4, GH, T, siding, M.WoodPlanks, {}, { out = "-X" })
	S:Ring(GX0, GX1, GZ0, GZ1, 0.4, 3, 0.3, brick, M.Brick, { front = { { 10.4, 49.6 } }, back = { { 39.6, 44.4 } }, left = { { -10, GZ1 } } })
	S:Gable(GX0 - 1, GX1 + 2, GH, GZ0 - 2.5, GZ1 + 1, 8, tile, { eave = white, alongZ = true })
	S:Neon(GX0 - 1, GX1 + 2, GH + 0.1, GH + 0.5, GZ0 - 2.9, GZ0 - 2.5, trim)
	S:Triangle(GX0, GX1, GH, 8 * (GX1 - GX0) / (GX1 - GX0 + 3), GZ0, 0.6, siding, M.WoodPlanks)
	S:Pipe("GableVent", false, GZ0 - 0.3, GZ0, GH + 3, (GX0 + GX1) / 2, 3, white, M.WoodPlanks, DETAIL)
	for i, d in ipairs(doors) do
		S:Box("GarageDoor", d[1], d[2], 0.4, 10, GZ0, GZ0 + 0.4, rgb(234, 230, 220), M.WoodPlanks)
		for r = 1, 3 do
			local y = 0.4 + r * 9.6 / 4
			S:Deco("Panel", d[1] + 0.3, d[2] - 0.3, y - 0.1, y + 0.1, GZ0 - 0.15, GZ0, rgb(204, 198, 186), M.WoodPlanks)
		end
		S:Deco("DoorFrame", d[1], d[2], 10, 10.6, GZ0 - 0.3, GZ0, white, M.WoodPlanks)
		S:WallLamp((d[1] + d[2]) / 2, 11.2, GZ0, P.Warm, i == 2 and 18 or nil)
	end
	Y:Bollards({ { GX0 + 1, -34.4 }, { GX1 - 1, -34.4 } })

	-- Front yard: a low hedge, flower beds along the porch, palms, a mailbox, the sign.
	Y:Hedge(-55, door.X - 4, -34.6, -33.4, 2.6)
	Y:Hedge(door.X + 4, GX0, -34.6, -33.4, 2.6)
	K:FlowerBed(-50, -38, -20, { rgb(232, 190, 60), rgb(196, 52, 64) })
	K:FlowerBed(-14, 2, -20, { rgb(232, 190, 60), rgb(196, 52, 64) })
	Y:Palm(-51, -28, 20, math.rad(70))
	Y:Palm(5, -27, 16, math.rad(130))
	Y:Bush(-8, -25, 4)
	Y:Bush(-54, 18, 4.5)
	local mailbox = Y:Sub(GX0 - 1.5, 0.2, -32, 90)
	mailbox:Box("MailPost", -0.25, 0.25, 0, 3.6, -0.25, 0.25, white, M.WoodPlanks)
	mailbox:Box("Mailbox", -0.8, 0.8, 3.6, 5, -1.2, 1.2, P.DarkMetal, M.Metal)
	K:StreetSign(-41, -31, white, M.WoodPlanks)

	-- Back yard, behind a cedar privacy fence (open at the gate by the garage): a pergola over the
	-- patio with a built-in grill and a picnic table, a hot tub on a deck, a swing set, a trampoline and
	-- a fire pit; string lights under the pergola.
	local cedar = rgb(160, 110, 74)
	Y:Box("Fence", -55, 55, 0.2, 7, 39.4, 40, cedar, M.WoodPlanks)
	Y:Box("Fence", -55, -54.4, 0.2, 7, Z1, 39.4, cedar, M.WoodPlanks)
	Y:Box("Fence", 54.4, 55, 0.2, 7, 24, 39.4, cedar, M.WoodPlanks)
	Y:Box("Fence", GX1, 55, 0.2, 7, GZ1, GZ1 + 0.6, cedar, M.WoodPlanks)
	K:Box("Patio", -40, 6, 0.2, 0.5, Z1, 34, P.Paving, M.Pavement)
	for _, x in ipairs({ -39, -24, -9, 5 }) do
		for _, z in ipairs({ 33 }) do
			S:Box("PergolaPost", x - 0.6, x + 0.6, 0.5, 11, z - 0.6, z + 0.6, white, M.WoodPlanks)
		end
	end
	S:Box("PergolaBeam", -40, 6, 11, 12, 32.4, 33.6, white, M.WoodPlanks)
	for i = 0, 11 do
		local x = -39 + i * 4
		S:Deco("PergolaSlat", x - 0.3, x + 0.3, 12, 12.6, Z1, 34.4, white, M.WoodPlanks)
	end
	Y:StringLights(-39, 10.6, 32.6, 5, 10.6, 32.6, 12, P.Warm)
	-- The grill station: a brick counter with a stainless grill and a hood.
	Y:Box("GrillCounter", -38, -28, 0.5, 4, 29, 32, brick, M.Brick)
	Y:Deco("CounterTop", -38.3, -27.7, 4, 4.4, 28.7, 32.2, rgb(214, 210, 200), M.Granite)
	Y:Box("Grill", -35, -30, 4.4, 5.6, 29.4, 31.6, P.Steel, M.Metal)
	Y:Deco("GrillLid", -35, -30, 5.6, 6.6, 30.6, 31.6, P.Steel, M.Metal)
	local pic = Y:Sub(-14, 0.5, 27, 0)
	pic:Box("TableTop", -5, 5, 3, 3.4, -1.8, 1.8, cedar, M.WoodPlanks)
	pic:Deco("TableLegs", -4, 4, 0, 3, -0.4, 0.4, cedar, M.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		pic:Box("Bench", -5, 5, 1.6, 2, s * 3 - 0.7, s * 3 + 0.7, cedar, M.WoodPlanks)
	end
	-- Hot tub on a little deck at the back-left corner (real water inside your copy).
	S:Slab("TubDeck", -54, -38, 0.2, 0.45, 26, 39, deck, M.WoodPlanks, { { -52, -40, 28, 36 } })
	K:Pool(-52, -40, 28, 36, 4, { tile = rgb(70, 160, 170), coping = deck, light = P.PoolLight })
	Y:Box("TubSteps", -40, -37, 0.2, 1.2, 30, 34, deck, M.WoodPlanks, DETAIL)
	-- Swing set (A-frame and two swings) and a trampoline behind the garage.
	local sw = Y:Sub(26, 0.2, 30, 0)
	for _, x in ipairs({ -7, 7 }) do
		sw:Bar("SwingLeg", x, 0, -3, x, 10, 0, 0.5, rgb(200, 60, 60), M.Metal)
		sw:Bar("SwingLeg", x, 0, 3, x, 10, 0, 0.5, rgb(200, 60, 60), M.Metal)
	end
	sw:Pipe("SwingBar", true, -7.4, 7.4, 10, 0, 0.6, rgb(200, 60, 60), M.Metal)
	for _, x in ipairs({ -3, 3 }) do
		sw:Bar("SwingChain", x - 1, 10, 0, x - 1, 2.4, 0, 0.1, P.Steel, M.Metal)
		sw:Bar("SwingChain", x + 1, 10, 0, x + 1, 2.4, 0, 0.1, P.Steel, M.Metal)
		sw:Deco("SwingSeat", x - 1.2, x + 1.2, 2.2, 2.5, -0.6, 0.6, P.Black, M.Rubber)
	end
	Y:Cyl("Trampoline", 45, 28, 3, 3.3, 12, rgb(40, 110, 200), M.Fabric)
	Y:Cyl("TrampolineMat", 45, 28, 3.3, 3.35, 10, P.Black, M.Fabric, DETAIL)
	for i = 0, 5 do
		local a = math.rad(i * 60)
		Y:Deco("TrampolineLeg", 45 + math.cos(a) * 5.6 - 0.15, 45 + math.cos(a) * 5.6 + 0.15, 0.2, 3, 28 + math.sin(a) * 5.6 - 0.15, 28 + math.sin(a) * 5.6 + 0.15, P.Steel, M.Metal)
	end
	Y:FirePit(-17, 0.2, 36, rgb(130, 118, 104))
	Y:Palm(-30, 37, 18, math.rad(20))
	Y:Palm(52, 37, 18, math.rad(300))

	if not K.inside then
		return
	end

	-- Inside ------------------------------------------------------------------------------------------------
	local R = K:In("Rooms")
	local I = K:In("Decor")
	local G = K:In("Garage")
	local IX0, IX1, IZ0, IZ1 = X0 + T, X1 - T, Z0 + T, Z1 - T
	local plaster = home.InsideWall:Lerp(rgb(244, 238, 228), 0.6)
	R:Box("Floor", IX0, IX1, F - 0.4, F, IZ0, IZ1, rgb(184, 140, 96), M.WoodPlanks)
	R:Box("Ceiling", IX0, IX1, H - 0.8, H, IZ0, IZ1, P.WarmWhite, M.Plaster)
	-- The shared wall with the garage (x = 8): a door from the kitchen.
	R:WallZ(X1 - T / 2, IZ0, GZ1, F, H - 0.8, T, siding, M.WoodPlanks, { { 9, 13, F, F + 9, "door" } }, { out = "+X" })
	R:Box("GarageStep", X1, X1 + 2, 0.4, F, 8.5, 13.5, rgb(168, 164, 156), M.Concrete)
	-- Bedrooms and the den along the back (z 6..21), the open family room and kitchen in front.
	R:WallX(6, IX0, IX1, F, H - 0.8, 0.5, plaster, M.Plaster, {
		{ -38, -34, F, F + 9, "door" }, { -26, -22, F, F + 9, "door" }, { -16, -13, F, F + 9, "door" }, { -5, 1, F, F + 9, "door" },
	}, { out = "-Z" })
	for _, x in ipairs({ -32, -20, -8 }) do
		R:WallZ(x, 6.25, IZ1, F, H - 0.8, 0.5, plaster, M.Plaster, {}, { out = "-X" })
	end
	for _, p in ipairs({ { -40, -1 }, { -12, -1 }, { -44, 14 }, { -25, 14 }, { -1, 14 } }) do
		K:CeilingLight(p[1], p[2], H - 0.8, 2.4, 24, 0.42)
	end

	-- Family room: a stone fireplace on the left wall with the TV over the mantel, a sectional sofa, a
	-- recliner, a rug, a coffee table, a floor lamp, plants.
	local stone = rgb(150, 140, 128)
	I:Fireplace(IX0 + 1, F, -1, -90, stone, { h = H - F - 0.8 })
	I:TV(IX0 + 2.9, F, -1, -90, 7, { wall = true, at = 6.6 })
	I:Rug(-40, F, -1, 0, 12, 14, rgb(120, 80, 60))
	I:Sofa(-33, F, -1, 90, 12, rgb(110, 96, 80), { pillows = theme:Lerp(P.Cream, 0.4), seats = 3 })
	I:Armchair(-46.5, F, 3, 45, rgb(96, 60, 44), M.Leather)
	I:Table(-41, F, -1, 90, 7, 3.5, 1.8, P.Walnut)
	I:FloorLamp(-51, F, -7.4, P.Warm)
	I:Plant(-28, F, -7.6, rgb(170, 100, 70), { tall = true })
	-- Kitchen on the right, an island, and the dining table by the front windows.
	I:Kitchen(IX1 - 1.4, F, 0.3, 90, 10, rgb(236, 226, 200), rgb(120, 96, 80), { upper = rgb(236, 226, 200), hood = P.Steel, splash = rgb(214, 190, 150) })
	I:Fridge(IX1 - 1.6, F, -7.2, 90, P.Steel)
	I:Island(-4, F, -1, 90, 9, teal, rgb(236, 232, 222), rgb(150, 112, 78), 3)
	I:Dining(-14, F, -2, 90, 9, 4, 3, P.Walnut, P.White, { lamp = true })
	K:Spawn(-28, F, 2, -90)

	-- Master bedroom (back-left): the bed on the back wall, nightstands, the wardrobe on the left wall.
	I:Bed(-47.2, F, 10.8, -90, 9, 10, P.Walnut, P.White, rgb(52, 112, 116), { headColor = rgb(120, 96, 80), headMat = M.Fabric })
	I:Nightstand(-51, F, 16.6, -90, P.Walnut)
	K:Closet(-38, F, IZ1 - 1.5, 0, { mirror = -1 })
	-- Kids' room: bunk beds, a desk, toys.
	I:BunkBed(-29.1, F, 16.5, 0, rgb(200, 160, 110), rgb(60, 130, 200), rgb(232, 120, 150))
	I:Desk(-23.3, F, IZ1 - 1.6, 0, rgb(200, 160, 110), rgb(232, 120, 150), theme)
	I:Ball("ToyBall", -24, F + 1, 9.5, 2, rgb(232, 70, 60), M.SmoothPlastic, DETAIL)
	I:Rug(-25, F, 12, 0, 6, 5, rgb(250, 210, 90), { round = true })
	-- Bathroom.
	I:Bath(-14, F, IZ1 - 1.7, 0, { shower = true, tile = rgb(220, 232, 236), vanity = P.White })
	-- Den: a pool table, a jukebox glowing after dark, a dartboard, French doors to the patio.
	I:PoolTable(-1, F, 13, 90)
	local juke = I:Sub(IX1 - 1.6, F, 17.5, 90)
	juke:Box("Jukebox", -1.8, 1.8, 0, 6.5, -1.4, 1.4, rgb(120, 40, 40), M.Wood)
	juke:Neon(-1.6, 1.6, 4, 6.2, -1.5, -1.4, theme)
	I:Pipe("Dartboard", true, -7.75, -7.45, F + 6.8, 13, 2.2, P.Black, M.Fabric, HouseBuilder.DETAIL)
	I:Pipe("DartRing", true, -7.45, -7.4, F + 6.8, 13, 1.2, rgb(200, 40, 40), M.SmoothPlastic, HouseBuilder.DETAIL)

	-- Garage: three bays, a workbench, a chest freezer, golf bags, a ride-on mower.
	K:Bay(17, 0.4, -1, 0)
	K:Bay(30, 0.4, -1, 0)
	K:Bay(43, 0.4, -1, 0)
	G:Box("Workbench", GX1 - 3.4, GX1 - 1, 0.4, 4, 0, 12, P.Walnut, M.WoodPlanks)
	G:Box("Freezer", 12, 17, 0.4, 3.6, GZ1 - 3.4, GZ1 - 1, rgb(236, 236, 230), M.Metal)
	G:Cyl("GolfBag", 20, GZ1 - 2, 0.4, 4.4, 1.6, rgb(40, 80, 60), M.Fabric)
	local mower = G:Sub(34, 0.4, GZ1 - 3.4, 90)
	mower:Box("Mower", -1.8, 1.8, 0.8, 2.6, -2.6, 2.6, rgb(60, 140, 60), M.Metal)
	mower:Deco("MowerSeat", -1, 1, 2.6, 3.6, 0.4, 2, P.Black, M.Leather)
	K:GarageSign(30, 9.4, GZ1 - 1.3, 0, 14, 3.6)
	G:Box("GarageCeiling", GX0 + T, GX1 - T, GH - 0.3, GH, GZ0 + T, GZ1 - T, rgb(196, 190, 180), M.WoodPlanks)
	for _, x in ipairs({ 17, 30, 43 }) do
		local strip = G:Deco("StripLight", x - 3, x + 3, GH - 0.6, GH - 0.3, -2, 0, rgb(240, 248, 255), M.Neon)
		K:Light(strip, rgb(235, 242, 255), 24, 0.5)
	end

	K:SaleStand(-11, F, 3.5, -20, -10)
	K:ParkStand(30, 0.4, 9, 30, -16)
	K:Backdrop("suburb")
	K:Bounds(-56, 56, -36, 41, -2, 50)
end
