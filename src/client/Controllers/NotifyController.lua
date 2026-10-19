-- NotifyController (ModuleScript, StarterPlayerScripts.Controllers.NotifyController)
-- Short toast messages under the top bar slot. The server sends a key (never raw text);
-- the words live here so they're easy to change and translate. NotifyController.Show(text, color)
-- for local messages: sized to fit the text, at most 2 on a phone (3 on bigger screens), no duplicates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
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
	NeedsUnlock_GusHunter = "Find all 40 Gus figurines to unlock Gator Green paint!",
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
	NeedsUnlock_CivRank10 = "Reach citizen rank 10 to unlock Neon Legend paint.",
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
	-- Tutorial (TutorialService)
	TutorialBagLost = "Your bag was emptied! Rob another OPEN store, then lose the cops.",
	-- Activities and garage
	RaceCooldown = "Catch your breath: this race reopens in a few seconds.",
	NoGlowOnBoats = "Boats can't take underglow (the hull hides it).",
	MissionWrongSide = "That mission is for the other side. Switch roles in JOBS.",
	-- Safehouses (PropertyService)
	PropBought = "Welcome home! You'll respawn here, and you can stash your bag on the pad.",
	PropHomeSet = "Home set! You'll respawn here.",
	PropRentCollected = "Rent collected!",
	PropNoRent = "No rent yet. It builds up every hour (up to 12 hours).",
	PropNotOwned = "You don't own this place yet.",
	PropAlreadyOwned = "You already own this place.",
	PropCiviliansOnly = "Only citizens can buy property.",
	PropNeedsRank_5 = "Reach citizen rank 5 to buy this place.",
	PropNeedsRank_10 = "Reach citizen rank 10 to buy this place.",
	PropHotNoBank = "Lose your heat before you stash cash at home.",
	-- Car damage (VehicleDamageService)
	CarSmoking = "Car damaged: it's slower now!",
	CarStalled = "Engine stalled! Limp mode until Spray & Go or a new car.",
}

local gui, holder
local width = 320
local order = 0

local TOP = 164 -- just below the top bar slot (tutorial / mission / objective, y 104..156)

local function layout()
	-- Between the left column (CAR / PHONE end at x 192) and the right-hand touch buttons.
	width = math.clamp(gui.AbsoluteSize.X - 420, 240, 520)
	holder.Size = UDim2.fromOffset(width, 260)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Toasts"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- same coordinates as every other HUD layer
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, TOP)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = holder
	layout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
end

function NotifyController.Show(text, color)
	if not holder then
		return
	end
	text = tostring(text)
	local shown = {}
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("TextLabel") and c:GetAttribute("Fading") ~= true then
			if c.Text == text then
				return -- already on screen: don't stack a copy
			end
			table.insert(shown, c)
		end
	end
	-- At most 2 toasts on a phone (3 on bigger screens) so they never reach the speed gauge.
	local small = gui.AbsoluteSize.Y < 500
	table.sort(shown, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #shown - (small and 2 or 3) + 1 do
		shown[i]:Destroy()
	end
	local textSize = small and 16 or 20
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, textSize, Enum.Font.FredokaOne, Vector2.new(width - 28, 1000))
	end)
	local height = math.max(40, (ok and math.ceil(bounds.Y) or textSize * 2) + 14)
	order += 1
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.FredokaOne
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, math.min(20, height // 2))
	c.Parent = label
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(255, 62, 165)
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
	pad.Parent = label
	label.Parent = holder
	-- Longer messages stay up a little longer.
	task.delay(math.clamp(3 + #text / 30, 4, 7), function()
		if not label.Parent then
			return
		end
		label:SetAttribute("Fading", true)
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
