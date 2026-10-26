-- HousingService (ModuleScript, ServerScriptService.Services.HousingService)
-- Homes you can buy (Config.Housing). Saved as data.home (one home at a time), mirrored to the
-- player attribute "Home".
--   * Every home has its own build: ServerScriptService.Services.Houses.<Style> (Config.Housing's
--     Style), drawn by HouseBuilder twice: at start-up on its lot in Workspace.Homes as the street sees
--     it (a closed shell: the brick dock loft, the Old Florida bungalow, the family ranch, the downtown
--     tower with its sky garage, the Mediterranean villa, the three-level beach mansion), and inside,
--     for each owner (below). The plain shared shell (`bodies`, legacyExterior / legacyInterior) is
--     only the fallback for a home whose own build is missing or fails. Many players can own the same
--     property: its door leads to each owner's own private inside.
--   * The look follows Look 3.0 (Tools/Look3): real materials in believable colours (Config.Housing's
--     pastel walls become stucco with a hint of their colour here), dark tinted glass, wood and dark
--     metal doors, clay-tile or flat roofs, a paved path and a concrete driveway with edging. Neon is
--     only thin strips and sign outlines, and only after dark: parts tagged "NightNeon" are dark metal
--     by day and every client's SkyClient lights them in their NeonColor attribute. Porch, garage,
--     bollard and indoor lamps are tagged "NightLamp" (LampColor), and about half the windows show a
--     warm lit room after dark (a NightNeon panel inside the glass). Lights inside tagged parts start
--     off (SkyClient switches them). Small details never collide and can't be queried.
--   * Front door prompt: not your home -> a buy card (HouseCard remote, with BUY and TOUR); your
--     home -> go inside.
--   * Buying spends cash here on the server. Buying a new home sells the old one back for half.
--     A purchase is reported to ProgressService as "BuyHome" (JourneyService's goal chain).
--   * Tours: TOUR on the buy card (RequestHouse "Tour") takes a citizen or a cop who is at that door,
--     on foot and not wanted inside a SHOW copy of the home: the same inside, built for the visitor in
--     their own far-off slot (a tour replaces whatever their slot holds, so their own home is rebuilt
--     the next time they go in). A show home's garage bays are empty but for a small "Your cars park
--     here" sign, it has no wardrobe prompt and no cars to drive, and a FOR SALE stand by the entrance
--     whose "Buy this home" prompt opens the normal buy card (HouseCard with At = the stand, where
--     BUY then works). Leaving is the normal Leave, back out of that home's front door. Player
--     attribute "Touring" = the home id while on a tour (InHome is set too: indoors is indoors); both
--     clear on leaving, respawning and leaving the server. Buying on the tour turns the show home
--     into your own inside where you stand (the stand goes, the closet and the garage fill in).
--   * Inside: the whole house again, rooms, stairs and furniture, with its yard (and pools of real
--     Terrain water, filled when the copy is built and cleared with it) inside a small neighbourhood
--     (HouseBuilder's Backdrop) so the windows look out on something, built for each player far off the
--     map (from x = 12000, y = 48, on a grid 2500 studs apart: further than the streaming radius, so
--     nobody else's inside ever streams in around yours) the first time they go in, reused after that,
--     destroyed when they leave the server. Its way out is the front door (the penthouse's: its
--     elevator), with an EXIT sign; a wardrobe (closet and mirror); a garage whose GarageSlots bays show
--     the land cars you own and can drive on your side. "Drive this" takes you out of the front door
--     and seats you in that car on the driveway. Invisible walls round the copy's lot keep everyone on
--     it. Indoors is Look 3.0 too, and softenInterior tones the rooms down a notch.
--   * The wardrobe's "Change look" prompt (WardrobePrompt) has no server handler: the owner's
--     WardrobeUI opens its dressing room from it (and shows its WARDROBE button anywhere inside), and
--     DisguiseService accepts a new look while InHome is set (IsInside: a tour too, where WardrobeUI's
--     button shows unless it checks Touring). A look changed at home never drops a star (only a
--     hideout does that; homes and tours turn wanted players away at the door anyway).
--   * Free-roam (Side "Civilian") home owners who aren't wanted spawn INSIDE their home, in the living
--     room (every respawn, and on join; never cops, prisoners or wanted players, who keep the normal
--     spawn), and VehicleService parks their starter car on the driveway (HousingService.DrivewayFor,
--     with the same rule). On join both wait the same VehicleService.JoinWait for the save, so the
--     player and the car end up in the same place. While the first-join title screen is up (HasPicked
--     not yet set: TeamUI's PLAY sends RequestTeam, which sets it) they wait at their front door, the
--     title camera circling their house, and go in when PLAY is pressed (also when PLAY came while the
--     door area was still loading). Not while FriendsService may still move them beside a friend they
--     arrived to meet (player attribute MeetPending).
--   * No hiding from the police at home: wanted players can't go in or tour, don't spawn at home, and
--     anyone inside who turns out to be wanted is put out of the front door (HomeWanted). "Drive this"
--     is refused while wanted too.
-- Remote RequestHouse(action, arg): "Buy" (home id), "Enter" (home id), "Tour" (home id), "Leave",
-- "Drive" (car id).
-- Server -> client: HouseCard { Id, OldId, Refund, At? (the FOR SALE stand, on a tour) },
-- HouseResult { Kind = "Bought", Id, Refund }, HouseFade ("Out" | "In"). Player attributes "InHome" =
-- true while inside (your own home or a tour), "Touring" = home id while on a tour.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Housing = require(ReplicatedStorage.Shared.Config.Housing)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local GarageService = require(ServerScriptService.Services.GarageService)
local VehicleService = require(ServerScriptService.Services.VehicleService)
local Telemetry = require(ServerScriptService.Services.Telemetry)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)
local HouseBuilder = require(ServerScriptService.Services.HouseBuilder)

local HousingService = {}

-- (on the 4-stud Terrain grid, so a pool's water lines up with its basin: x, y and the gap are multiples of 4)
local INTERIOR_ORIGIN = Vector3.new(12000, 48, 0)
-- Studs between two players' insides: more than the default StreamingTargetRadius (1024), so a
-- player at home never streams in the neighbours' insides and their display cars.
local INTERIOR_GAP = 2500
local INTERIOR_COLUMNS = 6 -- insides sit on a grid (6 per row), so coordinates stay moderate
local FADE_TIME = 0.35 -- seconds of black screen before a teleport
local SPAWN_DELAY = 0.25 -- let the normal spawn finish before moving a new character home
local STORY = 14 -- studs per floor outside

-- Look 3.0 colours (see the header): real whites, dark glass, brass. Neon colours only glow at night.
local DARK = Color3.fromRGB(26, 28, 32) -- sign boards and screens
local WHITE = Color3.fromRGB(236, 234, 228) -- painted trim: a real white, not a glowing one
local GOLD = Color3.fromRGB(255, 214, 10) -- sign small print (HouseClient uses the same)
local BRASS = Color3.fromRGB(176, 140, 72) -- door knobs
local WARM = Color3.fromRGB(255, 214, 170) -- lamplight
local GLASS = Color3.fromRGB(52, 62, 70) -- dark tinted glass
local ROOM_GLOW = Color3.fromRGB(210, 156, 96) -- a lit room seen through a window after dark
local DARK_METAL = Color3.fromRGB(44, 44, 48) -- frames, handrails, bollards
local TRIM_DAY = Color3.fromRGB(58, 60, 66) -- an unlit neon tube by day (SkyClient's day colour)
local LAMP_DAY = Color3.fromRGB(226, 226, 220) -- an unlit lamp by day (SkyClient's day colour)
local FONT = Enum.Font.Oswald -- names and headlines
local SMALL_FONT = Enum.Font.GothamBold -- small print

local notify, houseCard, houseResult, houseFade
local homesFolder, interiorFolder
-- [player] = { model, slot, homeId, show, spawn, bays, cars, shown, signSub, ... }: show = a tour's show
-- copy (see buildInterior for the rest)
local interiors = {}
local slots = {} -- [slot] = player
local inside = {} -- [player] = true while in their interior (their own home, or a tour)
local busy = {} -- [player] = true during a door transition
local spawned = {} -- [player] = { char, t, done }: the home spawn for the current character

-- Parts ---------------------------------------------------------------------------------------------

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
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- One part between two corners (x0..x1, y0..y1, z0..z1) of a frame's local space.
local function box(parent, name, frame, x0, x1, y0, y1, z0, z1, color, material, props)
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	local cf = frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return newPart(parent, name, size, cf, color, material, props)
end

-- Small details: no collisions, no queries (a car spawn check never trips on them), no shadow.
local DETAIL = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
-- Looks-only parts big enough to cast a shadow (awnings, roof units, the tile roofs on flat slabs).
local SHADE = { CanCollide = false, CanQuery = false, CanTouch = false }
-- A small ball with no collisions (flowers, the neon flamingo).
local BALL = { Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

-- Night-only neon (Look 3.0): dark metal by day; every client's SkyClient turns a part tagged
-- "NightNeon" into Neon in its NeonColor after dark (and switches any Light inside it on).
local function nightNeon(p, color)
	p.Material = Enum.Material.Metal
	p.Color = TRIM_DAY
	p:SetAttribute("NeonColor", color)
	CollectionService:AddTag(p, "NightNeon")
	return p
end

-- A lamp (tag "NightLamp"): a pale shade by day, lit in its LampColor after dark (SkyClient).
local function nightLamp(p, color)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = LAMP_DAY
	p:SetAttribute("LampColor", color)
	CollectionService:AddTag(p, "NightLamp")
	return p
end

-- A thin neon strip: no collisions, no shadow, and it only glows (in `color`) after dark.
local function neon(parent, frame, x0, x1, y0, y1, z0, z1, color)
	return nightNeon(box(parent, "Neon", frame, x0, x1, y0, y1, z0, z1, TRIM_DAY, Enum.Material.Metal, DETAIL), color)
end

-- A wedge filling the same corners as box(): a WedgePart is tall at its back (+Z) and slopes down to
-- its front, so by default it slopes down toward the street (-Z); `away` turns it to slope down away
-- from the street (tall side toward it). `props` as for box().
local function wedge(parent, name, frame, x0, x1, y0, y1, z0, z1, color, material, away, props)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	local cf = frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	w.CFrame = away and cf * CFrame.Angles(0, math.pi, 0) or cf
	w.Color = color
	w.Material = material or Enum.Material.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		w[k] = v
	end
	w.Parent = parent
	return w
end

-- A pitched roof over x0..x1, z0..z1: a painted wooden eave slab at height y, then two clay-tile
-- wedges rising `rise` studs to a ridge running along X halfway between the front and the back.
local function gable(parent, frame, x0, x1, y, z0, z1, rise, color, eaveColor)
	local zm = (z0 + z1) / 2
	box(parent, "Eave", frame, x0, x1, y, y + 0.6, z0, z1, eaveColor, Enum.Material.WoodPlanks)
	wedge(parent, "RoofSlope", frame, x0, x1, y + 0.6, y + 0.6 + rise, z0, zm, color, Enum.Material.ClayRoofTiles) -- faces the street
	wedge(parent, "RoofSlope", frame, x0, x1, y + 0.6, y + 0.6 + rise, zm, z1, color, Enum.Material.ClayRoofTiles, true) -- faces the back
end

-- A low clay-tile roof standing on a flat roof slab (the Classic houses): looks only, so it never
-- collides and the slab under it stays what you stand on.
local function tileRoof(parent, frame, x0, x1, y, z0, z1, rise, color)
	local zm = (z0 + z1) / 2
	wedge(parent, "RoofSlope", frame, x0, x1, y, y + rise, z0, zm, color, Enum.Material.ClayRoofTiles, nil, SHADE) -- faces the street
	wedge(parent, "RoofSlope", frame, x0, x1, y, y + rise, zm, z1, color, Enum.Material.ClayRoofTiles, true, SHADE) -- faces the back
end

-- A point light. Inside a NightNeon / NightLamp part it starts off: SkyClient switches it on after dark.
local function light(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Enabled = not (CollectionService:HasTag(part, "NightNeon") or CollectionService:HasTag(part, "NightLamp"))
	l.Parent = part
	return l
end

-- Which windows show a lit room after dark: a fixed, irregular pattern (6 in every 11).
local function litAt(n)
	return (n * 7) % 11 < 6
end

-- A window: dark tinted glass, the same size and place as ever (its outside face looks toward -Z on a
-- front wall, -X on the left side). A `lit` one is a little clear, with a room panel inside the glass:
-- dark by day, warm lamplight after dark (NightNeon, in `glow` or ROOM_GLOW).
local function window(parent, frame, x0, x1, y0, y1, z0, z1, lit, glow)
	local glass = box(parent, "Window", frame, x0, x1, y0, y1, z0, z1, GLASS, Enum.Material.Glass,
		{ Reflectance = 0.1, Transparency = lit and 0.45 or 0 })
	if lit then
		local ax0, ax1 = math.min(x0, x1), math.max(x0, x1)
		local az0, az1 = math.min(z0, z1), math.max(z0, z1)
		local ay0, ay1 = math.min(y0, y1) + 0.06, math.max(y0, y1) - 0.06
		-- The panel fills the back of the glass, just inside its edges.
		if az1 - az0 <= ax1 - ax0 then -- on a front wall
			ax0, ax1, az0, az1 = ax0 + 0.06, ax1 - 0.06, az0 + (az1 - az0) * 0.4, az1 - 0.02
		else -- on the left side
			az0, az1, ax0, ax1 = az0 + 0.06, az1 - 0.06, ax0 + (ax1 - ax0) * 0.4, ax1 - 0.02
		end
		nightNeon(box(parent, "WindowLight", frame, ax0, ax1, ay0, ay1, az0, az1, TRIM_DAY, Enum.Material.Metal, DETAIL),
			glow or ROOM_GLOW)
	end
	return glass
end

-- Sign text on one face of a part (LightInfluence 0: crisp by day, glowing at night): the title in
-- Oswald, the (optional) sub label in small print. Returns the title and the sub label.
local function signGui(part, face, title, sub, titleColor, subColor)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.04, sub and 0.06 or 0.1)
	t.Size = UDim2.fromScale(0.92, sub and 0.52 or 0.8)
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = titleColor or WHITE
	t.Text = title
	t.Parent = gui
	local s
	if sub then
		s = Instance.new("TextLabel")
		s.Name = "Sub"
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromScale(0.04, 0.6)
		s.Size = UDim2.fromScale(0.92, 0.34)
		s.Font = SMALL_FONT
		s.TextScaled = true
		s.TextColor3 = subColor or GOLD
		s.Text = sub
		s.Parent = gui
	end
	gui.Parent = part
	return t, s
end

local function makePrompt(parent, name, action, object)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function money(n)
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return "$" .. s
end

local BARK = Color3.fromRGB(128, 110, 88)
local FROND = Color3.fromRGB(64, 108, 58)

-- A palm tree standing at (x, z) of a lot, turned `yaw`. Its trunk part (PalmTrunk) is the palm's
-- collision either way. With the city art's palm mesh (ServerStorage.ArtAssets.PalmTree) the trunk is
-- an invisible post and the mesh is the look (kept under 14 studs across, so the minimap never takes
-- it for a building); without it, six drooping fronds and two coconuts on the trunk.
local function palm(parent, frame, x, z, height, yaw)
	local base = frame * CFrame.new(x, 0.2, z)
	-- Cylinders run along X: turn them upright.
	local trunk = newPart(parent, "PalmTrunk", Vector3.new(height, 1.6, 1.6), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		BARK, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("PalmTree")
	if template and template:IsA("BasePart") then
		trunk.Transparency = 1
		local mesh = template:Clone()
		mesh.Name = "PalmTree"
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = true
		mesh.Size = template.Size * math.min(height / 22, 13.5 / math.max(template.Size.X, template.Size.Z))
		mesh.CFrame = base * CFrame.new(0, mesh.Size.Y / 2, 0) * CFrame.Angles(0, yaw, 0)
		mesh.Parent = parent
		return
	end
	local top = base * CFrame.new(0, height, 0)
	for i = 0, 5 do
		newPart(parent, "PalmLeaf", Vector3.new(2.4, 0.3, 9),
			top * CFrame.Angles(0, yaw + math.rad(i * 60 + 15), 0) * CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -4.2),
			FROND, Enum.Material.Grass, DETAIL)
	end
	for _, a in ipairs({ 40, 200 }) do
		newPart(parent, "Coconut", Vector3.new(1, 1, 1), top * CFrame.Angles(0, math.rad(a), 0) * CFrame.new(0, -0.7, -0.9),
			Color3.fromRGB(92, 66, 40), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
end

-- A potted plant inside: a terracotta pot and a leafy ball.
local function plant(parent, frame, x, z)
	newPart(parent, "Pot", Vector3.new(2.6, 2.4, 2.4), frame * CFrame.new(x, 1.3, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(170, 100, 70), Enum.Material.Concrete, { Shape = Enum.PartType.Cylinder })
	newPart(parent, "Leaves", Vector3.new(4.2, 4.2, 4.2), frame * CFrame.new(x, 4.4, z), Color3.fromRGB(66, 112, 60),
		Enum.Material.Grass, { Shape = Enum.PartType.Ball })
end

-- Players --------------------------------------------------------------------------------------------

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function alive(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function ownedHome(player)
	local data = DataService.Get(player)
	local id = data and data.home
	return id and Housing.ById[id] or nil
end

local function nearDoor(player, home)
	local root = rootOf(player)
	return root ~= nil and (root.Position - Housing.DoorPosition(home)).Magnitude <= Housing.DoorRange
end

-- On a tour, near the show home's FOR SALE stand (the same reach as a front door).
local function nearSale(player, rec)
	local root = rootOf(player)
	return root ~= nil and rec.saleAt ~= nil and (root.Position - rec.saleAt).Magnitude <= Housing.DoorRange
end

-- In or out. `tourId` (a home id) while it's a tour's show home: attribute Touring, set before InHome
-- so a client reading InHome already knows it's a tour. Going out clears both.
local function setInside(player, on, tourId)
	inside[player] = on and true or nil
	player:SetAttribute("Touring", on and tourId or nil)
	player:SetAttribute("InHome", on and true or nil)
end

local function fade(player, phase)
	if player.Parent == Players then
		houseFade:FireClient(player, phase)
	end
end

-- Ask the player's device to load the area first (StreamingEnabled), for up to a few seconds.
local function stream(player, position)
	pcall(function()
		player:RequestStreamAroundAsync(position, 3)
	end)
end

-- Move a living character (out of any seat first, so a car never comes along).
local function moveTo(player, cf)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return false
	end
	local seat = hum.SeatPart
	if seat then
		local sw = seat:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
		hum.Sit = false
	end
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

local onDoor, leave, drive, onSale -- defined below (the builders hook prompts to them)

-- Outside ---------------------------------------------------------------------------------------------

local STEEL = Color3.fromRGB(58, 56, 66) -- dark steel (the loft)
local TEAL = Color3.fromRGB(52, 112, 116) -- Bahama shutters and the front door: the ranch's one accent
local WALNUT = Color3.fromRGB(92, 64, 44) -- wooden front doors
local LAWN = Color3.fromRGB(86, 124, 62)
local HEDGE = Color3.fromRGB(62, 104, 58)
local LEAF = Color3.fromRGB(70, 112, 60) -- bushes
local CONCRETE = Color3.fromRGB(178, 174, 166) -- driveways, planters, edging
local PAVING = Color3.fromRGB(198, 190, 176) -- the front path
local WARM_WHITE = Color3.fromRGB(238, 232, 222)
local ROOF_TILE = Color3.fromRGB(176, 92, 62) -- clay roof tiles
local AWNING = Color3.fromRGB(36, 58, 88) -- the bungalow's fabric window awnings
local RAIL_GLASS = Color3.fromRGB(150, 170, 176) -- glass balustrades
local RAIL_PROPS = { Transparency = 0.6, Reflectance = 0.1 }
local POOL_LIGHT = Color3.fromRGB(60, 200, 255)

-- Config.Housing's wall colours are bright pastels: outside they become stucco with a hint of that
-- colour (Look 3.0). The loft's brick stays brick, a little weathered.
local function stucco(c)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s * 0.35, math.min(v, 0.88)):Lerp(WARM_WHITE, 0.25)
end

local function wallColor(home, style)
	if style == "Loft" then
		return home.Wall:Lerp(Color3.fromRGB(140, 82, 64), 0.5)
	end
	return stucco(home.Wall)
end

-- A clay-tile colour near Config.Housing's Roof (when it gives one).
local function tileColor(home)
	return home.Roof and home.Roof:Lerp(ROOF_TILE, 0.5) or ROOF_TILE
end

-- What each Style (Config.Housing) changes on the parts every lot shares; the house itself comes from
-- that style's builder in `bodies` below. Classic is the original layout (bungalow, penthouse, villa).
--   Ground/GroundMat: the lawn. WallMat: the house and garage walls. Post/PostMat: door posts, sign
--   posts. Door/DoorMat: the front door. Frame/FrameMat: the door casings round the front door and the
--   garage door. GarageDoor/GarageDoorMat/Slat: the sectional garage door. Awning: a canopy
--   (Canopy/CanopyMat) on two posts over the front door (the ranch has its porch, the mansion its
--   overhanging upper floor). Gable: a pitched garage roof. Step: the floor height under the doormat
--   (0.3 = the path; the ranch's porch deck is higher).
local LOOKS = {
	Classic = { Ground = LAWN, GroundMat = Enum.Material.Grass, WallMat = Enum.Material.Plaster, Post = WHITE,
		PostMat = Enum.Material.Concrete, Door = WALNUT, DoorMat = Enum.Material.WoodPlanks, Frame = WHITE,
		FrameMat = Enum.Material.Concrete, GarageDoor = Color3.fromRGB(226, 224, 218), GarageDoorMat = Enum.Material.Metal,
		Slat = Color3.fromRGB(196, 194, 188), Awning = true, Canopy = WHITE, CanopyMat = Enum.Material.Concrete },
	Loft = { Ground = Color3.fromRGB(150, 148, 142), GroundMat = Enum.Material.Concrete, WallMat = Enum.Material.Brick,
		Post = STEEL, PostMat = Enum.Material.Metal, Door = STEEL, DoorMat = Enum.Material.Metal, Frame = STEEL,
		FrameMat = Enum.Material.Metal, GarageDoor = Color3.fromRGB(112, 114, 118), GarageDoorMat = Enum.Material.Metal,
		Slat = Color3.fromRGB(84, 86, 92), Awning = true, Canopy = STEEL, CanopyMat = Enum.Material.Metal },
	Ranch = { Ground = LAWN, GroundMat = Enum.Material.Grass, WallMat = Enum.Material.WoodPlanks, Post = WHITE,
		PostMat = Enum.Material.WoodPlanks, Door = TEAL, DoorMat = Enum.Material.WoodPlanks, Frame = WHITE,
		FrameMat = Enum.Material.WoodPlanks, GarageDoor = Color3.fromRGB(234, 230, 220), GarageDoorMat = Enum.Material.WoodPlanks,
		Slat = Color3.fromRGB(204, 198, 186), Gable = true, Step = 0.6 },
	Mansion = { Ground = LAWN, GroundMat = Enum.Material.Grass, WallMat = Enum.Material.Plaster, Post = WHITE,
		PostMat = Enum.Material.Concrete, Door = Color3.fromRGB(74, 54, 40), DoorMat = Enum.Material.WoodPlanks,
		Frame = DARK_METAL, FrameMat = Enum.Material.Metal, GarageDoor = Color3.fromRGB(66, 66, 70),
		GarageDoorMat = Enum.Material.Metal, Slat = Color3.fromRGB(90, 90, 96) },
}

-- House builders by Style: the block with its roof, windows and the style's own details, called as
-- (model, frame, home, H = wall height, GH = garage height, wall = the wall colour). Everything around
-- the house (door, garage, driveway, sign, pool, palms) is shared: buildExterior.
local bodies = {}

-- A stucco house or tower (the inside is a private copy far away): a concrete plinth, white bands
-- between the floors, a flat roof slab with a neon roofline (after dark), dark windows on white sills
-- on every floor (some lit after dark), glass balconies upstairs. Houses of one or two storeys wear a
-- low clay-tile roof (the bungalow fabric awnings over its front windows too); towers (3+ storeys) keep
-- the flat roof with a neon crown, two roof units and the building's name on a sign.
function bodies.Classic(model, frame, home, H, _, wall)
	box(model, "House", frame, -52, 12, 0.2, H, -10, 28, wall, Enum.Material.Plaster)
	box(model, "BaseBand", frame, -52.3, 12.3, 0.2, 1.6, -10.3, 28.3, wall:Lerp(Color3.fromRGB(110, 106, 100), 0.45), Enum.Material.Concrete)
	for s = 1, home.Stories - 1 do
		box(model, "FloorBand", frame, -52.3, 12.3, s * STORY - 0.3, s * STORY + 0.5, -10.3, 28.3, WHITE, Enum.Material.Concrete)
	end
	box(model, "Roof", frame, -54, 14, H, H + 1, -12, 30, WHITE, Enum.Material.Concrete)
	neon(model, frame, -54, 14, H + 0.2, H + 0.8, -12.4, -12, home.Trim)
	neon(model, frame, -54.4, -54, H + 0.2, H + 0.8, -12.4, 30, home.Trim)
	neon(model, frame, 14, 14.4, H + 0.2, H + 0.8, -12.4, 30, home.Trim)
	if home.Stories <= 2 then
		tileRoof(model, frame, -54, 14, H + 1, -12, 30, home.Stories + 6, tileColor(home))
	end

	-- Windows on every floor (front and left side); upper floors get a balcony.
	local n = 0
	for s = 0, home.Stories - 1 do
		local y0 = s * STORY + 4.2
		local spans = { { -48, -40 }, { -36, -28 }, { -8, 0 }, { 3, 10 } }
		if s > 0 then
			table.insert(spans, { -22, -14 }) -- above the front door
		end
		for _, span in ipairs(spans) do
			n += 1
			window(model, frame, span[1], span[2], y0, y0 + 6, -10.4, -10, litAt(n))
			box(model, "Sill", frame, span[1] - 0.4, span[2] + 0.4, y0 - 0.5, y0, -10.8, -10, WHITE, Enum.Material.Concrete)
			if home.Stories == 1 then
				-- A fabric awning over each of the bungalow's front windows (looks only).
				wedge(model, "WindowAwning", frame, span[1] - 0.5, span[2] + 0.5, y0 + 6.3, y0 + 7.9, -12.8, -10, AWNING,
					Enum.Material.Fabric, nil, SHADE)
			end
		end
		for _, span in ipairs({ { -4, 4 }, { 10, 18 } }) do
			n += 1
			window(model, frame, -52.4, -52, y0, y0 + 6, span[1], span[2], litAt(n))
		end
		if s > 0 then
			local y = s * STORY
			box(model, "Balcony", frame, -49, 11, y, y + 0.6, -14, -10.3, WHITE, Enum.Material.Concrete)
			box(model, "Rail", frame, -49, 11, y + 0.6, y + 3.4, -14.3, -14, RAIL_GLASS, Enum.Material.Glass, RAIL_PROPS)
			box(model, "Handrail", frame, -49, 11, y + 3.4, y + 3.65, -14.4, -13.9, DARK_METAL, Enum.Material.Metal, DETAIL)
			neon(model, frame, -49, 11, y - 0.25, y, -14.1, -13.7, home.Trim)
		end
	end

	-- Towers: a neon crown (after dark), two roof units, and the building's name on a dark sign standing
	-- on the roof (white letters, a neon line along its top after dark).
	if home.Stories >= 3 then
		neon(model, frame, -54, 14, H + 1, H + 1.6, -12, -11.4, home.Trim)
		neon(model, frame, -54, 14, H + 1, H + 1.6, 29.4, 30, home.Trim)
		neon(model, frame, -54, -53.4, H + 1, H + 1.6, -11.4, 29.4, home.Trim) -- the sides run between the front and back
		neon(model, frame, 13.4, 14, H + 1, H + 1.6, -11.4, 29.4, home.Trim)
		for _, x in ipairs({ -32, -18 }) do
			box(model, "RoofAC", frame, x - 2.5, x + 2.5, H + 1, H + 3.4, 14, 19, Color3.fromRGB(158, 162, 168), Enum.Material.Metal, SHADE)
		end
		for _, x in ipairs({ -40, 0 }) do
			box(model, "SignLeg", frame, x - 0.3, x + 0.3, H + 1, H + 1.6, -8.9, -8.5, DARK_METAL, Enum.Material.Metal, DETAIL)
		end
		local roofSign = box(model, "RoofSign", frame, -44, 4, H + 1.6, H + 10, -9, -8.4, DARK, Enum.Material.Metal)
		neon(model, frame, -44, 4, H + 10, H + 10.3, -9.1, -8.4, home.Trim)
		signGui(roofSign, Enum.NormalId.Front, string.upper(home.Name), nil, WHITE)
	end
end

-- A converted dock warehouse: brick on a steel plinth, a rusty beam between the floors, big factory
-- windows (some lit after dark), a fire escape, a sawtooth roof with a wooden water tank (its steel
-- hoop is a neon ring after dark), and the name on a dark sign over the loading door (the garage),
-- outlined in neon after dark.
function bodies.Loft(model, frame, home, H, GH, wall)
	local steel = home.Roof or STEEL
	box(model, "House", frame, -52, 12, 0.2, H, -10, 28, wall, Enum.Material.Brick)
	box(model, "BaseBand", frame, -52.3, 12.3, 0.2, 1.6, -10.3, 28.3, steel, Enum.Material.Metal)
	local rust = home.Accent:Lerp(Color3.fromRGB(120, 78, 56), 0.4)
	for s = 1, home.Stories - 1 do
		box(model, "FloorBand", frame, -52.3, 12.3, s * STORY - 0.3, s * STORY + 0.5, -10.3, 28.3, rust, Enum.Material.CorrodedMetal)
	end
	box(model, "Parapet", frame, -52.6, 12.6, H, H + 1.2, -10.6, 28.6, steel, Enum.Material.Metal)
	neon(model, frame, -52.6, 12.6, H + 0.3, H + 0.7, -10.9, -10.6, home.Trim)

	-- Factory windows: glass split into six panes by steel bars, on a steel sill.
	local n = 0
	local function factoryWindow(x0, x1, y0, y1)
		n += 1
		window(model, frame, x0, x1, y0, y1, -10.4, -10, litAt(n))
		box(model, "Sill", frame, x0 - 0.4, x1 + 0.4, y0 - 0.6, y0, -10.8, -10, steel, Enum.Material.Metal)
		box(model, "Mullion", frame, x0, x1, (y0 + y1) / 2 - 0.2, (y0 + y1) / 2 + 0.2, -10.6, -10.4, steel, Enum.Material.Metal)
		for i = 1, 2 do
			local x = x0 + (x1 - x0) * i / 3
			box(model, "Mullion", frame, x - 0.2, x + 0.2, y0, y1, -10.6, -10.4, steel, Enum.Material.Metal)
		end
	end
	for s = 0, home.Stories - 1 do
		local y0 = s * STORY + 3.5
		local spans = { { -49, -38 }, { -35, -25 }, { -10, 9 } }
		if s > 0 then
			table.insert(spans, { -22, -14 }) -- above the front door
		end
		for _, span in ipairs(spans) do
			factoryWindow(span[1], span[2], y0, y0 + 8)
		end
		-- One big window on the left side.
		n += 1
		window(model, frame, -52.4, -52, y0, y0 + 8, 0, 14, litAt(n))
		box(model, "Mullion", frame, -52.6, -52.4, y0, y0 + 8, 6.8, 7.2, steel, Enum.Material.Metal)
	end

	-- Fire escape on the left side: a landing at the upper floor and a stair down to the yard.
	if home.Stories >= 2 then
		box(model, "FireEscape", frame, -56, -52, STORY - 0.4, STORY, -4, 16, steel, Enum.Material.DiamondPlate)
		box(model, "Rail", frame, -56, -55.6, STORY, STORY + 3.2, -4, 16, steel, Enum.Material.Metal)
		local bottom, top = Vector3.new(-54, 0.4, 30), Vector3.new(-54, STORY - 0.2, 16)
		newPart(model, "Stair", Vector3.new(3, 0.4, (top - bottom).Magnitude), frame * CFrame.lookAt((bottom + top) / 2, top), steel,
			Enum.Material.DiamondPlate)
	end

	-- Sawtooth roof: three steel teeth, their dark glass faces toward the street.
	for _, z in ipairs({ -8, 3, 14 }) do
		wedge(model, "Sawtooth", frame, -38, 10, H + 1.2, H + 7.2, z, z + 11, steel, Enum.Material.Metal, true)
		box(model, "RoofGlass", frame, -37, 9, H + 1.6, H + 6.6, z - 0.3, z, GLASS, Enum.Material.Glass, { Reflectance = 0.1 })
	end

	-- A wooden water tank on steel legs, with a steel hoop that is a neon ring after dark.
	local tx, ty, tz = -46, H + 1.2, 18
	for _, o in ipairs({ { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }) do
		box(model, "TankLeg", frame, tx + o[1] - 0.4, tx + o[1] + 0.4, ty, ty + 8, tz + o[2] - 0.4, tz + o[2] + 0.4, steel, Enum.Material.Metal)
	end
	-- Cylinders run along X: turn them upright.
	local tank = frame * CFrame.new(tx, ty + 12, tz) * CFrame.Angles(0, 0, math.rad(90))
	newPart(model, "Tank", Vector3.new(8, 9, 9), tank, Color3.fromRGB(120, 96, 76), Enum.Material.WoodPlanks, { Shape = Enum.PartType.Cylinder })
	newPart(model, "TankLid", Vector3.new(1, 10, 10), frame * CFrame.new(tx, ty + 16.5, tz) * CFrame.Angles(0, 0, math.rad(90)), steel,
		Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	nightNeon(newPart(model, "Neon", Vector3.new(0.6, 9.3, 9.3), tank, TRIM_DAY, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }), home.Trim)

	-- The loft's name on a dark sign over the loading door, standing on the garage roof: white letters,
	-- neon lines above and below after dark.
	box(model, "SignFrame", frame, 14.6, 47.4, GH + 0.8, GH + 8, -8.8, -8.2, steel, Enum.Material.Metal)
	local dockSign = box(model, "DockSign", frame, 15.2, 46.8, GH + 1.4, GH + 7.4, -9, -8.8, DARK, Enum.Material.Metal)
	signGui(dockSign, Enum.NormalId.Front, string.upper(home.Name), nil, WHITE)
	neon(model, frame, 15.2, 46.8, GH + 7.4, GH + 7.8, -9.1, -8.8, home.Trim)
	neon(model, frame, 15.2, 46.8, GH + 1, GH + 1.4, -9.1, -8.8, home.Trim)

	-- Dockside clutter by the loading door: two crates and an oil drum.
	box(model, "Crate", frame, 50.6, 54.6, 0.2, 4.2, -7, -3, Color3.fromRGB(156, 120, 82), Enum.Material.WoodPlanks)
	box(model, "Crate", frame, 51, 54, 0.2, 3.2, -2, 1, Color3.fromRGB(136, 104, 72), Enum.Material.WoodPlanks)
	newPart(model, "Drum", Vector3.new(3.4, 2.6, 2.6), frame * CFrame.new(52.6, 1.9, 4) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(40, 90, 130), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
end

-- A Florida ranch house: one long storey in pale wooden siding on a concrete foundation, under a
-- clay-tile gable roof with a brick chimney, Bahama-shuttered windows (some lit after dark), and a
-- wide plank porch across the front with white posts and rails and two white rocking chairs.
function bodies.Ranch(model, frame, home, H, _, wall)
	local roof = tileColor(home)
	box(model, "House", frame, -52, 12, 0.2, H, -10, 28, wall, Enum.Material.WoodPlanks)
	box(model, "BaseBand", frame, -52.3, 12.3, 0.2, 1.6, -10.3, 28.3, Color3.fromRGB(168, 164, 156), Enum.Material.Concrete)
	gable(model, frame, -54, 13, H, -12, 30, 8, roof, WHITE)
	neon(model, frame, -54, 13, H + 0.1, H + 0.5, -12.4, -12, home.Trim)
	box(model, "Chimney", frame, -44, -40, H, H + 12, 16, 20, Color3.fromRGB(150, 86, 66), Enum.Material.Brick)
	box(model, "ChimneyCap", frame, -44.4, -39.6, H + 12, H + 12.5, 15.6, 20.4, Color3.fromRGB(150, 146, 140), Enum.Material.Concrete, DETAIL)

	-- Front windows with shutters; two windows on the left side.
	local n = 0
	for _, span in ipairs({ { -48, -41 }, { -36, -29 }, { -9, -3 }, { 3, 9 } }) do
		n += 1
		window(model, frame, span[1], span[2], 4.2, 10.2, -10.4, -10, litAt(n))
		box(model, "Sill", frame, span[1] - 0.4, span[2] + 0.4, 3.7, 4.2, -10.8, -10, WHITE, Enum.Material.WoodPlanks)
		box(model, "Shutter", frame, span[1] - 2, span[1] - 0.2, 4.2, 10.2, -10.5, -10, TEAL, Enum.Material.WoodPlanks)
		box(model, "Shutter", frame, span[2] + 0.2, span[2] + 2, 4.2, 10.2, -10.5, -10, TEAL, Enum.Material.WoodPlanks)
	end
	for _, span in ipairs({ { -4, 4 }, { 10, 18 } }) do
		n += 1
		window(model, frame, -52.4, -52, 4.2, 10.2, span[1], span[2], litAt(n))
	end

	-- The porch: a plank deck a step up, white posts and rails (open at the path), its own tiled roof.
	box(model, "Porch", frame, -53, 12, 0.2, 0.6, -20, -10, Color3.fromRGB(150, 112, 78), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -52, -38, -25, -11, 0, 11 }) do
		box(model, "PorchPost", frame, x - 0.4, x + 0.4, 0.6, 12.2, -19.6, -18.8, WHITE, Enum.Material.WoodPlanks)
	end
	box(model, "PorchRail", frame, -52, -25, 3, 3.5, -19.5, -18.9, WHITE, Enum.Material.WoodPlanks)
	box(model, "PorchRail", frame, -11, 11, 3, 3.5, -19.5, -18.9, WHITE, Enum.Material.WoodPlanks)
	wedge(model, "PorchRoof", frame, -53.5, 12.5, 12.2, 13.8, -21, -10, roof, Enum.Material.ClayRoofTiles)
	neon(model, frame, -53.5, 12.5, 11.8, 12.2, -21, -20.6, home.Trim)
	for _, x in ipairs({ -34, -29 }) do
		box(model, "Chair", frame, x - 1.3, x + 1.3, 0.6, 2.2, -16.6, -14, WHITE, Enum.Material.WoodPlanks)
		box(model, "ChairBack", frame, x - 1.3, x + 1.3, 0.6, 5.2, -14, -13.4, WHITE, Enum.Material.WoodPlanks)
	end

	-- Low hedges along the front of the lot, open for the path.
	box(model, "Hedge", frame, -55, -25, 0.2, 2.6, -35, -33.4, HEDGE, Enum.Material.Grass)
	box(model, "Hedge", frame, -11, 13, 0.2, 2.6, -35, -33.4, HEDGE, Enum.Material.Grass)
end

-- The beach mansion: three white stucco volumes stacked off-centre (the upper floor hangs out over the
-- front door, the top floor steps back behind a roof terrace with two planters), floor-to-ceiling glass
-- between white fins on every level (warm lit rooms after dark), neon strips on the edges and a neon
-- flamingo by the door (both dark metal by day, lit after dark), and the name in white on the roof.
function bodies.Mansion(model, frame, home, H, _, wall)
	local roof = home.Roof and stucco(home.Roof) or WHITE
	local S = STORY
	local top = math.max(H, 3 * STORY) - 2 -- top of the third floor
	box(model, "House", frame, -52, 12, 0.2, S, -10, 28, wall, Enum.Material.Plaster)
	box(model, "Upper", frame, -54, 12, S, 2 * S, -16, 26, wall, Enum.Material.Plaster)
	box(model, "Terrace", frame, -55, 13, 2 * S, 2 * S + 0.8, -17, 27, roof, Enum.Material.Concrete)
	box(model, "Top", frame, -44, -4, 2 * S + 0.8, top, -8, 20, wall, Enum.Material.Plaster)
	box(model, "Roof", frame, -46, -2, top, top + 0.8, -10, 22, roof, Enum.Material.Concrete)
	neon(model, frame, -54, 12, S, S + 0.4, -16.4, -16, home.Trim) -- under the overhang
	neon(model, frame, -55, 13, 2 * S + 0.2, 2 * S + 0.6, -17.4, -17, home.Trim) -- the terrace edge
	neon(model, frame, -46, -2, top + 0.2, top + 0.6, -10.4, -10, home.Trim) -- the roofline
	box(model, "Rail", frame, -55, 13, 2 * S + 0.8, 2 * S + 3.6, -17, -16.6, RAIL_GLASS, Enum.Material.Glass, RAIL_PROPS)
	box(model, "Handrail", frame, -55, 13, 2 * S + 3.6, 2 * S + 3.85, -17.05, -16.55, DARK_METAL, Enum.Material.Metal, DETAIL)
	-- Concrete planters with clipped shrubs at the front corners of the terrace (looks only).
	for _, x in ipairs({ -51.5, 9.5 }) do
		box(model, "Planter", frame, x - 2, x + 2, 2 * S + 0.8, 2 * S + 2.4, -16.2, -12.2, CONCRETE, Enum.Material.Concrete, SHADE)
		newPart(model, "Bush", Vector3.new(3.4, 3.4, 3.4), frame * CFrame.new(x, 2 * S + 3.6, -14.2), LEAF, Enum.Material.Grass,
			{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CanTouch = false })
	end

	-- Floor-to-ceiling glass between white fins, on the front of each level (the fins stand on z). The
	-- big panes glow a little softer than house windows after dark.
	local glow = Color3.fromRGB(180, 132, 80)
	local function glassWall(x0, x1, y0, y1, z, fins)
		window(model, frame, x0, x1, y0 + 0.8, y1 - 1, z - 0.4, z, true, glow)
		for i = 0, fins - 1 do
			local x = x0 + (x1 - x0) * i / (fins - 1)
			box(model, "Fin", frame, x - 0.3, x + 0.3, y0, y1, z - 0.8, z, WHITE, Enum.Material.Concrete)
		end
	end
	glassWall(-40, -24, 0.2, S, -10, 3)
	glassWall(-12, 10, 0.2, S, -10, 3)
	glassWall(-53, 11, S, 2 * S, -16, 6)
	glassWall(-43, -5, 2 * S + 0.8, top, -8, 4)
	window(model, frame, -52.4, -52, 1, S - 1, -4, 22, false)
	window(model, frame, -54.4, -54, S + 1, 2 * S - 1, -12, 22, true, glow)
	window(model, frame, -44.4, -44, 2 * S + 1.6, top - 1, -4, 16, false)

	-- The name in white letters on the roof: letters only (the board itself is invisible).
	local roofSign = box(model, "RoofSign", frame, -40, -8, top + 1, top + 5.5, -9, -8.6, WHITE, Enum.Material.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	signGui(roofSign, Enum.NormalId.Front, string.upper(home.Name), nil, WHITE)

	-- A neon flamingo on the plain wall left of the glass: body, neck, head, beak and two legs. Dark
	-- metal by day; after dark it glows (the light in its body comes on with it).
	local body = nightNeon(newPart(model, "NeonFlamingo", Vector3.new(3.2, 3.2, 3.2), frame * CFrame.new(-45.5, 7.4, -10), TRIM_DAY,
		Enum.Material.Metal, BALL), home.Trim)
	light(body, home.Trim, 16, 1)
	nightNeon(newPart(model, "NeonFlamingo", Vector3.new(1.6, 1.6, 1.6), frame * CFrame.new(-48.2, 12.6, -10.1), TRIM_DAY,
		Enum.Material.Metal, BALL), home.Trim)
	for _, bar in ipairs({
		{ 0.5, 4, -47.2, 10.4, 25, home.Trim }, -- neck, leaning up to the head
		{ 1.6, 0.45, -49.5, 12.2, 20, GOLD }, -- beak
		{ 0.3, 5, -45.3, 3.4, 0, home.Trim }, -- the leg it stands on
		{ 0.3, 2.8, -44.4, 5, 40, home.Trim }, -- the tucked-up leg
	}) do
		nightNeon(newPart(model, "NeonFlamingo", Vector3.new(bar[1], bar[2], 0.3),
			frame * CFrame.new(bar[3], bar[4], -10.2) * CFrame.Angles(0, 0, math.rad(bar[5])), TRIM_DAY, Enum.Material.Metal, DETAIL), bar[6])
	end
end

-- The plain shell every home used to share (the Style bodies above): now only the fallback for a home
-- whose own build (HouseBuilder, Houses.<Style>) is missing or fails. Returns the front door part.
local function legacyExterior(home)
	local frame = Housing.Frame(home)
	local style = bodies[home.Style or ""] and home.Style or "Classic"
	local look = LOOKS[style]
	local H = home.Stories * STORY
	local GH = home.Stories >= 2 and 16 or 12 -- garage height (lower than a one-storey house)
	local wall = wallColor(home, style)
	local model = Instance.new("Model")
	model.Name = "Home_" .. home.Id
	model:SetAttribute("HomeId", home.Id)

	-- Ground: lawn (a concrete yard at the loft), a paved front path with concrete edging, and a
	-- concrete driveway with low edges and two expansion joints (the edging and joints are looks only).
	local lawn = box(model, "Lawn", frame, -55, 55, 0, 0.2, -35, 35, look.Ground, look.GroundMat)
	model.PrimaryPart = lawn
	box(model, "Path", frame, -22, -14, 0.2, 0.3, -35, -10, PAVING, Enum.Material.Pavement)
	for _, x in ipairs({ -22.3, -14 }) do
		box(model, "Edging", frame, x, x + 0.3, 0.2, 0.36, -35, -20.5, CONCRETE, Enum.Material.Concrete, DETAIL)
	end
	box(model, "Driveway", frame, 18, 48, 0.2, 0.3, -35, -8, CONCRETE, Enum.Material.Concrete)
	for _, x in ipairs({ 17.5, 48 }) do
		box(model, "Edging", frame, x, x + 0.5, 0.2, 0.4, -35, -8, Color3.fromRGB(196, 192, 184), Enum.Material.Concrete, DETAIL)
	end
	for _, z in ipairs({ -26, -17 }) do
		box(model, "Joint", frame, 18, 48, 0.3, 0.32, z - 0.1, z + 0.1, Color3.fromRGB(138, 134, 126), Enum.Material.Concrete, DETAIL)
	end

	-- The house itself, in its style.
	bodies[style](model, frame, home, H, GH, wall)

	-- Front door in a painted casing, with a narrow glass light and a brass knob, a canopy and a porch
	-- light (warm after dark). Its prompt handles buying and going in.
	local door = box(model, "FrontDoor", frame, -21, -15, 0.2, 10.2, -10.6, -10, look.Door, look.DoorMat)
	box(model, "DoorFrame", frame, -21.8, -21, 0.2, 11, -10.9, -10, look.Frame, look.FrameMat, DETAIL)
	box(model, "DoorFrame", frame, -15, -14.2, 0.2, 11, -10.9, -10, look.Frame, look.FrameMat, DETAIL)
	box(model, "DoorFrame", frame, -21, -15, 10.2, 11, -10.9, -10, look.Frame, look.FrameMat, DETAIL) -- between the posts, so no faces overlap
	box(model, "DoorGlass", frame, -19.7, -18.9, 2.4, 8.6, -10.7, -10.6, GLASS, Enum.Material.Glass,
		{ Reflectance = 0.1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	box(model, "Knob", frame, -16.4, -15.8, 4.8, 5.4, -10.9, -10.6, BRASS, Enum.Material.Metal)
	if look.Awning then
		box(model, "Awning", frame, -24, -12, 12, 12.6, -16, -10, look.Canopy, look.CanopyMat)
		box(model, "Post", frame, -23.6, -22.8, 0.2, 12, -15.8, -15, look.Post, look.PostMat)
		box(model, "Post", frame, -13.2, -12.4, 0.2, 12, -15.8, -15, look.Post, look.PostMat)
	end
	if style == "Mansion" or style == "Ranch" then
		-- The porch light hangs on a rod from the overhanging upper floor (the ranch: its porch roof).
		box(model, "LampRod", frame, -18.1, -17.9, 12, style == "Mansion" and STORY or 12.2, -13.1, -12.9, DARK_METAL,
			Enum.Material.Metal, DETAIL)
	end
	light(nightLamp(box(model, "PorchLight", frame, -18.6, -17.4, 11.3, 12, -13.6, -12.4, LAMP_DAY, Enum.Material.SmoothPlastic, DETAIL),
		WARM), WARM, 18, 1.2)
	local step = look.Step or 0.3 -- the floor in front of the door: the path, or the ranch's porch deck
	box(model, "Doormat", frame, -20.5, -15.5, step, step + 0.1, -13.5, -10.6, Color3.fromRGB(88, 72, 56), Enum.Material.Fabric)

	-- A concrete planter under the front windows: bushes with a few hibiscus flowers.
	box(model, "Planter", frame, -48, -28, 0.2, 1, -12.6, -10, CONCRETE, Enum.Material.Concrete)
	for i, x in ipairs({ -46, -42, -38, -34, -30 }) do
		newPart(model, "Bush", Vector3.new(2.4, 2.4, 2.4), frame * CFrame.new(x, 1.8, -11.3), LEAF,
			Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		newPart(model, "Flower", Vector3.new(0.8, 0.8, 0.8), frame * CFrame.new(x + 0.5, 3, -11.8),
			i % 2 == 0 and Color3.fromRGB(232, 190, 60) or Color3.fromRGB(196, 52, 64), Enum.Material.SmoothPlastic, BALL)
	end

	-- Garage beside the house, in the house's walls: a sectional door in a painted casing, a wall light
	-- either side of it (warm after dark) and a neon line along the roof edge (after dark).
	box(model, "Garage", frame, 12, 50, 0.2, GH, -8, 28, wall, look.WallMat)
	if look.Gable then
		gable(model, frame, 11, 51, GH, -9, 29, 6, tileColor(home), WHITE) -- pitched, like the house
	elseif style == "Loft" then
		box(model, "GarageRoof", frame, 11, 51, GH, GH + 0.8, -9, 29, home.Roof or STEEL, Enum.Material.Metal)
	else
		box(model, "GarageRoof", frame, 11, 51, GH, GH + 0.8, -9, 29, home.Roof and stucco(home.Roof) or WHITE, Enum.Material.Concrete)
	end
	neon(model, frame, 11, 51, GH + 0.1, GH + 0.6, -9.4, -9, home.Trim)
	local doorTop = GH - 3
	box(model, "GarageDoor", frame, 19, 45, 0.2, doorTop, -8.4, -8, look.GarageDoor, look.GarageDoorMat)
	for i = 1, 4 do
		local y = 0.2 + i * (doorTop - 0.2) / 5
		box(model, "Slat", frame, 19, 45, y - 0.12, y + 0.12, -8.6, -8.4, look.Slat, look.GarageDoorMat)
	end
	box(model, "DoorFrame", frame, 18.2, 19, 0.2, doorTop + 0.8, -8.8, -8, look.Frame, look.FrameMat, DETAIL)
	box(model, "DoorFrame", frame, 45, 45.8, 0.2, doorTop + 0.8, -8.8, -8, look.Frame, look.FrameMat, DETAIL)
	box(model, "DoorFrame", frame, 19, 45, doorTop, doorTop + 0.8, -8.8, -8, look.Frame, look.FrameMat, DETAIL) -- between the posts
	for _, x in ipairs({ 16, 48 }) do
		box(model, "LampBack", frame, x - 0.5, x + 0.5, doorTop - 1.8, doorTop + 0.4, -8.3, -8, DARK_METAL, Enum.Material.Metal, DETAIL)
		nightLamp(box(model, "WallLight", frame, x - 0.35, x + 0.35, doorTop - 1.6, doorTop + 0.2, -8.7, -8.3, LAMP_DAY,
			Enum.Material.SmoothPlastic, DETAIL), WARM)
	end

	-- Bollard lights at the end of the driveway (warm after dark).
	for _, x in ipairs({ 16, 50 }) do
		box(model, "Bollard", frame, x - 0.6, x + 0.6, 0.2, 3, -34.6, -33.4, DARK_METAL, Enum.Material.Metal, { CastShadow = false })
		light(nightLamp(box(model, "BollardLight", frame, x - 0.6, x + 0.6, 3, 3.5, -34.6, -33.4, LAMP_DAY, Enum.Material.SmoothPlastic,
			DETAIL), WARM), WARM, 12, 0.8)
	end

	-- The pool (villa, mansion): concrete coping, a tiled floor under clear water, a pool light along the
	-- far side (after dark), white loungers and a parasol.
	if home.Pool then
		local coping = Color3.fromRGB(218, 212, 202)
		box(model, "PoolRim", frame, -49, -27, 0.2, 1.4, -30, -29, coping, Enum.Material.Concrete)
		box(model, "PoolRim", frame, -49, -27, 0.2, 1.4, -16, -15, coping, Enum.Material.Concrete)
		box(model, "PoolRim", frame, -49, -48, 0.2, 1.4, -29, -16, coping, Enum.Material.Concrete)
		box(model, "PoolRim", frame, -28, -27, 0.2, 1.4, -29, -16, coping, Enum.Material.Concrete)
		box(model, "PoolFloor", frame, -48, -28, 0.2, 0.3, -29, -16, Color3.fromRGB(96, 168, 186), Enum.Material.Concrete)
		box(model, "PoolWater", frame, -48, -28, 0.3, 1.1, -29, -16, Color3.fromRGB(54, 150, 170), Enum.Material.Glass,
			{ Transparency = 0.3, Reflectance = 0.1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		neon(model, frame, -48, -28, 0.3, 0.45, -29, -28.6, POOL_LIGHT)
		for _, z in ipairs({ -28, -21 }) do
			box(model, "Lounger", frame, -54.5, -51.8, 0.2, 1.2, z, z + 6, Color3.fromRGB(232, 228, 218), Enum.Material.Fabric)
		end
		box(model, "UmbrellaPole", frame, -52.15, -51.85, 0.2, 7.2, -21.65, -21.35, WHITE, Enum.Material.Metal, DETAIL)
		-- Cylinders run along X: turn the canopy flat.
		newPart(model, "Umbrella", Vector3.new(0.4, 6, 6), frame * CFrame.new(-52, 7.3, -21.5) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(236, 232, 222), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CanTouch = false })
	end

	-- Sign by the street: the name and price on a dark board with a neon line along its top after dark
	-- (an owner's own client shows "YOUR HOME" instead of the price).
	box(model, "SignPost", frame, -9.4, -8.6, 0.2, 8, -32.4, -31.6, look.Post, look.PostMat)
	box(model, "SignPost", frame, 2.6, 3.4, 0.2, 8, -32.4, -31.6, look.Post, look.PostMat)
	local board = box(model, "HomeSign", frame, -10, 4, 3.4, 8.6, -32.3, -31.7, DARK, Enum.Material.Metal)
	board:SetAttribute("HomeId", home.Id)
	neon(model, frame, -10, 4, 8.6, 9, -32.3, -31.7, home.Trim)
	signGui(board, Enum.NormalId.Front, home.Name, "FOR SALE · " .. money(home.Price), WHITE, GOLD)

	-- Palm spots in the order they're used (Palms = how many): the first three are the original lots'.
	local palms = { { -51, -31, 18 }, { 10, -29, 16 }, { -52, 32, 20 }, { 53, -22, 18 }, { 53, 31, 20 } }
	for i = 1, math.min(home.Palms or 0, #palms) do
		palm(model, frame, palms[i][1], palms[i][2], palms[i][3], math.rad(i * 77))
	end

	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the whole house streams in at once
	end)
	model.Parent = homesFolder
	return door
end

-- The home on its lot: its own build (HouseBuilder draws Houses.<Style>), or the plain shell when that is
-- missing or fails. Either way its front door gets the HomeDoor prompt: everyone gets the buy text, an
-- owner's own client changes it to "Enter home" (HouseClient).
local function buildExterior(home)
	local door
	if HouseBuilder.Has(home) then
		local ok, out = pcall(HouseBuilder.Lot, home, homesFolder)
		if ok and out.door then
			door = out.door
		else
			warn("[HousingService] couldn't build " .. home.Id .. "'s own house, using the plain one: " .. tostring(out))
			local broken = homesFolder:FindFirstChild("Home_" .. home.Id)
			if broken then
				broken:Destroy()
			end
		end
	end
	door = door or legacyExterior(home)
	local prompt = makePrompt(door, "HomeDoor", "View / Buy " .. money(home.Price), home.Name)
	prompt:SetAttribute("HomeId", home.Id)
	prompt.Triggered:Connect(function(player)
		onDoor(player, home)
	end)
end

-- Inside ----------------------------------------------------------------------------------------------

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
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.05, 0.22)
	t.Size = UDim2.fromScale(0.9, 0.34)
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = "MIAMI COAST TV"
	t.Parent = bg
	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromScale(0.08, 0.6)
	s.Size = UDim2.fromScale(0.84, 0.16)
	s.Font = Enum.Font.GothamMedium
	s.TextScaled = true
	s.TextColor3 = Color3.new(1, 1, 1)
	s.Text = "Cartoons, races and car shows all day!"
	s.Parent = bg
	gui.Parent = part
end

-- A free-standing sign (a show home's FOR SALE stand and its garage sign): a dark board w x h whose
-- bottom is `lift` up, on two slim dark-metal posts with flat feet, and a neon line along its top in
-- `trim` (after dark). `cf` is the spot on the floor, its front (-Z) the way the board faces. The posts
-- and feet never collide; the board only when `solid` (one that carries a prompt is a plain part, like
-- the doors). Returns the board.
local function standSign(parent, cf, w, h, lift, title, sub, titleColor, trim, solid)
	for _, x in ipairs({ -w / 2 + 0.6, w / 2 - 0.6 }) do
		box(parent, "SignPost", cf, x - 0.15, x + 0.15, 0.2, lift + h - 0.2, 0.15, 0.45, DARK_METAL, Enum.Material.Metal, DETAIL)
		box(parent, "SignFoot", cf, x - 0.3, x + 0.3, 0, 0.2, -0.9, 1.5, DARK_METAL, Enum.Material.Metal, DETAIL)
	end
	local board = box(parent, "SignBoard", cf, -w / 2, w / 2, lift, lift + h, -0.15, 0.15, DARK, Enum.Material.Metal,
		not solid and SHADE or nil)
	neon(parent, cf, -w / 2, w / 2, lift + h, lift + h + 0.25, -0.15, 0.15, trim)
	signGui(board, Enum.NormalId.Front, title, sub, titleColor, WHITE)
	return board
end

-- Wheels resting on the floor: the chassis centre's height above the ground (CarBuilder's wheel layout).
local function carLift(def)
	return def.Size.Y / 2 - 0.6 + def.RestLength * 0.6 + def.WheelRadius
end

-- Where slot N's inside sits: along +X in rows of INTERIOR_COLUMNS, then the next row along +Z.
local function slotFrame(slot)
	local col = (slot - 1) % INTERIOR_COLUMNS
	local row = math.floor((slot - 1) / INTERIOR_COLUMNS)
	return CFrame.new(INTERIOR_ORIGIN + Vector3.new(col * INTERIOR_GAP, 0, row * INTERIOR_GAP))
end

-- The plain inside every home used to share: now only the fallback for a home whose own build is missing
-- or fails. `show`: a tour's show copy (see the header): the same rooms, with an empty garage, no
-- wardrobe prompt and a FOR SALE stand. moveIn turns one into the owner's inside.
local function legacyInterior(player, home, slot, show)
	local frame = slotFrame(slot)
	local model = Instance.new("Model")
	model.Name = "Home_" .. player.UserId
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("HomeId", home.Id)
	model:SetAttribute("Show", show or nil)
	-- Look 3.0 indoors: warm plaster with a hint of the home's colour, marble, walnut and fabric. The
	-- home's Theme colour is the one accent (sign letters, cushions, a stripe in the garage, neon art).
	local theme = home.Theme
	local wall = home.InsideWall:Lerp(Color3.fromRGB(232, 226, 214), 0.6)
	local grey = Color3.fromRGB(188, 186, 180) -- painted block in the garage
	local accent = theme:Lerp(Color3.fromRGB(120, 116, 110), 0.45) -- cushions, a hat box
	local wood = Color3.fromRGB(110, 80, 56) -- walnut furniture and the front door
	local oak = Color3.fromRGB(190, 160, 120) -- the wardrobe

	-- Garage size: parking bays in one row for up to 3 cars, two rows for more, 16 studs a bay. The
	-- garage runs x 6..gx: 49 wide (gx = 55) up to 3 bays a row, wider past that (8 cars: 4 a row, gx = 70).
	local n = home.GarageSlots
	local rows = n > 3 and 2 or 1
	local perRow = math.ceil(n / rows)
	local width = math.max(49, perRow * 16)
	local gx = 6 + width
	local mid = (gx - 55) / 2 -- keeps the roll-up door and the sign centred on a wider garage (0 normally)

	-- Shell. Living room x -45..5, garage x 6..gx, both z -30..30; floor at y 0, ceiling at 18.
	local floor = box(model, "Floor", frame, -46, 5.5, -1, 0, -31, 31, Color3.fromRGB(236, 232, 226), Enum.Material.Marble)
	model.PrimaryPart = floor
	box(model, "GarageFloor", frame, 5.5, gx + 1, -1, 0, -31, 31, Color3.fromRGB(120, 120, 118), Enum.Material.Concrete)
	box(model, "Ceiling", frame, -46, gx + 1, 18, 19, -31, 31, WHITE, Enum.Material.Plaster)
	box(model, "Wall", frame, -46, 5.5, 0, 18, -31, -30, wall, Enum.Material.Plaster) -- front (the exit door)
	box(model, "Wall", frame, -46, 5.5, 0, 18, 30, 31, wall, Enum.Material.Plaster) -- back (the TV)
	box(model, "Wall", frame, -46, -45, 0, 18, -30, 30, wall, Enum.Material.Plaster) -- left (the bed, the wardrobe)
	box(model, "GarageWall", frame, 5.5, gx + 1, 0, 18, -31, -30, grey, Enum.Material.Concrete)
	box(model, "GarageWall", frame, 5.5, gx + 1, 0, 18, 30, 31, grey, Enum.Material.Concrete)
	box(model, "GarageWall", frame, gx, gx + 1, 0, 18, -30, 30, grey, Enum.Material.Concrete)
	-- Divider with a doorway (z -6..6): plaster on the living side, painted block on the garage side.
	for _, span in ipairs({ { 0, 18, -30, -6 }, { 0, 18, 6, 30 }, { 12, 18, -6, 6 } }) do
		box(model, "Divider", frame, 5, 5.5, span[1], span[2], span[3], span[4], wall, Enum.Material.Plaster)
		box(model, "Divider", frame, 5.5, 6, span[1], span[2], span[3], span[4], grey, Enum.Material.Concrete)
	end
	local arch = box(model, "GarageArch", frame, 4.6, 5, 12.6, 16.4, -5, 5, DARK, Enum.Material.Metal)
	signGui(arch, Enum.NormalId.Left, "GARAGE", nil, theme)

	-- Light: three ceiling lights (always on: the room has no windows) and a warm cove strip round the
	-- living room ceiling that comes on after dark.
	neon(model, frame, -45, 5, 17.3, 17.7, 29.6, 30, WARM)
	neon(model, frame, -45, -44.6, 17.3, 17.7, -29.6, 29.6, WARM) -- between the front and back strips
	neon(model, frame, -45, 5, 17.3, 17.7, -30, -29.6, WARM)
	for _, p in ipairs({ { -34, -12 }, { -12, -12 }, { -22, 14 } }) do
		local disc = newPart(model, "CeilingLight", Vector3.new(0.3, 4, 4), frame * CFrame.new(p[1], 17.8, p[2]) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(255, 246, 230), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
		light(disc, WARM, 34, 1.1)
	end

	-- The way out: a walnut front door in a white casing.
	local exit = box(model, "ExitDoor", frame, -24, -16, 0, 11, -30, -29.6, wood, Enum.Material.WoodPlanks)
	box(model, "DoorFrame", frame, -24.8, -24, 0, 11.8, -30, -29.3, WHITE, Enum.Material.Concrete, DETAIL)
	box(model, "DoorFrame", frame, -16, -15.2, 0, 11.8, -30, -29.3, WHITE, Enum.Material.Concrete, DETAIL)
	box(model, "DoorFrame", frame, -24, -16, 11, 11.8, -30, -29.3, WHITE, Enum.Material.Concrete, DETAIL) -- between the posts
	box(model, "Knob", frame, -17.4, -16.8, 5, 5.6, -29.6, -29.3, BRASS, Enum.Material.Metal)
	box(model, "Mat", frame, -23, -17, 0, 0.1, -29.5, -26, Color3.fromRGB(88, 72, 56), Enum.Material.Fabric)
	local leavePrompt = makePrompt(exit, "LeavePrompt", show and "End tour" or "Leave home", "Front door")
	leavePrompt.Triggered:Connect(function(who)
		if who == player then
			leave(player)
		end
	end)
	-- Neon waves above the door: dark metal by day, they glow after dark.
	for i = 0, 3 do
		nightNeon(newPart(model, "NeonWave", Vector3.new(3.8, 0.4, 0.3),
			frame * CFrame.new(-25.1 + i * 3.4, 14.5, -29.75) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 30 or -30)),
			TRIM_DAY, Enum.Material.Metal, DETAIL), theme)
	end

	-- Living room: rug, a couch you can sit on facing the TV, glass coffee table, floor lamp, plants,
	-- arcade machine.
	box(model, "Rug", frame, -34, -6, 0, 0.12, -6, 16, theme:Lerp(Color3.fromRGB(190, 180, 164), 0.85), Enum.Material.Fabric)
	local couch = Color3.fromRGB(122, 118, 112) -- a warm grey sofa
	box(model, "Couch", frame, -30, -10, 0, 2.4, 2, 8, couch, Enum.Material.Fabric)
	box(model, "CouchBack", frame, -30, -10, 0, 6, 0, 2, couch, Enum.Material.Fabric)
	box(model, "CouchArm", frame, -31.5, -30, 0, 4, 0, 8, couch, Enum.Material.Fabric)
	box(model, "CouchArm", frame, -10, -8.5, 0, 4, 0, 8, couch, Enum.Material.Fabric)
	box(model, "Cushion", frame, -28, -23, 2.4, 5, 2, 3, accent, Enum.Material.Fabric)
	box(model, "Cushion", frame, -17, -12, 2.4, 5, 2, 3, accent, Enum.Material.Fabric)
	for _, x in ipairs({ -24, -16 }) do
		local seat = Instance.new("Seat")
		seat.Name = "CouchSeat"
		seat.Anchored = true
		seat.Size = Vector3.new(4, 0.4, 4)
		seat.CFrame = frame * CFrame.new(x, 2.6, 5) * CFrame.Angles(0, math.pi, 0) -- facing the TV (+Z)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.Parent = model
	end
	box(model, "TableTop", frame, -24, -16, 1.8, 2.2, 11, 16, GLASS, Enum.Material.Glass, { Transparency = 0.2, Reflectance = 0.1 })
	box(model, "TableLeg", frame, -20.6, -19.4, 0, 1.8, 12.9, 14.1, Color3.fromRGB(150, 150, 152), Enum.Material.Metal)
	box(model, "TVStand", frame, -31, -9, 0, 3, 26.5, 29.5, wood, Enum.Material.WoodPlanks)
	local tv = box(model, "TV", frame, -30, -10, 5, 15, 29.4, 30, Color3.fromRGB(14, 14, 20))
	tvScreen(tv)
	neon(model, frame, -30, -10, 4.6, 5, 29.3, 30, theme) -- the TV's backlight, after dark
	box(model, "LampPole", frame, -38.3, -37.7, 0, 8, 3.7, 4.3, Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	light(nightLamp(box(model, "LampShade", frame, -39.5, -36.5, 8, 10, 2.5, 5.5, LAMP_DAY, Enum.Material.SmoothPlastic, DETAIL), WARM),
		WARM, 26, 1.3)
	plant(model, frame, -42, 26)
	plant(model, frame, 1, -26)
	box(model, "Arcade", frame, -3, 2, 0, 8, 25, 29.4, Color3.fromRGB(34, 34, 40))
	local screen = box(model, "ArcadeScreen", frame, -2.4, 1.4, 4.4, 7, 24.7, 25, Color3.fromRGB(16, 16, 24))
	signGui(screen, Enum.NormalId.Front, "HIGH SCORE", "YOU!", theme, GOLD)
	box(model, "ArcadeButtons", frame, -2.4, 1.4, 3.4, 3.8, 23.8, 25, Color3.fromRGB(44, 44, 50))
	neon(model, frame, -3, 2, 7.6, 8.2, 24.6, 25, theme)

	-- Neon art (dark metal by day, lit after dark): a palm on the back wall, "HOME SWEET HOME" letters,
	-- and a retro sunset over the bed.
	local trunk = frame * CFrame.new(-39, 7, 29.75) * CFrame.Angles(0, 0, math.rad(-8))
	nightNeon(newPart(model, "NeonPalm", Vector3.new(0.5, 7, 0.3), trunk * CFrame.new(0, 3.5, 0), TRIM_DAY, Enum.Material.Metal, DETAIL),
		Color3.fromRGB(255, 190, 60))
	for _, a in ipairs({ -115, -70, -25, 25, 70, 115 }) do
		nightNeon(newPart(model, "NeonPalm", Vector3.new(0.4, 3.6, 0.3), trunk * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.rad(a)) * CFrame.new(0, 1.8, 0),
			TRIM_DAY, Enum.Material.Metal, DETAIL), theme)
	end
	local sweet = box(model, "HomeSweetHome", frame, -8, 3, 10, 14, 29.7, 30, wall, Enum.Material.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	signGui(sweet, Enum.NormalId.Front, "HOME SWEET HOME", nil, theme)
	nightNeon(newPart(model, "NeonSun", Vector3.new(0.3, 7, 7), frame * CFrame.new(-44.8, 12, -16), TRIM_DAY, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }), Color3.fromRGB(255, 176, 60))
	for i, y in ipairs({ 9.6, 10.8, 11.8 }) do
		box(model, "SunStripe", frame, -44.65, -44.45, y, y + 0.5 - i * 0.08, -19.8, -12.2, wall, Enum.Material.Plaster)
	end
	neon(model, frame, -44.8, -44.5, 8.2, 8.6, -22, -10, theme)

	-- Bed against the left wall: an upholstered headboard with a reading light along its top (after
	-- dark), a walnut frame and nightstand, and a bedside lamp.
	box(model, "Headboard", frame, -45, -44, 0, 7, -22, -10, Color3.fromRGB(150, 140, 128), Enum.Material.Fabric)
	neon(model, frame, -45, -44, 7, 7.4, -22, -10, WARM)
	box(model, "BedFrame", frame, -44, -30, 0, 1.6, -21.5, -10.5, wood, Enum.Material.WoodPlanks)
	box(model, "Mattress", frame, -44, -30.5, 1.6, 3, -21, -11, Color3.fromRGB(236, 234, 228), Enum.Material.Fabric)
	box(model, "Blanket", frame, -38, -30.3, 2.4, 3.2, -21.2, -10.8, Color3.fromRGB(62, 70, 84), Enum.Material.Fabric)
	box(model, "Pillow", frame, -43.5, -41, 3, 3.8, -20.5, -16.8, WHITE, Enum.Material.Fabric)
	box(model, "Pillow", frame, -43.5, -41, 3, 3.8, -15.2, -11.5, WHITE, Enum.Material.Fabric)
	box(model, "Nightstand", frame, -45, -41, 0, 3, -26, -23, wood, Enum.Material.WoodPlanks)
	light(nightLamp(box(model, "BedsideLamp", frame, -43.6, -42.4, 3, 4.4, -25.1, -23.9, LAMP_DAY, Enum.Material.SmoothPlastic, DETAIL),
		WARM), WARM, 14, 1)

	-- Wardrobe on the left wall between the floor lamp and the corner plant (far from the exit door
	-- and the garage's "Drive this" prompts, which also use E): an oak closet with two painted doors and
	-- hat boxes on top, a mirror in a lit frame (after dark), a sign and a mat to stand on. Its "Change
	-- look" prompt is handled on the owner's device (WardrobeUI opens the dressing room, facing away
	-- from the closet so it's the backdrop).
	local closet = box(model, "Wardrobe", frame, -45, -42, 0, 11, 12.5, 22.5, oak, Enum.Material.WoodPlanks)
	local doorColor = Color3.fromRGB(226, 222, 214)
	box(model, "ClosetDoor", frame, -42, -41.8, 0.4, 10.6, 12.8, 17.4, doorColor, Enum.Material.WoodPlanks)
	box(model, "ClosetDoor", frame, -42, -41.8, 0.4, 10.6, 17.6, 22.2, doorColor, Enum.Material.WoodPlanks)
	box(model, "Knob", frame, -41.8, -41.5, 5, 6.2, 16.7, 17.1, BRASS, Enum.Material.Metal)
	box(model, "Knob", frame, -41.8, -41.5, 5, 6.2, 17.9, 18.3, BRASS, Enum.Material.Metal)
	neon(model, frame, -42, -41.7, 10.6, 11, 12.5, 22.5, WARM)
	-- Cylinders run along X: turn them upright.
	newPart(model, "HatBox", Vector3.new(1.6, 2.4, 2.4), frame * CFrame.new(-43.5, 11.8, 15) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(226, 214, 190), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	newPart(model, "HatBox", Vector3.new(1.2, 2, 2), frame * CFrame.new(-43.5, 11.6, 19.5) * CFrame.Angles(0, 0, math.rad(90)),
		accent, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	box(model, "Mirror", frame, -45, -44.7, 1.2, 10.2, 7.4, 11.2, Color3.fromRGB(214, 232, 246), Enum.Material.Glass, { Reflectance = 0.35 })
	neon(model, frame, -45, -44.5, 0.8, 1.2, 7, 11.6, WARM)
	light(neon(model, frame, -45, -44.5, 10.2, 10.6, 7, 11.6, WARM), WARM, 12, 0.7)
	neon(model, frame, -45, -44.5, 1.2, 10.2, 7, 7.4, WARM)
	neon(model, frame, -45, -44.5, 1.2, 10.2, 11.2, 11.6, WARM)
	local wardrobeSign = box(model, "WardrobeSign", frame, -45, -44.8, 12.8, 15.8, 7, 22.5, DARK, Enum.Material.Metal)
	signGui(wardrobeSign, Enum.NormalId.Right, "WARDROBE", nil, theme) -- Right = +X, facing the room
	box(model, "WardrobeMat", frame, -41.5, -35.5, 0, 0.1, 13.5, 21.5, Color3.fromRGB(88, 80, 72), Enum.Material.Fabric)
	if not show then -- (a show home's closet is just furniture: moveIn adds the prompt)
		makePrompt(closet, "WardrobePrompt", "Change look", "Wardrobe")
	end

	-- Garage: a steel roll-up door in a steel frame, strip lights (always on), a painted stripe in the
	-- home's colour, tyres, a toolbox and a sign with the count. The far wall is at gx; the door and the
	-- sign shift by `mid` to stay centred.
	box(model, "RollDoor", frame, 15 + mid, 45 + mid, 0, 14, -30, -29.6, Color3.fromRGB(214, 212, 206), Enum.Material.Metal)
	for i = 1, 5 do
		local y = i * 14 / 6
		box(model, "Slat", frame, 15 + mid, 45 + mid, y - 0.12, y + 0.12, -29.6, -29.4, Color3.fromRGB(188, 186, 180), Enum.Material.Metal)
	end
	local steel = Color3.fromRGB(96, 98, 104)
	box(model, "DoorFrame", frame, 14.2 + mid, 15 + mid, 0, 14.8, -30, -29.3, steel, Enum.Material.Metal, DETAIL)
	box(model, "DoorFrame", frame, 45 + mid, 45.8 + mid, 0, 14.8, -30, -29.3, steel, Enum.Material.Metal, DETAIL)
	box(model, "DoorFrame", frame, 15 + mid, 45 + mid, 14, 14.8, -30, -29.3, steel, Enum.Material.Metal, DETAIL) -- between the posts
	for _, z in ipairs({ -18, 0, 18 }) do
		local strip = box(model, "StripLight", frame, 9, gx - 3, 17.4, 17.8, z - 0.5, z + 0.5, Color3.fromRGB(240, 248, 255), Enum.Material.Neon, DETAIL)
		light(strip, Color3.fromRGB(235, 242, 255), 32, 1)
	end
	box(model, "Stripe", frame, 6, gx, 3, 3.4, 29.6, 30, theme, Enum.Material.SmoothPlastic, DETAIL)
	box(model, "Stripe", frame, gx - 0.4, gx, 3, 3.4, -30, 30, theme, Enum.Material.SmoothPlastic, DETAIL)
	for i = 0, 2 do
		newPart(model, "Tyre", Vector3.new(1.3, 4, 4), frame * CFrame.new(gx - 3.5, 0.65 + i * 1.3, 26.5) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(28, 28, 32), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
	box(model, "Toolbox", frame, gx - 11, gx - 7, 0, 4, 27.4, 29.6, Color3.fromRGB(176, 36, 44), Enum.Material.Metal)
	local garageSign = box(model, "GarageSign", frame, 14 + mid, 40 + mid, 9, 15, 29.6, 30, DARK, Enum.Material.Metal)
	local garageTitle, signSub = signGui(garageSign, Enum.NormalId.Front, show and "GARAGE" or "MY GARAGE",
		show and string.format("Room for %d cars", n) or "", theme, WHITE)

	-- Parking bays (n, rows and perRow above): 12 x 18 concrete bays with white painted side lines, spread
	-- evenly across the garage's width. Every car faces the roll-up door (-Z). EMPTY BAY shows on the
	-- bays refreshGarage leaves empty (never in a show home: its own sign says it all).
	local rowZ = rows == 2 and { -16, 15 } or { 14 }
	local bays = {}
	for r = 1, rows do
		for k = 1, perRow do
			if #bays < n then
				local x = 6 + width * (k - 0.5) / perRow
				local z = rowZ[r]
				local pad = box(model, "Bay", frame, x - 6, x + 6, 0, 0.06, z - 9, z + 9, Color3.fromRGB(100, 100, 100), Enum.Material.Concrete)
				-- The lines sit on top of the bay (not inside it), so no faces overlap.
				box(model, "BayLine", frame, x - 6, x - 5.7, 0.06, 0.08, z - 9, z + 9, Color3.fromRGB(232, 232, 226), Enum.Material.SmoothPlastic, DETAIL)
				box(model, "BayLine", frame, x + 5.7, x + 6, 0.06, 0.08, z - 9, z + 9, Color3.fromRGB(232, 232, 226), Enum.Material.SmoothPlastic, DETAIL)
				local bayText = signGui(pad, Enum.NormalId.Top, "EMPTY BAY", nil, Color3.fromRGB(200, 200, 196))
				bayText.Parent.Enabled = not show
				table.insert(bays, { cf = frame * CFrame.new(x, 0.06, z), pad = pad })
			end
		end
	end

	local cars = Instance.new("Folder")
	cars.Name = "GarageCars"
	cars.Parent = model

	-- A show home only: a FOR SALE stand by the entrance (to the side of the way in, out of the exit
	-- door prompt's reach, facing the door) whose "Buy this home" prompt opens the buy card, and a small
	-- sign in the middle of the garage, facing the doorway, where the visitor's cars would park. Both in
	-- one folder, so buying on the tour clears them in one go (moveIn).
	local sale, saleAt = nil, nil
	if show then
		sale = Instance.new("Folder")
		sale.Name = "ForSale"
		sale.Parent = model
		local standCf = frame * CFrame.lookAt(Vector3.new(-7, 0, -19), Vector3.new(-20, 0, -21))
		local board = standSign(sale, standCf, 6, 3.6, 3.4, "FOR SALE", money(home.Price), GOLD, theme, true)
		saleAt = (standCf * CFrame.new(0, 3, 0)).Position -- (about where a visitor's root stands by it)
		local salePrompt = makePrompt(board, "SalePrompt", "Buy this home", home.Name)
		salePrompt.Triggered:Connect(function(who)
			if who == player and RateLimit.Allow(player, "House", 2, 3) then
				onSale(player)
			end
		end)
		local parkCf = frame * CFrame.lookAt(Vector3.new(6 + width / 2, 0, 0), Vector3.new(0, 0, 0))
		standSign(sale, parkCf, 5, 2.4, 2, "YOUR CARS PARK HERE", string.format("%d bays", n), theme, theme)
	end

	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	model.Parent = interiorFolder
	pcall(function()
		model:AddPersistentPlayer(player) -- always loaded on the owner's device
	end)
	return {
		model = model,
		slot = slot,
		homeId = home.Id,
		show = show == true,
		-- Inside, facing the room, just out of reach of the exit door's prompt (no accidental exits).
		spawn = frame * CFrame.new(-20, 3.5, -16) * CFrame.Angles(0, math.pi, 0),
		bays = bays,
		cars = cars,
		shown = {},
		signSub = signSub,
		-- What moveIn changes when a show home becomes the owner's:
		garageTitle = garageTitle,
		closet = closet,
		leavePrompt = leavePrompt,
		sale = sale, -- the show-only folder (nil once it's yours)
		saleAt = saleAt, -- the FOR SALE stand (buying on the tour must happen near it)
	}
end

-- The land cars this player owns and can drive on their side: last picked (on this side) first, then
-- fastest.
local function garageList(player, side)
	local last = VehicleService.LastCarFor(player, side)
	local list = {}
	for _, def in ipairs(Vehicles.List) do
		-- (Hidden street cars are never owned, but never list them either.)
		if not def.Hidden and not def.Boat and VehicleService.CanDrive(side, def.Id) and GarageService.Owns(player, def.Id) then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		if (a.Id == last) ~= (b.Id == last) then
			return a.Id == last
		end
		if a.MaxSpeed ~= b.MaxSpeed then
			return a.MaxSpeed > b.MaxSpeed
		end
		return a.DisplayName < b.DisplayName
	end)
	return list
end

-- A parked, frozen copy of a car for a garage bay, with a "Drive this" prompt.
local function displayCar(player, id, bayCf)
	local def = Vehicles.Resolve(id)
	local templates = ServerStorage:FindFirstChild("VehicleTemplates")
	local template = templates and templates:FindFirstChild(id)
	local ok, car = pcall(function()
		return template and template:Clone() or CarBuilder.Build(id)
	end)
	if not ok or not car or not car.PrimaryPart then
		warn("[HousingService] couldn't build " .. tostring(id) .. " for a garage: " .. tostring(car))
		return nil
	end
	car:SetAttribute("NCVehicle", nil) -- not a real car: other systems leave it alone
	car:SetAttribute("GarageDisplay", true)
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d:Destroy() -- no Drive / Ride prompts on a display car
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = d == car.PrimaryPart -- the invisible chassis box keeps players out
			d.CanTouch = false
		elseif d:IsA("VectorForce") or d:IsA("Torque") then
			d.Enabled = false
		end
	end
	pcall(function()
		GarageService.ApplyCustom(car, player)
	end)
	pcall(function()
		car.ModelStreamingMode = Enum.ModelStreamingMode.Default -- part of the owner's persistent interior
	end)
	car:PivotTo(bayCf * CFrame.new(0, carLift(def), 0))
	local prompt = makePrompt(car.PrimaryPart, "DriveThis", "Drive this", def.DisplayName)
	prompt.MaxActivationDistance = 14
	prompt.Triggered:Connect(function(who)
		if who == player and RateLimit.Allow(player, "House", 2, 3) then
			drive(player, id)
		end
	end)
	return car
end

-- Park the player's cars in the bays (again on every visit: they may have bought or unlocked some).
local function refreshGarage(player, rec)
	rec.cars:ClearAllChildren()
	rec.shown = {}
	local list = garageList(player, player:GetAttribute("Side") or "Civilian")
	local parked = 0
	for i, bay in ipairs(rec.bays) do
		local def = list[i]
		local car = def and displayCar(player, def.Id, bay.cf)
		if car then
			car.Parent = rec.cars
			rec.shown[def.Id] = true
			parked += 1
		end
		local gui = bay.pad:FindFirstChild("SignGui")
		if gui then
			gui.Enabled = car == nil
		end
	end
	if rec.signSub then
		local text = string.format("%d of %d bays", parked, #rec.bays)
		if #list > #rec.bays then
			text ..= string.format("  ·  %d more in your phone's Garage", #list - #rec.bays)
		end
		rec.signSub.Text = text
	end
end

-- Pool water (Terrain) for an inside's pools: `material` Water to fill, Air to clear.
local function poolWater(list, material)
	for _, w in ipairs(list or {}) do
		pcall(function()
			Workspace.Terrain:FillBlock(w.cf, w.size, material)
		end)
	end
end

local function destroyInterior(player)
	local rec = interiors[player]
	interiors[player] = nil
	if rec then
		if slots[rec.slot] == player then
			slots[rec.slot] = nil
		end
		poolWater(rec.water, Enum.Material.Air)
		rec.model:Destroy()
	end
end

-- With the realistic day lighting (WorldService), near-white rooms under nine lamps looked blown out.
-- Tone every interior down a notch: softer lamps, and the brightest surfaces a little less white.
-- `lights` false keeps the lamps (a house's own build sets its lights low already).
local function softenInterior(model, lights)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") then
			if lights ~= false then
				d.Brightness *= 0.6
			end
		elseif d:IsA("BasePart") and d.Material ~= Enum.Material.Neon then
			local c = d.Color
			if c.R + c.G + c.B > 2.4 then -- nearly white
				d.Color = c:Lerp(Color3.fromRGB(150, 146, 140), 0.25)
			end
		end
	end
end

-- The home's own inside (HouseBuilder draws Houses.<Style> again, rooms and all, at this slot): its
-- prompts (the way out, the wardrobe unless it's a show copy, the FOR SALE stand on one), the rooms
-- toned down like every inside, streamed to the owner only, and the pools filled with water.
local function ownInterior(player, home, slot, show)
	local out = HouseBuilder.Inside(home, slotFrame(slot), { show = show, ownerId = player.UserId })
	local model = out.model
	local leavePrompt = makePrompt(out.exit, "LeavePrompt", show and "End tour" or "Leave home", out.exitName or "Front door")
	leavePrompt.Triggered:Connect(function(who)
		if who == player then
			leave(player)
		end
	end)
	if out.closet and not show then
		makePrompt(out.closet, "WardrobePrompt", "Change look", "Wardrobe")
	end
	if show and out.saleBoard then
		local salePrompt = makePrompt(out.saleBoard, "SalePrompt", "Buy this home", home.Name)
		salePrompt.Triggered:Connect(function(who)
			if who == player and RateLimit.Allow(player, "House", 2, 3) then
				onSale(player)
			end
		end)
	end
	for _, name in ipairs({ "Rooms", "Decor", "Garage" }) do
		local f = model:FindFirstChild(name)
		if f then
			softenInterior(f, false)
		end
	end
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	model.Parent = interiorFolder
	pcall(function()
		model:AddPersistentPlayer(player) -- always loaded on the owner's device
	end)
	poolWater(out.water, Enum.Material.Water)
	return {
		model = model,
		slot = slot,
		homeId = home.Id,
		show = show == true,
		spawn = out.spawn,
		bays = out.bays,
		cars = out.cars,
		shown = {},
		signSub = out.signSub,
		garageTitle = out.garageTitle,
		closet = out.closet,
		leavePrompt = leavePrompt,
		sale = model:FindFirstChild("ForSale"),
		saleAt = out.saleAt,
		water = out.water,
	}
end

-- This home's inside in `slot`: its own build, or the plain one when that's missing or fails.
local function buildInterior(player, home, slot, show)
	if HouseBuilder.Has(home) then
		local ok, rec = pcall(ownInterior, player, home, slot, show)
		if ok then
			return rec
		end
		warn("[HousingService] couldn't build " .. home.Id .. "'s own inside, using the plain one: " .. tostring(rec))
		for _, m in ipairs(interiorFolder:GetChildren()) do
			if m:GetAttribute("OwnerUserId") == player.UserId and not interiors[player] then
				m:Destroy() -- (a half-built copy)
			end
		end
	end
	local rec = legacyInterior(player, home, slot, show)
	softenInterior(rec.model)
	return rec
end

-- This player's inside for `home` (`show`: a tour's show copy of it): reused if it's already built for
-- that home in that version. Otherwise whatever their slot holds goes (their own home on a tour, a
-- show home on the way home) and the new one is built in the same slot when it's still free.
local function interiorFor(player, home, show)
	show = show == true
	local rec = interiors[player]
	if rec and rec.homeId == home.Id and rec.show == show and rec.model.Parent then
		return rec
	end
	local slot = rec and rec.slot or 1
	destroyInterior(player)
	if slots[slot] then
		slot = 1
		while slots[slot] do
			slot += 1
		end
	end
	slots[slot] = player
	rec = buildInterior(player, home, slot, show)
	interiors[player] = rec
	return rec
end

-- Bought on the tour: the show home they stand in becomes their own inside, without a trip outside.
-- The stand and the garage sign go, the closet gets its prompt, the garage fills with their cars and
-- the door says "Leave home" again; InHome stays set, Touring clears.
local function moveIn(player, rec)
	rec.show = false
	rec.model:SetAttribute("Show", nil)
	if rec.sale then
		rec.sale:Destroy()
		rec.sale, rec.saleAt = nil, nil
	end
	if rec.closet and rec.closet.Parent and not rec.closet:FindFirstChild("WardrobePrompt") then
		makePrompt(rec.closet, "WardrobePrompt", "Change look", "Wardrobe")
	end
	if rec.garageTitle then
		rec.garageTitle.Text = "MY GARAGE"
	end
	if rec.leavePrompt then
		rec.leavePrompt.ActionText = "Leave home"
	end
	refreshGarage(player, rec)
	setInside(player, true)
end

-- Actions ---------------------------------------------------------------------------------------------

-- `at`: the FOR SALE stand when the card comes from a tour (the client closes it on walking away from
-- there instead of from the front door, and hides TOUR).
local function sendCard(player, home, at)
	local old = ownedHome(player)
	houseCard:FireClient(player, { Id = home.Id, OldId = old and old.Id or nil, Refund = Housing.Refund(old), At = at })
end

-- On a tour of this home right now: the show copy they're standing in (else nil).
local function tourOf(player, id)
	local rec = interiors[player]
	if inside[player] and rec and rec.show and rec.homeId == id then
		return rec
	end
	return nil
end

-- At the front door, or on a tour of that home at its FOR SALE stand.
local function buy(player, id)
	local home = Housing.ById[id]
	local data = DataService.Get(player)
	local onTour = tourOf(player, id)
	if not home or not data or busy[player] or (inside[player] and not onTour) then
		return
	end
	if player:GetAttribute("Side") == "Prisoner" or not alive(player) then
		return
	end
	if onTour then
		if not nearSale(player, onTour) then
			return -- (the card closed when they walked off from the stand)
		end
	elseif not nearDoor(player, home) then
		notify:FireClient(player, "HomeTooFar") -- walked off with the buy card still open
		return
	end
	if data.home == id then
		notify:FireClient(player, "HomeAlreadyOwned")
		return
	end
	-- One home at a time: the old one sells back for half its price, which counts toward the new one.
	local old = data.home and Housing.ById[data.home] or nil
	local refund = Housing.Refund(old)
	local net = home.Price - refund
	if net > 0 then
		if not EconomyService.Spend(player, net, "home:" .. id) then
			notify:FireClient(player, "NotEnoughCash")
			return
		end
	elseif net < 0 then
		EconomyService.AddCash(player, -net, "home:tradein:" .. old.Id) -- moving somewhere cheaper
	end
	data.home = id
	player:SetAttribute("Home", id)
	if onTour then
		-- They're standing in it: it simply becomes theirs (busy: no Leave halfway through the garage).
		busy[player] = true
		local ok, err = pcall(moveIn, player, onTour)
		if not ok then
			warn("[HousingService] move-in failed: " .. tostring(err))
			onTour.show = nil -- (neither version: the next visit builds the owner's inside afresh)
			setInside(player, true) -- still indoors, no longer touring; Leave works as ever
		end
		busy[player] = nil
	else
		destroyInterior(player) -- the new home gets its own inside (garage size, colours) next visit
	end
	houseResult:FireClient(player, { Kind = "Bought", Id = id, Refund = refund })
	Telemetry.Custom(player, "HomeBought", home.Price)
	task.spawn(function() -- the goal chain (its own thread: nothing there can undo the purchase)
		require(ServerScriptService.Services.ProgressService).Event(player, "BuyHome", 1)
	end)
	task.spawn(DataService.SaveNow, player) -- a big purchase: save it right away
end

local function enter(player, id)
	local home = Housing.ById[id]
	local data = DataService.Get(player)
	if not home or not data or data.home ~= id or busy[player] or inside[player] then
		return
	end
	if player:GetAttribute("Side") == "Prisoner" or not alive(player) or not nearDoor(player, home) then
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 then
		notify:FireClient(player, "HomeWanted") -- no hiding from the cops at home
		return
	end
	busy[player] = true
	local ok, err = pcall(function()
		local rec = interiorFor(player, home)
		refreshGarage(player, rec)
		fade(player, "Out")
		task.wait(FADE_TIME)
		stream(player, rec.spawn.Position)
		if player.Parent == Players and moveTo(player, rec.spawn) then
			setInside(player, true)
		end
	end)
	if not ok then
		warn("[HousingService] enter failed: " .. tostring(err))
	end
	fade(player, "In")
	busy[player] = nil
end

-- A look round someone else's kind of home (see the header): a citizen or a cop at its front door, on
-- foot and not wanted. Your own home just lets you in.
local function tour(player, id)
	local home = Housing.ById[id]
	local data = DataService.Get(player)
	if not home or not data or busy[player] or inside[player] then
		return
	end
	if data.home == id then
		enter(player, id)
		return
	end
	local side = player:GetAttribute("Side") or "Civilian"
	if (side ~= "Civilian" and side ~= "Cop") or not alive(player) or not nearDoor(player, home) then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		notify:FireClient(player, "GetOutFirst")
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 then
		notify:FireClient(player, "HomeWanted") -- no hiding from the cops on a tour either
		return
	end
	busy[player] = true
	local ok, err = pcall(function()
		local rec = interiorFor(player, home, true)
		fade(player, "Out")
		task.wait(FADE_TIME)
		stream(player, rec.spawn.Position)
		if player.Parent == Players and moveTo(player, rec.spawn) then
			setInside(player, true, home.Id)
		end
	end)
	if not ok then
		warn("[HousingService] tour failed: " .. tostring(err))
	end
	fade(player, "In")
	busy[player] = nil
end

leave = function(player)
	if not inside[player] or busy[player] then
		return
	end
	local rec = interiors[player]
	local home = (rec and Housing.ById[rec.homeId]) or ownedHome(player)
	busy[player] = true
	local ok, err = pcall(function()
		fade(player, "Out")
		task.wait(FADE_TIME)
		if player.Parent ~= Players then
			return
		end
		if home then
			local cf = Housing.DoorCFrame(home)
			stream(player, cf.Position)
			moveTo(player, cf)
			setInside(player, false)
		else
			player:LoadCharacter() -- no home to walk out of: back to a normal spawn
		end
	end)
	if not ok then
		warn("[HousingService] leave failed: " .. tostring(err))
	end
	fade(player, "In")
	busy[player] = nil
end

drive = function(player, id)
	local rec = interiors[player]
	if not rec or rec.show or not inside[player] or busy[player] or not rec.shown[id] then
		return -- (a show home has no cars to drive)
	end
	local def = Vehicles.ById[id]
	local home = Housing.ById[rec.homeId]
	local side = player:GetAttribute("Side") or "Civilian"
	if not def or def.Boat or not home or not VehicleService.CanDrive(side, id) or not GarageService.Owns(player, id) then
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 then
		notify:FireClient(player, "HomeWanted") -- (the housekeeping loop puts them out within 2 s)
		return
	end
	busy[player] = true
	local ok, err = pcall(function()
		fade(player, "Out")
		task.wait(FADE_TIME)
		if player.Parent ~= Players then
			return
		end
		local door = Housing.DoorCFrame(home)
		stream(player, door.Position)
		-- Step outside first, so seating the driver never drags the character across the map.
		if not moveTo(player, door) then
			return
		end
		setInside(player, false)
		local car = VehicleService.Spawn(player, id, { At = Housing.DrivewayCFrames(home), Sit = true, IgnoreCooldown = true })
		if not car then
			notify:FireClient(player, "CarNoRoom")
		end
	end)
	if not ok then
		warn("[HousingService] drive failed: " .. tostring(err))
	end
	fade(player, "In")
	busy[player] = nil
end

onDoor = function(player, home)
	if not RateLimit.Allow(player, "House", 2, 3) then
		return
	end
	local data = DataService.Get(player)
	if not data or busy[player] or inside[player] then
		return
	end
	if data.home == home.Id then
		enter(player, home.Id)
	elseif player:GetAttribute("Side") ~= "Prisoner" then
		sendCard(player, home)
	end
end

-- The show home's FOR SALE stand: the normal buy card for the home on tour (rate-limited by the prompt).
onSale = function(player)
	local rec = interiors[player]
	local home = rec and Housing.ById[rec.homeId]
	if not home or busy[player] or not tourOf(player, home.Id) or not alive(player) or not nearSale(player, rec) then
		return
	end
	sendCard(player, home, rec.saleAt)
end

-- Home spawn ------------------------------------------------------------------------------------------

-- A character that may spawn at home: a free-roam citizen (not a cop, not a prisoner) who owns a home
-- and isn't wanted (no hiding from the cops at home, and a wanted respawn stays at the city spawn).
local function spawnsHome(player)
	return player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) <= 0 and ownedHome(player) ~= nil
		and player:GetAttribute("MeetPending") ~= true -- (arriving to meet a friend: FriendsService moves them)
end

-- Into the owner's own inside, standing in the living room (the join and respawn spawn): the same trip
-- as the front door's, without the door (they're not at it) and only for `char`.
local function goInside(player, home, char)
	if busy[player] or inside[player] or player.Parent ~= Players then
		return -- (gone: a copy built now would outlive PlayerRemoving's clean-up)
	end
	busy[player] = true
	local ok, err = pcall(function()
		local rec = interiorFor(player, home)
		refreshGarage(player, rec)
		fade(player, "Out")
		task.wait(FADE_TIME)
		stream(player, rec.spawn.Position)
		if player.Parent == Players and player.Character == char and spawnsHome(player) and moveTo(player, rec.spawn) then
			setInside(player, true)
		end
	end)
	if not ok then
		warn("[HousingService] home spawn failed: " .. tostring(err))
	end
	fade(player, "In")
	busy[player] = nil
end

-- Returning players spawn inside their home, once per character. On the first join the title screen
-- (TeamUI) is up until the player presses PLAY, and its camera circles the character: they wait at their
-- front door (their house is the title's backdrop) and go in when PLAY sets HasPicked, unless they walked
-- off, sat down or something changed meanwhile.
local function homeSpawn(player, char)
	local s = spawned[player]
	if not s or s.char ~= char or s.done then
		return
	end
	s.done = true
	if not spawnsHome(player) then
		return
	end
	task.wait(SPAWN_DELAY)
	local home = ownedHome(player)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not home or player.Character ~= char or not spawnsHome(player) or inside[player] or busy[player] then
		return
	end
	if hum and hum.SeatPart then
		return -- already in a car (called one before the save loaded): leave them be
	end
	if player:GetAttribute("HasPicked") == true then
		goInside(player, home, char)
		return
	end
	local cf = Housing.DoorCFrame(home)
	local atDoor = false -- (PLAY can come while the door area is still loading: see the end)
	local waiting = true -- until PLAY has been acted on (or the character went)
	local function tryInside()
		waiting = false
		local root = rootOf(player)
		local seated = hum and hum.SeatPart ~= nil
		if player.Character == char and root and not seated and not inside[player] and ownedHome(player) == home
			and (root.Position - cf.Position).Magnitude < 30 then
			task.spawn(goInside, player, home, char)
		end
	end
	local conn
	conn = player:GetAttributeChangedSignal("HasPicked"):Connect(function()
		if player:GetAttribute("HasPicked") ~= true or not atDoor then
			return -- (not at the door yet: the check after the trip below takes it)
		end
		conn:Disconnect()
		tryInside()
	end)
	char.AncestryChanged:Connect(function()
		if not char:IsDescendantOf(game) and conn.Connected then
			conn:Disconnect()
		end
	end)
	stream(player, cf.Position)
	if player.Character ~= char or not moveTo(player, cf) then
		conn:Disconnect()
		return
	end
	atDoor = true
	if player:GetAttribute("HasPicked") == true and waiting then
		-- PLAY was pressed while the door area loaded.
		conn:Disconnect()
		tryInside()
	end
end

local function onCharacter(player, char)
	setInside(player, false) -- a new character always starts outside
	spawned[player] = { char = char, t = os.clock(), done = false }
	if DataService.IsLoaded(player) then
		homeSpawn(player, char)
	end
end

-- Public ----------------------------------------------------------------------------------------------

function HousingService.HomeOf(player)
	local home = ownedHome(player)
	return home and home.Id or nil
end

-- Indoors in a home: their own, or a show home on a tour (DisguiseService: a change of clothes is fine
-- in either, a look changed at home never touches heat).
function HousingService.IsInside(player)
	return inside[player] == true
end

-- The home id they're touring right now, else nil.
function HousingService.TouringOf(player)
	local rec = interiors[player]
	return rec and tourOf(player, rec.homeId) and rec.homeId or nil
end

-- The driveway spots of the player's home when they roam free and aren't wanted (then they spawn at home
-- too: spawnsHome), else nil (VehicleService's starter car goes to a city pad instead).
function HousingService.DrivewayFor(player)
	if (player:GetAttribute("Side") or "Civilian") ~= "Civilian" or (player:GetAttribute("Heat") or 0) > 0 then
		return nil
	end
	local home = ownedHome(player)
	return home and Housing.DrivewayCFrames(home) or nil
end

-- Look 3.0 scattered loose palms and bushes over Palm Hills' open lawns (Workspace.City.Art.Plazas,
-- "LawnPalm" and "TropicalBush" models) before some homes' lots were where they are now: a few stand in a
-- driveway or through a garage. The ones on a lot go at start-up (looks only: they never collided).
local function clearLots()
	local city = Workspace:FindFirstChild("City")
	local art = city and city:FindFirstChild("Art")
	local plazas = art and art:FindFirstChild("Plazas")
	for _, d in ipairs(plazas and plazas:GetChildren() or {}) do
		if d.Name == "LawnPalm" or d.Name == "TropicalBush" then
			local pos = d:IsA("BasePart") and d.Position or (d:IsA("Model") and d:GetPivot().Position) or nil
			for _, home in ipairs(pos and Housing.List or {}) do
				local p = Housing.Frame(home):PointToObjectSpace(pos)
				if math.abs(p.X) < 60 and p.Z > -38 and p.Z < 42 then
					d:Destroy()
					break
				end
			end
		end
	end
end

local function onRequest(player, action, arg)
	if not RateLimit.Allow(player, "House", 2, 3) or type(action) ~= "string" then
		return
	end
	if action == "Buy" or action == "Enter" or action == "Tour" then
		if type(arg) ~= "string" or not Housing.ById[arg] then
			return
		end
		if action == "Buy" then
			buy(player, arg)
		elseif action == "Tour" then
			tour(player, arg)
		else
			enter(player, arg)
		end
	elseif action == "Leave" then
		leave(player)
	elseif action == "Drive" then
		if type(arg) ~= "string" or not Vehicles.ById[arg] then
			return
		end
		drive(player, arg)
	end
end

function HousingService.Init()
	notify = Remotes.Event("Notify")
	houseCard = Remotes.Event("HouseCard")
	houseResult = Remotes.Event("HouseResult")
	houseFade = Remotes.Event("HouseFade")
	Remotes.Event("RequestHouse").OnServerEvent:Connect(onRequest)

	homesFolder = Workspace:FindFirstChild("Homes") or Instance.new("Folder")
	homesFolder.Name = "Homes"
	homesFolder:ClearAllChildren()
	homesFolder.Parent = Workspace
	interiorFolder = Workspace:FindFirstChild("HomeInteriors") or Instance.new("Folder")
	interiorFolder.Name = "HomeInteriors"
	interiorFolder:ClearAllChildren()
	interiorFolder.Parent = Workspace
	pcall(clearLots)
	for _, home in ipairs(Housing.List) do
		local ok, err = pcall(buildExterior, home)
		if not ok then
			warn("[HousingService] couldn't build " .. home.Id .. ": " .. tostring(err))
		end
	end

	DataService.OnLoaded(function(player, data)
		if data.home and not Housing.ById[data.home] then
			data.home = nil -- a home that no longer exists
		end
		player:SetAttribute("Home", data.home)
		-- The first character usually spawns before the save loads: send it home now, unless the
		-- save took longer than VehicleService waited (its car already went to a city pad).
		local s = spawned[player]
		local char = player.Character
		if s and char and s.char == char and not s.done and os.clock() - s.t < VehicleService.JoinWait then
			task.spawn(homeSpawn, player, char)
		end
	end)

	local function onPlayer(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		destroyInterior(player)
		setInside(player, false) -- (clears InHome and Touring too)
		busy[player] = nil
		spawned[player] = nil
	end)

	-- Housekeeping: anyone moved out of their inside by something else counts as outside again; anyone
	-- who somehow falls through the floor goes back to the spot inside the door; anyone who turns out to
	-- be wanted in there (a crime that only counted after they went in) is put out of the front door.
	task.spawn(function()
		while true do
			task.wait(2)
			for player in pairs(inside) do
				local rec = interiors[player]
				local root = rootOf(player)
				if rec and root and not busy[player] and (player:GetAttribute("Heat") or 0) > 0 then
					notify:FireClient(player, "HomeWanted")
					task.spawn(leave, player)
				elseif rec and root and not busy[player] then
					local s = rec.spawn.Position
					local flat = Vector3.new(root.Position.X - s.X, 0, root.Position.Z - s.Z).Magnitude
					if flat > 150 then
						setInside(player, false)
					elseif root.Position.Y < s.Y - 30 then
						moveTo(player, rec.spawn)
					end
				elseif not rec then
					setInside(player, false)
				end
			end
		end
	end)
end

return HousingService
