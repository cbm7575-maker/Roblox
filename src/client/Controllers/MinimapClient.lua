-- MinimapClient (ModuleScript, StarterPlayerScripts.Controllers.MinimapClient)
-- The minimap, in the HUD's Minimap zone ("street" look, Shared.Util.Theme): bottom-left on PC /
-- gamepad (CombatClient's health and armour sit under it), top-left under Roblox's top bar on phones.
-- A flat rectangle with small corners and a thin dark frame, re-placed when the screen size or the input
-- type changes. Drawn from data the server publishes, so it works for streamed-out areas too:
--   ground tiles + building footprints (ReplicatedStorage "MapShapes", MapService), roads (RoadGraph),
--   places (MapService "Places"/"OpenHeists"), and the GPS route (GPSClient).
-- Look: toned like the real city: grey asphalt roads, dark blocks on darker ground, muted water, sand
-- and green. You are a white arrow a bit below the middle (more road ahead than behind). Blips are small
-- round discs (16 px, 18 for the ones you head for) with one letter, coloured by meaning: gold = a goal or reward (the GPS target ★, open
-- heists $), green = the Hideout (bank your cash), blue = Police HQ, grey = shops and services, white =
-- your home, purple = crewmates, orange = Florida moments. The GPS / race route is a gold line. A small
-- N sits on the edge, pointing north (-Z, CityGen).
-- How it's drawn: the map is a set of flat parts inside a ViewportFrame, filmed by a top-down camera
-- that turns with the player's camera (so "up" is where you're looking) and climbs when you drive
-- fast (zoom out). A ViewportFrame clips cleanly on every device. Blips are 2D labels on top,
-- placed with the same maths and pinned to the edge when they're off the map, like a compass.
-- Chase radar (only while you're wanted, Heat > 0; the server's ReplicatedStorage "ChaseRadar" mode,
-- set by HeatService: "On", "Seen" = only while a cop sees you (HeatSpotted), "Off" = none):
--   * the map's thin frame flashes red / blue while you're wanted (with any radar mode);
--   * police cars within 250 studs get flashing red / blue blips: AI patrols (car attribute AIPolice,
--     AIPoliceService) and police cars a player cop is driving (Police + DriverUserId). Parked police
--     cars don't show. Player cops only show while a cop sees you, even in "On": AI patrols always
--     drive at your real position, but a player cop searching while your stars are hollow can't see
--     you, so they don't see them either.
--   * up to 3 screen arrows (layer "ChaseArrows") point at the nearest of those within 120 studs that
--     are off screen, on a ring around the middle of the screen. An arrow never covers the HUD zones in
--     KEEP_OUT_ZONES (Theme zones: the map, vitals, status, pills, buttons, goal, banner, help-text
--     subtitle, car cluster, exit), the pieces in KEEP_OUT (the phone pedals, Roblox's jump button and
--     classic thumbstick, the action button, the cop tiles, banners...), the toast and Coast Feed cards
--     showing (CARD_STACKS, card by card) or, on phones, the lower-left where the thumb steers: it slides
--     inward or round the ring, else it hides.
-- Hidden in prison and while the first-join title screen is up (local attribute TitleScreen, TeamUI):
-- this file sets its layers' Enabled every frame, so it checks that itself.
-- API (both work before Init):
--   MinimapClient.Rect() -> x, y, w, h: the map's box in pixels from the top-left of the Minimap
--     ScreenGui (IgnoreGuiInset: y = 0 is the very top of the screen; the camera's view before Init).
--   MinimapClient.Bottom() -> the first free y (same pixels) on the RIGHT edge of the screen: under the
--     Status, Pills and Buttons zones. (It used to be the bottom of the map when the map sat top-right;
--     the map has moved to the left side, so a right-edge column wants this.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))

local player = Players.LocalPlayer

local MinimapClient = {}

local NEAR_RADIUS = 170 -- studs from the middle of the map to its top / bottom edge when slow
local FAR_RADIUS = 330 -- when flat out
local FOV = 20
local PLAYER_Y = 0.62 -- your arrow sits this far down the map, so more of the road ahead shows
local EDGE = 10 -- pixels: blips pinned to the edge sit this far in (their middle: an 18 px disc stays inside)
local NORTH = Vector3.new(0, 0, -1)

local C = Theme.Color
-- The map's palette. The ViewportFrame's light adds up to exactly 1 (Ambient + LightColor = 255) on the
-- flat tops, so these are the colours you see.
local COLORS = {
	water = Color3.fromRGB(46, 74, 96),
	grass = Color3.fromRGB(64, 84, 62),
	sand = Color3.fromRGB(122, 114, 92),
	concrete = Color3.fromRGB(62, 64, 68),
	wood = Color3.fromRGB(92, 80, 66),
	paving = Color3.fromRGB(76, 78, 82),
	building = Color3.fromRGB(40, 42, 47),
	road = Color3.fromRGB(118, 120, 124),
	route = C.Gold,
}
local DARK = C.Panel
local RED = C.Danger
local BLUE = C.Police

local COP_RANGE = 250 -- studs: police cars this close show on the map while you're wanted
local ARROW_RANGE = 120 -- studs: ...and get a screen arrow when they're off screen
local MAX_ARROWS = 3
-- Theme zones the chase arrows never cover (the always-on HUD), on the layout in use. (Toasts and Feed
-- have no height in the zone map: their cards are counted one by one, CARD_STACKS.)
local KEEP_OUT_ZONES = { "Minimap", "Vitals", "Status", "Pills", "Buttons", "Goal", "Banner", "Subtitle", "Corner", "Exit" }
-- ...and pieces that live outside those zones or come and go (paths under PlayerGui; a missing or
-- hidden one is skipped). The pedals and the jump button are the must-haves.
local KEEP_OUT = {
	{ "DriveUI", "Touch" }, -- GAS / BRAKE / NITRO / DRIFT (+ HORN, SMOKE)
	{ "DriveUI", "CarCluster" }, { "DriveUI", "ControlsHint" }, { "DriveUI", "Exit" }, { "DriveUI", "Flip" },
	{ "Interact", "Action" }, { "LawUI", "Taser" }, { "LawUI", "Spikes" },
	{ "LawUI", "Prison" }, { "House", "LeaveHome" }, { "House", "BuyCard" }, { "WardrobeUI", "Open" },
	{ "Objective", "Banner" }, { "Tutorial", "Next" }, { "GPS", "Route" }, { "Phone", "Body" },
	{ "Mission", "Step" }, { "Offer", "Card" }, { "Crew", "CrewInvite" }, { "BigScore", "Checklist" },
	{ "TouchGui", "TouchControlFrame", "JumpButton" }, -- Roblox's jump button on foot
	{ "TouchGui", "TouchControlFrame", "ThumbstickFrame" }, -- Roblox's classic thumbstick
}
-- Stacks of cards (toasts, Coast Feed posts) that come and go between looks: every card showing counts.
-- (Toasts.Holder is as tall as the room the stack may fill, so the holder itself can't be the box.)
local CARD_STACKS = { { "Toasts", "Holder" }, { "CoastFeed", "Holder" } }
-- Phones: where the left thumb steers (Roblox's dynamic thumbstick appears wherever it lands there):
-- the lower half of the screen, this share of its width from the left, at most THUMB_MAX pixels.
local THUMB_SHARE, THUMB_MAX = 0.32, 280
local SLIDE_ANGLES = { 0, 15, -15, 30, -30, 45, -45 } -- degrees round the ring an arrow may slide
local SLIDE_RADII = { 1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4 } -- shares of the ring's size, inward

local gui, view, cam, overlay, frameStroke, arrow, north, routeModel, mapModel
local staticParts = {} -- { part, pos, r } for culling
local mapW, mapH = 240, 160 -- the map's size in pixels now (fit)
local radius = NEAR_RADIUS
local blips = {} -- [key] = { frame, pos, edge, track, flash }
local routeStamp
local chaseGui
local copArrows = {} -- the MAX_ARROWS screen arrows
local arrowSize = 30
local copParts = {} -- chassis of the police cars within COP_RANGE (refreshBlips, once a second)
local copKeys = setmetatable({}, { __mode = "k" }) -- [car] = its blip key
local copCount = 0
local keepOut = {} -- GuiObjects found from KEEP_OUT (refreshed once a second)
local cardStacks = {} -- the holders found from CARD_STACKS (refreshed with keepOut)

local function viewport()
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(844, 390)
end

-- The Minimap ScreenGui's own size (the box its zones are laid out in), else the camera's view.
local function screenSize()
	local size = gui and gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then
		return size
	end
	return viewport()
end

-- A Theme zone's box on a screen of this size, in pixels (IgnoreGuiInset coordinates): x, y, w, h.
local function zoneBox(name, touch, screen)
	local z = Theme.Zone(name, touch)
	local w = z.Size.X.Scale * screen.X + z.Size.X.Offset
	local h = z.Size.Y.Scale * screen.Y + z.Size.Y.Offset
	return z.Pos.X.Scale * screen.X + z.Pos.X.Offset - z.Anchor.X * w, z.Pos.Y.Scale * screen.Y + z.Pos.Y.Offset - z.Anchor.Y * h, w, h
end

local function flatPart(parent, cf, sx, sz, y, color)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = Vector3.new(math.max(sx, 0.5), 0.2, math.max(sz, 0.5))
	p.CFrame = CFrame.new(cf.X, y, cf.Z) * (cf - cf.Position)
	p.Color = color
	p.Parent = parent
	return p
end

local function segment(parent, a, b, width, y, color)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	if len < 0.1 then
		return nil
	end
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.X, 0, b.Z))
	return flatPart(parent, cf, width, len + width * 0.5, y, color)
end

local function buildStatic()
	local model = Instance.new("Model")
	model.Name = "Map"
	local ok, data = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("MapShapes") or "{}")
	end)
	if ok and data then
		for _, t in ipairs(data.t or {}) do
			flatPart(model, CFrame.new(t[1], 0, t[2]) * CFrame.Angles(0, math.rad(t[5]), 0), t[3], t[4], 0,
				COLORS[t[6]] or COLORS.grass)
		end
		for _, b in ipairs(data.b or {}) do
			flatPart(model, CFrame.new(b[1], 0, b[2]) * CFrame.Angles(0, math.rad(b[5]), 0), b[3], b[4], 0.6,
				COLORS.building)
		end
	end
	local drawn = {}
	for i, edges in pairs(RoadGraph.Edges) do
		for j in pairs(edges) do
			local key = i < j and (i .. ":" .. j) or (j .. ":" .. i)
			if not drawn[key] then
				drawn[key] = true
				segment(model, RoadGraph.Nodes[i], RoadGraph.Nodes[j], math.max(RoadGraph.Width(i, j) * 0.8, 20), 0.3,
					COLORS.road)
			end
		end
	end
	model.Parent = view
	-- Culling list: only parts near the player stay in the ViewportFrame (see cull()).
	for _, p in ipairs(model:GetChildren()) do
		table.insert(staticParts, { part = p, pos = p.Position, r = math.max(p.Size.X, p.Size.Z) / 2 * 1.42 })
	end
	mapModel = model
end

-- A ViewportFrame redraws every part it holds whenever the camera moves, so keep only what's close.
-- The map is wider than tall and looks further ahead than behind: its far corners are ~2 radii away
-- when zoomed out, plus a margin for a second of driving between culls.
local CULL = FAR_RADIUS * 2.5
local function cull(pos)
	if not mapModel then
		return
	end
	local flat = Vector3.new(pos.X, 0, pos.Z)
	for _, rec in ipairs(staticParts) do
		local d = (Vector3.new(rec.pos.X, 0, rec.pos.Z) - flat).Magnitude - rec.r
		local want = d < CULL and mapModel or nil
		if rec.part.Parent ~= want then
			rec.part.Parent = want
		end
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Minimap"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- zone coordinates: y = 0 is the very top of the screen
	gui.Parent = player:WaitForChild("PlayerGui")

	view = Instance.new("ViewportFrame")
	view.Name = "Map"
	view.BackgroundColor3 = COLORS.water -- past the land: sea
	view.BorderSizePixel = 0
	view.Ambient = Color3.fromRGB(165, 165, 165)
	view.LightColor = Color3.fromRGB(90, 90, 90)
	view.LightDirection = Vector3.new(0, -1, 0)
	view.Parent = gui
	Theme.Corners(view)
	cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = view
	view.CurrentCamera = cam
	routeModel = Instance.new("Model")
	routeModel.Name = "Route"
	routeModel.Parent = view

	-- Blips, your arrow, the N and the thin frame sit on top in a same-sized frame.
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Parent = gui
	Theme.Corners(overlay)
	frameStroke = Instance.new("UIStroke")
	frameStroke.Name = "Frame"
	frameStroke.Color = DARK
	frameStroke.Thickness = 2
	frameStroke.Transparency = 0.1
	frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frameStroke.Parent = overlay

	arrow = Instance.new("TextLabel")
	arrow.Name = "You"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.FontFace = Theme.Font.Bold
	arrow.TextScaled = true
	arrow.Text = "▲"
	arrow.TextColor3 = C.Text
	arrow.ZIndex = 20
	arrow.Parent = overlay
	local st = Instance.new("UIStroke")
	st.Color = DARK
	st.Thickness = 1.5
	st.Parent = arrow

	north = Instance.new("TextLabel")
	north.Name = "North"
	north.AnchorPoint = Vector2.new(0.5, 0.5)
	north.Size = UDim2.fromOffset(18, 18)
	north.BackgroundColor3 = DARK
	north.BackgroundTransparency = 0.15
	north.BorderSizePixel = 0
	north.FontFace = Theme.Font.Bold
	north.TextSize = 13
	north.TextColor3 = C.Text
	north.Text = "N"
	north.ZIndex = 15
	north.Parent = overlay
	local nc = Instance.new("UICorner")
	nc.CornerRadius = UDim.new(0.5, 0)
	nc.Parent = north

	-- Chase arrows: their own full-screen layer (the minimap's gui is just the map's corner).
	chaseGui = Instance.new("ScreenGui")
	chaseGui.Name = "ChaseArrows"
	chaseGui.ResetOnSpawn = false
	chaseGui.IgnoreGuiInset = true -- the whole screen, like the camera's view
	chaseGui.Parent = gui.Parent
	for i = 1, MAX_ARROWS do
		local a = Instance.new("TextLabel")
		a.Name = "CopArrow" .. i
		a.AnchorPoint = Vector2.new(0.5, 0.5)
		a.BackgroundTransparency = 1
		a.FontFace = Theme.Font.Bold
		a.TextScaled = true
		a.Text = "▲"
		a.TextColor3 = RED
		a.Visible = false
		a.Parent = chaseGui
		local s = Instance.new("UIStroke")
		s.Color = C.Shadow
		s.Thickness = 1.5
		s.Transparency = 0.3
		s.Parent = a
		copArrows[i] = a
	end
end

-- Into the Minimap zone for this screen (PC: bottom-left; phone: top-left, smaller).
local function fit()
	local touch = Theme.IsTouch()
	Theme.Place(view, "Minimap", touch)
	Theme.Place(overlay, "Minimap", touch)
	local screen = screenSize()
	local _, _, w, h = zoneBox("Minimap", touch, screen)
	mapW, mapH = math.max(w, 1), math.max(h, 1)
	local a = touch and 12 or 14
	arrow.Size = UDim2.fromOffset(a, a)
	arrow.Position = UDim2.fromScale(0.5, PLAYER_Y)
	arrowSize = math.floor(math.clamp(screen.Y * 0.075, 22, 40)) -- ~29 px on a 390 px-tall phone
end

-- Dark letters on light discs, white letters on dark ones.
local function glyphColor(color)
	local lum = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return lum > 0.5 and DARK or C.Text
end

local function blip(key, pos, text, color, px, edge)
	local b = blips[key]
	if not b then
		local f = Instance.new("TextLabel")
		f.Name = key
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.FontFace = Theme.Font.Bold
		f.TextScaled = true
		f.ZIndex = 10
		f.Parent = overlay
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Color = DARK
		s.Thickness = 1
		s.Transparency = 0.2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
		-- A thin margin, so the letter is as big as the disc allows (~13 px in a 16 px disc).
		local p = Instance.new("UIPadding")
		p.PaddingTop, p.PaddingBottom = UDim.new(0.1, 0), UDim.new(0.1, 0)
		p.PaddingLeft, p.PaddingRight = UDim.new(0.1, 0), UDim.new(0.1, 0)
		p.Parent = f
		b = { frame = f }
		blips[key] = b
	end
	b.frame.Text = text or ""
	b.frame.BackgroundColor3 = color
	b.frame.TextColor3 = glyphColor(color)
	b.frame.Size = UDim2.fromOffset(px, px)
	b.pos = pos
	b.edge = edge -- pin to the edge when off the map (otherwise hide it)
	b.track, b.flash = nil, nil -- callers set these again after this call when they want them
	b.seen = true
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A police car worth showing: an AI patrol, or a police car a player cop is driving right now.
local function isCopCar(car)
	if car:GetAttribute("AIPolice") == true then
		return true
	end
	local driverId = car:GetAttribute("DriverUserId")
	if car:GetAttribute("Police") ~= true or typeof(driverId) ~= "number" then
		return false
	end
	local driver = Players:GetPlayerByUserId(driverId)
	return driver ~= nil and driver:GetAttribute("Side") == "Cop"
end

-- Whether the chase radar shows any cops right now (see the header).
local function radarShowing()
	local mode = ReplicatedStorage:GetAttribute("ChaseRadar") or "On"
	return (player:GetAttribute("Heat") or 0) > 0 and mode ~= "Off"
		and (mode ~= "Seen" or player:GetAttribute("HeatSpotted") == true)
end

local function refreshBlips()
	for _, b in pairs(blips) do
		b.seen = false
	end
	local ok, places = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Places") or "[]")
	end)
	local open = {}
	for id in string.gmatch(ReplicatedStorage:GetAttribute("OpenHeists") or "", "[^,]+") do
		open[id] = true
	end
	local cop = player:GetAttribute("Side") == "Cop"
	for _, p in ipairs(ok and places or {}) do
		local pos = Vector3.new(p.x, 0, p.z)
		if p.c == "Heist" and open[p.id] and not cop then
			blip("h_" .. p.id, pos, "$", C.Gold, 16, false)
		elseif p.n == "Hideout" and not cop then
			blip("hideout", pos, "H", C.Cash, 18, true)
		elseif p.n == "Police HQ" then
			blip("police", pos, "P", C.Police, 16, cop)
		elseif p.n == "Spray & Go" and not cop then
			blip("spray", pos, "S", C.Dim, 16, false)
		elseif p.n == "AutoNeon Motors" then
			blip("autoneon", pos, "A", C.Dim, 16, false)
		elseif p.n == "Marina Boat Sales" then
			blip("boatdealer", pos, "B", C.Dim, 16, false)
		elseif p.n == "Coast Arms" and not cop then
			blip("gunshop", pos, "G", C.Dim, 16, false)
		end
	end
	-- Your home (HouseClient), always pinned to the edge so you can find your way back.
	local okH, HouseClient = pcall(require, script.Parent:FindFirstChild("HouseClient"))
	local homePos = okH and HouseClient and HouseClient.HomePosition()
	if homePos then
		blip("home", homePos, "⌂", C.Text, 18, true)
	end
	-- The goal: the GPS target, or during a race the next checkpoint (its number, a flag at the finish).
	-- GPSClient.MapGoal hides the target while a race line or route preview is up, like the road dots.
	local target, glyph = GPSClient.MapGoal()
	if target then
		blip("gps", target, glyph or "★", C.Gold, 18, true)
	end
	-- Florida moments (EventService): pinned to the edge so you can go find them.
	local okE, events = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Events") or "[]")
	end)
	for i, e in ipairs(okE and events or {}) do
		blip("event_" .. i .. "_" .. e.x .. "_" .. e.z, Vector3.new(e.x, 0, e.z), "!", C.Orange, 16, true)
	end
	-- Crewmates (their position is re-read every frame below).
	local crew = player:GetAttribute("Crew")
	if crew then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p:GetAttribute("Crew") == crew then
				-- Their character when it's streamed in (smooth), else the server's CrewPos (every 1.5 s).
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				local x, z = string.match(p:GetAttribute("CrewPos") or "", "(-?%d+),(-?%d+)")
				local pos = root and root.Position or (x and Vector3.new(tonumber(x), 0, tonumber(z)))
				if pos then
					local okC, first = pcall(function()
						return utf8.char(utf8.codepoint(p.DisplayName, 1))
					end)
					blip("crew_" .. p.UserId, pos, okC and first or "?", C.Purple, 16, true)
					blips["crew_" .. p.UserId].track = root
				end
			end
		end
	end
	-- Police cars while you're wanted: flashing red / blue (RenderStepped), pinned to the edge past the
	-- map's border so you can see which way they are. Their list also feeds the screen arrows.
	table.clear(copParts)
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local vehicles = Workspace:FindFirstChild("Vehicles")
	local seen = player:GetAttribute("HeatSpotted") == true
	if myRoot and vehicles and radarShowing() then
		for _, car in ipairs(vehicles:GetChildren()) do
			local chassis = car:IsA("Model") and car.PrimaryPart
			if chassis and isCopCar(car) and (seen or car:GetAttribute("AIPolice") == true) -- player cops: only while seen
				and flatDistance(chassis.Position, myRoot.Position) <= COP_RANGE then
				if not copKeys[car] then
					copCount += 1
					copKeys[car] = "cop_" .. copCount
				end
				local key = copKeys[car]
				blip(key, chassis.Position, "", RED, 10, true)
				blips[key].track = chassis
				blips[key].flash = true
				table.insert(copParts, chassis)
			end
		end
	end
	for key, b in pairs(blips) do
		if not b.seen then
			b.frame:Destroy()
			blips[key] = nil
		end
	end
end

-- The GPS re-plans every second with a fresh table; only redraw when the route itself changed
-- (ignoring the first point, which is just where you're standing).
local function refreshRoute()
	local points = GPSClient.RoutePoints()
	local stamp = "none"
	if points then
		stamp = #points .. "|" .. tostring(points[2]) .. "|" .. tostring(points[#points]) .. "|" .. tostring(GPSClient.RouteColor())
	end
	if stamp == routeStamp then
		return
	end
	routeStamp = stamp
	routeModel:ClearAllChildren()
	if points then
		for i = 2, #points - 1 do
			segment(routeModel, points[i], points[i + 1], 12, 1.2, GPSClient.RouteColor() or COLORS.route)
		end
	end
end

-- Slides a point (map pixels from its top-left) back along the line from your arrow until it is `inset`
-- pixels inside the map. Returns x, y, and whether it was inside already.
local function pin(x, y, inset)
	local ax, ay = mapW / 2, mapH * PLAYER_Y
	local dx, dy = x - ax, y - ay
	local t = 1
	if dx > 0 then
		t = math.min(t, (mapW - inset - ax) / dx)
	elseif dx < 0 then
		t = math.min(t, (inset - ax) / dx)
	end
	if dy > 0 then
		t = math.min(t, (mapH - inset - ay) / dy)
	elseif dy < 0 then
		t = math.min(t, (inset - ay) / dy)
	end
	return ax + dx * t, ay + dy * t, t >= 1
end

-- Chase arrows ---------------------------------------------------------------------------------

local function findKeepOuts()
	table.clear(keepOut)
	table.clear(cardStacks)
	local playerGui = player:FindFirstChild("PlayerGui")
	local function find(path, into)
		local obj = playerGui
		for _, name in ipairs(path) do
			obj = obj and obj:FindFirstChild(name)
		end
		if obj and obj:IsA("GuiObject") then
			table.insert(into, obj)
		end
	end
	for _, path in ipairs(KEEP_OUT) do
		find(path, keepOut)
	end
	for _, path in ipairs(CARD_STACKS) do
		find(path, cardStacks)
	end
end

-- On screen right now: it and every frame above it visible, inside an enabled ScreenGui.
local function guiShown(obj)
	local o = obj
	while o and o:IsA("GuiObject") do
		if not o.Visible then
			return false
		end
		o = o.Parent
	end
	return o ~= nil and o:IsA("ScreenGui") and o.Enabled
end

-- Screen boxes { x0, y0, x1, y1 } the arrows must stay out of, in the arrows' own pixels: the HUD zones
-- (from the Theme, the arrows' ScreenGui is full-screen like every HUD gui), the keep-out pieces and the
-- toast / feed cards showing now, and on phones the thumb's corner. AbsolutePosition starts under the top
-- bar whatever a ScreenGui's IgnoreGuiInset says, so pieces are measured from the arrows' ScreenGui
-- corner (as InteractClient does): right whichever way Roblox counts it.
local function keepOutBoxes(screen)
	local boxes = {}
	local touch = Theme.IsTouch()
	for _, name in ipairs(KEEP_OUT_ZONES) do
		local x, y, w, h = zoneBox(name, touch, screen)
		if w > 0 and h > 0 then
			table.insert(boxes, { x, y, x + w, y + h })
		end
	end
	if touch then
		table.insert(boxes, { 0, screen.Y * 0.5, math.min(screen.X * THUMB_SHARE, THUMB_MAX), screen.Y })
	end
	local origin = chaseGui.AbsolutePosition
	local function add(obj)
		local pos, sz = obj.AbsolutePosition - origin, obj.AbsoluteSize
		if sz.X > 0 and sz.Y > 0 then
			table.insert(boxes, { pos.X, pos.Y, pos.X + sz.X, pos.Y + sz.Y })
		end
	end
	for _, obj in ipairs(keepOut) do
		if obj.Parent and guiShown(obj) then
			add(obj)
		end
	end
	for _, stack in ipairs(cardStacks) do
		if stack.Parent and guiShown(stack) then
			for _, card in ipairs(stack:GetChildren()) do
				if card:IsA("GuiObject") and card.Visible then
					add(card)
				end
			end
		end
	end
	return boxes
end

local function hitsBox(boxes, x, y, half)
	for _, b in ipairs(boxes) do
		if x + half > b[1] and x - half < b[3] and y + half > b[2] and y - half < b[4] then
			return true
		end
	end
	return false
end

-- Up to MAX_ARROWS arrows for the nearest police cars within ARROW_RANGE that the camera can't see.
-- They sit on a ring round the middle of the screen: up = ahead of the camera, down = behind you,
-- measured from your character so a car right behind you reads as "behind" even in a chase cam.
local function placeArrows(root, flashRed)
	local shown = 0
	local camera = Workspace.CurrentCamera
	if #copParts > 0 and radarShowing() and gui.Enabled then
		local near = {}
		for _, part in ipairs(copParts) do
			if part.Parent then
				local d = flatDistance(part.Position, root.Position)
				if d <= ARROW_RANGE then
					local _, visible = camera:WorldToViewportPoint(part.Position)
					if not visible then
						table.insert(near, { part = part, d = d })
					end
				end
			end
		end
		if #near > 0 then
			table.sort(near, function(a, b)
				return a.d < b.d
			end)
			local vp = chaseGui.AbsoluteSize -- the same pixels as the boxes and the arrows
			if vp.X < 1 or vp.Y < 1 then
				vp = camera.ViewportSize
			end
			local boxes = keepOutBoxes(vp)
			local cx, cy = vp.X / 2, vp.Y / 2
			local rx, ry = math.min(vp.X * 0.36, vp.Y * 0.95), vp.Y * 0.34
			local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude < 0.01 then
				look = camera.CFrame.UpVector * Vector3.new(1, 0, 1) -- camera straight down: its top is "ahead"
			end
			look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
			local right = Vector3.new(-look.Z, 0, look.X)
			for _, c in ipairs(near) do
				if shown >= MAX_ARROWS then
					break
				end
				local rel = c.part.Position - root.Position
				local angle = math.atan2(rel:Dot(right), rel:Dot(look)) -- 0 = ahead, + = to the right
				local px = math.floor(arrowSize * (1.2 - 0.4 * math.clamp(c.d / ARROW_RANGE, 0, 1))) -- nearer = bigger
				local half = px / 2 + 6
				local x, y
				for _, turn in ipairs(SLIDE_ANGLES) do
					local a = angle + math.rad(turn)
					for _, f in ipairs(SLIDE_RADII) do
						local tx, ty = cx + math.sin(a) * rx * f, cy - math.cos(a) * ry * f
						if not hitsBox(boxes, tx, ty, half) then
							x, y = tx, ty
							break
						end
					end
					if x then
						break
					end
				end
				if x then -- no free spot: better no arrow than one over the pedals
					shown += 1
					local arrowLabel = copArrows[shown]
					arrowLabel.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
					arrowLabel.Size = UDim2.fromOffset(px, px)
					arrowLabel.Rotation = math.deg(angle) -- always points the true way, even after sliding
					arrowLabel.TextColor3 = flashRed and RED or BLUE
					arrowLabel.Visible = true
					table.insert(boxes, { x - half, y - half, x + half, y + half }) -- arrows don't pile up
				end
			end
		end
	end
	for i = shown + 1, MAX_ARROWS do
		copArrows[i].Visible = false
	end
end

-- (see the header) The map's box in pixels from the Minimap gui's top-left.
function MinimapClient.Rect()
	local x, y, w, h = zoneBox("Minimap", Theme.IsTouch(), screenSize())
	return math.floor(x), math.floor(y), math.floor(w), math.floor(h)
end

-- (see the header) The first free y on the right edge, under the top-right HUD zones.
function MinimapClient.Bottom()
	local screen = screenSize()
	local touch = Theme.IsTouch()
	local bottom = 0
	for _, name in ipairs({ "Status", "Pills", "Buttons" }) do
		local _, y, _, h = zoneBox(name, touch, screen)
		bottom = math.max(bottom, y + h)
	end
	return math.floor(bottom + 0.5)
end

function MinimapClient.Init()
	build()
	fit()
	-- Re-place when the screen size or the kind of device changes (rotating a phone, resizing the
	-- window, plugging a mouse into a tablet).
	local camConn
	local function watchCamera()
		if camConn then
			camConn:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		if camera then
			camConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		end
		fit()
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(fit)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(fit)
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				break
			end
			task.wait(1)
		end
		buildStatic()
	end)
	local lastBlips = 0
	local camAcc = 0
	-- Cop blips and arrows follow the heat, a sighting and the radar mode on the next frame, not up
	-- to a second later (0 = refresh now).
	for _, name in ipairs({ "Heat", "HeatSpotted" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			lastBlips = 0
		end)
	end
	ReplicatedStorage:GetAttributeChangedSignal("ChaseRadar"):Connect(function()
		lastBlips = 0
	end)
	RunService.RenderStepped:Connect(function(dt)
		-- Off in prison and on the first-join title screen (TeamUI switches HUD layers off then, and
		-- this would switch them straight back on).
		local show = player:GetAttribute("Side") ~= "Prisoner" and player:GetAttribute("TitleScreen") ~= true
		gui.Enabled = show
		chaseGui.Enabled = show
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			for _, a in ipairs(copArrows) do
				a.Visible = false
			end
			return
		end
		local pos = root.Position
		-- Police lights: the frame flashes one colour while cop blips and arrows show the other.
		local flashRed = os.clock() % 0.6 < 0.3
		local look = Workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
		look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
		local right = Vector3.new(-look.Z, 0, look.X)
		-- Zoom out with speed.
		local speed = root.AssemblyLinearVelocity.Magnitude
		local want = NEAR_RADIUS + (FAR_RADIUS - NEAR_RADIUS) * math.clamp(speed / 150, 0, 1)
		radius += (want - radius) * math.clamp(dt * 2, 0, 1)
		local height = radius / math.tan(math.rad(FOV / 2))
		-- The camera films the point a little ahead of you, so your arrow sits below the middle.
		local centre = Vector3.new(pos.X, 0, pos.Z) + look * ((PLAYER_Y - 0.5) * 2 * radius)
		-- The map camera redraws the whole viewport, so move it at most 30 times a second.
		camAcc += dt
		if camAcc >= 1 / 30 then
			camAcc = 0
			cam.CFrame = CFrame.lookAt(centre + Vector3.new(0, height, 0), centre, look)
		end
		-- Arrow: where your character (or car) faces, relative to the view.
		local face = root.CFrame.LookVector
		arrow.Rotation = math.deg(math.atan2(face:Dot(right), face:Dot(look)))
		-- Blips: same maths as the camera (up = look, right = right), from the map's middle.
		local pxPerStud = (mapH / 2) / radius
		local midX, midY = mapW / 2, mapH / 2
		for _, b in pairs(blips) do
			if b.track and b.track.Parent then
				b.pos = b.track.Position
			end
			local rel = b.pos - centre
			local x, y = midX + rel:Dot(right) * pxPerStud, midY - rel:Dot(look) * pxPerStud
			local px, py, inside = pin(x, y, EDGE)
			if inside then
				b.frame.Visible = true
			else
				b.frame.Visible = b.edge == true
				x, y = px, py
			end
			b.frame.Position = UDim2.fromOffset(x, y)
			if b.flash then
				b.frame.BackgroundColor3 = flashRed and BLUE or RED
			end
		end
		-- N: north's direction from your arrow, on the edge.
		local nx, ny = pin(mapW / 2 + NORTH:Dot(right) * 10000, mapH * PLAYER_Y - NORTH:Dot(look) * 10000, 10)
		north.Position = UDim2.fromOffset(nx, ny)
		if os.clock() - lastBlips > 1 then
			lastBlips = os.clock()
			refreshBlips()
			refreshRoute()
			cull(pos)
			findKeepOuts()
		end
		-- Wanted: the thin frame flashes red and blue.
		if (player:GetAttribute("Heat") or 0) > 0 then
			frameStroke.Color = flashRed and RED or BLUE
			frameStroke.Transparency = 0
		else
			frameStroke.Color = DARK
			frameStroke.Transparency = 0.1
		end
		placeArrows(root, not flashRed)
	end)
end

return MinimapClient
