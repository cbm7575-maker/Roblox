-- Bungalow (ModuleScript, ServerScriptService.Services.Houses.Bungalow)
-- Palm Hills Bungalow: a one-storey seafoam craftsman cottage with a columned front porch and a
-- two-car garage. Inside: living room, open kitchen and dining, a master bedroom with its own bath,
-- a second bedroom. Out back, behind a privacy fence: a stone patio with a barrel BBQ, a picnic
-- table, string lights, a hammock between palms and a pair of flamingos.
-- Drawn by HouseBuilder (lot frame: front = -Z); see HouseBuilder for the Kit.

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local SIDING = rgb(168, 222, 205)
local TRIM = C.White
local ROOF = rgb(88, 96, 110)
local STONE = rgb(150, 145, 140)
local FLOOR = rgb(200, 170, 130)
local PLASTER = rgb(246, 238, 222)
local FENCE = rgb(176, 136, 96)

local F = 1 -- floor top
local TOP = 13 -- eaves

return function(K, def)
	local accent = def.Color
	-- Slabs.
	K:Solid(-30.4, 0, -12.4, 4, F, 16.4, FLOOR, M.WoodPlanks, { n = "Floor" })
	K:Solid(4, 0, -12, 30.4, 0.5, 14.4, C.Concrete, M.Concrete, { n = "GarageFloor" })
	K:Solid(-26, 0, -18.5, -16, F - 0.2, -12.4, STONE, M.Slate, { n = "Porch" })
	K:Solid(6, -0.5, -40, 28, 0.5, -12, C.Concrete, M.Concrete, { n = "Driveway" })
	K:Box(-22.5, -0.4, -30, -19.5, 0.45, -18.5, STONE, M.Slate, { n = "Path", c = true })

	-- House walls.
	local win = function(a, b)
		return { a, b, F + 3, F + 9, glass = true, mull = 1 }
	end
	K:Walls4(-30, -12, 4, 16, F, TOP, 0.8, SIDING, M.WoodPlanks, {
		front = { win(2, 7), { 7.5, 11.5, F, F + 8.5 }, win(13, 17), win(22, 28) },
		back = { win(2, 8), { 9, 15, F, F + 9 }, win(22, 30) },
		left = { win(1, 5), win(18, 24) },
		right = {},
	}, { trim = TRIM, frame = TRIM })
	K:Door(-20.5, F, -12, 0, 4, 8.5, 0.8, { main = true, color = rgb(240, 110, 90) })
	K:Door(-18, F, 16, 180, 6, 9, 0.8, { style = "slide", color = C.Glass, mat = M.Glass, t = 0.5 })
	-- Inside walls (cream plaster): bedrooms on the right, the en-suite bath.
	K:Wall(-12, -11.6, -12, 15.6, F, TOP, 0.6, PLASTER, M.Plaster, { { 5, 10, F, F + 8.5 }, { 19, 24, F, F + 8.5 } })
	K:Wall(-11.7, 2, 3.6, 2, F, TOP, 0.6, PLASTER, M.Plaster, { { 10.5, 14.5, F, F + 8.5 } })
	K:Wall(-2, -11.6, -2, 1.7, F, TOP, 0.6, PLASTER, M.Plaster)
	-- Porch: stone-based columns and a little gable.
	for _, x in ipairs({ -25.4, -16.6 }) do
		K:Box(x - 0.9, F - 0.2, -18.4, x + 0.9, F + 2.6, -16.6, STONE, M.Cobblestone, { n = "ColumnBase", c = true })
		K:Box(x - 0.55, F + 2.6, -18.05, x + 0.55, TOP - 1, -16.95, TRIM, M.SmoothPlastic, { n = "Column", c = true })
	end
	K:Gable(-26.5, -19, -15.5, -12, TOP - 1, 3.5, false, ROOF, M.RoofShingles, TRIM, M.WoodPlanks, { over = 0.6 })
	K:Neon(-26, TOP - 1.4, -19.2, -16, TOP - 1.1, -19, accent)
	-- Main roof and the garage's front-facing gable.
	K:Gable(-30, -12, 4, 16, TOP, 7, true, ROOF, M.RoofShingles, SIDING, M.WoodPlanks, { over = 1.6, cap = TRIM })
	K:Gable(4, -12, 30, 14.4, TOP, 6, false, ROOF, M.RoofShingles, SIDING, M.WoodPlanks, { over = 1.2, cap = TRIM })

	-- Garage: two doors, two bays, the bank pad, shelves.
	K:Walls4(4, -12, 30, 14.4, 0, TOP, 0.8, SIDING, M.WoodPlanks, {
		front = { { 2, 12, 0, 9 }, { 14, 24, 0, 9 } },
		back = { { 10, 16, 5, 9, glass = true } },
		right = { win(8, 14) },
	}, { trim = TRIM, frame = TRIM })
	K:GarageDoor(11, 0.5, -12, 0, 10, 8.5, TRIM, M.WoodPlanks)
	K:GarageDoor(23, 0.5, -12, 0, 10, 8.5, TRIM, M.WoodPlanks)
	K:Neon(5, 9.6, -12.7, 29, 9.9, -12.5, accent)
	K:Bay(11, 0.5, 1, 0)
	K:Bay(23, 0.5, 1, 0)
	K:BankPad(17, 0.5, 11.4, 5, 4, accent)
	K:Box(28.6, 0.5, -6, 29.6, 8, 6, rgb(120, 100, 80), M.Wood, { n = "Shelves", c = true })
	for i = 0, 2 do
		K:Box(28.2, 2 + i * 2.2, -5 + i * 3, 29.4, 3.6 + i * 2.2, -2.6 + i * 3, ({ rgb(220, 80, 60), rgb(60, 140, 200), rgb(240, 200, 60) })[i + 1], M.SmoothPlastic, { n = "Bins" })
	end
	K:Light(17, TOP - 0.8, 1, C.Warm, 20, 1, { n = "GarageLight", size = Vector3.new(4, 0.3, 1) })
	K:Zone(4.4, 0.5, -11.6, 29.6, TOP, 14)

	-- Living room.
	local I = K:In("Decor")
	I:Rug(-24, F, -3, 0, 9, 12, rgb(90, 140, 170))
	I:Sofa(-19.5, F, -3, 90, 9, rgb(240, 230, 210), { pillows = accent })
	I:Armchair(-25, F, -9.6, 0, rgb(240, 150, 120))
	I:Table(-24.5, F, -3, 90, 5, 3, 1.7, FLOOR, M.Wood)
	I:TV(-28.8, F, -2, 270, 7, { cabinet = rgb(240, 240, 235) })
	I:Bookshelf(-29.2, F, 8, 90, 5, 7, rgb(240, 240, 235))
	I:Plant(-28.5, F, -10.5, rgb(240, 120, 100), { tall = true })
	I:Art(-12.4, F + 6, -6, 90, 5, 3.5, C.White, accent, false)
	K:Light(-21, TOP - 0.6, -3, C.Warm, 22, 1.1, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.6, 1.6, 1.6) })
	-- Kitchen and dining, by the sliding door to the patio.
	I:Kitchen(-26, F, 14.3, 0, 7, rgb(240, 240, 235), rgb(60, 60, 66), { upper = rgb(240, 240, 235) })
	I:Fridge(-28.2, F, 9, 90, C.Steel)
	I:Island(-24, F, 7.5, 180, 6, accent, rgb(240, 240, 235), rgb(60, 60, 66), 2)
	I:DiningSet(-15.5, F, 8.5, 90, 6, 4, 2, FLOOR, rgb(240, 240, 235))
	K:Light(-20, TOP - 0.6, 9, C.Warm, 20, 1, { n = "Pendant", shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4) })
	-- Master bedroom (back right) with the en-suite bath (front right).
	I:Rug(-4, F, 9, 0, 13, 11, rgb(220, 205, 190), { mat = M.Carpet })
	I:Bed(-4, F, 10.8, 0, 7, 9, rgb(240, 240, 235), C.White, accent, {})
	I:Nightstand(1.2, F, 14.4, 0, rgb(240, 240, 235))
	I:Nightstand(-9.2, F, 14.4, 0, rgb(240, 240, 235))
	I:Box(-11.4, F, 3, -9.6, F + 7, 7, FLOOR, M.Wood, { n = "Wardrobe", c = true })
	K:Light(-4, TOP - 0.6, 7, rgb(255, 230, 200), 18, 0.9, { n = "CeilingLight", shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4) })
	I:Bath(1, F, -5, 270, rgb(170, 220, 230))
	-- Second bedroom (front right of the hall): single bed and a desk.
	I:Bed(-7, F, -3.5, 90, 4.4, 8, rgb(110, 160, 210), C.White, rgb(250, 200, 80), { head = 4 })
	I:Desk(-7.5, F, -10, 180, FLOOR, rgb(60, 60, 66))
	I:Rug(-7, F, -5, 0, 7, 9, rgb(250, 200, 80), { round = true })
	K:Spawn(-22, F, 1.5, 270)
	K:Zone(-29.6, F, -11.6, 3.6, TOP, 15.6)

	-- Back yard: privacy fence, patio with BBQ, picnic table, string lights, hammock, flamingos.
	K:Solid(-31.8, 0, 4, -31, 8.2, 29.8, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(-31, 0, 4, -30, 8.2, 4.8, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(31, 0, 14, 31.8, 8.2, 29.8, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(30, 0, 14, 31, 8.2, 14.8, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Solid(-31.8, 0, 29, 31.8, 8.2, 29.8, FENCE, M.WoodPlanks, { n = "Fence" })
	K:Box(-30, 0, 16.4, -4, 0.25, 26, STONE, M.Slate, { n = "Patio", c = true })
	K:BBQ(-26, 0.25, 22, 90)
	K:PicnicTable(-14, 0.25, 21.5, 0, FENCE)
	K:Umbrella(-14, 0.25, 21.5, rgb(240, 110, 90))
	for _, x in ipairs({ -29.5, -4.5 }) do
		K:Box(x - 0.3, 0.25, 25.4, x + 0.3, 9, 26, FENCE, M.Wood, { n = "LightPost" })
	end
	for i = 0, 7 do
		local x = -28 + i * 3.2
		K:Ball(x, 8.4 - math.sin(i / 7 * math.pi) * 1.2, 25.7, 0.6, i % 2 == 0 and rgb(255, 220, 120) or accent, M.Neon, { n = "StringLight" })
	end
	K:Light(-17, 7.5, 25.7, C.Warm, 24, 1, { n = "PatioLight", shape = "Ball", size = Vector3.new(0.8, 0.8, 0.8) })
	K:Box(-8, 0.25, 18, -6, 2, 20, rgb(80, 160, 200), M.Plastic, { n = "Cooler" })
	K:Palm(8, 25, 0.7)
	K:Palm(24, 24, 0.75)
	K:Hammock(16, 0, 24.5, 0, accent, 11)
	K:Asset("FlamingoStatue", 26, 18.5, 0.16, 210)
	K:Asset("FlamingoStatue", 28, 21, 0.14, 160)
	K:Box(2, 0, 27, 12, 1, 28.6, rgb(120, 90, 60), M.Wood, { n = "GardenBed" })
	for i = 0, 3 do
		K:Bush(3.2 + i * 2.6, 27.8, 1.8, ({ rgb(240, 90, 120), rgb(250, 210, 80), rgb(240, 90, 120), rgb(110, 180, 90) })[i + 1], 1)
	end

	-- Front yard: palms, bushes, mailbox, sale sign.
	K:Palm(-29, -24, 0.85)
	K:Palm(1, -20, 0.7)
	for _, x in ipairs({ -28, -12.5, -8, -3.5 }) do
		K:Bush(x, -13.6, 2.4, rgb(70, 160, 90))
	end
	K:Mailbox(-24.5, -28.5, 0, accent)
	K:SaleSign(-12, -27.5, 0, def)
end
