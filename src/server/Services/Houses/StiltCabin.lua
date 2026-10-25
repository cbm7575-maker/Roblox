-- StiltCabin (ModuleScript, ServerScriptService.Services.Houses.StiltCabin)
-- Bayou Stilt Cabin (Gator Glades): a weathered plank cabin raised on stilts over a one-car carport,
-- a screened-in feel porch with string lights, a fire pit, a reedy pond with a gator and cypress trees.
-- One room inside: bed, kitchenette, wood stove and armchair, a little table, fishing trophies.
-- Drawn by HouseBuilder (lot frame: front = -Z); see HouseBuilder for the Kit.

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local M = HouseBuilder.M
local C = HouseBuilder.C
local rgb = HouseBuilder.rgb

local PLANK = rgb(122, 108, 86)
local TRIM = rgb(84, 112, 70)
local ROOF = rgb(150, 92, 64)
local STILT = rgb(78, 58, 42)
local DECK = rgb(140, 112, 80)
local FLOOR = rgb(150, 112, 74)
local MUD = rgb(104, 86, 62)

local F = 10 -- cabin floor top
local TOP = 21 -- eaves

return function(K, def)
	local accent = def.Color
	-- Carport floor and driveway (shell-and-dirt) out to the trail.
	K:Solid(-12, 0, -6, 2, 0.5, 14, C.Concrete, M.Concrete, { n = "GarageFloor" })
	K:Solid(-11, -0.5, -32, 1, 0.5, -6, rgb(170, 160, 140), M.Pebble, { n = "Driveway" })

	-- Stilts (the carport walls stand between the left ones).
	for _, x in ipairs({ -11.6, -4, 4, 11.6 }) do
		for _, z in ipairs({ -11.6, -6, 4, 13.6 }) do
			if x ~= -4 or z == 13.6 then -- keep the carport bay and the driveway clear
				K:Solid(x - 0.6, 0, z - 0.6, x + 0.6, F - 1, z + 0.6, STILT, M.Wood, { n = "Stilt" })
			end
		end
	end
	-- Cross braces under the open (right) half.
	K:Beam(4, 1, 13.6, 11.6, 8, 13.6, 0.4, STILT, M.Wood, { n = "Brace" })
	K:Beam(11.6, 1, -6, 11.6, 8, 4, 0.4, STILT, M.Wood, { n = "Brace" })

	-- Carport: plank walls on three sides, roll-up door at the front.
	K:Solid(-12, 0.5, 13.4, 2, F - 1, 14, PLANK, M.WoodPlanks, { n = "GarageWall" })
	K:Solid(-12, 0.5, -6, -11.4, F - 1, 13.4, PLANK, M.WoodPlanks, { n = "GarageWall" })
	K:Solid(1.4, 0.5, -6, 2, F - 1, 13.4, PLANK, M.WoodPlanks, { n = "GarageWall" })
	K:Solid(-11.4, 8.5, -6.3, 1.4, F - 1, -5.7, PLANK, M.WoodPlanks, { n = "Lintel" })
	K:Solid(-11.4, 0.5, -6.3, -10.5, 8.5, -5.7, PLANK, M.WoodPlanks, { n = "Jamb" })
	K:Solid(0.5, 0.5, -6.3, 1.4, 8.5, -5.7, PLANK, M.WoodPlanks, { n = "Jamb" })
	K:GarageDoor(-5, 0.5, -6, 0, 11, 8, rgb(170, 150, 110), M.WoodPlanks)
	K:Bay(-5, 0.5, 3, 0)
	K:BankPad(-5, 0.5, 12.2, 8, 2, accent)
	-- Garage odds and ends: a workbench and a tackle shelf on the side walls.
	K:Box(-11.4, 0.5, 8, -9.6, 3.4, 13.4, DECK, M.WoodPlanks, { n = "Workbench", c = true })
	K:Box(-11.3, 5, 8.5, -11, 7.5, 13, rgb(210, 90, 60), M.SmoothPlastic, { n = "Tackle" })
	K:Light(-5, 8.3, 6, C.Warm, 16, 1, { n = "GarageBulb" })
	K:Zone(-11.4, 0.5, -5.7, 1.4, F - 1, 13.4)

	-- Cabin floor, porch deck and walls.
	K:Solid(-12.4, F - 1, -6.4, 12.4, F, 14.4, FLOOR, M.WoodPlanks, { n = "Floor" })
	K:Solid(-12.4, F - 0.6, -12.4, 12.4, F, -6.4, DECK, M.WoodPlanks, { n = "Porch" })
	local win = function(a, b)
		return { a, b, F + 3, F + 7.5, glass = rgb(170, 200, 190), mull = 1 }
	end
	K:Walls4(-12, -6, 12, 14, F, TOP, 0.8, PLANK, M.WoodPlanks, {
		front = { { 10, 14, F, F + 8 }, win(3, 7), win(17, 21) },
		back = { win(3, 7), win(14, 20) },
		left = { win(7, 13) },
		right = { win(4, 10) },
	}, { trim = TRIM, frame = TRIM })
	K:Door(0, F, -6, 0, 4, 8, 0.8, { main = true, color = TRIM })
	-- Corner trims and a mossy band under the eaves.
	for _, x in ipairs({ -12.5, 12.5 }) do
		for _, z in ipairs({ -6.5, 14.5 }) do
			K:Box(x - 0.4, F, z - 0.4, x + 0.4, TOP, z + 0.4, TRIM, M.Wood, { n = "CornerTrim" })
		end
	end
	K:Gable(-12, -6, 12, 14, TOP, 6, true, ROOF, M.CorrodedMetal, PLANK, M.WoodPlanks, { over = 1.6, cap = rgb(110, 70, 50) })
	-- Porch roof (shed) on posts, string lights along its edge.
	K:Shed(-12.6, -12.6, 12.6, -6.2, TOP - 3.2, 2.6, ROOF, M.CorrodedMetal, { over = 0.6, flip = true })
	for _, x in ipairs({ -11.8, -4, 4, 11.8 }) do
		K:Box(x - 0.35, F, -12.2, x + 0.35, TOP - 3, -11.5, STILT, M.Wood, { n = "PorchPost", c = true })
	end
	for i = 0, 7 do
		local x = -10.5 + i * 3
		K:Ball(x, TOP - 3.6 - (i % 2) * 0.4, -12, 0.6, i % 2 == 0 and rgb(255, 220, 120) or accent, M.Neon, { n = "StringLight" })
	end
	K:Light(0, F + 8.6, -9, C.Warm, 18, 1.1, { n = "PorchLantern", size = Vector3.new(0.9, 1.3, 0.9) })
	-- Spanish moss dripping off the porch roof, and a glowing BAYOU sign on its fascia.
	for i, x in ipairs({ -11, -7.5, -2.5, 2.5, 7.5, 11 }) do
		K:Box(x - 0.35, TOP - 3.4 - (i % 3), -12.9, x + 0.35, TOP - 2.9, -12.5, rgb(120, 150, 90), M.Grass, { n = "Moss" })
	end
	K:Banner(0, TOP - 1.8, -13.05, 0, 9, 1.6, "BAYOU", accent)
	-- Porch railing (open at the top of the stairs) and a rocking chair.
	K:Rail(-12, -12, 12, -12, F, 3.2, STILT, { every = 4 })
	K:Rail(-12, -12, -12, -6.4, F, 3.2, STILT, { every = 3 })
	K:Rail(12, -12, 12, -9, F, 3.2, STILT, { every = 3 })
	K:Armchair(-8, F, -9.2, 0, rgb(120, 80, 50), M.Wood)
	K:Box(6, F, -10.6, 8, F + 1.6, -8.6, rgb(90, 140, 160), M.Plastic, { n = "Cooler" })

	-- Stairs up the right side, climbing toward the back and stepping onto the porch.
	local run = K:Stairs(14.6, -21, "+Z", 4, 0, F, DECK, M.WoodPlanks)
	K:Beam(16.6, 3.2, -21, 16.6, F + 3, -21 + run, 0.35, STILT, M.Wood, { n = "Handrail", c = true })
	for _, z in ipairs({ -21, -14, -7 }) do
		local h = (z + 21) / run * F
		K:Box(16.4, 0, z - 0.2, 16.8, h + 3, z + 0.2, STILT, M.Wood, { n = "RailPost" })
	end

	-- Inside: one cosy room.
	local I = K:In("Decor")
	I:Rug(-5, F, 0, 0, 8, 6, rgb(150, 60, 50))
	I:Bed(-8, F, 9.1, 0, 6, 8, STILT, rgb(230, 225, 210), rgb(90, 120, 150), { pillow = rgb(240, 235, 220) })
	I:Box(-11.5, F + 2.4, 5.4, -11.3, F + 6, 7, rgb(200, 170, 90), M.Fabric, { n = "Quilt" })
	I:Nightstand(-3.6, F, 12.4, 0, DECK)
	I:Kitchen(4.5, F, 12.2, 0, 7, rgb(96, 120, 92), rgb(200, 190, 170), { topMat = M.Wood })
	I:Fridge(9.8, F, 12, 0, rgb(220, 220, 200))
	I:Box(1.2, F + 8, 12.8, 8, F + 8.3, 13.6, DECK, M.Wood, { n = "Shelf" })
	for i = 0, 3 do
		I:Post(2 + i * 1.6, F + 8.3, 13.2, F + 9.6, 0.8, ({ rgb(220, 120, 60), rgb(120, 180, 90), rgb(230, 200, 80), rgb(150, 90, 160) })[i + 1], M.Glass, { n = "Jar", t = 0.2 })
	end
	-- Wood stove with its pipe through the roof, and an armchair to warm up in.
	I:Box(-11.4, F, -2.4, -8.8, F + 3.4, 0.4, C.Black, M.Metal, { n = "Stove", c = true })
	I:Box(-10.9, F + 0.8, 0.45, -9.3, F + 2.4, 0.5, rgb(255, 120, 40), M.Neon, { n = "StoveFire" })
	I:Post(-10.1, F + 3.4, -1, TOP + 5, 0.8, C.Black, M.Metal, { n = "StovePipe" })
	I:Armchair(-5, F, -1, 90, rgb(140, 90, 60), M.Leather)
	I:Box(-4.6, F, 2.4, -2.6, F + 2.6, 4.4, DECK, M.Wood, { n = "SideTable" })
	-- Table for two by the front window.
	I:Table(7, F, -1.5, 0, 4, 4, 3, DECK, M.Wood)
	I:Chair(7, F, -4.3, 180, STILT, M.Wood)
	I:Chair(7, F, 1.3, 0, STILT, M.Wood)
	-- Fishing rods and a glowing trophy fish on the right wall.
	for i = 0, 2 do
		I:Beam(11.3, F + 1 + i * 0.3, 2 + i * 1.2, 11.3, F + 9, 4 + i * 1.2, 0.15, rgb(60, 50, 40), M.Wood, { n = "Rod" })
	end
	I:Art(11.4, F + 6, 9, 90, 5, 2.4, STILT, rgb(80, 230, 230), true)
	I:Art(-11.4, F + 6.5, 9, 270, 4, 3, STILT, rgb(110, 150, 90), false)
	K:Light(-4, TOP - 1, 4, C.Warm, 22, 1.2, { n = "Bulb", shape = "Ball", size = Vector3.new(1, 1, 1) })
	K:Light(6, TOP - 1, 8, C.Warm, 18, 1, { n = "Bulb", shape = "Ball", size = Vector3.new(1, 1, 1) })
	K:Spawn(-2, F, 3, 180)
	K:Zone(-11.6, F, -5.6, 11.6, TOP, 13.6)

	-- Under the cabin's open half: a hammock and a canoe on the stilts.
	K:Hammock(8, 0, 4, 90, rgb(200, 70, 60), 9)
	K:Beam(4.6, 1.2, -4, 4.6, 6.5, 2.5, 1.6, rgb(200, 120, 60), M.Wood, { n = "Canoe", w = 2.4 })

	-- Yard: muddy patches, a fire pit with log benches, a reedy pond with a gator, cypress trees.
	K:Box(-22, 0, -22, -12, 0.08, -6, MUD, M.Mud, { n = "Mud" })
	K:FirePit(-17, 0, -14, rgb(110, 100, 90))
	K:Beam(-21, 0.6, -11, -21, 0.6, -17, 1.2, STILT, M.Wood, { n = "LogBench", c = true })
	K:Beam(-13.5, 0.6, -19, -20, 0.6, -19, 1.2, STILT, M.Wood, { n = "LogBench", c = true })
	K:Disc(13, 0, 16.5, 10, 0.15, rgb(60, 110, 100), M.Glass, { n = "Pond", t = 0.15 })
	K:Disc(13, 0, 16.5, 11.2, 0.1, MUD, M.Mud, { n = "PondBank" })
	for i = 0, 6 do
		local a = i * 0.9
		K:Post(13 + math.cos(a) * 5.3, 0, 16.5 + math.sin(a) * 5.3, 3 + (i % 3), 0.25, rgb(110, 140, 70), M.Grass, { n = "Reed" })
	end
	K:Asset("Gator", 11, 16, 2.2, 200, 0.1)
	K:Box(17, 0.2, 13, 19.5, 0.6, 20, DECK, M.WoodPlanks, { n = "Dock" })
	if not K:Asset("CypressTree", -16.5, 17, 0.7) then
		K:Palm(-16.5, 17, 0.8)
	end
	K:Asset("CypressTree", 17.5, 6, 0.55)
	K:Asset("TropicalBush", -15, 8, 0.8)
	K:Mailbox(3, -20.5, 0, TRIM)
	K:SaleSign(-17, -20.5, 0, def)
end
