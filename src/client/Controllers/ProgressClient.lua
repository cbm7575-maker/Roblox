-- ProgressClient (ModuleScript, StarterPlayerScripts.Controllers.ProgressClient)
-- Rank chip beside the role badge (rank for the side you're playing + XP bar), RANK UP stamps with
-- the unlock, and challenge-complete celebrations. The phone's GOALS app shows the details.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local ProgressClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local GOLD = Color3.fromRGB(255, 214, 10)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local chip, chipText, fill

-- XP progress within the current rank, 0..1, for a side ("Civilian"/"Cop").
function ProgressClient.Progress(side)
	local xp = player:GetAttribute(side == "Cop" and "CopXP" or "CivXP") or 0
	local rank = Progression.RankFor(xp)
	if rank >= Progression.MaxRank then
		return rank, 1, xp, xp
	end
	local a, b = Progression.XPFor(rank), Progression.XPFor(rank + 1)
	return rank, (xp - a) / (b - a), xp, b
end

local function refresh()
	local side = player:GetAttribute("Side")
	chip.Visible = side == "Civilian" or side == "Cop"
	if not chip.Visible then
		return
	end
	local rank, frac = ProgressClient.Progress(side)
	local color = side == "Cop" and CYAN or PINK
	chipText.Text = "RANK " .. rank
	chipText.TextColor3 = color
	chip.UIStroke.Color = color
	fill.BackgroundColor3 = color
	TweenService:Create(fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(frac, 0.02, 1), 1) }):Play()
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Rank"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	chip = Instance.new("Frame")
	chip.Name = "RankChip"
	chip.Position = UDim2.new(0, 154, 0, 64)
	chip.Size = UDim2.fromOffset(92, 36)
	chip.BackgroundColor3 = DARK
	chip.BackgroundTransparency = 0.2
	chip.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = chip
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = PINK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = chip
	chipText = Instance.new("TextLabel")
	chipText.BackgroundTransparency = 1
	chipText.Position = UDim2.new(0, 8, 0, 4)
	chipText.Size = UDim2.new(1, -16, 0, 20)
	chipText.Font = FONT
	chipText.TextScaled = true
	chipText.Parent = chip
	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 10, 1, -10)
	bar.Size = UDim2.new(1, -20, 0, 5)
	bar.BackgroundColor3 = Color3.fromRGB(60, 50, 90)
	bar.Parent = chip
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = bar
	fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.02, 1)
	fill.Parent = bar
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = fill
end

function ProgressClient.Init()
	build()
	refresh()
	for _, a in ipairs({ "Side", "CivXP", "CopXP" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	task.spawn(function()
		Remotes.OnClient("RankUp", function(info)
			HUDController.Stamp("RANK UP! " .. info.Rank, info.Unlock and ("Unlocked: " .. info.Unlock)
				or (info.Side == "Cop" and "Police rank" or "Free roam rank"), GOLD)
		end)
	end)
	task.spawn(function()
		Remotes.OnClient("ChallengeDone", function(info)
			NotifyController.Show("CHALLENGE DONE: " .. info.Text .. "  +" .. HUDController.Money(info.Cash)
				.. "  +" .. info.XP .. " XP", GOLD)
		end)
	end)
end

return ProgressClient
