-- NotifyController (ModuleScript, StarterPlayerScripts.Controllers.NotifyController)
-- Short toast messages at the top of the screen. The server sends a key (never raw text);
-- the words live here so they're easy to change and translate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local NotifyController = {}

NotifyController.Messages = {
	CarSank = "Your car sank! Tap CAR to get it back.",
	CarRemoved = "Your car was removed.",
	NoCarWhileWanted = "The cops can see you! Break line of sight before calling a car.",
	CarCooldown = "Your car is on its way... try again in a few seconds.",
	CarNoRoom = "No room for your car here. Try an open road.",
	CopsFull = "The police force is full right now. Try again in a moment!",
	TeamHasHeat = "Lose your heat before switching sides.",
	TeamInPrison = "You can't switch sides from prison.",
	TeamCooldown = "Wait a few seconds before switching again.",
	ShakeCopsFirst = "The cops can see you! Lose them before you bank.",
	LostTheCops = "You lost the cops! Heat cleared.",
	TiresPopped = "Tires popped! You're slow for a few seconds.",
	NoSpikes = "No spike strips left. They recharge every 30 seconds.",
	Released = "You served your time. Welcome back to Port Solana.",
	VentJammed = "The vent is jammed. Try again in a few seconds.",
	Disguised = "New look! The cops lost your description. (-1 star)",
	Resprayed = "Fresh paint! -$500, and the cops lost your car. (-1 star)",
	SprayNoCash = "Spray & Go costs $500. Bank some cash first.",
	CarBoosted = "Car boosted! Deliver it to the Chop Shop at the Docks.",
	NoSmoke = "Smoke is recharging (30 seconds).",
	RaceNeedCar = "Races start in your own car. Drive onto the pad!",
	RaceNeedBoat = "This race is on the water: bring a boat (PHONE > GARAGE > LAUNCH).",
	TrackerPing = "This car had a GPS tracker! The cops know where you are.",
	CarNotOwned = "You don't own that car yet. Check AUTONEON on your phone!",
	NotEnoughCash = "Not enough cash for that.",
	CarNeedsPass = "That car comes with a game pass.",
	CarNeedsRank = "Reach police rank 5 to unlock that car.",
	NeedsPass_VIP = "That paint comes with the VIP pass (PHONE > SHOP).",
	NeedsPass_NeonGarage = "That glow color comes with the Neon Garage pass (PHONE > SHOP).",
	NeedsUnlock_Streak7 = "Log in 7 days in a row to unlock Streak Sunset paint!",
	NeedsUnlock_CivRank10 = "Reach free-roam rank 10 to unlock Neon Legend paint.",
	NeedsUnlock_CopRank10 = "Reach police rank 10 to unlock the Midnight Blue livery.",
	NeedsUnlock_Rank20 = "Reach rank 20 to unlock gold rims.",
	BankNeedsRank = "The Coastal Bank is for rank 3 and up. Rob stores to rank up!",
	NeedPrep_CoastalBank = "The vault's locked tight. Cut the power first: the fuse box is on the bank's east wall.",
	NeedPrep_SeaDream = "The yacht's alarm is armed. Disable the security panel on the boarding deck first.",
	CrewJoined = "Crew updated! Rob together for +20% cash.",
	TreasureFound = "You dug up some treasure! Cash added.",
	CarMeetLike = "Someone liked your ride! +$150",
	CarMeetFan = "A fan loved your ride! +$150",
	MissionBusy = "Finish what you're doing first (and lose any heat).",
	MissionCooldown = "Take a breather: new missions in a few seconds.",
	UFOWave = "They waved back. +$500 (don't tell anyone)",
	CrewLeft = "Someone left your crew.",
	CrewFull = "That crew is full (4 max).",
	CrewInviteSent = "Invite sent!",
	CrewInvitePending = "They already have an invite waiting.",
	CrewDeclined = "Your crew invite was declined.",
}

local gui, holder

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Toasts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	-- Below the top row (GPS / race timer / job banner at ~58) and the tutorial pill (~98).
	holder.Position = UDim2.new(0.5, 0, 0, 146)
	holder.Size = UDim2.fromScale(0.5, 0.3)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 6)
	list.Parent = holder
end

function NotifyController.Show(text, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 44)
	label.TextWrapped = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 13
	limit.MaxTextSize = 24
	limit.Parent = label
	-- At most 3 toasts on screen: drop the oldest.
	local shown = {}
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(shown, c)
		end
	end
	if #shown >= 3 then
		shown[1]:Destroy()
	end
	label.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = label
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(255, 62, 165)
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = label
	label.Parent = holder
	task.delay(4, function()
		local t = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		t:Play()
		t.Completed:Wait()
		label:Destroy()
	end)
end

function NotifyController.Init()
	build()
	Remotes.OnClient("Notify", function(key)
		local text = NotifyController.Messages[key]
		if text then
			NotifyController.Show(text)
		end
	end)
end

return NotifyController
