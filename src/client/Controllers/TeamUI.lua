-- TeamUI (ModuleScript, StarterPlayerScripts.Controllers.TeamUI)
-- Team picker: two big cards (ROBBER / COP) shown on first join, and a small team badge in the top-left
-- corner that reopens it. The server decides; this only asks (RequestTeam).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamsConfig = require(ReplicatedStorage.Shared.Config.Teams)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local TeamUI = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local ORANGE = Color3.fromRGB(255, 138, 61)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne
local COLOR = { Civilian = PINK, Cop = CYAN, Prisoner = ORANGE }
local LABEL = { Civilian = "CITIZEN", Cop = "COP", Prisoner = "PRISONER" }

local gui, overlay, badge, copCount, robberCount, copFull, closeButton
local requestTeam

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 18)
	c.Parent = obj
end

local function stroke(obj, color, t)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = t or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
end

local function text(parent, str, size, pos, color, anchor)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.AnchorPoint = anchor or Vector2.new(0.5, 0)
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Text = str
	l.Parent = parent
	return l
end

local function card(parent, side, xScale)
	local color = COLOR[side]
	local b = Instance.new("TextButton")
	b.Name = side
	b.AutoButtonColor = true
	b.Text = ""
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(xScale, 0.55)
	b.Size = UDim2.fromScale(0.3, 0.55)
	b.BackgroundColor3 = DARK
	b.BackgroundTransparency = 0.1
	b.Parent = parent
	corner(b)
	stroke(b, color, 5)
	text(b, TeamsConfig.BySide[side].Label, UDim2.fromScale(0.9, 0.22), UDim2.fromScale(0.5, 0.1), color)
	text(b, TeamsConfig.BySide[side].Pitch, UDim2.fromScale(0.85, 0.2), UDim2.fromScale(0.5, 0.4))
	local count = text(b, "", UDim2.fromScale(0.8, 0.12), UDim2.fromScale(0.5, 0.72), Color3.fromRGB(200, 200, 220))
	b.Activated:Connect(function()
		requestTeam:FireServer(side)
		overlay.Visible = false
	end)
	return b, count
end

local function refresh()
	local robbers, cops = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		local s = p:GetAttribute("Side")
		if s == "Cop" then
			cops += 1
		elseif s == "Civilian" or s == "Prisoner" then
			robbers += 1
		end
	end
	local maxCops = TeamsConfig.MaxCops(#Players:GetPlayers())
	robberCount.Text = robbers .. " in the city"
	local full = cops >= maxCops and player:GetAttribute("Side") ~= "Cop"
	copCount.Text = full and "FULL - try again soon" or string.format("%d / %d cops", cops, maxCops)
	copFull.Visible = full
	closeButton.Visible = player:GetAttribute("HasPicked") == true
	local side = player:GetAttribute("Side") or "Civilian"
	badge.Text = LABEL[side]
	badge.TextColor3 = COLOR[side]
	badge.UIStroke.Color = COLOR[side]
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "TeamUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	overlay = Instance.new("Frame")
	overlay.Name = "Picker"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 6, 20)
	overlay.BackgroundTransparency = 0.25
	overlay.Parent = gui
	text(overlay, "NEON COAST", UDim2.fromScale(0.6, 0.11), UDim2.fromScale(0.5, 0.07), PINK)
	text(overlay, "How do you want to play?", UDim2.fromScale(0.4, 0.06), UDim2.fromScale(0.5, 0.18))
	local robberCard
	robberCard, robberCount = card(overlay, "Civilian", 0.32)
	local copCard
	copCard, copCount = card(overlay, "Cop", 0.68)
	copFull = Instance.new("Frame")
	copFull.Name = "FullShade"
	copFull.Size = UDim2.fromScale(1, 1)
	copFull.BackgroundColor3 = Color3.new(0, 0, 0)
	copFull.BackgroundTransparency = 0.45
	copFull.Visible = false
	copFull.Parent = copCard
	corner(copFull)
	-- New players: the free-roam card pulses a little so it is the obvious first choice.
	local scale = Instance.new("UIScale")
	scale.Parent = robberCard
	task.spawn(function()
		local t = 0
		while robberCard.Parent do
			t += task.wait()
			scale.Scale = overlay.Visible and (1 + 0.03 * math.sin(t * 4)) or 1
		end
	end)
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -24)
	close.Size = UDim2.fromScale(0.16, 0.07)
	close.BackgroundColor3 = DARK
	close.Font = FONT
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "KEEP MY SIDE"
	close.Parent = overlay
	corner(close, UDim.new(0.5, 0))
	stroke(close, Color3.new(1, 1, 1), 2)
	closeButton = close
	close.Activated:Connect(function()
		requestTeam:FireServer(player:GetAttribute("Side") or "Civilian")
		overlay.Visible = false
	end)

	badge = Instance.new("TextButton")
	badge.Name = "TeamBadge"
	badge.Position = UDim2.new(0, 16, 0, 64)
	badge.Size = UDim2.fromOffset(130, 36)
	badge.BackgroundColor3 = DARK
	badge.BackgroundTransparency = 0.2
	badge.Font = FONT
	badge.TextScaled = true
	badge.Parent = gui
	corner(badge, UDim.new(0.5, 0))
	stroke(badge, PINK, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
	pad.Parent = badge
	badge.Activated:Connect(function()
		if player:GetAttribute("Side") == "Prisoner" then
			return
		end
		refresh()
		overlay.Visible = true
	end)
end

-- Open the role picker (the phone's JOBS app uses this).
function TeamUI.Open()
	if player:GetAttribute("Side") == "Prisoner" then
		return
	end
	refresh()
	overlay.Visible = true
end

function TeamUI.Init()
	requestTeam = Remotes.Event("RequestTeam")
	build()
	overlay.Visible = player:GetAttribute("HasPicked") ~= true
	refresh()
	player:GetAttributeChangedSignal("Side"):Connect(refresh)
	player:GetAttributeChangedSignal("HasPicked"):Connect(function()
		if player:GetAttribute("HasPicked") then
			overlay.Visible = false
		end
		refresh()
	end)
	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
	local function watch(p)
		p:GetAttributeChangedSignal("Side"):Connect(refresh)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
end

return TeamUI
