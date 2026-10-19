-- DriveUI (ModuleScript, StarterPlayerScripts.Controllers.DriveUI)
-- The driving HUD, shown only while driving:
--   * Every device: speed gauge (MPH) with a nitro bar.
--   * Touch devices: big GAS and BRAKE pedals, NITRO and DRIFT buttons, EXIT, and FLIP when the car
--     is upside down. Steering stays on Roblox's thumbstick (it feeds the seat's SteerFloat).
-- Pedals override the throttle so the thumbstick only steers. Icons first, very few words.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DriveController = require(script.Parent:WaitForChild("DriveController"))
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local DriveUI = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local ORANGE = Color3.fromRGB(255, 138, 61)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne
local STUDS_TO_MPH = 0.626 -- 1 stud ~ 0.28 m

local gui
local touchFrame
local smokeButton
local gauge
local speedLabel, nitroFill
local flipButton
local held = { Gas = false, Brake = false }
local forceTouch = false -- Studio preview of the phone layout

local function isTouch()
	return forceTouch or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
end

local function corner(obj, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.5, 0)
	c.Parent = obj
end

local function stroke(obj, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function button(parent, name, text, color, size, pos, anchor)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundColor3 = DARK
	b.BackgroundTransparency = 0.25
	b.Size = size
	b.Position = pos
	b.AnchorPoint = anchor or Vector2.new(1, 1)
	b.Font = FONT
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = color
	b.Parent = parent
	corner(b)
	stroke(b, color, 4)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.22, 0), UDim.new(0.22, 0)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.12, 0), UDim.new(0.12, 0)
	pad.Parent = b
	return b
end

-- Hold-style button: calls onChange(true) while any finger or click holds it.
-- Each touch is tracked by its own InputObject until that finger lifts or is cancelled, even if it
-- slid off the button first (GuiObject.InputEnded alone can miss that and leave GAS stuck on).
local function holdable(b, color, onChange)
	local active = {} -- [InputObject] = connection
	local isDown = false
	local function set(down)
		if down == isDown then
			return
		end
		isDown = down
		b.BackgroundColor3 = down and color or DARK
		b.TextColor3 = down and DARK or color
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

local resets = {}

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DriveUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Speed gauge (all devices), bottom centre
	gauge = Instance.new("Frame")
	gauge.Name = "Gauge"
	gauge.AnchorPoint = Vector2.new(0.5, 1)
	gauge.Position = UDim2.new(0.5, 0, 1, -18)
	gauge.Size = UDim2.fromScale(0.26, 0.13)
	gauge.SizeConstraint = Enum.SizeConstraint.RelativeYY
	gauge.BackgroundTransparency = 1
	gauge.Parent = gui
	speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "Speed"
	speedLabel.BackgroundTransparency = 1
	speedLabel.Size = UDim2.fromScale(1, 0.7)
	speedLabel.Font = FONT
	speedLabel.TextScaled = true
	speedLabel.TextColor3 = Color3.new(1, 1, 1)
	speedLabel.Text = "0 MPH"
	speedLabel.Parent = gauge
	local ls = Instance.new("UIStroke")
	ls.Color = PINK
	ls.Thickness = 2
	ls.Parent = speedLabel
	local bar = Instance.new("Frame")
	bar.Name = "NitroBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.fromScale(0.5, 1)
	bar.Size = UDim2.fromScale(0.9, 0.16)
	bar.BackgroundColor3 = DARK
	bar.BackgroundTransparency = 0.3
	bar.Parent = gauge
	corner(bar)
	stroke(bar, CYAN, 2)
	nitroFill = Instance.new("Frame")
	nitroFill.Name = "Fill"
	nitroFill.Size = UDim2.fromScale(1, 1)
	nitroFill.BackgroundColor3 = CYAN
	nitroFill.Parent = bar
	corner(nitroFill)

	-- Touch controls, bottom right cluster (sizes follow screen height)
	touchFrame = Instance.new("Frame")
	touchFrame.Name = "Touch"
	touchFrame.AnchorPoint = Vector2.new(1, 1)
	touchFrame.Position = UDim2.new(1, -20, 1, -20)
	touchFrame.Size = UDim2.fromScale(0.52, 0.52)
	touchFrame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	touchFrame.BackgroundTransparency = 1
	touchFrame.Parent = gui

	local gas = button(touchFrame, "Gas", "GAS", PINK, UDim2.fromScale(0.42, 0.42), UDim2.fromScale(1, 1))
	local brake = button(touchFrame, "Brake", "BRAKE", CYAN, UDim2.fromScale(0.33, 0.33), UDim2.fromScale(0.55, 1))
	local nitro = button(touchFrame, "Nitro", "NITRO", ORANGE, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(1, 0.55))
	local drift = button(touchFrame, "Drift", "DRIFT", CYAN, UDim2.fromScale(0.26, 0.26), UDim2.fromScale(0.66, 0.6))
	table.insert(resets, holdable(gas, PINK, function(d)
		held.Gas = d
	end))
	table.insert(resets, holdable(brake, CYAN, function(d)
		held.Brake = d
	end))
	table.insert(resets, holdable(nitro, ORANGE, function(d)
		DriveController.Input.Nitro = d
	end))
	table.insert(resets, holdable(drift, CYAN, function(d)
		DriveController.Input.Handbrake = d
	end))

	-- HORN (civilians) / SIREN (cops): the server decides which.
	local horn = button(touchFrame, "Horn", "HORN", Color3.fromRGB(255, 214, 10), UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.66, 0.3))
	horn.Activated:Connect(function()
		Remotes.Event("RequestHorn"):FireServer()
	end)
	local function hornLabel()
		horn.Text = player:GetAttribute("Side") == "Cop" and "SIREN" or "HORN"
	end
	hornLabel()
	player:GetAttributeChangedSignal("Side"):Connect(hornLabel)

	-- SMOKE: only while wanted (the server checks too).
	smokeButton = button(touchFrame, "Smoke", "SMOKE", PINK, UDim2.fromScale(0.24, 0.24), UDim2.fromScale(0.3, 0.62))
	smokeButton.Activated:Connect(function()
		Remotes.Event("RequestSmoke"):FireServer()
	end)

	-- Exit and Flip, top right, just left of the minimap (MinimapClient, 170 px at the right edge)
	local exit = button(gui, "Exit", "EXIT", Color3.new(1, 1, 1), UDim2.fromScale(0.1, 0.1), UDim2.new(1, -200, 0, 60), Vector2.new(1, 0))
	exit.SizeConstraint = Enum.SizeConstraint.RelativeYY
	exit.Activated:Connect(function()
		DriveController.Exit()
	end)
	flipButton = button(gui, "Flip", "FLIP", ORANGE, UDim2.fromScale(0.1, 0.1), UDim2.new(1, -200, 0, 60), Vector2.new(1, 0))
	flipButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
	flipButton.Position = UDim2.new(1, -200, 0.12, 64)
	flipButton.Visible = false
	flipButton.Activated:Connect(function()
		DriveController.Flip()
	end)
end

local wasDriving = false

local function update()
	local status = DriveController.Status
	local driving = status.Driving
	if driving ~= wasDriving then
		wasDriving = driving
		gui.Enabled = driving
		if not driving then
			held.Gas, held.Brake = false, false
			for _, r in ipairs(resets) do
				r()
			end
			DriveController.Input.Throttle = nil
		end
	end
	if not driving then
		return
	end
	local touch = isTouch()
	touchFrame.Visible = touch
	if touch then
		DriveController.Input.Throttle = (held.Gas and 1 or 0) - (held.Brake and 1 or 0)
	else
		DriveController.Input.Throttle = nil
	end
	speedLabel.Text = string.format("%d MPH", math.floor(math.abs(status.Speed) * STUDS_TO_MPH + 0.5))
	nitroFill.Size = UDim2.fromScale(math.clamp(status.NitroFuel, 0, 1), 1)
	nitroFill.BackgroundColor3 = status.NitroActive and ORANGE or CYAN
	local wanted = player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) > 0
	smokeButton.Visible = wanted
	smokeButton.TextTransparency = (player:GetAttribute("SmokeCharges") or 0) > 0 and 0 or 0.6
	local car = status.Car
	local chassis = car and car.PrimaryPart
	flipButton.Visible = chassis ~= nil and chassis.CFrame.UpVector.Y < 0.5 and chassis.AssemblyLinearVelocity.Magnitude < 15
end

-- Studio only: preview the phone layout on a PC (DriveUI.PreviewTouch(true)).
function DriveUI.PreviewTouch(on)
	forceTouch = on
end

function DriveUI.Init()
	build()
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
			forceTouch = player:GetAttribute("PreviewTouch") == true
		end)
	end
end

return DriveUI
