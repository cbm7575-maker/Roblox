-- BrickLoft (ModuleScript, ServerScriptService.Services.Houses.BrickLoft)
-- Rustwater Loft (Rustwater Docks): a two-storey brick warehouse turned loft. Ground floor: a one-car
-- garage behind a roller door, an industrial kitchen with a long table, steel stairs. Upstairs: one
-- open loft with a chesterfield lounge, a pool table, a bed nook and a bathroom behind a brick
-- partition, Edison bulbs on wires. Outside: factory windows, a rooftop water tower, a neon sign.
-- Drawn by HouseBuilder (lot frame: front = -Z); see HouseBuilder for the Kit.

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local BRICK = rgb(150, 74, 54)
local DARKBRICK = rgb(104, 52, 40)
local STEEL = rgb(52, 56, 62)
local CONCRETE = rgb(150, 148, 144)
local GLASS = rgb(170, 200, 190)

local F1, F2 = 1, 15 -- floor tops
local ROOF = 28 -- roof slab top

return function(K, def)
	local accent = def.Color
	local x0, x1, z0, z1 = -18, 18, -14, 14
	-- Slabs: garage floor (flush with the driveway), ground floor, upper floor with the stairwell.
	K:Solid(4, 0, z0, x1, 0.5, z1, CONCRETE, M.Concrete, { n = "GarageFloor" })
	K:Solid(x0, 0, z0, 4, F1, z1, CONCRETE, M.Concrete, { n = "Floor" })
	K:Slab(x0, z0, x1, z1, F2 - 1, F2, rgb(120, 86, 60), M.WoodPlanks, { -17.6, -2, -13.4, 11 })
	K:Solid(-22, -0.5, -24, 22, 0.5, z0, CONCRETE, M.Pavement, { n = "Path" })

	-- Ground floor walls: factory windows, the front door, the roller door opening.
	local factory = function(a, b, lo, hi, bars)
		return { a, b, lo, hi, glass = GLASS, mull = bars or 1, t = 0.45 }
	end
	K:Walls4(x0, z0, x1, z1, F1 - 1, F2 - 1, 1, BRICK, M.Brick, {
		front = { factory(2, 8, 4, 11, 2), { 10, 14, F1, F1 + 8.5 }, factory(16, 21, 4, 11, 2), { 23.5, 34.5, 0, 10.5 } },
		back = { factory(6, 14, 5, 11), factory(26, 32, 5, 11) },
		left = { factory(4, 10, 5, 11) },
		right = { factory(6, 12, 5, 11), factory(18, 24, 5, 11) },
	}, { frame = STEEL })
	K:Door(-6, F1, z0, 0, 4, 8.5, 1, { main = true, color = STEEL, mat = M.DiamondPlate })
	K:Box(-9, 10.2, -16.5, -3, 10.6, z0 - 0.5, STEEL, M.Metal, { n = "Awning" })
	K:GarageDoor(11, 0.5, z0, 0, 11, 10, rgb(120, 112, 104), M.CorrodedMetal)
	K:Neon(5, 11.2, z0 - 0.7, 17, 11.5, z0 - 0.5, accent)
	-- Party wall between the kitchen and the garage, with a doorway (one 0.5 step down).
	K:Wall(4, z0 + 0.5, 4, z1 - 0.5, F1, F2 - 1, 0.8, DARKBRICK, M.Brick, { { 18.5, 22.5, F1, F1 + 8 } })
	K:Bay(11, 0.5, -1, 0)
	K:BankPad(11, 0.5, 11, 9, 3, accent)
	K:Box(16.4, 0.5, 2, 17.5, 9, 10, rgb(70, 74, 80), M.DiamondPlate, { n = "ToolWall" })
	K:Box(15.2, 0.5, 3, 17.5, 3.4, 9, rgb(150, 110, 70), M.WoodPlanks, { n = "Workbench", c = true })
	K:Zone(4.5, 0.5, -13.5, 17.5, F2 - 1, 13.5)

	-- Upper storey walls: tall factory windows all round.
	K:Walls4(x0, z0, x1, z1, F2 - 1, ROOF - 1, 1, BRICK, M.Brick, {
		front = { factory(3, 11, F2 + 2, F2 + 10, 2), factory(14, 22, F2 + 2, F2 + 10, 2), factory(25, 33, F2 + 2, F2 + 10, 2) },
		back = { factory(4, 10, F2 + 3, F2 + 10), factory(26, 32, F2 + 3, F2 + 10) },
		left = { factory(6, 14, F2 + 2, F2 + 10) },
		right = { factory(4, 12, F2 + 2, F2 + 10), factory(16, 24, F2 + 2, F2 + 10) },
	}, { frame = STEEL })
	-- Brick bands: a dark course at the floor line and a cornice under the parapet.
	K:Box(x0 - 0.8, F2 - 1.2, z0 - 0.8, x1 + 0.8, F2 + 0.2, z0 - 0.5, DARKBRICK, M.Brick, { n = "Band" })
	K:Box(x0 - 0.8, F2 - 1.2, z1 + 0.5, x1 + 0.8, F2 + 0.2, z1 + 0.8, DARKBRICK, M.Brick, { n = "Band" })
	K:FlatRoof(x0, z0, x1, z1, ROOF - 1, rgb(70, 70, 76), M.Asphalt, 2, DARKBRICK, M.Brick, { over = 0.5 })
	-- Rooftop water tower and the neon sign on the parapet.
	for _, lx in ipairs({ -12, -6 }) do
		for _, lz in ipairs({ 3, 9 }) do
			K:Box(lx - 0.3, ROOF, lz - 0.3, lx + 0.3, ROOF + 6, lz + 0.3, STEEL, M.Metal, { n = "TowerLeg" })
		end
	end
	K:Post(-9, ROOF + 6, 6, ROOF + 13, 8.4, rgb(140, 100, 70), M.WoodPlanks, { n = "WaterTank" })
	K:Post(-9, ROOF + 13, 6, ROOF + 14.5, 6, rgb(90, 80, 74), M.CorrodedMetal, { n = "TankLid" })
	K:Box(-1, ROOF + 1, z0 - 0.4, 15, ROOF + 5, z0 + 0.2, rgb(30, 24, 30), M.Metal, { n = "LoftSign" })
	K:Neon(-1, ROOF + 1, z0 - 0.6, 15, ROOF + 1.3, z0 - 0.4, accent)
	K:Neon(-1, ROOF + 4.7, z0 - 0.6, 15, ROOF + 5, z0 - 0.4, accent)
	K:Banner(7, ROOF + 3, z0 - 0.45, 0, 15, 3.4, "RUSTWATER LOFTS", accent)
	-- Fire escape on the right wall (decoration).
	K:Box(x1 + 0.5, F2 - 0.4, -8, x1 + 4.5, F2, 4, STEEL, M.DiamondPlate, { n = "FireEscape" })
	K:Box(x1 + 4.3, F2, -8, x1 + 4.5, F2 + 3, 4, STEEL, M.Metal, { n = "FireEscapeRail" })
	K:Beam(x1 + 2.5, 5, 6, x1 + 2.5, F2, -6, 0.3, STEEL, M.Metal, { n = "FireLadder", w = 3 })

	-- Stairs: steel treads along the left wall up to the loft, with a rail round the stairwell.
	local run = K:Stairs(-15.6, -10, "+Z", 4, F1, F2, STEEL, M.DiamondPlate)
	K:Beam(-13.4, F1 + 3, -10, -13.4, F2 + 3, -10 + run, 0.3, accent, M.Neon, { n = "Handrail" })
	K:Rail(-13.4, -2, -13.4, 9.5, F2, 3, STEEL, { mat = M.Metal, every = 4 })
	K:Rail(-17.4, -2, -13.4, -2, F2, 3, STEEL, { mat = M.Metal, every = 4 })

	-- Ground floor: industrial kitchen and a long table.
	local I = K:In("Decor")
	I:Kitchen(-6.5, F1, 11.9, 0, 12, rgb(60, 64, 70), C.Steel, { topMat = M.Metal, cabMat = M.Metal, hood = C.Steel })
	I:Fridge(1.7, F1, 11.9, 0, C.Steel)
	I:Island(-3, F1, 4, 0, 8, rgb(110, 80, 56), CONCRETE, rgb(200, 120, 60), 3)
	I:DiningSet(-4, F1, -4.6, 0, 9, 4, 2, rgb(120, 84, 56), STEEL, { chairMat = M.Metal })
	I:Plant(-11, F1, -11.5, rgb(60, 64, 70), { tall = true })
	I:Art(-17.4, F1 + 6, 6, 270, 6, 4, STEEL, rgb(255, 150, 60), true)
	K:Light(-4, F2 - 2.5, 4, C.Warm, 24, 1.3, { n = "Edison", shape = "Ball", size = Vector3.new(1, 1, 1) })
	I:Beam(-4, F2 - 2, 4, -4, F2 - 1, 4, 0.1, C.Black, M.SmoothPlastic, { n = "Wire" })

	-- Loft: lounge at the front windows, pool table, bed nook, bathroom.
	I:Rug(-5, F2, -6.5, 0, 13, 9, rgb(140, 50, 50))
	I:Sofa(-5, F2, -3, 0, 8, rgb(110, 60, 36), { mat = M.Leather })
	I:Armchair(-11, F2, -7.5, 270, rgb(110, 60, 36), M.Leather)
	I:Table(-5, F2, -7.5, 0, 5, 3, 1.6, STEEL, M.Metal)
	I:TV(-5, F2, -12, 180, 6, { cabinet = rgb(110, 80, 56), glow = rgb(255, 120, 60) })
	I:Box(-14.5, F2, -13.3, -11.5, F2 + 3, -11.5, rgb(110, 80, 56), M.Wood, { n = "RecordShelf", c = true })
	I:Disc(-13, F2 + 3, -12.4, 2.2, 0.2, C.Black, M.SmoothPlastic, { n = "Record" })
	-- Pool table.
	I:Box(5, F2, -10, 11, F2 + 2.6, -6.5, rgb(90, 60, 40), M.Wood, { n = "PoolTable", c = true })
	I:Box(5.4, F2 + 2.6, -9.6, 10.6, F2 + 2.8, -6.9, rgb(30, 130, 70), M.Fabric, { n = "Felt" })
	I:Ball(6.5, F2 + 3.1, -8, 0.5, C.White, M.SmoothPlastic, { n = "Ball" })
	I:Ball(9, F2 + 3.1, -8.6, 0.5, rgb(220, 60, 60), M.SmoothPlastic, { n = "Ball" })
	I:Ball(9.3, F2 + 3.1, -7.6, 0.5, rgb(240, 200, 40), M.SmoothPlastic, { n = "Ball" })
	-- Bed nook at the back right, a clothes rail, and the bathroom behind a brick partition.
	I:Bed(-1, F2, 8.6, 0, 7, 9, STEEL, rgb(220, 220, 215), rgb(60, 70, 90), { frameMat = M.Metal, headMat = M.Brick, headColor = DARKBRICK })
	I:Nightstand(3.6, F2, 12, 0, rgb(110, 80, 56))
	I:Beam(-9, F2 + 6, 5, -9, F2 + 6, 11, 0.2, STEEL, M.Metal, { n = "ClothesRail" })
	for i = 0, 1 do
		I:Box(-9.4, F2 + 2.5, 5.6 + i * 1.3, -8.6, F2 + 6, 6.4 + i * 1.3, ({ rgb(200, 60, 60), rgb(60, 60, 70), rgb(230, 200, 120), rgb(70, 120, 180) })[i + 1], M.Fabric, { n = "Clothes" })
	end
	-- Bathroom behind brick partitions in the back right corner.
	K:Wall(5.5, 7.5, 17.5, 7.5, F2, ROOF - 1, 0.8, DARKBRICK, M.Brick, { { 1, 5, F2, F2 + 8 } })
	K:Wall(5.5, 7.1, 5.5, z1 - 0.5, F2, ROOF - 1, 0.8, DARKBRICK, M.Brick)
	I:Bath(11.6, F2, 11.8, 0, rgb(230, 230, 225))
	I:Plant(-13, F2, 12, rgb(60, 64, 70))
	I:Art(17.4, F2 + 6, -1, 90, 6, 4, STEEL, rgb(60, 200, 255), true)
	-- Edison bulbs hanging from the beams.
	for i, p in ipairs({ { -5, -6 }, { 8, -8 }, { 0, 4 } }) do
		I:Beam(p[1], ROOF - 1, p[2], p[1], ROOF - 4, p[2], 0.1, C.Black, M.SmoothPlastic, { n = "Wire" })
		K:Light(p[1], ROOF - 4.5, p[2], C.Warm, i == 1 and 26 or 20, 1.2, { n = "Edison", shape = "Ball", size = Vector3.new(1, 1, 1) })
	end
	for _, bz in ipairs({ -7, 0, 7 }) do
		I:Box(x0 + 0.5, ROOF - 2.2, bz - 0.5, x1 - 0.5, ROOF - 1, bz + 0.5, STEEL, M.Metal, { n = "Beam" })
	end
	K:Spawn(-5, F2, 1.5, 0)
	K:Zone(-17.5, F1, -13.5, 3.6, F2 - 1, 13.5)
	K:Zone(-17.5, F2, -13.5, 17.5, ROOF - 1, 13.5)

	-- Outside: driveway, pallets and barrels, a container planter, the sale sign.
	K:Solid(5, -0.5, -28, 17, 0.6, z0, rgb(90, 90, 96), M.Asphalt, { n = "Driveway" })
	for i = 0, 1 do
		K:Post(-20.5, 0.5, 8 + i * 2.4, 4, 2.2, ({ rgb(200, 80, 50), rgb(60, 110, 160), rgb(200, 80, 50) })[i + 1], M.Metal, { n = "Barrel" })
	end
	K:Box(-21.5, 0.5, -4, -18.5, 1.6, 2, rgb(160, 120, 80), M.WoodPlanks, { n = "Pallet" })
	K:Box(-21.6, 0.5, 15, -6, 3.5, 19.6, rgb(40, 110, 120), M.CorrodedMetal, { n = "ContainerPlanter", c = true })
	for i = 0, 2 do
		K:Bush(-18 + i * 5, 17.3, 3, rgb(70, 150, 80), 3.5)
	end
	K:Light(-6, 9.6, -15.4, C.Warm, 16, 1, { n = "DoorLamp", size = Vector3.new(1, 1, 0.6) })
	K:SaleSign(-15, -19.5, 0, def)
end
