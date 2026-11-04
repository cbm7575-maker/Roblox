-- RideClient (ModuleScript, StarterPlayerScripts.Controllers.RideClient)
-- Riding together with players who aren't your crewmates or Roblox friends (RideService has the rules;
-- InteractClient's HOP IN button and VehicleVisuals' bubble do the asking at a stranger's door).
--   * INVITE (button "Invite" in ScreenGui "Ride"): shows while you sit at the wheel of your own car,
--     nearly stopped (under K.INVITE_SPEED studs/s; it stays until K.INVITE_HIDE so it doesn't blink while
--     you creep along), with the passenger seat free (no one, no taxi fare), and another player on foot
--     within K.INVITE_SHOW studs of the car, on your side, who can't hop in already (not a crewmate, a
--     Roblox friend or someone you let in this session). PC: a button with the key cap B (not I: Roblox's
--     camera takes I and O for zoom, so the game never sees them; no gamepad button is free while
--     driving, so on a gamepad the walker asks with HOP IN at the door instead). Phone: a side-column tile (+ over
--     INVITE). It takes the first side-column slot (LawClient.SideSlot, from LawClient.PlaceSlots()) that
--     CHALLENGE, END SHIFT and the cop tiles aren't using, and steps aside while DriveUI's FLIP or key
--     strip or InteractClient's car card is on its spot. B, a click or a tap invites the nearest such
--     player; it then hides until RideService answers (a few seconds), and someone who said no isn't
--     offered again for a minute.
--   * The card (ScreenGui "RideInvite", frame "RideCard"; laid out like CrewClient's invite and the race
--     challenge card: under the Banner zone, centred on the Stamp zone, between the left column and the
--     Status column): an ask ("HOP IN?", "<name> wants to hop in your car", LET IN / NO) or an invite
--     ("RIDE INVITE", "<name> invites you to hop in", HOP IN / NO THANKS). A yes lets that player ride
--     with the car's owner for the rest of the session, and sits them in the passenger seat at once when
--     they're close. The card goes after the server's seconds or when the server closes it, and steps
--     aside (keeping its time) while a HUD stamp uses its spot and on the first-join title screen.
--   * Toasts for each step (RideService "Toast" { Key, Name }: the words are in TOASTS).
-- Hidden in prison and on the title screen (player attributes Side == "Prisoner", TitleScreen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer
local STUDIO = RunService:IsStudio()

local RideClient = {}

local C = Theme.Color

local K = {
	INVITE_SHOW = 35, -- studs from your car to a player on foot for INVITE to show (the server allows 45)
	INVITE_SPEED = 16, -- studs/s: INVITE shows below this (about 10 mph on the gauge)...
	INVITE_HIDE = 24, -- ...and stays until this
	INVITE_KEY = Enum.KeyCode.B, -- (not I: the default camera zooms with I / O and swallows them)
	BUTTON_W = 150, -- PC: the INVITE button's width (a phone uses the side column's tile)
	PENDING = 4, -- seconds INVITE hides after a press, until the server's answer comes
	REFUSED = 60, -- seconds a player who said no (or didn't answer) isn't offered again
	CARD_W = 320, -- PC card width (two rows)
	CARD_W_TOUCH = 380, -- phones: one row...
	CARD_MIN_TOUCH = 330, -- ...narrowing to this before it covers the minimap
	YES_W = 76, -- phone button widths
	NO_W = 96,
	EXPIRE = 15, -- seconds a card shows when the server doesn't say
	TICK = 0.2,
	-- Pieces INVITE never covers (paths under PlayerGui), like CHALLENGE.
	CLEAR = { { "DriveUI", "Flip" }, { "DriveUI", "ControlsHint" }, { "Interact", "CarCard" } },
	-- Side-column pieces that may hold a slot while you drive: INVITE takes the first slot none of them uses.
	SLOT_USERS = {
		{ "ActivityUI", "Challenge" }, { "ActivityUI", "EndShift" },
		{ "LawUI", "Taser" }, { "LawUI", "Spikes" }, { "LawUI", "HandsUp" },
	},
}

-- RideService's toast keys, in words (%s = the other player's name) and the toast's style.
local TOASTS = {
	AskSent = { "Asked %s to let you in. Hang on...", "crew" },
	InviteSent = { "Invited %s to hop in.", "crew" },
	Pending = { "Still waiting for %s to answer.", "info" },
	Busy = { "%s has another question on screen. Try again in a moment.", "info" },
	Cooldown = { "Give %s a minute before you ask again.", "warning" },
	Away = { "%s isn't near their car.", "warning" },
	Declined = { "%s said no.", "warning" },
	Expired = { "No answer from %s.", "warning" },
	Off = { "%s left: the ride is off.", "warning" },
	LetIn = { "%s let you in: walk to the passenger door and press HOP IN.", "crew" },
	LetInSeated = { "%s let you in. Enjoy the ride!", "crew" },
	WalkOver = { "Walk to %s's car and press HOP IN.", "crew" },
	RiderSeated = { "%s hopped in.", "crew" },
	RiderComing = { "%s can hop in now.", "crew" },
}

local ui = {} -- gui, button, row, key, tile, cardGui, card
local S = {
	target = nil, -- the player INVITE would invite now
	showing = false, -- INVITE is up (for the speed hysteresis)
	pendingUntil = 0,
	refused = {}, -- [userId] = os.clock() of their no / lapse
	hinted = false,
}

local function now()
	return os.clock()
end

------------------------------------------------------------------ layout helpers

-- A Theme zone's box on a W x H screen (IgnoreGuiInset pixels): x, y, w, h.
local function zoneBox(name, touch, W, H)
	local z = Theme.Zone(name, touch)
	local w = z.Size.X.Scale * W + z.Size.X.Offset
	local h = z.Size.Y.Scale * H + z.Size.Y.Offset
	return z.Pos.X.Scale * W + z.Pos.X.Offset - z.Anchor.X * w, z.Pos.Y.Scale * H + z.Pos.Y.Offset - z.Anchor.Y * h, w, h
end

-- A piece of another ScreenGui (path under PlayerGui) while it shows: x, y, w, h in our gui's pixels.
local function liveBox(path, origin)
	local playerGui = player:FindFirstChild("PlayerGui")
	local sg = playerGui and playerGui:FindFirstChild(path[1])
	local obj = sg and sg:FindFirstChild(path[2])
	if obj and obj:IsA("GuiObject") and obj.Visible and sg:IsA("ScreenGui") and sg.Enabled then
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize
		return p.X - origin.X, p.Y - origin.Y, s.X, s.Y
	end
	return nil
end

local function overlaps(x, y, w, h, ox, oy, ow, oh)
	return ox ~= nil and ox < x + w and ox + ow > x and oy < y + h and oy + oh > y
end

-- LawClient's side column (soft: without it, no INVITE).
local function law()
	local module = script.Parent:FindFirstChild("LawClient")
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" and type(mod.SideSlot) == "function" then
		return mod
	end
	return nil
end

------------------------------------------------------------------ INVITE

-- Would RideService let `p` hop in with us already (so INVITE has nothing to offer them)? The same
-- test as CrewService.MayRide, seen from the owner's side.
local function rideable(p)
	local crew = player:GetAttribute("Crew")
	if crew ~= nil and p:GetAttribute("Crew") == crew then
		return true
	end
	local id = "," .. tostring(p.UserId) .. ","
	for _, name in ipairs({ "FriendIds", "RideIds" }) do
		local ids = player:GetAttribute(name)
		if type(ids) == "string" and string.find(ids, id, 1, true) then
			return true
		end
	end
	return STUDIO and player.UserId < 0 and p.UserId < 0 and Workspace:GetAttribute("RideAsStrangers") ~= true
end

-- Our own car while we sit at its wheel, else nil.
local function myCar()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.Health > 0 and hum.SeatPart
	local car = seat and seat.Name == "DriverSeat" and seat.Parent
	if car and car:IsA("Model") and car:GetAttribute("OwnerUserId") == player.UserId and car.PrimaryPart then
		return car
	end
	return nil
end

-- The nearest player INVITE could invite now (see the header), or nil.
local function inviteTarget()
	if player:GetAttribute("TitleScreen") == true or now() < S.pendingUntil then
		return nil
	end
	local side = player:GetAttribute("Side")
	if side == "Prisoner" then
		return nil
	end
	local car = myCar()
	local pseat = car and car:FindFirstChild("PassengerSeat")
	if not car or not (pseat and pseat:IsA("Seat")) or pseat.Occupant ~= nil or pseat:GetAttribute("NPCRider") then
		return nil
	end
	local speed = car.PrimaryPart.AssemblyLinearVelocity.Magnitude
	if speed > (S.showing and K.INVITE_HIDE or K.INVITE_SPEED) then
		return nil
	end
	-- Whoever sits in a car is out (another body's SeatPart doesn't always reach this device; the seats'
	-- Occupant does).
	local seated = {}
	local vehicles = Workspace:FindFirstChild("Vehicles")
	for _, v in ipairs(vehicles and vehicles:GetChildren() or {}) do
		for _, name in ipairs({ "DriverSeat", "PassengerSeat" }) do
			local s = v:FindFirstChild(name)
			if s and (s:IsA("Seat") or s:IsA("VehicleSeat")) and s.Occupant then
				seated[s.Occupant] = true
			end
		end
	end
	local here = car.PrimaryPart.Position
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p ~= player and p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 and not seated[hum] and hum.SeatPart == nil and not hum.Sit
			and p:GetAttribute("Side") == side and not rideable(p)
			and not (S.refused[p.UserId] and now() - S.refused[p.UserId] < K.REFUSED) then
			local d = (root.Position - here).Magnitude
			if d <= K.INVITE_SHOW and (not bestD or d < bestD) then
				best, bestD = p, d
			end
		end
	end
	return best
end

-- The key for INVITE from the last input used: "B", or nil (touch, gamepad: no key).
local function keyWord()
	local name = UserInputService:GetLastInputType().Name
	if string.sub(name, 1, 7) == "Gamepad" or Theme.IsTouch() or name == "Touch" then
		return nil
	end
	return "B"
end

local function refreshKey()
	local word = keyWord()
	local cap = ui.key
	if cap and cap.Text == word then
		return
	end
	if cap then
		cap:Destroy()
		ui.key = nil
	end
	if word then
		ui.key = Theme.Key(ui.row, word)
		ui.key.LayoutOrder = 1
	end
end

-- Into the first side-column slot nobody else holds (see the header). False when there's no column.
local function placeButton()
	local L = law()
	if not L then
		return false
	end
	local touch = Theme.IsTouch()
	local okBase, base = pcall(L.PlaceSlots)
	base = okBase and type(base) == "number" and base or 0
	local origin = ui.gui.AbsolutePosition
	local pos, size
	for i = base, base + 4 do
		local okSlot, p, s = pcall(L.SideSlot, ui.gui, i, touch)
		if not okSlot or typeof(p) ~= "Vector2" then
			return false
		end
		pos, size = p, s
		local w = touch and s.X or K.BUTTON_W
		local x = touch and p.X or (p.X + s.X - K.BUTTON_W)
		local h = touch and s.Y or 44
		local taken = false
		for _, path in ipairs(K.SLOT_USERS) do
			if overlaps(x, p.Y, w, h, liveBox(path, origin)) then
				taken = true
				break
			end
		end
		if not taken then
			break
		end
	end
	local b = ui.button
	if touch then
		b.Position = UDim2.fromOffset(pos.X, pos.Y)
		b.Size = UDim2.fromOffset(size.X, size.Y)
	else
		b.Position = UDim2.fromOffset(pos.X + size.X - K.BUTTON_W, pos.Y)
		b.Size = UDim2.fromOffset(K.BUTTON_W, 44)
	end
	ui.row.Visible = not touch
	ui.tile.Visible = touch
	return true
end

-- Is one of K.CLEAR on the button's spot right now?
local function covered()
	local origin = ui.gui.AbsolutePosition
	local b = ui.button
	local x, y, w, h = b.Position.X.Offset, b.Position.Y.Offset, b.Size.X.Offset, b.Size.Y.Offset
	for _, path in ipairs(K.CLEAR) do
		if overlaps(x, y, w, h, liveBox(path, origin)) then
			return true
		end
	end
	return false
end

local function inviteTick()
	local target = inviteTarget()
	S.target = target
	local show = target ~= nil and placeButton()
	if show then
		refreshKey()
		show = not covered()
	end
	S.showing = show
	if ui.button.Visible ~= show then
		ui.button.Visible = show
		if show and not S.hinted then
			S.hinted = true
			local key = keyWord()
			local how = key and ("press " .. key .. " (or click INVITE)") or "tap INVITE"
			NotifyController.Show("Someone's next to your car: " .. how .. " to offer them a ride!", C.Gold, "crew")
		end
	end
end

local function sendInvite()
	local target = S.target
	if not target or not ui.button.Visible then
		return
	end
	S.pendingUntil = now() + K.PENDING
	ui.button.Visible = false
	S.showing = false
	local userId = target.UserId
	task.spawn(function()
		Remotes.Event("RideInvite"):FireServer("Invite", userId)
	end)
end

local function buildButton()
	ui.gui = Instance.new("ScreenGui")
	ui.gui.Name = "Ride"
	ui.gui.ResetOnSpawn = false
	ui.gui.IgnoreGuiInset = true -- (the zone map's coordinates, like the side column)
	ui.gui.Parent = player:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton")
	b.Name = "Invite"
	b.Text = ""
	Theme.Button(b, "Quiet")
	b.Size = UDim2.fromOffset(K.BUTTON_W, 44)
	b.Visible = false
	b.Parent = ui.gui
	ui.button = b
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = b
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = row
	local word = Instance.new("TextLabel")
	word.Name = "Word"
	word.LayoutOrder = 2
	word.Size = UDim2.fromOffset(0, 22)
	word.AutomaticSize = Enum.AutomaticSize.X
	word.Text = "INVITE"
	Theme.Text(word, 17, "Display")
	word.Parent = row
	ui.row = row
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.BackgroundTransparency = 1
	tile.Size = UDim2.fromScale(1, 1)
	tile.Visible = false
	tile.Parent = b
	local plus = Instance.new("TextLabel")
	plus.Name = "Plus"
	plus.Position = UDim2.fromOffset(0, 2)
	plus.Size = UDim2.new(1, 0, 0, 22)
	plus.Text = "+"
	Theme.Text(plus, 22, "Display")
	plus.TextColor3 = C.Gold
	plus.Parent = tile
	local small = Instance.new("TextLabel")
	small.Name = "Word"
	small.Position = UDim2.new(0, 2, 1, -18)
	small.Size = UDim2.new(1, -4, 0, 14)
	small.Text = "INVITE"
	Theme.Text(small, nil, "Display")
	small.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 11
	limit.MinTextSize = 7
	limit.Parent = small
	small.Parent = tile
	ui.tile = tile
	b.Activated:Connect(sendInvite)
end

------------------------------------------------------------------ the card

-- HUDController's moment stamp: is it showing? (The card keeps out of its spot.)
local function stampUp()
	local ok, top = pcall(function()
		return HUDController.StampTop and HUDController.StampTop()
	end)
	return ok and type(top) == "number"
end

local function cardWanted()
	return player:GetAttribute("TitleScreen") ~= true and player:GetAttribute("Side") ~= "Prisoner" and not stampUp()
end

-- (see the header) Laid out like ActivityClient's race challenge card.
local function fitCard()
	local card = ui.card
	local gui = ui.cardGui
	if not card or not gui then
		return
	end
	local screen = gui.AbsoluteSize
	if screen.X < 1 then
		return
	end
	local W, H = screen.X, screen.Y
	local touch = Theme.IsTouch()
	local pad = touch and 8 or 10
	local buttonH = touch and Theme.Touch or 32
	local h = touch and (pad + buttonH + pad) or (pad + 18 + 36 + 6 + buttonH + pad)
	-- Across: right of the left column (feed; minimap on phones), left of the Status column.
	local lx, _, lw = zoneBox(touch and "Minimap" or "Feed", touch, W, H)
	local left = lx + lw + 8
	local right = zoneBox("Status", touch, W, H) - 8
	local least = touch and K.CARD_MIN_TOUCH or K.CARD_W
	if right - left < least then
		left = 12 -- too tight (small phones): cover the minimap rather than squash the words
	end
	local w = math.min(touch and K.CARD_W_TOUCH or K.CARD_W, math.max(least, right - left), W - 24)
	local x = math.clamp(W / 2, left + w / 2, math.max(left + w / 2, right - w / 2))
	-- Down: centred on the Stamp zone, under the Banner zone and above the Subtitle zone (phones: Action).
	local _, sy, _, sh = zoneBox("Stamp", touch, W, H)
	local _, by, _, bh = zoneBox("Banner", touch, W, H)
	local _, ly = zoneBox(touch and "Action" or "Subtitle", touch, W, H)
	local minTop = by + bh + 4
	local y = math.clamp(sy + sh / 2 - h / 2, minTop, math.max(minTop, ly - 4 - h))
	card.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	card.Size = UDim2.fromOffset(w, h)
	local tag, line = card:FindFirstChild("Tag"), card:FindFirstChild("Line")
	local yes, no = card:FindFirstChild("Yes"), card:FindFirstChild("No")
	if not (tag and line and yes and no) then
		return
	end
	if touch then
		-- One row: [HOP IN? / <name> wants to hop in...] .... [LET IN] [NO]
		local reserved = 14 + 10 + K.YES_W + 6 + K.NO_W + 8
		tag.TextSize = 13
		tag.Position = UDim2.fromOffset(14, 6)
		tag.Size = UDim2.new(1, -reserved, 0, 14)
		line.TextSize = 13
		line.Position = UDim2.fromOffset(14, 22)
		line.Size = UDim2.new(1, -reserved, 0, 32)
		no.AnchorPoint = Vector2.new(1, 0.5)
		no.Position = UDim2.new(1, -8, 0.5, 0)
		no.Size = UDim2.fromOffset(K.NO_W, buttonH)
		yes.AnchorPoint = Vector2.new(1, 0.5)
		yes.Position = UDim2.new(1, -(8 + K.NO_W + 6), 0.5, 0)
		yes.Size = UDim2.fromOffset(K.YES_W, buttonH)
	else
		tag.TextSize = 14
		tag.Position = UDim2.fromOffset(16, pad)
		tag.Size = UDim2.new(1, -32, 0, 16)
		line.TextSize = 15
		line.Position = UDim2.fromOffset(16, pad + 18)
		line.Size = UDim2.new(1, -32, 0, 36)
		for _, b in ipairs({ yes, no }) do
			b.AnchorPoint = Vector2.new(0, 1)
			b.Size = UDim2.new(0.5, -(16 + 4), 0, buttonH)
			b.Position = UDim2.new(b == yes and 0 or 0.5, b == yes and 16 or 4, 1, -pad)
		end
	end
end

local function closeCard()
	if ui.card then
		ui.card:Destroy()
		ui.card = nil
	end
end

local function cardButton(card, name, words, kind, yes)
	local b = Instance.new("TextButton")
	b.Name = name
	Theme.Button(b, kind)
	if kind == "Quiet" then
		b.BackgroundColor3 = C.PanelLight
		b.BackgroundTransparency = 0.15
	end
	b.TextSize = 14
	b.Text = words
	b.Parent = card
	b.Activated:Connect(function()
		local from = card:GetAttribute("From") -- (whose card this is: the server checks it)
		closeCard()
		if type(from) == "number" then
			task.spawn(function()
				Remotes.Event("RideInvite"):FireServer("Answer", from, yes)
			end)
		end
	end)
	return b
end

-- d = RideService's "Card": Kind ("Ask" | "Invite"), FromUserId, FromName, Expires.
local function showCard(d)
	if type(d) ~= "table" or type(d.FromUserId) ~= "number" then
		return
	end
	closeCard()
	local ask = d.Kind == "Ask"
	local name = tostring(d.FromName or "Someone")
	local card = Instance.new("Frame")
	card.Name = "RideCard"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Active = true -- taps on the card don't reach the world behind it
	Theme.Panel(card, 0.2)
	card:SetAttribute("From", d.FromUserId)
	card.Parent = ui.cardGui
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(0, 8)
	accent.Size = UDim2.new(0, 2, 1, -16)
	accent.BackgroundColor3 = C.Gold
	accent.BorderSizePixel = 0
	accent.Parent = card
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	Theme.Text(tag, 14, "Display")
	tag.TextColor3 = C.Gold
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Size = UDim2.new(1, -32, 0, 16)
	tag.Text = ask and "HOP IN?" or "RIDE INVITE"
	tag.Parent = card
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	Theme.Text(line, 15, "Body")
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.TextWrapped = true
	line.TextTruncate = Enum.TextTruncate.AtEnd
	line.Size = UDim2.new(1, -32, 0, 36)
	line.Text = name .. (ask and " wants to hop in your car" or " invites you to hop in")
	line.Parent = card
	cardButton(card, "Yes", ask and "LET IN" or "HOP IN", "Primary", true)
	cardButton(card, "No", ask and "NO" or "NO THANKS", "Quiet", false)
	ui.card = card
	fitCard()
	card.Visible = cardWanted()
	local seconds = math.clamp(tonumber(d.Expires) or K.EXPIRE, 1, 60)
	task.delay(seconds, function()
		if ui.card == card then
			closeCard()
		end
	end)
end

local function onEvent(kind, d)
	if kind == "Card" then
		showCard(d)
	elseif kind == "Gone" then
		if ui.card and type(d) == "table" and ui.card:GetAttribute("From") == d.FromUserId then
			closeCard()
		end
	elseif kind == "Toast" and type(d) == "table" then
		local t = TOASTS[d.Key]
		if t then
			NotifyController.Show(string.format(t[1], tostring(d.Name or "They")), nil, t[2])
		end
		-- A no or no answer to our invite: don't offer that player again for a while.
		if d.Key == "Declined" or d.Key == "Expired" then
			for _, p in ipairs(Players:GetPlayers()) do
				if p.DisplayName == d.Name then
					S.refused[p.UserId] = now()
				end
			end
		end
		if d.Key == "InviteSent" or d.Key == "AskSent" then
			S.pendingUntil = now() + K.EXPIRE -- (INVITE stays down while the card waits)
		elseif d.Key ~= "Pending" then
			S.pendingUntil = math.min(S.pendingUntil, now() + 1)
		end
	end
end

------------------------------------------------------------------ start

function RideClient.Init()
	buildButton()
	ui.cardGui = Instance.new("ScreenGui")
	ui.cardGui.Name = "RideInvite"
	ui.cardGui.ResetOnSpawn = false
	ui.cardGui.IgnoreGuiInset = true -- (the zone map's coordinates)
	ui.cardGui.DisplayOrder = 8
	ui.cardGui.Parent = player:WaitForChild("PlayerGui")
	ui.cardGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCard)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(fitCard)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(fitCard)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return -- (typing in the chat, a text box)
		end
		if input.KeyCode == K.INVITE_KEY and ui.button.Visible then
			sendInvite()
		end
	end)
	Remotes.OnClient("RideInvite", onEvent)
	task.spawn(function()
		while true do
			task.wait(K.TICK)
			local ok, err = pcall(inviteTick)
			if not ok then
				warn("[RideClient] invite: " .. tostring(err))
				task.wait(5)
			end
			if ui.card then
				local want = cardWanted()
				if ui.card.Visible ~= want then
					ui.card.Visible = want
				end
			end
		end
	end)
end

return RideClient
