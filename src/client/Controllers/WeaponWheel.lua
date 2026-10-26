-- WeaponWheel (ModuleScript, StarterPlayerScripts.Controllers.WeaponWheel)
-- The weapon wheel. Hold Tab (keyboard) or D-pad left (gamepad) and a ring of slots opens round the
-- middle of the screen, one for everything your hands can hold: Fists, every gun you own (CombatClient's
-- tools, in hotbar order; a cop's Service Pistol) and PUT AWAY (empty hands). Let go and the highlighted
-- one is in your hand.
--   * Each slot is a dark, nearly solid tile with the name (Theme Display font), the magazine for a gun
--     ("12 / ∞", like the weapon readout; RELOADING while it reloads) and a thin pink line under the one
--     in hand. The middle disc shows the highlighted slot (before a pick: the one in hand): its name, IN
--     HAND or its class, and for a gun the shop's three bars (damage, fire rate, range).
--   * Picking: the slot in the direction the mouse points from the middle of the screen (past a 35 px
--     dead zone, once the mouse has moved) or the right stick points (past 0.35) grows a little and gets
--     a white edge, and a short white bar on the inner ring points at it. The pick stays when the pointer
--     comes back to the middle. Nothing picked = keep what is in hand. A click or tap on a slot takes it
--     at once.
--   * Gamepad: D-pad left, because it is free on foot (up flips the car, left / right are the radio
--     only while driving, down is the phone) while the bumpers are Roblox's own tool switch on foot.
--   * Phone: CombatClient's WEAPON button held for 0.4 s opens it (WeaponWheel.OpenTouch); tap a slot to
--     take it, tap anywhere else to close it without a change.
--   * While it is up: the world behind it is blurred (a BlurEffect on the camera, size 12, made on this
--     device only) and a dark sheet dims it and the HUD (the blur never reaches other GUIs, so the HUD's
--     words would read through the tiles); the mouse is free and shows (CombatClient.SetWheelOpen keeps
--     its crosshair lock off, a Modal button frees it in first person and shift lock; MouseBehavior and
--     the icon are put back after); the camera doesn't turn (a free cursor turns nothing, and the right
--     stick, mouse movement, the mouse wheel and the arrow keys are taken here at a higher priority than
--     Roblox's camera); nothing fires or swings (CombatClient). The game keeps running: a shared world
--     has no slow motion, so it is quick.
--   * Never opens, and closes without a change: on the title screen (TitleScreen), with the phone up
--     (PhoneUI.IsOpen), in any seat (the driver's seat above all: CombatClient puts tools away there),
--     knocked out or tasered, in prison, at home, behind another panel, with the Roblox menu up, when the
--     window loses focus or on a respawn. CombatClient.CanSwitch says the rest.
--   * Equipping goes through CombatClient.EquipKey: the same Humanoid:EquipTool as the WEAPON button and
--     the hotbar keys, with its click. SoundClient's "Click" ticks when it opens and as the pick moves.
-- Other controllers are looked up softly (CombatClient, PhoneUI, SoundClient): without CombatClient's
-- wheel functions it never opens.
-- API: WeaponWheel.IsOpen(), WeaponWheel.OpenTouch() -> true if it opened, WeaponWheel.Close().

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local WeaponWheel = {}

local C = Theme.Color

-- Constants, in one table (a Luau function, this file's top level too, holds 200 locals at most).
local K = {
	KEY = Enum.KeyCode.Tab, -- hold to open it (keyboard)
	PAD = Enum.KeyCode.DPadLeft, -- hold to open it (gamepad)
	PUT_AWAY = "None", -- the empty-hands slot's key (CombatClient.EquipKey takes it)
	RADIUS = 148, -- pixels from the middle to a slot's centre at least (place: more when the slots need the room)
	TILE = Vector2.new(124, 72), -- a slot tile, before the fit-the-screen scale
	TILE_ALPHA = 0.08, -- its background (dark, nearly solid: no HUD words read through it); 0.04 lit
	BACK_ALPHA = 0.3, -- the dark sheet over the screen (the HUD under it keeps 30% of its brightness)
	GROW = 1.12, -- the highlighted slot's scale
	DISC = 170, -- the middle disc's diameter
	NOTCH = 98, -- the pointer bar's distance from the middle (between the disc and the tiles)
	CLEAR = 8, -- pixels between the pointer bar's ring and the nearest edge of any (grown) tile
	DEAD_PX = 35, -- the mouse must be this far from the middle to pick
	DEAD_STICK = 0.35, -- ...the right stick this far from rest
	BLUR = 12, -- BlurEffect.Size while it is up
	CHECK = 0.1, -- seconds between two looks at "may it stay up?" (and at the ammo counts)
	DISPLAY_ORDER = 12, -- over the HUD (0-4), the phone (5) and the cards (6-10), under the toasts (20)
	LOOK_ACTION = "NC_WheelLook", -- ContextActionService: what would turn the camera, while it is up
	STEP = "NC_WeaponWheel", -- RenderStep, while it is up
	PRIORITY = 4000, -- over Roblox's camera input (2000) and our own bindings (3000)
	FADE = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	POP = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	STATS = { "DAMAGE", "FIRE RATE", "RANGE" }, -- the middle's bars, in Combat.Stats order
}

local ui = { tiles = {} } -- every GUI object, by name (build); tiles[i] = slot i's tile (tile)
-- Everything that has to be remembered, in one table.
local S = {
	open = false,
	how = nil, -- "keyboard" | "gamepad" | "touch": what opened it
	pad = nil, -- the gamepad (Enum.UserInputType.Gamepad1...) whose D-pad holds it open
	slots = {}, -- what is shown, by slot number: CombatClient.Weapons() entries, then PUT AWAY
	pick = nil, -- the highlighted slot number (nil: nothing picked yet)
	fit = 1, -- the wheel's scale on this screen
	stick = Vector2.zero, -- the right stick while it is up
	mouseFrom = nil, mouseMoved = false, -- where the cursor was when it opened, and whether it has moved since
	mouseWas = nil, iconWas = nil, -- MouseBehavior and MouseIconEnabled to put back
	checkAt = 0,
	blur = nil, -- the BlurEffect (made when first needed)
	lazy = {}, -- [name] = another controller's module, false if missing
	warned = false,
}

local setPick, close -- (defined further down)

------------------------------------------------------------------ helpers

local function now()
	return Workspace:GetServerTimeNow()
end

-- Another controller's module, or nil if it isn't there (never an error: they start before us).
local function other(name)
	local m = S.lazy[name]
	if m == nil then
		local ok, res = pcall(require, script.Parent:FindFirstChild(name))
		m = (ok and type(res) == "table") and res or false
		S.lazy[name] = m
	end
	return m or nil
end

-- Call another controller's function. A missing controller, a missing function or an error inside it
-- all give nil (and so does a false answer).
local function ask(name, fn, ...)
	local m = other(name)
	local f = m and m[fn]
	if type(f) ~= "function" then
		return nil
	end
	local ok, res = pcall(f, ...)
	if not ok then
		return nil
	end
	return res
end

local function sound(name)
	ask("SoundClient", "Play", name)
end

-- The screen in pixels: the camera's view, which our IgnoreGuiInset gui covers exactly (and which is
-- right even while that gui is switched off). The middle of it is the middle of the wheel.
local function screen()
	local cam = Workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 0 then
		return cam.ViewportSize
	end
	return ui.gui.AbsoluteSize
end

-- May the wheel NOT be up right now? (The same test for opening it and for keeping it up.)
local function blocked()
	if player:GetAttribute("TitleScreen") == true or player:GetAttribute("Side") == "Prisoner" or GuiService.MenuIsOpen then
		return true
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.SeatPart ~= nil then
		return true -- (in any seat: nobody switches guns from behind the wheel, and a passenger can't hold one)
	end
	local t = now()
	if (player:GetAttribute("KnockedUntil") or 0) > t or (player:GetAttribute("StunnedUntil") or 0) > t then
		return true
	end
	if ask("PhoneUI", "IsOpen") == true then
		return true
	end
	-- (also: a citizen or a cop, not at home, not picking a side, no gun shop / dressing room / card up)
	return ask("CombatClient", "CanSwitch") ~= true
end

-- Slot i of n sits at this angle (radians; 0 = right, growing clockwise on screen): the first at the top.
local function slotAngle(i, n)
	return -math.pi / 2 + (i - 1) * 2 * math.pi / n
end

-- The slot a direction on screen (v: x right, y down) points at.
local function slotAt(v, n)
	local step = 2 * math.pi / n
	return math.floor((math.atan2(v.Y, v.X) + math.pi / 2) / step + 0.5) % n + 1
end

-- A Theme label (white, soft shadow). kind = "Display" | "Body" | "Bold".
local function label(parent, name, size, kind, text)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text or ""
	Theme.Text(l, size, kind)
	l.Parent = parent
	return l
end

-- Text that shrinks to fit its box (a long gun name in a small tile), never past these sizes.
local function shrinkToFit(l, min, max)
	l.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MinTextSize, fit.MaxTextSize = min, max
	fit.Parent = l
end

------------------------------------------------------------------ the slots

-- Slot tile number i: made the first time it is needed, then kept (hidden while unused).
local function tile(i)
	local t = ui.tiles[i]
	if t then
		return t
	end
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. i
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(K.TILE.X, K.TILE.Y)
	b.Text = ""
	b.AutoButtonColor = false
	b.Selectable = false -- (the gamepad picks with the stick, never by GUI selection)
	Theme.Panel(b, K.TILE_ALPHA)
	Theme.Corners(b, 8)
	b.ZIndex = 3
	b.Parent = ui.wheel
	local edge = Instance.new("UIStroke")
	edge.Color = C.Text
	edge.Thickness = 2
	edge.Transparency = 1 -- (shown on the highlighted slot only)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = b
	local grow = Instance.new("UIScale")
	grow.Parent = b
	local name = label(b, "Name", nil, "Display")
	name.Position = UDim2.fromOffset(6, 12)
	name.Size = UDim2.new(1, -12, 0, 24)
	shrinkToFit(name, 11, 18)
	local count = label(b, "Ammo", 14, "Display")
	count.Position = UDim2.fromOffset(6, 38)
	count.Size = UDim2.new(1, -12, 0, 18)
	count.TextColor3 = C.Dim
	-- The one in hand: a thin brand line along the bottom.
	local inHand = Instance.new("Frame")
	inHand.Name = "InHand"
	inHand.AnchorPoint = Vector2.new(0.5, 1)
	inHand.Position = UDim2.new(0.5, 0, 1, -6)
	inHand.Size = UDim2.new(0.4, 0, 0, 3)
	inHand.BackgroundColor3 = C.Brand
	inHand.BorderSizePixel = 0
	inHand.Visible = false
	Theme.Corners(inHand, 2)
	inHand.Parent = b
	-- A click or a tap takes it at once (the only way on a phone).
	b.Activated:Connect(function()
		if S.open and i <= #S.slots then
			setPick(i, true)
			close(true)
		end
	end)
	t = { button = b, edge = edge, grow = grow, name = name, count = count, inHand = inHand }
	ui.tiles[i] = t
	return t
end

-- Write slot i's tile from its entry.
local function fill(i, entry)
	local t = tile(i)
	t.name.Text = string.upper(entry.Name or entry.Key or "")
	local count = ""
	if entry.Reloading then
		count = "RELOADING"
	elseif type(entry.Ammo) == "number" then
		count = tostring(entry.Ammo) .. " / ∞"
	end
	t.count.Text = count
	t.count.TextColor3 = (entry.Ammo == 0 and not entry.Reloading) and C.Danger or C.Dim
	t.inHand.Visible = entry.Held == true
end

-- Slot i highlighted (on) or not. instant: no grow animation (a reset).
local function light(i, on, instant)
	local t = ui.tiles[i]
	if not t then
		return
	end
	t.edge.Transparency = on and 0 or 1
	t.button.BackgroundColor3 = on and C.PanelLight or C.Panel
	t.button.BackgroundTransparency = on and 0.04 or K.TILE_ALPHA
	local scale = on and K.GROW or 1
	if instant then
		t.grow.Scale = scale
	else
		TweenService:Create(t.grow, K.POP, { Scale = scale }):Play()
	end
end

-- The middle disc: the highlighted slot, or before a pick the one in hand.
local function showMiddle()
	local entry = S.pick and S.slots[S.pick]
	if not entry then
		for _, e in ipairs(S.slots) do
			if e.Held then
				entry = e
				break
			end
		end
	end
	entry = entry or S.slots[1]
	if not entry then
		return
	end
	ui.title.Text = string.upper(entry.Name or "")
	local sub, color = "", C.Dim
	if entry.Key == K.PUT_AWAY then
		sub = "EMPTY HANDS"
	elseif entry.Held then
		sub, color = "IN HAND", C.Brand
	elseif entry.Class then
		sub = string.upper(entry.Class)
	elseif entry.Key == "Fists" then
		sub = "PUNCH"
	end
	ui.sub.Text = sub
	ui.sub.TextColor3 = color
	local g = entry.Class and Combat.Gun(entry.Key) or nil
	ui.stats.Visible = g ~= nil
	if g then
		local values = { Combat.Stats(g) }
		for n, bar in ipairs(ui.statFills) do
			bar.Size = UDim2.fromScale(values[n] or 0, 1)
		end
	end
end

-- The short white bar on the inner ring, turned toward the highlighted slot.
local function pointNotch()
	local n = #S.slots
	if not S.pick or n == 0 then
		ui.notch.Visible = false
		return
	end
	local a = slotAngle(S.pick, n)
	ui.notch.Position = UDim2.new(0.5, math.floor(math.cos(a) * K.NOTCH + 0.5), 0.5, math.floor(math.sin(a) * K.NOTCH + 0.5))
	ui.notch.Rotation = math.deg(a) + 90 -- (along the ring)
	ui.notch.Visible = true
end

setPick = function(i, quiet)
	if i == S.pick then
		return
	end
	if S.pick then
		light(S.pick, false)
	end
	S.pick = i
	if i then
		light(i, true)
	end
	pointNotch()
	showMiddle()
	if i and not quiet then
		sound("Click")
	end
end

-- The radius (at least `from`) a tile centred in direction a needs so that no part of it, grown, comes
-- within K.CLEAR of the pointer bar's ring. A tile is wider than it is tall: one to the side or on a
-- diagonal would otherwise sit over the middle disc and hide the pointer under it.
local function clearRadius(a, from)
	local hw, hh = K.TILE.X / 2 * K.GROW, K.TILE.Y / 2 * K.GROW
	local ux, uy = math.abs(math.cos(a)), math.abs(math.sin(a))
	local inner = K.NOTCH + K.CLEAR
	local r = from
	while r < 600 do
		-- (the tile's nearest point to the middle, from its centre and half sizes)
		local dx, dy = math.max(ux * r - hw, 0), math.max(uy * r - hh, 0)
		if dx * dx + dy * dy >= inner * inner then
			break
		end
		r += 1
	end
	return r
end

-- n slot tiles on their circle, and the wheel sized to hold them and scaled to fit the screen. The
-- circle grows so neighbours keep 8 px between them and every tile stays clear of the middle.
local function place(n)
	n = math.max(n, 2)
	local r = math.max(K.RADIUS, (K.TILE.X / 2 + 8) / math.sin(math.pi / n))
	for i = 1, n do
		r = clearRadius(slotAngle(i, n), r)
	end
	for i, t in ipairs(ui.tiles) do
		t.button.Visible = i <= #S.slots
	end
	local hw, hh = K.TILE.X / 2 * K.GROW, K.TILE.Y / 2 * K.GROW
	local w, h = K.DISC, K.DISC
	for i = 1, #S.slots do
		local a = slotAngle(i, n)
		local x, y = math.floor(math.cos(a) * r + 0.5), math.floor(math.sin(a) * r + 0.5)
		local t = tile(i)
		t.button.Position = UDim2.new(0.5, x, 0.5, y)
		t.button.Visible = true
		w = math.max(w, 2 * (math.abs(x) + hw))
		h = math.max(h, 2 * (math.abs(y) + hh))
	end
	-- (the box the tiles really use, seldom square: a landscape phone fits it at a bigger scale)
	w, h = math.ceil(w + 8), math.ceil(h + 8)
	ui.wheel.Size = UDim2.fromOffset(w, h)
	local view = screen()
	S.fit = math.clamp(math.min((view.X - 24) / w, (view.Y - 80) / h), 0.5, 1) -- (room for the hint underneath)
	ui.scale.Scale = S.fit
end

-- The key caps under the wheel, for the device that opened it.
local function showHint(how)
	for _, c in ipairs(ui.hint:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local list
	if how == "touch" then
		list = { { false, "TAP ONE TO HOLD IT, OR TAP OUTSIDE TO CLOSE" } }
	elseif how == "gamepad" then
		list = { { "R STICK", "PICK" }, { "D-PAD LEFT", "LET GO TO EQUIP" } }
	else
		list = { { "MOUSE", "PICK" }, { "TAB", "LET GO TO EQUIP" } }
	end
	local order = 0
	for _, pair in ipairs(list) do
		if pair[1] then
			order += 1
			Theme.Key(ui.hint, pair[1]).LayoutOrder = order
		end
		order += 1
		local word = label(ui.hint, "Word", 13, "Bold", pair[2])
		word.LayoutOrder = order
		word.Size = UDim2.fromOffset(0, 22)
		word.AutomaticSize = Enum.AutomaticSize.X
	end
end

-- Ammo counts and what is in hand, fresh (a reload can finish while the wheel is up). The slots
-- themselves stay as they opened.
local function refreshSlots()
	local list = ask("CombatClient", "Weapons")
	if type(list) ~= "table" then
		return
	end
	local byKey, any = {}, false
	for _, e in ipairs(list) do
		byKey[e.Key] = e
		any = any or e.Held == true
	end
	for i, old in ipairs(S.slots) do
		local e = byKey[old.Key]
		if old.Key == K.PUT_AWAY then
			old.Held = not any
			e = old
		end
		if e then
			S.slots[i] = e
			fill(i, e)
		end
	end
	showMiddle()
end

------------------------------------------------------------------ open and close

-- The world behind the wheel goes soft: a BlurEffect on the camera (made on this device: nobody else
-- sees it), eased in and out.
local function blurTo(size)
	local cam = Workspace.CurrentCamera
	local blur = S.blur
	if size > 0 and cam and (not blur or blur.Parent ~= cam) then
		if blur then
			blur:Destroy()
		end
		blur = Instance.new("BlurEffect")
		blur.Name = "NCWeaponWheelBlur"
		blur.Size = 0
		blur.Parent = cam
		S.blur = blur
	end
	if not blur or not blur.Parent then
		return
	end
	blur.Enabled = true
	local tween = TweenService:Create(blur, K.FADE, { Size = size })
	tween:Play()
	if size <= 0 then
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not S.open and blur.Parent then
				blur.Enabled = false
			end
		end)
	end
end

-- While it is up: the right stick picks (and is kept from Roblox's camera), mouse movement, the
-- wheel and the Left / Right arrows are kept from it too.
local function onLook(_, state, input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			S.stick = Vector2.zero
		else
			S.stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end
	return Enum.ContextActionResult.Sink
end

-- Every frame while it is up (after Roblox's camera and CombatClient's gun camera).
local function step()
	if not S.open then
		return
	end
	local t = os.clock()
	if t >= S.checkAt then
		S.checkAt = t + K.CHECK
		if blocked() then
			close(false)
			return
		end
		refreshSlots()
	end
	if S.how == "keyboard" then
		if not UserInputService:IsKeyDown(K.KEY) then
			close(true) -- (a let-go we never heard about)
			return
		end
		-- The cursor stays free and visible (shift lock or first person would take it back).
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
		local m = UserInputService:GetMouseLocation() -- (screen pixels, the same as our IgnoreGuiInset gui)
		if not S.mouseMoved and S.mouseFrom and (m - S.mouseFrom).Magnitude > 3 then
			S.mouseMoved = true
		end
		local v = m - screen() / 2
		if S.mouseMoved and v.Magnitude >= K.DEAD_PX then
			setPick(slotAt(v, #S.slots))
		end
	elseif S.how == "gamepad" then
		if not (S.pad and UserInputService:IsGamepadButtonDown(S.pad, K.PAD)) then
			close(true)
			return
		end
		local v = Vector2.new(S.stick.X, -S.stick.Y) -- (the stick's y points up, the screen's down)
		if v.Magnitude >= K.DEAD_STICK then
			setPick(slotAt(v, #S.slots))
		end
	end
end

-- Open it (how = "keyboard" | "gamepad" | "touch"; pad = the gamepad holding it). True if it opened.
local function open(how, pad)
	if S.open or not ui.gui or blocked() then
		return false
	end
	local list = ask("CombatClient", "Weapons")
	if type(list) ~= "table" then
		if not S.warned then
			S.warned = true
			warn("[WeaponWheel] CombatClient.Weapons is missing: the wheel stays shut")
		end
		return false
	end
	if #list == 0 then
		return false -- (nothing to switch to: the tools haven't arrived yet)
	end
	local slots, any = {}, false
	for _, e in ipairs(list) do
		table.insert(slots, e)
		any = any or e.Held == true
	end
	table.insert(slots, { Key = K.PUT_AWAY, Name = "Put away", Held = not any })
	S.slots = slots
	S.open, S.how, S.pad = true, how, pad
	S.pick, S.stick, S.mouseMoved = nil, Vector2.zero, false
	S.checkAt = os.clock() + K.CHECK
	place(#slots)
	for i, e in ipairs(slots) do
		fill(i, e)
		light(i, false, true)
	end
	pointNotch()
	showMiddle()
	showHint(how)
	ask("CombatClient", "SetWheelOpen", true)
	if how == "keyboard" then
		-- The cursor, free and visible. With a gun out CombatClient holds it at the crosshair and takes it
		-- back by itself once we close (if the gun is still out), so "free" is what gets put back then.
		if ask("CombatClient", "GunOut") == true then
			S.mouseWas, S.iconWas = Enum.MouseBehavior.Default, true
		else
			S.mouseWas, S.iconWas = UserInputService.MouseBehavior, UserInputService.MouseIconEnabled
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		S.mouseFrom = UserInputService:GetMouseLocation()
	end
	-- (Left / Right arrow: Roblox's camera turns with those keys too.)
	ContextActionService:BindActionAtPriority(K.LOOK_ACTION, onLook, false, K.PRIORITY,
		Enum.KeyCode.Thumbstick2, Enum.UserInputType.MouseMovement, Enum.UserInputType.MouseWheel,
		Enum.KeyCode.Left, Enum.KeyCode.Right)
	RunService:BindToRenderStep(K.STEP, Enum.RenderPriority.Camera.Value + 4, step)
	ui.gui.Enabled = true
	ui.back.BackgroundTransparency = 1
	TweenService:Create(ui.back, K.FADE, { BackgroundTransparency = K.BACK_ALPHA }):Play()
	ui.scale.Scale = S.fit * 0.92
	TweenService:Create(ui.scale, K.FADE, { Scale = S.fit }):Play()
	blurTo(K.BLUR)
	sound("Click")
	return true
end

-- Close it. apply: equip the highlighted slot (nothing highlighted, or it is in hand already: no change).
close = function(apply)
	if not S.open then
		return
	end
	S.open = false
	local entry = (apply and S.pick) and S.slots[S.pick] or nil
	pcall(ContextActionService.UnbindAction, ContextActionService, K.LOOK_ACTION)
	pcall(RunService.UnbindFromRenderStep, RunService, K.STEP)
	ask("CombatClient", "SetWheelOpen", false)
	if S.how == "keyboard" and S.mouseWas then
		UserInputService.MouseBehavior = S.mouseWas
		UserInputService.MouseIconEnabled = S.iconWas ~= false
	end
	S.mouseWas, S.iconWas, S.mouseFrom = nil, nil, nil
	S.stick = Vector2.zero
	ui.gui.Enabled = false
	if S.pick then
		light(S.pick, false, true)
	end
	S.pick = nil
	blurTo(0)
	if entry and not entry.Held then
		ask("CombatClient", "EquipKey", entry.Key) -- (with CombatClient's own click)
	end
end

------------------------------------------------------------------ building it

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeaponWheel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = K.DISPLAY_ORDER
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui

	-- A dark sheet over the whole screen (K.BACK_ALPHA: it dims the HUD under the wheel, which the blur
	-- can't): it takes every click and tap (no shot, no camera drag), a tap on it closes the wheel on a
	-- phone, and being Modal it frees the mouse.
	local back = Instance.new("TextButton")
	back.Name = "Backdrop"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = C.Shadow
	back.BackgroundTransparency = 1
	back.BorderSizePixel = 0
	back.AutoButtonColor = false
	back.Selectable = false
	back.Text = ""
	back.Modal = true
	back.Parent = gui
	back.Activated:Connect(function()
		if S.how == "touch" then
			close(false)
		end
	end)
	ui.back = back

	local wheel = Instance.new("Frame")
	wheel.Name = "Wheel"
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.Size = UDim2.fromOffset(440, 440) -- (place sizes it for the slots)
	wheel.BackgroundTransparency = 1
	wheel.ZIndex = 2
	wheel.Parent = gui
	ui.wheel = wheel
	local scale = Instance.new("UIScale")
	scale.Parent = wheel
	ui.scale = scale

	-- The middle: a round dark disc with a faint ring, the highlighted slot's name, a line under it and
	-- (for a gun) the three bars.
	local disc = Instance.new("Frame")
	disc.Name = "Middle"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(K.DISC, K.DISC)
	Theme.Panel(disc, 0.08)
	Theme.Corners(disc).CornerRadius = UDim.new(0.5, 0)
	disc.ZIndex = 2
	disc.Parent = wheel
	local ring = Instance.new("UIStroke")
	ring.Color = C.Text
	ring.Thickness = 1.5
	ring.Transparency = 0.7
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = disc
	ui.title = label(disc, "Title", nil, "Display")
	ui.title.Position = UDim2.fromOffset(16, 34)
	ui.title.Size = UDim2.new(1, -32, 0, 30)
	shrinkToFit(ui.title, 12, 26)
	ui.sub = label(disc, "Sub", 11, "Bold")
	ui.sub.Position = UDim2.fromOffset(16, 66)
	ui.sub.Size = UDim2.new(1, -32, 0, 14)
	ui.sub.TextColor3 = C.Dim
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(28, 88)
	stats.Size = UDim2.new(1, -56, 0, 44)
	stats.Visible = false
	stats.Parent = disc
	ui.stats = stats
	ui.statFills = {}
	for n, word in ipairs(K.STATS) do
		local y = (n - 1) * 15
		local l = label(stats, word, 9, "Bold", word)
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(0.5, 0, 0, 11)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = C.Dim
		local bar, barFill = Theme.Bar(stats, C.Text)
		bar.Name = word
		bar.AnchorPoint = Vector2.new(1, 0)
		bar.Position = UDim2.new(1, 0, 0, y + 3)
		bar.Size = UDim2.new(0.46, 0, 0, 5)
		ui.statFills[n] = barFill
	end

	-- The pointer: a short white bar along the inner ring, toward the highlighted slot (pointNotch).
	local notch = Instance.new("Frame")
	notch.Name = "Pointer"
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.Size = UDim2.fromOffset(34, 4)
	notch.BackgroundColor3 = C.Text
	notch.BorderSizePixel = 0
	notch.Visible = false
	notch.ZIndex = 2
	Theme.Corners(notch, 2)
	notch.Parent = wheel
	ui.notch = notch

	-- Key caps under the wheel (showHint).
	local hint = Instance.new("Frame")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 1, 2)
	hint.Size = UDim2.fromOffset(0, 30)
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.ZIndex = 2
	Theme.Panel(hint, 0.15)
	hint.Parent = wheel
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 6)
	row.Parent = hint
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 10)
	pad.Parent = hint
	ui.hint = hint
end

------------------------------------------------------------------ API

function WeaponWheel.IsOpen()
	return S.open
end

-- CombatClient's WEAPON button, held: the wheel for a finger (tap a slot, or outside to close).
function WeaponWheel.OpenTouch()
	return open("touch") == true
end

function WeaponWheel.Close()
	close(false)
end

function WeaponWheel.Init()
	build()
	-- Hold Tab / D-pad left. (A key a text box or a GUI selection took comes in processed: not ours.)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or S.open then
			return
		end
		if input.KeyCode == K.KEY then
			open("keyboard")
		elseif input.KeyCode == K.PAD then
			open("gamepad", input.UserInputType)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if S.open and ((S.how == "keyboard" and input.KeyCode == K.KEY) or (S.how == "gamepad" and input.KeyCode == K.PAD)) then
			close(true)
		end
	end)
	-- Alt-tab, the Roblox menu, a respawn: shut, nothing changed.
	UserInputService.WindowFocusReleased:Connect(function()
		close(false)
	end)
	GuiService.MenuOpened:Connect(function()
		close(false)
	end)
	player.CharacterRemoving:Connect(function()
		close(false)
	end)
	ui.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.open then
			place(#S.slots)
		end
	end)
end

return WeaponWheel
