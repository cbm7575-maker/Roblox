-- HouseClient (ModuleScript, StarterPlayerScripts.Controllers.HouseClient)
-- The client side of homes (Config.Housing; HousingService on the server decides everything), in the
-- flat "street" look (Shared.Util.Theme):
--   * Front-door prompts read "Enter home" at your own home and "View / Buy $X" elsewhere, and your
--     home's street sign says YOUR HOME (local changes to the server's prompt and sign text; the sign
--     keeps the neon colours of the server's sign art).
--   * The buy card (HouseCard remote), a menu panel: the home's name in Display with its price on the
--     right (cash green), garage size and where you spawn, the blurb, a thin rule, what your old home
--     sells back for (gold), and BUY / MOVE IN, TOUR and CANCEL. Key caps on the buttons: ENTER / V / X
--     on a keyboard, Y / D-PAD (its right side) / B on a gamepad (none on touch, and none on BUY while you
--     can't afford it, when it reads NEED $X MORE). BUY asks the server (RequestHouse "Buy"), TOUR for a
--     look round the inside first (RequestHouse "Tour": not while wanted). The keys never act while you
--     sit (in a car Y is NITRO and B is EXIT) or from behind Roblox's own menu (there Y is Reset
--     Character). On a PC: top-left under Roblox's top bar, over the Coast Feed column and above the
--     toast stack (a full stack can just touch its bottom edge on a 720 px tall window), the three
--     buttons in a row; Roblox's chat window, which sits there and draws over everything, hides while
--     the card is open. On a phone: centred, TOUR on a row of its own above CANCEL on the left (nearest
--     the thumbstick) and BUY on the right. Walking away from the door or sitting down closes it.
--   * Tours (player attribute Touring = the home id, InHome is set too): a toast says what to do, and
--     the show home's FOR SALE stand sends the same card with At = the stand. That card has no TOUR
--     (BUY | CANCEL as before, on a 360 px card) and closes on walking away from the stand instead.
--   * A quick fade to black around door teleports (HouseFade), no rain indoors (a home, or a penthouse
--     room: InApartment), and a stamp when you buy (HouseResult).
--   * Inside (player attribute InHome, your own home or a tour): a LEAVE tile (button "LeaveHome": a
--     door glyph over the word) in the side column under the Buttons zone, the top slot
--     (LawClient.SideSlot; WardrobeUI's OUTFIT tile sits under it). Hidden while the first-join title
--     screen is up (attribute TitleScreen). WardrobeUI switches the whole "House" ScreenGui off while
--     its dressing room is open.
-- For the phone and minimap: HouseClient.HomePosition() -> your front door (Vector3) or nil,
-- HouseClient.HomeName() -> string or nil, HouseClient.Homes() -> every property (for a list),
-- HouseClient.RouteTo(id) -> GPS route to a property's door (your own home if id is nil).
-- For CombatClient: HouseClient.IsOpen() -> the buy card is up (no gun out, no punches behind it).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Housing = require(ReplicatedStorage.Shared.Config.Housing)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local HouseClient = {}

local C = Theme.Color
-- The street signs are world art (the server builds them in its neon palette): their sub line keeps it.
local SIGN_MINE = Color3.fromRGB(110, 242, 196)
local SIGN_SALE = Color3.fromRGB(255, 214, 10)
local CARD_PAD = 18
local CARD_W = 360 -- PC; on a phone 42% of the width, 300-360
-- PC, with BUY | TOUR | CANCEL in one row (its right edge, at x 416, stays left of the Banner zone on a
-- 1280 px wide window)
local CARD_W_TOUR = 392

local gui, curtain, card, buyButton, tourButton, cancelButton, leaveButton
-- The home the buy card is showing, and the server's info (trade-in; At = the FOR SALE stand on a tour)
local cardHome, cardInfo
local canBuy = false
local chatHidden = false -- the card hid Roblox's chat window (PC), to show again when it closes
local fadeToken = 0
local hinted = false
local caps = {} -- the buttons' key caps: { Cap, Keyboard, Gamepad, Pad, Button }
local prompts = setmetatable({}, { __mode = "k" }) -- front-door prompts seen in Workspace.Homes
local signs = setmetatable({}, { __mode = "k" }) -- street sign boards seen in Workspace.Homes

local money = HUDController.Money

local function myHome()
	return Housing.ById[player:GetAttribute("Home") or ""]
end

local function sound(name)
	task.spawn(function()
		local ok, SoundClient = pcall(require, script.Parent:WaitForChild("SoundClient"))
		if ok and SoundClient and SoundClient.Play then
			pcall(SoundClient.Play, name)
		end
	end)
end

-- "keyboard", "gamepad" or "touch": which key caps (if any) to show.
local function inputMode()
	local name = UserInputService:GetLastInputType().Name
	if string.sub(name, 1, 7) == "Gamepad" then
		return "gamepad"
	elseif name == "Touch" or Theme.IsTouch() then
		return "touch"
	end
	return "keyboard"
end

local function label(parent, name, size, kind)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = ""
	Theme.Text(l, size, kind)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(parent, name, text)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	Theme.Button(b, "Quiet")
	b.FontFace = Theme.Font.Display
	b.TextSize = 18
	b.Parent = parent
	return b
end

-- A key cap at the left inside a button; the button's word moves right of it while it shows.
local function cap(b, keyboard, gamepad)
	local k = Theme.Key(b, keyboard)
	k.AnchorPoint = Vector2.new(0, 0.5)
	k.ZIndex = 3
	local pad = Instance.new("UIPadding")
	pad.Parent = b
	table.insert(caps, { Cap = k, Keyboard = keyboard, Gamepad = gamepad, Pad = pad, Button = b })
	return k
end

local function refreshCaps()
	local mode = inputMode()
	for _, c in ipairs(caps) do
		local text = (mode == "keyboard" and c.Keyboard) or (mode == "gamepad" and c.Gamepad) or nil
		if c.Button == buyButton and not canBuy then
			text = nil -- nothing to press it for
		end
		c.Cap.Visible = text ~= nil
		if text and c.Cap.Text ~= text then
			c.Cap.Text = text
			c.Cap.Size = UDim2.fromOffset(math.max(22, 10 + #text * 9), 22) -- (as Theme.Key sizes it)
		end
		-- The padding moves the cap too (a child), so its own offset takes that back off.
		local padLeft = text and c.Cap.Size.X.Offset + 14 or 0
		c.Pad.PaddingLeft = UDim.new(0, padLeft)
		c.Cap.Position = UDim2.new(0, 8 - padLeft, 0.5, 0)
	end
end

-- Buy card ----------------------------------------------------------------------------------------------

local function closeCard()
	cardHome, cardInfo = nil, nil
	if card then
		card.Visible = false
	end
	if chatHidden then
		chatHidden = false
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, true)
	end
end

-- The FOR SALE stand this card came from (on a tour), else nil.
local function cardStand()
	local at = cardInfo and cardInfo.At
	return typeof(at) == "Vector3" and at or nil
end

-- Top-left on a PC, centred on a phone (clear of the thumbstick); buttons Theme.Touch tall there.
local function placeCard()
	local touch = Theme.IsTouch()
	local withTour = cardStand() == nil -- (no TOUR at the stand: you're on it)
	local w = (withTour and not touch) and CARD_W_TOUR or CARD_W
	if touch then
		local vp = Workspace.CurrentCamera.ViewportSize
		w = math.clamp(math.floor(vp.X * 0.42), 300, 360)
	end
	local btnH = touch and Theme.Touch or 40
	local inner = w - CARD_PAD * 2
	local half = math.floor((inner - 8) / 2)
	-- BUY on the left and CANCEL on the right; on a phone the other way round, so a left thumb coming
	-- down to steer (Roblox's thumbstick starts wherever it lands on the left) meets CANCEL, never BUY.
	local leftX, rightX, rightW = CARD_PAD, CARD_PAD + half + 8, inner - half - 8
	local buyX, buyW, cancelX, cancelW = leftX, half, rightX, rightW
	if touch then
		buyX, buyW, cancelX, cancelW = rightX, rightW, leftX, half
	end
	local rowY = 200
	tourButton.Visible = withTour
	if withTour and touch then
		-- Phone: TOUR on its own row above, so the bottom row stays CANCEL (thumb side) | BUY and NEED
		-- $X MORE keeps its half.
		tourButton.Position = UDim2.fromOffset(CARD_PAD, rowY)
		tourButton.Size = UDim2.fromOffset(inner, btnH)
		rowY += btnH + 8
	elseif withTour then
		-- PC: BUY | TOUR | CANCEL, BUY the widest (its ENTER cap, MOVE IN, NEED $X MORE).
		local small = math.floor((inner - 16) * 0.3)
		buyW = inner - 16 - small * 2
		tourButton.Position = UDim2.fromOffset(CARD_PAD + buyW + 8, rowY)
		tourButton.Size = UDim2.fromOffset(small, btnH)
		buyX, cancelX, cancelW = CARD_PAD, CARD_PAD + buyW + 8 + small + 8, small
	end
	buyButton.Position = UDim2.fromOffset(buyX, rowY)
	buyButton.Size = UDim2.fromOffset(buyW, btnH)
	cancelButton.Position = UDim2.fromOffset(cancelX, rowY)
	cancelButton.Size = UDim2.fromOffset(cancelW, btnH)
	card.Size = UDim2.fromOffset(w, rowY + btnH + CARD_PAD)
	if touch then
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
	else
		-- Under Roblox's top bar, so it ends above the toast stack (which grows up from above the
		-- minimap, never past 42% of the screen). The chat window up there hides while it's open.
		card.AnchorPoint = Vector2.zero
		card.Position = UDim2.fromOffset(24, Theme.TopBar + 8)
	end
end

local function refreshCard()
	local home = cardHome
	if not home then
		return
	end
	local old = cardInfo and Housing.ById[cardInfo.OldId or ""]
	local refund = old and (tonumber(cardInfo.Refund) or Housing.Refund(old)) or 0
	local net = home.Price - refund
	card.Title.Text = home.Name
	card.Price.Text = money(home.Price)
	-- HousingService only spawns Civilians at home (cops keep the police spawn), so say so to everyone else.
	local civ = (player:GetAttribute("Side") or "Civilian") == "Civilian"
	card.Info.Text = "Garage for " .. home.GarageSlots .. " cars  ·  " .. (civ and "You spawn here" or "Citizens spawn here")
	card.Blurb.Text = home.Blurb or ""
	if old and net >= 0 then
		card.Trade.Text = "Moving? Your " .. old.Name .. " sells back for " .. money(refund) .. " (half price), so you pay " .. money(net) .. "."
		card.Trade.TextColor3 = C.Gold
	elseif old then
		card.Trade.Text = "Moving? Your " .. old.Name .. " sells back for " .. money(refund) .. " (half price): you get " .. money(-net) .. " back."
		card.Trade.TextColor3 = C.Gold
	else
		card.Trade.Text = "One home at a time. It's yours every time you come back."
		card.Trade.TextColor3 = C.Dim
	end
	local short = math.max(net, 0) - (player:GetAttribute("Cash") or 0)
	canBuy = short <= 0
	if canBuy then
		buyButton.Text = old and "MOVE IN" or "BUY"
		Theme.Button(buyButton, "Primary")
	else
		buyButton.Text = "NEED " .. money(short) .. " MORE"
		Theme.Button(buyButton, "Quiet")
		buyButton.AutoButtonColor = false
		buyButton.TextColor3 = C.Dim
	end
	buyButton.FontFace = Theme.Font.Display -- (sized to fit, 13-18 px: see buildCard)
	-- The white key cap turns dark on the white BUY button.
	local buyCap = buyButton:FindFirstChild("Key")
	if buyCap then
		buyCap.BackgroundColor3 = canBuy and C.Panel or Color3.fromRGB(245, 245, 245)
		buyCap.TextColor3 = canBuy and C.Text or Color3.fromRGB(12, 14, 18)
	end
	refreshCaps()
end

local function openCard(home, info)
	cardHome, cardInfo = home, info
	placeCard()
	refreshCard()
	card.Visible = true
	-- PC: Roblox's chat window sits top-left, over the card (it draws above every ScreenGui).
	if not Theme.IsTouch() and not chatHidden and StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat) then
		chatHidden = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, false)
	end
	sound("Click")
end

local function buy()
	local home = cardHome
	if not home or not canBuy then
		return
	end
	closeCard()
	Remotes.Event("RequestHouse"):FireServer("Buy", home.Id)
end

-- TOUR: the server takes you round a show copy of the inside (it checks the rest: at the door, on
-- foot, citizen or cop). Wanted is said here, in words that fit a tour.
local function tour()
	local home = cardHome
	if not home or not tourButton.Visible then
		return
	end
	closeCard()
	if (player:GetAttribute("Heat") or 0) > 0 then
		NotifyController.Show("Lose the cops first! No home tours while you're wanted.", nil, "police")
		return
	end
	Remotes.Event("RequestHouse"):FireServer("Tour", home.Id)
end

local function buildCard()
	card = Instance.new("Frame")
	card.Name = "BuyCard"
	card.Active = true
	Theme.Panel(card, 0.18)
	card.Visible = false
	card.Parent = gui
	-- The brand's thin pink accent, top-left.
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(CARD_PAD, 0)
	accent.Size = UDim2.fromOffset(40, 2)
	accent.BackgroundColor3 = C.Brand
	accent.BorderSizePixel = 0
	accent.Parent = card
	-- Name (left) and price (right) on one row.
	local title = label(card, "Title", nil, "Display")
	title.TextScaled = true
	title.Position = UDim2.fromOffset(CARD_PAD, 14)
	title.Size = UDim2.new(1, -(CARD_PAD * 2 + 116), 0, 30)
	local fit = Instance.new("UITextSizeConstraint")
	fit.MinTextSize = 16
	fit.MaxTextSize = 24
	fit.Parent = title
	local price = label(card, "Price", 22, "Display")
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.TextColor3 = C.Cash
	price.AnchorPoint = Vector2.new(1, 0)
	price.Position = UDim2.new(1, -CARD_PAD, 0, 15)
	price.Size = UDim2.fromOffset(110, 28)
	local info = label(card, "Info", 14, "Body")
	info.TextColor3 = C.Dim
	info.Position = UDim2.fromOffset(CARD_PAD, 50)
	info.Size = UDim2.new(1, -CARD_PAD * 2, 0, 18)
	info.TextTruncate = Enum.TextTruncate.AtEnd
	local blurb = label(card, "Blurb", 14, "Body")
	blurb.TextWrapped = true
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.Position = UDim2.fromOffset(CARD_PAD, 76)
	blurb.Size = UDim2.new(1, -CARD_PAD * 2, 0, 52) -- three lines at most
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Position = UDim2.fromOffset(CARD_PAD, 136)
	rule.Size = UDim2.new(1, -CARD_PAD * 2, 0, 1)
	rule.BackgroundColor3 = C.Text
	rule.BackgroundTransparency = 0.8
	rule.BorderSizePixel = 0
	rule.Parent = card
	local trade = label(card, "Trade", 13, "Body")
	trade.TextWrapped = true
	trade.TextYAlignment = Enum.TextYAlignment.Top
	trade.Position = UDim2.fromOffset(CARD_PAD, 146)
	trade.Size = UDim2.new(1, -CARD_PAD * 2, 0, 48) -- three lines at most
	buyButton = button(card, "Buy", "BUY")
	-- "NEED $110,000 MORE" has to fit half the card on a phone: the text shrinks, never under 13 px.
	buyButton.TextScaled = true
	local buyFit = Instance.new("UITextSizeConstraint")
	buyFit.MinTextSize = 13
	buyFit.MaxTextSize = 18
	buyFit.Parent = buyButton
	cap(buyButton, "ENTER", "Y")
	-- TOUR (the middle of the PC row): its gamepad cap is wide, so the word may shrink a little.
	tourButton = button(card, "Tour", "TOUR")
	tourButton.TextScaled = true
	local tourFit = Instance.new("UITextSizeConstraint")
	tourFit.MinTextSize = 13
	tourFit.MaxTextSize = 18
	tourFit.Parent = tourButton
	cap(tourButton, "V", "D-PAD")
	cancelButton = button(card, "Cancel", "CANCEL")
	cap(cancelButton, "X", "B")
	buyButton.Activated:Connect(buy)
	tourButton.Activated:Connect(tour)
	cancelButton.Activated:Connect(closeCard)
	placeCard()
	refreshCaps()
	-- Walking away from the door closes the card: just inside the server's buy range (Housing.DoorRange),
	-- so BUY is only offered where the server accepts it (a late press gets the HomeTooFar message).
	-- On a tour the same range is measured from the FOR SALE stand. Sitting down (getting in the car on
	-- the driveway) closes it too.
	local lastCheck = 0
	RunService.Heartbeat:Connect(function()
		if not cardHome or os.clock() - lastCheck < 0.25 then
			return
		end
		lastCheck = os.clock()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local at = cardStand() or Housing.DoorPosition(cardHome)
		if not root or (hum and hum.SeatPart) or (root.Position - at).Magnitude > Housing.DoorRange - 1 then
			closeCard()
		end
	end)
	-- ENTER / gamepad Y buys, V / D-pad right tours, X / gamepad B closes, while the card is up.
	-- (V and D-pad right change radio station only while driving; T would be a cop's taser. D-pad left
	-- is not used: on foot, holding it opens WeaponWheel, which would pop up as this card closes.)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not cardHome then
			return
		end
		-- Seated: Y is NITRO and B is EXIT, never BUY / CANCEL. (The check above only runs every 0.25 s.)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonB then
			closeCard() -- (closing is always safe)
			return
		end
		-- Never buy from behind Roblox's own menu (its Y is "Reset Character") or a key something else took.
		if processed or GuiService.MenuIsOpen then
			return
		end
		if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonY then
			buy()
		elseif key == Enum.KeyCode.V or key == Enum.KeyCode.DPadRight then
			tour() -- (does nothing on the stand's card, which has no TOUR)
		elseif key == Enum.KeyCode.X then
			closeCard()
		end
	end)
end

-- Fade and the LEAVE tile ---------------------------------------------------------------------------------

local function fadeTo(black)
	fadeToken += 1
	local token = fadeToken
	TweenService:Create(curtain, TweenInfo.new(black and 0.3 or 0.45), { BackgroundTransparency = black and 0 or 1 }):Play()
	if black then
		-- Never leave the screen black if the "In" message goes missing.
		task.delay(4, function()
			if fadeToken == token then
				fadeTo(false)
			end
		end)
	end
end

-- One white stroke of a glyph, centred on (cx, cy) inside the glyph box, turned `rot` degrees.
local function glyphStroke(parent, w, h, cx, cy, rot)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(cx, cy)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	f.BackgroundColor3 = C.Text
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = parent
	return f
end

-- A door (outline and knob) with an arrow leaving it to the right.
local function doorGlyph(g)
	local door = glyphStroke(g, 11, 17, 8.5, 10)
	door.BackgroundTransparency = 1
	Theme.Corners(door, 1)
	local frame = Instance.new("UIStroke")
	frame.Color = C.Text
	frame.Thickness = 2
	frame.Parent = door
	glyphStroke(g, 2.5, 2.5, 11, 10.5)
	glyphStroke(g, 8, 2, 19, 10)
	glyphStroke(g, 5, 2, 21.5, 8.4, 45)
	glyphStroke(g, 5, 2, 21.5, 11.6, -45)
end

-- Same tile recipe as LawClient's TASER / SPIKES and WardrobeUI's OUTFIT.
local function buildLeave()
	leaveButton = Instance.new("TextButton")
	leaveButton.Name = "LeaveHome"
	leaveButton.Size = UDim2.fromOffset(52, 52)
	leaveButton.Text = "LEAVE"
	Theme.Button(leaveButton, "Quiet")
	leaveButton.FontFace = Theme.Font.Display
	leaveButton.TextSize = 13
	leaveButton.TextYAlignment = Enum.TextYAlignment.Bottom
	leaveButton.Visible = false
	Theme.Shadow(leaveButton)
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = leaveButton
	local g = Instance.new("Frame")
	g.Name = "Glyph"
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.new(0.5, 0, 0, 5)
	g.Size = UDim2.fromOffset(24, 20)
	g.BackgroundTransparency = 1
	g.Parent = leaveButton
	doorGlyph(g)
	leaveButton.Parent = gui
	leaveButton.Activated:Connect(function()
		Remotes.Event("RequestHouse"):FireServer("Leave")
	end)
end

-- The top slot of the side column.
local function placeLeave()
	local touch = Theme.IsTouch()
	local ok, pos, size = false, nil, nil
	local module = script.Parent:FindFirstChild("LawClient")
	local okLaw, LawClient = false, nil
	if module then
		okLaw, LawClient = pcall(require, module)
	end
	if okLaw and type(LawClient) == "table" and LawClient.SideSlot then
		ok, pos, size = pcall(LawClient.SideSlot, gui, 0, touch)
	end
	if not ok or typeof(pos) ~= "Vector2" or typeof(size) ~= "Vector2" then
		-- (LawClient missing: a rough spot under the PC Buttons zone)
		local s = gui.AbsoluteSize
		pos, size = Vector2.new(s.X - 72, s.Y * 0.5 + 66), Vector2.new(52, 52)
	end
	leaveButton.Position = UDim2.fromOffset(pos.X, pos.Y)
	leaveButton.Size = UDim2.fromOffset(size.X, size.Y)
end

local function showLeave()
	leaveButton.Visible = player:GetAttribute("InHome") == true and player:GetAttribute("TitleScreen") ~= true
	if leaveButton.Visible then
		placeLeave()
	end
end

local function buildScreens()
	gui = Instance.new("ScreenGui")
	gui.Name = "House"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 9
	gui.Parent = player:WaitForChild("PlayerGui")

	local fadeGui = Instance.new("ScreenGui")
	fadeGui.Name = "HouseFade"
	fadeGui.ResetOnSpawn = false
	fadeGui.IgnoreGuiInset = true
	fadeGui.DisplayOrder = 60 -- over everything
	fadeGui.Parent = gui.Parent
	curtain = Instance.new("Frame")
	curtain.Name = "Curtain"
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.BorderSizePixel = 0
	curtain.BackgroundColor3 = Color3.new(0, 0, 0)
	curtain.BackgroundTransparency = 1
	curtain.Parent = fadeGui

	buildLeave()
end

-- SkyClient's rain follows the camera and falls through any roof: switch it off indoors, in a home or in
-- a penthouse room (ApartmentService's InApartment). SkyClient only ever changes its rate.
local function indoorRain()
	local camera = Workspace.CurrentCamera
	local cloud = camera and camera:FindFirstChild("RainCloud")
	local rain = cloud and cloud:FindFirstChild("Rain")
	if rain then
		rain.Enabled = player:GetAttribute("InHome") ~= true and player:GetAttribute("InApartment") == nil
	end
end

local function onInHome()
	local inHome = player:GetAttribute("InHome") == true
	showLeave()
	indoorRain()
	if inHome then
		closeCard()
		-- (The server sets Touring before InHome: a tour gets its own toast, onTouring.)
		if not hinted and player:GetAttribute("Touring") == nil then
			hinted = true
			NotifyController.Show("Welcome home! Pick a car in the garage, or use the glowing door to go out.", nil, "info")
		end
	end
end

-- A tour starts (Touring = a home id) or ends (nil: left, bought it, respawned). A card from the stand
-- of a tour that's over closes.
local function onTouring()
	local home = Housing.ById[player:GetAttribute("Touring") or ""]
	if cardStand() and cardHome ~= home then
		closeCard()
	end
	if home then
		NotifyController.Show("Welcome to the " .. home.Name .. "! Look around, buy it at the FOR SALE stand, or LEAVE by the front door.", nil, "info")
	end
end

-- Door prompts and street signs ------------------------------------------------------------------------------

local function dressPrompt(prompt)
	local home = Housing.ById[prompt:GetAttribute("HomeId") or ""]
	if home then
		prompt.ActionText = player:GetAttribute("Home") == home.Id and "Enter home" or ("View / Buy " .. money(home.Price))
	end
end

local function dressSign(board)
	local home = Housing.ById[board:GetAttribute("HomeId") or ""]
	local signGui = board:FindFirstChild("SignGui")
	local sub = signGui and signGui:FindFirstChild("Sub")
	if not home or not sub then
		return
	end
	if player:GetAttribute("Home") == home.Id then
		sub.Text = "★ YOUR HOME ★"
		sub.TextColor3 = SIGN_MINE
	else
		sub.Text = "FOR SALE · " .. money(home.Price)
		sub.TextColor3 = SIGN_SALE
	end
end

-- Houses stream in and out: dress each prompt and sign as it arrives.
local function track(inst)
	if inst:IsA("ProximityPrompt") and inst.Name == "HomeDoor" then
		prompts[inst] = true
		dressPrompt(inst)
	elseif inst:IsA("TextLabel") and inst.Name == "Sub" then
		local board = inst.Parent and inst.Parent.Parent
		if board and board:IsA("BasePart") and board.Name == "HomeSign" then
			signs[board] = true
			dressSign(board)
		end
	end
end

local function redressAll()
	for prompt in pairs(prompts) do
		dressPrompt(prompt)
	end
	for board in pairs(signs) do
		dressSign(board)
	end
end

-- Public -----------------------------------------------------------------------------------------------------

-- Is the buy card up? CombatClient asks: it puts a gun down behind the card, so the mouse is free for
-- BUY / CANCEL (with a pistol out it stayed locked to the crosshair, and the click fired instead).
function HouseClient.IsOpen()
	return cardHome ~= nil and card ~= nil and card.Visible
end

function HouseClient.HomePosition()
	local home = myHome()
	return home and Housing.DoorPosition(home) or nil
end

function HouseClient.HomeName()
	local home = myHome()
	return home and home.Name or nil
end

-- Every property: { Id, Name, Price, GarageSlots, Blurb, Position (front door), Owned }.
function HouseClient.Homes()
	local list = {}
	for _, home in ipairs(Housing.List) do
		table.insert(list, {
			Id = home.Id,
			Name = home.Name,
			Price = home.Price,
			GarageSlots = home.GarageSlots,
			Blurb = home.Blurb,
			Position = Housing.DoorPosition(home),
			Owned = player:GetAttribute("Home") == home.Id,
		})
	end
	return list
end

-- GPS to a property's front door (your own home when id is nil). Returns true if a route was set.
function HouseClient.RouteTo(id)
	local home = Housing.ById[id or ""] or myHome()
	if not home then
		return false
	end
	local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
	GPSClient.SetTarget(player:GetAttribute("Home") == home.Id and "Home" or home.Name, Housing.DoorPosition(home))
	return true
end

function HouseClient.Init()
	buildScreens()
	buildCard()
	onInHome()
	player:GetAttributeChangedSignal("InHome"):Connect(onInHome)
	player:GetAttributeChangedSignal("InApartment"):Connect(indoorRain)
	player:GetAttributeChangedSignal("Touring"):Connect(onTouring)
	player:GetAttributeChangedSignal("TitleScreen"):Connect(showLeave)
	player:GetAttributeChangedSignal("Home"):Connect(function()
		redressAll()
		if cardHome then
			closeCard() -- the card's trade-in numbers are out of date
		end
	end)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if cardHome then
			refreshCard()
		end
	end)
	-- Re-place for a new screen size or a new kind of input (phone layout, key caps).
	local lastMode = inputMode()
	local function replace()
		placeCard()
		refreshCaps()
		showLeave()
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(replace)
	UserInputService.LastInputTypeChanged:Connect(function()
		local mode = inputMode()
		if mode ~= lastMode then
			lastMode = mode
			replace()
		end
	end)
	-- The LEAVE tile's slot follows the jump button (LawClient.SideSlot measures it).
	local lastPlace = 0
	RunService.Heartbeat:Connect(function()
		if leaveButton.Visible and os.clock() - lastPlace > 0.5 then
			lastPlace = os.clock()
			placeLeave()
		end
	end)

	Remotes.OnClient("HouseCard", function(info)
		if type(info) ~= "table" then
			return
		end
		local home = Housing.ById[info.Id or ""]
		if not home then
			return
		end
		-- Indoors only from the FOR SALE stand of the home on tour (At); outside, never with an At.
		local touring = player:GetAttribute("InHome") == true and player:GetAttribute("Touring") == home.Id
		if player:GetAttribute("InHome") and not (touring and typeof(info.At) == "Vector3") then
			return
		end
		if not touring then
			info.At = nil
		end
		openCard(home, info)
	end)
	Remotes.OnClient("HouseResult", function(info)
		if type(info) ~= "table" or info.Kind ~= "Bought" then
			return
		end
		local home = Housing.ById[info.Id or ""]
		if not home then
			return
		end
		closeCard()
		HUDController.Stamp("HOME SWEET HOME", "The " .. home.Name .. " is yours", C.Gold)
		sound("Success")
		local refund = tonumber(info.Refund) or 0
		if refund > 0 then
			NotifyController.Show("Your old home sold back for " .. money(refund) .. ".", C.Cash, "money")
		end
		if player:GetAttribute("InHome") == true then
			-- Bought on the tour: the show home is already yours, garage and all.
			hinted = true
			NotifyController.Show("Welcome home! Your cars are in the garage now: pick one to drive out.", nil, "info")
		else
			NotifyController.Show("Press Enter home at the door: your cars wait in its garage!", nil, "info")
		end
	end)
	Remotes.OnClient("HouseFade", function(phase)
		if phase == "Out" then
			closeCard()
			sound("Door")
			fadeTo(true)
		else
			fadeTo(false)
		end
	end)

	-- The Homes folder is made by the server at start-up; wait for it off the main thread.
	task.spawn(function()
		local homes = Workspace:WaitForChild("Homes")
		homes.DescendantAdded:Connect(track)
		for _, d in ipairs(homes:GetDescendants()) do
			track(d)
		end
	end)
end

return HouseClient
