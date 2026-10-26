-- Bungalow (ModuleScript, ServerScriptService.Services.Houses.Bungalow)
-- Palm Hills Bungalow ($60k, 2 cars): an Old Florida cottage. Seafoam lap siding with white corner
-- boards, a silver standing-seam tin roof with a front gable over the porch, a deep front porch on brick
-- piers (white columns and rails, a haint-blue ceiling with a fan, a porch swing, rockers, ferns), Bahama
-- shutters, a white picket fence with a gate, a mailbox and a two-strip "ribbon" driveway to a detached
-- two-car garage out back. Behind the house: a screened back porch, a fenced garden with raised beds, a
-- fire pit ring of chairs, a hammock between palms and string lights.
-- Inside: honey oak floors, a living room with a reading wall of books and a rattan sofa, a dining nook
-- in the bay, a white kitchen, the bedroom with the wardrobe and an iron bed, a bathroom with a claw-foot
-- tub. Drawn by HouseBuilder (lot space: front = -Z).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local P, M, rgb = HouseBuilder.P, HouseBuilder.M, HouseBuilder.rgb
local DETAIL, SHADE = HouseBuilder.DETAIL, HouseBuilder.SHADE

local X0, X1, Z0, Z1 = -48, 10, -12, 20 -- the house's outer faces
local T = 1 -- walls
local F = 1.2 -- the floor (the house stands on piers)
local H = 13.2 -- wall tops (eaves)
local GX0, GX1, GZ0, GZ1 = 20, 50, 6, 34 -- the garage
local GH = 11 -- garage eaves

return function(K, home)
	local siding = home.Wall:Lerp(rgb(238, 232, 222), 0.25):Lerp(rgb(150, 170, 160), 0.15)
	local white = P.White
	local tin = rgb(176, 182, 186)
	local shutter = rgb(52, 112, 116)
	local brick = rgb(150, 86, 66)
	local haint = rgb(176, 214, 222) -- the porch ceiling
	local oak = rgb(196, 150, 96)
	local trim, theme = home.Trim, home.Theme
	local door = K.door -- (-24, 1.2, -12)
	local lawn = P.Lawn

	-- Ground: the lawn, the path to the porch steps, the ribbon driveway (two concrete strips each side).
	K.out.ground = K:Box("Lawn", -55, 55, 0, 0.2, -35, 40, lawn, M.Grass)
	if K.inside then
		K:Box("Base", -60, 60, -2, 0, -40, 40, rgb(110, 96, 80), M.Ground)
	end
	K:Box("Path", door.X - 3, door.X + 3, 0.2, 0.3, -34, -26, P.Paving, M.Pavement)
	for _, x in ipairs({ 22, 31, 36, 45 }) do
		K:Box("Driveway", x, x + 5, 0.2, 0.3, -35, GZ0, P.Concrete, M.Concrete)
	end
	K:Box("Apron", GX0 + 1, GX1 - 1, 0.2, 0.3, -2, GZ0, P.Concrete, M.Concrete)

	-- The house: brick piers under a skirt, lap siding with white corner boards, the windows (white
	-- casings, Bahama shutters on the front), a tin roof with a front gable over the porch.
	local S = K
	S:Box("Skirt", X0, X1, 0.2, F, Z0, Z1, brick:Lerp(rgb(90, 80, 70), 0.3), M.Brick)
	local wo = { sill = white, sillMat = M.WoodPlanks, frame = white, bars = 1, transom = true }
	S:WallX(Z0 + T / 2, X0, X1, F, H, T, siding, M.WoodPlanks, {
		{ door.X - 3, door.X + 3, F, F + 9.5, "none" },
		{ -42, -36, F + 2.6, F + 9, "win" }, { -34, -28, F + 2.6, F + 9, "win" },
		{ -18, -12, F + 2.6, F + 9, "win" }, { -4, 6, F + 2.6, F + 9, "win", bars = 2 },
	}, HouseBuilder.Merge(wo, { out = "-Z", shutters = shutter }))
	S:WallX(Z1 - T / 2, X0, X1, F, H, T, siding, M.WoodPlanks, {
		{ -42, -36, F + 2.6, F + 9, "win" }, { -18, -13, F + 4, F + 8, "win" }, { -4, 0, F, F + 9, "exit", color = white }, { 2, 8, F + 2.6, F + 9, "win" },
	}, HouseBuilder.Merge(wo, { out = "+Z" }))
	S:WallZ(X0 + T / 2, Z0 + T, Z1 - T, F, H, T, siding, M.WoodPlanks, {
		{ -6, 0, F + 2.6, F + 9, "win" }, { 8, 14, F + 2.6, F + 9, "win" },
	}, HouseBuilder.Merge(wo, { out = "-X" }))
	S:WallZ(X1 - T / 2, Z0 + T, Z1 - T, F, H, T, siding, M.WoodPlanks, {
		{ -8, 0, F + 2.6, F + 9, "win" }, { 7, 13, F + 4.4, F + 9, "win" },
	}, HouseBuilder.Merge(wo, { out = "+X" }))
	for _, c in ipairs({ { X0, Z0 }, { X1, Z0 }, { X0, Z1 }, { X1, Z1 } }) do
		S:Deco("CornerBoard", c[1] - 0.6, c[1] + 0.6, F, H, c[2] - 0.6, c[2] + 0.6, white, M.WoodPlanks)
	end
	S:Ring(X0, X1, Z0, Z1, H - 0.8, H, 0.4, white, M.WoodPlanks)
	-- The tin roof: eaves, two long slopes (ridge along X), the front gable over the porch with a vent.
	S:Gable(X0 - 2, X1 + 2, H, Z0 - 2, Z1 + 2, 9, tin, { mat = M.Metal, eave = white })
	S:Box("Ridge", X0 - 2, X1 + 2, H + 9.4, H + 10, (Z0 + Z1) / 2 - 0.6, (Z0 + Z1) / 2 + 0.6, tin:Lerp(P.DarkMetal, 0.3), M.Metal, DETAIL)
	S:Neon(X0 - 2, X1 + 2, H + 0.1, H + 0.5, Z0 - 2.4, Z0 - 2, trim)
	S:Box("Chimney", -40, -36, H, H + 13, 8, 12, brick, M.Brick)
	S:Deco("ChimneyCap", -40.4, -35.6, H + 13, H + 13.5, 7.6, 12.4, rgb(150, 146, 140), M.Concrete)

	-- The porch: a plank deck on brick piers, two steps, white columns, rails (open at the steps), the
	-- haint-blue ceiling under its own gabled tin roof, a ceiling fan, a swing, rockers and ferns.
	local PZ0 = -22
	S:Box("PorchDeck", -46, -2, F - 0.4, F, PZ0, Z0, rgb(150, 112, 78), M.WoodPlanks)
	for _, x in ipairs({ -45, -31, -17, -3 }) do
		S:Box("Pier", x - 1, x + 1, 0.2, F - 0.4, PZ0 + 0.2, PZ0 + 2.2, brick, M.Brick)
		S:Box("Column", x - 0.7, x + 0.7, F, F + 11, PZ0 + 0.5, PZ0 + 1.9, white, M.WoodPlanks)
		S:Deco("ColumnBase", x - 1, x + 1, F, F + 1.2, PZ0 + 0.2, PZ0 + 2.2, white, M.WoodPlanks)
	end
	S:Box("Step", door.X - 4, door.X + 4, 0.2, 0.7, PZ0 - 3, PZ0 - 1.5, rgb(150, 112, 78), M.WoodPlanks)
	S:Box("Step", door.X - 4, door.X + 4, 0.2, F - 0.4, PZ0 - 1.5, PZ0, rgb(150, 112, 78), M.WoodPlanks)
	K:Rail(-45, PZ0 + 1.2, door.X - 4, PZ0 + 1.2, F, 3.4, "posts", { color = white, mat = M.WoodPlanks, every = 1.6 })
	K:Rail(door.X + 4, PZ0 + 1.2, -3, PZ0 + 1.2, F, 3.4, "posts", { color = white, mat = M.WoodPlanks, every = 1.6 })
	K:Rail(-45.8, PZ0 + 1.2, -45.8, Z0, F, 3.4, "posts", { color = white, mat = M.WoodPlanks, every = 1.6 })
	K:Rail(-2.2, PZ0 + 1.2, -2.2, Z0, F, 3.4, "posts", { color = white, mat = M.WoodPlanks, every = 1.6 })
	S:Box("PorchCeiling", -46, -2, F + 11, F + 11.6, PZ0, Z0, haint, M.WoodPlanks)
	S:Box("PorchBeam", -46.5, -1.5, F + 11.6, F + 12.6, PZ0 - 0.5, PZ0 + 2.4, white, M.WoodPlanks)
	S:Wedge("PorchRoof", -47, -1, F + 12.6, F + 14.4, PZ0 - 1, Z0 - 2, tin, M.Metal, "-Z")
	-- A front gable over the steps: two slopes, its triangle in siding, a white vent.
	S:Gable(door.X - 8, door.X + 8, F + 12.6, PZ0 - 1.6, Z0 - 2, 5.5, tin, { mat = M.Metal, alongZ = true })
	S:Wedge("GableEnd", door.X - 7.6, door.X, F + 12.6, F + 18, PZ0 - 1.2, PZ0 - 0.9, siding, M.WoodPlanks, "-X", SHADE)
	S:Wedge("GableEnd", door.X, door.X + 7.6, F + 12.6, F + 18, PZ0 - 1.2, PZ0 - 0.9, siding, M.WoodPlanks, "+X", SHADE)
	S:Deco("GableVent", door.X - 1.6, door.X + 1.6, F + 14, F + 16, PZ0 - 1.4, PZ0 - 1.2, white, M.WoodPlanks)
	S:Neon(-47, -1, F + 12.2, F + 12.6, PZ0 - 1, PZ0 - 0.6, trim)
	-- The front door: a white Craftsman door with glass, a brass knob, a porch light, house numbers.
	K:FrontDoor(5.6, 9.5, T, white, M.WoodPlanks, white, M.WoodPlanks)
	S:WallLamp(door.X - 4, F + 7.2, Z0, P.Warm, 18)
	S:Deco("HouseNumber", door.X + 3.6, door.X + 5.4, F + 6.4, F + 7.4, Z0 - 0.2, Z0, P.Brass, M.Metal)
	local Y = K:In("Yard")
	-- Porch furniture (on the lot and inside: you see it from the front windows).
	local swing = Y:Sub(-40, F, PZ0 + 5, 0)
	swing:Box("PorchSwing", -3, 3, 2.2, 2.6, -1.2, 1.2, white, M.WoodPlanks)
	swing:Deco("SwingBack", -3, 3, 2.6, 4.8, 0.9, 1.2, white, M.WoodPlanks)
	swing:Bar("Chain", -2.8, 2.6, 0, -2.8, 11, 0, 0.12, P.DarkMetal, M.Metal)
	swing:Bar("Chain", 2.8, 2.6, 0, 2.8, 11, 0, 0.12, P.DarkMetal, M.Metal)
	swing:Deco("Cushion", -2.8, 2.8, 2.6, 2.9, -1, 0.8, theme:Lerp(P.Cream, 0.4), M.Fabric)
	for _, x in ipairs({ -13, -8 }) do
		local r = Y:Sub(x, F, PZ0 + 5, 20 - x)
		r:Box("Rocker", -1.2, 1.2, 1.4, 1.8, -1.2, 1.2, white, M.WoodPlanks)
		r:Deco("RockerBack", -1.2, 1.2, 1.8, 5, 1, 1.2, white, M.WoodPlanks)
		r:Deco("Runner", -1.2, -0.9, 0, 1.4, -1.6, 1.6, white, M.WoodPlanks)
		r:Deco("Runner", 0.9, 1.2, 0, 1.4, -1.6, 1.6, white, M.WoodPlanks)
	end
	for _, x in ipairs({ -44, -4.2 }) do
		Y:Cyl("FernPot", x, PZ0 + 3.5, F, F + 2, 2, rgb(170, 100, 70), M.Concrete)
		Y:Ball("Fern", x, F + 3, PZ0 + 3.5, 3.4, rgb(80, 130, 60), M.Grass, DETAIL)
	end
	-- The fan under the porch ceiling.
	Y:Cyl("FanHub", -24, PZ0 + 5, F + 10, F + 11, 1, white, M.Metal, DETAIL)
	for a = 0, 3 do
		Y:Part("Part", "FanBlade", Vector3.new(4.5, 0.15, 1), Y.cf * CFrame.new(-24, F + 10.2, PZ0 + 5) * CFrame.Angles(0, math.rad(a * 90 + 20), 0) * CFrame.new(2.6, 0, 0),
			rgb(150, 112, 78), M.WoodPlanks, DETAIL)
	end

	-- Front yard: a white picket fence (gates at the path and the driveway), flower beds, palms, bushes,
	-- a mailbox and the sign.
	local function picket(a, b, z)
		Y:Box("FenceRail", a, b, 1.2, 1.5, z - 0.15, z + 0.15, white, M.WoodPlanks)
		Y:Box("FenceRail", a, b, 2.8, 3.1, z - 0.15, z + 0.15, white, M.WoodPlanks)
		for x = a + 0.3, b - 0.3, 1.4 do
			Y:Deco("Picket", x - 0.3, x + 0.3, 0.2, 3.8, z - 0.1, z + 0.1, white, M.WoodPlanks)
		end
		Y:Box("FenceGuard", a, b, 0.2, 3.8, z - 0.1, z + 0.1, white, M.SmoothPlastic, HouseBuilder.GHOST)
	end
	picket(-54, door.X - 4, -34)
	picket(door.X + 4, 20, -34)
	K:FlowerBed(-45, -30, -24.5, { rgb(232, 120, 150), rgb(250, 240, 220) })
	K:FlowerBed(-18, -4, -24.5, { rgb(232, 120, 150), rgb(250, 240, 220) })
	Y:Palm(-50, -27, 21, math.rad(40))
	Y:Palm(13, -26, 18, math.rad(200))
	Y:Palm(52, 30, 20, math.rad(110))
	Y:Bush(-52, 18, 4.5)
	Y:Bush(15, 3, 4)
	local mailbox = Y:Sub(18.5, 0.2, -31.5, 90)
	mailbox:Box("MailPost", -0.25, 0.25, 0, 3.6, -0.25, 0.25, white, M.WoodPlanks)
	mailbox:Box("Mailbox", -0.8, 0.8, 3.6, 5, -1.2, 1.2, theme:Lerp(P.Black, 0.3), M.Metal)
	mailbox:Deco("Flag", 0.8, 0.9, 4.4, 5.6, 0.6, 1, rgb(200, 40, 40), M.Metal)
	K:StreetSign(-38, -31.5, white, M.WoodPlanks)

	-- The garage out back: siding, a front gable, two single doors (white panels), a lamp over each, a
	-- side door to the yard.
	local G0 = { sill = white, frame = white, bars = 1 }
	S:Box("GarageSlab", GX0, GX1, 0.2, 0.4, GZ0, GZ1, P.Concrete, M.Concrete)
	S:WallX(GZ0 + 0.5, GX0, GX1, 0.4, GH, T, siding, M.WoodPlanks, { { 22, 34, 0.4, 9.4, "none" }, { 36, 48, 0.4, 9.4, "none" } },
		HouseBuilder.Merge(G0, { out = "-Z" }))
	S:WallX(GZ1 - 0.5, GX0, GX1, 0.4, GH, T, siding, M.WoodPlanks, { { 30, 40, 5, 9, "win" } }, HouseBuilder.Merge(G0, { out = "+Z" }))
	S:WallZ(GX0 + 0.5, GZ0 + T, GZ1 - T, 0.4, GH, T, siding, M.WoodPlanks, { { 23, 27, 0.4, 8.4, "exit", color = white }, { 12, 18, 5, 9, "win" } },
		HouseBuilder.Merge(G0, { out = "-X" }))
	S:WallZ(GX1 - 0.5, GZ0 + T, GZ1 - T, 0.4, GH, T, siding, M.WoodPlanks, { { 14, 24, 5, 9, "win" } }, HouseBuilder.Merge(G0, { out = "+X" }))
	S:Gable(GX0 - 1.5, GX1 + 1.5, GH, GZ0 - 1.5, GZ1 + 1.5, 7, tin, { mat = M.Metal, eave = white, alongZ = true })
	S:Triangle(GX0, GX1, GH, 7 * (GX1 - GX0) / (GX1 - GX0 + 3), GZ0, 0.6, siding, M.WoodPlanks)
	S:Pipe("GableVent", false, GZ0 - 0.3, GZ0, GH + 2.6, (GX0 + GX1) / 2, 2.4, white, M.WoodPlanks, DETAIL)
	for _, d in ipairs({ { 22, 34 }, { 36, 48 } }) do
		S:Box("GarageDoor", d[1], d[2], 0.4, 9.4, GZ0, GZ0 + 0.4, white, M.WoodPlanks)
		for i = 1, 3 do
			local y = 0.4 + i * 9 / 4
			S:Deco("Panel", d[1] + 0.4, d[2] - 0.4, y - 0.1, y + 0.1, GZ0 - 0.15, GZ0, rgb(214, 210, 200), M.WoodPlanks)
		end
		S:Deco("DoorFrame", d[1] - 0.6, d[1], 0.4, 10, GZ0 - 0.3, GZ0, white, M.WoodPlanks)
		S:Deco("DoorFrame", d[2], d[2] + 0.6, 0.4, 10, GZ0 - 0.3, GZ0, white, M.WoodPlanks)
		S:Deco("DoorFrame", d[1], d[2], 9.4, 10, GZ0 - 0.3, GZ0, white, M.WoodPlanks)
		S:WallLamp((d[1] + d[2]) / 2, 10.4, GZ0, P.Warm, d[1] == 22 and 16 or nil)
	end
	S:Neon(GX0 - 1.5, GX1 + 1.5, GH + 0.1, GH + 0.5, GZ0 - 1.9, GZ0 - 1.5, trim)

	-- Back: the screened porch behind the kitchen (a shed roof), the fenced garden: raised beds, a fire
	-- pit with chairs, a hammock between palms, string lights over the yard.
	local SP = { -12, 8, Z1, 30 }
	S:Box("BackPorch", SP[1], SP[2], F - 0.4, F, SP[3], SP[4], rgb(150, 112, 78), M.WoodPlanks)
	for _, x in ipairs({ SP[1] + 0.5, SP[2] - 0.5 }) do
		for _, z in ipairs({ SP[4] - 0.5 }) do
			S:Box("PorchPost", x - 0.5, x + 0.5, F, F + 10, z - 0.5, z + 0.5, white, M.WoodPlanks)
		end
	end
	local screen = { Transparency = 0.7, CanQuery = false, CastShadow = false }
	S:Box("Screen", SP[1] + 1, SP[2] - 1, F + 0.6, F + 10, SP[4] - 0.3, SP[4] - 0.1, rgb(40, 44, 48), M.Glass, screen)
	S:Box("Screen", SP[1], SP[1] + 0.2, F + 0.6, F + 10, SP[3], SP[4] - 0.5, rgb(40, 44, 48), M.Glass, screen)
	S:Box("Screen", SP[2] - 0.2, SP[2], F + 0.6, F + 10, SP[3], SP[4] - 6, rgb(40, 44, 48), M.Glass, screen)
	S:Box("PorchRail", SP[1], SP[2], F, F + 0.6, SP[4] - 0.4, SP[4], white, M.WoodPlanks)
	S:Wedge("PorchRoof", SP[1] - 1, SP[2] + 1, F + 10, F + 12, SP[3], SP[4] + 1.5, tin, M.Metal, "+Z")
	S:Box("Step", SP[2], SP[2] + 3, 0.2, 0.7, SP[4] - 6, SP[4] - 1, rgb(150, 112, 78), M.WoodPlanks)
	-- Garden fence round the back yard (a gate gap by the garage's side door path).
	local fence = rgb(206, 196, 178)
	Y:Box("Fence", -55, 20, 0.2, 6, 39.5, 40, fence, M.WoodPlanks)
	Y:Box("Fence", -55, -54.5, 0.2, 6, Z1 - 4, 40, fence, M.WoodPlanks)
	Y:Box("Fence", 54.5, 55, 0.2, 6, GZ1, 40, fence, M.WoodPlanks)
	Y:Box("Fence", GX1, 55, 0.2, 6, 39.5, 40, fence, M.WoodPlanks)
	Y:Box("Fence", GX0, GX1, 0.2, 6, 39.5, 40, fence, M.WoodPlanks)
	for i, x in ipairs({ -44, -36, -28 }) do
		Y:Box("RaisedBed", x - 3, x + 3, 0.2, 1.8, 26, 34, rgb(140, 104, 72), M.WoodPlanks)
		Y:Deco("Soil", x - 2.6, x + 2.6, 1.8, 1.9, 26.4, 33.6, rgb(86, 64, 46), M.Ground)
		for k = 0, 2 do
			Y:Ball("Veg", x - 1.4 + (k % 2) * 2.8, 2.6, 27.8 + k * 2.2, 1.8, i == 2 and rgb(200, 60, 50) or rgb(90, 150, 60), M.Grass, DETAIL)
		end
	end
	Y:FirePit(-17.5, 0.2, 32)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		local c = Y:Sub(-17.5 + math.cos(a) * 5.5, 0.2, 32 + math.sin(a) * 5.5, -math.deg(a) - 90)
		c:Box("Adirondack", -1.4, 1.4, 1.2, 1.6, -1.6, 1.4, ({ rgb(232, 120, 150), theme, rgb(250, 240, 220), rgb(60, 150, 170) })[i + 1], M.WoodPlanks)
		c:Deco("ChairBack", -1.4, 1.4, 1.6, 5, 1.2, 1.6, ({ rgb(232, 120, 150), theme, rgb(250, 240, 220), rgb(60, 150, 170) })[i + 1], M.WoodPlanks)
	end
	Y:Hammock(-42, 0.2, 21.5, 0, theme:Lerp(P.Cream, 0.3), 12)
	Y:Palm(-50, 30, 19, math.rad(10))
	Y:Palm(-14, 37, 17, math.rad(250))
	for _, p in ipairs({ { -50, 24 }, { -14, 37 }, { 15, 24 } }) do
		Y:Box("LightPole", p[1] - 0.3, p[1] + 0.3, 0.2, 9.6, p[2] - 0.3, p[2] + 0.3, P.Walnut, M.Wood)
	end
	Y:StringLights(-50, 9.4, 24, -14, 9.4, 37, 10, P.Warm)
	Y:StringLights(-14, 9.4, 37, 15, 9.4, 24, 8, P.Warm)

	if not K.inside then
		return
	end

	-- Inside ------------------------------------------------------------------------------------------------
	local R = K:In("Rooms")
	local I = K:In("Decor")
	local G = K:In("Garage")
	local IX0, IX1, IZ0, IZ1 = X0 + T, X1 - T, Z0 + T, Z1 - T
	local plaster = home.InsideWall:Lerp(rgb(244, 238, 228), 0.6)
	R:Box("Floor", IX0, IX1, F - 0.4, F, IZ0, IZ1, oak, M.WoodPlanks)
	R:Box("Ceiling", IX0, IX1, H - 0.8, H, IZ0, IZ1, P.WarmWhite, M.Plaster)
	-- Inner skin of plaster over the siding, so the rooms read as painted walls.
	-- Partitions: bedroom (back-left), bathroom (back-middle), kitchen (back-right, open to the front).
	R:WallX(6, IX0, -8, F, H - 0.8, 0.5, plaster, M.Plaster, { { -26, -22, F, F + 9, "door" }, { -15, -11, F, F + 9, "door" } }, { out = "-Z" })
	R:WallZ(-21, 6.25, IZ1, F, H - 0.8, 0.5, plaster, M.Plaster, {}, { out = "-X" })
	R:WallZ(-8, 6.25, IZ1, F, H - 0.8, 0.5, plaster, M.Plaster, {}, { out = "+X" })
	K:CeilingLight(-34, -3, H - 0.8, 2.6, 26, 0.45)
	K:CeilingLight(-2, -3, H - 0.8, 2.6, 26, 0.45)
	K:CeilingLight(-34, 12, H - 0.8, 2.4, 20, 0.4)
	K:CeilingLight(0, 12, H - 0.8, 2.4, 20, 0.4)

	-- Living room (front-left): the reading wall, a rattan sofa and armchair facing the TV, a rug, a
	-- floor lamp, plants and a ceiling fan.
	local rattan = rgb(196, 160, 110)
	I:Bookshelf(-38, F, 4.95, 0, 12, 10, P.Walnut)
	I:Rug(-40, F, -3, 0, 12, 12, rgb(70, 120, 120))
	I:Sofa(-36, F, -3, 90, 10, rattan, { mat = M.Wood, pillows = rgb(232, 120, 150), seats = 2 })
	I:Armchair(-41, F, -9.4, 0, rattan, M.Wood)
	I:Table(-41.5, F, -3, 90, 6, 3.5, 1.8, rgb(150, 112, 78))
	I:TV(IX0 + 1.2, F, -3, -90, 8, { glow = theme })
	I:FloorLamp(-45, F, 3.2, P.Warm)
	I:Plant(-26, F, -9.5, rgb(170, 100, 70), { tall = true })
	I:Cyl("FanHub", -33, -4, H - 2, H - 0.8, 1, white, M.Metal, DETAIL)
	for a = 0, 3 do
		I:Part("Part", "FanBlade", Vector3.new(4.5, 0.15, 1), I.cf * CFrame.new(-33, H - 1.8, -4) * CFrame.Angles(0, math.rad(a * 90 + 10), 0) * CFrame.new(2.6, 0, 0),
			rgb(150, 112, 78), M.WoodPlanks, DETAIL)
	end
	I:Art(-15, F + 7, IZ0 + 0.3, 180, 6, 4, white, rgb(60, 150, 170))
	-- Dining nook in the front-right bay, the white kitchen behind it.
	I:Table(0, F, -5, 0, 7, 7, 3.2, white, M.WoodPlanks, { round = true })
	for i = 0, 3 do
		local a = i * 90
		local c = I:Sub(0, F, -5, a)
		c:Chair(0, 0, -4.6, 0, white, M.WoodPlanks)
	end
	I:Lamp("Pendant", -1, 1, H - 3, H - 2.2, -6, -4, P.Warm, 18, 0.5)
	I:Kitchen(IX1 - 1.4, F, 10, 90, 12, white, rgb(214, 210, 200), { upper = white, hood = P.Steel, splash = rgb(200, 226, 220) })
	I:Fridge(IX1 - 1.6, F, 1.8, 90, rgb(236, 232, 222))
	I:Island(-1, F, 10, 90, 7, rgb(150, 190, 180), rgb(236, 232, 222), rgb(196, 160, 110), 0)
	K:Spawn(-32, F, 0, -90)

	-- Bedroom (back-left): an iron bed on the left wall, a nightstand, the wardrobe on the back wall, a
	-- dresser and a rug.
	I:Bed(-42, F, 12, -90, 8, 9, P.DarkMetal, P.White, rgb(232, 120, 150), { frameMat = M.Metal, headColor = P.DarkMetal, headMat = M.Metal, head = 5.5 })
	I:Nightstand(-45.4, F, 17.6, -90, P.Walnut)
	K:Closet(-32, F, IZ1 - 2, 0)
	I:Rug(-32, F, 12, 0, 9, 6, rgb(200, 190, 170))
	-- Bathroom (back-middle): a claw-foot tub, a basin, a toilet.
	I:Bath(-14.5, F, IZ1 - 1.7, 0, { tile = rgb(220, 236, 232), vanity = white })

	-- Garage: two bays, a workbench, surfboards on the wall, bikes, an old fridge.
	K:Bay(28, 0.4, 21, 0)
	K:Bay(42, 0.4, 21, 0)
	G:Box("Workbench", GX0 + 1, GX0 + 3.6, 0.4, 4, 8, 20, P.Walnut, M.WoodPlanks)
	for i, c in ipairs({ rgb(232, 120, 150), rgb(60, 150, 170), rgb(250, 210, 90) }) do
		G:Deco("Surfboard", GX1 - 1.4, GX1 - 1, 2, 11 - i * 0.6, 10 + i * 4, 12.6 + i * 4, c, M.SmoothPlastic)
	end
	G:Box("OldFridge", GX0 + 1, GX0 + 4, 0.4, 7.4, 29, 32, rgb(236, 220, 160), M.Metal)
	K:GarageSign(35, 8.4, GZ1 - 1.3, 0, 14, 3.6)
	for _, x in ipairs({ 28, 42 }) do
		local strip = G:Deco("StripLight", x - 3, x + 3, GH - 0.6, GH - 0.3, 20, 22, rgb(240, 248, 255), M.Neon)
		K:Light(strip, rgb(235, 242, 255), 24, 0.5)
	end
	G:Box("GarageCeiling", GX0 + T, GX1 - T, GH - 0.3, GH, GZ0 + T, GZ1 - T, rgb(196, 190, 180), M.WoodPlanks)

	K:SaleStand(-10, F, -3, -24, -12)
	K:ParkStand(35, 0.4, 26, 35, 6)
	K:Backdrop("suburb")
	K:Bounds(-56, 56, -36, 41, -2, 50)
end
