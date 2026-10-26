-- Loft (ModuleScript, ServerScriptService.Services.Houses.Loft)
-- Rustwater Loft ($25k, 2 cars): a red-brick net-and-rope warehouse on the docks turned into one big
-- loft. Outside: brick on a steel plinth, a rusty beam between the floors, steel factory windows (some
-- lit after dark), a roll-up loading door that is the garage, a steel canopy over the front door, a
-- fire escape, a sawtooth roof with glass teeth, a wooden water tank on steel legs (its hoop a neon ring
-- after dark) and the name on a rooftop sign outlined in neon; a concrete yard with crates, pallets,
-- drums and a forklift, and a walled back patio with string lights.
-- Inside, all one room: the garage behind a steel-and-glass screen (two cars), a double-height living
-- room under Edison bulbs on long wires, a kitchen and an island under the mezzanine, a long table, an
-- open steel stair up to the mezzanine with the bed, the wardrobe, a desk over the room and a bathroom
-- behind brick; a back door to the patio. Drawn by HouseBuilder (lot space: front = -Z).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local P, M, rgb = HouseBuilder.P, HouseBuilder.M, HouseBuilder.rgb
local DETAIL = HouseBuilder.DETAIL
local Row, Holes = HouseBuilder.Row, HouseBuilder.Holes

local X0, X1, Z0, Z1 = -42, 30, -12, 26 -- the building's outer faces
local T = 1.2 -- brick walls
local F = 0.6 -- living floor top (the garage floor is the yard's, 0.2)
local MEZ = 14 -- mezzanine floor top
local ROOF = 28 -- roof slab bottom
local GX = 3 -- the glass screen between the living room and the garage (x 2.5..3)

return function(K, home)
	local steel = home.Roof or rgb(58, 56, 66)
	local brick = home.Wall:Lerp(rgb(140, 82, 64), 0.5)
	local rust = home.Accent:Lerp(rgb(120, 78, 56), 0.4)
	local concrete = rgb(150, 148, 142)
	local trim, theme = home.Trim, home.Theme
	local door = K.door -- (-30, 0.6, -12)
	local wood = rgb(120, 86, 60)

	-- Ground: the concrete yard (painted bays in front of the loading door), the step up to the door.
	K.out.ground = K:Box("Yard", -55, 55, 0, 0.2, -35, 40, concrete, M.Concrete)
	for _, x in ipairs({ 1.5, 14, 26.5 }) do
		K:Deco("BayLine", x - 0.25, x + 0.25, 0.2, 0.22, -34, -14, rgb(220, 200, 90), M.SmoothPlastic)
	end
	K:Box("Stoop", door.X - 5, door.X + 5, 0.2, F, -16, Z0, concrete:Lerp(P.White, 0.2), M.Concrete)
	if K.inside then
		K:Box("Base", -60, 60, -2, 0, -40, 40, concrete, M.Concrete) -- (the copy's ground under the yard)
	end

	-- Shell ---------------------------------------------------------------------------------------------
	local S = K
	S:Ring(X0, X1, Z0, Z1, 0.2, 1.6, 0.3, steel, M.Metal, { front = { { door.X - 3.8, door.X + 3.8 }, { 0.8, 27.2 } }, back = { { -9, -3 } } })
	S:Ring(X0, X1, Z0, Z1, MEZ - 0.3, MEZ + 0.6, 0.3, rust, M.CorrodedMetal)
	local wo = { sill = steel, sillMat = M.Metal, bars = 2, transom = true, frame = steel }
	-- Front: the door, a big factory window into the living room, the loading door (garage), and a row
	-- of factory windows upstairs.
	S:WallX(Z0 + T / 2, X0, X1, 0.2, ROOF, T, brick, M.Brick, Holes(
		{ { door.X - 3, door.X + 3, F, F + 10, "none" }, { -22, -6, 3.5, 11.5, "win", bars = 3 }, { 2, 26, 0.2, 12.4, "none" } },
		Row(X0, X1, 5, 8, 16.5, 25, "win")
	), HouseBuilder.Merge(wo, { out = "-Z" }))
	S:WallX(Z1 - T / 2, X0, X1, 0.2, ROOF, T, brick, M.Brick, Holes(
		{ { -9, -3, F, F + 10, "exit", color = steel, mat = M.Metal } },
		Row(X0, -12, 2, 8, 3.5, 11.5, "win"), Row(4, X1, 2, 8, 3.5, 11.5, "win"),
		Row(X0, X1, 5, 8, 16.5, 25, "win")
	), HouseBuilder.Merge(wo, { out = "+Z" }))
	S:WallZ(X0 + T / 2, Z0 + T, Z1 - T, 0.2, ROOF, T, brick, M.Brick, {
		{ -6, 4, 3.5, 11.5, "win" }, { 10, 20, 16.5, 25, "win" },
	}, HouseBuilder.Merge(wo, { out = "-X", bars = 1 }))
	S:WallZ(X1 - T / 2, Z0 + T, Z1 - T, 0.2, ROOF, T, brick, M.Brick, Holes(
		Row(Z0 + T, Z1 - T, 3, 7, 7.5, 11.5, "win"),
		Row(Z0 + T, Z1 - T, 3, 7, 16.5, 25, "win")
	), HouseBuilder.Merge(wo, { out = "+X", bars = 1, transom = false }))
	S:FlatRoof(X0, X1, ROOF, Z0, Z1, rgb(84, 84, 88), M.Asphalt, 1.6, steel, M.Metal, 0.3)
	S:Neon(X0 - 0.3, X1 + 0.3, ROOF + 2.2, ROOF + 2.6, Z0 - 0.6, Z0 - 0.3, trim)

	-- The front door: steel, under a steel canopy on tie rods, wall lamps either side.
	K:FrontDoor(6, 10, T, steel, M.Metal, steel, M.Metal, { glass = false })
	S:Box("Canopy", door.X - 6, door.X + 6, F + 11.4, F + 12, Z0 - 6, Z0, steel, M.Metal)
	S:Neon(door.X - 6, door.X + 6, F + 11.2, F + 11.4, Z0 - 6, Z0 - 5.7, trim)
	S:Bar("TieRod", door.X - 5.5, F + 11.8, Z0 - 5.6, door.X - 5.5, F + 16, Z0, 0.2, steel, M.Metal)
	S:Bar("TieRod", door.X + 5.5, F + 11.8, Z0 - 5.6, door.X + 5.5, F + 16, Z0, 0.2, steel, M.Metal)
	S:WallLamp(door.X - 4.6, F + 7.5, Z0, P.Warm, 16)
	S:WallLamp(door.X + 4.6, F + 7.5, Z0, P.Warm)

	-- The loading door (the garage): a steel roll-up door in a steel frame under a rusty lintel, its
	-- slats, a yellow kerb either side, wall lamps.
	S:Box("GarageDoor", 2, 26, 0.2, 12.4, Z0, Z0 + 0.4, rgb(112, 114, 118), M.Metal)
	for i = 1, 7 do
		local y = 0.2 + i * 12.2 / 8
		S:Deco("Slat", 2, 26, y - 0.12, y + 0.12, Z0 - 0.2, Z0, rgb(84, 86, 92), M.Metal)
	end
	S:Deco("Lintel", 0.6, 27.4, 12.4, 13.6, Z0 - 0.5, Z0, rust, M.CorrodedMetal)
	S:Deco("DoorFrame", 0.8, 2, 0.2, 12.4, Z0 - 0.5, Z0, steel, M.Metal)
	S:Deco("DoorFrame", 26, 27.2, 0.2, 12.4, Z0 - 0.5, Z0, steel, M.Metal)
	for _, x in ipairs({ -0.6, 27.4 }) do
		S:Box("Kerb", x - 0.6, x + 0.6, 0.2, 1.2, Z0 - 3, Z0, rgb(220, 190, 40), M.Concrete, DETAIL)
	end
	S:WallLamp(-1.2, 10, Z0, P.Warm, 14)
	S:WallLamp(29, 10, Z0, P.Warm)

	-- Fire escape on the left side: a steel landing under the upper window, a stair down to the yard.
	S:Box("FireEscape", X0 - 5, X0, MEZ - 0.4, MEZ, 8, 22, steel, M.DiamondPlate)
	K:Rail(X0 - 5, 8, X0 - 5, 22, MEZ, 3.4, "posts", { color = steel })
	K:Rail(X0 - 5, 22, X0, 22, MEZ, 3.4, "posts", { color = steel })
	local run = K:Stairs(X0 - 2.5, 8 - 21, "+Z", 4, 0.2, MEZ, steel, M.DiamondPlate, { thin = 0.5 })
	S:Bar("Stringer", X0 - 4.6, 0.6, 8 - run, X0 - 4.6, MEZ, 8, 0.3, steel, M.Metal)
	S:Bar("Stringer", X0 - 0.4, 0.6, 8 - run, X0 - 0.4, MEZ, 8, 0.3, steel, M.Metal)
	S:Bar("Handrail", X0 - 4.6, 3.6, 8 - run, X0 - 4.6, MEZ + 3.4, 8, 0.25, steel, M.Metal)

	-- Sawtooth roof over the right half (three steel teeth, dark glass toward the street), the water tank
	-- on the left (a neon hoop after dark), two roof units and the rooftop name sign.
	for _, z in ipairs({ -8, 3, 14 }) do
		S:Wedge("Sawtooth", -8, 26, ROOF + 1, ROOF + 7, z, z + 11, steel, M.Metal, "+Z")
		S:Box("RoofGlass", -7, 25, ROOF + 1.4, ROOF + 6.4, z - 0.3, z, P.Glass, M.Glass, { Reflectance = 0.1 })
	end
	local tx, tz = -32, 16
	for _, o in ipairs({ { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }) do
		S:Box("TankLeg", tx + o[1] - 0.4, tx + o[1] + 0.4, ROOF + 1, ROOF + 9, tz + o[2] - 0.4, tz + o[2] + 0.4, steel, M.Metal)
	end
	S:Cyl("Tank", tx, tz, ROOF + 9, ROOF + 17, 9, rgb(120, 96, 76), M.WoodPlanks)
	S:Cyl("TankLid", tx, tz, ROOF + 17, ROOF + 18, 10, steel, M.Metal)
	HouseBuilder.NightNeon(S:Cyl("TankHoop", tx, tz, ROOF + 12.7, ROOF + 13.3, 9.3, P.TrimDay, M.Metal, DETAIL), trim)
	for _, x in ipairs({ -22, -14 }) do
		S:Box("RoofAC", x - 2.5, x + 2.5, ROOF + 1, ROOF + 3.4, 18, 23, rgb(158, 162, 168), M.Metal)
	end
	for _, x in ipairs({ -24, 4 }) do
		S:Deco("SignLeg", x - 0.4, x + 0.4, ROOF + 1, ROOF + 4, Z0 + 1.6, Z0 + 2.4, steel, M.Metal)
	end
	local roofSign = S:Box("RoofSign", -27, 7, ROOF + 4, ROOF + 10, Z0 + 1.7, Z0 + 2.3, P.Dark, M.Metal)
	HouseBuilder.SignGui(roofSign, Enum.NormalId.Front, string.upper(home.Name), nil, P.White)
	S:Neon(-27, 7, ROOF + 10, ROOF + 10.4, Z0 + 1.6, Z0 + 2.3, trim)
	S:Neon(-27, 7, ROOF + 3.6, ROOF + 4, Z0 + 1.6, Z0 + 2.3, trim)

	-- Yard: crates, a pallet stack, oil drums, a forklift, a bench by the door, bollards, the sign.
	local Y = K:In("Yard")
	Y:Box("Crate", 34, 38, 0.2, 4.2, -12, -8, rgb(156, 120, 82), M.WoodPlanks)
	Y:Box("Crate", 34.5, 37.5, 4.2, 7.2, -11.5, -8.5, rgb(136, 104, 72), M.WoodPlanks)
	Y:Box("Crate", 39, 42, 0.2, 3.2, -11, -8, rgb(136, 104, 72), M.WoodPlanks)
	for i = 0, 3 do
		Y:Box("Pallet", 45, 51, 0.2 + i * 0.7, 0.8 + i * 0.7, -12, -6, rgb(168, 134, 92), M.WoodPlanks, DETAIL)
	end
	for i, p in ipairs({ { 36, -2 }, { 39, -1 }, { 37.5, 1.6 } }) do
		Y:Cyl("Drum", p[1], p[2], 0.2, 3.8, 2.6, i == 2 and rgb(170, 60, 40) or rgb(40, 90, 130), M.Metal)
	end
	-- The forklift: body, counterweight, mast, forks, seat, overhead guard and four wheels.
	local FL = Y:Sub(46, 0.2, 8, 200)
	FL:Box("Forklift", -2.2, 2.2, 1, 4.2, -2.5, 3.5, rgb(232, 176, 30), M.Metal)
	FL:Box("Counterweight", -2.2, 2.2, 1, 5, 3.5, 4.5, rgb(52, 52, 56), M.Metal)
	FL:Deco("Seat", -1, 1, 4.2, 5, 0.5, 2.4, P.Black, M.Leather)
	FL:Deco("Mast", -1.8, -1.4, 1, 10, -3, -2.6, P.DarkMetal, M.Metal)
	FL:Deco("Mast", 1.4, 1.8, 1, 10, -3, -2.6, P.DarkMetal, M.Metal)
	FL:Deco("Fork", -1.5, -0.9, 0.6, 0.9, -7, -2.6, P.DarkMetal, M.Metal)
	FL:Deco("Fork", 0.9, 1.5, 0.6, 0.9, -7, -2.6, P.DarkMetal, M.Metal)
	FL:Deco("Guard", -2.2, 2.2, 8.6, 8.9, -2.6, 2.6, P.DarkMetal, M.Metal)
	for _, x in ipairs({ -2.2, 2.2 }) do
		FL:Deco("GuardPost", x - 0.15, x + 0.15, 4.2, 8.6, 2.3, 2.6, P.DarkMetal, M.Metal)
	end
	for _, w in ipairs({ { -2.3, -1.6 }, { 2.3, -1.6 }, { -2.3, 2.8 }, { 2.3, 2.8 } }) do
		FL:Pipe("Wheel", true, w[1] - 0.5, w[1] + 0.5, 0.9, w[2], 1.8, P.Black, M.SmoothPlastic, DETAIL)
	end
	Y:Box("Bench", -24, -16, 0.2, 2, -17, -15.5, wood, M.WoodPlanks)
	Y:Bollards({ { -6, -34 }, { 32, -34 } })
	K:StreetSign(-44, -31, steel, M.Metal)
	Y:Palm(-51, -24, 18, math.rad(77))
	Y:Palm(51, 30, 20, math.rad(154))

	-- Back patio, walled in brick: a steel table, a grill, plants, string lights.
	S:Box("PatioWall", X0, X1, 0.2, 9, 39, 40, brick, M.Brick)
	S:Box("PatioWall", X0, X0 + 1, 0.2, 9, Z1, 39, brick, M.Brick)
	S:Box("PatioWall", X1 - 1, X1, 0.2, 9, Z1, 39, brick, M.Brick)
	S:Deco("WallCap", X0, X1, 9, 9.4, 38.8, 40.2, steel, M.Metal)
	Y:Box("PatioTable", -20, -12, 2.8, 3.1, 30, 35, steel, M.DiamondPlate)
	Y:Deco("TableLeg", -16.3, -15.7, 0.2, 2.8, 32.2, 32.8, steel, M.Metal)
	Y:BBQ(10, 0.2, 36, 180)
	Y:StringLights(X0 + 1, 8.4, 30, X1 - 1, 8.4, 30, 12, P.Warm)
	Y:StringLights(X0 + 1, 8.4, 36, X1 - 1, 8.4, 36, 12, P.Warm)
	for _, x in ipairs({ -32, 0, 22 }) do
		Y:Plant(x, 0.2, 37.5, rgb(90, 90, 94))
	end

	if not K.inside then
		return
	end

	-- Inside ------------------------------------------------------------------------------------------------
	local R = K:In("Rooms")
	local I = K:In("Decor")
	local G = K:In("Garage")
	local IX0, IX1, IZ0, IZ1 = X0 + T, X1 - T, Z0 + T, Z1 - T -- the inner faces
	-- Floors: the garage is the yard's concrete (0.2) behind the loading door; the living floor a step up.
	R:Box("Floor", IX0, GX - 0.5, 0.2, F, IZ0, IZ1, rgb(170, 166, 158), M.Concrete)
	R:Box("Ceiling", IX0, IX1, ROOF - 0.6, ROOF, IZ0, IZ1, rgb(120, 96, 76), M.WoodPlanks)
	for _, z in ipairs({ -5, 4, 13, 22 }) do
		R:Deco("Joist", IX0, IX1, ROOF - 1.6, ROOF - 0.6, z - 0.4, z + 0.4, rgb(96, 74, 56), M.Wood)
	end
	-- The steel-and-glass screen to the garage, a doorway in the middle, brick above it.
	R:WallZ(GX - 0.25, IZ0, IZ1, F, 13, 0.5, steel, M.Metal, {
		{ IZ0, 6, F + 0.8, 12.4, "pane" }, { 6, 12, F, F + 9, "door" }, { 12, IZ1, F + 0.8, 12.4, "pane" },
	}, { out = "+X" })
	R:Box("ScreenTop", GX - 0.5, GX, 13, ROOF - 0.6, IZ0, IZ1, brick, M.Brick)
	R:Deco("StepEdge", GX - 0.5, GX + 0.3, 0.2, F, 6, 12, rgb(220, 190, 40), M.Metal)

	-- Mezzanine over the back-left (x -40.8..-14, z 8..24.8) and the open steel stair beside it.
	R:Box("Mezzanine", IX0, -14, MEZ - 1, MEZ, 8, IZ1, wood, M.WoodPlanks)
	R:Deco("MezzanineEdge", IX0, -14, MEZ - 1.4, MEZ, 7.7, 8, steel, M.Metal)
	for _, x in ipairs({ -14.6, -27.5 }) do
		R:Cyl("Column", x, 8.4, F, MEZ - 1, 1, steel, M.Metal)
	end
	local srun = K:Stairs(-11.8, -8, "+Z", 3.6, F, MEZ, steel, M.DiamondPlate, { thin = 0.6 })
	R:Bar("Handrail", -10, F + 3.4, -8, -10, MEZ + 3.4, -8 + srun, 0.25, steel, M.Metal)
	R:Bar("Stringer", -10, F, -8, -10, MEZ - 0.6, -8 + srun, 0.4, steel, M.Metal)
	K:Rail(IX0, 8, -14, 8, MEZ, 3.4, "glass", { color = steel })
	K:Rail(-14, 8, -14, 11.2, MEZ, 3.4, "glass", { color = steel })

	-- Living room: an L sofa facing the TV on the left wall under a neon script of the name, a rug, a
	-- coffee table, plants, an arcade cabinet and a punching bag.
	I:Rug(-28, F, 0, 0, 18, 14, rgb(150, 70, 60))
	I:Sofa(-22, F, 0.5, 90, 12, rgb(96, 70, 52), { mat = M.Leather, l = 4, pillows = theme:Lerp(rgb(120, 116, 110), 0.45), seats = 3 })
	I:Table(-29.5, F, 0.5, 0, 5, 8, 1.8, wood, M.WoodPlanks)
	I:TV(IX0 + 1.2, F, 0.5, -90, 10, { glow = theme })
	I:Sub(IX0 + 0.2, 0, 0.5, -90):Letters(0, 15, 0, 18, 3.6, home.Name, trim)
	I:Plant(-38, F, -9, rgb(90, 90, 94), { tall = true })
	I:Plant(-19, F, -9, rgb(90, 90, 94))
	I:Arcade(0, F, IZ1 - 1.6, 0, theme)
	I:Bar("BagChain", -1, ROOF - 0.6, -7.5, -1, 9, -7.5, 0.2, P.DarkMetal, M.Metal)
	I:Cyl("PunchingBag", -1, -7.5, 3.6, 9, 2.4, rgb(150, 30, 40), M.Leather, DETAIL)
	-- Kitchen on the back wall under the mezzanine, an island with stools, a long table to the right.
	I:Kitchen(-26, F, IZ1 - 1.4, 0, 16, rgb(52, 56, 62), rgb(214, 210, 200), { upper = rgb(52, 56, 62), hood = P.Steel, splash = rgb(236, 232, 222) })
	I:Fridge(-16, F, IZ1 - 1.6, 0, P.Steel)
	I:Island(-26, F, 15, 0, 10, wood, rgb(214, 210, 200), rgb(150, 30, 40), 3)
	I:Dining(-5, F, 8, 90, 10, 4, 3, wood, P.DarkMetal, { chairMat = M.Metal })
	-- Edison bulbs on long wires (always on, soft), and two lamps after dark.
	for i, p in ipairs({ { -26, -6 }, { -5, 8 }, { -20, 3 }, { -33, 2 }, { -5, -3 } }) do
		local y = 15 - (i % 2) * 2
		I:Bar("Wire", p[1], ROOF - 0.6, p[2], p[1], y + 0.4, p[2], 0.08, P.Black, M.SmoothPlastic)
		local bulb = I:Ball("Bulb", p[1], y, p[2], 0.9, rgb(255, 214, 150), M.Neon, DETAIL)
		if i <= 3 then
			K:Light(bulb, P.Warm, 28, 0.45)
		end
	end
	I:FloorLamp(-38, F, 4, P.Warm)
	K:Spawn(-6, F, -2, -90)

	-- Mezzanine: the wardrobe on the left wall, the bed on the back wall, a desk looking over the room,
	-- and the bathroom in brick at the right end.
	local up = MEZ
	K:Closet(IX0 + 1.5, up, 13, -90)
	I:Bed(-29, up, 19.4, 0, 9, 10, wood, P.White, rgb(62, 70, 84), { headColor = rgb(96, 70, 52), headMat = M.Leather, reading = P.Warm })
	I:Nightstand(-35.5, up, 23, 0, wood)
	I:Nightstand(-22.5, up, 23, 0, wood)
	I:Rug(-29, up, 11.5, 0, 10, 5, rgb(70, 76, 90))
	I:Desk(-24, up, 12, 0, wood, P.Black, theme)
	R:WallZ(-21, 14, IZ1, up, ROOF - 0.6, 0.8, brick, M.Brick, { { 14, 17.5, up, up + 9, "door" } }, { out = "-X" })
	R:WallX(14, -21.4, -14, up, ROOF - 0.6, 0.8, brick, M.Brick, {}, { out = "-Z" })
	R:Box("BathWall", -14.4, -14, up, ROOF - 0.6, 14.4, IZ1, brick, M.Brick)
	I:Bath(-16, up, 19.6, 90, { shower = true, tile = rgb(220, 220, 214) })
	K:CeilingLight(-29, 16, ROOF - 0.6, 3, 24, 0.5)

	-- Garage: two bays behind the loading door, a workbench and pegboard on the back wall, tyres, a tool
	-- chest, a stripe in the theme colour and the garage sign.
	K:Bay(9.5, 0.2, -1, 0)
	K:Bay(22.5, 0.2, -1, 0)
	G:Box("Workbench", 6, 18, 0.2, 3.6, IZ1 - 2.6, IZ1, wood, M.WoodPlanks)
	G:Deco("Pegboard", 5, 19, 5, 11, IZ1 - 0.2, IZ1, rgb(150, 120, 90), M.Wood)
	for i = 0, 5 do
		G:Deco("Tool", 6 + i * 2.2, 6.6 + i * 2.2, 6 + (i % 3), 9 + (i % 2), IZ1 - 0.5, IZ1 - 0.2, ({ P.Steel, rgb(176, 36, 44), P.DarkMetal })[i % 3 + 1], M.Metal)
	end
	G:Box("ToolChest", 21, 25, 0.2, 5, IZ1 - 2.4, IZ1, rgb(176, 36, 44), M.Metal)
	for i = 0, 2 do
		G:Cyl("Tyre", 26.6, 17, 0.2 + i * 1.3, 1.5 + i * 1.3, 4, P.Black, M.SmoothPlastic)
	end
	G:Deco("Stripe", GX, IX1, 3, 3.4, IZ1 - 0.1, IZ1, theme, M.SmoothPlastic)
	K:GarageSign(16, 14.5, IZ1 - 0.3, 0, 18, 5)
	for _, x in ipairs({ 9.5, 22.5 }) do
		local strip = G:Deco("StripLight", x - 4, x + 4, ROOF - 1.2, ROOF - 0.8, -2, 0, rgb(240, 248, 255), M.Neon)
		K:Light(strip, rgb(235, 242, 255), 30, 0.55)
	end

	-- A show copy: the FOR SALE stand inside the door (out of the exit prompt's reach), the garage sign.
	K:SaleStand(-17, F, -6, -30, -10)
	K:ParkStand(16, 0.2, 7, 16, -10)
	K:Backdrop("docks")
	K:Bounds(-58, 58, -38, 41, -2, 60)
end
