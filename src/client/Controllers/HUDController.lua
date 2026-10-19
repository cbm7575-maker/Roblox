-- HUDController (ModuleScript, StarterPlayerScripts.Controllers.HUDController)
-- Always-on HUD: cash and bag (top left, under the team badge), heat stars (top right), and big
-- full-screen stamps for moments ("CLEAN GETAWAY +$1,200", "CAUGHT!", "BOUNTY +$900").
-- Everything reads player attributes the server sets: Cash, Carried, Heat, HeatSpotted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local HUDController = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local GOLD = Color3.fromRGB(255, 214, 10)
local MINT = Color3.fromRGB(110, 242, 196)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local gui, cashLabel, bagLabel, starsFrame
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
	layout.Padding = UDim.new(0, 4)
	layout.Parent = starsFrame
	for i = 1, 5 do
		local s = Instance.new("TextLabel")
		s.Name = "Star" .. i
		s.LayoutOrder = i
		s.Size = UDim2.fromOffset(36, 36)
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
end

-- Big centre-screen stamp. Stamps queue up so two moments never draw on top of each other.
local stampQueue = {}
local stamping = false
local showStamp

function HUDController.Stamp(title, sub, color)
	table.insert(stampQueue, { title, sub, color })
	if stamping then
		return
	end
	stamping = true
	task.spawn(function()
		while #stampQueue > 0 do
			local s = table.remove(stampQueue, 1)
			showStamp(s[1], s[2], s[3])
			task.wait(2.6)
		end
		stamping = false
	end)
end

showStamp = function(title, sub, color)
	task.spawn(function()
		require(script.Parent:WaitForChild("SoundClient")).Play("Stamp")
	end)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.35)
	frame.Size = UDim2.fromScale(0.6, 0.2)
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
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = frame
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.2, function()
		TweenService:Create(scale, TweenInfo.new(0.3), { Scale = 0 }):Play()
		task.wait(0.35)
		frame:Destroy()
	end)
end

function HUDController.Init()
	build()
	refresh()
	for _, a in ipairs({ "Cash", "Carried", "Heat", "HeatSpotted", "Side" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
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
