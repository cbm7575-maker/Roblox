-- OfferClient (ModuleScript, StarterPlayerScripts.Controllers.OfferClient)
-- Right-moment offers: when the game already knows a player would want a pass (Config.Shop.Offers), a
-- small flat card fades in, in the upper middle of the screen: what happened (Display title), what the
-- pass does (one line), a price button [BUY  R$ 99], a close ✕ and "Don't show this again". BUY opens
-- the normal Roblox purchase prompt (MarketplaceService); the server confirms the purchase and grants
-- the pass (ShopService). The card is fed by:
--   * HeistClient: OfferClient.Queue("BagFull", { LeftBehind = n }) when a heist or hot car overflowed
--     the bag (the cash left behind shows in red in the title);
--   * the server's Notify keys that refuse a pass item (NeedsPass_VIP, NeedsPass_NeonGarage,
--     CarNeedsPass), heard here directly; NotifyController still shows its own toast for them.
-- Rules: at most one card per Shop.OfferGap seconds (10 min); only on foot (never while seated: the drive
-- HUD is up then); never while wanted (Heat > 0), faster than Shop.OfferMaxMph, in prison, during a race,
-- job shift or mission, while the dealer card or a crew invite (CrewClient, same spot) is open, while a
-- HUDController stamp shows, on the title screen (TitleScreen), or before the tutorial is done; never for
-- a pass the player owns or an offer hidden with "Don't show again" (setting HideOffer_<key>, saved by
-- SettingsService). A card that's up fades away at once if the player gets wanted, sits in a car, opens
-- the dealer card, gets a crew invite, goes to prison, starts a race, job shift or mission (their timers
-- and QUIT live in the Banner zone, which the card may reach on short phones) or the title screen comes
-- up. A card that can't show yet waits a while for a calm moment, then is dropped (a bag usually
-- overflows with the cops on you, so that card comes once you've lost them and are on foot, e.g. at the
-- Hideout to bank).
-- A pass whose Id is still 0 is never offered in a live game. In Studio the card still shows.
-- Free shop (player attribute "ShopFree" = "Studio" | "Owner", ShopService): BUY reads FREE and asks the
-- server for the pass (RequestShopFree "Pass"; the server checks Studio / owner itself) instead of
-- Roblox's prompt. The owner already has every pass on join, so live cards never show for them; in
-- Studio the card and the dealer's pass cars grant the pass at once.
-- Studio only: the Workspace attribute TestOfferGap (number, seconds) replaces the 10-minute gap.
-- Look and place ("street" HUD, Theme; fitToScreen, again when the screen size or input type changes):
-- CanvasGroup "Card" in ScreenGui "Offer": a flat dark panel with small corners and a thin brand-pink
-- accent at its left edge. It sits centred on the Stamp zone's middle, between the left column (Feed
-- zone; Minimap zone on phones) and the right one (Status / Buttons zones), below the Banner zone (or,
-- on phones too short for that, below the Goal zone: there it may cover the Banner zone's passive
-- pieces, the GPS distance or a race preview, for its 12 s; never a timer, see the rules above) and
-- above the Subtitle zone (phones: above the Action zone), so it never covers the Corner or Action zones
-- (the car cluster, GET IN / JACK). Where that band is too narrow (small phones) it may cover the
-- minimap. While the phone is open it stays left of it. It fades out while a stamp shows (same spot) and
-- back in after; its 12 seconds only count while it's on screen. Touch targets are Theme.Touch tall on
-- touch screens.
-- API (DealerClient's pass cars use Buy / CanBuy / PriceText / Seen too):
--   OfferClient.Queue(key, info)    ask for the card for Shop.Offers[key]; it waits for a good moment
--   OfferClient.CanBuy(passKey)     true when the pass has a real Id (it can be bought), or the shop is free
--   OfferClient.Buy(passKey, key)   Roblox purchase prompt, the free grant (ShopFree), or "coming soon"
--                                   while the Id is 0; key = the offer it came from (analytics), may be nil
--   OfferClient.PriceText(passKey)  "R$ 499" read live from Roblox (yields, cached), "FREE" when the shop
--                                   is free, nil if unknown
--   OfferClient.Seen(key)           log an offer as shown (analytics, ShopService)
--   OfferClient.Hide()              fade the card away now

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local SettingsClient = require(script.Parent:WaitForChild("SettingsClient"))

local player = Players.LocalPlayer

local OfferClient = {}

local C = Theme.Color

local W = 440 -- the card's widest; it narrows to the free band (never under MIN_W if it can help it)
local MIN_W = 300
local EDGE = 12 -- pixels kept from the screen's edges
local GAP = 8 -- pixels kept from the neighbouring zones (side by side) and the open phone
local GAP_Y = 4 -- pixels kept from the Goal zone above and the Action / Subtitle zone below
local SLIDE = 8 -- pixels the card rises as it fades in
local SHOW_FOR = 12 -- seconds on screen before the card goes by itself (time behind a stamp doesn't count)
local WAIT_FOR = { BagFull = 360 } -- seconds a queued card may wait for a calm moment...
local DEFAULT_WAIT = 45 -- ...for the others (a refused tap is only worth answering soon after)
local STUDS_TO_MPH = 0.626 -- same as the speed gauge (DriveUI)
local CHECK_EVERY = 0.5

local gui, card, titleLabel, lineLabel, buyButton, neverButton, closeButton
local cardH = 116 -- the card's height for this screen (layoutCard)
local cardX, cardY = 0, 0 -- screen spot of the card's top centre (fitToScreen)
local pending -- { key, info, expires } waiting for a good moment
local showing -- { key, pass, left } while the card is up (left = seconds still to show)
local cardShown = false -- faded in (false while it steps aside for a stamp, and once hidden)
local fadeToken, showToken = 0, 0
local lastShownAt = -math.huge -- os.clock() when the last card showed
local prices = {} -- [pass Id] = "R$ 499"

------------------------------------------------------------------ small helpers

local function sound(name)
	task.spawn(function()
		pcall(function()
			require(script.Parent:WaitForChild("SoundClient")).Play(name)
		end)
	end)
end

local function label(parent, name, size, kind)
	local l = Instance.new("TextLabel")
	l.Name = name
	Theme.Text(l, size, kind)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function button(parent, name, onClick)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Parent = parent
	b.Activated:Connect(function()
		sound("Click")
		onClick()
	end)
	return b
end

-- Analytics only (ShopService logs it); never blocks the caller.
local function report(action, key)
	task.spawn(function()
		Remotes.Event("OfferEvent"):FireServer(action, key)
	end)
end

------------------------------------------------------------------ public helpers

-- Studio, or the game's owner: passes are free (ShopService sets it and checks it again on every ask).
local function freeShop()
	local free = player:GetAttribute("ShopFree")
	return free == "Studio" or free == "Owner"
end

function OfferClient.CanBuy(passKey)
	local pass = Shop.PassByKey(passKey)
	return pass ~= nil and (pass.Id ~= 0 or freeShop())
end

function OfferClient.PriceText(passKey)
	local pass = Shop.PassByKey(passKey)
	if pass and freeShop() then
		return "FREE"
	end
	if not pass or pass.Id == 0 then
		return nil
	end
	if prices[pass.Id] then
		return prices[pass.Id]
	end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.Id, Enum.InfoType.GamePass)
	if ok and type(info) == "table" and info.PriceInRobux then
		prices[pass.Id] = "R$ " .. info.PriceInRobux
		return prices[pass.Id]
	end
	return nil
end

function OfferClient.Seen(key)
	report("Shown", key)
end

function OfferClient.Buy(passKey, key)
	local pass = Shop.PassByKey(passKey)
	if not pass then
		return
	end
	if player:GetAttribute("Pass_" .. pass.Key) then
		NotifyController.Show("You already have the " .. pass.Name .. " pass!", C.Cash, "success")
		return
	end
	if freeShop() then
		Remotes.Event("RequestShopFree"):FireServer("Pass", pass.Key) -- (the server says yes with PassGranted)
		return
	end
	if pass.Id == 0 then
		NotifyController.Show("The " .. pass.Name .. " pass is coming soon!", C.Gold, "info")
		return
	end
	if key then
		report("Tapped", key)
	end
	local ok, err = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.Id)
	if not ok then
		warn("[OfferClient] purchase prompt failed: " .. tostring(err))
	end
end

------------------------------------------------------------------ when may a card show?

local function tutorialDone()
	return (player:GetAttribute("TutorialStep") or 0) >= #Tutorial.Steps
end

-- Seconds between cards (Studio testers can shorten it with the Workspace attribute TestOfferGap).
local function offerGap()
	local test = RunService:IsStudio() and Workspace:GetAttribute("TestOfferGap")
	return type(test) == "number" and test or Shop.OfferGap
end

-- Could this offer be shown at all (now or later)?
local function offerable(key)
	local offer = Shop.Offers[key]
	local pass = offer and Shop.PassByKey(offer.Pass)
	if not pass or player:GetAttribute("Pass_" .. pass.Key) then
		return false
	end
	if SettingsClient.Get("HideOffer_" .. key) == true then
		return false
	end
	return pass.Id ~= 0 or RunService:IsStudio() -- no Id yet: nothing to sell in a live game
end

local function speedMph()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.AssemblyLinearVelocity.Magnitude * STUDS_TO_MPH or 0
end

local function uiPart(guiName, childName)
	local pg = player:FindFirstChild("PlayerGui")
	local screenGui = pg and pg:FindFirstChild(guiName)
	return screenGui and screenGui:FindFirstChild(childName)
end

-- Sitting in a car (or any seat): the drive HUD is up, and offers are for calm moments on foot.
local function seated()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.SeatPart ~= nil
end

-- The dealer card fills the right side (and already shows a pass car's own BUY).
local function dealerOpen()
	local dealerCard = uiPart("DealerCard", "Card")
	return dealerCard ~= nil and dealerCard.Visible
end

-- CrewClient's invite card uses the same spot (and has buttons that matter more).
local function crewInviteUp()
	return uiPart("Crew", "CrewInvite") ~= nil
end

local function stampShowing()
	return HUDController.StampTop ~= nil and HUDController.StampTop() ~= nil
end

-- On the title screen, not picked yet, in prison, or in a race, job shift or mission (their own banners,
-- timers and help lines are up).
local function busy()
	if player:GetAttribute("TitleScreen") == true then
		return true
	end
	local side = player:GetAttribute("Side")
	if side ~= "Civilian" and side ~= "Cop" then
		return true -- not picked yet, or in prison
	end
	return player:GetAttribute("RacingId") ~= nil or player:GetAttribute("JobKind") ~= nil
		or player:GetAttribute("Mission") ~= nil
end

-- A calm moment: on foot, not wanted, not in prison or in the middle of an activity.
local function calm()
	if seated() or dealerOpen() or crewInviteUp() or stampShowing() or busy() then
		return false
	end
	return tutorialDone() and (player:GetAttribute("Heat") or 0) <= 0 and speedMph() <= Shop.OfferMaxMph
end

------------------------------------------------------------------ the card

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Offer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the zone map's coordinates (y = 0 is the very top of the screen)
	gui.DisplayOrder = 7 -- above the phone (5) and the dealer card (6), below the toasts (20)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- A CanvasGroup, so the whole card fades as one.
	card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Size = UDim2.fromOffset(W, cardH)
	card.GroupTransparency = 1
	card.Active = true -- taps on the card don't reach the world behind it
	card.Visible = false
	Theme.Panel(card, 0.2)
	card.Parent = gui

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(0, 0)
	accent.Size = UDim2.new(0, 2, 1, 0)
	accent.BackgroundColor3 = C.Brand
	accent.BorderSizePixel = 0
	accent.Parent = card

	titleLabel = label(card, "Title", 19, "Display")
	titleLabel.RichText = true
	lineLabel = label(card, "Line", 14, "Body")
	lineLabel.TextColor3 = C.Dim
	lineLabel.TextWrapped = true -- two lines at most, so the words stay a readable size
	lineLabel.TextYAlignment = Enum.TextYAlignment.Top

	-- "Don't show this again": a quiet text link at the bottom left (a full touch target on phones).
	neverButton = button(card, "Never", function()
		if not showing then
			return
		end
		local key = showing.key
		SettingsClient.Set("HideOffer_" .. key, true)
		report("Hidden", key)
		OfferClient.Hide()
		NotifyController.Show("Okay! You won't see that offer again.", C.Text, "info")
	end)
	Theme.Text(neverButton, 13, "Body")
	neverButton.TextColor3 = C.Dim
	neverButton.TextXAlignment = Enum.TextXAlignment.Left
	neverButton.AutoButtonColor = false
	neverButton.AnchorPoint = Vector2.new(0, 1)
	neverButton.Text = "Don't show this again"

	-- The price button, bottom right.
	buyButton = button(card, "Buy", function()
		if showing then
			local offer = showing
			OfferClient.Hide() -- Roblox's purchase prompt takes over from here
			OfferClient.Buy(offer.pass, offer.key)
		end
	end)
	Theme.Button(buyButton, "Primary")
	buyButton.TextSize = 14
	buyButton.AnchorPoint = Vector2.new(1, 1)
	buyButton.Text = "BUY"

	-- Close, top right ("Later": the old NO THANKS button's name).
	closeButton = button(card, "Later", function()
		OfferClient.Hide()
	end)
	Theme.Text(closeButton, 15, "Body")
	closeButton.TextColor3 = C.Dim
	closeButton.AutoButtonColor = false
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.Text = "X" -- (the font has no multiplication-sign glyph)
end

-- Sizes inside the card for this screen: phones get Theme.Touch-tall buttons, tighter rows and slightly
-- smaller words (111 px tall, so it fits between the Goal and Action zones on a 375 px-tall phone).
local function layoutCard(touch)
	local pad = touch and 5 or 10
	local titleRow = touch and 24 or 26
	local buttonH = touch and Theme.Touch or 32
	local closeW = touch and Theme.Touch or 34
	local lineSize = touch and 13 or 14
	local lineH = touch and 30 or 34 -- two lines
	local rowGap = touch and 3 or 4
	titleLabel.TextSize = touch and 18 or 19
	titleLabel.Position = UDim2.fromOffset(16, pad + 1)
	titleLabel.Size = UDim2.new(1, -(16 + closeW + 4), 0, 22)
	lineLabel.TextSize = lineSize
	lineLabel.Position = UDim2.fromOffset(16, pad + titleRow)
	lineLabel.Size = UDim2.new(1, -(16 + closeW + 4), 0, lineH)
	closeButton.Size = UDim2.fromOffset(closeW, closeW)
	buyButton.Size = UDim2.fromOffset(128, buttonH)
	buyButton.Position = UDim2.new(1, -10, 1, -pad)
	neverButton.Size = UDim2.new(1, -(16 + 128 + 10 + GAP), 0, buttonH)
	neverButton.Position = UDim2.new(0, 16, 1, -pad)
	cardH = pad + titleRow + lineH + rowGap + buttonH + pad
end

-- A zone's box on this screen: x, y, width, height (pixels).
local function zoneBox(name, touch, screen)
	local z = Theme.Zone(name, touch)
	local w = z.Size.X.Scale * screen.X + z.Size.X.Offset
	local h = z.Size.Y.Scale * screen.Y + z.Size.Y.Offset
	return z.Pos.X.Scale * screen.X + z.Pos.X.Offset - z.Anchor.X * w, z.Pos.Y.Scale * screen.Y + z.Pos.Y.Offset - z.Anchor.Y * h, w, h
end

-- Where the card goes on this screen (see the header). While the card is up this runs again (tick,
-- screen resize), so opening or closing the phone moves the card out of its way.
local function fitToScreen()
	if not gui or not card then
		return
	end
	local screen = gui.AbsoluteSize
	if screen.X < 1 then
		return
	end
	local touch = Theme.IsTouch()
	layoutCard(touch)
	-- Across: right of the left column, left of the right one (and of the open phone).
	local lx, _, lw = zoneBox(touch and "Minimap" or "Feed", touch, screen)
	local left = lx + lw + GAP
	local sx = zoneBox("Status", touch, screen)
	local right = sx - GAP
	if not touch then
		local bx = zoneBox("Buttons", touch, screen)
		right = math.min(right, bx - GAP)
	end
	local body = uiPart("Phone", "Body")
	if body and body.Visible then
		right = math.min(right, body.AbsolutePosition.X - GAP)
	end
	if right - left < MIN_W then
		left = EDGE -- too tight (small phones): cover the minimap rather than squash the words
	end
	if right - left < MIN_W then
		right = screen.X - EDGE
	end
	local w = math.min(W, right - left)
	local x = math.clamp(screen.X / 2, left + w / 2, math.max(left + w / 2, right - w / 2))
	-- Down: centred on the Stamp zone, under the Banner zone (which sits under the Goal zone) and above
	-- the Subtitle zone (phones: the Action zone). A phone too short for that (390 px: 90 px between the
	-- Banner and Action zones) gets it under the Goal zone instead; only passive Banner pieces can be up
	-- then (calm() and tick keep it away from missions, races, shifts, prison and the cops).
	local _, sy, _, sh = zoneBox("Stamp", touch, screen)
	local _, gy, _, gh = zoneBox("Goal", touch, screen)
	local _, by, _, bh = zoneBox("Banner", touch, screen)
	local _, ly = zoneBox(touch and "Action" or "Subtitle", touch, screen)
	local lowest = ly - GAP_Y - cardH
	local minTop = by + bh + GAP_Y
	if minTop > lowest then
		minTop = gy + gh + GAP_Y
	end
	local y = math.clamp(sy + sh / 2 - cardH / 2, minTop, math.max(minTop, lowest))
	card.Size = UDim2.fromOffset(math.floor(w), cardH)
	x, y = math.floor(x + 0.5), math.floor(y + 0.5)
	if x ~= cardX or y ~= cardY then
		cardX, cardY = x, y
		if cardShown then
			TweenService:Create(card, TweenInfo.new(0.15), { Position = UDim2.fromOffset(cardX, cardY) }):Play()
		end
	end
end

-- Fade the card in (rising a few pixels) or out.
local function fadeCard(on)
	if on == cardShown then
		return
	end
	cardShown = on
	fadeToken += 1
	local token = fadeToken
	if on then
		card.Visible = true
		card.Position = UDim2.fromOffset(cardX, cardY + SLIDE)
		TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 0, Position = UDim2.fromOffset(cardX, cardY) }):Play()
	else
		local tween = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 })
		tween.Completed:Connect(function(playback)
			if playback == Enum.PlaybackState.Completed and token == fadeToken then
				card.Visible = false
			end
		end)
		tween:Play()
	end
end

function OfferClient.Hide()
	if not showing then
		return
	end
	showing = nil
	showToken += 1
	fadeCard(false)
end

local function show(p)
	local offer = Shop.Offers[p.key]
	local pass = Shop.PassByKey(offer.Pass)
	fitToScreen() -- before the fade-in below, so it rises into the right spot
	lastShownAt = os.clock()
	showing = { key = p.key, pass = pass.Key, left = SHOW_FOR }
	showToken += 1
	local token = showToken

	local title = offer.Title
	local left = tonumber(p.info.LeftBehind)
	if p.key == "BagFull" and left and left > 0 then
		-- The cash that didn't fit, in the danger colour: that's what the pass would have saved.
		title = title .. "   " .. string.format('<font color="#%s">%s LEFT BEHIND</font>', C.Danger:ToHex(),
			HUDController.Money(left))
	end
	titleLabel.Text = title
	lineLabel.Text = offer.Line
	local canBuy = OfferClient.CanBuy(pass.Key)
	buyButton.Text = canBuy and (prices[pass.Id] and ("BUY  " .. prices[pass.Id]) or "BUY") or "SOON"

	fadeCard(true)
	sound("Checkpoint")

	if canBuy then
		OfferClient.Seen(p.key)
		task.spawn(function()
			local text = OfferClient.PriceText(pass.Key)
			if text and token == showToken then
				buyButton.Text = "BUY  " .. text
			end
		end)
	end
end

function OfferClient.Queue(key, info)
	if type(key) ~= "string" or not Shop.Offers[key] or not offerable(key) then
		return
	end
	pending = { key = key, info = type(info) == "table" and info or {}, expires = os.clock() + (WAIT_FOR[key] or DEFAULT_WAIT) }
end

-- Every half second: show a waiting card once the moment is right, drop it once it's stale; while one
-- is up, step aside for stamps, count its time on screen, follow the phone opening or closing.
local function tick()
	if showing then
		if (player:GetAttribute("Heat") or 0) > 0 or seated() or dealerOpen() or crewInviteUp() or busy() then
			-- The cops came, they got in a car or opened the dealer card, a crew invite came, or a mission,
			-- race or shift started (its timer and QUIT may sit right under the card on a short phone).
			OfferClient.Hide()
			return
		end
		fitToScreen()
		local covered = stampShowing()
		fadeCard(not covered)
		if not covered then
			showing.left -= CHECK_EVERY
			if showing.left <= 0 then
				OfferClient.Hide()
			end
		end
		return
	end
	if not pending then
		return
	end
	if os.clock() > pending.expires or not offerable(pending.key) then
		pending = nil
	elseif os.clock() - lastShownAt >= offerGap() and calm() then
		local p = pending
		pending = nil
		show(p)
	end
end

------------------------------------------------------------------ start

function OfferClient.Init()
	build()
	fitToScreen()
	-- Re-place when the screen changes size or the device's input changes (phone layout or not).
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(fitToScreen)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(fitToScreen)
	-- A refused pass item (a VIP paint, a Neon Garage glow, a pass car): offer that pass.
	Remotes.OnClient("Notify", function(key)
		if type(key) == "string" and Shop.Offers[key] then
			OfferClient.Queue(key)
		end
	end)
	-- Bought it (here or anywhere else): the card has done its job.
	player.AttributeChanged:Connect(function(name)
		if showing and name == "Pass_" .. showing.pass and player:GetAttribute(name) then
			OfferClient.Hide()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(tick)
			if not ok then
				warn("[OfferClient] " .. tostring(err))
			end
		end
	end)
end

return OfferClient
