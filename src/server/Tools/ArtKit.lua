-- ArtKit (ModuleScript, ServerStorage.Tools.ArtKit). Studio-only art toolbox for Port Solana.
-- Every district builder uses these helpers so the city shares one look: pastel art deco by day,
-- neon trims by night, palms everywhere. Built from simple parts and a few reused meshes so phones
-- stay fast (reused meshes and identical parts render cheaply; textures are avoided).
--
-- Conventions
--   * cf arguments are "ground CFrames": position on the ground (y = 0 is the land surface), facing
--     = LookVector (the front of a building faces LookVector, i.e. the street).
--   * Every helper takes a parent (Folder/Model) first and returns the Model it built.
--   * Small props never cast shadows; buildings do.
--   * Budget guide: a building 8-16 parts, a prop 1-8 parts. Real lights (PointLight/SpotLight)
--     only through ArtKit.Light (it caps how many exist in total).

local ServerStorage = game:GetService("ServerStorage")

local ArtKit = {}

ArtKit.Colors = {
	Pastels = {
		Color3.fromRGB(255, 196, 218), -- flamingo pink
		Color3.fromRGB(176, 236, 226), -- seafoam
		Color3.fromRGB(255, 218, 178), -- peach
		Color3.fromRGB(212, 196, 255), -- lavender
		Color3.fromRGB(196, 240, 200), -- mint
		Color3.fromRGB(255, 242, 196), -- butter
		Color3.fromRGB(246, 246, 240), -- deco white
	},
	Neon = {
		Pink = Color3.fromRGB(255, 62, 165),
		Cyan = Color3.fromRGB(34, 225, 255),
		Purple = Color3.fromRGB(123, 47, 255),
		Orange = Color3.fromRGB(255, 138, 61),
		Yellow = Color3.fromRGB(255, 214, 10),
		Mint = Color3.fromRGB(110, 242, 196),
	},
	Glass = Color3.fromRGB(40, 56, 84),
	Sand = Color3.fromRGB(244, 217, 166),
	Concrete = Color3.fromRGB(196, 190, 186),
	Asphalt = Color3.fromRGB(58, 58, 66),
	Wood = Color3.fromRGB(150, 110, 70),
	DarkWood = Color3.fromRGB(96, 70, 48),
	Leaf = Color3.fromRGB(70, 170, 90),
	Rust = Color3.fromRGB(150, 90, 70),
	Steel = Color3.fromRGB(120, 128, 140),
	White = Color3.fromRGB(245, 245, 245),
}
local C = ArtKit.Colors

local rng = Random.new(1985)
function ArtKit.Random()
	return rng
end
function ArtKit.Pick(list)
	return list[rng:NextInteger(1, #list)]
end
function ArtKit.PickNeon()
	local n = C.Neon
	return ArtKit.Pick({ n.Pink, n.Cyan, n.Purple, n.Orange, n.Yellow, n.Mint })
end

-- Basic anchored part. opts: Shape, Transparency, CanCollide (default true), Shadow (default false),
-- Name, Reflectance.
function ArtKit.Part(parent, size, cf, color, material, opts)
	opts = opts or {}
	local p = Instance.new(opts.Class or "Part")
	p.Name = opts.Name or "Part"
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = opts.Shadow == true
	p.CanCollide = opts.CanCollide ~= false
	p.CanTouch = false
	p.CanQuery = opts.CanQuery ~= false and p.CanCollide
	if opts.Shape then
		p.Shape = opts.Shape
	end
	if opts.Transparency then
		p.Transparency = opts.Transparency
	end
	if opts.Reflectance then
		p.Reflectance = opts.Reflectance
	end
	p.Parent = parent
	return p
end

function ArtKit.Model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function neon(parent, size, cf, color)
	return ArtKit.Part(parent, size, cf, color, Enum.Material.Neon, { CanCollide = false, Name = "Neon" })
end
ArtKit.Neon = neon

-- Real lights are expensive: ArtKit.Light only creates one if the city-wide cap isn't reached.
ArtKit.LightCap = 160
local lightCount = 0
function ArtKit.ResetLights()
	lightCount = 0
end
function ArtKit.Light(part, color, range, brightness, kind)
	if lightCount >= ArtKit.LightCap then
		return nil
	end
	lightCount += 1
	local l = Instance.new(kind or "PointLight")
	l.Color = color
	l.Range = math.min(range or 30, 60)
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = part
	return l
end

-- Art deco building. cf = ground CFrame, front faces LookVector.
-- opts: Color, Trim (neon colour), Tiers (1-3), Sign (text on the top tier, front), Awning (bool),
--       Stripes (vertical glass strips per face, default 3), Name
function ArtKit.Deco(parent, cf, w, h, d, opts)
	opts = opts or {}
	local m = ArtKit.Model(parent, opts.Name or "DecoBuilding")
	local color = opts.Color or ArtKit.Pick(C.Pastels)
	local trim = opts.Trim or ArtKit.PickNeon()
	local base = ArtKit.Part(m, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color, Enum.Material.SmoothPlastic, { Shadow = true, Name = "Body" })
	m.PrimaryPart = base
	-- Horizontal deco bands (slightly proud of the walls)
	local bands = h > 60 and 3 or 2
	for i = 1, bands do
		local y = h * (i / (bands + 1))
		ArtKit.Part(m, Vector3.new(w + 0.8, 1, d + 0.8), cf * CFrame.new(0, y, 0), C.White, Enum.Material.SmoothPlastic, { CanCollide = false, Name = "Band" })
	end
	-- Neon cornice at the roof line
	neon(m, Vector3.new(w + 1, 0.8, d + 1), cf * CFrame.new(0, h - 1.5, 0), trim)
	-- Vertical glass strips on front and back (and sides if deep enough)
	local strips = opts.Stripes or 3
	local stripH = h - 10
	if stripH > 6 then
		for s = 1, strips do
			local x = -w / 2 + w * (s - 0.5) / strips
			for _, z in ipairs({ -d / 2 - 0.15, d / 2 + 0.15 }) do
				ArtKit.Part(m, Vector3.new(math.max(2, w / strips * 0.45), stripH, 0.4), cf * CFrame.new(x, 4 + stripH / 2, z), C.Glass,
					Enum.Material.Glass, { CanCollide = false, Name = "Window", Reflectance = 0.1 })
			end
		end
		if d > 30 then
			for _, x in ipairs({ -w / 2 - 0.15, w / 2 + 0.15 }) do
				ArtKit.Part(m, Vector3.new(0.4, stripH, math.max(2, d * 0.35)), cf * CFrame.new(x, 4 + stripH / 2, 0), C.Glass,
					Enum.Material.Glass, { CanCollide = false, Name = "Window", Reflectance = 0.1 })
			end
		end
	end
	-- Stepped top tiers (the classic deco "wedding cake")
	local tiers = opts.Tiers or (h > 70 and 2 or 1)
	local tw, td, ty = w, d, h
	for t = 2, tiers do
		tw, td = tw * 0.66, td * 0.66
		local th = math.max(6, h * 0.12)
		ArtKit.Part(m, Vector3.new(tw, th, td), cf * CFrame.new(0, ty + th / 2, 0), color, Enum.Material.SmoothPlastic, { Shadow = true, Name = "Tier" })
		neon(m, Vector3.new(tw + 0.8, 0.6, td + 0.8), cf * CFrame.new(0, ty + th - 1, 0), trim)
		ty += th
	end
	-- Neon corner fins on the street side
	for _, x in ipairs({ -w / 2, w / 2 }) do
		neon(m, Vector3.new(0.8, h * 0.7, 0.8), cf * CFrame.new(x, h * 0.35 + 3, -d / 2), trim)
	end
	if opts.Awning ~= false and h < 90 then
		ArtKit.Part(m, Vector3.new(math.min(w * 0.5, 30), 0.8, 6), cf * CFrame.new(0, 11, -d / 2 - 3), trim, Enum.Material.SmoothPlastic, { CanCollide = false, Name = "Awning" })
		ArtKit.Part(m, Vector3.new(math.min(w * 0.3, 14), 9, 0.4), cf * CFrame.new(0, 4.5, -d / 2 - 0.25), C.Glass, Enum.Material.Glass, { CanCollide = false, Name = "Door" })
	end
	if opts.Sign then
		ArtKit.Sign(m, cf * CFrame.new(0, ty + 5, -td / 2 + 0.5), opts.Sign, trim, math.max(16, tw * 0.9), 8)
	end
	return m
end

-- A flat neon sign: panel + glowing text (SurfaceGui). cf = centre of the panel, facing LookVector.
function ArtKit.Sign(parent, cf, text, color, width, height)
	width, height = width or 20, height or 6
	local panel = ArtKit.Part(parent, Vector3.new(width, height, 0.6), cf, Color3.fromRGB(20, 16, 30), Enum.Material.SmoothPlastic,
		{ CanCollide = false, Name = "Sign" })
	neon(parent, Vector3.new(width + 0.6, 0.4, 0.7), cf * CFrame.new(0, height / 2, 0), color)
	neon(parent, Vector3.new(width + 0.6, 0.4, 0.7), cf * CFrame.new(0, -height / 2, 0), color)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.PixelsPerStud = 20
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.MaxDistance = 600
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	gui.Parent = panel
	return panel
end

-- Billboard on two legs with a parody ad. cf = ground CFrame under the middle, facing the road.
function ArtKit.Billboard(parent, cf, text, color)
	local m = ArtKit.Model(parent, "Billboard")
	for _, x in ipairs({ -10, 10 }) do
		ArtKit.Part(m, Vector3.new(1.2, 22, 1.2), cf * CFrame.new(x, 11, 0), C.Steel, Enum.Material.Metal, { Name = "Leg" })
	end
	ArtKit.Sign(m, cf * CFrame.new(0, 28, 0), text, color or ArtKit.PickNeon(), 34, 12)
	return m
end

-- Palm tree: the generated mesh in ServerStorage.ArtAssets.PalmTree if present, else a part palm.
function ArtKit.Palm(parent, pos, scale, yaw)
	scale = scale or 1
	yaw = yaw or rng:NextNumber(0, math.pi * 2)
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("PalmTree")
	if template then
		local p = template:Clone()
		p.Anchored = true
		p.CanTouch = false
		p.CastShadow = false
		p.Size = template.Size * scale
		p.CFrame = CFrame.new(pos + Vector3.new(0, p.Size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
		p.Parent = parent
		return p
	end
	local m = ArtKit.Model(parent, "Palm")
	local lean = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(8), 0, 0)
	local top = CFrame.new(pos) * lean
	for i = 0, 3 do
		local seg = 7 * scale
		ArtKit.Part(m, Vector3.new(seg, 1.6 * scale - i * 0.15, 1.6 * scale - i * 0.15), top * CFrame.new(0, seg / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(180, 140, 95), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Name = "Trunk", CanCollide = i == 0 })
		top = top * CFrame.new(0, seg * 0.95, 0) * CFrame.Angles(math.rad(3), 0, 0)
	end
	for f = 1, 6 do
		local a = math.rad(f * 60)
		ArtKit.Part(m, Vector3.new(2.2 * scale, 0.3, 10 * scale), top * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -4.5 * scale) * CFrame.Angles(math.rad(-18), 0, 0),
			C.Leaf, Enum.Material.SmoothPlastic, { CanCollide = false, Name = "Frond" })
	end
	return m
end

-- Street light with a neon lamp; withLight adds a real PointLight (subject to the cap).
function ArtKit.StreetLight(parent, cf, withLight, color)
	color = color or C.Neon.Pink
	local m = ArtKit.Model(parent, "StreetLight")
	ArtKit.Part(m, Vector3.new(16, 0.8, 0.8), cf * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder, Name = "Pole" })
	ArtKit.Part(m, Vector3.new(0.6, 0.6, 5), cf * CFrame.new(0, 15.8, -2.2), C.Steel, Enum.Material.Metal, { CanCollide = false, Name = "Arm" })
	local lamp = neon(m, Vector3.new(1.6, 0.6, 2.4), cf * CFrame.new(0, 15.4, -4.4), color)
	if withLight then
		ArtKit.Light(lamp, color, 36, 1.4)
	end
	return m
end

function ArtKit.Umbrella(parent, pos, color)
	local m = ArtKit.Model(parent, "Umbrella")
	ArtKit.Part(m, Vector3.new(8, 0.4, 0.4), CFrame.new(pos + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.White, nil,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, Name = "Pole" })
	ArtKit.Part(m, Vector3.new(1.2, 9, 9), CFrame.new(pos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90)), color or ArtKit.PickNeon(), nil,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, Name = "Canopy" })
	return m
end

function ArtKit.Lounger(parent, cf, color)
	local m = ArtKit.Model(parent, "Lounger")
	ArtKit.Part(m, Vector3.new(3, 0.5, 7), cf * CFrame.new(0, 1.2, 0), color or C.White, nil, { Name = "Bed" })
	ArtKit.Part(m, Vector3.new(3, 0.5, 3), cf * CFrame.new(0, 2.2, 3.6) * CFrame.Angles(math.rad(40), 0, 0), color or C.White, nil, { Name = "Back" })
	return m
end

function ArtKit.LifeguardTower(parent, cf)
	local m = ArtKit.Model(parent, "LifeguardTower")
	for _, x in ipairs({ -3, 3 }) do
		for _, z in ipairs({ -3, 3 }) do
			ArtKit.Part(m, Vector3.new(0.8, 9, 0.8), cf * CFrame.new(x, 4.5, z), C.White, nil, { Name = "Leg" })
		end
	end
	ArtKit.Part(m, Vector3.new(8, 0.6, 8), cf * CFrame.new(0, 9.3, 0), C.Wood, Enum.Material.WoodPlanks, { Name = "Deck" })
	ArtKit.Part(m, Vector3.new(7, 5, 7), cf * CFrame.new(0, 12, 0), C.Neon.Cyan, nil, { Name = "Hut" })
	ArtKit.Part(m, Vector3.new(9, 0.6, 9), cf * CFrame.new(0, 14.8, 0), C.Neon.Pink, nil, { Name = "Roof" })
	return m
end

function ArtKit.Bench(parent, cf)
	local m = ArtKit.Model(parent, "Bench")
	ArtKit.Part(m, Vector3.new(6, 0.4, 2), cf * CFrame.new(0, 1.6, 0), C.Wood, Enum.Material.WoodPlanks, { Name = "Seat" })
	ArtKit.Part(m, Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.6, 1), C.Wood, Enum.Material.WoodPlanks, { CanCollide = false, Name = "Back" })
	return m
end

-- Shipping container. cf = ground CFrame; long side along LookVector.
function ArtKit.Container(parent, cf, color)
	return ArtKit.Part(parent, Vector3.new(8, 8.5, 20), cf * CFrame.new(0, 4.25, 0), color or ArtKit.Pick({ C.Rust, C.Neon.Cyan, C.Neon.Orange, C.Steel }),
		Enum.Material.Metal, { Shadow = true, Name = "Container" })
end

-- Suburban house: box + wedge roof + garage door + a front-yard palm.
function ArtKit.House(parent, cf, w, d, color)
	local m = ArtKit.Model(parent, "House")
	local h = 11
	color = color or ArtKit.Pick(C.Pastels)
	ArtKit.Part(m, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color, nil, { Shadow = true, Name = "Body" })
	local roof = C.White
	for _, s in ipairs({ -1, 1 }) do
		local wd = Instance.new("WedgePart")
		wd.Anchored = true
		wd.Size = Vector3.new(w + 1, 4, d / 2 + 0.5)
		wd.CFrame = cf * CFrame.new(0, h + 2, s * d / 4) * CFrame.Angles(0, s == 1 and 0 or math.pi, 0)
		wd.Color = roof
		wd.Material = Enum.Material.SmoothPlastic
		wd.CastShadow = true
		wd.Parent = m
	end
	ArtKit.Part(m, Vector3.new(w * 0.35, 7, 0.4), cf * CFrame.new(w * 0.2, 3.5, -d / 2 - 0.2), C.White, nil, { CanCollide = false, Name = "Garage" })
	ArtKit.Part(m, Vector3.new(4, 7, 0.4), cf * CFrame.new(-w * 0.25, 3.5, -d / 2 - 0.2), ArtKit.PickNeon(), nil, { CanCollide = false, Name = "Door" })
	ArtKit.Part(m, Vector3.new(w * 0.3, 4, 0.4), cf * CFrame.new(-w * 0.25, 8, -d / 2 - 0.2), C.Glass, Enum.Material.Glass, { CanCollide = false, Name = "Window" })
	return m
end

-- Simple boat hull with a cabin. cf = water-level CFrame, bow toward LookVector.
function ArtKit.Boat(parent, cf, length, color)
	length = length or 24
	local m = ArtKit.Model(parent, "Boat")
	local w = length * 0.35
	ArtKit.Part(m, Vector3.new(w, 3, length * 0.75), cf * CFrame.new(0, 0.5, length * 0.12), color or C.White, nil, { Shadow = true, Name = "Hull" })
	local bow = Instance.new("WedgePart")
	bow.Anchored = true
	bow.Size = Vector3.new(w, 3, length * 0.25)
	bow.CFrame = cf * CFrame.new(0, 0.5, -length * 0.375) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, 0)
	bow.Color = color or C.White
	bow.Material = Enum.Material.SmoothPlastic
	bow.Parent = m
	ArtKit.Part(m, Vector3.new(w * 0.7, 3, length * 0.3), cf * CFrame.new(0, 3.5, length * 0.15), C.Glass, Enum.Material.Glass, { Name = "Cabin" })
	neon(m, Vector3.new(w + 0.2, 0.3, length * 0.75), cf * CFrame.new(0, 2, length * 0.12), ArtKit.PickNeon())
	return m
end

return ArtKit
