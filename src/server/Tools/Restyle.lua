-- Restyle (ModuleScript, ServerStorage.Tools.Restyle). Studio-only "Look 2.0" pass over the built city:
-- realistic materials and window textures on top of what ArtGen/CityGen built. Run it after ArtGen:
--   require(game.ServerStorage.Tools.Restyle:Clone()).Run()
-- Safe to run again: restyled models are marked (attribute Restyled) and skipped.
--   * Deco buildings (Body / Tier boxes): plaster or concrete walls in softer colours, window-bay
--     textures on every side (Config.Textures: apartments, or office glass on towers over 70 studs),
--     the old glass strips removed, a glass shopfront along the street side, AC units on the roof.
--   * Houses: plaster walls, terracotta clay-tile (or slate shingle) roofs, darker glass.
--   * Warehouses: calmer corrugated metal, roof trim, roll-up doors along the long sides.
--   * Ground: concrete districts get sidewalk slab joints; greens a more natural grass colour.
--   * Roads: a neutral asphalt grey.
--   * Streets (opts.Streets): crosswalks and traffic signals at crossings, hydrants / bins / news
--     boxes / benches along the kerbs, yellow centre lines.
--   * Infill (opts.Infill): Deco buildings on empty street frontage downtown and along Marina Row, and
--     the middle of big blocks filled with low buildings, car parks (parked cars) and pocket parks.
--   * Nature (opts.Nature): Glades swamp pools (flat water parts, lily pads), cypress trees, sawgrass.
-- Full pass: Run({ Infill = true, Streets = true, Nature = true }).
-- Night lights for the facades are added on each client by SkyClient.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- A fresh copy: in the Studio edit session a plain require keeps returning the first-loaded version.
local Textures = require(ReplicatedStorage.Shared.Config.Textures:Clone())

local Restyle = {}

local WARM_WHITE = Color3.fromRGB(238, 232, 222)
local AC_GREY = Color3.fromRGB(158, 162, 168)
local ROOF_TILES = { Color3.fromRGB(176, 92, 62), Color3.fromRGB(160, 82, 58), Color3.fromRGB(190, 112, 78) }
local SLATE = Color3.fromRGB(92, 96, 104)
local SIDES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }

local rng = Random.new(20261119)

local function faceWidth(part, face)
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		return part.Size.X
	end
	return part.Size.Z
end

-- Window bays on every side of a wall box that is wide enough for at least one bay.
local function facade(part, image)
	for _, t in ipairs(part:GetChildren()) do
		if t:IsA("Texture") and t.Name == "Facade" then
			t:Destroy()
		end
	end
	for _, face in ipairs(SIDES) do
		local w = faceWidth(part, face)
		if w >= Textures.BayWidth then
			local t = Instance.new("Texture")
			t.Name = "Facade"
			t.Face = face
			t.Texture = image
			t.StudsPerTileU = Textures.BayWidth
			t.StudsPerTileV = Textures.FloorHeight
			-- Centre the bays across the face and line the floors up from the ground.
			t.OffsetStudsU = (w % Textures.BayWidth) / 2
			t.OffsetStudsV = part.Size.Y % Textures.FloorHeight
			t.Parent = part
		end
	end
end

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- A few rooftop AC boxes (and sometimes a water tank) on the top face of `top`.
local function roofClutter(model, top)
	local s = top.Size
	if s.X < 14 or s.Z < 14 then
		return
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local x = rng:NextNumber(-s.X / 2 + 4, s.X / 2 - 4)
		local z = rng:NextNumber(-s.Z / 2 + 4, s.Z / 2 - 4)
		local ac = part(model, "RoofAC", Vector3.new(4, 2.4, 5), top.CFrame * CFrame.new(x, s.Y / 2 + 1.2, z), AC_GREY, Enum.Material.Metal)
		ac.CastShadow = true
	end
	if rng:NextNumber() < 0.3 then
		local x = rng:NextNumber(-s.X / 2 + 5, s.X / 2 - 5)
		local z = rng:NextNumber(-s.Z / 2 + 5, s.Z / 2 - 5)
		local tank = part(model, "WaterTank", Vector3.new(7, 5, 5), top.CFrame * CFrame.new(x, s.Y / 2 + 3, z) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(120, 96, 76), Enum.Material.WoodPlanks)
		tank.Shape = Enum.PartType.Cylinder
		tank.CastShadow = true
	end
end

-- Glass shop windows along the street (front, -Z) side of a Deco building's ground floor.
local function shopfront(model, body)
	local w, h, d = body.Size.X, body.Size.Y, body.Size.Z
	if w < 16 or h < 20 then
		return
	end
	local door = model:FindFirstChild("Door")
	if door then
		door:Destroy()
	end
	local sf = part(model, "Shopfront", Vector3.new(w - 4, 11, 0.3), body.CFrame * CFrame.new(0, -h / 2 + 5.5, -d / 2 - 0.16),
		Color3.fromRGB(38, 40, 46))
	local t = Instance.new("Texture")
	t.Name = "Shop"
	t.Face = Enum.NormalId.Front
	t.Texture = Textures.Storefront
	t.StudsPerTileU = 16
	t.StudsPerTileV = 11
	t.OffsetStudsU = ((w - 4) % 16) / 2
	t.Parent = sf
end

function Restyle.Buildings(root)
	local count = 0
	for _, m in ipairs(root:GetDescendants()) do
		if m:IsA("Model") and m.Name == "DecoBuilding" and not m:GetAttribute("Restyled") then
			local body = m:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				m:SetAttribute("Restyled", true)
				count += 1
				local tall = body.Size.Y > 70
				-- Mostly glass offices up high and apartments lower down, with some mix so the skyline
				-- isn't one uniform blue.
				local office = rng:NextNumber() < (tall and 0.6 or 0.15)
				local image = office and Textures.Office or Textures.Apartment
				local top = body
				for _, p in ipairs(m:GetChildren()) do
					if p:IsA("BasePart") then
						if p.Name == "Window" then
							p:Destroy()
						elseif p.Name == "Body" or p.Name == "Tier" then
							p.Material = office and Enum.Material.Concrete or Enum.Material.Plaster
							p.Color = p.Color:Lerp(WARM_WHITE, 0.3)
							p.CastShadow = true
							if p.Size.Y >= 6 then
								facade(p, image)
							end
							if p.Position.Y + p.Size.Y / 2 > top.Position.Y + top.Size.Y / 2 then
								top = p
							end
						elseif p.Name == "Band" then
							p.Material = Enum.Material.Concrete
						end
					end
				end
				shopfront(m, body)
				roofClutter(m, top)
			end
		end
	end
	return count
end

function Restyle.Houses(root)
	local count = 0
	for _, m in ipairs(root:GetDescendants()) do
		if m:IsA("Model") and m.Name == "House" and not m:GetAttribute("Restyled") then
			m:SetAttribute("Restyled", true)
			count += 1
			local slate = rng:NextNumber() < 0.3
			local roofColor = slate and SLATE or ROOF_TILES[rng:NextInteger(1, #ROOF_TILES)]
			for _, p in ipairs(m:GetChildren()) do
				if p:IsA("WedgePart") then
					p.Material = slate and Enum.Material.RoofShingles or Enum.Material.ClayRoofTiles
					p.Color = roofColor
				elseif p:IsA("BasePart") then
					if p.Name == "Body" then
						p.Material = Enum.Material.Plaster
						p.Color = p.Color:Lerp(WARM_WHITE, 0.25)
						facade(p, Textures.Apartment) -- white-framed windows all round (the garage and door cover the front ones)
					elseif p.Name == "Window" then
						p:Destroy() -- the facade has proper windows now
					elseif p.Name == "Door" then
						p.Material = Enum.Material.WoodPlanks
						p.Color = rng:NextNumber() < 0.5 and Color3.fromRGB(120, 82, 54) or Color3.fromRGB(236, 232, 224)
					elseif p.Name == "Garage" then
						p.Material = Enum.Material.Metal
						p.Color = Color3.fromRGB(232, 230, 226)
					end
				end
			end
		end
	end
	return count
end

function Restyle.Warehouses(root)
	local count = 0
	for _, p in ipairs(root:GetDescendants()) do
		if p:IsA("BasePart") and p.Name == "Warehouse" and not p:GetAttribute("Restyled") then
			p:SetAttribute("Restyled", true)
			count += 1
			p.Color = p.Color:Lerp(Color3.fromRGB(150, 150, 150), 0.3)
			p.Material = Enum.Material.Metal
			-- Corrugated siding on the walls.
			for _, face in ipairs(SIDES) do
				local t = Instance.new("Texture")
				t.Name = "Siding"
				t.Face = face
				t.Texture = Textures.Corrugated
				t.StudsPerTileU = 2
				t.StudsPerTileV = p.Size.Y
				t.Parent = p
			end
			local s = p.Size
			local parent = p.Parent
			-- Roof edge trim.
			part(parent, "RoofTrim", Vector3.new(s.X + 0.6, 0.8, s.Z + 0.6), p.CFrame * CFrame.new(0, s.Y / 2 - 0.4, 0), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
			-- Roll-up doors along both long sides.
			local alongX = s.X >= s.Z
			local long = alongX and s.X or s.Z
			local depth = alongX and s.Z or s.X
			local doors = math.max(1, math.floor(long / 34))
			for side = -1, 1, 2 do
				for k = 1, doors do
					local u = -long / 2 + long * (k - 0.5) / doors
					local offset = alongX and CFrame.new(u, -s.Y / 2 + 7, side * (depth / 2 + 0.16)) or CFrame.new(side * (depth / 2 + 0.16), -s.Y / 2 + 7, u)
					local facing = alongX and (side > 0 and 0 or math.pi) or (side > 0 and math.pi / 2 or -math.pi / 2)
					local door = part(parent, "RollUpDoor", Vector3.new(12, 14, 0.3), p.CFrame * offset * CFrame.Angles(0, facing, 0), Color3.fromRGB(150, 154, 160), Enum.Material.Metal)
					local t = Instance.new("Texture")
					t.Face = Enum.NormalId.Back -- the outward face; Front sits flush against the wall
					t.Texture = Textures.RollUpDoor
					t.StudsPerTileU = 12
					t.StudsPerTileV = 14
					t.Parent = door
				end
			end
		end
	end
	return count
end

function Restyle.Ground(city)
	local count = 0
	local ground = city:FindFirstChild("Ground")
	for _, p in ipairs(ground and ground:GetChildren() or {}) do
		if p:IsA("BasePart") and not p:GetAttribute("Restyled") then
			p:SetAttribute("Restyled", true)
			count += 1
			if p.Material == Enum.Material.Concrete then
				p.Color = Color3.fromRGB(186, 184, 180)
				local t = Instance.new("Texture")
				t.Name = "Slabs"
				t.Face = Enum.NormalId.Top
				t.Texture = Textures.Slabs
				t.StudsPerTileU = 6
				t.StudsPerTileV = 6
				t.Parent = p
			elseif p.Material == Enum.Material.WoodPlanks and p.Size.X > 200 and p.Size.Z > 200 then
				-- A whole district of boardwalk looked odd: Marina Row gets warm stone paving instead
				-- (the piers keep their planks).
				p.Material = Enum.Material.Pavement
				p.Color = Color3.fromRGB(200, 186, 166)
			elseif p.Material == Enum.Material.Grass then
				p.Color = p.Color:Lerp(Color3.fromRGB(86, 122, 64), 0.5)
			end
		end
	end
	local roads = city:FindFirstChild("Roads")
	for _, p in ipairs(roads and roads:GetDescendants() or {}) do
		if p:IsA("BasePart") and p.Material == Enum.Material.Asphalt then
			p.Color = Color3.fromRGB(72, 72, 76)
		end
	end
	return count
end

------------------------------------------------------------------ streets

local ROAD_TOP = 0.1 -- top of every road surface (CityGen)
local STREET_W = 20 -- roads at least this wide get crosswalks, signals and kerbside props
local YELLOW = Color3.fromRGB(240, 196, 44)
local POLE = Color3.fromRGB(58, 60, 66)

-- Folders the props and infill must keep clear of, plus the run-time lots nothing can see in Studio.
local function blockers(city)
	local list = { city:FindFirstChild("Art"), city:FindFirstChild("Landmarks"), city:FindFirstChild("Walls"),
		Workspace:FindFirstChild("Heists"), Workspace:FindFirstChild("Spawns"), Workspace:FindFirstChild("Activities") }
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = list
	return op
end

-- Keep in step with ArtGen's runtime lots (Layout.IsFree).
local RUNTIME_LOTS = {
	{ -210, -90, -543, -457 }, -- AutoNeon Motors
	{ 1668, 1700, 975, 1110 }, -- Marina Boat Sales (showcase dock reaches ~z 982 with 4 boats)
	{ -278, -218, -354, -306 }, -- Zap Shack (CombatService)
	{ 545, 695, 725, 835 }, -- Car Meet lot (CarMeetService, centre 620, 780)
	{ 537, 583, 617, 663 }, -- Courier Depot (JobService, 560, 640)
}
local function runtimeLots()
	local lots = table.clone(RUNTIME_LOTS)
	local ok, Housing = pcall(require, ReplicatedStorage.Shared.Config.Housing:Clone())
	for _, h in ipairs(ok and Housing.List or {}) do
		table.insert(lots, { h.Position.X - 62, h.Position.X + 62, h.Position.Z - 62, h.Position.Z + 62 })
	end
	return lots
end
-- runtimeLots() plus a 20-stud margin around every gameplay pad (Heists, Spawns, Activities). Those
-- pads are CanQuery = false, so an overlap query can't see them; players need room around them.
local function gameplayLots()
	local lots = runtimeLots()
	for _, name in ipairs({ "Heists", "Spawns", "Activities" }) do
		local f = Workspace:FindFirstChild(name)
		for _, p in ipairs(f and f:GetDescendants() or {}) do
			if p:IsA("BasePart") then
				table.insert(lots, { p.Position.X - p.Size.X / 2 - 20, p.Position.X + p.Size.X / 2 + 20, p.Position.Z - p.Size.Z / 2 - 20, p.Position.Z + p.Size.Z / 2 + 20 })
			end
		end
	end
	return lots
end

local function inLots(lots, x, z, r)
	for _, l in ipairs(lots) do
		if x + r > l[1] and x - r < l[2] and z + r > l[3] and z - r < l[4] then
			return true
		end
	end
	return false
end

local function groundAt(city, x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { city:FindFirstChild("Ground"), city:FindFirstChild("Roads"), Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -120, 0), params)
	return hit and hit.Instance:IsDescendantOf(city.Ground) and hit or nil
end

-- Street furniture only belongs in town: downtown, the marina, the docks, the suburbs and the beach
-- road. Out in the Glades a traffic light or a hydrant looks silly. (CityGen.Districts rects.)
local URBAN = { SolanaHeights = true, MarinaRow = true, RustwaterDocks = true, PalmHills = true, FlamingoBeach = true }
local urbanRects
local function isUrban(x, z)
	if not urbanRects then
		urbanRects = {}
		local ok, CityGen = pcall(require, game:GetService("ServerStorage").Tools.CityGen:Clone())
		for _, d in ipairs(ok and CityGen.Districts or {}) do
			if URBAN[d.Name] then
				table.insert(urbanRects, d.Rect)
			end
		end
	end
	for _, r in ipairs(urbanRects) do
		if x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] then
			return true
		end
	end
	return false
end

local function crosswalk(folder, c, dir, w)
	local cw = part(folder, "Crosswalk", Vector3.new(w - 3, 0.05, 6), CFrame.lookAt(c, c + dir) + Vector3.new(0, ROAD_TOP + 0.02 - c.Y, 0),
		Color3.fromRGB(72, 72, 76), Enum.Material.Asphalt)
	cw.Transparency = 1 -- only the stripes show
	local t = Instance.new("Texture")
	t.Name = "Zebra"
	t.Face = Enum.NormalId.Top
	t.Texture = Textures.Zebra
	t.StudsPerTileU = 2.4
	t.StudsPerTileV = 6
	t.Parent = cw
end

-- A signal on the driver's right before the junction, its arm reaching over the lanes.
local function signal(folder, base, dir, w, green)
	local right = (-dir):Cross(Vector3.yAxis)
	local m = Instance.new("Model")
	m.Name = "TrafficSignal"
	m.Parent = folder
	local p = base + right * (w / 2 + 2.5)
	local pole = part(m, "Pole", Vector3.new(0.9, 17, 0.9), CFrame.new(p.X, 8.5, p.Z), POLE, Enum.Material.Metal)
	pole.CanCollide = true
	pole.CanQuery = true
	pole.CastShadow = true
	local reach = w / 2 + 1
	local tip = Vector3.new(p.X, 16.6, p.Z) - right * reach
	part(m, "Arm", Vector3.new(0.5, 0.5, reach), CFrame.lookAt(Vector3.new(p.X, 16.6, p.Z), tip) * CFrame.new(0, 0, -reach / 2), POLE, Enum.Material.Metal)
	local headCf = CFrame.lookAt(tip - Vector3.new(0, 1.9, 0), tip - Vector3.new(0, 1.9, 0) + dir)
	part(m, "Head", Vector3.new(1.3, 3.4, 1.1), headCf, Color3.fromRGB(24, 24, 28), Enum.Material.Metal)
	local lamps = { { 1.05, Color3.fromRGB(255, 40, 40), not green }, { 0, Color3.fromRGB(255, 176, 0), false }, { -1.05, Color3.fromRGB(40, 255, 110), green } }
	for _, l in ipairs(lamps) do
		local lamp = part(m, "Lamp", Vector3.new(0.8, 0.8, 0.2), headCf * CFrame.new(0, l[1], -0.62), l[3] and l[2] or l[2]:Lerp(Color3.new(0, 0, 0), 0.75),
			l[3] and Enum.Material.Neon or Enum.Material.SmoothPlastic)
		lamp:SetAttribute("Colour", l[1] > 0.5 and "Red" or l[1] < -0.5 and "Green" or "Amber")
	end
	m:SetAttribute("Axis", math.abs(dir.X) > math.abs(dir.Z) and "X" or "Z")
	return m
end

local PROPS = {
	function(folder, cf) -- fire hydrant
		local m = Instance.new("Model")
		m.Name = "Hydrant"
		m.Parent = folder
		local body = part(m, "Body", Vector3.new(2.2, 1.1, 1.1), cf * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(196, 38, 38), Enum.Material.Metal)
		body.Shape = Enum.PartType.Cylinder
		body.CanCollide = true
		part(m, "Cap", Vector3.new(0.6, 1.4, 0.6), cf * CFrame.new(0, 1.6, 0), Color3.fromRGB(220, 200, 60), Enum.Material.Metal)
	end,
	function(folder, cf) -- trash can
		local m = Instance.new("Model")
		m.Name = "TrashCan"
		m.Parent = folder
		local can = part(m, "Can", Vector3.new(3, 1.8, 1.8), cf * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(46, 70, 58), Enum.Material.Metal)
		can.Shape = Enum.PartType.Cylinder
		can.CanCollide = true
		part(m, "Lid", Vector3.new(2, 0.3, 2), cf * CFrame.new(0, 3.1, 0), Color3.fromRGB(36, 54, 46), Enum.Material.Metal)
	end,
	function(folder, cf) -- newspaper box
		local b = part(folder, "NewsBox", Vector3.new(1.8, 3.2, 1.6), cf * CFrame.new(0, 1.6, 0), Color3.fromRGB(34, 88, 170), Enum.Material.Metal)
		b.CanCollide = true
	end,
	function(folder, cf) -- bench facing the road
		local m = Instance.new("Model")
		m.Name = "Bench"
		m.Parent = folder
		part(m, "Seat", Vector3.new(6, 0.4, 2), cf * CFrame.new(0, 1.6, 0), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks).CanCollide = true
		part(m, "Back", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.6, 1), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
		for _, x in ipairs({ -2.6, 2.6 }) do
			part(m, "Leg", Vector3.new(0.4, 1.4, 1.8), cf * CFrame.new(x, 0.7, 0), POLE, Enum.Material.Metal)
		end
	end,
}

-- Crosswalks and signals at crossings, kerbside props along city streets, yellow centre lines.
function Restyle.Streets(city)
	local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph:Clone())
	RoadGraph.BuildFromWorld()
	local art = city:FindFirstChild("Art")
	local old = art:FindFirstChild("StreetDetails")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "StreetDetails"
	folder.Parent = art
	local op = blockers(city)
	local lots = runtimeLots()
	local crossings, signals, props = 0, 0, 0
	local junctionR = {} -- [node] = half size of its junction box
	for i, node in ipairs(RoadGraph.Nodes) do
		local n, widest = 0, 0
		for j in pairs(RoadGraph.Edges[i]) do
			n += 1
			widest = math.max(widest, RoadGraph.Width(i, j))
		end
		junctionR[i] = n >= 3 and widest / 2 or 0
		if n >= 3 and isUrban(node.X, node.Z) then
			crossings += 1
			for j in pairs(RoadGraph.Edges[i]) do
				local w = RoadGraph.Width(i, j)
				local d = RoadGraph.Nodes[j] - node
				local len = d.Magnitude
				local dir = Vector3.new(d.X, 0, d.Z).Unit
				if w >= STREET_W and len > widest + 24 then
					local c = node + dir * (widest / 2 + 4)
					crosswalk(folder, c, dir, w)
					-- The pole stands on the driver's right; check that spot (street lights, corner
					-- buildings, reserved lots), and try once a little further back before giving up.
					for _, back in ipairs({ 8, 12 }) do
						local s = node + dir * (widest / 2 + back)
						local pole = s + (-dir):Cross(Vector3.yAxis) * (w / 2 + 2.5)
						if not inLots(lots, pole.X, pole.Z, 3)
							and #Workspace:GetPartBoundsInBox(CFrame.new(pole.X, 8.5, pole.Z), Vector3.new(4, 17, 4), op) == 0 then
							signal(folder, s, dir, w, math.abs(dir.X) > math.abs(dir.Z))
							signals += 1
							break
						end
					end
				end
			end
		end
	end
	-- Kerbside props every ~70 studs on both sides of each city street, clear of junctions.
	local k = 0
	for i, node in ipairs(RoadGraph.Nodes) do
		for j in pairs(RoadGraph.Edges[i]) do
			local w = RoadGraph.Width(i, j)
			if i < j and w >= STREET_W then
				local d = RoadGraph.Nodes[j] - node
				local len = d.Magnitude
				local dir = Vector3.new(d.X, 0, d.Z).Unit
				local right = Vector3.new(-dir.Z, 0, dir.X)
				local t = junctionR[i] + 14
				while t < len - junctionR[j] - 14 do
					for _, side in ipairs({ -1, 1 }) do
						local p = node + dir * t + right * side * (w / 2 + 2)
						if isUrban(p.X, p.Z) and groundAt(city, p.X, p.Z) and not inLots(lots, p.X, p.Z, 3)
							and #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 4, p.Z), Vector3.new(4, 8, 4), op) == 0 then
							k += 1
							local cf = CFrame.lookAt(Vector3.new(p.X, 0, p.Z), Vector3.new(p.X, 0, p.Z) - right * side)
							PROPS[k % #PROPS + 1](folder, cf)
							props += 1
						end
					end
					t += 70
				end
			end
		end
	end
	-- Yellow centre lines (they were white, which reads as a lane divider, not a two-way street).
	for _, l in ipairs(art:GetDescendants()) do
		if l:IsA("BasePart") and l.Name == "Line" then
			l.Color = YELLOW
		end
	end
	return string.format("%d crossings, %d signals, %d kerbside props", crossings, signals, props)
end

------------------------------------------------------------------ infill

-- Fill empty frontage along city streets with Deco buildings (then restyled like the rest), so the
-- downtown blocks stop looking like empty car parks. rects = { {x0, x1, z0, z1, hMin, hMax}, ... }.
Restyle.InfillAreas = {
	{ -900, 1000, -850, 600, 40, 150 }, -- Solana Heights (downtown)
	{ 450, 1500, 600, 2000, 24, 60 }, -- Marina Row
}

function Restyle.Infill(city, areas)
	areas = areas or Restyle.InfillAreas
	local ArtKit = require(game:GetService("ServerStorage").Tools.ArtKit:Clone())
	local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph:Clone())
	RoadGraph.BuildFromWorld()
	local art = city:FindFirstChild("Art")
	local folder = art:FindFirstChild("Infill")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Infill"
	folder.Parent = art
	local op = blockers(city)
	local roadOp = OverlapParams.new()
	roadOp.FilterType = Enum.RaycastFilterType.Include
	roadOp.FilterDescendantsInstances = { city:FindFirstChild("Roads") }
	local lots = gameplayLots() -- keep room around heist fronts, pads and activities
	local function areaOf(x, z)
		for _, a in ipairs(areas) do
			if x >= a[1] and x <= a[2] and z >= a[3] and z <= a[4] then
				return a
			end
		end
		return nil
	end
	local built = 0
	for i, node in ipairs(RoadGraph.Nodes) do
		for j in pairs(RoadGraph.Edges[i]) do
			local w = RoadGraph.Width(i, j)
			if i < j and w >= STREET_W then
				local d = RoadGraph.Nodes[j] - node
				local len = d.Magnitude
				local dir = Vector3.new(d.X, 0, d.Z).Unit
				local right = Vector3.new(-dir.Z, 0, dir.X)
				for _, side in ipairs({ -1, 1 }) do
					local t = 40
					while t < len - 40 do
						local bw = rng:NextInteger(30, 48) -- along the street
						local bd = rng:NextInteger(28, 42) -- depth
						local setback = w / 2 + 10 -- sidewalk + the pedestrians' path
						local c = node + dir * (t + bw / 2) + right * side * (setback + bd / 2)
						local area = areaOf(c.X, c.Z)
						local look = -right * side -- the front faces the street
						local cf = CFrame.lookAt(Vector3.new(c.X, 0, c.Z), Vector3.new(c.X, 0, c.Z) + look)
						local boxCf = cf * CFrame.new(0, 40, 0)
						local boxSize = Vector3.new(bw + 6, 80, bd + 6)
						local ok = area ~= nil and groundAt(city, c.X, c.Z) ~= nil and not inLots(lots, c.X, c.Z, math.max(bw, bd) / 2 + 2)
							and #Workspace:GetPartBoundsInBox(boxCf, boxSize, op) == 0
							and #Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 2, 0), Vector3.new(bw + 2, 4, bd + 2), roadOp) == 0
						if ok then
							local h = rng:NextInteger(area[5], area[6])
							ArtKit.Deco(folder, cf, bw, h, bd, { Tiers = h > 90 and 3 or (h > 55 and 2 or 1), Awning = h < 90 })
							built += 1
							t += bw + rng:NextInteger(6, 14)
						else
							t += 12
						end
					end
				end
			end
		end
	end
	return string.format("%d infill buildings", built)
end

------------------------------------------------------------------ block fill

-- The middle of big blocks (away from the streets) was empty paving. Fill a grid of 64-stud cells
-- with low buildings, car parks (painted stalls, parked cars) and small parks, wherever a cell is free.
Restyle.BlockAreas = {
	{ -900, 1000, -850, 600, 30, 90 }, -- Solana Heights
	{ 450, 1500, 600, 2000, 20, 48 }, -- Marina Row
}
local CAR_COLOURS = {
	Color3.fromRGB(220, 220, 224), Color3.fromRGB(40, 42, 48), Color3.fromRGB(150, 24, 40), Color3.fromRGB(34, 70, 140),
	Color3.fromRGB(190, 190, 196), Color3.fromRGB(110, 242, 196), Color3.fromRGB(255, 214, 170),
}

local function carPark(folder, cf, w, d)
	local m = Instance.new("Model")
	m.Name = "CarPark"
	m.Parent = folder
	local lot = part(m, "Lot", Vector3.new(w, 0.2, d), cf * CFrame.new(0, 0.12, 0), Color3.fromRGB(66, 66, 70), Enum.Material.Asphalt)
	lot.CanCollide = true
	lot.CanQuery = true
	local models = ReplicatedStorage:FindFirstChild("TrafficModels")
	local list = models and models:GetChildren() or {}
	-- Two rows of 9-stud stalls facing a middle aisle.
	local stalls = math.floor((w - 4) / 9)
	for row = -1, 1, 2 do
		for i = 1, stalls do
			local x = -w / 2 + 2 + (i - 0.5) * 9
			local z = row * (d / 2 - 8)
			part(m, "Stall", Vector3.new(0.3, 0.05, 12), cf * CFrame.new(x - 4.5, 0.24, z), Color3.fromRGB(230, 230, 224))
			if #list > 0 and rng:NextNumber() < 0.55 then
				local car = list[rng:NextInteger(1, #list)]:Clone()
				car:PivotTo(cf * CFrame.new(x, 0.22, z) * CFrame.Angles(0, row > 0 and math.pi or 0, 0))
				for _, p in ipairs(car:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Anchored = true
						p.CanTouch = false
						p.CastShadow = true
						if p.Name == "Body" or (p:IsA("MeshPart") and p.Size.Magnitude > 8 and p.Name ~= "Wheels") then
							p.Color = CAR_COLOURS[rng:NextInteger(1, #CAR_COLOURS)]
						end
					end
				end
				car.Parent = m
			end
		end
	end
	return m
end

local function park(folder, cf, w, d, ArtKit)
	local m = Instance.new("Model")
	m.Name = "PocketPark"
	m.Parent = folder
	part(m, "Lawn", Vector3.new(w, 0.3, d), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(86, 128, 64), Enum.Material.Grass).CanCollide = true
	part(m, "Path", Vector3.new(4, 0.32, d), cf * CFrame.new(0, 0.12, 0), Color3.fromRGB(210, 200, 184), Enum.Material.Pavement)
	for _ = 1, rng:NextInteger(3, 6) do
		local p = cf * CFrame.new(rng:NextNumber(-w / 2 + 5, w / 2 - 5), 0.25, rng:NextNumber(-d / 2 + 5, d / 2 - 5))
		if math.abs(cf:PointToObjectSpace(p.Position).X) > 4 then
			ArtKit.Palm(m, p.Position, rng:NextNumber(0.8, 1.2))
		end
	end
	for _, z in ipairs({ -d / 4, d / 4 }) do
		PROPS[4](m, cf * CFrame.new(5, 0.25, z) * CFrame.Angles(0, math.pi / 2, 0))
	end
	return m
end

function Restyle.BlockFill(city, areas)
	areas = areas or Restyle.BlockAreas
	local ArtKit = require(game:GetService("ServerStorage").Tools.ArtKit:Clone())
	local art = city:FindFirstChild("Art")
	local folder = art:FindFirstChild("BlockFill")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "BlockFill"
	folder.Parent = art
	local op = blockers(city)
	local roadOp = OverlapParams.new()
	roadOp.FilterType = Enum.RaycastFilterType.Include
	roadOp.FilterDescendantsInstances = { city:FindFirstChild("Roads") }
	local lots = gameplayLots()
	local counts = { building = 0, carpark = 0, park = 0 }
	local CELL = 64
	for _, a in ipairs(areas) do
		for x = a[1] + CELL / 2, a[2] - CELL / 2, CELL do
			for z = a[3] + CELL / 2, a[4] - CELL / 2, CELL do
				local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, (rng:NextInteger(0, 3)) * math.pi / 2, 0)
				local free = groundAt(city, x, z) ~= nil and not inLots(lots, x, z, CELL / 2)
					and #Workspace:GetPartBoundsInBox(CFrame.new(x, 40, z), Vector3.new(CELL - 4, 80, CELL - 4), op) == 0
					-- keep 8 studs of pavement next to any road
					and #Workspace:GetPartBoundsInBox(CFrame.new(x, 1, z), Vector3.new(CELL + 12, 4, CELL + 12), roadOp) == 0
				if free then
					local roll = rng:NextNumber()
					if roll < 0.62 then
						local w, d = rng:NextInteger(36, 52), rng:NextInteger(36, 52)
						ArtKit.Deco(folder, cf, w, rng:NextInteger(a[5], a[6]), d, { Awning = false })
						counts.building += 1
					elseif roll < 0.84 then
						carPark(folder, cf, 54, 44)
						counts.carpark += 1
					else
						park(folder, cf, 54, 54, ArtKit)
						counts.park += 1
					end
				end
			end
		end
	end
	return string.format("block fill: %d buildings, %d car parks, %d parks", counts.building, counts.carpark, counts.park)
end

------------------------------------------------------------------ Glades nature

-- The Glades were flat lawn. Scatter swamp pools (flat dark water parts with lily pads),
-- cypress trees and sawgrass tufts, clear of roads, trails and everything built.
local GLADES = { GatorGlades = true, GladesSouthWest = true, GladesSouthEast = true, GladesSouth = true }
local CYPRESS_BARK = Color3.fromRGB(112, 98, 82)
local CYPRESS_LEAF = { Color3.fromRGB(54, 84, 52), Color3.fromRGB(66, 96, 58), Color3.fromRGB(48, 74, 50) }
local SAWGRASS = Color3.fromRGB(150, 150, 86)

local function cypress(folder, pos)
	local m = Instance.new("Model")
	m.Name = "Cypress"
	m.Parent = folder
	local h = rng:NextNumber(14, 24)
	local lean = CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.06, 0.06))
	local base = CFrame.new(pos) * lean
	local trunk = part(m, "Trunk", Vector3.new(h, 1.8, 1.8), base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), CYPRESS_BARK, Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CanCollide = true
	trunk.CanQuery = true
	trunk.CastShadow = true
	local foot = part(m, "Buttress", Vector3.new(2, 3, 3), base * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)), CYPRESS_BARK, Enum.Material.Wood)
	foot.Shape = Enum.PartType.Cylinder
	for k = 1, rng:NextInteger(3, 4) do
		-- Flat, wide canopy layers: an ellipsoid (a Ball part is always a perfect sphere, so a sphere
		-- SpecialMesh stretched to the part's size instead).
		local s = rng:NextNumber(9, 15) * (1 - k * 0.12)
		local blob = part(m, "Canopy", Vector3.new(s, s * 0.42, s), base * CFrame.new(rng:NextNumber(-2.5, 2.5), h - 5 + k * 2.4, rng:NextNumber(-2.5, 2.5)),
			CYPRESS_LEAF[rng:NextInteger(1, #CYPRESS_LEAF)], Enum.Material.Grass)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = blob
		blob.CastShadow = true
	end
end

local function sawgrass(folder, pos)
	local m = Instance.new("Model")
	m.Name = "Sawgrass"
	m.Parent = folder
	for k = 1, 3 do
		local h = rng:NextNumber(2.5, 4.5)
		local w = Instance.new("WedgePart")
		w.Name = "Blade"
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.CanQuery = false
		w.CastShadow = false
		w.Size = Vector3.new(0.2, h, 2.2)
		w.CFrame = CFrame.new(pos) * CFrame.Angles(0, k * 2.1 + rng:NextNumber(), 0) * CFrame.new(0, h / 2, 0)
		w.Color = SAWGRASS:Lerp(Color3.fromRGB(90, 110, 60), rng:NextNumber(0, 0.6))
		w.Material = Enum.Material.Grass
		w.Parent = m
	end
end

-- A still, dark swamp pool: a few overlapping flat discs (terrain water can't sit on the ground parts
-- without flickering) with a muddy rim and some lily pads. Players and cars pass over it.
local POOL = Color3.fromRGB(40, 56, 44) -- murky swamp green-brown
local function swampPool(folder, x, z, sx, sz)
	local m = Instance.new("Model")
	m.Name = "SwampPool"
	m.Parent = folder
	local yaw = rng:NextNumber(0, math.pi)
	for k = 1, 3 do
		local ox, oz = rng:NextNumber(-sx * 0.2, sx * 0.2), rng:NextNumber(-sz * 0.2, sz * 0.2)
		local w, d = sx * rng:NextNumber(0.55, 0.8), sz * rng:NextNumber(0.55, 0.8)
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0) * CFrame.new(ox, 0, oz)
		local rim = part(m, "Mud", Vector3.new(0.12, w + 5, d + 5), cf * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(92, 78, 58), Enum.Material.Mud)
		rim.Shape = Enum.PartType.Cylinder
		local water = part(m, "Water", Vector3.new(0.12, w, d), cf * CFrame.new(0, 0.08 + k * 0.004, 0) * CFrame.Angles(0, 0, math.rad(90)),
			POOL, Enum.Material.SmoothPlastic)
		water.Shape = Enum.PartType.Cylinder
		water.Reflectance = 0.18 -- a still-water sheen (Glass reflected the sky as cartoon blue)
		for _ = 1, rng:NextInteger(2, 5) do
			local p = cf * CFrame.new(rng:NextNumber(-w * 0.35, w * 0.35), 0.16, rng:NextNumber(-d * 0.35, d * 0.35))
			local pad = part(m, "LilyPad", Vector3.new(0.06, 2.2, 2.2), p * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 128, 60), Enum.Material.Grass)
			pad.Shape = Enum.PartType.Cylinder
		end
	end
end

function Restyle.Nature(city)
	local ok, CityGen = pcall(require, game:GetService("ServerStorage").Tools.CityGen:Clone())
	if not ok then
		return "no CityGen"
	end
	local art = city:FindFirstChild("Art")
	local folder = art:FindFirstChild("GladesNature")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "GladesNature"
	folder.Parent = art
	local op = blockers(city)
	local roadOp = OverlapParams.new()
	roadOp.FilterType = Enum.RaycastFilterType.Include
	roadOp.FilterDescendantsInstances = { city:FindFirstChild("Roads") }
	local lots = gameplayLots()
	-- Stunt jumps: keep the run-up, the flight and the landing clear (a trunk mid-air ruins the jump).
	local okA, Activities = pcall(require, ReplicatedStorage.Shared.Config.Activities:Clone())
	for _, st in ipairs(okA and Activities.Stunts or {}) do
		local t = st.Travel.Unit
		local a = st.Ramp - t * 120 -- run-up behind the ramp
		local b = st.Ramp + t * ((st.MinDist or 60) + 70) -- lip, flight and landing
		table.insert(lots, { math.min(a.X, b.X) - 12, math.max(a.X, b.X) + 12, math.min(a.Z, b.Z) - 12, math.max(a.Z, b.Z) + 12 })
	end
	local counts = { pools = 0, trees = 0, grass = 0 }
	local function clear(x, z, r, roadMargin)
		return groundAt(city, x, z) ~= nil and not inLots(lots, x, z, r)
			and #Workspace:GetPartBoundsInBox(CFrame.new(x, 10, z), Vector3.new(r * 2, 20, r * 2), op) == 0
			and #Workspace:GetPartBoundsInBox(CFrame.new(x, 1, z), Vector3.new(r * 2 + roadMargin, 4, r * 2 + roadMargin), roadOp) == 0
	end
	for _, d in ipairs(CityGen.Districts) do
		if GLADES[d.Name] then
			local r = d.Rect
			local area = (r[2] - r[1]) * (r[4] - r[3])
			-- Pools first (trees then avoid them: pool parts are CanQuery off, so the blocker check can't see them).
			local pools = {}
			for _ = 1, math.floor(area / 60000) do
				local x, z = rng:NextNumber(r[1] + 40, r[2] - 40), rng:NextNumber(r[3] + 40, r[4] - 40)
				local sx, sz = rng:NextNumber(30, 90), rng:NextNumber(30, 90)
				if clear(x, z, math.max(sx, sz) / 2, 24) then
					swampPool(folder, x, z, sx, sz)
					table.insert(pools, { x, z, math.max(sx, sz) / 2 + 4 })
					counts.pools += 1
				end
			end
			local function wet(x, z)
				for _, p in ipairs(pools) do
					if (Vector2.new(x, z) - Vector2.new(p[1], p[2])).Magnitude < p[3] then
						return true
					end
				end
				return false
			end
			for _ = 1, math.floor(area / 14000) do
				local x, z = rng:NextNumber(r[1] + 10, r[2] - 10), rng:NextNumber(r[3] + 10, r[4] - 10)
				if not wet(x, z) and clear(x, z, 4, 16) then
					cypress(folder, Vector3.new(x, 0, z))
					counts.trees += 1
				end
			end
			for _ = 1, math.floor(area / 12000) do
				local x, z = rng:NextNumber(r[1] + 6, r[2] - 6), rng:NextNumber(r[3] + 6, r[4] - 6)
				if clear(x, z, 2, 10) then
					sawgrass(folder, Vector3.new(x, 0, z))
					counts.grass += 1
				end
			end
		end
	end
	return string.format("glades: %d pools, %d cypress, %d sawgrass", counts.pools, counts.trees, counts.grass)
end

-- For other edit-time passes (Look3): the reserved lots and the test against them.
Restyle.GameplayLots = gameplayLots
Restyle.InLots = inLots
Restyle.Blockers = blockers

function Restyle.Run(opts)
	opts = opts or {}
	local city = Workspace:FindFirstChild("City")
	if not city then
		return "no Workspace.City"
	end
	local art = city:FindFirstChild("Art") or city
	local lines = {}
	if opts.Infill then
		table.insert(lines, Restyle.Infill(city))
		table.insert(lines, Restyle.BlockFill(city))
	end
	local b = Restyle.Buildings(art)
	local h = Restyle.Houses(art)
	local w = Restyle.Warehouses(art)
	local g = Restyle.Ground(city)
	table.insert(lines, string.format("%d deco buildings, %d houses, %d warehouses, %d ground tiles", b, h, w, g))
	if opts.Streets then
		table.insert(lines, Restyle.Streets(city))
	end
	if opts.Nature then
		table.insert(lines, Restyle.Nature(city))
	end
	return "Restyle: " .. table.concat(lines, "; ")
end

return Restyle
