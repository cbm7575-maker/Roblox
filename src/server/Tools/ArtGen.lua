-- ArtGen (ModuleScript, ServerStorage.Tools.ArtGen). Studio-only: dresses the greybox city.
-- Run AFTER CityGen: require(game.ServerStorage.Tools.ArtGen:Clone()).Build()
--   1. Replaces every placeholder building with a styled one for its district
--      (downtown/beachfront: art deco towers and hotels; Palm Hills: houses; Docks: warehouses).
--   2. Street lights along the main roads and centre lines on every road.
--   3. Runs each district decoration module in ServerStorage.Tools.Art (Beach, DocksMarina,
--      GladesPrison, HeistFronts, ...), passing ArtKit and a Layout helper.
-- Everything goes into Workspace.City.Art (rebuilt from scratch each run).
--
-- Decoration modules: return { Build = function(folder, ArtKit, Layout) ... return partCount end }
-- Layout helpers (so props never land on roads, pads, heists, spawns or activities):
--   Layout.IsFree(position, radius)  -> true if nothing important is within radius (studs)
--   Layout.GroundY(x, z)             -> height of the ground/road surface there (or 0)
--   Layout.District(x, z)            -> district name from CityGen.Districts, or nil
--   Layout.Heist(name) / Layout.Spawn(name) -> the model in Workspace.Heists / Workspace.Spawns
--   Layout.Roads                     -> list of { a = Vector3, b = Vector3, width = number, name = string }

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- Fresh copies every run: this is a Studio edit-time tool, and a plain require would keep returning
-- whatever version was loaded first in the session.
local ArtKit = require(ServerStorage.Tools.ArtKit:Clone())
local CityGen = require(ServerStorage.Tools.CityGen:Clone())

local ArtGen = {}

local function districtAt(x, z)
	for _, d in ipairs(CityGen.Districts) do
		local r = d.Rect
		if x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] then
			return d.Name
		end
	end
	return nil
end

local function buildLayout()
	local city = Workspace.City
	local Layout = { Roads = {} }
	for _, part in ipairs(city.Roads:GetChildren()) do
		if part:IsA("BasePart") then
			local look = part.CFrame.LookVector * Vector3.new(1, 0, 1)
			look = look.Magnitude > 0 and look.Unit or Vector3.new(0, 0, 1)
			local half = (part.Size.Z - part.Size.X * 0.5) / 2
			local c = Vector3.new(part.Position.X, 0, part.Position.Z)
			table.insert(Layout.Roads, { a = c - look * half, b = c + look * half, width = part.Size.X, name = part.Name })
		end
	end
	local blockers = { city.Roads, Workspace.Heists, Workspace.Spawns, Workspace:FindFirstChild("Activities"), city:FindFirstChild("Landmarks") }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = blockers
	-- Gameplay pads are often CanQuery = false (spatial queries skip them), so every part in the
	-- gameplay folders is also kept as a flat box and checked directly.
	local reserved = {}
	for _, folder in ipairs({ Workspace.Heists, Workspace.Spawns, Workspace:FindFirstChild("Activities") }) do
		for _, p in ipairs(folder and folder:GetDescendants() or {}) do
			if p:IsA("BasePart") then
				local cf, s = p.CFrame, p.Size
				local ex = math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z
				local ez = math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
				table.insert(reserved, { x = cf.X, z = cf.Z, hx = ex / 2, hz = ez / 2 })
			end
		end
	end
	function Layout.IsFree(pos, radius)
		radius = radius or 6
		for _, r in ipairs(reserved) do
			if math.abs(pos.X - r.x) < r.hx + radius and math.abs(pos.Z - r.z) < r.hz + radius then
				return false
			end
		end
		local hits = Workspace:GetPartBoundsInBox(CFrame.new(pos.X, 5, pos.Z), Vector3.new(radius * 2, 20, radius * 2), overlap)
		return #hits == 0
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { city.Ground, city.Roads, Workspace.Terrain }
	function Layout.GroundY(x, z)
		local hit = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), groundParams)
		return hit and hit.Position.Y or 0
	end
	Layout.District = districtAt
	function Layout.Heist(name)
		return Workspace.Heists:FindFirstChild(name)
	end
	function Layout.Spawn(name)
		return Workspace.Spawns:FindFirstChild(name)
	end
	return Layout
end

-- Which way should a building in this lot face? Toward the nearest road.
local function facingToRoad(pos, Layout)
	local best, bestD
	for _, r in ipairs(Layout.Roads) do
		local ab = r.b - r.a
		local t = math.clamp((pos - r.a):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
		local p = r.a + ab * t
		local d = (Vector3.new(pos.X, 0, pos.Z) - p).Magnitude
		if not bestD or d < bestD then
			best, bestD = p, d
		end
	end
	if not best then
		return Vector3.new(0, 0, -1)
	end
	local dir = best - Vector3.new(pos.X, 0, pos.Z)
	-- Snap to the nearest axis so fronts line up with the street grid.
	if math.abs(dir.X) > math.abs(dir.Z) then
		return Vector3.new(math.sign(dir.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(dir.Z) ~= 0 and math.sign(dir.Z) or -1)
end

local HOTEL_NAMES = { "THE FLAMINGO", "SUNSET HOTEL", "CORAL CLUB", "NEON PALMS", "THE BREAKERS", "PARADISE INN", "OCEAN VIEW", "THE ESTELLE" }

local function replaceBuildings(art, Layout)
	local placeholders = Workspace.City:FindFirstChild("Buildings")
	if not placeholders then
		return 0
	end
	local count, hotels = 0, 0
	local out = Instance.new("Folder")
	out.Name = "Buildings"
	out.Parent = art
	-- Landmarks (Police HQ, prison...) keep their lots: skip placeholders that overlap one.
	local landmarks = {}
	local lm = Workspace.City:FindFirstChild("Landmarks")
	for _, p in ipairs(lm and lm:GetChildren() or {}) do
		if p:IsA("BasePart") and p.Size.X > 30 and p.Size.Z > 30 then
			table.insert(landmarks, p)
		end
	end
	local function onLandmark(pos, size)
		for _, p in ipairs(landmarks) do
			if math.abs(pos.X - p.Position.X) < (size.X + p.Size.X) / 2 and math.abs(pos.Z - p.Position.Z) < (size.Z + p.Size.Z) / 2 then
				return true
			end
		end
		return false
	end
	for _, b in ipairs(placeholders:GetChildren()) do
		if b:IsA("BasePart") and not onLandmark(b.Position, b.Size) then
			local pos, size = b.Position, b.Size
			local dist = districtAt(pos.X, pos.Z)
			local face = facingToRoad(pos, Layout)
			local cf = CFrame.lookAt(Vector3.new(pos.X, 0, pos.Z), Vector3.new(pos.X, 0, pos.Z) + face)
			-- Footprint in the building's own frame (swap width/depth when it faces east/west).
			local w, d = size.X, size.Z
			if math.abs(face.X) > 0.5 then
				w, d = size.Z, size.X
			end
			if dist == "SolanaHeights" then
				local beachfront = pos.X > 760
				local sign = nil
				if beachfront or (size.Y > 150 and hotels < #HOTEL_NAMES) then
					hotels += 1
					sign = HOTEL_NAMES[(hotels - 1) % #HOTEL_NAMES + 1]
				end
				ArtKit.Deco(out, cf, w, size.Y, d, { Sign = sign, Tiers = size.Y > 120 and 3 or (size.Y > 70 and 2 or 1) })
			elseif dist == "PalmHills" then
				-- Split the lot into two houses with a palm between them.
				local hw = math.min(w * 0.42, 40)
				local hd = math.min(d * 0.55, 34)
				for _, x in ipairs({ -w / 4, w / 4 }) do
					ArtKit.House(out, cf * CFrame.new(x, 0, -d / 2 + hd / 2 + 6), hw, hd)
				end
				ArtKit.Palm(out, (cf * CFrame.new(0, 0, -d / 2 + 4)).Position, 1.3)
			elseif dist == "RustwaterDocks" then
				local h = math.min(size.Y, 32)
				local wh = ArtKit.Part(out, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), ArtKit.Pick({ ArtKit.Colors.Rust, ArtKit.Colors.Steel, Color3.fromRGB(90, 110, 130) }),
					Enum.Material.Metal, { Shadow = true, Name = "Warehouse" })
				wh.Parent = out
				ArtKit.Part(out, Vector3.new(math.min(w * 0.4, 20), 14, 0.5), cf * CFrame.new(0, 7, -d / 2 - 0.3), Color3.fromRGB(60, 60, 66), Enum.Material.DiamondPlate,
					{ CanCollide = false, Name = "RollerDoor" })
				ArtKit.Neon(out, Vector3.new(math.min(w * 0.4, 20) + 1, 0.6, 0.6), cf * CFrame.new(0, 14.5, -d / 2 - 0.4), ArtKit.Colors.Neon.Orange)
			else
				ArtKit.Deco(out, cf, w, math.min(size.Y, 60), d, {})
			end
			count += 1
		end
	end
	-- Keep the placeholder footprints out of the world (but around, so ArtGen can be re-run).
	local stored = ServerStorage:FindFirstChild("CityPlaceholders")
	if stored then
		stored:Destroy()
	end
	placeholders.Name = "CityPlaceholders"
	placeholders.Parent = ServerStorage
	return count
end

local function streetDressing(art, Layout)
	local folder = Instance.new("Folder")
	folder.Name = "Streets"
	folder.Parent = art
	local lights = 0
	for _, r in ipairs(Layout.Roads) do
		local len = (r.b - r.a).Magnitude
		local dir = (r.b - r.a).Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local dirt = r.name == "GladesTrail"
		if not dirt and len > 20 then
			-- Centre line (double yellow on the highway, dashed-look white elsewhere)
			local mid = (r.a + r.b) / 2
			local cf = CFrame.lookAt(Vector3.new(mid.X, 0.16, mid.Z), Vector3.new(r.b.X, 0.16, r.b.Z))
			if r.name == "Highway1" or r.name == "Causeway" then
				for _, o in ipairs({ -0.8, 0.8 }) do
					ArtKit.Part(folder, Vector3.new(0.5, 0.05, len), cf * CFrame.new(o, 0, 0), ArtKit.Colors.Neon.Yellow, Enum.Material.SmoothPlastic,
						{ CanCollide = false, Name = "Line" })
				end
			elseif r.width >= 30 then
				ArtKit.Part(folder, Vector3.new(0.6, 0.05, len), cf, Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic, { CanCollide = false, Name = "Line" })
			end
			-- Street lights every 110 studs, alternating sides; one in three gets a real light.
			if r.width >= 30 and r.name ~= "Pier" and r.name ~= "FerrisPier" then
				local n = math.floor(len / 110)
				for i = 1, n do
					local s = (i % 2 == 0) and 1 or -1
					local p = r.a + dir * (i * 110 - 55) + side * s * (r.width / 2 + 3)
					if Layout.IsFree(p, 2) then
						local lookDir = -side * s
						ArtKit.StreetLight(folder, CFrame.lookAt(p, p + lookDir), lights % 3 == 0, ArtKit.PickNeon())
						lights += 1
					end
				end
			end
		end
	end
	return lights
end

function ArtGen.Build()
	local city = Workspace.City
	local old = city:FindFirstChild("Art")
	if old then
		old:Destroy()
	end
	-- Restore placeholders from a previous run so the replacement pass has footprints.
	local stored = ServerStorage:FindFirstChild("CityPlaceholders")
	if stored and not city:FindFirstChild("Buildings") then
		stored.Name = "Buildings"
		stored.Parent = city
	end
	ArtKit.ResetLights()
	local art = Instance.new("Folder")
	art.Name = "Art"
	art.Parent = city
	local Layout = buildLayout()
	local report = {}
	table.insert(report, "buildings: " .. replaceBuildings(art, Layout))
	table.insert(report, "street lights: " .. streetDressing(art, Layout))
	local modules = ServerStorage.Tools:FindFirstChild("Art")
	if modules then
		-- Order matters: HeistFronts builds real buildings and forecourts first, so the dressing
		-- modules after it can see them. Unknown modules run last, alphabetically.
		local ORDER = { HeistFronts = 1, GladesPrison = 2, DocksMarina = 3, Beach = 4, PalmHillsDowntown = 5 }
		local list = modules:GetChildren()
		table.sort(list, function(a, b)
			local ra, rb = ORDER[a.Name] or 99, ORDER[b.Name] or 99
			if ra ~= rb then
				return ra < rb
			end
			return a.Name < b.Name
		end)
		for _, m in ipairs(list) do
			if m:IsA("ModuleScript") then
				local folder = Instance.new("Folder")
				folder.Name = m.Name
				folder.Parent = art
				local ok, result = pcall(function()
					return require(m:Clone()).Build(folder, ArtKit, Layout)
				end)
				table.insert(report, m.Name .. ": " .. (ok and tostring(result) or ("ERROR " .. tostring(result))))
			end
		end
	end
	local parts = 0
	for _, d in ipairs(art:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	table.insert(report, "art parts total: " .. parts)
	return table.concat(report, "\n")
end

return ArtGen
