-- Beach (ModuleScript, ServerStorage.Tools.Art.Beach). Studio-only art for Flamingo Beach, the Ferris pier
-- and Lighthouse Key: boardwalk, palms, umbrellas, lifeguard towers, snack shacks, volleyball, the pier
-- (arch, booths, railings, lamps, Ferris wheel), Flo the flamingo statue, the FLAMINGO BEACH gantry over
-- Ocean Drive, the lighthouse, the Key Drift Club and a few Gus the Gator touches.
-- Area: sand x 1030..1500, z -2000..600 (Ocean Drive's east edge is x 1030); pier deck z -417..-383 from
-- x 1431; Lighthouse Key x 2100..2450, z -1550..-1150 (the drift pad x 2105..2295 stays clear).

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Art = {}

function Art.Build(folder, ArtKit, Layout)
	local C, N = ArtKit.Colors, ArtKit.Colors.Neon
	local M = Enum.Material
	local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
	local DARK = Color3.fromRGB(40, 36, 52)
	local ROCK = Color3.fromRGB(150, 138, 124)
	local rng = Random.new(1502) -- own seed: the beach comes out the same on every rebuild
	local assets = ServerStorage:FindFirstChild("ArtAssets")

	local function sub(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		return f
	end
	local fLand, fPier, fSand, fWalk, fKey = sub("Landmarks"), sub("Pier"), sub("Sand"), sub("Boardwalk"), sub("LighthouseKey")

	-- Part helpers -------------------------------------------------------------------------------
	local part, neon = ArtKit.Part, ArtKit.Neon
	local function deco(parent, size, cf, color, material) -- small non-colliding decoration
		return ArtKit.Part(parent, size, cf, color, material, { CanCollide = false })
	end
	local function cyl(parent, pos, length, dia, color, material, opts) -- upright cylinder centred on pos
		opts = opts or {}
		opts.Shape = CYL
		return ArtKit.Part(parent, Vector3.new(length, dia, dia), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, material, opts)
	end
	local function ball(parent, pos, dia, color, material, opts)
		opts = opts or {}
		opts.Shape = BALL
		return ArtKit.Part(parent, Vector3.new(dia, dia, dia), CFrame.new(pos), color, material, opts)
	end

	-- Real lights: at most 20 in this module (ArtKit.Light also enforces the city-wide cap).
	local lights, MAX_LIGHTS = 0, 20
	local function light(p, color, range, brightness)
		if p and lights < MAX_LIGHTS and ArtKit.Light(p, color, range, brightness) then
			lights += 1
		end
	end
	local function lightAnchor(parent, pos)
		return part(parent, Vector3.new(1, 1, 1), CFrame.new(pos), C.White, nil, { CanCollide = false, Transparency = 1, Name = "LightAnchor" })
	end

	-- Generated mesh from ServerStorage.ArtAssets, scaled, standing on groundCf. nil if the asset is missing.
	local function asset(parent, name, scale, groundCf, collide)
		local template = assets and assets:FindFirstChild(name)
		if not template then
			return nil
		end
		local c = template:Clone()
		if c:IsA("BasePart") then
			c.Anchored = true
			c.CanTouch = false
			c.CanCollide = collide ~= false
			c.CastShadow = collide ~= false
			c.Size = template.Size * scale
			c.CFrame = groundCf * CFrame.new(0, c.Size.Y / 2, 0)
		elseif c:IsA("Model") then
			c:ScaleTo(c:GetScale() * scale)
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanTouch = false
					d.CanCollide = collide ~= false
				end
			end
			local box, size = c:GetBoundingBox()
			c:PivotTo(groundCf * CFrame.new(0, size.Y / 2, 0) * box:ToObjectSpace(c:GetPivot()))
		else
			c:Destroy()
			return nil
		end
		c.Name = name
		c.Parent = parent
		return c
	end

	-- The real landmarks replace the greybox placeholders in City.Landmarks: hide those, but leave them in
	-- place (still queryable) so Layout.IsFree and anything else that looks them up keeps working.
	local city = Workspace:FindFirstChild("City")
	local landmarks = city and city:FindFirstChild("Landmarks")
	local function hidePlaceholder(name)
		local p = landmarks and landmarks:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Transparency = 1
			p.CanCollide = false
			p.CastShadow = false
		end
	end

	-- Keep-out areas ------------------------------------------------------------------------------
	-- hard: gameplay parts (+4 studs); even the flush boardwalk avoids them.
	-- soft: everything props avoid: pads with room to drive off, runways, heist fronts, road verges, and
	--       every feature placed so far (claim). Many pads are CanQuery = false, so Layout.IsFree can't see them.
	local hard, soft = {}, {}
	local function rect(list, x0, x1, z0, z1)
		table.insert(list, { x0, x1, z0, z1 })
	end
	local function hits(list, x, z, r)
		for _, b in ipairs(list) do
			if x + r > b[1] and x - r < b[2] and z + r > b[3] and z - r < b[4] then
				return true
			end
		end
		return false
	end
	local function open(x, z, r)
		return not hits(hard, x, z, r) and not hits(soft, x, z, r) and Layout.IsFree(Vector3.new(x, 0, z), r)
	end
	local function claim(x, z, r)
		rect(soft, x - r, x + r, z - r, z + r)
	end
	local function findSpot(x, z, r) -- z, or a nearby z, where a prop of radius r fits
		for _, dz in ipairs({ 0, 30, -30, 60, -60 }) do
			if open(x, z + dz, r) then
				return z + dz
			end
		end
		return nil
	end

	for _, name in ipairs({ "Heists", "Spawns", "Activities" }) do
		local f = Workspace:FindFirstChild(name)
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				local cf, h = d.CFrame, d.Size / 2
				local ex = math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z
				local ez = math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
				local p = cf.Position
				rect(hard, p.X - ex - 4, p.X + ex + 4, p.Z - ez - 4, p.Z + ez + 4)
				rect(soft, p.X - ex - 12, p.X + ex + 12, p.Z - ez - 12, p.Z + ez + 12)
			end
		end
	end
	rect(soft, 960, 1036, -2000, 600) -- Ocean Drive and its verge
	rect(soft, 1030, 1100, -735, -665) -- beach ATM (1060, -700): room for its kiosk
	rect(soft, 1040, 1205, -240, -60) -- Club Nova (1120, -150) frontage
	rect(soft, 1035, 1150, -1035, -865) -- beach spawn, car pads and the lane they drive out on
	rect(soft, 1220, 1280, -1920, -1500) -- Beach Launch ramp (1250, -1780): run-up and landing
	rect(soft, 1290, 1350, -520, -130) -- Boardwalk Hop ramp (1320, -250): run-up and landing
	rect(soft, 990, 2120, -1392, -1308) -- causeway
	rect(soft, 1420, 1800, -432, -368) -- Ferris pier deck

	-- Small props ---------------------------------------------------------------------------------
	local palmMesh = assets and assets:FindFirstChild("PalmTree")
	local function palm(parent, x, z, s)
		ArtKit.Palm(parent, Vector3.new(x, 0, z), s, rng:NextNumber(0, math.pi * 2))
	end
	local function bench(parent, x, z, facing)
		local p = Vector3.new(x, 0, z)
		local cf = CFrame.lookAt(p, p + facing)
		ArtKit.Bench(parent, cf)
		part(parent, Vector3.new(4.5, 1.4, 1.2), cf * CFrame.new(0, 0.7, 0.2), C.White, nil, { Name = "BenchBase" })
	end
	local function bin(parent, x, z)
		cyl(parent, Vector3.new(x, 1.5, z), 3, 2.2, C.Pastels[2], nil, { Name = "Bin" })
		cyl(parent, Vector3.new(x, 3.15, z), 0.3, 2.4, N.Pink, M.Neon, { CanCollide = false, Name = "Neon" })
	end
	local function lamp(parent, x, y0, z, height, color, lit)
		part(parent, Vector3.new(0.6, height, 0.6), CFrame.new(x, y0 + height / 2, z), C.White, nil, { Name = "LampPost" })
		local head = neon(parent, Vector3.new(1.4, 2, 1.4), CFrame.new(x, y0 + height + 1, z), color)
		if lit then
			light(head, color, 32, 1.3)
		end
	end
	local function picnic(parent, pos, yaw, umbrellaColor)
		local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		part(parent, Vector3.new(7, 0.4, 3.4), cf * CFrame.new(0, 2.8, 0), C.Wood, M.WoodPlanks, { Name = "TableTop" })
		part(parent, Vector3.new(1, 2.6, 1), cf * CFrame.new(0, 1.3, 0), C.White, nil, { Name = "TableLeg" })
		for _, s in ipairs({ -1, 1 }) do
			part(parent, Vector3.new(7, 1.6, 1.2), cf * CFrame.new(0, 0.8, s * 2.8), C.Wood, M.WoodPlanks, { Name = "BenchBlock" })
		end
		if umbrellaColor then
			ArtKit.Umbrella(parent, pos, umbrellaColor)
		end
	end
	-- Sign on two posts; facing = direction the text faces; y = centre height of the panel.
	local function postedSign(parent, x, z, facing, text, color, width, height, y)
		local base = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x, 0, z) + facing)
		local postH = y - height / 2 + 0.3
		for _, s in ipairs({ -1, 1 }) do
			part(parent, Vector3.new(0.6, postH, 0.6), base * CFrame.new(s * (width / 2 - 1), postH / 2, 0.5), C.White, nil, { Name = "Post" })
		end
		return ArtKit.Sign(parent, base * CFrame.new(0, y, 0), text, color, width, height)
	end

	-- Part fallbacks for missing meshes -----------------------------------------------------------
	local function partFlamingo(parent, cf, s)
		local pink = Color3.fromRGB(255, 120, 180)
		for _, x in ipairs({ -1.2, 1.2 }) do
			part(parent, Vector3.new(0.5 * s, 14 * s, 0.5 * s), cf * CFrame.new(x * s, 7 * s, 0), pink, nil, { Name = "Leg" })
		end
		ball(parent, (cf * CFrame.new(0, 17 * s, 0)).Position, 9 * s, pink, nil, { Name = "Body" })
		part(parent, Vector3.new(1.4 * s, 10 * s, 1.4 * s), cf * CFrame.new(0, 24 * s, -3 * s) * CFrame.Angles(math.rad(-15), 0, 0), pink, nil, { Name = "Neck" })
		ball(parent, (cf * CFrame.new(0, 29 * s, -4.5 * s)).Position, 3 * s, pink, nil, { Name = "Head" })
		part(parent, Vector3.new(0.8 * s, 0.8 * s, 3 * s), cf * CFrame.new(0, 28.6 * s, -7 * s), DARK, nil, { Name = "Beak" })
	end
	local function partGator(parent, cf, s)
		local green = Color3.fromRGB(80, 170, 90)
		part(parent, Vector3.new(0.9 * s, 0.6 * s, 1.6 * s), cf * CFrame.new(0, 0.3 * s, 0), green, nil, { Name = "Body" })
		part(parent, Vector3.new(0.7 * s, 0.45 * s, 0.9 * s), cf * CFrame.new(0, 0.25 * s, -1.2 * s), green, nil, { Name = "Head" })
		part(parent, Vector3.new(0.4 * s, 0.3 * s, 1.2 * s), cf * CFrame.new(0, 0.15 * s, 1.3 * s), green, nil, { Name = "Tail" })
	end
	local function partWheel(parent, cf) -- wheel plane = local XY of cf; hub 58 up, radius 50
		local R, hubY = 50, 58
		local lean = math.rad(20)
		for _, s in ipairs({ -1, 1 }) do
			for _, side in ipairs({ -1, 1 }) do
				part(parent, Vector3.new(1.6, hubY / math.cos(lean), 1.6), cf * CFrame.new(side * hubY * math.tan(lean) / 2, hubY / 2, s * 8) * CFrame.Angles(0, 0, side * lean),
					C.White, nil, { Name = "Leg" })
			end
		end
		local n = 16
		for i = 1, n do
			local a = (i - 0.5) / n * math.pi * 2
			neon(parent, Vector3.new(2 * R * math.sin(math.pi / n) + 0.5, 1.2, 1.2), cf * CFrame.new(R * math.cos(a), hubY + R * math.sin(a), 0) * CFrame.Angles(0, 0, a + math.pi / 2),
				i % 2 == 0 and N.Pink or N.Cyan)
		end
		part(parent, Vector3.new(18, 4, 4), cf * CFrame.new(0, hubY, 0) * CFrame.Angles(0, math.pi / 2, 0), C.White, nil, { Shape = CYL, Name = "Hub" })
	end
	local function partLighthouse(parent, cf) -- returns its height
		cyl(parent, (cf * CFrame.new(0, 15, 0)).Position, 30, 22, C.White, nil, { Shadow = true, Name = "Tower" })
		cyl(parent, (cf * CFrame.new(0, 42.5, 0)).Position, 25, 19, C.Pastels[1], nil, { Shadow = true, Name = "Tower" })
		cyl(parent, (cf * CFrame.new(0, 67.5, 0)).Position, 25, 16, C.White, nil, { Shadow = true, Name = "Tower" })
		cyl(parent, (cf * CFrame.new(0, 84, 0)).Position, 8, 12, N.Yellow, M.Neon, { Name = "Lamp" })
		ball(parent, (cf * CFrame.new(0, 90, 0)).Position, 14, N.Pink, nil, { Name = "Cap" })
		return 92
	end

	-- Landmark: FLAMINGO BEACH gantry over Ocean Drive -----------------------------------------------
	-- Replaces the FlamingoSign placeholder. At z = -860 (south of the beach car pads, so nothing stands
	-- in the lane cars take off the pads); both pylons stand 6+ studs outside the road edges (x 970..1030).
	do
		local GZ = -860
		for _, x in ipairs({ 962, 1038 }) do
			part(fLand, Vector3.new(4, 46, 4), CFrame.new(x, 23, GZ), C.Pastels[1], nil, { Shadow = true, Name = "Pylon" })
			neon(fLand, Vector3.new(0.5, 40, 1.2), CFrame.new(x + (x < 1000 and 2.2 or -2.2), 22, GZ), N.Cyan)
			ball(fLand, Vector3.new(x, 48.5, GZ), 5, N.Pink, M.Neon, { CanCollide = false, Name = "Neon" })
		end
		part(fLand, Vector3.new(80, 3, 3), CFrame.new(1000, 42.5, GZ), C.White, nil, { Shadow = true, Name = "Beam" })
		for _, dz in ipairs({ -1, 1 }) do -- back-to-back signs, one for each direction of traffic
			local c = Vector3.new(1000, 50, GZ + dz * 0.4)
			local s = ArtKit.Sign(fLand, CFrame.lookAt(c, c + Vector3.new(0, 0, dz)), "FLAMINGO BEACH", N.Pink, 70, 12)
			if dz == 1 then
				light(s, N.Pink, 40, 1.6)
			end
		end
		claim(1038, GZ, 8)
		hidePlaceholder("FlamingoSign")
	end

	-- Landmark: Flo the flamingo on her plinth (1180, -900), facing Ocean Drive ----------------------
	do
		local SX, SZ = 1180, -900
		cyl(fLand, Vector3.new(SX, 0.6, SZ), 1.2, 46, C.Pastels[2], nil, { Shadow = true, Name = "PlinthStep" })
		cyl(fLand, Vector3.new(SX, 2.5, SZ), 5, 40, C.White, nil, { Shadow = true, Name = "Plinth" })
		cyl(fLand, Vector3.new(SX, 4.7, SZ), 0.6, 40.6, N.Pink, M.Neon, { CanCollide = false, Name = "Neon" })
		local face = CFrame.lookAt(Vector3.new(SX, 5, SZ), Vector3.new(SX - 1, 5, SZ))
		if not asset(fLand, "FlamingoStatue", 2, face) then
			partFlamingo(fLand, face, 2)
		end
		part(fLand, Vector3.new(1.2, 1.6, 14), CFrame.new(SX - 25, 0.8, SZ), C.White, nil, { Name = "PlaqueStand" })
		ArtKit.Sign(fLand, CFrame.lookAt(Vector3.new(SX - 25, 2.9, SZ), Vector3.new(SX - 26, 2.9, SZ)), "FLO THE FLAMINGO", N.Pink, 14, 2.6)
		light(lightAnchor(fLand, Vector3.new(SX - 18, 14, SZ)), N.Pink, 40, 2)
		-- a little flock of lawn flamingos behind her (mesh only; skipped if the asset is missing)
		for i = 0, 5 do
			local a = math.rad(-100 + i * 40)
			local p = Vector3.new(SX + 28 * math.cos(a), 0, SZ + 28 * math.sin(a))
			asset(fLand, "FlamingoStatue", 0.2, CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), false)
		end
		for _, d in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			local x, z = SX + d[1] * 32, SZ + d[2] * 32
			if open(x, z, 4) then
				palm(fLand, x, z, 1.6)
			end
		end
		rect(soft, SX - 36, SX + 36, SZ - 36, SZ + 36)
	end

	-- Ferris pier -------------------------------------------------------------------------------------
	-- The deck is the road part "FerrisPier" (x 1431.5..1768.5, z -417..-383, top y 0.1); cars can drive
	-- on it, so nothing goes on the deck itself. The wheel stands on a wider plaza at the far end.
	do
		local PZ, EDGE = -400, 17.6
		local N0, S0 = PZ - EDGE, PZ + EDGE -- railing lines just outside the deck edges

		-- Entrance arch (pillars outside the deck, 20 studs of headroom)
		local AX = 1452
		for _, s in ipairs({ -1, 1 }) do
			local z = PZ + s * 21.5
			part(fPier, Vector3.new(3, 20, 3), CFrame.new(AX, 10, z), C.Pastels[2], nil, { Shadow = true, Name = "ArchPillar" })
			neon(fPier, Vector3.new(0.5, 17, 1.2), CFrame.new(AX - 1.7, 10, z), N.Cyan)
			ball(fPier, Vector3.new(AX, 24, z), 3, N.Pink, M.Neon, { CanCollide = false, Name = "Neon" })
		end
		part(fPier, Vector3.new(3, 2.5, 46), CFrame.new(AX, 21.25, PZ), C.White, nil, { Shadow = true, Name = "ArchBeam" })
		local front, back = Vector3.new(AX - 0.4, 26, PZ), Vector3.new(AX + 0.4, 26, PZ)
		light(ArtKit.Sign(fPier, CFrame.lookAt(front, front - Vector3.xAxis), "PORT SOLANA PIER", N.Cyan, 40, 7), N.Cyan, 30, 1.4)
		ArtKit.Sign(fPier, CFrame.lookAt(back, back + Vector3.xAxis), "COME BACK SOON!", N.Pink, 40, 7)

		-- Game booths and food stalls on the sand either side of the landward end, facing the pier
		local function booth(x, z, facing, title, color, lit)
			local p = Vector3.new(x, 0, z)
			local cf = CFrame.lookAt(p, p + facing)
			local m = ArtKit.Model(fPier, "Booth")
			part(m, Vector3.new(10, 7, 8), cf * CFrame.new(0, 3.5, 0), ArtKit.Pick(C.Pastels), nil, { Shadow = true, Name = "Body" })
			deco(m, Vector3.new(8, 3, 0.4), cf * CFrame.new(0, 4.3, -4.1), DARK)
			part(m, Vector3.new(10.4, 0.5, 1.6), cf * CFrame.new(0, 2.6, -4.6), C.White, nil, { Name = "Counter" })
			part(m, Vector3.new(11, 0.6, 10), cf * CFrame.new(0, 7.3, -0.8), color, nil, { Name = "Roof" })
			local sign = ArtKit.Sign(m, cf * CFrame.new(0, 9.3, -3.5), title, color, 10.5, 3.4)
			if lit then
				light(sign, color, 28, 1.2)
			end
			claim(x, z, 9)
		end
		booth(1468, PZ - 40, Vector3.zAxis, "HOOP SHOT", N.Orange)
		booth(1488, PZ - 40, Vector3.zAxis, "COTTON CANDY CLOUD", N.Pink, true)
		booth(1468, PZ + 40, -Vector3.zAxis, "SPLASH RACE", N.Cyan, true)
		booth(1488, PZ + 40, -Vector3.zAxis, "HOT DIGGITY DOGS", N.Yellow)

		-- Wheel plaza: a wider deck under the Ferris wheel (top y 0, just under the pier road's 0.1)
		local PX0, PX1 = 1696, 1786
		local cx = (PX0 + PX1) / 2
		part(fPier, Vector3.new(PX1 - PX0, 1.2, 116), CFrame.new(cx, -0.6, PZ), C.Wood, M.WoodPlanks, { Name = "WheelPlaza" })
		for _, s in ipairs({ -1, 1 }) do
			neon(fPier, Vector3.new(PX1 - PX0, 0.4, 0.3), CFrame.new(cx, -0.6, PZ + s * 58.15), s < 0 and N.Pink or N.Cyan)
		end
		neon(fPier, Vector3.new(0.3, 0.4, 116), CFrame.new(PX1 + 0.15, -0.6, PZ), N.Purple)

		-- Railings (collidable: they keep cars on the pier), from where the water starts
		local function railing(a, b)
			local len = (b - a).Magnitude
			local mid = (a + b) / 2
			local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.X, 0, b.Z))
			for _, y in ipairs({ 1.7, 3.2 }) do
				part(fPier, Vector3.new(0.4, 0.4, len), cf * CFrame.new(0, y, 0), C.White, nil, { Name = "Rail" })
			end
			local n = math.max(1, math.ceil(len / 26))
			for i = 0, n do
				local p = a:Lerp(b, i / n)
				part(fPier, Vector3.new(0.7, 4.3, 0.7), CFrame.new(p.X, 1.25, p.Z), C.White, nil, { Name = "RailPost" })
			end
		end
		local RX0, RX1, RZN, RZS = PX0 + 0.4, PX1 - 0.4, PZ - 57.6, PZ + 57.6
		railing(Vector3.new(1505, 0, N0), Vector3.new(RX0, 0, N0))
		railing(Vector3.new(1505, 0, S0), Vector3.new(RX0, 0, S0))
		railing(Vector3.new(RX0, 0, N0), Vector3.new(RX0, 0, RZN))
		railing(Vector3.new(RX0, 0, RZN), Vector3.new(RX1, 0, RZN))
		railing(Vector3.new(RX1, 0, RZN), Vector3.new(RX1, 0, RZS))
		railing(Vector3.new(RX1, 0, RZS), Vector3.new(RX0, 0, RZS))
		railing(Vector3.new(RX0, 0, RZS), Vector3.new(RX0, 0, S0))

		-- Neon lamp posts on the railing lines (3 real lights) and at the plaza corners
		for i, x in ipairs({ 1525, 1570, 1615, 1660 }) do
			for s, z in ipairs({ N0, S0 }) do
				local lit = (i == 1 and s == 1) or (i == 3 and s == 2) or (i == 4 and s == 1)
				lamp(fPier, x, -0.9, z, 15, (i + s) % 2 == 0 and N.Pink or N.Cyan, lit)
			end
		end
		for _, c in ipairs({ { PX0 + 2, PZ - 56 }, { PX1 - 2, PZ - 56 }, { PX1 - 2, PZ + 56 }, { PX0 + 2, PZ + 56 } }) do
			lamp(fPier, c[1], 0, c[2], 12, N.Purple, false)
		end

		-- Pilings down to the sea bed (y -21) under the deck edges and the plaza
		for _, x in ipairs({ 1550, 1600, 1650 }) do
			for _, s in ipairs({ -1, 1 }) do
				cyl(fPier, Vector3.new(x, -10.95, PZ + s * 15.5), 20.1, 1.8, C.DarkWood, M.Wood, { Name = "Piling" })
			end
		end
		for _, x in ipairs({ PX0 + 4, cx, PX1 - 4 }) do
			for _, s in ipairs({ -1, 1 }) do
				cyl(fPier, Vector3.new(x, -11.1, PZ + s * 55), 20, 1.8, C.DarkWood, M.Wood, { Name = "Piling" })
			end
		end

		-- The Ferris wheel (~5x): wheel plane across the pier, so it faces you all the way down the deck
		local wheelCf = CFrame.new(1740, 0.1, PZ) * CFrame.Angles(0, math.pi / 2, 0)
		if not asset(fPier, "FerrisWheel", 5, wheelCf) then
			partWheel(fPier, wheelCf)
		end
		hidePlaceholder("FerrisWheel")
		light(lightAnchor(fPier, Vector3.new(1740, 60, PZ)), N.Pink, 60, 2)
		postedSign(fPier, 1708, PZ - 38, -Vector3.xAxis, "SOLANA SKY WHEEL", N.Pink, 18, 4, 8)
		postedSign(fPier, 1708, PZ + 38, -Vector3.xAxis, "GUS SAYS: HOLD ON TO YOUR HAT!", N.Yellow, 18, 4, 8)
	end

	-- Beach: snack shacks (east of the boardwalk, serving windows facing it) -------------------------
	local function coconuts(m, cf)
		for _, o in ipairs({ { -1.8, 0 }, { 1.6, 0.8 } }) do
			ball(m, (cf * CFrame.new(o[1], 1.5, o[2])).Position, 3.2, Color3.fromRGB(110, 76, 50), nil, { CanCollide = false, Name = "Coconut" })
		end
	end
	local function shavedIce(m, cf)
		cyl(m, (cf * CFrame.new(0, 1.6, 0)).Position, 3.2, 3.2, C.White, nil, { CanCollide = false, Name = "Cup" })
		ball(m, (cf * CFrame.new(0, 3.9, 0)).Position, 4.4, N.Pink, nil, { CanCollide = false, Name = "ShavedIce" })
	end
	local function taco(m, cf) -- a half-buried disc reads as a taco from the boardwalk
		local face = cf * CFrame.Angles(0, math.pi / 2, 0)
		part(m, Vector3.new(1.4, 7, 7), face, N.Yellow, nil, { Shape = CYL, CanCollide = false, Name = "Taco" })
		part(m, Vector3.new(1.7, 6.2, 6.2), face * CFrame.new(0, 0.9, 0), C.Leaf, nil, { Shape = CYL, CanCollide = false, Name = "Lettuce" })
	end
	local function shack(z, title, body, trim, topper)
		z = findSpot(1110, z, 13)
		if not z then
			return
		end
		local p = Vector3.new(1116, 0, z)
		local cf = CFrame.lookAt(p, p - Vector3.xAxis)
		local m = ArtKit.Model(fSand, "SnackShack")
		part(m, Vector3.new(16, 9, 12), cf * CFrame.new(0, 4.5, 0), body, nil, { Shadow = true, Name = "Body" })
		deco(m, Vector3.new(12, 3.5, 0.4), cf * CFrame.new(0, 5.3, -6.1), DARK)
		part(m, Vector3.new(14, 0.5, 2.2), cf * CFrame.new(0, 3.3, -7), C.White, nil, { Name = "Counter" })
		part(m, Vector3.new(19, 0.8, 15), cf * CFrame.new(0, 9.4, 0), C.White, nil, { Shadow = true, Name = "Roof" })
		neon(m, Vector3.new(19.2, 0.4, 0.4), cf * CFrame.new(0, 9, -7.6), trim)
		deco(m, Vector3.new(16, 0.4, 4.4), cf * CFrame.new(0, 7.6, -8.1) * CFrame.Angles(math.rad(-20), 0, 0), trim) -- awning
		light(ArtKit.Sign(m, cf * CFrame.new(0, 12, -6.5), title, trim, 18, 4.4), trim, 26, 1.3)
		topper(m, cf * CFrame.new(3.5, 9.8, 2.5))
		for _, x in ipairs({ -3.5, 3.5 }) do
			cyl(m, (cf * CFrame.new(x, 1.2, -10)).Position, 2.4, 0.4, C.Steel, M.Metal, { Name = "StoolLeg" })
			cyl(m, (cf * CFrame.new(x, 2.55, -10)).Position, 0.3, 2, trim, nil, { Name = "StoolSeat" })
		end
		picnic(m, (cf * CFrame.new(0, 0, -19)).Position, math.pi / 2, ArtKit.PickNeon())
		rect(soft, 1090, 1128, z - 13, z + 13)
	end
	shack(-1230, "Coco's Coconuts", C.Pastels[3], N.Orange, coconuts)
	shack(-500, "Frozen Flamingo Shaved Ice", C.Pastels[2], N.Pink, shavedIce)
	shack(260, "Taco Wave", C.Pastels[6], N.Cyan, taco)

	-- Beach: lifeguard towers near the waterline, each with a flag and two surfboards -----------------
	for i, z0 in ipairs({ -1700, -1150, -700, -40, 420 }) do
		local z = findSpot(1440, z0, 8)
		if z then
			local p = Vector3.new(1440, 0, z)
			local cf = CFrame.lookAt(p, p + Vector3.xAxis)
			ArtKit.LifeguardTower(fSand, cf)
			part(fSand, Vector3.new(0.3, 6, 0.3), cf * CFrame.new(3.5, 18.1, 3.5), C.White, nil, { CanCollide = false, Name = "FlagPole" })
			deco(fSand, Vector3.new(0.15, 2, 3), cf * CFrame.new(3.5, 20.1, 5.15), i % 2 == 0 and N.Orange or N.Pink)
			for _, s in ipairs({ -1, 1 }) do
				deco(fSand, Vector3.new(2.4, 9, 0.5), cf * CFrame.new(-6.5, 3.8, s * 2.5) * CFrame.Angles(0, 0, math.rad(s * 7)), ArtKit.PickNeon())
			end
			claim(1440, z, 10)
		end
	end

	-- Beach: volleyball court with net and two sideline benches ------------------------------------
	do
		local cx, cz = 1300, findSpot(1300, -1080, 30)
		if cz then
			local vb = ArtKit.Model(fSand, "Volleyball")
			deco(vb, Vector3.new(30, 0.12, 58), CFrame.new(cx, 0.06, cz), Color3.fromRGB(250, 230, 190), M.Sand)
			for _, s in ipairs({ -1, 1 }) do
				deco(vb, Vector3.new(0.5, 0.14, 56), CFrame.new(cx + s * 14, 0.07, cz), C.White)
				deco(vb, Vector3.new(28.5, 0.14, 0.5), CFrame.new(cx, 0.07, cz + s * 28), C.White)
				part(vb, Vector3.new(0.6, 9, 0.6), CFrame.new(cx + s * 16, 4.5, cz), C.White, nil, { Name = "NetPost" })
				bench(vb, cx + s * 22, cz + s * 14, Vector3.new(-s, 0, 0))
			end
			part(vb, Vector3.new(32, 3.2, 0.15), CFrame.new(cx, 6.3, cz), C.White, nil, { CanCollide = false, Transparency = 0.35, Name = "Net" })
			neon(vb, Vector3.new(32, 0.4, 0.3), CFrame.new(cx, 8.1, cz), N.Pink)
			ball(vb, Vector3.new(cx + 6, 0.8, cz + 12), 1.6, N.Yellow, nil, { CanCollide = false, Name = "Volleyball" })
			rect(soft, cx - 28, cx + 28, cz - 34, cz + 34)
		end
	end

	-- Gus the Gator: roadside billboards and Gus himself sunbathing on a towel ----------------------
	for _, b in ipairs({ { -1480, "GUS SAYS: WEAR SUNSCREEN!", N.Yellow }, { 380, "SUNBURN INSURANCE: GUS HAS YOU COVERED", N.Pink } }) do
		local z = findSpot(1054, b[1], 12)
		if z then
			local p = Vector3.new(1054, 0, z)
			ArtKit.Billboard(fSand, CFrame.lookAt(p, p - Vector3.xAxis), b[2], b[3])
			claim(1054, z, 18)
		end
	end
	do
		local gx, gz = 1370, findSpot(1370, -760, 11)
		if gz then
			deco(fSand, Vector3.new(7, 0.12, 13), CFrame.new(gx, 0.06, gz), C.Pastels[1], M.Fabric)
			deco(fSand, Vector3.new(7.02, 0.14, 1.6), CFrame.new(gx, 0.07, gz + 4), N.Cyan, M.Fabric)
			local towel = CFrame.new(gx, 0.12, gz) * CFrame.Angles(0, math.rad(10), 0)
			if not asset(fSand, "Gator", 3.5, towel) then
				partGator(fSand, towel, 3.5)
			end
			ArtKit.Umbrella(fSand, Vector3.new(gx + 6, 0, gz - 6), N.Mint)
			part(fSand, Vector3.new(3, 2.2, 2), CFrame.new(gx - 6, 1.1, gz + 5), N.Cyan, nil, { Name = "Cooler" })
			part(fSand, Vector3.new(3.2, 0.4, 2.2), CFrame.new(gx - 6, 2.4, gz + 5), C.White, nil, { CanCollide = false, Name = "CoolerLid" })
			part(fSand, Vector3.new(0.4, 2, 0.4), CFrame.new(gx - 7, 1, gz - 6), C.Wood, nil, { CanCollide = false, Name = "Stake" })
			ArtKit.Sign(fSand, CFrame.lookAt(Vector3.new(gx - 7, 3.2, gz - 6), Vector3.new(gx - 8, 3.2, gz - 6)), "GUS IS ON VACATION", N.Mint, 9, 2.4)
			claim(gx, gz, 12)
		end
	end

	-- Boardwalk: flush planks (top 0.5, edge boards 0.6) so cars roll straight over; gaps at pads/roads
	local function planks(from, to, width)
		local dir = (to - from).Unit
		local STEP = 10
		local n = math.floor((to - from).Magnitude / STEP)
		local function build(i0, i1)
			local a, b = from + dir * (i0 * STEP), from + dir * (i1 * STEP)
			if (b - a).Magnitude < 10 then
				return
			end
			local cf = CFrame.lookAt((a + b) / 2, b)
			part(fWalk, Vector3.new(width, 1, (b - a).Magnitude), cf, C.Wood, M.WoodPlanks, { Name = "Boardwalk" })
			for _, s in ipairs({ -1, 1 }) do
				part(fWalk, Vector3.new(0.8, 1.2, (b - a).Magnitude), cf * CFrame.new(s * (width / 2 + 0.4), 0, 0), C.DarkWood, M.Wood, { Name = "Edge" })
			end
		end
		local runStart
		for i = 0, n - 1 do
			local c = from + dir * ((i + 0.5) * STEP)
			local ok = not hits(hard, c.X, c.Z, width / 2 + 1) and Layout.IsFree(c, width / 2 + 1)
			if ok and not runStart then
				runStart = i
			elseif not ok and runStart then
				build(runStart, i)
				runStart = nil
			end
		end
		if runStart then
			build(runStart, n)
		end
		local w = width / 2 + 2
		rect(soft, math.min(from.X, to.X) - w, math.max(from.X, to.X) + w, math.min(from.Z, to.Z) - w, math.max(from.Z, to.Z) + w)
	end
	planks(Vector3.new(1070, 0, -1890), Vector3.new(1070, 0, 590), 10)
	planks(Vector3.new(1076.2, 0, -400), Vector3.new(1428, 0, -400), 10) -- spur out to the pier

	-- Along the boardwalk's east side: benches + bins, alternating with neon lamps (4 real lights)
	local slot, lampLights = 0, 0
	for z = -1860, 570, 70 do
		slot += 1
		if slot % 2 == 1 then
			if open(1083, z, 4) then
				bench(fWalk, 1083, z, -Vector3.xAxis)
				bin(fWalk, 1083, z + 5)
				claim(1083, z, 6)
			end
		elseif open(1081, z, 2) then
			local lit = slot % 6 == 0 and lampLights < 4
			if lit then
				lampLights += 1
			end
			lamp(fWalk, 1081, 0, z, 10, slot % 4 == 0 and N.Pink or N.Cyan, lit)
			claim(1081, z, 3)
		end
	end

	-- Palms: a row each side of the boardwalk, a sparse row near the water, and clumps on the sand.
	-- (Part palms cost ~10 parts each, so space them out if the PalmTree mesh is missing.)
	local gap = palmMesh and 50 or 120
	for z = -1880, 580, gap do
		if open(1050, z, 4) then
			palm(fSand, 1050, z, rng:NextNumber(1.3, 1.8))
			claim(1050, z, 3)
		end
		local z2 = z + gap / 2
		if z2 < 590 and open(1097, z2, 4) then
			palm(fSand, 1097, z2, rng:NextNumber(1.5, 2.2))
			claim(1097, z2, 3)
		end
	end
	for z = -1880, 580, gap * 2.8 do
		local zz = z + rng:NextNumber(-20, 20)
		if open(1470, zz, 4) then
			palm(fSand, 1470, zz, rng:NextNumber(1.6, 2.2))
			claim(1470, zz, 3)
		end
	end
	for _ = 1, palmMesh and 16 or 5 do
		local x, z = rng:NextNumber(1160, 1410), rng:NextNumber(-1950, 560)
		for _ = 1, rng:NextInteger(2, 3) do
			local px, pz = x + rng:NextNumber(-10, 10), z + rng:NextNumber(-10, 10)
			if open(px, pz, 5) then
				palm(fSand, px, pz, rng:NextNumber(1.4, 2.2))
				claim(px, pz, 4)
			end
		end
	end

	-- Umbrella clusters: loungers, towels or a beach ball under each umbrella
	for z = -1960, 570, 48 do
		for _, cx in ipairs({ 1170, 1225, 1280, 1335, 1390 }) do
			local x, zz = cx + rng:NextNumber(-10, 10), z + rng:NextNumber(-12, 12)
			if rng:NextNumber() < 0.22 and open(x, zz, 9) then
				claim(x, zz, 8)
				ArtKit.Umbrella(fSand, Vector3.new(x, 0, zz), ArtKit.PickNeon())
				local kind = rng:NextNumber()
				if kind < 0.5 then
					for _, dz in ipairs({ -2.2, 2.2 }) do -- heads west, feet toward the sea
						local p = Vector3.new(x + 1, -0.9, zz + dz)
						ArtKit.Lounger(fSand, CFrame.lookAt(p, p + Vector3.xAxis), ArtKit.Pick(C.Pastels))
					end
				elseif kind < 0.8 then
					for _, dz in ipairs({ -2.5, 2.5 }) do
						deco(fSand, Vector3.new(7, 0.12, 3.4), CFrame.new(x + 2, 0.06, zz + dz) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), ArtKit.Pick(C.Pastels), M.Fabric)
					end
				else
					local p = Vector3.new(x + 1, -0.9, zz + 2.2)
					ArtKit.Lounger(fSand, CFrame.lookAt(p, p + Vector3.xAxis), C.White)
					ball(fSand, Vector3.new(x + 4, 1.1, zz - 4), 2.2, ArtKit.PickNeon(), nil, { CanCollide = false, Name = "BeachBall" })
				end
			end
		end
	end

	-- Lighthouse Key ------------------------------------------------------------------------------------
	-- Free ground: east of the drift pad (x 2310..2445) north and south of the KeyLoop road (z -1365..-1335),
	-- plus thin strips north/south of the pad. The pad itself (and 12 studs round it) stays clear.
	do
		local LX, LZ = 2380, -1294
		-- rock base (a few overlapping slabs, top y 4); kept 9+ studs off the KeyLoop road
		for _, r in ipairs({ { 0, 0, 64, 54, 10 }, { -8, 8, 44, 40, -14 }, { 10, -4, 40, 46, 27 } }) do
			part(fKey, Vector3.new(r[3], 8, r[4]), CFrame.new(LX + r[1], 0, LZ + r[2]) * CFrame.Angles(0, math.rad(r[5]), 0), ROCK, M.Slate,
				{ Shadow = true, Name = "RockBase" })
		end
		local lcf = CFrame.lookAt(Vector3.new(LX, 4, LZ), Vector3.new(LX - 1, 4, LZ))
		local lh = asset(fKey, "Lighthouse", 2, lcf)
		local height = lh and (lh:IsA("BasePart") and lh.Size.Y or 90) or partLighthouse(fKey, lcf)
		light(lightAnchor(fKey, Vector3.new(LX, 4 + height * 0.86, LZ)), N.Yellow, 60, 3)
		hidePlaceholder("Lighthouse")
		hidePlaceholder("LighthouseLamp")
		rect(soft, LX - 40, LX + 40, LZ - 34, LZ + 36)
	end

	-- Key Drift Club: a little clubhouse whose neon sign faces the drift pad
	do
		local p = Vector3.new(2334, 0, -1450)
		local cf = CFrame.lookAt(p, p - Vector3.xAxis)
		local m = ArtKit.Model(fKey, "KeyDriftClub")
		part(m, Vector3.new(18, 9, 12), cf * CFrame.new(0, 4.5, 0), C.Pastels[4], nil, { Shadow = true, Name = "Body" })
		part(m, Vector3.new(12, 4, 0.4), cf * CFrame.new(0, 5, -6.1), C.Glass, M.Glass, { CanCollide = false, Name = "Window" })
		part(m, Vector3.new(20, 0.8, 14), cf * CFrame.new(0, 9.4, 0), C.White, nil, { Shadow = true, Name = "Roof" })
		neon(m, Vector3.new(20.2, 0.4, 0.4), cf * CFrame.new(0, 9, -7.1), N.Purple)
		light(ArtKit.Sign(m, cf * CFrame.new(0, 12.3, -5), "KEY DRIFT CLUB", N.Purple, 20, 5), N.Purple, 30, 1.5)
		for _, s in ipairs({ -1, 1 }) do
			part(m, Vector3.new(0.3, 12, 0.3), cf * CFrame.new(s * 11, 6, -5), C.White, nil, { CanCollide = false, Name = "FlagPole" })
			neon(m, Vector3.new(3, 2, 0.15), cf * CFrame.new(s * 12.65, 11, -5), s < 0 and N.Purple or N.Mint)
		end
		claim(2334, -1450, 14)
	end

	-- Spectator steps facing the pad, picnic tables, Gus on his day off, palms
	if Layout.IsFree(Vector3.new(2321, 0, -1230), 14) then
		for i = 0, 2 do
			part(fKey, Vector3.new(3, 1.2 * (i + 1), 26), CFrame.new(2318 + i * 3, 0.6 * (i + 1), -1230), i % 2 == 0 and C.White or C.Pastels[2], nil, { Name = "Bleacher" })
		end
		claim(2321, -1230, 15)
	end
	for _, t in ipairs({ { 2395, -1478, 0.2, N.Pink }, { 2420, -1425, -0.3 }, { 2362, -1200, 0.1, N.Cyan }, { 2414, -1214, 0.5 } }) do
		if open(t[1], t[2], 6) then
			picnic(fKey, Vector3.new(t[1], 0, t[2]), t[3], t[4])
			claim(t[1], t[2], 6)
		end
	end
	if open(2400, -1170, 7) then
		deco(fKey, Vector3.new(7, 0.12, 13), CFrame.new(2400, 0.06, -1170) * CFrame.Angles(0, math.rad(80), 0), C.Pastels[2], M.Fabric)
		local cf = CFrame.new(2400, 0.12, -1170) * CFrame.Angles(0, math.rad(80), 0)
		if not asset(fKey, "Gator", 3.5, cf) then
			partGator(fKey, cf, 3.5)
		end
		claim(2400, -1170, 8)
	end
	for _, p in ipairs({
		{ 2360, -1528 }, { 2425, -1535 }, { 2442, -1480 }, { 2376, -1395 }, { 2440, -1398 }, { 2320, -1300 },
		{ 2335, -1172 }, { 2380, -1162 }, { 2442, -1240 }, { 2442, -1300 },
		{ 2130, -1541 }, { 2200, -1541 }, { 2270, -1541 }, { 2130, -1159 }, { 2200, -1159 }, { 2270, -1159 },
	}) do
		if open(p[1], p[2], 4) then
			palm(fKey, p[1], p[2], rng:NextNumber(1.3, 1.9))
			claim(p[1], p[2], 3)
		end
	end

	-- Rocks along the shore, half in the water (skipped wherever they'd touch a road or the drift pad)
	local function shore(ax, az, bx, bz, nx, nz)
		local a, b = Vector3.new(ax, 0, az), Vector3.new(bx, 0, bz)
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		for d = 10, len - 10, 28 do
			local p = a:Lerp(b, d / len) + Vector3.new(nx, 0, nz) * 1.5 + dir * rng:NextNumber(-6, 6)
			for _, s in ipairs({ rng:NextNumber(6, 10), 4.5 }) do
				if Layout.IsFree(p, s * 0.8) then
					part(fKey, Vector3.new(s, s * 0.7, s * 1.2),
						CFrame.new(p.X, -0.8, p.Z) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4)), ROCK, M.Slate,
						{ Name = "Rock" })
					break
				end
			end
		end
	end
	shore(2100, -1550, 2450, -1550, 0, -1)
	shore(2100, -1150, 2450, -1150, 0, 1)
	shore(2450, -1550, 2450, -1150, 1, 0)
	shore(2100, -1550, 2100, -1150, -1, 0)

	local parts = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end

return Art
