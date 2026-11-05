-- MapClient (ModuleScript, StarterPlayerScripts.Controllers.MapClient)
-- The big map: the whole city on one screen, to see where everything is and point the GPS anywhere.
-- Opening it: tap or click the minimap (MinimapClient.OnTap), or press M on a keyboard. Never in prison,
-- on the first-join title screen (player attribute TitleScreen), with Roblox's menu up or without a
-- living character. (No gamepad button: every free one is taken or belongs to Roblox.)
-- Look ("street" HUD, Shared.Util.Theme): a full-screen layer (ScreenGui "BigMap", DisplayOrder 11: over
-- the HUD, the phone (5), the cards (6-10) and the title screen's layer, under the weapon wheel (12) and
-- the toasts (20)) with a dark backdrop, and the city in its own ViewportFrame ("Map", small corners and
-- a thin dark frame) filling the screen less a small margin (on a PC it starts under Roblox's top bar;
-- on a phone only the top bar's corner buttons sit over its top-left corner). The city is a copy of the
-- minimap's flat parts (MinimapClient.BuildMap: the same ground, buildings, roads, colours and light),
-- built the first time the map opens, not at join (and again next time if the data wasn't all in yet).
-- North is up (-Z, CityGen): screen x grows east (+X), screen y grows south (+Z). The camera looks
-- straight down and never turns (K.FOV, wider than the minimap's 20: the parts are all within 1.2
-- studs of the ground, so there is still no parallax to speak of, and the whole city fits with the
-- camera about 5,700 studs up rather than 12,000). It opens showing the whole city.
-- Zoom and pan: the mouse wheel (about the cursor), the + / − buttons (about the middle; from the whole
-- city, about you) and a two-finger pinch (about the fingers), between the whole city and K.MAX_ZOOM
-- times closer. Drag with the mouse or one finger to move the map; it never leaves the city. A press
-- that moves less than K.TAP_SLOP pixels (and never had a second finger) is a tap; anything more is a
-- drag and never drops a waypoint.
-- On top, as 2D labels placed with the camera's own maths (layout):
--   * you: the white ▲, turned to where you face;
--   * other players: the minimap's rules (MinimapClient.PlayerKind: prisoners and players inside a home
--     never show; a cop doesn't see wanted players; a wanted player doesn't see player cops; crewmates
--     always), as K.PLAYER px discs with their first initial: purple crewmates, police blue player cops,
--     white everyone else. Their character while it's streamed in, else the server's MapPos / CrewPos;
--   * places (ReplicatedStorage "Places", with the minimap's letters and colours where it has them):
--     Hideout H green, Police HQ P blue, shops and services grey (Spray & Go S, Chop Shop C, AutoNeon A,
--     Marina Boat Sales B, Coast Arms G, apartment towers T, homes for sale ⌂), heists $ (gold while
--     open, small and grey while shut), things to do in cyan (races R, stunt jumps J, Drift Zone D, Taxi
--     Stand T, Car Meet M, Courier Depot C), your home ⌂ white (HouseClient.HomePosition), Florida
--     moments ! orange (ReplicatedStorage "Events") and player businesses in their own letter and colour
--     (BusinessClient.MapBlips: a gold ring on yours, flashing red during a break-in you should answer). As on the minimap a cop never sees the heists, the
--     Hideout, Spray & Go, Coast Arms (nor the Chop Shop). Each place's name sits beside its blip on a
--     small dark pill: the main places' (K.PLACES, open heists, your home, Florida moments) at every
--     zoom, the rest from K.NAMES_AT times closer, never on top of another name nor off the map;
--   * the GPS: its route as a line (GPSClient.RoutePoints: gold, or a race line in its own colour), its
--     goal (GPSClient.MapGoal: the ★, or during a race the next checkpoint) and, during a race, the
--     waypoint kept for after it as a faded ★; and a readout at the top: ★ WHERE  distance.
-- Setting the GPS: tap a place's blip or its name and the GPS routes there by name (GPSClient.SetTarget(
-- place name, position), like the phone's GPS app); tap anywhere else for a "Waypoint" ★ there. Every
-- position is y = 0, like every other caller: GPSClient stands its pillar on the ground by itself. The
-- hint line says so in gold and the map closes K.CLOSE_AFTER seconds later so you can drive (touching
-- the map again before that keeps it open). A waypoint is a GPS target, never a teleport. During a race
-- (GPSClient.PathName) the race line wins, as GPSClient's header says: the target is kept for after the
-- race, the hint says so and a toast too. CLEAR ROUTE (top right, while there is a target) drops it.
-- Closing: the X (top right; Theme.Touch pixels on phones), M again, or by itself: prison, the title
-- screen, death or a new character, or the phone coming up. (Esc is Roblox's own menu: not used here.)
-- Input while it is up: the backdrop is a Modal button, so a tap or click always lands on the map, never
-- on a HUD button or the world under it, and the mouse is free in first person and shift lock;
-- CombatClient counts it as a panel (MapClient.IsOpen): no shots or punches, a gun is lowered, the weapon
-- wheel stays shut. The mouse wheel is taken at a higher priority than Roblox's camera
-- (ContextActionService K.PRIORITY), so the camera behind doesn't zoom; that binding goes when it shuts.
-- Keys keep working (you can still drive with it up). Opening it puts the phone and the weapon wheel away.
-- Performance (phones first): the city's parts are built once; the map camera only moves on a pan or a
-- zoom (a ViewportFrame redraws whenever its camera moves), at most once per K.CAM_EVERY; the blips
-- refresh every K.BLIPS_EVERY (places every K.PLACES_EVERY); nothing runs while it is shut (its
-- RenderStepped is only connected while it is up).
-- API: MapClient.Open(), MapClient.Close(), MapClient.Toggle(), MapClient.IsOpen() (CombatClient asks).
-- Names other code and the Studio test tools may use: ScreenGui "BigMap" > "Backdrop", "Map" (the
-- ViewportFrame), "Overlay" (blips, names, the route, "You"), "Input" (takes the presses on the map) >
-- "Close", "ZoomIn", "ZoomOut", "Clear", "Title", "Hint".

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local RobloxMenu = require(ReplicatedStorage.Shared.Util.RobloxMenu)
local MinimapClient = require(script.Parent:WaitForChild("MinimapClient"))
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local MapClient = {}

local C = Theme.Color
local DARK = C.Panel
local NORTH = Vector3.new(0, 0, -1)

-- Every number the map is built from.
local K = {
	KEY = Enum.KeyCode.M, -- opens and shuts it (keyboard)
	DISPLAY_ORDER = 11, -- see the header
	FOV = 40, -- the map camera's field of view (degrees, vertical)
	MARGIN = 0.04, -- share of the city's size left round it at the whole-city view
	MAX_ZOOM = 4, -- how much closer than the whole city it may get
	WHEEL_STEP = 1.25, -- zoom per mouse-wheel notch
	BUTTON_STEP = 1.6, -- ...per + / − press
	TAP_SLOP = 8, -- pixels a press may move and still be a tap
	TAP_REACH = 8, -- pixels past a blip's edge that still count as tapping it (mouse)
	TAP_REACH_TOUCH = 14, -- ...(finger)
	CAM_EVERY = 1 / 30, -- seconds between two moves of the map camera at most
	BLIPS_EVERY = 0.1, -- seconds between blip refreshes while it is up
	PLACES_EVERY = 1, -- ...of the places, your home and the Florida moments
	CLOSE_AFTER = 0.6, -- seconds after setting the GPS before it shuts
	HINT_HOLD = 2, -- seconds the gold "GPS set" line stays (if the map stays up)
	NAMES_AT = 1.8, -- from this many times closer than the whole city every place's name shows
	PLAYER = 14, -- pixels: other players' discs
	YOU = 18, -- ...your arrow (16 on phones)
	NAME_PX = 12, -- text size of a place's name
	ROUTE_PX = 4, -- the GPS line's width
	LOOK_ACTION = "NC_BigMapLook", -- ContextActionService: the mouse wheel, while it is up
	PRIORITY = 4000, -- over Roblox's camera input (2000) and our own bindings (3000)
	-- Places with their own blip (the minimap's choices): glyph, colour, size, hidden from cops.
	PLACES = {
		["Hideout"] = { "H", C.Cash, 18, true },
		["Police HQ"] = { "P", C.Police, 16, false },
		["Spray & Go"] = { "S", C.Dim, 16, true },
		["Chop Shop"] = { "C", C.Dim, 16, true },
		["AutoNeon Motors"] = { "A", C.Dim, 16, false },
		["Marina Boat Sales"] = { "B", C.Dim, 16, false },
		["Coast Arms"] = { "G", C.Dim, 16, true },
	},
	ACTIVITY = { ["Drift Zone"] = "D", ["Taxi Stand"] = "T", ["Car Meet"] = "M", ["Courier Depot"] = "C" },
	EVENTS = { GatorVisit = "Gator on the loose", BeachTreasure = "Beach treasure", UFO = "UFO sighting" },
	PLAYER_COLORS = { crew = C.Purple, cop = C.Police, player = C.Text },
}

-- Every GUI object (build): gui, back, view, cam, overlay, input, controls, you, close, zoomIn, zoomOut,
-- clear, title, hint; and model (the city's parts, once built).
local ui = {}
-- What the map is doing.
local S = {
	open = false,
	built = false, -- the city's parts are in, and complete (shapes and roads)
	box = nil, -- { minX, maxX, minZ, maxZ }: the land, in studs (MinimapClient.BuildMap)
	vw = 1, vh = 1, -- the map's size in pixels (place)
	touch = false, -- the phone layout is in use (place)
	cx = 0, cz = 0, span = 1000, -- what the camera should show: its middle, and studs from there to the top edge
	ax = 0, az = 0, aspan = 1000, -- what it shows now (applyCamera): blips are placed from these
	dirty = false, -- the camera should move
	camAt = 0, blipsAt = 0, placesAt = 0,
	conn = nil, -- RenderStepped, while it is up
	pointers = {}, -- [touch InputObject or "mouse"] = { start, last, now } (Vector2, map pixels)
	count = 0, -- pointers down on the map now
	moved = 0, -- the most pixels one of them has moved this press
	multi = false, -- a second finger joined this press: it isn't a tap
	pinch = nil, -- { a, b (pointer keys), dist, span, anchor (Vector3 under the fingers' middle) }
	closing = nil, -- the token of a pending close after setting the GPS
	hintUntil = 0, -- the gold "GPS set" line stays until then
	shownTitle = nil, shownHint = nil,
	placesRaw = nil, places = {}, -- the Places JSON last read, and its list
	lazy = {}, -- [name] = another controller's module (false if missing)
}
local blips = {} -- [key] = { frame, group ("place" | "live"), pos, px, track, go, main, order, label, labelW, x, y, on, box, seen }
local routeBits = {} -- the GPS line's pieces (a pool of thin frames)

------------------------------------------------------------------ helpers

-- Another controller's module, or nil if it isn't there (never an error).
local function other(name)
	local m = S.lazy[name]
	if m == nil then
		local ok, res = pcall(require, script.Parent:FindFirstChild(name))
		m = (ok and type(res) == "table") and res or false
		S.lazy[name] = m
	end
	return m or nil
end

-- Call another controller's function; a missing controller or function, or an error, gives nil.
local function ask(name, fn, ...)
	local m = other(name)
	local f = m and m[fn]
	if type(f) ~= "function" then
		return nil
	end
	local ok, res = pcall(f, ...)
	return ok and res or nil
end

local function sound(name)
	ask("SoundClient", "Play", name)
end

local function myRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- Dark letters on light discs, white letters on dark ones (as on the minimap).
local function glyphColor(color)
	local lum = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return lum > 0.5 and DARK or C.Text
end

local function firstLetter(s)
	local ok, ch = pcall(function()
		return utf8.char(utf8.codepoint(s, 1))
	end)
	return ok and string.upper(ch) or "?"
end

-- For RichText: the five characters it reads as markup.
local function escape(s)
	return (string.gsub(s, "[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }))
end

-- May the map NOT be up right now? (Opening also waits for Roblox's menu to shut.)
local function blocked()
	if player:GetAttribute("Side") == "Prisoner" or player:GetAttribute("TitleScreen") == true then
		return true
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return not hum or hum.Health <= 0 or not myRoot()
end

local function screenSize()
	local size = ui.gui and ui.gui.AbsoluteSize
	if size and size.X > 1 and size.Y > 1 then
		return size
	end
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(844, 390)
end

------------------------------------------------------------------ the camera

-- The whole-city span (studs from the middle to the top edge that fit all the land in) and the closest.
local function spanLimits()
	local box = S.box
	local aspect = S.vw / math.max(S.vh, 1)
	local fit = math.max((box.maxZ - box.minZ) / 2, (box.maxX - box.minX) / 2 / aspect) * (1 + K.MARGIN)
	fit = math.max(fit, 50)
	return fit, fit / K.MAX_ZOOM
end

-- Keep the wanted view inside the city: the zoom within its limits, and the middle where no edge of the
-- view goes past the land (plus the margin). A view wider than the land is centred on it.
local function clampView()
	local maxSpan, minSpan = spanLimits()
	S.span = math.clamp(S.span, minSpan, maxSpan)
	local halfH = S.span
	local halfW = S.span * S.vw / math.max(S.vh, 1)
	local box = S.box
	local mx = (box.maxX - box.minX) * K.MARGIN / 2
	local mz = (box.maxZ - box.minZ) * K.MARGIN / 2
	local function axis(v, lo, hi, half)
		lo, hi = lo + half, hi - half
		if lo >= hi then
			return (lo + hi) / 2
		end
		return math.clamp(v, lo, hi)
	end
	S.cx = axis(S.cx, box.minX - mx, box.maxX + mx, halfW)
	S.cz = axis(S.cz, box.minZ - mz, box.maxZ + mz, halfH)
	S.dirty = true
end

-- Move the map camera to the wanted view (straight down, north up). Blips follow in layout.
local function applyCamera()
	S.dirty = false
	S.camAt = os.clock()
	S.ax, S.az, S.aspan = S.cx, S.cz, S.span
	local height = S.span / math.tan(math.rad(K.FOV / 2))
	local middle = Vector3.new(S.cx, 0, S.cz)
	ui.cam.CFrame = CFrame.lookAt(middle + Vector3.new(0, height, 0), middle, NORTH)
end

-- Map pixels (from the map's top-left) -> the ground there, for the view on screen now.
local function toWorld(x, y)
	local pps = S.vh / 2 / S.aspan
	return Vector3.new(S.ax + (x - S.vw / 2) / pps, 0, S.az + (y - S.vh / 2) / pps)
end

-- Zoom the wanted view by `factor` (> 1 = closer) keeping the ground under map pixel (x, y) where it is.
local function zoomAt(x, y, factor)
	local pps = S.vh / 2 / S.span
	local wx = S.cx + (x - S.vw / 2) / pps
	local wz = S.cz + (y - S.vh / 2) / pps
	local maxSpan, minSpan = spanLimits()
	S.span = math.clamp(S.span / factor, minSpan, maxSpan)
	pps = S.vh / 2 / S.span
	S.cx = wx - (x - S.vw / 2) / pps
	S.cz = wz - (y - S.vh / 2) / pps
	clampView()
end

------------------------------------------------------------------ blips

local function blip(key, group, pos, glyph, color, px, opts)
	local b = blips[key]
	if not b then
		local f = Instance.new("TextLabel")
		f.Name = key
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.FontFace = Theme.Font.Bold
		f.TextScaled = true
		f.Parent = ui.overlay
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = DARK
		stroke.Thickness = 1
		stroke.Transparency = 0.2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = f
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.1, 0), UDim.new(0.1, 0)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0.1, 0), UDim.new(0.1, 0)
		pad.Parent = f
		b = { frame = f, group = group }
		blips[key] = b
	end
	local f = b.frame
	if f.Text ~= glyph then
		f.Text = glyph
	end
	f.BackgroundColor3 = color
	f.TextColor3 = glyphColor(color)
	f.BackgroundTransparency = opts.faded and 0.45 or 0
	f.TextTransparency = opts.faded and 0.3 or 0
	f.Size = UDim2.fromOffset(px, px)
	f.ZIndex = opts.z or 5
	b.pos, b.px = pos, px
	b.track = opts.track
	b.go = opts.go -- { name, pos }: a tap on it points the GPS there
	b.main = opts.main == true
	b.order = opts.order or 0
	if opts.name then
		if not b.label then
			local l = Instance.new("TextLabel")
			l.Name = "Name"
			l.AnchorPoint = Vector2.new(0, 0.5)
			l.BackgroundColor3 = DARK
			l.BackgroundTransparency = 0.3
			l.BorderSizePixel = 0
			l.FontFace = Theme.Font.Bold
			l.TextSize = K.NAME_PX
			l.TextColor3 = C.Text
			l.AutomaticSize = Enum.AutomaticSize.X
			l.Size = UDim2.fromOffset(0, K.NAME_PX + 6)
			l.ZIndex = 3
			l.Visible = false
			Theme.Corners(l, 3)
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
			pad.Parent = l
			l.Parent = ui.overlay
			b.label = l
		end
		if b.label.Text ~= opts.name then
			b.label.Text = opts.name
			b.labelW = (utf8.len(opts.name) or #opts.name) * K.NAME_PX * 0.62 -- (a guess until it has been drawn)
		end
	elseif b.label then
		b.label:Destroy()
		b.label = nil
	end
	b.seen = true
	return b
end

local function markGroup(group)
	for _, b in pairs(blips) do
		if b.group == group then
			b.seen = false
		end
	end
end

local function sweepGroup(group)
	for key, b in pairs(blips) do
		if b.group == group and not b.seen then
			b.frame:Destroy()
			if b.label then
				b.label:Destroy()
			end
			blips[key] = nil
		end
	end
end

-- How one Places entry shows (see the header): glyph, colour, size, main (its name shows at every zoom);
-- nil = not on your map.
local function placeLook(p, cop, open)
	if p.c == "Business" then
		return nil -- (drawn by refreshLive from BusinessClient.MapBlips: a ring on yours, a flashing break-in)
	end
	if p.c == "Heist" then
		if cop then
			return nil
		end
		if open[tostring(p.id)] then
			return "$", C.Gold, 16, true
		end
		return "$", C.Dim, 12, false
	end
	local fixed = K.PLACES[p.n]
	if fixed then
		if fixed[4] and cop then
			return nil
		end
		return fixed[1], fixed[2], fixed[3], true
	end
	if p.c == "Activity" then
		local glyph = K.ACTIVITY[p.n]
		if p.g == "Race" or p.g == "BoatRace" then
			glyph = "R"
		elseif p.g == "Stunt" then
			glyph = "J"
		end
		return glyph or firstLetter(p.n), C.BrandAlt, 14, false
	end
	local kind = type(p.k) == "string" and p.k or ""
	if string.find(kind, "Home for sale", 1, true) then
		return "⌂", C.Dim, 14, false
	elseif string.find(kind, "Penthouse", 1, true) then
		return "T", C.Dim, 14, false
	end
	return firstLetter(p.n), C.Dim, 14, false
end

-- The places, your home and the Florida moments (once a second: they hardly ever change).
local function refreshPlaces()
	markGroup("place")
	local raw = ReplicatedStorage:GetAttribute("Places")
	if raw ~= S.placesRaw then
		S.placesRaw = raw
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw or "[]")
		end)
		S.places = (ok and type(list) == "table") and list or {}
	end
	local open = {}
	for id in string.gmatch(ReplicatedStorage:GetAttribute("OpenHeists") or "", "[^,]+") do
		open[id] = true
	end
	local cop = player:GetAttribute("Side") == "Cop"
	local homeName = ask("HouseClient", "HomeName")
	for i, p in ipairs(S.places) do
		if type(p) == "table" and type(p.n) == "string" and type(p.x) == "number" and type(p.z) == "number"
			and p.n ~= homeName then -- (your own home is the white ⌂ below)
			local glyph, color, px, main = placeLook(p, cop, open)
			if glyph then
				local pos = Vector3.new(p.x, 0, p.z)
				blip("p" .. i .. "_" .. p.n, "place", pos, glyph, color, px,
					{ z = px <= 12 and 4 or 5, go = { p.n, pos }, main = main, order = i, name = p.n })
			end
		end
	end
	local homePos = ask("HouseClient", "HomePosition")
	if typeof(homePos) == "Vector3" then
		local pos = Vector3.new(homePos.X, 0, homePos.Z)
		blip("home", "place", pos, "⌂", C.Text, 18, { z = 5, go = { "Home", pos }, main = true, order = 0, name = "Home" })
	end
	local okE, events = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Events") or "[]")
	end)
	for i, e in ipairs(okE and type(events) == "table" and events or {}) do
		if type(e) == "table" and type(e.x) == "number" and type(e.z) == "number" then
			local name = K.EVENTS[e.n] or "Florida moment"
			local pos = Vector3.new(e.x, 0, e.z)
			blip("event_" .. i .. "_" .. e.x .. "_" .. e.z, "place", pos, "!", C.Orange, 16,
				{ z = 5, go = { name, pos }, main = true, order = -1, name = name })
		end
	end
	sweepGroup("place")
end

-- Other players and the GPS goal (K.BLIPS_EVERY).
local function refreshLive()
	markGroup("live")
	for _, p in ipairs(Players:GetPlayers()) do
		local kind = MinimapClient.PlayerKind(p)
		if kind then
			local pos, root = MinimapClient.PlayerPos(p)
			if pos then
				blip("pl_" .. p.UserId, "live", pos, firstLetter(p.DisplayName), K.PLAYER_COLORS[kind] or C.Text, K.PLAYER,
					{ z = 6, track = root })
			end
		end
	end
	-- The goal as the minimap shows it (during a race: its next checkpoint, never the target)...
	local goal, glyph = GPSClient.MapGoal()
	if typeof(goal) == "Vector3" then
		blip("gps", "live", goal, glyph or "★", C.Gold, 18, { z = 7 })
	end
	-- Player businesses (BusinessClient.MapBlips): their letter and colour, a gold ring on yours, flashing red
	-- during a break-in you should answer. Tap one (or its name) to route the GPS to its door.
	local bizList = ask("BusinessClient", "MapBlips")
	local flashRed = os.clock() % 0.6 < 0.3
	for _, m in ipairs(type(bizList) == "table" and bizList or {}) do
		if m.Pos then
			local pos = Vector3.new(m.Pos.X, 0, m.Pos.Z)
			local b = blip("biz_" .. tostring(m.Id), "live", pos, tostring(m.Letter or "$"), (m.Alarm and flashRed) and C.Danger or m.Color or C.Gold,
				m.Owned and 18 or 16, { z = 5, go = { m.Name, pos }, main = true, order = 1, name = m.Name })
			local ring = b.frame:FindFirstChildOfClass("UIStroke")
			if ring then
				ring.Color = m.Owned and C.Gold or DARK
				ring.Thickness = m.Owned and 2 or 1
				ring.Transparency = m.Owned and 0 or 0.2
			end
		end
	end
	-- ...and during a race, the target kept for after it, faded.
	local kept = GPSClient.PathName() ~= nil and GPSClient.TargetPos() or nil
	if typeof(kept) == "Vector3" then
		blip("gps_kept", "live", kept, "★", C.Gold, 18, { z = 7, faded = true })
	end
	sweepGroup("live")
end

-- The words along the bottom.
local function defaultHint()
	local racing = GPSClient.PathName() ~= nil
	if S.touch then
		return racing and "Racing: a waypoint you set shows after the race · drag or pinch to look around"
			or "Tap the map to set a waypoint · tap a place to go there · drag or pinch to look around"
	end
	return racing and "Racing: a waypoint you set shows after the race · drag to move · scroll to zoom · M to close"
		or "Click the map to set a waypoint · click a place to go there · drag to move · scroll to zoom · M to close"
end

local function setHint(text, color)
	if S.shownHint ~= text then
		S.shownHint = text
		ui.hint.Text = text
	end
	ui.hint.TextColor3 = color or C.Text
end

-- The readout at the top (★ WHERE  distance, or MAP), CLEAR ROUTE and the hint.
local function refreshText()
	local name = GPSClient.Target()
	local text = "MAP"
	if name then
		local pos = GPSClient.TargetPos()
		local d = pos and GPSClient.Distance(pos)
		text = "★ " .. escape(string.upper(tostring(name)))
		if d then
			text ..= '  <font color="#' .. C.Gold:ToHex() .. '">' .. GPSClient.FormatDistance(d) .. "</font>"
		end
	end
	if S.shownTitle ~= text then
		S.shownTitle = text
		ui.title.Text = text
	end
	ui.clear.Visible = name ~= nil
	if os.clock() >= S.hintUntil then
		setHint(defaultHint())
	end
end

-- The GPS line: one thin frame per stretch, from the minimap's second point on (its first is "where
-- you were" at the last re-plan), the same way the minimap draws it.
local function drawRoute(sx, sy)
	local points = GPSClient.RoutePoints()
	local color = GPSClient.RouteColor() or C.Gold
	local n = 0
	if type(points) == "table" then
		for i = 2, #points - 1 do
			local a, b = points[i], points[i + 1]
			local x1, y1, x2, y2 = sx(a), sy(a), sx(b), sy(b)
			local dx, dy = x2 - x1, y2 - y1
			local len = math.sqrt(dx * dx + dy * dy)
			if len >= 1 then
				n += 1
				local f = routeBits[n]
				if not f then
					f = Instance.new("Frame")
					f.Name = "Route"
					f.AnchorPoint = Vector2.new(0.5, 0.5)
					f.BorderSizePixel = 0
					f.ZIndex = 2
					Theme.Corners(f, K.ROUTE_PX // 2)
					f.Parent = ui.overlay
					routeBits[n] = f
				end
				f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
				f.Size = UDim2.fromOffset(len + K.ROUTE_PX, K.ROUTE_PX) -- (a little longer: the joints overlap)
				f.Rotation = math.deg(math.atan2(dy, dx))
				f.BackgroundColor3 = color
				f.Visible = true
			end
		end
	end
	for i = n + 1, #routeBits do
		if routeBits[i].Visible then
			routeBits[i].Visible = false
		end
	end
end

local function overlaps(boxes, b)
	for _, o in ipairs(boxes) do
		if b[1] < o[3] and b[3] > o[1] and b[2] < o[4] and b[4] > o[2] then
			return true
		end
	end
	return false
end

-- Everything on top of the map to where the camera shows it now: you, the blips (hidden past the edge),
-- the names that fit (main places first, never over another name or off the map) and the GPS line.
-- Same maths as the camera: x grows east (+X), y grows south (+Z), from the map's middle.
local function layout()
	local vw, vh = S.vw, S.vh
	local pps = vh / 2 / S.aspan
	local function sx(pos)
		return vw / 2 + (pos.X - S.ax) * pps
	end
	local function sy(pos)
		return vh / 2 + (pos.Z - S.az) * pps
	end
	local root = myRoot()
	if root then
		local p = root.Position
		ui.you.Position = UDim2.fromOffset(sx(p), sy(p))
		local face = root.CFrame.LookVector
		ui.you.Rotation = math.deg(math.atan2(face.X, -face.Z)) -- 0 = north (up), 90 = east (right)
		ui.you.Visible = true
	else
		ui.you.Visible = false
	end
	local maxSpan = spanLimits()
	local allNames = maxSpan / S.aspan >= K.NAMES_AT
	local named = {}
	for _, b in pairs(blips) do
		if b.track and b.track.Parent then
			b.pos = b.track.Position
		end
		local x, y = sx(b.pos), sy(b.pos)
		local half = b.px / 2
		local on = x > -half and x < vw + half and y > -half and y < vh + half
		b.x, b.y, b.on, b.box = x, y, on, nil
		if b.frame.Visible ~= on then
			b.frame.Visible = on
		end
		b.frame.Position = UDim2.fromOffset(x, y)
		if b.label then
			if on and (b.main or allNames) then
				table.insert(named, b)
			elseif b.label.Visible then
				b.label.Visible = false
			end
		end
	end
	table.sort(named, function(a, b)
		if a.main ~= b.main then
			return a.main
		end
		return a.order < b.order
	end)
	local taken = {}
	local h = K.NAME_PX + 6
	for _, b in ipairs(named) do
		local drawn = b.label.AbsoluteSize.X
		local w = drawn > 1 and drawn or (b.labelW or 40) + 10
		local gap = b.px / 2 + 3
		local placed = false
		for _, side in ipairs({ 1, -1 }) do -- right of the blip, else left of it
			local x0 = side == 1 and b.x + gap or b.x - gap - w
			local box = { x0, b.y - h / 2, x0 + w, b.y + h / 2 }
			if box[1] >= 2 and box[3] <= vw - 2 and box[2] >= 2 and box[4] <= vh - 2 and not overlaps(taken, box) then
				b.label.Position = UDim2.fromOffset(x0, b.y)
				b.box = box
				table.insert(taken, box)
				placed = true
				break
			end
		end
		if b.label.Visible ~= placed then
			b.label.Visible = placed
		end
	end
	drawRoute(sx, sy)
end

------------------------------------------------------------------ setting the GPS

-- Point the GPS at `name` / `pos` (y = 0: GPSClient finds the ground for its pillar), then shut after a
-- beat. During a race the race line wins (GPSClient): the target waits for the end of it.
local function setDestination(name, pos)
	local racing = GPSClient.PathName() ~= nil
	if not pcall(GPSClient.SetTarget, name, pos) then
		return
	end
	sound("Click")
	local words = name == "Waypoint" and "Waypoint set" or ("GPS set: " .. name)
	if racing then
		NotifyController.Show(words .. ". It shows once the race is over.", C.Gold, "info")
	end
	setHint(racing and (words .. " · it shows once the race is over") or words, C.Gold)
	S.hintUntil = os.clock() + K.HINT_HOLD
	S.blipsAt = 0 -- the ★ and the line on the next frame
	local token = {}
	S.closing = token
	task.delay(K.CLOSE_AFTER, function()
		if S.closing == token then
			MapClient.Close()
		end
	end)
end

-- A tap at map pixel (x, y): the nearest place blip (or its name) within reach goes by name, else a
-- waypoint on the ground there.
local function tapAt(x, y)
	local reach = S.touch and K.TAP_REACH_TOUCH or K.TAP_REACH
	local best, bestD
	for _, b in pairs(blips) do
		if b.go and b.on then
			local d = math.sqrt((b.x - x) ^ 2 + (b.y - y) ^ 2)
			if b.box and x >= b.box[1] and x <= b.box[3] and y >= b.box[2] and y <= b.box[4] then
				d = math.min(d, b.px / 2) -- on its name: as good as on the blip
			end
			if d <= b.px / 2 + reach and (not bestD or d < bestD) then
				best, bestD = b, d
			end
		end
	end
	if best then
		setDestination(best.go[1], best.go[2])
	else
		setDestination("Waypoint", toWorld(x, y))
	end
end

------------------------------------------------------------------ presses, drags, pinches

-- Map pixels from a press's screen position (InputObject.Position and AbsolutePosition count from the
-- same corner, under the top bar).
local function mapPos(input)
	local at = ui.view.AbsolutePosition
	return Vector2.new(input.Position.X - at.X, input.Position.Y - at.Y)
end

-- Is this screen position on one of the controls (X, zoom, CLEAR, the readout, the hint)?
local function onControl(input)
	local p = Vector2.new(input.Position.X, input.Position.Y)
	for _, c in ipairs({ ui.close, ui.zoomIn, ui.zoomOut, ui.clear, ui.title, ui.hint }) do
		if c.Visible then
			local at, size = c.AbsolutePosition, c.AbsoluteSize
			if p.X >= at.X and p.X <= at.X + size.X and p.Y >= at.Y and p.Y <= at.Y + size.Y then
				return true
			end
		end
	end
	return false
end

local function pointerKey(input)
	return input.UserInputType == Enum.UserInputType.Touch and input or "mouse"
end

local function startPinch()
	local a, b
	for key in pairs(S.pointers) do
		if not a then
			a = key
		elseif not b then
			b = key
		end
	end
	local pa, pb = a and S.pointers[a], b and S.pointers[b]
	if not pa or not pb then
		S.pinch = nil
		return
	end
	local mid = (pa.now + pb.now) / 2
	local pps = S.vh / 2 / S.span
	S.pinch = {
		a = a, b = b,
		dist = math.max((pa.now - pb.now).Magnitude, 10),
		span = S.span,
		anchor = Vector3.new(S.cx + (mid.X - S.vw / 2) / pps, 0, S.cz + (mid.Y - S.vh / 2) / pps),
	}
end

-- Forget presses whose end we never heard of (a touch the system took away, a button let go off the
-- window), so a stale one can't turn every later tap into a pinch.
local function pruneStale()
	for key in pairs(S.pointers) do
		local gone
		if key == "mouse" then
			gone = not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		else
			local state = key.UserInputState
			gone = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
		end
		if gone then
			S.pointers[key] = nil
			S.count = math.max(S.count - 1, 0)
			if S.pinch and (S.pinch.a == key or S.pinch.b == key) then
				S.pinch = nil
			end
		end
	end
end

local function pointerDown(input)
	local key = pointerKey(input)
	if onControl(input) then
		return
	end
	pruneStale()
	if S.pointers[key] then
		if key ~= "mouse" then
			return
		end
		-- A new click while an old one never ended: the old one is over.
		S.pointers.mouse = nil
		S.count = math.max(S.count - 1, 0)
		S.pinch = nil
	end
	S.closing = nil -- touching the map again: stay up
	local p = mapPos(input)
	S.pointers[key] = { start = p, last = p, now = p }
	S.count += 1
	if S.count == 1 then
		S.moved, S.multi = 0, false
	else
		S.multi = true
		startPinch()
	end
end

local function pointerMove(input)
	local p = S.pointers[pointerKey(input)]
	if not p then
		return
	end
	local now = mapPos(input)
	p.now = now
	S.moved = math.max(S.moved, (now - p.start).Magnitude)
	local pinch = S.pinch
	if pinch then
		local a, b = S.pointers[pinch.a], S.pointers[pinch.b]
		if a and b then
			local maxSpan, minSpan = spanLimits()
			local dist = math.max((a.now - b.now).Magnitude, 10)
			S.span = math.clamp(pinch.span * pinch.dist / dist, minSpan, maxSpan)
			-- The ground that was under the fingers' middle stays under it.
			local mid = (a.now + b.now) / 2
			local pps = S.vh / 2 / S.span
			S.cx = pinch.anchor.X - (mid.X - S.vw / 2) / pps
			S.cz = pinch.anchor.Z - (mid.Y - S.vh / 2) / pps
			clampView()
		end
	elseif S.count == 1 then
		-- Drag: the ground follows the finger (or the mouse).
		local d = now - p.last
		if d.Magnitude > 0 then
			local pps = S.vh / 2 / S.span
			S.cx -= d.X / pps
			S.cz -= d.Y / pps
			clampView()
		end
	end
	p.last = now
end

local function pointerUp(input)
	local key = pointerKey(input)
	local p = S.pointers[key]
	if not p then
		return
	end
	S.pointers[key] = nil
	S.count = math.max(S.count - 1, 0)
	if S.pinch and (S.pinch.a == key or S.pinch.b == key) then
		S.pinch = nil
		for _, q in pairs(S.pointers) do
			q.last = q.now -- the finger still down carries on dragging from where it is
		end
		if S.count >= 2 then
			startPinch()
		end
	end
	if S.count == 0 then
		local tap = not S.multi and S.moved < K.TAP_SLOP
		S.moved, S.multi = 0, false
		if tap then
			tapAt(p.now.X, p.now.Y)
		end
	end
end

local function dropPointers()
	table.clear(S.pointers)
	S.count, S.moved, S.multi, S.pinch = 0, 0, false, nil
end

------------------------------------------------------------------ building it

-- A flat button on the map (Theme.Button's quiet look, words in the Display font).
local function button(name, text, onTap)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	Theme.Button(b, "Quiet")
	b.BackgroundTransparency = 0.2
	b.FontFace = Theme.Font.Display
	b.Selectable = false
	b.ZIndex = 2
	b.Parent = ui.controls
	b.Activated:Connect(function()
		if S.open then
			onTap()
		end
	end)
	return b
end

-- Lay the pieces out for this screen (phone: thumb-sized controls, a smaller margin).
local function place()
	local touch = Theme.IsTouch()
	S.touch = touch
	local screen = screenSize()
	local m = touch and 8 or 16
	local top = touch and 8 or Theme.TopBar
	S.vw = math.max(math.floor(screen.X - 2 * m), 1)
	S.vh = math.max(math.floor(screen.Y - top - m), 1)
	for _, f in ipairs({ ui.view, ui.overlay, ui.input }) do
		f.Position = UDim2.fromOffset(m, top)
		f.Size = UDim2.fromOffset(S.vw, S.vh)
	end
	local b = touch and Theme.Touch or 36
	local gap = 8
	ui.close.Size = UDim2.fromOffset(b, b)
	ui.close.Position = UDim2.new(1, -gap, 0, gap)
	ui.close.TextSize = touch and 22 or 18
	ui.zoomIn.Size = UDim2.fromOffset(b, b)
	ui.zoomIn.Position = UDim2.new(1, -gap, 0.5, -4)
	ui.zoomOut.Size = UDim2.fromOffset(b, b)
	ui.zoomOut.Position = UDim2.new(1, -gap, 0.5, 4)
	ui.zoomIn.TextSize, ui.zoomOut.TextSize = touch and 26 or 22, touch and 26 or 22
	local clearW = touch and 140 or 124
	ui.clear.Size = UDim2.fromOffset(clearW, b)
	ui.clear.Position = UDim2.new(1, -(gap + b + gap), 0, gap)
	ui.clear.TextSize = touch and 16 or 15
	ui.title.Size = UDim2.fromOffset(0, b)
	ui.title.Position = UDim2.new(0.5, 0, 0, gap)
	ui.title.TextSize = touch and 17 or 18
	ui.titleCap.MaxSize = Vector2.new(math.max(120, S.vw - 2 * (clearW + b + 4 * gap)), b)
	-- (as wide as the room between the side buttons allows; a second line makes it grow upward. Roblox's
	-- own hotbar would sit over it down there: CombatClient hides that while the map is up.)
	ui.hint.Size = UDim2.fromOffset(math.max(160, math.min(touch and 680 or 760, S.vw - 2 * (b + 3 * gap))), 30)
	ui.hint.Position = UDim2.new(0.5, 0, 1, -gap)
	ui.hint.TextSize = touch and 13 or 14
	ui.you.Size = UDim2.fromOffset(touch and K.YOU - 2 or K.YOU, touch and K.YOU - 2 or K.YOU)
	S.shownHint = nil
	if S.box then
		clampView()
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BigMap"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- y = 0 is the very top of the screen
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = K.DISPLAY_ORDER
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui

	-- The dark sheet over everything: it takes every press that misses the map (no HUD button, no shot,
	-- no camera drag), and being Modal it frees the mouse.
	local back = Instance.new("TextButton")
	back.Name = "Backdrop"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = DARK
	back.BackgroundTransparency = 0.12
	back.BorderSizePixel = 0
	back.AutoButtonColor = false
	back.Selectable = false
	back.Text = ""
	back.Modal = true
	back.ZIndex = 1
	back.Parent = gui
	ui.back = back

	local view = Instance.new("ViewportFrame")
	view.Name = "Map"
	MinimapClient.StyleView(view)
	view.ZIndex = 2
	view.Parent = gui
	Theme.Corners(view)
	ui.view = view
	local cam = Instance.new("Camera")
	cam.FieldOfView = K.FOV
	cam.Parent = view
	view.CurrentCamera = cam
	ui.cam = cam

	-- Blips, names, the GPS line and your arrow, clipped to the map; the thin dark frame round it.
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.ClipsDescendants = true
	overlay.ZIndex = 3
	overlay.Parent = gui
	Theme.Corners(overlay)
	local frame = Instance.new("UIStroke")
	frame.Name = "Frame"
	frame.Color = DARK
	frame.Thickness = 2
	frame.Transparency = 0.1
	frame.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frame.Parent = overlay
	ui.overlay = overlay

	local you = Instance.new("TextLabel")
	you.Name = "You"
	you.AnchorPoint = Vector2.new(0.5, 0.5)
	you.BackgroundTransparency = 1
	you.FontFace = Theme.Font.Bold
	you.TextScaled = true
	you.Text = "▲"
	you.TextColor3 = C.Text
	you.ZIndex = 8
	you.Parent = overlay
	local youEdge = Instance.new("UIStroke")
	youEdge.Color = DARK
	youEdge.Thickness = 1.5
	youEdge.Parent = you
	ui.you = you

	-- Takes the presses on the map (drags, pinches, taps, the mouse wheel).
	local input = Instance.new("TextButton")
	input.Name = "Input"
	input.BackgroundTransparency = 1
	input.BorderSizePixel = 0
	input.AutoButtonColor = false
	input.Selectable = false
	input.Text = ""
	input.ZIndex = 4
	input.Parent = gui
	ui.input = input
	input.InputBegan:Connect(function(io)
		local t = io.UserInputType
		if S.open and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			pointerDown(io)
		end
	end)
	input.InputChanged:Connect(function(io)
		if S.open and io.UserInputType == Enum.UserInputType.MouseWheel and io.Position.Z ~= 0 then
			local p = mapPos(io)
			zoomAt(p.X, p.Y, K.WHEEL_STEP ^ io.Position.Z)
		end
	end)

	-- The controls sit on the press-taker itself (nothing see-through lies over it), above the map.
	ui.controls = input
	local controls = input

	ui.close = button("Close", "X", function()
		sound("Click")
		MapClient.Close()
	end)
	ui.close.AnchorPoint = Vector2.new(1, 0)
	ui.zoomIn = button("ZoomIn", "+", function()
		local maxSpan = spanLimits()
		local root = myRoot()
		if root and S.span >= maxSpan * 0.99 then
			S.cx, S.cz = root.Position.X, root.Position.Z -- from the whole city: in on you
		end
		zoomAt(S.vw / 2, S.vh / 2, K.BUTTON_STEP)
	end)
	ui.zoomIn.AnchorPoint = Vector2.new(1, 1)
	ui.zoomOut = button("ZoomOut", "−", function()
		zoomAt(S.vw / 2, S.vh / 2, 1 / K.BUTTON_STEP)
	end)
	ui.zoomOut.AnchorPoint = Vector2.new(1, 0)
	ui.clear = button("Clear", "CLEAR ROUTE", function()
		GPSClient.Clear()
		sound("Click")
		S.blipsAt = 0
	end)
	ui.clear.AnchorPoint = Vector2.new(1, 0)
	ui.clear.Visible = false

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.AutomaticSize = Enum.AutomaticSize.X
	title.RichText = true
	title.Text = "MAP"
	Theme.Text(title, 18, "Display")
	Theme.Panel(title, 0.25)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 2
	title.Parent = controls
	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingLeft, titlePad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	titlePad.Parent = title
	ui.titleCap = Instance.new("UISizeConstraint")
	ui.titleCap.Parent = title
	ui.title = title

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	Theme.Text(hint, 14, "Body")
	Theme.Panel(hint, 0.25)
	hint.TextWrapped = true
	hint.AutomaticSize = Enum.AutomaticSize.Y
	hint.ZIndex = 2
	hint.Parent = controls
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft, hintPad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	hintPad.PaddingTop, hintPad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	hintPad.Parent = hint
	ui.hint = hint

	place()
end

-- The city's parts, the first time the map opens (and again if the data wasn't all there yet).
-- False while there is nothing to draw at all.
local function ensureBuilt()
	if S.built then
		return true
	end
	if ui.model then
		ui.model:Destroy()
		ui.model = nil
	end
	local ok, model, box, complete = pcall(MinimapClient.BuildMap, ui.view)
	if not ok or not model then
		return false
	end
	if not box then
		model:Destroy()
		return false
	end
	ui.model, S.box, S.built = model, box, complete == true
	return true
end

------------------------------------------------------------------ open / shut

local function step()
	local now = os.clock()
	local moved = false
	if now - S.blipsAt >= K.BLIPS_EVERY then
		S.blipsAt = now
		if blocked() or ask("PhoneUI", "IsOpen") == true then
			MapClient.Close()
			return
		end
		if now - S.placesAt >= K.PLACES_EVERY then
			S.placesAt = now
			refreshPlaces()
		end
		refreshLive()
		refreshText()
		moved = true
	end
	if S.dirty and now - S.camAt >= K.CAM_EVERY then
		applyCamera()
		moved = true
	end
	if moved then
		layout()
	end
end

function MapClient.IsOpen()
	return S.open
end

function MapClient.Open()
	if S.open or not ui.gui or blocked() or RobloxMenu.IsOpen() then
		return
	end
	if not ensureBuilt() then
		NotifyController.Show("The map is still loading. Try again in a moment!", nil, "info")
		return
	end
	S.open = true
	ask("PhoneUI", "Close")
	ask("WeaponWheel", "Close")
	dropPointers()
	S.closing, S.hintUntil = nil, 0
	place()
	-- The whole city to start with.
	S.span = spanLimits()
	S.cx, S.cz = (S.box.minX + S.box.maxX) / 2, (S.box.minZ + S.box.maxZ) / 2
	clampView()
	applyCamera()
	S.placesAt, S.blipsAt = 0, 0
	-- The camera behind the map mustn't zoom with the wheel (taken here before Roblox's camera sees it).
	pcall(function()
		ContextActionService:BindActionAtPriority(K.LOOK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, K.PRIORITY, Enum.UserInputType.MouseWheel)
	end)
	ui.gui.Enabled = true
	if S.conn then
		S.conn:Disconnect()
	end
	-- (An error in here shuts the map rather than leave a full-screen layer up that can't be used.)
	local function guarded()
		local ok, err = pcall(step)
		if not ok then
			warn("[MapClient] " .. tostring(err))
			MapClient.Close()
		end
	end
	S.conn = RunService.RenderStepped:Connect(guarded)
	guarded()
	sound("Click")
end

function MapClient.Close()
	if not S.open then
		return
	end
	S.open = false
	S.closing = nil
	if S.conn then
		S.conn:Disconnect()
		S.conn = nil
	end
	pcall(ContextActionService.UnbindAction, ContextActionService, K.LOOK_ACTION)
	dropPointers()
	ui.gui.Enabled = false
end

function MapClient.Toggle()
	if S.open then
		MapClient.Close()
	else
		MapClient.Open()
	end
end

function MapClient.Init()
	build()
	ui.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(place)
	-- A tap on the minimap opens it (and shuts it, though the map covers the minimap while it is up).
	MinimapClient.OnTap(MapClient.Toggle)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == K.KEY and not processed then
			MapClient.Toggle()
		end
	end)
	-- Drags and pinches go on wherever the pointer goes, and end wherever it is let go.
	UserInputService.InputChanged:Connect(function(input)
		if not S.open then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
			pointerMove(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not S.open then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			pointerUp(input)
		end
	end)
	-- A new character (a respawn, a side switch) shuts it; so do prison and the title screen (step).
	player.CharacterAdded:Connect(function()
		MapClient.Close()
	end)
	for _, name in ipairs({ "Side", "TitleScreen" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if S.open and blocked() then
				MapClient.Close()
			end
		end)
	end
end

return MapClient
