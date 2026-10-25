-- FamilyHome (ModuleScript, ServerScriptService.Services.Houses.FamilyHome)
-- Palm Hills Family Home: a two-storey butter-yellow colonial with white trim, navy shutters,
-- dormers, a long front porch and a three-car garage. Ground floor: living room with a fireplace,
-- an open kitchen with an island, dining by the patio doors, a mudroom to the garage. Upstairs: the
-- master suite with its own bath, two kids' rooms (bunk beds, a gaming corner), a hall bath and a
-- landing den. Out back: a raised wooden deck round a pool, a swing set, a trampoline, a doghouse.
-- Drawn by HouseBuilder (lot frame: front = -Z); see HouseBuilder for the Kit.

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local SIDING = rgb(255, 232, 160)
local TRIM = C.White
local SHUTTER = rgb(50, 70, 110)
local ROOF = rgb(70, 74, 82)
local OAK = rgb(190, 150, 100)
local PLASTER = rgb(244, 236, 220)
local DECK = rgb(170, 128, 88)
local FENCE = rgb(240, 240, 232)

local F1, F2, TOP = 1, 14, 26

return function(K, def)
	local accent = def.Color
	local x0, x1, z0, z1 = -40, 4, -16, 14
	-- Slabs: ground floor, upstairs with the stairwell, garage, porch, driveway, walk.
	K:Solid(x0, 0, z0, x1, F1, z1, OAK, M.WoodPlanks, { n = "Floor" })
	K:Slab(x0, z0, x1, z1, F2 - 1, F2, OAK, M.WoodPlanks, { -24, -3.5, -20, 7.5 })
	K:Solid(x1, 0, z0, 42, 0.5, 10, C.Concrete, M.Concrete, { n = "GarageFloor" })
	K:Solid(-37, 0, -22, -7, F1 - 0.2, z0, rgb(200, 200, 205), M.WoodPlanks, { n = "Porch" })
	K:Solid(5, -0.5, -46, 41, 0.5, z0, C.Concrete, M.Concrete, { n = "Driveway" })
	K:Box(-24, -0.4, -40, -20, 0.45, -22, rgb(200, 190, 175), M.Brick, { n = "Path", c = true })

	-- Walls with windows (shuttered upstairs), the front and patio doors.
	local win = function(a, b, lo, hi)
		return { a, b, lo, hi, glass = true, mull = 1 }
	end
	K:Walls4(x0, z0, x1, z1, 0, F2 - 1, 0.8, SIDING, M.WoodPlanks, {
		front = { win(4, 10, F1 + 3, F1 + 9), { 16, 20, F1, F1 + 8.5 }, win(25, 31, F1 + 3, F1 + 9), win(36, 41, F1 + 3, F1 + 9) },
		back = { win(4, 9, F1 + 3, F1 + 9), { 18, 24, F1, F1 + 9 }, win(30, 42, F1 + 4, F1 + 9) },
		left = { win(6, 12, F1 + 3, F1 + 9), win(20, 25, F1 + 3, F1 + 9) },
		right = { { 4, 8, F1, F1 + 8 } }, -- mudroom door into the garage (one 0.5 step down)
	}, { trim = TRIM, frame = TRIM })
	local upper = {
		front = { win(4, 10, F2 + 3, F2 + 9), win(14, 20, F2 + 3, F2 + 9), win(25, 31, F2 + 3, F2 + 9), win(36, 41, F2 + 3, F2 + 9) },
		back = { win(5, 11, F2 + 3, F2 + 9), win(17, 22, F2 + 3, F2 + 9), win(37, 42, F2 + 3, F2 + 9) },
		left = { win(6, 12, F2 + 3, F2 + 9), win(20, 25, F2 + 3, F2 + 9) },
		right = { win(5, 10, F2 + 3, F2 + 9), win(20, 25, F2 + 3, F2 + 9) },
	}
	K:Walls4(x0, z0, x1, z1, F2 - 1, TOP, 0.8, SIDING, M.WoodPlanks, upper, { trim = TRIM, frame = TRIM })
	for _, a in ipairs({ 4, 14, 25, 36 }) do
		local w = upper.front[1][2] - upper.front[1][1]
		local x = x0 + a
		K:Box(x - 1.6, F2 + 2.6, z0 - 0.7, x - 0.2, F2 + 9.4, z0 - 0.4, SHUTTER, M.Wood, { n = "Shutter" })
		K:Box(x + w + 0.2, F2 + 2.6, z0 - 0.7, x + w + 1.6, F2 + 9.4, z0 - 0.4, SHUTTER, M.Wood, { n = "Shutter" })
	end
	K:Door(-22, F1, z0, 0, 4, 8.5, 0.8, { main = true, color = rgb(190, 50, 50) })
	K:Door(-19, F1, z1, 180, 6, 9, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5 })
	K:Box(-27, F1 + 9, z0 - 0.6, -17, F1 + 9.6, z0 - 0.3, TRIM, M.SmoothPlastic, { n = "DoorHead" })
	-- Porch: white columns under a shed roof.
	for _, x in ipairs({ -36.4, -29, -15, -7.6 }) do
		K:Post(x, F1 - 0.2, -21.4, 12, 1.2, TRIM, M.SmoothPlastic, { n = "Column", c = true })
	end
	K:Shed(-37.5, -22.5, -6.5, z0, 11.5, 1.8, ROOF, M.RoofShingles, { over = 0.4, flip = true })
	K:Rail(-37, -22, -29, -22, F1 - 0.2, 3, TRIM, { every = 4 })
	K:Rail(-15, -22, -7, -22, F1 - 0.2, 3, TRIM, { every = 4 })
	-- Roofs: main gable with two dormers and a brick chimney; the garage gable.
	K:Gable(x0, z0, x1, z1, TOP, 8, true, ROOF, M.RoofShingles, SIDING, M.WoodPlanks, { over = 1.4, cap = rgb(60, 62, 70) })
	for _, dx in ipairs({ -32, -12 }) do
		K:Solid(dx - 3, TOP, -12.5, dx + 3, TOP + 5, -7, SIDING, M.WoodPlanks, { n = "Dormer" })
		K:Box(dx - 2, TOP + 1, -12.7, dx + 2, TOP + 4, -12.4, C.Glass, M.Glass, { n = "DormerWindow", t = 0.4 })
		K:Gable(dx - 3.6, -13.2, dx + 3.6, -6, TOP + 5, 2.2, false, ROOF, M.RoofShingles, TRIM, M.SmoothPlastic, { over = 0.3, th = 0.5 })
	end
	K:Solid(-43, 0, -2, -40, TOP + 11, 3, rgb(150, 74, 54), M.Brick, { n = "Chimney" })
	K:Walls4(x1, z0, 42, 10, 0, 13, 0.8, SIDING, M.WoodPlanks, {
		front = { { 2, 12, 0, 9 }, { 14, 24, 0, 9 }, { 26, 36, 0, 9 } },
		back = { win(14, 22, 5, 10) },
		left = false,
		right = { win(10, 16, 5, 10) },
	}, { trim = TRIM, frame = TRIM })
	K:Gable(x1, z0, 42, 10, 13, 6, true, ROOF, M.RoofShingles, SIDING, M.WoodPlanks, { over = 1.2, cap = rgb(60, 62, 70) })
	for _, x in ipairs({ 11, 23, 35 }) do
		K:GarageDoor(x, 0.5, z0, 0, 10, 8.5, TRIM, M.WoodPlanks)
		K:Bay(x, 0.5, -3, 0)
		K:Box(x - 5, 9.4, z0 - 0.6, x + 5, 9.8, z0 - 0.4, accent, M.Neon, { n = "Neon" })
	end
	K:BankPad(23, 0.5, 7.6, 12, 3, accent)
	K:Box(39.6, 0.5, 2, 41.4, 8, 9.4, rgb(120, 100, 80), M.Wood, { n = "Shelves", c = true })
	K:Post(6.4, 0.5, 8, 4.5, 2.6, rgb(60, 140, 80), M.Plastic, { n = "Bin" })
	K:Light(23, 12.4, -3, C.Warm, 24, 1, { n = "GarageLight", size = Vector3.new(6, 0.3, 1) })
	K:Zone(4.4, 0.5, -15.6, 41.6, 13, 9.6)

	-- Ground floor rooms.
	local I = K:In("Decor")
	K:Wall(-10, -15.6, -10, -2, F1, F2 - 1, 0.6, PLASTER, M.Plaster, { { 6.5, 10.5, F1, F1 + 8.5 } })
	-- Living room: sofa round the fireplace, TV above it.
	I:Fireplace(-39.2, F1, -6, 90, rgb(150, 74, 54), { mat = M.Brick })
	I:TV(-39.4, F1, -6, 90, 7, { wall = true, at = 7.5 })
	I:Rug(-32, F1, -6, 0, 11, 12, rgb(170, 60, 60))
	I:Sofa(-26.5, F1, -6, 90, 10, rgb(90, 110, 150), { pillows = SIDING })
	I:Armchair(-32, F1, -13.5, 0, rgb(200, 170, 120))
	I:Table(-32, F1, -6, 90, 5, 3, 1.7, OAK, M.Wood)
	I:Bookshelf(-34, F1, 1.4, 180, 6, 8, TRIM)
	I:Plant(-38.5, F1, -14.5, rgb(60, 110, 160), { tall = true })
	K:Light(-32, F2 - 1.6, -6, C.Warm, 24, 1.1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.6, 1.6, 1.6) })
	-- Kitchen (back right), island and the dining table by the patio doors.
	I:Kitchen(-3, F1, 12.4, 0, 12, TRIM, rgb(70, 70, 76), { upper = TRIM, hood = C.Steel })
	I:Fridge(2.2, F1, 4, 270, C.Steel)
	I:Island(-4, F1, 3, 0, 8, SHUTTER, TRIM, rgb(200, 170, 120), 3)
	I:DiningSet(-31, F1, 8, 0, 9, 4, 3, OAK, TRIM)
	K:Light(-12, F2 - 1.6, 6, C.Warm, 24, 1.1, { n = "Pendant", shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4) })
	-- Mudroom by the garage door: bench, coat hooks, washer and dryer.
	I:Box(-9.4, F1, -15.4, -6, F1 + 2, -12, OAK, M.Wood, { n = "Bench" })
	I:Box(3.4, F1, -15.4, 0.6, F1 + 3.4, -12.8, C.White, M.SmoothPlastic, { n = "Washer" })
	I:Box(0.4, F1, -15.4, -2.4, F1 + 3.4, -12.8, C.White, M.SmoothPlastic, { n = "Dryer" })
	-- Stairs up from the foyer (the stairwell rail upstairs).
	local run = K:Stairs(-22, -12, "+Z", 4, F1, F2, OAK, M.WoodPlanks)
	K:Beam(-24.2, F1 + 3, -12, -24.2, F2 + 3, -12 + run, 0.3, TRIM, M.Wood, { n = "Handrail", c = true })
	K:Rail(-20, -3.5, -20, 7.5, F2, 3, TRIM, { every = 5 })

	-- Upstairs: master suite (left), kids' rooms (front), hall bath, landing den.
	K:Wall(-24, -15.6, -24, 13.6, F2, TOP, 0.6, PLASTER, M.Plaster, { { 23.6, 27.6, F2, F2 + 8.5 } })
	K:Wall(-39.6, -6, -24.3, -6, F2, TOP, 0.6, PLASTER, M.Plaster, { { 9, 13, F2, F2 + 8.5 } })
	K:Wall(-23.7, -3.5, -6.3, -3.5, F2, TOP, 0.6, PLASTER, M.Plaster, { { 7.7, 11.7, F2, F2 + 8.5 } })
	K:Wall(-6, -15.6, -6, 13.6, F2, TOP, 0.6, PLASTER, M.Plaster, { { 16, 20, F2, F2 + 8.5 }, { 24, 28, F2, F2 + 8.5 } })
	K:Wall(-5.7, 4, 3.6, 4, F2, TOP, 0.6, PLASTER, M.Plaster)
	-- Master bedroom and bath.
	I:Rug(-32, F2, 4, 0, 12, 12, rgb(200, 190, 230), { mat = M.Carpet })
	I:Bed(-32, F2, 8.8, 0, 8, 9, OAK, C.White, rgb(110, 90, 160), { headColor = TRIM })
	I:Nightstand(-37.4, F2, 12.6, 0, OAK)
	I:Nightstand(-26.6, F2, 12.6, 0, OAK)
	I:Box(-39.4, F2, -4.8, -37, F2 + 4.5, 1.5, OAK, M.Wood, { n = "Dresser", c = true })
	I:Armchair(-35, F2, -2, 90, rgb(200, 170, 120))
	I:Bath(-32, F2, -14.3, 180, rgb(200, 225, 235))
	K:Light(-32, TOP - 0.8, 3, rgb(255, 230, 200), 22, 1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4) })
	-- Kid room 1: bunk bed, toy chest, a bright rug.
	I:BunkBed(-21.2, F2, -11.5, 0, rgb(240, 240, 240), rgb(80, 160, 230), rgb(250, 120, 160))
	I:Rug(-15, F2, -9, 0, 8, 8, rgb(250, 200, 80), { round = true })
	I:Box(-11.4, F2, -15.4, -7, F2 + 2.2, -13, rgb(230, 90, 80), M.Wood, { n = "ToyChest" })
	I:Ball(-14, F2 + 1, -6, 1.6, rgb(240, 80, 60), M.Plastic, { n = "BeachBall" })
	I:Bookshelf(-15, F2, -2.6, 180, 5, 5, rgb(110, 190, 230), { books = { rgb(250, 200, 80), rgb(230, 90, 80) } })
	-- Kid room 2: bed and a gaming desk.
	I:Bed(-1, F2, -10.5, 180, 4.6, 8, rgb(60, 60, 70), C.White, rgb(60, 200, 120), { head = 4 })
	I:Desk(0.6, F2, -1.2, 180, rgb(40, 40, 46), rgb(200, 40, 60), rgb(120, 60, 255))
	I:Rug(-1, F2, -6, 0, 7, 6, rgb(40, 40, 46))
	I:Bath(-1, F2, 12.3, 0, rgb(250, 220, 200), { shower = true })
	-- Landing den: beanbags and shelves.
	I:Ball(-14, F2 + 1.2, 9, 3, rgb(240, 120, 60), M.Fabric, { n = "Beanbag" })
	I:Ball(-10, F2 + 1.2, 11, 3, rgb(80, 160, 230), M.Fabric, { n = "Beanbag" })
	I:TV(-14, F2, 13, 0, 5, { cabinet = OAK })
	K:Light(-14, TOP - 0.8, 6, C.Warm, 22, 1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4) })
	K:Spawn(-31, F1, -1.5, 90)
	K:Zone(-39.6, F1, -15.6, 3.6, F2 - 1, 13.6)
	K:Zone(-39.6, F2, -15.6, 3.6, TOP, 13.6)

	-- Back yard: patio, steps up to the pool deck, the pool, play area, fence.
	K:Solid(-36, 0, z1, -2, 0.5, 16.4, rgb(190, 180, 170), M.Slate, { n = "Patio" })
	K:Stairs(-19, 16, "+Z", 8, 0.5, 4.5, DECK, M.WoodPlanks)
	K:Slab(-36, 22, 0, 38, 0, 4.5, DECK, M.WoodPlanks, { -28, 24, -8, 36 }, { n = "Deck" })
	K:Pool(-28, 24, -8, 36, 4.5, { glow = accent })
	K:Rail(-36, 22, -36, 38, 4.5, 3, TRIM, { every = 8 })
	K:Rail(-36, 38, 0, 38, 4.5, 3, TRIM, { every = 8 })
	K:Rail(0, 22, 0, 38, 4.5, 3, TRIM, { every = 8 })
	K:Rail(-36, 22, -24, 22, 4.5, 3, TRIM, { every = 8 })
	K:Rail(-14, 22, 0, 22, 4.5, 3, TRIM, { every = 8 })
	K:Lounger(-32, 4.75, 27, 0, accent)
	K:Lounger(-32, 4.75, 33, 0, rgb(80, 170, 230))
	K:Umbrella(-4, 4.75, 30, rgb(250, 200, 80))
	K:Table(-4, 4.75, 26, 0, 3, 3, 3, TRIM, M.SmoothPlastic, { round = true })
	-- Play area on the lawn.
	K:Beam(8, 0, 22, 10, 10, 26, 0.5, rgb(200, 60, 60), M.Metal, { n = "SwingFrame" })
	K:Beam(12, 0, 30, 10, 10, 26, 0.5, rgb(200, 60, 60), M.Metal, { n = "SwingFrame" })
	K:Beam(22, 0, 22, 20, 10, 26, 0.5, rgb(200, 60, 60), M.Metal, { n = "SwingFrame" })
	K:Beam(18, 0, 30, 20, 10, 26, 0.5, rgb(200, 60, 60), M.Metal, { n = "SwingFrame" })
	K:Beam(9.5, 10, 26, 20.5, 10, 26, 0.5, rgb(200, 60, 60), M.Metal, { n = "SwingBar" })
	for _, x in ipairs({ 13, 17 }) do
		K:Beam(x, 10, 26, x, 3, 26, 0.1, C.Steel, M.Metal, { n = "Chain" })
		K:Box(x - 1, 2.6, 25.4, x + 1, 3, 26.6, rgb(250, 200, 80), M.Plastic, { n = "Swing" })
	end
	K:Disc(32, 3, 30, 12, 0.4, rgb(40, 40, 46), M.Fabric, { n = "Trampoline", c = true })
	K:Disc(32, 2.9, 30, 12.6, 0.3, rgb(80, 170, 230), M.Plastic, { n = "TrampolineRing" })
	for _, a in ipairs({ 0, 2.1, 4.2 }) do
		K:Post(32 + math.cos(a) * 5.6, 0, 30 + math.sin(a) * 5.6, 2.9, 0.4, C.Steel, M.Metal, { n = "TrampolineLeg" })
	end
	K:Box(36, 0, 14, 41, 3.6, 19, rgb(200, 60, 50), M.WoodPlanks, { n = "Doghouse", c = true })
	K:Wedge(5.6, 1.8, 2.8, 38.5, 4.5, 15.1, 0, rgb(70, 74, 82), M.RoofShingles, { n = "DoghouseRoof" })
	K:Wedge(5.6, 1.8, 2.8, 38.5, 4.5, 17.9, 180, rgb(70, 74, 82), M.RoofShingles, { n = "DoghouseRoof" })
	K:Palm(-40, 34, 0.8)
	K:Palm(36, 33, 0.75)
	K:Palm(4, 36, 0.7)
	-- Privacy fence round the back yard.
	K:Solid(-43.6, 0, z1, -43, 8.2, 39.6, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(-43, 0, z1, x0, 8.2, z1 + 0.6, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(43, 0, 10, 43.6, 8.2, 39.6, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(42, 0, 10, 43, 8.2, 10.6, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(-43.6, 0, 39, 43.6, 8.2, 39.6, FENCE, M.WoodPlanks, { n = "Fence" })

	-- Front yard: lawn trees, hedges, flower beds, a basketball hoop, mailbox and sale sign.
	K:Palm(-41, -30, 0.85)
	K:Palm(-4, -32, 0.75)
	for _, x in ipairs({ -38, -32, -12, -8 }) do
		K:Bush(x, -24.5, 2.6, rgb(70, 160, 90))
	end
	K:Box(-36, 0, -25.6, -26, 0.6, -24, rgb(110, 80, 60), M.Mud, { n = "FlowerBed" })
	for i = 0, 3 do
		K:Bush(-34.5 + i * 2.8, -24.8, 1.6, ({ rgb(240, 90, 120), rgb(250, 210, 80), rgb(240, 90, 120), rgb(250, 140, 60) })[i + 1], 0.6)
	end
	K:Post(42.6, 0, -30, 11, 0.6, C.Steel, M.Metal, { n = "HoopPole" })
	K:Box(42.2, 10, -32, 42.6, 13.4, -28, C.White, M.SmoothPlastic, { n = "Backboard" })
	K:Disc(41.2, 10.4, -30, 2, 0.15, rgb(250, 120, 40), M.Metal, { n = "Hoop" })
	K:Mailbox(-27, -38.5, 0, SHUTTER)
	K:SaleSign(-36, -37, 0, def)
end
