-- DealerClient (ModuleScript, StarterPlayerScripts.Controllers.DealerClient)
-- The walk-in dealerships DealershipService builds (AutoNeon Motors downtown, Marina Boat Sales on
-- the first marina pier):
--   * Press "View" at a display: a card eases in with the vehicle's name, class, factory colour, stat
--     bars (top speed, acceleration, handling, toughness from Config.Vehicles), the price and a BUY
--     button. BUY takes two taps (the second within 4 s) and sends the normal garage purchase
--     (RequestBuyCar); GarageService checks cash and ownership and answers with GarageResult (PhoneUI
--     shows the NEW RIDE! stamp). OWNED, "game pass" and "cop rank" locks come from the vehicle def.
--   * The card is in the flat "street" look (Shared.Util.Theme): a flat dark panel with small corners,
--     white text in the two Theme fonts, thin white stat bars, flat Theme buttons, and colour only where
--     it means something (green = cash and "yours", gold = game pass, blue = police, purple = a heist
--     lock, red = short of cash; a thin pink or cyan line marks cars or boats). It is wide and short:
--     name, class and stats on the left, price, status and the buttons on the right, one hint line
--     along the foot.
--   * Where it sits (fitToScreen): never over the HUD's Status, Buttons or Corner zones (Theme's zone
--     map). On a PC it is on the right, left of the PHONE / CAR tiles, between the status pills and the
--     car cluster's corner. On a phone it is left of the status column and the PHONE / CAR row, above
--     the bottom-centre corner zone, and clear of Roblox's own buttons in the top left corner (beside
--     them on a wide phone, under them on a narrow one). A UIScale fits it into that room (1.0 on most
--     phones, up to 1.3 on a big monitor), and its buttons grow so they stay about Theme.Touch real
--     pixels tall when the card has to shrink. It eases in and out sideways from the left, so it never
--     slides across those zones.
--   * Game-pass cars (the Vortex, on its spotlit turntable): BUY opens the Roblox purchase prompt right
--     there, with the live Robux price (OfferClient.Buy; it says "coming soon" while the pass Id is 0).
--   * Heist-locked rides (UnlockHeists): "LOCKED: 3 BIG HEISTS" on the button, "BIG HEISTS: 1 / 3" as
--     the status line and "🔒 3 BIG HEISTS (1/3)" on the tag, until the player's BigHeists count (their
--     own and their crew's Coastal Bank / Sea Dream jobs) is enough; then they're bought with cash like
--     any other.
--   * TUNE IT: once a car that can be tuned is yours (Config.Garage.CanTune: not boats, not police cars),
--     a white TUNE IT button shows under OWNED. It opens the phone on that car's TUNE page
--     (PhoneUI.Open("Tune", id)), and pulses a few times right after the purchase; the hint line says
--     tuning means speed AND exhaust sound. The stat bars are the car's stock numbers.
--   * The card closes by itself when you walk away, sit down, respawn or open the phone (the phone
--     comes up over the same part of the screen).
--   * Display cars turn slowly on their turntables and boats bob at their berths. Local only (the
--     server keeps them still), synced to server time, and only near the camera.
--   * The price tags over the displays read OWNED once you own that vehicle.
-- Names other code and the test tools use (keep them): ScreenGui "DealerCard" > "Card" > "Close",
-- "Class", "Colour", the stat bars "SPEED" / "ACCEL" / "HANDLING" / "TOUGH" (each with a "Fill"), "Buy"
-- and "Tune".
-- DealerClient.Close() / IsOpen() for other controllers.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Garage = require(ReplicatedStorage.Shared.Config.Garage)
local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local DealerClient = {}

local C = Theme.Color

local W, H = 430, 252 -- card design size; a UIScale fits it to the room the HUD leaves (fitToScreen)
local EDGE = 16 -- from the card's edge to what is on it
local COL = 228 -- where the right column (price, status, buttons) starts
local COL_W = W - EDGE - COL -- ...and how wide it is
local BUTTONS_Y = 100 -- top of BUY; TUNE IT sits under it
local BUTTON_MAX = 58 -- the tallest those two can grow (design pixels) before they reach the hint line
local GAP = 8 -- pixels kept between the card and a HUD zone (and the screen's edge)
local TOPBAR_W = 170 -- phones: how far Roblox's own buttons (and the minimap under them) reach in from the left
local NUDGE = 28 -- pixels the card eases in from (and out to), to its left
local STUDS_TO_MPH = 0.626 -- same as the speed gauge (DriveUI)
local MAX_SPEED_BAR = math.max(Vehicles.TopSpeed or 0, 1) -- the fastest vehicle fills the speed bar
local CONFIRM_TIME = 4
local PENDING_TIME = 3 -- how long BUY waits for the server's answer
local CLOSE_DIST = 24 -- walk this far from the display and the card closes
local SPIN = math.pi * 2 / 30 -- turntables: one turn every 30 seconds
local MOTION_RANGE = 170 -- only animate displays this close to the camera
local MOTION_STEP = 1 / 30
local TAU = math.pi * 2

local money = HUDController.Money

local gui, card, fit, accentBar, dealerLabel, nameLabel, classLabel, colorDot
local priceLabel, statusLabel, buyButton, closeButton, hintLabel
local tuneButton, tunePop -- TUNE IT and the UIScale that pulses it
local tunePulseUntil = 0 -- os.clock() until which TUNE IT pulses when it appears (just bought)
local restPos = UDim2.new(1, -108, 0.5, 0) -- where the card sits while it is open (fitToScreen)
local bars = {}
local openId, openPart
local state -- what BUY does right now: "buy", "short", "owned", "pass", "rank" or "heists"
local passPrices = {} -- [pass key] = "R$ 499" once read from Roblox
local confirmUntil, pendingUntil = 0, 0
local onBuy -- forward declaration (the button is built before it)

local displays = {} -- [display model] = { pivot, phase, motion, parts, rels, cfs, has, conns }

------------------------------------------------------------------ small helpers

local function sound(name)
	task.spawn(function()
		pcall(function()
			require(script.Parent:WaitForChild("SoundClient")).Play(name)
		end)
	end)
end

-- A label on the card in a Theme font at a fixed size, placed in design pixels.
local function text(name, x, y, w, h, px, kind, color, align)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.FontFace = Theme.Font[kind or "Body"]
	l.TextSize = px
	l.TextColor3 = color or C.Text
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = card
	return l
end

-- Let a one-line label shrink its text to fit (a long car name, a seven-figure price): never bigger
-- than `px`.
local function shrinkToFit(l, px)
	l.TextScaled = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = px
	cap.MinTextSize = 10
	cap.Parent = l
end

-- Theme.Button as it looks on the card, words in the Display font. kind: "Primary" (white), "Quiet", or
-- "Confirm" (cash green: a buy waiting for its second tap, or for the server). Theme's quiet button is
-- see-through black, made to sit over the street; on the card's own black it couldn't be told from the
-- panel, so here it is Theme's lighter panel colour (as on the phone's pages).
local function look(b, kind)
	Theme.Button(b, kind == "Confirm" and "Primary" or kind)
	b.FontFace = Theme.Font.Display
	if kind == "Confirm" then
		b.BackgroundColor3 = C.Cash
	elseif kind == "Quiet" then
		b.BackgroundColor3 = C.PanelLight
		b.BackgroundTransparency = 0.2
	end
	return b
end

-- A flat button on the card. The caller places it.
local function flatButton(name, words, kind, px, onTap)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = words
	b.TextSize = px
	b.TextTruncate = Enum.TextTruncate.AtEnd
	look(b, kind)
	b.Parent = card
	b.Activated:Connect(function()
		sound("Click")
		onTap()
	end)
	return b
end

-- Same rules as GarageService.Owns: the saved list, a game pass, or a high enough cop rank.
local function owns(def)
	if def.Pass and player:GetAttribute("Pass_" .. def.Pass) then
		return true
	end
	if def.UnlockCopRank and (player:GetAttribute("CopRank") or 0) >= def.UnlockCopRank then
		return true
	end
	for id in string.gmatch(player:GetAttribute("OwnedCars") or "", "[^,]+") do
		if id == def.Id then
			return true
		end
	end
	return false
end

local function priceText(def)
	if def.Pass then
		return passPrices[def.Pass] or "GAME PASS"
	elseif def.UnlockCopRank then
		return "COP RANK " .. def.UnlockCopRank
	elseif (def.Price or 0) > 0 then
		return money(def.Price)
	end
	return "FREE"
end

-- Big heists needed and done, while a heist-locked ride is still locked for us (else nil).
local function heistLock(def)
	local need = def.UnlockHeists
	local have = player:GetAttribute("BigHeists") or 0
	if type(need) == "number" and have < need then
		return need, have
	end
	return nil
end

-- The lock as the price tags over the displays show it (DealershipService builds them, in its own look).
local function heistLockText(need, have)
	return "🔒 " .. need .. " BIG HEISTS (" .. have .. "/" .. need .. ")"
end

-- OfferClient (looked up when needed): the Roblox pass prompt, live prices and the Id 0 handling.
local function offers()
	local module = script.Parent:FindFirstChild("OfferClient")
	if not module then
		return nil
	end
	local ok, o = pcall(require, module)
	return ok and type(o) == "table" and o or nil
end

------------------------------------------------------------------ the card

-- TUNE IT: open the phone on this car's TUNE page (PHONE > GARAGE > TUNE). The phone puts the card away
-- itself (it comes up over the same part of the screen).
local function tuneIt()
	local id = openId
	if not id then
		return
	end
	local ok = pcall(function()
		require(script.Parent:FindFirstChild("PhoneUI")).Open("Tune", id)
	end)
	if not ok then
		NotifyController.Show("Tune it from PHONE > GARAGE > TUNE.", nil, "info")
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DealerCard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 6 -- above the phone (5), below the toasts (20)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- A flat dark panel, anchored at the middle of its right edge (fitToScreen says where that is).
	card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(1, 0.5)
	card.Position = restPos
	card.Size = UDim2.fromOffset(W, H)
	card.Active = true -- taps on the card don't reach the world behind it
	card.Visible = false
	Theme.Panel(card, 0.12)
	card.Parent = gui
	fit = Instance.new("UIScale")
	fit.Parent = card

	-- Left: who sells it (a thin pink line for cars, cyan for boats), the name, class and factory colour.
	accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Position = UDim2.fromOffset(EDGE, 13)
	accentBar.Size = UDim2.fromOffset(3, 12)
	accentBar.BackgroundColor3 = C.Brand
	accentBar.BorderSizePixel = 0
	accentBar.Parent = card
	dealerLabel = text("Dealer", EDGE + 10, 11, COL - EDGE - 18, 16, 12, "Bold", C.Dim)
	dealerLabel.Text = "AUTONEON MOTORS"
	nameLabel = text("Name", EDGE, 28, COL - EDGE - 12, 34, 28, "Display")
	shrinkToFit(nameLabel, 28)

	local classChip = Instance.new("Frame")
	classChip.Name = "Class"
	classChip.Position = UDim2.fromOffset(EDGE, 68)
	classChip.Size = UDim2.fromOffset(128, 22)
	classChip.BackgroundColor3 = C.PanelLight
	classChip.BackgroundTransparency = 0.3
	classChip.BorderSizePixel = 0
	Theme.Corners(classChip, 4)
	classChip.Parent = card
	classLabel = text("Label", 0, 0, 0, 0, 12, "Bold", nil, Enum.TextXAlignment.Center)
	classLabel.Size = UDim2.new(1, -8, 1, 0)
	classLabel.Position = UDim2.fromOffset(4, 0)
	classLabel.Parent = classChip
	colorDot = Instance.new("Frame")
	colorDot.Name = "Colour"
	colorDot.Position = UDim2.fromOffset(EDGE + 128 + 8, 68)
	colorDot.Size = UDim2.fromOffset(22, 22)
	colorDot.BorderSizePixel = 0
	Theme.Corners(colorDot, 4)
	colorDot.Parent = card
	local rim = Instance.new("UIStroke")
	rim.Color = C.Text
	rim.Thickness = 1
	rim.Transparency = 0.7
	rim.Parent = colorDot

	-- Four stats: name, a thin white bar (dim where it's empty: Theme's black track can't be seen on the
	-- card) and the number.
	for i, name in ipairs({ "SPEED", "ACCEL", "HANDLING", "TOUGH" }) do
		local y = 102 + (i - 1) * 25
		text("Stat" .. i, EDGE, y, 68, 16, 12, "Bold", C.Dim).Text = name
		local bar, fill = Theme.Bar(card, C.Text)
		bar.Name = name
		bar.Position = UDim2.fromOffset(EDGE + 70, y + 5)
		bar.Size = UDim2.fromOffset(64, 6)
		bar.BackgroundColor3 = C.Dim
		bar.BackgroundTransparency = 0.75
		fill.Size = UDim2.fromScale(0, 1)
		local value = text("Value" .. i, EDGE + 140, y, COL - 12 - (EDGE + 140), 16, 14, "Display", nil, Enum.TextXAlignment.Right)
		bars[i] = { fill = fill, value = value }
	end

	-- Right: close, the price, what stands between you and it, and the buttons (fitToScreen sizes them).
	closeButton = flatButton("Close", "X", "Quiet", 18, function()
		DealerClient.Close()
	end)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.fromOffset(W - GAP, GAP)
	closeButton.Size = UDim2.fromOffset(Theme.Touch, Theme.Touch)
	-- (The price is narrower than the column: the close button's corner reaches down beside it.)
	priceLabel = text("Price", COL, 50, COL_W - 52, 30, 28, "Display", C.Cash)
	shrinkToFit(priceLabel, 28)
	statusLabel = text("Status", COL, 82, COL_W, 14, 12, "Bold", C.Dim)
	buyButton = flatButton("Buy", "BUY", "Primary", 18, function()
		onBuy()
	end)
	buyButton.Position = UDim2.fromOffset(COL, BUTTONS_Y)
	buyButton.Size = UDim2.fromOffset(COL_W, Theme.Touch)
	-- TUNE IT (shown by refresh once the car is owned), anchored at its middle so its pulse grows evenly.
	tuneButton = flatButton("Tune", "TUNE IT  ›", "Primary", 20, tuneIt)
	tuneButton.AnchorPoint = Vector2.new(0.5, 0.5)
	tuneButton.Size = UDim2.fromOffset(COL_W, Theme.Touch)
	tuneButton.Position = UDim2.fromOffset(COL + COL_W / 2, BUTTONS_Y + Theme.Touch + 6 + Theme.Touch / 2)
	tuneButton.Visible = false
	tunePop = Instance.new("UIScale")
	tunePop.Parent = tuneButton

	hintLabel = text("Hint", EDGE, H - 26, W - 2 * EDGE, 18, 12, "Body", C.Dim, Enum.TextXAlignment.Center)
end

-- The screen the card is laid out in (its own full-screen ScreenGui; the camera's until that has a size).
local function screenSize()
	local size = gui and gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then
		return size
	end
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(844, 390)
end

-- Fit the card into the room the HUD leaves it (see the header): its right edge, the band it is centred
-- in and its scale, then the buttons' height for that scale.
local function fitToScreen()
	if not fit then
		return
	end
	local vp = screenSize()
	local touch = Theme.IsTouch()
	local buttons = Theme.Zone("Buttons", touch)
	local corner = Theme.Zone("Corner", touch)
	-- Above the Corner zone (anchored to the screen's foot in both layouts).
	local bottom = vp.Y + corner.Pos.Y.Offset - corner.Size.Y.Offset - GAP
	local top, left, right = GAP, GAP, nil
	if touch then
		-- Phone: Status and the PHONE / CAR row share the top right corner: stay left of both.
		local status = Theme.Zone("Status", true)
		right = math.min(status.Pos.X.Offset - status.Size.X.Offset, buttons.Pos.X.Offset - buttons.Size.X.Offset) - GAP
		-- Roblox's own buttons own the top left corner (Theme.TopBar pixels tall). Either the card stays
		-- right of them and uses the whole height, or it goes under them and uses the whole width:
		-- whichever leaves it bigger (a wide phone fits it beside them at full size).
		local beside = math.min((bottom - GAP) / H, (vp.X + right - TOPBAR_W) / W)
		local under = math.min((bottom - Theme.TopBar - GAP) / H, (vp.X + right - GAP) / W)
		if beside >= under then
			left = TOPBAR_W
		else
			top = Theme.TopBar + GAP
		end
	else
		-- PC: left of the tile column on the right edge (and its key caps, like the phone), under Status
		-- and its pills.
		local pills = Theme.Zone("Pills", false)
		top = pills.Pos.Y.Offset + pills.Size.Y.Offset + GAP
		right = buttons.Pos.X.Offset - buttons.Size.X.Offset - 36
	end
	local scale = math.clamp(math.min((bottom - top) / H, (vp.X + right - left) / W), 0.6, touch and 1 or 1.3)
	fit.Scale = scale
	restPos = UDim2.new(1, right, 0, math.floor((top + bottom) / 2))
	if openId then
		card.Position = restPos
	end
	-- BUY and TUNE IT stay about Theme.Touch real pixels tall when the card is scaled down (BUTTON_MAX
	-- design pixels each is the room the right column has); the close button a little less, beside the price.
	local tall = math.clamp(math.ceil(Theme.Touch / scale), Theme.Touch, BUTTON_MAX)
	local small = math.min(tall, 48)
	closeButton.Size = UDim2.fromOffset(small, small)
	buyButton.Size = UDim2.fromOffset(COL_W, tall)
	tuneButton.Size = UDim2.fromOffset(COL_W, tall)
	tuneButton.Position = UDim2.fromOffset(COL + COL_W / 2, BUTTONS_Y + tall + 6 + tall / 2)
end

-- BUY's words and look. kind: "Primary" (a tap buys), "Quiet" (nothing to buy right now) or "Confirm"
-- (see look). ink: another colour for the words.
local function setButton(words, kind, ink)
	look(buyButton, kind)
	if ink then
		buyButton.TextColor3 = ink
	end
	buyButton.Text = words
	buyButton.TextSize = #words > 18 and 15 or 18 -- the long ones (TAP AGAIN TO CONFIRM) still fit
end

-- Price, status line and the BUY button for the vehicle on the card (cash and ownership change live).
local function refresh()
	local def = openId and Vehicles.ById[openId]
	if not def then
		return
	end
	local price = def.Price or 0
	local cash = player:GetAttribute("Cash") or 0
	local now = os.clock()
	local heistNeed, heistHave = heistLock(def)
	statusLabel.Text = ""
	priceLabel.Text = priceText(def)
	priceLabel.TextColor3 = (def.Pass and C.Gold) or (def.UnlockCopRank and C.Police) or C.Cash
	if owns(def) then
		state = "owned"
		statusLabel.Text = "IN YOUR GARAGE"
		statusLabel.TextColor3 = C.Cash
		setButton("OWNED", "Quiet", C.Cash)
	elseif def.Pass then
		state = "pass"
		local pass = Shop.PassByKey(def.Pass)
		statusLabel.Text = string.upper(pass and pass.Name or def.Pass) .. " PASS"
		statusLabel.TextColor3 = C.Gold
		local o = offers()
		if o and o.CanBuy(def.Pass) then
			setButton(passPrices[def.Pass] and ("BUY  " .. passPrices[def.Pass]) or "BUY WITH ROBUX", "Primary")
		else
			setButton("COMING SOON", "Quiet", C.Dim)
		end
	elseif def.UnlockCopRank then
		state = "rank"
		statusLabel.Text = "YOUR COP RANK: " .. (player:GetAttribute("CopRank") or 0)
		statusLabel.TextColor3 = C.Dim
		setButton("UNLOCKS AT COP RANK " .. def.UnlockCopRank, "Quiet", C.Dim)
	elseif heistNeed then
		state = "heists"
		statusLabel.Text = "BIG HEISTS: " .. heistHave .. " / " .. heistNeed
		statusLabel.TextColor3 = C.Purple
		setButton("LOCKED: " .. heistNeed .. " BIG HEISTS", "Quiet", C.Dim)
	elseif cash < price then
		state = "short"
		statusLabel.Text = "NEED " .. money(price - cash) .. " MORE"
		statusLabel.TextColor3 = C.Danger
		setButton("BUY " .. money(price), "Quiet", C.Dim)
	else
		state = "buy"
		statusLabel.Text = "YOU HAVE " .. money(cash)
		statusLabel.TextColor3 = C.Dim
		if now < pendingUntil then
			setButton("BUYING...", "Confirm")
		elseif now < confirmUntil then
			setButton("TAP AGAIN TO CONFIRM", "Confirm")
		else
			setButton(price > 0 and ("BUY " .. money(price)) or "GET IT FREE", "Primary")
		end
	end
	-- Owned and tunable: TUNE IT shows under OWNED.
	local offerTune = state == "owned" and Garage.CanTune(def)
	tuneButton.Visible = offerTune
	if offerTune and now < tunePulseUntil then
		-- Just bought: a few gentle pulses so the new owner spots it (never a popup).
		tunePulseUntil = 0
		tunePop.Scale = 1
		-- 1.04: about a pixel each way, inside the gaps around the button.
		TweenService:Create(tunePop, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true),
			{ Scale = 1.04 }):Play()
	end
	if heistNeed then
		-- Short, so it fits the one hint line (the BUY toast explains the rest).
		hintLabel.Text = "Rob the " .. Heists.BigNames() .. " (crew help counts)."
	elseif offerTune then
		-- Both halves of tuning (speed and the exhaust sound), so new owners look for both.
		hintLabel.Text = "TUNE IT for speed and sound. Step outside to call it."
	else
		hintLabel.Text = def.Boat and "Boats you own launch from PHONE > GARAGE at the marina."
			or "Owned cars: step outside, then PHONE > GARAGE." -- no room to call a car in the showroom
	end
end

onBuy = function()
	local def = openId and Vehicles.ById[openId]
	if not def then
		return
	end
	local name = def.DisplayName or def.Id
	local now = os.clock()
	if state == "owned" then
		NotifyController.Show("You own the " .. name .. "! " .. (def.Boat and "LAUNCH it from PHONE > GARAGE." or "Step outside and call it from PHONE > GARAGE."),
			nil, "info")
	elseif state == "pass" then
		local o = offers()
		if o then
			o.Buy(def.Pass, "Showroom_" .. def.Pass) -- the Roblox prompt (or "coming soon" while its Id is 0)
		else
			DealerClient.Close()
			local ok = pcall(function()
				require(script.Parent:FindFirstChild("PhoneUI")).Open("Shop")
			end)
			if not ok then
				NotifyController.Show("The " .. name .. " comes with a game pass (PHONE > SHOP).", nil, "info")
			end
		end
	elseif state == "rank" then
		NotifyController.Show("Reach police rank " .. def.UnlockCopRank .. " to unlock the " .. name .. ".", nil, "info")
	elseif state == "heists" then
		local need, have = heistLock(def)
		if need then
			local left = need - have
			NotifyController.Show("Pull " .. left .. " more big heist" .. (left == 1 and "" or "s") .. " (" .. Heists.BigNames()
				.. ") to unlock the " .. name .. ", then buy it with cash. Helping your crew counts too!", nil, "info")
		end
	elseif state == "short" then
		local short = math.max(0, (def.Price or 0) - (player:GetAttribute("Cash") or 0))
		NotifyController.Show("You need " .. money(short) .. " more for the " .. name .. ". Jobs, races and missions pay!", nil, "money")
	elseif state == "buy" and now >= pendingUntil then
		if now < confirmUntil then
			-- Second tap: ask the server (it checks the price and our cash again).
			confirmUntil = 0
			pendingUntil = now + PENDING_TIME
			Remotes.Event("RequestBuyCar"):FireServer(def.Id)
			task.delay(PENDING_TIME + 0.05, refresh)
		else
			confirmUntil = now + CONFIRM_TIME
			task.delay(CONFIRM_TIME + 0.05, refresh)
		end
	end
	refresh()
end

-- Stat bars grow in one after another when the card opens.
local function fillStats(def)
	local speed = def.MaxSpeed or 0
	local stats = {
		{ speed / MAX_SPEED_BAR, math.floor(speed * STUDS_TO_MPH + 0.5) .. " mph" },
		{ (def.AccelRating or 1) / 5, (def.AccelRating or 1) .. " / 5" },
		{ (def.HandlingRating or 1) / 5, (def.HandlingRating or 1) .. " / 5" },
		{ (def.Toughness or 1) / 5, (def.Toughness or 1) .. " / 5" },
	}
	for i, s in ipairs(stats) do
		local b = bars[i]
		b.value.Text = s[2]
		b.fill.Size = UDim2.fromScale(0, 1)
		TweenService:Create(b.fill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.1 + i * 0.06),
			{ Size = UDim2.fromScale(math.clamp(s[1], 0.05, 1), 1) }):Play()
	end
end

local function open(id, part)
	local def = Vehicles.ById[id]
	if not def then
		return
	end
	local wasOpen = openId ~= nil
	openId, openPart = id, part
	confirmUntil, pendingUntil = 0, 0
	local accent = def.Boat and C.BrandAlt or C.Brand
	dealerLabel.Text = def.Boat and "MARINA BOAT SALES" or "AUTONEON MOTORS"
	accentBar.BackgroundColor3 = accent
	nameLabel.Text = string.upper(def.DisplayName or def.Id)
	classLabel.Text = string.upper(def.Class or (def.Boat and "Boat" or "Car"))
	colorDot.BackgroundColor3 = def.Color or accent
	fillStats(def)
	fitToScreen()
	refresh()
	-- A pass car you don't own yet: read its Robux price (then show it) and count the card as an offer.
	if def.Pass and not owns(def) then
		task.spawn(function()
			local o = offers()
			if not o or not o.CanBuy(def.Pass) then
				return
			end
			o.Seen("Showroom_" .. def.Pass)
			local robux = o.PriceText(def.Pass)
			if robux then
				passPrices[def.Pass] = robux
				if openId == id then
					refresh()
				end
			end
		end)
	end
	-- The phone comes up over the same part of the screen: put it away.
	pcall(function()
		require(script.Parent:FindFirstChild("PhoneUI")).Close()
	end)
	card.Visible = true
	if not wasOpen then
		card.Position = restPos - UDim2.fromOffset(NUDGE, 0)
	end
	TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = restPos }):Play()
	sound("Click")
end

function DealerClient.Close()
	if not openId then
		return
	end
	openId, openPart, state = nil, nil, nil
	confirmUntil, pendingUntil = 0, 0
	local tween = TweenService:Create(card, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = restPos - UDim2.fromOffset(NUDGE, 0) })
	tween.Completed:Connect(function(playback)
		if playback == Enum.PlaybackState.Completed and not openId then
			card.Visible = false
		end
	end)
	tween:Play()
end

function DealerClient.IsOpen()
	return openId ~= nil
end

local function onPrompt(prompt, who)
	if who ~= player or prompt.Name ~= "DealerView" then
		return
	end
	local id = prompt:GetAttribute("VehicleId")
	if type(id) ~= "string" or not Vehicles.ById[id] then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		NotifyController.Show("Hop out to take a closer look!", nil, "info")
		return
	end
	open(id, prompt.Parent)
end

-- Close the card once we walk away from the display, sit down or die.
local function checkDistance()
	if not openId then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local far = not root or not openPart or not openPart.Parent or (root.Position - openPart.Position).Magnitude > CLOSE_DIST
	if far or not hum or hum.Health <= 0 or hum.SeatPart ~= nil then
		DealerClient.Close()
	end
end

------------------------------------------------------------------ price tags

local function refreshTag(tagGui)
	local id = tagGui:GetAttribute("VehicleId")
	local def = id and Vehicles.ById[id]
	local price = tagGui:FindFirstChild("Price", true)
	if not def or not price then
		return
	end
	local need, have = heistLock(def)
	if owns(def) then
		price.Text = "OWNED ✓"
		price.TextColor3 = C.Cash
	elseif need then
		price.Text = heistLockText(need, have)
		price.TextColor3 = C.Purple
	else
		price.Text = priceText(def)
		price.TextColor3 = C.Gold
	end
end

-- Every tag streamed in right now. Only runs when ownership, cop rank or a pass changes (rare), so a
-- walk over the dealerships is cheap and nothing has to keep a list of tags.
local function refreshTags()
	local folder = Workspace:FindFirstChild("Dealerships")
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BillboardGui") and d.Name == "DealerTag" then
			refreshTag(d)
		end
	end
end

------------------------------------------------------------------ turntables and bobbing boats

local function untrack(model)
	local rec = displays[model]
	if rec then
		displays[model] = nil
		for _, c in ipairs(rec.conns) do
			c:Disconnect()
		end
	end
end

-- Start animating a display model. Each part's place relative to the pivot is captured as it arrives
-- (at the server's resting position), so parts can be re-placed around the pivot every step.
local function track(model)
	local pivot = model:GetAttribute("DisplayPivot")
	if displays[model] or typeof(pivot) ~= "CFrame" or not model:IsDescendantOf(Workspace) then
		return
	end
	local rec = {
		pivot = pivot,
		phase = model:GetAttribute("DisplayPhase") or 0,
		motion = model:GetAttribute("DisplayMotion") or "Spin",
		parts = {}, rels = {}, cfs = {}, has = {}, conns = {},
	}
	local function add(d)
		if d:IsA("BasePart") and not rec.has[d] then
			rec.has[d] = true
			table.insert(rec.parts, d)
			table.insert(rec.rels, pivot:ToObjectSpace(d.CFrame))
			table.insert(rec.cfs, d.CFrame)
		end
	end
	local function remove(d)
		if rec.has[d] then
			rec.has[d] = nil
			local i = table.find(rec.parts, d)
			if i then
				table.remove(rec.parts, i)
				table.remove(rec.rels, i)
				table.remove(rec.cfs, i)
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		add(d)
	end
	table.insert(rec.conns, model.DescendantAdded:Connect(add))
	table.insert(rec.conns, model.DescendantRemoving:Connect(remove))
	table.insert(rec.conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			untrack(model) -- streamed out; it's tracked again when it streams back in
		end
	end))
	displays[model] = rec
end

local function animate()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local t = Workspace:GetServerTimeNow() -- every player sees the same angle
	for model, rec in pairs(displays) do
		if #rec.parts > 0 and (rec.pivot.Position - camPos).Magnitude < MOTION_RANGE then
			local cf
			if rec.motion == "Bob" then
				local a = (t * 1.3 + rec.phase) % TAU
				cf = rec.pivot * CFrame.new(0, math.sin(a) * 0.3, 0) * CFrame.Angles(math.sin(a * 0.5) * 0.02, 0, math.cos(a) * 0.035)
			else
				cf = rec.pivot * CFrame.Angles(0, (t * SPIN + rec.phase) % TAU, 0)
			end
			for i, rel in ipairs(rec.rels) do
				rec.cfs[i] = cf * rel
			end
			local ok = pcall(Workspace.BulkMoveTo, Workspace, rec.parts, rec.cfs, Enum.BulkMoveMode.FireCFrameChanged)
			if not ok then
				-- A part left the world mid-step: drop whatever isn't there any more.
				for i = #rec.parts, 1, -1 do
					local p = rec.parts[i]
					if not p:IsDescendantOf(Workspace) then
						rec.has[p] = nil
						table.remove(rec.parts, i)
						table.remove(rec.rels, i)
						table.remove(rec.cfs, i)
					end
				end
			end
		end
	end
end

-- Displays and tags stream in and out: pick them up whenever they arrive.
local function watchDealerships()
	local folder = Workspace:WaitForChild("Dealerships")
	local function consider(d)
		if d:IsA("Model") and d:GetAttribute("DisplayPivot") ~= nil then
			task.defer(track, d)
		elseif d:IsA("BillboardGui") and d.Name == "DealerTag" then
			task.defer(refreshTag, d)
		end
	end
	folder.DescendantAdded:Connect(consider)
	for _, d in ipairs(folder:GetDescendants()) do
		consider(d)
	end
end

------------------------------------------------------------------ start

function DealerClient.Init()
	build()
	fitToScreen()
	-- The card is laid out in its own ScreenGui's box (screenSize): fit it again when that changes, and
	-- when the camera's view does (the ScreenGui's size can follow a frame later).
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen)
	end
	ProximityPromptService.PromptTriggered:Connect(onPrompt)
	player.AttributeChanged:Connect(function(name)
		if name == "OwnedCars" or name == "CopRank" or name == "BigHeists" or string.sub(name, 1, 5) == "Pass_" then
			refreshTags()
			refresh()
		elseif name == "Cash" then
			refresh()
		elseif name == "Side" and player:GetAttribute("Side") == "Prisoner" then
			DealerClient.Close()
		end
	end)
	Remotes.OnClient("GarageResult", function(result)
		if type(result) == "table" and result.Kind == "Bought" and result.Id == openId then
			pendingUntil = 0
			tunePulseUntil = os.clock() + 3 -- TUNE IT pulses when it shows (now, or once OwnedCars arrives)
			sound("Cash")
			refresh()
		end
	end)
	task.spawn(watchDealerships)
	-- Opening the phone puts the card away. (open() closes the phone, which never makes "Body" Visible: no loop.)
	task.spawn(function()
		local body = player:WaitForChild("PlayerGui"):WaitForChild("Phone"):WaitForChild("Body")
		body:GetPropertyChangedSignal("Visible"):Connect(function()
			if body.Visible then
				DealerClient.Close()
			end
		end)
	end)
	local motionAcc, checkAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		motionAcc += dt
		checkAcc += dt
		if motionAcc >= MOTION_STEP then
			motionAcc = 0
			if next(displays) then
				animate()
			end
		end
		if checkAcc >= 0.25 then
			checkAcc = 0
			checkDistance()
		end
	end)
end

return DealerClient
