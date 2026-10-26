-- ApartmentService (ModuleScript, ServerScriptService.Services.ApartmentService)
-- Apartment towers you can tour (Config.Apartments), open to everyone and nothing to buy:
--   * At start-up (Init) it picks a handful of the city's own tall DecoBuilding towers (the rules are in
--     Config.Apartments: tall with a big flat roof, downtown / marina / beach / docks, a road in front,
--     spaced out, never over a heist site, the Big Score's lots or a home). Only the place's art decides,
--     so every server gets the same towers, names and colours. Built in Workspace.Apartments: a Folder per
--     tower (named after it) holding its Entrance and Penthouse models (each streams in whole).
--   * Street entrance on the facade facing the road, at ground level: a glass double door in a dark metal
--     frame set in light limestone, a canopy on two tie rods with downlights, the tower's name lit over
--     it (Oswald), two palms in planters and two wall lamps. Shop signs behind the canopy go. Its "Enter"
--     prompt (ObjectText = the name) takes you up.
--   * Penthouse on the tower's highest part, so the glass looks out at the real city: an elevator lobby,
--     an open-plan living room (a sofa and armchairs you can sit in, a TV on MIAMI COAST TV), a kitchen
--     island with stools, a juice bar (juice and soda), a dining table, a bedroom, a bathroom nook, art
--     panels with a neon accent and potted palms, all under a flat roof with recessed lights; outside, a
--     terrace with a pool (just to look at), sun loungers, palms in planters and 8-stud glass railings
--     round every roof edge with an invisible wall above them (nobody walks or jumps off by accident).
--     Rooftop AC boxes and water tanks (Restyle) under it go.
--   * Look 3.0 like HousingService: plaster, marble, walnut, leather and fabric, limestone and dark
--     metal, each tower with one accent colour. Neon is only thin strips that glow after dark (tag
--     "NightNeon", attribute NeonColor); lamps are tagged "NightLamp" (LampColor) and their lights start
--     off (SkyClient switches both). The ceiling lights and the pool light are always on and low
--     (Config.Apartments.Lights: Realistic lighting whites rooms out). Everything is anchored; small
--     details never collide and can't be queried. Glass walls are "GlassWall", never "Window" (SkyClient
--     lights every part named Window at night).
--   * Going up: the door's prompt fires here. On foot (not tasered or knocked over either), Side Civilian
--     or Cop, within EnterRange of the door and not wanted (Heat > 0: the "ApartmentWanted" toast).
--     Rate-limited, one trip at a time per player. HouseFade "Out" to
--     that player (HouseClient fades to black), FadeTime, the area streams in, the character moves to the
--     elevator lobby facing the room, HouseFade "In". The tower they went in by is remembered (forgotten
--     when the character goes or the player leaves). Coming down: the elevator's prompt ("Down to the
--     street") takes anyone in a penthouse out to the door they came in by, or to this tower's own door if
--     they never used one, the same way. Falling off a roof needs nothing special.
--   * Player attribute "InApartment" = the tower's name while the character is in its penthouse room (the
--     indoor part's footprint, floor to ceiling: not the terrace, not its flat roof), else nil. Set on the
--     trip up, cleared on the way down and when the character goes, and checked every RoomCheck seconds
--     (walking out to the terrace and back). HouseClient keeps the rain off there; VehicleService brings
--     no car (CarNoRoom). Never InHome: that one is a home's (the LEAVE tile, a safe zone).
--   * Every seat names where EXIT stands you (attribute ExitAt, a world position VehicleService uses): the
--     seat's model is the whole penthouse, so a car's side-step would land on the next cushion or out
--     through the glass.
-- ApartmentService.Towers() -> { { Name, Door = Vector3 (the ground in front of the door), Kind } }, for
-- MapService's GPS list (ApartmentService starts before it).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Apartments = require(ReplicatedStorage.Shared.Config.Apartments)
local Ambience = require(ReplicatedStorage.Shared.Config.Ambience)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)

local ApartmentService = {}

local P = Apartments.Pick
local H = Apartments.Penthouse
local L = Apartments.Lights

-- Look 3.0 colours (HousingService's palette and a few more). Whites sit a notch under white: near-white
-- rooms under lamps looked blown out in the realistic day lighting.
local COL = {
	White = Color3.fromRGB(236, 234, 228), -- painted trim, a real white
	Plaster = Color3.fromRGB(222, 216, 204), -- inside walls
	Ceiling = Color3.fromRGB(228, 226, 220),
	Marble = Color3.fromRGB(220, 216, 208), -- indoor floor, worktops
	Stone = Color3.fromRGB(206, 198, 184), -- limestone round the street door
	Coping = Color3.fromRGB(214, 208, 196), -- the pool's edge
	Slate = Color3.fromRGB(62, 62, 66), -- the lobby's floor inlay
	Paver = Color3.fromRGB(198, 192, 180), -- terrace paving
	Teak = Color3.fromRGB(146, 106, 72), -- pool deck, loungers
	Walnut = Color3.fromRGB(100, 72, 50), -- furniture
	DarkMetal = Color3.fromRGB(44, 46, 50), -- frames, mullions, the canopy
	Steel = Color3.fromRGB(170, 174, 180), -- brushed: the elevator, the fridge, taps
	Dark = Color3.fromRGB(26, 28, 32), -- sign boards and screens
	DoorGlass = Color3.fromRGB(62, 78, 88), -- dark tinted glass (the street door)
	Glass = Color3.fromRGB(150, 178, 190), -- the penthouse's clear glass walls
	RailGlass = Color3.fromRGB(150, 170, 176),
	Frosted = Color3.fromRGB(226, 232, 234),
	Mirror = Color3.fromRGB(214, 232, 246),
	Sofa = Color3.fromRGB(122, 118, 112), -- a warm grey
	Cushion = Color3.fromRGB(138, 134, 128),
	Leather = Color3.fromRGB(140, 92, 60), -- cognac armchairs and stools
	Linen = Color3.fromRGB(226, 222, 214),
	Headboard = Color3.fromRGB(150, 140, 128),
	Rug = Color3.fromRGB(176, 166, 150),
	Tile = Color3.fromRGB(206, 214, 216), -- the bathroom floor
	Canvas = Color3.fromRGB(232, 222, 204), -- art panels
	ArtSun = Color3.fromRGB(232, 140, 70),
	ArtSea = Color3.fromRGB(52, 104, 140),
	Concrete = Color3.fromRGB(178, 174, 166), -- planters
	Pot = Color3.fromRGB(170, 100, 70), -- terracotta
	Bark = Color3.fromRGB(128, 110, 88),
	Frond = Color3.fromRGB(64, 108, 58),
	Leaf = Color3.fromRGB(70, 112, 60),
	PoolTile = Color3.fromRGB(110, 184, 198),
	PoolWater = Color3.fromRGB(64, 160, 192),
	PoolLight = Color3.fromRGB(60, 200, 255),
	Warm = Color3.fromRGB(255, 214, 170), -- lamplight
	Downlight = Color3.fromRGB(250, 242, 226), -- a ceiling light's disc
	RoomGlow = Color3.fromRGB(210, 156, 96), -- a lit lobby seen through glass after dark
	TrimDay = Color3.fromRGB(58, 60, 66), -- an unlit neon tube by day (SkyClient's day colour)
	LampDay = Color3.fromRGB(226, 226, 220), -- an unlit lamp by day (SkyClient's day colour)
	Gold = Color3.fromRGB(255, 214, 10), -- sign small print
	Amber = Color3.fromRGB(255, 176, 60),
}

-- Heights are in the roof's frame (y 0 = the top of the tower's highest part). The rooms are laid out
-- on a fixed indoor part 50 x 32 (the indoor frame: x -25..25, z -16..16, -Z = the terrace side):
-- living room front-left, bedroom back-left behind the TV wall, the elevator core back-middle with the
-- lobby in front of it, kitchen back-right with the island before it, the bathroom nook in the back-right
-- corner, the juice bar along the right glass, the dining table front-right; the terrace door is the gap
-- in the front glass at x -1..7.
local K = {
	Deck = 0.4, -- top of the terrace paving laid over the whole roof
	Floor = 0.6, -- top of the indoor floor
	IndoorD = 32, -- the indoor part's depth (see above)
	RoadProbeY = -0.3, -- a road part is 1 stud thick with its top at y 0.1: a level ray here hits its side
	DoorRoom = Vector3.new(28, 12, 9), -- what the street entrance needs in front of the facade (planters to x +-13.7)
	PropsGroup = "Props", -- PropService's street furniture: never "in the way" of a door
	RoomCheck = 0.5, -- seconds between checks of who is in a penthouse room (attribute InApartment)
	-- Ceiling lights { x, z, with a light } in the indoor frame: living room, lobby, island, dining table,
	-- bedroom, bathroom; then three discs without a light of their own.
	Downlights = {
		{ -19.5, -6, true }, { 0, 4.5, true }, { 13, 4.5, true }, { 12, -6, true }, { -16, 8, true }, { 20.6, 10.5, true },
		{ -19.5, -13, false }, { 13, 11, false }, { 22.4, -2.5, false },
	},
	-- Mullions { x, z } in the indoor frame: the corners, the front (either side of the terrace door at
	-- -1 and 7), the back and the sides.
	Mullions = {
		{ -24.8, -15.8 }, { 24.8, -15.8 }, { -24.8, 15.8 }, { 24.8, 15.8 },
		{ -13, -15.8 }, { -1, -15.8 }, { 7, -15.8 }, { 16, -15.8 },
		{ -12.5, 15.8 }, { 0, 15.8 }, { 12.5, 15.8 },
		{ -24.8, -5 }, { -24.8, 5 }, { 24.8, -5 }, { 24.8, 5 },
	},
	Juices = { Color3.fromRGB(255, 150, 40), Color3.fromRGB(150, 214, 60), Color3.fromRGB(240, 110, 150) }, -- orange, lime, berry
	Fruit = { Color3.fromRGB(255, 150, 40), Color3.fromRGB(244, 214, 70), Color3.fromRGB(196, 52, 64) },
}

local S = {
	towers = {}, -- built towers in pick order (see setup)
	entered = {}, -- [player] = index (in towers) of the tower whose street door they came in by
	busy = {}, -- [player] = true during a trip up or down
	notify = nil, -- remotes (Init)
	fade = nil,
	folder = nil, -- Workspace.Apartments
}

local enter, down -- defined below (the builders hook prompts to them)

-- Parts ---------------------------------------------------------------------------------------------

-- Small details: no collisions, no queries, no shadow. SHADE: looks only, but big enough to cast a
-- shadow (the parasol). BALL: a small ball with no collisions (fruit, pendant globes).
local DETAIL = { CanCollide = false, CanQuery = false, CastShadow = false }
local SHADE = { CanCollide = false, CanQuery = false }
local BALL = { Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }

local function newPart(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if props and props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide -- first: CanQuery can only go off once CanCollide is off
	end
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- One part between two corners (x0..x1, y0..y1, z0..z1) of a frame's local space.
local function box(parent, name, frame, x0, x1, y0, y1, z0, z1, color, material, props)
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	return newPart(parent, name, size, frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, props)
end

-- An upright cylinder `width` across from y0 to y1 at (x, z) of a frame (cylinders run along X: turned).
local function post(parent, name, frame, x, z, y0, y1, width, color, material, props)
	local p = newPart(parent, name, Vector3.new(y1 - y0, width, width), frame * CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A flat disc `thick` deep and `width` across on a wall: axis "X" for a wall facing +-X, "Z" for +-Z.
local function disc(parent, name, frame, x, y, z, thick, width, axis, color, material)
	local turn = axis == "Z" and CFrame.Angles(0, math.rad(90), 0) or CFrame.new()
	local p = newPart(parent, name, Vector3.new(thick, width, width), frame * CFrame.new(x, y, z) * turn, color, material, DETAIL)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A thin bar from point a to point b of a frame (the canopy's tie rods).
local function rod(parent, frame, a, b, thick, color)
	local pa, pb = frame * a, frame * b
	return newPart(parent, "TieRod", Vector3.new(thick, thick, (pb - pa).Magnitude), CFrame.lookAt((pa + pb) / 2, pb), color,
		Enum.Material.Metal, DETAIL)
end

-- Night-only neon (Look 3.0): dark metal by day; every client's SkyClient turns a part tagged
-- "NightNeon" into Neon in its NeonColor after dark (and switches any Light inside it on).
local function nightNeon(p, color)
	p.Material = Enum.Material.Metal
	p.Color = COL.TrimDay
	p:SetAttribute("NeonColor", color)
	CollectionService:AddTag(p, "NightNeon")
	return p
end

-- A lamp (tag "NightLamp"): a pale shade by day, lit in its LampColor after dark (SkyClient).
local function nightLamp(p, color)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = COL.LampDay
	p:SetAttribute("LampColor", color)
	CollectionService:AddTag(p, "NightLamp")
	return p
end

-- A thin neon strip: no collisions, no shadow, and it only glows (in `color`) after dark.
local function neon(parent, frame, x0, x1, y0, y1, z0, z1, color)
	return nightNeon(box(parent, "Neon", frame, x0, x1, y0, y1, z0, z1, COL.TrimDay, Enum.Material.Metal, DETAIL), color)
end

-- A point light. Inside a NightNeon / NightLamp part it starts off: SkyClient switches it on after dark.
local function light(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Enabled = not (CollectionService:HasTag(part, "NightNeon") or CollectionService:HasTag(part, "NightLamp"))
	l.Parent = part
	return l
end

-- A light shining straight down out of a part's bottom (the canopy's downlights; off until dark there).
local function downlight(part, color, range, brightness)
	local l = Instance.new("SpotLight")
	l.Face = Enum.NormalId.Bottom
	l.Angle = 100
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Enabled = not CollectionService:HasTag(part, "NightLamp")
	l.Parent = part
	return l
end

-- Something to sit on: a Seat part (it keeps CanTouch, or nobody could sit) whose middle is (x, y, z) of
-- `frame`. size = width x thickness x depth in its own frame; yaw turns it, and the sitter looks the
-- way it faces: 0 = -Z, math.pi = +Z, math.pi / 2 = -X, -math.pi / 2 = +X. exit = where EXIT stands you,
-- (x, z) of `frame` as a Vector2, standing on the floor: attribute ExitAt (VehicleService), clear of the
-- furniture and of the seats beside it by a character's width with its arms (4 studs: touching a free
-- seat sits you straight back down).
local function seat(parent, frame, x, y, z, size, yaw, color, material, exit)
	local s = Instance.new("Seat")
	s.Name = "Seat"
	s.Anchored = true
	s.Size = size
	s.CFrame = frame * CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	s.Color = color
	s.Material = material
	s.TopSurface = Enum.SurfaceType.Smooth
	s.BottomSurface = Enum.SurfaceType.Smooth
	s.CastShadow = false
	s:SetAttribute("ExitAt", (frame * CFrame.new(exit.X, K.Floor + 3, exit.Y)).Position)
	s.Parent = parent
	return s
end

-- A bar stool at (x, z) of the indoor frame: a steel post under a leather seat facing `yaw` (exit: seat).
local function stool(parent, frame, x, z, yaw, exit)
	box(parent, "StoolPost", frame, x - 0.2, x + 0.2, K.Floor, K.Floor + 2.9, z - 0.2, z + 0.2, COL.Steel, Enum.Material.Metal, DETAIL)
	seat(parent, frame, x, K.Floor + 3.1, z, Vector3.new(1.8, 0.4, 1.8), yaw, COL.Leather, Enum.Material.Leather, exit)
end

-- A dining chair at (x, z) of the indoor frame facing `yaw`: a linen seat and a walnut back behind it
-- (exit: seat).
local function chair(parent, frame, x, z, yaw, exit)
	local s = seat(parent, frame, x, K.Floor + 1.8, z, Vector3.new(1.9, 0.4, 1.9), yaw, COL.Linen, Enum.Material.Fabric, exit)
	newPart(parent, "ChairBack", Vector3.new(1.9, 4, 0.3), s.CFrame * CFrame.new(0, 0.2, 1.1), COL.Walnut, Enum.Material.WoodPlanks)
end

-- Sign text on one face of a part (LightInfluence 0: crisp by day, glowing at night): the title in
-- Oswald, the (optional) sub label in small print under it.
local function signGui(part, face, title, sub, titleColor, subColor, brightness)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = brightness or 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.04, sub and 0.06 or 0.1)
	t.Size = UDim2.fromScale(0.92, sub and 0.56 or 0.8)
	t.Font = Enum.Font.Oswald
	t.TextScaled = true
	t.TextColor3 = titleColor or COL.White
	t.Text = title
	t.Parent = gui
	if sub then
		local s = Instance.new("TextLabel")
		s.Name = "Sub"
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromScale(0.04, 0.64)
		s.Size = UDim2.fromScale(0.92, 0.28)
		s.Font = Enum.Font.GothamBold
		s.TextScaled = true
		s.TextColor3 = subColor or COL.Gold
		s.Text = sub
		s.Parent = gui
	end
	gui.Parent = part
	return gui
end

-- The TV picture: an evening sky over the sea under the channel's name (a screen stays lit by day).
local function tvScreen(part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 46, 96)), -- evening sky
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(226, 128, 76)), -- sunset on the horizon
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(40, 76, 104)), -- the sea
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 40, 60)),
	})
	grad.Rotation = 90
	grad.Parent = bg
	for _, line in ipairs({
		{ "MIAMI COAST TV", Enum.Font.Oswald, 0.22, 0.34 },
		{ "Sunset on the coast, live from the roof", Enum.Font.GothamMedium, 0.6, 0.15 },
	}) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.06, line[3])
		label.Size = UDim2.fromScale(0.88, line[4])
		label.Font = line[2]
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = line[1]
		label.Parent = bg
	end
	gui.Parent = part
end

local function makePrompt(parent, name, action, object, range)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.MaxActivationDistance = range
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- A palm whose foot stands at (x, y, z) of `frame`, `height` studs tall, turned `yaw`. With the city art's
-- palm mesh (ServerStorage.ArtAssets.PalmTree) the mesh is the look, kept narrower than the palm is tall
-- (and, when `solid`, an invisible trunk is its collision); without it, a trunk and six drooping fronds.
-- Potted palms aren't solid: the pot is what you bump into.
local function palm(parent, frame, x, y, z, height, yaw, solid)
	local base = frame * CFrame.new(x, y, z)
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("PalmTree")
	local hasMesh = template ~= nil and template:IsA("BasePart")
	if solid or not hasMesh then
		local trunk = post(parent, "PalmTrunk", base, 0, 0, 0, height, 1.2, COL.Bark, Enum.Material.Wood,
			{ CanCollide = solid == true, CanQuery = solid == true, CastShadow = false })
		if hasMesh then
			trunk.Transparency = 1
		end
	end
	if hasMesh then
		local mesh = template:Clone()
		mesh.Name = "PalmTree"
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = true
		mesh.Size = template.Size * math.min(height / 22, height * 0.7 / math.max(template.Size.X, template.Size.Z))
		mesh.CFrame = base * CFrame.new(0, mesh.Size.Y / 2, 0) * CFrame.Angles(0, yaw, 0)
		mesh.Parent = parent
		return
	end
	local top = base * CFrame.new(0, height, 0)
	for i = 0, 5 do
		newPart(parent, "PalmLeaf", Vector3.new(1.8, 0.25, height * 0.42),
			top * CFrame.Angles(0, yaw + math.rad(i * 60 + 15), 0) * CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -height * 0.2),
			COL.Frond, Enum.Material.Grass, DETAIL)
	end
end

-- Indoors, standing on the floor at (x, z) of the indoor frame: a palm in a terracotta pot, or a leafy
-- plant in one.
local function pottedPalm(parent, frame, x, z)
	post(parent, "Pot", frame, x, z, K.Floor, K.Floor + 2.4, 2.6, COL.Pot, Enum.Material.Concrete, { CastShadow = false })
	palm(parent, frame, x, K.Floor + 2.4, z, 8, math.rad((x * 37 + z * 11) % 360), false)
end

local function pottedPlant(parent, frame, x, z)
	post(parent, "Pot", frame, x, z, K.Floor, K.Floor + 2.2, 2.2, COL.Pot, Enum.Material.Concrete, { CastShadow = false })
	newPart(parent, "Leaves", Vector3.new(3.4, 3.4, 3.4), frame * CFrame.new(x, K.Floor + 3.8, z), COL.Leaf, Enum.Material.Grass, BALL)
end

-- Picking -------------------------------------------------------------------------------------------

-- Config.Ambience's area key for a spot (the first rectangle that holds it wins), or nil.
local function areaAt(x, z)
	for _, d in ipairs(Ambience.Districts) do
		local r = d.Rect
		if x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] then
			return d.Area
		end
	end
	return nil
end

-- A box's footprint on the map, however it is turned: x0, x1, z0, z1.
local function flat(cf, size)
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * size.X / 2 + math.abs(u.X) * size.Y / 2 + math.abs(l.X) * size.Z / 2
	local ez = math.abs(r.Z) * size.X / 2 + math.abs(u.Z) * size.Y / 2 + math.abs(l.Z) * size.Z / 2
	return cf.X - ex, cf.X + ex, cf.Z - ez, cf.Z + ez
end

-- Every footprint a tower must stay off, grown by KeepClearMargin: the Big Score's lots (Config) and each
-- part in the KeepClear folders (heist sites, homes, showrooms...), part by part, so one far-flung piece
-- of a model never blanks out a whole district.
local function keepClear()
	local m = P.KeepClearMargin
	local list = {}
	for _, r in ipairs(P.KeepClearRects) do
		table.insert(list, { math.min(r[1], r[2]) - m, math.max(r[1], r[2]) + m, math.min(r[3], r[4]) - m, math.max(r[3], r[4]) + m })
	end
	for _, name in ipairs(P.KeepClear) do
		local root = Workspace:FindFirstChild(name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				local x0, x1, z0, z1 = flat(d.CFrame, d.Size)
				table.insert(list, { x0 - m, x1 + m, z0 - m, z1 + m })
			end
		end
	end
	return list
end

local function overlaps(list, x0, x1, z0, z1)
	for _, r in ipairs(list) do
		if x0 < r[2] and x1 > r[1] and z0 < r[4] and z1 > r[3] then
			return true
		end
	end
	return false
end

-- A DecoBuilding's highest Body / Tier box, and the height of its top.
local function topOf(model)
	local top, topY = nil, -math.huge
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == "Body" or p.Name == "Tier") then
			local y = p.Position.Y + p.Size.Y / 2
			if y > topY then
				top, topY = p, y
			end
		end
	end
	return top, topY
end

-- The ground's height at a spot (city ground, roads, Look3's kerbs), 0 if nothing is found.
local function groundY(ctx, pos)
	local hit = Workspace:Raycast(Vector3.new(pos.X, 40, pos.Z), Vector3.new(0, -80, 0), ctx.groundRay)
	return hit and hit.Position.Y or 0
end

-- Room for the street entrance in front of a facade: nothing solid there (a bus shelter, a billboard's
-- legs, the next building). Street furniture (PropService's group, or anything under 3 studs) is fine.
local function doorRoom(ctx, model, entrance)
	ctx.doorParams.FilterDescendantsInstances = { model, ctx.roads, ctx.ground }
	local cf = entrance * CFrame.new(0, K.DoorRoom.Y / 2 + 1, -K.DoorRoom.Z / 2 - 0.5)
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf, K.DoorRoom, ctx.doorParams)) do
		if p.CanCollide and p.CollisionGroup ~= K.PropsGroup and math.max(p.Size.X, p.Size.Y, p.Size.Z) > 3 then
			return false
		end
	end
	return true
end

-- Where the street entrance goes: the facade (from the Body, at ground level) with a road straight out
-- from its middle within RoadReach studs (at least MinRoadGap away) and room for the door. The front
-- (a DecoBuilding faces its street) wins; else the side with the nearest road. Returns the entrance's
-- frame (on the ground at the middle of the facade, -Z = out to the street), or nil.
local function facadeOf(ctx, model, body)
	local cf = body.CFrame
	local faces = {
		{ cf.LookVector, body.Size.Z / 2 }, -- the front
		{ -cf.LookVector, body.Size.Z / 2 },
		{ cf.RightVector, body.Size.X / 2 },
		{ -cf.RightVector, body.Size.X / 2 },
	}
	local best, bestGap = nil, math.huge
	for i, f in ipairs(faces) do
		local n = Vector3.new(f[1].X, 0, f[1].Z).Unit
		local base = Vector3.new(body.Position.X, 0, body.Position.Z) + n * f[2]
		local hit = Workspace:Raycast(base + n * 0.5 + Vector3.new(0, K.RoadProbeY, 0), n * P.RoadReach, ctx.roadRay)
		local gap = hit and hit.Distance + 0.5
		if gap and gap >= P.MinRoadGap and (i == 1 or gap < bestGap) then
			local y = groundY(ctx, base + n) -- just off the wall: on an avenue Look3's kerb starts 2 studs out
			local spot = Vector3.new(base.X, y, base.Z)
			local entrance = CFrame.lookAt(spot, spot + n)
			if doorRoom(ctx, model, entrance) then
				if i == 1 then
					return entrance
				end
				best, bestGap = entrance, gap
			end
		end
	end
	return best
end

-- Drop candidates with another model's parts standing on the roof (a tower sign, a billboard). Only parts
-- whose middle is over a candidate's roof count (roof-line trims sit level with it, and stay).
local function dropCluttered(art, list)
	if #list == 0 then
		return list
	end
	local low = math.huge
	for _, c in ipairs(list) do
		low = math.min(low, c.topY)
	end
	for _, d in ipairs(art:GetDescendants()) do
		if d:IsA("BasePart") and d.Position.Y > low + 0.5 then
			for _, c in ipairs(list) do
				local y = d.Position.Y
				if not c.cluttered and y > c.topY + 0.5 and y < c.topY + 80 then
					local rel = c.top.CFrame:PointToObjectSpace(d.Position)
					if math.abs(rel.X) < c.top.Size.X / 2 + 1 and math.abs(rel.Z) < c.top.Size.Z / 2 + 1 and not d:IsDescendantOf(c.model) then
						c.cluttered = true
					end
				end
			end
		end
	end
	local kept = {}
	for _, c in ipairs(list) do
		if not c.cluttered then
			table.insert(kept, c)
		end
	end
	return kept
end

-- The towers, picked as Config.Apartments says: { model, body, top, topY, entrance } in pick order.
local function pick()
	local city = Workspace:FindFirstChild("City")
	local art = city and city:FindFirstChild("Art")
	local roads = city and city:FindFirstChild("Roads")
	if not art or not roads then
		warn("[ApartmentService] no Workspace.City.Art / Roads: no apartment towers")
		return {}
	end
	local ground = city:FindFirstChild("Ground") or roads
	local ctx = { roads = roads, ground = ground }
	ctx.roadRay = RaycastParams.new()
	ctx.roadRay.FilterType = Enum.RaycastFilterType.Include
	ctx.roadRay.FilterDescendantsInstances = { roads }
	local underfoot = { roads, ground }
	local paint = art:FindFirstChild("RoadPaint") -- Look3's kerbs and sidewalks
	if paint then
		table.insert(underfoot, paint)
	end
	ctx.groundRay = RaycastParams.new()
	ctx.groundRay.FilterType = Enum.RaycastFilterType.Include
	ctx.groundRay.FilterDescendantsInstances = underfoot
	ctx.doorParams = OverlapParams.new()
	ctx.doorParams.FilterType = Enum.RaycastFilterType.Exclude

	local clear = keepClear()
	local list = {}
	for _, folderName in ipairs(P.Folders) do
		local folder = art:FindFirstChild(folderName)
		for _, m in ipairs(folder and folder:GetChildren() or {}) do
			-- (ArtGen's hotels carry a "Sign" on their top tier: a hotel, not an apartment tower.)
			local body = m:IsA("Model") and m.Name == "DecoBuilding" and not m:FindFirstChild("Sign") and m:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				local top, topY = topOf(m)
				local pos = body.Position
				if top and topY >= P.MinTop and math.min(top.Size.X, top.Size.Z) >= P.MinRoof and top.CFrame.UpVector.Y > 0.99
					and pos.Y - body.Size.Y / 2 < 3 and P.Areas[areaAt(pos.X, pos.Z) or ""] then
					local x0, x1, z0, z1 = flat(body.CFrame, body.Size)
					if not overlaps(clear, x0, x1, z0, z1) then
						table.insert(list, { model = m, body = body, top = top, topY = topY })
					end
				end
			end
		end
	end
	list = dropCluttered(art, list)
	-- By position, then greedily: each one taken must be Spacing from all taken before it, and needs a
	-- street entrance.
	table.sort(list, function(a, b)
		local pa, pb = a.body.Position, b.body.Position
		if pa.X ~= pb.X then
			return pa.X < pb.X
		end
		return pa.Z < pb.Z
	end)
	local picked = {}
	for _, c in ipairs(list) do
		if #picked >= Apartments.Count.Max then
			break
		end
		local far = true
		for _, o in ipairs(picked) do
			local d = c.body.Position - o.body.Position
			if Vector3.new(d.X, 0, d.Z).Magnitude < P.Spacing then
				far = false
				break
			end
		end
		if far then
			c.entrance = facadeOf(ctx, c.model, c.body)
			if c.entrance then
				table.insert(picked, c)
			end
		end
	end
	if #picked < Apartments.Count.Min then
		warn(string.format("[ApartmentService] only %d apartment tower(s) fit the rules (%d candidates): want %d",
			#picked, #list, Apartments.Count.Min))
	end
	return picked
end

-- A picked tower's record. Frames: frame = the roof (origin at the middle of the top of the highest
-- part, -Z toward the side the street door is on), indoor = the indoor part's middle on the roof (at the
-- back, Inset in from the edge), terrace = the middle of the indoor part's front glass (the terrace runs
-- out from it to -Z). w / d = the roof's width (along x) and depth (along z) in the roof frame.
local function setup(c, index)
	local top = c.top
	local n = c.entrance.LookVector
	local along = math.abs(n:Dot(top.CFrame.LookVector)) > 0.7
	local w = along and top.Size.X or top.Size.Z
	local d = along and top.Size.Z or top.Size.X
	local roof = top.Position + Vector3.new(0, top.Size.Y / 2, 0)
	local frame = CFrame.lookAt(roof, roof + n)
	local indoor = frame * CFrame.new(0, 0, d / 2 - H.Inset - K.IndoorD / 2)
	return {
		Name = Apartments.Names[index] or ("Tower " .. index),
		Kind = Apartments.Kind,
		Door = (c.entrance * CFrame.new(0, 0, -4)).Position,
		index = index,
		style = Apartments.Styles[(index - 1) % #Apartments.Styles + 1],
		model = c.model,
		topY = c.topY,
		entrance = c.entrance,
		frame = frame,
		indoor = indoor,
		terrace = frame * CFrame.new(0, 0, d / 2 - H.Inset - K.IndoorD),
		w = w,
		d = d,
		-- In the lobby facing the room and the glass, out of the elevator prompt's reach (8.7 studs).
		lobby = indoor * CFrame.new(0, K.Floor + 3.5, 0.5),
		elevator = (indoor * CFrame.new(0, K.Floor + 3.5, 9.2)).Position,
		-- On the sidewalk under the canopy's edge, facing the street.
		exit = c.entrance * CFrame.new(0, 3.5, -7),
		doorPrompt = (c.entrance * CFrame.new(0, 3, -1.6)).Position,
	}
end

-- Restyle's rooftop AC boxes and water tanks stood where the penthouse goes.
local function clearRoof(t)
	for _, p in ipairs(t.model:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == "RoofAC" or p.Name == "WaterTank") and p.Position.Y > t.topY - 0.5 then
			p:Destroy()
		end
	end
end

-- The street entrance -------------------------------------------------------------------------------

-- In the entrance frame (origin on the ground at the middle of the facade, -Z out to the street). The
-- facade is z 0; Restyle's shopfront glass lies flush on it (0.3 thick), so the door starts at z -0.4
-- (the limestone runs back to the wall over it: on a side facade there is no shopfront to fill the gap).
local function buildEntrance(model, t)
	local E = t.entrance
	-- Shop signs over this stretch of the ground floor go, and so does ArtKit's front awning (a tower
	-- under 90 studs has one, 11 up and 6 out: right where the canopy goes). The canopy and the name
	-- sign take their place.
	for _, p in ipairs(t.model:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == "ShopSign" or p.Name == "Awning") then
			local rel = E:PointToObjectSpace(p.Position)
			if math.abs(rel.X) < 9.5 + p.Size.X / 2 and math.abs(rel.Z) < 9 and rel.Y < 20 then
				p:Destroy()
			end
		end
	end
	-- Light limestone round the doorway; the lobby behind the doors is a panel set back in it: dark by
	-- day, warm lamplight after dark.
	for _, span in ipairs({ { -8.5, -5.4, 0, 14 }, { 5.4, 8.5, 0, 14 }, { -5.4, 5.4, 10.4, 14 } }) do
		box(model, "Cladding", E, span[1], span[2], span[3], span[4], -1, 0, COL.Stone, Enum.Material.Limestone)
	end
	nightNeon(box(model, "LobbyGlow", E, -5.4, 5.4, 0, 10.4, -0.7, -0.4, COL.TrimDay, Enum.Material.Metal, DETAIL), COL.RoomGlow)
	-- The glass double door in a dark metal frame, with long steel pulls and a mat in front.
	box(model, "DoorFrame", E, -5.4, -4.9, 0, 10.4, -1.2, -0.7, COL.DarkMetal, Enum.Material.Metal)
	box(model, "DoorFrame", E, 4.9, 5.4, 0, 10.4, -1.2, -0.7, COL.DarkMetal, Enum.Material.Metal)
	box(model, "DoorFrame", E, -4.9, 4.9, 9.9, 10.4, -1.2, -0.7, COL.DarkMetal, Enum.Material.Metal) -- between the posts
	box(model, "DoorFrame", E, -0.15, 0.15, 0, 9.9, -1.2, -0.7, COL.DarkMetal, Enum.Material.Metal) -- where the two doors meet
	for _, x in ipairs({ -1, 1 }) do
		box(model, "DoorGlass", E, x * 0.15, x * 4.9, 0, 9.9, -1, -0.8, COL.DoorGlass, Enum.Material.Glass,
			{ Transparency = 0.35, Reflectance = 0.1, CastShadow = false })
		box(model, "DoorPull", E, x * 0.6, x * 0.9, 3.8, 7, -1.5, -1.2, COL.Steel, Enum.Material.Metal, DETAIL)
	end
	box(model, "Doormat", E, -4.6, 4.6, 0, 0.1, -4, -1.2, COL.Slate, Enum.Material.Fabric, DETAIL)
	-- A dark metal canopy on two tie rods, with a neon line under its front edge (after dark) and two
	-- downlights (after dark).
	box(model, "Canopy", E, -9, 9, 11, 11.7, -8.4, -1, COL.DarkMetal, Enum.Material.Metal, { CanCollide = false, CanQuery = false })
	neon(model, E, -9, 9, 10.8, 11, -8.4, -8.1, t.style.Neon)
	for _, x in ipairs({ -8.4, 8.4 }) do
		rod(model, E, Vector3.new(x, 11.7, -8), Vector3.new(x, 17.5, -0.05), 0.25, COL.DarkMetal)
	end
	for _, x in ipairs({ -4.5, 4.5 }) do
		downlight(nightLamp(box(model, "CanopyLight", E, x - 0.5, x + 0.5, 10.85, 11, -5.5, -4.5, COL.LampDay, Enum.Material.SmoothPlastic, DETAIL),
			COL.Warm), COL.Warm, 16, L.Canopy)
	end
	-- The name, lit, on the canopy's front edge (a neon line along its top after dark).
	local sign = box(model, "NameSign", E, -7.6, 7.6, 11.7, 14.5, -8.4, -8, COL.Dark, Enum.Material.Metal, DETAIL)
	signGui(sign, Enum.NormalId.Front, string.upper(t.Name), "RESIDENCES · PENTHOUSE TOURS", COL.White, COL.Gold, 1.6)
	neon(model, E, -7.6, 7.6, 14.5, 14.75, -8.4, -8, t.style.Neon)
	-- Wall lamps on the limestone either side of the door (warm after dark).
	for _, x in ipairs({ -7, 7 }) do
		light(nightLamp(box(model, "WallLamp", E, x - 0.3, x + 0.3, 6.4, 8.2, -1.4, -1, COL.LampDay, Enum.Material.SmoothPlastic, DETAIL), COL.Warm),
			COL.Warm, 10, 0.8)
	end
	-- Palms in concrete planters either side.
	for _, x in ipairs({ -12, 12 }) do
		box(model, "Planter", E, x - 1.7, x + 1.7, 0, 2.6, -4.4, -1, COL.Concrete, Enum.Material.Concrete)
		palm(model, E, x, 2.6, -2.7, 8, math.rad(x * 9), true) -- its crown clear of the canopy's edge
	end
	-- The prompt hangs in front of the glass.
	local anchor = newPart(model, "DoorPrompt", Vector3.new(1, 1, 1), CFrame.new(t.doorPrompt), COL.White, nil,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local prompt = makePrompt(anchor, "ApartmentDoor", "Enter", t.Name, Apartments.PromptRange)
	prompt.Triggered:Connect(function(player)
		enter(player, t)
	end)
end

-- The penthouse ------------------------------------------------------------------------------------

-- Paving, the indoor floor, the glass walls, the flat roof and its lights, the partitions and the core.
local function buildShell(model, t)
	local F, I = t.frame, t.indoor
	local FY, CEIL = K.Floor, K.Floor + H.Ceiling
	box(model, "Terrace", F, -t.w / 2, t.w / 2, 0, K.Deck, -t.d / 2, t.d / 2, COL.Paver, Enum.Material.Pavement)
	box(model, "Floor", I, -25, 25, K.Deck, FY, -16, 16, COL.Marble, Enum.Material.Marble)
	-- Floor-to-ceiling glass all round (the terrace door is the gap in the front at x -1..7), dark metal
	-- mullions, and the door's sliding panel pushed open behind the glass on its right.
	local glass = { Transparency = H.GlassTransparency, Reflectance = 0.05, CastShadow = false }
	for _, g in ipairs({
		{ -25, -1, -16, -15.6 }, { 7, 25, -16, -15.6 }, -- the front, either side of the terrace door
		{ -25, 25, 15.6, 16 }, -- the back
		{ -25, -24.6, -15.6, 15.6 }, { 24.6, 25, -15.6, 15.6 }, -- the sides
	}) do
		box(model, "GlassWall", I, g[1], g[2], FY, CEIL, g[3], g[4], COL.Glass, Enum.Material.Glass, glass)
	end
	box(model, "SlidingDoor", I, 7.2, 14.6, FY, CEIL - 0.6, -15.5, -15.25, COL.Glass, Enum.Material.Glass,
		{ Transparency = H.GlassTransparency, CanCollide = false, CanQuery = false, CastShadow = false })
	box(model, "DoorTrack", I, -1, 7, FY, FY + 0.06, -16.2, -15.4, COL.DarkMetal, Enum.Material.Metal, DETAIL)
	for _, m in ipairs(K.Mullions) do
		box(model, "Mullion", I, m[1] - 0.25, m[1] + 0.25, FY, CEIL, m[2] - 0.25, m[2] + 0.25, COL.DarkMetal, Enum.Material.Metal)
	end
	-- The flat roof (out over the terrace door), a neon line along its front edge after dark, and the
	-- tower's name in letters standing on it, facing the street side.
	box(model, "Roof", I, -26, 26, CEIL, CEIL + 1, -18, 17, COL.Ceiling, Enum.Material.Plaster)
	neon(model, I, -26, 26, CEIL + 0.25, CEIL + 0.75, -18.2, -18, t.style.Neon)
	local roofSign = box(model, "RoofSign", I, -14, 14, CEIL + 1, CEIL + 5, -17.8, -17.4, COL.White, Enum.Material.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	signGui(roofSign, Enum.NormalId.Front, string.upper(t.Name), nil, COL.White, nil, 1)
	-- Recessed ceiling lights: soft discs flush with the ceiling, most with a low light of their own.
	for _, d in ipairs(K.Downlights) do
		local spot = newPart(model, "CeilingLight", Vector3.new(0.2, 2.4, 2.4), I * CFrame.new(d[1], CEIL - 0.1, d[2]) * CFrame.Angles(0, 0, math.rad(90)),
			COL.Downlight, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CastShadow = false })
		if d[3] then
			light(spot, COL.Warm, L.CeilingRange, L.Ceiling)
		end
	end
	-- Partitions to the ceiling: the TV wall between the living room and the bedroom, the bedroom's wall on
	-- the lobby (its doorway by the TV wall), the bathroom nook's two walls with a frosted panel beside its
	-- doorway, and the elevator core at the back.
	box(model, "Wall", I, -24.6, -7, FY, CEIL, -0.6, 0, COL.Plaster, Enum.Material.Plaster) -- the TV wall
	box(model, "Wall", I, -7.6, -7, FY, CEIL, 4.6, 15.6, COL.Plaster, Enum.Material.Plaster) -- the bedroom on the lobby
	box(model, "Wall", I, -7.6, -7, FY + 9.4, CEIL, 0, 4.6, COL.Plaster, Enum.Material.Plaster) -- over the bedroom door
	box(model, "Wall", I, 16, 16.6, FY, CEIL, 7, 15.6, COL.Plaster, Enum.Material.Plaster) -- the nook on the kitchen
	box(model, "Wall", I, 16, 18.6, FY, CEIL, 6.4, 7, COL.Plaster, Enum.Material.Plaster) -- the nook's front
	box(model, "Wall", I, 18.6, 24.6, FY + 9.4, CEIL, 6.4, 7, COL.Plaster, Enum.Material.Plaster) -- over its doorway and panel
	box(model, "FrostedGlass", I, 21.8, 24.6, FY, FY + 9.4, 6.4, 7, COL.Frosted, Enum.Material.Glass, { Transparency = 0.25, CastShadow = false })
	box(model, "Core", I, -7, 7, FY, CEIL, 10, 15.6, COL.Plaster, Enum.Material.Plaster)
end

-- The elevator lobby: brushed steel doors in a dark frame on the core, the floor sign over them, a lit
-- call button, a slate inlay on the floor and a plant. Its prompt takes you down.
local function buildElevator(model, t)
	local I = t.indoor
	local FY = K.Floor
	box(model, "ElevatorDoor", I, -2.5, 0, FY, FY + 9, 9.7, 10, COL.Steel, Enum.Material.Metal, { Reflectance = 0.15 })
	box(model, "ElevatorDoor", I, 0, 2.5, FY, FY + 9, 9.7, 10, COL.Steel, Enum.Material.Metal, { Reflectance = 0.15 })
	box(model, "ElevatorFrame", I, -3.1, -2.5, FY, FY + 9.6, 9.6, 10, COL.DarkMetal, Enum.Material.Metal)
	box(model, "ElevatorFrame", I, 2.5, 3.1, FY, FY + 9.6, 9.6, 10, COL.DarkMetal, Enum.Material.Metal)
	box(model, "ElevatorFrame", I, -2.5, 2.5, FY + 9, FY + 9.6, 9.6, 10, COL.DarkMetal, Enum.Material.Metal) -- between the posts
	local floorSign = box(model, "FloorSign", I, -1.6, 1.6, FY + 10, FY + 11.2, 9.8, 10, COL.Dark, Enum.Material.Metal, DETAIL)
	signGui(floorSign, Enum.NormalId.Front, "PENTHOUSE", nil, COL.Amber, nil, 1.2)
	box(model, "CallPanel", I, 3.6, 4.4, FY + 4, FY + 5.8, 9.85, 10, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "CallButton", I, 3.8, 4.2, FY + 4.7, FY + 5.1, 9.78, 9.85, COL.Downlight, Enum.Material.Neon, DETAIL)
	box(model, "Inlay", I, -4.5, 4.5, FY, FY + 0.04, 1.5, 9.3, COL.Slate, Enum.Material.Slate, DETAIL)
	pottedPlant(model, I, 5.6, 8.4)
	local anchor = newPart(model, "ElevatorPrompt", Vector3.new(1, 1, 1), CFrame.new(t.elevator), COL.White, nil,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local prompt = makePrompt(anchor, "ApartmentElevator", "Elevator", "Down to the street", Apartments.ElevatorRange)
	prompt.Triggered:Connect(function(player)
		down(player, t)
	end)
end

-- The living room (front left): a rug, a grey sofa facing the TV with two seats and accent cushions, a
-- walnut coffee table, two leather armchairs turned to the sofa, the TV on the bedroom wall over a
-- console (a backlight after dark), a floor lamp and two potted palms by the glass.
local function buildLiving(model, t)
	local I = t.indoor
	local FY = K.Floor
	local accent = t.style.Accent
	box(model, "Rug", I, -24, -10, FY, FY + 0.08, -14.5, -2, COL.Rug, Enum.Material.Carpet, DETAIL)
	box(model, "Sofa", I, -23.4, -15.6, FY, FY + 1.2, -12, -9, COL.Sofa, Enum.Material.Fabric)
	box(model, "SofaBack", I, -24, -15, FY, FY + 3.6, -12.8, -12, COL.Sofa, Enum.Material.Fabric)
	box(model, "SofaArm", I, -24, -23.4, FY, FY + 2.4, -12, -9, COL.Sofa, Enum.Material.Fabric)
	box(model, "SofaArm", I, -15.6, -15, FY, FY + 2.4, -12, -9, COL.Sofa, Enum.Material.Fabric)
	for _, x in ipairs({ -21.45, -17.55 }) do
		-- Facing the TV (+Z); EXIT stands you in front of it, short of the coffee table.
		seat(model, I, x, FY + 1.45, -10.5, Vector3.new(3.8, 0.5, 2.9), math.pi, COL.Cushion, Enum.Material.Fabric, Vector2.new(x, -8))
		box(model, "Cushion", I, x - 1, x + 1, FY + 1.7, FY + 3.3, -11.95, -11.5, accent, Enum.Material.Fabric, DETAIL)
	end
	box(model, "CoffeeTable", I, -22, -17, FY + 1.4, FY + 1.7, -7, -4.5, COL.Walnut, Enum.Material.WoodPlanks)
	box(model, "TableBase", I, -21.4, -17.6, FY, FY + 1.4, -6.5, -5, COL.DarkMetal, Enum.Material.Metal)
	box(model, "Books", I, -20.6, -19.2, FY + 1.7, FY + 2, -6.2, -5.3, accent, Enum.Material.SmoothPlastic, DETAIL)
	for _, z in ipairs({ -9, -4 }) do
		box(model, "Armchair", I, -13, -10.4, FY, FY + 1.2, z - 1.5, z + 1.5, COL.Leather, Enum.Material.Leather)
		box(model, "ArmchairBack", I, -10.4, -9.8, FY, FY + 3.4, z - 1.5, z + 1.5, COL.Leather, Enum.Material.Leather)
		box(model, "ArmchairArm", I, -13, -10.4, FY + 1.2, FY + 2.3, z - 1.5, z - 1.1, COL.Leather, Enum.Material.Leather)
		box(model, "ArmchairArm", I, -13, -10.4, FY + 1.2, FY + 2.3, z + 1.1, z + 1.5, COL.Leather, Enum.Material.Leather)
		-- Facing the sofa (-X); EXIT stands you in front of it.
		seat(model, I, -11.7, FY + 1.45, z, Vector3.new(2.2, 0.5, 2.6), math.pi / 2, COL.Leather, Enum.Material.Leather, Vector2.new(-14.2, z))
	end
	box(model, "TVConsole", I, -23.5, -15.5, FY, FY + 1.8, -2.4, -0.6, COL.Walnut, Enum.Material.WoodPlanks)
	local tv = box(model, "TV", I, -24, -15, FY + 3.8, FY + 8.8, -0.9, -0.6, COL.Dark, Enum.Material.SmoothPlastic)
	tvScreen(tv)
	neon(model, I, -24, -15, FY + 3.5, FY + 3.8, -0.75, -0.6, t.style.Neon)
	box(model, "LampPole", I, -12.8, -12.2, FY, FY + 7, -1.95, -1.35, COL.DarkMetal, Enum.Material.Metal, DETAIL)
	light(nightLamp(box(model, "LampShade", I, -13.6, -11.4, FY + 7, FY + 8.8, -2.75, -0.75, COL.LampDay, Enum.Material.SmoothPlastic, DETAIL),
		COL.Warm), COL.Warm, 16, L.Lamp)
	pottedPalm(model, I, -23, -14.3)
	pottedPalm(model, I, -3.6, -14.2)
end

-- The kitchen (back right) and the dining table: a steel fridge by the core, walnut cabinets under a
-- marble worktop with a cooktop, a sink and a hood; the island with three stools on the lobby side and two
-- pendants over it (warm after dark); the dining table by the glass with four chairs.
local function buildKitchen(model, t)
	local I = t.indoor
	local FY, CEIL = K.Floor, K.Floor + H.Ceiling
	box(model, "Fridge", I, 7, 10, FY, FY + 9.2, 12.4, 15.6, COL.Steel, Enum.Material.Metal, { Reflectance = 0.1 })
	box(model, "FridgeHandle", I, 9.2, 9.5, FY + 3, FY + 7, 12.1, 12.4, COL.DarkMetal, Enum.Material.Metal, DETAIL)
	box(model, "Cabinets", I, 10, 16, FY, FY + 3.3, 13.4, 15.6, COL.Walnut, Enum.Material.WoodPlanks)
	box(model, "Worktop", I, 10, 16, FY + 3.3, FY + 3.6, 13.2, 15.6, COL.Marble, Enum.Material.Marble)
	box(model, "Cooktop", I, 13, 15, FY + 3.6, FY + 3.65, 13.8, 15.2, COL.Dark, Enum.Material.Glass, DETAIL)
	box(model, "Sink", I, 10.8, 12.4, FY + 3.6, FY + 3.64, 13.9, 15.1, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "Tap", I, 11.5, 11.7, FY + 3.6, FY + 4.8, 15.1, 15.3, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "Hood", I, 13.2, 14.8, CEIL - 2.6, CEIL, 13.8, 15.2, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "Island", I, 8.4, 17.6, FY, FY + 3.4, 3.4, 5.6, COL.Walnut, Enum.Material.WoodPlanks)
	box(model, "IslandTop", I, 7.8, 18.2, FY + 3.4, FY + 3.75, 2.6, 6, COL.Marble, Enum.Material.Marble)
	-- { x, EXIT's x }: EXIT stands you behind the stool, the last one's clear of the juice bar's stool.
	for _, s in ipairs({ { 9.8, 9.8 }, { 13, 13 }, { 16.2, 15.8 } }) do
		stool(model, I, s[1], 1.4, math.pi, Vector2.new(s[2], -0.3)) -- facing the island (+Z)
	end
	for _, x in ipairs({ 10.5, 15.5 }) do
		box(model, "PendantCord", I, x - 0.05, x + 0.05, CEIL - 3.4, CEIL, 4.45, 4.55, COL.DarkMetal, Enum.Material.Metal, DETAIL)
		local globe = newPart(model, "Pendant", Vector3.new(1.4, 1.4, 1.4), I * CFrame.new(x, CEIL - 4, 4.5), COL.LampDay, Enum.Material.SmoothPlastic, BALL)
		light(nightLamp(globe, COL.Warm), COL.Warm, 12, L.Lamp)
	end
	box(model, "DinnerTable", I, 8, 16, FY + 3, FY + 3.3, -8.2, -3.8, COL.Walnut, Enum.Material.WoodPlanks)
	for _, x in ipairs({ 9.7, 14.3 }) do
		box(model, "TableLeg", I, x - 0.5, x + 0.5, FY, FY + 3, -6.5, -5.5, COL.DarkMetal, Enum.Material.Metal)
	end
	for _, x in ipairs({ 10, 14 }) do
		-- EXIT: behind a chair on the glass side, beside one on the island side (the stools are behind it).
		chair(model, I, x, -9.6, math.pi, Vector2.new(x, -12.6)) -- on the glass side, facing the table (+Z)
		chair(model, I, x, -2.4, 0, Vector2.new(x < 12 and 6.5 or 17.5, -2.4)) -- on the island side, facing it (-Z)
	end
end

-- The juice bar along the right-hand glass (juice and soda only): a walnut bar under a marble top with a
-- neon line under its edge (after dark), a back counter with three juice dispensers, a fruit bowl, a sign
-- and two stools.
local function buildJuiceBar(model, t)
	local I = t.indoor
	local FY = K.Floor
	box(model, "Bar", I, 20.6, 22.4, FY, FY + 3.5, -7, 2, COL.Walnut, Enum.Material.WoodPlanks)
	box(model, "BarTop", I, 20.2, 22.6, FY + 3.5, FY + 3.8, -7.2, 2.2, COL.Marble, Enum.Material.Marble)
	neon(model, I, 20.45, 20.6, FY + 3.1, FY + 3.4, -7, 2, t.style.Neon)
	box(model, "BackCounter", I, 23.4, 24.6, FY, FY + 3.2, -7, 2, COL.Plaster, Enum.Material.Plaster)
	for i, juice in ipairs(K.Juices) do
		post(model, "Dispenser", I, 24, -5.4 + (i - 1) * 2.6, FY + 3.2, FY + 5, 1.2, juice, Enum.Material.Glass,
			{ Transparency = 0.15, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	post(model, "FruitBowl", I, 21.4, -5.4, FY + 3.8, FY + 4.2, 2, COL.White, Enum.Material.SmoothPlastic, DETAIL)
	for i, fruit in ipairs(K.Fruit) do
		newPart(model, "Fruit", Vector3.new(0.7, 0.7, 0.7), I * CFrame.new(21 + (i - 1) * 0.4, FY + 4.4, -5.6 + (i % 2) * 0.4), fruit,
			Enum.Material.SmoothPlastic, BALL)
	end
	local barSign = box(model, "BarSign", I, 24.2, 24.5, FY + 6, FY + 8.2, -6.5, 1.5, COL.Dark, Enum.Material.Metal, DETAIL)
	signGui(barSign, Enum.NormalId.Left, "JUICE BAR", "FRESH JUICE · SODA · SMOOTHIES", t.style.Neon, COL.Gold, 1) -- Left = -X, the room
	for _, s in ipairs({ { -4.6, -7.8 }, { -0.4, 2.8 } }) do -- { z, EXIT's z: off the outer side of each }
		stool(model, I, 19, s[1], -math.pi / 2, Vector2.new(19, s[2])) -- facing the bar (+X)
	end
end

-- The bedroom (back left, behind the TV wall): the bed against the back glass (an upholstered headboard,
-- walnut frame, white linen, a blanket in the tower's accent), nightstands with lamps (warm after dark), a
-- rug, a dresser on the TV wall and a plant.
local function buildBedroom(model, t)
	local I = t.indoor
	local FY = K.Floor
	box(model, "Rug", I, -22, -10, FY, FY + 0.08, 1.2, 8, COL.Rug, Enum.Material.Carpet, DETAIL)
	box(model, "Headboard", I, -21, -11, FY, FY + 5.5, 15, 15.6, COL.Headboard, Enum.Material.Fabric)
	box(model, "BedFrame", I, -20.5, -11.5, FY, FY + 1.4, 4.5, 15, COL.Walnut, Enum.Material.WoodPlanks)
	box(model, "Mattress", I, -20.3, -11.7, FY + 1.4, FY + 2.6, 4.8, 14.8, COL.Linen, Enum.Material.Fabric)
	box(model, "Blanket", I, -20.4, -11.6, FY + 2, FY + 2.8, 4.7, 10.6, t.style.Accent, Enum.Material.Fabric, DETAIL)
	for _, x in ipairs({ -18, -14 }) do
		box(model, "Pillow", I, x - 1.6, x + 1.6, FY + 2.6, FY + 3.3, 12.6, 14.6, COL.White, Enum.Material.Fabric, DETAIL)
	end
	for _, x in ipairs({ -22.4, -9.6 }) do
		box(model, "Nightstand", I, x - 1.2, x + 1.2, FY, FY + 2.2, 13, 15.4, COL.Walnut, Enum.Material.WoodPlanks)
		box(model, "LampStem", I, x - 0.1, x + 0.1, FY + 2.2, FY + 2.8, 14.1, 14.3, COL.DarkMetal, Enum.Material.Metal, DETAIL)
		light(nightLamp(box(model, "BedsideLamp", I, x - 0.6, x + 0.6, FY + 2.8, FY + 4, 13.6, 14.8, COL.LampDay, Enum.Material.SmoothPlastic, DETAIL),
			COL.Warm), COL.Warm, 12, L.Lamp)
	end
	box(model, "Dresser", I, -24, -18.5, FY, FY + 3, 0, 1.8, COL.Walnut, Enum.Material.WoodPlanks)
	pottedPlant(model, I, -23, 3.4)
end

-- The bathroom nook (back right corner): tiles, a marble vanity with a basin, a tap and a mirror under a
-- soft strip light (always on), a walk-in shower behind a glass screen, a towel in the tower's accent and
-- a plant.
local function buildBathroom(model, t)
	local I = t.indoor
	local FY = K.Floor
	box(model, "Tiles", I, 16.6, 24.6, FY, FY + 0.04, 7, 15.6, COL.Tile, Enum.Material.CeramicTiles, DETAIL)
	box(model, "Vanity", I, 16.6, 18.8, FY, FY + 3.1, 9, 13, COL.Marble, Enum.Material.Marble)
	post(model, "Basin", I, 17.8, 11, FY + 3.1, FY + 3.35, 1.6, COL.White, Enum.Material.SmoothPlastic, DETAIL)
	box(model, "Tap", I, 16.8, 17, FY + 3.1, FY + 4.1, 10.9, 11.1, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "Mirror", I, 16.6, 16.75, FY + 4.4, FY + 8.6, 9.4, 12.6, COL.Mirror, Enum.Material.Glass,
		{ Reflectance = 0.35, CanCollide = false, CanQuery = false, CastShadow = false })
	box(model, "MirrorLight", I, 16.6, 16.8, FY + 8.7, FY + 8.9, 9.4, 12.6, COL.Downlight, Enum.Material.Neon, DETAIL)
	box(model, "ShowerTray", I, 21, 24.6, FY, FY + 0.25, 12, 15.6, COL.White, Enum.Material.SmoothPlastic)
	box(model, "ShowerScreen", I, 21, 24.6, FY + 0.25, FY + 8.5, 11.9, 12.05, COL.Glass, Enum.Material.Glass, { Transparency = 0.6, CastShadow = false })
	box(model, "ShowerPipe", I, 23.7, 23.9, FY + 6, FY + 9.6, 15.35, 15.55, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "ShowerHead", I, 22.9, 24.3, FY + 9.4, FY + 9.6, 13.8, 15.5, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "TowelRail", I, 16.8, 18.4, FY + 7, FY + 7.2, 7, 7.35, COL.Steel, Enum.Material.Metal, DETAIL)
	box(model, "Towel", I, 16.9, 18.3, FY + 4.2, FY + 7, 7, 7.2, t.style.Accent, Enum.Material.Fabric, DETAIL)
	pottedPlant(model, I, 23.4, 8.4)
end

-- Three art panels, each with a neon line under it (after dark): a sun over the sea on the core beside
-- the elevator, two colour blocks on the bedroom wall in the lobby, a sun and a stripe on the nook's wall
-- by the kitchen.
local function buildArt(model, t)
	local I = t.indoor
	local FY = K.Floor
	local accent, glow = t.style.Accent, t.style.Neon
	box(model, "Canvas", I, -6.4, -3.8, FY + 3.4, FY + 9.4, 9.8, 10, COL.Canvas, Enum.Material.SmoothPlastic, DETAIL)
	disc(model, "ArtSun", I, -5.1, FY + 7.6, 9.75, 0.1, 1.6, "Z", COL.ArtSun, Enum.Material.SmoothPlastic)
	box(model, "ArtSea", I, -6.2, -4, FY + 4.6, FY + 6.2, 9.72, 9.8, COL.ArtSea, Enum.Material.SmoothPlastic, DETAIL)
	neon(model, I, -6.4, -3.8, FY + 3, FY + 3.25, 9.8, 10, glow)
	box(model, "Canvas", I, -7, -6.8, FY + 3.4, FY + 8.8, 5.4, 9.4, COL.Canvas, Enum.Material.SmoothPlastic, DETAIL)
	box(model, "ArtBlock", I, -6.8, -6.72, FY + 4, FY + 6.6, 5.8, 7.6, accent, Enum.Material.SmoothPlastic, DETAIL)
	box(model, "ArtBlock", I, -6.8, -6.68, FY + 5.6, FY + 8.2, 7, 9, COL.ArtSun, Enum.Material.SmoothPlastic, DETAIL) -- proud of the first
	neon(model, I, -7, -6.8, FY + 3, FY + 3.25, 5.4, 9.4, glow)
	box(model, "Canvas", I, 15.8, 16, FY + 4, FY + 9, 7.6, 12, COL.Canvas, Enum.Material.SmoothPlastic, DETAIL)
	disc(model, "ArtSun", I, 15.75, FY + 7.4, 9.8, 0.1, 1.8, "X", COL.ArtSun, Enum.Material.SmoothPlastic)
	box(model, "ArtSea", I, 15.72, 15.8, FY + 5, FY + 5.6, 8, 11.6, COL.ArtSea, Enum.Material.SmoothPlastic, DETAIL)
	neon(model, I, 15.8, 16, FY + 3.6, FY + 3.85, 7.6, 12, glow)
end

-- The terrace (from the front glass out to the street-side railing): the pool on a teak deck left of the
-- terrace door (limestone coping, a tiled floor under clear blue water with a soft light in it that is
-- always on, a strip along its far side after dark; just to look at, or wade in), three sun loungers facing
-- the view with cushions you can sit on, a parasol, palms in concrete planters along the railing and wall
-- lights either side of the door (warm after dark).
local function buildTerrace(model, t)
	local T = t.terrace
	local deck = K.Deck
	local depth = t.d - H.Inset - K.IndoorD -- from the glass to the street-side edge (21 on the smallest roof)
	box(model, "PoolDeck", T, -24.5, -1.5, deck, deck + 0.1, -15.6, -2, COL.Teak, Enum.Material.WoodPlanks)
	for _, c in ipairs({ { -22.8, -3.2, -13.8, -13 }, { -22.8, -3.2, -5, -4.2 }, { -22.8, -22, -13, -5 }, { -4, -3.2, -13, -5 } }) do
		box(model, "PoolCoping", T, c[1], c[2], deck, deck + 1.6, c[3], c[4], COL.Coping, Enum.Material.Limestone)
	end
	box(model, "PoolFloor", T, -22, -4, deck, deck + 0.2, -13, -5, COL.PoolTile, Enum.Material.CeramicTiles)
	local water = box(model, "PoolWater", T, -22, -4, deck + 0.2, deck + 1.4, -13, -5, COL.PoolWater, Enum.Material.Glass,
		{ Transparency = 0.35, Reflectance = 0.1, CanCollide = false, CanQuery = false, CastShadow = false })
	light(water, COL.PoolLight, 12, L.Pool)
	neon(model, T, -22, -4, deck + 0.3, deck + 0.5, -5.3, -5, COL.PoolLight)
	for _, x in ipairs({ 10, 14.5, 19 }) do
		box(model, "Lounger", T, x - 1.4, x + 1.4, deck, deck + 0.9, -10.5, -3.5, COL.Teak, Enum.Material.WoodPlanks)
		-- Facing the view (-Z); EXIT stands you at its foot.
		seat(model, T, x, deck + 1.1, -8, Vector3.new(2.6, 0.4, 4.6), 0, COL.Linen, Enum.Material.Fabric, Vector2.new(x, -12.2))
		-- The back rest rises toward the building (a turn of -55 degrees lifts its +Z end).
		newPart(model, "LoungerBack", Vector3.new(2.6, 0.4, 3.2), T * CFrame.new(x, deck + 2.3, -4.6) * CFrame.Angles(math.rad(-55), 0, 0),
			COL.Linen, Enum.Material.Fabric, DETAIL)
	end
	post(model, "ParasolPole", T, 23.5, -7, deck, deck + 7.4, 0.3, COL.White, Enum.Material.Metal, DETAIL)
	post(model, "Parasol", T, 23.5, -7, deck + 7.2, deck + 7.6, 7, t.style.Accent, Enum.Material.Fabric, SHADE)
	local front = -depth + 3.2
	for _, x in ipairs({ -t.w / 2 + 3.2, 1.5, t.w / 2 - 3.2 }) do
		box(model, "Planter", T, x - 1.8, x + 1.8, deck, deck + 2.6, front - 1.8, front + 1.8, COL.Concrete, Enum.Material.Concrete)
		palm(model, T, x, deck + 2.6, front, 13, math.rad(x * 7), true)
	end
	for _, x in ipairs({ -1, 7 }) do
		light(nightLamp(box(model, "WallLight", T, x - 0.3, x + 0.3, K.Floor + 7.8, K.Floor + 9, -0.45, -0.05, COL.LampDay, Enum.Material.SmoothPlastic,
			DETAIL), COL.Warm), COL.Warm, 14, L.Lamp)
	end
end

-- Glass railings Rail studs tall round every edge of the roof, a handrail on top, and an invisible wall
-- above them up to Guard (higher than a jump from a planter or a lounger).
local function buildRailings(model, t)
	local F = t.frame
	local w, d = t.w / 2, t.d / 2
	local top = K.Deck + H.Rail
	for _, e in ipairs({
		{ -w, w, -d, -d + 0.4 }, -- the street side
		{ -w, w, d - 0.4, d }, -- the back
		{ -w, -w + 0.4, -d + 0.4, d - 0.4 }, -- the sides, between those two
		{ w - 0.4, w, -d + 0.4, d - 0.4 },
	}) do
		box(model, "RailGlass", F, e[1], e[2], K.Deck, top, e[3], e[4], COL.RailGlass, Enum.Material.Glass,
			{ Transparency = 0.6, Reflectance = 0.1, CastShadow = false })
		box(model, "Handrail", F, e[1], e[2], top, top + 0.3, e[3], e[4], COL.DarkMetal, Enum.Material.Metal, { CastShadow = false })
		box(model, "RailGuard", F, e[1], e[2], top + 0.3, K.Deck + H.Guard, e[3], e[4], COL.White, Enum.Material.SmoothPlastic,
			{ Transparency = 1, CastShadow = false })
	end
end

-- Builds a picked tower's entrance and penthouse into a Folder under Workspace.Apartments (t.root).
local function build(t)
	local root = Instance.new("Folder")
	root.Name = t.Name
	t.root = root
	clearRoof(t)
	local entrance = Instance.new("Model")
	entrance.Name = "Entrance"
	buildEntrance(entrance, t)
	local penthouse = Instance.new("Model")
	penthouse.Name = "Penthouse"
	buildShell(penthouse, t)
	buildElevator(penthouse, t)
	buildLiving(penthouse, t)
	buildKitchen(penthouse, t)
	buildJuiceBar(penthouse, t)
	buildBedroom(penthouse, t)
	buildBathroom(penthouse, t)
	buildArt(penthouse, t)
	buildTerrace(penthouse, t)
	buildRailings(penthouse, t)
	t.parts = 0
	for _, p in ipairs(penthouse:GetDescendants()) do
		if p:IsA("BasePart") then
			t.parts += 1
		end
	end
	for _, m in ipairs({ entrance, penthouse }) do
		pcall(function()
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- each streams in whole
		end)
		m.Parent = root
	end
	root.Parent = S.folder
end

-- Players --------------------------------------------------------------------------------------------

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function humanoidOf(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Tasered or knocked over (VehicleService's rule for its prompts): no trips until back up.
local function isDown(player)
	local now = Workspace:GetServerTimeNow()
	return (player:GetAttribute("StunnedUntil") or 0) > now or (player:GetAttribute("KnockedUntil") or 0) > now
end

-- The tower whose penthouse room a spot is in: the indoor part's footprint (x -25..25, z -16..16 of the
-- indoor frame) between the floor and the ceiling (not the terrace, not on its flat roof), else nil.
local function roomAt(pos)
	for _, t in ipairs(S.towers) do
		local rel = t.indoor:PointToObjectSpace(pos)
		if math.abs(rel.X) < 25 and math.abs(rel.Z) < 16 and rel.Y > K.Deck and rel.Y < K.Floor + H.Ceiling then
			return t
		end
	end
	return nil
end

-- Player attribute "InApartment" = the tower's name while in its penthouse room (see the header), else nil.
local function setRoom(player, t)
	local name = t and t.Name or nil
	if player:GetAttribute("InApartment") ~= name then
		player:SetAttribute("InApartment", name)
	end
end

local function fade(player, phase)
	if player.Parent == Players then
		S.fade:FireClient(player, phase)
	end
end

-- Ask the player's device to load the area first (StreamingEnabled), for up to a few seconds.
local function stream(player, position)
	pcall(function()
		player:RequestStreamAroundAsync(position, 3)
	end)
end

-- Move a living character (out of any seat first, so a couch or a car never comes along).
local function moveTo(player, cf)
	local char = player.Character
	local hum = humanoidOf(player)
	local root = rootOf(player)
	if not char or not hum or not root or hum.Health <= 0 then
		return false
	end
	local seatPart = hum.SeatPart
	if seatPart then
		local weld = seatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		hum.Sit = false
	end
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- The trip itself: fade out (HouseClient), wait, load the area, move, fade back in. True if they moved.
-- Only the character that asked goes: a respawn, an arrest or a team switch (each a new character)
-- during the fade calls the trip off, so nobody new lands in a penthouse or walks out of prison.
local function trip(player, cf, what)
	S.busy[player] = true
	local char = player.Character
	local moved = false
	local ok, err = pcall(function()
		fade(player, "Out")
		task.wait(Apartments.FadeTime)
		if player.Parent == Players then
			stream(player, cf.Position)
			if player.Character == char and player:GetAttribute("Side") ~= "Prisoner" then
				moved = moveTo(player, cf)
			end
		end
	end)
	if not ok then
		warn("[ApartmentService] " .. what .. " failed: " .. tostring(err))
	end
	fade(player, "In")
	S.busy[player] = nil
	return moved
end

-- The street door's prompt: up to the penthouse.
enter = function(player, t)
	if not RateLimit.Allow(player, "Apartment", 2, 3) or S.busy[player] then
		return
	end
	local side = player:GetAttribute("Side") or "Civilian"
	local hum, root = humanoidOf(player), rootOf(player)
	if (side ~= "Civilian" and side ~= "Cop") or not hum or not root or hum.Health <= 0 or hum.SeatPart or isDown(player) then
		return
	end
	if (root.Position - t.doorPrompt).Magnitude > Apartments.EnterRange then
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 then
		S.notify:FireClient(player, "ApartmentWanted") -- no hiding from the cops up there
		return
	end
	if trip(player, t.lobby, "going up") then
		S.entered[player] = t.index
		setRoom(player, t) -- (the lobby is in the room)
	end
end

-- The elevator's prompt: anyone in this penthouse goes down to the door they came in by (this tower's
-- own door if they never used one).
down = function(player, t)
	if not RateLimit.Allow(player, "Apartment", 2, 3) or S.busy[player] then
		return
	end
	local hum, root = humanoidOf(player), rootOf(player)
	if not hum or not root or hum.Health <= 0 or isDown(player) then
		return
	end
	local rel = t.frame:PointToObjectSpace(root.Position)
	if math.abs(rel.X) > t.w / 2 + 2 or math.abs(rel.Z) > t.d / 2 + 2 or rel.Y < -4 or rel.Y > H.Guard + 6 then
		return -- not in this penthouse
	end
	if (root.Position - t.elevator).Magnitude > Apartments.EnterRange then
		return
	end
	local out = S.towers[S.entered[player] or 0] or t
	if trip(player, out.exit, "going down") then
		S.entered[player] = nil
		setRoom(player, nil)
	end
end

-- Public ----------------------------------------------------------------------------------------------

function ApartmentService.Towers()
	local list = {}
	for _, t in ipairs(S.towers) do
		table.insert(list, { Name = t.Name, Door = t.Door, Kind = t.Kind })
	end
	return list
end

function ApartmentService.Init()
	S.notify = Remotes.Event("Notify")
	S.fade = Remotes.Event("HouseFade")
	local folder = Workspace:FindFirstChild("Apartments") or Instance.new("Folder")
	folder.Name = "Apartments"
	folder:ClearAllChildren()
	folder.Parent = Workspace
	S.folder = folder

	local okPick, picked = pcall(pick)
	if not okPick then
		warn("[ApartmentService] picking towers failed: " .. tostring(picked))
		picked = {}
	end
	local names, most = {}, 0
	for _, c in ipairs(picked) do
		local t = setup(c, #S.towers + 1) -- a tower that fails to build hands its name to the next
		local ok, err = pcall(build, t)
		if ok then
			table.insert(S.towers, t)
			table.insert(names, string.format("%s (%d, %d)", t.Name, math.floor(t.Door.X), math.floor(t.Door.Z)))
			most = math.max(most, t.parts)
		else
			warn("[ApartmentService] couldn't build " .. t.Name .. ": " .. tostring(err))
			if t.root then
				t.root:Destroy()
			end
		end
	end
	print(string.format("[ApartmentService] %d apartment tower(s), up to %d parts a penthouse: %s", #S.towers, most,
		table.concat(names, ", ")))

	local function onPlayer(player)
		player.CharacterRemoving:Connect(function()
			S.entered[player] = nil
			setRoom(player, nil) -- (a respawn, an arrest or a team switch)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		S.entered[player] = nil
		S.busy[player] = nil
	end)
	-- Who is in a penthouse room (InApartment): walking out to the terrace and back. Not mid-trip (the
	-- trip itself sets it).
	task.spawn(function()
		while true do
			task.wait(K.RoomCheck)
			for _, p in ipairs(Players:GetPlayers()) do
				if not S.busy[p] then
					local root = rootOf(p)
					setRoom(p, root and roomAt(root.Position) or nil)
				end
			end
		end
	end)
end

return ApartmentService
