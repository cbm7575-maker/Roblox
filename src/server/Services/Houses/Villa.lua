-- Villa (ModuleScript, ServerScriptService.Services.Houses.Villa)
-- Marina Row Villa: a two-storey white Mediterranean-modern villa on a stone plinth by the water,
-- terracotta roof, black iron balconies and pink neon. A three-car garage wing faces the street
-- beside a palm-lined motor court. Inside: marble floors, an open kitchen and dining room, a lounge
-- with a piano facing the marina; upstairs the master suite with a waterfront balcony and two more
-- bedrooms. Out back: a pool terrace with loungers, a pergola dining table and an outdoor bar.
-- Drawn by HouseBuilder (lot frame: front = -Z, the marina off to +X).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local WHITE = rgb(246, 242, 234)
local STONE = rgb(222, 206, 178)
local TILE = rgb(196, 98, 62)
local IRON = rgb(30, 30, 34)
local MARBLE = rgb(236, 232, 226)
local WOOD = rgb(120, 78, 50)

local F1, F2, TOP = 4.5, 17.5, 30.5

return function(K, def)
	local accent = def.Color
	local x0, x1, z0, z1 = -10, 40, -12, 20
	-- Plinth (house + pool terrace) and its stone face, the motor court, the garage.
	K:Solid(x0, 0, z0, x1, F1, z1, MARBLE, M.Marble, { n = "Floor" })
	K:Slab(-8, 20, 44, 38, 0, F1, STONE, M.Limestone, { 16, 24, 36, 36 }, { n = "Terrace" })
	K:Slab(x0, z0, x1, z1, F2 - 1, F2, MARBLE, M.Marble, { 22, -2, 26, 11.5 })
	K:Neon(-8.4, F1 - 0.4, 38.1, 44.4, F1 - 0.1, 38.4, accent)
	K:Neon(44.1, F1 - 0.4, 20, 44.4, F1 - 0.1, 38.4, accent)
	K:Solid(-6, 0, -40, 40, 0.5, z0, rgb(214, 200, 176), M.Cobblestone, { n = "Driveway" })
	K:Solid(-44, 0, -44, -6, 0.5, -38, rgb(214, 200, 176), M.Cobblestone, { n = "Driveway" })
	K:Solid(-44, 0, -38, -6, 0.5, -14, C.Concrete, M.Concrete, { n = "GarageFloor" })
	K:Stairs(14, -18.4, "+Z", 8, 0.5, F1, STONE, M.Limestone)

	-- House walls: tall windows, the front door, sliding doors to the terrace.
	local win = function(a, b, lo, hi, bars)
		return { a, b, lo, hi, glass = rgb(160, 205, 225), mull = bars or 1 }
	end
	K:Walls4(x0, z0, x1, z1, F1, F2 - 1, 0.8, WHITE, M.Plaster, {
		front = { win(4, 10, F1 + 2, F1 + 10), { 22, 26, F1, F1 + 9.5 }, win(32, 38, F1 + 2, F1 + 10), win(42, 47, F1 + 2, F1 + 10) },
		back = { win(4, 9, F1 + 3, F1 + 9), { 10, 16, F1, F1 + 9.5 }, { 37, 45, F1, F1 + 9.5 } },
		left = { win(6, 12, F1 + 2, F1 + 10), win(20, 26, F1 + 2, F1 + 10) },
		right = { win(3, 29, F1 + 1, F1 + 11, 4) },
	}, { trim = STONE, frame = IRON })
	K:Walls4(x0, z0, x1, z1, F2 - 1, TOP, 0.8, WHITE, M.Plaster, {
		front = { win(4, 10, F2 + 2, F2 + 10), win(17, 23, F2 + 2, F2 + 10), win(28, 34, F2 + 2, F2 + 10), win(40, 46, F2 + 2, F2 + 10) },
		back = { win(4, 10, F2 + 2, F2 + 10), win(17, 23, F2 + 2, F2 + 10), win(40, 46, F2 + 3, F2 + 9) },
		left = { win(8, 14, F2 + 2, F2 + 10) },
		right = { win(3, 6, F2 + 2, F2 + 10), { 7, 13, F2, F2 + 9.5 }, win(14, 22, F2 + 2, F2 + 10, 1) },
	}, { trim = STONE, frame = IRON })
	K:Door(14, F1, z0, 0, 4, 9.5, 0.8, { main = true, color = WOOD })
	K:Door(3, F1, z1, 180, 6, 9.5, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5 })
	K:Door(31, F1, z1, 180, 8, 9.5, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5 })
	K:Door(x1, F2, -2, 270, 6, 9.5, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5, noBlock = true })
	-- Entry canopy, waterfront balcony (black iron), roofs and neon under the eaves.
	K:Box(9, F1 + 10.5, -15, 19, F1 + 11.2, z0, WHITE, M.Plaster, { n = "Canopy", c = true })
	K:Neon(9, F1 + 10.3, -15.2, 19, F1 + 10.5, -14.9, accent)
	K:Solid(x1, F2 - 1, -10, 44, F2, 6, STONE, M.Limestone, { n = "Balcony" })
	K:Rail(44, -10, 44, 6, F2, 3.4, IRON, { mat = M.Metal, every = 2, mid = true })
	K:Rail(x1, -10, 44, -10, F2, 3.4, IRON, { mat = M.Metal, every = 2 })
	K:Rail(x1, 6, 44, 6, F2, 3.4, IRON, { mat = M.Metal, every = 2 })
	K:Gable(x0, z0, x1, z1, TOP, 6, true, TILE, M.ClayRoofTiles, WHITE, M.Plaster, { over = 1.8, cap = rgb(170, 84, 52) })
	K:Neon(x0 - 0.6, TOP - 0.6, z0 - 0.7, x1 + 0.6, TOP - 0.3, z0 - 0.5, accent)
	K:Box(x0 - 1, F1 - 0.6, z0 - 0.8, x1 + 1, F1, z1 + 0.8, STONE, M.Limestone, { n = "Plinth", c = true })

	-- Garage wing: three doors to the street, a flat roof edged in terracotta.
	K:Walls4(-44, -38, -6, -14, 0, 13, 0.8, WHITE, M.Plaster, {
		front = { { 1, 11, 0, 9 }, { 14, 24, 0, 9 }, { 26.5, 36.5, 0, 9 } },
		back = { win(14, 24, 5, 10) },
		left = { win(8, 16, 5, 10) },
	}, { trim = STONE, frame = IRON })
	K:FlatRoof(-44, -38, -6, -14, 13, WHITE, M.Plaster, 1.4, TILE, M.ClayRoofTiles, { over = 0.4 })
	for _, x in ipairs({ -38, -25, -12.5 }) do
		K:GarageDoor(x, 0.5, -38, 0, 10, 8.5, WOOD, M.WoodPlanks)
		K:Bay(x, 0.5, -26, 0)
		K:Neon(x - 5, 9.3, -38.6, x + 5, 9.6, -38.4, accent)
	end
	K:BankPad(-25, 0.5, -16, 14, 3, accent)
	K:Light(-25, 12.3, -26, C.Warm, 26, 1, { n = "GarageLight", size = Vector3.new(8, 0.3, 1) })
	K:Box(-43.4, 0.5, -30, -42, 8, -18, rgb(120, 100, 80), M.Wood, { n = "Shelves", c = true, q = false })
	K:Zone(-43.6, 0.5, -37.6, -6.4, 13, -14.4)

	-- Ground floor: dining and kitchen (west), foyer and stairs, lounge facing the marina (east).
	local I = K:In("Decor")
	local run = K:Stairs(24, -8, "+Z", 4, F1, F2, WOOD, M.Wood)
	K:Beam(21.8, F1 + 3.4, -8, 21.8, F2 + 3.4, -8 + run, 0.3, IRON, M.Metal, { n = "Handrail", c = true })
	K:Rail(22, -2, 22, 11.5, F2, 3.2, IRON, { mat = M.Metal, every = 4 })
	K:Rail(22, -2, 26, -2, F2, 3.2, IRON, { mat = M.Metal, every = 4 })
	I:DiningSet(0, F1, -4, 0, 11, 4.5, 3, WOOD, WHITE, { ends = true })
	I:Kitchen(-4, F1, 18.4, 0, 6, WHITE, rgb(60, 60, 66), { upper = WHITE, hood = C.Steel }) -- clear of the patio door (x 0..6)
	I:Fridge(-8, F1, 14, 90, C.Steel)
	I:Island(0, F1, 10, 0, 10, WOOD, MARBLE, accent, 3)
	I:Plant(-8.4, F1, -10.4, TILE, { tall = true })
	K:Light(0, F2 - 1.6, 2, C.Warm, 26, 1.1, { n = "Chandelier", shape = "Ball", size = Vector3.new(2, 2, 2) })
	I:Rug(33, F1, 2, 0, 11, 14, rgb(230, 220, 205))
	I:Sofa(30, F1, 2, 270, 12, WHITE, { pillows = accent })
	I:Armchair(35, F1, -6.5, 0, rgb(230, 180, 160))
	I:Table(34, F1, 2, 90, 5, 3, 1.6, WOOD, M.Wood)
	I:Box(35, F1, 12, 39.4, F1 + 3.2, 18, IRON, M.SmoothPlastic, { n = "Piano", c = true })
	I:Box(35, F1 + 3.2, 17, 39.4, F1 + 6, 18, IRON, M.SmoothPlastic, { n = "PianoLid" })
	I:Box(34, F1, 13.5, 34.8, F1 + 2, 16.5, IRON, M.Leather, { n = "PianoBench" })
	I:Art(26.6, F1 + 6, 2, 90, 6, 4, rgb(212, 175, 55), accent, true)
	K:Light(33, F2 - 1.6, 2, C.Warm, 26, 1.1, { n = "Chandelier", shape = "Ball", size = Vector3.new(2, 2, 2) })
	K:Spawn(37.5, F1, 5, 90)

	-- Upstairs: master suite to the east (balcony over the water), two bedrooms to the west.
	K:Wall(18, z0 + 0.4, 18, z1 - 0.4, F2, TOP, 0.6, WHITE, M.Plaster, { { 1, 6, F2, F2 + 9 }, { 22, 27, F2, F2 + 9 } })
	K:Wall(28, 12, 39.6, 12, F2, TOP, 0.6, WHITE, M.Plaster, { { 1, 5, F2, F2 + 9 } })
	K:Wall(-9.6, 4, 18, 4, F2, TOP, 0.6, WHITE, M.Plaster, { { 20, 25, F2, F2 + 9 } })
	I:Bed(33, F2, 0, 90, 9, 10, WOOD, WHITE, accent, { headColor = WHITE })
	I:Rug(32, F2, 0, 0, 12, 14, rgb(230, 220, 205), { mat = M.Carpet })
	I:Nightstand(27.6, F2, -5.5, 90, WOOD)
	I:Nightstand(27.6, F2, 5.5, 90, WOOD)
	I:Bath(34, F2, 18.3, 0, rgb(210, 230, 235))
	I:Box(18.6, F2, -11, 20.4, F2 + 7, -3, WOOD, M.Wood, { n = "Wardrobe", c = true })
	K:Light(32, TOP - 1, 0, C.Warm, 22, 1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4) })
	I:Bed(2, F2, -6.5, 180, 7, 9, WOOD, WHITE, rgb(80, 150, 200), {})
	I:Desk(12, F2, -9.5, 180, WOOD, IRON)
	I:Bed(2, F2, 14, 0, 7, 9, WOOD, WHITE, rgb(230, 170, 80), {})
	I:Bookshelf(12, F2, 18.8, 0, 6, 8, WHITE)
	I:Plant(16, F2, 13, TILE, { tall = true })
	K:Zone(-9.6, F1, -11.6, 39.6, F2 - 1, 19.6)
	K:Zone(-9.6, F2, -11.6, 39.6, TOP, 19.6)

	-- Pool terrace: pool, loungers, pergola dining, outdoor bar, balustrade.
	K:Pool(16, 24, 36, 36, F1, { glow = accent })
	for i, x in ipairs({ 19, 24, 29 }) do
		K:Lounger(x, F1 + 0.25, 21.5, 180, i == 2 and WHITE or accent)
	end
	K:Umbrella(39.5, F1 + 0.25, 30, WHITE)
	K:Lounger(41, F1 + 0.25, 35, 270, accent)
	for _, p in ipairs({ { -6, 23 }, { 10, 23 }, { -6, 35 }, { 10, 35 } }) do
		K:Box(p[1] - 0.5, F1, p[2] - 0.5, p[1] + 0.5, F1 + 10, p[2] + 0.5, WHITE, M.Plaster, { n = "PergolaPost", c = true })
	end
	for i = 0, 5 do
		K:Box(-6.6, F1 + 10, 23 + i * 2.4, 10.6, F1 + 10.5, 23.6 + i * 2.4, WOOD, M.Wood, { n = "PergolaSlat" })
	end
	K:Neon(-6.6, F1 + 9.6, 22.4, 10.6, F1 + 9.9, 22.6, accent)
	K:DiningSet(2, F1, 29, 0, 8, 4, 2, WOOD, WHITE)
	K:Box(-7.4, F1, 37, 1, F1 + 3.6, 37.6 + 0.2, WOOD, M.Wood, { n = "OutdoorBar", c = true })
	K:Box(-7.6, F1 + 3.6, 36.6, 1.2, F1 + 4, 37.8, MARBLE, M.Marble, { n = "BarTop" })
	K:Rail(-8, 38, 44, 38, F1, 3.5, WHITE, { mat = M.Plaster, every = 4 })
	K:Rail(44, 20, 44, 38, F1, 3.5, WHITE, { mat = M.Plaster, every = 4 })
	K:Rail(-8, 20, -8, 38, F1, 3.5, WHITE, { mat = M.Plaster, every = 4 })
	K:Rail(x1, 20, 44, 20, F1, 3.5, WHITE, { mat = M.Plaster, every = 4 })
	for _, p in ipairs({ { 42, 23 }, { -5, 37 }, { 14, 37 } }) do
		K:Post(p[1], F1, p[2], F1 + 2, 2.4, TILE, M.SmoothPlastic, { n = "Pot" })
		K:Palm(p[1], p[2], 0.5, F1 + 2)
	end

	-- Motor court: palms in planters, bougainvillea, the sale sign.
	for _, x in ipairs({ -2, 30 }) do
		K:Box(x - 3, 0.5, -30, x + 3, 2, -24, STONE, M.Limestone, { n = "Planter", c = true })
		K:Palm(x, -27, 0.8, 2)
	end
	for _, p in ipairs({ { -8, -10 }, { 38, -14 }, { 42, 12 }, { -12, 18 } }) do
		K:Bush(p[1], p[2], 3, rgb(240, 70, 150))
	end
	K:SaleSign(12, -37, 0, def)
end
