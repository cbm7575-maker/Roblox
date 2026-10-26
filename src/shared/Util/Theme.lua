-- Theme (ModuleScript, ReplicatedStorage.Shared.Util.Theme)
-- The look of every screen element ("street" HUD, 2026-10): small, flat and quiet, like a console
-- open-world game, not a cartoon simulator.
--   * Panels are flat black, see-through, with small corners and NO thick coloured outlines.
--   * Text is white, in two fonts: Display (condensed, for numbers, titles and stamps) and Body.
--   * Colour is used for meaning only: green = cash, red = danger / wanted, blue = police / armour,
--     gold = reward / goal. Pink is the brand accent, used sparingly (a thin line, a highlight).
--   * Sizes are in pixels and small on a PC; touch buttons stay at least Theme.Touch pixels tall.
-- Use the helpers so every screen matches:
--   Theme.Panel(guiObject, alpha?)   flat dark panel look (background, corner)
--   Theme.Text(label, size?, kind?)  font + colour + soft shadow; kind = "Display" | "Body" | "Bold"
--   Theme.Button(button, kind?)      a flat button; kind = "Primary" | "Quiet" | "Danger"
--   Theme.Key(parent, text)          a little key cap ("F", "E", "SPACE") for control hints
--   Theme.Bar(parent, color)         a thin progress bar; returns frame, fill (set fill.Size X scale)

local Theme = {}

Theme.Color = {
	Panel = Color3.fromRGB(8, 10, 14),
	PanelLight = Color3.fromRGB(28, 32, 40),
	Text = Color3.fromRGB(245, 245, 245),
	Dim = Color3.fromRGB(176, 182, 190),
	Shadow = Color3.fromRGB(0, 0, 0),
	Cash = Color3.fromRGB(114, 204, 114),
	Danger = Color3.fromRGB(224, 62, 62),
	Police = Color3.fromRGB(93, 182, 229),
	Gold = Color3.fromRGB(240, 200, 80),
	Orange = Color3.fromRGB(255, 150, 70),
	Purple = Color3.fromRGB(150, 120, 235),
	Health = Color3.fromRGB(96, 176, 96),
	Armor = Color3.fromRGB(80, 152, 220),
	Brand = Color3.fromRGB(255, 62, 165), -- the brand pink: accents only
	BrandAlt = Color3.fromRGB(34, 225, 255), -- neon cyan: accents only
}

Theme.Font = {
	Display = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	DisplayLight = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular),
	Body = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	Bold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
	-- Big moments only (HUDController stamps: MISSION PASSED, CUFFED, +$1,200...): heavy, slanted, thick
	-- black outline, the open-world-crime-game "headline" look. Our own font choice, not any game's.
	Big = Font.new("rbxasset://fonts/families/Bangers.json", Enum.FontWeight.Regular),
	-- The game logo (TeamUI title screen): extra-heavy italic, filled with Theme.Sunset.
	Logo = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
}

-- The logo's sunset fill, top to bottom (UIGradient Rotation 90): sun yellow, orange, brand pink, violet.
Theme.Sunset = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 92)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 138, 60)),
	ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 62, 165)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 70, 230)),
})
Theme.Ink = Color3.fromRGB(20, 12, 40) -- the logo's outline and drop shadow (a deep night violet)

Theme.PanelAlpha = 0.4 -- BackgroundTransparency of a normal panel
Theme.Corner = 5 -- pixels
Theme.Touch = 44 -- smallest height of anything meant to be tapped

-- WHERE THINGS GO ("street" HUD layout). Every always-on HUD piece has one zone; nothing else may sit
-- in another piece's zone. All HUD ScreenGuis use IgnoreGuiInset = true, so y = 0 is the very top of the
-- screen and Roblox's own top bar covers the first Theme.TopBar pixels on the left.
--   Theme.Zone(name, touch) -> { Anchor = Vector2, Pos = UDim2, Size = UDim2, Grow = "Up" | "Down" | nil }
--   Theme.Place(guiObject, name, touch) sets AnchorPoint / Position / Size from the zone.
-- "touch" = the phone layout (Roblox thumbstick bottom-left, jump / pedals bottom-right).
--   PC / gamepad                                   PHONE
--   Minimap   bottom-left, Vitals under it         Minimap   top-left under the top bar, Vitals under it
--   Toasts    stack upward above the minimap       Toasts    stack downward under the vitals
--   Status    top-right: stars, cash, bag, role    Status    top-right (smaller)
--   Pills     under Status (SAFE ZONE, PASSIVE...)  Pills     under Status
--   Buttons   right edge, middle (PHONE, CAR)      Buttons   a row under the pills (PHONE, CAR / EXIT)
--   Goal      top-centre strip                     Goal      top-centre strip (narrower)
--   Banner    under Goal (race / drift / timers)   Banner    under Goal
--   Subtitle  bottom-centre lines of help text     Subtitle  bottom-centre, above the car cluster
--   Action    bottom-centre button (GET IN, JACK)  Action    right of centre, above the jump button
--   Corner    bottom-right: car cluster / weapon   Corner    bottom-centre (the pedals own bottom-right)
--   Exit      left of the car cluster              Exit      in the Buttons row (takes CAR's place)
--   Stamp     big moment text, upper middle        Stamp     same
Theme.TopBar = 58

local function zone(ax, ay, pos, size, grow)
	return { Anchor = Vector2.new(ax, ay), Pos = pos, Size = size, Grow = grow }
end

local ZONES = {
	Desktop = {
		Minimap = zone(0, 1, UDim2.new(0, 20, 1, -42), UDim2.fromOffset(240, 160)),
		Vitals = zone(0, 1, UDim2.new(0, 20, 1, -20), UDim2.fromOffset(240, 14)),
		Toasts = zone(0, 1, UDim2.new(0, 20, 1, -212), UDim2.fromOffset(340, 0), "Up"),
		Feed = zone(0, 0, UDim2.new(0, 16, 0, 66), UDim2.fromOffset(320, 0), "Down"),
		Status = zone(1, 0, UDim2.new(1, -20, 0, 14), UDim2.fromOffset(280, 116)),
		Pills = zone(1, 0, UDim2.new(1, -20, 0, 136), UDim2.fromOffset(280, 26)),
		Buttons = zone(1, 0.5, UDim2.new(1, -20, 0.5, 0), UDim2.fromOffset(52, 112)),
		Goal = zone(0.5, 0, UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(520, 44)),
		Banner = zone(0.5, 0, UDim2.new(0.5, 0, 0, 64), UDim2.fromOffset(440, 40)),
		Subtitle = zone(0.5, 1, UDim2.new(0.5, 0, 1, -140), UDim2.fromOffset(640, 52)), -- (narrower on small windows: Theme.Zone)
		Action = zone(0.5, 1, UDim2.new(0.5, 0, 1, -64), UDim2.fromOffset(240, 48)),
		Corner = zone(1, 1, UDim2.new(1, -24, 1, -24), UDim2.fromOffset(300, 110)),
		Exit = zone(1, 1, UDim2.new(1, -336, 1, -24), UDim2.fromOffset(88, 44)),
		Stamp = zone(0.5, 0.5, UDim2.new(0.5, 0, 0.3, 0), UDim2.fromOffset(720, 164)),
	},
	Touch = {
		Minimap = zone(0, 0, UDim2.new(0, 12, 0, 64), UDim2.fromOffset(150, 104)),
		Vitals = zone(0, 0, UDim2.new(0, 12, 0, 172), UDim2.fromOffset(150, 12)),
		Toasts = zone(0, 0, UDim2.new(0, 12, 0, 190), UDim2.fromOffset(260, 0), "Down"),
		Feed = zone(0, 0, UDim2.new(0, 12, 0, 190), UDim2.fromOffset(260, 0), "Down"), -- shares the toast stack
		Status = zone(1, 0, UDim2.new(1, -12, 0, 10), UDim2.fromOffset(210, 98)),
		Pills = zone(1, 0, UDim2.new(1, -12, 0, 112), UDim2.fromOffset(210, 24)),
		Buttons = zone(1, 0, UDim2.new(1, -12, 0, 142), UDim2.fromOffset(112, 48)),
		Goal = zone(0.5, 0, UDim2.new(0.5, 0, 0, 8), UDim2.new(0.42, 0, 0, 40)),
		Banner = zone(0.5, 0, UDim2.new(0.5, 0, 0, 54), UDim2.new(0.4, 0, 0, 36)),
		Subtitle = zone(0.5, 1, UDim2.new(0.5, 0, 1, -105), UDim2.new(0.5, 0, 0, 44)), -- (between the radio row, top at -104, and Action, bottom at -150)
		Action = zone(0.5, 1, UDim2.new(0.62, 0, 1, -150), UDim2.fromOffset(200, 52)),
		Corner = zone(0.5, 1, UDim2.new(0.5, 0, 1, -10), UDim2.fromOffset(300, 92)),
		Exit = zone(1, 0, UDim2.new(1, -12, 0, 142), UDim2.fromOffset(112, 48)),
		Stamp = zone(0.5, 0.5, UDim2.new(0.5, 0, 0.3, 0), UDim2.new(0.8, 0, 0, 120)),
	},
}

function Theme.Zone(name, touch)
	local set = touch and ZONES.Touch or ZONES.Desktop
	local z = set[name] or ZONES.Desktop[name]
	if touch and (name == "Goal" or name == "Banner") then
		-- On a narrow phone (under ~800 px wide) the centred strip would run under Status in the top
		-- right: keep its left edge and end it 8 px short of Status.
		local camera = workspace.CurrentCamera
		local w = camera and camera.ViewportSize.X or 0
		local status = ZONES.Touch.Status
		local width = z.Size.X.Scale * w + z.Size.X.Offset
		local left = z.Pos.X.Scale * w + z.Pos.X.Offset - z.Anchor.X * width
		local limit = w + status.Pos.X.Offset - status.Size.X.Offset - 8
		if w > 0 and left + width > limit and limit - left >= 160 then
			width = limit - left
			return { Anchor = Vector2.new(0, z.Anchor.Y), Pos = UDim2.new(0, left, z.Pos.Y.Scale, z.Pos.Y.Offset),
				Size = UDim2.new(0, width, z.Size.Y.Scale, z.Size.Y.Offset), Grow = z.Grow }
		end
	end
	if name == "Subtitle" and not touch then
		-- The strip sits level with the minimap: on a narrow window it shrinks to stay clear of it (and of
		-- the same margin on the right), never under 360 px.
		local camera = workspace.CurrentCamera
		local mini = ZONES.Desktop.Minimap
		local free = (camera and camera.ViewportSize.X or 1920) - 2 * (mini.Pos.X.Offset + mini.Size.X.Offset + 12)
		if free < z.Size.X.Offset then
			return { Anchor = z.Anchor, Pos = z.Pos, Size = UDim2.fromOffset(math.max(360, free), z.Size.Y.Offset), Grow = z.Grow }
		end
	end
	return z
end

function Theme.Place(obj, name, touch)
	local z = Theme.Zone(name, touch)
	obj.AnchorPoint = z.Anchor
	obj.Position = z.Pos
	if z.Size.X.Offset ~= 0 or z.Size.X.Scale ~= 0 then
		obj.Size = z.Grow and UDim2.new(z.Size.X.Scale, z.Size.X.Offset, obj.Size.Y.Scale, obj.Size.Y.Offset) or z.Size
	end
	return z
end

-- The phone layout is in use: a touch screen with no mouse (same test the drive HUD uses).
function Theme.IsTouch()
	local uis = game:GetService("UserInputService")
	return uis.TouchEnabled and not uis.MouseEnabled
end

function Theme.Corners(obj, px)
	local c = obj:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or Theme.Corner)
	c.Parent = obj
	return c
end

function Theme.Panel(obj, alpha)
	obj.BackgroundColor3 = Theme.Color.Panel
	obj.BackgroundTransparency = alpha or Theme.PanelAlpha
	obj.BorderSizePixel = 0
	Theme.Corners(obj)
	return obj
end

-- A soft dark edge so white text reads over a bright street or sky.
function Theme.Shadow(label, thickness)
	local s = label:FindFirstChild("Shadow") or Instance.new("UIStroke")
	s.Name = "Shadow"
	s.Color = Theme.Color.Shadow
	s.Thickness = thickness or 1.5
	s.Transparency = 0.45
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
	return s
end

function Theme.Text(label, size, kind)
	label.FontFace = Theme.Font[kind or "Body"] or Theme.Font.Body
	label.TextColor3 = Theme.Color.Text
	label.BackgroundTransparency = 1
	if size then
		label.TextScaled = false
		label.TextSize = size
	end
	Theme.Shadow(label)
	return label
end

local BUTTON = {
	Primary = { Back = Color3.fromRGB(245, 245, 245), Text = Color3.fromRGB(12, 14, 18), Alpha = 0.05 },
	Quiet = { Back = Theme.Color.Panel, Text = Theme.Color.Text, Alpha = 0.35 },
	Danger = { Back = Theme.Color.Danger, Text = Theme.Color.Text, Alpha = 0.1 },
}

function Theme.Button(button, kind)
	local look = BUTTON[kind or "Quiet"] or BUTTON.Quiet
	button.AutoButtonColor = true
	button.BackgroundColor3 = look.Back
	button.BackgroundTransparency = look.Alpha
	button.BorderSizePixel = 0
	button.FontFace = Theme.Font.Bold
	button.TextColor3 = look.Text
	Theme.Corners(button)
	return button
end

function Theme.Key(parent, text)
	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.Size = UDim2.fromOffset(math.max(22, 10 + #text * 9), 22)
	key.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	key.BackgroundTransparency = 0.05
	key.BorderSizePixel = 0
	key.FontFace = Theme.Font.Bold
	key.TextSize = 13
	key.TextColor3 = Color3.fromRGB(12, 14, 18)
	key.Text = text
	Theme.Corners(key, 4)
	key.Parent = parent
	return key
end

function Theme.Bar(parent, color)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Theme.Color.Panel
	bar.BackgroundTransparency = 0.35
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0, 6)
	Theme.Corners(bar, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color or Theme.Color.Text
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	Theme.Corners(fill, 2)
	fill.Parent = bar
	bar.Parent = parent
	return bar, fill
end

return Theme
