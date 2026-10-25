-- Townhouse (ModuleScript, ServerScriptService.Services.Houses.Townhouse)
-- Solana Heights Townhouse: a sleek white-and-charcoal modern box with cyan neon edges. Ground
-- floor: a two-car garage behind glass showroom doors, the kitchen and dining. Upstairs (it
-- cantilevers over the entry): a glass-fronted living room with a fireplace wall, the bedroom suite
-- and a bath. On the roof: a terrace with a hot tub, loungers, a pergola and glass railings.
-- Stairs scissor up the left side. Drawn by HouseBuilder (lot frame: front = -Z).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local WHITE = rgb(240, 240, 236)
local CHAR = rgb(54, 58, 66)
local WOOD = rgb(180, 130, 82)
local FLOOR = rgb(214, 208, 198)
local GLASS = rgb(150, 205, 230)

local F1, F2, R = 1, 14, 27 -- floor tops: ground, upstairs, roof terrace

return function(K, def)
	local accent = def.Color
	-- Slabs: ground, garage, upstairs (cantilevered to z = -18) and the roof, with stairwells.
	K:Solid(-26, 0, -14, 2, F1, 14, FLOOR, M.Marble, { n = "Floor" })
	K:Solid(2, 0, -14, 26, 0.5, 10, C.Concrete, M.Concrete, { n = "GarageFloor" })
	K:Slab(-26, -18, 26, 14, F2 - 1, F2, rgb(190, 150, 110), M.WoodPlanks, { -25.6, -8, -21.6, 3.5 })
	K:Slab(-26, -18, 26, 14, R - 1, R, rgb(176, 128, 84), M.WoodPlanks, { -21.6, 0, -17.6, 11.5 })
	K:Solid(3, -0.5, -40, 25, 0.5, -14, rgb(80, 82, 90), M.Asphalt, { n = "Driveway" })
	K:Box(-11, -0.4, -30, -5, 0.45, -14, rgb(200, 196, 190), M.Concrete, { n = "Path", c = true })

	-- Ground floor walls (the garage gets glass showroom doors).
	K:Walls4(-26, -14, 26, 14, 0, F2 - 1, 0.8, WHITE, M.Plaster, {
		front = { { 4, 14, F1 + 2, F1 + 10, glass = GLASS, mull = 2 }, { 16, 20, F1, F1 + 9 }, { 29, 39, 0, 9.5 }, { 41, 51, 0, 9.5 } },
		back = { { 5.5, 9.5, F1, F1 + 9 }, { 10, 22, F1 + 3, F1 + 10, glass = GLASS, mull = 2 }, { 32, 44, 5, 10, glass = GLASS } },
		left = { { 4, 12, F1 + 3, F1 + 10, glass = GLASS } },
		right = { { 6, 14, 5, 10, glass = GLASS } },
	}, { frame = CHAR })
	K:Door(-8, F1, -14, 0, 4, 9, 0.8, { main = true, color = WOOD })
	K:Box(-13, F1, -14.6, -10.6, F2 - 1, -14.3, WOOD, M.WoodPlanks, { n = "SlatPanel" })
	K:GarageDoor(8, 0.5, -14, 0, 10, 9, GLASS, M.Glass, { t = 0.35 })
	K:GarageDoor(20, 0.5, -14, 0, 10, 9, GLASS, M.Glass, { t = 0.35 })
	K:Wall(2, -13.6, 2, 9.6, F1, F2 - 1, 0.6, WHITE, M.Plaster)
	K:Wall(2.3, 10, 25.6, 10, 0, F2 - 1, 0.6, WHITE, M.Plaster)
	K:Bay(8, 0.5, -2, 0)
	K:Bay(20, 0.5, -2, 0)
	K:BankPad(14, 0.5, 7.4, 6, 3, accent)
	K:Neon(3, 0.55, -13, 25, 0.65, -12.6, accent)
	K:Light(14, F2 - 1.6, -2, rgb(220, 240, 255), 22, 1, { n = "GarageLight", size = Vector3.new(10, 0.3, 0.6) })
	K:Zone(2.4, 0.5, -13.6, 25.6, F2 - 1, 9.7)

	-- Upstairs: glass front over the cantilever, charcoal side panels.
	K:Walls4(-26, -18, 26, 14, F2, R - 1, 0.8, WHITE, M.Plaster, {
		front = { { 2, 50, F2 + 1, R - 2, glass = GLASS, mull = 5, t = 0.5 } },
		back = { { 8, 16, F2 + 3, F2 + 10, glass = GLASS }, { 30, 38, F2 + 3, F2 + 10, glass = GLASS } },
		left = { { 3, 13, F2 + 2, F2 + 10, glass = GLASS, mull = 1 } },
		right = { { 4, 12, F2 + 2, F2 + 10, glass = GLASS }, { 20, 28, F2 + 3, F2 + 10, glass = GLASS } },
	}, { frame = CHAR })
	K:Box(-26.6, F2 - 1, -18.6, 26.6, F2 - 0.2, -18.3, accent, M.Neon, { n = "Neon" })
	K:Box(-26.8, R - 1.2, -18.8, 26.8, R - 0.4, -18.2, CHAR, M.Slate, { n = "Fascia" })
	K:Box(-26.8, R - 1.2, 14.2, 26.8, R - 0.4, 14.8, CHAR, M.Slate, { n = "Fascia" })
	K:Box(-26.6, 0, -14.6, -24, F2 - 1, -14.3, CHAR, M.Slate, { n = "CornerPanel" })
	-- Roof terrace edge: low wall with glass on top, neon along it.
	for _, e in ipairs({ { -26.4, -18.4, 26.4, -17.6 }, { -26.4, 13.6, 26.4, 14.4 }, { -26.4, -17.6, -25.6, 13.6 }, { 25.6, -17.6, 26.4, 13.6 } }) do
		K:Solid(e[1], R, e[2], e[3], R + 1.2, e[4], CHAR, M.Slate, { n = "Parapet" })
	end
	K:Rail(-26, -18, 26, -18, R + 1.2, 2.8, CHAR, { glass = true })
	K:Rail(26, -18, 26, 14, R + 1.2, 2.8, CHAR, { glass = true })
	K:Rail(-26, -18, -26, 14, R + 1.2, 2.8, CHAR, { glass = true })
	K:Neon(-26.4, R + 1.2, -18.5, 26.4, R + 1.4, -18.3, accent)

	-- Stairs: flight 1 climbs to the front of the living room, flight 2 climbs to the roof.
	local run1 = K:Stairs(-23.6, 11.5, "-Z", 4, F1, F2, CHAR, M.Slate)
	local run2 = K:Stairs(-19.6, -8, "+Z", 4, F2, R, WOOD, M.Wood)
	K:Rail(-21.6, -8, -21.6, 3.5, F2, 3, CHAR, { glass = true })
	K:Rail(-25.6, 3.5, -21.6, 3.5, F2, 3, CHAR, { glass = true })
	K:Beam(-21.4, F1 + 3, 11.5, -21.4, F2 + 3, 11.5 - run1, 0.25, accent, M.Neon, { n = "Handrail" })
	K:Beam(-17.4, F2 + 3, -8, -17.4, R + 3, -8 + run2, 0.25, accent, M.Neon, { n = "Handrail" })
	-- Roof stair box, opening onto the terrace.
	K:Walls4(-22, -0.4, -17.2, 14, R, R + 10, 0.6, WHITE, M.Plaster, { right = { { 8.5, 13, R, R + 8.5 } } })
	K:FlatRoof(-22, -0.4, -17.2, 14, R + 10, CHAR, M.Slate, 0, nil, nil, { over = 0.6 })

	-- Ground floor: kitchen, island, dining.
	local I = K:In("Decor")
	I:Kitchen(-9, F1, 12.4, 0, 12, CHAR, WHITE, { upper = WHITE })
	I:Fridge(-0.2, F1, 12, 0, C.Steel)
	I:Island(-9, F1, 5, 0, 8, WHITE, CHAR, accent, 3)
	I:DiningSet(-12, F1, -6.5, 90, 7, 4, 2, WOOD, CHAR)
	I:Plant(-1, F1, -12.5, CHAR, { tall = true })
	I:Art(-25.4, F1 + 6, -6, 270, 6, 4, CHAR, rgb(255, 90, 180), true)
	K:Light(-9, F2 - 1.6, 1, rgb(220, 240, 255), 26, 1.1, { n = "LinearLight", size = Vector3.new(10, 0.3, 0.6) })

	-- Upstairs living room: sectional facing the fireplace wall, the city view behind.
	K:Wall(-17.2, -3, 25.6, -3, F2, R - 1, 0.6, CHAR, M.Slate, { { 4, 9, F2, F2 + 9 } })
	I:Fireplace(6, F2, -3.4, 180, CHAR, { mat = M.Slate, mantle = CHAR })
	I:TV(6, F2, -3.2, 180, 8, { wall = true, at = 7.5, glow = rgb(40, 200, 255) })
	I:Rug(6, F2, -10, 0, 16, 10, rgb(230, 228, 222))
	I:Sofa(4, F2, -13.5, 180, 12, WHITE, { l = 4, pillows = accent })
	I:Table(6, F2, -9, 0, 6, 3.5, 1.6, WOOD, M.Wood)
	I:Armchair(16, F2, -9, 90, CHAR, M.Leather)
	I:Plant(22, F2, -16, CHAR, { tall = true })
	I:Box(-16, F2, -16.8, -9, F2 + 3, -15, WOOD, M.Wood, { n = "Bar", c = true })
	for i = 0, 2 do
		I:Disc(-14.5 + i * 2.5, F2 + 2.2, -13.5, 1.4, 0.4, accent, M.Leather, { n = "Stool" })
	end
	K:Light(6, R - 1.5, -10, rgb(255, 240, 220), 26, 1.1, { n = "LinearLight", size = Vector3.new(10, 0.3, 0.6) })
	-- Bedroom suite behind the fireplace wall; the bath in a glass box.
	I:Bed(4, F2, 9.3, 0, 8, 9, CHAR, WHITE, rgb(70, 80, 100), { headColor = WOOD })
	I:Nightstand(-1.5, F2, 12.6, 0, WOOD, accent)
	I:Nightstand(9.5, F2, 12.6, 0, WOOD, accent)
	I:Rug(4, F2, 7, 0, 12, 8, rgb(70, 80, 100), { mat = M.Carpet })
	I:Desk(-12, F2, 10, 0, WOOD, CHAR)
	K:Wall(14, 2, 14, 13.6, F2, R - 1, 0.4, GLASS, M.Glass, { { 1, 5, F2, F2 + 9 } })
	I:Bath(20, F2, 12, 0, rgb(230, 230, 225))
	K:Light(4, R - 1.5, 5, rgb(255, 230, 210), 20, 0.9, { n = "LinearLight", size = Vector3.new(6, 0.3, 0.6) })
	K:Spawn(-9, F2, -8, 270)
	K:Zone(-25.6, F1, -13.6, 1.7, F2 - 1, 13.6)
	K:Zone(-25.6, F2, -17.6, 25.6, R - 1, 13.6)
	K:Zone(-21.7, R, -0.1, -17.5, R + 10, 13.7)

	-- Roof terrace: hot tub, loungers, pergola, planters.
	local T = K:In("Yard")
	-- Hot tub: a raised wooden tub you can climb into (the water is a glowing surface).
	T:Solid(3, R, -15, 13, R + 0.6, -5, WOOD, M.WoodPlanks, { n = "HotTubFloor" })
	T:Solid(3, R + 0.6, -15, 13, R + 3, -14.2, WOOD, M.WoodPlanks, { n = "HotTubWall" })
	T:Solid(3, R + 0.6, -5.8, 13, R + 3, -5, WOOD, M.WoodPlanks, { n = "HotTubWall" })
	T:Solid(3, R + 0.6, -14.2, 3.8, R + 3, -5.8, WOOD, M.WoodPlanks, { n = "HotTubWall" })
	T:Solid(12.2, R + 0.6, -14.2, 13, R + 3, -5.8, WOOD, M.WoodPlanks, { n = "HotTubWall" })
	T:Box(3.8, R + 2.1, -14.2, 12.2, R + 2.4, -5.8, rgb(60, 210, 240), M.Glass, { n = "TubWater", t = 0.25 })
	T:Box(3.8, R + 0.6, -14.2, 12.2, R + 0.7, -5.8, accent, M.Neon, { n = "TubGlow" })
	T:Stairs(8, -0.4, "-Z", 4, R, R + 3, WOOD, M.Wood)
	T:Lounger(17, R, -12, 0, accent)
	T:Lounger(21, R, -12, 0, accent)
	T:Umbrella(19, R, -5, WHITE)
	T:Sofa(-8, R, -12, 0, 8, CHAR, { mat = M.Fabric, pillows = accent })
	T:Table(-8, R, -15.5, 0, 5, 2.5, 1.5, WOOD, M.Wood)
	for _, x in ipairs({ -14, -2 }) do
		T:Box(x - 0.4, R, -1.4, x + 0.4, R + 9, -0.6, WOOD, M.Wood, { n = "PergolaPost" })
	end
	for i = 0, 4 do
		T:Box(-14.6, R + 9, -10 + i * 2.3, -1.4, R + 9.5, -9.4 + i * 2.3, WOOD, M.Wood, { n = "PergolaSlat" })
	end
	T:Box(-14.6, R + 8.6, -1.2, -1.4, R + 8.9, -0.8, accent, M.Neon, { n = "PergolaNeon" })
	for _, x in ipairs({ -12, 0, 12, 22 }) do
		T:Box(x - 2, R, 10, x + 2, R + 2, 13, CHAR, M.Slate, { n = "Planter" })
		T:Bush(x, 11.5, 3, rgb(70, 160, 90), R + 2)
	end

	-- Back courtyard behind a white wall; front palms and the sale sign.
	K:Solid(-26.4, 0, 28.6, 26.4, 8.5, 29.4, WHITE, M.Plaster, { n = "YardWall" })
	K:Solid(-26.4, 0, 14, -25.6, 8.5, 28.6, WHITE, M.Plaster, { n = "YardWall" })
	K:Solid(25.6, 0, 14, 26.4, 8.5, 28.6, WHITE, M.Plaster, { n = "YardWall" })
	K:Box(-25.6, 0, 14.4, 25.6, 0.2, 28.6, rgb(225, 220, 210), M.Pebble, { n = "Gravel" })
	K:Palm(-18, 22, 0.8)
	K:Palm(16, 21, 0.7)
	K:Box(-6, 0.2, 18, 6, 1, 24, rgb(60, 66, 74), M.Slate, { n = "Bench", c = true })
	K:Door(-18.5, F1, 14, 180, 4, 9, 0.8, { color = WOOD }) -- courtyard (doorway x -20.5..-16.5)
	K:Palm(-21, -24, 0.75)
	K:Bush(-15, -15.5, 2.4, rgb(70, 160, 90))
	K:Bush(-2, -15.5, 2.4, rgb(70, 160, 90))
	K:SaleSign(-19, -27.5, 0, def)
end
