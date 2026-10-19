-- WardrobeUI (ModuleScript, StarterPlayerScripts.Controllers.WardrobeUI)
-- Inside a hideout (player attribute InHideout, set by the server) and on foot, a WARDROBE button
-- appears (DisguiseService refuses seated players, so it hides while you're in a car).
-- It opens a picker of hats and masks; choosing asks the server (RequestDisguise), which checks
-- you're really in a hideout and handles the heat drop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Disguises = require(ReplicatedStorage.Shared.Config.Disguises)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local WardrobeUI = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local gui, openButton, panel
local pickedHat, pickedMask = "none", "none"
local rows = {}

local function style(obj, color, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 14)
	c.Parent = obj
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
end

local function refreshSelection()
	for _, r in ipairs(rows) do
		local selected = (r.kind == "hat" and r.id == pickedHat) or (r.kind == "mask" and r.id == pickedMask)
		r.button.BackgroundColor3 = selected and r.color or DARK
		r.button.TextColor3 = selected and DARK or Color3.new(1, 1, 1)
	end
end

local function row(parent, title, list, kind, y)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, y)
	label.Size = UDim2.fromScale(0.92, 0.1)
	label.Font = FONT
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = kind == "hat" and PINK or CYAN
	label.Text = title
	label.Parent = parent
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0.04, y + 0.11)
	holder.Size = UDim2.fromScale(0.92, 0.2)
	holder.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(0.23, 0.9)
	layout.CellPadding = UDim2.fromScale(0.02, 0)
	layout.Parent = holder
	for _, item in ipairs(list) do
		local b = Instance.new("TextButton")
		b.Font = FONT
		b.TextScaled = true
		b.Text = item.Name
		b.BackgroundColor3 = DARK
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = holder
		local color = item.Color or Color3.fromRGB(200, 200, 210)
		style(b, color, UDim.new(0, 10))
		b.Activated:Connect(function()
			if kind == "hat" then
				pickedHat = item.Id
			else
				pickedMask = item.Id
			end
			refreshSelection()
			Remotes.Event("RequestDisguise"):FireServer(pickedHat, pickedMask)
		end)
		table.insert(rows, { kind = kind, id = item.Id, button = b, color = color })
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "WardrobeUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	openButton = Instance.new("TextButton")
	openButton.Name = "Open"
	openButton.Position = UDim2.new(0, 16, 0, 236)
	openButton.Size = UDim2.fromOffset(150, 40)
	openButton.BackgroundColor3 = DARK
	openButton.Font = FONT
	openButton.TextScaled = true
	openButton.TextColor3 = PINK
	openButton.Text = "WARDROBE"
	openButton.Visible = false
	openButton.Parent = gui
	style(openButton, PINK, UDim.new(0.5, 0))

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.62, 0.6)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	style(panel, PINK, UDim.new(0, 18))
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.04, 0.03)
	title.Size = UDim2.fromScale(0.7, 0.11)
	title.Font = FONT
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "New look = cops lose track of you"
	title.Parent = panel
	row(panel, "HATS", Disguises.Hats, "hat", 0.17)
	row(panel, "MASKS", Disguises.Masks, "mask", 0.52)
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(0.97, 0.03)
	close.Size = UDim2.fromScale(0.16, 0.1)
	close.BackgroundColor3 = DARK
	close.Font = FONT
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "DONE"
	close.Parent = panel
	style(close, Color3.new(1, 1, 1), UDim.new(0.5, 0))
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	openButton.Activated:Connect(function()
		pickedHat = player:GetAttribute("LookHat") or "none"
		pickedMask = player:GetAttribute("LookMask") or "none"
		refreshSelection()
		panel.Visible = true
	end)
end

local function refresh()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seated = hum ~= nil and hum.SeatPart ~= nil
	local usable = player:GetAttribute("InHideout") == true and not seated
	openButton.Visible = usable
	if not usable then
		panel.Visible = false
	end
end

function WardrobeUI.Init()
	build()
	refresh()
	player:GetAttributeChangedSignal("InHideout"):Connect(refresh)
	-- Getting in or out of a car shows or hides it.
	local function watch(character)
		local hum = character:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum:GetPropertyChangedSignal("SeatPart"):Connect(refresh)
		end
		refresh()
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return WardrobeUI
