-- Look3 (ModuleScript, ServerStorage.Tools.Look3). Studio-only "Look 3.0" pass: Port Solana should read
-- like a real Florida city in a big open-world game, not a pastel toy town. Run after Restyle (through
-- tools/syncpack_run.lua):   require(Tools.Look3).Run()            every pass
--                             require(Tools.Look3).Palette(city)   one pass
-- Safe to run again: every pass recolours in place or rebuilds its own folder under City.Art.
--   * Palette: real wall colours and materials by district. Downtown: glass towers, concrete, brick and
--     stucco. Beach and marina: white and soft deco pastels. Palm Hills houses: stucco shades.
--   * Neon: building trims are dark metal by day and only glow at night (tag "NightNeon", attribute
--     NeonColor; SkyClient switches them). Street lamps are tagged "NightLamp" and each gets a
--     SpotLight; shopfronts are tagged "NightShop" (a warm light onto the sidewalk). Corner fins go.
--   * Roads: darker asphalt, raised kerbs with sidewalk slabs along city streets, dashed lane lines on
--     wide roads.
--   * Pads: the pink car pads and spawn pads become invisible; car pads get painted parking bays.
--   * StreetLife: palms along the kerbs, shop signs over the shopfronts, billboards, parked cars on
--     the avenues.
--   * Yards: Palm Hills houses get a driveway, a hedge, a tree or two and sometimes a parked car.
--   * Plazas: small lawns with palms and benches at each city spawn; loose palms on the big lawns.
--   * Landmarks: the hand-built places get stucco walls, night-only neon strips and clean sign fonts.
--   * Lighting: the edit-time defaults (WorldService drives the day at run time).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Textures = require(ReplicatedStorage.Shared.Config.Textures)

local Look3 = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Stable choice per building: the same building always gets the same colour, run after run.
local function hash(pos, salt)
	return math.abs(math.floor(pos.X * 7.3 + pos.Z * 13.7 + (salt or 0) * 31.1))
end
local function pick(list, pos, salt)
	return list[hash(pos, salt) % #list + 1]
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

local function freshFolder(art, name)
	local old = art:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = art
	return f
end

local districts
local function districtAt(x, z)
	if not districts then
		districts = require(ServerStorage.Tools.CityGen).Districts
	end
	for _, d in ipairs(districts) do
		local r = d.Rect
		if x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] then
			return d.Name
		end
	end
	return nil
end

------------------------------------------------------------------ palette

local GLASS = { rgb(56, 62, 68), rgb(64, 66, 64), rgb(48, 54, 62), rgb(72, 74, 76), rgb(60, 58, 56) }
local CONCRETE = { rgb(188, 186, 180), rgb(170, 170, 166), rgb(204, 198, 186), rgb(150, 152, 154), rgb(214, 210, 200) }
local BRICK = { rgb(146, 80, 62), rgb(126, 74, 60), rgb(160, 104, 78), rgb(110, 70, 58), rgb(176, 146, 116) }
local STUCCO = { rgb(226, 214, 190), rgb(214, 198, 172), rgb(236, 230, 218), rgb(204, 188, 160), rgb(222, 206, 186) }
local DECO = { -- beach and marina: mostly white with soft colour, like a real deco strip
	rgb(244, 240, 232), rgb(244, 240, 232), rgb(246, 226, 214), rgb(214, 234, 230), rgb(250, 236, 200),
	rgb(232, 222, 240), rgb(248, 214, 204), rgb(216, 232, 244),
}
local HOUSE = { rgb(232, 222, 200), rgb(214, 196, 170), rgb(240, 236, 228), rgb(222, 196, 168), rgb(200, 208, 198), rgb(208, 214, 224), rgb(236, 214, 188) }
local INDUSTRIAL = { rgb(120, 78, 64), rgb(138, 134, 128), rgb(104, 100, 98), rgb(150, 126, 104) }
local AWNING = { rgb(120, 32, 36), rgb(28, 52, 92), rgb(34, 78, 60), rgb(60, 60, 64), rgb(196, 150, 60), rgb(150, 84, 40) }
local TRIM_DAY = rgb(58, 60, 66) -- unlit neon tube / parapet cap
local GLASS_TINT = { rgb(150, 140, 120), rgb(120, 150, 145), rgb(140, 140, 146), rgb(105, 115, 135), rgb(170, 185, 200), rgb(160, 150, 140) }

local function wallLook(m, body)
	local pos = body.Position
	local district = districtAt(pos.X, pos.Z)
	local facadeTex = body:FindFirstChild("Facade")
	local office = facadeTex and facadeTex.Texture == Textures.Office
	local h = body.Size.Y
	if district == "FlamingoBeach" or district == "MarinaRow" or district == "LighthouseKey" then
		return pick(DECO, pos), Enum.Material.Plaster, 0
	elseif district == "RustwaterDocks" or district == "SaltmarshIsland" then
		local c = pick(INDUSTRIAL, pos)
		return c, (c.R > c.B * 1.25) and Enum.Material.Brick or Enum.Material.Concrete, 0
	elseif office then
		return pick(GLASS, pos), Enum.Material.Glass, 0.1
	elseif h > 80 then
		return pick(CONCRETE, pos), Enum.Material.Concrete, 0
	end
	local roll = hash(pos, 3) % 10
	if roll < 4 then
		return pick(BRICK, pos, 1), Enum.Material.Brick, 0
	elseif roll < 7 then
		return pick(STUCCO, pos, 1), Enum.Material.Plaster, 0
	end
	return pick(CONCRETE, pos, 1), Enum.Material.Concrete, 0
end

-- Is this neon part one of ArtKit.Deco's thin vertical corner fins?
local function isFin(p)
	return p.Size.Y > 8 and p.Size.X < 1.2 and p.Size.Z < 1.2
end

local function nightNeon(p)
	if p:GetAttribute("NeonColor") == nil then
		p:SetAttribute("NeonColor", p.Color)
	end
	CollectionService:AddTag(p, "NightNeon")
	p.Material = Enum.Material.Metal
	p.Color = TRIM_DAY
	for _, l in ipairs(p:GetChildren()) do
		if l:IsA("Light") then
			l.Enabled = false -- SkyClient turns these on at night
		end
	end
end

function Look3.Palette(city)
	local art = city:FindFirstChild("Art")
	local counts = { deco = 0, houses = 0, fins = 0, neon = 0, lamps = 0 }
	for _, m in ipairs(art:GetDescendants()) do
		if m:IsA("Model") and m.Name == "DecoBuilding" then
			local body = m:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				counts.deco += 1
				local color, material, reflect = wallLook(m, body)
				local district = districtAt(body.Position.X, body.Position.Z)
				local keepFins = district == "FlamingoBeach" or district == "MarinaRow"
				for _, p in ipairs(m:GetChildren()) do
					if p:IsA("BasePart") then
						if p.Name == "Body" or p.Name == "Tier" then
							p.Color = color
							p.Material = material
							p.Reflectance = reflect
							-- Office glass is drawn blue: tint it per tower (bronze, green, grey, blue) so the
							-- skyline isn't one colour.
							local tint = material == Enum.Material.Glass and pick(GLASS_TINT, body.Position, 7) or Color3.new(1, 1, 1)
							for _, t in ipairs(p:GetChildren()) do
								if t:IsA("Texture") and t.Name == "Facade" then
									t.Color3 = tint
								end
							end
						elseif p.Name == "Band" then
							-- Floor bands: stone on masonry, dark mullions on glass.
							p.Material = Enum.Material.Concrete
							p.Color = material == Enum.Material.Glass and rgb(40, 46, 54) or color:Lerp(rgb(236, 232, 224), 0.55)
						elseif p.Name == "Shopfront" then
							-- Shops are lit inside at night: warm light spills onto the sidewalk (SkyClient
							-- switches the light on after dark).
							p:SetAttribute("NeonColor", nil)
							CollectionService:AddTag(p, "NightShop")
							local light = p:FindFirstChild("ShopLight") or Instance.new("SurfaceLight")
							light.Name = "ShopLight"
							light.Face = Enum.NormalId.Front
							light.Angle = 120
							light.Range = 22
							light.Brightness = 1.4
							light.Color = rgb(255, 220, 176)
							light.Shadows = false
							light.Enabled = false
							light.Parent = p
						elseif p.Name == "Awning" then
							p.Material = Enum.Material.Fabric
							p.Color = pick(AWNING, p.Position, 5)
						elseif p.Name == "Neon" or p.Material == Enum.Material.Neon or p:GetAttribute("NeonColor") ~= nil then
							if p.Name == "Neon" and isFin(p) and not keepFins then
								p:Destroy()
								counts.fins += 1
							elseif p.Name == "Neon" then
								nightNeon(p)
								counts.neon += 1
							end
						end
					end
				end
			end
		elseif m:IsA("Model") and m.Name == "House" then
			local body = m:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				counts.houses += 1
				body.Color = pick(HOUSE, body.Position)
				body.Material = Enum.Material.Plaster
			end
		elseif m:IsA("Model") and m.Name == "StreetLight" then
			for _, p in ipairs(m:GetChildren()) do
				if p:IsA("BasePart") and (p.Material == Enum.Material.Neon or p:GetAttribute("LampColor") ~= nil) then
					counts.lamps += 1
					p:SetAttribute("LampColor", rgb(255, 214, 170)) -- warm white at night, whatever it was
					CollectionService:AddTag(p, "NightLamp")
					p.Material = Enum.Material.SmoothPlastic
					p.Color = rgb(226, 226, 220)
					-- Every lamp lights the street below it at night (SkyClient switches it on).
					for _, l in ipairs(p:GetChildren()) do
						if l:IsA("Light") then
							l:Destroy()
						end
					end
					local spot = Instance.new("SpotLight")
					spot.Name = "Lamp"
					spot.Face = Enum.NormalId.Bottom
					spot.Angle = 130
					spot.Range = 44
					spot.Brightness = 2.2
					spot.Color = rgb(255, 214, 170)
					spot.Shadows = false
					spot.Enabled = false
					spot.Parent = p
				end
			end
		end
	end
	-- Loose roof-line neon outside Deco models (the first art pass put "Neon" / "RoofTrim" parts straight
	-- into the Buildings folder).
	local buildings = art:FindFirstChild("Buildings")
	for _, p in ipairs(buildings and buildings:GetChildren() or {}) do
		if p:IsA("BasePart") and p.Name == "Neon" then
			nightNeon(p)
			counts.neon += 1
		end
	end
	return string.format("palette: %d deco buildings, %d houses, %d corner fins removed, %d night-neon trims, %d street lamps",
		counts.deco, counts.houses, counts.fins, counts.neon, counts.lamps)
end

------------------------------------------------------------------ roads

local ROAD_TOP = 0.1
local STREET_W = 20
local KERB_W = 8 -- sidewalk strip width
local KERB_TOP = 0.34 -- a low kerb: cars and walkers ride over it
local ASPHALT = rgb(54, 54, 58)
local SIDEWALK = rgb(176, 174, 168)
local URBAN = { SolanaHeights = true, MarinaRow = true, RustwaterDocks = true, PalmHills = true, FlamingoBeach = true }

function Look3.Roads(city)
	local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
	RoadGraph.BuildFromWorld()
	local art = city:FindFirstChild("Art")
	local folder = freshFolder(art, "RoadPaint")
	local roads = city:FindFirstChild("Roads")
	for _, p in ipairs(roads and roads:GetDescendants() or {}) do
		if p:IsA("BasePart") and p.Material == Enum.Material.Asphalt then
			p.Color = ASPHALT
		end
	end
	local roadOp = OverlapParams.new()
	roadOp.FilterType = Enum.RaycastFilterType.Include
	roadOp.FilterDescendantsInstances = { roads }
	local junctionR = {}
	for i in ipairs(RoadGraph.Nodes) do
		local n, widest = 0, 0
		for j in pairs(RoadGraph.Edges[i]) do
			n += 1
			widest = math.max(widest, RoadGraph.Width(i, j))
		end
		junctionR[i] = n >= 3 and widest / 2 or 0
	end
	local kerbs, dashes = 0, 0
	for i, node in ipairs(RoadGraph.Nodes) do
		for j in pairs(RoadGraph.Edges[i]) do
			local w = RoadGraph.Width(i, j)
			if i < j and w >= STREET_W then
				local other = RoadGraph.Nodes[j]
				local d = other - node
				local dir = Vector3.new(d.X, 0, d.Z)
				local len = dir.Magnitude
				dir = dir.Unit
				local right = Vector3.new(-dir.Z, 0, dir.X)
				local alongX = math.abs(dir.X) > 0.99
				local alongZ = math.abs(dir.Z) > 0.99
				local mid = (node + other) / 2
				local urban = URBAN[districtAt(mid.X, mid.Z) or ""] == true
				-- Kerbs: straight city streets only. Z-running streets own the corner squares; X-running
				-- streets stop short of them, so two strips never share a corner (no flicker).
				if urban and (alongX or alongZ) then
					local a = junctionR[i] + (alongX and KERB_W or 0)
					local b = len - junctionR[j] - (alongX and KERB_W or 0)
					if b - a > 6 then
						for _, side in ipairs({ -1, 1 }) do
							local c = node + dir * ((a + b) / 2) + right * side * (w / 2 + KERB_W / 2)
							local size = Vector3.new(KERB_W, KERB_TOP + 0.6, b - a)
							local cf = CFrame.lookAt(Vector3.new(c.X, KERB_TOP - size.Y / 2, c.Z), Vector3.new(c.X, KERB_TOP - size.Y / 2, c.Z) + dir)
							-- Not where another road runs through (a side street without a graph junction).
							if #Workspace:GetPartBoundsInBox(cf, Vector3.new(KERB_W - 1, 2, b - a - 2), roadOp) == 0 then
								local k = part(folder, "Kerb", size, cf, SIDEWALK, Enum.Material.Concrete)
								k.CanCollide = true
								k.CanQuery = true
								local t = Instance.new("Texture")
								t.Name = "Slabs"
								t.Face = Enum.NormalId.Top
								t.Texture = Textures.Slabs
								t.StudsPerTileU = 4
								t.StudsPerTileV = 4
								t.Parent = k
								kerbs += 1
							end
						end
					end
				end
				-- Lane dashes on wide roads (two lanes each way): at a quarter width either side.
				if w >= 50 then -- TrafficClient runs two lanes each way from this width
					local a = junctionR[i] + 10
					local b = len - junctionR[j] - 10
					if b - a > 20 then
						for _, side in ipairs({ -1, 1 }) do
							local c = node + dir * ((a + b) / 2) + right * side * (w * 0.245)
							local y = ROAD_TOP + 0.03
							-- The dash texture repeats along the part's X axis, so X runs along the road.
							local cf = CFrame.lookAt(Vector3.new(c.X, y, c.Z), Vector3.new(c.X, y, c.Z) + right)
							local dash = part(folder, "LaneDash", Vector3.new(b - a, 0.05, 0.6), cf, ASPHALT, Enum.Material.Asphalt)
							dash.Transparency = 1
							local t = Instance.new("Texture")
							t.Name = "Dash"
							t.Face = Enum.NormalId.Top
							t.Texture = Textures.Zebra
							t.StudsPerTileU = 14
							t.StudsPerTileV = 0.6
							t.Parent = dash
							dashes += 1
						end
					end
				end
			end
		end
	end
	return string.format("roads: %d kerb strips, %d dashed lane lines", kerbs, dashes)
end

------------------------------------------------------------------ pads

function Look3.Pads(city)
	local art = city:FindFirstChild("Art")
	local folder = freshFolder(art, "ParkingBays")
	local spawns = Workspace:FindFirstChild("Spawns")
	local bays, hidden = 0, 0
	local white = rgb(232, 232, 226)
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { city:FindFirstChild("Ground"), city:FindFirstChild("Roads") }
	for _, p in ipairs(spawns and spawns:GetChildren() or {}) do
		if p:IsA("BasePart") and p.Name == "CarPad" then
			p.Transparency = 1
			p.Material = Enum.Material.SmoothPlastic
			bays += 1
			local s = p.Size
			local y = 0.02
			-- On grass or sand the bay gets its own strip of asphalt.
			local under = Workspace:Raycast(p.Position + Vector3.new(0, 5, 0), Vector3.new(0, -12, 0), groundParams)
			if under and (under.Material == Enum.Material.Grass or under.Material == Enum.Material.Sand) then
				local slab = part(folder, "BaySlab", Vector3.new(s.X + 3, 0.16, s.Z + 3),
					CFrame.new(p.Position.X, under.Position.Y + 0.08, p.Position.Z) * p.CFrame.Rotation, ASPHALT, Enum.Material.Asphalt)
				slab.CanCollide = true
			end
			-- A painted bay: two long side lines and a short line at the back.
			for _, x in ipairs({ -s.X / 2, s.X / 2 }) do
				part(folder, "BayLine", Vector3.new(0.35, 0.05, s.Z), p.CFrame * CFrame.new(x, y, 0), white)
			end
			part(folder, "BayLine", Vector3.new(s.X + 0.35, 0.05, 0.35), p.CFrame * CFrame.new(0, y, s.Z / 2), white)
		elseif p:IsA("SpawnLocation") then
			p.Transparency = 1
			hidden += 1
			for _, d in ipairs(p:GetChildren()) do
				if d:IsA("Decal") then
					d.Transparency = 1
				end
			end
		end
	end
	return string.format("pads: %d parking bays painted, %d spawn pads hidden", bays, hidden)
end

------------------------------------------------------------------ lighting (edit-time defaults)

function Look3.Lighting()
	pcall(function()
		Lighting.LightingStyle = Enum.LightingStyle.Realistic
	end)
	Lighting.GeographicLatitude = 26
	Lighting.ShadowSoftness = 0.12
	Lighting.EnvironmentDiffuseScale = 0.75
	Lighting.EnvironmentSpecularScale = 1
	local old = Lighting:FindFirstChild("Bloom") -- the stock bloom: NeonBloom (WorldService) does the job
	if old and old:IsA("BloomEffect") then
		old.Enabled = false
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.SunAngularSize = 7 -- the stock 11 reads as a white dinner plate
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Intensity = 0.12
		rays.Spread = 0.55
	end
	return "lighting: realistic style, shadows, sun rays"
end

------------------------------------------------------------------ street life

local SHOPS = {
	"SOLANA PHARMACY", "COAST COFFEE", "GATOR GRILL", "PALM LAUNDRY", "TIKI TACOS", "NEON NAILS", "SUNSET PAWN",
	"MARLIN MARKET", "FLAMINGO FASHION", "BAYSIDE BOOKS", "OCEAN OPTICS", "MANGO JUICE BAR", "PORT PIZZA",
	"LUCKY LEMONADE", "CORAL DENTAL", "WAVE RECORDS", "PELICAN HARDWARE", "KEYS LOCKSMITH", "TROPIC TAN",
	"SOLANA GYM", "CAFE CUBANO", "24/7 MINI MART", "DOCKSIDE DINER", "BAIT & TACKLE", "SURF SHACK",
	"SANDBAR SPORTS", "PINK PALM MOTEL", "ISLAND ELECTRONICS", "SEA BREEZE SALON", "HIBISCUS FLOWERS",
	"CITRUS CYCLES", "GULF TRAVEL", "LA PLAYA BAKERY", "REEF PET SHOP", "SUNNY SIDE BREAKFAST", "COCONUT ICE CREAM",
	"HARBOR INSURANCE", "PALM TREE REALTY", "MOONLIGHT ARCADE", "BLUE HERON BANK", "STARFISH TOYS", "DRIFTWOOD FURNITURE",
}
local SIGN_STYLES = {
	{ Back = rgb(24, 26, 30), Text = rgb(245, 245, 240), Font = Enum.Font.Oswald },
	{ Back = rgb(150, 30, 34), Text = rgb(255, 240, 220), Font = Enum.Font.GothamBold },
	{ Back = rgb(24, 60, 110), Text = rgb(240, 245, 255), Font = Enum.Font.GothamBold },
	{ Back = rgb(236, 230, 214), Text = rgb(40, 40, 44), Font = Enum.Font.Oswald },
	{ Back = rgb(20, 84, 66), Text = rgb(250, 236, 190), Font = Enum.Font.Bangers },
	{ Back = rgb(250, 196, 40), Text = rgb(30, 30, 34), Font = Enum.Font.Oswald },
	{ Back = rgb(40, 40, 46), Text = rgb(255, 120, 190), Font = Enum.Font.Michroma },
}

local function textFace(p, face, text, color, font, brightness)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 0
	gui.Brightness = brightness or 1
	gui.MaxDistance = 320
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	gui.Parent = p
	return gui
end

local ADS = {
	{ "GATOR COLA", "Bite into summer.", rgb(190, 30, 40), rgb(255, 255, 255) },
	{ "PALM 99 FM", "Feel-good hits, all day.", rgb(250, 190, 40), rgb(30, 30, 34) },
	{ "NEON FM 101.9", "The sound of the coast at night.", rgb(40, 20, 70), rgb(255, 110, 200) },
	{ "AUTONEON MOTORS", "Your next ride is waiting.", rgb(20, 24, 30), rgb(110, 242, 196) },
	{ "FLAMINGO AIR", "Port Solana to anywhere.", rgb(250, 130, 170), rgb(255, 255, 255) },
	{ "SOLANA ZOO", "Somebody has to feed the gators.", rgb(24, 110, 70), rgb(250, 230, 120) },
	{ "TIKI TACOS", "Open late. Really late.", rgb(240, 110, 40), rgb(255, 250, 230) },
	{ "COASTAL BANK", "Your money is safe with us.", rgb(20, 50, 90), rgb(240, 240, 245) },
	{ "GATOR RADIO", "Slow jams for slow traffic.", rgb(40, 70, 50), rgb(230, 240, 200) },
	{ "MARINA BOAT SALES", "Leave the traffic behind.", rgb(30, 110, 150), rgb(255, 255, 255) },
	{ "COAST CAR WASH", "Shine like you mean it.", rgb(30, 30, 34), rgb(240, 200, 80) },
	{ "SUNNY SIDE HOMES", "Wake up to the beach.", rgb(250, 240, 220), rgb(200, 90, 60) },
}

local function billboard(folder, cf, ad)
	local m = Instance.new("Model")
	m.Name = "Billboard"
	m.Parent = folder
	for _, x in ipairs({ -9, 9 }) do
		local leg = part(m, "Leg", Vector3.new(1.2, 24, 1.2), cf * CFrame.new(x, 12, 0.4), rgb(70, 74, 80), Enum.Material.Metal)
		leg.CanCollide = true
		leg.CanQuery = true
		leg.CastShadow = true
	end
	local panel = part(m, "Panel", Vector3.new(36, 14, 0.8), cf * CFrame.new(0, 30, 0), ad[3], Enum.Material.SmoothPlastic)
	panel.CastShadow = true
	part(m, "Frame", Vector3.new(37, 15, 0.5), cf * CFrame.new(0, 30, 0.3), rgb(40, 42, 48), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ad"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 14
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.MaxDistance = 700
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.9, 0.5)
	title.Position = UDim2.fromScale(0.05, 0.1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Oswald
	title.TextScaled = true
	title.TextColor3 = ad[4]
	title.Text = ad[1]
	title.Parent = gui
	local line = Instance.new("TextLabel")
	line.Size = UDim2.fromScale(0.9, 0.22)
	line.Position = UDim2.fromScale(0.05, 0.66)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.GothamMedium
	line.TextScaled = true
	line.TextColor3 = ad[4]
	line.Text = ad[2]
	line.Parent = gui
	gui.Parent = panel
	return m
end

local CAR_PAINT = {
	rgb(220, 220, 224), rgb(40, 42, 48), rgb(150, 24, 40), rgb(34, 70, 140), rgb(190, 190, 196), rgb(120, 126, 132),
	rgb(236, 232, 220), rgb(30, 70, 60), rgb(180, 150, 90),
}
local function parkedCar(folder, cf, seed)
	local models = ReplicatedStorage:FindFirstChild("TrafficModels")
	local list = models and models:GetChildren() or {}
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	local car = list[seed % #list + 1]:Clone()
	car.Name = "ParkedCar"
	car:PivotTo(cf)
	local paint = CAR_PAINT[(seed * 7) % #CAR_PAINT + 1]
	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanTouch = false
			p.CastShadow = true
			if p.Name == "Body" or (p:IsA("MeshPart") and p.Size.Magnitude > 8 and p.Name ~= "Wheels") then
				p.Color = paint
			end
		end
	end
	car.Parent = folder
	return car
end

function Look3.StreetLife(city)
	local Restyle = require(ServerStorage.Tools.Restyle)
	local ArtKit = require(ServerStorage.Tools.ArtKit)
	local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
	RoadGraph.BuildFromWorld()
	local art = city:FindFirstChild("Art")
	local folder = freshFolder(art, "StreetLife")
	local op = Restyle.Blockers(city)
	local lots = Restyle.GameplayLots()
	local roads = city:FindFirstChild("Roads")
	local roadOp = OverlapParams.new()
	roadOp.FilterType = Enum.RaycastFilterType.Include
	roadOp.FilterDescendantsInstances = { roads }
	local counts = { palms = 0, signs = 0, boards = 0, cars = 0 }

	-- Shop signs over every shopfront (Restyle's "Shopfront" parts on Deco buildings).
	local k = 0
	for _, sf in ipairs(art:GetDescendants()) do
		if sf:IsA("BasePart") and sf.Name == "Shopfront" then
			for _, old in ipairs(sf.Parent:GetChildren()) do
				if old.Name == "ShopSign" then
					old:Destroy()
				end
			end
			-- One shop every ~28 studs of glass, each with its own sign.
			local shops = math.max(1, math.floor(sf.Size.X / 28))
			local each = sf.Size.X / shops
			for s = 1, shops do
				k += 1
				local x = -sf.Size.X / 2 + each * (s - 0.5)
				local style = SIGN_STYLES[(hash(sf.Position, 2) + s * 3) % #SIGN_STYLES + 1]
				local sign = part(sf.Parent, "ShopSign", Vector3.new(math.min(each - 4, 24), 2.6, 0.5), sf.CFrame * CFrame.new(x, sf.Size.Y / 2 + 1.5, -0.2),
					style.Back, Enum.Material.SmoothPlastic)
				textFace(sign, Enum.NormalId.Front, SHOPS[(hash(sf.Position, 9) + k * 5) % #SHOPS + 1], style.Text, style.Font)
				counts.signs += 1
			end
		end
	end

	local junctionR = {}
	for i in ipairs(RoadGraph.Nodes) do
		local n, widest = 0, 0
		for j in pairs(RoadGraph.Edges[i]) do
			n += 1
			widest = math.max(widest, RoadGraph.Width(i, j))
		end
		junctionR[i] = n >= 3 and widest / 2 or 0
	end
	local seed = 0
	local highway = 0 -- studs of highway since the last billboard
	for i, node in ipairs(RoadGraph.Nodes) do
		for j in pairs(RoadGraph.Edges[i]) do
			local w = RoadGraph.Width(i, j)
			if i < j and w >= STREET_W then
				local other = RoadGraph.Nodes[j]
				local d = other - node
				local dir = Vector3.new(d.X, 0, d.Z)
				local len = dir.Magnitude
				dir = dir.Unit
				local right = Vector3.new(-dir.Z, 0, dir.X)
				local mid = (node + other) / 2
				local district = districtAt(mid.X, mid.Z) or ""
				local urban = URBAN[district] == true
				local straight = math.abs(dir.X) > 0.99 or math.abs(dir.Z) > 0.99
				-- Palms along the outer edge of the kerb, every 56 studs, staggered left and right.
				if urban and straight then
					local t = junctionR[i] + 26
					local flip = false
					while t < len - junctionR[j] - 26 do
						for _, side in ipairs({ -1, 1 }) do
							local p = node + dir * (t + (flip == (side > 0) and 28 or 0)) + right * side * (w / 2 + KERB_W - 1.6)
							if not Restyle.InLots(lots, p.X, p.Z, 3)
								and #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 6, p.Z), Vector3.new(5, 10, 5), op) == 0
								and #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 1, p.Z), Vector3.new(3, 4, 3), roadOp) == 0 then
								local palm = ArtKit.Palm(folder, Vector3.new(p.X, KERB_TOP, p.Z), 0.85 + (hash(p, 4) % 40) / 100)
								if palm:IsA("BasePart") then
									palm.Name = "StreetPalm"
									palm.CanCollide = false
									palm.CanQuery = false
									palm.CastShadow = true
								end
								counts.palms += 1
							end
						end
						flip = not flip
						t += 56
					end
				end
				-- Parked cars along both edges of the avenues (44 wide: one driving lane each way leaves room).
				if urban and straight and w >= 42 and w < 50 then
					local t = junctionR[i] + 30
					while t < len - junctionR[j] - 30 do
						for _, side in ipairs({ -1, 1 }) do
							seed += 1
							if (seed * 37) % 100 < 42 then
								local p = node + dir * t + right * side * (w / 2 - 4)
								if not Restyle.InLots(lots, p.X, p.Z, 8)
									and #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 4, p.Z), Vector3.new(9, 6, 15), op) == 0 then
									-- Parked the way the traffic on that side drives.
									local facing = dir * side
									local cf = CFrame.lookAt(Vector3.new(p.X, ROAD_TOP + 0.02, p.Z), Vector3.new(p.X, ROAD_TOP + 0.02, p.Z) + facing)
									if parkedCar(folder, cf, seed) then
										counts.cars += 1
									end
								end
							end
						end
						t += 30
					end
				end
				-- Billboards beside the highway, one every ~450 studs of it, facing the oncoming lane.
				if w >= 56 then
					highway += len
				end
				if w >= 56 and highway > 450 then
					local c = node + dir * (len / 2)
					seed += 1
					do
						local side = (seed % 2 == 0) and 1 or -1
						local p = c + right * side * (w / 2 + 16)
						if not Restyle.InLots(lots, p.X, p.Z, 20)
							and #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 20, p.Z), Vector3.new(40, 40, 8), op) == 0
							and #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 1, p.Z), Vector3.new(38, 4, 6), roadOp) == 0
							and Workspace:Raycast(Vector3.new(p.X, 40, p.Z), Vector3.new(0, -60, 0)) ~= nil then
							-- The panel's front (-Z) looks back along the road at the drivers coming toward it.
							local cf = CFrame.lookAt(Vector3.new(p.X, 0, p.Z), Vector3.new(p.X, 0, p.Z) - dir * side)
							billboard(folder, cf, ADS[seed % #ADS + 1])
							counts.boards += 1
							highway = 0
						end
					end
				end
			end
		end
	end
	return string.format("street life: %d shop signs, %d palms, %d parked cars, %d billboards", counts.signs, counts.palms, counts.cars, counts.boards)
end

------------------------------------------------------------------ yards (Palm Hills)

local HEDGE = rgb(62, 104, 58)
local DRIVE = rgb(170, 166, 158)

function Look3.Yards(city)
	local Restyle = require(ServerStorage.Tools.Restyle)
	local ArtKit = require(ServerStorage.Tools.ArtKit)
	local art = city:FindFirstChild("Art")
	local folder = freshFolder(art, "Yards")
	local op = Restyle.Blockers(city)
	local lots = Restyle.GameplayLots()
	local roadParams = RaycastParams.new()
	roadParams.FilterType = Enum.RaycastFilterType.Include
	roadParams.FilterDescendantsInstances = { city:FindFirstChild("Roads") }
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local bush = assets and assets:FindFirstChild("TropicalBush")
	local counts = { drives = 0, hedges = 0, trees = 0, cars = 0, bushes = 0 }
	local n = 0
	for _, m in ipairs(art:GetDescendants()) do
		if m:IsA("Model") and m.Name == "House" then
			local body = m:FindFirstChild("Body")
			local garage = m:FindFirstChild("Garage")
			if body and garage then
				n += 1
				local cf = body.CFrame
				local w, d = body.Size.X, body.Size.Z
				-- The garage door sits on the front wall: "front" is the way that wall faces.
				local out = garage.Position - body.Position
				out = Vector3.new(out.X, 0, out.Z)
				out = out - cf.RightVector * out:Dot(cf.RightVector)
				local front = out.Unit
				-- Driveway: from the garage door out to the road (if one is within 70 studs).
				local start = Vector3.new(garage.Position.X, 0, garage.Position.Z)
				local reach
				for dist = 6, 70, 3 do
					local p = start + front * dist
					if Workspace:Raycast(Vector3.new(p.X, 10, p.Z), Vector3.new(0, -20, 0), roadParams) then
						reach = dist
						break
					end
				end
				if reach and reach > 8 then
					local c = start + front * (reach / 2)
					local drive = part(folder, "Driveway", Vector3.new(garage.Size.X + 1, 0.14, reach),
						CFrame.lookAt(Vector3.new(c.X, 0.07, c.Z), Vector3.new(c.X, 0.07, c.Z) + front), DRIVE, Enum.Material.Concrete)
					drive.CanCollide = true
					counts.drives += 1
					if n % 5 < 2 then
						local p = start + front * 9
						if #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 4, p.Z), Vector3.new(9, 6, 14), op) == 0 then
							if parkedCar(folder, CFrame.lookAt(Vector3.new(p.X, 0.16, p.Z), Vector3.new(p.X, 0.16, p.Z) - front), n) then
								counts.cars += 1
							end
						end
					end
				end
				-- A hedge along the back of the yard.
				local hp = Vector3.new(body.Position.X, 1.6, body.Position.Z) - front * (d / 2 + 9)
				if #Workspace:GetPartBoundsInBox(CFrame.new(hp), Vector3.new(4, 3, 4), op) == 0 then
					local hedge = part(folder, "Hedge", Vector3.new(w + 10, 3.2, 2), CFrame.lookAt(hp, hp + front), HEDGE, Enum.Material.Grass)
					hedge.CanCollide = true
					hedge.CastShadow = true
					counts.hedges += 1
				end
				-- Trees and bushes in the front yard, clear of the driveway and the door path.
				for t = 1, 2 do
					local sx = (t == 1 and -1 or 1) * (w / 2 + 3 + (hash(body.Position, t) % 5))
					local p = body.Position + cf.RightVector * sx + front * (d / 2 + 6 + (hash(body.Position, t + 4) % 8))
					if not Restyle.InLots(lots, p.X, p.Z, 3)
						and #Workspace:GetPartBoundsInBox(CFrame.new(p.X, 6, p.Z), Vector3.new(4, 10, 4), op) == 0
						and not Workspace:Raycast(Vector3.new(p.X, 10, p.Z), Vector3.new(0, -20, 0), roadParams) then
						if (hash(body.Position, t) % 3 > 0) or not bush then
							local palm = ArtKit.Palm(folder, Vector3.new(p.X, 0, p.Z), 0.8 + (hash(p, 2) % 40) / 100)
							if palm:IsA("BasePart") then
								palm.Name = "YardPalm"
								palm.CanCollide = false
								palm.CanQuery = false
								palm.CastShadow = true
							end
							counts.trees += 1
						else
							local b = bush:Clone()
							b:PivotTo(CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, (hash(p, 1) % 6), 0))
							for _, bp in ipairs(b:GetDescendants()) do
								if bp:IsA("BasePart") then
									bp.Anchored = true
									bp.CanCollide = false
									bp.CanQuery = false
									bp.CanTouch = false
								end
							end
							b.Parent = folder
							counts.bushes += 1
						end
					end
				end
			end
		end
	end
	return string.format("yards: %d driveways, %d hedges, %d palms, %d bushes, %d parked cars", counts.drives, counts.hedges, counts.trees, counts.bushes, counts.cars)
end

------------------------------------------------------------------ plazas and greenery

local PLANTER = rgb(150, 146, 138)

local function planter(folder, ArtKit, pos, scale)
	local m = Instance.new("Model")
	m.Name = "Planter"
	m.Parent = folder
	local box = part(m, "Box", Vector3.new(6, 1.6, 6), CFrame.new(pos.X, pos.Y + 0.8, pos.Z), PLANTER, Enum.Material.Concrete)
	box.CanCollide = true
	box.CanQuery = true
	box.CastShadow = true
	part(m, "Soil", Vector3.new(5.2, 0.2, 5.2), CFrame.new(pos.X, pos.Y + 1.62, pos.Z), rgb(70, 110, 62), Enum.Material.Grass)
	local palm = ArtKit.Palm(m, Vector3.new(pos.X, pos.Y + 1.6, pos.Z), scale)
	if palm:IsA("BasePart") then
		palm.CanCollide = false
		palm.CanQuery = false
		palm.CastShadow = true
	end
	return m
end

local function bench(folder, cf)
	local m = Instance.new("Model")
	m.Name = "PlazaBench"
	m.Parent = folder
	part(m, "Seat", Vector3.new(6, 0.4, 2), cf * CFrame.new(0, 1.6, 0), rgb(120, 86, 58), Enum.Material.WoodPlanks).CanCollide = true
	part(m, "Back", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.6, 1), rgb(120, 86, 58), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(m, "Leg", Vector3.new(0.4, 1.4, 1.8), cf * CFrame.new(x, 0.7, 0), rgb(58, 60, 66), Enum.Material.Metal)
	end
end

-- The places new players first see: each city spawn gets four small lawns with palms, bushes and
-- benches, so nobody starts on a bare slab. Then loose palms and bushes over the Palm Hills lawns.
function Look3.Plazas(city)
	local Restyle = require(ServerStorage.Tools.Restyle)
	local ArtKit = require(ServerStorage.Tools.ArtKit)
	local art = city:FindFirstChild("Art")
	local folder = freshFolder(art, "Plazas")
	local op = Restyle.Blockers(city)
	local roadParams = RaycastParams.new()
	roadParams.FilterType = Enum.RaycastFilterType.Include
	roadParams.FilterDescendantsInstances = { city:FindFirstChild("Roads") }
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { city:FindFirstChild("Ground") }
	local function onRoad(x, z)
		return Workspace:Raycast(Vector3.new(x, 10, z), Vector3.new(0, -20, 0), roadParams) ~= nil
	end
	local function free(x, z, r)
		return not onRoad(x, z) and #Workspace:GetPartBoundsInBox(CFrame.new(x, 6, z), Vector3.new(r * 2, 10, r * 2), op) == 0
	end
	local counts = { planters = 0, benches = 0, signs = 0, loose = 0 }
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local bush = assets and assets:FindFirstChild("TropicalBush")
	local spawns = Workspace:FindFirstChild("Spawns")
	local pads = {}
	for _, p in ipairs(spawns and spawns:GetChildren() or {}) do
		if p:IsA("BasePart") and (p.Name == "CarPad" or p.Name == "BoatPad") then
			table.insert(pads, p)
		end
	end
	local function nearPad(x, z, r)
		for _, p in ipairs(pads) do
			if math.abs(p.Position.X - x) < p.Size.X / 2 + r and math.abs(p.Position.Z - z) < p.Size.Z / 2 + r then
				return true
			end
		end
		return false
	end
	for _, s in ipairs(spawns and spawns:GetChildren() or {}) do
		if s:IsA("SpawnLocation") and string.sub(s.Name, 1, 9) == "CitySpawn" then
			local c = s.Position
			-- Four little lawns around the spawn (cross paths between them stay clear): palms, bushes
			-- and a bench each, wherever that corner is free.
			local q = 0
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					q += 1
					local x, z = c.X + sx * 27, c.Z + sz * 27
					if free(x, z, 16) and not nearPad(x, z, 17) then
						local lawn = part(folder, "PlazaLawn", Vector3.new(30, 0.5, 30), CFrame.new(x, 0.2, z), rgb(78, 122, 62), Enum.Material.Grass)
						lawn.CanCollide = true
						lawn.CanQuery = true
						local kerb = part(folder, "PlazaKerb", Vector3.new(31.2, 0.36, 31.2), CFrame.new(x, 0.17, z), PLANTER, Enum.Material.Concrete)
						kerb.CanCollide = true
						for k = 1, 3 do
							local px = x + ((hash(c, q * 10 + k) % 20) - 10)
							local pz = z + ((hash(c, q * 20 + k) % 20) - 10)
							local palm = ArtKit.Palm(folder, Vector3.new(px, 0.45, pz), 0.9 + (k * 0.12))
							if palm:IsA("BasePart") then
								palm.Name = "PlazaPalm"
								palm.CanCollide = false
								palm.CanQuery = false
								palm.CastShadow = true
							end
							counts.planters += 1
						end
						if bush then
							for k = 1, 2 do
								local bsh = bush:Clone()
								bsh:PivotTo(CFrame.new(x + (k == 1 and -9 or 8), 0.45, z + (k == 1 and 9 or -8)) * CFrame.Angles(0, k * 2.1, 0))
								for _, bp in ipairs(bsh:GetDescendants()) do
									if bp:IsA("BasePart") then
										bp.Anchored = true
										bp.CanCollide = false
										bp.CanQuery = false
										bp.CanTouch = false
									end
								end
								bsh.Parent = folder
							end
						end
						-- A bench on the path side, facing the spawn.
						local bp = Vector3.new(x - sx * 17.5, 0, z)
						bench(folder, CFrame.lookAt(bp, Vector3.new(c.X, 0, bp.Z)) * CFrame.Angles(0, math.pi, 0))
						counts.benches += 1
					end
				end
			end
		end
	end
	-- Loose palms and bushes over the open lawns of Palm Hills (clear of roads, yards and pads).
	local lots = Restyle.GameplayLots()
	local rng = Random.new(31)
	for _ = 1, 520 do
		local x, z = rng:NextNumber(-880, 980), rng:NextNumber(-1980, -870)
		local hit = Workspace:Raycast(Vector3.new(x, 20, z), Vector3.new(0, -40, 0), groundParams)
		if hit and hit.Material == Enum.Material.Grass and not Restyle.InLots(lots, x, z, 6)
			and #Workspace:GetPartBoundsInBox(CFrame.new(x, 6, z), Vector3.new(10, 10, 10), op) == 0
			and #Workspace:GetPartBoundsInBox(CFrame.new(x, 1, z), Vector3.new(26, 4, 26), (function()
				local o = OverlapParams.new()
				o.FilterType = Enum.RaycastFilterType.Include
				o.FilterDescendantsInstances = { city:FindFirstChild("Roads") }
				return o
			end)()) == 0 then
			if bush and rng:NextNumber() < 0.35 then
				local b = bush:Clone()
				b:PivotTo(CFrame.new(x, hit.Position.Y, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
				for _, bp in ipairs(b:GetDescendants()) do
					if bp:IsA("BasePart") then
						bp.Anchored = true
						bp.CanCollide = false
						bp.CanQuery = false
						bp.CanTouch = false
					end
				end
				b.Parent = folder
			else
				local palm = ArtKit.Palm(folder, Vector3.new(x, hit.Position.Y, z), rng:NextNumber(0.8, 1.25))
				if palm:IsA("BasePart") then
					palm.Name = "LawnPalm"
					palm.CanCollide = false
					palm.CanQuery = false
					palm.CastShadow = true
				end
			end
			counts.loose += 1
		end
	end
	return string.format("plazas: %d palms, %d benches, %d loose palms and bushes", counts.planters, counts.benches, counts.loose)
end

------------------------------------------------------------------ landmarks

-- The hand-built places (heist fronts, the beach, docks, marina, prison, downtown set pieces): stucco
-- instead of flat pastel plastic on the big walls, neon strips that only glow at night, and signs in
-- the same clean fonts as the rest of the city.
local WALL_NAMES = { Wall = true, Tier = true, Header = true, Fascia = true, Body = true, Tower = true, Base = true }

function Look3.Landmarks(city)
	local art = city:FindFirstChild("Art")
	local counts = { walls = 0, neon = 0, signs = 0 }
	local skip = { Buildings = true, Infill = true, BlockFill = true, StreetLife = true, Yards = true, Plazas = true, RoadPaint = true,
		ParkingBays = true, StreetDetails = true, GladesNature = true, Streets = true }
	local roots = {}
	for _, f in ipairs(art:GetChildren()) do
		if not skip[f.Name] then
			table.insert(roots, f)
		end
	end
	for _, root in ipairs(roots) do
		for _, p in ipairs(root:GetDescendants()) do
			if p:IsA("BasePart") then
				if p.Material == Enum.Material.Neon or p:GetAttribute("NeonColor") ~= nil then
					-- Thin strips and tubes only: big glowing panels (vault lights, pool water...) stay.
					local s = p.Size
					local thin = math.min(s.X, s.Y, s.Z) <= 1.2 and math.max(s.X, s.Y, s.Z) >= 4
					if thin and p.Name == "Neon" then
						nightNeon(p)
						counts.neon += 1
					end
				elseif WALL_NAMES[p.Name] and p.Material == Enum.Material.SmoothPlastic and p.Size.Magnitude > 20 and p.Transparency == 0 then
					local h, sat, val = p.Color:ToHSV()
					if sat > 0.12 and val > 0.6 then
						-- A pastel wall: keep a hint of its colour on warm stucco.
						p.Color = Color3.fromHSV(h, sat * 0.45, math.min(val, 0.9))
					end
					p.Material = Enum.Material.Plaster
					counts.walls += 1
				end
			elseif p:IsA("TextLabel") or p:IsA("TextButton") then
				if p.Font == Enum.Font.FredokaOne then
					p.Font = Enum.Font.Oswald
					counts.signs += 1
				end
			end
		end
	end
	-- Signs outside the Art folder (heist sites, activities).
	for _, name in ipairs({ "Heists", "Activities", "Spawns" }) do
		local f = Workspace:FindFirstChild(name)
		for _, p in ipairs(f and f:GetDescendants() or {}) do
			if (p:IsA("TextLabel") or p:IsA("TextButton")) and p.Font == Enum.Font.FredokaOne then
				p.Font = Enum.Font.Oswald
				counts.signs += 1
			end
		end
	end
	return string.format("landmarks: %d stucco walls, %d night-neon strips, %d signs set in the new font", counts.walls, counts.neon, counts.signs)
end

function Look3.Run(opts)
	opts = opts or {}
	local city = Workspace:FindFirstChild("City")
	if not city then
		return "no Workspace.City"
	end
	local lines = {}
	table.insert(lines, Look3.Palette(city))
	table.insert(lines, Look3.Roads(city))
	table.insert(lines, Look3.Pads(city))
	table.insert(lines, Look3.StreetLife(city))
	table.insert(lines, Look3.Yards(city))
	table.insert(lines, Look3.Plazas(city))
	table.insert(lines, Look3.Landmarks(city))
	table.insert(lines, Look3.Lighting())
	return "Look3: " .. table.concat(lines, "; ")
end

return Look3
