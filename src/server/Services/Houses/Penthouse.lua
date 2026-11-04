-- Penthouse (ModuleScript, ServerScriptService.Services.Houses.Penthouse)
-- Solana Heights Penthouse ($180k, 10 cars): a slim lavender-and-glass tower downtown with the home on
-- its top floor. Outside: a double-height glass lobby under a white canopy with the name, a podium with
-- two garage doors (the way into the owner's underground garage, and where its cars come up), five
-- floors of glass bands between white slabs with balconies, a glass car-lift shaft up the side to the
-- SKY LOUNGE (a glass box cantilevered off the top floor on two steel columns), the penthouse behind
-- floor-to-ceiling glass with a pool terrace, and a neon crown. Inside (your copy, up at the top with
-- the city's towers all round): the elevator lobby (the elevator is the way out; its call panel goes
-- down to the garage), an open living room facing the view with a white sectional and a grand piano, a
-- dining table beside the sky lounge's glass wall, a marble kitchen, the bedroom with the wardrobe and
-- its own TV, a bathroom, and the terrace with a lap pool along the glass rail (a walkway between it and
-- the doors), loungers, palms and a fire table. The sky lounge (through a doorway by the kitchen): a
-- pool table, arcade machines, a sofa facing the view and the car lift (its control post also goes down
-- to the garage).
-- P1, the underground garage (inside only, under the tower): a big concrete parking level with the
-- owner's 10 bays (7 along the back wall, 3 at the front, every car facing the 26-stud aisle), columns,
-- strip lights, the elevator and a street door at the front, and an exit ramp: a tunnel climbing toward
-- the street to an open roll-up door full of daylight. "Drive this" there sits you in the car in its bay
-- (out.bays[i].drive), and driving it into the daylight (out.garage.exit) brings it up out of the podium's
-- garage door onto the street (HousingService). out.garage = { spawn (P1, by the elevator), home (up in
-- the penthouse, by its elevator), exit = { cf, size } (world box), lift / door (P1's elevator and street
-- door: prompts), calls (the parts whose prompts go down), upText }; on the lot the podium's two doors
-- carry the attribute GarageEntry (the owner's "My garage" prompt).
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
-- The terrace's lap pool (multiples of 4: Terrain water): along the glass rail, a walkway behind it. The
-- terrace runs out to TERRACE (its glass rail), so the pool's water can spill a whole voxel under the
-- deck all round and still stay inside the slab.
local POOL = { -40, -16, -24, -16 }
local TERRACE = -30
-- P1, the underground garage: its floor (lot space; the copy's frame sits on the 4-stud grid at y 48, so
-- the floor is at world y 24, well clear of VehicleService's sunk-car line at 0.2) and its layout, in
-- P1's own frame (y = 0 on its floor).
local P1 = -24
local P1X0, P1X1, P1Z0, P1Z1, P1H = -54, 54, -26, 42, 16 -- the hall (inside faces) and its clear height
local RX0, RX1 = 26, 46 -- the exit ramp's lane (the tunnel's inside faces)
local RAMP0, RAMP1, RAMP_UP = -36, -84, 10 -- the ramp climbs RAMP_UP from z RAMP0 to RAMP1
local TUNNEL_END, TUNNEL_TOP = -104, 21 -- the daylight at the end, the tunnel's ceiling

return function(K, home)
	local wall = home.Wall:Lerp(rgb(236, 232, 240), 0.35)
	local white = P.White
	local steel = rgb(70, 72, 80)
	local marble = rgb(238, 236, 232)
	local trim, theme = home.Trim, home.Theme
	local door = K.door -- (-20, 0.6, -14)
	local glassOpts = { bars = 3, frame = steel }

	if K.inside then
		K.stats.maxLights = 32 -- (P1 has no windows: strip lights all the way up its ramp)
	end

	-- Ground: plaza paving with planter beds, the driveway to the two garage doors.
	local pools = K.inside and { POOL } or nil
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
	-- Garage doors (dark metal, slats), a lamp over each, a yellow kerb between them. On the lot they are
	-- the owner's way into P1 (attribute GarageEntry: HousingService puts a "My garage" prompt on each).
	for i, d in ipairs({ { 10, 26 }, { 30, 46 } }) do
		local gdoor = S:Box("GarageDoor", d[1], d[2], 0.6, 12.2, PZ0, PZ0 + 0.4, rgb(66, 66, 72), M.Metal)
		if K.lot and gdoor then
			gdoor:SetAttribute("GarageEntry", true)
		end
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
	S:Slab("TerraceSlab", TX0 - 2, TX1, PH - 6, PH, TERRACE, TZ0, white, M.Concrete, pools)
	-- The deck boards stop at the pool's edge (they used to run right over the water in your copy).
	S:Slab("TerraceDeck", TX0 - 2, TX1, PH - 0.05, PH, TERRACE, TZ0, rgb(176, 150, 120), M.WoodPlanks, pools, DETAIL)
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
	-- The glass wall between the dining room and the sky lounge, with a doorway by the kitchen island.
	S:WallZ(TX1, TZ0 + 0.6, TZ1 - 1, PH, CEIL, 0.4, steel, M.Metal, {
		{ TZ0 + 0.6, 5.5, PH, CEIL - 0.6, "pane" }, { 5.5, 10.5, PH, PH + 10, "door" },
		{ 5.5, 10.5, PH + 10, CEIL - 0.6, "pane" }, { 10.5, TZ1 - 1, PH, CEIL - 0.6, "pane" },
	}, { out = "+X", frame = steel, bars = 3 })
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

	-- The terrace: a lap pool along the glass rail (real water in your copy) with a walkway between it and
	-- the doors, loungers, palms in planters, a fire table, glass railings with an invisible wall above.
	-- (spill / below: the water stays flat right to the tiles, its surface a little under the coping.)
	K:Sub(0, PH, 0, 0):Pool(POOL[1], POOL[2], POOL[3], POOL[4], 4, { tile = rgb(60, 150, 200), light = theme, spill = 4, below = 0.6 })
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
	K:Rail(TX0 - 2, TERRACE, TX1, TERRACE, PH, 3.6, "glass", { color = steel, guard = PH + 24 })
	K:Rail(TX0 - 2, TERRACE, TX0 - 2, TZ0, PH, 3.6, "glass", { color = steel, guard = PH + 24 })
	K:Rail(TX1, TERRACE, TX1, GZ0, PH, 3.6, "glass", { color = steel, guard = PH + 24 })
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
	-- Its call panel on the lobby's side wall: down to the garage (HousingService's "Garage" prompt).
	local call = R:Box("GarageCall", -13.75, -13.45, PH + 3.6, PH + 6.4, 19.2, 20.8, rgb(176, 178, 184), M.Metal)
	HouseBuilder.SignGui(call, Enum.NormalId.Right, "▼ P1", "GARAGE", theme, P.White, 40)
	local garageCalls = { call }

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

	-- The sky lounge (the glass box off the dining room, through the doorway by the island): the car
	-- lift's steel platform in its hazard-striped square at the front (its control post goes down to
	-- P1), a sofa facing the view, a pool table, two arcade machines on the back wall, strip lights.
	local sky = K:Sub(0, PH, 0, 0)
	local lift = sky:In("Garage")
	lift:Deco("LiftPlate", 3, 15, 0, 0.06, -10.8, 6.8, rgb(150, 152, 158), M.DiamondPlate)
	for _, e in ipairs({ { 2.6, 15.4, -11.6, -11.2 }, { 2.6, 15.4, 7.2, 7.6 }, { 2.6, 3, -11.2, 7.2 }, { 15, 15.4, -11.2, 7.2 } }) do
		lift:Deco("LiftEdge", e[1], e[2], 0.06, 0.1, e[3], e[4], rgb(230, 190, 40), M.SmoothPlastic)
	end
	local post = lift:Box("LiftControl", 16, 17.2, 0, 4, -9.2, -7.8, rgb(60, 62, 68), M.Metal)
	HouseBuilder.SignGui(post, Enum.NormalId.Left, "▼ P1", "CAR LIFT", theme, P.White, 40)
	lift:Neon(16, 17.2, 4, 4.2, -9.2, -7.8, theme)
	table.insert(garageCalls, post)
	local liftSign = lift:Box("LiftSign", 4, 14, 9.6, 12, 7.4, 7.6, P.Dark, M.Metal, DETAIL)
	HouseBuilder.SignGui(liftSign, Enum.NormalId.Front, "CAR LIFT  ▼  P1", "YOUR GARAGE IS DOWNSTAIRS", theme, P.White)
	for _, z in ipairs({ -2.2, 16 }) do
		local strip = lift:Deco("StripLight", 4, 30, CEIL - PH - 1.2, CEIL - PH - 0.9, z - 0.5, z + 0.5, rgb(240, 248, 255), M.Neon)
		K:Light(strip, rgb(235, 242, 255), 30, 0.5)
	end
	I:Rug(24, 0, -4, 0, 12, 8, rgb(70, 66, 84))
	I:Sofa(24, 0, -1.5, 0, 11, rgb(60, 60, 68), { mat = M.Leather, pillows = theme:Lerp(P.White, 0.3), seats = 2 })
	I:Table(24, 0, -6.5, 0, 6, 3, 1.6, P.Dark, M.Marble)
	I:PoolTable(24, 0, 14, 0, theme:Lerp(rgb(30, 70, 60), 0.6))
	I:Arcade(7, 0, 23.4, 0, theme)
	I:Arcade(11.5, 0, 23.4, 0, rgb(255, 62, 165))
	I:Plant(30, 0, 23, rgb(60, 60, 66), { tall = true })
	I:Plant(30, 0, -10, rgb(60, 60, 66), { tall = true })
	sky:Board("LoungeSign", 24, 7.6, TZ1 - 1.2, 12, 3, "SKY LOUNGE", nil, theme, theme) -- (under the strip light's glow)
	G:Box("GarageBack", GX0 + 0.6, GX1 - 0.6, PH, PH + 0.06, TZ1 - 1.6, TZ1 - 1, rgb(100, 100, 100), M.Concrete, DETAIL)

	sky:SaleStand(-6, 0, -7, -24, -3)
	K:Backdrop("city", { level = PH })
	K:Bounds(-56, 56, -36, 40, PH - 8, PH + 40)

	-- P1, the underground garage -------------------------------------------------------------------------
	local U = K:In("Garage"):Sub(0, P1, 0, 0)
	local concrete = rgb(196, 194, 188)
	local floor = rgb(112, 112, 116)
	local paint = wall:Lerp(rgb(96, 96, 108), 0.35) -- the lower walls: the tower's lavender, darker
	local line = rgb(232, 232, 226)
	local yellow = rgb(230, 190, 40)
	-- Shell: floor, ceiling, walls (the front one open where the ramp leaves), the tunnel to the street.
	U:Box("P1Floor", P1X0 - 1, P1X1 + 1, -1, 0, P1Z0 - 1, P1Z1 + 1, floor, M.Concrete)
	U:Box("P1Ceiling", P1X0 - 1, P1X1 + 1, P1H, P1H + 1, P1Z0 - 1, P1Z1 + 1, concrete, M.Concrete)
	U:Box("P1Wall", P1X0 - 1, P1X1 + 1, 0, P1H, P1Z1, P1Z1 + 1, concrete, M.Concrete)
	U:Box("P1Wall", P1X0 - 1, P1X0, 0, P1H, P1Z0, P1Z1, concrete, M.Concrete)
	U:Box("P1Wall", P1X1, P1X1 + 1, 0, P1H, P1Z0, P1Z1, concrete, M.Concrete)
	U:Box("P1Wall", P1X0 - 1, RX0, 0, P1H, P1Z0 - 1, P1Z0, concrete, M.Concrete)
	U:Box("P1Wall", RX1, P1X1 + 1, 0, P1H, P1Z0 - 1, P1Z0, concrete, M.Concrete)
	-- Painted lower walls with a stripe in the home's colour (looks only, just proud of the concrete).
	U:Deco("WallPaint", P1X0, P1X1, 0, 4, P1Z1 - 0.1, P1Z1, paint, M.SmoothPlastic)
	U:Deco("WallPaint", P1X0, P1X0 + 0.1, 0, 4, P1Z0, P1Z1, paint, M.SmoothPlastic)
	U:Deco("WallPaint", P1X1 - 0.1, P1X1, 0, 4, P1Z0, P1Z1, paint, M.SmoothPlastic)
	U:Deco("WallPaint", P1X0, RX0, 0, 4, P1Z0, P1Z0 + 0.1, paint, M.SmoothPlastic)
	U:Deco("WallPaint", RX1, P1X1, 0, 4, P1Z0, P1Z0 + 0.1, paint, M.SmoothPlastic)
	U:Deco("WallStripe", P1X0, P1X1, 4, 4.4, P1Z1 - 0.12, P1Z1, theme, M.SmoothPlastic)
	U:Deco("WallStripe", P1X0, P1X0 + 0.12, 4, 4.4, P1Z0, P1Z1, theme, M.SmoothPlastic)
	U:Deco("WallStripe", P1X1 - 0.12, P1X1, 4, 4.4, P1Z0, P1Z1, theme, M.SmoothPlastic)
	U:Sub(P1X0 + 0.2, 0, 9, -90):Letters(0, 10, 0, 16, 7, "P1", theme)
	U:Sub(P1X1 - 0.2, 0, 9, 90):Letters(0, 10, 0, 16, 7, "P1", theme)

	-- The bays (HousingService parks the owner's cars in this order; "Drive this" sits you in it right
	-- there): seven along the back wall facing the aisle, three at the front, the nearest ones to the
	-- elevator first. Wheel stops at the back of each, columns between them on the aisle's edges.
	for _, x in ipairs({ 0, 14, -14, 28, -28, 42, -42 }) do
		U:Bay(x, 0, 33, 0, { drive = true })
		U:Deco("WheelStop", x - 3.5, x + 3.5, 0, 0.5, 40.4, 41.2, concrete, M.Concrete)
	end
	for _, x in ipairs({ -14, -28, -42 }) do
		U:Bay(x, 0, -11, 180, { drive = true })
		U:Deco("WheelStop", x - 3.5, x + 3.5, 0, 0.5, -19.2, -18.4, concrete, M.Concrete)
	end
	for _, c in ipairs({ { -35, 23.5 }, { -7, 23.5 }, { 21, 23.5 }, { 49, 23.5 }, { -35, -1.5 }, { -21, -1.5 }, { -7, -1.5 } }) do
		U:Box("Column", c[1] - 0.9, c[1] + 0.9, 0, P1H, c[2] - 0.9, c[2] + 0.9, concrete, M.Concrete)
		U:Deco("ColumnBand", c[1] - 1, c[1] + 1, 0, 1.4, c[2] - 1, c[2] + 1, yellow, M.SmoothPlastic)
		U:Deco("ColumnBand", c[1] - 1, c[1] + 1, 1.4, 1.8, c[2] - 1, c[2] + 1, P.Black, M.SmoothPlastic)
	end
	-- The aisle: a dashed centre line, the lane edges, and the ramp lane's lines toward the tunnel.
	for x = -48, 20, 8 do
		U:Deco("LaneDash", x, x + 4, 0.02, 0.05, 10.8, 11.2, line, M.SmoothPlastic)
	end
	U:Deco("LaneEdge", P1X0 + 2, P1X1 - 2, 0.02, 0.05, 23.2, 23.5, yellow, M.SmoothPlastic)
	U:Deco("LaneEdge", P1X0 + 2, RX0 - 1, 0.02, 0.05, -1.5, -1.2, yellow, M.SmoothPlastic)
	U:Deco("LaneEdge", RX0 + 0.5, RX0 + 0.8, 0.02, 0.05, TUNNEL_END, -1.2, yellow, M.SmoothPlastic)
	U:Deco("LaneEdge", RX1 - 0.8, RX1 - 0.5, 0.02, 0.05, TUNNEL_END, -1.2, yellow, M.SmoothPlastic)
	-- Pipes and strip lights under the ceiling (the lights are always on: there's no daylight down here).
	U:Pipe("Sprinkler", true, P1X0, P1X1, P1H - 1.2, 17, 0.5, rgb(170, 44, 40), M.Metal, DETAIL)
	U:Pipe("Duct", true, P1X0, P1X1, P1H - 1.6, 20, 1.4, rgb(150, 152, 156), M.Metal, DETAIL)
	-- (Hung 2 studs down on rods, so they light the ceiling and the columns too, not just the floor.)
	for _, x in ipairs({ -36, 0, 36 }) do
		for _, z in ipairs({ 4, 30 }) do
			local strip = U:Deco("StripLight", x - 12, x + 12, P1H - 2.2, P1H - 1.9, z - 0.4, z + 0.4, rgb(240, 248, 255), M.Neon)
			U:Deco("Hanger", x - 9.1, x - 8.9, P1H - 1.9, P1H, z - 0.1, z + 0.1, P.DarkMetal, M.Metal)
			U:Deco("Hanger", x + 8.9, x + 9.1, P1H - 1.9, P1H, z - 0.1, z + 0.1, P.DarkMetal, M.Metal)
			K:Light(strip, rgb(232, 240, 255), 46, 1.1)
		end
	end

	-- The front: the elevator up to the penthouse and a door out to the street (the lobby), on a paved
	-- walkway behind bollards.
	U:Deco("Walkway", -6, 18, 0.02, 0.06, P1Z0, -12, rgb(150, 150, 154), M.Concrete)
	U:Deco("WalkwayEdge", -6, 18, 0.02, 0.07, -12.4, -12, yellow, M.SmoothPlastic)
	for _, x in ipairs({ -4, 4, 12 }) do
		U:Box("Bollard", x - 0.5, x + 0.5, 0, 3.2, -12.7, -11.7, yellow, M.Metal)
	end
	local liftDoor = U:Box("LiftDoor", 1, 7, 0, 10, P1Z0, P1Z0 + 0.4, rgb(176, 178, 184), M.Metal)
	U:Deco("DoorSplit", 3.95, 4.05, 0, 10, P1Z0 + 0.4, P1Z0 + 0.5, P.DarkMetal, M.Metal)
	U:Deco("LiftFrame", 0.2, 7.8, 0, 10.8, P1Z0, P1Z0 + 0.2, steel, M.Metal)
	local p1Sign = U:Box("FloorSign", 2.6, 5.4, 11.2, 12.4, P1Z0, P1Z0 + 0.2, P.Dark, M.SmoothPlastic, DETAIL)
	HouseBuilder.SignGui(p1Sign, Enum.NormalId.Back, "P1  ▲  PH", nil, theme)
	local streetDoor = U:Box("StreetDoor", 11.5, 16, 0, 8.6, P1Z0, P1Z0 + 0.3, rgb(46, 92, 70), M.Metal)
	U:Deco("DoorBar", 12, 15.5, 3.8, 4.2, P1Z0 + 0.3, P1Z0 + 0.6, steel, M.Metal)
	local streetSign = U:Box("StreetSign", 11.75, 15.75, 9.2, 10.6, P1Z0, P1Z0 + 0.2, rgb(20, 110, 60), M.SmoothPlastic, DETAIL)
	HouseBuilder.SignGui(streetSign, Enum.NormalId.Back, "EXIT · STREET", nil, Color3.new(1, 1, 1))
	local lobbyStrip = U:Deco("StripLight", -2, 16, P1H - 0.4, P1H - 0.1, -20.4, -19.6, rgb(240, 248, 255), M.Neon)
	K:Light(lobbyStrip, rgb(255, 236, 214), 24, 0.7)
	U:GarageSign(0, 11, P1Z1 - 0.3, 0, 18, 4)
	U:ParkStand(4, 0, 4, 4, -20)

	-- The exit: the lane out of the hall's front wall into a tunnel that climbs toward the street, to an
	-- open roll-up door full of daylight (a raised barrier in front of it). Signs point the way.
	U:Box("TunnelFloor", RX0 - 1, RX1 + 1, -1, 0, TUNNEL_END - 1, P1Z0 - 1, floor, M.Concrete)
	U:Box("TunnelWall", RX0 - 1, RX0, 0, TUNNEL_TOP, TUNNEL_END - 1, P1Z0 - 1, concrete, M.Concrete)
	U:Box("TunnelWall", RX1, RX1 + 1, 0, TUNNEL_TOP, TUNNEL_END - 1, P1Z0 - 1, concrete, M.Concrete)
	U:Box("TunnelWall", RX0, RX1, P1H + 1, TUNNEL_TOP, P1Z0 - 1, P1Z0, concrete, M.Concrete)
	U:Box("TunnelRoof", RX0 - 1, RX1 + 1, TUNNEL_TOP, TUNNEL_TOP + 1, TUNNEL_END - 1, P1Z0 - 1, concrete, M.Concrete)
	U:Deco("TunnelPaint", RX0, RX0 + 0.1, 0, 4, TUNNEL_END, P1Z0 - 1, paint, M.SmoothPlastic)
	U:Deco("TunnelPaint", RX1 - 0.1, RX1, 0, 4, TUNNEL_END, P1Z0 - 1, paint, M.SmoothPlastic)
	U:Wedge("Ramp", RX0, RX1, 0, RAMP_UP, RAMP1, RAMP0, floor, M.Concrete, "+Z")
	U:Box("RampTop", RX0, RX1, 0, RAMP_UP, TUNNEL_END, RAMP1, floor, M.Concrete)
	for _, z in ipairs({ -46, -78 }) do
		local strip = U:Deco("StripLight", RX0 + 4, RX1 - 4, TUNNEL_TOP - 2.2, TUNNEL_TOP - 1.9, z - 0.4, z + 0.4, rgb(240, 248, 255), M.Neon)
		U:Deco("Hanger", RX0 + 6.9, RX0 + 7.1, TUNNEL_TOP - 1.9, TUNNEL_TOP, z - 0.1, z + 0.1, P.DarkMetal, M.Metal)
		U:Deco("Hanger", RX1 - 7.1, RX1 - 6.9, TUNNEL_TOP - 1.9, TUNNEL_TOP, z - 0.1, z + 0.1, P.DarkMetal, M.Metal)
		K:Light(strip, rgb(232, 240, 255), 40, 1.1)
	end
	local day = U:Box("Daylight", RX0, RX1, RAMP_UP, TUNNEL_TOP, TUNNEL_END - 0.6, TUNNEL_END, rgb(255, 250, 236), M.Neon)
	K:Light(day, rgb(255, 244, 222), 40, 1.4)
	U:Box("DoorHousing", RX0, RX1, TUNNEL_TOP - 2.4, TUNNEL_TOP, TUNNEL_END, TUNNEL_END + 1.6, P.DarkMetal, M.Metal)
	U:Box("BarrierPost", RX1 - 2.6, RX1 - 1.4, RAMP_UP, RAMP_UP + 3.6, TUNNEL_END + 7.4, TUNNEL_END + 8.6, yellow, M.Metal)
	U:Bar("BarrierArm", RX1 - 2, RAMP_UP + 3.4, TUNNEL_END + 8, RX1 - 7, RAMP_UP + 9.4, TUNNEL_END + 8, 0.5, rgb(220, 50, 50), M.SmoothPlastic)
	-- Signs: over the ramp's mouth (seen from the back row), over the aisle (seen driving toward it), at the
	-- top of the ramp.
	U:Sub((RX0 + RX1) / 2, 0, P1Z0 + 0.2, 180):Board("ExitSign", 0, 14.4, 0, 14, 3, "EXIT  ▲", "TO THE STREET", rgb(110, 242, 160), theme)
	U:Sub(14, 0, 11, 90):Board("ExitSign", 0, 14.4, 0, 12, 3, "◀  EXIT", "TO THE STREET", rgb(110, 242, 160), theme)
	U:Sub((RX0 + RX1) / 2, 0, TUNNEL_END + 1.7, 180):Board("ExitSign", 0, TUNNEL_TOP - 1.2, 0, 14, 1.6, "STREET  ·  SOLANA HEIGHTS", nil, P.White)

	-- What HousingService needs: where you arrive down here and back up top, the daylight that takes a car
	-- up to the street, the elevator and the street door (their prompts), and the call buttons upstairs.
	local exitLo = U:World(RX0 + 1, RAMP_UP, TUNNEL_END + 4).Position
	local exitHi = U:World(RX1 - 1, RAMP_UP + 10, RAMP1 - 4).Position
	K.out.garage = {
		spawn = U:World(4, 3.5, -19) * CFrame.Angles(0, math.pi, 0),
		home = K:World(-10, PH + 3.5, 19.5),
		exit = { cf = CFrame.new((exitLo + exitHi) / 2), size = (exitHi - exitLo):Abs() },
		lift = liftDoor,
		door = streetDoor,
		calls = garageCalls,
		upText = "Penthouse",
	}
end
