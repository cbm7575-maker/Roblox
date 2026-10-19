-- PalmHillsDowntown (ModuleScript, ServerStorage.Tools.Art.PalmHillsDowntown). Studio-only art for
-- Palm Hills (suburbs) and Solana Heights (downtown).
--   Palm Hills: Palm Plaza strip mall by the citizen spawn, Palm Hills Park (playground + Gus statue),
--   Palm Hills Swim Club, extra houses behind/between ArtGen's lot houses, driveways, mailboxes,
--   backyard pools, picket fences and hedges, flamingo lawn ornaments, lawn palms.
--   Downtown: fountain plaza with the SOLANA HEIGHTS arch (Palm Blvd / Solana Ave corner), neon bus
--   stops, benches and palms in planters along the avenues, parody billboards, rooftop tower signs.
-- Every spot is checked four ways: district, an explicit gameplay keep-out list (pads are
-- CanQuery=false, so Layout.IsFree can't see them), Layout.IsFree (roads, 6+ studs), and existing art
-- (a physics box query on Workspace.City.Art plus a footprint list that also covers non-collidable
-- art such as awnings, and everything this module lays flat: pools, driveways, paving).

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local Art = {}

-- Gameplay spots to keep clear: circles { x, z, radius } and rectangles { x0, x1, z0, z1 }.
local KEEP_CIRCLES = {
	{ -470, -1450, 75 }, -- Glow Mart heist (building by another module)
	{ 580, -1150, 75 }, -- Fuel Stop heist
	{ 600, -1450, 22 }, -- ATM5
	{ 225, -1450, 32 }, -- Palm Hills citizen spawn
	{ -600, -1850, 40 }, -- Highway 1 Loop race start
	{ -500, -1862, 40 }, -- Northern Lights stunt ramp
	{ 1000, -1560, 40 }, -- Ocean Drive Sprint race start
	{ 975, -900, 45 }, -- Flamingo sign landmark
	{ -120, -380, 85 }, -- Sparkle & Co heist
	{ 230, 300, 95 }, -- Coastal Bank heist
	{ -480, 300, 24 }, -- ATM1
	{ -125, 40, 32 }, -- downtown citizen spawn
	{ -240, 40, 28 }, -- taxi stand
	{ -760, -600, 40 }, -- Downtown Dash race start
	{ 1060, -700, 24 }, -- ATM2 (beach side)
	{ 1120, -150, 70 }, -- Club Nova (beach side)
}
local KEEP_RECTS = {
	{ 160, 290, -1322, -1234 }, -- Palm Hills car pads and their pull-out to z -1250
	{ -222, -28, 88, 134 }, -- downtown car pads and their pull-out to z 150
	{ 465, 685, -505, -235 }, -- Police HQ, its lot and the cop pads
}

-- Palm Hills road grid: { centre line, half width } (half 0 = district edge, no road).
local PH_X = { { -900, 0 }, { -650, 16 }, { -300, 16 }, { 50, 22 }, { 400, 16 }, { 750, 16 }, { 1000, 30 } }
local PH_Z = { { -2000, 0 }, { -1850, 30 }, { -1650, 16 }, { -1250, 16 }, { -850, 0 } }
local HOUSE_FRONT = { 52, 116 } -- house front distance from the street centre line (52 = ArtGen's houses)

-- Downtown roads as { axis of the centre line, centre, half width, from, to }.
-- "x" = the road runs north-south at x = centre; "z" = it runs east-west at z = centre.
local DT_AVENUES = {
	{ "x", 50, 22, -850, 600 }, -- Solana Ave
	{ "z", -150, 22, -900, 1000 }, -- Palm Blvd
}
local DT_STREETS = {
	{ "z", -600, 16, -900, 1000 }, { "z", 150, 16, -900, 1000 }, { "z", 450, 16, -900, 1000 },
	{ "x", -650, 16, -850, 600 }, { "x", -300, 16, -850, 600 }, { "x", 400, 16, -850, 600 }, { "x", 750, 16, -850, 600 },
}
local DT_X = { { -650, 16 }, { -300, 16 }, { 50, 22 }, { 400, 16 }, { 750, 16 } }
local DT_Z = { { -600, 16 }, { -150, 22 }, { 150, 16 }, { 450, 16 } }

local POOL = Color3.fromRGB(70, 220, 232)
local HEDGE = Color3.fromRGB(60, 150, 80)
local PAVING = Color3.fromRGB(232, 224, 210)
local FLAMINGO = Color3.fromRGB(255, 122, 184)
local LAVENDER = Color3.fromRGB(212, 196, 255)
local PINK = Color3.fromRGB(255, 196, 218)

local SHOPS = { "SUNNY SIDE DONUTS", "PALMETTO PETS", "GLOW-UP NAILS", "SEASHELL SUDS" }
local BILLBOARD_ADS = {
	"SUNBURN INSURANCE\nBecause you WILL forget",
	"GATOR WRESTLING LESSONS\nFirst hug is free",
	"DJ COCO LIVE TONIGHT\non Flamingo FM",
	"Gus the Gator says:\nWEAR SUNSCREEN",
	"SPF 9000\nNow in NEON!",
	"SEAGULL-PROOF SANDWICHES",
	"TAN LINES R US",
	"BEACH BUM SURF SCHOOL\nWipeouts included",
}
local TOWER_NAMES = { "PALMETTO TOWER", "CORAL CAPITAL", "SEABREEZE SUITES", "FLAMINGO FM 88.8", "GUS TOWER", "AQUA VISTA", "MANGO CENTER" }

function Art.Build(folder, ArtKit, Layout)
	local C, N = ArtKit.Colors, ArtKit.Colors.Neon
	local NEONS = { N.Pink, N.Cyan, N.Yellow, N.Orange, N.Mint, N.Purple }
	local rng = Random.new(7031)
	local artRoot = folder.Parent
	local roadsFolder = artRoot.Parent:FindFirstChild("Roads")
	local assets = ServerStorage:FindFirstChild("ArtAssets")

	---------------------------------------------------------------------------------------------
	-- Budget, lights, small utilities

	local used, limit, lights = 0, 0, 0
	local MAX_LIGHTS = 18
	local stats = {}

	local function room(n)
		return used + n <= limit
	end
	local function add(inst) -- count the BaseParts an ArtKit helper just built
		if inst then
			if inst:IsA("BasePart") then
				used += 1
			end
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") then
					used += 1
				end
			end
		end
		return inst
	end
	local function P(parent, size, cf, color, mat, opts)
		used += 1
		return ArtKit.Part(parent, size, cf, color, mat, opts)
	end
	local function glow(parent, size, cf, color)
		used += 1
		return ArtKit.Neon(parent, size, cf, color)
	end
	local function sign(parent, cf, text, color, w, h)
		used += 3 -- panel + two neon strips
		return ArtKit.Sign(parent, cf, text, color, w, h)
	end
	local function light(part, color, range, brightness)
		if part and lights < MAX_LIGHTS and ArtKit.Light(part, color, range, brightness) then
			lights += 1
		end
	end
	local function sub(parent, name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		return f
	end
	local function pick(list)
		return list[rng:NextInteger(1, #list)]
	end
	local function shuffle(list)
		for i = #list, 2, -1 do
			local j = rng:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
		return list
	end
	local function asset(name)
		local a = assets and assets:FindFirstChild(name)
		return (a and a:IsA("BasePart")) and a or nil
	end
	local function cyl(len, dia) -- Size of a cylinder part (its axis is X)
		return Vector3.new(len, dia, dia)
	end
	local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder's axis up
	local function farFrom(list, p, dist)
		for _, q in ipairs(list) do
			if Vector2.new(q.X - p.X, q.Z - p.Z).Magnitude < dist then
				return false
			end
		end
		return true
	end

	---------------------------------------------------------------------------------------------
	-- Footprints: a grid-bucketed list of claimed ground rectangles (x0, x1, z0, z1)

	local function footprint(cf, sx, sz) -- world AABB of an sx-by-sz rectangle centred on cf
		local r, l, p = cf.RightVector, cf.LookVector, cf.Position
		local ex = math.abs(r.X) * sx / 2 + math.abs(l.X) * sz / 2
		local ez = math.abs(r.Z) * sx / 2 + math.abs(l.Z) * sz / 2
		return p.X - ex, p.X + ex, p.Z - ez, p.Z + ez
	end

	local CELL = 64
	local grid = {}
	local function claim(x0, x1, z0, z1)
		local rect = { x0, x1, z0, z1 }
		for i = math.floor(x0 / CELL), math.floor(x1 / CELL) do
			for j = math.floor(z0 / CELL), math.floor(z1 / CELL) do
				local k = i * 65536 + j
				grid[k] = grid[k] or {}
				table.insert(grid[k], rect)
			end
		end
	end
	local function claimed(x0, x1, z0, z1)
		for i = math.floor(x0 / CELL), math.floor(x1 / CELL) do
			for j = math.floor(z0 / CELL), math.floor(z1 / CELL) do
				local list = grid[i * 65536 + j]
				if list then
					for _, r in ipairs(list) do
						if x0 < r[2] and x1 > r[1] and z0 < r[4] and z1 > r[3] then
							return true
						end
					end
				end
			end
		end
		return false
	end
	local function claimCF(cf, sx, sz)
		local x0, x1, z0, z1 = footprint(cf, sx, sz)
		claim(x0, x1, z0, z1)
	end

	local function isPalm(p)
		return p.Name == "PalmTree" or (p.Parent ~= nil and p.Parent.Name == "Palm")
	end

	-- Claim everything already standing near the ground in (or near) our two districts, including
	-- non-collidable parts (awnings, doors, windows) that the physics query below cannot see.
	for _, d in ipairs(artRoot:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Line" and not d:IsDescendantOf(folder) then
			local cf, s = d.CFrame, d.Size
			local p = cf.Position
			if p.X > -1000 and p.X < 1100 and p.Z > -2100 and p.Z < 700 then
				if isPalm(d) then
					if d.Name ~= "Frond" then -- trunk only: crowns sit high above our props
						claim(p.X - 2.5, p.X + 2.5, p.Z - 2.5, p.Z + 2.5)
					end
				else
					local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
					local ey = math.abs(r.Y) * s.X / 2 + math.abs(u.Y) * s.Y / 2 + math.abs(l.Y) * s.Z / 2
					if p.Y - ey < 20 then
						local ex = math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2
						local ez = math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
						claim(p.X - ex, p.X + ex, p.Z - ez, p.Z + ez)
					end
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------
	-- Placement checks

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { artRoot }

	-- Any collidable art (other than palms) inside this box?
	local function physBlocked(x0, x1, z0, z1, y0, y1)
		y0, y1 = y0 or 0.4, y1 or 14
		local box = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
		for _, hit in ipairs(Workspace:GetPartBoundsInBox(box, Vector3.new(x1 - x0, y1 - y0, z1 - z0), overlap)) do
			if not isPalm(hit) then
				return true
			end
		end
		return false
	end

	local function inKeepOut(x0, x1, z0, z1)
		for _, c in ipairs(KEEP_CIRCLES) do
			local dx = math.clamp(c[1], x0, x1) - c[1]
			local dz = math.clamp(c[2], z0, z1) - c[2]
			if dx * dx + dz * dz < c[3] * c[3] then
				return true
			end
		end
		for _, r in ipairs(KEEP_RECTS) do
			if x0 < r[2] and x1 > r[1] and z0 < r[4] and z1 > r[3] then
				return true
			end
		end
		return false
	end

	-- Layout.IsFree tests a square, so cover the rectangle with squares along its long side.
	local function clearOfRoads(x0, x1, z0, z1, margin)
		local w, d = x1 - x0, z1 - z0
		local short = math.min(w, d)
		local r = short / 2 + margin
		local span = math.max(w, d) - short
		local n = math.ceil(span / (2 * r)) + 1
		for i = 0, n - 1 do
			local t = n == 1 and 0 or i / (n - 1)
			local cx, cz
			if w >= d then
				cx, cz = x0 + short / 2 + span * t, (z0 + z1) / 2
			else
				cx, cz = (x0 + x1) / 2, z0 + short / 2 + span * t
			end
			if not Layout.IsFree(Vector3.new(cx, 0, cz), r) then
				return false
			end
		end
		return true
	end

	local function inDistrict(x0, x1, z0, z1, name)
		return Layout.District(x0, z0) == name and Layout.District(x1, z0) == name
			and Layout.District(x0, z1) == name and Layout.District(x1, z1) == name
	end

	-- pad: extra clearance from other art; margin: clearance from roads/gameplay (default 6);
	-- y1: height of the physics check box (default 14).
	local function spotFree(x0, x1, z0, z1, district, pad, margin, y1)
		pad = pad or 0
		if district and not inDistrict(x0, x1, z0, z1, district) then
			return false
		end
		if inKeepOut(x0, x1, z0, z1) or claimed(x0 - pad, x1 + pad, z0 - pad, z1 + pad) then
			return false
		end
		if physBlocked(x0 - pad, x1 + pad, z0 - pad, z1 + pad, 0.4, y1) then
			return false
		end
		return clearOfRoads(x0, x1, z0, z1, margin or 6)
	end
	local function spotFreeCF(cf, sx, sz, district, pad, margin, y1)
		local x0, x1, z0, z1 = footprint(cf, sx, sz)
		return spotFree(x0, x1, z0, z1, district, pad, margin, y1), x0, x1, z0, z1
	end

	---------------------------------------------------------------------------------------------
	-- Small props

	local function palm(parent, pos, scale)
		return add(ArtKit.Palm(parent, pos, scale, rng:NextNumber(0, math.pi * 2)))
	end

	-- ArtKit's bench and lounger have no legs; give them a support block so nothing floats.
	local function bench(parent, cf)
		local m = add(ArtKit.Bench(parent, cf))
		P(m, Vector3.new(5, 1.4, 1.2), cf * CFrame.new(0, 0.7, 0), C.DarkWood, Enum.Material.WoodPlanks, { Name = "Support" })
		return m
	end
	local function lounger(parent, cf, color)
		local m = add(ArtKit.Lounger(parent, cf, color))
		P(m, Vector3.new(2.4, 1, 5.6), cf * CFrame.new(0, 0.5, 0), C.White, nil, { Name = "Support" })
		return m
	end

	-- Gus the Gator: the generated mesh if present, else a little part gator. cf = ground CFrame.
	local function gus(parent, cf, scale, pedestal)
		local top = cf
		if pedestal then
			P(parent, Vector3.new(7, 2, 11), cf * CFrame.new(0, 1, 0), C.White, Enum.Material.Marble, { Name = "Pedestal" })
			top = cf * CFrame.new(0, 2, 0)
		end
		local t = asset("Gator")
		if t then
			local g = t:Clone()
			g.Name = "GusTheGator"
			g.Anchored, g.CanTouch, g.CastShadow = true, false, false
			g.Size = t.Size * scale
			g.CFrame = top * CFrame.new(0, g.Size.Y / 2, 0)
			g.Parent = parent
			used += 1
			return
		end
		local k, green = scale / 3.5, Color3.fromRGB(80, 190, 110)
		P(parent, Vector3.new(3, 2, 6) * k, top * CFrame.new(0, k, 0.5 * k), green, nil, { Name = "GusBody" })
		P(parent, Vector3.new(2.6, 1.6, 3) * k, top * CFrame.new(0, 1.2 * k, -3.5 * k), green, nil, { Name = "GusHead" })
		for _, x in ipairs({ -0.7, 0.7 }) do
			P(parent, Vector3.new(0.8, 0.8, 0.8) * k, top * CFrame.new(x * k, 2.2 * k, -3 * k), C.White, nil,
				{ Shape = Enum.PartType.Ball, CanCollide = false, Name = "GusEye" })
		end
	end

	local function flamingo(parent, pos, yaw)
		local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		local opts = { CanCollide = false, Name = "Flamingo" }
		P(parent, Vector3.new(0.25, 2.6, 0.25), base * CFrame.new(0, 1.3, 0), FLAMINGO, nil, opts)
		P(parent, Vector3.new(1.3, 1.1, 2.3), base * CFrame.new(0, 3.1, 0.2) * CFrame.Angles(math.rad(-12), 0, 0), FLAMINGO, nil, opts)
		P(parent, Vector3.new(0.35, 2.2, 0.35), base * CFrame.new(0, 4.4, -0.8) * CFrame.Angles(math.rad(-12), 0, 0), FLAMINGO, nil, opts)
		P(parent, Vector3.new(0.7, 0.7, 1.3), base * CFrame.new(0, 5.5, -1.1), FLAMINGO, nil, opts)
	end

	---------------------------------------------------------------------------------------------
	-- Palm Hills landmarks

	-- Palm Plaza: four shops facing south toward the citizen spawn (225, -1450), pylon sign by Solana Ave.
	local function buildStripMall(parent)
		for _, frontZ in ipairs({ -1494, -1530, -1566 }) do
			if spotFree(84, 346, frontZ - 28, frontZ + 11, "PalmHills", 2) then
				local m = ArtKit.Model(parent, "PalmPlaza")
				local H = 17
				local walls = { PINK, Color3.fromRGB(176, 236, 226), Color3.fromRGB(255, 242, 196), LAVENDER }
				local trims = { N.Pink, N.Cyan, N.Orange, N.Purple }
				for i, name in ipairs(SHOPS) do
					local sx = 128 + (i - 1) * 58
					P(m, Vector3.new(56, H, 26), CFrame.new(sx, H / 2, frontZ - 13), walls[i], nil, { Shadow = true, Name = "Shop" })
					P(m, Vector3.new(40, 8, 0.4), CFrame.new(sx, 4.5, frontZ + 0.2), C.Glass, Enum.Material.Glass,
						{ CanCollide = false, Name = "Storefront", Reflectance = 0.1 })
					P(m, Vector3.new(46, 0.6, 5), CFrame.new(sx, 10, frontZ + 2.5), trims[i], nil, { CanCollide = false, Name = "Awning" })
					local s = sign(m, CFrame.lookAt(Vector3.new(sx, 13.6, frontZ + 0.35), Vector3.new(sx, 13.6, frontZ + 10)), name, trims[i], 44, 4.4)
					if i == 1 or i == 3 then
						light(s, trims[i], 26, 1.2)
					end
				end
				glow(m, Vector3.new(234, 0.6, 0.6), CFrame.new(215, H - 0.6, frontZ + 0.3), N.Cyan)
				P(m, Vector3.new(240, 0.2, 10), CFrame.new(215, 0.03, frontZ + 5), PAVING, Enum.Material.Concrete, { CanCollide = false, Name = "Sidewalk" })
				-- Giant donut on the donut shop roof (axis along z, facing the spawn)
				local dcf = CFrame.new(128, H + 4.8, frontZ - 8) * CFrame.Angles(0, math.pi / 2, 0)
				local cylOpts = { Shape = Enum.PartType.Cylinder, Name = "Donut" }
				P(m, cyl(2, 9.6), dcf * CFrame.new(0.4, 0, 0), Color3.fromRGB(222, 170, 110), nil, cylOpts)
				P(m, cyl(1.4, 8.4), dcf * CFrame.new(-0.5, 0, 0), N.Pink, nil, cylOpts)
				P(m, cyl(1.6, 3.2), dcf * CFrame.new(-0.6, 0, 0), Color3.fromRGB(150, 100, 70), nil, cylOpts)
				-- Pylon sign facing Solana Ave
				P(m, Vector3.new(2, 22, 2), CFrame.new(90, 11, frontZ + 4), C.White, nil, { Name = "Pylon" })
				sign(m, CFrame.lookAt(Vector3.new(90, 24, frontZ + 4), Vector3.new(80, 24, frontZ + 4)), "PALM PLAZA", N.Pink, 16, 6)
				claim(84, 346, frontZ - 28, frontZ + 11)
				stats.mall = string.format("(215, %d)", frontZ - 13)
				return true
			end
		end
		return false
	end

	-- Palm Hills Park: cross paths, playground (slide, swings), sandbox, Gus statue, picnic tables.
	local function buildPark(parent)
		for _, s in ipairs({ { -125, -1450 }, { -125, -1030 }, { -475, -1030 }, { 225, -1030 }, { -775, -1450 }, { 875, -1450 } }) do
			local cx, cz = s[1], s[2]
			if spotFree(cx - 70, cx + 70, cz - 65, cz + 65, "PalmHills", 4) then
				local m = ArtKit.Model(parent, "PalmHillsPark")
				local flat = { CanCollide = false, Name = "Path" }
				P(m, Vector3.new(140, 0.2, 6), CFrame.new(cx, 0.03, cz), PAVING, Enum.Material.Concrete, flat)
				P(m, Vector3.new(6, 0.2, 130), CFrame.new(cx, 0.04, cz), PAVING, Enum.Material.Concrete, flat)
				-- Playground (north-east quarter)
				local qx, qz = cx + 36, cz - 33
				P(m, Vector3.new(46, 0.2, 36), CFrame.new(qx, 0.04, qz), LAVENDER, nil, { CanCollide = false, Name = "SoftMat" })
				local sx, sz = qx - 12, qz - 6
				for _, o in ipairs({ { -2.7, -2.7 }, { 2.7, -2.7 }, { -2.7, 2.7 }, { 2.7, 2.7 } }) do
					P(m, Vector3.new(0.6, 7, 0.6), CFrame.new(sx + o[1], 3.5, sz + o[2]), C.White, nil, { Name = "SlideLeg" })
				end
				P(m, Vector3.new(6.4, 0.6, 6.4), CFrame.new(sx, 7.3, sz), N.Cyan, nil, { Name = "SlidePlatform" })
				P(m, Vector3.new(2, 8, 2), CFrame.new(sx, 4, sz - 4.2), C.White, nil, { Class = "TrussPart", Name = "SlideLadder" })
				-- 14-stud chute tilted 30 degrees: high end at the platform edge, low end on the mat
				P(m, Vector3.new(3, 0.4, 14), CFrame.new(sx, 3.8, sz + 9.26) * CFrame.Angles(math.rad(30), 0, 0), N.Yellow, nil, { Name = "Slide" })
				local wx, wz = qx + 10, qz - 2
				for _, o in ipairs({ -7, 7 }) do
					P(m, Vector3.new(0.8, 9, 0.8), CFrame.new(wx + o, 4.5, wz), PINK, nil, { Name = "SwingPost" })
				end
				P(m, cyl(15, 0.7), CFrame.new(wx, 9.2, wz), C.White, nil, { Shape = Enum.PartType.Cylinder, Name = "SwingBar" })
				for _, o in ipairs({ -3.2, 3.2 }) do
					P(m, Vector3.new(2.2, 0.3, 1.2), CFrame.new(wx + o, 2.4, wz), N.Orange, nil, { CanCollide = false, Name = "SwingSeat" })
					for _, r in ipairs({ -0.9, 0.9 }) do
						P(m, Vector3.new(0.15, 6.6, 0.15), CFrame.new(wx + o + r, 5.8, wz), C.Steel, nil, { CanCollide = false, Name = "SwingChain" })
					end
				end
				-- Sandbox and Gus statue (north-west quarter)
				local nx, nz = cx - 36, cz - 33
				P(m, Vector3.new(16, 0.6, 16), CFrame.new(nx - 8, 0.3, nz), C.Wood, Enum.Material.WoodPlanks, { CanCollide = false, Name = "SandboxRim" })
				P(m, Vector3.new(14.4, 0.6, 14.4), CFrame.new(nx - 8, 0.4, nz), C.Sand, Enum.Material.Sand, { CanCollide = false, Name = "Sand" })
				gus(m, CFrame.new(nx + 12, 0, nz) * CFrame.Angles(0, math.pi, 0), 3.5, true)
				-- Picnic tables with umbrellas (south-east quarter)
				for _, o in ipairs({ -10, 10 }) do
					local tx, tz = cx + 36 + o, cz + 33
					P(m, Vector3.new(3.5, 0.4, 8), CFrame.new(tx, 2.8, tz), C.Wood, Enum.Material.WoodPlanks, { Name = "TableTop" })
					P(m, Vector3.new(1, 2.6, 2), CFrame.new(tx, 1.3, tz), C.DarkWood, Enum.Material.WoodPlanks, { Name = "TableLeg" })
					for _, so in ipairs({ -2.6, 2.6 }) do
						P(m, Vector3.new(1.2, 1.6, 8), CFrame.new(tx + so, 0.8, tz), C.Wood, Enum.Material.WoodPlanks, { Name = "TableSeat" })
					end
					add(ArtKit.Umbrella(m, Vector3.new(tx, 0, tz), o < 0 and N.Pink or N.Cyan))
				end
				-- Benches by the east-west path, palms around the edge
				for _, o in ipairs({ -25, 25 }) do
					local p = Vector3.new(cx + o, 0, cz + 6.5)
					bench(m, CFrame.lookAt(p, p - Vector3.new(0, 0, 1)))
				end
				for _, o in ipairs({ { -60, -56 }, { 60, -56 }, { -60, 56 }, { 60, 56 }, { -45, 38 }, { -20, 50 } }) do
					palm(m, Vector3.new(cx + o[1], 0, cz + o[2]), rng:NextNumber(1.3, 1.7))
				end
				-- Sign on the side facing the nearest east-west street
				local nearest, best = -1650, math.huge
				for _, zr in ipairs({ -1850, -1650, -1250 }) do
					if math.abs(zr - cz) < best then
						nearest, best = zr, math.abs(zr - cz)
					end
				end
				local dir = nearest > cz and 1 or -1
				local scf = CFrame.lookAt(Vector3.new(cx + 20, 0, cz + dir * 60), Vector3.new(cx + 20, 0, cz + dir * 70))
				for _, o in ipairs({ -8, 8 }) do
					P(m, Vector3.new(0.8, 6.5, 0.8), scf * CFrame.new(o, 3.25, 0), C.White, nil, { Name = "SignPost" })
				end
				light(sign(m, scf * CFrame.new(0, 8.8, 0), "PALM HILLS PARK", N.Mint, 20, 5), N.Mint, 24, 1)
				claim(cx - 70, cx + 70, cz - 65, cz + 65)
				stats.park = string.format("(%d, %d)", cx, cz)
				return true
			end
		end
		return false
	end

	-- Palm Hills Swim Club: clubhouse, big pool, loungers, lifeguard tower; faces the z = -1250 street.
	local function buildSwimClub(parent)
		for _, cx in ipairs({ -125, 225, -475, -775, 875 }) do
			-- Looking north (-Z) keeps local axes equal to world axes; local -z is the street side.
			local base = CFrame.lookAt(Vector3.new(cx, 0, -1181), Vector3.new(cx, 0, -1191))
			if spotFreeCF(base * CFrame.new(0, 0, 3.5), 134, 97, "PalmHills", 3) then
				local m = ArtKit.Model(parent, "PalmHillsSwimClub")
				local function at(x, y, z)
					return base * CFrame.new(x, y, z)
				end
				P(m, Vector3.new(130, 0.24, 90), at(0, 0.02, 5), PAVING, Enum.Material.Concrete, { CanCollide = false, Name = "Deck" })
				add(ArtKit.Deco(m, at(-45, 0, -25), 36, 16, 24, { Color = Color3.fromRGB(176, 236, 226), Trim = N.Cyan, Tiers = 1, Name = "Clubhouse" }))
				light(sign(m, at(-45, 19.5, -36.5), "PALM HILLS SWIM CLUB", N.Pink, 34, 7), N.Pink, 30, 1.2)
				P(m, Vector3.new(60, 0.4, 30), at(18, 0.2, 5), C.White, nil, { CanCollide = false, Name = "PoolRim" })
				local water = P(m, Vector3.new(56, 0.4, 26), at(18, 0.26, 5), POOL, nil, { CanCollide = false, Name = "Pool", Reflectance = 0.15 })
				light(water, N.Cyan, 30, 1)
				P(m, Vector3.new(3, 1.4, 3), at(50, 0.7, 5), C.White, nil, { Name = "BoardBase" })
				P(m, Vector3.new(10, 0.4, 2.6), at(45.5, 1.6, 5), N.Mint, nil, { Name = "DivingBoard" })
				for i = 0, 4 do
					lounger(m, at(-4 + i * 12, 0, 27), pick(C.Pastels))
				end
				for _, x in ipairs({ 2, 26, 50 }) do
					add(ArtKit.Umbrella(m, at(x, 0, 34).Position, pick({ N.Pink, N.Cyan, N.Yellow })))
				end
				add(ArtKit.LifeguardTower(m, at(57, 0, -22)))
				-- White fence around the deck with a gate beside the clubhouse
				for _, f in ipairs({ { 0, 50, 130, 0.5 }, { -65, 5, 0.5, 90 }, { 65, 5, 0.5, 90 }, { -13, -40, 24, 0.5 }, { 38, -40, 54, 0.5 } }) do
					P(m, Vector3.new(f[3], 3.2, f[4]), at(f[1], 1.6, f[2]), C.White, Enum.Material.WoodPlanks, { Name = "Fence" })
				end
				for _, p in ipairs({ { -58, 44 }, { 58, 44 }, { -58, 2 }, { 24, -34 } }) do
					palm(m, at(p[1], 0, p[2]).Position, rng:NextNumber(1.2, 1.5))
				end
				claimCF(base * CFrame.new(0, 0, 3.5), 134, 97)
				stats.club = string.format("(%d, -1177)", cx)
				return true
			end
		end
		return false
	end

	---------------------------------------------------------------------------------------------
	-- Palm Hills houses and yards

	local houses = {} -- { cf = ground CFrame (front = LookVector), w, d, drive = {...} }

	local function addExistingHouses()
		local b = artRoot:FindFirstChild("Buildings")
		if not b then
			return
		end
		for _, m in ipairs(b:GetChildren()) do
			local body = m:IsA("Model") and m.Name == "House" and m:FindFirstChild("Body")
			if body and Layout.District(body.Position.X, body.Position.Z) == "PalmHills" then
				table.insert(houses, { cf = body.CFrame * CFrame.new(0, -body.Size.Y / 2, 0), w = body.Size.X, d = body.Size.Z })
			end
		end
	end

	-- Candidate house slots: rows along every street side of every block, at ArtGen's setback
	-- (front row) and one lot further back (second row), all facing their street.
	local function houseSlots()
		local slots = {}
		local function row(lineIsX, line, dir, from, to, frontDist)
			local t = from
			for _ = 1, 60 do
				local w, d = rng:NextInteger(26, 40), rng:NextInteger(26, 32)
				if t + w > to then
					break
				end
				local along, off = t + w / 2, line + dir * (frontDist + d / 2)
				local pos = lineIsX and Vector3.new(off, 0, along) or Vector3.new(along, 0, off)
				local look = lineIsX and Vector3.new(-dir, 0, 0) or Vector3.new(0, 0, -dir)
				table.insert(slots, { cf = CFrame.lookAt(pos, pos + look), w = w, d = d })
				t += w + rng:NextInteger(14, 22)
			end
		end
		for i = 1, #PH_X - 1 do
			for j = 1, #PH_Z - 1 do
				local xa, xb, za, zb = PH_X[i], PH_X[i + 1], PH_Z[j], PH_Z[j + 1]
				local streetsHere = j > 1 -- the north-south streets stop at Highway 1
				local x0 = xa[1] + (streetsHere and xa[2] or 0) + 10
				local x1 = xb[1] - (streetsHere and xb[2] or 0) - 10
				local z0, z1 = za[1] + za[2] + 10, zb[1] - zb[2] - 10
				for _, f in ipairs(HOUSE_FRONT) do
					if za[2] > 0 then
						row(false, za[1], 1, x0, x1, f)
					end
					if zb[2] > 0 then
						row(false, zb[1], -1, x0, x1, f)
					end
					if streetsHere and xa[2] > 0 then
						row(true, xa[1], 1, z0, z1, f)
					end
					if streetsHere and xb[2] > 0 then
						row(true, xb[1], -1, z0, z1, f)
					end
				end
			end
		end
		return shuffle(slots)
	end

	local function placeHouses(parent, cap)
		local n = 0
		for _, s in ipairs(houseSlots()) do
			if n >= cap or not room(8) then
				break
			end
			if spotFreeCF(s.cf, s.w, s.d, "PalmHills", 6) then
				ArtKit.House(parent, s.cf, s.w, s.d, pick(C.Pastels))
				used += 6
				claimCF(s.cf, s.w + 1, s.d + 1)
				table.insert(houses, { cf = s.cf, w = s.w, d = s.d })
				n += 1
			end
		end
		return n
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { roadsFolder }

	-- Concrete strip from the garage (house-local x = +0.2w) straight out to the street edge.
	local function placeDriveways(parent, cap)
		local n = 0
		for _, h in ipairs(houses) do
			if n >= cap or not room(1) then
				break
			end
			local look = h.cf.LookVector
			local front = (h.cf * CFrame.new(h.w * 0.2, 0, -h.d / 2)).Position
			-- Road slabs span y -0.9..0.1, so a ray just below the grass hits their side face.
			local hit = roadsFolder and Workspace:Raycast(Vector3.new(front.X, -0.4, front.Z), look * 110, rayParams)
			if hit and hit.Distance > 8 then
				local len, dw = hit.Distance, h.w * 0.35 + 2
				local mid = front + look * (len / 2)
				local cf = CFrame.lookAt(Vector3.new(mid.X, 0.02, mid.Z), Vector3.new(mid.X, 0.02, mid.Z) + look)
				local x0, x1, z0, z1 = footprint(cf * CFrame.new(0, 0, -0.6), dw, len - 1.2) -- skip the stud at the garage door
				if not inKeepOut(x0, x1, z0, z1) and not claimed(x0, x1, z0, z1) and not physBlocked(x0, x1, z0, z1, 0.4, 8) then
					P(parent, Vector3.new(dw, 0.2, len), cf, C.Concrete, Enum.Material.Concrete, { CanCollide = false, Name = "Driveway" }) -- top y 0.12
					claim(x0, x1, z0, z1)
					h.drive = { len = len, dw = dw, front = front, look = look }
					n += 1
				end
			end
		end
		return n
	end

	local function placeMailboxes(parent, cap)
		local n = 0
		for _, h in ipairs(houses) do
			if n >= cap or not room(2) then
				break
			end
			local dv = h.drive
			if dv and dv.len >= 16 then
				local pos = dv.front + dv.look * (dv.len - 7) + h.cf.RightVector * (dv.dw / 2 + 1.5)
				local mcf = CFrame.lookAt(pos, pos + dv.look)
				local x0, x1, z0, z1 = footprint(mcf, 2, 2.6)
				if not claimed(x0, x1, z0, z1) and not inKeepOut(x0, x1, z0, z1) and not physBlocked(x0, x1, z0, z1) and Layout.IsFree(pos, 6) then
					P(parent, Vector3.new(0.35, 3.4, 0.35), mcf * CFrame.new(0, 1.7, 0), C.White, nil, { Name = "MailPost" })
					P(parent, Vector3.new(1.3, 1.3, 2.2), mcf * CFrame.new(0, 3.9, 0), pick({ N.Pink, N.Cyan, N.Mint, N.Yellow }), nil,
						{ CanCollide = false, Name = "Mailbox" })
					claim(x0, x1, z0, z1)
					n += 1
				end
			end
		end
		return n
	end

	local function placePools(parent, cap)
		local n, loungers = 0, 0
		for _, h in ipairs(houses) do
			if n >= cap or not room(5) then
				break
			end
			if rng:NextNumber() < 0.45 then
				local pw, pd = rng:NextInteger(14, 20), rng:NextInteger(9, 12)
				local pcf = h.cf * CFrame.new(rng:NextNumber(-0.15, 0.15) * h.w, 0, h.d / 2 + 6 + pd / 2) -- local +z = backyard
				local ok, x0, x1, z0, z1 = spotFreeCF(pcf, pw + 2, pd + 2, "PalmHills", 2)
				if ok then
					P(parent, Vector3.new(pw + 2, 0.4, pd + 2), pcf * CFrame.new(0, 0.2, 0), C.White, nil, { CanCollide = false, Name = "PoolRim" })
					P(parent, Vector3.new(pw, 0.4, pd), pcf * CFrame.new(0, 0.26, 0), POOL, nil, { CanCollide = false, Name = "Pool", Reflectance = 0.15 })
					claim(x0, x1, z0, z1)
					n += 1
					if loungers < 6 and rng:NextNumber() < 0.5 then
						local lcf = pcf * CFrame.new(pw / 2 + 4, 0, 0)
						local ok2, a0, a1, b0, b1 = spotFreeCF(lcf, 3.4, 9, "PalmHills", 1)
						if ok2 then
							lounger(parent, lcf, pick(C.Pastels))
							claim(a0, a1, b0, b1)
							loungers += 1
						end
					end
				end
			end
		end
		return n
	end

	-- Back picket fence behind the yard and a hedge down one side of the lot.
	local function placeYardEdges(parent, cap)
		local n = 0
		for _, h in ipairs(houses) do
			if n >= cap or not room(2) then
				break
			end
			if rng:NextNumber() < 0.55 then
				local did = false
				local fcf = h.cf * CFrame.new(0, 0, h.d / 2 + 24)
				local ok, x0, x1, z0, z1 = spotFreeCF(fcf, h.w + 12, 0.5, "PalmHills", 0)
				if ok then
					P(parent, Vector3.new(h.w + 12, 3.2, 0.5), fcf * CFrame.new(0, 1.6, 0), C.White, Enum.Material.WoodPlanks, { Name = "PicketFence" })
					claim(x0, x1, z0, z1)
					did = true
				end
				local side = rng:NextNumber() < 0.5 and -1 or 1
				-- runs from 4 studs behind the front wall to just short of the back fence
				local hcf = h.cf * CFrame.new(side * (h.w / 2 + 5), 0, 13.75)
				local ok2, a0, a1, b0, b1 = spotFreeCF(hcf, 2.4, h.d + 19.5, "PalmHills", 0)
				if ok2 then
					P(parent, Vector3.new(2.4, 3, h.d + 19.5), hcf * CFrame.new(0, 1.5, 0), HEDGE, Enum.Material.Grass, { Name = "Hedge" })
					claim(a0, a1, b0, b1)
					did = true
				end
				if did then
					n += 1
				end
			end
		end
		return n
	end

	-- A pair of pink flamingos on the front lawn, door side.
	local function placeFlamingos(parent, cap)
		local n = 0
		for _, h in ipairs(houses) do
			if n >= cap or not room(8) then
				break
			end
			if rng:NextNumber() < 0.15 then
				local p0 = h.cf * CFrame.new(-h.w / 2 + 3, 0, -h.d / 2 - 6)
				local x0, x1, z0, z1 = footprint(p0 * CFrame.new(1.2, 0, 0.4), 5, 3)
				if not claimed(x0, x1, z0, z1) and not inKeepOut(x0, x1, z0, z1) and not physBlocked(x0, x1, z0, z1) and Layout.IsFree(p0.Position, 8) then
					for k = 0, 1 do
						flamingo(parent, (p0 * CFrame.new(k * 2.4, 0, k * 0.8)).Position, rng:NextNumber(0, math.pi * 2))
					end
					claim(x0, x1, z0, z1)
					n += 1
				end
			end
		end
		return n
	end

	-- Scatter palms over whatever open lawn is left.
	local function placeLawnPalms(parent, cap)
		local pts = {}
		for x = -870, 970, 55 do
			for z = -1980, -870, 55 do
				table.insert(pts, Vector3.new(x + rng:NextNumber(-12, 12), 0, z + rng:NextNumber(-12, 12)))
			end
		end
		local n = 0
		for _, p in ipairs(shuffle(pts)) do
			if n >= cap or not room(1) then
				break
			end
			if spotFree(p.X - 6, p.X + 6, p.Z - 6, p.Z + 6, "PalmHills", 4) then
				palm(parent, p, rng:NextNumber(1.0, 1.5))
				claim(p.X - 3, p.X + 3, p.Z - 3, p.Z + 3)
				n += 1
			end
		end
		return n
	end

	---------------------------------------------------------------------------------------------
	-- Downtown (Solana Heights)

	-- Fountain plaza on the open corner NW of Palm Blvd / Solana Ave (the lots there were cleared for
	-- the Sparkle & Co heist; the plaza stays 100+ studs from it), with the SOLANA HEIGHTS arch.
	local function buildPlaza(parent)
		local x0, x1, z0, z1 = -50, 20, -290, -180
		if not spotFree(x0, x1, z0, z1, "SolanaHeights", 2) then
			return false
		end
		local m = ArtKit.Model(parent, "SolanaPlaza")
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		P(m, Vector3.new(x1 - x0, 0.24, z1 - z0), CFrame.new(cx, 0.02, cz), PAVING, Enum.Material.Concrete, { CanCollide = false, Name = "Paving" })
		-- Tiered fountain with Gus the Gator on top
		local fx, fz = cx, cz - 15
		local function disc(h, dia, y, color, mat, collide)
			return P(m, cyl(h, dia), CFrame.new(fx, y, fz) * UPRIGHT, color, mat, { Shape = Enum.PartType.Cylinder, CanCollide = collide, Name = "Fountain" })
		end
		disc(0.4, 27, 0.2, N.Pink, Enum.Material.Neon, false) -- glowing ring at the foot
		disc(2, 26, 1.1, C.White, Enum.Material.Marble, true) -- basin wall (0.1..2.1)
		disc(0.3, 23.5, 2.2, POOL, nil, false) -- basin water
		disc(6, 4, 5, PINK, nil, true) -- column (2..8)
		disc(1, 12, 8.5, C.White, Enum.Material.Marble, true) -- middle bowl (8..9)
		local bowlWater = disc(0.3, 10.5, 9.1, POOL, nil, false)
		disc(3, 2.4, 10.5, PINK, nil, true) -- column (9..12)
		disc(0.8, 6, 12.4, C.White, Enum.Material.Marble, true) -- top bowl (12..12.8)
		gus(m, CFrame.new(fx, 12.8, fz), 1.5, false)
		light(bowlWater, N.Cyan, 28, 1.2)
		for _, o in ipairs({ { 19, 0 }, { -19, 0 }, { 0, 19 }, { 0, -19 } }) do
			local p = Vector3.new(fx + o[1], 0, fz + o[2])
			bench(m, CFrame.lookAt(p, Vector3.new(fx, 0, fz)))
		end
		for _, p in ipairs({ { -44, -284 }, { 14, -284 }, { -44, -222 }, { -40, -188 } }) do
			palm(m, Vector3.new(p[1], 0, p[2]), rng:NextNumber(1.3, 1.6))
		end
		-- Arch at the plaza's street corner, turned 45 degrees to face the intersection (50, -150).
		-- Pillars land at (15.6, -215.6) and (-15.6, -184.4): 10 studs from both road edges.
		local acf = CFrame.lookAt(Vector3.new(0, 0, -200), Vector3.new(50, 0, -150))
		for _, s in ipairs({ -22, 22 }) do
			P(m, Vector3.new(3.4, 28, 3.4), acf * CFrame.new(s, 14, 0), LAVENDER, nil, { Shadow = true, Name = "ArchPillar" })
			light(glow(m, Vector3.new(0.6, 26, 0.6), acf * CFrame.new(s, 14, -1.9), N.Cyan), N.Cyan, 30, 1.2)
		end
		P(m, Vector3.new(48, 3.4, 3.4), acf * CFrame.new(0, 29.7, 0), LAVENDER, nil, { Shadow = true, Name = "ArchBeam" })
		glow(m, Vector3.new(48.4, 0.5, 0.5), acf * CFrame.new(0, 28.2, -1.9), N.Pink)
		sign(m, acf * CFrame.new(0, 34.9, -0.3), "SOLANA HEIGHTS", N.Pink, 44, 7)
		claim(x0, x1, z0, z1)
		stats.plaza = string.format("(%d, %d)", cx, cz)
		return true
	end

	local function downtownDecos()
		local list = {}
		local b = artRoot:FindFirstChild("Buildings")
		for _, m in ipairs(b and b:GetChildren() or {}) do
			local body = m:IsA("Model") and m.Name == "DecoBuilding" and m:FindFirstChild("Body")
			if body and Layout.District(body.Position.X, body.Position.Z) == "SolanaHeights" then
				table.insert(list, { model = m, body = body, h = body.Size.Y })
			end
		end
		return list
	end

	-- Neon name signs on the top tier of tall towers (ones ArtGen didn't already sign), facing the
	-- street (a Deco's front faces the nearest road).
	local function placeRoofSigns(parent, decos, cap)
		table.sort(decos, function(a, b)
			return a.h > b.h
		end)
		local done = {}
		for _, d in ipairs(decos) do
			if #done >= cap or not room(3) then
				break
			end
			if d.h >= 100 and not d.model:FindFirstChild("Sign") and farFrom(done, d.body.Position, 200) then
				local top = d.body
				for _, c in ipairs(d.model:GetChildren()) do
					if c.Name == "Tier" and c:IsA("BasePart") and c.Position.Y > top.Position.Y then
						top = c
					end
				end
				local cf = top.CFrame * CFrame.new(0, top.Size.Y / 2 + 4.5, -top.Size.Z / 2 + 0.6)
				sign(parent, cf, TOWER_NAMES[#done + 1], NEONS[#done % #NEONS + 1], math.min(top.Size.X * 0.85, 44), 9)
				table.insert(done, d.body.Position)
			end
		end
		return #done
	end

	-- Parody billboards: on the front edge of low roofs, then on open ground corners.
	local function placeBillboards(parent, decos, capRoof, capGround)
		local spots, ad = {}, 0
		local function nextAd()
			ad += 1
			return BILLBOARD_ADS[(ad - 1) % #BILLBOARD_ADS + 1], NEONS[(ad - 1) % #NEONS + 1]
		end
		table.sort(decos, function(a, b)
			return a.h < b.h
		end)
		local roof = 0
		for _, d in ipairs(decos) do
			if roof >= capRoof or not room(5) then
				break
			end
			local body = d.body
			if d.h >= 40 and d.h <= 95 and body.Size.X >= 44 and not d.model:FindFirstChild("Sign") and farFrom(spots, body.Position, 260) then
				local cf = body.CFrame * CFrame.new(0, body.Size.Y / 2, -body.Size.Z / 2 + 5)
				local x0, x1, z0, z1 = footprint(cf, 36, 3)
				local y = cf.Position.Y
				if not physBlocked(x0, x1, z0, z1, y + 0.5, y + 34) then -- clear of upper tiers
					local text, color = nextAd()
					add(ArtKit.Billboard(parent, cf, text, color))
					table.insert(spots, body.Position)
					roof += 1
				end
			end
		end
		-- Corner candidates beside every downtown intersection, facing the east-west street.
		local cands = {}
		for _, xr in ipairs(DT_X) do
			for _, zr in ipairs(DT_Z) do
				for _, sx in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local pos = Vector3.new(xr[1] + sx * (xr[2] + 26), 0, zr[1] + sz * (zr[2] + 12))
						table.insert(cands, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -sz)))
					end
				end
			end
		end
		local ground = 0
		for _, cf in ipairs(shuffle(cands)) do
			if ground >= capGround or not room(5) then
				break
			end
			-- The lot behind must be empty too, so these only go on open corners, not before facades.
			local l0, l1, m0, m1 = footprint(cf * CFrame.new(0, 0, 16), 38, 36)
			if farFrom(spots, cf.Position, 200) and spotFreeCF(cf, 38, 4, "SolanaHeights", 2, 6, 36)
				and not claimed(l0, l1, m0, m1) and not physBlocked(l0, l1, m0, m1, 0.4, 36) then
				local text, color = nextAd()
				add(ArtKit.Billboard(parent, cf, text, color))
				claimCF(cf, 38, 4)
				table.insert(spots, cf.Position)
				ground += 1
			end
		end
		return roof, ground
	end

	-- Point `off` studs beyond the edge of a downtown road, and the direction back toward the road.
	local function sidePoint(run, t, side, off)
		local line, half = run[2], run[3]
		if run[1] == "x" then
			return Vector3.new(line + side * (half + off), 0, t), Vector3.new(-side, 0, 0)
		end
		return Vector3.new(t, 0, line + side * (half + off)), Vector3.new(0, 0, -side)
	end

	-- Bus shelter, open side facing the road: roof, glass back, bench, neon trim and a BUS sign.
	local function busStop(parent, cf, color)
		local m = ArtKit.Model(parent, "BusStop")
		P(m, Vector3.new(11, 0.5, 5), cf * CFrame.new(0, 8.2, 0), C.White, nil, { Name = "Roof" })
		P(m, Vector3.new(10, 7.95, 0.3), cf * CFrame.new(0, 3.975, 2.1), C.Glass, Enum.Material.Glass, { Name = "Glass", Transparency = 0.45 })
		for _, x in ipairs({ -5.2, 5.2 }) do
			P(m, Vector3.new(0.4, 7.95, 0.4), cf * CFrame.new(x, 3.975, -2.1), C.Steel, Enum.Material.Metal, { Name = "Post" })
		end
		P(m, Vector3.new(8, 0.4, 1.5), cf * CFrame.new(0, 1.8, 1.2), C.Wood, Enum.Material.WoodPlanks, { Name = "Seat" })
		light(glow(m, Vector3.new(11.2, 0.35, 0.35), cf * CFrame.new(0, 8.1, -2.6), color), color, 18, 1)
		sign(m, cf * CFrame.new(0, 9.55, -2.1), "BUS", color, 4, 2.2)
	end

	-- At most one stop per street side; sides tried in random order.
	local function placeBusStops(parent, cap)
		local sides = {}
		for _, list in ipairs({ DT_AVENUES, DT_STREETS }) do
			for _, run in ipairs(list) do
				table.insert(sides, { run, -1 })
				table.insert(sides, { run, 1 })
			end
		end
		local n = 0
		for _, s in ipairs(shuffle(sides)) do
			if n >= cap or not room(9) then
				break
			end
			local ts = {}
			for t = s[1][4] + 40, s[1][5] - 40, 45 do
				table.insert(ts, t)
			end
			for _, t in ipairs(shuffle(ts)) do
				local pos, look = sidePoint(s[1], t, s[2], 9)
				local cf = CFrame.lookAt(pos, pos + look)
				local ok, x0, x1, z0, z1 = spotFreeCF(cf, 11.4, 5.6, "SolanaHeights", 1)
				if ok then
					busStop(parent, cf, NEONS[n % #NEONS + 1])
					claim(x0, x1, z0, z1)
					n += 1
					break
				end
			end
		end
		return n
	end

	-- Planters every 70 studs along both sides of Solana Ave and Palm Blvd (8 studs off the road
	-- edge), with benches in between. The sidewalk is only 10 studs wide where towers line it, so a
	-- planter gets a palm only if a crown fits; otherwise a round shrub.
	local function dressAvenues(parent)
		local palms, shrubs, benches = 0, 0, 0
		for _, run in ipairs(DT_AVENUES) do
			for _, side in ipairs({ -1, 1 }) do
				local i = 0
				for t = run[4] + 20, run[5] - 20, 35 do
					i += 1
					local pos, look = sidePoint(run, t, side, 8)
					if i % 2 == 1 then
						if room(2) and spotFree(pos.X - 1.5, pos.X + 1.5, pos.Z - 1.5, pos.Z + 1.5, "SolanaHeights", 0.3) then
							P(parent, Vector3.new(3, 1.4, 3), CFrame.new(pos + Vector3.new(0, 0.7, 0)), C.White, Enum.Material.Concrete, { Name = "Planter" })
							if not physBlocked(pos.X - 5, pos.X + 5, pos.Z - 5, pos.Z + 5, 9, 20) then
								palm(parent, pos, 1)
								palms += 1
							else
								P(parent, Vector3.new(3.2, 3.2, 3.2), CFrame.new(pos + Vector3.new(0, 2.2, 0)), HEDGE, Enum.Material.Grass,
									{ Shape = Enum.PartType.Ball, CanCollide = false, Name = "Shrub" })
								shrubs += 1
							end
							claim(pos.X - 1.5, pos.X + 1.5, pos.Z - 1.5, pos.Z + 1.5)
						end
					elseif i % 4 == 0 and benches < 12 and room(3) then
						local cf = CFrame.lookAt(pos, pos + look)
						local ok, x0, x1, z0, z1 = spotFreeCF(cf, 6.2, 2.6, "SolanaHeights", 0.5)
						if ok then
							bench(parent, cf)
							claim(x0, x1, z0, z1)
							benches += 1
						end
					end
				end
			end
		end
		return palms, shrubs, benches
	end

	---------------------------------------------------------------------------------------------
	-- Build: Palm Hills first (landmarks before houses so houses fill around them), then downtown.
	-- Each district has its own part budget.

	limit = 710
	local ph = sub(folder, "PalmHills")
	buildStripMall(sub(ph, "StripMall"))
	buildPark(sub(ph, "Park"))
	buildSwimClub(sub(ph, "SwimClub"))
	addExistingHouses()
	local oldHouses = #houses
	local newHouses = placeHouses(sub(ph, "Houses"), 44)
	shuffle(houses)
	local yards = sub(ph, "Yards")
	local nDrive = placeDriveways(yards, 90)
	local nMail = placeMailboxes(yards, 24)
	local nPools = placePools(yards, 22)
	local nEdges = placeYardEdges(yards, 24)
	local nFlamingo = placeFlamingos(yards, 4)
	local nLawnPalms = placeLawnPalms(sub(ph, "Palms"), 16)
	local phUsed = used

	limit = math.min(used + 480, 1190)
	local dt = sub(folder, "Downtown")
	buildPlaza(dt)
	local decos = downtownDecos()
	local nRoofSigns = placeRoofSigns(sub(dt, "RoofSigns"), decos, 7)
	local nRoofBoards, nGroundBoards = placeBillboards(sub(dt, "Billboards"), decos, 5, 3)
	local nStops = placeBusStops(sub(dt, "BusStops"), 6)
	local nPalms, nShrubs, nBenches = dressAvenues(sub(dt, "Sidewalks"))

	local parts = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format(
		"[PalmHillsDowntown] PH (%d parts): mall %s, park %s, club %s, houses %d new + %d old, driveways %d, mailboxes %d, pools %d, fenced yards %d, flamingo pairs %d, lawn palms %d | "
			.. "DT (%d parts): plaza %s, roof signs %d, billboards %d roof + %d ground, bus stops %d, planter palms %d, shrubs %d, benches %d | lights %d, parts %d",
		phUsed, stats.mall or "SKIPPED", stats.park or "SKIPPED", stats.club or "SKIPPED", newHouses, oldHouses, nDrive, nMail, nPools, nEdges, nFlamingo, nLawnPalms,
		used - phUsed, stats.plaza or "SKIPPED", nRoofSigns, nRoofBoards, nGroundBoards, nStops, nPalms, nShrubs, nBenches, lights, parts))
	return parts
end

return Art
