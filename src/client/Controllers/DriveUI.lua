-- DriveUI (ModuleScript, StarterPlayerScripts.Controllers.DriveUI)
-- The in-car HUD, shown only while driving or riding as a passenger. Flat "street" look (Shared.Util.Theme),
-- every piece in its Theme zone, re-placed whenever the device kind or the screen size changes.
--   * Driving, every device: the car cluster (frame "CarCluster"), a small stack, bottom-aligned:
--         RadioSlot   an empty 40 px row that SoundClient fills with the radio controls
--         Speed       the speed (big number + MPH), a DRIFT tag while sliding, the nitro bar
--     It fills Theme's "Corner" zone. Keyboard / gamepad: bottom-right corner, 300 x 110 (a 64 px
--     readout). Touch (pedals showing): bottom-centre, 300 x 92 (a 46 px readout), and narrower on small
--     phones so it stays between Roblox's thumbstick and the pedals.
--   * Any seat: EXIT (button "Exit", DriveUI.ExitButton) in Theme's "Exit" zone. It sends RequestExitCar
--     through DriveController.Exit, for the driver and for passengers alike.
--       keyboard / gamepad: bottom-right, just left of the cluster (88 x 44): a key cap from the last
--         input used (F on a keyboard, B on a gamepad, none after a touch) and the word;
--       phone: CAR's tile in the Buttons row, top-right (HUDController hides CAR while a seat is under
--         you, the same test as ours), drawn like that tile: a small door-and-arrow glyph over the word.
--     FLIP (button "Flip", DriveUI.FlipButton) only shows while the car lies on its roof or side, nearly
--     stopped: just above EXIT on a PC (key cap R, or the D-pad's up arrow), a tile just left of the
--     Buttons row on a phone. Its word is orange: something is wrong.
--   * Driving on a touch device: GAS and BRAKE pedals, NITRO, DRIFT, HORN and SMOKE buttons (frame
--     "Touch"). Steering stays on Roblox's thumbstick (it feeds the seat's SteerFloat). DRIFT turns gold
--     inside the drift zone (player attribute InDriftZone).
--   * Riding as a passenger: just EXIT (and the car's name).
--   * Keyboard / gamepad players: a controls strip (frame "ControlsHint": two rows of key caps on a flat
--     panel) the first time they drive each session (20 s) and again whenever they drive into the drift
--     zone (12 s). Its second row says how to drift: steer + handbrake, then hold the throttle and keep
--     steering. It stands directly on the cluster, right-aligned with it. Where the window is too narrow
--     to pass beside them it is lifted over the Subtitle zone's help text and over the minimap; in a
--     window too short to pass under the right-edge column (PHONE, CAR, the cop's tiles, END SHIFT) it
--     ends left of that column; and it is left out altogether if all that would put it on the Goal /
--     Banner zones. It waits while InteractClient's car name card (PlayerGui.Interact.CarCard, which
--     stands on the cluster for about 4 s after you sit down) is up: one thing at a time up there.
--   * The car's name (frame "CarName"): for 3 s after you sit down, the name in the script face (Kalam
--     Bold, the face AmbienceClient's area names use), white with a soft shadow, and the class small and
--     dim under it in Theme.Font.Bold ("NIGHT HERON" / "MUSCLE"). Keyboard / gamepad:
--     bottom-right, standing on the cluster (on the controls strip while that is up, over AmbienceClient's
--     area card if that is there, left of the right-edge column in a short window). Phone: top centre,
--     under the Banner zone; it waits up to 4 s for that spot to be free (a banner, a stamp, the area
--     card) and is skipped if it never is. Text only: it never takes a tap.
--     InteractClient names the car a driver sits down in with a card of its own; while that card is up
--     ours is not shown, so a car is never named twice. Ours is what passengers see, and what shows if
--     that card is ever taken out.
-- Pedals override the throttle so the thumbstick only steers. Icons and key caps first, very few words.
-- Other controllers:
--   DriveUI.RadioSlot   (Frame, exists right after Init, never destroyed) SoundClient parents its radio
--                       controls into it; they should fill it (Size 1,0,1,0). It is only visible while
--                       driving, and its width follows the cluster (300 px, 180-300 on small phones).
--   DriveUI.ExitButton  the EXIT button (see above for where it is now)
--   DriveUI.HintSpot()  -> anchor (Vector2), x, y: where a hint about EXIT goes (InteractClient's "Get
--                       out first"), in pixels from the top-left corner of a full-screen IgnoreGuiInset
--                       ScreenGui; nil while EXIT isn't showing. It is FLIP's spot (above EXIT on a PC,
--                       left of the Buttons row on a phone): the hint needs the car upright, FLIP needs
--                       it on its roof, so the two never meet.
--   DriveUI.ShowCarName(name, class?) -> true if it will show. Anyone may call it (a getting-in
--                       animation that wants the name on its own beat). DriveUI calls it itself 0.6 s
--                       after you sit down, unless DriveUI.AutoCarName is set to false, somebody else
--                       showed a name in the last 2 s, or InteractClient's CarCard is up.
--   DriveUI.IsTouch()   true when the phone pedals are showing
-- Constants are fields of K, the pieces fields of ui and what changes fields of S: the top level of a
-- script is one Luau function, and a function holds at most 200 locals.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DriveController = require(script.Parent:WaitForChild("DriveController"))
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)

local player = Players.LocalPlayer

local DriveUI = {}
DriveUI.AutoCarName = true -- (see the header)

local C = Theme.Color
local K = {}
K.STUDS_TO_MPH = 0.626 -- 1 stud ~ 0.28 m
K.CONTROLS_SECONDS = 20 -- the controls strip, first drive of the session
K.ZONE_SECONDS = 12 -- ...and again on driving into the drift zone
-- The cluster fills Theme's "Corner" zone (PC: bottom-right, 300 x 110, 24 px in; phone: bottom-centre,
-- 300 x 92, 10 px up), so the radio row's 40 px plus the gap leave a 64 / 46 px speed readout.
K.SLOT_HEIGHT = 40 -- the radio's row
K.LIST_GAP = 6
K.GAP = 12 -- the controls strip and the car's name keep this far from the HUD pieces around them
K.PEDAL_ALPHA = 0.45 -- how see-through an idle pedal is
K.TILE_GAP = 8 -- between the tiles of the phone's Buttons row (HUDController's TILE_GAP)
K.SEAT_GAP = 8 -- between EXIT and FLIP (or the hint in FLIP's place)
K.NAME_DELAY = 0.6 -- seconds after you sit down before the car's name shows (the door has shut by then)
K.NAME_SECONDS = 3 -- fully shown this long...
K.NAME_IN, K.NAME_OUT = 0.3, 0.6 -- ...after fading in, before fading out
K.NAME_WAIT = 4 -- phone: how long the name waits for its spot to be free before it is skipped
K.NAME_QUIET = 2 -- no name of our own this soon after somebody else showed one (ShowCarName)
K.NAME_W = 300 -- the name's box: as wide as the cluster
K.NAME_SLIDE = 14 -- PC: pixels it drifts in from the right while fading in
K.NAME_FONT = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold) -- the name's script face
K.NAME_SIZE, K.NAME_SIZE_TOUCH = 30, 22 -- its text size (the class line stays 13 px)
-- PC: tiles that can stand in the right-edge column between the Buttons zone and the cluster (paths
-- under PlayerGui; one that is missing or hidden is skipped).
K.SIDE_TILES = {
	{ "LawUI", "Taser" }, { "LawUI", "Spikes" }, { "ActivityUI", "EndShift" }, { "House", "LeaveHome" },
	{ "WardrobeUI", "Open" },
}
K.AREA_CARD = { "AreaName", "Card" } -- AmbienceClient's area name: it uses the car name's spots too
-- InteractClient's own card naming the car you just sat down to drive. It stands right on the cluster:
-- while it is up we show no name of our own, and the controls strip waits for it to go.
K.NAME_CARD = { "Interact", "CarCard" }
-- Phone: top-centre pieces the car's name never prints over (the same kind of list as SoundClient's
-- TITLE.CLEAR). HUDController's stamp has no name to look up: stampBand asks it.
K.NAME_CLEAR = {
	K.AREA_CARD, { "Tutorial", "Next" }, { "Objective", "Banner" }, { "Objective", "Escape" },
	{ "Mission", "Banner" }, { "BigScore", "Goal" }, { "BigScore", "Status" },
	{ "Crew", "CrewInvite" }, { "Offer", "Card" }, { "GPS", "Route" },
	{ "ActivityUI", "Timer" }, { "ActivityUI", "Checkpoint" }, { "ActivityUI", "Job" },
	{ "ActivityUI", "RacePreview" }, { "ActivityUI", "TurnCue" }, { "ActivityUI", "WrongWay" },
	{ "ActivityUI", "Countdown" }, { "ActivityUI", "Finish" }, { "ActivityUI", "DriftTeach" },
	{ "ActivityUI", "DriftScore" }, { "ActivityUI", "DriftStamp" }, { "CombatHUD", "Stamp" },
}

-- The pieces, set once by build():
--   gui, cluster, readout, speed, unit, driftTag, nitroWord, nitroBar, nitroFill
--   touch (the pedal block), smoke, drift
--   exit, exitRow, exitKey, exitGlyph, exitPad / flip, flipRow, flipKey
--   strip (the controls strip), keyRows, padRows
--   nameFrame, nameLabel, classLabel, nameShadow, classShadow
local ui = {}
local S = {
	controlsShown = false, -- the strip has had its first-drive showing this session
	controlsUntil = 0, -- os.clock() until the strip shows
	forceTouch = false, -- Studio preview of the phone layout
	lastKey = "", -- from the last input used: "F" (keyboard), "B" (gamepad) or "" (touch)
	wasDriving = false,
	placedTouch = nil, placedWidth = nil, placedHeight = nil, -- what everything was last laid out for
	shownMph = -1, shownFuel = -1, shownBoost = nil, shownAngle = -1, -- what the readout says now
	seatCar = nil, -- the car we sit in (driving or riding); nil on foot and on a plain seat
	nameAt = nil, -- os.clock() when the car's name is due (nil: none due)
	nameOn = false, -- a name is waiting for its spot, or showing
	nameFrom = nil, -- os.clock() it started fading in (nil: still waiting for its spot)
	nameGiveUp = 0, -- os.clock() after which a name still waiting is dropped
	namedAt = -math.huge, -- os.clock() of the last ShowCarName
	nameAlpha = 1, -- the fade the name is drawn with now (0 = fully shown)
	nameH = 47, -- how tall the name's box is on this device (place)
	hud = nil, -- HUDController, found on first use (false: not there)
}
local held = { Gas = false, Brake = false }
local idleText = {} -- [button] = text colour while it isn't pressed
local pressed = {} -- [button] = true while a hold button is down
local resets = {} -- one function per hold button: lets go of it

local function isTouch()
	return S.forceTouch or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
end
DriveUI.IsTouch = isTouch

-- The key that gets you out for an input type: F (keyboard / mouse), B (gamepad), "" (touch), or nil
-- for inputs that say nothing about the device (window focus, tilt sensors, mouse events on a device
-- with no mouse).
local function keyFor(inputType)
	local name = inputType.Name
	if string.sub(name, 1, 7) == "Gamepad" then
		return "B"
	elseif name == "Touch" then
		return ""
	elseif name == "Keyboard" or name == "TextInput" then
		return "F"
	elseif string.sub(name, 1, 5) == "Mouse" and UserInputService.MouseEnabled then
		return "F"
	end
	return nil
end

-- The key caps on EXIT and FLIP (none on the phone layout or its Studio preview, nor after a touch on a
-- PC with a touch screen), and the controls strip's rows for the same device.
local function refreshKeys()
	if not ui.exit then
		return -- not built yet
	end
	local key = isTouch() and "" or S.lastKey
	local pad = S.lastKey == "B"
	local flipKey = key == "" and "" or (pad and "↑" or "R") -- (DriveController: R, or D-pad up)
	if ui.exitKey.Text ~= key then
		ui.exitKey.Text = key
	end
	ui.exitKey.Visible = key ~= ""
	if ui.flipKey.Text ~= flipKey then
		ui.flipKey.Text = flipKey
	end
	ui.flipKey.Visible = flipKey ~= ""
	ui.keyRows.Visible = not pad
	ui.padRows.Visible = pad
end

------------------------------------------------------------------ buttons

-- Hold buttons paint their own pressed look: white with dark text while a finger is on them.
local function paint(b)
	local down = pressed[b] == true
	b.BackgroundColor3 = down and C.Text or C.Panel
	b.BackgroundTransparency = down and 0.15 or K.PEDAL_ALPHA
	b.TextColor3 = down and C.Panel or (idleText[b] or C.Text)
end

-- A pedal: a flat dark button with scaled Display text (sizes follow the screen height, so the text
-- does too). round = true: a circle (the thumb pedals); otherwise the Theme's small corners.
local function button(parent, name, text, size, pos, anchor, round)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.AnchorPoint = anchor or Vector2.new(1, 1)
	b.Text = text
	Theme.Button(b, "Quiet")
	b.FontFace = Theme.Font.Display
	b.TextScaled = true
	b.BackgroundTransparency = K.PEDAL_ALPHA
	if round then
		Theme.Corners(b).CornerRadius = UDim.new(0.5, 0)
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.22, 0), UDim.new(0.22, 0)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.12, 0), UDim.new(0.12, 0)
	pad.Parent = b
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 8
	limit.MaxTextSize = 30
	limit.Parent = b
	b.Parent = parent
	return b
end

-- Hold-style button: calls onChange(true) while any finger or click holds it.
-- Each touch is tracked by its own InputObject until that finger lifts or is cancelled, even if it
-- slid off the button first (GuiObject.InputEnded alone can miss that and leave GAS stuck on).
local function holdable(b, onChange)
	local active = {} -- [InputObject] = connection
	local isDown = false
	b.AutoButtonColor = false -- paint() does it
	local function set(down)
		if down == isDown then
			return
		end
		isDown = down
		pressed[b] = down or nil
		paint(b)
		onChange(down)
	end
	local function release(input)
		local conn = active[input]
		if conn then
			conn:Disconnect()
			active[input] = nil
		end
		if next(active) == nil then
			set(false)
		end
	end
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) and not active[input] then
			active[input] = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				local st = input.UserInputState
				if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
					release(input)
				end
			end)
			set(true)
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			release(input)
		end
	end)
	return function()
		for input in pairs(active) do
			release(input)
		end
		set(false)
	end
end

-- EXIT / FLIP: a flat dark button with two looks (placeSeat switches between them). PC: a row with a
-- key cap and the word. Phone: a tile, with the word as the button's own text. Returns the button, the
-- PC row and its key cap.
local function seatButton(name, word, color)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	Theme.Button(b, "Quiet")
	b.FontFace = Theme.Font.Display
	b.TextSize = 13
	b.TextColor3 = color
	Theme.Shadow(b)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = UDim2.fromScale(1, 1)
	row.BackgroundTransparency = 1
	row.Parent = b
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 7)
	list.Parent = row
	local cap = Theme.Key(row, "F")
	cap.LayoutOrder = 1
	cap.Visible = false
	local label = Instance.new("TextLabel")
	label.Name = "Word"
	label.LayoutOrder = 2
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 22)
	label.Text = word
	Theme.Text(label, 18, "Display")
	label.TextColor3 = color
	label.Parent = row
	b.Parent = ui.gui
	return b, row, cap
end

-- The phone tile's icon, drawn from frames like HUDController's CAR and PHONE glyphs: an open door
-- frame with an arrow leaving through it.
local function exitGlyph(parent)
	local g = Instance.new("Frame")
	g.Name = "Glyph"
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.new(0.5, 0, 0, 6)
	g.Size = UDim2.fromOffset(24, 18)
	g.BackgroundTransparency = 1
	g.Visible = false
	g.Parent = parent
	local function bar(x, y, w, h, turn) -- centred on (x, y)
		local f = Instance.new("Frame")
		f.Name = "Bar"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.Rotation = turn or 0
		f.BackgroundColor3 = C.Text
		f.BorderSizePixel = 0
		f.Parent = g
	end
	bar(2, 9, 2, 18) -- the door frame: hinge side...
	bar(7, 1, 12, 2) -- ...top...
	bar(7, 17, 12, 2) -- ...and bottom
	bar(15, 9, 14, 2) -- the arrow's shaft
	bar(20, 6.5, 8, 2, 45) -- its head: "\" over...
	bar(20, 11.5, 8, 2, -45) -- ..."/"
	return g
end

------------------------------------------------------------------ controls strip

-- One row of the strip: key caps and short words, left to right.
-- items: { "key", "F" } a key cap, { "word", "Exit" } plain text, { "title", "DRIFT" } gold Display text.
local function stripRow(parent, order, items)
	local row = Instance.new("Frame")
	row.Name = "Row" .. order
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.fromOffset(0, 22)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 5)
	list.Parent = row
	for i, item in ipairs(items) do
		local kind, text = item[1], item[2]
		local obj
		if kind == "key" then
			obj = Theme.Key(row, text)
		else
			obj = Instance.new("TextLabel")
			obj.Name = "Word"
			obj.AutomaticSize = Enum.AutomaticSize.X
			obj.Size = UDim2.fromOffset(0, 22)
			obj.Text = text
			if kind == "title" then
				Theme.Text(obj, 16, "Display")
				obj.TextColor3 = C.Gold
			else
				Theme.Text(obj, 13, "Body")
			end
			obj.Parent = row
		end
		obj.LayoutOrder = i
	end
	row.Parent = parent
	return row
end

-- The rows for one kind of device, stacked.
local function stripRows(name, rows)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.AutomaticSize = Enum.AutomaticSize.XY
	holder.Size = UDim2.fromOffset(0, 0)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 5)
	list.Parent = holder
	for i, items in ipairs(rows) do
		stripRow(holder, i, items)
	end
	holder.Parent = ui.strip
	return holder
end

------------------------------------------------------------------ where things go

-- A Theme zone's box on this screen, in pixels from the top-left corner of our full-screen gui: x, y,
-- width, height.
local function zoneBox(name, touch, view)
	local z = Theme.Zone(name, touch)
	local w = z.Size.X.Scale * view.X + z.Size.X.Offset
	local h = z.Size.Y.Scale * view.Y + z.Size.Y.Offset
	return z.Pos.X.Scale * view.X + z.Pos.X.Offset - z.Anchor.X * w, z.Pos.Y.Scale * view.Y + z.Pos.Y.Offset - z.Anchor.Y * h, w, h
end

-- A piece of another ScreenGui (path under PlayerGui) while it shows: x, y, width, height in the same
-- pixels (AbsolutePosition starts under the top bar whatever IgnoreGuiInset says, so it is measured
-- from our own gui's corner). nil when it is missing or hidden.
local function liveBox(path)
	local playerGui = player:FindFirstChild("PlayerGui")
	local sg = playerGui and playerGui:FindFirstChild(path[1])
	local obj = sg and sg:FindFirstChild(path[2])
	if obj and obj:IsA("GuiObject") and obj.Visible and sg:IsA("ScreenGui") and sg.Enabled then
		local p, s = obj.AbsolutePosition - ui.gui.AbsolutePosition, obj.AbsoluteSize
		return p.X, p.Y, s.X, s.Y
	end
	return nil
end

-- PC: the right-edge column (PHONE and CAR in the Buttons zone, the tiles under them). A piece whose
-- rows (top .. bottom) reach into the column's ends left of it: returns the right edge to use.
local function leftOfColumn(right, top, bottom, view)
	local gap = K.GAP
	local bx, by, _, bh = zoneBox("Buttons", false, view)
	if top < by + bh + gap and bottom > by - gap then
		right = math.min(right, bx - gap)
	end
	for _, path in ipairs(K.SIDE_TILES) do
		local x, y, _, h = liveBox(path)
		if x and top < y + h + gap and bottom > y - gap then
			right = math.min(right, x - gap)
		end
	end
	return right
end

-- The controls strip stands on the cluster, right-aligned with it (see the header for what it steps
-- over or beside). Returns false when the only room left is the Goal / Banner zones: it isn't shown.
local function placeStrip(view)
	local size = ui.strip.AbsoluteSize
	local w, h = size.X, size.Y
	local gap = K.GAP
	local cx, cy, cw = zoneBox("Corner", false, view) -- (the cluster fills it: place)
	local sx, sy, sw, sh = zoneBox("Subtitle", false, view)
	local mx, my, mw = zoneBox("Minimap", false, view)
	local right, bottom = cx + cw, cy - gap
	-- Every rule only ever moves the strip up or to the left, and a move can bring it into another
	-- rule's way: a few rounds settle it.
	for _ = 1, 3 do
		local oldRight, oldBottom = right, bottom
		if right - w < sx + sw + gap and right > sx - gap and bottom > sy - gap and bottom - h < sy + sh + gap then
			bottom = sy - gap -- over the help text
		end
		if right - w < mx + mw + gap and bottom > my - gap then
			bottom = my - gap -- over the minimap (the health strip is under it)
		end
		right = leftOfColumn(right, bottom - h, bottom, view)
		if right == oldRight and bottom == oldBottom then
			break
		end
	end
	right = math.max(right, math.min(w + 8, view.X)) -- (never off the left edge)
	local _, by, _, bh = zoneBox("Banner", false, view)
	if bottom - h < by + bh + gap then
		return false
	end
	ui.strip.Position = UDim2.fromOffset(math.floor(right), math.floor(bottom))
	return true
end

-- EXIT and FLIP into Theme's "Exit" zone, in the look for this device.
local function placeSeat(touch)
	local exit, flip = ui.exit, ui.flip
	local z = Theme.Zone("Exit", touch)
	if touch then
		-- On a phone the Exit zone IS the Buttons row: EXIT takes CAR's tile (slot 2, the right-hand
		-- one), laid out the way HUDController.placeTile lays that tile out. FLIP gets a tile of the same
		-- size just left of the row.
		local w, h = z.Size.X.Offset, z.Size.Y.Offset
		local tile = math.floor((w - K.TILE_GAP) / 2)
		local left = z.Pos.X.Offset - z.Anchor.X * w
		local y = z.Pos.Y.Offset - z.Anchor.Y * h
		exit.AnchorPoint = Vector2.zero
		exit.Position = UDim2.new(z.Pos.X.Scale, left + tile + K.TILE_GAP, z.Pos.Y.Scale, y)
		exit.Size = UDim2.fromOffset(tile, h)
		flip.AnchorPoint = Vector2.zero
		flip.Position = UDim2.new(z.Pos.X.Scale, left - K.TILE_GAP - tile, z.Pos.Y.Scale, y)
		flip.Size = UDim2.fromOffset(tile, h)
	else
		exit.AnchorPoint = z.Anchor
		exit.Position = z.Pos
		exit.Size = z.Size
		flip.AnchorPoint = z.Anchor
		flip.Position = z.Pos - UDim2.fromOffset(0, z.Size.Y.Offset + K.SEAT_GAP)
		flip.Size = z.Size
	end
	ui.exitRow.Visible = not touch
	ui.exitGlyph.Visible = touch
	exit.Text = touch and "EXIT" or ""
	ui.exitPad.PaddingBottom = UDim.new(0, touch and 4 or 0)
	ui.flipRow.Visible = not touch
	flip.Text = touch and "FLIP" or ""
end

-- Lay everything out for this device and screen. The cluster: Theme's Corner zone (where, how wide,
-- how tall). Touch: bottom-centre, a shorter readout, and no wider than the gap between the screen's
-- middle and the leftmost pedal (SMOKE) allows.
local function place(touch, view)
	S.placedTouch, S.placedWidth, S.placedHeight = touch, view.X, view.Y
	local zone = Theme.Zone("Corner", touch)
	local width = zone.Size.X.Offset
	-- (whatever the zone says, the readout stays big enough for its number, bar and tag)
	local readoutH = math.clamp(zone.Size.Y.Offset - K.SLOT_HEIGHT - K.LIST_GAP, 44, 64)
	if touch then
		local pedals = view.Y * 0.52 -- the pedal block: this square, 20 px in from the corner
		local smokeLeft = view.X - 20 - pedals * 0.94
		width = math.clamp(math.floor(2 * (smokeLeft - 8 - view.X / 2)), math.min(180, width), width)
	end
	ui.cluster.AnchorPoint = zone.Anchor
	ui.cluster.Position = zone.Pos
	ui.cluster.Size = UDim2.fromOffset(width, K.SLOT_HEIGHT + K.LIST_GAP + readoutH)
	ui.readout.Size = UDim2.new(1, 0, 0, readoutH)
	-- Right: the number with MPH on its baseline. Left: the DRIFT tag over the word NITRO. The bar
	-- runs along the bottom.
	local number = touch and 32 or 46
	local top = touch and 1 or 3
	ui.speed.TextSize = number
	ui.speed.Size = UDim2.fromOffset(120, number)
	ui.speed.Position = UDim2.new(1, -52, 0, top)
	ui.unit.Position = UDim2.new(1, -46, 0, top + number - 19)
	ui.driftTag.TextSize = touch and 15 or 18
	ui.driftTag.Position = UDim2.fromOffset(12, touch and 4 or 8)
	ui.nitroWord.Position = UDim2.new(0, 12, 1, touch and -24 or -28)
	ui.nitroBar.Position = UDim2.new(0.5, 0, 1, touch and -6 or -8)

	placeSeat(touch)
	refreshKeys()

	-- The car's name: right-aligned on a PC (it stands on the cluster), centred on a phone (top centre).
	-- The class tucks up into the bottom of the name's box: the script face keeps room under its line for
	-- tails, and an upper-case name has none.
	local nameSize = touch and K.NAME_SIZE_TOUCH or K.NAME_SIZE
	local align = touch and Enum.TextXAlignment.Center or Enum.TextXAlignment.Right
	ui.nameLabel.TextSize = nameSize
	ui.nameLabel.Size = UDim2.new(1, 0, 0, nameSize + 4)
	ui.nameLabel.TextXAlignment = align
	ui.classLabel.Position = UDim2.fromOffset(0, nameSize + 1)
	ui.classLabel.TextXAlignment = align
	S.nameH = nameSize + 1 + 16
end

------------------------------------------------------------------ the car's name

-- HUDController's big moment stamp while one shows: its top and bottom in pixels from the top of the
-- screen, else nil. It is drawn with no name to look up, so ask HUDController (found on first use: it
-- starts after us).
local function stampBand(view)
	if S.hud == nil then
		local module = script.Parent:FindFirstChild("HUDController")
		local ok, found = false, nil
		if module then
			ok, found = pcall(require, module)
		end
		S.hud = ok and type(found) == "table" and found or false
	end
	local hud = S.hud
	if not hud or type(hud.StampTop) ~= "function" then
		return nil
	end
	local top, bottom = hud.StampTop()
	if type(top) ~= "number" then
		return nil
	end
	if type(bottom) ~= "number" then
		local _, _, _, h = zoneBox("Stamp", true, view) -- (the stamp fills its zone)
		bottom = top + h
	end
	return top, bottom
end

local function setNameFade(a) -- 0 = fully shown, 1 = gone
	ui.nameLabel.TextTransparency = a
	ui.classLabel.TextTransparency = a
	ui.nameShadow.Transparency = 0.45 + 0.55 * a
	ui.classShadow.Transparency = 0.45 + 0.55 * a
end

local function hideName()
	S.nameOn = false
	S.nameFrom = nil
	if ui.nameFrame.Visible then
		ui.nameFrame.Visible = false
	end
end

-- Put the name in its spot for right now (see the header). slide = pixels it still has to drift in
-- (PC). Returns false when the spot isn't free: the name isn't drawn this frame.
local function placeName(touch, view, slide)
	local frame = ui.nameFrame
	local w, h = K.NAME_W, S.nameH
	if touch then
		w = math.min(w, math.floor(view.X * 0.5))
		local _, by, _, bh = zoneBox("Banner", true, view)
		local x, y = view.X / 2 - w / 2, by + bh + K.SEAT_GAP
		for _, path in ipairs(K.NAME_CLEAR) do
			local px, py, pw, ph = liveBox(path)
			if px and px < x + w and px + pw > x and py < y + h and py + ph > y then
				return false
			end
		end
		local stampTop, stampBottom = stampBand(view)
		if stampTop and stampTop < y + h and stampBottom > y then
			return false
		end
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.fromOffset(math.floor(view.X / 2), math.floor(y))
		frame.Size = UDim2.fromOffset(w, h)
		return true
	end
	local cx, cy, cw = zoneBox("Corner", false, view)
	local right, bottom = cx + cw, cy - K.GAP
	if ui.strip.Visible then
		-- The controls strip stands on the cluster: the name stands on the strip.
		local p = ui.strip.AbsolutePosition - ui.gui.AbsolutePosition
		right, bottom = p.X + ui.strip.AbsoluteSize.X, p.Y - K.SEAT_GAP
	end
	local ax, ay, aw, ah = liveBox(K.AREA_CARD)
	if ax and ax < right and ax + aw > right - w and ay < bottom and ay + ah > bottom - h then
		bottom = ay - K.SEAT_GAP -- AmbienceClient's area name is up there: over it
	end
	right = leftOfColumn(right, bottom - h, bottom, view)
	local _, by, _, bh = zoneBox("Banner", false, view)
	if bottom - h < by + bh + K.GAP then
		return false -- (a window this short has no room that isn't the Goal / Banner zones)
	end
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.fromOffset(math.floor(right + slide), math.floor(bottom))
	frame.Size = UDim2.fromOffset(w, h)
	return true
end

-- Every frame while seated: the name waits for its spot, fades in, stays, fades out.
local function updateName(now, touch, view)
	if not S.nameOn then
		return
	end
	if not S.nameFrom then
		if placeName(touch, view, 0) then
			S.nameFrom = now
		else
			if now > S.nameGiveUp then
				hideName()
			end
			return
		end
	end
	local t = now - S.nameFrom
	if t >= K.NAME_IN + K.NAME_SECONDS + K.NAME_OUT then
		hideName()
		return
	end
	local a, slide = 0, 0
	if t < K.NAME_IN then
		a = 1 - t / K.NAME_IN
		slide = touch and 0 or a * a * K.NAME_SLIDE
	elseif t > K.NAME_IN + K.NAME_SECONDS then
		a = (t - K.NAME_IN - K.NAME_SECONDS) / K.NAME_OUT
	end
	local fits = placeName(touch, view, slide)
	if ui.nameFrame.Visible ~= fits then
		ui.nameFrame.Visible = fits
	end
	if a ~= S.nameAlpha then
		S.nameAlpha = a
		setNameFade(a)
	end
end

-- (see the header) The name only draws while you sit in a seat: called a moment before that, it
-- comes up as soon as you do.
function DriveUI.ShowCarName(name, class)
	if type(name) ~= "string" or name == "" or not ui.nameFrame or player:GetAttribute("TitleScreen") == true then
		return false
	end
	local now = os.clock()
	local kind = (type(class) == "string" and class ~= "") and string.upper(class) or ""
	ui.nameLabel.Text = string.upper(name)
	ui.classLabel.Text = kind
	ui.classLabel.Visible = kind ~= ""
	ui.nameFrame.Visible = false
	S.namedAt = now
	S.nameOn = true
	S.nameFrom = nil
	S.nameGiveUp = now + K.NAME_WAIT
	S.nameAlpha = 1
	setNameFade(1)
	return true
end

------------------------------------------------------------------ build

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui

	-- The car cluster: the radio's slot over the speed readout (place() sizes and positions it).
	local cluster = Instance.new("Frame")
	cluster.Name = "CarCluster"
	cluster.BackgroundTransparency = 1
	cluster.Visible = false
	cluster.Parent = gui
	ui.cluster = cluster
	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.VerticalAlignment = Enum.VerticalAlignment.Bottom
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, K.LIST_GAP)
	stack.Parent = cluster

	local radioSlot = Instance.new("Frame")
	radioSlot.Name = "RadioSlot"
	radioSlot.LayoutOrder = 1
	radioSlot.Size = UDim2.new(1, 0, 0, K.SLOT_HEIGHT)
	radioSlot.BackgroundTransparency = 1
	radioSlot.Parent = cluster
	DriveUI.RadioSlot = radioSlot

	local readout = Instance.new("Frame")
	readout.Name = "Speed"
	readout.LayoutOrder = 2
	Theme.Panel(readout)
	readout.Parent = cluster
	ui.readout = readout
	local speed = Instance.new("TextLabel")
	speed.Name = "Number"
	speed.AnchorPoint = Vector2.new(1, 0)
	speed.TextXAlignment = Enum.TextXAlignment.Right
	speed.Text = "0"
	Theme.Text(speed, 46, "Display")
	speed.Parent = readout
	ui.speed = speed
	local unit = Instance.new("TextLabel")
	unit.Name = "Unit"
	unit.Size = UDim2.fromOffset(36, 14)
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.Text = "MPH"
	Theme.Text(unit, 12, "Bold")
	unit.TextColor3 = C.Dim
	unit.Parent = readout
	ui.unit = unit
	local driftTag = Instance.new("TextLabel")
	driftTag.Name = "Drift"
	driftTag.Size = UDim2.fromOffset(110, 20)
	driftTag.TextXAlignment = Enum.TextXAlignment.Left
	driftTag.Text = "DRIFT"
	Theme.Text(driftTag, 18, "Display")
	driftTag.TextColor3 = C.Gold
	driftTag.Visible = false
	driftTag.Parent = readout
	ui.driftTag = driftTag
	local nitroWord = Instance.new("TextLabel")
	nitroWord.Name = "NitroWord"
	nitroWord.Size = UDim2.fromOffset(60, 12)
	nitroWord.TextXAlignment = Enum.TextXAlignment.Left
	nitroWord.Text = "NITRO"
	Theme.Text(nitroWord, 10, "Bold")
	nitroWord.TextColor3 = C.Dim
	nitroWord.Parent = readout
	ui.nitroWord = nitroWord
	ui.nitroBar, ui.nitroFill = Theme.Bar(readout, C.BrandAlt)
	ui.nitroBar.Name = "NitroBar"
	ui.nitroBar.AnchorPoint = Vector2.new(0.5, 1)
	ui.nitroBar.Size = UDim2.new(1, -24, 0, 5)

	-- Touch controls, bottom right (sizes follow the screen height).
	local touchFrame = Instance.new("Frame")
	touchFrame.Name = "Touch"
	touchFrame.AnchorPoint = Vector2.new(1, 1)
	touchFrame.Position = UDim2.new(1, -20, 1, -20)
	touchFrame.Size = UDim2.fromScale(0.52, 0.52)
	touchFrame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	touchFrame.BackgroundTransparency = 1
	touchFrame.Parent = gui
	ui.touch = touchFrame

	local gas = button(touchFrame, "Gas", "GAS", UDim2.fromScale(0.42, 0.42), UDim2.fromScale(1, 1), nil, true)
	local brake = button(touchFrame, "Brake", "BRAKE", UDim2.fromScale(0.33, 0.33), UDim2.fromScale(0.55, 1), nil, true)
	local nitro = button(touchFrame, "Nitro", "NITRO", UDim2.fromScale(0.3, 0.3), UDim2.fromScale(1, 0.55), nil, true)
	ui.drift = button(touchFrame, "Drift", "DRIFT", UDim2.fromScale(0.26, 0.26), UDim2.fromScale(0.66, 0.6), nil, true)
	table.insert(resets, holdable(gas, function(d)
		held.Gas = d
	end))
	table.insert(resets, holdable(brake, function(d)
		held.Brake = d
	end))
	table.insert(resets, holdable(nitro, function(d)
		DriveController.Input.Nitro = d
	end))
	table.insert(resets, holdable(ui.drift, function(d)
		DriveController.Input.Handbrake = d
	end))

	-- HORN (civilians) / SIREN (cops): the server decides which.
	local horn = button(touchFrame, "Horn", "HORN", UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.66, 0.3), nil, true)
	horn.Activated:Connect(function()
		Remotes.Event("RequestHorn"):FireServer()
	end)
	local function hornLabel()
		horn.Text = player:GetAttribute("Side") == "Cop" and "SIREN" or "HORN"
	end
	hornLabel()
	player:GetAttributeChangedSignal("Side"):Connect(hornLabel)

	-- SMOKE: only while wanted (the server checks too).
	ui.smoke = button(touchFrame, "Smoke", "SMOKE", UDim2.fromScale(0.24, 0.24), UDim2.fromScale(0.3, 0.62), nil, true)
	ui.smoke.Activated:Connect(function()
		Remotes.Event("RequestSmoke"):FireServer()
	end)

	-- EXIT and FLIP (placeSeat puts them in the Exit zone; other controllers find them by these names:
	-- InteractClient through DriveUI.ExitButton, MinimapClient and ActivityClient by "Exit" / "Flip").
	ui.exit, ui.exitRow, ui.exitKey = seatButton("Exit", "EXIT", C.Text)
	ui.exit.TextYAlignment = Enum.TextYAlignment.Bottom -- (the phone tile: glyph on top, word at the bottom)
	ui.exitPad = Instance.new("UIPadding")
	ui.exitPad.Parent = ui.exit
	ui.exitGlyph = exitGlyph(ui.exit)
	ui.exit.Activated:Connect(function()
		DriveController.Exit() -- any seat: driver, passenger, or a driver whose car is still loading
	end)
	DriveUI.ExitButton = ui.exit
	ui.flip, ui.flipRow, ui.flipKey = seatButton("Flip", "FLIP", C.Orange)
	ui.flip.TextSize = 16
	ui.flip.Visible = false
	ui.flip.Activated:Connect(function()
		DriveController.Flip()
	end)
	DriveUI.FlipButton = ui.flip

	-- Controls strip (keyboard / gamepad): two rows of key caps on a flat panel. The second row is the
	-- drift how-to. placeStrip() stands it on the cluster.
	local strip = Instance.new("Frame")
	strip.Name = "ControlsHint"
	strip.AnchorPoint = Vector2.new(1, 1)
	strip.AutomaticSize = Enum.AutomaticSize.XY
	strip.Size = UDim2.fromOffset(0, 0)
	Theme.Panel(strip)
	strip.Visible = false
	strip.Parent = gui
	ui.strip = strip
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 7), UDim.new(0, 7)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = strip
	-- (a list, so the strip is only as big as the rows that are showing: keyboard or gamepad)
	local stripList = Instance.new("UIListLayout")
	stripList.FillDirection = Enum.FillDirection.Vertical
	stripList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stripList.SortOrder = Enum.SortOrder.LayoutOrder
	stripList.Parent = strip
	ui.keyRows = stripRows("Keyboard", {
		{ { "key", "F" }, { "word", "Exit" }, { "key", "SHIFT" }, { "word", "Nitro" }, { "key", "H" }, { "word", "Horn" },
			{ "key", "V" }, { "word", "Radio" }, { "key", "RMB" }, { "word", "Look" } },
		-- (the slide only holds while you steer into it: CarPhysics. Letting go of A / D ends it.)
		{ { "title", "DRIFT" }, { "key", "A" }, { "key", "D" }, { "word", "+" }, { "key", "SPACE" },
			{ "word", "then hold" }, { "key", "W" }, { "word", "+ keep steering" } },
	})
	ui.padRows = stripRows("Gamepad", {
		{ { "key", "B" }, { "word", "Exit" }, { "key", "Y" }, { "word", "Nitro" }, { "key", "D-PAD" }, { "word", "Radio" }, { "key", "RS" }, { "word", "Look" } },
		{ { "title", "DRIFT" }, { "word", "steer +" }, { "key", "X" }, { "word", "then hold" }, { "key", "RT" },
			{ "word", "+ keep steering" } },
	})
	ui.padRows.Visible = false

	-- The car's name (ShowCarName). Labels only: it never takes a tap.
	local nameFrame = Instance.new("Frame")
	nameFrame.Name = "CarName"
	nameFrame.BackgroundTransparency = 1
	nameFrame.Size = UDim2.fromOffset(K.NAME_W, S.nameH)
	nameFrame.Visible = false
	nameFrame.Parent = gui
	ui.nameFrame = nameFrame
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, K.NAME_SIZE + 4)
	nameLabel.Text = ""
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Text(nameLabel, K.NAME_SIZE)
	nameLabel.FontFace = K.NAME_FONT
	ui.nameShadow = Theme.Shadow(nameLabel, 2)
	nameLabel.Parent = nameFrame
	ui.nameLabel = nameLabel
	local classLabel = Instance.new("TextLabel")
	classLabel.Name = "Class"
	classLabel.Position = UDim2.fromOffset(0, K.NAME_SIZE + 1)
	classLabel.Size = UDim2.new(1, 0, 0, 16)
	classLabel.Text = ""
	Theme.Text(classLabel, 13, "Bold")
	classLabel.TextColor3 = C.Dim
	ui.classShadow = Theme.Shadow(classLabel)
	classLabel.Parent = nameFrame
	ui.classLabel = classLabel
	setNameFade(1)
end

------------------------------------------------------------------ every frame

-- The seat under us while we're alive, else nil. Any seat counts: a passenger, or a driver whose car is
-- still loading, gets EXIT too, so nobody is ever stuck in a seat.
local function seatPart()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return hum.SeatPart
end

-- Can this device use the strip's key caps?
local function hasKeys()
	return not isTouch() and (UserInputService.KeyboardEnabled or UserInputService.GamepadEnabled)
end

local function update()
	local status = DriveController.Status
	local driving = status.Driving == true
	local seat = not driving and seatPart() or nil
	local passenger = seat ~= nil
	local seated = driving or passenger
	-- (nothing of the HUD shows over the first-join title screen, whatever the character sits on)
	local shown = seated and player:GetAttribute("TitleScreen") ~= true
	if ui.gui.Enabled ~= shown then
		ui.gui.Enabled = shown
	end
	local now = os.clock()
	if driving ~= S.wasDriving then
		S.wasDriving = driving
		-- First drive this session with keys or a gamepad: show the controls for a while.
		if driving and not S.controlsShown and hasKeys() then
			S.controlsShown = true
			S.controlsUntil = now + K.CONTROLS_SECONDS
		end
		if not driving then
			held.Gas, held.Brake = false, false
			for _, r in ipairs(resets) do
				r()
			end
			DriveController.Input.Throttle = nil
		end
	end
	-- The car we sit in (a bench or a chair is no car): a new one gets its name on screen in a moment.
	local car = nil
	if driving then
		car = status.Car
	elseif passenger then
		local model = seat.Parent
		if model and model:IsA("Model") and model:GetAttribute("NCVehicle") == true then
			car = model
		end
	end
	if car ~= S.seatCar then
		S.seatCar = car
		S.nameAt = car and (now + K.NAME_DELAY) or nil
		if not car then
			hideName()
		end
	end
	if not seated then
		return
	end
	local touch = isTouch()
	local view = ui.gui.AbsoluteSize
	if touch ~= S.placedTouch or view.X ~= S.placedWidth or view.Y ~= S.placedHeight then
		place(touch, view)
	end
	if S.nameAt and car and now >= S.nameAt then
		S.nameAt = nil
		-- Not when the car has been named already: by a caller of ShowCarName a moment ago, or by
		-- InteractClient's card (drivers get that one; passengers and anything it misses get ours).
		if DriveUI.AutoCarName ~= false and now - S.namedAt > K.NAME_QUIET and liveBox(K.NAME_CARD) == nil then
			local id = car:GetAttribute("VehicleId")
			local def = type(id) == "string" and Vehicles.ById[id] or nil
			DriveUI.ShowCarName(car:GetAttribute("DisplayName") or (def and def.DisplayName), def and def.Class)
		end
	end
	if not driving then
		-- Passengers only get EXIT (and the car's name): the rest is the driver's.
		ui.cluster.Visible, ui.touch.Visible, ui.strip.Visible, ui.flip.Visible = false, false, false, false
		updateName(now, touch, view)
		return
	end
	ui.cluster.Visible = true
	ui.touch.Visible = touch
	-- (one thing at a time on the cluster: InteractClient's name card first, then the strip)
	local stripOn = not touch and now < S.controlsUntil and liveBox(K.NAME_CARD) == nil
	if stripOn then
		-- Shown first and placed every frame: its size is only known once it has been laid out.
		ui.strip.Visible = true
		stripOn = placeStrip(view)
	end
	if ui.strip.Visible ~= stripOn then
		ui.strip.Visible = stripOn
	end
	updateName(now, touch, view) -- (after the strip: the name stands on it)
	if touch then
		DriveController.Input.Throttle = (held.Gas and 1 or 0) - (held.Brake and 1 or 0)
	else
		DriveController.Input.Throttle = nil
	end
	local chassis = car and car.PrimaryPart
	-- The real speed over the ground (in a drift the car moves faster than its nose does). Labels are
	-- only rewritten when the shown value changes.
	local speed = math.abs(status.Speed)
	if chassis then
		local v = chassis.AssemblyLinearVelocity
		speed = math.sqrt(v.X * v.X + v.Z * v.Z)
	end
	local mph = math.floor(speed * K.STUDS_TO_MPH + 0.5)
	if mph ~= S.shownMph then
		S.shownMph = mph
		ui.speed.Text = tostring(mph)
	end
	local fuel = math.clamp(status.NitroFuel, 0, 1)
	if math.abs(fuel - S.shownFuel) > 0.004 then
		S.shownFuel = fuel
		ui.nitroFill.Size = UDim2.fromScale(fuel, 1)
	end
	if status.NitroActive ~= S.shownBoost then
		S.shownBoost = status.NitroActive
		ui.nitroFill.BackgroundColor3 = S.shownBoost and C.Orange or C.BrandAlt
	end
	local drifting = status.Drifting == true
	if ui.driftTag.Visible ~= drifting then
		ui.driftTag.Visible = drifting
	end
	if drifting then
		local angle = math.floor(status.SlipAngle + 0.5)
		if angle ~= S.shownAngle then
			S.shownAngle = angle
			ui.driftTag.Text = "DRIFT " .. angle .. "°"
		end
	end
	local wanted = player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) > 0
	ui.smoke.Visible = wanted
	ui.smoke.TextTransparency = (player:GetAttribute("SmokeCharges") or 0) > 0 and 0 or 0.6
	ui.flip.Visible = chassis ~= nil and chassis.CFrame.UpVector.Y < 0.5 and chassis.AssemblyLinearVelocity.Magnitude < 15
end

-- Inside the drift zone (DriftService sets InDriftZone): the phone's DRIFT button turns gold, and the
-- key strip comes back for a while so its drift row is on screen.
local function onDriftZone()
	local inZone = player:GetAttribute("InDriftZone") == true
	idleText[ui.drift] = inZone and C.Gold or nil
	paint(ui.drift)
	if inZone and DriveController.Status.Driving and hasKeys() then
		S.controlsShown = true
		S.controlsUntil = math.max(S.controlsUntil, os.clock() + K.ZONE_SECONDS)
	end
end

------------------------------------------------------------------ API and start

-- (see the header) FLIP's spot: above EXIT on a PC, left of the Buttons row on a phone.
function DriveUI.HintSpot()
	local exit = ui.exit
	if not exit or not ui.gui.Enabled or not exit.Visible then
		return nil
	end
	local p, s = exit.AbsolutePosition - ui.gui.AbsolutePosition, exit.AbsoluteSize
	if S.placedTouch then
		-- EXIT is the row's right-hand tile: one tile and a gap further left is the row's left edge, and
		-- FLIP's tile ends a gap left of that.
		return Vector2.new(1, 0.5), math.floor(p.X - s.X - 2 * K.TILE_GAP), math.floor(p.Y + s.Y / 2)
	end
	return Vector2.new(1, 1), math.floor(p.X + s.X), math.floor(p.Y - K.SEAT_GAP)
end

-- Studio only: preview the phone layout on a PC (DriveUI.PreviewTouch(true)).
function DriveUI.PreviewTouch(on)
	S.forceTouch = on == true
	refreshKeys()
end

function DriveUI.Init()
	build()
	place(isTouch(), ui.gui.AbsoluteSize)
	-- The key caps follow the last input used. Before any input, guess from the device.
	local first = keyFor(UserInputService:GetLastInputType())
	if first == nil then
		if isTouch() then
			first = ""
		elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
			first = "B"
		else
			first = UserInputService.KeyboardEnabled and "F" or ""
		end
	end
	S.lastKey = first
	refreshKeys()
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local key = keyFor(inputType)
		if key ~= nil and key ~= S.lastKey then
			S.lastKey = key
			refreshKeys()
		end
	end)
	player:GetAttributeChangedSignal("InDriftZone"):Connect(onDriftZone)
	onDriftZone()
	RunService.RenderStepped:Connect(update)
	-- Keyboard: C drops smoke while driving and wanted.
	ContextActionService:BindAction("NC_Smoke", function(_, state)
		if state == Enum.UserInputState.Begin and DriveController.Status.Driving then
			Remotes.Event("RequestSmoke"):FireServer()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C, Enum.KeyCode.ButtonL1)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("PreviewTouch"):Connect(function()
			S.forceTouch = player:GetAttribute("PreviewTouch") == true
			refreshKeys()
		end)
	end
end

return DriveUI
