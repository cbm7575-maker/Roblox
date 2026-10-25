-- Mansion (ModuleScript, ServerScriptService.Services.Houses.Mansion)
-- Coastal Mansion (Marina Row waterfront, $1.2M): a gated white-and-gold art deco estate. A hedge
-- wall with an iron gate (it opens for owners), a motor court round a fountain, a columned portico
-- under a pediment, and two garage wings with three bays each (six cars on show). Inside: a
-- double-height foyer with twin staircases and a chandelier, a living room with a grand piano, a
-- library, a dining room for ten, a big kitchen and a bar room with a pool table. Upstairs: the
-- master suite with a balcony over the pool, a guest room, a game room with arcade cabinets and a
-- home theatre. Out back: a big pool and spa on a terrace, a pool house bar, loungers, a pergola.
-- Drawn by HouseBuilder (lot frame: front = -Z, the marina off to +X).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local WHITE = rgb(248, 246, 242)
local GOLD = rgb(212, 175, 55)
local MARBLE = rgb(238, 236, 232)
local DARK = rgb(28, 28, 34)
local HEDGE = rgb(52, 120, 64)
local PAVE = rgb(214, 204, 186)
local WOOD = rgb(110, 70, 44)
local GLASS = rgb(120, 170, 200)

local F1, F2, TOP = 4.5, 17.5, 30.5

return function(K, def)
	local accent = def.Color
	local x0, x1, z0, z1 = -24, 24, -16, 24

	-- Grounds: hedge wall with the gate, motor court, fountain, sale sign outside.
	K:Hedge(-60, -50.6, -8, -49.4, 8.5, HEDGE)
	K:Hedge(8, -50.6, 60, -49.4, 8.5, HEDGE)
	K:Hedge(-60, -49.4, -58.8, 54.8, 8.5, HEDGE)
	K:Hedge(58.8, -49.4, 60, 54.8, 8.5, HEDGE)
	K:Hedge(-58.8, 53.6, 58.8, 54.8, 8.5, HEDGE)
	for _, x in ipairs({ -9, 9 }) do
		K:Solid(x - 1.2, 0, -51.2, x + 1.2, 11, -48.8, WHITE, M.Marble, { n = "GatePier" })
		K:Box(x - 1.4, 11, -51.4, x + 1.4, 11.6, -48.6, GOLD, M.Metal, { n = "PierCap" })
		K:Ball(x, 12.4, -50, 1.4, accent, M.Neon, { n = "PierLamp" })
	end
	K:Door(-4, 0.5, -50, 0, 8, 8.5, 1.2, { style = "swing", color = DARK, mat = M.Metal, t = 0.25 })
	K:Door(4, 0.5, -50, 0, 8, 8.5, 1.2, { style = "swing", mirror = true, color = DARK, mat = M.Metal, t = 0.25 })
	K:Box(-8, 9.2, -50.3, 8, 9.6, -49.7, GOLD, M.Metal, { n = "GateArch" })
	K:Banner(0, 10.6, -50.4, 0, 14, 1.6, def.Name:upper(), accent)
	K:Solid(-10, -0.5, -61, 10, 0.5, -49.4, PAVE, M.Cobblestone, { n = "Driveway" })
	K:Solid(-58.8, 0, -49.4, 58.8, 0.5, z0, PAVE, M.Cobblestone, { n = "Driveway" })
	K:SaleSign(-24, -53.5, 0, def)
	K:Zone(-58.4, 0, -49, 58.4, 12, -16.4) -- the motor court: nobody gets shut in between gate and house
	-- Fountain: a round basin with a tiered pedestal and glowing jets.
	local FZ = -40
	K:Disc(0, 0.5, FZ, 14, 2.2, WHITE, M.Marble, { n = "FountainRim", c = true })
	K:Disc(0, 0.5, FZ, 12.4, 2, rgb(60, 170, 220), M.Glass, { n = "FountainWater", t = 0.2 })
	K:Post(0, 0.5, FZ, 7, 1.8, WHITE, M.Marble, { n = "FountainColumn", c = true })
	K:Disc(0, 7, FZ, 6, 0.8, WHITE, M.Marble, { n = "FountainBowl" })
	K:Disc(0, 7.3, FZ, 5, 0.6, rgb(60, 170, 220), M.Glass, { n = "BowlWater", t = 0.2 })
	K:Post(0, 7.8, FZ, 11, 0.8, rgb(170, 230, 255), M.Neon, { n = "Jet" })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		K:Beam(math.cos(a) * 1.3, 9.8, FZ + math.sin(a) * 1.3, math.cos(a) * 4.6, 3, FZ + math.sin(a) * 4.6, 0.3, rgb(170, 230, 255), M.Neon, { n = "Spray" })
	end
	for _, p in ipairs({ { -18, -44 }, { 18, -44 }, { -18, -24 }, { 18, -24 } }) do
		K:Box(p[1] - 2.5, 0.5, p[2] - 2.5, p[1] + 2.5, 2, p[2] + 2.5, WHITE, M.Marble, { n = "Planter", c = true })
		K:Palm(p[1], p[2], 0.85, 2)
	end
	K:Light(0, 3, FZ, rgb(170, 230, 255), 24, 1.2, { n = "FountainLight", shape = "Ball", size = Vector3.new(1.2, 1.2, 1.2) })

	-- The house on its plinth, with the grand steps and the portico.
	K:Solid(x0, 0, z0, x1, F1, z1, MARBLE, M.Marble, { n = "Floor" })
	K:Box(x0 - 1, F1 - 0.6, z0 - 1, x1 + 1, F1, z1 + 1, GOLD, M.Metal, { n = "PlinthTrim" })
	K:Solid(-13, 0, -24, 13, F1, z0, MARBLE, M.Marble, { n = "Portico" })
	K:Stairs(0, -30, "+Z", 20, 0.5, F1, MARBLE, M.Marble)
	for _, x in ipairs({ -11, -4, 4, 11 }) do
		K:Post(x, F1, -22.5, TOP, 2.2, WHITE, M.Marble, { n = "Column", c = true })
		K:Box(x - 1.5, TOP - 1, -24, x + 1.5, TOP, -21, GOLD, M.Metal, { n = "Capital" })
	end
	K:Box(-13.5, TOP, -25, 13.5, TOP + 1.5, z0, WHITE, M.Marble, { n = "Entablature", c = true })
	K:Gable(-13.5, -25, 13.5, -15, TOP + 1.5, 5, false, WHITE, M.Marble, WHITE, M.Marble, { over = 0.6 })
	K:Box(-13.6, TOP + 0.4, -25.2, 13.6, TOP + 0.8, -25, accent, M.Neon, { n = "Neon" })

	-- Walls: tall windows with gold mullions, the double front door, terrace doors.
	local win = function(a, b, lo, hi, bars)
		return { a, b, lo, hi, glass = GLASS, mull = bars or 1, t = 0.45 }
	end
	K:Walls4(x0, z0, x1, z1, F1, F2 - 1, 1, WHITE, M.Plaster, {
		front = { win(3, 9, F1 + 2, F1 + 10), win(12, 18, F1 + 2, F1 + 10), { 21, 27, F1, F1 + 10 }, win(30, 36, F1 + 2, F1 + 10), win(39, 45, F1 + 2, F1 + 10) },
		back = { win(3, 9, F1 + 2, F1 + 10), { 18, 30, F1, F1 + 10 }, win(39, 45, F1 + 2, F1 + 10) },
		left = { win(5, 11, F1 + 2, F1 + 10), win(28, 34, F1 + 2, F1 + 10) },
		right = { win(5, 11, F1 + 2, F1 + 10), win(28, 34, F1 + 2, F1 + 10) },
	}, { frame = GOLD, trim = GOLD })
	K:Walls4(x0, z0, x1, z1, F2 - 1, TOP, 1, WHITE, M.Plaster, {
		front = { win(3, 9, F2 + 2, F2 + 10), win(12, 36, F2 + 1, F2 + 11, 3), win(39, 45, F2 + 2, F2 + 10) },
		back = { win(3, 7, F2 + 2, F2 + 10), { 8, 14, F2, F2 + 10 }, win(18, 30, F2 + 2, F2 + 10, 2), win(39, 45, F2 + 2, F2 + 10) },
		left = { win(5, 11, F2 + 2, F2 + 10), win(28, 34, F2 + 2, F2 + 10) },
		right = { win(5, 11, F2 + 2, F2 + 10), win(28, 34, F2 + 2, F2 + 10) },
	}, { frame = GOLD, trim = GOLD })
	K:Door(-1.5, F1, z0, 0, 3, 10, 1, { main = true, color = WOOD })
	K:Door(1.5, F1, z0, 0, 3, 10, 1, { mirror = true, color = WOOD })
	K:Door(0, F1, z1, 180, 12, 10, 1, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5 })
	K:Door(-13, F2, z1, 180, 6, 10, 1, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5, noBlock = true })
	-- Flat roof with a parapet, gold cornice and neon pilasters up the facade.
	K:FlatRoof(x0, z0, x1, z1, TOP, WHITE, M.Plaster, 2.4, WHITE, M.Marble, { over = 0.6 })
	K:Box(x0 - 0.9, TOP - 0.6, z0 - 0.9, x1 + 0.9, TOP, z1 + 0.9, GOLD, M.Metal, { n = "Cornice" })
	for _, x in ipairs({ -23.6, -14, 14, 23.6 }) do
		K:Neon(x - 0.25, F1, z0 - 0.75, x + 0.25, TOP - 0.6, z0 - 0.5, accent)
	end
	-- Master balcony over the pool terrace.
	K:Solid(x0, F2 - 1, z1, -4, F2, 30, MARBLE, M.Marble, { n = "Balcony" })
	K:Rail(x0, 30, -4, 30, F2, 3.4, GOLD, { glass = true })
	K:Rail(-4, z1, -4, 30, F2, 3.4, GOLD, { glass = true })
	K:Rail(x0, z1, x0, 30, F2, 3.4, GOLD, { glass = true })

	-- Garage wings: three bays each, doors to the motor court, balustraded roofs.
	for side = -1, 1, 2 do
		local wx0, wx1 = side < 0 and -58.8 or x1, side < 0 and x0 or 58.8
		K:Walls4(wx0, z0, wx1, 10, 0, 13, 0.8, WHITE, M.Plaster, {
			front = { { 1.6, 11.6, 0, 9 }, { 13.4, 23.4, 0, 9 }, { 25.2, 33.2, 0, 9 } },
			back = { win(10, 24, 5, 10, 2) },
			left = side < 0 and {} or false,
			right = side > 0 and {} or false,
		}, { frame = GOLD })
		K:FlatRoof(wx0, z0, wx1, 10, 13, WHITE, M.Plaster, 2, WHITE, M.Marble, { over = 0.4 })
		for i = 0, 2 do
			local bx = wx0 + 6.6 + i * 11.8
			if i == 2 then
				bx = wx0 + 29.2
			end
			K:GarageDoor(bx, 0.5, z0, 0, i == 2 and 8 or 10, 8.5, GLASS, M.Glass, { t = 0.35 })
			K:Bay(bx, 0.5, -3, 0)
			K:Neon(bx - 5, 9.3, z0 - 0.6, bx + 5, 9.6, z0 - 0.4, accent)
		end
		K:Solid(wx0, 0, z0, wx1, 0.5, 10, rgb(60, 60, 66), M.Granite, { n = "GarageFloor" })
		K:BankPad((wx0 + wx1) / 2, 0.5, 7.4, 12, 3, accent)
		K:Box(wx0 + 0.8, 0.5, -10, wx0 + 2, 9, 6, DARK, M.DiamondPlate, { n = "ShowroomWall" })
		K:Light((wx0 + wx1) / 2, 12.3, -3, rgb(230, 240, 255), 30, 1.1, { n = "GarageLight", size = Vector3.new(14, 0.3, 1) })
		K:Zone(wx0 + 0.4, 0.5, z0 + 0.4, wx1 - 0.4, 13, 9.6)
	end

	-- Foyer: double height, twin staircases, the chandelier.
	K:Slab(x0, z0, x1, z1, F2 - 1, F2, MARBLE, M.Marble, { -8, z0, 8, 7.5 })
	local I = K:In("Decor")
	for _, sx in ipairs({ -6, 6 }) do
		local run = K:Stairs(sx, -12, "+Z", 4, F1, F2, WHITE, M.Marble)
		K:Beam(sx + (sx < 0 and 2.2 or -2.2), F1 + 3.4, -12, sx + (sx < 0 and 2.2 or -2.2), F2 + 3.4, -12 + run, 0.3, GOLD, M.Metal, { n = "Handrail", c = true })
	end
	K:Rail(-4, 7.5, 4, 7.5, F2, 3.4, GOLD, { glass = true }) -- between the stair tops (x 4..8 each side)
	I:Rug(0, F1, -10, 0, 7, 10, rgb(150, 30, 50))
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		I:Beam(math.cos(a) * 3, TOP - 6, -4 + math.sin(a) * 3, 0, TOP - 1, -4, 0.15, GOLD, M.Metal, { n = "ChandelierArm" })
		I:Ball(math.cos(a) * 3, TOP - 6.4, -4 + math.sin(a) * 3, 0.9, rgb(255, 240, 200), M.Neon, { n = "Crystal" })
	end
	K:Light(0, TOP - 6.5, -4, rgb(255, 236, 200), 40, 1.4, { n = "Chandelier", shape = "Ball", size = Vector3.new(2.4, 2.4, 2.4) })
	I:Plant(-6.5, F1, -14.5, GOLD, { tall = true })
	I:Plant(6.5, F1, -14.5, GOLD, { tall = true })

	-- Interior walls (ground): living | foyer | dining; library and kitchen behind; bar room.
	K:Wall(-8, z0 + 0.5, -8, z1 - 0.5, F1, F2 - 1, 0.6, WHITE, M.Plaster, { { 4, 10, F1, F1 + 10 }, { 26, 32, F1, F1 + 10 } })
	K:Wall(8, z0 + 0.5, 8, z1 - 0.5, F1, F2 - 1, 0.6, WHITE, M.Plaster, { { 4, 10, F1, F1 + 10 }, { 26, 32, F1, F1 + 10 } })
	K:Wall(-23.5, 8, -8.3, 8, F1, F2 - 1, 0.6, WHITE, M.Plaster, { { 6, 11, F1, F1 + 10 } })
	K:Wall(8.3, 4, 23.5, 4, F1, F2 - 1, 0.6, WHITE, M.Plaster, { { 5, 10, F1, F1 + 10 } })
	-- Living room: fireplace, sofas, grand piano.
	I:Fireplace(-23.2, F1, -4, 90, MARBLE, { mat = M.Marble, mantle = GOLD })
	I:Art(-23.4, F1 + 9, -4, 90, 7, 4, GOLD, rgb(40, 60, 120), false)
	I:Rug(-16, F1, -4, 0, 10, 12, rgb(230, 220, 200))
	I:Sofa(-12, F1, -4, 90, 10, rgb(240, 236, 228), { pillows = GOLD })
	I:Armchair(-17, F1, -12.4, 0, rgb(150, 30, 50), M.Leather)
	I:Armchair(-17, F1, 4.4, 180, rgb(150, 30, 50), M.Leather)
	I:Table(-17, F1, -4, 90, 5, 3, 1.6, GOLD, M.Metal)
	I:Box(-21, F1, -15, -14, F1 + 3.2, -10.5, DARK, M.SmoothPlastic, { n = "GrandPiano", c = true })
	I:Box(-21, F1 + 3.2, -15, -14, F1 + 3.5, -14.2, DARK, M.SmoothPlastic, { n = "PianoLid", rot = CFrame.Angles(math.rad(-30), 0, 0) })
	K:Light(-16, F2 - 1.8, -4, rgb(255, 236, 200), 26, 1.1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.8, 1.8, 1.8) })
	K:Spawn(-12, F1, 5.5, 90)
	-- Library behind the living room.
	for i = 0, 2 do
		I:Bookshelf(-21 + i * 5.5, F1, 23, 0, 5, 10, WOOD, { books = { rgb(150, 30, 50), rgb(40, 60, 120), GOLD } })
	end
	I:Armchair(-20, F1, 15, 45, rgb(110, 70, 44), M.Leather)
	I:Armchair(-12, F1, 15, 315, rgb(110, 70, 44), M.Leather)
	I:Rug(-16, F1, 15, 0, 9, 7, rgb(40, 60, 120))
	-- Dining room for ten, then the kitchen.
	I:DiningSet(16, F1, -6, 90, 15, 5, 5, WOOD, WHITE)
	I:Art(23.4, F1 + 7, -6, 270, 8, 5, GOLD, accent, true)
	I:Kitchen(16, F1, 22.5, 0, 14, WHITE, DARK, { upper = WHITE, hood = GOLD })
	I:Fridge(22, F1, 10, 270, C.Steel)
	I:Island(15, F1, 13, 0, 9, DARK, MARBLE, GOLD, 3)
	K:Light(16, F2 - 1.8, 12, rgb(255, 236, 200), 26, 1.1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.6, 1.6, 1.6) })
	-- Bar room behind the foyer, opening onto the terrace.
	I:Box(-6.6, F1, 12, -2, F1 + 3.6, 22, WOOD, M.Wood, { n = "Bar", c = true })
	I:Box(-6.8, F1 + 3.6, 11.8, -1.8, F1 + 4, 22.2, MARBLE, M.Marble, { n = "BarTop" })
	for i = 0, 2 do
		I:Disc(-0.8, F1 + 2.4, 14 + i * 3, 1.5, 0.4, GOLD, M.Leather, { n = "Stool" })
	end
	I:Box(2, F1, 13, 7, F1 + 2.8, 19, WOOD, M.Wood, { n = "PoolTable", c = true })
	I:Box(2.3, F1 + 2.8, 13.3, 6.7, F1 + 3, 18.7, rgb(30, 110, 70), M.Fabric, { n = "Felt" })

	-- Upstairs: master suite (left), guest room (back), game room and theatre (right).
	K:Wall(-8, z0 + 0.5, -8, z1 - 0.5, F2, TOP, 0.6, WHITE, M.Plaster, { { 25, 30, F2, F2 + 9 } })
	K:Wall(8, z0 + 0.5, 8, z1 - 0.5, F2, TOP, 0.6, WHITE, M.Plaster, { { 25, 30, F2, F2 + 9 } })
	K:Wall(-7.7, 12, 7.7, 12, F2, TOP, 0.6, WHITE, M.Plaster, { { 5.5, 10, F2, F2 + 9 } })
	K:Wall(8.3, 4, 23.5, 4, F2, TOP, 0.6, WHITE, M.Plaster, { { 5, 10, F2, F2 + 9 } })
	K:Wall(-23.5, 10, -8.3, 10, F2, TOP, 0.6, WHITE, M.Plaster, { { 6, 11, F2, F2 + 9 } })
	K:Rail(-8, z0, -8, 7.5, F2, 3.4, GOLD, { glass = true })
	K:Rail(8, z0, 8, 7.5, F2, 3.4, GOLD, { glass = true })
	I:Bed(-16, F2, -11, 180, 10, 10, GOLD, WHITE, rgb(150, 30, 50), { headColor = WHITE, headMat = M.Leather, head = 7, frameMat = M.Metal })
	I:Nightstand(-22.2, F2, -14.6, 180, WOOD, GOLD)
	I:Nightstand(-9.8, F2, -14.6, 180, WOOD, GOLD)
	I:Rug(-16, F2, -4, 0, 12, 10, rgb(240, 230, 210), { mat = M.Carpet })
	I:Sofa(-16, F2, 4, 0, 8, rgb(150, 30, 50), { mat = M.Leather })
	I:Bath(-16, F2, 22.5, 0, MARBLE, { vanity = GOLD })
	I:Box(-23.4, F2, 11, -21.4, F2 + 8, 19, WOOD, M.Wood, { n = "Closet", c = true })
	K:Light(-16, TOP - 1.2, -4, rgb(255, 236, 200), 26, 1.1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.6, 1.6, 1.6) })
	I:Bed(0, F2, 18, 0, 8, 9, WOOD, WHITE, rgb(40, 60, 120), { headColor = GOLD, headMat = M.Metal })
	I:Nightstand(5.4, F2, 22.4, 0, WOOD)
	-- Game room: arcade cabinets, a gaming couch.
	for i = 0, 2 do
		local ax = 11 + i * 4.5
		I:Box(ax - 1.6, F2, -15.4, ax + 1.6, F2 + 7.5, -12.8, DARK, M.SmoothPlastic, { n = "Arcade", c = true })
		I:Box(ax - 1.2, F2 + 4, -12.85, ax + 1.2, F2 + 6.2, -12.7, ({ accent, rgb(60, 220, 255), rgb(255, 60, 160) })[i + 1], M.Neon, { n = "ArcadeScreen" })
	end
	I:Sofa(16, F2, -3.5, 180, 9, DARK, { mat = M.Leather, pillows = accent })
	I:TV(16, F2, -14, 180, 6, { wall = true, at = 9.2, glow = rgb(120, 60, 255) })
	-- Home theatre: a glowing screen and three rows of seats.
	I:Box(9, F2 + 2, 23.2, 23, F2 + 10, 23.5, rgb(200, 230, 255), M.Neon, { n = "CinemaScreen" })
	for row = 0, 2 do
		I:Sofa(16, F2 + row * 0.8, 17 - row * 4, 180, 10, rgb(120, 20, 40), { mat = M.Fabric })
		if row > 0 then
			I:Box(9, F2, 18.6 - row * 4, 23.5, F2 + row * 0.8, 15.4 - row * 4, DARK, M.Carpet, { n = "Riser", c = true })
		end
	end
	K:Zone(x0 + 0.5, F1, z0 + 0.5, x1 - 0.5, F2 - 1, z1 - 0.5)
	K:Zone(x0 + 0.5, F2, z0 + 0.5, x1 - 0.5, TOP, z1 - 0.5)

	-- Pool terrace: the pool and spa, the pool house bar, loungers, pergola dining, palms.
	K:Deck(-58.8, z1, 58.8, 53.6, 0, F1, rgb(230, 222, 206), M.Limestone, { { -20, 28, 20, 40 }, { 24, 32, 32, 40 } }, { n = "Terrace" })
	K:Deck(-58.8, 10, x0, z1, 0, F1, rgb(230, 222, 206), M.Limestone, {}, { n = "Terrace" })
	K:Deck(x1, 10, 58.8, z1, 0, F1, rgb(230, 222, 206), M.Limestone, {}, { n = "Terrace" })
	K:Pool(-20, 28, 20, 40, F1, { glow = accent, tile = rgb(60, 150, 210) })
	K:Pool(24, 32, 32, 40, F1, { glow = GOLD, step = false })
	for i = 0, 5 do
		K:Lounger(-17 + i * 6.8, F1 + 0.25, 46, 0, i % 2 == 0 and accent or WHITE)
	end
	for _, x in ipairs({ -13.6, 0, 13.6 }) do
		K:Umbrella(x, F1 + 0.25, 50, WHITE)
	end
	-- Pool house with a bar.
	K:Walls4(38, 28, 56, 48, F1, F1 + 10, 0.6, WHITE, M.Plaster, { left = { { 4, 16, F1, F1 + 8 } } }, {})
	K:FlatRoof(38, 28, 56, 48, F1 + 10, WHITE, M.Plaster, 0, nil, nil, { over = 1.5 })
	K:Neon(36.5, F1 + 9.6, 26.4, 57.5, F1 + 9.9, 26.6, accent)
	K:Box(44, F1, 30, 46, F1 + 3.6, 46, WOOD, M.Wood, { n = "PoolBar", c = true })
	K:Box(43.8, F1 + 3.6, 29.8, 46.2, F1 + 4, 46.2, MARBLE, M.Marble, { n = "BarTop" })
	K:Box(54.6, F1, 30, 55.4, F1 + 8, 46, WOOD, M.Wood, { n = "BarShelf" })
	K:Banner(37.6, F1 + 8, 38, 90, 10, 1.6, "POOL BAR", accent)
	-- Pergola dining and a fire lounge on the west side.
	for _, p in ipairs({ { -54, 28 }, { -38, 28 }, { -54, 44 }, { -38, 44 } }) do
		K:Box(p[1] - 0.5, F1, p[2] - 0.5, p[1] + 0.5, F1 + 10, p[2] + 0.5, WHITE, M.Marble, { n = "PergolaPost", c = true })
	end
	for i = 0, 6 do
		K:Box(-54.6, F1 + 10, 28 + i * 2.6, -37.4, F1 + 10.5, 28.6 + i * 2.6, WOOD, M.Wood, { n = "PergolaSlat" })
	end
	K:DiningSet(-46, F1, 36, 90, 10, 4, 3, WOOD, WHITE)
	K:FirePit(-46, F1, 18)
	K:Sofa(-46, F1, 12.6, 180, 8, WHITE, { pillows = accent })
	for _, p in ipairs({ { 22, 47 }, { -24, 50 }, { 34, 20 }, { -30, 18 } }) do
		K:Post(p[1], F1, p[2], F1 + 2, 2.6, GOLD, M.Metal, { n = "Pot" })
		K:Palm(p[1], p[2], 0.6, F1 + 2)
	end
	-- Terrace edge: balustrade above the hedge line, steps down from the garages' backs.
	K:Rail(-58.8, 53.4, 58.8, 53.4, F1, 3.4, WHITE, { mat = M.Marble, every = 8 })
end
