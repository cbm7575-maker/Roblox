-- Mansion (ModuleScript, ServerScriptService.Services.Houses.Mansion)
-- Flamingo Beach Mansion ($1.2M, 8 cars, the biggest garage): a three-level modern beach house in white
-- stucco, glass and teak, raised the Florida way over a ground floor that is mostly an eight-car
-- SHOWROOM garage behind four glass doors (neon under them after dark). Level 2 cantilevers over the
-- motor court, level 3 steps back behind a glass-railed terrace, and the roof carries a pink neon
-- flamingo and the name. Out back, toward the sea: a pool deck at level 2 with an infinity pool, a spa
-- and a pool bar under a pergola, over a shaded beach cabana with a lounge and an outdoor bar, and a
-- stair down to the sand. Inside: a foyer with a koi pond, a home cinema, a stair core up through all
-- three floors to the roof; on level 2 one great room (living, dining, kitchen, a neon bar) with glass
-- walls onto the pool and a game room (arcade, pool table); on level 3 the master suite (wardrobe, a
-- tub by the window) and two guest rooms; on the roof a raised spa, loungers and a DJ booth.
-- Drawn by HouseBuilder (lot space: front = -Z; the beach and the sea are behind, +Z).

local HouseBuilder = require(script.Parent.Parent.HouseBuilder)

local P, M, rgb = HouseBuilder.P, HouseBuilder.M, HouseBuilder.rgb
local DETAIL = HouseBuilder.DETAIL
local Row = HouseBuilder.Row

local X0, X1 = -54, 56 -- the building, side to side
local Z0, Z1 = -16, 22 -- ground floor front and back
local GX = 2 -- the garage's left wall (the garage is x 2..56)
local G0 = 0.6 -- ground floor top (the garage floor is 0.4)
local L2, L3, RF = 16, 30, 44 -- floor tops: level 2, level 3, the roof
local C2Z0 = -20 -- level 2 cantilevers 4 over the front
local C3Z0 = -12 -- level 3 steps back 4 behind the front
local C3X1 = 40 -- level 3 ends here (the game room's roof is a terrace)
local CORE = { -54, -44 } -- the stair core, x
local DECK = 40 -- the pool deck's back edge

return function(K, home)
	local white = rgb(244, 242, 238)
	local teak = rgb(168, 120, 78)
	local glassFrame = rgb(52, 54, 60)
	local pink = home.Trim
	local theme = home.Theme
	local sand = P.Sand
	local door = K.door -- (-26, 0.6, -16)
	local marble = rgb(238, 236, 232)
	local dark = rgb(30, 30, 34)

	local pools = { { -48, -8, 24, 36 }, { 0, 12, 28, 36 } }
	-- Ground: sand, the paved motor court, the front walk. Inside, the copy's ground under it.
	K.out.ground = K:Box("Sand", -55, 57, 0, 0.2, -35, 40, sand, M.Sand)
	K:Box("MotorCourt", -38, 57, 0.2, 0.3, -35, Z0, rgb(206, 198, 184), M.Cobblestone)
	K:Box("Walk", door.X - 4, door.X + 4, 0.2, 0.3, -35, -22, rgb(206, 198, 184), M.Cobblestone)
	if K.inside then
		K:Box("Base", -60, 60, -2, 0, -40, 40, sand, M.Sand)
	end
	local S = K
	local Y = K:In("Yard")

	-- Ground floor: the foyer's glass front with the pivot front door, the four glass garage doors, a
	-- white wall between, the back wall to the cabana.
	S:Box("GroundSlab", X0, X1, 0.2, G0, Z0, Z1, marble, M.Marble)
	local gdoors = { { 4, 15 }, { 17, 28 }, { 30, 41 }, { 43, 54 } }
	local front = {
		{ -42, door.X - 3.4, G0 + 0.4, L2 - 2, "pane", bars = 2 }, { door.X - 3, door.X + 3, G0, G0 + 11, "none" },
		{ door.X - 3, door.X + 3, G0 + 11.8, L2 - 2, "pane" }, { door.X + 3.4, -6, G0 + 0.4, L2 - 2, "pane", bars = 3 },
	}
	for _, d in ipairs(gdoors) do
		table.insert(front, { d[1], d[2], 0.4, 11, "none" })
	end
	S:WallX(Z0 + 0.5, X0, X1, 0.2, L2 - 1, 1, white, M.Plaster, front, { out = "-Z", frame = glassFrame })
	S:WallX(Z1 - 0.5, X0, X1, 0.2, L2 - 1, 1, white, M.Plaster, Row(GX, X1, 3, 10, 5, 12, "win"), { out = "+Z", frame = glassFrame })
	S:WallZ(X0 + 0.5, Z0 + 1, Z1 - 1, 0.2, L2 - 1, 1, white, M.Plaster, { { -6, 14, 3, 13, "pane", bars = 3 } }, { out = "-X", frame = glassFrame })
	S:WallZ(X1 - 0.5, Z0 + 1, Z1 - 1, 0.2, L2 - 1, 1, white, M.Plaster, { { -10, 18, 4, 12, "pane", bars = 3 } }, { out = "+X", frame = glassFrame })
	for i, d in ipairs(gdoors) do
		S:Box("GarageDoor", d[1], d[2], 0.4, 11, Z0, Z0 + 0.3, rgb(46, 52, 58), M.Glass, { Transparency = K.inside and 0.4 or 0.15, Reflectance = 0.15 })
		for r = 1, 3 do
			local y = 0.4 + r * 10.6 / 4
			S:Deco("DoorFrame", d[1], d[2], y - 0.12, y + 0.12, Z0 - 0.15, Z0, glassFrame, M.Metal)
		end
		S:Neon(d[1], d[2], 0.3, 0.55, Z0 - 0.6, Z0 - 0.2, pink)
		S:Deco("Fin", d[2], d[2] + 2, 0.2, L2 - 1, Z0 - 1.2, Z0, white, M.Plaster)
		if i == 1 then
			S:Deco("Fin", d[1] - 2, d[1], 0.2, L2 - 1, Z0 - 1.2, Z0, white, M.Plaster)
		end
	end
	K:FrontDoor(6, 11, 1, rgb(60, 66, 72), M.Glass, teak, M.Wood, { glass = false })
	S:Deco("DoorHandle", door.X + 1.6, door.X + 2, G0 + 2, G0 + 8, Z0 - 0.7, Z0 - 0.3, P.Brass, M.Metal)

	-- Level 2: a glass band right round, cantilevered 4 over the front on a white slab with a pink neon
	-- line under its edge after dark; sliding glass doors onto the pool deck at the back.
	S:Slab("L2Slab", X0, X1, L2 - 1, L2, C2Z0, Z1, white, M.Concrete, K.inside and { { -53, -49, -12, 12.4 } } or nil)
	S:Neon(X0, X1, L2 - 1.3, L2 - 1, C2Z0 - 0.1, C2Z0 + 0.3, pink)
	S:WallX(C2Z0 + 0.3, X0, X1, L2, L3 - 1, 0.6, white, M.Plaster, { { X0 + 1, X1 - 1, L2 + 0.6, L3 - 2, "pane", bars = 10 } }, { out = "-Z", frame = glassFrame })
	S:WallX(Z1 - 0.3, X0, X1, L2, L3 - 1, 0.6, white, M.Plaster, {
		{ CORE[2] + 1, -12, L2, L3 - 2, "pane", bars = 3 }, { -12, 4, L2, L3 - 2, "exit", color = rgb(60, 66, 72), mat = M.Glass },
		{ 4, X1 - 1, L2, L3 - 2, "pane", bars = 5 },
	}, { out = "+Z", frame = glassFrame })
	S:WallZ(X0 + 0.3, C2Z0 + 0.6, Z1 - 0.6, L2, L3 - 1, 0.6, white, M.Plaster, { { C2Z0 + 2, Z1 - 2, L2 + 3, L3 - 3, "win", bars = 3 } }, { out = "-X", frame = glassFrame })
	S:WallZ(X1 - 0.3, C2Z0 + 0.6, Z1 - 0.6, L2, L3 - 1, 0.6, white, M.Plaster, { { C2Z0 + 2, Z1 - 2, L2 + 0.6, L3 - 2, "pane", bars = 3 } }, { out = "+X", frame = glassFrame })
	-- Level 3: set back, glass with teak fins, the master's balcony along the front on level 2's roof,
	-- the game room's roof a terrace.
	S:Slab("L3Slab", X0, X1, L3 - 1, L3, C2Z0, Z1, white, M.Concrete, K.inside and { { -49, -45, -9.4, 12 } } or nil)
	S:Box("L3Deck", X0, X1, L3 - 0.05, L3, C2Z0, C3Z0, teak, M.WoodPlanks, DETAIL)
	S:WallX(C3Z0 + 0.3, X0, C3X1, L3, RF - 1, 0.6, white, M.Plaster, { { X0 + 1, C3X1 - 1, L3 + 0.6, RF - 2, "pane", bars = 9 } }, { out = "-Z", frame = glassFrame })
	S:WallX(Z1 - 0.3, X0, C3X1, L3, RF - 1, 0.6, white, M.Plaster, { { CORE[2] + 1, C3X1 - 1, L3 + 0.6, RF - 2, "pane", bars = 8 } }, { out = "+Z", frame = glassFrame })
	S:WallZ(X0 + 0.3, C3Z0 + 0.6, Z1 - 0.6, L3, RF - 1, 0.6, white, M.Plaster, {}, { out = "-X" })
	S:WallZ(C3X1 - 0.3, C3Z0 + 0.6, Z1 - 0.6, L3, RF - 1, 0.6, white, M.Plaster, { { -4, 4, L3, L3 + 9.6, "exit", color = rgb(60, 66, 72), mat = M.Glass }, { 6, 18, L3 + 2, RF - 3, "win" } }, { out = "+X", frame = glassFrame })
	for x = X0 + 6, C3X1 - 4, 8 do
		S:Deco("TeakFin", x - 0.4, x + 0.4, L3, RF - 1, C3Z0 - 1.2, C3Z0, teak, M.WoodPlanks)
	end
	K:Rail(X0, C2Z0, X1, C2Z0, L3, 3.6, "glass", { color = glassFrame, guard = L3 + 16 })
	K:Rail(X0, C2Z0, X0, C3Z0, L3, 3.6, "glass", { color = glassFrame, guard = L3 + 16 })
	K:Rail(X1, C2Z0, X1, Z1, L3, 3.6, "glass", { color = glassFrame, guard = L3 + 16 })
	K:Rail(C3X1, Z1, X1, Z1, L3, 3.6, "glass", { color = glassFrame, guard = L3 + 16 })
	-- The roof: a white slab with a pink neon edge, the name and a neon flamingo on the front.
	S:Slab("Roof", X0 - 0.6, C3X1 + 0.6, RF - 1, RF, C3Z0 - 0.6, Z1 + 0.6, white, M.Concrete, K.inside and { { -53, -49, -9, 12.4 } } or nil)
	-- The stair's bulkhead on the roof (its door side open toward +X at the top of the stair).
	if K.inside then
		S:Box("Bulkhead", -54, -53.4, RF, RF + 10, -10, 14, white, M.Plaster)
		S:Box("Bulkhead", -48.6, -48, RF, RF + 10, -10, 7, white, M.Plaster)
		S:Box("Bulkhead", -54, -48, RF, RF + 10, -10, -9.4, white, M.Plaster)
		S:Box("Bulkhead", -54, -48, RF, RF + 10, 13.4, 14, white, M.Plaster)
		S:Box("BulkheadRoof", -54.4, -47.6, RF + 10, RF + 10.6, -10.4, 14.4, white, M.Concrete)
	else
		S:Box("Bulkhead", -54, -48, RF, RF + 10, -10, 14, white, M.Plaster)
		S:Box("BulkheadRoof", -54.4, -47.6, RF + 10, RF + 10.6, -10.4, 14.4, white, M.Concrete)
	end
	S:Neon(X0 - 0.6, C3X1 + 0.6, RF - 0.4, RF, C3Z0 - 1, C3Z0 - 0.6, pink)
	local nameBoard = S:Box("RoofName", -30, 6, RF + 1, RF + 6, C3Z0 + 0.6, C3Z0 + 1, white, M.SmoothPlastic, HouseBuilder.Merge(DETAIL, { Transparency = 1 }))
	HouseBuilder.SignGui(nameBoard, Enum.NormalId.Front, "FLAMINGO BEACH", nil, pink)
	-- A giant pink flamingo on the roof (the city art's flamingo statue), lit pink from below after dark;
	-- without the statue, a neon flamingo (dark metal by day).
	local fl = S:Sub(16, RF, C3Z0 + 3, 0)
	if fl:Asset("FlamingoStatue", 0, 0, 0.45, 200) then
		fl:Lamp("FlamingoUplight", -1.5, 1.5, 0, 0.6, -3, -1.6, pink, 26, 1.2)
	else
		local body = HouseBuilder.NightNeon(fl:Ball("NeonFlamingo", 0, 6, 0, 4.4, P.TrimDay, M.Metal, DETAIL), pink)
		K:Light(body, pink, 30, 1.2)
		HouseBuilder.NightNeon(fl:Ball("NeonFlamingo", -3.2, 12.4, 0, 2.2, P.TrimDay, M.Metal, DETAIL), pink)
		for _, b in ipairs({ { -2.8, 7.4, -3.4, 12, 0.7 }, { -4.2, 12.6, -5.8, 12, 0.5 }, { 0.2, 4, 0.2, 0, 0.4 }, { 1, 4.6, 2.8, 2.4, 0.4 } }) do
			HouseBuilder.NightNeon(fl:Bar("NeonFlamingo", b[1], b[2], 0, b[3], b[4], 0, b[5], P.TrimDay, M.Metal), pink)
		end
	end

	-- The stair core's tall glass slot on the left end, the roof's DJ booth, the raised roof spa.
	S:Window(X0 - 0.4, X0 - 0.1, L2 + 1, RF - 2, -10, 8, "-X", { lit = false })

	-- Motor court: a planter with the flamingo statue, palms, bollards, the sign.
	Y:Box("Planter", -50, -38, 0.2, 2, -32, -22, white, M.Concrete)
	Y:Box("PlanterSand", -49.6, -38.4, 2, 2.1, -31.6, -22.4, sand, M.Sand, DETAIL)
	if not Y:Asset("FlamingoStatue", -44, -27, 0.32, 160, 2) then
		HouseBuilder.NightNeon(Y:Ball("Flamingo", -44, 6, -27, 3, P.TrimDay, M.Metal, DETAIL), pink)
	end
	Y:Palm(-52, -33, 22, math.rad(30))
	Y:Palm(-36, -33, 18, math.rad(200))
	Y:Palm(-14, -33, 20, math.rad(120))
	Y:Palm(52.5, -26, 20, math.rad(300))
	Y:Bollards({ { -6, -34.4 }, { 56, -34.4 }, { door.X - 5, -34.4 } })
	K:StreetSign(-6 - 9, -29, white, M.Concrete)

	-- Out back: the pool deck at level 2 over the beach cabana, the infinity pool and the spa, a pool
	-- bar under a pergola, loungers, the stair down to the sand, glass rails with a guard above.
	local deckHoles = { { 50, 54, 23, 39 } }
	if K.inside then
		for _, p in ipairs(pools) do
			table.insert(deckHoles, p)
		end
	end
	S:Slab("PoolDeck", X0, X1, L2 - 1, L2, Z1, DECK, white, M.Concrete, deckHoles)
	S:Slab("DeckBoards", X0, X1, L2 - 0.02, L2 + 0.02, Z1, DECK, teak, M.WoodPlanks, deckHoles, DETAIL)
	S:Box("PoolPlinth", X0, -6, 0.2, 7.4, Z1, DECK, white, M.Plaster)
	-- Teak slats on the plinth's beach face and a neon line along it after dark.
	for x = X0 + 1, -7, 2 do
		S:Deco("PlinthSlat", x - 0.5, x + 0.5, 0.6, 7, DECK, DECK + 0.3, teak, M.WoodPlanks)
	end
	S:Neon(X0, -6, 7.4, 7.7, DECK, DECK + 0.4, theme)

	for _, x in ipairs({ -2, 18, 36, 56 }) do
		S:Box("Column", x - 0.8, x + 0.8, 0.2, L2 - 1, DECK - 1.6, DECK, white, M.Plaster)
	end
	local D = K:Sub(0, L2, 0, 0)
	D:Pool(-48, -8, 24, 36, 8, { tile = rgb(40, 150, 200), light = theme, coping = white })
	D:Pool(0, 12, 28, 36, 4, { tile = rgb(40, 150, 200), light = pink, coping = white, step = false })
	S:Neon(-48, -8, L2 - 1.4, L2 - 1.1, DECK - 0.2, DECK + 0.1, theme) -- the infinity edge glows over the sand
	local DY = K:In("Yard"):Sub(0, L2, 0, 0)
	for i, x in ipairs({ -44, -37, -30, -23, -16 }) do
		DY:Lounger(x, 0, 38.4 - 0.6, 180, i % 2 == 0 and pink:Lerp(P.White, 0.5) or P.White)
	end
	for _, x in ipairs({ -40.5, -26.5 }) do
		DY:Umbrella(x, 0, 37.8, pink:Lerp(P.White, 0.6), 7)
	end
	local bar = DY:Sub(32, 0, 31, 0)
	for _, c in ipairs({ { -10, -5 }, { 10, -5 }, { -10, 5 }, { 10, 5 } }) do
		bar:Box("PergolaPost", c[1] - 0.5, c[1] + 0.5, 0, 10, c[2] - 0.5, c[2] + 0.5, white, M.Plaster)
	end
	for i = 0, 8 do
		bar:Deco("PergolaSlat", -10.5 + i * 2.6, -9.9 + i * 2.6, 10, 10.6, -5.5, 5.5, teak, M.Wood)
	end
	bar:Box("PoolBar", -7, 7, 0, 3.8, 2, 4.4, teak, M.WoodPlanks)
	bar:Deco("PoolBarTop", -7.3, 7.3, 3.8, 4.2, 1.6, 4.8, marble, M.Marble)
	bar:Neon(-7, 7, 0.4, 0.7, 1.9, 2, pink)
	for i = 0, 3 do
		bar:Cyl("Stool", -5 + i * 3.4, 0, 2.8, 3.2, 1.8, white, M.Leather, DETAIL)
		bar:Cyl("StoolLeg", -5 + i * 3.4, 0, 0, 2.8, 0.35, P.Steel, M.Metal, DETAIL)
	end
	bar:Lamp("BarLight", -1, 1, 9, 9.6, -1, 1, P.Warm, 24, 0.8)
	K:Rail(X0, DECK, X1, DECK, L2, 3.6, "glass", { color = glassFrame, guard = L2 + 12 })
	K:Rail(X0, Z1, X0, DECK, L2, 3.6, "glass", { color = glassFrame, guard = L2 + 12 })
	K:Rail(X1, Z1, X1, DECK, L2, 3.6, "glass", { color = glassFrame, guard = L2 + 12 })
	K:Rail(49.6, 23, 49.6, 39, L2, 3.6, "glass", { color = glassFrame })
	K:Rail(49.6, 23, 54, 23, L2, 3.6, "glass", { color = glassFrame })
	K:Stairs(52, DECK - 1, "-Z", 4, G0, L2, white, M.Concrete, { tread = 1 })
	for _, p in ipairs({ { -52, 24 }, { 47, 24 } }) do
		DY:Box("Planter", p[1] - 1.8, p[1] + 1.8, 0, 2.4, p[2] - 1.8, p[2] + 1.8, white, M.Concrete)
		DY:Palm(p[1], p[2], 11, nil, 2.4)
	end
	-- The beach cabana under the deck: a lounge, an outdoor bar, outdoor showers, surfboards.
	local CB = K:In("Yard")
	CB:Box("CabanaFloor", -6, X1, 0.2, G0, Z1, DECK, rgb(206, 198, 184), M.Limestone)
	CB:Sofa(10, G0, 31, 180, 12, white, { pillows = pink, seats = 0 })
	CB:Box("CabanaSofa", 4, 16, G0, G0 + 2, 32.2, 35.8, white, M.Fabric)
	CB:Box("CabanaBack", 4, 16, G0 + 2, G0 + 4.6, 35, 35.8, white, M.Fabric)
	CB:Box("CabanaTable", 7, 13, G0, G0 + 1.8, 27, 30, teak, M.WoodPlanks)
	CB:Box("OutdoorBar", 24, 38, G0, G0 + 3.8, 24, 27, teak, M.WoodPlanks)
	CB:Deco("OutdoorBarTop", 23.7, 38.3, G0 + 3.8, G0 + 4.2, 23.7, 27.3, marble, M.Marble)
	CB:Neon(24, 38, G0 + 0.4, G0 + 0.7, 27.3, 27.4, theme)
	for i, c in ipairs({ pink, theme, rgb(250, 210, 90) }) do
		CB:Deco("Surfboard", -4.6, -4.2, G0 + 1, G0 + 10, 24 + i * 4, 27 + i * 4, c, M.SmoothPlastic)
	end
	CB:Cyl("ShowerPost", 46, 38, G0, G0 + 9, 0.4, P.Steel, M.Metal, DETAIL)
	CB:Deco("ShowerHead", 45.4, 46.6, G0 + 8.6, G0 + 9, 37.4, 38.6, P.Steel, M.Metal)
	CB:Lamp("CabanaLight", 14, 16, L2 - 1.6, L2 - 1.2, 30, 32, P.Warm, 26, 0.8)

	-- The roof: a raised spa (real water), loungers, a DJ booth with neon, glass rails.
	local RT = K:Sub(0, RF + 4, 0, 0)
	if K.lot then
		S:Box("SpaBase", -24.6, -11.4, RF, RF + 4, 3.4, 16.6, white, M.Plaster)
	end
	RT:Pool(-24, -12, 4, 16, 4, { tile = rgb(40, 150, 200), light = pink, coping = white, step = false })
	S:Box("SpaSteps", -12, -9, RF, RF + 2, 7, 13, white, M.Concrete)
	S:Box("SpaSteps", -12, -10.5, RF + 2, RF + 4, 7, 13, white, M.Concrete)
	local RY = K:In("Yard"):Sub(0, RF, 0, 0)
	for i, x in ipairs({ -38, -33, -4, 1 }) do
		RY:Lounger(x, 0, 14, 180, i % 2 == 0 and pink:Lerp(P.White, 0.5) or P.White)
	end
	local dj = RY:Sub(20, 0, 10, 180)
	dj:Box("DJBooth", -4, 4, 0, 3.8, -1.6, 1.6, dark, M.Metal)
	dj:Neon(-4, 4, 3.4, 3.8, -1.7, -1.6, pink)
	dj:Deco("Decks", -3, 3, 3.8, 4.1, -1.2, 1.2, P.Black, M.SmoothPlastic)
	for _, x in ipairs({ -6, 6 }) do
		dj:Box("Speaker", x - 1.2, x + 1.2, 0, 6, -1.2, 1.2, P.Black, M.Fabric)
	end
	K:Rail(X0 + 1, C3Z0 + 0.6, C3X1 - 0.6, C3Z0 + 0.6, RF, 3.6, "glass", { color = glassFrame, guard = RF + 16 })
	K:Rail(X0 + 1, Z1 - 0.6, C3X1 - 0.6, Z1 - 0.6, RF, 3.6, "glass", { color = glassFrame, guard = RF + 16 })
	K:Rail(X0 + 1, C3Z0 + 0.6, X0 + 1, Z1 - 0.6, RF, 3.6, "glass", { color = glassFrame, guard = RF + 16 })
	K:Rail(C3X1 - 0.6, C3Z0 + 0.6, C3X1 - 0.6, Z1 - 0.6, RF, 3.6, "glass", { color = glassFrame, guard = RF + 16 })

	if not K.inside then
		return
	end

	-- Inside ------------------------------------------------------------------------------------------------
	local R = K:In("Rooms")
	local I = K:In("Decor")
	local G = K:In("Garage")
	local plaster = home.InsideWall:Lerp(rgb(248, 244, 244), 0.55)
	-- The stair core (x -54..-44): three straight flights, ground to level 2 (along +Z), level 2 to 3
	-- (along -Z), level 3 to the roof (along +Z), each under a hole in the floor above.
	local SA, SB = -51, -47 -- the two lanes' middles
	K:Stairs(SA, -12, "+Z", 4, G0, L2, marble, M.Marble)
	K:Stairs(SB, 12, "-Z", 4, L2, L3, marble, M.Marble)
	K:Stairs(SA, -9, "+Z", 4, L3, RF, marble, M.Marble)
	R:Bar("Handrail", SA + 2, G0 + 3.4, -12, SA + 2, L2 + 3.4, 12, 0.25, P.Steel, M.Metal)
	R:Bar("Handrail", SA + 2, L3 + 3.4, -9, SA + 2, RF + 3.4, 12, 0.25, P.Steel, M.Metal)
	-- Floors with their stair holes (level 2 over flight 1, level 3 over flight 2, the roof over flight 3).
	R:Slab("L2Floor", X0 + 1, X1 - 1, L2 - 1, L2, C2Z0 + 0.6, Z1 - 0.6, marble, M.Marble, { { -53, -49, -12, 12.4 } })
	R:Slab("L3Floor", X0 + 1, C3X1 - 0.6, L3 - 1, L3, C3Z0 + 0.6, Z1 - 0.6, rgb(190, 160, 120), M.WoodPlanks, { { -49, -45, -9.4, 12 } })
	R:Slab("RoofFloor", X0 + 1, C3X1 - 0.6, RF - 1.2, RF - 1, C3Z0 + 0.6, Z1 - 0.6, P.WarmWhite, M.Plaster, { { -53, -49, -9, 12.4 } })
	K:Rail(-49, -12, -49, 12.4, L2, 3.4, "glass", { color = glassFrame })
	K:Rail(-45, -9.4, -45, 12, L3, 3.4, "glass", { color = glassFrame })
	K:Rail(-49, -9.4, -49, 12, L3, 3.4, "glass", { color = glassFrame })
	R:WallZ(CORE[2], Z0 + 1, Z1 - 1, G0, L2 - 1, 0.5, plaster, M.Plaster, { { -14, -6, G0, G0 + 10, "door" } }, { out = "+X" })
	-- Ceilings.
	R:Box("GroundCeiling", X0 + 1, X1 - 1, L2 - 1.2, L2 - 1, Z0 + 1, Z1 - 1, P.WarmWhite, M.Plaster, DETAIL)
	R:Box("L2Ceiling", X0 + 1, X1 - 1, L3 - 1.2, L3 - 1, C2Z0 + 0.6, Z1 - 0.6, P.WarmWhite, M.Plaster, DETAIL)

	-- Ground floor: the foyer (a koi pond, a glass sculpture, plants), the home cinema behind it (in by the
	-- side aisle, clear of the risers), the door into the garage.
	R:WallX(4, CORE[2], GX - 0.5, G0, L2 - 1, 0.5, plaster, M.Plaster, { { -12, -6, G0, G0 + 10, "door" } }, { out = "-Z" })
	I:Box("KoiPond", -40, -30, G0, G0 + 1.6, -10, -2, white, M.Marble)
	I:Deco("KoiWater", -39.4, -30.6, G0 + 1.6, G0 + 1.7, -9.4, -2.6, rgb(40, 120, 140), M.Glass, { Transparency = 0.2 })
	for i, p in ipairs({ { -37, -7 }, { -33, -4 }, { -35, -5.5 } }) do
		I:Ball("Koi", p[1], G0 + 1.5, p[2], 0.8, i == 2 and P.White or rgb(255, 120, 40), M.SmoothPlastic, DETAIL)
	end
	I:Cyl("Sculpture", -12, -10, G0, G0 + 2, 2, marble, M.Marble)
	I:Ball("SculptureBall", -12, G0 + 4, -10, 4, pink, M.Glass, HouseBuilder.Merge(DETAIL, { Transparency = 0.2 }))
	I:Plant(-42, G0, -13, white, { tall = true })
	I:Plant(-14.5, G0, 1.8, white, { tall = true })
	K:Sub(0, G0, 0, 0):CeilingLight(-24, -6, L2 - 1.2 - G0, 3, 30, 0.45)
	-- Cinema: a big screen on the back wall, three rows of sofas on risers, star lights, a popcorn cart.
	I:Box("CinemaScreen", -38, -10, G0 + 2, G0 + 11, Z1 - 1.4, Z1 - 1.1, rgb(210, 226, 240), M.Neon)
	for row = 0, 2 do
		local y, z = G0 + row, 14.5 - row * 3.9
		if row > 0 then
			R:Box("Riser", -34, -14, G0, y, z - 2, z + 2, dark, M.Carpet)
		end
		-- (Getting up steps into the side aisle: the rows stand too close to stand between them.)
		I:Sofa(-24, y, z, 180, 16, rgb(120, 20, 40), { mat = M.Fabric, seats = 4, exitSide = -1 })
	end
	K:Sub(0, G0, 0, 0):CeilingLight(-24, 12, L2 - 1.2 - G0, 2, 24, 0.25)
	-- Garage showroom: eight bays in two rows, a gloss-black floor with pink neon lines, the garage sign.
	G:Box("ShowroomFloor", GX + 0.5, X1 - 1, 0.4, 0.45, Z0 + 1, Z1 - 1, rgb(24, 24, 28), M.Marble)
	R:WallZ(GX, Z0 + 1, Z1 - 1, G0, L2 - 1, 0.6, plaster, M.Plaster, { { -2, 4, G0, G0 + 10, "door" } }, { out = "+X" })
	for _, x in ipairs({ 8.5, 21.5, 34.5, 47.5 }) do
		K:Bay(x, 0.45, -6, 0)
		K:Bay(x, 0.45, 12, 0)
	end
	for _, x in ipairs({ 15, 28, 41 }) do
		G:Neon(x - 0.15, x + 0.15, 0.5, 0.56, Z0 + 1, Z1 - 1, pink)
	end
	K:GarageSign(29, 11, Z1 - 1.3, 0, 18, 4)
	for _, z in ipairs({ -6, 12 }) do
		local strip = G:Deco("StripLight", GX + 4, X1 - 4, L2 - 1.8, L2 - 1.4, z - 0.6, z + 0.6, rgb(240, 248, 255), M.Neon)
		K:Light(strip, rgb(235, 242, 255), 34, 0.55)
	end

	-- Level 2: the great room (living, dining, kitchen, the bar) and the game room.
	local up = K:Sub(0, L2, 0, 0)
	local U = K:In("Decor"):Sub(0, L2, 0, 0)
	U:Rug(-28, 0, 0, 0, 22, 16, rgb(236, 226, 216))
	U:Sofa(-28, 0, -2, 180, 18, white, { mat = M.Leather, l = 5, pillows = pink, seats = 4 })
	U:Table(-28, 0, 4, 0, 9, 4.5, 1.8, P.ClearGlass, M.Glass, { glass = true })
	U:Plant(-42, 0, -16, white, { tall = true })
	U:Plant(-14, 0, 18, white, { tall = true })
	U:Dining(-2, 0, -6, 90, 14, 5, 5, dark, white, { mat = M.Marble, chairMat = M.Leather, lamp = true })
	U:Kitchen(14, 0, Z1 - 2, 0, 16, white, dark, { upper = white, hood = P.Steel, splash = marble })
	U:Fridge(24, 0, Z1 - 2.4, 0, P.Steel)
	U:Island(14, 0, 10, 0, 14, dark, marble, pink, 4)
	U:Counter(-4, 0, 14, 0, 12, teak, marble, pink)
	local barSign = U:Letters(-4, 11, 19.6, 10, 2, "FLAMINGO BAR", pink, Enum.NormalId.Front)
	barSign.Name = "BarSign"
	R:WallZ(30, C2Z0 + 0.6, Z1 - 0.6, L2, L3 - 1.2, 0.5, plaster, M.Plaster, { { -2, 6, L2, L2 + 10, "door" } }, { out = "+X" })
	for i, c in ipairs({ pink, theme, P.Gold }) do
		U:Arcade(36 + i * 5, 0, Z1 - 2.2, 0, c)
	end
	U:PoolTable(43, 0, 2, 90)
	U:Sofa(46, 0, -12, -90, 12, dark, { mat = M.Leather, pillows = theme, seats = 3 })
	U:TV(54.4, 0, -12, 90, 10, { wall = true, at = 4, glow = theme, title = "RACE NIGHT", sub = "Live from the Port Solana circuit" })
	for _, p in ipairs({ { -32, -4 }, { -4, -4 }, { 14, 4 }, { 43, -2 } }) do
		up:CeilingLight(p[1], p[2], L3 - 1.2 - L2, 2.6, 28, 0.42)
	end
	K:Spawn(-16, L2, 8, 180)

	-- Level 3: the master suite (bed facing the sea, the wardrobe, a sitting area, a tub by the glass),
	-- two guest rooms.
	local T3 = K:In("Decor"):Sub(0, L3, 0, 0)
	R:WallZ(-8, C3Z0 + 0.6, Z1 - 0.6, L3, RF - 1.2, 0.5, plaster, M.Plaster, { { 14, 19, L3, L3 + 9.4, "door" } }, { out = "+X" })
	R:WallZ(16, C3Z0 + 0.6, Z1 - 0.6, L3, RF - 1.2, 0.5, plaster, M.Plaster, { { 14, 19, L3, L3 + 9.4, "door" } }, { out = "+X" })
	R:WallX(13, -8, C3X1 - 0.6, L3, RF - 1.2, 0.5, plaster, M.Plaster, { { 1, 5, L3, L3 + 9.4, "door" }, { 26, 30, L3, L3 + 9.4, "door" } }, { out = "-Z" })
	T3:Bed(-26, 0, 2, 180, 10, 10, white, P.White, pink:Lerp(P.White, 0.4), { headColor = teak, headMat = M.WoodPlanks, head = 8, reading = P.Warm })
	T3:Nightstand(-33, 0, -2.4, 180, teak)
	T3:Nightstand(-19, 0, -2.4, 180, teak)
	K:Sub(0, L3, 0, 0):Closet(-37, 0, Z1 - 2.1, 0, { mirror = -1 })
	T3:Armchair(-14, 0, 16, 135, white, M.Leather)
	T3:Box("Tub", -42, -34, 0, 2.8, -10.6, -6.4, white, M.Marble)
	T3:Deco("TubWater", -41.6, -34.4, 2, 2.85, -10.2, -6.8, P.PoolWater, M.Glass, { Transparency = 0.3 })
	T3:Rug(-26, 0, 10, 0, 12, 6, rgb(236, 226, 216))
	T3:Bed(4, 0, -6, 180, 8, 9, teak, P.White, theme:Lerp(P.White, 0.4), { headColor = white })
	T3:Bed(28, 0, -6, 180, 8, 9, teak, P.White, P.Gold:Lerp(P.White, 0.4), { headColor = white })
	T3:Desk(14.1, 0, 4, 90, teak, dark, theme)
	T3:TV(28, 0, 11.4, 0, 7, { glow = pink })
	for _, p in ipairs({ { -26, 6 }, { 4, 2 }, { 28, 2 } }) do
		K:Sub(0, L3, 0, 0):CeilingLight(p[1], p[2], RF - 1.2 - L3, 2.2, 22, 0.4)
	end

	K:SaleStand(-10, G0, -10, -26, -16)
	K:ParkStand(29, 0.45, 3.3, 29, -16)
	K:Backdrop("beach")
	K:Bounds(-58, 60, -36, 41, -2, RF + 24)
end
