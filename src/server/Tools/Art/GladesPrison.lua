-- GladesPrison (ModuleScript, ServerStorage.Tools.Art.GladesPrison). Studio-only art for Gator Glades
-- and Saltmarsh Prison island.
--   Glades (x -2000..-900, z -2000..850): cypress clusters, ponds with lily pads and reeds, a boardwalk
--     loop, stilt shacks, Deke's Bait & Tackle, an airboat, friendly gators, the GATOR GLADES sign.
--   Prison (island x -1750..-1100, z 1000..1700): facade on PrisonBlock's north face, gatehouse at the
--     bridge, four guard towers, perimeter fence, yard details and orange-striped warning signs.
-- The Landmarks parts (PrisonBlock, yard walls, PrisonVent) are never touched. The yard centre, the vent
-- (-1425, 3, 1690) and the strip from the vent south to the moat stay clear.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Art = {}

local ArtKit, Layout, C, N, rng, assets
local MAX_LIGHTS = 20
local lightsUsed = 0
local claims = {} -- { centre, radius } circles already used by props in this module
local posted = {} -- fence posts already placed (corners are shared by two runs)
local blockerParams -- overlap filter: heists, spawns, activities, landmarks (roads are tested exactly)

local ROT_UP = CFrame.Angles(0, 0, math.rad(90)) -- stands a Cylinder (axis X) upright
local ROT_FWD = CFrame.Angles(0, math.rad(90), 0) -- points a Cylinder's axis along LookVector

local BARK = Color3.fromRGB(118, 92, 70)
local MOSS = Color3.fromRGB(86, 150, 84)
local MOSS_LIGHT = Color3.fromRGB(118, 180, 98)
local MOSS_HANG = Color3.fromRGB(180, 200, 142)
local REED = Color3.fromRGB(98, 164, 82)
local CATTAIL = Color3.fromRGB(128, 84, 52)
local WATER = Color3.fromRGB(64, 196, 196)
local LILY = Color3.fromRGB(92, 184, 84)
local GATOR_GREEN = Color3.fromRGB(84, 150, 72)
local INK = Color3.fromRGB(34, 30, 46)
local FACADE = Color3.fromRGB(255, 222, 186)
local WINDOW = Color3.fromRGB(168, 214, 236)
local BARS = Color3.fromRGB(52, 54, 68)
local WIRE = Color3.fromRGB(200, 214, 226)
local WARN_TEXT = Color3.fromRGB(226, 96, 24)
local LAMP = Color3.fromRGB(255, 214, 140)

-- Helpers -------------------------------------------------------------------------------------------

local function part(parent, size, cf, color, material, opts)
	return ArtKit.Part(parent, size, cf, color, material, opts)
end

-- Decorative part nobody should trip over.
local function deco(parent, size, cf, color, material, opts)
	opts = opts or {}
	opts.CanCollide = false
	return ArtKit.Part(parent, size, cf, color, material, opts)
end

local function glow(parent, size, cf, color)
	return ArtKit.Neon(parent, size, cf, color)
end

-- Upright cylinder standing on `base`.
local function column(parent, base, height, dia, color, material, opts)
	opts = opts or {}
	opts.Shape = Enum.PartType.Cylinder
	return ArtKit.Part(parent, Vector3.new(height, dia, dia), CFrame.new(base + Vector3.new(0, height / 2, 0)) * ROT_UP, color, material, opts)
end

-- Flat round disc centred on `pos`.
local function disc(parent, pos, dia, thick, color, material, opts)
	opts = opts or {}
	opts.Shape = Enum.PartType.Cylinder
	return ArtKit.Part(parent, Vector3.new(thick, dia, dia), CFrame.new(pos) * ROT_UP, color, material, opts)
end

-- Real lights go through ArtKit.Light and are capped at MAX_LIGHTS for this module.
local function light(p, color, range, brightness, kind)
	if lightsUsed >= MAX_LIGHTS then
		return nil
	end
	local l = ArtKit.Light(p, color, range, brightness, kind)
	if l then
		lightsUsed += 1
	end
	return l
end

-- Panel with text on its front (LookVector) face.
local function textPanel(parent, size, cf, bg, fg, text)
	local p = deco(parent, size, cf, bg, Enum.Material.SmoothPlastic, { Name = "SignPanel" })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.4
	gui.MaxDistance = 250
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.84)
	label.Position = UDim2.fromScale(0.04, 0.08)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Oswald
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = fg
	label.Text = text
	label.Parent = gui
	gui.Parent = p
	return p, label
end

-- Orange-striped warning sign: white panel, text on top, diagonal orange stripes below.
-- cf = centre of the panel, facing outward.
local function warnSign(parent, cf, text)
	local _, label = textPanel(parent, Vector3.new(8, 5.4, 0.3), cf, C.White, WARN_TEXT, text)
	label.Size = UDim2.fromScale(0.92, 0.6)
	label.Position = UDim2.fromScale(0.04, 0.05)
	for i = -1.5, 1.5 do
		deco(parent, Vector3.new(1.2, 1, 0.1), cf * CFrame.new(i * 2, -1.9, -0.2) * CFrame.Angles(0, 0, math.rad(35)), N.Orange)
	end
end

-- Clone a generated mesh from ServerStorage.ArtAssets with its bottom at `pos` (minus `sink` of its
-- height, for things half in water). Returns nil when the asset is missing so callers can fall back.
local function mesh(parent, name, pos, scale, yaw, collide, sink)
	local template = assets and assets:FindFirstChild(name)
	if not (template and template:IsA("BasePart")) then
		return nil
	end
	local m = template:Clone()
	m.Anchored = true
	m.CanTouch = false
	m.CastShadow = false
	m.Size = template.Size * scale
	m.CFrame = CFrame.new(pos + Vector3.new(0, m.Size.Y * (0.5 - (sink or 0)), 0)) * CFrame.Angles(0, yaw or 0, 0)
	if collide == false then
		m.CanCollide = false
		m.CanQuery = false
	end
	m.Parent = parent
	return m
end

-- Glades placement ----------------------------------------------------------------------------------

local GLADES = { -1995, -925, -1995, 838 } -- xMin, xMax, zMin, zMax that props stay inside
local KEEP_OUT = { -- open-looking spots that must stay empty: { xMin, xMax, zMin, zMax }
	{ -1545, -1455, -130, 215 }, -- Glades Hopper ramp (-1500, 150) and its landing to the north
	{ -1640, -1420, -200, -95 }, -- Palm Blvd Leap ramp (-1600, -138) and its landing
	{ -1312, -1248, -532, -468 }, -- ATM heist pad (-1280, -500)
}

local function claim(pos, r)
	table.insert(claims, { Vector3.new(pos.X, 0, pos.Z), r })
end

-- Distance from pos to the nearest road edge (negative when on a road).
local function roadDistance(pos)
	local flat = Vector3.new(pos.X, 0, pos.Z)
	local best = math.huge
	for _, r in ipairs(Layout.Roads) do
		local ab = r.b - r.a
		local t = math.clamp((flat - r.a):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
		best = math.min(best, (flat - (r.a + ab * t)).Magnitude - r.width / 2)
	end
	return best
end

-- Layout.IsFree tests bounding boxes, and the long diagonal Glades trails have huge ones, so when it
-- says no we fall back to an exact road test plus the same overlap test for everything but roads.
local function siteFree(pos, r)
	if Layout.IsFree(pos, r + 6) then
		return true
	end
	if roadDistance(pos) < r + 6 then
		return false
	end
	local hits = Workspace:GetPartBoundsInBox(CFrame.new(pos.X, 5, pos.Z), Vector3.new(r * 2, 20, r * 2), blockerParams)
	return #hits == 0
end

-- True if a prop of radius r fits at pos: inside the Glades, off roads (6+ studs), off pads and ramps,
-- and (unless ignoreClaims) not on top of something this module already placed.
local function open(pos, r, ignoreClaims)
	if pos.X - r < GLADES[1] or pos.X + r > GLADES[2] or pos.Z - r < GLADES[3] or pos.Z + r > GLADES[4] then
		return false
	end
	for _, k in ipairs(KEEP_OUT) do
		if pos.X + r > k[1] and pos.X - r < k[2] and pos.Z + r > k[3] and pos.Z - r < k[4] then
			return false
		end
	end
	if not ignoreClaims then
		local flat = Vector3.new(pos.X, 0, pos.Z)
		for _, c in ipairs(claims) do
			if (flat - c[1]).Magnitude < r + c[2] then
				return false
			end
		end
	end
	return siteFree(pos, r)
end

-- Glades props --------------------------------------------------------------------------------------

-- Clump of reeds with one cattail. pos = ground point.
local function reeds(parent, pos)
	for _ = 1, 2 do
		local h = rng:NextNumber(3.5, 6)
		local o = Vector3.new(rng:NextNumber(-0.9, 0.9), h / 2 - 0.1, rng:NextNumber(-0.9, 0.9))
		deco(parent, Vector3.new(0.3, h, 0.3), CFrame.new(pos + o) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), REED)
	end
	local h = rng:NextNumber(5.5, 7)
	deco(parent, Vector3.new(0.25, h, 0.25), CFrame.new(pos + Vector3.new(0, h / 2, 0)), REED)
	deco(parent, Vector3.new(0.7, 1.8, 0.7), CFrame.new(pos + Vector3.new(0, h - 0.5, 0)), CATTAIL)
end

-- Swamp cypress: the CypressTree mesh if it exists, else a flared trunk, flat mossy canopy and moss strips.
local function cypress(parent, pos, s)
	local yaw = rng:NextNumber(0, math.pi * 2)
	if mesh(parent, "CypressTree", pos, 1.5 * s, yaw) then
		return
	end
	local m = ArtKit.Model(parent, "Cypress")
	local h = rng:NextNumber(16, 24) * s
	column(m, pos, 4 * s, 5.5 * s, BARK, nil, { Name = "Flare" })
	column(m, pos, h, 2.4 * s, BARK, nil, { Name = "Trunk" })
	disc(m, pos + Vector3.new(0, h, 0), 20 * s, 2.6 * s, MOSS, nil, { CanCollide = false, Name = "Canopy" })
	local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	disc(m, pos + dir * 2.5 * s + Vector3.new(0, h + 2.2 * s, 0), 13 * s, 2.4 * s, MOSS_LIGHT, nil, { CanCollide = false, Name = "Canopy" })
	for i = 1, 2 do
		local a = yaw + i * 2.2
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = pos + d * 7 * s + Vector3.new(0, h - 3.8 * s, 0)
		deco(m, Vector3.new(1.2 * s, 5 * s, 0.3 * s), CFrame.lookAt(mid, mid + d), MOSS_HANG, nil, { Name = "Moss" })
	end
end

-- Pond: two overlapping translucent teal discs (an organic outline), lily pads, lotus glow, reeds.
local function pond(parent, c, r, reedCount, padCount)
	local m = ArtKit.Model(parent, "Pond")
	local water = { CanCollide = false, Transparency = 0.25, Reflectance = 0.15, Name = "Water" }
	disc(m, Vector3.new(c.X, 0.05, c.Z), r * 2, 0.1, WATER, nil, water)
	local a = rng:NextNumber(0, math.pi * 2)
	local lobe = c + Vector3.new(math.cos(a), 0, math.sin(a)) * r * 0.55
	disc(m, Vector3.new(lobe.X, 0.08, lobe.Z), r * 1.2, 0.1, WATER, nil, water)
	for i = 1, padCount do
		local pa = rng:NextNumber(0, math.pi * 2)
		local p = c + Vector3.new(math.cos(pa), 0, math.sin(pa)) * rng:NextNumber(0.2, 0.7) * r
		disc(m, Vector3.new(p.X, 0.16, p.Z), rng:NextNumber(3.5, 5.5), 0.06, LILY, nil, { CanCollide = false, Name = "LilyPad" })
		if i % 2 == 1 then
			deco(m, Vector3.new(1, 1, 1), CFrame.new(p + Vector3.new(0.7, 0.5, 0.4)), N.Pink, Enum.Material.Neon, { Shape = Enum.PartType.Ball, Name = "Lotus" })
		end
	end
	for i = 1, reedCount do
		local ra = i / reedCount * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		reeds(m, c + Vector3.new(math.cos(ra), 0, math.sin(ra)) * r * rng:NextNumber(0.88, 1.05))
	end
	claim(c, r * 1.15 + 6)
	return m
end

-- Friendly gator (non-collidable). sink > 0 puts it partly under water.
local function gator(parent, pos, scale, yaw, sink)
	yaw = yaw or rng:NextNumber(0, math.pi * 2)
	if mesh(parent, "Gator", pos, scale, yaw, false, sink) then
		return
	end
	local s = scale / 3.5
	local m = ArtKit.Model(parent, "Gator")
	local cf = CFrame.new(pos - Vector3.new(0, (sink or 0) * 2.4 * s, 0)) * CFrame.Angles(0, yaw, 0)
	deco(m, Vector3.new(3.4, 1.6, 6) * s, cf * CFrame.new(0, 0.8 * s, 0), GATOR_GREEN, nil, { Name = "Body" })
	deco(m, Vector3.new(2.4, 1.1, 3.6) * s, cf * CFrame.new(0, 0.6 * s, -4.6 * s), GATOR_GREEN, nil, { Name = "Snout" })
	deco(m, Vector3.new(1.8, 1, 5) * s, cf * CFrame.new(0.6 * s, 0.5 * s, 5 * s) * CFrame.Angles(0, 0.3, 0), GATOR_GREEN, nil, { Name = "Tail" })
	for _, x in ipairs({ -0.8, 0.8 }) do
		deco(m, Vector3.new(1, 1, 1) * s, cf * CFrame.new(x * s, 1.7 * s, -2.6 * s), C.White, nil, { Shape = Enum.PartType.Ball, Name = "Eye" })
	end
end

-- Stilt shack at a pond's edge: porch faces the pond (facePos), a ramp runs down the land side.
local function stiltShack(parent, pos, facePos, color)
	local cf = CFrame.lookAt(Vector3.new(pos.X, 0, pos.Z), Vector3.new(facePos.X, 0, facePos.Z))
	local m = ArtKit.Model(parent, "StiltShack")
	local deckY = 7.8
	for _, x in ipairs({ -6.5, 6.5 }) do
		for _, z in ipairs({ -6.5, 6.5 }) do
			part(m, Vector3.new(0.9, deckY - 0.8, 0.9), cf * CFrame.new(x, (deckY - 0.8) / 2, z), C.DarkWood, Enum.Material.Wood, { Name = "Stilt" })
		end
	end
	part(m, Vector3.new(16, 0.8, 16), cf * CFrame.new(0, deckY - 0.4, 0), C.Wood, Enum.Material.WoodPlanks, { Name = "Deck" })
	part(m, Vector3.new(11, 8, 9), cf * CFrame.new(0, deckY + 4, 1.5), color, Enum.Material.WoodPlanks, { Shadow = true, Name = "Hut" })
	part(m, Vector3.new(13.5, 0.7, 12), cf * CFrame.new(0, deckY + 8.35, 1.5), ArtKit.PickNeon(), nil, { Name = "Roof" })
	deco(m, Vector3.new(0.8, 3, 0.8), cf * CFrame.new(3.5, deckY + 10.2, 4), C.Steel, Enum.Material.Metal, { Name = "Stovepipe" })
	deco(m, Vector3.new(3, 5.5, 0.3), cf * CFrame.new(-2, deckY + 2.75, -3.15), C.White, nil, { Name = "Door" })
	deco(m, Vector3.new(3, 2.4, 0.3), cf * CFrame.new(2.5, deckY + 4.5, -3.15), C.Glass, Enum.Material.Glass, { Name = "Window" })
	local lamp = glow(m, Vector3.new(0.8, 1, 0.8), cf * CFrame.new(0.2, deckY + 6.5, -3.4), N.Yellow)
	light(lamp, LAMP, 18, 1)
	deco(m, Vector3.new(16, 0.35, 0.35), cf * CFrame.new(0, deckY + 2.6, -7.8), C.DarkWood, nil, { Name = "Rail" })
	for _, x in ipairs({ -7.8, 7.8 }) do
		deco(m, Vector3.new(0.4, 2.6, 0.4), cf * CFrame.new(x, deckY + 1.3, -7.8), C.DarkWood, nil, { Name = "RailPost" })
	end
	-- Ramp from the back edge of the deck down to the ground, 12 studs behind.
	local run = 12
	part(m, Vector3.new(4, 0.6, math.sqrt(run * run + deckY * deckY)), cf * CFrame.new(4, deckY / 2, 8 + run / 2) * CFrame.Angles(math.atan2(deckY, run), 0, 0),
		C.Wood, Enum.Material.WoodPlanks, { Name = "Ramp" })
	claim(pos, 12)
	claim((cf * CFrame.new(4, 0, 8 + run)).Position, 5)
end

-- Boardwalk ring around a pond: 12 deck segments, a rail on the pond side, two lanterns, two benches.
local function boardwalk(parent, c, radius)
	local m = ArtKit.Model(parent, "Boardwalk")
	local segs = 12
	local deckY = Vector3.new(0, 1.1, 0)
	local railY = Vector3.new(0, 3.9, 0)
	for i = 0, segs - 1 do
		local a0, a1 = i / segs * math.pi * 2, (i + 1) / segs * math.pi * 2
		local d0 = Vector3.new(math.cos(a0), 0, math.sin(a0))
		local d1 = Vector3.new(math.cos(a1), 0, math.sin(a1))
		local p0, p1 = c + d0 * radius, c + d1 * radius
		part(m, Vector3.new(6, 0.6, (p1 - p0).Magnitude + 1.2), CFrame.lookAt((p0 + p1) / 2 + deckY, p1 + deckY), C.Wood, Enum.Material.WoodPlanks, { Name = "Deck" })
		local r0, r1 = c + d0 * (radius - 2.8), c + d1 * (radius - 2.8)
		deco(m, Vector3.new(0.35, 0.35, (r1 - r0).Magnitude + 0.4), CFrame.lookAt((r0 + r1) / 2 + railY, r1 + railY), C.DarkWood, nil, { Name = "Rail" })
		deco(m, Vector3.new(0.6, 4.1, 0.6), CFrame.new(r0 + Vector3.new(0, 2.05, 0)), C.DarkWood, nil, { Name = "RailPost" })
	end
	-- Lanterns and benches sit on segment middles (where the deck centre is at radius * cos 15).
	for k, deg in ipairs({ 45, 135, 225, 315 }) do
		local d = Vector3.new(math.cos(math.rad(deg)), 0, math.sin(math.rad(deg)))
		if k % 2 == 1 then
			local base = c + d * (radius + 1)
			deco(m, Vector3.new(0.6, 7, 0.6), CFrame.new(base + Vector3.new(0, 4.9, 0)), C.DarkWood, nil, { Name = "LanternPost" })
			local lamp = glow(m, Vector3.new(1.4, 1.8, 1.4), CFrame.new(base + Vector3.new(0, 9.3, 0)), N.Yellow)
			light(lamp, LAMP, 22, 1)
		else
			local p = c + d * (radius - 0.5) + Vector3.new(0, 1.4, 0)
			ArtKit.Bench(m, CFrame.lookAt(p, Vector3.new(c.X, 1.4, c.Z)))
		end
	end
	local signBase = c + Vector3.new(0, 0, radius + 7)
	deco(m, Vector3.new(0.5, 6, 0.5), CFrame.new(signBase + Vector3.new(0, 3, -0.3)), C.DarkWood, nil, { Name = "SignPost" })
	textPanel(m, Vector3.new(8, 3.4, 0.3), CFrame.lookAt(signBase + Vector3.new(0, 6.5, 0), signBase + Vector3.new(0, 6.5, 1)), C.Pastels[6], INK,
		"GATOR WATCHING DECK - please no splashing")
	claim(c, radius + 6)
end

-- Airboat: flat hull, driver's perch and a big rear fan in a glowing cage. cf = on the water, bow = LookVector.
local function airboat(parent, cf)
	local m = ArtKit.Model(parent, "Airboat")
	part(m, Vector3.new(8, 1.2, 16), cf * CFrame.new(0, 0.6, 0), C.White, nil, { Name = "Hull" })
	part(m, Vector3.new(8, 1.2, 3), cf * CFrame.new(0, 0.6, -9.5), C.White, nil, { Class = "WedgePart", Name = "Bow" })
	deco(m, Vector3.new(8.3, 0.3, 16.3), cf * CFrame.new(0, 1.05, 0), N.Pink, Enum.Material.Neon, { Name = "Stripe" })
	part(m, Vector3.new(6, 1, 2), cf * CFrame.new(0, 1.7, -3), N.Cyan, nil, { Name = "Bench" })
	deco(m, Vector3.new(0.6, 3.6, 0.6), cf * CFrame.new(0, 3, 2.5), C.Steel, Enum.Material.Metal, { Name = "SeatPost" })
	deco(m, Vector3.new(2.6, 0.5, 2.4), cf * CFrame.new(0, 5, 2.5), N.Yellow, nil, { Name = "Seat" })
	deco(m, Vector3.new(2.6, 2.4, 0.4), cf * CFrame.new(0, 6.4, 3.6), N.Yellow, nil, { Name = "SeatBack" })
	deco(m, Vector3.new(3, 2.6, 3), cf * CFrame.new(0, 2.5, 5.5), C.Steel, Enum.Material.Metal, { Name = "Engine" })
	local fan = cf * CFrame.new(0, 6.2, 8)
	deco(m, Vector3.new(0.9, 10, 10), fan * ROT_FWD, Color3.fromRGB(210, 220, 230), nil, { Shape = Enum.PartType.Cylinder, Transparency = 0.55, Name = "Cage" })
	for _, y in ipairs({ -5.2, 5.2 }) do
		glow(m, Vector3.new(10.9, 0.5, 0.5), fan * CFrame.new(0, y, 0), N.Cyan)
	end
	for _, x in ipairs({ -5.2, 5.2 }) do
		glow(m, Vector3.new(0.5, 10.4, 0.5), fan * CFrame.new(x, 0, 0), N.Cyan)
	end
	for _, a in ipairs({ 45, -45 }) do
		deco(m, Vector3.new(0.6, 8.6, 0.25), fan * CFrame.new(0, 0, -0.7) * CFrame.Angles(0, 0, math.rad(a)), INK, nil, { Name = "Blade" })
	end
	for _, x in ipairs({ -2.2, 2.2 }) do
		deco(m, Vector3.new(0.3, 4, 2.4), cf * CFrame.new(x, 5.5, 9.8), N.Orange, nil, { Name = "Rudder" })
	end
	return m
end

-- Deke's Bait & Tackle: wooden shop on a deck with a false front, neon sign and a neon fish on top.
-- cf = ground CFrame, front faces LookVector (the trail).
local function dekes(parent, cf)
	local m = ArtKit.Model(parent, "DekesBaitAndTackle")
	part(m, Vector3.new(34, 1, 30), cf * CFrame.new(0, 0.5, -5), C.Wood, Enum.Material.WoodPlanks, { Name = "Deck" })
	part(m, Vector3.new(30, 12, 18), cf * CFrame.new(0, 7, 0), C.Pastels[2], Enum.Material.WoodPlanks, { Shadow = true, Name = "Shop" })
	part(m, Vector3.new(32, 0.8, 20), cf * CFrame.new(0, 13.4, 0.5), Color3.fromRGB(255, 150, 140), nil, { Name = "Roof" })
	part(m, Vector3.new(32, 7, 0.8), cf * CFrame.new(0, 16, -9.4), C.Pastels[6], Enum.Material.WoodPlanks, { Name = "FalseFront" })
	local sign = ArtKit.Sign(m, cf * CFrame.new(0, 16, -10.2), "DEKE'S BAIT & TACKLE", N.Mint, 28, 5)
	light(sign, N.Mint, 30, 1.2)
	glow(m, Vector3.new(9, 3.2, 0.7), cf * CFrame.new(-2, 21, -9.4), N.Orange)
	glow(m, Vector3.new(2.6, 2.6, 0.7), cf * CFrame.new(3.4, 21, -9.4) * CFrame.Angles(0, 0, math.rad(45)), N.Orange)
	deco(m, Vector3.new(0.9, 0.9, 0.9), cf * CFrame.new(-5, 21.6, -9.9), INK, nil, { Shape = Enum.PartType.Ball, Name = "FishEye" })
	deco(m, Vector3.new(4, 8, 0.3), cf * CFrame.new(0, 5, -9.15), N.Pink, nil, { Name = "Door" })
	for _, x in ipairs({ -9, 9 }) do
		deco(m, Vector3.new(6, 4, 0.3), cf * CFrame.new(x, 7, -9.15), C.Glass, Enum.Material.Glass, { Name = "Window" })
	end
	textPanel(m, Vector3.new(8, 2.4, 0.2), cf * CFrame.new(-9, 10.8, -9.2), C.White, INK, "LIVE WORMS - ICE - SNACKS")
	textPanel(m, Vector3.new(8, 2.4, 0.2), cf * CFrame.new(9, 10.8, -9.2), C.White, INK, "OPEN 24/7 (NAPS 1-3)")
	-- Porch
	deco(m, Vector3.new(30, 0.5, 7), cf * CFrame.new(0, 10.2, -12.6) * CFrame.Angles(math.rad(-8), 0, 0), N.Orange, nil, { Name = "Awning" })
	for _, x in ipairs({ -14, 14 }) do
		part(m, Vector3.new(0.8, 8.8, 0.8), cf * CFrame.new(x, 5.4, -15.6), C.DarkWood, Enum.Material.Wood, { Name = "PorchPost" })
	end
	part(m, Vector3.new(3, 3, 3), cf * CFrame.new(-11, 2.5, -13), C.Wood, Enum.Material.WoodPlanks, { Name = "Crate" })
	part(m, Vector3.new(2.6, 2.6, 2.6), cf * CFrame.new(-11, 5.3, -13) * CFrame.Angles(0, 0.3, 0), C.Wood, Enum.Material.WoodPlanks, { Name = "Crate" })
	part(m, Vector3.new(4, 2.4, 2.4), cf * CFrame.new(10, 2.2, -12.5), C.White, nil, { Name = "IceChest" })
	deco(m, Vector3.new(4.1, 0.4, 2.5), cf * CFrame.new(10, 3.6, -12.5), N.Cyan, nil, { Name = "IceChestLid" })
	for i, col in ipairs({ N.Pink, N.Yellow, N.Cyan }) do
		deco(m, Vector3.new(0.2, 9, 0.2), cf * CFrame.new(4 + i * 0.9, 5.5, -10.3) * CFrame.Angles(math.rad(10), 0, 0), col, nil, { Name = "FishingRod" })
	end
	for _, x in ipairs({ -19, 19 }) do
		ArtKit.Palm(m, (cf * CFrame.new(x, 0, -2)).Position, 1.4)
	end
	claim((cf * CFrame.new(0, 0, -4)).Position, 26)
	return m
end

-- GATOR GLADES welcome sign with Gus the Gator lounging in front. cf = ground CFrame facing the highway.
local function welcomeSign(parent, cf)
	local m = ArtKit.Model(parent, "GatorGladesSign")
	for _, x in ipairs({ -21, 21 }) do
		part(m, Vector3.new(1.6, 21, 1.6), cf * CFrame.new(x, 10.5, 0.9), C.DarkWood, Enum.Material.Wood, { Name = "Post" })
	end
	local main = ArtKit.Sign(m, cf * CFrame.new(0, 15.5, 0), "GATOR GLADES", N.Mint, 40, 9)
	light(main, N.Mint, 36, 1.3)
	ArtKit.Sign(m, cf * CFrame.new(0, 7.6, 0), "Home of Gus the Gator - please don't feed the locals!", N.Yellow, 36, 3.6)
	for _, x in ipairs({ -19.4, 19.4 }) do
		deco(m, Vector3.new(1.2, 3.4, 0.2), cf * CFrame.new(x, 18.4, -0.45), MOSS_HANG, nil, { Name = "Moss" })
	end
	gator(m, (cf * CFrame.new(9, 0, -7)).Position, 5.5, math.pi / 2 + 0.4)
	for _, x in ipairs({ -10, -5, 14 }) do
		reeds(m, (cf * CFrame.new(x, 0, -3)).Position)
	end
	for _, x in ipairs({ -28, 28 }) do
		ArtKit.Palm(m, (cf * CFrame.new(x, 0, 2)).Position, 1.5)
	end
	claim(cf.Position, 32)
	return m
end

-- Yellow "GATOR X-ING" sign on a post, facing the trail.
local function xingSign(parent, pos, facePos)
	local cf = CFrame.lookAt(pos, Vector3.new(facePos.X, pos.Y, facePos.Z))
	deco(parent, Vector3.new(0.5, 7.5, 0.5), cf * CFrame.new(0, 3.75, 0.3), C.Steel, Enum.Material.Metal, { Name = "SignPost" })
	textPanel(parent, Vector3.new(6, 4, 0.3), cf * CFrame.new(0, 8.5, 0), N.Yellow, INK, "GATOR X-ING  slow down!")
	claim(pos, 4)
end

-- Cluster of cypress trees scattered around a centre, each on a free spot.
local function treeCluster(parent, centre, count)
	for _ = 1, count do
		for _ = 1, 5 do
			local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(4, 34)
			local p = centre + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
			if open(p, 9) then
				cypress(parent, p, rng:NextNumber(0.85, 1.15))
				claim(p, 7)
				break
			end
		end
	end
end

-- Glades layout -------------------------------------------------------------------------------------
-- Every spot below was picked in open grass between the trails; open() re-checks each one, and a
-- spot that isn't free is simply skipped.

local PONDS = {
	{ id = "Boardwalk", c = Vector3.new(-1600, 0, -600), r = 38, reeds = 5, pads = 4 },
	{ id = "Airboat", c = Vector3.new(-1640, 0, 430), r = 36, reeds = 4, pads = 3 },
	{ id = "North", c = Vector3.new(-1470, 0, -1480), r = 28, reeds = 4, pads = 3 },
	{ id = "Bayou", c = Vector3.new(-1080, 0, -880), r = 32, reeds = 4, pads = 3 },
	{ id = "Southeast", c = Vector3.new(-1090, 0, 560), r = 30, reeds = 4, pads = 3 },
	{ id = "West", c = Vector3.new(-1935, 0, -900), r = 22, reeds = 3, pads = 2 },
	{ id = "Bait", c = Vector3.new(-1228, 0, -645), r = 18, reeds = 3, pads = 2 }, -- behind Deke's
}

local SHACKS = { -- stilt shacks half over a pond's edge, porch facing the water
	{ pond = "Bayou", offset = Vector3.new(27, 0, 2), color = 1 },
	{ pond = "Airboat", offset = Vector3.new(-30, 0, -14), color = 4 },
	{ pond = "North", offset = Vector3.new(0, 0, -24), color = 3 },
	{ pond = "Southeast", offset = Vector3.new(25, 0, 8), color = 2 },
}

local GATORS = { -- sink = wading in the pond; no sink = lounging on the bank
	{ pond = "Boardwalk", offset = Vector3.new(16, 0, 9), sink = 0.35 },
	{ pond = "Boardwalk", offset = Vector3.new(-15, 0, -14), sink = 0.35 },
	{ pond = "Airboat", offset = Vector3.new(-4, 0, 22), sink = 0.35 },
	{ pond = "North", offset = Vector3.new(31, 0, 10) },
	{ pond = "Bayou", offset = Vector3.new(-10, 0, 12), sink = 0.35 },
	{ pond = "Southeast", offset = Vector3.new(-34, 0, -8) },
	{ pond = "West", offset = Vector3.new(26, 0, 5) },
	{ pond = "Bait", offset = Vector3.new(4, 0, -5), sink = 0.35 },
}

local XINGS = { -- { trail segment ax, az, bx, bz, fraction along it }
	{ -1250, -1300, -1350, -700, 0.5 },
	{ -1250, -100, -1350, 500, 0.35 },
	{ -1850, -1100, -1500, -1000, 0.55 },
	{ -1300, -1850, -1250, -1300, 0.6 },
}

local TREE_CLUSTERS = { -- { x, z, trees }
	{ -1700, -780, 4 }, { -1470, -420, 4 }, { -1740, 180, 3 }, { -1560, 660, 4 }, { -1440, -1290, 3 },
	{ -1700, -1360, 4 }, { -1100, -1110, 3 }, { -1040, -320, 3 }, { -1120, 160, 3 }, { -1090, -1600, 4 },
	{ -1945, -520, 3 }, { -1945, 460, 3 }, { -1230, 740, 3 }, { -985, -1380, 3 },
}

local function buildGlades(root)
	local f = Instance.new("Folder")
	f.Name = "Glades"
	f.Parent = root

	local ponds = {} -- id -> centre, for the ponds that were built
	for _, p in ipairs(PONDS) do
		if open(p.c, p.r * 1.2 + 4) then
			pond(f, p.c, p.r, p.reeds, p.pads)
			ponds[p.id] = p.c
		end
	end

	if ponds.Boardwalk and open(ponds.Boardwalk, 57, true) then
		boardwalk(f, ponds.Boardwalk, 50)
	end

	for _, s in ipairs(SHACKS) do
		local c = ponds[s.pond]
		if c then
			local pos = c + s.offset
			local rampEnd = (CFrame.lookAt(pos, c) * CFrame.new(4, 0, 20)).Position
			if open(pos, 10, true) and open(rampEnd, 4, true) then
				stiltShack(f, pos, c, C.Pastels[s.color])
			end
		end
	end

	-- Airboat moored beside a little dock.
	local ab = ponds.Airboat
	if ab then
		airboat(f, CFrame.new(ab + Vector3.new(14, 0.1, 14)) * CFrame.Angles(0, math.rad(30), 0))
		part(f, Vector3.new(14, 0.6, 5), CFrame.new(ab + Vector3.new(35, 0.9, 0)), C.Wood, Enum.Material.WoodPlanks, { Name = "Dock" })
		for _, z in ipairs({ -2.2, 2.2 }) do
			part(f, Vector3.new(0.7, 1.6, 0.7), CFrame.new(ab + Vector3.new(29, 0.8, z)), C.DarkWood, Enum.Material.Wood, { Name = "DockPost" })
		end
	end

	-- Deke's Bait & Tackle, east of the trail near (-1300, -600), well north of the ATM pad (-1280, -500).
	local dcf = CFrame.lookAt(Vector3.new(-1285, 0, -620), Vector3.new(-1286, 0, -620))
	if open((dcf * CFrame.new(0, 0, -4)).Position, 24) then
		dekes(f, dcf)
		local g = (dcf * CFrame.new(24, 0, 6)).Position
		if open(g, 5, true) then
			gator(f, g, 3.5, math.pi * 0.8)
		end
		local sp = Vector3.new(-1304, 0, -592)
		if open(sp, 4) then
			local cf = CFrame.lookAt(sp, Vector3.new(-1400, 0, -592))
			deco(f, Vector3.new(0.5, 6, 0.5), cf * CFrame.new(0, 3, 0.3), C.DarkWood, nil, { Name = "SignPost" })
			textPanel(f, Vector3.new(7, 3.6, 0.3), cf * CFrame.new(0, 6.5, 0), C.Pastels[1], INK, "GUS SAYS: DON'T FEED THE GATORS!")
			claim(sp, 4)
		end
	end

	for _, g in ipairs(GATORS) do
		local c = ponds[g.pond]
		if c then
			local pos = c + g.offset
			if g.sink or open(pos, 5, true) then
				gator(f, pos + Vector3.new(0, g.sink and 0.1 or 0, 0), 3.5, nil, g.sink)
			end
		end
	end

	-- GATOR GLADES welcome sign beside Highway 1 (west side), facing the traffic.
	local wcf = CFrame.lookAt(Vector3.new(-1785, 0, -262), Vector3.new(-1786, 0, -262))
	if open(wcf.Position, 26) then
		welcomeSign(f, wcf)
	end

	local billboards = {
		{ Vector3.new(-1790, 0, 640), Vector3.new(-1, 0, 0), "SWAMP TOURS BY DEKE: AIRBOAT RIDES & GATOR HIGH-FIVES", N.Pink },
		{ Vector3.new(-1100, 0, -96), Vector3.new(0, 0, -1), "GUS THE GATOR SAYS: WEAR SUNSCREEN!", N.Yellow },
		{ Vector3.new(-1500, 0, -1790), Vector3.new(0, 0, -1), "GATOR WRESTLING LESSONS (HUGS ONLY)", N.Orange },
	}
	for _, b in ipairs(billboards) do
		if open(b[1], 12) then
			ArtKit.Billboard(f, CFrame.lookAt(b[1], b[1] + b[2]), b[3], b[4])
			claim(b[1], 12)
		end
	end

	for _, x in ipairs(XINGS) do
		local a, b = Vector3.new(x[1], 0, x[2]), Vector3.new(x[3], 0, x[4])
		local p = a:Lerp(b, x[5])
		local d = (b - a).Unit
		local perp = Vector3.new(-d.Z, 0, d.X)
		for _, side in ipairs({ 1, -1 }) do
			local pos = p + perp * 26 * side
			if open(pos, 3) then
				xingSign(f, pos, p)
				break
			end
		end
	end

	-- Trees last, so they fill whatever space is left around everything above.
	for _, t in ipairs(TREE_CLUSTERS) do
		treeCluster(f, Vector3.new(t[1], 0, t[2]), t[3])
	end
end

-- Saltmarsh Prison ----------------------------------------------------------------------------------

local PX = -1425 -- the island's centre line (bridge, PrisonRoad, vent)
local FZ = 1350 -- north face of PrisonBlock (x -1555..-1295, y 0..40, z 1350..1550)

-- Barred window: pale pane with three dark bars. cf = centre on the wall surface, facing outward.
local function barredWindow(parent, cf)
	deco(parent, Vector3.new(5, 7, 0.3), cf * CFrame.new(0, 0, -0.15), WINDOW, nil, { Name = "Window" })
	for _, x in ipairs({ -1.5, 0, 1.5 }) do
		deco(parent, Vector3.new(0.4, 7.4, 0.4), cf * CFrame.new(x, 0, -0.45), BARS, nil, { Name = "Bars" })
	end
end

-- A peach facade layer over PrisonBlock's north face (the block itself is left alone), plus windows
-- on the other faces and a mural over the yard.
local function facade(parent)
	local m = ArtKit.Model(parent, "PrisonFacade")
	part(m, Vector3.new(262, 40.2, 1), CFrame.new(PX, 20.2, FZ - 0.5), FACADE, nil, { Shadow = true, Name = "FacadeWall" })
	part(m, Vector3.new(264, 1.2, 4), CFrame.new(PX, 40.6, FZ - 0.5), C.White, nil, { Name = "Cornice" })
	glow(m, Vector3.new(263, 0.5, 0.3), CFrame.new(PX, 39, FZ - 1.15), N.Cyan)
	glow(m, Vector3.new(262.4, 0.8, 0.4), CFrame.new(PX, 26, FZ - 1.2), N.Orange)
	local sign = ArtKit.Sign(m, CFrame.new(PX, 33, FZ - 1.4), "SALTMARSH CORRECTIONAL", N.Orange, 130, 9.5)
	light(sign, N.Orange, 45, 1.3)
	textPanel(m, Vector3.new(60, 1.8, 0.2), CFrame.new(PX, 24.6, FZ - 1.1), FACADE, INK, "Est. 1987 - now with extra comfy bunk beds!")
	-- Entrance where PrisonRoad meets the block
	deco(m, Vector3.new(26, 16, 0.4), CFrame.new(PX, 8.1, FZ - 1.2), Color3.fromRGB(70, 76, 96), nil, { Name = "Door" })
	glow(m, Vector3.new(27, 0.6, 0.5), CFrame.new(PX, 16.4, FZ - 1.25), N.Cyan)
	for i = 0, 4 do
		deco(m, Vector3.new(6, 0.5, 7), CFrame.new(PX - 12 + i * 6, 18.2, FZ - 4.5), i % 2 == 0 and N.Orange or C.White, nil, { Name = "Awning" })
	end
	textPanel(m, Vector3.new(9, 4, 0.2), CFrame.new(PX - 22.5, 8, FZ - 1.1), C.White, INK, "VISITING HOURS: SUNDAYS 2-4. BRING SNACKS!")
	-- Barred windows: two rows on the north face (skipping the entrance), a row on each side, and a
	-- row high on the yard side.
	for _, y in ipairs({ 8, 20 }) do
		for _, x in ipairs({ -1540, -1514, -1488, -1462, -1388, -1362, -1336, -1310 }) do
			barredWindow(m, CFrame.new(x, y, FZ - 1))
		end
	end
	for _, z in ipairs({ 1390, 1430, 1470, 1510 }) do
		barredWindow(m, CFrame.lookAt(Vector3.new(-1295, 20, z), Vector3.new(-1294, 20, z)))
		barredWindow(m, CFrame.lookAt(Vector3.new(-1555, 20, z), Vector3.new(-1556, 20, z)))
	end
	for _, x in ipairs({ -1530, -1490, -1450, -1400, -1360, -1320 }) do
		barredWindow(m, CFrame.lookAt(Vector3.new(x, 30, 1550), Vector3.new(x, 30, 1551)))
	end
	glow(m, Vector3.new(0.3, 0.5, 200), CFrame.new(-1294.85, 39, 1450), N.Cyan)
	glow(m, Vector3.new(0.3, 0.5, 200), CFrame.new(-1555.15, 39, 1450), N.Cyan)
	glow(m, Vector3.new(260, 0.5, 0.3), CFrame.new(PX, 39, 1550.15), N.Cyan)
	ArtKit.Sign(m, CFrame.lookAt(Vector3.new(PX, 15, 1550.4), Vector3.new(PX, 15, 1551.4)), "GUS SAYS: BE GOOD, GO HOME SOONER!", N.Yellow, 60, 8)
end

-- Gatehouse at the bridge end: two booths beside the road, an arch with a sign, raised boom barriers.
local function gatehouse(parent)
	local m = ArtKit.Model(parent, "Gatehouse")
	local z = 1024
	for _, bx in ipairs({ -1467, -1383 }) do
		local inward = bx < PX and 1 or -1
		part(m, Vector3.new(14, 11, 12), CFrame.new(bx, 5.5, z), C.Pastels[5], nil, { Shadow = true, Name = "Booth" })
		deco(m, Vector3.new(0.3, 4, 8), CFrame.new(bx + inward * 7.15, 7, z), C.Glass, Enum.Material.Glass, { Name = "Window" })
		part(m, Vector3.new(16, 1, 14), CFrame.new(bx, 11.5, z), C.White, nil, { Name = "Roof" })
		glow(m, Vector3.new(16.3, 0.4, 14.3), CFrame.new(bx, 10.9, z), N.Cyan)
		deco(m, Vector3.new(3, 7, 0.3), CFrame.new(bx, 3.5, z + 6.15), N.Orange, nil, { Name = "Door" })
	end
	warnSign(m, CFrame.new(-1467, 6, z - 6.3), "STOP! SHOW US YOUR BEST SMILE")
	warnSign(m, CFrame.new(-1383, 6, z - 6.3), "ALL VISITORS MUST WIPE THEIR FLIPPERS")
	for _, x in ipairs({ -1453, -1397 }) do
		part(m, Vector3.new(2.5, 30, 2.5), CFrame.new(x, 15, z), C.White, nil, { Name = "ArchPost" })
	end
	part(m, Vector3.new(58.5, 3, 2.5), CFrame.new(PX, 28.5, z), C.Pastels[1], nil, { Name = "ArchBeam" })
	local gateSign = ArtKit.Sign(m, CFrame.new(PX, 28.5, z - 1.6), "SALTMARSH ISLAND - PLEASE BEHAVE", N.Orange, 50, 5.5)
	light(gateSign, N.Orange, 40, 1.2)
	-- Boom barriers, both raised and leaning just short of the road edge.
	for _, b in ipairs({ { -1447, 1012, -1 }, { -1403, 1036, 1 } }) do
		local base = Vector3.new(b[1], 0, b[2])
		part(m, Vector3.new(1.2, 4, 1.2), CFrame.new(base + Vector3.new(0, 2, 0)), C.Steel, Enum.Material.Metal, { Name = "BoomPost" })
		local tilt = CFrame.Angles(0, 0, math.rad(10 * b[3]))
		for k = 0, 2 do
			deco(m, Vector3.new(0.6, 4, 0.6), CFrame.new(base + Vector3.new(0, 4, 0) + tilt.UpVector * (2 + 4 * k)) * tilt, k % 2 == 0 and N.Orange or C.White,
				nil, { Name = "BoomArm" })
		end
	end
end

-- Guard tower: legs, deck, pastel cabin with a window band, pink roof and a cyan searchlight lens
-- tipped toward the prison. Only one tower gets a real SpotLight.
local function guardTower(parent, pos, withSpot)
	local toward = Vector3.new(PX, 0, 1350) - pos
	local cf = CFrame.lookAt(pos, pos + Vector3.new(toward.X, 0, toward.Z).Unit)
	local m = ArtKit.Model(parent, "GuardTower")
	for _, x in ipairs({ -4.5, 4.5 }) do
		for _, z in ipairs({ -4.5, 4.5 }) do
			part(m, Vector3.new(1.2, 26, 1.2), cf * CFrame.new(x, 13, z), C.White, nil, { Name = "Leg" })
		end
	end
	deco(m, Vector3.new(2.2, 26, 0.3), cf * CFrame.new(0, 13, 5.3), C.Steel, Enum.Material.Metal, { Name = "Ladder" })
	part(m, Vector3.new(12, 1, 12), cf * CFrame.new(0, 26.5, 0), C.Wood, Enum.Material.WoodPlanks, { Name = "Deck" })
	part(m, Vector3.new(9, 7, 9), cf * CFrame.new(0, 30.5, 0), C.Pastels[4], nil, { Shadow = true, Name = "Cabin" })
	deco(m, Vector3.new(9.4, 2.6, 9.4), cf * CFrame.new(0, 31.4, 0), C.Glass, Enum.Material.Glass, { Name = "WindowBand" })
	glow(m, Vector3.new(12.3, 0.4, 12.3), cf * CFrame.new(0, 34, 0), N.Cyan)
	part(m, Vector3.new(12, 0.8, 12), cf * CFrame.new(0, 34.6, 0), N.Pink, nil, { Name = "Roof" })
	deco(m, Vector3.new(1.2, 1.4, 1.2), cf * CFrame.new(0, 35.7, 0), C.Steel, Enum.Material.Metal, { Name = "LampMount" })
	local aim = cf * CFrame.new(0, 36.8, 0) * CFrame.Angles(math.rad(-40), 0, 0)
	deco(m, Vector3.new(3.4, 2.6, 2.6), aim * ROT_FWD, C.Steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Name = "Searchlight" })
	local lens = glow(m, Vector3.new(0.3, 2.3, 2.3), aim * CFrame.new(0, 0, -1.8) * ROT_FWD, N.Cyan)
	lens.Shape = Enum.PartType.Cylinder
	if withSpot then
		local l = light(lens, N.Cyan, 60, 3, "SpotLight")
		if l then
			l.Face = Enum.NormalId.Right -- the lens cylinder's axis (+X) points along the beam
			l.Angle = 40
		end
	end
end

local function fencePost(parent, p)
	local key = math.floor(p.X + 0.5) .. "," .. math.floor(p.Z + 0.5)
	if posted[key] then
		return
	end
	posted[key] = true
	part(parent, Vector3.new(0.9, 14, 0.9), CFrame.new(p + Vector3.new(0, 7, 0)), C.Steel, Enum.Material.Metal, { Name = "FencePost" })
end

-- Straight fence from a to b (y = 0): posts, see-through wire panels and one glowing top wire.
local function fenceRun(parent, a, b)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local n = math.max(1, math.ceil(len / 48))
	local bay = len / n
	for i = 0, n do
		fencePost(parent, a + dir * bay * i)
	end
	for i = 1, n do
		local mid = a + dir * bay * (i - 0.5) + Vector3.new(0, 7, 0)
		part(parent, Vector3.new(0.2, 12, bay - 0.9), CFrame.lookAt(mid, mid + dir), WIRE, nil, { Transparency = 0.55, Name = "WirePanel" })
	end
	local top = Vector3.new(0, 13.6, 0)
	glow(parent, Vector3.new(0.35, 0.35, len), CFrame.lookAt((a + b) / 2 + top, b + top), N.Cyan)
end

-- Fence 4 studs in from the island edge, with a gap for the bridge (north) and one south of the vent
-- so the escape route from the vent to the moat stays open.
local function perimeterFence(parent)
	local m = ArtKit.Model(parent, "PerimeterFence")
	local W, E, NZ, SZ = -1746, -1104, 1004, 1696
	local function v(x, z)
		return Vector3.new(x, 0, z)
	end
	fenceRun(m, v(W, NZ), v(PX - 31, NZ))
	fenceRun(m, v(PX + 31, NZ), v(E, NZ))
	fenceRun(m, v(E, NZ), v(E, SZ))
	fenceRun(m, v(E, SZ), v(PX + 33, SZ))
	fenceRun(m, v(PX - 33, SZ), v(W, SZ))
	fenceRun(m, v(W, SZ), v(W, NZ))
	-- Warning signs hung on the outside, between posts.
	local signs = {
		{ v(-1600, NZ - 0.35), Vector3.new(0, 0, -1), "NO SWIMMING - THE GATORS ARE NAPPING" },
		{ v(-1250, NZ - 0.35), Vector3.new(0, 0, -1), "PLEASE DO NOT FEED THE GUARDS" },
		{ v(W - 0.35, 1200), Vector3.new(-1, 0, 0), "CAUTION: MOAT IS VERY WET" },
		{ v(W - 0.35, 1500), Vector3.new(-1, 0, 0), "KEEP OUT (AND KEEP IN)" },
		{ v(E + 0.35, 1250), Vector3.new(1, 0, 0), "NO DIGGING. WE MEAN IT." },
		{ v(E + 0.35, 1530), Vector3.new(1, 0, 0), "DANGER: EXTREMELY BORING AREA" },
		{ v(-1626, SZ + 0.35), Vector3.new(0, 0, 1), "WET PAINT (SINCE 1987)" },
		{ v(-1272, SZ + 0.35), Vector3.new(0, 0, 1), "NO SWIMMING - GATORS NAPPING" },
	}
	for _, s in ipairs(signs) do
		local p = s[1] + Vector3.new(0, 7, 0)
		warnSign(m, CFrame.lookAt(p, p + s[2]), s[3])
	end
end

-- Yard: half-court by the west wall, gym corner by the east wall, benches along the block, planters
-- and two floodlights. The middle (spawn at x -1425) and everything near the vent stay empty.
local function yard(parent)
	local m = ArtKit.Model(parent, "YardDetails")
	deco(m, Vector3.new(66, 0.1, 56), CFrame.new(-1557, 0.05, 1620), Color3.fromRGB(120, 200, 214), nil, { Name = "Court" })
	deco(m, Vector3.new(15, 0.1, 12), CFrame.new(-1582.5, 0.08, 1620), C.Pastels[1], nil, { Name = "CourtKey" })
	deco(m, Vector3.new(0.6, 0.1, 12), CFrame.new(-1575, 0.1, 1620), C.White, nil, { Name = "CourtLine" })
	deco(m, Vector3.new(0.6, 0.1, 56), CFrame.new(-1527, 0.1, 1620), C.White, nil, { Name = "CourtLine" })
	part(m, Vector3.new(1, 12, 1), CFrame.new(-1594, 6, 1620), C.White, nil, { Name = "HoopPole" })
	deco(m, Vector3.new(3, 0.6, 0.6), CFrame.new(-1592.5, 11.6, 1620), C.White, nil, { Name = "HoopArm" })
	part(m, Vector3.new(0.4, 5, 8), CFrame.new(-1591, 12, 1620), C.White, nil, { Name = "Backboard" })
	for _, x in ipairs({ -1590.2, -1587.8 }) do
		deco(m, Vector3.new(0.2, 0.2, 2.6), CFrame.new(x, 10, 1620), N.Orange, nil, { Name = "Rim" })
	end
	for _, z in ipairs({ 1618.8, 1621.2 }) do
		deco(m, Vector3.new(2.6, 0.2, 0.2), CFrame.new(-1589, 10, z), N.Orange, nil, { Name = "Rim" })
	end
	deco(m, Vector3.new(1.6, 1.6, 1.6), CFrame.new(-1560, 0.8, 1612), N.Orange, nil, { Shape = Enum.PartType.Ball, Name = "Basketball" })

	for _, x in ipairs({ -1545, -1515, -1335, -1305 }) do
		ArtKit.Bench(m, CFrame.lookAt(Vector3.new(x, 0, 1557), Vector3.new(x, 0, 1558)))
	end

	-- Gym corner
	deco(m, Vector3.new(40, 0.2, 36), CFrame.new(-1290, 0.1, 1630), C.Pastels[4], nil, { Name = "GymMat" })
	for _, x in ipairs({ -1306, -1296 }) do
		part(m, Vector3.new(0.6, 9, 0.6), CFrame.new(x, 4.5, 1618), C.Steel, Enum.Material.Metal, { Name = "PullUpPost" })
	end
	part(m, Vector3.new(10.6, 0.4, 0.4), CFrame.new(-1301, 8.8, 1618), C.Steel, Enum.Material.Metal, { Name = "PullUpBar" })
	part(m, Vector3.new(2, 1.6, 6), CFrame.new(-1280, 1, 1633), N.Pink, nil, { Name = "WeightBench" })
	for _, x in ipairs({ -1281.4, -1278.6 }) do
		deco(m, Vector3.new(0.4, 4.2, 0.4), CFrame.new(x, 2.1, 1630.4), C.Steel, Enum.Material.Metal, { Name = "Upright" })
	end
	deco(m, Vector3.new(8, 0.3, 0.3), CFrame.new(-1280, 4.2, 1630.4), C.Steel, Enum.Material.Metal, { Name = "Barbell" })
	for _, x in ipairs({ -1283.6, -1276.4 }) do
		deco(m, Vector3.new(0.6, 3, 3), CFrame.new(x, 4.2, 1630.4), N.Purple, nil, { Shape = Enum.PartType.Cylinder, Name = "Plate" })
	end
	part(m, Vector3.new(6, 2, 2), CFrame.new(-1300, 1, 1644), C.Steel, Enum.Material.Metal, { Name = "DumbbellRack" })
	for i, col in ipairs({ N.Cyan, N.Pink, N.Yellow }) do
		deco(m, Vector3.new(2.2, 0.8, 0.8), CFrame.new(-1304 + i * 2, 2.4, 1644) * ROT_FWD, col, nil, { Shape = Enum.PartType.Cylinder, Name = "Dumbbell" })
	end
	ArtKit.Sign(m, CFrame.lookAt(Vector3.new(-1252.35, 12, 1630), Vector3.new(-1253.35, 12, 1630)), "GUS'S GYM - NO GRUNTING PLEASE", N.Pink, 30, 5)

	for _, x in ipairs({ -1592, -1258 }) do
		part(m, Vector3.new(5, 2, 5), CFrame.new(x, 1, 1560), C.Pastels[1], nil, { Name = "Planter" })
		ArtKit.Palm(m, Vector3.new(x, 2, 1560), 1.1)
		part(m, Vector3.new(1, 22, 1), CFrame.new(x, 11, 1682), C.Steel, Enum.Material.Metal, { Name = "FloodPole" })
		local lamp = glow(m, Vector3.new(3, 1.2, 2), CFrame.new(x, 22.6, 1682), Color3.fromRGB(255, 244, 214))
		light(lamp, Color3.fromRGB(255, 236, 200), 50, 1.2)
	end
	-- A cheeky hint on the inside of the south wall, well away from the vent (x -1470 vs -1425).
	warnSign(m, CFrame.lookAt(Vector3.new(-1470, 9, 1687.6), Vector3.new(-1470, 9, 1686.6)), "PLEASE DO NOT PRY OPEN THE VENT (SERIOUSLY)")
end

-- Palms in planters lining PrisonRoad.
local function roadPalms(parent)
	local m = ArtKit.Model(parent, "RoadPalms")
	for _, z in ipairs({ 1090, 1180, 1270 }) do
		for _, x in ipairs({ PX - 28, PX + 28 }) do
			if Layout.IsFree(Vector3.new(x, 0, z), 4) then
				part(m, Vector3.new(6, 1.6, 6), CFrame.new(x, 0.8, z), C.Pastels[1], nil, { Name = "Planter" })
				ArtKit.Palm(m, Vector3.new(x, 1.6, z), 1.4)
			end
		end
	end
end

-- Lily pads and a few swimming gators in the moat (water surface y ~ -1.5), away from the bridge,
-- Highway 1 and the swim route south of the vent.
local function moat(parent)
	local m = ArtKit.Model(parent, "Moat")
	local WATER_Y = -1.5
	for _, p in ipairs({ { -1600, 925 }, { -1520, 960 }, { -1300, 920 }, { -1180, 970 }, { -1000, 1100 }, { -1020, 1550 }, { -1250, 1800 }, { -1620, 1770 } }) do
		disc(m, Vector3.new(p[1], WATER_Y + 0.03, p[2]), rng:NextNumber(4, 6), 0.06, LILY, nil, { CanCollide = false, Name = "LilyPad" })
	end
	for _, g in ipairs({ { -1300, 1790, 0.5 }, { -1020, 1250, 2.5 }, { -1790, 1400, 4 } }) do
		gator(m, Vector3.new(g[1], WATER_Y, g[2]), 3.5, g[3], 0.4)
	end
end

local function buildPrison(root)
	local f = Instance.new("Folder")
	f.Name = "Prison"
	f.Parent = root
	facade(f)
	gatehouse(f)
	for _, t in ipairs({ { -1728, 1022, false }, { -1122, 1022, true }, { -1728, 1678, false }, { -1122, 1678, false } }) do
		guardTower(f, Vector3.new(t[1], 0, t[2]), t[3])
	end
	perimeterFence(f)
	yard(f)
	roadPalms(f)
	moat(f)
	-- Heads-up on the mainland where the trail reaches the bridge, facing arriving traffic.
	local sp = Vector3.new(-1468, 0, 812)
	if open(sp, 6) then
		deco(f, Vector3.new(0.6, 9.5, 0.6), CFrame.new(sp + Vector3.new(0, 4.75, 0.5)), C.Steel, Enum.Material.Metal, { Name = "SignPost" })
		warnSign(f, CFrame.lookAt(sp + Vector3.new(0, 7, 0), sp + Vector3.new(0, 7, -1)), "SALTMARSH ISLAND AHEAD - NO HITCHHIKERS!")
	end
end

-- Entry point -----------------------------------------------------------------------------------------

function Art.Build(folder, artKit, layout)
	ArtKit, Layout = artKit, layout
	C, N = ArtKit.Colors, ArtKit.Colors.Neon
	rng = ArtKit.Random()
	assets = ServerStorage:FindFirstChild("ArtAssets")
	lightsUsed = 0
	claims = {}
	posted = {}

	-- Same blockers as Layout.IsFree minus roads (see siteFree).
	local city = Workspace:FindFirstChild("City")
	local roots = { Workspace:FindFirstChild("Heists"), Workspace:FindFirstChild("Spawns"), Workspace:FindFirstChild("Activities"), city and city:FindFirstChild("Landmarks") }
	local include = {}
	for i = 1, 4 do
		if roots[i] then
			table.insert(include, roots[i])
		end
	end
	blockerParams = OverlapParams.new()
	blockerParams.FilterType = Enum.RaycastFilterType.Include
	blockerParams.FilterDescendantsInstances = include

	buildGlades(folder)
	buildPrison(folder)

	local parts = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end

return Art
