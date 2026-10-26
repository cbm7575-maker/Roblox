-- WardrobeUI (ModuleScript, StarterPlayerScripts.Controllers.WardrobeUI)
-- Inside a hideout (player attribute InHideout) or your own home (InHome, both set by the server) an
-- OUTFIT tile (button "Open": a hanger glyph over the word) appears in the side column under the Buttons
-- zone (LawClient.SideSlot: under HouseClient's LEAVE HOME at home, the top slot at a hideout); at home
-- the closet's "Change look" prompt (WardrobePrompt, built by HousingService) opens the room too, with
-- you facing away from the closet so it's the backdrop. Nothing shows while the first-join title screen
-- is up (player attribute TitleScreen).
-- It opens a dressing room (MY CLOSET at home) in the flat "street" menu look (Shared.Util.Theme): the
-- camera swings round to a portrait of your own character (which turns to face it), and a dark menu
-- panel (a left column on wide screens, a bottom sheet on tall ones) lists the hats and masks: a
-- Display title, one quiet hint line, HATS / MASKS tabs (the open one white and underlined), then one
-- row per item (a colour swatch, its name, WEARING or FREE on the right; the picked row is white with
-- dark text) and the WEAR IT / DONE button (on a phone's left column it sits in the turn / zoom bar
-- under the character instead, so the short list gets the room). The character stands in the clear
-- part of the screen.
-- Every pick shows on your character straight away, as a preview only you can see. WEAR IT sends the
-- look to the server (RequestDisguise), which checks you're really in a hideout or at home, puts it on
-- for everyone and handles the heat drop, at a hideout only (DisguiseService). So just browsing never
-- costs a star early or trips the server's rate limit.
-- Controls (key caps show for the keyboard or gamepad in use, none on touch):
--   keyboard  Q / E tabs, W / S or the arrows up / down pick, A / D or the arrows spin, Z zoom,
--             ENTER wear it, X close; the mouse clicks rows and drags across the picture to spin
--   gamepad   LT / RT tabs, A picks the selected row, LB / RB and the right stick spin, R3 zoom,
--             Y wear it (never from behind Roblox's own menu, where Y is Reset Character), B close
--   touch     tap a row, swipe across the picture or hold the turn arrows to spin, ZOOM, WEAR IT, the
--             close button (all at least Theme.Touch pixels tall)
-- ZOOM goes close on the face. Sitting in a car (or any seat) it tells you to hop out first.
-- The room always gives the camera and movement back: DONE / close, dying, getting in a seat, being
-- moved by the server, getting arrested (Side changes) or leaving the hideout or home all close it.
-- While the room is open the phone is kept shut (it would sit hidden behind the panel), Roblox's
-- player list, hotbar and chat window are hidden (the chat sits over the menu column), proximity
-- prompts are switched off on this screen (so E, gamepad X or a stray tap can't take you out of the
-- house or into a car mid-look), at home HouseClient's "House" ScreenGui (LEAVE HOME) is hidden, and
-- a cop's TASER / SPIKES tiles (LawClient's "LawUI" ScreenGui) go too (they'd float over the picture
-- on a phone, and T / G would still zap); all come back when it closes. The room draws over the
-- toasts (NotifyController, DisplayOrder 20), which would cover the list on a phone: a toast that
-- comes in meanwhile runs out unseen behind the panel.
-- WardrobeUI.IsOpen(), WardrobeUI.Close(). (InteractClient asks IsOpen: its GET IN / STEAL / JACK listen
-- for E, F and gamepad X by themselves, not through a prompt, so they stand down while the room is open;
-- E for the MASKS tab used to put you back in the car parked beside you at a hideout.)

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Disguises = require(ReplicatedStorage.Shared.Config.Disguises)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local WardrobeUI = {}

local C = Theme.Color
local INK = Color3.fromRGB(12, 14, 18) -- dark text on a white (picked) row, as on Theme's Primary button

local CAMERA_STEP = "NC_WardrobeCamera"
local PREVIEW_STEP = "NC_WardrobePreview"
local MARGIN = 12 -- between the panel, the orbit bar and the screen edges
local PANEL_MIN_W, PANEL_MAX_W = 270, 360 -- the left column on wide screens
local SIDE_MAX_H = 500
local SHEET_MIN_H, SHEET_MAX_H = 260, 430 -- the bottom sheet on tall screens
local ZOOM_W = 104 -- the ZOOM / FULL button in the orbit bar
local WEAR_BAR_W = 112 -- WEAR IT when it sits in the orbit bar (a phone's left column)
local LIFT = 0.14 -- camera height above the focus, as a share of its distance (looks slightly down)
local ORBIT_SPEED = math.rad(60) -- per second while an arrow or key is held
local NUDGE = math.rad(20) -- a single tap on an arrow
local DRAG_SPEED = math.rad(0.4) -- per pixel dragged across the picture
local MOVED_TOO_FAR = 6 -- studs: the server moved us (arrest, teleport), so the room closes
local CONFIRM_WAIT = 3 -- seconds to wait for the server to put the new look on
-- Roblox's own GUI that sits on top of the room: the player list and hotbar, and the chat window
-- (top-left on a PC, right over the menu column). Each comes back when the room closes.
local HIDE_CORE = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Chat }

-- Keys that spin the view (movement is switched off while the room is open, so A / D are free).
-- The D-pad only gets here when no button is selected; with a selection it moves between buttons.
local SPIN_KEYS = {
	[Enum.KeyCode.A] = -1,
	[Enum.KeyCode.Left] = -1,
	[Enum.KeyCode.DPadLeft] = -1,
	[Enum.KeyCode.D] = 1,
	[Enum.KeyCode.Right] = 1,
	[Enum.KeyCode.DPadRight] = 1,
}
-- Gamepad bumpers: GUI navigation doesn't use them, so they spin even with a row selected.
local PAD_SPIN = {
	[Enum.KeyCode.ButtonL1] = -1,
	[Enum.KeyCode.ButtonR1] = 1,
}
-- Keys that pick the item above / below the picked one in the open tab.
local STEP_KEYS = {
	[Enum.KeyCode.W] = -1,
	[Enum.KeyCode.Up] = -1,
	[Enum.KeyCode.DPadUp] = -1,
	[Enum.KeyCode.S] = 1,
	[Enum.KeyCode.Down] = 1,
	[Enum.KeyCode.DPadDown] = 1,
}
local TAB_KEYS = { [Enum.KeyCode.Q] = "hat", [Enum.KeyCode.E] = "mask" }
local PAD_TABS = { [Enum.KeyCode.ButtonL2] = "hat", [Enum.KeyCode.ButtonR2] = "mask" } -- (no gun is out behind a panel)
local STICK_DEADZONE = 0.25 -- right stick, for spinning too

local buttonGui, openButton
local roomGui, panel, bar, title, hint, closeButton, tabRow, wearButton, wearCap
local spinLeft, spinRight, zoomButton, spinCaption
local tabs = {} -- [kind] = { Button, Line, Grid }
local cards = {} -- one per item row: { Kind, Id, Button, Name, Tag }
local caps = {} -- key caps: { Cap, Keyboard, Gamepad, Pad (UIPadding to make room), PadBy }
local picked = { hat = "none", mask = "none" }
local tab = "hat"
local panelHome = UDim2.fromOffset(MARGIN, 64)
local panelAway = UDim2.fromOffset(-400, 64) -- where it slides in from
local panelTween
-- Where the character should sit on screen (the part the panel doesn't cover), worked out by layout().
local framing = { Side = true, Fov = 45, FreeW = 400, FreeH = 300, Ndc = Vector2.zero }
local room -- the open dressing room (see openRoom), nil when closed
local preview -- the local look preview (see startPreview), nil when off
local opening = false
local hold -- an orbit arrow being held: { Input, Dir }
local drag -- a drag across the picture: { Input, X }
local keyDir = 0 -- a spin key or bumper held (-1, 0 or 1)
local stickDir = 0 -- the right stick's sideways push (-1..1)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- see-through triggers and decorations don't push the camera in

local closeRoom -- defined further down; the room's safety checks call it

------------------------------------------------------------------ small helpers

-- Sizes in pixels: on a phone everything you tap is at least Theme.Touch tall.
local function metrics(touch)
	return {
		Row = touch and Theme.Touch or 36,
		Tab = touch and Theme.Touch or 36,
		Button = touch and Theme.Touch or 40,
		Close = touch and Theme.Touch or 32,
		Spin = touch and 48 or 44,
		Title = touch and 22 or 24,
	}
end

local function label(parent, name, str, size, kind)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Text = str
	Theme.Text(t, size, kind)
	t.Parent = parent
	return t
end

-- Another controller (they all live next to this one); nil if it's missing or broken.
local function controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, c = pcall(require, module)
	return ok and c or nil
end

local function sound(name)
	local s = controller("SoundClient")
	if s and s.Play then
		pcall(s.Play, name)
	end
end

-- A toast message (NotifyController); category as NotifyController.Show takes it.
local function tell(msg, category)
	local notify = controller("NotifyController")
	if notify and notify.Show then
		notify.Show(msg, nil, category)
	end
end

-- "keyboard", "gamepad" or "touch": which key caps (if any) to show.
local function inputMode()
	local name = UserInputService:GetLastInputType().Name
	if string.sub(name, 1, 7) == "Gamepad" then
		return "gamepad"
	elseif name == "Touch" or Theme.IsTouch() then
		return "touch"
	end
	return "keyboard"
end

local function gamepad()
	return inputMode() == "gamepad"
end

-- A key cap that follows the input in use (`keyboard` / `gamepad` text; nil = no cap for that one).
local function cap(parent, keyboard, gamepadKey)
	local k = Theme.Key(parent, keyboard or gamepadKey or "")
	k.ZIndex = 3
	k.Visible = false
	local entry = { Cap = k, Keyboard = keyboard, Gamepad = gamepadKey }
	table.insert(caps, entry)
	return k, entry
end

local function refreshCaps()
	local mode = inputMode()
	for _, c in ipairs(caps) do
		local text = (mode == "keyboard" and c.Keyboard) or (mode == "gamepad" and c.Gamepad) or nil
		c.Cap.Visible = text ~= nil
		if text and c.Cap.Text ~= text then
			c.Cap.Text = text
			c.Cap.Size = UDim2.fromOffset(math.max(22, 10 + #text * 9), 22) -- (as Theme.Key sizes it)
		end
		if c.Pad then
			-- The padding pushes the button's word right of the cap. It moves the cap too (a child), so
			-- the cap's own offset takes it back off again.
			local padLeft = text and c.Cap.Size.X.Offset + c.PadBy or 0
			c.Pad.PaddingLeft = UDim.new(0, padLeft)
			c.Cap.Position = UDim2.new(0, c.CapX - padLeft, 0.5, 0)
		end
	end
	if spinCaption then
		spinCaption.Text = mode == "gamepad" and "LB / RB to spin" or mode == "touch" and "Swipe to spin"
			or "Drag or A / D to spin"
	end
end

-- The phone (DisplayOrder 5) would open hidden behind the room (21), so the room keeps it shut.
local function shutPhone(phone)
	if phone and phone.IsOpen and phone.IsOpen() then
		phone.Close()
	end
end

-- Where a wardrobe is open to you right now: "hideout" (a new look can drop a star there), "home"
-- (your own inside: just a change of clothes) or nil.
local function wardrobeSpot()
	if player:GetAttribute("InHideout") == true then
		return "hideout"
	elseif player:GetAttribute("InHome") == true and player:GetAttribute("Touring") == nil then
		return "home" -- (a show home on a tour has no wardrobe: HousingService)
	end
	return nil
end

local function titleScreen()
	return player:GetAttribute("TitleScreen") == true
end

-- Why the room won't open while sitting (the OUTFIT tile shows in a car at the hideout, and on the
-- couch at home).
local function seatedMessage(hum)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if hum.SeatPart and vehicles and hum.SeatPart:IsDescendantOf(vehicles) then
		return "Hop out of your ride to change your look."
	end
	return "Stand up to change your look."
end

-- What the server says you're wearing right now.
local function worn(kind)
	return player:GetAttribute(kind == "hat" and "LookHat" or "LookMask") or "none"
end

local function changed()
	return picked.hat ~= worn("hat") or picked.mask ~= worn("mask")
end

-- Roblox's own movement controls (PlayerModule), so the room can switch walking off and on.
local function getControls()
	local ok, controls = pcall(function()
		local scripts = player:FindFirstChildOfClass("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		return module and require(module):GetControls()
	end)
	return ok and controls or nil
end

------------------------------------------------------------------ hat and mask parts

-- The same shapes and offsets as DisguiseService.apply (keep the two in step when adding a Kind).
local function piece(head, parent, size, offset, color, shape, material)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = head.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = head
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

local function dress(head, parent, hatId, maskId)
	local s = head.Size.Y / 1.2 -- scale offsets to the head size
	local hat = Disguises.HatById[hatId or "none"]
	if hat and hat.Kind == "cap" then
		piece(head, parent, Vector3.new(1.3, 0.55, 1.3) * s, CFrame.new(0, 0.62 * s, 0.02 * s), hat.Color)
		piece(head, parent, Vector3.new(1.15, 0.12, 0.7) * s, CFrame.new(0, 0.4 * s, -0.8 * s), hat.Color)
	elseif hat and hat.Kind == "bucket" then
		piece(head, parent, Vector3.new(0.6, 1.3, 1.3) * s, CFrame.new(0, 0.6 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), hat.Color, Enum.PartType.Cylinder)
		piece(head, parent, Vector3.new(0.12, 1.9, 1.9) * s, CFrame.new(0, 0.32 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), hat.Color, Enum.PartType.Cylinder)
	end
	local mask = Disguises.MaskById[maskId or "none"]
	if mask and mask.Kind == "bandana" then
		piece(head, parent, Vector3.new(1.28, 0.5, 0.22) * s, CFrame.new(0, -0.28 * s, -0.58 * s), mask.Color)
	elseif mask and mask.Kind == "shades" then
		piece(head, parent, Vector3.new(1.15, 0.26, 0.12) * s, CFrame.new(0, 0.12 * s, -0.62 * s), mask.Color, nil, Enum.Material.Neon)
	end
end

------------------------------------------------------------------ local preview on your character

-- The server's parts live in the character's "NCDisguise" folder.
local function isServerDisguisePart(inst)
	return inst:IsA("BasePart") and inst.Parent ~= nil and inst.Parent.Name == "NCDisguise"
end

local function dropPreview(p)
	if not p or p.Dropped then
		return
	end
	p.Dropped = true
	if preview == p then
		preview = nil
		RunService:UnbindFromRenderStep(PREVIEW_STEP)
	end
	p.Conn:Disconnect()
	p.Folder:Destroy()
	for part, old in pairs(p.Hidden) do
		if part.Parent then
			part.LocalTransparencyModifier = old
		end
	end
end

-- Hides the real (server) disguise on this screen only and gives the character a local "NCPreview"
-- folder that showLook() fills with the picked hat and mask.
local function startPreview(char, head)
	dropPreview(preview)
	local folder = Instance.new("Folder")
	folder.Name = "NCPreview"
	folder.Parent = char
	local p = { Head = head, Folder = folder, Hidden = {} } -- Hidden: [part] = its old modifier
	local function hide(part)
		if p.Hidden[part] == nil then
			p.Hidden[part] = part.LocalTransparencyModifier
		end
		part.LocalTransparencyModifier = 1
	end
	for _, d in ipairs(char:GetDescendants()) do
		if isServerDisguisePart(d) then
			hide(d)
		end
	end
	-- The server rebuilds its parts whenever the look changes; hide the new ones too.
	p.Conn = char.DescendantAdded:Connect(function(d)
		if isServerDisguisePart(d) then
			hide(d)
		end
	end)
	preview = p
	-- Every frame, after the default camera scripts (which can reset the modifier on character parts).
	RunService:BindToRenderStep(PREVIEW_STEP, Enum.RenderPriority.Camera.Value + 2, function()
		for part in pairs(p.Hidden) do
			if part.Parent then
				part.LocalTransparencyModifier = 1
			end
		end
	end)
	return p
end

local function showLook()
	local p = preview
	if not p or not p.Head.Parent then
		return
	end
	p.Folder:ClearAllChildren()
	dress(p.Head, p.Folder, picked.hat, picked.mask)
end

------------------------------------------------------------------ panel

-- The hint line and its colour: grey for plain advice, gold when a new look pays off, red for danger.
local function hintText()
	local heat = player:GetAttribute("Heat") or 0
	if heat <= 0 then
		return "Cops remember what you wear. Pick a look.", C.Dim
	elseif wardrobeSpot() ~= "hideout" then
		return "Only a hideout's new look drops a star.", C.Dim -- (homes turn wanted players away)
	elseif player:GetAttribute("HeatSpotted") then
		return "A cop can see you! Hide first, then change.", C.Danger
	end
	return "Wanted: a new look drops 1 star.", C.Gold
end

local function rowFor(kind, id)
	for _, c in ipairs(cards) do
		if c.Kind == kind and c.Id == id then
			return c.Button
		end
	end
	return nil
end

-- Scroll the open list so this row is in view (keyboard and gamepad picks).
local function scrollTo(button)
	local list = button and button.Parent
	if not list or not list:IsA("ScrollingFrame") then
		return
	end
	local canvasY = list.CanvasPosition.Y
	local top = button.AbsolutePosition.Y - list.AbsolutePosition.Y + canvasY
	local bottom = top + button.AbsoluteSize.Y
	local view = list.AbsoluteWindowSize.Y
	if top < canvasY then
		list.CanvasPosition = Vector2.new(0, top)
	elseif bottom > canvasY + view then
		list.CanvasPosition = Vector2.new(0, bottom - view)
	end
end

local function refreshCards()
	if not panel then
		return
	end
	for _, c in ipairs(cards) do
		local on = picked[c.Kind] == c.Id
		local wearing = worn(c.Kind) == c.Id
		c.Button.BackgroundTransparency = on and 0.04 or 1
		c.Name.TextColor3 = on and INK or C.Text
		c.Tag.Text = wearing and "WEARING" or "FREE"
		c.Tag.TextColor3 = on and INK or (wearing and C.Text or C.Dim)
		-- No dark text shadow on the white row.
		for _, t in ipairs({ c.Name, c.Tag }) do
			local s = t:FindFirstChild("Shadow")
			if s then
				s.Enabled = not on
			end
		end
	end
	for kind, t in pairs(tabs) do
		local active = kind == tab
		t.Button.TextColor3 = active and C.Text or C.Dim
		t.Line.BackgroundTransparency = active and 0 or 1
		if t.Grid then
			t.Grid.Visible = active
		end
	end
	local diff = changed()
	wearButton.Text = diff and "WEAR IT" or "DONE"
	Theme.Button(wearButton, diff and "Primary" or "Quiet")
	wearButton.FontFace = Theme.Font.Display
	-- The key cap is white; on the white WEAR IT button it turns dark.
	wearCap.BackgroundColor3 = diff and C.Panel or Color3.fromRGB(245, 245, 245)
	wearCap.TextColor3 = diff and C.Text or INK
	local str, color = hintText()
	hint.Text = str
	hint.TextColor3 = color
end

-- Pick an item: it shows on your character straight away (only on this screen).
local function pick(kind, id)
	picked[kind] = id
	showLook()
	refreshCards()
	sound("Click")
end

-- The item above (-1) or below (1) the picked one in the open tab.
local function step(dir)
	local list = tab == "hat" and Disguises.Hats or Disguises.Masks
	local at = 1
	for i, item in ipairs(list) do
		if item.Id == picked[tab] then
			at = i
		end
	end
	local nextAt = math.clamp(at + dir, 1, #list)
	if nextAt ~= at then
		pick(tab, list[nextAt].Id)
		scrollTo(rowFor(tab, list[nextAt].Id))
	end
end

local function setTab(kind)
	tab = kind
	refreshCards()
	sound("Click")
	-- A gamepad selection inside the list that just hid moves to the picked row of the new one.
	local sel = GuiService.SelectedObject
	if gamepad() and room and (sel == nil or sel:IsDescendantOf(panel)) then
		local target = rowFor(kind, picked[kind])
		if target then
			GuiService.SelectedObject = target
			scrollTo(target)
		end
	end
end

-- One item row: swatch, name on the left, WEARING / FREE on the right.
local function row(list, kind, item, order)
	local b = Instance.new("TextButton")
	b.Name = item.Id
	b.LayoutOrder = order
	b.AutoButtonColor = false
	b.Text = ""
	b.Size = UDim2.new(1, -8, 0, 36)
	b.BackgroundColor3 = C.Text
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	Theme.Corners(b, 3)
	b.Parent = list
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 10, 0.5, 0)
	swatch.Size = UDim2.fromOffset(10, 10)
	swatch.BorderSizePixel = 0
	swatch.BackgroundColor3 = item.Color or C.Panel
	swatch.BackgroundTransparency = item.Color and 0 or 1 -- "No hat" / "No mask": just the outline
	Theme.Corners(swatch, 2)
	local edge = Instance.new("UIStroke")
	edge.Color = C.Dim
	edge.Transparency = item.Color and 0.5 or 0
	edge.Thickness = 1
	edge.Parent = swatch
	swatch.Parent = b
	local name = label(b, "Label", item.Name, 15, "Body")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(30, 0)
	name.Size = UDim2.new(1, -120, 1, 0)
	local tag = label(b, "Tag", "FREE", 13, "Bold")
	tag.TextXAlignment = Enum.TextXAlignment.Right
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -10, 0, 0)
	tag.Size = UDim2.new(0, 84, 1, 0)
	b.Activated:Connect(function()
		if room then
			pick(kind, item.Id)
		end
	end)
	table.insert(cards, { Kind = kind, Id = item.Id, Button = b, Name = name, Tag = tag })
end

local function grid(kind, list)
	local s = Instance.new("ScrollingFrame")
	s.Name = kind == "hat" and "Hats" or "Masks"
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ScrollBarThickness = 3
	s.ScrollBarImageColor3 = C.Text
	s.ScrollBarImageTransparency = 0.5
	s.Parent = panel
	local rows = Instance.new("UIListLayout")
	rows.Padding = UDim.new(0, 2)
	rows.SortOrder = Enum.SortOrder.LayoutOrder
	rows.Parent = s
	for i, item in ipairs(list) do
		row(s, kind, item, i)
	end
	return s
end

-- A tab heading: Display text, white and underlined while open, its key cap at the left.
local function tabButton(kind, text, key, padKey, order)
	local b = Instance.new("TextButton")
	b.Name = kind == "hat" and "TabHats" or "TabMasks"
	b.Position = UDim2.new(order * 0.5, order * 4, 0, 0)
	b.Size = UDim2.new(0.5, -4, 1, 0)
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Text = text
	b.FontFace = Theme.Font.Display
	b.TextSize = 16
	b.TextColor3 = C.Dim
	Theme.Shadow(b)
	b.Parent = tabRow
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.fromScale(0, 1)
	line.Size = UDim2.new(1, 0, 0, 2)
	line.BackgroundColor3 = C.Text
	line.BorderSizePixel = 0
	line.ZIndex = 2
	line.Parent = b
	local k = cap(b, key, padKey)
	k.AnchorPoint = Vector2.new(0, 0.5)
	k.Position = UDim2.new(0, 2, 0.5, -1)
	b.Activated:Connect(function()
		setTab(kind)
	end)
	return { Button = b, Line = line }
end

-- Left column on wide screens, bottom sheet on tall ones; the camera frames the character in the rest.
local function layout()
	if not panel then
		return
	end
	local vp = Workspace.CurrentCamera.ViewportSize
	if vp.X < 50 or vp.Y < 50 then
		return
	end
	local touch = Theme.IsTouch()
	local m = metrics(touch)
	local side = vp.X >= vp.Y * 1.15
	local pw, ph
	if side then
		-- Under Roblox's top bar (its buttons sit top-left), vertically centred when there's room.
		pw = math.clamp(math.floor(vp.X * 0.3), PANEL_MIN_W, PANEL_MAX_W)
		local top = Theme.TopBar + 6
		ph = math.max(math.min(vp.Y - top - MARGIN, SIDE_MAX_H), 200)
		top = math.max(top, math.floor((vp.Y - ph) / 2))
		panel.AnchorPoint = Vector2.zero
		panelHome = UDim2.fromOffset(MARGIN, top)
		panelAway = UDim2.fromOffset(-pw - MARGIN, top)
	else
		pw = vp.X - MARGIN * 2
		ph = math.clamp(math.floor(vp.Y * 0.48), SHEET_MIN_H, SHEET_MAX_H)
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panelHome = UDim2.new(0.5, 0, 1, -MARGIN)
		panelAway = UDim2.new(0.5, 0, 1, ph + MARGIN)
	end
	panel.Size = UDim2.fromOffset(pw, ph)
	if panelTween then
		panelTween:Cancel()
		panelTween = nil
	end
	panel.Position = panelHome

	-- Inside the panel, top to bottom: title and close, hint, tabs, the list, WEAR IT. A phone's left
	-- column is short (about 300 px), so there WEAR IT goes in the orbit bar and the list gets its room.
	local wearInBar = touch and side
	title.TextSize = m.Title
	closeButton.Size = UDim2.fromOffset(m.Close, m.Close)
	local headY = math.max(44, 8 + m.Close + 2)
	local footer = wearInBar and 12 or m.Button + 24
	-- Two hint lines when the list still shows three rows, else one (short phones).
	local twoLines = ph - (headY + 32 + 6 + m.Tab + 8 + footer) >= 3 * (m.Row + 2)
	local hintH = twoLines and 32 or 16
	hint.Position = UDim2.fromOffset(16, headY)
	hint.Size = UDim2.new(1, -32, 0, hintH)
	hint.TextTruncate = twoLines and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
	local tabsY = headY + hintH + 6
	tabRow.Position = UDim2.fromOffset(16, tabsY)
	tabRow.Size = UDim2.new(1, -32, 0, m.Tab)
	local listY = tabsY + m.Tab + 8
	for _, t in pairs(tabs) do
		t.Grid.Position = UDim2.fromOffset(12, listY)
		t.Grid.Size = UDim2.new(1, -20, 0, math.max(ph - listY - footer, m.Row))
	end
	for _, c in ipairs(cards) do
		c.Button.Size = UDim2.new(1, -8, 0, m.Row)
	end

	-- The orbit bar: caption over [turn left] [ZOOM] [turn right] (then [WEAR IT] on a phone's column).
	local s = m.Spin
	local barW, barH = s * 2 + ZOOM_W + 16, s + 22
	if wearInBar then
		wearButton.Parent = bar
		wearButton.AnchorPoint = Vector2.zero
		wearButton.Position = UDim2.fromOffset(barW + 8, 22)
		wearButton.Size = UDim2.fromOffset(WEAR_BAR_W, s)
		barW += 8 + WEAR_BAR_W
	else
		wearButton.Parent = panel
		wearButton.AnchorPoint = Vector2.new(0, 1)
		wearButton.Position = UDim2.new(0, 16, 1, -12)
		wearButton.Size = UDim2.new(1, -32, 0, m.Button)
	end
	bar.Size = UDim2.fromOffset(barW, barH)
	spinCaption.Size = UDim2.new(1, 40, 0, 16)
	spinLeft.Size = UDim2.fromOffset(s, s)
	spinLeft.Position = UDim2.fromOffset(0, 22)
	zoomButton.Size = UDim2.fromOffset(ZOOM_W, s)
	zoomButton.Position = UDim2.fromOffset(s + 8, 22)
	spinRight.Size = UDim2.fromOffset(s, s)
	spinRight.Position = UDim2.fromOffset(s + 8 + ZOOM_W + 8, 22)

	local freeX, freeW, freeH
	if side then
		freeX = MARGIN + pw + MARGIN
		freeW = vp.X - freeX - MARGIN
		freeH = vp.Y - barH - MARGIN * 2
		bar.Position = UDim2.fromOffset(math.floor(freeX + freeW / 2), vp.Y - MARGIN)
	else
		freeX = 0
		freeW = vp.X
		freeH = vp.Y - ph - barH - MARGIN * 3
		bar.Position = UDim2.new(0.5, 0, 1, -(ph + MARGIN * 2))
	end
	framing.Side = side
	framing.Fov = side and 45 or 60 -- tall screens need a wider lens to fit a whole character
	framing.FreeW = math.max(freeW, 80)
	framing.FreeH = math.max(freeH, 80)
	-- Middle of the free area in screen coordinates (-1..1, up is +).
	framing.Ndc = Vector2.new(2 * (freeX + freeW / 2) / vp.X - 1, 1 - 2 * (freeH / 2) / vp.Y)
end

local function slideIn()
	panel.Position = panelAway
	panelTween = TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = panelHome })
	panelTween:Play()
end

------------------------------------------------------------------ the OUTFIT tile (side column)

-- One white stroke of a glyph, centred on (cx, cy) inside the glyph box, turned `rot` degrees.
local function glyphStroke(parent, w, h, cx, cy, rot)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(cx, cy)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	f.BackgroundColor3 = C.Text
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = parent
	return f
end

-- A coat hanger: a hook, two shoulders and the bar.
local function hangerGlyph(g)
	local hook = glyphStroke(g, 6, 6, 12, 3.5)
	hook.BackgroundTransparency = 1
	Theme.Corners(hook, 3)
	local ring = Instance.new("UIStroke")
	ring.Color = C.Text
	ring.Thickness = 1.5
	ring.Parent = hook
	glyphStroke(g, 2, 2, 12, 7)
	glyphStroke(g, 14, 2, 7, 12.5, -42)
	glyphStroke(g, 14, 2, 17, 12.5, 42)
	glyphStroke(g, 22, 2, 12, 17)
end

-- Same tile recipe as LawClient's TASER / SPIKES: flat square, glyph on top, Display word underneath.
local function buildOpen()
	openButton = Instance.new("TextButton")
	openButton.Name = "Open"
	openButton.Size = UDim2.fromOffset(52, 52)
	openButton.Text = "OUTFIT"
	Theme.Button(openButton, "Quiet")
	openButton.FontFace = Theme.Font.Display
	openButton.TextSize = 13
	openButton.TextYAlignment = Enum.TextYAlignment.Bottom
	openButton.Visible = false
	Theme.Shadow(openButton)
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = openButton
	local g = Instance.new("Frame")
	g.Name = "Glyph"
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.new(0.5, 0, 0, 5)
	g.Size = UDim2.fromOffset(24, 20)
	g.BackgroundTransparency = 1
	g.Parent = openButton
	hangerGlyph(g)
	openButton.Parent = buttonGui
end

-- Its slot: right under LEAVE HOME at home, the top slot at a hideout.
local function placeOpen()
	local touch = Theme.IsTouch()
	local index = player:GetAttribute("InHome") == true and 1 or 0
	local law = controller("LawClient")
	local ok, pos, size = false, nil, nil
	if law and law.SideSlot then
		ok, pos, size = pcall(law.SideSlot, buttonGui, index, touch)
	end
	if not ok or typeof(pos) ~= "Vector2" or typeof(size) ~= "Vector2" then
		-- (LawClient missing: a rough spot under the PC Buttons zone)
		local s = buttonGui.AbsoluteSize
		pos, size = Vector2.new(s.X - 72, s.Y * 0.5 + 66 + index * 60), Vector2.new(52, 52)
	end
	openButton.AnchorPoint = Vector2.zero
	openButton.Position = UDim2.fromOffset(pos.X, pos.Y)
	openButton.Size = UDim2.fromOffset(size.X, size.Y)
end

local function showOpen()
	openButton.Visible = wardrobeSpot() ~= nil and room == nil and not titleScreen()
	if openButton.Visible then
		placeOpen()
	end
end

------------------------------------------------------------------ camera

-- How far back the camera sits so the shot (H studs tall, W wide) fits the free part of the screen.
local function shotDistance(shot)
	local vpY = Workspace.CurrentCamera.ViewportSize.Y
	local tanV = math.tan(math.rad(framing.Fov) / 2)
	local d = math.max(shot.H * vpY / (2 * tanV * framing.FreeH), shot.W * vpY / (2 * tanV * framing.FreeW))
	return math.clamp(d, 3, 16)
end

-- Two shots, measured from the root: knees-up portrait, and a close-up of the head and shoulders.
local function measureShots(r)
	local root, head, hum = r.Root, r.Head, r.Hum
	local s = head.Size.Y / 1.2
	local headY = head.Position.Y - root.Position.Y
	local top = headY + head.Size.Y / 2 + 0.7 * s -- room for a hat
	local feet
	if hum.RigType == Enum.HumanoidRigType.R15 then
		feet = -root.Size.Y / 2 - hum.HipHeight
	else
		feet = -3 -- R6: legs hang 2 studs under a 2-stud torso
	end
	local bottom = feet + (top - feet) * 0.2
	r.Full = { Y = (top + bottom) / 2, H = top - bottom + 0.4, W = 3.4 * s }
	local chin = headY - head.Size.Y / 2 - 0.9 * s
	r.Close = { Y = (top + chin) / 2, H = top - chin + 0.3, W = 2.2 * s }
end

-- Which way to face: straight ahead if the camera has room there, otherwise the clearest way
-- (30-degree steps alternating left and right, so the current facing wins when it fits).
local function pickFacing(focus, ahead, reach)
	local best, bestRoom = ahead, -1
	for i = 0, 11 do
		local stepAt = math.ceil(i / 2) * (i % 2 == 1 and 1 or -1)
		local dir = CFrame.Angles(0, math.rad(stepAt * 30), 0) * ahead
		local hit = Workspace:Raycast(focus, dir * reach + Vector3.new(0, reach * LIFT, 0), rayParams)
		if not hit then
			return dir
		end
		if hit.Distance > bestRoom then
			best, bestRoom = dir, hit.Distance
		end
	end
	return best
end

local function cameraStep(dt)
	local r = room
	if not r then
		return
	end
	local root = r.Root
	-- Safety net: anything that ends the visit gives the camera and movement back.
	if not r.Char.Parent or not root.Parent or r.Hum.Health <= 0 or r.Hum.SeatPart
		or (root.Position - r.AnchorPos).Magnitude > MOVED_TOO_FAR then
		closeRoom(false)
		return
	end
	-- The PHONE button and P key still work, so shut the phone if it gets opened (own pcall: a phone
	-- problem shouldn't close the room).
	pcall(shutPhone, r.Phone)
	local camera = Workspace.CurrentCamera
	local vp = camera.ViewportSize
	if vp.X < 2 or vp.Y < 2 then
		return
	end
	-- Spin: arrows / keys / bumpers / stick held, then ease towards the target angle.
	local spin = math.clamp((hold and hold.Dir or 0) + keyDir + stickDir, -1, 1)
	r.TargetYaw += spin * ORBIT_SPEED * dt
	r.Yaw += (r.TargetYaw - r.Yaw) * (1 - math.exp(-dt * 8))

	local shot = r.Zoom and r.Close or r.Full
	local dist = shotDistance(shot)
	local focus = root.Position + Vector3.new(0, shot.Y, 0)
	local dir = CFrame.Angles(0, r.Yaw, 0) * r.Facing
	local offset = dir * dist + Vector3.new(0, dist * LIFT, 0)
	local hit = Workspace:Raycast(focus, offset, rayParams)
	if hit then
		offset = offset.Unit * math.max(hit.Distance - 0.5, 1.5) -- stay on this side of walls
	end
	-- Aim off to one side (or lower) so the character sits in the middle of the free part of the screen.
	local tanV = math.tan(math.rad(framing.Fov) / 2)
	local d = offset.Magnitude
	local fwd = -offset.Unit
	local right = fwd:Cross(Vector3.yAxis).Unit
	local up = right:Cross(fwd)
	local lookAt = focus - right * (framing.Ndc.X * d * tanV * vp.X / vp.Y) - up * (framing.Ndc.Y * d * tanV)
	local alpha = 1 - math.exp(-dt * 6)
	r.CamCF = r.CamCF:Lerp(CFrame.lookAt(focus + offset, lookAt), alpha)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = r.CamCF
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView += (framing.Fov - camera.FieldOfView) * alpha
	-- Keep the body solid (a first-person zoom before opening leaves it see-through).
	for part in pairs(r.Shown) do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
end

------------------------------------------------------------------ opening and closing

closeRoom = function(keepPreview)
	local r = room
	if not r then
		return
	end
	room = nil
	hold, drag, keyDir, stickDir = nil, nil, 0, 0
	if r.Bound then
		RunService:UnbindFromRenderStep(CAMERA_STEP)
	end
	for _, c in ipairs(r.Conns) do
		c:Disconnect()
	end
	if panelTween then
		panelTween:Cancel()
		panelTween = nil
	end
	roomGui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(roomGui) then
		GuiService.SelectedObject = nil
	end
	-- Camera back to normal, following the (current) character.
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = r.OldFov
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
	-- Movement back.
	if r.Root.Parent then
		r.Root.Anchored = r.OldAnchored
	end
	if r.Controls then
		pcall(function()
			r.Controls:Enable()
		end)
	end
	for part, old in pairs(r.Shown) do
		if part.Parent then
			part.LocalTransparencyModifier = old
		end
	end
	for _, t in ipairs(r.CoreGui) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, true)
	end
	if r.Preview and not keepPreview then
		dropPreview(r.Preview)
	end
	if r.PromptsOff then
		pcall(function()
			ProximityPromptService.Enabled = true
		end)
	end
	if r.HouseGui and r.HouseGui.Parent then
		r.HouseGui.Enabled = true
	end
	if r.LawGui and r.LawGui.Parent then
		r.LawGui.Enabled = true
	end
	showOpen()
end

local function setUpRoom(r)
	local char, hum, root = r.Char, r.Hum, r.Root
	layout()
	measureShots(r)
	-- Bodies never push the camera in.
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	-- Stand still and turn to face the camera. The root is anchored on this screen only; the server
	-- (and everyone else) just sees you standing there.
	r.Controls = getControls()
	if r.Controls then
		r.Controls:Disable()
	end
	root.Anchored = true
	-- Opened at a closet: face away from it, so it's behind you in the shot.
	local look = root.CFrame.LookVector
	local from = r.From
	if from and from.Parent and from:IsA("BasePart") then
		look = root.Position - from.Position
	end
	local ahead = Vector3.new(look.X, 0, look.Z)
	ahead = ahead.Magnitude > 0.05 and ahead.Unit or Vector3.new(0, 0, -1)
	r.Facing = pickFacing(root.Position + Vector3.new(0, r.Full.Y, 0), ahead, shotDistance(r.Full) + 1)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + r.Facing)
	r.AnchorPos = root.Position
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and not isServerDisguisePart(d) then
			r.Shown[d] = d.LocalTransparencyModifier
		end
	end
	-- Start the preview from what you're wearing now.
	picked.hat, picked.mask = worn("hat"), worn("mask")
	r.Preview = startPreview(char, r.Head)
	showLook()
	-- Clear the clutter: leaderboard, hotbar and chat window, and the phone if it's out.
	for _, t in ipairs(HIDE_CORE) do
		if StarterGui:GetCoreGuiEnabled(t) then
			StarterGui:SetCoreGuiEnabled(t, false)
			table.insert(r.CoreGui, t)
		end
	end
	r.Phone = controller("PhoneUI") -- cameraStep keeps it shut from here on
	pcall(shutPhone, r.Phone)
	-- Every prompt off, on this screen only: the closet's would float in the shot, and E, gamepad X
	-- or a tap on a nearby "Leave home" or "Drive this" (or a car's prompt at the hideout) would take
	-- you out mid-look. Own pcall: if the service says no, the room still opens.
	if ProximityPromptService.Enabled then
		r.PromptsOff = pcall(function()
			ProximityPromptService.Enabled = false
		end)
	end
	-- At home: HouseClient's "House" ScreenGui (LEAVE HOME, which never changes its gui's Enabled)
	-- goes too, so nothing of the house screen sits over the menu or takes a stray tap.
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if r.Spot == "home" then
		local house = pg and pg:FindFirstChild("House")
		if house and house:IsA("ScreenGui") and house.Enabled then
			house.Enabled = false
			r.HouseGui = house
		end
	end
	-- A cop's TASER / SPIKES tiles (LawClient's "LawUI") would float over the picture on a phone, and
	-- T / G would still zap: off too (LawClient's keys check its Enabled), back on close.
	local law = pg and pg:FindFirstChild("LawUI")
	if law and law:IsA("ScreenGui") and law.Enabled then
		law.Enabled = false
		r.LawGui = law
	end
	-- Anything that ends the visit closes the room. (Leaving the hideout or home: see refresh.)
	local function bail()
		closeRoom(false)
	end
	table.insert(r.Conns, hum.Died:Connect(bail))
	table.insert(r.Conns, hum:GetPropertyChangedSignal("SeatPart"):Connect(bail))
	table.insert(r.Conns, player.CharacterRemoving:Connect(bail))
	table.insert(r.Conns, player:GetAttributeChangedSignal("Side"):Connect(bail)) -- arrested, or switched team
	tab = "hat"
	title.Text = r.Spot == "home" and "MY CLOSET" or "DRESSING ROOM"
	zoomButton.Text = "ZOOM"
	refreshCaps()
	refreshCards()
	for _, t in pairs(tabs) do
		t.Grid.CanvasPosition = Vector2.zero
	end
	roomGui.Enabled = true
	slideIn()
	-- On a gamepad, start on the row you're wearing (A picks, Y wears it, B closes, LB / RB spin).
	if gamepad() then
		local first = rowFor(tab, picked[tab]) or (cards[1] and cards[1].Button)
		if first then
			GuiService.SelectedObject = first
			task.defer(scrollTo, first)
		end
	end
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local ok, err = pcall(cameraStep, dt)
		if not ok then
			warn("[WardrobeUI] " .. tostring(err))
			closeRoom(false)
		end
	end)
	r.Bound = true
	sound("Click")
end

-- `from`: the closet part whose prompt opened the room (nil from the OUTFIT tile).
local function openRoom(from)
	local spot = wardrobeSpot()
	if room or not spot or titleScreen() then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	if not hum or not root or not head or hum.Health <= 0 then
		return
	end
	if hum.SeatPart then
		tell(seatedMessage(hum), "info")
		return
	end
	local camera = Workspace.CurrentCamera
	local r = {
		Spot = spot, -- "hideout" or "home"
		From = from,
		Char = char,
		Hum = hum,
		Root = root,
		Head = head,
		OldFov = camera.FieldOfView,
		OldAnchored = root.Anchored,
		AnchorPos = root.Position,
		CamCF = camera.CFrame, -- the camera swoops from wherever it was
		Yaw = 0,
		TargetYaw = 0,
		Zoom = false,
		Conns = {},
		Shown = {}, -- [body part] = its old LocalTransparencyModifier
		CoreGui = {}, -- core GUI we hid (to show again)
	}
	room = r
	openButton.Visible = false
	-- If anything goes wrong half-way, undo what was done so the player is never stuck.
	local ok, err = pcall(setUpRoom, r)
	if not ok then
		warn("[WardrobeUI] couldn't open: " .. tostring(err))
		closeRoom(false)
	end
end

-- Waits (a moment at most) for the character to land, so nobody gets frozen mid-jump. `from` as in
-- openRoom.
local function requestOpen(from)
	if room or opening then
		return
	end
	-- Sitting: say so straight away (a seated character never "lands", so don't wait first).
	local seatedHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if seatedHum and seatedHum.SeatPart then
		tell(seatedMessage(seatedHum), "info")
		return
	end
	opening = true
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < 1.5 do
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not hum or hum.FloorMaterial ~= Enum.Material.Air then
				break
			end
			task.wait()
		end
		opening = false
		openRoom(from)
	end)
end

-- After WEAR IT the preview stays on until the server's copy of the look arrives (so the old look
-- never flashes back), or CONFIRM_WAIT seconds pass (the server said no, e.g. you'd just left).
local function awaitServer(p, hat, mask)
	local done = false
	local conns = {}
	local function finish()
		if done then
			return
		end
		done = true
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		dropPreview(p)
		if worn("hat") == hat and worn("mask") == mask then
			local hud = controller("HUDController")
			if hud and hud.Stamp then
				hud.Stamp("NEW LOOK", Disguises.Describe(hat, mask), C.Gold)
			end
		else
			tell("Your new look didn't stick. Try again at a hideout or at home.", "warning")
		end
	end
	local matched = false
	local function check()
		if not matched and worn("hat") == hat and worn("mask") == mask then
			matched = true
			task.delay(0.15, finish) -- a beat for the server's new parts to arrive too
		end
	end
	table.insert(conns, player:GetAttributeChangedSignal("LookHat"):Connect(check))
	table.insert(conns, player:GetAttributeChangedSignal("LookMask"):Connect(check))
	task.delay(CONFIRM_WAIT, finish)
end

local function wear()
	local r = room
	if not r then
		return
	end
	if not changed() then
		closeRoom(false)
		sound("Click")
		return
	end
	local hat, mask = picked.hat, picked.mask
	task.spawn(function()
		Remotes.Event("RequestDisguise"):FireServer(hat, mask)
	end)
	local p = r.Preview
	closeRoom(true)
	if p then
		awaitServer(p, hat, mask)
	end
end

local function toggleZoom()
	if not room then
		return
	end
	room.Zoom = not room.Zoom
	zoomButton.Text = room.Zoom and "FULL" or "ZOOM"
	sound("Click")
end

------------------------------------------------------------------ building the UI

local function orbitButton(name, glyph, dir)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = glyph
	Theme.Button(b, "Quiet")
	b.TextSize = 22
	b.Parent = bar
	-- Hold to keep spinning (released in onInputEnded); a tap gives a small nudge.
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if room and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			hold = { Input = input, Dir = dir }
			room.TargetYaw += dir * NUDGE
		end
	end)
	-- Gamepad: A on the selected arrow nudges too (mouse and touch already nudged above).
	b.Activated:Connect(function()
		if room and gamepad() then
			room.TargetYaw += dir * NUDGE
		end
	end)
	return b
end

local function build()
	local playerGui = player:WaitForChild("PlayerGui")

	-- Same ScreenGui and button names as before ("WardrobeUI" / "Open").
	buttonGui = Instance.new("ScreenGui")
	buttonGui.Name = "WardrobeUI"
	buttonGui.ResetOnSpawn = false
	buttonGui.IgnoreGuiInset = true
	buttonGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	buttonGui.Parent = playerGui
	buildOpen()
	openButton.Activated:Connect(function()
		requestOpen() -- (not requestOpen directly: Activated passes an InputObject)
	end)

	roomGui = Instance.new("ScreenGui")
	roomGui.Name = "WardrobeRoom"
	roomGui.ResetOnSpawn = false
	roomGui.IgnoreGuiInset = true
	roomGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Over the phone (5), the team picker (10) and the toasts (20): on a phone the toast stack would
	-- sit right over the list. Nothing of the room's own speaks while it's open (see the header).
	roomGui.DisplayOrder = 21
	roomGui.Enabled = false
	roomGui.Parent = playerGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true -- touches on the panel don't spin the view
	Theme.Panel(panel, 0.18)
	panel.Parent = roomGui
	-- The brand's thin pink accent, top-left.
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(16, 0)
	accent.Size = UDim2.fromOffset(40, 2)
	accent.BackgroundColor3 = C.Brand
	accent.BorderSizePixel = 0
	accent.Parent = panel

	title = label(panel, "Title", "DRESSING ROOM", 24, "Display")
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -96, 0, 30)

	closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.fromOffset(32, 32)
	closeButton.Text = "X" -- (the font has no cross glyph: it drew an empty box)
	Theme.Button(closeButton, "Quiet")
	closeButton.TextSize = 16
	closeButton.Parent = panel
	local closeCap = cap(closeButton, "X", "B")
	closeCap.AnchorPoint = Vector2.new(1, 0.5)
	closeCap.Position = UDim2.new(0, -6, 0.5, 0)
	closeButton.Activated:Connect(function()
		closeRoom(false) -- cancel: back to what you had on
		sound("Click")
	end)

	hint = label(panel, "Hint", "", 13, "Body")
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextWrapped = true

	tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.BackgroundTransparency = 1
	tabRow.Parent = panel
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.fromScale(0, 1)
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.BackgroundColor3 = C.Text
	rule.BackgroundTransparency = 0.8
	rule.BorderSizePixel = 0
	rule.Parent = tabRow
	tabs.hat = tabButton("hat", "HATS", "Q", "LT", 0)
	tabs.mask = tabButton("mask", "MASKS", "E", "RT", 1)
	tabs.hat.Grid = grid("hat", Disguises.Hats)
	tabs.mask.Grid = grid("mask", Disguises.Masks)

	wearButton = Instance.new("TextButton")
	wearButton.Name = "Wear"
	wearButton.AnchorPoint = Vector2.new(0, 1)
	wearButton.Position = UDim2.new(0, 16, 1, -12)
	wearButton.Size = UDim2.new(1, -32, 0, 40)
	wearButton.Text = "DONE"
	Theme.Button(wearButton, "Quiet")
	wearButton.FontFace = Theme.Font.Display
	wearButton.TextSize = 18
	wearButton.Parent = panel -- (layout moves it into the orbit bar on a phone's left column)
	local wearPad = Instance.new("UIPadding")
	wearPad.Parent = wearButton
	local wearEntry
	wearCap, wearEntry = cap(wearButton, "ENTER", "Y")
	wearCap.AnchorPoint = Vector2.new(0, 0.5)
	wearCap.Position = UDim2.new(0, 10, 0.5, 0)
	-- While a cap shows, the word moves right of it (refreshCaps), so it clears the cap on the narrow
	-- orbit-bar button too: cap 10 px in, then at least 8 px, then the word.
	wearEntry.Pad, wearEntry.PadBy, wearEntry.CapX = wearPad, 18, 10
	wearButton.Activated:Connect(wear)

	-- Turn left / ZOOM / turn right, under the character.
	bar = Instance.new("Frame")
	bar.Name = "Orbit"
	bar.Active = true
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundTransparency = 1
	bar.Parent = roomGui
	-- Its words follow the input in use (refreshCaps).
	spinCaption = label(bar, "Caption", "Drag to spin", 13, "Body")
	spinCaption.AnchorPoint = Vector2.new(0.5, 0)
	spinCaption.Position = UDim2.fromScale(0.5, 0)
	spinLeft = orbitButton("SpinLeft", "<", -1) -- (plain signs: the font has no round-arrow glyphs)
	spinRight = orbitButton("SpinRight", ">", 1)
	zoomButton = Instance.new("TextButton")
	zoomButton.Name = "Zoom"
	zoomButton.Text = "ZOOM"
	Theme.Button(zoomButton, "Quiet")
	zoomButton.FontFace = Theme.Font.Display
	zoomButton.TextSize = 16
	zoomButton.Parent = bar
	local zoomPad = Instance.new("UIPadding")
	zoomPad.Parent = zoomButton
	local zoomCap, zoomEntry = cap(zoomButton, "Z", "R3")
	zoomCap.AnchorPoint = Vector2.new(0, 0.5)
	zoomCap.Position = UDim2.new(0, 8, 0.5, 0)
	-- While a cap shows, the word moves right of it (refreshCaps): cap 8 px in, then 12 px, then the word.
	zoomEntry.Pad, zoomEntry.PadBy, zoomEntry.CapX = zoomPad, 12, 8
	zoomButton.Activated:Connect(toggleZoom)
end

------------------------------------------------------------------ input (keys and spinning the view)

local function onInputBegan(input, processed)
	if not room then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.ButtonB then
		closeRoom(false)
		return
	end
	-- Gamepad buttons GUI navigation doesn't use work even with a row selected ("processed").
	if PAD_SPIN[key] then
		keyDir = PAD_SPIN[key]
		return
	elseif PAD_TABS[key] then
		setTab(PAD_TABS[key])
		return
	elseif key == Enum.KeyCode.ButtonY and not GuiService.MenuIsOpen then
		wear() -- (not from behind Roblox's own menu: its Y is "Reset Character")
		return
	elseif key == Enum.KeyCode.ButtonR3 then
		toggleZoom()
		return
	end
	if processed then
		return
	end
	if TAB_KEYS[key] then
		setTab(TAB_KEYS[key])
		return
	elseif STEP_KEYS[key] then
		step(STEP_KEYS[key])
		return
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
		wear()
		return
	elseif key == Enum.KeyCode.Z then
		toggleZoom()
		return
	elseif key == Enum.KeyCode.X then
		closeRoom(false)
		sound("Click")
		return
	end
	local k = SPIN_KEYS[key]
	if k then
		keyDir = k
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		drag = { Input = input, X = input.Position.X }
	end
end

local function onInputChanged(input)
	if not room then
		return
	end
	-- Right stick sideways spins (the camera is ours while the room is open, so the stick is free).
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local x = input.Position.X
		stickDir = math.abs(x) > STICK_DEADZONE and x or 0
		return
	end
	if not drag then
		return
	end
	local mouseDrag = input.UserInputType == Enum.UserInputType.MouseMovement
		and drag.Input.UserInputType == Enum.UserInputType.MouseButton1
	if input == drag.Input or mouseDrag then
		local x = input.Position.X
		room.TargetYaw -= (x - drag.X) * DRAG_SPEED
		drag.X = x
	end
end

local function onInputEnded(input)
	local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
	if hold and (input == hold.Input or (mouse and hold.Input.UserInputType == Enum.UserInputType.MouseButton1)) then
		hold = nil
	end
	if drag and (input == drag.Input or (mouse and drag.Input.UserInputType == Enum.UserInputType.MouseButton1)) then
		drag = nil
	end
	if SPIN_KEYS[input.KeyCode] or PAD_SPIN[input.KeyCode] then
		keyDir = 0
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stickDir = 0
	end
end

------------------------------------------------------------------ start

local function refresh()
	local spot = wardrobeSpot()
	showOpen()
	if room and room.Spot ~= spot then
		closeRoom(false) -- left the hideout or home the room was opened in
	end
end

-- Your home closet's "Change look" prompt (only yours: WardrobePrompt is built in your own inside).
local function onPrompt(prompt, who)
	if who ~= player or prompt.Name ~= "WardrobePrompt" or player:GetAttribute("InHome") ~= true then
		return
	end
	requestOpen(prompt.Parent)
end

function WardrobeUI.IsOpen()
	return room ~= nil
end

function WardrobeUI.Close()
	closeRoom(false)
end

function WardrobeUI.Init()
	build()
	layout()
	refreshCaps()
	refresh()
	refreshCards()
	player:GetAttributeChangedSignal("InHideout"):Connect(refresh)
	player:GetAttributeChangedSignal("InHome"):Connect(refresh)
	player:GetAttributeChangedSignal("Touring"):Connect(refresh)
	player:GetAttributeChangedSignal("TitleScreen"):Connect(refresh)
	ProximityPromptService.PromptTriggered:Connect(onPrompt)
	for _, a in ipairs({ "LookHat", "LookMask", "Heat", "HeatSpotted" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshCards)
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		layout()
		showOpen()
	end)
	-- A phone layout or a different set of key caps when the input changes (a pad plugged in...).
	-- Only on a real change of kind: a keyboard player moving the mouse fires this all the time.
	local lastMode = inputMode()
	UserInputService.LastInputTypeChanged:Connect(function()
		local mode = inputMode()
		if mode == lastMode then
			return
		end
		lastMode = mode
		refreshCaps()
		if not room then
			layout() -- (an open room keeps its sizes until it closes)
		end
		showOpen()
	end)
	-- The tile's slot moves with the drive pedals and the jump button (LawClient.SideSlot measures them).
	local lastPlace = 0
	RunService.Heartbeat:Connect(function()
		if openButton.Visible and os.clock() - lastPlace > 0.25 then
			lastPlace = os.clock()
			placeOpen()
		end
	end)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
end

return WardrobeUI
