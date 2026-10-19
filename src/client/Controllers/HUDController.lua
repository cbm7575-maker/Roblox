-- HUDController (ModuleScript, StarterPlayerScripts.Controllers.HUDController)
-- Always-on HUD: cash and bag (top left, under the team badge), heat stars (top right) with the
-- escape bar beside them, and big full-screen stamps for moments ("CLEAN GETAWAY +$1,200", "CAUGHT!").
-- Everything reads player attributes the server sets: Cash, Carried, Heat, HeatSpotted, and the
-- escape window from HeatService: EscapeEnd (server time the stars clear if you stay unseen) and
-- EscapeTotal (that window's full length in seconds).
-- Shared layout: HUDController.TopBar(gui, name, color) builds the two-line bar in the top slot
-- (tutorial, mission, objective: one shows at a time); HUDController.TopBarRect(w, h) is its rectangle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local HUDController = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local GOLD = Color3.fromRGB(255, 214, 10)
local MINT = Color3.fromRGB(110, 242, 196)
local RED = Color3.fromRGB(255, 70, 70)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local STAR, STAR_GAP = 36, 4

local gui, cashLabel, bagLabel, starsFrame
local escapeFrame, escapeFill, escapeLabel, escapeStroke
local stars = {}

local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end
HUDController.Money = money

------------------------------------------------------------------ the top bar slot

-- Between the left column and the minimap, below the badge row. The cash and bag pills end at
-- x = 186; the team badge and rank chip above them reach x = 246 but end at y = 100.
local BAR_TOP, BAR_H = 104, 52
local LEFT_EDGE = 186
local RANK_RIGHT = 246 -- right edge of the rank chip (TeamUI), on the top row

-- While the driving HUD shows, DriveUI's EXIT/FLIP column (0.1H wide, right edge at W - 200) sits
-- left of the minimap: the bar and the GPS label end before it instead of under it.
local driving = false
local layouts = {} -- re-run when the driving HUD shows or hides

-- Rightmost x the top bar and the top row may use on a w x h screen.
local function rightLimit(w, h)
	local map = math.floor(math.clamp(h * 0.22, 110, 170)) -- MinimapClient's size rule
	local right = w - 16 - map
	if driving then
		right = math.min(right, w - 200 - math.floor(h * 0.1 + 0.5))
	end
	return right - 8
end

-- The top row (y 58-90, the GPS route label) between the rank chip and rightLimit: x, width.
function HUDController.TopRowRect(w, h)
	local left, right = RANK_RIGHT + 8, rightLimit(w, h)
	local width = math.min(300, right - left)
	if width < 160 then -- a very narrow screen: the middle of it
		width = math.max(0, math.min(w - 24, 300))
		return math.floor((w - width) / 2), width
	end
	return left + math.floor((right - left - width) / 2), width
end

-- fn() runs now and again whenever the driving HUD shows or hides (callers also handle resizes).
function HUDController.OnLayout(fn)
	table.insert(layouts, fn)
	fn()
end

-- The bar's rectangle on a w x h screen: x, y, width, height (pixels, IgnoreGuiInset coordinates).
function HUDController.TopBarRect(w, h)
	local left, right = LEFT_EDGE + 8, rightLimit(w, h)
	local width = math.min(right - left, 560)
	if width < 220 then -- a very narrow screen: the middle of it
		width = math.max(0, math.min(w - 24, 320))
		return math.floor((w - width) / 2), BAR_TOP, width, BAR_H
	end
	return left + math.floor((right - left - width) / 2), BAR_TOP, width, BAR_H
end

-- A two-line bar (wrapped text, 14-20 px) in the top slot of `parent` (a ScreenGui with
-- IgnoreGuiInset). Returns { Frame, Text, Stroke, SetText(richText), SetInsets(left, right) }:
-- SetText picks the largest size from 20 down to 14 that fits two lines (then truncates with "...");
-- insets are the pixels kept free for the owner's buttons at each end. Starts hidden.
function HUDController.TopBar(parent, name, color)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = DARK
	frame.BackgroundTransparency = 0.15
	frame.Visible = false
	frame.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = frame
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = frame
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.TextSize = 18
	text.TextWrapped = true
	text.RichText = true
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.ZIndex = 2
	text.Parent = frame
	local bar = { Frame = frame, Text = text, Stroke = st }
	local wanted, fitted = "", nil
	local function fit()
		local w, h = text.AbsoluteSize.X, text.AbsoluteSize.Y
		local key = wanted .. "|" .. w .. "x" .. h
		if key == fitted or w <= 0 then
			return
		end
		fitted = key
		local plain = string.gsub(wanted, "<[^>]->", "")
		local size = 14
		for s = 20, 15, -1 do
			local ok, b = pcall(TextService.GetTextSize, TextService, plain, s, FONT, Vector2.new(w, 10000))
			if ok and b.Y <= h then
				size = s
				break
			end
		end
		text.TextSize = size
		text.Text = wanted
	end
	function bar.SetText(rich)
		wanted = tostring(rich)
		fit()
		if text.Text ~= wanted then -- not laid out yet: fit() runs again when it is
			text.Text = wanted
		end
	end
	function bar.SetInsets(left, right)
		text.Position = UDim2.fromOffset(left, 5)
		text.Size = UDim2.new(1, -(left + right), 1, -10)
	end
	bar.SetInsets(18, 18)
	text:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local function layout()
		local size = parent.AbsoluteSize
		local x, y, w, h = HUDController.TopBarRect(size.X, size.Y)
		frame.Position = UDim2.fromOffset(x, y)
		frame.Size = UDim2.fromOffset(w, h)
	end
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	HUDController.OnLayout(layout)
	return bar
end

local function pill(name, pos, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = pos
	l.Size = UDim2.fromOffset(170, 34)
	l.BackgroundColor3 = DARK
	l.BackgroundTransparency = 0.2
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = l
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = l
	local p = Instance.new("UIPadding")
	p.PaddingLeft, p.PaddingRight = UDim.new(0, 14), UDim.new(0, 10)
	p.PaddingTop, p.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
	p.Parent = l
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- same coordinates as the team badge (TeamUI)
	gui.Parent = player:WaitForChild("PlayerGui")

	cashLabel = pill("Cash", UDim2.new(0, 16, 0, 108), MINT)
	bagLabel = pill("Bag", UDim2.new(0, 16, 0, 148), GOLD)

	-- CAR: bring your car to you (until the phone Garage app, step 4.3). The server decides.
	local carButton = Instance.new("TextButton")
	carButton.Name = "CarButton"
	carButton.Position = UDim2.new(0, 16, 0, 188) -- left column, under cash and bag
	carButton.Size = UDim2.fromOffset(84, 40)
	carButton.BackgroundColor3 = DARK
	carButton.BackgroundTransparency = 0.2
	carButton.Font = FONT
	carButton.TextScaled = true
	carButton.TextColor3 = CYAN
	carButton.Text = "CAR"
	carButton.Parent = gui
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.5, 0)
	cc.Parent = carButton
	local cs = Instance.new("UIStroke")
	cs.Color = CYAN
	cs.Thickness = 2
	cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cs.Parent = carButton
	local cp = Instance.new("UIPadding")
	cp.PaddingTop, cp.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	cp.Parent = carButton
	carButton.Activated:Connect(function()
		local side = player:GetAttribute("Side") or "Civilian"
		local fallback = side == "Cop" and "SunrayPatrol" or "Palmetto"
		Remotes.Event("RequestSpawnCar"):FireServer(player:GetAttribute("LastCar") or fallback)
	end)
	HUDController.CarButton = carButton

	starsFrame = Instance.new("Frame")
	starsFrame.Name = "Heat"
	starsFrame.AnchorPoint = Vector2.new(1, 0)
	starsFrame.Position = UDim2.new(1, -16, 0, 12)
	starsFrame.Size = UDim2.fromOffset(200, 40)
	starsFrame.BackgroundTransparency = 1
	starsFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = starsFrame
	layout.Padding = UDim.new(0, STAR_GAP)
	for i = 1, 5 do
		local s = Instance.new("TextLabel")
		s.Name = "Star" .. i
		s.LayoutOrder = i
		s.Size = UDim2.fromOffset(STAR, STAR)
		s.BackgroundTransparency = 1
		s.Font = Enum.Font.GothamBlack
		s.TextScaled = true
		s.Text = "★"
		s.TextColor3 = Color3.new(1, 1, 1)
		local st = Instance.new("UIStroke")
		st.Color = PINK
		st.Thickness = 2
		st.Parent = s
		s.Parent = starsFrame
		stars[i] = s
	end

	-- Escape bar, left of the stars (the minimap sits right under them): SPOTTED in red while a cop
	-- can see you; LOSING THEM filling up while you stay out of sight.
	escapeFrame = Instance.new("Frame")
	escapeFrame.Name = "Escape"
	escapeFrame.AnchorPoint = Vector2.new(1, 0)
	escapeFrame.Position = UDim2.new(1, -60, 0, 14)
	escapeFrame.Size = UDim2.fromOffset(190, 36)
	escapeFrame.BackgroundColor3 = DARK
	escapeFrame.BackgroundTransparency = 0.15
	escapeFrame.Visible = false
	escapeFrame.Parent = gui
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0.5, 0)
	ec.Parent = escapeFrame
	escapeStroke = Instance.new("UIStroke")
	escapeStroke.Thickness = 2
	escapeStroke.Color = MINT
	escapeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	escapeStroke.Parent = escapeFrame
	escapeFill = Instance.new("Frame")
	escapeFill.Name = "Fill"
	escapeFill.Size = UDim2.fromScale(0, 1)
	escapeFill.BackgroundColor3 = MINT
	escapeFill.BackgroundTransparency = 0.45
	escapeFill.Parent = escapeFrame
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = escapeFill
	escapeLabel = Instance.new("TextLabel")
	escapeLabel.Name = "Label"
	escapeLabel.BackgroundTransparency = 1
	escapeLabel.Size = UDim2.fromScale(1, 1)
	escapeLabel.Font = FONT
	escapeLabel.TextScaled = true
	escapeLabel.TextColor3 = Color3.new(1, 1, 1)
	escapeLabel.ZIndex = 2
	escapeLabel.Parent = escapeFrame
	local ls = Instance.new("UIStroke")
	ls.Color = DARK
	ls.Thickness = 2
	ls.Parent = escapeLabel
	local lp = Instance.new("UIPadding")
	lp.PaddingTop, lp.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	lp.PaddingLeft, lp.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	lp.Parent = escapeLabel
end

-- How far through the escape window (0..1) and the seconds left, from EscapeEnd / EscapeTotal.
-- Pure, so it can be tested: EscapeTotal falls back to HeatService's 30 + 10 per star.
function HUDController.EscapeProgress(escapeEnd, total, heat, now)
	if type(escapeEnd) ~= "number" then
		return nil, nil
	end
	total = (type(total) == "number" and total > 0) and total or (30 + 10 * heat)
	local left = math.max(0, escapeEnd - now)
	return math.clamp(1 - left / total, 0, 1), math.ceil(left)
end

local function updateEscape()
	local heat = player:GetAttribute("Heat") or 0
	escapeFrame.Visible = heat > 0
	if heat <= 0 then
		return
	end
	-- Right beside the visible stars (they're right-aligned), whatever the star count.
	local n = math.clamp(math.floor(heat), 1, 5)
	local starsW = n * STAR + (n - 1) * STAR_GAP
	local w = math.clamp(math.floor(gui.AbsoluteSize.X * 0.26), 150, 220)
	escapeFrame.Position = UDim2.new(1, -(16 + starsW + 8), 0, 14)
	escapeFrame.Size = UDim2.fromOffset(w, 36)
	if player:GetAttribute("HeatSpotted") == true then
		escapeLabel.Text = "SPOTTED!"
		escapeLabel.TextColor3 = RED
		escapeStroke.Color = RED
		escapeFill.BackgroundColor3 = RED
		escapeFill.BackgroundTransparency = 0.75
		escapeFill.Size = UDim2.fromScale(1, 1)
		return
	end
	local frac, left = HUDController.EscapeProgress(player:GetAttribute("EscapeEnd"), player:GetAttribute("EscapeTotal"),
		heat, Workspace:GetServerTimeNow())
	escapeLabel.TextColor3 = Color3.new(1, 1, 1)
	escapeFill.BackgroundColor3 = MINT
	escapeFill.BackgroundTransparency = 0.45
	if frac then
		escapeLabel.Text = "LOSING THEM  " .. left .. "s"
		escapeStroke.Color = MINT
		escapeFill.Size = UDim2.fromScale(frac, 1)
	else
		escapeLabel.Text = "STAY HIDDEN"
		escapeStroke.Color = PINK
		escapeFill.Size = UDim2.fromScale(0, 1)
	end
end

local function refresh()
	cashLabel.Text = money(player:GetAttribute("Cash") or 0)
	local carried = player:GetAttribute("Carried") or 0
	bagLabel.Visible = carried > 0
	bagLabel.Text = "BAG " .. money(carried)
	local heat = player:GetAttribute("Heat") or 0
	local spotted = player:GetAttribute("HeatSpotted") == true
	if HUDController.CarButton then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local driving = hum ~= nil and hum.SeatPart ~= nil
		HUDController.CarButton.Visible = player:GetAttribute("Side") ~= "Prisoner" and not driving
	end
	starsFrame.Visible = heat > 0
	for i, s in ipairs(stars) do
		local on = i <= heat
		s.Visible = on
		-- Solid stars = a cop can see you; hollow (outline) = they're searching.
		s.Text = spotted and "★" or "☆"
		s.TextTransparency = 0
		s.TextColor3 = spotted and Color3.fromRGB(255, 240, 120) or Color3.new(1, 1, 1)
		s.UIStroke.Color = spotted and Color3.fromRGB(255, 60, 60) or PINK
	end
	updateEscape()
end

-- Big centre-screen stamp. Stamps queue up so two moments never draw on top of each other.
-- opts (optional): { Big = true } for a larger stamp that stays up longer (district / all-40 finds).
local stampQueue = {}
local stamping = false
local showStamp

function HUDController.Stamp(title, sub, color, opts)
	local big = type(opts) == "table" and opts.Big == true
	table.insert(stampQueue, { title, sub, color, big })
	if stamping then
		return
	end
	stamping = true
	task.spawn(function()
		while #stampQueue > 0 do
			local s = table.remove(stampQueue, 1)
			pcall(showStamp, s[1], s[2], s[3], s[4])
			task.wait(s[4] and 4 or 2.6)
		end
		stamping = false
	end)
end

showStamp = function(title, sub, color, big)
	task.spawn(function()
		require(script.Parent:WaitForChild("SoundClient")).Play("Stamp")
	end)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, big and 0.4 or 0.35)
	frame.Size = UDim2.fromScale(big and 0.8 or 0.6, big and 0.3 or 0.2)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 0.65)
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = color or PINK
	t.Text = title
	t.Parent = frame
	local ts = Instance.new("UIStroke")
	ts.Color = Color3.new(1, 1, 1)
	ts.Thickness = 3
	ts.Parent = t
	if sub then
		local s = Instance.new("TextLabel")
		s.Position = UDim2.fromScale(0, 0.65)
		s.Size = UDim2.fromScale(1, 0.35)
		s.BackgroundTransparency = 1
		s.Font = FONT
		s.TextScaled = true
		s.TextColor3 = Color3.new(1, 1, 1)
		s.Text = sub
		s.Parent = frame
		local ss = Instance.new("UIStroke")
		ss.Color = DARK
		ss.Thickness = 2
		ss.Parent = s
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = frame
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(big and 3.6 or 2.2, function()
		TweenService:Create(scale, TweenInfo.new(0.3), { Scale = 0 }):Play()
		task.wait(0.35)
		frame:Destroy()
	end)
end

function HUDController.Init()
	build()
	refresh()
	-- Follow the driving HUD (DriveUI's ScreenGui is enabled exactly while you drive).
	task.spawn(function()
		local driveGui = player:WaitForChild("PlayerGui"):WaitForChild("DriveUI", 30)
		if not driveGui then
			return
		end
		local function update()
			if driving ~= driveGui.Enabled then
				driving = driveGui.Enabled
				for _, fn in ipairs(layouts) do
					task.spawn(fn)
				end
			end
		end
		driveGui:GetPropertyChangedSignal("Enabled"):Connect(update)
		update()
	end)
	for _, a in ipairs({ "Cash", "Carried", "Heat", "HeatSpotted", "Side", "EscapeEnd", "EscapeTotal" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	-- The escape bar fills a few times a second (never per frame), only while wanted.
	task.spawn(function()
		while true do
			local wanted = (player:GetAttribute("Heat") or 0) > 0
			if wanted then
				local ok, err = pcall(updateEscape)
				if not ok then
					warn("[HUDController] " .. tostring(err))
				end
			end
			task.wait(wanted and 0.2 or 0.5)
		end
	end)
	Remotes.OnClient("Banked", function(amount)
		HUDController.Stamp("CLEAN GETAWAY", "+" .. money(amount) .. " banked", MINT)
	end)
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
end

return HUDController
