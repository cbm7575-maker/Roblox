-- Penthouse (ModuleScript, ServerScriptService.Services.Houses.Penthouse)
-- Solana Heights Penthouse ($180k, 4 cars): a slim lavender-and-glass tower downtown with the home on
-- its top floor. Outside: a double-height glass lobby under a white canopy with the name, a podium with
-- two garage doors (a car lift brings your cars down), five floors of glass bands between white slabs
-- with balconies, a glass car-lift shaft up the side to a SKY GARAGE (a glass box cantilevered off the
-- top floor on two steel columns), the penthouse behind floor-to-ceiling glass with a pool terrace, and
-- a neon crown. Inside (your copy, up at the top with the city's towers all round): the elevator lobby
-- (the elevator is the way out), an open living room facing the view with a white sectional and a
-- grand piano, a dining table beside the sky garage's glass wall (your cars on show next to dinner), a
-- marble kitchen, the bedroom with the wardrobe and its own TV, a bathroom, and the terrace with a pool
-- you can swim in, loungers, palms and a fire table behind glass railings.
-- Drawn by HouseBuilder (lot space: front = -Z).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local P, M, rgb = HouseBuilder.P, HouseBuilder.M, HouseBuilder.rgb
local DETAIL = HouseBuilder.DETAIL
local Row = HouseBuilder.Row

local PX0, PX1, PZ0, PZ1 = -48, 54, -14, 30 -- the podium
local TX0, TX1, TZ0, TZ1 = -44, 2, -10, 26 -- the tower (and the penthouse)
local GX0, GX1, GZ0, GZ1 = 2, 32, -12, 26 -- the sky garage
local PODIUM = 20 -- podium roof (slab 20..21)
local PH = 92 -- the penthouse floor top
local CEIL = 104 -- its ceiling (roof slab 104..106)
local STORY = 14

return function(K, home)
	local wall = home.Wall:Lerp(rgb(236, 232, 240), 0.35)
	local white = P.White
	local steel = rgb(70, 72, 80)
	local marble = rgb(238, 236, 232)
	local trim, theme = home.Trim, home.Theme
	local door = K.door -- (-20, 0.6, -14)
	local glassOpts = { bars = 3, frame = steel }

	-- Ground: plaza paving with planter beds, the driveway to the two garage doors.
	local pools = K.inside and { { -40, -12, -24, -12 } } or nil
	K.out.ground = K:Box("Plaza", -55, 55, 0, 0.2, -35, 40, P.Paving, M.Pavement)
	K:Box("Driveway", 8, 48, 0.2, 0.3, -35, PZ0, rgb(110, 110, 114), M.Asphalt)
	if K.inside then
		K:Box("Base", -60, 60, -2, 0, -40, 40, rgb(150, 148, 142), M.Concrete)
	end
	local S = K
	local Y = K:In("Yard")

	-- Podium: the glass lobby on the left (double height), the garage on the right behind two dark
	-- doors, a neon strip along its roof edge after dark.
	S:Box("PodiumFloor", PX0, PX1, 0.2, 0.6, PZ0, PZ1, marble, M.Marble)
	S:WallX(PZ0 + 0.5, PX0, PX1, 0.6, PODIUM, 1, wall, M.Plaster, {
		{ -46, door.X - 3.4, 1, PODIUM - 1, "pane", bars = 4 }, { door.X - 3, door.X + 3, 0.6, 10.6, "none" },
		{ door.X - 3, door.X + 3, 11.4, PODIUM - 1, "pane", bars = 1 }, { door.X + 3.4, 4, 1, PODIUM - 1, "pane", bars = 3 },
		{ 10, 26, 0.6, 12.2, "none" }, { 30, 46, 0.6, 12.2, "none" },
	}, HouseBuilder.Merge(glassOpts, { out = "-Z" }))
	S:WallX(PZ1 - 0.5, PX0, PX1, 0.6, PODIUM, 1, wall, M.Plaster, Row(PX0, PX1, 4, 10, 8, 16, "win"), { out = "+Z", frame = steel, bars = 1 })
	S:WallZ(PX0 + 0.5, PZ0 + 1, PZ1 - 1, 0.6, PODIUM, 1, wall, M.Plaster, { { -10, 20, 4, 16, "pane", bars = 3 } }, HouseBuilder.Merge(glassOpts, { out = "-X" }))
	S:WallZ(PX1 - 0.5, PZ0 + 1, PZ1 - 1, 0.6, PODIUM, 1, wall, M.Plaster, Row(PZ0 + 1, PZ1 - 1, 3, 8, 8, 15, "win"), { out = "+X", frame = steel })
	S:FlatRoof(PX0, PX1, PODIUM, PZ0, PZ1, rgb(170, 168, 164), M.Concrete, 0, nil, nil, 0.4)
	S:Neon(PX0 - 0.4, PX1 + 0.4, PODIUM + 0.3, PODIUM + 0.7, PZ0 - 0.8, PZ0 - 0.4, trim)
	K:Rail(PX0, PZ0, TX0, PZ0, PODIUM + 1, 3.6, "glass", { color = steel })
	K:Rail(TX1, PZ0, PX1, PZ0, PODIUM + 1, 3.6, "glass", { color = steel })
	-- Garage doors (dark metal, slats), a lamp over each, a yellow kerb between them.
	for i, d in ipairs({ { 10, 26 }, { 30, 46 } }) do
		S:Box("GarageDoor", d[1], d[2], 0.6, 12.2, PZ0, PZ0 + 0.4, rgb(66, 66, 72), M.Metal)
		for r = 1, 5 do
			local y = 0.6 + r * 11.6 / 6
			S:Deco("Slat", d[1], d[2], y - 0.1, y + 0.1, PZ0 - 0.15, PZ0, rgb(90, 90, 96), M.Metal)
		end
		S:Neon(d[1], d[2], 12.4, 12.8, PZ0 - 0.4, PZ0, theme)
		S:WallLamp((d[1] + d[2]) / 2, 14.2, PZ0, P.Warm, i == 1 and 18 or nil)
	end
	S:Box("Kerb", 27, 29, 0.2, 1, PZ0 - 4, PZ0, rgb(220, 190, 40), M.Concrete, DETAIL)
	-- The lobby: glass doors under a white canopy with the name in letters, planters with palms,
	-- bollard lights.
	if K.lot then
		K:FrontDoor(6, 10, 1, rgb(60, 64, 70), M.Glass, steel, M.Metal, { glass = false })
	else
		S:Box("LobbyDoor", door.X - 3, door.X + 3, 0.6, 10.6, PZ0 - 0.3, PZ0 + 1, rgb(60, 64, 70), M.Glass, { Transparency = 0.4 })
	end
	S:Box("Canopy", door.X - 14, door.X + 14, 12.2, 13.4, PZ0 - 9, PZ0, white, M.Concrete)
	S:Neon(door.X - 14, door.X + 14, 12, 12.2, PZ0 - 9, PZ0 - 8.6, theme)
	S:Letters(door.X, 12.8, PZ0 - 9.2, 24, 1.2, string.upper(home.Name), P.Dark)
	for _, x in ipairs({ door.X - 6, door.X + 6 }) do
		S:Lamp("Downlight", x - 0.8, x + 0.8, 11.9, 12.2, PZ0 - 5.8, PZ0 - 4.2, P.Warm, x < door.X and 18 or nil, 0.8)
	end
	for _, x in ipairs({ -40, 0 }) do
		Y:Box("Planter", x - 4, x + 4, 0.2, 2.2, -24, -17, P.Concrete, M.Concrete)
		Y:Box("PlanterSoil", x - 3.6, x + 3.6, 2.2, 2.3, -23.6, -17.4, rgb(86, 64, 46), M.Ground, DETAIL)
		Y:Palm(x, -20.5, 18, nil, 2.2)
	end
	Y:Bollards({ { 8, -34.4 }, { 48, -34.4 }, { door.X - 4, -34 }, { door.X + 4, -34 } })
	K:StreetSign(-44, -31, steel, M.Metal)

	-- The tower: five floors of glass bands between white slabs (balconies with glass rails across the
	-- front), lavender stucco ends.
	local floors = {}
	for f = 0, 4 do
		table.insert(floors, PODIUM + 1 + f * STORY)
	end
	for _, y0 in ipairs(floors) do
		local y1 = y0 + STORY
		S:WallX(TZ0 + 0.5, TX0, TX1, y0, y1, 1, wall, M.Plaster, { { TX0 + 3, TX1 - 3, y0 + 1.5, y1 - 1.5, "win", bars = 6 } }, { out = "-Z", frame = steel })
		S:WallX(TZ1 - 0.5, TX0, TX1, y0, y1, 1, wall, M.Plaster, Row(TX0, TX1, 3, 10, y0 + 3, y1 - 3, "win"), { out = "+Z", frame = steel, bars = 1 })
		S:WallZ(TX0 + 0.5, TZ0 + 1, TZ1 - 1, y0, y1, 1, wall, M.Plaster, { { TZ0 + 3, TZ1 - 3, y0 + 1.5, y1 - 1.5, "win", bars = 5 } }, { out = "-X", frame = steel })
		S:WallZ(TX1 - 0.5, TZ0 + 1, TZ1 - 1, y0, y1, 1, wall, M.Plaster, { { 16, 24, y0 + 3, y1 - 3, "win" } }, { out = "+X", frame = steel })
		-- The slab between floors, proud of the facade: a balcony with a glass rail along the front (the
		-- top floor's is the terrace).
		if y1 < PH - 2 then
			S:Box("Balcony", TX0 - 1.5, TX1, y1 - 0.6, y1 + 0.6, TZ0 - 4, TZ0, white, M.Concrete)
			S:Box("SlabEdge", TX0 - 1.5, TX0, y1 - 0.6, y1 + 0.6, TZ0, TZ1 + 1.5, white, M.Concrete, DETAIL)
			K:Rail(TX0 - 1.5, TZ0 - 3.8, TX1, TZ0 - 3.8, y1 + 0.6, 3.4, "glass", { color = steel })
			S:Neon(TX0 - 1.5, TX1, y1 - 0.8, y1 - 0.6, TZ0 - 4, TZ0 - 3.6, trim)
		end
	end

	-- The car lift: a glass shaft up the tower's right side, in a steel frame, to the sky garage.
	for _, c in ipairs({ { 2, -2 }, { 14, -2 }, { 2, 14 }, { 14, 14 } }) do
		S:Box("LiftPost", c[1] - 0.6, c[1] + 0.6, PODIUM + 1, PH - 4, c[2] - 0.6, c[2] + 0.6, steel, M.Metal)
	end
	S:Window(2.6, 13.4, PODIUM + 1, PH - 4, -2.2, -1.8, "-Z", { lit = false })
	S:Window(13.8, 14.2, PODIUM + 1, PH - 4, -1.4, 13.4, "+X", { lit = false })
	for y = PODIUM + 8, PH - 8, 14 do
		S:Deco("LiftBand", 1.4, 14.6, y, y + 0.6, -2.6, 14.6, steel, M.Metal)
	end
	S:Neon(13.9, 14.3, PODIUM + 2, PH - 6, -2.3, -1.9, theme)

	-- The penthouse level: glass all round (but the back, where the elevator is), on a slab with the
	-- terrace in front, the sky garage on the right on two steel columns, the roof with a neon crown.
	S:Box("PHSlab", TX0 - 2, GX1, PH - 6, PH - 1, TZ0, GZ1, white, M.Concrete)
	S:Slab("TerraceSlab", TX0 - 2, TX1, PH - 6, PH, -26, TZ0, white, M.Concrete, pools)
	S:Box("TerraceDeck", TX0 - 2, TX1, PH - 0.05, PH, -26, TZ0, rgb(176, 150, 120), M.WoodPlanks, DETAIL)
	for _, z in ipairs({ GZ0 + 1, GZ1 - 1 }) do
		S:Cyl("SkyColumn", GX1 - 1.5, z, PODIUM + 1, PH - 6, 2, steel, M.Metal)
	end
	S:Box("PHFloor", TX0, GX1, PH - 1, PH, TZ0, GZ1, marble, M.Marble)
	S:Box("SkyFloor", GX0, GX1, PH - 6, PH, GZ0, TZ0, marble, M.Marble)
	S:WallX(TZ0 + 0.3, TX0, TX1, PH, CEIL, 0.6, steel, M.Metal, {
		{ TX0 + 0.6, -27, PH, CEIL - 0.6, "pane" }, { -27, -19, PH, CEIL - 2, "exit", color = rgb(60, 64, 70), mat = M.Glass },
		{ -19, TX1 - 0.6, PH, CEIL - 0.6, "pane" },
	}, { out = "-Z", frame = steel, bars = 3 })
	S:WallZ(TX0 + 0.3, TZ0 + 0.6, TZ1 - 0.6, PH, CEIL, 0.6, steel, M.Metal, { { TZ0 + 0.6, TZ1 - 0.6, PH, CEIL - 0.6, "pane" } }, { out = "-X", frame = steel, bars = 4 })
	S:WallX(TZ1 - 0.5, TX0, GX1, PH, CEIL, 1, wall, M.Plaster, {}, { out = "+Z" })
	S:WallZ(TX1, TZ0 + 0.6, TZ1 - 1, PH, CEIL, 0.4, steel, M.Metal, { { TZ0 + 0.6, TZ1 - 1, PH, CEIL - 0.6, "pane" } }, { out = "+X", frame = steel, bars = 4 })
	S:WallX(GZ0 + 0.3, GX0, GX1, PH, CEIL, 0.6, steel, M.Metal, { { GX0 + 0.6, GX1 - 0.6, PH, CEIL - 0.6, "pane" } }, { out = "-Z", frame = steel, bars = 3 })
	S:WallZ(GX1 - 0.3, GZ0 + 0.6, GZ1 - 1, PH, CEIL, 0.6, steel, M.Metal, { { GZ0 + 0.6, GZ1 - 1, PH, CEIL - 0.6, "pane" } }, { out = "+X", frame = steel, bars = 4 })
	S:Box("SkyLeft", GX0, GX0 + 0.6, PH, CEIL, GZ0, TZ0, steel, M.Metal)
	S:FlatRoof(TX0, GX1, CEIL, GZ0, GZ1, white, M.Concrete, 1.4, wall, M.Plaster, 0.5)
	S:Neon(TX0 - 0.5, GX1 + 0.5, CEIL + 2.6, CEIL + 3, GZ0 - 0.9, GZ0 - 0.5, trim)
	S:Neon(TX0 - 0.9, TX0 - 0.5, CEIL + 2.6, CEIL + 3, GZ0 - 0.5, GZ1 + 0.5, trim)
	-- The crown: a fin on the roof with the name in white letters and neon on its edges.
	S:Box("CrownFin", -36, -4, CEIL + 2.4, CEIL + 12, 6, 7, wall, M.Plaster)
	local crown = S:Box("CrownSign", -35, -5, CEIL + 4, CEIL + 10, 5.6, 6, P.Dark, M.Metal)
	HouseBuilder.SignGui(crown, Enum.NormalId.Front, "SOLANA HEIGHTS", nil, P.White)
	S:Neon(-36, -4, CEIL + 12, CEIL + 12.4, 5.6, 7, theme)
	S:Neon(-36.4, -36, CEIL + 2.4, CEIL + 12.4, 5.6, 7, theme)
	S:Neon(-4, -3.6, CEIL + 2.4, CEIL + 12.4, 5.6, 7, theme)
	for _, x in ipairs({ 10, 22 }) do
		S:Box("RoofUnit", x - 3, x + 3, CEIL + 2.4, CEIL + 5, 12, 20, rgb(158, 162, 168), M.Metal)
	end

	-- The terrace: the pool (real water in your copy), loungers, palms in planters, a fire table,
	-- glass railings with an invisible wall above them.
	K:Sub(0, PH, 0, 0):Pool(-40, -12, -24, -12, 4, { tile = rgb(60, 150, 200), light = theme })
	local T = K:In("Yard"):Sub(0, PH, 0, 0)
	for i, x in ipairs({ -8.5, -4.5, -0.5 }) do
		T:Lounger(x, 0, -20, 180, i % 2 == 0 and theme:Lerp(P.Cream, 0.5) or P.White)
	end
	T:Umbrella(-4.5, 0, -14, theme:Lerp(P.White, 0.4), 7)
	for _, p in ipairs({ { -44, -24 }, { -44, -12 }, { 0, -25 } }) do
		T:Box("Planter", p[1] - 1.8, p[1] + 1.8, 0, 2.6, p[2] - 1.8, p[2] + 1.8, white, M.Concrete)
		T:Palm(p[1], p[2], 12, nil, 2.6)
	end
	T:Box("FireTable", -10, -6, 0, 2.4, -11.5, -10.6, rgb(60, 60, 66), M.Slate)
	T:Deco("FireGlow", -9.6, -6.4, 2.4, 2.7, -11.4, -10.7, rgb(255, 140, 50), M.Neon)
	K:Rail(TX0 - 2, -26, TX1, -26, PH, 3.6, "glass", { color = steel, guard = PH + 24 })
	K:Rail(TX0 - 2, -26, TX0 - 2, TZ0, PH, 3.6, "glass", { color = steel, guard = PH + 24 })
	K:Rail(TX1, -26, TX1, GZ0, PH, 3.6, "glass", { color = steel, guard = PH + 24 })
	K:Rail(TX0 - 2, TZ0, TX0, TZ0, PH, 3.6, "glass", { color = steel, guard = PH + 24 })

	if not K.inside then
		return
	end

	-- Inside ------------------------------------------------------------------------------------------------
	local R = K:In("Rooms")
	local I = K:In("Decor"):Sub(0, PH, 0, 0)
	local G = K:In("Garage")
	local B = K:In("Rooms"):Sub(0, PH, 0, 0)
	B:Box("Ceiling", TX0, GX1, CEIL - 0.6 - PH, CEIL - PH, GZ0, GZ1, P.WarmWhite, M.Plaster)
	-- The elevator: steel doors on the back wall (the way out), its frame, a PH floor light, EXIT.
	local ev = { at = Vector3.new(-10, PH, TZ1 - 1), w = 5, h = 9.6 }
	local exit = R:Box("ElevatorDoor", ev.at.X - ev.w / 2, ev.at.X + ev.w / 2, PH, PH + ev.h, TZ1 - 1.4, TZ1 - 1, rgb(176, 178, 184), M.Metal)
	R:Deco("DoorSplit", ev.at.X - 0.05, ev.at.X + 0.05, PH, PH + ev.h, TZ1 - 1.45, TZ1 - 1.35, P.DarkMetal, M.Metal)
	R:Deco("ElevatorFrame", ev.at.X - ev.w / 2 - 0.8, ev.at.X + ev.w / 2 + 0.8, PH, PH + ev.h + 0.8, TZ1 - 1.2, TZ1 - 1, steel, M.Metal)
	local floorSign = R:Box("FloorSign", ev.at.X - 1.2, ev.at.X + 1.2, PH + ev.h + 1, PH + ev.h + 2.2, TZ1 - 1.2, TZ1 - 1, P.Dark, M.SmoothPlastic, DETAIL)
	HouseBuilder.SignGui(floorSign, Enum.NormalId.Front, "PH  ▼  LOBBY", nil, theme)
	local exitSign = R:Box("ExitSign", ev.at.X + 3.4, ev.at.X + 6.4, PH + 8, PH + 9.2, TZ1 - 1.2, TZ1 - 1, rgb(20, 110, 60), M.SmoothPlastic, DETAIL)
	HouseBuilder.SignGui(exitSign, Enum.NormalId.Front, "EXIT", nil, Color3.new(1, 1, 1), nil, 30)
	K.out.exit = exit
	K.out.exitName = "Elevator"

	-- Rooms along the back: the bedroom (left), the bathroom, the elevator lobby, the kitchen (right).
	local plaster = home.InsideWall:Lerp(rgb(246, 244, 250), 0.5)
	B:WallX(10, TX0 + 0.6, -14, 0, CEIL - PH - 0.6, 0.5, plaster, M.Plaster, { { -32, -28, 0, 9.4, "door" }, { -21, -17, 0, 9.4, "door" } }, { out = "-Z" })
	B:WallZ(-26, 10.25, TZ1 - 1, 0, CEIL - PH - 0.6, 0.5, plaster, M.Plaster, {}, { out = "+X" })
	B:WallZ(-14, 10.25, TZ1 - 1, 0, CEIL - PH - 0.6, 0.5, plaster, M.Plaster, {}, { out = "+X" })
	for _, p in ipairs({ { -30, -1 }, { -7, -1 }, { -35, 18 }, { -4, 18 } }) do
		K:Sub(0, PH, 0, 0):CeilingLight(p[1], p[2], CEIL - PH - 0.6, 2.4, 26, 0.4)
	end
	-- Living room facing the view: a white sectional, a glass coffee table, a rug, the grand piano in
	-- the corner, a neon art panel, plants.
	I:Rug(-30, 0, -2, 0, 16, 12, rgb(196, 190, 210))
	I:Sofa(-30, 0, 3, 0, 14, rgb(240, 238, 234), { mat = M.Leather, l = 4, pillows = theme:Lerp(P.White, 0.3), seats = 3 })
	I:Table(-30, 0, -3, 0, 7, 4, 1.8, P.ClearGlass, M.Glass, { glass = true, top = { Transparency = 0.3 } })
	I:Piano(-39, 0, -2, 30)
	I:Plant(-43, 0, 8, rgb(60, 60, 66), { tall = true })
	I:Plant(-15, 0, -8, rgb(60, 60, 66), { tall = true })
	I:Art(-38, 6.5, 9.7, 0, 9, 4.5, P.Dark, rgb(40, 30, 60), theme)
	-- Dining beside the sky garage's glass wall, the kitchen behind it.
	I:Dining(-6, 0, 1, 0, 10, 4, 3, P.Dark, rgb(236, 234, 228), { mat = M.Marble, chairMat = M.Leather, lamp = true })
	I:Kitchen(-2.2, 0, TZ1 - 2.4, 0, 7.2, rgb(40, 40, 46), marble, { upper = rgb(40, 40, 46), hood = P.Steel })
	I:Island(-2.2, 0, 15, 0, 7, rgb(40, 40, 46), marble, theme:Lerp(P.Dark, 0.4), 2)
	K:Spawn(-17, PH, -4, 0)
	-- The bedroom: the bed on the back wall, nightstands, its TV, the wardrobe on the partition.
	I:Bed(-39.3, 0, 19.5, 0, 8, 10, P.Dark, P.White, theme:Lerp(P.Dark, 0.5), { headColor = rgb(200, 196, 210), headMat = M.Fabric, head = 7, reading = P.Warm })
	I:Nightstand(-32.6, 0, 23.6, 0, P.Dark)
	I:TV(-38, 0, 11.5, 180, 7, { glow = theme })
	K:Sub(0, PH, 0, 0):Closet(-27.75, 0, 20, 90, { w = 8 })
	-- The bathroom: a glass shower, a toilet, a vanity, marble tiles.
	I:Bath(-20, 0, TZ1 - 2.6, 0, { shower = true, tile = marble, vanity = P.Dark })

	-- The sky garage: four bays in two rows behind the glass, a hazard-striped car-lift square, strip
	-- lights, the garage sign.
	local sky = K:Sub(0, PH, 0, 0)
	sky:Bay(9, 0, -2.2, 0)
	sky:Bay(23, 0, -2.2, 0)
	sky:Bay(9, 0, 16, 0)
	sky:Bay(23, 0, 16, 0)
	local lift = sky:In("Garage")
	for _, e in ipairs({ { 2.6, 15.4, -11.6, -11.2 }, { 2.6, 15.4, 7.2, 7.6 }, { 2.6, 3, -11.2, 7.2 }, { 15, 15.4, -11.2, 7.2 } }) do
		lift:Deco("LiftEdge", e[1], e[2], 0.06, 0.1, e[3], e[4], rgb(230, 190, 40), M.SmoothPlastic)
	end
	sky:GarageSign(16, 9, TZ1 - 1.3, 0, 14, 3.6)
	for _, z in ipairs({ -2.2, 16 }) do
		local strip = lift:Deco("StripLight", 4, 30, CEIL - PH - 1.2, CEIL - PH - 0.9, z - 0.5, z + 0.5, rgb(240, 248, 255), M.Neon)
		K:Light(strip, rgb(235, 242, 255), 30, 0.5)
	end
	G:Box("GarageBack", GX0 + 0.6, GX1 - 0.6, PH, PH + 0.06, TZ1 - 1.6, TZ1 - 1, rgb(100, 100, 100), M.Concrete, DETAIL)

	sky:SaleStand(-6, 0, -7, -24, -3)
	sky:ParkStand(16, 0, 7.2, 16, -12)
	K:Backdrop("city", { level = PH })
	K:Bounds(-56, 56, -36, 40, PH - 8, PH + 40)
end
