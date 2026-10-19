-- HeistFronts (ModuleScript, ServerStorage.Tools.Art.HeistFronts). Studio-only art for the gameplay spots:
-- shops built around each heist RobPoint (Glow Mart, Fuel Stop, Sparkle & Co., Club Nova, Coastal Bank),
-- ATM kiosks, and the service spots (Hideout canopy, Mari's stall, Chop Shop, Spray & Go, Police HQ
-- facade, taxi kiosk). Heist / spawn / activity models are only read, never moved or edited.
--
-- Each heist building is laid out in a local frame: origin = the RobPoint on the ground, front (glass
-- shop front + open doorway, 12+ studs wide) toward the nearest road. The centre line x = 0 is always a
-- clear aisle from the doorway to the spot 6 studs in front of the RobPoint.

local Workspace = game:GetService("Workspace")

local Art = {}

local MAX_LIGHTS = 20
local FLOOR_Y = -0.04 -- centre of 0.2-thick floors/paving: top at 0.06, between the ground (0) and pads (0.12)

local V, CF = Vector3.new, CFrame.new
local UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y (columns, tyres)
local FWD = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z (discs facing the front)
local CYL = Enum.PartType.Cylinder

local DARK = Color3.fromRGB(34, 28, 48)
local GOLD = Color3.fromRGB(232, 190, 90)
local VELVET = Color3.fromRGB(170, 30, 80)
local CASE_GLASS = Color3.fromRGB(210, 235, 255)

local Kit, C, N, P -- ArtKit, its colours, neon colours, named pastels (set in Build)
local GOODS, KIOSK, PAINT
local lightsUsed = 0
local reserved = {} -- footprints of what we build (see the end of Build)
local myFolder -- the folder Build fills

-- Small helpers ------------------------------------------------------------------------------------

local function box(parent, size, cf, color, mat, opts)
	return Kit.Part(parent, size, cf, color, mat, opts)
end

local function deco(parent, size, cf, color, mat, opts)
	opts = opts or {}
	opts.CanCollide = false
	return Kit.Part(parent, size, cf, color, mat, opts)
end

local function glow(parent, size, cf, color)
	return Kit.Neon(parent, size, cf, color)
end

-- Floor / paving slab centred on ground frame cf.
local function slab(parent, w, d, cf, color, mat, name)
	return Kit.Part(parent, V(w, 0.2, d), cf * CF(0, FLOOR_Y, 0), color, mat, { Name = name or "Floor" })
end

-- Vertical cylinder standing on ground frame cf.
local function column(parent, cf, h, dia, color, mat, collide)
	return Kit.Part(parent, V(h, dia, dia), cf * CF(0, h / 2, 0) * UP, color, mat,
		{ Shape = CYL, CanCollide = collide ~= false, Name = "Column" })
end

-- Disc facing the frame's front (axis along local Z), centred at cf.
local function disc(parent, cf, thick, dia, color, mat, collide)
	return Kit.Part(parent, V(thick, dia, dia), cf * FWD, color, mat, { Shape = CYL, CanCollide = collide == true, Name = "Disc" })
end

local function ball(parent, cf, dia, color, mat)
	return Kit.Part(parent, V(dia, dia, dia), cf, color, mat, { Shape = Enum.PartType.Ball, CanCollide = false, Name = "Ball" })
end

local function light(part, color, range, brightness)
	if lightsUsed < MAX_LIGHTS and Kit.Light(part, color, range, brightness) then
		lightsUsed += 1
	end
end

-- True if no other module's (queryable) art is within r of pos. Our own parts don't count.
local function artFree(pos, r)
	local city = Workspace:FindFirstChild("City")
	local art = city and city:FindFirstChild("Art")
	if not art then
		return true
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { art }
	for _, hit in ipairs(Workspace:GetPartBoundsInBox(CF(pos.X, 8, pos.Z), V(r * 2, 16, r * 2), params)) do
		if not (myFolder and hit:IsDescendantOf(myFolder)) then
			return false
		end
	end
	return true
end

-- Layout.IsFree can't see pads (they are CanQuery = false), so every palm spot below is also picked by hand
-- to sit off the pads.
local function palm(parent, Layout, pos, scale)
	if Layout.IsFree(pos, 3) and artFree(pos, 2.5) then
		Kit.Palm(parent, V(pos.X, 0, pos.Z), scale or 1.4)
	end
end

local function reserve(cf, x0, x1, z0, z1)
	table.insert(reserved, { cf, x0, x1, z0, z1 })
end

local function isReserved(pos, r)
	for _, f in ipairs(reserved) do
		local p = f[1]:PointToObjectSpace(V(pos.X, 0, pos.Z))
		if p.X > f[2] - r and p.X < f[3] + r and p.Z > f[4] - r and p.Z < f[5] + r then
			return true
		end
	end
	return false
end

-- Placement ----------------------------------------------------------------------------------------

local function frame(pos, dir)
	local p = V(pos.X, 0, pos.Z)
	return CFrame.lookAt(p, p + dir)
end

local function snap(v)
	if math.abs(v.X) > math.abs(v.Z) then
		return V(math.sign(v.X), 0, 0)
	end
	return V(0, 0, v.Z >= 0 and 1 or -1)
end

-- Nearest road: the axis-snapped direction toward it and the distance from pos to its near edge.
-- `prefer` (a snapped direction) wins ties within 2 studs, so equidistant sites face a chosen street.
local function nearestRoad(Layout, pos, prefer)
	local flat = V(pos.X, 0, pos.Z)
	local best, preferred
	for _, r in ipairs(Layout.Roads) do
		local ab = r.b - r.a
		local t = math.clamp((flat - r.a):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
		local offset = (r.a + ab * t) - flat
		if offset.Magnitude > 1e-3 then
			local c = { dist = offset.Magnitude - r.width / 2, dir = snap(offset) }
			if not best or c.dist < best.dist then
				best = c
			end
			if prefer and c.dir == prefer and (not preferred or c.dist < preferred.dist) then
				preferred = c
			end
		end
	end
	if not best then
		return prefer or V(0, 0, -1), 60
	end
	if preferred and preferred.dist <= best.dist + 2 then
		best = preferred
	end
	return best.dir, math.max(best.dist, 0)
end

-- A heist model's RobPoint (position + part), else its pad, else the planned spot.
local function sitePos(model, fallback)
	local rp = model and model:FindFirstChild("RobPoint", true)
	if rp and rp:IsA("BasePart") then
		return rp.Position, rp
	end
	local pad = model and (model.PrimaryPart or model:FindFirstChild("Pad"))
	return pad and pad.Position or fallback, nil
end

local function padOf(model)
	return model and (model.PrimaryPart or model:FindFirstChild("Pad"))
end

-- Half the RobPoint's depth along the building's front axis (it is world-aligned, 4 x 4 x 3).
local function halfDepth(rp, dir)
	if not rp then
		return 2
	end
	return (math.abs(dir.X) * rp.Size.X + math.abs(dir.Z) * rp.Size.Z) / 2
end

-- Shop kit ------------------------------------------------------------------------------------------

-- Shop shell in RobPoint frame cf. s = { xh (half width), zf (front z < 0), zb (back z), h, door,
-- glassH, color, trim, floor, floorMat, roof, fascia }. Glass storefront + open doorway at the front,
-- roof on, false-front fascia for the sign. Returns the y for a sign centred on the fascia.
local function shell(m, cf, s)
	local w, d, midZ = s.xh * 2, s.zb - s.zf, (s.zf + s.zb) / 2
	local gh = s.glassH or (s.h - 4)
	local fh = s.fascia or 7
	local top = s.h + 1 + fh
	slab(m, w, d, cf * CF(0, 0, midZ), s.floor or C.White, s.floorMat)
	box(m, V(w, s.h, 1), cf * CF(0, s.h / 2, s.zb - 0.5), s.color, nil, { Shadow = true, Name = "Wall" })
	local pane = s.xh - 1 - s.door / 2
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(1, s.h, d), cf * CF(sx * (s.xh - 0.5), s.h / 2, midZ), s.color, nil, { Shadow = true, Name = "Wall" })
		box(m, V(pane, gh, 0.4), cf * CF(sx * (s.door / 2 + pane / 2), gh / 2, s.zf + 0.5), C.Glass, Enum.Material.Glass,
			{ Transparency = 0.45, Reflectance = 0.15, Name = "ShopWindow" })
		glow(m, V(0.6, gh, 0.6), cf * CF(sx * (s.door / 2 + 0.3), gh / 2, s.zf + 0.2), s.trim) -- door jamb
		glow(m, V(0.8, top, 0.8), cf * CF(sx * (s.xh + 0.1), top / 2, s.zf - 0.1), s.trim) -- corner fin
	end
	box(m, V(w, s.h - gh, 1), cf * CF(0, gh + (s.h - gh) / 2, s.zf + 0.5), s.color, nil, { Shadow = true, Name = "Header" })
	glow(m, V(s.door + 1.2, 0.6, 0.6), cf * CF(0, gh + 0.3, s.zf + 0.2), s.trim)
	box(m, V(w + 2, 1, d + 2), cf * CF(0, s.h + 0.5, midZ), s.roof or C.White, nil, { Shadow = true, Name = "Roof" })
	glow(m, V(w + 2.4, 0.5, 0.5), cf * CF(0, s.h + 0.2, s.zf - 1.1), s.trim)
	glow(m, V(w + 2.4, 0.5, 0.5), cf * CF(0, s.h + 0.2, s.zb + 1.1), s.trim)
	if fh > 0 then
		box(m, V(w, fh, 1), cf * CF(0, s.h + 1 + fh / 2, s.zf + 0.5), s.color, nil, { Shadow = true, Name = "Fascia" })
	end
	return s.h + 1 + fh / 2
end

-- Counter either side of the RobPoint, which becomes the till / console in the middle of it.
local function counter(m, cf, reach, color, trim)
	local len = reach - 2.6
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (2.6 + len / 2)
		box(m, V(len, 3.6, 3), cf * CF(x, 1.8, 0), color, nil, { Name = "Counter" })
		glow(m, V(len, 0.35, 0.2), cf * CF(x, 2.8, -1.6), trim)
	end
end

-- Little till screen sitting on the RobPoint.
local function register(m, cf, color)
	glow(m, V(1.8, 1.1, 0.2), cf * CF(0, 4.95, 0.4) * CFrame.Angles(math.rad(-15), 0, 0), color)
end

-- Shelf unit running front-to-back at local x, with two bands of colourful goods.
local function gondola(m, cf, x, z0, z1, goods)
	local len, mid = z1 - z0, (z0 + z1) / 2
	box(m, V(3, 5, len), cf * CF(x, 2.5, mid), C.White, nil, { Name = "Shelf" })
	deco(m, V(3.3, 1.2, len - 0.6), cf * CF(x, 1.4, mid), goods[1], nil, { Name = "Goods" })
	deco(m, V(3.3, 1.2, len - 0.6), cf * CF(x, 3.6, mid), goods[2], nil, { Name = "Goods" })
end

-- Glass-door fridges against a side wall (x = centre of the unit, facing the middle of the shop).
local function fridgeWall(m, cf, x, z0, z1, color)
	local len, mid, inward = z1 - z0, (z0 + z1) / 2, -math.sign(x)
	box(m, V(3, 9, len), cf * CF(x, 4.5, mid), C.White, nil, { Name = "Fridge" })
	for _, y in ipairs({ 3, 6.2 }) do
		glow(m, V(0.2, 0.3, len - 1.2), cf * CF(x + inward * 1.55, y, mid), color)
	end
	deco(m, V(0.3, 7.4, len - 0.8), cf * CF(x + inward * 1.75, 4.6, mid), CASE_GLASS, Enum.Material.Glass,
		{ Transparency = 0.55, Name = "FridgeDoor" })
end

-- Paving from zStart (a building front) out to the road edge: a wide apron, then a narrower drive.
local function apron(m, cf, zStart, roadDist, width, apronLen, driveW, color, mat)
	local zEnd = -(roadDist - 1)
	local total = zStart - zEnd
	if total < 2 then
		return
	end
	local a = math.min(apronLen, total)
	slab(m, width, a, cf * CF(0, 0, zStart - a / 2), color, mat, "Paving")
	local rest = total - a
	if rest > 1 then
		slab(m, driveW, rest, cf * CF(0, 0, zEnd + rest / 2), color, mat, "Drive")
	end
end

-- Two-sided roadside sign on a pole at local (lx, lz); the faces point along the road.
local function pylon(m, Layout, cf, lx, lz, text, color, height, width)
	local base = cf * CF(lx, 0, lz)
	if not (Layout.IsFree(base.Position, 3) and artFree(base.Position, 3)) then
		return
	end
	column(m, base, height, 1.2, C.Steel, Enum.Material.Metal)
	for _, a in ipairs({ 90, -90 }) do
		Kit.Sign(m, base * CF(0, height - 2, 0) * CFrame.Angles(0, math.rad(a), 0) * CF(0, 0, -0.95), text, color, width or 14, 5)
	end
end

-- Glow Mart: convenience store, register (RobPoint) at the back counter, aisles either side ------------

local function buildGlowMart(root, Layout)
	local pos = sitePos(Layout.Heist("GlowMart"), V(-470, 0, -1450))
	local dir, roadDist = nearestRoad(Layout, pos)
	local cf = frame(pos, dir)
	local m = Kit.Model(root, "GlowMart_Building")
	local s = { xh = 28, zf = -30, zb = 24, h = 16, door = 14, color = P.Mint, trim = N.Mint, floor = C.White }
	local signY = shell(m, cf, s)
	Kit.Sign(m, cf * CF(0, signY, s.zf - 0.35), "GLOW MART", N.Pink, 40, 5.5)
	box(m, V(22, 0.6, 5), cf * CF(0, 13.2, s.zf - 2.5), N.Pink, nil, { CanCollide = false, Name = "Awning" })
	glow(m, V(22.4, 0.3, 0.3), cf * CF(0, 12.9, s.zf - 5), N.Yellow)

	counter(m, cf, 13, C.White, N.Mint)
	register(m, cf, N.Cyan)
	for i, x in ipairs({ -17, -9, 9, 17 }) do
		gondola(m, cf, x, -25, -10, GOODS[i])
	end
	fridgeWall(m, cf, -(s.xh - 2.5), -26, 5, N.Cyan)
	fridgeWall(m, cf, s.xh - 2.5, -26, 5, N.Mint)
	-- Behind the counter: snack wall and a slushie machine
	box(m, V(24, 7, 2), cf * CF(0, 3.5, s.zb - 2), C.White, nil, { Name = "BackShelf" })
	for i, y in ipairs({ 2, 4.2, 6.2 }) do
		deco(m, V(23, 1, 0.4), cf * CF(0, y, s.zb - 3.1), GOODS[i][2], nil, { Name = "Goods" })
	end
	box(m, V(5, 3.6, 3), cf * CF(18, 1.8, s.zb - 3), C.Steel, Enum.Material.Metal, { Name = "Slushie" })
	glow(m, V(1.8, 2.6, 1.8), cf * CF(17, 4.9, s.zb - 3), N.Pink)
	glow(m, V(1.8, 2.6, 1.8), cf * CF(19, 4.9, s.zb - 3), N.Cyan)
	for _, x in ipairs({ -8, 8 }) do
		local strip = glow(m, V(1.5, 0.3, 44), cf * CF(x, s.h - 0.2, -4), Color3.fromRGB(235, 255, 245))
		if x < 0 then
			light(strip, Color3.fromRGB(220, 255, 240), 40, 1.2)
		end
	end

	-- Parking lot out to the road, bay lines, roadside pylon, palms
	apron(m, cf, s.zf, roadDist, 2 * s.xh + 8, 50, 18, C.Asphalt, Enum.Material.Asphalt)
	if roadDist - 1 + s.zf > 24 then
		for _, x in ipairs({ -28, -20, -12, 12, 20, 28 }) do
			deco(m, V(0.4, 0.05, 12), cf * CF(x, 0.085, s.zf - 13), C.White, nil, { Name = "BayLine" })
		end
	end
	if roadDist > 60 then
		pylon(m, Layout, cf, 16, -(roadDist - 8), "GLOW MART", N.Pink, 18, 14)
		palm(m, Layout, (cf * CF(-16, 0, -(roadDist - 8))).Position, 1.5)
	end
	for _, sx in ipairs({ -1, 1 }) do
		palm(m, Layout, (cf * CF(sx * (s.xh + 6), 0, s.zf + 4)).Position, 1.4)
	end
	reserve(cf, -s.xh - 1, s.xh + 1, -roadDist, s.zb + 1)
end

-- Fuel Stop: shop with the till at the RobPoint, canopy over two pump islands toward the road --------

local function buildFuelStop(root, Layout)
	local pos = sitePos(Layout.Heist("FuelStop"), V(580, 0, -1150))
	local dir, roadDist = nearestRoad(Layout, pos)
	local cf = frame(pos, dir)
	local m = Kit.Model(root, "FuelStop_Building")
	local s = { xh = 24, zf = -22, zb = 22, h = 16, door = 14, color = P.Peach, trim = N.Orange, floor = C.White }
	local signY = shell(m, cf, s)
	Kit.Sign(m, cf * CF(0, signY, s.zf - 0.35), "FUEL STOP", N.Yellow, 34, 5.5)

	counter(m, cf, 12, C.White, N.Orange)
	register(m, cf, N.Yellow)
	for i, x in ipairs({ -9, 9 }) do
		gondola(m, cf, x, -18, -8, GOODS[i + 1])
	end
	fridgeWall(m, cf, -(s.xh - 2.5), -19, 4, N.Cyan)
	-- Slushie bar on the other wall, snack wall behind the till
	box(m, V(3, 3.6, 12), cf * CF(s.xh - 2.5, 1.8, -10), C.White, nil, { Name = "SlushieBar" })
	for i, z in ipairs({ -13, -10, -7 }) do
		glow(m, V(1.6, 2.4, 1.6), cf * CF(s.xh - 2.5, 4.8, z), PAINT[i])
	end
	box(m, V(22, 7, 2), cf * CF(0, 3.5, s.zb - 2), C.White, nil, { Name = "BackShelf" })
	deco(m, V(21, 1, 0.4), cf * CF(0, 2.5, s.zb - 3.1), GOODS[1][1], nil, { Name = "Goods" })
	deco(m, V(21, 1, 0.4), cf * CF(0, 5, s.zb - 3.1), GOODS[3][2], nil, { Name = "Goods" })
	local strip = glow(m, V(1.5, 0.3, 36), cf * CF(0, s.h - 0.2, -2), Color3.fromRGB(255, 245, 230))
	light(strip, Color3.fromRGB(255, 235, 210), 36, 1.2)
	box(m, V(4, 3, 2.5), cf * CF(16, 1.5, s.zf - 2), C.White, nil, { Name = "IceChest" })
	glow(m, V(4.1, 0.4, 2.6), cf * CF(16, 2.4, s.zf - 2), N.Cyan)

	-- Forecourt: concrete to the road, canopy (16 studs clear) over two pump islands
	apron(m, cf, s.zf, roadDist, 64, 1000, 64, C.Concrete, Enum.Material.Concrete)
	local cz = s.zf - 26
	if cz - 14 < -(roadDist - 8) then
		cz = -(roadDist - 22)
	end
	box(m, V(56, 2.4, 28), cf * CF(0, 17.2, cz), C.White, nil, { Shadow = true, Name = "Canopy" })
	for _, z in ipairs({ -14.1, 14.1 }) do
		glow(m, V(56.6, 0.5, 0.5), cf * CF(0, 16.2, cz + z), N.Orange)
	end
	local panel = glow(m, V(44, 0.2, 18), cf * CF(0, 15.9, cz), Color3.fromRGB(255, 250, 235))
	light(panel, Color3.fromRGB(255, 240, 220), 40, 1.3)
	Kit.Sign(m, cf * CF(0, 17.2, cz - 14.45), "FUEL STOP", N.Orange, 26, 2)
	for _, x in ipairs({ -12, 12 }) do
		box(m, V(3, 0.5, 16), cf * CF(x, 0.25, cz), C.Concrete, Enum.Material.Concrete, { Name = "Island" })
		column(m, cf * CF(x, 0.5, cz), 15.5, 1.6, C.White, nil)
		for _, z in ipairs({ -5, 5 }) do
			box(m, V(2, 5, 1.6), cf * CF(x, 3, cz + z), P.Butter, nil, { Name = "Pump" })
			glow(m, V(2.2, 0.4, 1.8), cf * CF(x, 5.7, cz + z), N.Orange)
		end
	end
	if roadDist > 30 then
		pylon(m, Layout, cf, 38, -(roadDist - 7), "FUEL STOP", N.Yellow, 20, 14)
		palm(m, Layout, (cf * CF(-38, 0, -(roadDist - 8))).Position, 1.5)
	end
	for _, sx in ipairs({ -1, 1 }) do
		palm(m, Layout, (cf * CF(sx * (s.xh + 6), 0, s.zb - 4)).Position, 1.4)
	end
	reserve(cf, -33, 33, -roadDist, s.zb + 1)
end

-- ATM kiosks: freestanding open-front booth around each RobPoint, small plaza + path to the road -------

local ATMS = {
	{ V(-480, 0, 300), V(0, 0, -1) }, -- equidistant from two streets: face north
	{ V(1060, 0, -700) },
	{ V(200, 0, 1480) },
	{ V(-1280, 0, -500) },
	{ V(600, 0, -1450) },
}

local function buildATM(root, Layout, i)
	local pos, rp = sitePos(Layout.Heist("ATM" .. i), ATMS[i][1])
	local dir, roadDist = nearestRoad(Layout, pos, ATMS[i][2])
	local cf = frame(pos, dir)
	local hd = halfDepth(rp, dir)
	local m = Kit.Model(root, "ATM" .. i .. "_Kiosk")
	local body, trim = KIOSK[i][1], KIOSK[i][2]
	local back = hd + 0.8 -- back wall sits just behind the machine; the front (z = -4.5) is open
	local depth = back + 4.5
	local zc = back - depth / 2

	slab(m, 18, 18, cf, P.Paver, Enum.Material.Concrete, "Plaza")
	if roadDist > 10 then
		local len = roadDist - 10
		slab(m, 6, len, cf * CF(0, 0, -9 - len / 2), P.Paver, Enum.Material.Concrete, "Path")
	end
	box(m, V(12, 9, 0.8), cf * CF(0, 4.5, back + 0.4), body, nil, { Shadow = true, Name = "Wall" })
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(0.8, 9, depth + 0.8), cf * CF(sx * 5.6, 4.5, zc + 0.4), body, nil, { Shadow = true, Name = "Wall" })
		glow(m, V(0.4, 9, 0.4), cf * CF(sx * 5.6, 4.5, -4.6), trim)
	end
	box(m, V(12.8, 0.8, depth + 2.3), cf * CF(0, 9.4, zc - 0.35), C.White, nil, { Shadow = true, Name = "Roof" })
	Kit.Sign(m, cf * CF(0, 11.3, -5.2), "ATM", trim, 8, 3)
	-- Screen and keypad on the machine's face
	glow(m, V(2.4, 1.4, 0.15), cf * CF(0, 3.1, -hd - 0.08), N.Cyan)
	deco(m, V(1.8, 0.2, 0.8), cf * CF(0, 2, -hd - 0.4), DARK, nil, { Name = "Keypad" })
	for _, sx in ipairs({ -1, 1 }) do
		palm(m, Layout, (cf * CF(sx * 12, 0, 2)).Position, 1.3)
	end
	reserve(cf, -7, 7, -6, back + 1.5)
end

-- Sparkle & Co.: jewelry store, RobPoint = the main case in the middle -------------------------------

local function buildSparkleCo(root, Layout)
	local pos = sitePos(Layout.Heist("SparkleCo"), V(-120, 0, -380))
	local dir, roadDist = nearestRoad(Layout, pos)
	local cf = frame(pos, dir)
	local m = Kit.Model(root, "SparkleCo_Building")
	local s = { xh = 30, zf = -34, zb = 28, h = 20, door = 14, color = P.Lavender, trim = N.Pink,
		floor = Color3.fromRGB(250, 238, 246), floorMat = Enum.Material.Marble, fascia = 9 }
	local signY = shell(m, cf, s)
	Kit.Sign(m, cf * CF(0, signY, s.zf - 0.35), "SPARKLE & CO.", N.Cyan, 46, 6)
	box(m, V(20, 0.6, 5), cf * CF(0, 16.6, s.zf - 2.5), N.Pink, nil, { CanCollide = false, Name = "Awning" })
	glow(m, V(20.4, 0.3, 0.3), cf * CF(0, 16.3, s.zf - 5), N.Cyan)

	-- The main case: the RobPoint is its plinth, with a glass hood and a giant gem on top
	deco(m, V(2.8, 2.6, 2.8), cf * CF(0, 5.7, 0), CASE_GLASS, Enum.Material.Glass, { Transparency = 0.6, Name = "CaseGlass" })
	local gem = ball(m, cf * CF(0, 5.4, 0), 1.5, N.Cyan, Enum.Material.Neon)
	light(gem, N.Cyan, 24, 1.2)
	-- Velvet ropes either side of it (the approach from the door stays open)
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -4, 3 }) do
			column(m, cf * CF(sx * 5.5, 0, z), 3.2, 0.5, GOLD, Enum.Material.Metal, false)
			ball(m, cf * CF(sx * 5.5, 3.4, z), 0.9, GOLD, Enum.Material.Metal)
		end
		deco(m, V(0.3, 0.3, 7), cf * CF(sx * 5.5, 2.7, -0.5), VELVET, Enum.Material.Fabric, { Name = "Rope" })
	end

	-- Display cases along both side walls, each glowing a different gem colour
	local gems = { N.Pink, N.Cyan, N.Mint, N.Purple, N.Yellow, N.Orange, N.Cyan, N.Pink }
	local k = 0
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -24, -13, -2, 9 }) do
			k += 1
			local c = cf * CF(sx * 21, 0, z)
			box(m, V(3, 3, 7), c * CF(0, 1.5, 0), C.White, Enum.Material.Marble, { Name = "Case" })
			glow(m, V(1.2, 0.5, 5.6), c * CF(0, 3.25, 0), gems[k])
			deco(m, V(3, 1.8, 7), c * CF(0, 3.9, 0), CASE_GLASS, Enum.Material.Glass, { Transparency = 0.55, Name = "CaseGlass" })
		end
	end

	-- Neon chandelier over the entrance hall
	local top = cf * CF(0, s.h, -14)
	deco(m, V(0.3, 3, 0.3), top * CF(0, -1.5, 0), GOLD, Enum.Material.Metal, { Name = "Chain" })
	local hub = ball(m, top * CF(0, -4, 0), 2, Color3.fromRGB(255, 245, 250), Enum.Material.Neon)
	light(hub, Color3.fromRGB(255, 220, 240), 45, 1.4)
	for i = 1, 8 do
		local a = math.rad(i * 45)
		glow(m, V(0.5, 2.6, 0.5), top * CF(math.cos(a) * 4.5, -5.4, math.sin(a) * 4.5), i % 2 == 0 and N.Pink or C.White)
	end
	for i = 1, 6 do
		local a = math.rad(i * 60 + 30)
		glow(m, V(0.5, 2, 0.5), top * CF(math.cos(a) * 2.4, -6.6, math.sin(a) * 2.4), N.Cyan)
	end
	ball(m, top * CF(0, -7.8, 0), 1, N.Pink, Enum.Material.Neon)

	-- Neon diamond logo on the back wall
	local logo = cf * CF(0, 12, s.zb - 1.2)
	for _, e in ipairs({ { 2.5, 2.5, 45 }, { -2.5, 2.5, -45 }, { 2.5, -2.5, -45 }, { -2.5, -2.5, 45 } }) do
		glow(m, V(0.5, 7.1, 0.4), logo * CF(e[1], e[2], 0) * CFrame.Angles(0, 0, math.rad(e[3])), N.Cyan)
	end

	apron(m, cf, s.zf, roadDist, 2 * s.xh + 8, 16, 16, P.Paver, Enum.Material.Concrete)
	for _, sx in ipairs({ -1, 1 }) do
		palm(m, Layout, (cf * CF(sx * 13, 0, s.zf - 6)).Position, 1.4)
		if roadDist > 50 then
			palm(m, Layout, (cf * CF(sx * 12, 0, -(roadDist - 6))).Position, 1.6)
		end
	end
	reserve(cf, -s.xh - 1, s.xh + 1, -roadDist, s.zb + 1)
end

-- Club Nova: nightclub (no bar), dance floor + DJ, RobPoint = the office safe at the back ---------------

local function buildClubNova(root, Layout)
	local pos, rp = sitePos(Layout.Heist("ClubNova"), V(1120, 0, -150))
	local dir, roadDist = nearestRoad(Layout, pos)
	local cf = frame(pos, dir)
	local hd = halfDepth(rp, dir)
	local m = Kit.Model(root, "ClubNova_Building")
	local s = { xh = 30, zf = -58, zb = 26, h = 24, door = 14, glassH = 12, color = P.Lavender, trim = N.Purple,
		floor = Color3.fromRGB(46, 38, 62), fascia = 10, roof = Color3.fromRGB(70, 56, 96) }
	local signY = shell(m, cf, s)
	Kit.Sign(m, cf * CF(0, signY, s.zf - 0.35), "CLUB NOVA", N.Pink, 40, 7)
	for _, sx in ipairs({ -1, 1 }) do -- neon stars either side of the sign
		for _, a in ipairs({ 0, 60, 120 }) do
			glow(m, V(0.6, 5, 0.3), cf * CF(sx * (s.xh - 4.5), signY, s.zf - 0.2) * CFrame.Angles(0, 0, math.rad(a)), N.Yellow)
		end
	end
	-- Marquee over the doors, velvet queue rope beside them
	box(m, V(22, 1.2, 6), cf * CF(0, 12.8, s.zf - 3), DARK, nil, { CanCollide = false, Name = "Marquee" })
	glow(m, V(22.4, 0.4, 0.4), cf * CF(0, 12.8, s.zf - 6.1), N.Pink)
	glow(m, V(20, 0.2, 5), cf * CF(0, 12.1, s.zf - 3), N.Yellow)
	for _, x in ipairs({ 10, 18 }) do
		column(m, cf * CF(x, 0, s.zf - 5), 3.2, 0.5, GOLD, Enum.Material.Metal, false)
	end
	deco(m, V(8, 0.3, 0.3), cf * CF(14, 2.7, s.zf - 5), VELVET, Enum.Material.Fabric, { Name = "Rope" })

	-- Office at the back: partition with a 12-stud doorway, safe (RobPoint) against the office back wall
	local oz = -14
	local side = s.xh - 1 - 6
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(side, s.h, 1), cf * CF(sx * (6 + side / 2), s.h / 2, oz), s.color, nil, { Name = "OfficeWall" })
	end
	box(m, V(12, s.h - 12, 1), cf * CF(0, 12 + (s.h - 12) / 2, oz), s.color, nil, { Name = "OfficeWall" })
	box(m, V(2 * s.xh - 2, s.h, 1), cf * CF(0, s.h / 2, hd + 1), s.color, nil, { Name = "OfficeBack" })
	Kit.Sign(m, cf * CF(0, 14.5, oz - 0.85), "STAFF ONLY", N.Cyan, 12, 2.5)
	deco(m, V(2.6, 3.2, 0.2), cf * CF(0, 2.1, -hd - 0.1), C.Steel, Enum.Material.Metal, { Name = "SafeDoor" })
	disc(m, cf * CF(0.5, 2.5, -hd - 0.35), 0.3, 1.2, N.Yellow, Enum.Material.Neon)
	deco(m, V(0.3, 1.4, 0.3), cf * CF(-0.7, 2.1, -hd - 0.35), GOLD, Enum.Material.Metal, { Name = "Handle" })
	box(m, V(7, 3, 3), cf * CF(14, 1.5, -6), C.DarkWood, Enum.Material.Wood, { Name = "Desk" })
	box(m, V(8, 1.8, 3), cf * CF(-15, 0.9, -1), N.Purple, Enum.Material.Fabric, { Name = "Couch" })
	box(m, V(8, 2, 0.8), cf * CF(-15, 2.4, 0.2), N.Purple, Enum.Material.Fabric, { Name = "Couch" })
	local lamp = glow(m, V(8, 0.3, 1), cf * CF(0, s.h - 0.2, -6), N.Purple)
	light(lamp, N.Purple, 24, 1)

	-- Dance floor: 5 x 4 neon tiles, alternating colours
	local tiles = { N.Pink, N.Cyan, N.Purple, N.Yellow }
	for r = 0, 3 do
		for c = -2, 2 do
			glow(m, V(5.8, 0.3, 5.8), cf * CF(c * 6, 0.15, -47 + r * 6), tiles[(r + c + 4) % 4 + 1])
		end
	end
	-- DJ booth against the left wall with a NOVA sign behind it
	local dj = cf * CF(-22, 0, -38)
	box(m, V(4, 4, 10), dj * CF(0, 2, 0), DARK, nil, { Name = "DJBooth" })
	glow(m, V(0.2, 0.6, 10), dj * CF(2.1, 3, 0), N.Cyan)
	for _, z in ipairs({ -2.5, 2.5 }) do
		Kit.Part(m, V(0.3, 2.4, 2.4), dj * CF(0, 4.15, z) * UP, C.Steel, Enum.Material.Metal, { Shape = CYL, CanCollide = false, Name = "Turntable" })
	end
	Kit.Sign(m, cf * CF(-(s.xh - 1.4), 13, -38) * CFrame.Angles(0, math.rad(-90), 0), "NOVA", N.Cyan, 16, 6)
	-- Speaker stacks at the corners of the dance floor
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -52, -24 }) do
			box(m, V(4, 9, 4), cf * CF(sx * 25, 4.5, z), DARK, nil, { Name = "Speaker" })
			Kit.Part(m, V(0.3, 3, 3), cf * CF(sx * 22.85, 5.5, z), N.Purple, Enum.Material.Neon, { Shape = CYL, CanCollide = false, Name = "Cone" })
		end
	end
	-- Disco ball and ceiling light strips
	deco(m, V(0.2, 3, 0.2), cf * CF(0, s.h - 1.5, -38), C.Steel, Enum.Material.Metal, { Name = "Chain" })
	Kit.Part(m, V(3.2, 3.2, 3.2), cf * CF(0, s.h - 4.5, -38), C.White, Enum.Material.Foil,
		{ Shape = Enum.PartType.Ball, CanCollide = false, Reflectance = 0.5, Name = "DiscoBall" })
	for i, x in ipairs({ -12, 0, 12 }) do
		local strip = glow(m, V(0.5, 0.4, 40), cf * CF(x, s.h - 0.3, -36), tiles[i])
		if x ~= 0 then
			light(strip, tiles[i], 45, 1.3)
		end
	end

	apron(m, cf, s.zf, roadDist, 2 * s.xh + 8, 14, 18, P.Paver, Enum.Material.Concrete)
	for _, sx in ipairs({ -1, 1 }) do
		palm(m, Layout, (cf * CF(sx * (s.xh + 6), 0, s.zf + 6)).Position, 1.6)
	end
	reserve(cf, -s.xh - 1, s.xh + 1, -roadDist, s.zb + 1)
end

-- Coastal Bank: grand deco bank, RobPoint = vault console, round vault door behind it -------------------

local function buildCoastalBank(root, Layout)
	local pos, rp = sitePos(Layout.Heist("CoastalBank"), V(230, 0, 300))
	local dir, roadDist = nearestRoad(Layout, pos, V(0, 0, -1)) -- equidistant streets: face downtown (north)
	local cf = frame(pos, dir)
	local hd = halfDepth(rp, dir)
	local m = Kit.Model(root, "CoastalBank_Building")
	local MARBLE = Color3.fromRGB(238, 234, 228)
	local s = { xh = 40, zf = -48, zb = 34, h = 30, door = 16, glassH = 22, color = P.Deco, trim = N.Cyan,
		floor = MARBLE, floorMat = Enum.Material.Marble, fascia = 0, roof = P.Butter }
	shell(m, cf, s)
	local midZ = (s.zf + s.zb) / 2

	-- Portico: six columns (clear of the doorway), entablature with the name, marble porch
	local pz = s.zf - 6
	slab(m, 84, 12, cf * CF(0, 0, pz), MARBLE, Enum.Material.Marble, "Porch")
	for _, x in ipairs({ -36, -24, -12, 12, 24, 36 }) do
		column(m, cf * CF(x, 0, pz), 28, 3.2, C.White, Enum.Material.Marble)
	end
	box(m, V(84, 5, 10), cf * CF(0, 30.5, s.zf - 5), C.White, Enum.Material.Marble, { Shadow = true, Name = "Entablature" })
	glow(m, V(84.4, 0.5, 0.5), cf * CF(0, 28.2, s.zf - 10.1), N.Cyan)
	Kit.Sign(m, cf * CF(0, 30.8, s.zf - 10.35), "COASTAL BANK", N.Yellow, 56, 4)
	-- Stepped deco crown with a sunburst crest
	box(m, V(60, 10, 46), cf * CF(0, 36, midZ), P.Butter, nil, { Shadow = true, Name = "Tier" })
	glow(m, V(60.8, 0.6, 46.8), cf * CF(0, 40.5, midZ), N.Cyan)
	box(m, V(34, 8, 26), cf * CF(0, 45, midZ), P.Deco, nil, { Shadow = true, Name = "Tier" })
	glow(m, V(34.8, 0.6, 26.8), cf * CF(0, 48.6, midZ), N.Pink)
	local sun = cf * CF(0, 34, midZ - 23.3)
	disc(m, sun, 0.4, 6, N.Yellow, Enum.Material.Neon)
	for _, a in ipairs({ -60, -30, 0, 30, 60 }) do
		glow(m, V(0.8, 6, 0.4), sun * CFrame.Angles(0, 0, math.rad(a)) * CF(0, 6.5, 0), N.Orange)
	end

	-- Vault wall and the big round vault door behind the console
	local vz = 8
	box(m, V(2 * s.xh - 2, s.h, 1), cf * CF(0, s.h / 2, vz), P.Butter, nil, { Name = "VaultWall" })
	local door = cf * CF(0, 10.5, vz - 0.5)
	local rim = disc(m, door * CF(0, 0, 0.1), 0.4, 19, N.Cyan, Enum.Material.Neon)
	disc(m, door * CF(0, 0, -0.6), 1.2, 17.5, C.Steel, Enum.Material.Metal, true)
	disc(m, door * CF(0, 0, -1.4), 0.6, 12, Color3.fromRGB(150, 158, 170), Enum.Material.Metal)
	disc(m, door * CF(0, 0, -1.9), 0.8, 3.4, GOLD, Enum.Material.Metal)
	for _, a in ipairs({ 0, 60, 120 }) do
		deco(m, V(0.6, 11, 0.5), door * CF(0, 0, -2.1) * CFrame.Angles(0, 0, math.rad(a)), GOLD, Enum.Material.Metal, { Name = "Spoke" })
	end
	light(rim, N.Cyan, 30, 1.2)
	-- Console dressing on the RobPoint
	glow(m, V(2.8, 1.6, 0.2), cf * CF(0, 5.3, math.min(0.4, hd - 0.2)) * CFrame.Angles(math.rad(-20), 0, 0), N.Cyan)
	deco(m, V(2.4, 0.2, 1), cf * CF(0, 4.5, -0.9), DARK, nil, { Name = "Keypad" })

	-- Teller counters along the sides, marble columns flanking the vault, ceiling light strips
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(4, 4, 24), cf * CF(sx * 31, 2, -20), P.Deco, Enum.Material.Marble, { Name = "TellerCounter" })
		glow(m, V(0.2, 0.5, 24), cf * CF(sx * 28.9, 3, -20), N.Cyan)
		deco(m, V(0.3, 5, 24), cf * CF(sx * 29.4, 6.5, -20), CASE_GLASS, Enum.Material.Glass, { Transparency = 0.55, Name = "TellerGlass" })
		column(m, cf * CF(sx * 16, 0, 3), s.h, 3, C.White, Enum.Material.Marble)
		local strip = glow(m, V(1, 0.4, 50), cf * CF(sx * 10, s.h - 0.3, -20), Color3.fromRGB(255, 244, 220))
		if sx < 0 then
			light(strip, Color3.fromRGB(255, 236, 200), 55, 1.3)
		end
	end

	-- Plaza out to the road, a Gus sign and palms
	apron(m, cf, pz - 6, roadDist, 60, 20, 24, P.Paver, Enum.Material.Concrete)
	local g = cf * CF(-22, 0, pz - 14)
	for _, sx in ipairs({ -1, 1 }) do
		deco(m, V(0.5, 3, 0.5), g * CF(sx * 6, 1.5, 0), C.White, nil, { Name = "SignLeg" })
	end
	Kit.Sign(m, g * CF(0, 5, 0), "GUS SAYS: SAVE YOUR SHELLS!", N.Mint, 16, 4)
	for _, sx in ipairs({ -1, 1 }) do
		palm(m, Layout, (cf * CF(sx * 46, 0, s.zf + 4)).Position, 1.8)
		if roadDist > 70 then
			palm(m, Layout, (cf * CF(sx * 34, 0, -(roadDist - 6))).Position, 1.6)
		end
	end
	reserve(cf, -44, 44, -roadDist, s.zb + 1)
end

-- Hideout: open-sided garage canopy over the back half of the pad, mural wall, wardrobe rack -------------

local function buildHideout(root, Layout)
	local pad = padOf(Layout.Spawn("Hideout"))
	local c = pad and V(pad.Position.X, 0, pad.Position.Z) or V(-475, 0, 1100)
	local hs = pad and pad.Size.X / 2 or 45
	-- Its car pads face north (-Z), so the "back half" is the south half. Local axes = world axes.
	local cf = CF(c)
	local m = Kit.Model(root, "Hideout_Canopy")
	local roofCol = Color3.fromRGB(90, 70, 130)
	local face = hs + 6.75 -- north face of the mural wall, just behind the pad
	-- Posts stand outside the pad so it stays fully drivable; 18+ studs clear under the beams
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ 1, hs + 5 }) do
			box(m, V(2, 20, 2), cf * CF(sx * (hs + 4), 10, z), C.White, nil, { Shadow = true, Name = "Post" })
		end
	end
	for _, z in ipairs({ 1, hs + 5 }) do
		box(m, V(2 * hs + 10, 2, 1.6), cf * CF(0, 19, z), C.White, nil, { Name = "Beam" })
	end
	box(m, V(2 * hs + 12, 1.5, hs + 9.75), cf * CF(0, 20.75, (hs + 6.75) / 2), roofCol, nil, { Shadow = true, Name = "Roof" })
	glow(m, V(2 * hs + 12.4, 0.6, 0.6), cf * CF(0, 20, -1.8), N.Pink)
	for _, sx in ipairs({ -1, 1 }) do
		glow(m, V(0.6, 0.6, hs + 10), cf * CF(sx * (hs + 6.2), 20, (hs + 6.75) / 2), N.Cyan)
		local panel = glow(m, V(30, 0.2, 4), cf * CF(sx * 22, 19.85, hs / 2 + 3), sx < 0 and N.Pink or N.Cyan)
		light(panel, sx < 0 and N.Pink or N.Cyan, 40, 1.2)
	end
	Kit.Sign(m, cf * CF(0, 24.5, -1.2), "HIDEOUT", N.Pink, 36, 6)

	-- Mural wall: sunset over the sea with palm silhouettes, and Gus the Gator in shades
	box(m, V(2 * hs + 12, 20, 1.5), cf * CF(0, 10, face + 0.75), P.Deco, nil, { Shadow = true, Name = "MuralWall" })
	local mx, mw = -20, 52
	for i, col in ipairs({ N.Purple, N.Pink, N.Orange, N.Yellow }) do
		deco(m, V(mw, 3.2, 0.2), cf * CF(mx, 16.4 - (i - 1) * 3.2, face - 0.1), col, nil, { Name = "Mural" })
	end
	disc(m, cf * CF(mx, 7, face - 0.2), 0.2, 10, N.Yellow, Enum.Material.Neon)
	deco(m, V(mw, 3.2, 0.2), cf * CF(mx, 3.6, face - 0.35), N.Cyan, nil, { Name = "Mural" })
	local shade = Color3.fromRGB(70, 34, 100)
	for _, px in ipairs({ mx - 17, mx + 16 }) do
		deco(m, V(1.2, 12, 0.2), cf * CF(px, 8, face - 0.45) * CFrame.Angles(0, 0, math.rad(-6)), shade, nil, { Name = "Mural" })
		deco(m, V(7, 0.7, 0.2), cf * CF(px - 2.4, 13.6, face - 0.45) * CFrame.Angles(0, 0, math.rad(20)), shade, nil, { Name = "Mural" })
		deco(m, V(7, 0.7, 0.2), cf * CF(px + 4, 13.6, face - 0.45) * CFrame.Angles(0, 0, math.rad(-20)), shade, nil, { Name = "Mural" })
		deco(m, V(0.7, 4.5, 0.2), cf * CF(px + 1.2, 15.6, face - 0.45) * CFrame.Angles(0, 0, math.rad(-10)), shade, nil, { Name = "Mural" })
	end
	local gus, gz = Color3.fromRGB(90, 190, 110), face - 0.3
	deco(m, V(26, 12, 0.2), cf * CF(20, 8, face - 0.1), P.Butter, nil, { Name = "Mural" })
	deco(m, V(13, 3, 0.2), cf * CF(19, 6, gz), gus, nil, { Name = "Gus" })
	deco(m, V(6, 1.8, 0.2), cf * CF(27.5, 5.6, gz), gus, nil, { Name = "Gus" })
	deco(m, V(6, 1.4, 0.2), cf * CF(10.5, 5.2, gz) * CFrame.Angles(0, 0, math.rad(12)), gus, nil, { Name = "Gus" })
	for _, x in ipairs({ 15, 22 }) do
		deco(m, V(1.2, 2, 0.2), cf * CF(x, 4, gz), gus, nil, { Name = "Gus" })
	end
	deco(m, V(1.8, 1.8, 0.2), cf * CF(24, 8.2, gz), C.White, nil, { Name = "Gus" })
	deco(m, V(4.4, 1, 0.2), cf * CF(24.5, 8.2, face - 0.45), DARK, nil, { Name = "Shades" })
	Kit.Sign(m, cf * CF(20, 12.2, face - 0.4), "GUS SAYS: STAY COOL", N.Mint, 22, 3)

	-- Wardrobe rack between the pad's back edge and the wall
	local w = cf * CF(40, 0, hs + 3.2)
	for _, sx in ipairs({ -1, 1 }) do
		deco(m, V(0.3, 7, 0.3), w * CF(sx * 4, 3.5, 0), C.Steel, Enum.Material.Metal, { Name = "Rack" })
	end
	deco(m, V(8.4, 0.3, 0.3), w * CF(0, 7, 0), C.Steel, Enum.Material.Metal, { Name = "Rack" })
	for i, col in ipairs({ N.Pink, N.Cyan, N.Yellow, N.Mint, N.Purple }) do
		deco(m, V(0.4, 3.2, 1.8), w * CF(-3.2 + (i - 1) * 1.6, 5.2, 0), col, Enum.Material.Fabric, { Name = "Outfit" })
	end
	Kit.Sign(m, cf * CF(40, 11, face - 0.4), "WARDROBE", N.Mint, 12, 2.6)
	reserve(cf, -hs - 7, hs + 7, -2, hs + 9)
end

-- Mari's market stall: on the west side of the Fence pad, counter facing the pad ------------------------

local function buildMarisStall(root, Layout)
	local pad = padOf(Layout.Spawn("Fence"))
	local c = pad and V(pad.Position.X, 0, pad.Position.Z) or V(-560, 0, 1020)
	local hs = pad and pad.Size.X / 2 or 12
	local cf = frame(c - V(hs + 5, 0, 0), V(1, 0, 0))
	local m = Kit.Model(root, "MarisStall")
	box(m, V(13, 3.5, 3), cf * CF(0, 1.75, -1.5), C.Wood, Enum.Material.WoodPlanks, { Name = "Counter" })
	box(m, V(13, 12, 0.6), cf * CF(0, 6, 4), P.Seafoam, nil, { Shadow = true, Name = "Back" })
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(0.5, 9, 0.5), cf * CF(sx * 6.4, 4.5, -2.8), C.White, nil, { Name = "Post" })
	end
	for i, x in ipairs({ -4.875, -1.625, 1.625, 4.875 }) do
		deco(m, V(3.25, 0.3, 8), cf * CF(x, 9.6, 0.2) * CFrame.Angles(math.rad(-12), 0, 0), i % 2 == 1 and N.Pink or C.White, nil, { Name = "Awning" })
	end
	for i, x in ipairs({ -4, 0, 4 }) do
		deco(m, V(2.4, 1.6, 2), cf * CF(x, 4.3, -1.5), ({ P.Mint, P.Peach, P.Pink })[i], Enum.Material.WoodPlanks, { Name = "Crate" })
	end
	local bulbs = glow(m, V(13, 0.25, 0.25), cf * CF(0, 8.5, -3.9), N.Yellow)
	light(bulbs, Color3.fromRGB(255, 220, 160), 20, 1)
	Kit.Sign(m, cf * CF(0, 13.2, 3.4), "MARI'S", N.Pink, 12, 3)
	reserve(cf, -7, 7, -4, 5)
end

-- Chop Shop: garage behind the pad, roller door rolled up, tools and tyres ---------------------------------

local function buildChopShop(root, Layout)
	local pad = padOf(Layout.Spawn("ChopShop"))
	local c = pad and V(pad.Position.X, 0, pad.Position.Z) or V(-780, 0, 1580)
	local hs = pad and pad.Size.X / 2 or 25
	local dir = nearestRoad(Layout, c)
	local W, D, H, DOOR = 56, 40, 22, 26
	local cf = frame(c - dir * (hs + 5 + D / 2), dir) -- garage behind the pad, door facing it and the road
	local m = Kit.Model(root, "ChopShop_Garage")
	local wall = Color3.fromRGB(128, 146, 168)
	slab(m, W, D, cf, C.Concrete, Enum.Material.Concrete)
	slab(m, DOOR + 4, 5, cf * CF(0, 0, -D / 2 - 2.5), C.Concrete, Enum.Material.Concrete, "Apron")
	box(m, V(W, H, 1), cf * CF(0, H / 2, D / 2 - 0.5), wall, nil, { Shadow = true, Name = "Wall" })
	local side = (W - DOOR) / 2
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(1, H, D), cf * CF(sx * (W / 2 - 0.5), H / 2, 0), wall, nil, { Shadow = true, Name = "Wall" })
		box(m, V(side, H, 1), cf * CF(sx * (DOOR / 2 + side / 2), H / 2, -D / 2 + 0.5), wall, nil, { Shadow = true, Name = "Wall" })
		glow(m, V(0.5, 16, 0.5), cf * CF(sx * (DOOR / 2 + 0.25), 8, -D / 2 - 0.1), N.Orange)
	end
	box(m, V(DOOR, H - 16, 1), cf * CF(0, 16 + (H - 16) / 2, -D / 2 + 0.5), wall, nil, { Shadow = true, Name = "Header" })
	glow(m, V(DOOR + 1, 0.5, 0.5), cf * CF(0, 16.25, -D / 2 - 0.1), N.Orange)
	box(m, V(W + 2, 1, D + 2), cf * CF(0, H + 0.5, 0), Color3.fromRGB(70, 74, 86), nil, { Shadow = true, Name = "Roof" })
	Kit.Sign(m, cf * CF(0, 19, -D / 2 - 0.35), "CHOP SHOP", N.Orange, 24, 4.5)
	-- The roller door, rolled up above the opening (16 studs clear)
	Kit.Part(m, V(DOOR + 2, 2.4, 2.4), cf * CF(0, 17.4, -D / 2 + 2), C.Steel, Enum.Material.Metal, { Shape = CYL, CanCollide = false, Name = "DoorRoll" })
	deco(m, V(DOOR, 1, 0.3), cf * CF(0, 16.2, -D / 2 + 1.3), Color3.fromRGB(60, 60, 66), Enum.Material.DiamondPlate, { Name = "DoorEdge" })

	-- Car lift (left), tool wall + bench (back), toolboxes (right)
	for _, z in ipairs({ -6, 8 }) do
		box(m, V(1.4, 12, 1.4), cf * CF(-24, 6, z), N.Yellow, nil, { Name = "LiftPost" })
		deco(m, V(8, 0.6, 0.8), cf * CF(-20, 4, z), C.Steel, Enum.Material.Metal, { Name = "LiftArm" })
	end
	deco(m, V(20, 8, 0.3), cf * CF(6, 9, D / 2 - 1.15), P.Peach, nil, { Name = "Pegboard" })
	glow(m, V(20.4, 0.4, 0.4), cf * CF(6, 13.3, D / 2 - 1.2), N.Orange)
	for i, a in ipairs({ 20, -15, 30, 0 }) do
		deco(m, V(0.5, 4, 0.2), cf * CF(-3 + i * 3.6, 9, D / 2 - 1.4) * CFrame.Angles(0, 0, math.rad(a)), C.Steel, Enum.Material.Metal, { Name = "Tool" })
	end
	box(m, V(14, 3.5, 3), cf * CF(6, 1.75, D / 2 - 2.5), C.DarkWood, Enum.Material.Wood, { Name = "Bench" })
	for _, z in ipairs({ 4, 10 }) do
		box(m, V(3, 4, 2.4), cf * CF(W / 2 - 3, 2, z), Color3.fromRGB(230, 70, 80), nil, { Name = "Toolbox" })
		glow(m, V(0.2, 0.3, 2), cf * CF(W / 2 - 4.6, 3, z), N.Yellow)
	end
	-- Tyre stacks: two inside, one outside by the door (off the pad)
	for _, at in ipairs({ CF(-22, 0, 16), CF(23, 0, -14), CF(-(W / 2 + 3), 0, -D / 2 + 3) }) do
		for k = 0, 2 do
			Kit.Part(m, V(1.1, 3, 3), cf * at * CF(0, 0.55 + k * 1.1, 0) * UP, Color3.fromRGB(34, 34, 40), nil,
				{ Shape = CYL, CanCollide = false, Name = "Tyre" })
		end
	end
	for _, x in ipairs({ -8, 8 }) do
		local strip = glow(m, V(1, 0.3, 34), cf * CF(x, H - 0.2, 0), Color3.fromRGB(255, 240, 220))
		if x < 0 then
			light(strip, Color3.fromRGB(255, 225, 190), 36, 1.2)
		end
	end
	reserve(cf, -W / 2 - 5, W / 2 + 1, -D / 2 - 1, D / 2 + 1)
end

-- Spray & Go: drive-through paint booth over the pad, open at both ends along the road ------------------

local function buildSprayAndGo(root, Layout)
	local pad = padOf(Layout.Spawn("SprayAndGo"))
	local c = pad and V(pad.Position.X, 0, pad.Position.Z) or V(250, 0, 820)
	local hs = pad and pad.Size.X / 2 or 20
	local dir, roadDist = nearestRoad(Layout, c)
	local cf = frame(c, dir) -- local X runs along the road; the booth is open at both X ends
	local m = Kit.Model(root, "SprayAndGo_Booth")
	local L, H, wz = 2 * hs + 12, 18, hs + 3 -- walls stand 3 studs outside the pad
	local wallCol = P.Seafoam
	slab(m, L, 2 * wz, cf, C.Concrete, Enum.Material.Concrete)
	for _, sz in ipairs({ -1, 1 }) do
		box(m, V(L, H, 1), cf * CF(0, H / 2, sz * (wz + 0.5)), wallCol, nil, { Shadow = true, Name = "Wall" })
		for i, y in ipairs({ 3, 5, 7 }) do
			deco(m, V(L - 6, 1.2, 0.2), cf * CF(0, y, sz * (wz - 0.1)), PAINT[i], nil, { Name = "PaintStripe" })
		end
		for _, x in ipairs({ -10, 10 }) do
			deco(m, V(0.8, 12, 0.8), cf * CF(x, 7, sz * (wz - 0.6)), C.Steel, Enum.Material.Metal, { Name = "SprayArm" })
			glow(m, V(0.9, 10, 0.3), cf * CF(x, 7, sz * (wz - 1.1)), x < 0 and N.Pink or N.Cyan)
		end
	end
	box(m, V(L + 2, 1, 2 * wz + 4), cf * CF(0, H + 0.5, 0), C.White, nil, { Shadow = true, Name = "Roof" })
	-- End portals: header (15 studs clear), neon outline, small signs facing out
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(1, 3, 2 * wz), cf * CF(sx * (L / 2 - 0.5), H - 1.5, 0), wallCol, nil, { Name = "Header" })
		glow(m, V(0.6, 0.6, 2 * wz), cf * CF(sx * L / 2, H - 3.2, 0), N.Mint)
		for _, sz in ipairs({ -1, 1 }) do
			glow(m, V(0.6, H - 3, 0.6), cf * CF(sx * L / 2, (H - 3) / 2, sz * (wz - 0.3)), N.Mint)
		end
		Kit.Sign(m, cf * CF(sx * (L / 2 + 0.35), H - 1.5, 0) * CFrame.Angles(0, math.rad(sx * -90), 0), "SPRAY & GO", N.Pink, 16, 2.6)
	end
	-- Overhead spray gantry (bottom at 15 studs)
	deco(m, V(1.2, 1.2, 2 * wz - 2), cf * CF(0, 15.6, 0), C.Steel, Enum.Material.Metal, { Name = "Gantry" })
	for i, z in ipairs({ -10, 0, 10 }) do
		local nozzle = glow(m, V(1, 0.6, 1), cf * CF(0, 14.7, z), PAINT[i])
		if i == 2 then
			light(nozzle, N.Mint, 36, 1.2)
		end
	end
	Kit.Sign(m, cf * CF(0, 12, -(wz + 1.35)), "SPRAY & GO", N.Mint, 34, 6)
	-- Drives from the road to both ends of the booth
	local zEnd = -(roadDist - 1)
	if wz - zEnd > 2 then
		for _, sx in ipairs({ -1, 1 }) do
			slab(m, 30, wz - zEnd, cf * CF(sx * (L / 2 + 15), 0, (wz + zEnd) / 2), C.Asphalt, Enum.Material.Asphalt, "Drive")
		end
	end
	reserve(cf, -L / 2 - 30, L / 2 + 30, -roadDist, wz + 2)
end

-- Police HQ: facade on the landmark's face toward the lot, flag pole, barriers beside the cop car pads -----

local function buildPoliceFacade(root, Layout)
	local city = Workspace:FindFirstChild("City")
	local lm = city and city:FindFirstChild("Landmarks")
	local hq = lm and lm:FindFirstChild("PoliceHQ")
	local hqPos = hq and hq.Position or V(575, 25, -420)
	local hqSize = hq and hq.Size or V(160, 50, 120)
	local lotPad = padOf(Layout.Spawn("PoliceLot"))
	local lot = lotPad and lotPad.Position or V(575, 0, -300)
	local dir = snap(V(lot.X - hqPos.X, 0, lot.Z - hqPos.Z))
	local alongX = math.abs(dir.X) > 0
	local W = alongX and hqSize.Z or hqSize.X
	local H = hqSize.Y
	local cf = frame(V(hqPos.X, 0, hqPos.Z) + dir * ((alongX and hqSize.X or hqSize.Z) / 2), dir) -- z = 0 is the face
	local m = Kit.Model(root, "PoliceHQ_Facade")
	local BLUE = Color3.fromRGB(40, 110, 255)

	-- Glass entrance, cyan frame, canopy on two posts
	box(m, V(30, 16, 0.6), cf * CF(0, 8, -0.3), C.Glass, Enum.Material.Glass, { Transparency = 0.35, Reflectance = 0.2, Name = "Entrance" })
	for _, sx in ipairs({ -1, 1 }) do
		deco(m, V(6, 11, 0.3), cf * CF(sx * 3.1, 5.5, -0.75), Color3.fromRGB(30, 50, 90), Enum.Material.Glass, { Transparency = 0.2, Name = "Door" })
		glow(m, V(0.8, 16.8, 0.8), cf * CF(sx * 15.4, 8.4, -0.5), N.Cyan)
		glow(m, V((W - 34) / 2, 0.5, 0.5), cf * CF(sx * (17 + (W - 34) / 4), 3, -0.3), N.Cyan)
		box(m, V(0.8, 18.5, 0.8), cf * CF(sx * 19, 9.25, -9.5), C.Steel, Enum.Material.Metal, { Name = "CanopyPost" })
	end
	glow(m, V(31.6, 0.8, 0.8), cf * CF(0, 16.4, -0.5), N.Cyan)
	box(m, V(40, 1, 10), cf * CF(0, 19, -5), C.White, nil, { Shadow = true, Name = "Canopy" })
	local canopyGlow = glow(m, V(40.4, 0.4, 0.4), cf * CF(0, 18.5, -10.1), N.Cyan)
	light(canopyGlow, N.Cyan, 40, 1.3)

	-- Window bands, neon lines, corner fins
	local ww = W / 2 - 14
	for _, y in ipairs({ 26, 36 }) do
		for _, sx in ipairs({ -1, 1 }) do
			deco(m, V(ww, 6, 0.4), cf * CF(sx * (10 + ww / 2), y, -0.2), C.Glass, Enum.Material.Glass, { Reflectance = 0.2, Name = "Window" })
		end
	end
	glow(m, V(W, 0.6, 0.6), cf * CF(0, 21.5, -0.3), N.Cyan)
	glow(m, V(W, 0.6, 0.6), cf * CF(0, 43, -0.3), BLUE)
	for _, sx in ipairs({ -1, 1 }) do
		glow(m, V(0.8, H, 0.8), cf * CF(sx * (W / 2 - 0.2), H / 2, -0.4), N.Cyan)
	end
	-- Badge: gold disc, blue disc, white neon star
	local badge = cf * CF(0, 31, 0)
	disc(m, badge * CF(0, 0, -0.25), 0.5, 11, GOLD, Enum.Material.Metal)
	local blueDisc = disc(m, badge * CF(0, 0, -0.5), 0.6, 8, BLUE, Enum.Material.SmoothPlastic)
	for _, a in ipairs({ 0, 60, 120 }) do
		glow(m, V(0.9, 5.5, 0.2), badge * CF(0, 0, -0.9) * CFrame.Angles(0, 0, math.rad(a)), C.White)
	end
	light(blueDisc, BLUE, 30, 1.2)
	-- Name on a parapet standing on the roof edge
	box(m, V(82, 9, 1.2), cf * CF(0, H + 4.5, 0.8), Color3.fromRGB(40, 60, 120), nil, { Shadow = true, Name = "Parapet" })
	Kit.Sign(m, cf * CF(0, H + 4.5, -0.15), "PORT SOLANA PD", N.Cyan, 76, 7)

	-- Flag pole off the lot's corner, planters with palms either side of the entrance
	local fp = cf * CF(W / 2 - 20, 0, -12)
	box(m, V(3, 1.5, 3), fp * CF(0, 0.75, 0), C.Concrete, Enum.Material.Concrete, { Name = "FlagBase" })
	column(m, fp, 40, 0.8, C.White, Enum.Material.Metal)
	ball(m, fp * CF(0, 40.5, 0), 1.4, N.Yellow, Enum.Material.Neon)
	local flag = fp * CF(5.4, 36, 0)
	deco(m, V(10, 6, 0.2), flag, BLUE, Enum.Material.Fabric, { Name = "Flag" })
	deco(m, V(10, 1.2, 0.3), flag * CF(0, -1.2, 0), C.White, Enum.Material.Fabric, { Name = "Flag" })
	disc(m, flag * CF(-2.5, 1.2, 0), 0.4, 2.6, N.Yellow, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		box(m, V(6, 1.5, 6), cf * CF(sx * 27, 0.75, -5), C.Concrete, Enum.Material.Concrete, { Name = "Planter" })
		palm(m, Layout, (cf * CF(sx * 27, 0, -5)).Position, 1.2)
	end

	-- Sawhorse barriers parked beyond both ends of the row of cop car pads (the pads stay clear)
	local minX, maxX = math.huge, -math.huge
	local spawns = Workspace:FindFirstChild("Spawns")
	for _, p in ipairs(spawns and spawns:GetChildren() or {}) do
		if p:IsA("BasePart") and p.Name == "CarPad" and p:GetAttribute("Side") == "Cop" then
			minX = math.min(minX, p.Position.X - p.Size.X / 2)
			maxX = math.max(maxX, p.Position.X + p.Size.X / 2)
		end
	end
	if minX == math.huge then
		minX, maxX = lot.X - 97, lot.X + 97
	end
	for _, x in ipairs({ minX - 12, maxX + 12 }) do
		for _, dz in ipairs({ -20, 20 }) do
			local b = CF(x, 0, lot.Z + dz)
			for _, z in ipairs({ -3.5, 3.5 }) do
				deco(m, V(2.4, 3, 0.4), b * CF(0, 1.5, z), C.White, nil, { Name = "BarrierLeg" })
			end
			deco(m, V(0.5, 1.1, 8), b * CF(0, 3.1, 0), BLUE, nil, { Name = "BarrierRail" })
			glow(m, V(0.6, 0.5, 0.6), b * CF(0, 3.9, 3.5), N.Cyan)
		end
	end
end

-- Taxi stand: small yellow kiosk + TAXI sign beside the stand (road side), never on it ---------------------

local function buildTaxiKiosk(root, Layout)
	local acts = Workspace:FindFirstChild("Activities")
	local stand = acts and acts:FindFirstChild("TaxiStand")
	local c = stand and V(stand.Position.X, 0, stand.Position.Z) or V(-240, 0, 40)
	local hs = stand and stand.Size.X / 2 or 13
	local dir, roadDist = nearestRoad(Layout, c)
	local side = dir
	if roadDist - 10 < hs + 8 then -- not enough room toward the road: stand the kiosk to one side
		side = V(-dir.Z, 0, dir.X)
	end
	local cf = frame(c + side * (hs + 8), -side) -- window faces the stand
	local m = Kit.Model(root, "TaxiKiosk")
	box(m, V(6, 8, 6), cf * CF(0, 4, 0), N.Yellow, nil, { Shadow = true, Name = "Kiosk" })
	deco(m, V(4.4, 3, 0.3), cf * CF(0, 5, -3.1), C.Glass, Enum.Material.Glass, { Transparency = 0.3, Name = "Window" })
	deco(m, V(5, 0.4, 1.2), cf * CF(0, 3.4, -3.6), C.White, nil, { Name = "Ledge" })
	deco(m, V(6.2, 1, 6.2), cf * CF(0, 7.2, 0), Color3.fromRGB(25, 25, 30), nil, { Name = "Checker" })
	for _, x in ipairs({ -2, 0, 2 }) do
		deco(m, V(1, 1, 0.1), cf * CF(x, 7.2, -3.15), C.White, nil, { Name = "Checker" })
	end
	box(m, V(7.6, 0.6, 7.6), cf * CF(0, 8.3, 0), C.White, nil, { Shadow = true, Name = "Roof" })
	for _, a in ipairs({ 0, 180 }) do
		Kit.Sign(m, cf * CF(0, 10.1, 0) * CFrame.Angles(0, math.rad(a), 0) * CF(0, 0, -0.35), "TAXI", N.Yellow, 7, 3)
	end
	Kit.Bench(m, cf * CF(6.5, 0, -1))
	reserve(cf, -4, 10, -4, 4)
end

-- Build ------------------------------------------------------------------------------------------------

function Art.Build(folder, ArtKit, Layout)
	Kit, C, N = ArtKit, ArtKit.Colors, ArtKit.Colors.Neon
	local p = C.Pastels
	P = { Pink = p[1], Seafoam = p[2], Peach = p[3], Lavender = p[4], Mint = p[5], Butter = p[6], Deco = p[7],
		Paver = Color3.fromRGB(226, 214, 200) }
	GOODS = { { N.Pink, N.Yellow }, { N.Cyan, N.Orange }, { N.Mint, N.Pink }, { N.Purple, N.Yellow } }
	KIOSK = { { N.Pink, N.Cyan }, { N.Cyan, N.Pink }, { N.Purple, N.Yellow }, { N.Orange, N.Mint }, { N.Mint, N.Purple } }
	PAINT = { N.Pink, N.Cyan, N.Yellow }
	lightsUsed = 0
	myFolder = folder
	table.clear(reserved)

	local jobs = {
		{ "GlowMart", buildGlowMart },
		{ "FuelStop", buildFuelStop },
		{ "SparkleCo", buildSparkleCo },
		{ "ClubNova", buildClubNova },
		{ "CoastalBank", buildCoastalBank },
		{ "Hideout", buildHideout },
		{ "Fence", buildMarisStall },
		{ "ChopShop", buildChopShop },
		{ "SprayAndGo", buildSprayAndGo },
		{ "PoliceHQ", buildPoliceFacade },
		{ "TaxiStand", buildTaxiKiosk },
	}
	for i = 1, #ATMS do
		table.insert(jobs, { "ATM" .. i, function(root, L)
			buildATM(root, L, i)
		end })
	end
	-- One broken site must not stop the rest.
	for _, job in ipairs(jobs) do
		local ok, err = pcall(job[2], folder, Layout)
		if not ok then
			warn("[HeistFronts] " .. job[1] .. ": " .. tostring(err))
		end
	end

	-- Modules that run after this one keep their props out of these buildings and forecourts.
	local baseIsFree = Layout.IsFree
	Layout.IsFree = function(pos, radius)
		return baseIsFree(pos, radius) and not isReserved(pos, radius or 6)
	end

	local parts = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end

return Art
