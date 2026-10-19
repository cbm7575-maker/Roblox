-- CityGen (ModuleScript, ServerStorage.Tools.CityGen). Studio-only builder for the greybox of Port Solana.
-- Run from the MCP: require(game.ServerStorage.Tools.CityGen:Clone()).Build()
-- Rebuilds Workspace.City, Workspace.Heists, Workspace.Spawns and the terrain water from scratch.
-- Layout (studs): land x -2000..1500, z -2000..2000; ocean east of x 1500. North is -Z.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local CityGen = {}

local ROAD_Y = 0.1 -- top of every road surface
local rng = Random.new(20261112)

CityGen.Districts = {
	{ Name = "GatorGlades", Rect = { -2000, -900, -2000, 850 }, Color = Color3.fromRGB(74, 102, 58), Material = Enum.Material.Grass },
	{ Name = "GladesSouthWest", Rect = { -2000, -1900, 850, 2000 }, Color = Color3.fromRGB(74, 102, 58), Material = Enum.Material.Grass },
	{ Name = "GladesSouthEast", Rect = { -950, -900, 850, 2000 }, Color = Color3.fromRGB(74, 102, 58), Material = Enum.Material.Grass },
	{ Name = "GladesSouth", Rect = { -1900, -950, 1900, 2000 }, Color = Color3.fromRGB(74, 102, 58), Material = Enum.Material.Grass },
	{ Name = "SaltmarshIsland", Rect = { -1750, -1100, 1000, 1700 }, Color = Color3.fromRGB(150, 150, 140), Material = Enum.Material.Concrete },
	{ Name = "PalmHills", Rect = { -900, 1000, -2000, -850 }, Color = Color3.fromRGB(120, 176, 92), Material = Enum.Material.Grass },
	{ Name = "SolanaHeights", Rect = { -900, 1000, -850, 600 }, Color = Color3.fromRGB(214, 200, 196), Material = Enum.Material.Concrete },
	{ Name = "RustwaterDocks", Rect = { -900, 450, 600, 2000 }, Color = Color3.fromRGB(120, 112, 108), Material = Enum.Material.Concrete },
	{ Name = "MarinaRow", Rect = { 450, 1500, 600, 2000 }, Color = Color3.fromRGB(196, 170, 130), Material = Enum.Material.WoodPlanks },
	{ Name = "FlamingoBeach", Rect = { 1000, 1500, -2000, 600 }, Color = Color3.fromRGB(244, 217, 166), Material = Enum.Material.Sand },
	{ Name = "LighthouseKey", Rect = { 2100, 2450, -1550, -1150 }, Color = Color3.fromRGB(244, 217, 166), Material = Enum.Material.Sand },
}

local PASTELS = {
	Color3.fromRGB(255, 190, 214), Color3.fromRGB(170, 232, 222), Color3.fromRGB(255, 214, 170),
	Color3.fromRGB(206, 190, 255), Color3.fromRGB(190, 240, 190), Color3.fromRGB(255, 240, 190),
}

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local box

-- Boat pads on the water beside the marina piers and the beach pier (FacingYaw 270 = nose east,
-- out to sea). VehicleService launches boats from the nearest one for the player's side.
-- Safe to run on its own: require(ServerStorage.Tools.CityGen).BoatPads()
function CityGen.BoatPads(spawns)
	spawns = spawns or Workspace:FindFirstChild("Spawns")
	for _, old in ipairs(spawns:GetChildren()) do
		if old.Name == "BoatPad" then
			old:Destroy()
		end
	end
	local WATER_Y = -1.5
	local function pad(side, color, x, z, i)
		local p = box(spawns, "BoatPad", Vector3.new(26, 0.2, 13), CFrame.new(x, WATER_Y + 0.05, z), color, Enum.Material.Neon,
			{ CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 0.7 })
		p:SetAttribute("Side", side)
		p:SetAttribute("Index", i)
		p:SetAttribute("FacingYaw", 270)
	end
	local civ, cop = Color3.fromRGB(255, 62, 165), Color3.fromRGB(34, 225, 255)
	-- Marina pads sit past the end of the finger docks (x 1552..1662, DocksMarina art).
	for i, z in ipairs({ 1140, 1160, 1180 }) do
		pad("Civilian", civ, 1705, z, i) -- marina, north side of the first pier
	end
	for i, z in ipairs({ -438, -458 }) do
		pad("Civilian", civ, 1560, z, 3 + i) -- beach pier, by the Ferris wheel
	end
	for i, z in ipairs({ 1590, 1610 }) do
		pad("Cop", cop, 1705, z, i) -- harbor patrol dock, south of the last pier
	end
end

box = function(parent, name, size, cf, color, material, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	if opts then
		for k, v in pairs(opts) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Split a rectangle into tiles of at most `maxTile` studs so no part exceeds the size limit.
local function tiles(x0, x1, z0, z1, maxTile, fn)
	local nx = math.max(1, math.ceil((x1 - x0) / maxTile))
	local nz = math.max(1, math.ceil((z1 - z0) / maxTile))
	local sx, sz = (x1 - x0) / nx, (z1 - z0) / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			fn(x0 + i * sx, x0 + (i + 1) * sx, z0 + j * sz, z0 + (j + 1) * sz)
		end
	end
end

-- Roads ---------------------------------------------------------------------------------------

local roadIndex = 0
local MAX_ROAD_PIECE = 900 -- parts can't be longer than 2048 studs; long roads are built from pieces
local function road(parent, name, ax, az, bx, bz, width, color, material)
	local a, b = Vector3.new(ax, 0, az), Vector3.new(bx, 0, bz)
	local total = (b - a).Magnitude
	local pieces = math.max(1, math.ceil(total / MAX_ROAD_PIECE))
	local last
	for i = 1, pieces do
		roadIndex += 1
		-- Tiny height offsets stop overlapping roads from flickering; the bump is 0.01 studs at most.
		local top = ROAD_Y + (roadIndex % 5) * 0.002
		local pa = a:Lerp(b, (i - 1) / pieces)
		local pb = a:Lerp(b, i / pieces)
		local len = (pb - pa).Magnitude
		local mid = (pa + pb) / 2
		local cf = CFrame.lookAt(Vector3.new(mid.X, top - 0.5, mid.Z), Vector3.new(pb.X, top - 0.5, pb.Z))
		-- Extend by half the width so joints overlap instead of leaving gaps.
		last = box(parent, name, Vector3.new(width, 1, len + width * 0.5), cf, color or Color3.fromRGB(58, 58, 66), material or Enum.Material.Asphalt)
	end
	return last
end

local function polyline(parent, name, points, width, color, material)
	for i = 1, #points - 1 do
		road(parent, name, points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], width, color, material)
	end
end

-- Rounded-rectangle loop, corners approximated by `steps` segments.
local function loopPoints(xMin, xMax, zMin, zMax, r, steps)
	local pts = {}
	local corners = {
		{ xMax - r, zMin + r, -90, 0 }, -- NE
		{ xMax - r, zMax - r, 0, 90 }, -- SE
		{ xMin + r, zMax - r, 90, 180 }, -- SW
		{ xMin + r, zMin + r, 180, 270 }, -- NW
	}
	for _, c in ipairs(corners) do
		for s = 0, steps do
			local ang = math.rad(c[3] + (c[4] - c[3]) * s / steps)
			table.insert(pts, { c[1] + r * math.cos(ang), c[2] + r * math.sin(ang) })
		end
	end
	table.insert(pts, pts[1])
	return pts
end

-- Buildings -------------------------------------------------------------------------------------

local function building(parent, x, z, sx, sz, h, color)
	local b = box(parent, "Building", Vector3.new(sx, h, sz), CFrame.new(x, h / 2, z), color, Enum.Material.SmoothPlastic)
	-- Neon band just below the roof line: only a 0.3-stud rim sticks out, so roofs stay pastel.
	box(b, "Trim", Vector3.new(sx + 0.6, 0.8, sz + 0.6), CFrame.new(x, h - 2, z),
		rng:NextInteger(0, 1) == 0 and Color3.fromRGB(255, 62, 165) or Color3.fromRGB(34, 225, 255), Enum.Material.Neon,
		{ CanCollide = false, CanTouch = false, CanQuery = false })
	return b
end

-- Fill the block between road lines with 1-4 buildings.
local function fillBlock(parent, x0, x1, z0, z1, inset, hMin, hMax, colors)
	x0, x1, z0, z1 = x0 + inset, x1 - inset, z0 + inset, z1 - inset
	if x1 - x0 < 30 or z1 - z0 < 30 then
		return
	end
	local splitX = (x1 - x0) > 160 and 2 or 1
	local splitZ = (z1 - z0) > 160 and 2 or 1
	local cw, cd = (x1 - x0) / splitX, (z1 - z0) / splitZ
	for i = 0, splitX - 1 do
		for j = 0, splitZ - 1 do
			if rng:NextNumber() < 0.9 then
				local w, d = cw - 12, cd - 12
				local cx, cz = x0 + (i + 0.5) * cw, z0 + (j + 0.5) * cd
				building(parent, cx, cz, w, d, rng:NextInteger(hMin, hMax), colors[rng:NextInteger(1, #colors)])
			end
		end
	end
end

-- Markers (heists, spawns, landmarks) -------------------------------------------------------------

local function label(parent, text, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, 14, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 700
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.Parent = gui
	gui.Parent = parent
end

local function marker(parent, name, x, z, size, color, text, attrs)
	local m = Instance.new("Model")
	m.Name = name
	local pad = box(m, "Pad", Vector3.new(size, 0.2, size), CFrame.new(x, ROAD_Y + 0.12, z), color, Enum.Material.Neon,
		{ CanCollide = false, CanTouch = true, CanQuery = false, Transparency = size >= 50 and 0.8 or 0.4 })
	m.PrimaryPart = pad
	label(pad, text, color)
	for k, v in pairs(attrs or {}) do
		m:SetAttribute(k, v)
	end
	m.Parent = parent
	return m
end

-- Build ----------------------------------------------------------------------------------------

function CityGen.Build()
	local city = folder(Workspace, "City")
	local heists = folder(Workspace, "Heists")
	local spawns = folder(Workspace, "Spawns")
	city:ClearAllChildren()
	heists:ClearAllChildren()
	spawns:ClearAllChildren()
	for _, n in ipairs({ "Baseplate", "SpawnLocation" }) do
		local old = Workspace:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	roadIndex = 0

	-- Ground
	local ground = folder(city, "Ground")
	for _, d in ipairs(CityGen.Districts) do
		local r = d.Rect
		tiles(r[1], r[2], r[3], r[4], 1000, function(x0, x1, z0, z1)
			box(ground, d.Name, Vector3.new(x1 - x0, 4, z1 - z0), CFrame.new((x0 + x1) / 2, -2, (z0 + z1) / 2), d.Color, d.Material)
		end)
	end
	-- Beach slopes down into the ocean (wedge: high edge west, low edge east).
	for _, zr in ipairs({ { -2000, 0 }, { 0, 2000 } }) do
		local cz = (zr[1] + zr[2]) / 2
		local w = Instance.new("WedgePart")
		w.Name = "ShoreSlope"
		w.Anchored = true
		w.Size = Vector3.new(zr[2] - zr[1], 6, 120)
		w.CFrame = CFrame.lookAt(Vector3.new(1560, -3, cz), Vector3.new(1561, -3, cz))
		w.Color = Color3.fromRGB(236, 206, 150)
		w.Material = Enum.Material.Sand
		w.CastShadow = false
		w.Parent = ground
	end

	-- Water (terrain): ocean east, moat around the prison island.
	local terrain = Workspace.Terrain
	terrain:Clear()
	terrain:FillBlock(CFrame.new(2200, -25, 0), Vector3.new(1400, 8, 4800), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(2200, -11.25, 0), Vector3.new(1400, 19.5, 4800), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(-1425, -11, 1375), Vector3.new(950, 6, 1050), Enum.Material.Mud)
	terrain:FillBlock(CFrame.new(-1425, -4.75, 1375), Vector3.new(950, 6.5, 1050), Enum.Material.Water)
	terrain.WaterColor = Color3.fromRGB(40, 190, 200)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 8

	-- Roads
	local roads = folder(city, "Roads")
	local HWY, AVE, ST = 60, 44, 32
	polyline(roads, "Highway1", loopPoints(-1850, 1000, -1850, 1850, 220, 6), HWY)
	road(roads, "SolanaAve", 50, -1850, 50, 1850, AVE)
	road(roads, "PalmBlvd", -1850, -150, 1000, -150, AVE)
	-- Downtown and Palm Hills north-south streets
	for _, x in ipairs({ -650, -300, 400, 750 }) do
		road(roads, "Street", x, -1850, x, 600, ST)
	end
	-- Downtown east-west streets
	for _, z in ipairs({ -600, 150, 450 }) do
		road(roads, "Street", -900, z, 1000, z, ST)
	end
	-- Palm Hills east-west streets
	for _, z in ipairs({ -1650, -1250 }) do
		road(roads, "Street", -900, z, 1000, z, ST)
	end
	-- Docks
	for _, z in ipairs({ 900, 1300, 1650 }) do
		road(roads, "Street", -900, z, 450, z, ST)
	end
	for _, x in ipairs({ -650, -300 }) do
		road(roads, "Street", x, 600, x, 1850, ST)
	end
	-- Marina Row
	road(roads, "MarinaRow", 450, 1000, 1450, 1000, ST)
	road(roads, "MarinaRow", 450, 1500, 1450, 1500, ST)
	road(roads, "MarinaLink", 450, 600, 450, 1850, ST)
	-- Glades dirt roads
	local DIRT = Color3.fromRGB(120, 92, 60)
	polyline(roads, "GladesTrail", { { -1300, -1850 }, { -1250, -1300 }, { -1350, -700 }, { -1250, -100 }, { -1350, 500 }, { -1425, 850 } }, 28, DIRT, Enum.Material.Ground)
	polyline(roads, "GladesTrail", { { -1850, -1100 }, { -1500, -1000 }, { -1250, -1300 } }, 28, DIRT, Enum.Material.Ground)
	-- Prison bridge (the only road onto the island)
	road(roads, "PrisonBridge", -1425, 850, -1425, 1000, 34, Color3.fromRGB(90, 90, 96), Enum.Material.Concrete)
	road(roads, "PrisonRoad", -1425, 1000, -1425, 1350, 30, Color3.fromRGB(90, 90, 96), Enum.Material.Concrete)
	-- Causeway to Lighthouse Key
	road(roads, "Causeway", 1000, -1350, 2100, -1350, 40, Color3.fromRGB(70, 70, 80), Enum.Material.Concrete)
	road(roads, "KeyLoop", 2100, -1350, 2400, -1350, 30)
	-- Piers
	local WOOD = Color3.fromRGB(150, 110, 70)
	for _, z in ipairs({ 1100, 1300, 1650 }) do
		road(roads, "Pier", 1440, z, 1680, z, 18, WOOD, Enum.Material.WoodPlanks)
	end
	road(roads, "FerrisPier", 1440, -400, 1760, -400, 34, WOOD, Enum.Material.WoodPlanks)

	-- Buildings
	local blds = folder(city, "Buildings")
	local dtX = { -900, -650, -300, 50, 400, 750, 1000 }
	local dtZ = { -850, -600, -150, 150, 450, 600 }
	for i = 1, #dtX - 1 do
		for j = 1, #dtZ - 1 do
			fillBlock(blds, dtX[i], dtX[i + 1], dtZ[j], dtZ[j + 1], 26, 50, 200, PASTELS)
		end
	end
	local phZ = { -2000, -1850, -1650, -1250, -850 } -- -1850 = highway north side
	for i = 1, #dtX - 1 do
		for j = 1, #phZ - 1 do
			fillBlock(blds, dtX[i], dtX[i + 1], phZ[j], phZ[j + 1], 40, 18, 30, PASTELS)
		end
	end
	local dkX = { -900, -650, -300, 50, 450 } -- 50 = Solana Ave
	local dkZ = { 600, 900, 1300, 1650, 1850, 2000 } -- 1850 = highway south side
	local RUST = { Color3.fromRGB(150, 90, 70), Color3.fromRGB(90, 110, 130), Color3.fromRGB(120, 120, 110) }
	for i = 1, #dkX - 1 do
		for j = 1, #dkZ - 1 do
			fillBlock(blds, dkX[i], dkX[i + 1], dkZ[j], dkZ[j + 1], 30, 25, 45, RUST)
		end
	end

	-- Landmarks (placeholders)
	local lm = folder(city, "Landmarks")
	-- (The lighthouse, Ferris wheel and flamingo landmarks are real models placed by Art/Beach.)
	box(lm, "PrisonBlock", Vector3.new(260, 40, 200), CFrame.new(-1425, 20, 1450), Color3.fromRGB(170, 170, 160), Enum.Material.Concrete)
	-- Prison yard behind the block (x -1600..-1250, z 1550..1690), 24-stud walls, a vent in the south wall.
	local WALL = Color3.fromRGB(150, 150, 140)
	box(lm, "YardWallWest", Vector3.new(4, 24, 140), CFrame.new(-1600, 12, 1620), WALL, Enum.Material.Concrete)
	box(lm, "YardWallEast", Vector3.new(4, 24, 140), CFrame.new(-1250, 12, 1620), WALL, Enum.Material.Concrete)
	box(lm, "YardWallNW", Vector3.new(45, 24, 4), CFrame.new(-1577.5, 12, 1550), WALL, Enum.Material.Concrete)
	box(lm, "YardWallNE", Vector3.new(45, 24, 4), CFrame.new(-1272.5, 12, 1550), WALL, Enum.Material.Concrete)
	box(lm, "YardWallSouthW", Vector3.new(169, 24, 4), CFrame.new(-1515.5, 12, 1690), WALL, Enum.Material.Concrete)
	box(lm, "YardWallSouthE", Vector3.new(169, 24, 4), CFrame.new(-1334.5, 12, 1690), WALL, Enum.Material.Concrete)
	box(lm, "YardWallSouthTop", Vector3.new(12, 18, 4), CFrame.new(-1425, 15, 1690), WALL, Enum.Material.Concrete)
	box(lm, "PrisonVent", Vector3.new(12, 6, 4), CFrame.new(-1425, 3, 1690), Color3.fromRGB(90, 90, 100), Enum.Material.DiamondPlate)
	box(lm, "VentGlow", Vector3.new(12.4, 0.4, 4.4), CFrame.new(-1425, 6.2, 1690), Color3.fromRGB(255, 138, 61), Enum.Material.Neon,
		{ CanCollide = false, CanQuery = false, CanTouch = false })
	box(lm, "PoliceHQ", Vector3.new(160, 50, 120), CFrame.new(575, 25, -420), Color3.fromRGB(60, 90, 160))

	-- Heist sites (markers now, buildings in phase 3). Each gets a RobPoint: the thing you rob
	-- (register, ATM, safe). HeistService puts the Rob prompt on it.
	local H = Color3.fromRGB(255, 138, 61)
	local function heist(name, x, z, size, text, id, tier)
		local m = marker(heists, name, x, z, size, H, text, { HeistId = id, Tier = tier })
		box(m, "RobPoint", Vector3.new(4, 4, 3), CFrame.new(x, ROAD_Y + 2, z), Color3.fromRGB(40, 36, 52), Enum.Material.SmoothPlastic,
			{ CanCollide = true })
		box(m, "RobGlow", Vector3.new(4.2, 0.4, 3.2), CFrame.new(x, ROAD_Y + 4.2, z), H, Enum.Material.Neon,
			{ CanCollide = false, CanQuery = false, CanTouch = false })
		return m
	end
	heist("GlowMart", -470, -1450, 40, "Glow Mart", "GlowMart", 1)
	heist("FuelStop", 580, -1150, 40, "Fuel Stop", "FuelStop", 1)
	for i, p in ipairs({ { -480, 300 }, { 1060, -700 }, { 200, 1480 }, { -1280, -500 }, { 600, -1450 } }) do
		heist("ATM" .. i, p[1], p[2], 16, "ATM", "ATM", 1)
	end
	heist("SparkleCo", -120, -380, 50, "Sparkle & Co.", "SparkleCo", 2)
	heist("ClubNova", 1120, -150, 50, "Club Nova", "ClubNova", 2)
	heist("CoastalBank", 230, 300, 60, "Coastal Bank", "CoastalBank", 3)
	heist("SeaDream", 1720, 1300, 50, "Sea Dream (yacht)", "SeaDream", 3)

	-- Spawns and service spots
	local ROB, COP = Color3.fromRGB(255, 62, 165), Color3.fromRGB(34, 225, 255)
	-- The hideout: where Wanted players bank their loot (and lose their heat).
	marker(spawns, "Hideout", -475, 1100, 90, ROB, "Hideout", { Service = "Hideout" })
	-- Team spawns (TeamColor must match Config.Teams)
	-- facing: the direction new players look when they appear (toward their car pads and the street).
	local function teamSpawn(name, pos, teamColor, facing)
		local sp = Instance.new("SpawnLocation")
		sp.Name = name
		sp.Anchored = true
		sp.Size = Vector3.new(12, 1, 12)
		sp.CFrame = facing and CFrame.lookAt(pos, pos + facing) or CFrame.new(pos)
		sp.Neutral = false
		sp.AllowTeamChangeOnTouch = false
		sp.TeamColor = BrickColor.new(teamColor)
		sp.Color = sp.TeamColor.Color
		sp.Transparency = 0.5
		sp.Duration = 0
		sp.Parent = spawns
		return sp
	end
	-- Citizens spawn at one of three spots around the city; each has car pads facing a street.
	teamSpawn("CitySpawnDowntown", Vector3.new(-125, ROAD_Y + 0.5, 40), "Hot pink", Vector3.new(0, 0, 1))
	teamSpawn("CitySpawnBeach", Vector3.new(1120, ROAD_Y + 0.5, -950), "Hot pink", Vector3.new(-1, 0, 0))
	teamSpawn("CitySpawnPalmHills", Vector3.new(225, ROAD_Y + 0.5, -1450), "Hot pink", Vector3.new(0, 0, 1))
	teamSpawn("CopSpawn", Vector3.new(575, ROAD_Y + 0.5, -335), "Cyan", Vector3.new(0, 0, 1))
	teamSpawn("PrisonSpawn", Vector3.new(-1425, ROAD_Y + 0.5, 1610), "Deep orange")
	marker(spawns, "PoliceLot", 575, -300, 90, COP, "Police HQ", { Side = "Cop" })
	marker(spawns, "ChopShop", -780, 1580, 50, ROB, "Chop Shop", { Service = "ChopShop" })
	marker(spawns, "SprayAndGo", 250, 820, 40, Color3.fromRGB(110, 242, 196), "Spray & Go", { Service = "Spray" })
	marker(spawns, "Fence", -560, 1020, 24, ROB, "Mari (Fence)", { Service = "Fence" })
	-- Car pads: where starter and garage cars appear. FacingYaw: 0 = nose north (-Z), 90 = west,
	-- 180 = south. Pads are 22 studs long along the facing direction.
	local function pads(side, color, yaw, list)
		for i, p in ipairs(list) do
			local size = (yaw == 90 or yaw == 270) and Vector3.new(22, 0.2, 14) or Vector3.new(14, 0.2, 22)
			local pad = box(spawns, "CarPad", size, CFrame.new(p[1], ROAD_Y + 0.12, p[2]), color, Enum.Material.Neon,
				{ CanCollide = false, CanQuery = false, Transparency = 0.6 })
			pad:SetAttribute("Side", side)
			pad:SetAttribute("Index", i)
			pad:SetAttribute("FacingYaw", yaw)
		end
	end
	pads("Civilian", ROB, 180, { { -200, 110 }, { -150, 110 }, { -100, 110 }, { -50, 110 } }) -- downtown, toward z = 150
	pads("Civilian", ROB, 90, { { 1060, -1010 }, { 1060, -970 }, { 1060, -930 }, { 1060, -890 } }) -- beach, toward Ocean Drive
	pads("Civilian", ROB, 180, { { 180, -1300 }, { 225, -1300 }, { 270, -1300 } }) -- Palm Hills, toward z = -1250
	pads("Civilian", ROB, 0, { { -520, 1060 }, { -475, 1060 }, { -430, 1060 } }) -- hideout, toward z = 900
	pads("Cop", COP, 180, { { 485, -300 }, { 530, -300 }, { 575, -300 }, { 620, -300 }, { 665, -300 } }) -- Police HQ
	CityGen.BoatPads(spawns)

	-- Activities: race start pads and stunt ramps (positions from Config.Activities)
	local Activities = require(game:GetService("ReplicatedStorage").Shared.Config.Activities)
	local acts = folder(Workspace, "Activities")
	acts:ClearAllChildren()
	local GOLD = Color3.fromRGB(255, 214, 10)
	for _, race in ipairs(Activities.Races) do
		local padY = race.Boat and -1.4 or ROAD_Y + 0.14 -- boat races start on the water
		local pad = box(acts, "RaceStart_" .. race.Id, Vector3.new(30, 0.2, 30), CFrame.new(race.Start.X, padY, race.Start.Z), GOLD,
			Enum.Material.Neon, { CanCollide = false, CanQuery = false, Transparency = 0.7 })
		pad:SetAttribute("RaceId", race.Id)
		label(pad, "RACE: " .. race.Name, GOLD)
	end
	-- Taxi Stand downtown, next to the downtown citizen spawn.
	local taxi = box(acts, "TaxiStand", Vector3.new(26, 0.2, 26), CFrame.new(-240, ROAD_Y + 0.14, 40), Color3.fromRGB(255, 214, 10),
		Enum.Material.Neon, { CanCollide = false, CanQuery = false, Transparency = 0.6 })
	label(taxi, "TAXI STAND", Color3.fromRGB(255, 214, 10))

	-- Drift zone: a big asphalt pad on Lighthouse Key (clear of the lighthouse at x 2350).
	local dz = box(acts, "DriftZone", Vector3.new(190, 0.3, 340), CFrame.new(2200, ROAD_Y + 0.05, -1350),
		Color3.fromRGB(46, 44, 56), Enum.Material.Asphalt)
	label(dz, "DRIFT ZONE", Color3.fromRGB(123, 47, 255))
	for _, x in ipairs({ -95, 95 }) do
		box(acts, "DriftEdge", Vector3.new(1.5, 0.4, 340), CFrame.new(2200 + x, ROAD_Y + 0.25, -1350), Color3.fromRGB(123, 47, 255), Enum.Material.Neon,
			{ CanCollide = false, CanQuery = false })
	end
	for _, stunt in ipairs(Activities.Stunts) do
		-- Wedge: the low edge faces LookVector, so point it back toward the approaching car.
		local w = Instance.new("WedgePart")
		w.Name = "Stunt_" .. stunt.Id
		w.Anchored = true
		w.Size = Vector3.new(16, 9, 20)
		local center = Vector3.new(stunt.Ramp.X, ROAD_Y + 4.5, stunt.Ramp.Z)
		w.CFrame = CFrame.lookAt(center, center - stunt.Travel)
		w.Color = Color3.fromRGB(255, 138, 61)
		w.Material = Enum.Material.DiamondPlate
		w.TopSurface = Enum.SurfaceType.Smooth
		w:SetAttribute("StuntId", stunt.Id)
		w.Parent = acts
		label(w, stunt.Name, Color3.fromRGB(255, 138, 61))
	end

	-- Safety pass: remove any building touching a road, heist site or spawn spot
	-- (road curves, and future layout edits). Pads are inflated so lots get breathing room.
	local keepClear = {}
	for _, r in ipairs(roads:GetChildren()) do
		table.insert(keepClear, { r.CFrame, r.Size })
	end
	for _, f in ipairs({ heists, spawns, acts }) do
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(keepClear, { d.CFrame, d.Size + Vector3.new(30, 20, 30) })
			end
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { blds }
	local removed = {}
	for _, k in ipairs(keepClear) do
		for _, hit in ipairs(Workspace:GetPartBoundsInBox(k[1], k[2], overlap)) do
			local b = hit.Name == "Trim" and hit.Parent or hit
			removed[b] = true
		end
	end
	for b in pairs(removed) do
		b:Destroy()
	end

	-- Map edge walls (invisible)
	local walls = folder(city, "Walls")
	-- Land edges at x = -2000 and z = +-2000; the ocean reaches z = +-2400 and x = 2900.
	-- Each wall is a line from (x1, z1) to (x2, z2), built in pieces of at most 1000 studs.
	local function wall(x1, z1, x2, z2)
		local a, b = Vector3.new(x1, 200, z1), Vector3.new(x2, 200, z2)
		local n = math.max(1, math.ceil((b - a).Magnitude / 1000))
		for i = 1, n do
			local pa, pb = a:Lerp(b, (i - 1) / n), a:Lerp(b, i / n)
			local len = (pb - pa).Magnitude
			box(walls, "Wall", Vector3.new(4, 400, len + 4), CFrame.lookAt((pa + pb) / 2, pb), Color3.new(1, 1, 1), nil,
				{ Transparency = 1, CanQuery = false })
		end
	end
	wall(-2010, -2010, -2010, 2010) -- west
	wall(-2010, -2010, 1500, -2010) -- north (land)
	wall(-2010, 2010, 1500, 2010) -- south (land)
	wall(1500, -2010, 1500, -2410) -- ocean step north
	wall(1500, 2010, 1500, 2410) -- ocean step south
	wall(1500, -2410, 2910, -2410) -- ocean north
	wall(1500, 2410, 2910, 2410) -- ocean south
	wall(2910, -2410, 2910, 2410) -- ocean east

	-- Golden-hour lighting for the greybox (the full neon pass is step 3.5)
	Lighting.ClockTime = 16.8
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 130, 150)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atm.Density = 0.28
	atm.Color = Color3.fromRGB(255, 200, 190)
	atm.Decay = Color3.fromRGB(120, 90, 160)
	atm.Haze = 1.2
	atm.Parent = Lighting

	local count = 0
	for _, d in ipairs(Workspace.City:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return string.format("City built: %d parts, %d heist sites, %d roads", count, #heists:GetChildren(), #roads:GetChildren())
end

return CityGen
