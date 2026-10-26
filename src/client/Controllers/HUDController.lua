-- HUDController (ModuleScript, StarterPlayerScripts.Controllers.HUDController)
-- The always-on HUD's top-right corner, the CAR button, the big moment stamps and the mission intros
-- ("street" look, Shared.Util.Theme): small, flat and quiet, every piece in its Theme zone, re-placed
-- when the screen size or the input type changes.
--   STATUS zone (top right), frame "Status": text straight on the screen, all right-aligned, top to
--   bottom (the tags with a soft shadow, the stars and the money with a hard black outline, the open-world
--   crime game "headline" look):
--     Heat         five white stars with a black outline while wanted (5 is the most), a small tag on
--                  their left. Your level = lit, the rest = faint outlines (never as bright as a lit star;
--                  the black edge fades with each star). Seen by a cop = solid stars with a soft glow that
--                  flash ("SEEN", red tag); searching = hollow stars that pulse slowly ("SEARCHING") but
--                  stay much brighter than the empty slots. A star that lights up slams in (drops from big
--                  to its size).
--     EscapeMeter  LOSING THEM: while the stars are hollow, a thin white bar under them fills from
--                  EscapeFrom to EscapeAt (server times from HeatService: full = the moment the heat goes),
--                  with a small LOSING THEM tag. Seen again: it turns red, drains and the tag says SPOTTED!
--                  for a moment (SoundClient plays the beep).
--     CashRow      Cash in the heavy slanted headline face (Theme.Font.Big), green with a black outline;
--                  when it changes, a "+$900" (green) / "-$50" (red) CashDelta in the same face floats in
--                  left of it and fades, outline and all (the save loading in - before the server's
--                  DataLoaded - and changes on the title screen don't count).
--     Bag          gold bag cash in the headline face with a small BAG tag, only while carrying.
--     (bottom row) ProgressClient's RANK readout, then TeamUI's role line at the right: not built here.
--   BUTTONS zone: CAR (HUD.CarButton, a square tile with a drawn car) brings your car to you: the last
--     land car this side can drive, else the side's starter. Hidden while seated and in prison. PhoneUI's
--     PHONE tile sits beside it (slot 1), built with HUDController.ZoneButton.
--   STAMP zone: big moments ("MISSION PASSED", "CLEAN GETAWAY", "CUFFED", "RANK UP"), the open-world
--     crime game "headline" (2026-10): an optional small line on top, a huge slanted title (Theme.Font.Big)
--     with a thick black outline and a drop shadow that slams in (scales down into place), an optional
--     reward line ("+$500   +50 XP": cash green, XP gold, it pops in a beat later) and a smaller line under
--     it, on a dark band across the screen. Their colour means something (old neon colours from callers
--     are mapped with NotifyController.Tone; pink becomes a white title). A stamp with a reward plays the
--     Passed sting and stays up longer, a red one the Failed sting; the rest play the Stamp thump.
--     Stamps queue so two never draw on top of each other, and wait while the title screen is up.
--   MISSION INTRO (HUDController.Intro, ScreenGui "MissionIntro"): the cinematic start of a mission. Two
--     black letterbox bars (11% of the screen height each) slide in from the top and the bottom, then
--     the title fades in large in the script face (Kalam Bold, white, soft shadow) just over the bottom
--     bar, centred in the lower third, with a smaller line under it; it holds, then the words fade and the
--     bars slide away. Intros wait in the stamps' queue (one moment at a time, never over the title
--     screen). Their ScreenGui (DisplayOrder 4, which nothing else uses) draws over every HUD layer (HUD
--     and DriveUI 0 up to CombatHUD 3, with Locomotion / ImpactFx) and under the phone (5) and everything
--     above it; it is edge to edge (no safe-area insets), so the bars reach the sides of a notched phone.
--     Labels and bars never take a tap.
-- Roblox's own health bar is switched off here (CombatClient draws health and armour in the Vitals zone).
-- While the first-join title screen is up (local attribute TitleScreen) TeamUI keeps the "HUD"
-- ScreenGui switched off; nothing here switches it back on.
-- Reads player attributes the server sets: Cash, Carried, Heat, HeatSpotted, EscapeFrom, EscapeAt (plus
-- Side and LastCar for the CAR button, HasPicked for the saving note, DataLoaded for the cash delta), and
-- the ReplicatedStorage attribute SavesOff.
-- API:
--   HUDController.Money(n) -> "$1,234"
--   HUDController.Stamp(title, sub?, color?, kicker?, reward?)  queue a stamp; kicker = the small line
--     above the title (ProgressClient: "RANK UP" over "RANK 5"); reward = { Cash = n?, XP = n? } for the
--     big "+$500   +50 XP" line (MissionClient: MISSION PASSED)
--   HUDController.StampTop() -> top, bottom of the stamp's band while one is showing, else nil: pixels
--     from the top-left corner of the HUD's full-screen IgnoreGuiInset ScreenGui (y = 0 is the very top
--     of the screen). Compare it with another full-screen gui's pieces measured from that gui's own
--     corner (obj.AbsolutePosition.Y - itsGui.AbsolutePosition.Y): raw AbsolutePosition starts under
--     the top bar. ObjectiveClient / TutorialClient / MissionClient / CrewClient / OfferClient step aside
--     while a stamp would draw over them; SoundClient keeps the station name under the band. (nil while
--     a mission intro shows: it doesn't use the Stamp zone. See IntroUp.)
--   HUDController.Intro(title, sub?, seconds?)  queue a mission intro (see above); seconds = how long the
--     words hold once they are in (default 3, 1..10). MissionClient: the mission's name over its first step.
--   HUDController.IntroUp() -> true while an intro is on screen (from the bars coming in to their going):
--     pieces in the letterbox's way (top-centre banners, the Subtitle zone's lines) step aside meanwhile
--     (MissionClient's banner and step do).
--   HUDController.ZoneButton(parent, name, glyph, text, key?, slot) -> TextButton: a square tile in the
--     Buttons zone (Quiet button, drawn glyph "Car" | "Phone", Display label at the bottom, the PC key
--     cap on its left while a keyboard / mouse is in use). slot 1 = PHONE, 2 = CAR (PC: top / bottom of
--     the right-edge column; phone: left / right of the row). Placed relative to the zone's anchor (so it
--     follows whatever box its ScreenGui gets, safe-area insets included) and re-placed with the rest of
--     the HUD. The parent should be a full-screen IgnoreGuiInset ScreenGui like the HUD's.
--   HUDController.CarButton  the CAR tile
-- Two small one-time info toasts (once per session each, via NotifyController):
--   * saving is off (SavesOff, set by DataService when it can't reach the DataStores, e.g. an
--     unpublished Studio test), shown a few seconds after the side is picked;
--   * the first time the bag gets cash: bank it at the Hideout, unbanked cash is lost on leaving.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local HUDController = {}

local C = Theme.Color
local MAX_STARS = 5
local UNLIT = 0.7 -- an empty star slot: a faint outline (a lit star never gets this faint)
local FLASH_PERIOD, FLASH_ON = 0.7, 0.5 -- seen: the stars blink off for 0.2 s in every 0.7 s
local PULSE_SPEED = 3.9 -- searching: one slow breath every ~1.6 s, between 0.1 and 0.4 transparency
local GLOW_ALPHA = 0.8 -- the soft halo behind a solid star
local SNAP_TIME = 1.2 -- seconds the red SPOTTED! snap-back stays up
local TAG_SIZE = 13 -- the small tags (SEARCHING, LOSING THEM, BAG)
local DELTA_HOLD = 1.6 -- seconds a "+$900" stays before it fades (changes meanwhile add up)
local TILE_GAP = 8 -- pixels between the square tiles in the Buttons zone
local STAMP_EVERY = 2.6 -- seconds each queued stamp gets (it fades out over its last half second)...
local REWARD_EVERY = 3.6 -- ...and one with a reward line (MISSION PASSED): the sting is 4 s long

-- Rows inside the Status zone, pixels from its top (PC 280 x 116, phone 210 x 98). The bottom 22 px are
-- the RANK readout's and the role line's: PC heat 0-24, meter 24-38, cash 38-74, bag 74-94; phone heat
-- 0-20, meter 20-30, cash 30-59, bag 59-76 (the cash and bag rows are their text size + 2). Outline = the
-- black edge round the cash, the "+$900" and the bag; StarLine = the stars' black edge (pixels).
local ROWS = {
	Desktop = { Star = 24, StarGap = 3, Heat = 24, MeterY = 24, Meter = 14, CashY = 38, Cash = 34, Delta = 22, BagY = 74,
		Bag = 18, Outline = 2, StarLine = 2 },
	Touch = { Star = 20, StarGap = 2, Heat = 20, MeterY = 20, Meter = 10, CashY = 30, Cash = 27, Delta = 18, BagY = 59,
		Bag = 15, Outline = 1.5, StarLine = 1.5 },
}
-- The stamp's lines inside the Stamp zone (PC 164 tall, phone 120), pixels from its top. SubY = the small
-- line's top with no reward line, RewardSubY with one. Shift = how far everything moves down when
-- there's no small line above the title, so it stays centred. Stroke = the title's black outline.
local STAMP = {
	Desktop = { KickerY = 2, Kicker = 15, TitleY = 16, Title = 76, RewardY = 96, Reward = 34, SubY = 100,
		RewardSubY = 134, Sub = 20, Shift = 8, Stroke = 3, Drop = 4 },
	Touch = { KickerY = 2, Kicker = 13, TitleY = 14, Title = 52, RewardY = 69, Reward = 24, SubY = 72,
		RewardSubY = 96, Sub = 14, Shift = 6, Stroke = 2, Drop = 3 },
}
-- The mission intro (HUDController.Intro). Bar = each letterbox bar's share of the screen height; Order =
-- its ScreenGui's DisplayOrder (see the header); Hold = default seconds the words stay fully in. Times:
-- the bars slide in over Slide s, the title starts fading in at TitleAt (FadeIn s), the sub at SubAt;
-- out, the words fade over FadeOut s and the bars slide away BarsOutAt s after that fade starts. Line =
-- the title's box as a share of its text size (a script face has tall loops and tails, as
-- AmbienceClient's area name has). Per layout: Title = the title's text size (MinTitle when a long one
-- has to shrink to fit Width, the share of the screen width), Sub = the line under it, Gap = pixels
-- between the words and the bottom bar: enough to stand clear of Theme's Subtitle and Action zones (the
-- tutorial's pill, help lines and the GET IN button live there; on a short phone the Action zone stands
-- higher than that, so there the words stay 8 px over it instead: showIntro), Stroke = the soft shadow's
-- thickness, Drop = the drop shadow's offset.
local INTRO = {
	Font = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold),
	Bar = 0.11, Order = 4, Hold = 3, Line = 1.3,
	Slide = 0.35, TitleAt = 0.3, SubAt = 0.55, FadeIn = 0.45, FadeOut = 0.4, BarsOutAt = 0.15,
	Desktop = { Title = 64, MinTitle = 32, Sub = 20, Width = 0.8, Gap = 168, Stroke = 2, Drop = 3 },
	Touch = { Title = 40, MinTitle = 22, Sub = 14, Width = 0.62, Gap = 116, Stroke = 1.5, Drop = 2 },
}

local gui, status, heatRow, heatTag, meterRow, meterTag, meterBar, meterFill
local cashLabel, deltaLabel, deltaShadow, bagRow, bagAmount
-- [i] = { label = the star, stroke = its black outline, glow = the halo behind it, scale = its UIScale
-- (the slam) }
local stars = {}
local lastHeat = 0 -- the star count refresh last drew (a rise slams the new stars in)
local tiles = {} -- ZoneButton tiles: { button, slot, key = key cap or nil }
local rows = ROWS.Desktop
local showKeys = false -- key caps beside the tiles (a keyboard / mouse is in use)
local lastMeter, snapUntil = 0, 0 -- os.clock() the meter last drew / the snap-back ends
local lastCash = nil
local deltaSum, deltaUntil = 0, 0 -- the change on show, and os.clock() it starts fading
-- The mission intro: gui = its ScreenGui (made on first use), on = one is on screen (IntroUp).
local intro = { gui = nil, on = false }

local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end
HUDController.Money = money

-- The HUD ScreenGui's own size (what its zones are laid out in: the safe area, which can be narrower than
-- the camera's view on a notched phone). Until it has been laid out, the camera's.
local function screenSize()
	local size = gui and gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then
		return size
	end
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(844, 390)
end

-- A Theme zone's box in the HUD ScreenGui, in pixels from its corner (IgnoreGuiInset): x, y, w, h.
local function zoneBox(name, touch)
	local z = Theme.Zone(name, touch)
	local size = screenSize()
	local w = z.Size.X.Scale * size.X + z.Size.X.Offset
	local h = z.Size.Y.Scale * size.Y + z.Size.Y.Offset
	return z.Pos.X.Scale * size.X + z.Pos.X.Offset - z.Anchor.X * w, z.Pos.Y.Scale * size.Y + z.Pos.Y.Offset - z.Anchor.Y * h, w, h
end

local function textLabel(parent, name, kind, size, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	Theme.Text(l, size, kind)
	if color then
		l.TextColor3 = color
	end
	l.Parent = parent
	return l
end

-- A right-aligned row of labels that size themselves to their text (the list does the measuring).
local function row(parent, name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Parent = parent
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = f
	return f
end

local function fitText(l)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromScale(0, 1)
	l.TextXAlignment = Enum.TextXAlignment.Right
end

-- Theme.Text's soft shadow turned into a hard black outline (round corners, so a star's points and the
-- headline face's sharp ends don't spike). Its thickness follows the layout (layout()). Returns the stroke.
local function hardEdge(l)
	local s = Theme.Shadow(l)
	s.Transparency = 0
	s.LineJoinMode = Enum.LineJoinMode.Round
	return s
end

-- Fade helpers: `map` = { [instance] = { prop = hidden value } }, built in the shown state.
local function fadeIn(map, info)
	for inst, hidden in pairs(map) do
		local shown = {}
		for prop, value in pairs(hidden) do
			shown[prop] = inst[prop]
			inst[prop] = value
		end
		TweenService:Create(inst, info, shown):Play()
	end
end

local function fadeOut(map, info)
	for inst, hidden in pairs(map) do
		if inst.Parent then
			TweenService:Create(inst, info, hidden):Play()
		end
	end
end

------------------------------------------------------------------ square tiles (Buttons zone)

-- One white piece of a glyph.
local function piece(parent, name, x, y, w, h, radius, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = C.Text
	f.BorderSizePixel = 0
	f.ZIndex = z or 2
	Theme.Corners(f, radius)
	f.Parent = parent
	return f
end

-- Small white icons drawn from frames (no image assets): a car side-on, a phone.
local function drawGlyph(parent, kind)
	local g = Instance.new("Frame")
	g.Name = "Glyph"
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.new(0.5, 0, 0, 6)
	g.BackgroundTransparency = 1
	g.Parent = parent
	if kind == "Car" then
		g.Size = UDim2.fromOffset(28, 18)
		piece(g, "Cabin", 7, 1, 14, 9, 3)
		piece(g, "Body", 0, 6, 28, 7, 2)
		for i, x in ipairs({ 4, 17 }) do
			local wheel = piece(g, "Wheel" .. i, x, 10, 7, 7, 4, 3)
			wheel.BackgroundColor3 = C.Panel
			local rim = Instance.new("UIStroke")
			rim.Color = C.Text
			rim.Thickness = 1.5
			rim.Parent = wheel
		end
	else
		g.Size = UDim2.fromOffset(12, 19)
		local shell = piece(g, "Case", 0, 0, 12, 19, 3)
		shell.BackgroundTransparency = 1
		local rim = Instance.new("UIStroke")
		rim.Color = C.Text
		rim.Thickness = 2
		rim.Parent = shell
		local screen = piece(g, "Screen", 3, 3, 6, 10, 1)
		screen.BackgroundTransparency = 0.6
		piece(g, "Home", 4, 15, 4, 2, 1)
	end
	return g
end

-- Into its share of the Buttons zone, measured from the zone's anchor (the same scale part as the zone),
-- so the tile lands where Theme.Place would put the zone in whatever box its ScreenGui has.
local function placeTile(t)
	local z = Theme.Zone("Buttons", Theme.IsTouch())
	local w, h = z.Size.X.Offset, z.Size.Y.Offset -- (the Buttons zone is sized in pixels in both layouts)
	local across = w > h -- phone: a row; PC: a column
	local tw = across and math.floor((w - TILE_GAP) / 2) or w
	local th = across and h or math.floor((h - TILE_GAP) / 2)
	local i = t.slot - 1
	local x = z.Pos.X.Offset - z.Anchor.X * w + (across and i * (tw + TILE_GAP) or 0)
	local y = z.Pos.Y.Offset - z.Anchor.Y * h + (across and 0 or i * (th + TILE_GAP))
	t.button.AnchorPoint = Vector2.zero
	t.button.Position = UDim2.new(z.Pos.X.Scale, math.floor(x), z.Pos.Y.Scale, math.floor(y))
	t.button.Size = UDim2.fromOffset(tw, th)
	if t.key then
		t.key.Visible = showKeys
	end
end

-- Key caps: shown while a keyboard or mouse was the last thing used (never on the phone layout; no
-- gamepad button is bound to these tiles, so a gamepad shows none).
local function updateKeys(inputType)
	local name = inputType and inputType.Name or ""
	if Theme.IsTouch() or name == "Touch" or string.sub(name, 1, 7) == "Gamepad" then
		showKeys = false
	elseif name == "Keyboard" or string.sub(name, 1, 5) == "Mouse" then
		showKeys = true
	end -- (other inputs - focus, sensors - say nothing about the device)
	for _, t in ipairs(tiles) do
		if t.key then
			t.key.Visible = showKeys
		end
	end
end

-- (see the header)
function HUDController.ZoneButton(parent, name, glyph, text, key, slot)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text or ""
	Theme.Button(b, "Quiet")
	b.FontFace = Theme.Font.Display
	b.TextSize = 13
	b.TextYAlignment = Enum.TextYAlignment.Bottom
	Theme.Shadow(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	drawGlyph(b, glyph)
	local t = { button = b, slot = slot or (#tiles + 1) }
	if type(key) == "string" and key ~= "" then
		local cap = Theme.Key(b, key)
		cap.AnchorPoint = Vector2.new(1, 0.5)
		cap.Position = UDim2.new(0, -6, 0.5, 0)
		t.key = cap
	end
	table.insert(tiles, t)
	placeTile(t)
	b.Parent = parent
	return b
end

------------------------------------------------------------------ build and layout

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- zone coordinates: y = 0 is the very top of the screen
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	status = Instance.new("Frame")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Parent = gui

	-- Heat: the tag and five star slots, right-aligned. Each star has a halo (a bigger, very faint star
	-- behind it) that only shows while a cop can see you.
	heatRow = Instance.new("Frame")
	heatRow.Name = "Heat"
	heatRow.BackgroundTransparency = 1
	heatRow.Visible = false
	heatRow.Parent = status
	heatTag = textLabel(heatRow, "Tag", "Bold", TAG_SIZE, C.Dim)
	heatTag.AnchorPoint = Vector2.new(1, 0.5)
	heatTag.Size = UDim2.fromOffset(120, 16)
	heatTag.TextXAlignment = Enum.TextXAlignment.Right
	heatTag.Text = "SEARCHING"
	for i = 1, MAX_STARS do
		local glow = Instance.new("TextLabel")
		glow.Name = "Glow" .. i
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.BackgroundTransparency = 1
		glow.FontFace = Theme.Font.Bold
		glow.TextScaled = true
		glow.Text = "★"
		glow.TextColor3 = C.Text
		glow.TextTransparency = 1
		glow.ZIndex = 1
		glow.Parent = heatRow
		local s = textLabel(heatRow, "Star" .. i, "Bold")
		s.AnchorPoint = Vector2.new(1, 0.5)
		s.TextScaled = true
		s.Text = "☆"
		s.ZIndex = 2
		local stroke = hardEdge(s) -- (a bold game star: its edge fades with it, starAlpha)
		local scale = Instance.new("UIScale")
		scale.Parent = s
		stars[i] = { label = s, stroke = stroke, glow = glow, scale = scale }
	end

	-- The LOSING THEM meter: a thin bar under the stars (as wide as them) and its tag on the left.
	meterRow = Instance.new("Frame")
	meterRow.Name = "EscapeMeter"
	meterRow.BackgroundTransparency = 1
	meterRow.Visible = false
	meterRow.Parent = status
	meterTag = textLabel(meterRow, "LosingThem", "Bold", TAG_SIZE, C.Dim)
	meterTag.AnchorPoint = Vector2.new(1, 0.5)
	meterTag.Size = UDim2.fromOffset(120, 16)
	meterTag.TextXAlignment = Enum.TextXAlignment.Right
	meterTag.Text = "LOSING THEM"
	meterBar = Instance.new("Frame")
	meterBar.Name = "Bar"
	meterBar.AnchorPoint = Vector2.new(1, 0.5)
	meterBar.Position = UDim2.fromScale(1, 0.5)
	meterBar.BackgroundColor3 = C.Text
	meterBar.BackgroundTransparency = 0.78 -- a faint line: how far the bar has to go
	meterBar.BorderSizePixel = 0
	meterBar.Parent = meterRow
	meterFill = Instance.new("Frame")
	meterFill.Name = "Fill"
	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.BackgroundColor3 = C.Text
	meterFill.BorderSizePixel = 0
	meterFill.Parent = meterBar

	-- Cash, and the "+$900" that floats in on its left (in a slot of its own, so it can rise into place
	-- without moving the cash). Both in the headline face with a hard black outline.
	local cashRow = row(status, "CashRow")
	local deltaSlot = Instance.new("Frame")
	deltaSlot.Name = "DeltaSlot"
	deltaSlot.LayoutOrder = 1
	deltaSlot.AutomaticSize = Enum.AutomaticSize.X
	deltaSlot.Size = UDim2.fromScale(0, 1)
	deltaSlot.BackgroundTransparency = 1
	deltaSlot.Parent = cashRow
	deltaLabel = textLabel(deltaSlot, "CashDelta", "Big", ROWS.Desktop.Delta, C.Cash)
	fitText(deltaLabel)
	deltaLabel.Text = ""
	deltaLabel.TextTransparency = 1
	deltaShadow = hardEdge(deltaLabel) -- (hidden with the words: showDelta fades it in and out with them)
	deltaShadow.Transparency = 1
	cashLabel = textLabel(cashRow, "Cash", "Big", ROWS.Desktop.Cash, C.Cash)
	cashLabel.LayoutOrder = 2
	fitText(cashLabel)
	hardEdge(cashLabel)

	-- Bag cash: a small BAG tag, then the amount in gold, in the headline face like the cash.
	bagRow = row(status, "Bag")
	bagRow.Visible = false
	local bagTag = textLabel(bagRow, "Tag", "Bold", TAG_SIZE, C.Dim)
	bagTag.LayoutOrder = 1
	fitText(bagTag)
	bagTag.Text = "BAG"
	bagAmount = textLabel(bagRow, "Amount", "Big", ROWS.Desktop.Bag, C.Gold)
	bagAmount.LayoutOrder = 2
	fitText(bagAmount)
	hardEdge(bagAmount)

	-- CAR: bring your car to you. The server decides.
	local carButton = HUDController.ZoneButton(gui, "CarButton", "Car", "CAR", nil, 2)
	carButton.Activated:Connect(function()
		local side = player:GetAttribute("Side") or "Civilian"
		local fallback = side == "Cop" and "SunrayPatrol" or "Palmetto"
		-- The last car, if it's a land car this side can drive (a boat launches at a far-off marina),
		-- else the side's starter.
		local last = player:GetAttribute("LastCar")
		local def = type(last) == "string" and Vehicles.ById[last] or nil
		if not def or def.Boat or (def.Police == true) ~= (side == "Cop") then
			last = fallback
		end
		Remotes.Event("RequestSpawnCar"):FireServer(last)
	end)
	HUDController.CarButton = carButton
end

-- Everything into its zone and its size for this screen (phones get the smaller rows).
local function layout()
	if not gui then
		return
	end
	local touch = Theme.IsTouch()
	rows = touch and ROWS.Touch or ROWS.Desktop
	Theme.Place(status, "Status", touch)
	local starsW = MAX_STARS * rows.Star + (MAX_STARS - 1) * rows.StarGap
	heatRow.Position = UDim2.new()
	heatRow.Size = UDim2.new(1, 0, 0, rows.Heat)
	for i, s in ipairs(stars) do
		local right = -(MAX_STARS - i) * (rows.Star + rows.StarGap) -- star 5 at the zone's right edge
		s.label.Position = UDim2.new(1, right, 0.5, 0)
		s.label.Size = UDim2.fromOffset(rows.Star, rows.Star)
		s.glow.Position = UDim2.new(1, right - rows.Star / 2, 0.5, 0)
		s.glow.Size = UDim2.fromOffset(rows.Star * 1.6, rows.Star * 1.6)
		s.stroke.Thickness = rows.StarLine
	end
	heatTag.Position = UDim2.new(1, -(starsW + 8), 0.5, 0)
	meterRow.Position = UDim2.fromOffset(0, rows.MeterY)
	meterRow.Size = UDim2.new(1, 0, 0, rows.Meter)
	meterBar.Size = UDim2.fromOffset(starsW, 3)
	meterTag.Position = UDim2.new(1, -(starsW + 8), 0.5, 0)
	local cashRow = status:FindFirstChild("CashRow")
	cashRow.Position = UDim2.fromOffset(0, rows.CashY)
	cashRow.Size = UDim2.new(1, 0, 0, rows.Cash + 2)
	cashLabel.TextSize = rows.Cash
	deltaLabel.TextSize = rows.Delta
	bagRow.Position = UDim2.fromOffset(0, rows.BagY)
	bagRow.Size = UDim2.new(1, 0, 0, rows.Bag + 2)
	bagAmount.TextSize = rows.Bag
	-- (the outlines are hardEdge's strokes, named "Shadow" like every Theme text stroke)
	for _, l in ipairs({ cashLabel, deltaLabel, bagAmount }) do
		local edge = l:FindFirstChild("Shadow")
		if edge then
			edge.Thickness = rows.Outline
		end
	end
	for _, t in ipairs(tiles) do
		placeTile(t)
	end
	updateKeys(UserInputService:GetLastInputType())
end

------------------------------------------------------------------ status

local function heatState()
	local heat = math.clamp(math.floor(player:GetAttribute("Heat") or 0), 0, MAX_STARS)
	return heat, player:GetAttribute("HeatSpotted") == true
end

-- A star and its black outline at one transparency (a stroke doesn't follow its text's, so an empty slot
-- or a blinking star would keep a solid black star shape otherwise).
local function starAlpha(s, a)
	s.label.TextTransparency = a
	s.stroke.Transparency = a
end

local function refresh()
	cashLabel.Text = money(player:GetAttribute("Cash") or 0)
	local carried = player:GetAttribute("Carried") or 0
	bagRow.Visible = carried > 0
	bagAmount.Text = money(carried)
	if HUDController.CarButton then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local driving = hum ~= nil and hum.SeatPart ~= nil
		HUDController.CarButton.Visible = player:GetAttribute("Side") ~= "Prisoner" and not driving
	end
	local heat, spotted = heatState()
	if heat > lastHeat and player:GetAttribute("TitleScreen") ~= true then
		-- New stars slam in one after another, from 2.6x down to their size (Back overshoots a touch).
		for i = lastHeat + 1, math.min(heat, MAX_STARS) do
			local st = stars[i]
			st.scale.Scale = 2.6
			TweenService:Create(st.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false,
				(i - lastHeat - 1) * 0.12), { Scale = 1 }):Play()
		end
	end
	lastHeat = heat
	heatRow.Visible = heat > 0
	heatTag.Text = spotted and "SEEN" or "SEARCHING"
	heatTag.TextColor3 = spotted and C.Danger or C.Dim
	for i, s in ipairs(stars) do
		-- Always 5 slots, so you can see how bad it can get. Solid = a cop can see you; hollow = searching.
		local lit = i <= heat
		s.label.Text = (lit and spotted) and "★" or "☆"
		if not lit then
			starAlpha(s, UNLIT)
			s.glow.TextTransparency = 1
		end
	end
end

-- Every frame while wanted: seen stars flash with their halo, searching stars breathe slowly. Even at
-- their faintest (0.55 / 0.4) lit stars stay brighter than an empty slot (UNLIT).
local function animateStars(heat, spotted)
	local t = os.clock()
	local on = t % FLASH_PERIOD < FLASH_ON
	local breath = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(t * PULSE_SPEED))
	for i = 1, math.min(heat, MAX_STARS) do
		local s = stars[i]
		if spotted then
			starAlpha(s, on and 0 or 0.55)
			s.glow.TextTransparency = on and GLOW_ALPHA or 1
		else
			starAlpha(s, breath)
			s.glow.TextTransparency = 1
		end
	end
end

-- LOSING THEM meter: the share of the unseen escape time used up (0-1), or nil while it isn't running.
local function escapeShare()
	local from, at = player:GetAttribute("EscapeFrom"), player:GetAttribute("EscapeAt")
	if typeof(from) ~= "number" or typeof(at) ~= "number" or at <= from then
		return nil
	end
	return math.clamp((Workspace:GetServerTimeNow() - from) / (at - from), 0, 1)
end

local function meterLook(spottedAgain)
	meterFill.BackgroundColor3 = spottedAgain and C.Danger or C.Text
	meterTag.TextColor3 = spottedAgain and C.Danger or C.Dim
	meterTag.Text = spottedAgain and "SPOTTED!" or "LOSING THEM"
end

-- Every frame, so the fill moves smoothly. Shown while the stars are hollow and HeatService has
-- published the escape time; kept up through the short red snap-back after a sighting.
local function updateMeter(heat, spotted)
	if heat <= 0 and not meterRow.Visible then
		return
	end
	local share = heat > 0 and not spotted and escapeShare()
	if share then
		lastMeter = os.clock()
		snapUntil = 0
		meterLook(false)
		meterFill.Size = UDim2.fromScale(share, 1)
		meterRow.Visible = true
	elseif heat <= 0 or os.clock() >= snapUntil then
		meterRow.Visible = false
	end
end

-- Seen again while the meter was running: it turns red and drains (SoundClient beeps at the same
-- moment). The half-second window covers EscapeAt clearing a frame before HeatSpotted arrives.
local function snapBack()
	if player:GetAttribute("HeatSpotted") ~= true or os.clock() - lastMeter > 0.5 then
		return
	end
	snapUntil = os.clock() + SNAP_TIME
	meterLook(true)
	meterRow.Visible = true
	TweenService:Create(meterFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(0, 1) }):Play()
end

local function update()
	local heat, spotted = heatState()
	if heat > 0 then
		animateStars(heat, spotted)
	end
	updateMeter(heat, spotted)
end

-- "+$900" / "-$50" left of the cash: rises 8 px into place as it fades in, holds, then fades while
-- drifting up. Changes that come while it's up add to it and restart the hold. Its black outline
-- (deltaShadow) fades with it: solid while shown, gone while hidden.
local function showDelta(diff)
	local now = os.clock()
	local fresh = now >= deltaUntil
	deltaSum = fresh and diff or deltaSum + diff
	deltaUntil = now + DELTA_HOLD
	local untilNow = deltaUntil
	if deltaSum == 0 then
		deltaLabel.TextTransparency = 1
		if deltaShadow then
			deltaShadow.Transparency = 1
		end
		return
	end
	deltaLabel.Text = (deltaSum > 0 and "+" or "-") .. money(math.abs(deltaSum))
	deltaLabel.TextColor3 = deltaSum > 0 and C.Cash or C.Danger
	if fresh then
		deltaLabel.Position = UDim2.fromOffset(0, 8)
		deltaLabel.TextTransparency = 1
		if deltaShadow then
			deltaShadow.Transparency = 1
		end
	end
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(deltaLabel, info, { Position = UDim2.new(), TextTransparency = 0 }):Play()
	if deltaShadow then
		TweenService:Create(deltaShadow, info, { Transparency = 0 }):Play()
	end
	task.delay(DELTA_HOLD, function()
		if deltaUntil ~= untilNow then
			return -- a newer change restarted the hold
		end
		local out = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(deltaLabel, out, { Position = UDim2.fromOffset(0, -6), TextTransparency = 1 }):Play()
		if deltaShadow then
			TweenService:Create(deltaShadow, out, { Transparency = 1 }):Play()
		end
	end)
end

-- DataService sets the saved Cash just before DataLoaded, so the save loading in (however late it comes)
-- only moves lastCash; from then on every change is news.
local function onCash()
	local cash = player:GetAttribute("Cash")
	if typeof(cash) == "number" and typeof(lastCash) == "number" and player:GetAttribute("DataLoaded") == true
		and player:GetAttribute("TitleScreen") ~= true then
		local diff = math.floor(cash) - math.floor(lastCash)
		if diff ~= 0 then
			showDelta(diff)
		end
	end
	lastCash = cash
end

------------------------------------------------------------------ stamps

-- Stamps (and mission intros) queue up so two moments never draw on top of each other.
local stampQueue = {} -- { title, sub, color, kicker, reward } / intros: { title, sub, seconds, intro = true }
local stamping = false -- the queue is being worked through
local stampOn = false -- a stamp is on screen right now (not one waiting for the title screen to go)
local showStamp, showIntro

-- (see the header) The Stamp zone's top and bottom: the band fills it.
function HUDController.StampTop()
	if not stampOn or not gui then
		return nil
	end
	local _, y, _, h = zoneBox("Stamp", Theme.IsTouch())
	return math.floor(y), math.ceil(y + h)
end

-- (see the header)
function HUDController.IntroUp()
	return intro.on
end

-- Works through the queue, one moment at a time, each for as long as it says it needs.
local function runQueue()
	if stamping then
		return
	end
	stamping = true
	task.spawn(function()
		while #stampQueue > 0 do
			-- Not over the first-join title screen (and not before the HUD exists): it waits its turn.
			while not gui or player:GetAttribute("TitleScreen") == true do
				task.wait(0.25)
			end
			local s = table.remove(stampQueue, 1)
			-- (an intro owns the letterbox and the lower third, not the Stamp zone: StampTop stays nil)
			if s.intro then
				intro.on = true
			else
				stampOn = true
			end
			-- One bad stamp never stalls the queue (nor leaves a half-built intro on screen).
			local ok, res = pcall(s.intro and showIntro or showStamp, s[1], s[2], s[3], s[4], s[5])
			local holdFor = ok and type(res) == "number" and res or STAMP_EVERY
			if not ok then
				warn("[HUDController] " .. (s.intro and "intro" or "stamp") .. " failed: " .. tostring(res))
				if s.intro then
					holdFor = 0 -- (whatever it had drawn goes at once)
					if intro.gui then
						intro.gui:ClearAllChildren()
					end
				end
			end
			task.wait(holdFor)
			stampOn = false
			intro.on = false
		end
		stamping = false
	end)
end

function HUDController.Stamp(title, sub, color, kicker, reward)
	table.insert(stampQueue, { title, sub, color, kicker, reward })
	runQueue()
end

-- (see the header)
function HUDController.Intro(title, sub, seconds)
	if title == nil or tostring(title) == "" then
		return
	end
	table.insert(stampQueue, { title, sub, seconds, intro = true })
	runQueue()
end

-- One line of the stamp, centred, shrinking to fit its box (never under 13 px).
local function stampLine(parent, name, font, y, h, maxSize, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, -16, 0, h)
	Theme.Text(l, nil, "Body")
	l.FontFace = font
	l.TextScaled = true
	l.TextColor3 = color
	l.ZIndex = 2
	l.Active = false
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = math.min(13, maxSize)
	limit.Parent = l
	l.Parent = parent
	return l
end

-- "+$500   +50 XP": cash in green, XP in gold (rich text), or nil when the reward has neither.
local function rewardText(reward)
	if type(reward) ~= "table" then
		return nil
	end
	local parts = {}
	local function hex(c)
		return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	if type(reward.Cash) == "number" and reward.Cash > 0 then
		table.insert(parts, '<font color="' .. hex(C.Cash) .. '">+' .. money(reward.Cash) .. "</font>")
	end
	if type(reward.XP) == "number" and reward.XP > 0 then
		table.insert(parts, '<font color="' .. hex(C.Gold) .. '">+' .. math.floor(reward.XP) .. " XP</font>")
	end
	return #parts > 0 and table.concat(parts, "     ") or nil
end

-- A label (and its "Shadow" stroke, outline or soft shadow) into a fade map: both fade out to nothing.
local function addFade(map, l)
	map[l] = { TextTransparency = 1 }
	local stroke = l:FindFirstChild("Shadow")
	if stroke then
		map[stroke] = { Transparency = 1 }
	end
end

-- A block that scales down into place: a UIScale from `from` to 1 (Back easing overshoots a touch).
local function slam(obj, from, delay, time)
	local scale = Instance.new("UIScale")
	scale.Scale = from
	scale.Parent = obj
	TweenService:Create(scale, TweenInfo.new(time or 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay or 0),
		{ Scale = 1 }):Play()
	return scale
end

-- Draws one stamp and schedules its fade; returns how long it owns the stamp zone (seconds).
showStamp = function(title, sub, color, kicker, reward)
	local rewardLine = rewardText(reward)
	local every = rewardLine and REWARD_EVERY or STAMP_EVERY
	local touch = Theme.IsTouch()
	local m = touch and STAMP.Touch or STAMP.Desktop
	local accent = NotifyController.Tone(color) or C.Text
	-- A reward plays the Passed sting, a red stamp (MISSION FAILED, CUFFED, HEIST FAILED) the Failed one,
	-- the rest the Stamp thump (also the fallback while a sting has no asset).
	local cue = rewardLine and "Passed" or (accent == C.Danger and "Failed") or "Stamp"
	task.spawn(function()
		local sounds = require(script.Parent:WaitForChild("SoundClient"))
		if not sounds.Play(cue) and cue ~= "Stamp" then
			sounds.Play("Stamp")
		end
	end)
	local titleColor = accent == C.Brand and C.Text or accent -- the brand pink would read as a cartoon
	local dy = kicker and 0 or m.Shift

	local frame = Instance.new("Frame")
	frame.Name = "Stamp"
	frame.BackgroundTransparency = 1
	frame.Active = false
	Theme.Place(frame, "Stamp", touch)
	frame.Parent = gui

	-- A dark band right across the screen behind the words (fading out at both ends), so they read over
	-- a bright sky.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.fromScale(touch and 1.3 or 1.9, 1)
	band.BackgroundColor3 = C.Shadow
	band.BackgroundTransparency = 0.4
	band.BorderSizePixel = 0
	band.ZIndex = 1
	band.Active = false
	band.Parent = frame
	local ends = Instance.new("UIGradient")
	ends.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	ends.Parent = band

	local head, late, tail = {}, {}, {} -- fades in: at once (kicker, title) / with the reward / last (sub)
	if kicker then
		local k = stampLine(frame, "Kicker", Theme.Font.Bold, m.KickerY, m.Kicker + 2, m.Kicker, accent)
		k.Text = string.upper(tostring(kicker))
		addFade(head, k)
	end

	-- The title: a box that slams in holding the drop shadow and the outlined words.
	local box = Instance.new("Frame")
	box.Name = "TitleBox"
	box.AnchorPoint = Vector2.new(0.5, 0.5) -- (centred, so the slam shrinks toward the middle)
	box.Position = UDim2.new(0.5, 0, 0, m.TitleY + dy + (m.Title + 4) / 2)
	box.Size = UDim2.new(1, 0, 0, m.Title + 4)
	box.BackgroundTransparency = 1
	box.ZIndex = 2
	box.Parent = frame
	local drop = stampLine(box, "Drop", Theme.Font.Big, m.Drop, m.Title + 4, m.Title, C.Shadow)
	drop.Position = UDim2.new(0.5, m.Drop, 0, m.Drop)
	drop.Text = tostring(title)
	drop.TextTransparency = 0.35
	local dropStroke = Theme.Shadow(drop, m.Stroke)
	dropStroke.Transparency = 0.35
	addFade(head, drop)
	local titleLabel = stampLine(box, "Title", Theme.Font.Big, 0, m.Title + 4, m.Title, titleColor)
	titleLabel.Text = tostring(title)
	titleLabel.ZIndex = 3
	local outline = Theme.Shadow(titleLabel, m.Stroke)
	outline.Transparency = 0
	outline.LineJoinMode = Enum.LineJoinMode.Round
	addFade(head, titleLabel)

	local subY = m.SubY + dy
	local rewardLabel
	if rewardLine then
		rewardLabel = stampLine(frame, "Reward", Theme.Font.Big, m.RewardY + dy, m.Reward + 2, m.Reward, C.Text)
		rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		rewardLabel.Position = UDim2.new(0.5, 0, 0, m.RewardY + dy + (m.Reward + 2) / 2)
		rewardLabel.RichText = true
		rewardLabel.Text = rewardLine
		local rs = Theme.Shadow(rewardLabel, math.max(1.5, m.Stroke - 1))
		rs.Transparency = 0
		addFade(late, rewardLabel)
		subY = m.RewardSubY + dy
	end
	if sub then
		local s = stampLine(frame, "Sub", Theme.Font.Body, subY, touch and 30 or 40, m.Sub, C.Text)
		s.TextWrapped = true
		s.TextYAlignment = Enum.TextYAlignment.Top
		s.Text = tostring(sub)
		addFade(tail, s)
	end

	-- In: the band fades in, the title slams down into place, the reward pops a beat later, then the sub.
	fadeIn({ [band] = { BackgroundTransparency = 1 } }, TweenInfo.new(0.2))
	fadeIn(head, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	local boxScale = slam(box, 1.7, 0, 0.3)
	if rewardLabel then
		fadeIn(late, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.3))
		slam(rewardLabel, 1.5, 0.3, 0.26)
	end
	fadeIn(tail, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, rewardLabel and 0.5 or 0.2))
	-- Out: everything fades together over the last half second, the title swelling a little.
	task.delay(every - 0.5, function()
		local out = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeOut(head, out)
		fadeOut(late, out)
		fadeOut(tail, out)
		fadeOut({ [band] = { BackgroundTransparency = 1 } }, out)
		TweenService:Create(boxScale, out, { Scale = 1.06 }):Play()
		task.wait(0.5)
		frame:Destroy()
	end)
	return every
end

------------------------------------------------------------------ mission intro

-- Its own ScreenGui, made on first use: edge to edge (no safe-area insets, so the bars reach past a
-- phone's notch and over its home bar), over the HUD layers and under the phone (INTRO.Order).
local function introScreen()
	if intro.gui and intro.gui.Parent then
		return intro.gui
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "MissionIntro"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = INTRO.Order
	sg.Parent = player:WaitForChild("PlayerGui")
	intro.gui = sg
	return sg
end

-- The title's text size: m.Title, or smaller (never under m.MinTitle) when a long title would be wider
-- than `width` pixels. Measured in the script face itself (this waits for the font to load, which it must
-- before the title can draw anyway); m.Title when it can't be measured.
local function introTitleSize(text, m, width)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = INTRO.Font
	params.Size = m.Title
	params.Width = 100000 -- (one line: no wrapping)
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	if ok and typeof(bounds) == "Vector2" and bounds.X > width then
		return math.max(m.MinTitle, math.floor(m.Title * width / bounds.X))
	end
	return m.Title
end

-- Draws one intro and schedules its way out; returns how long it owns the screen (seconds).
showIntro = function(title, sub, seconds)
	local hold = math.clamp(tonumber(seconds) or INTRO.Hold, 1, 10)
	local touch = Theme.IsTouch()
	local m = touch and INTRO.Touch or INTRO.Desktop
	local sg = introScreen()
	local screen = sg.AbsoluteSize
	if screen.X <= 0 or screen.Y <= 0 then
		local cam = Workspace.CurrentCamera
		screen = cam and cam.ViewportSize or Vector2.new(844, 390)
	end
	local text = tostring(title)
	local size = introTitleSize(text, m, screen.X * m.Width - 2 * m.Drop - 8)
	-- A sting for the moment: Config.Sounds' "Intro" when it has one, else the stamp thump.
	task.spawn(function()
		local sounds = require(script.Parent:WaitForChild("SoundClient"))
		if not sounds.Play("Intro") then
			sounds.Play("Stamp")
		end
	end)

	local frame = Instance.new("Frame")
	frame.Name = "Intro"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.Parent = sg

	-- The letterbox: two black bars waiting just off the top and bottom edges. Sized as shares of the
	-- screen, so a phone turned meanwhile keeps them right.
	local function bar(name, top)
		local b = Instance.new("Frame")
		b.Name = name
		b.AnchorPoint = Vector2.new(0, top and 0 or 1)
		b.Position = UDim2.fromScale(0, top and -INTRO.Bar or 1 + INTRO.Bar)
		b.Size = UDim2.fromScale(1, INTRO.Bar)
		b.BackgroundColor3 = C.Shadow
		b.BorderSizePixel = 0
		b.Active = false
		b.Parent = frame
		return b
	end
	local topBar, bottomBar = bar("TopBar", true), bar("BottomBar", false)

	-- The words, centred, standing just over the bottom bar's place: the title box (a soft dark drop
	-- shadow behind the title) over the sub line, which wraps (the box grows upward).
	local block = Instance.new("Frame")
	block.Name = "Words"
	block.AnchorPoint = Vector2.new(0.5, 1)
	block.Position = UDim2.new(0.5, 0, 1 - INTRO.Bar, -m.Gap)
	-- (On a short phone the Action zone, the GET IN / JACK button, stands higher than bar + Gap: the
	-- words then stay 8 px over it.)
	if touch and gui then
		local _, actionY = zoneBox("Action", true)
		local actionTop = actionY + gui.AbsolutePosition.Y - sg.AbsolutePosition.Y - 8
		if actionTop < screen.Y * (1 - INTRO.Bar) - m.Gap then
			block.Position = UDim2.new(0.5, 0, 0, math.floor(actionTop))
		end
	end
	block.Size = UDim2.new(m.Width, 0, 0, 0)
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.BackgroundTransparency = 1
	block.Active = false
	block.ZIndex = 2
	block.Parent = frame
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = block
	local titleBox = Instance.new("Frame")
	titleBox.Name = "TitleBox"
	titleBox.LayoutOrder = 1
	titleBox.Size = UDim2.new(1, 0, 0, math.ceil(size * INTRO.Line))
	titleBox.BackgroundTransparency = 1
	titleBox.Active = false
	titleBox.Parent = block
	local function titleLine(name, color, z)
		local l = Instance.new("TextLabel")
		l.Name = name
		Theme.Text(l, size, "Body")
		l.FontFace = INTRO.Font
		l.TextColor3 = color
		l.Size = UDim2.fromScale(1, 1)
		l.Text = text
		l.ZIndex = z
		l.Active = false
		l.Parent = titleBox
		return l
	end
	local drop = titleLine("Drop", C.Shadow, 1)
	drop.Position = UDim2.fromOffset(m.Drop, m.Drop)
	drop.TextTransparency = 0.55
	local dropEdge = drop:FindFirstChild("Shadow")
	if dropEdge then
		dropEdge:Destroy() -- (just the see-through dark copy)
	end
	local titleLabel = titleLine("Title", C.Text, 2)
	Theme.Shadow(titleLabel, m.Stroke)
	local head, tail = {}, {} -- fades in: the title (with its drop shadow), then the sub
	addFade(head, titleLabel)
	head[drop] = { TextTransparency = 1 }
	if sub ~= nil and tostring(sub) ~= "" then
		local s = Instance.new("TextLabel")
		s.Name = "Sub"
		s.LayoutOrder = 2
		Theme.Text(s, m.Sub, "Body")
		s.Size = UDim2.new(1, 0, 0, m.Sub + 4)
		s.AutomaticSize = Enum.AutomaticSize.Y
		s.TextWrapped = true
		s.Text = tostring(sub)
		s.Active = false
		s.Parent = block
		addFade(tail, s)
	end

	-- In: the bars slide in, then the title fades in (settling from a touch big to its size), the sub a
	-- beat later.
	local slideIn = TweenInfo.new(INTRO.Slide, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(topBar, slideIn, { Position = UDim2.fromScale(0, 0) }):Play()
	TweenService:Create(bottomBar, slideIn, { Position = UDim2.fromScale(0, 1) }):Play()
	fadeIn(head, TweenInfo.new(INTRO.FadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, INTRO.TitleAt))
	fadeIn(tail, TweenInfo.new(INTRO.FadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, INTRO.SubAt))
	local settle = Instance.new("UIScale")
	settle.Scale = 1.06
	settle.Parent = block
	TweenService:Create(settle, TweenInfo.new(INTRO.FadeIn + 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false,
		INTRO.TitleAt), { Scale = 1 }):Play()
	-- Out, after the hold: the words fade, the bars slide back off the edges a moment later.
	local outAt = INTRO.TitleAt + INTRO.FadeIn + hold
	local outFor = math.max(INTRO.FadeOut, INTRO.BarsOutAt + INTRO.Slide) + 0.05
	task.delay(outAt, function()
		local out = TweenInfo.new(INTRO.FadeOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeOut(head, out)
		fadeOut(tail, out)
		local slideOut = TweenInfo.new(INTRO.Slide, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, INTRO.BarsOutAt)
		TweenService:Create(topBar, slideOut, { Position = UDim2.fromScale(0, -INTRO.Bar) }):Play()
		TweenService:Create(bottomBar, slideOut, { Position = UDim2.fromScale(0, 1 + INTRO.Bar) }):Play()
		task.wait(outFor)
		frame:Destroy()
	end)
	return outAt + outFor
end

------------------------------------------------------------------ one-time notes

-- Module state lives for the whole session, so respawning doesn't repeat them.
local BAG_HINT = "Bank your bag at the Hideout - unbanked cash is lost if you leave."
local savesNoteShown = false
local bagHintShown, bagHintPending = false, false

-- Why nothing is being saved, in words that point at the fix.
local function savesOffText()
	if not RunService:IsStudio() then
		return "Saving is off on this server right now, so progress here won't be kept."
	elseif game.PlaceId == 0 then
		return "Test mode: progress isn't saved in Studio. Publish the game to turn saving on."
	end
	-- Published, but this Studio session isn't allowed to reach the saves.
	return "Test mode: progress isn't saved. Turn on Studio API access (Game Settings > Security) to save."
end

local function checkSavesOff()
	if savesNoteShown or ReplicatedStorage:GetAttribute("SavesOff") ~= true then
		return
	end
	savesNoteShown = true
	task.spawn(function()
		-- Wait for the side pick (toasts draw over the picker cards), then let the join stamps go first.
		local waited = 0
		while player:GetAttribute("HasPicked") ~= true and waited < 60 do
			waited += task.wait(0.5)
		end
		task.wait(3)
		NotifyController.Show(savesOffText(), nil, "info")
	end)
end

local function checkBag()
	if bagHintShown or bagHintPending or (player:GetAttribute("Carried") or 0) <= 0 then
		return
	end
	bagHintPending = true
	-- A beat after the "+$X in your bag" stamp, so the two don't arrive at once.
	task.delay(3, function()
		bagHintPending = false
		if (player:GetAttribute("Carried") or 0) > 0 then -- skip it if the bag was banked or lost meanwhile
			bagHintShown = true
			NotifyController.Show(BAG_HINT, nil, "info")
		end
	end)
end

------------------------------------------------------------------ start

function HUDController.Init()
	build()
	-- Health and armour are CombatClient's (Vitals zone): Roblox's own health bar would double them.
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false)
	showKeys = UserInputService.KeyboardEnabled and not Theme.IsTouch()
	layout()
	-- Re-place everything when the screen size or the kind of device changes (rotating a phone,
	-- resizing the window, plugging a mouse into a tablet); key caps follow the last input used.
	local camConn
	local function watchCamera()
		if camConn then
			camConn:Disconnect()
		end
		local cam = Workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
		end
		layout()
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(layout)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(layout)
	UserInputService.LastInputTypeChanged:Connect(updateKeys)

	refresh()
	for _, a in ipairs({ "Cash", "Carried", "Heat", "HeatSpotted", "Side" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	lastCash = player:GetAttribute("Cash")
	player:GetAttributeChangedSignal("Cash"):Connect(onCash)
	Remotes.OnClient("Banked", function(amount)
		-- (ProgressService gives Bank XP per $250 banked)
		local xp = Progression.XP.Bank * math.floor((tonumber(amount) or 0) / 250)
		HUDController.Stamp("CLEAN GETAWAY", "Banked at the Hideout", C.Cash, nil, { Cash = amount, XP = xp })
	end)
	-- Stars and the LOSING THEM meter every frame (snap-back when seen).
	player:GetAttributeChangedSignal("HeatSpotted"):Connect(snapBack)
	RunService.RenderStepped:Connect(update)
	-- Re-check the CAR button when getting in or out of a car.
	local function watch(character)
		local hum = character:WaitForChild("Humanoid", 10)
		if hum then
			hum:GetPropertyChangedSignal("SeatPart"):Connect(refresh)
		end
		refresh()
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
	-- One-time notes (the server may set SavesOff after this client has started).
	ReplicatedStorage:GetAttributeChangedSignal("SavesOff"):Connect(checkSavesOff)
	checkSavesOff()
	player:GetAttributeChangedSignal("Carried"):Connect(checkBag)
	checkBag()
end

return HUDController
