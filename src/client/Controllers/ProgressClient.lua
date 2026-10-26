-- ProgressClient (ModuleScript, StarterPlayerScripts.Controllers.ProgressClient)
-- The RANK readout, RANK UP stamps with the unlock, and challenge-complete toasts ("street" look,
-- Shared.Util.Theme). The phone's GOALS app shows the details.
--   * RANK readout (ScreenGui "Rank", frame "RankChip"): the Status zone's bottom row (top right), just
--     left of TeamUI's role line ("RANK 4  CITIZEN"): the rank for the side you're playing in condensed
--     white numbers, a thin XP bar under them (brand pink for free roam, police blue for police). Only
--     for free roam and police. Re-placed when the screen size, the input type or the role line's width
--     changes (it measures TeamUI.Badge's text, which is right-aligned in the same row).
--   * RANK UP: a cinematic stamp through HUDController.Stamp: small gold "RANK UP" over "RANK 5", a gold
--     rule, then the unlock ("Unlocked: Gold rims") or the side ("Free roam rank").
--   * XP gained: a gold "+15 XP" floats in left of the rank, holds and fades (gains while it's up add
--     up), for the side you're playing; the save loading in and the title screen don't count.
--   * Challenge done: a gold toast with the cash and XP.
-- While the first-join title screen is up TeamUI keeps the "Rank" ScreenGui switched off.
--   ProgressClient.Progress(side) -> rank, share of the way to the next rank (0-1), xp, next rank's xp

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local TeamUI = require(script.Parent:WaitForChild("TeamUI"))

local player = Players.LocalPlayer

local ProgressClient = {}

local ROW_H = 22 -- the Status zone's bottom row (TeamUI's role line is as tall)
local WIDTH = 90 -- room for "RANK 20"
local GAP = 12 -- pixels between the rank and the role line's words
local ROLE_FALLBACK = 70 -- the role line's width while it can't be measured
local XP_HOLD = 1.6 -- seconds a "+15 XP" stays before it fades (gains meanwhile add to it)

local gui, chip, chipText, bar, fill
local gain -- the "+15 XP" label
local lastXP = {} -- [attribute] = the value last seen
local gainSum, gainUntil = 0, 0

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

-- Bottom row of the Status zone, right edge just left of the role line's words. Measured from the zone's
-- anchor (the same scale part as the zone, as TeamUI places the role line), so the two stay in one row in
-- whatever box the ScreenGuis get (safe-area insets included).
local function place()
	if not chip then
		return
	end
	local touch = Theme.IsTouch()
	local z = Theme.Zone("Status", touch)
	local w, h = z.Size.X.Offset, z.Size.Y.Offset -- (the Status zone is sized in pixels in both layouts)
	local badge = TeamUI.Badge
	local roleW = ROLE_FALLBACK
	if badge and badge.Text ~= "" and badge.TextBounds.X > 0 then
		roleW = badge.TextBounds.X
	end
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(z.Pos.X.Scale, math.floor(z.Pos.X.Offset + (1 - z.Anchor.X) * w - roleW - GAP),
		z.Pos.Y.Scale, math.floor(z.Pos.Y.Offset - z.Anchor.Y * h + h - ROW_H))
	chip.Size = UDim2.fromOffset(WIDTH, ROW_H)
	chipText.TextSize = touch and 15 or 16
end

-- The XP bar underlines the words exactly.
local function fitBar()
	bar.Size = UDim2.fromOffset(math.max(math.floor(chipText.TextBounds.X), 24), 3)
end

local function refresh()
	local side = player:GetAttribute("Side")
	chip.Visible = side == "Civilian" or side == "Cop"
	if not chip.Visible then
		return
	end
	local rank, frac = ProgressClient.Progress(side)
	chipText.Text = "RANK " .. rank
	fill.BackgroundColor3 = side == "Cop" and Theme.Color.Police or Theme.Color.Brand
	TweenService:Create(fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(frac, 0.02, 1), 1) }):Play()
end

-- "+15 XP" left of the rank words: rises 8 px into place as it fades in, holds, then fades drifting up.
local function showGain(diff)
	local now = os.clock()
	local fresh = now >= gainUntil
	gainSum = fresh and diff or gainSum + diff
	gainUntil = now + XP_HOLD
	local untilNow = gainUntil
	local x = -(math.floor(chipText.TextBounds.X) + 8)
	gain.Text = "+" .. gainSum .. " XP"
	gain.TextSize = chipText.TextSize
	if fresh then
		gain.Position = UDim2.new(1, x, 1, 3)
		gain.TextTransparency = 1
		gain.Shadow.Transparency = 1
	end
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gain, info, { Position = UDim2.new(1, x, 1, -5), TextTransparency = 0 }):Play()
	TweenService:Create(gain.Shadow, info, { Transparency = 0.45 }):Play()
	task.delay(XP_HOLD, function()
		if gainUntil ~= untilNow then
			return -- a newer gain restarted the hold
		end
		local out = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(gain, out, { Position = UDim2.new(1, x, 1, -11), TextTransparency = 1 }):Play()
		TweenService:Create(gain.Shadow, out, { Transparency = 1 }):Play()
	end)
end

-- DataService sets the saved XP before DataLoaded, so the save loading in only moves lastXP.
local function onXP(attr)
	local xp = player:GetAttribute(attr)
	local before = lastXP[attr]
	lastXP[attr] = xp
	if typeof(xp) ~= "number" or typeof(before) ~= "number" or xp <= before or not chip.Visible then
		return
	end
	if player:GetAttribute("DataLoaded") ~= true or player:GetAttribute("TitleScreen") == true then
		return
	end
	if (attr == "CopXP") ~= (player:GetAttribute("Side") == "Cop") then
		return -- (only the side you're playing has a rank on screen)
	end
	showGain(math.floor(xp - before))
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Rank"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- zone coordinates: y = 0 is the very top of the screen
	gui.Parent = player:WaitForChild("PlayerGui")
	chip = Instance.new("Frame")
	chip.Name = "RankChip"
	chip.BackgroundTransparency = 1
	chip.Parent = gui
	-- Straight on the screen with a soft shadow, right-aligned so it hugs the role line.
	chipText = Instance.new("TextLabel")
	chipText.Name = "Text"
	chipText.Size = UDim2.new(1, 0, 0, ROW_H - 5)
	chipText.TextXAlignment = Enum.TextXAlignment.Right
	chipText.TextYAlignment = Enum.TextYAlignment.Bottom
	Theme.Text(chipText, 16, "Display")
	chipText.Parent = chip
	gain = Instance.new("TextLabel")
	gain.Name = "XPGain"
	gain.AnchorPoint = Vector2.new(1, 1)
	gain.AutomaticSize = Enum.AutomaticSize.X
	gain.Size = UDim2.fromOffset(0, ROW_H - 5)
	gain.TextXAlignment = Enum.TextXAlignment.Right
	gain.TextYAlignment = Enum.TextYAlignment.Bottom
	Theme.Text(gain, 16, "Display")
	gain.TextColor3 = Theme.Color.Gold
	gain.TextTransparency = 1
	gain.Shadow.Transparency = 1
	gain.Parent = chip
	bar, fill = Theme.Bar(chip, Theme.Color.Brand)
	bar.Name = "XP"
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(1, 0, 1, -1)
	bar.BackgroundColor3 = Theme.Color.Text
	bar.BackgroundTransparency = 0.78 -- a faint line: the rest of the way to the next rank
	fill.Size = UDim2.fromScale(0.02, 1)
end

function ProgressClient.Init()
	build()
	refresh()
	fitBar()
	place()
	for _, a in ipairs({ "Side", "CivXP", "CopXP" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	for _, a in ipairs({ "CivXP", "CopXP" }) do
		lastXP[a] = player:GetAttribute(a)
		player:GetAttributeChangedSignal(a):Connect(function()
			onXP(a)
		end)
	end
	chipText:GetPropertyChangedSignal("TextBounds"):Connect(fitBar)
	-- Re-place when the screen size or the kind of device changes, and when the role line's words do.
	local camConn
	local function watchCamera()
		if camConn then
			camConn:Disconnect()
		end
		local cam = Workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(place)
		end
		place()
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(place)
	if TeamUI.Badge then
		TeamUI.Badge:GetPropertyChangedSignal("TextBounds"):Connect(place)
	end
	task.spawn(function()
		Remotes.OnClient("RankUp", function(info)
			if type(info) ~= "table" then
				return
			end
			local line = info.Unlock and ("Unlocked: " .. tostring(info.Unlock))
				or (info.Side == "Cop" and "Police rank" or "Free roam rank")
			HUDController.Stamp("RANK " .. tostring(info.Rank), line, Theme.Color.Gold, "RANK UP")
		end)
	end)
	task.spawn(function()
		Remotes.OnClient("ChallengeDone", function(info)
			NotifyController.Show("CHALLENGE DONE: " .. info.Text .. "  +" .. HUDController.Money(info.Cash)
				.. "  +" .. info.XP .. " XP", Theme.Color.Gold)
		end)
	end)
end

return ProgressClient
