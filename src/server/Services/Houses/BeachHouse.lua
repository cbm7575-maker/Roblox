-- BeachHouse (ModuleScript, ServerScriptService.Services.Houses.BeachHouse)
-- Flamingo Beach House: a tropical-modern two-storey house of white stucco and pale wood under a
-- butterfly roof, flamingo-pink neon, on a raised deck by the sand. A four-car garage with a rooftop
-- sun deck, a pool and a spa on the deck, and a beach yard with a thatched tiki bar, a cabana, a
-- fire pit, a volleyball net, surfboards and hammocks. Inside: an open great room with an aquarium
-- wall and an egg chair facing the ocean; upstairs the master suite and a bunk room for guests.
-- Drawn by HouseBuilder (lot frame: front = -Z, the ocean off to +X).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local WHITE = rgb(248, 246, 240)
local WOOD = rgb(212, 176, 126)
local DECK = rgb(186, 140, 96)
local THATCH = rgb(214, 182, 112)
local SAND = rgb(240, 220, 170)
local TEAL = rgb(40, 170, 170)
local GLASS = rgb(160, 215, 230)

local F1, F2, TOP = 4.5, 17.5, 30.5

return function(K, def)
	local accent = def.Color
	local x0, x1, z0, z1 = 2, 48, -20, 14
	-- Plinth, pool deck (pool + spa cut out), upstairs slab, the entry court and garage floor.
	K:Solid(x0, 0, z0, x1, F1, z1, rgb(230, 225, 215), M.Limestone, { n = "Floor" })
	K:Deck(-48, -16.6, x0, z1, 0, F1, DECK, M.WoodPlanks, { { -40, -8, -12, 4 }, { -8, -4, 0, 4 } })
	K:Pool(-40, -8, -12, 4, F1, { glow = accent })
	K:Pool(-8, -4, 0, 4, F1, { glow = rgb(255, 200, 80), step = false })
	K:Slab(x0, z0, x1, z1, F2 - 1, F2, WOOD, M.WoodPlanks, { 2.4, -3.5, 6.4, 7.5 })
	K:Solid(2, 0, -45, 48, 0.5, z0, rgb(225, 215, 190), M.Pavement, { n = "Driveway" })
	K:Solid(-50, 0, -52, -2, 0.5, -17, C.Concrete, M.Concrete, { n = "Driveway" })
	K:Stairs(14, -26.4, "+Z", 8, 0.5, F1, WHITE, M.Limestone)
	K:Neon(x0 - 0.3, F1 - 0.5, z0 - 0.3, x1 + 0.3, F1 - 0.2, z0 - 0.1, accent)

	-- Walls: big glass to the ocean (+X), the front door, sliding doors to the deck and the beach.
	local win = function(a, b, lo, hi, bars)
		return { a, b, lo, hi, glass = GLASS, mull = bars or 1 }
	end
	K:Walls4(x0, z0, x1, z1, F1, F2 - 1, 0.8, WHITE, M.Plaster, {
		front = { win(2, 8, F1 + 2, F1 + 10), { 10, 14, F1, F1 + 9.5 }, win(18, 30, F1 + 4.5, F1 + 9.5, 2), win(34, 44, F1 + 2, F1 + 10, 1) },
		back = { win(4, 10, F1 + 2, F1 + 10), { 26, 34, F1, F1 + 9.5 } },
		left = { win(2, 8, F1 + 2, F1 + 10), { 20, 26, F1, F1 + 9.5 } },
		right = { win(2, 32, F1 + 1, F1 + 11, 5) },
	}, { frame = WOOD })
	K:Walls4(x0, z0, x1, z1, F2 - 1, TOP - 2, 0.8, WOOD, M.WoodPlanks, {
		front = { win(4, 12, F2 + 2, F2 + 9), win(18, 28, F2 + 2, F2 + 9), win(34, 42, F2 + 2, F2 + 9) },
		back = { win(4, 12, F2 + 2, F2 + 9), win(20, 26, F2 + 2, F2 + 9), win(32, 42, F2 + 2, F2 + 9) },
		left = { win(10, 24, F2 + 2, F2 + 9, 2) },
		right = { win(2, 12, F2 + 1, F2 + 10), { 13, 19, F2, F2 + 9.5 }, win(20, 32, F2 + 1, F2 + 10) },
	}, { frame = WHITE })
	K:Door(14, F1, z0, 0, 4, 9.5, 0.8, { main = true, color = TEAL })
	K:Door(x0, F1, 3, 90, 6, 9.5, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5 })
	K:Door(32, F1, z1, 180, 8, 9.5, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5 })
	K:Door(x1, F2, -4, 270, 6, 9.5, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5, noBlock = true })
	K:Solid(x1, F2 - 1, -9, 50, F2, 1, WOOD, M.WoodPlanks, { n = "Balcony" })
	K:Rail(50, -9, 50, 1, F2, 3.2, WHITE, { glass = true })
	-- Butterfly roof: two wood-soffit slopes dipping to a valley over the middle.
	K:Sub(13.5, 0, -3, 90):Shed(-18.6, -11.5, 18.6, 11.5, TOP - 2, 3, WHITE, M.SmoothPlastic, { over = 1.6 })
	K:Sub(36.5, 0, -3, 90):Shed(-18.6, -11.5, 18.6, 11.5, TOP - 2, 3, WHITE, M.SmoothPlastic, { over = 1.6, flip = true })
	K:Neon(x0 - 1.4, TOP - 2.6, z0 - 1.8, x1 + 1.4, TOP - 2.3, z0 - 1.6, accent)
	-- Steps down from the house's beach door and from the pool deck to the sand.
	K:Stairs(32, 14.4, "+Z", 8, 0, F1, DECK, M.WoodPlanks)
	K:Stairs(-30, 14.4, "+Z", 6, 0, F1, DECK, M.WoodPlanks)
	K:Rail(-48, 14, -33, 14, F1, 3.5, WHITE, { every = 5 })
	K:Rail(-27, 14, x0, 14, F1, 3.5, WHITE, { every = 5 })
	K:Rail(-48, -16.6, -48, 14, F1, 3.5, WHITE, { every = 6 })

	-- Garage: four bays under a sun deck you climb to from the pool deck.
	K:Walls4(-50, -43, -2, -17, 0, 13, 0.8, WHITE, M.Plaster, {
		front = { { 1, 11, 0, 9 }, { 13, 23, 0, 9 }, { 25, 35, 0, 9 }, { 37, 47, 0, 9 } },
		back = { win(6, 14, 5, 10) },
		left = { win(8, 18, 5, 10) },
	}, { frame = WOOD })
	K:FlatRoof(-50, -43, -2, -17, 13, WOOD, M.WoodPlanks, 0, nil, nil, { over = 0.4 })
	for _, x in ipairs({ -44, -32, -20, -8 }) do
		K:GarageDoor(x, 0.5, -43, 0, 10, 8.5, WOOD, M.WoodPlanks)
		K:Bay(x, 0.5, -30, 0)
		K:Neon(x - 5, 9.3, -43.6, x + 5, 9.6, -43.4, accent)
	end
	K:BankPad(-26, 0.5, -19.6, 16, 3, accent)
	K:Light(-26, 12.4, -30, C.Warm, 28, 1, { n = "GarageLight", size = Vector3.new(10, 0.3, 1) })
	K:Box(-49.4, 0.5, -38, -48, 8, -22, rgb(120, 100, 80), M.Wood, { n = "SurfRack", c = true, q = false })
	for i = 0, 2 do
		K:Box(-48, 2, -36 + i * 5, -47.6, 9, -33 + i * 5, ({ accent, TEAL, rgb(250, 200, 80) })[i + 1], M.SmoothPlastic, { n = "Surfboard" })
	end
	K:Zone(-49.6, 0.5, -42.6, -2.4, 13, -17.4)
	local run = K:Stairs(-8, -15, "-X", 3.6, F1, 14, WOOD, M.WoodPlanks)
	K:Rail(-8, -13.2, -8 - run, -13.2, F1, 3, WHITE, { every = 7 })
	K:Rail(-50, -43, -2, -43, 14, 3.2, WHITE, { glass = true })
	K:Rail(-50, -43, -50, -17, 14, 3.2, WHITE, { glass = true })
	K:Rail(-2, -43, -2, -17, 14, 3.2, WHITE, { glass = true })
	K:Rail(-50, -17, -8 - run - 1, -17, 14, 3.2, WHITE, { glass = true })
	K:Lounger(-40, 14, -26, 0, accent)
	K:Lounger(-35, 14, -26, 0, TEAL)
	K:Umbrella(-37.5, 14, -33, accent)
	K:Box(-20, 14, -36, -10, 14.6, -26, rgb(250, 240, 220), M.Fabric, { n = "DayBed" })

	-- Inside, ground floor: great room facing the ocean, kitchen, dining, aquarium wall.
	local I = K:In("Decor")
	local srun = K:Stairs(4.4, -12, "+Z", 4, F1, F2, WOOD, M.WoodPlanks, { thin = 0.8 })
	K:Rail(6.4, -3.5, 6.4, 7.5, F2, 3, WHITE, { glass = true })
	K:Rail(2.4, -3.5, 6.4, -3.5, F2, 3, WHITE, { glass = true })
	K:Beam(6.6, F1 + 3, -12, 6.6, F2 + 3, -12 + srun, 0.25, accent, M.Neon, { n = "Handrail" })
	I:Kitchen(24, F1, -18.3, 180, 12, WHITE, WOOD, {})
	I:Fridge(32, F1, -18, 180, C.Steel)
	I:Island(24, F1, -10, 180, 10, TEAL, WHITE, accent, 3)
	I:DiningSet(19, F1, 4, 0, 12, 4.5, 4, WOOD, WHITE)
	I:Rug(38, F1, -2, 0, 14, 16, rgb(240, 230, 210))
	I:Sofa(38, F1, 5.5, 0, 12, WHITE, { l = 5, pillows = accent })
	I:Table(38, F1, 0, 0, 6, 3.5, 1.6, WOOD, M.Wood)
	I:TV(38, F1, 12.8, 0, 8, { wall = true, at = 5, glow = rgb(60, 200, 255) })
	-- Egg chair hanging by the ocean glass.
	I:Beam(44, F2 - 1, -12, 44, F1 + 6, -12, 0.15, C.Black, M.SmoothPlastic, { n = "ChairRope" })
	I:Ball(44, F1 + 4, -12, 4, WHITE, M.Fabric, { n = "EggChair" })
	I:Ball(44, F1 + 3.6, -12.6, 2.6, accent, M.Fabric, { n = "EggCushion" })
	-- Aquarium on the back wall.
	I:Box(12, F1 + 2, 12, 26, F1 + 8, 13.6, rgb(30, 120, 200), M.Glass, { n = "Aquarium", t = 0.3 })
	I:Box(12.2, F1 + 2.1, 12.6, 25.8, F1 + 7.8, 12.8, rgb(40, 200, 230), M.Neon, { n = "AquariumGlow", t = 0.6 })
	for i, c in ipairs({ rgb(255, 140, 40), rgb(255, 220, 60), accent, rgb(255, 140, 40) }) do
		I:Ball(14 + i * 2.6, F1 + 3.5 + (i % 2) * 2, 12.4, 0.8, c, M.Neon, { n = "Fish" })
	end
	I:Plant(46, F1, 12, TEAL, { tall = true })
	K:Light(19, F2 - 1.6, -4, C.Warm, 26, 1.1, { n = "Pendant", shape = "Ball", size = Vector3.new(1.6, 1.6, 1.6) })
	K:Light(38, F2 - 1.6, 0, C.Warm, 26, 1.1, { n = "Pendant", shape = "Ball", size = Vector3.new(1.6, 1.6, 1.6) })
	K:Spawn(38, F1, -6, 90)

	-- Upstairs: master suite to the ocean, a bunk room, a lounge, the bath.
	K:Wall(30, z0 + 0.4, 30, z1 - 0.4, F2, TOP - 2, 0.6, WHITE, M.Plaster, { { 20.6, 25.6, F2, F2 + 9 } })
	K:Wall(6.6, 0, 29.7, 0, F2, TOP - 2, 0.6, WHITE, M.Plaster, { { 14, 19, F2, F2 + 9 } })
	I:Bed(39.5, F2, -6, 270, 9, 10, WOOD, WHITE, accent, { headColor = WHITE })
	I:Nightstand(34.6, F2, -12, 270, WOOD)
	I:Nightstand(34.6, F2, 0, 270, WOOD)
	I:Bath(39, F2, 12.3, 0, rgb(200, 235, 235))
	I:Armchair(44, F2, -16, 315, TEAL)
	K:Light(39, TOP - 3, -4, C.Warm, 22, 1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4) })
	I:BunkBed(12, F2, -15, 90, WOOD, TEAL, accent)
	I:BunkBed(24, F2, -15, 90, WOOD, rgb(250, 200, 80), TEAL)
	I:Rug(18, F2, -8, 0, 12, 7, accent, { round = false })
	I:Sofa(18, F2, 10.5, 0, 10, TEAL, { pillows = WHITE })
	I:Ball(13, F2 + 1.2, 4, 3, accent, M.Fabric, { n = "Beanbag" })
	I:Ball(23, F2 + 1.2, 4, 3, rgb(250, 200, 80), M.Fabric, { n = "Beanbag" })
	K:Zone(2.4, F1, -19.6, 47.6, F2 - 1, 13.6)
	K:Zone(2.4, F2, -19.6, 47.6, TOP - 2, 13.6)

	-- Pool deck furniture.
	for i, x in ipairs({ -38, -33, -28, -23 }) do
		K:Lounger(x, F1 + 0.25, -12.5, 180, i % 2 == 0 and TEAL or accent)
	end
	K:Umbrella(-44, F1 + 0.25, -2, accent)
	K:Umbrella(-18, F1 + 0.25, 9, TEAL)
	K:Lounger(-44, F1 + 0.25, 8, 0, WHITE)
	K:Post(-46, F1, -14, F1 + 2, 2.4, TEAL, M.SmoothPlastic, { n = "Pot" })
	K:Palm(-46, -14, 0.5, F1 + 2)

	-- Beach yard: tiki bar, cabana, fire pit, volleyball, hammock, palms, outdoor shower.
	local Y = K:In("Yard")
	Y:Box(-48, 0, z1, 50, 0.1, 45, SAND, M.Sand, { n = "Sand" })
	for _, p in ipairs({ { 22, 27 }, { 34, 27 }, { 22, 37 }, { 34, 37 } }) do
		Y:Box(p[1] - 0.5, 0, p[2] - 0.5, p[1] + 0.5, 9, p[2] + 0.5, rgb(150, 110, 70), M.Wood, { n = "TikiPost" })
	end
	Y:Gable(20.5, 25.5, 35.5, 38.5, 9, 4, true, THATCH, M.Grass, THATCH, M.Grass, { over = 1.2, th = 1 })
	Y:Box(23, 0, 28, 33, 3.6, 30, rgb(150, 110, 70), M.WoodPlanks, { n = "TikiBar", c = true })
	Y:Box(22.6, 3.6, 27.4, 33.4, 4, 30.2, THATCH, M.Wood, { n = "BarTop" })
	for i = 0, 3 do
		Y:Disc(24 + i * 2.8, 2.6, 26.4, 1.5, 0.4, accent, M.Fabric, { n = "Stool" })
		Y:Post(24 + i * 2.8, 0, 26.4, 2.6, 0.4, rgb(150, 110, 70), M.Wood, { n = "StoolLeg" })
	end
	Y:Box(24, 4, 35.5, 32, 7.5, 36.5, rgb(150, 110, 70), M.WoodPlanks, { n = "BackBar" })
	Y:Banner(28, 7.6, 25.4, 0, 9, 1.8, "TIKI BAR", accent)
	K:Light(28, 8, 32, rgb(255, 180, 90), 26, 1.1, { n = "TikiLamp", shape = "Ball", size = Vector3.new(1, 1, 1) })
	-- Cabana with white curtains.
	for _, p in ipairs({ { -40, 24 }, { -30, 24 }, { -40, 34 }, { -30, 34 } }) do
		Y:Box(p[1] - 0.4, 0, p[2] - 0.4, p[1] + 0.4, 9, p[2] + 0.4, WHITE, M.Wood, { n = "CabanaPost" })
	end
	Y:Box(-40.6, 9, 23.4, -29.4, 9.6, 34.6, WHITE, M.Fabric, { n = "CabanaRoof" })
	Y:Box(-40.5, 1, 33.6, -29.5, 8.8, 34, WHITE, M.Fabric, { n = "Curtain", t = 0.2 })
	Y:Box(-39, 0, 26, -31, 1.6, 32, rgb(250, 240, 220), M.Fabric, { n = "DayBed", c = true })
	Y:Box(-38.5, 1.6, 30.4, -31.5, 2.8, 31.6, accent, M.Fabric, { n = "Cushion" })
	-- Fire pit circle.
	Y:FirePit(-6, 0, 31)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		Y:Ball(-6 + math.cos(a) * 6.5, 1.1, 31 + math.sin(a) * 6.5, 2.6, ({ accent, TEAL, rgb(250, 200, 80) })[i % 3 + 1], M.Fabric, { n = "Beanbag" })
	end
	-- Volleyball net and a hammock between palms.
	Y:Post(4, 0, 39, 8.5, 0.5, WHITE, M.Metal, { n = "NetPost" })
	Y:Post(18, 0, 39, 8.5, 0.5, WHITE, M.Metal, { n = "NetPost" })
	Y:Box(4, 5.5, 38.9, 18, 8, 39.1, WHITE, M.Fabric, { n = "Net", t = 0.4 })
	Y:Ball(11, 9.5, 37, 1.2, rgb(250, 230, 120), M.Plastic, { n = "Volleyball" })
	K:Palm(40, 38.5, 0.8)
	K:Palm(43.5, 30, 0.85)
	K:Palm(-43, 37, 0.8)
	K:Palm(-20, 38.5, 0.75)
	Y:Hammock(-20, 0, 24, 90, accent, 10)
	Y:Post(46, 0, 17, 8, 0.4, C.Steel, M.Metal, { n = "ShowerPost" })
	Y:Box(44.8, 7.6, 16.6, 46.2, 8, 17.4, C.Steel, M.Metal, { n = "ShowerHead" })
	Y:Box(44, 0, 16, 48, 0.3, 18.5, DECK, M.WoodPlanks, { n = "ShowerDeck" })

	-- Front: palms, flamingos and the sale sign.
	K:Palm(-1, -40, 0.85)
	K:Palm(46, -38, 0.8)
	K:Asset("FlamingoStatue", 34, -32, 0.2, 200)
	K:Asset("FlamingoStatue", 38, -30, 0.17, 160)
	for _, p in ipairs({ { 4, -23 }, { 26, -23 }, { 44, -23 } }) do
		K:Bush(p[1], p[2], 3, rgb(240, 90, 170))
	end
	K:SaleSign(26, -41, 0, def)
end
