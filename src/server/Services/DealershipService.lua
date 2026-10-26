-- DealershipService (ModuleScript, ServerScriptService.Services.DealershipService)
-- Real shops for rides, so players can walk around a car before they buy it:
--   * AutoNeon Motors: a glass-front showroom downtown in Solana Heights (lot x -210..-90,
--     z -542.5..-458, the door facing the street to the north). Every civilian land car for sale
--     sits on its own turntable, cheapest first from the front windows: 12 slots in 3 rows of 4.
--     Game-pass cars (the Vortex) come after them on gold, spotlit turntables; their card's BUY opens
--     the Roblox purchase prompt (DealerClient). More cars than slots add rows at the back (the lot
--     grows south, with a warning).
--   * Marina Boat Sales: a kiosk on the end of the first marina pier (z 1100) with a floating
--     showcase dock running north from it; every civilian boat and jet ski is moored along it, cheapest
--     nearest the pier, each berth as long as its hull needs (the dock grows to fit).
-- Walking up to a display shows a "View" prompt; DealerClient opens the stats card from it, and its
-- BUY button fires the normal garage purchase (RequestBuyCar: GarageService checks cash/ownership).
-- Tags read the price, "GAME PASS", "COP RANK n" or, for heist-locked rides (UnlockHeists), "n BIG
-- HEISTS" (DealerClient swaps in each player's own count, or OWNED).
-- Display vehicles are real CarBuilder models stripped of seats and forces, every part anchored and
-- only the chassis colliding. They stand still here; each client spins/bobs them locally.
-- The look follows Look 3.0 (Tools/Look3, SkyClient's night neon): the showroom is white plaster panels,
-- dark tinted glass in dark metal frames, a polished light-grey marble floor and a brushed aluminium
-- brand pylon; the marina kiosk is white timber with a slate metal roof and a navy-and-white awning. Each
-- place keeps one accent (AutoNeon blue, marina teal). Neon trims are dark metal by day and only glow
-- after dark (tag "NightNeon", attribute NeonColor; any Light inside starts off); the canopy and kiosk
-- downlights are "NightLamp"s (LampColor). Only the pass cars' ceiling spotlights stay lit by day.
-- Built at start-up under Workspace.Dealerships: one Model per dealership whose PrimaryPart is where
-- the GPS should lead (model attributes PlaceName / PlaceKind, for MapService). VehicleService's
-- spawn-room check (isClear) should list Workspace.Dealerships too, so a car called here doesn't
-- appear inside a display car or a wall.
--   DealershipService.Places                  { { Name, Kind, Pos } } once built
--   DealershipService.IsNear(player, id?)     is the player at that vehicle's display (any, if no id)?
-- Buying a car or boat while standing at its display posts it to the Coast Feed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)

local DealershipService = {}

DealershipService.Places = {}

-- Look 3.0 palette (Tools/Look3): real materials in believable colours, one accent per place, and neon
-- only as thin strips that glow after dark.
local WHITE_PANEL = Color3.fromRGB(238, 238, 234) -- plaster wall panels
local GREY_PANEL = Color3.fromRGB(216, 216, 212)
local FRAME = Color3.fromRGB(44, 46, 50) -- dark anodised metal: mullions, door frames, the canopy
local SILVER = Color3.fromRGB(186, 189, 193) -- brushed aluminium: the brand pylon, flag poles
local GLASS = Color3.fromRGB(62, 78, 88) -- dark tinted glass
local TILE_A = Color3.fromRGB(230, 230, 226) -- polished floor: two close greys
local TILE_B = Color3.fromRGB(212, 212, 208)
local PAVING = Color3.fromRGB(184, 182, 176)
local KERB = Color3.fromRGB(210, 208, 202)
local MAT = Color3.fromRGB(38, 40, 44)
local PLANTER = Color3.fromRGB(150, 146, 138)
local SOIL = Color3.fromRGB(70, 110, 62)
local ROOF = Color3.fromRGB(214, 214, 210) -- a pale membrane roof (a light ceiling inside)
local UNIT = Color3.fromRGB(150, 152, 154) -- roof units
local SIGN_BOARD = Color3.fromRGB(28, 30, 34)
local TURNTABLE = Color3.fromRGB(52, 54, 58) -- graphite
local PASS_GOLD = Color3.fromRGB(176, 146, 88) -- brushed champagne gold: the game-pass turntables
local SPOT_LENS = Color3.fromRGB(255, 236, 190)
local GOLD = Color3.fromRGB(255, 214, 10) -- price text (DealerClient uses the same)
local DARK = Color3.fromRGB(18, 20, 24) -- tag background
local SOFT = Color3.fromRGB(196, 198, 204)
local TRUNK = Color3.fromRGB(128, 104, 80)
local LEAF = Color3.fromRGB(62, 118, 60)
-- AutoNeon's one accent: electric blue (the NEON in the logo, tag outlines, flags, the night glow).
local BRAND = Color3.fromRGB(0, 170, 230) -- #00AAE6
local BRAND_GLOW = Color3.fromRGB(40, 200, 255)
local PASS_GLOW = Color3.fromRGB(255, 200, 90)
local CEILING_GLOW = Color3.fromRGB(255, 240, 222)
-- Marina Boat Sales: white timber, a slate roof, navy stripes; teal is its accent.
local TIMBER_WHITE = Color3.fromRGB(234, 232, 224)
local CANVAS = Color3.fromRGB(242, 240, 234)
local NAVY = Color3.fromRGB(28, 52, 92)
local SIGN_NAVY = Color3.fromRGB(22, 32, 50)
local MARINA_TEAL = Color3.fromRGB(46, 196, 206) -- #2EC4CE
local SLATE = Color3.fromRGB(84, 90, 98)
local DECK_WOOD = Color3.fromRGB(140, 110, 80)
local PILING = Color3.fromRGB(104, 86, 66)
local TEAK = Color3.fromRGB(128, 92, 62)
local WORKTOP = Color3.fromRGB(230, 228, 222)
local ROPE = Color3.fromRGB(224, 218, 200)
-- Day looks of night neon and lamps (SkyClient switches them after dark).
local TRIM_DAY = Color3.fromRGB(58, 60, 66) -- an unlit neon tube: dark metal
local LAMP_DAY = Color3.fromRGB(226, 226, 220)
local LAMP_WARM = Color3.fromRGB(255, 214, 170)

-- Rich-text logo: AUTO in white, NEON in the brand blue.
local AUTONEON = '<font color="#FFFFFF">AUTO</font><font color="#00AAE6">NEON</font>'

-- AutoNeon Motors. The nearest street is north (z -600), so the glass front faces north.
local SHOW_X = -150 -- centre line: the door and the middle aisle
local SHOW_FRONT = -532 -- outer face of the glass front
local HALF_W = 57 -- outer half width of the building (x -207..-93)
local FLOOR_Y = 0.6 -- top of the tiled floor
local WALL_H = 22
local GLASS_TOP = 16.5
local DOOR_W, DOOR_H = 10, 11.5
local FORECOURT = 10.5 -- paved strip in front of the glass (to z -542.5)
local COLS = { -42, -14, 14, 42 } -- turntable centres across the hall: 10-stud aisles between them
local MIN_ROWS = 3 -- 3 rows of 4 = 12 slots
local ROW_GAP = 23
local DISC = 18 -- turntable diameter: a 16 x 8 car can turn on it
local LOT_BACK = -457.5 -- south edge of the lot that was checked free

-- Marina Boat Sales. The first marina pier is a deck at x 1440..1684, z 1091..1109, top y 0.1;
-- finger docks stay west of x 1664 and the boat launch pads are south of z 1133.
local WATER_Y = -1.5
local PIER_Z = 1100
local PIER_TOP = 0.1
local WALK_X = 1681 -- showcase dock (6 wide) running north off the pier's end; boats moor along its east side
local FIRST_BERTH = PIER_Z - 9 - 14 -- z of the first berth (the pier's north edge is at z 1091)
local BERTH_GAP = 24 -- least distance between berth centres
local BOAT_ROOM = 6 -- open water between one hull and the next
local DOCK_GAP = 2 -- open water between the dock's edge and a hull
local MIN_BERTHS = 3

local NEAR = 40 -- IsNear radius around a display (studs)
local PART_BUDGET = 400 -- per dealership, not counting the vehicles
local POST_GAP = 20 -- seconds between Coast Feed posts about the same player

local feed
local count = 0 -- parts built for the current dealership (budget check)
local stands = {} -- { id, pos }
local standsById = {}
local lastPost = {} -- [player] = os.clock() of their last feed post
local rng = Random.new(2026) -- same look on every server

------------------------------------------------------------------ building helpers

local function part(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.CanTouch = false
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	count += 1
	return p
end

-- Night neon (Look 3.0): tag a part "NightNeon" with its glow colour, so every client's SkyClient turns
-- it to Neon in that colour after dark (and any Light inside it on) and back to dark metal by day.
local function nightNeon(p, color)
	p:SetAttribute("NeonColor", color)
	CollectionService:AddTag(p, "NightNeon")
	return p
end

-- A thin night-neon strip: dark metal by day, glowing `color` after dark.
local function neon(parent, size, cf, color, name)
	return nightNeon(part(parent, size, cf, TRIM_DAY, Enum.Material.Metal, { Name = name or "Neon", CanCollide = false, CanQuery = false }), color)
end

-- A small decorative piece nothing collides with or queries (frames, mats, trims, roof units, flags).
local function detail(parent, size, cf, color, material, name)
	return part(parent, size, cf, color, material, { Name = name, CanCollide = false, CanQuery = false })
end

-- A downlight (tag "NightLamp"): a pale lens by day; after dark SkyClient lights it in LampColor and
-- switches on its SpotLight onto whatever is below.
local function lamp(parent, cf, name, range, angle)
	local p = detail(parent, Vector3.new(1.2, 0.1, 1.2), cf, LAMP_DAY, Enum.Material.SmoothPlastic, name)
	p:SetAttribute("LampColor", LAMP_WARM)
	CollectionService:AddTag(p, "NightLamp")
	local spot = Instance.new("SpotLight")
	spot.Name = "Lamp"
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = angle
	spot.Range = range
	spot.Brightness = 1.8
	spot.Color = LAMP_WARM
	spot.Shadows = false
	spot.Enabled = false -- SkyClient switches it on after dark
	spot.Parent = p
	return p
end

-- Upright cylinder (turntables, posts): `height` along world Y, centred on `pos`.
local function cylinder(parent, diameter, height, pos, color, material, props)
	local p = part(parent, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A PointLight inside a night-neon part: off by day, SkyClient switches it on with the part after dark.
local function glow(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Enabled = false
	l.Parent = p
	return l
end

-- Text on one face of a part (rich text allowed). LightInfluence 0: clean by day, it glows at night.
-- Oswald for names and headlines; pass GothamBold for small print.
local function surfaceText(p, face, text, color, font)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.MaxDistance = 600
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.Oswald
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.08, 0), UDim.new(0.08, 0)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.03, 0), UDim.new(0.03, 0)
	pad.Parent = label
	gui.Parent = p
	return label
end

-- Dark metal sign board with thin night-neon strips along the top and bottom (dark metal by day, `glowColor`
-- after dark). Text shows on the Front face (the board's LookVector side) and on any other faces listed.
-- Returns the board and its bottom strip (a light for the sign goes in the strip, so it only shines at night).
local function signBoard(parent, cf, w, h, text, glowColor, faces, boardColor)
	local board = part(parent, Vector3.new(w, h, 0.6), cf, boardColor or SIGN_BOARD, Enum.Material.Metal, { Name = "Sign", CanCollide = false })
	neon(parent, Vector3.new(w + 0.6, 0.4, 0.7), cf * CFrame.new(0, h / 2, 0), glowColor, "SignTrim")
	local strip = neon(parent, Vector3.new(w + 0.6, 0.4, 0.7), cf * CFrame.new(0, -h / 2, 0), glowColor, "SignTrim")
	for _, face in ipairs(faces or { Enum.NormalId.Front }) do
		surfaceText(board, face, text, Color3.new(1, 1, 1))
	end
	return board, strip
end

-- Palm: the generated palm mesh the city art uses (ServerStorage.ArtAssets.PalmTree) or a part palm.
local function palm(parent, pos, scale)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("PalmTree")
	if template and template:IsA("BasePart") then
		local p = template:Clone()
		p.Anchored = true
		p.CanTouch = false
		p.CastShadow = true -- like the city's street palms (Look3)
		p.Size = template.Size * scale
		p.CFrame = CFrame.new(pos + Vector3.new(0, p.Size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
		p.Parent = parent
		count += 1
		return
	end
	local h = 20 * scale
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(7), 0, 0)
	part(parent, Vector3.new(h, 1.4 * scale, 1.4 * scale), base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), TRUNK,
		Enum.Material.Wood, { Name = "Trunk", Shape = Enum.PartType.Cylinder, CastShadow = true })
	local top = base * CFrame.new(0, h, 0)
	for f = 1, 6 do
		part(parent, Vector3.new(2.2 * scale, 0.3, 10 * scale),
			top * CFrame.Angles(0, math.rad(f * 60), 0) * CFrame.new(0, 0, -4.5 * scale) * CFrame.Angles(math.rad(-18), 0, 0),
			LEAF, Enum.Material.Grass, { Name = "Frond", CanCollide = false, CanQuery = false })
	end
end

local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

local function priceText(def)
	if def.Pass then
		return "GAME PASS"
	elseif def.UnlockCopRank then
		return "COP RANK " .. def.UnlockCopRank
	elseif def.UnlockHeists then
		return "🔒 " .. def.UnlockHeists .. " BIG HEISTS"
	elseif (def.Price or 0) > 0 then
		return money(def.Price)
	end
	return "FREE"
end

-- Warn (only) if a dealership overlaps something already in the city, so the lead can move it.
local function checkLot(name, cf, size)
	local list = {}
	local city = Workspace:FindFirstChild("City")
	for _, n in ipairs({ "Art", "Buildings", "Landmarks" }) do
		local f = city and city:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	for _, n in ipairs({ "Heists", "Spawns", "Activities" }) do
		local f = Workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	if #list == 0 then
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	local hits = Workspace:GetPartBoundsInBox(cf, size, params)
	if #hits > 0 then
		local names = {}
		for i = 1, math.min(#hits, 4) do
			table.insert(names, hits[i]:GetFullName())
		end
		warn(string.format("[DealershipService] %s overlaps %d existing part(s), e.g. %s", name, #hits, table.concat(names, ", ")))
	end
end

------------------------------------------------------------------ displays

-- Name tag over a display: vehicle name and price (DealerClient swaps the price for OWNED). A dark
-- pill outlined in the place's accent (gold for game-pass cars).
local function tag(p, def, height, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DealerTag"
	gui.Size = UDim2.fromScale(11, 3.2) -- in studs, so tags shrink with distance like real signs
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	if def then
		gui:SetAttribute("VehicleId", def.Id)
	end
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = DARK
	pill.BackgroundTransparency = 0.15
	pill.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.3, 0)
	c.Parent = pill
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 2
	s.Parent = pill
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromScale(0.05, 0.06)
	title.Size = UDim2.fromScale(0.9, 0.52)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Oswald
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = def and string.upper(def.DisplayName or def.Id) or "COMING SOON"
	title.Parent = pill
	local price = title:Clone()
	price.Name = "Price"
	price.Position = UDim2.fromScale(0.05, 0.58)
	price.Size = UDim2.fromScale(0.9, 0.36)
	price.Font = Enum.Font.GothamBold -- small print
	price.TextColor3 = def and GOLD or SOFT
	price.Text = def and priceText(def) or "New rides arriving soon"
	price.Parent = pill
	gui.Parent = p
	return gui
end

local function viewPrompt(p, def, range)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DealerView"
	prompt.ActionText = "View"
	prompt.ObjectText = def.DisplayName or def.Id
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = range
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("VehicleId", def.Id)
	prompt.Parent = p
end

local function stand(def, pos)
	local s = { id = def.Id, pos = pos }
	table.insert(stands, s)
	standsById[def.Id] = s
end

-- Same source as VehicleService: a hand-made template if there is one, else CarBuilder.
local function vehicleModel(id)
	local templates = ServerStorage:FindFirstChild("VehicleTemplates")
	local t = templates and templates:FindFirstChild(id)
	if t then
		return t:Clone()
	end
	return CarBuilder.Build(id)
end

-- Lowest point of the visible parts (the tyres, on a car).
local function lowestVisible(model)
	local low
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf, s = d.CFrame, d.Size
			local half = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2
			if not low or cf.Y - half < low then
				low = cf.Y - half
			end
		end
	end
	return low
end

-- How far the visible parts reach from the model's pivot along its own X / Y / Z axes (half sizes).
-- A mesh hull can be bigger than the def's Size.
local function visibleHalf(model)
	local frame = model:GetPivot()
	local half = Vector3.zero
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local rel, s = frame:ToObjectSpace(d.CFrame), d.Size
			local r, u, l = rel.RightVector, rel.UpVector, rel.LookVector
			local ext = Vector3.new(
				math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
				math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
				math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
			) / 2
			local c = rel.Position
			half = half:Max((c + ext):Abs()):Max((c - ext):Abs())
		end
	end
	return half
end

-- A display vehicle: the real model with nothing to sit in or drive, every part anchored and only the
-- chassis colliding. Not placed or parented yet (placeDisplay does that); nil if it couldn't be built.
local function displayModel(def)
	local ok, car = pcall(vehicleModel, def.Id)
	if not ok or not car then
		warn("[DealershipService] couldn't build " .. tostring(def.Id) .. ": " .. tostring(car))
		return nil
	end
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("Seat") or d:IsA("VehicleSeat") or d:IsA("ProximityPrompt") or d:IsA("BaseScript")
			or d:IsA("VectorForce") or d:IsA("Torque") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") and (d.Name == "Underglow" or string.match(d.Name, "^Bump%u%u$")) then
			d:Destroy() -- underglow is an upgrade (show the stock car); bump balls only hold up parked cars
		end
	end
	local chassis = car.PrimaryPart
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy() -- all anchored: joints would only drag parts along when a client spins the car
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = d == chassis
			d.CanQuery = d == chassis
		end
	end
	return car
end

-- Put a display model in place. `cf` is where the chassis goes; with `groundY` the car is then raised or
-- lowered so its tyres touch that height (boats pass nil: their cf is already their floating height).
-- `motion` ("Spin" / "Bob") tells DealerClient how to animate it.
local function placeDisplay(parent, car, def, cf, groundY, motion)
	car:PivotTo(cf)
	if groundY then
		local low = lowestVisible(car)
		if low then
			car:PivotTo(cf + Vector3.new(0, groundY - low, 0))
		end
	end
	car.Name = "Display_" .. def.Id
	car:SetAttribute("NCVehicle", nil) -- not a drivable car to any other system
	car:SetAttribute("OwnerUserId", nil)
	car:SetAttribute("DealerDisplay", true)
	car:SetAttribute("DisplayPivot", car:GetPivot())
	car:SetAttribute("DisplayMotion", motion)
	car:SetAttribute("DisplayPhase", rng:NextNumber(0, math.pi * 2))
	pcall(function()
		car.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the client sees the whole car or none of it
	end)
	car.Parent = parent
	return car
end

------------------------------------------------------------------ AutoNeon Motors

local function buildShowroom(root, cars)
	count = 0
	local m = Instance.new("Model")
	m.Name = "AutoNeonMotors"
	m:SetAttribute("PlaceName", "AutoNeon Motors")
	m:SetAttribute("PlaceKind", "Car dealer: see every ride")
	local X, F = SHOW_X, SHOW_FRONT
	local rows = math.max(MIN_ROWS, math.ceil(#cars / #COLS))
	local firstRow = F + 14 -- glass (1) + walkway (4) + turntable radius (9)
	local back = firstRow + (rows - 1) * ROW_GAP + 14 -- outer face of the back wall
	local depth = back - F
	local midZ = (F + back) / 2
	local x0 = X - HALF_W

	-- Polished floor: big marble tiles in two close light greys.
	local tilesX = 12
	local tilesZ = math.max(1, math.floor(depth / 9.25 + 0.5))
	local tw, td = HALF_W * 2 / tilesX, depth / tilesZ
	for i = 0, tilesX - 1 do
		for j = 0, tilesZ - 1 do
			part(m, Vector3.new(tw, 1, td), CFrame.new(x0 + (i + 0.5) * tw, FLOOR_Y - 0.5, F + (j + 0.5) * td),
				(i + j) % 2 == 0 and TILE_A or TILE_B, Enum.Material.Marble, { Name = "Tile", Reflectance = 0.12 })
		end
	end

	-- Forecourt: concrete paving with a kerb stone along the street edge, a dark entrance mat and two
	-- concrete planters with palms (a night-neon uplight strip along each).
	local pave = part(m, Vector3.new(HALF_W * 2 + 6, 0.3, FORECOURT), CFrame.new(X, 0.15, F - FORECOURT / 2), PAVING,
		Enum.Material.Concrete, { Name = "Forecourt" })
	m.PrimaryPart = pave
	detail(m, Vector3.new(HALF_W * 2 + 6, 0.12, 0.5), CFrame.new(X, 0.33, F - FORECOURT + 0.25), KERB, Enum.Material.Concrete, "Kerb")
	detail(m, Vector3.new(DOOR_W - 1, 0.1, 3), CFrame.new(X, 0.33, F - 2), MAT, Enum.Material.Fabric, "WelcomeMat")
	for _, s in ipairs({ -1, 1 }) do
		part(m, Vector3.new(14, 1.6, 4), CFrame.new(X + s * 42, 0.8, F - 5.5), PLANTER, Enum.Material.Concrete, { Name = "Planter", CastShadow = true })
		detail(m, Vector3.new(13.2, 0.2, 3.2), CFrame.new(X + s * 42, 1.62, F - 5.5), SOIL, Enum.Material.Grass, "Soil")
		neon(m, Vector3.new(14.2, 0.3, 0.2), CFrame.new(X + s * 42, 1.2, F - 7.55), BRAND_GLOW, "PlanterTrim")
		for _, ox in ipairs({ 38, 46 }) do
			palm(m, Vector3.new(X + s * ox, 1.6, F - 5.5), 1.15)
		end
	end

	-- Side walls: white plaster panels, a ribbon of tinted glass, plaster again; the sill strip under the
	-- glass is night neon.
	for _, s in ipairs({ -1, 1 }) do
		local wx = X + s * (HALF_W - 0.5)
		part(m, Vector3.new(1, 10 - FLOOR_Y, depth), CFrame.new(wx, (FLOOR_Y + 10) / 2, midZ), WHITE_PANEL, Enum.Material.Plaster,
			{ Name = "Wall", CastShadow = true })
		part(m, Vector3.new(0.6, GLASS_TOP - 10, depth), CFrame.new(wx, (10 + GLASS_TOP) / 2, midZ), GLASS, Enum.Material.Glass,
			{ Name = "Window", Transparency = 0.45, Reflectance = 0.1 })
		part(m, Vector3.new(1, WALL_H - GLASS_TOP, depth), CFrame.new(wx, (GLASS_TOP + WALL_H) / 2, midZ), WHITE_PANEL, Enum.Material.Plaster,
			{ Name = "Wall", CastShadow = true })
		neon(m, Vector3.new(0.3, 0.4, depth), CFrame.new(X + s * (HALF_W + 0.1), 10, midZ), BRAND_GLOW, "Stripe")
	end
	part(m, Vector3.new(HALF_W * 2 - 2, WALL_H - FLOOR_Y, 1), CFrame.new(X, (FLOOR_Y + WALL_H) / 2, back - 0.5), GREY_PANEL, Enum.Material.Plaster,
		{ Name = "BackWall", CastShadow = true })
	neon(m, Vector3.new(HALF_W * 2 - 2, 0.3, 0.3), CFrame.new(X, FLOOR_Y + 0.15, back - 1.15), BRAND_GLOW, "Cove")

	-- Glass front: two big tinted panes in dark metal mullions, an open doorway in the middle in a dark
	-- metal frame, a small OPEN sign behind the glass.
	local paneW = HALF_W - 1 - DOOR_W / 2 -- each pane runs from a side wall to the door
	local glassMid = (FLOOR_Y + GLASS_TOP) / 2
	for _, s in ipairs({ -1, 1 }) do
		part(m, Vector3.new(paneW, GLASS_TOP - FLOOR_Y, 0.6), CFrame.new(X + s * (DOOR_W / 2 + paneW / 2), glassMid, F + 0.5), GLASS,
			Enum.Material.Glass, { Name = "Window", Transparency = 0.5, Reflectance = 0.1 })
		for k = 1, 3 do
			part(m, Vector3.new(0.8, GLASS_TOP - FLOOR_Y, 1.2), CFrame.new(X + s * (DOOR_W / 2 + paneW * k / 4), glassMid, F + 0.5),
				FRAME, Enum.Material.Metal, { Name = "Mullion" })
		end
		detail(m, Vector3.new(0.8, DOOR_H - FLOOR_Y, 1.3), CFrame.new(X + s * (DOOR_W / 2 + 0.4), (FLOOR_Y + DOOR_H) / 2, F + 0.5), FRAME,
			Enum.Material.Metal, "DoorFrame")
	end
	part(m, Vector3.new(DOOR_W, GLASS_TOP - DOOR_H, 0.6), CFrame.new(X, (DOOR_H + GLASS_TOP) / 2, F + 0.5), GLASS, Enum.Material.Glass,
		{ Name = "Transom", Transparency = 0.5, Reflectance = 0.1 })
	detail(m, Vector3.new(DOOR_W + 1.6, 0.8, 1.3), CFrame.new(X, DOOR_H + 0.4, F + 0.5), FRAME, Enum.Material.Metal, "DoorFrame")
	local openSign = part(m, Vector3.new(5, 1.6, 0.2), CFrame.new(X + 11.5, 7, F + 1.3), SIGN_BOARD, nil, { Name = "OpenSign", CanCollide = false })
	surfaceText(openSign, Enum.NormalId.Front, "OPEN 24/7", Color3.fromRGB(255, 244, 230), Enum.Font.GothamBold)

	-- Fascia: a white band over the glass carrying the big AUTONEON MOTORS sign; a dark metal canopy over
	-- the door with downlights under it.
	part(m, Vector3.new(HALF_W * 2 - 2, WALL_H - GLASS_TOP, 1), CFrame.new(X, (GLASS_TOP + WALL_H) / 2, F + 0.5), WHITE_PANEL,
		Enum.Material.Plaster, { Name = "Fascia", CastShadow = true })
	local _, signStrip = signBoard(m, CFrame.new(X, (GLASS_TOP + WALL_H) / 2, F - 0.3), 66, 4.4, AUTONEON .. " MOTORS", BRAND_GLOW)
	glow(signStrip, BRAND_GLOW, 30, 1.2)
	part(m, Vector3.new(28, 0.8, 5), CFrame.new(X, 15.7, F - 2.5), FRAME, Enum.Material.Metal, { Name = "Canopy", CastShadow = true })
	neon(m, Vector3.new(28.4, 0.4, 0.4), CFrame.new(X, 15.5, F - 5.1), BRAND_GLOW, "CanopyTrim")
	for _, dx in ipairs({ -9, 0, 9 }) do
		lamp(m, CFrame.new(X + dx, 15.25, F - 2.5), "CanopyLight", 20, 110)
	end

	-- Roof: a pale membrane (no shadow, so the hall stays bright by day) with a night-neon parapet cap
	-- along the front and sides, two roof units and a pair of brand flags over the front.
	part(m, Vector3.new(HALF_W * 2 + 1, 1, depth + 1), CFrame.new(X, WALL_H + 0.5, midZ), ROOF, Enum.Material.Concrete, { Name = "Roof" })
	neon(m, Vector3.new(HALF_W * 2 + 1.4, 0.5, 0.5), CFrame.new(X, WALL_H + 1.1, F - 0.7), BRAND_GLOW, "Roofline")
	for _, s in ipairs({ -1, 1 }) do
		neon(m, Vector3.new(0.5, 0.5, depth + 1.4), CFrame.new(X + s * (HALF_W + 0.7), WALL_H + 1.1, midZ), BRAND_GLOW, "Roofline")
	end
	for _, u in ipairs({ { -24, 12 }, { 18, 6 } }) do
		detail(m, Vector3.new(6, 2.6, 4.4), CFrame.new(X + u[1], WALL_H + 2.3, midZ + u[2]), UNIT, Enum.Material.Metal, "RoofUnit")
	end
	for _, s in ipairs({ -1, 1 }) do
		local px = X + s * 50
		cylinder(m, 0.35, 10, Vector3.new(px, WALL_H + 6, F + 3), SILVER, Enum.Material.Metal,
			{ Name = "FlagPole", CanCollide = false, CanQuery = false })
		detail(m, Vector3.new(5, 3, 0.12), CFrame.new(px + 2.65, WALL_H + 9.3, F + 3), BRAND, Enum.Material.Fabric, "Flag")
	end
	-- Ceiling light strips over the three aisles: dark tracks by day, lit after dark.
	for _, ax in ipairs({ -28, 0, 28 }) do
		local strip = neon(m, Vector3.new(1.2, 0.2, depth - 8), CFrame.new(X + ax, WALL_H - 0.1, midZ), CEILING_GLOW, "CeilingLight")
		local l = Instance.new("SurfaceLight")
		l.Face = Enum.NormalId.Bottom
		l.Range = 24
		l.Angle = 120
		l.Brightness = 1.2
		l.Color = CEILING_GLOW
		l.Shadows = false
		l.Enabled = false -- SkyClient switches it on with the strip
		l.Parent = strip
	end
	-- Logo on the back wall, above the back row.
	local logo = part(m, Vector3.new(46, 7, 0.4), CFrame.new(X, 15.5, back - 1.2), SIGN_BOARD, Enum.Material.Metal, { Name = "Logo", CanCollide = false })
	surfaceText(logo, Enum.NormalId.Front, AUTONEON .. ' <font color="#C8CCD2">MOTORS</font>', Color3.new(1, 1, 1))
	neon(m, Vector3.new(46.6, 0.3, 0.5), CFrame.new(X, 19.15, back - 1.2), BRAND_GLOW, "LogoTrim")
	neon(m, Vector3.new(46.6, 0.3, 0.5), CFrame.new(X, 11.85, back - 1.2), BRAND_GLOW, "LogoTrim")

	-- Brand pylon on the front corner: brushed aluminium, the name down a dark panel, night-neon reveal
	-- bands and a dark crown with the AN badge.
	local finX = x0 - 0.5
	part(m, Vector3.new(5, 42, 8), CFrame.new(finX, 21, F), SILVER, Enum.Material.Metal, { Name = "Fin", CastShadow = true })
	local finSign = part(m, Vector3.new(4, 28, 0.4), CFrame.new(finX, 20, F - 4.2), SIGN_BOARD, Enum.Material.Metal,
		{ Name = "FinSign", CanCollide = false })
	surfaceText(finSign, Enum.NormalId.Front, '<font color="#FFFFFF">A\nU\nT\nO</font>\n<font color="#00AAE6">N\nE\nO\nN</font>', Color3.new(1, 1, 1))
	local topBand
	for _, y in ipairs({ 36.5, 38.5, 40.5 }) do
		topBand = neon(m, Vector3.new(5.4, 0.5, 8.4), CFrame.new(finX, y, F), BRAND_GLOW, "FinBand")
	end
	glow(topBand, BRAND_GLOW, 30, 1)
	local cap = part(m, Vector3.new(5.4, 3, 8.4), CFrame.new(finX, 43.5, F), FRAME, Enum.Material.Metal,
		{ Name = "FinCap", CanCollide = false, CanQuery = false })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Left }) do
		surfaceText(cap, face, '<font color="#FFFFFF">A</font><font color="#00AAE6">N</font>', Color3.new(1, 1, 1))
	end

	-- Turntables, cheapest car first: front row left to right, then the next row back (game-pass cars
	-- last, on gold turntables under a ceiling spotlight). Each sits in a metal ring that glows after dark.
	for i = 1, rows * #COLS do
		local row = math.ceil(i / #COLS)
		local col = (i - 1) % #COLS + 1
		local x, z = X + COLS[col], firstRow + (row - 1) * ROW_GAP
		local def = cars[i]
		local pass = def and def.Pass
		local accent = pass and GOLD or BRAND
		nightNeon(cylinder(m, DISC + 0.8, 0.3, Vector3.new(x, FLOOR_Y + 0.15, z), TRIM_DAY, Enum.Material.Metal,
			{ Name = "TurntableGlow", CanCollide = false, CanQuery = false }), pass and PASS_GLOW or BRAND_GLOW)
		cylinder(m, DISC, 0.8, Vector3.new(x, FLOOR_Y + 0.4, z), pass and PASS_GOLD or TURNTABLE, Enum.Material.Metal,
			{ Name = "Turntable", Reflectance = 0.2 })
		if pass then
			-- A spotlight in the ceiling shining straight down on the car (a small lens, lit day and night).
			detail(m, Vector3.new(3.8, 0.3, 3.8), CFrame.new(x, WALL_H - 0.15, z), FRAME, Enum.Material.Metal, "SpotHousing")
			local lens = detail(m, Vector3.new(3, 0.3, 3), CFrame.new(x, WALL_H - 0.25, z), SPOT_LENS, Enum.Material.Neon, "Spotlight")
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Bottom
			spot.Angle = 50
			spot.Range = 28
			spot.Brightness = 4
			spot.Color = SPOT_LENS
			spot.Shadows = false
			spot.Parent = lens
		end
		local point = part(m, Vector3.new(1, 1, 1), CFrame.new(x, FLOOR_Y + 3, z), accent, nil,
			{ Name = "DisplayPoint", Transparency = 1, CanCollide = false, CanQuery = false })
		tag(point, def, def and 5.5 or 2.5, accent)
		if def then
			point.Name = "DisplayPoint_" .. def.Id
			viewPrompt(point, def, 15)
			stand(def, point.Position)
			local yaw = CFrame.Angles(0, math.rad(col <= 2 and 35 or -35), 0) -- a three-quarter view toward the door
			local car = displayModel(def)
			if car then
				placeDisplay(m, car, def, CFrame.new(x, FLOOR_Y + 4, z) * yaw, FLOOR_Y + 0.8, "Spin")
			end
		end
	end

	checkLot("AutoNeon Motors", CFrame.new(X, 12, (F - FORECOURT + back) / 2), Vector3.new(HALF_W * 2 + 6, 20, depth + FORECOURT))
	if back > LOT_BACK then
		warn(string.format("[DealershipService] AutoNeon Motors needs %d rows for %d cars: its back wall moved to z %s "
			.. "(the checked lot ends at z %s). Make sure the lot behind it is clear.", rows, #cars, tostring(back), tostring(LOT_BACK)))
	end
	if count > PART_BUDGET then
		warn("[DealershipService] AutoNeon Motors used " .. count .. " parts (budget " .. PART_BUDGET .. ")")
	end
	m.Parent = root
	table.insert(DealershipService.Places, { Name = "AutoNeon Motors", Kind = "Car dealer", Pos = Vector3.new(X, 0, F - FORECOURT / 2) })
end

------------------------------------------------------------------ Marina Boat Sales

local function buildMarina(root, boats)
	count = 0
	local m = Instance.new("Model")
	m.Name = "MarinaBoatSales"
	m:SetAttribute("PlaceName", "Marina Boat Sales")
	m:SetAttribute("PlaceKind", "Boats and jet skis")

	-- Build the boats first: each berth is sized to its hull (the def's Size or the mesh, whichever is
	-- bigger), so a yacht gets a long berth and a jet ski a short one. Empty berths are "coming soon".
	local berths = {}
	for i = 1, math.max(MIN_BERTHS, #boats) do
		local def = boats[i]
		local b = { def = def, len = 20, width = 8 }
		if def then
			b.cfg = Vehicles.Resolve(def.Id)
			b.len, b.width = b.cfg.Size.Z, b.cfg.Size.X
			b.car = displayModel(def)
			if b.car then
				local half = visibleHalf(b.car)
				b.len = math.max(b.len, half.Z * 2)
				b.width = math.max(b.width, half.X * 2)
			end
		end
		berths[i] = b
	end
	-- Bows north, one after another up the dock: at least BERTH_GAP between centres and BOAT_ROOM of
	-- water between hulls; each hull sits DOCK_GAP off the dock's east edge.
	local pierEdge = PIER_Z - 9 -- the pier's north edge
	local lineX = WALK_X + 3 -- x of the berth lines: just past the widest hull
	for i, b in ipairs(berths) do
		if i == 1 then
			b.z = math.min(FIRST_BERTH, pierEdge - 3 - b.len / 2)
		else
			local prev = berths[i - 1]
			b.z = prev.z - math.max(BERTH_GAP, prev.len / 2 + b.len / 2 + BOAT_ROOM)
		end
		b.x = WALK_X + 3 + DOCK_GAP + b.width / 2
		lineX = math.max(lineX, b.x + b.width / 2 + 2.5)
	end
	local last = berths[#berths]
	local north = last.z - math.max(BERTH_GAP / 2, last.len / 2 + 3) -- far end of the showcase dock
	local south = PIER_Z - 8 -- tucked 1 stud under the pier's north edge
	local len = south - north
	local midZ = (south + north) / 2

	-- Showcase dock: a floating timber walkway off the pier's end with metal edge strips that glow teal
	-- after dark, and wooden pilings with white caps between the berths.
	part(m, Vector3.new(6, 1.2, len), CFrame.new(WALK_X, -0.6, midZ), DECK_WOOD, Enum.Material.WoodPlanks, { Name = "ShowcaseDock" })
	neon(m, Vector3.new(0.3, 0.25, len), CFrame.new(WALK_X - 3.05, 0.05, midZ), MARINA_TEAL, "DockEdge")
	local edge = neon(m, Vector3.new(0.3, 0.25, len), CFrame.new(WALK_X + 3.05, 0.05, midZ), MARINA_TEAL, "DockEdge")
	glow(edge, MARINA_TEAL, 28, 0.8)
	local function mooringPost(z)
		cylinder(m, 1.2, 4, Vector3.new(WALK_X + 3.6, 0, z), PILING, Enum.Material.Wood, { Name = "MooringPost" })
		cylinder(m, 1.35, 0.3, Vector3.new(WALK_X + 3.6, 2.1, z), TIMBER_WHITE, nil, { Name = "PostCap", CanCollide = false, CanQuery = false })
	end
	-- One by the pier, one in the middle of each stretch of water between hulls, one at the far end.
	local first = berths[1]
	mooringPost(math.min(first.z + math.max(BERTH_GAP / 2, first.len / 2 + 3), pierEdge - 1.5))
	for i = 2, #berths do
		local a, b = berths[i - 1], berths[i]
		mooringPost(((a.z - a.len / 2) + (b.z + b.len / 2)) / 2)
	end
	mooringPost(north + 1)

	-- Berths: a floating rope line on the far side, the tag over the boat, the View prompt beside it.
	for _, b in ipairs(berths) do
		local accent = MARINA_TEAL
		detail(m, Vector3.new(0.4, 0.3, math.max(b.len + 2, BERTH_GAP - 4)), CFrame.new(lineX, WATER_Y + 0.1, b.z), ROPE, Enum.Material.Fabric, "BerthLine")
		local point = part(m, Vector3.new(1, 1, 1), CFrame.new(b.x, 2.5, b.z), accent, nil,
			{ Name = "DisplayPoint", Transparency = 1, CanCollide = false, CanQuery = false })
		local def = b.def
		tag(point, def, def and 6 or 2, accent)
		if def then
			point.Name = "DisplayPoint_" .. def.Id
			viewPrompt(point, def, 12)
			stand(def, point.Position)
			if b.car then
				local cfg = b.cfg
				-- The height a driven boat rides at: its water springs settle at 45% of their travel.
				local y = WATER_Y + cfg.Size.Y / 2 - 0.6 + cfg.RestLength * 0.55 + cfg.WheelRadius
				placeDisplay(m, b.car, def, CFrame.new(b.x, y, b.z), nil, "Bob")
			end
		end
	end

	-- Kiosk on the pier's end (south half, so the way onto the showcase dock stays open): white timber
	-- walls, a teak counter with a stone top facing back down the pier, a slate metal roof with teal
	-- night-neon edges, a navy-and-white canvas awning, a downlight over the counter and the sign on the roof.
	local kx0, kx1, kz0, kz1 = 1673, 1684, 1100.5, 1108.5
	local kcx, kcz = (kx0 + kx1) / 2, (kz0 + kz1) / 2
	local wallH = 9
	part(m, Vector3.new(1, wallH, kz1 - kz0), CFrame.new(kx1 - 0.5, PIER_TOP + wallH / 2, kcz), TIMBER_WHITE, Enum.Material.WoodPlanks,
		{ Name = "KioskWall", CastShadow = true })
	part(m, Vector3.new(kx1 - kx0 - 1, wallH, 1), CFrame.new(kcx - 0.5, PIER_TOP + wallH / 2, kz1 - 0.5), TIMBER_WHITE, Enum.Material.WoodPlanks,
		{ Name = "KioskWall", CastShadow = true })
	part(m, Vector3.new(0.8, wallH, 0.8), CFrame.new(kx0 + 0.4, PIER_TOP + wallH / 2, kz0 + 0.4), TIMBER_WHITE, Enum.Material.Wood,
		{ Name = "KioskPost", CastShadow = true })
	part(m, Vector3.new(1.2, 3.4, kz1 - kz0 - 1.8), CFrame.new(kx0 + 0.6, PIER_TOP + 1.7, kcz - 0.1), TEAK, Enum.Material.WoodPlanks,
		{ Name = "Counter", CastShadow = true })
	detail(m, Vector3.new(1.4, 0.25, kz1 - kz0 - 1.8), CFrame.new(kx0 + 0.6, PIER_TOP + 3.45, kcz - 0.1), WORKTOP, Enum.Material.Marble, "CounterTrim")
	local roof = part(m, Vector3.new(kx1 - kx0 + 2, 0.6, kz1 - kz0 + 1.4), CFrame.new(kcx - 1, PIER_TOP + wallH + 0.3, kcz), SLATE, Enum.Material.Metal,
		{ Name = "KioskRoof", CastShadow = true })
	m.PrimaryPart = roof
	neon(m, Vector3.new(0.4, 0.4, kz1 - kz0 + 1.4), CFrame.new(kx0 - 2, PIER_TOP + wallH + 0.3, kcz), MARINA_TEAL, "RoofTrim")
	neon(m, Vector3.new(kx1 - kx0 + 2, 0.4, 0.4), CFrame.new(kcx - 1, PIER_TOP + wallH + 0.3, kz0 - 0.7), MARINA_TEAL, "RoofTrim")
	lamp(m, CFrame.new(kx0 + 0.6, PIER_TOP + wallH - 0.05, kcz - 0.1), "KioskLight", 16, 110)
	local stripe = (kz1 - kz0) / 4
	for k = 0, 3 do
		-- Tilted so the outer edge hangs lower (+X end up).
		part(m, Vector3.new(3.6, 0.25, stripe), CFrame.new(kx0 - 2.6, PIER_TOP + wallH - 0.9, kz0 + (k + 0.5) * stripe) * CFrame.Angles(0, 0, math.rad(22)),
			k % 2 == 0 and NAVY or CANVAS, Enum.Material.Fabric, { Name = "Awning", CanCollide = false })
	end
	-- Sign faces west (down the pier); the back face reads from the sea.
	local signPos = Vector3.new(kcx, PIER_TOP + wallH + 2.4, kcz)
	local _, signStrip = signBoard(m, CFrame.lookAt(signPos, signPos + Vector3.new(-1, 0, 0)), 11, 3.2,
		'<font color="#2EC4CE">MARINA</font> BOAT SALES', MARINA_TEAL, { Enum.NormalId.Front, Enum.NormalId.Back }, SIGN_NAVY)
	glow(signStrip, MARINA_TEAL, 26, 1.2)

	local lotX0, lotX1 = 1671, math.max(1699, lineX + 1) -- from the kiosk's awning to past the berth lines
	checkLot("Marina Boat Sales", CFrame.new((lotX0 + lotX1) / 2, 7.3, (north + kz1) / 2), Vector3.new(lotX1 - lotX0, 13.4, kz1 - north))
	if count > PART_BUDGET then
		warn("[DealershipService] Marina Boat Sales used " .. count .. " parts (budget " .. PART_BUDGET .. ")")
	end
	m.Parent = root
	table.insert(DealershipService.Places, { Name = "Marina Boat Sales", Kind = "Boat dealer", Pos = Vector3.new(kcx, 0, kz0 - 5) })
end

------------------------------------------------------------------ purchases -> Coast Feed

local function forSale(filter)
	local list = {}
	for _, def in ipairs(Vehicles.List) do
		if not def.Hidden and filter(def) then -- Hidden: street cars, never for sale
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a.Price or 0, b.Price or 0
		if pa ~= pb then
			return pa < pb
		end
		return a.Id < b.Id
	end)
	return list
end

local function ownedSet(player)
	local set = {}
	for id in string.gmatch(player:GetAttribute("OwnedCars") or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function announce(player, def)
	local now = os.clock()
	if lastPost[player] and now - lastPost[player] < POST_GAP then
		return
	end
	lastPost[player] = now
	local name = def.DisplayName or def.Id
	local article = string.find(string.lower(name), "^[aeiou]") and "an " or "a "
	local where = def.Boat and "Marina Boat Sales" or "AutoNeon Motors"
	feed:FireAllClients("Event", { Text = player.DisplayName .. " just bought " .. article .. name .. " at " .. where .. "!" })
end

-- GarageService mirrors ownership to the "OwnedCars" attribute; a new id that appears while the player
-- stands at its display was bought here.
local function watchPurchases(player)
	local known = player:GetAttribute("OwnedCars") ~= nil and ownedSet(player) or nil
	player:GetAttributeChangedSignal("OwnedCars"):Connect(function()
		local now = ownedSet(player)
		if known then
			for id in pairs(now) do
				local def = Vehicles.ById[id]
				if not known[id] and def and standsById[id] and DealershipService.IsNear(player, id) then
					announce(player, def)
				end
			end
		end
		known = now -- the first list (right after the save loads) is only the starting point
	end)
end

------------------------------------------------------------------ API

function DealershipService.IsNear(player, id)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, s in ipairs(stands) do
		if (id == nil or s.id == id) and (root.Position - s.pos).Magnitude <= NEAR then
			return true
		end
	end
	return false
end

function DealershipService.Init()
	feed = Remotes.Event("Feed")
	local old = Workspace:FindFirstChild("Dealerships")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Dealerships"
	root.Parent = Workspace
	local cars = forSale(function(def)
		return not def.Boat and not def.Police and not def.Pass and (def.Price or 0) > 0
	end)
	-- Civilian game-pass cars go after the cash cars (their own spotlit turntables).
	for _, def in ipairs(forSale(function(def)
		return not def.Boat and not def.Police and def.Pass ~= nil
	end)) do
		table.insert(cars, def)
	end
	local boats = forSale(function(def)
		return def.Boat == true and not def.Police and not def.Pass
	end)
	for _, job in ipairs({ { "AutoNeon Motors", buildShowroom, cars }, { "Marina Boat Sales", buildMarina, boats } }) do
		local ok, err = pcall(job[2], root, job[3])
		if not ok then
			warn("[DealershipService] " .. job[1] .. " failed to build: " .. tostring(err))
		end
	end
	Players.PlayerAdded:Connect(watchPurchases)
	for _, p in ipairs(Players:GetPlayers()) do
		watchPurchases(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		lastPost[p] = nil
	end)
end

return DealershipService
