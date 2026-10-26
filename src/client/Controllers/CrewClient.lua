-- CrewClient (ModuleScript, StarterPlayerScripts.Controllers.CrewClient)
-- Crew invites, crewmate name tags and the friend-bonus toast, in the flat "street" look (Theme). The
-- phone's CREW app sends invites; the minimap draws crewmates (MinimapClient).
--   * Invite (CrewInvite from CrewService, which sends it at any time): frame "CrewInvite" in ScreenGui
--     "Crew", a flat dark card in the upper middle: centred on the Stamp zone, between the left column
--     and the Status column, always UNDER the Banner zone (the mission timer and QUIT, the escape
--     countdown and the prison timer live there; it never covers them) and above the Subtitle zone
--     (phones: the Action zone), so never over the car cluster or GET IN either. A thin brand-pink
--     accent, a small gold CREW INVITE tag, "<name> wants you in their crew", JOIN ("Accept", the
--     primary button) and NO THANKS ("Decline"). PC: two rows, the buttons under the words. Phones: one
--     60 px row (it fits between the Banner and Action zones on a 375 px-tall phone), the words on the
--     left, Theme.Touch-tall buttons on the right; where the band between the columns is too narrow
--     (667 px-wide phones) it keeps to the right and covers the minimap's right part.
--     It goes after 60 s, steps aside while a HUDController stamp shows (same spot) and on the title
--     screen, and is re-placed when the screen size or input type changes. OfferClient's pass card
--     waits while it's up.
--   * Name tags over crewmates' heads (BillboardGui "CrewTag", through walls, local only): the name in
--     small white Body text with a soft shadow and a thin pink bar under it (crew = the brand accent).
--     Hidden on the first-join title screen (local attribute TitleScreen, set by TeamUI).
--   CrewClient.Crewmates() -> the other players in your crew

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local CrewClient = {}

local C = Theme.Color

local CARD_W = 320 -- PC: two rows
local CARD_W_TOUCH, MIN_W_TOUCH = 380, 330 -- phones: one row (it narrows to MIN_W_TOUCH before covering the minimap)
local JOIN_W, NO_W = 64, 92 -- phone button widths
local GAP = 8 -- pixels kept from the zones beside the card
local GAP_Y = 4 -- ...and above / below it
local EDGE = 12
local INVITE_FOR = 60 -- seconds before an unanswered invite goes
local TAGS_EVERY = 1 -- seconds between name tag checks
local CHECK_EVERY = 0.2 -- seconds between checks for a stamp over the card

local gui, card
local tags = {} -- [player] = BillboardGui

function CrewClient.Crewmates()
	local list = {}
	local crew = player:GetAttribute("Crew")
	if not crew then
		return list
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p:GetAttribute("Crew") == crew then
			table.insert(list, p)
		end
	end
	return list
end

local function tagFor(p)
	local head = p.Character and p.Character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local tag = tags[p]
	if tag and tag.Parent == head then
		return tag
	end
	if tag then
		tag:Destroy()
	end
	tag = Instance.new("BillboardGui")
	tag.Name = "CrewTag"
	tag.Size = UDim2.fromOffset(160, 24)
	tag.StudsOffset = Vector3.new(0, 2.6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 1500
	tag.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	Theme.Text(name, 14, "Body")
	name.Size = UDim2.new(1, 0, 0, 18)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = p.DisplayName
	name.Parent = tag
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 20)
	bar.Size = UDim2.fromOffset(24, 2)
	bar.BackgroundColor3 = C.Brand
	bar.BorderSizePixel = 0
	bar.Parent = tag
	tag.Adornee = head
	tag.Parent = head -- a local instance: only this player sees it
	tags[p] = tag
	return tag
end

local function refreshTags()
	local title = player:GetAttribute("TitleScreen") == true
	local mates = {}
	for _, p in ipairs(CrewClient.Crewmates()) do
		mates[p] = true
		local tag = tagFor(p)
		if tag then
			tag.Enabled = not title
		end
	end
	for p, tag in pairs(tags) do
		if not mates[p] then
			tag:Destroy()
			tags[p] = nil
		end
	end
end

-- A zone's box on this screen: x, y, width, height (pixels).
local function zoneBox(name, touch, screen)
	local z = Theme.Zone(name, touch)
	local w = z.Size.X.Scale * screen.X + z.Size.X.Offset
	local h = z.Size.Y.Scale * screen.Y + z.Size.Y.Offset
	return z.Pos.X.Scale * screen.X + z.Pos.X.Offset - z.Anchor.X * w, z.Pos.Y.Scale * screen.Y + z.Pos.Y.Offset - z.Anchor.Y * h, w, h
end

-- Size and place the card for this screen (see the header; OfferClient's card uses the same band).
local function fitCard()
	if not card then
		return
	end
	local screen = gui.AbsoluteSize
	if screen.X < 1 then
		return
	end
	local touch = Theme.IsTouch()
	local pad = touch and 8 or 10
	local buttonH = touch and Theme.Touch or 32
	local h = touch and (pad + buttonH + pad) or (pad + 18 + 36 + 6 + buttonH + pad) -- 60 on phones, 112 on a PC
	-- Across: right of the left column (feed; minimap on phones), left of the Status column.
	local lx, _, lw = zoneBox(touch and "Minimap" or "Feed", touch, screen)
	local left = lx + lw + GAP
	local right = zoneBox("Status", touch, screen) - GAP
	local least = touch and MIN_W_TOUCH or CARD_W
	local band = right - left
	if band < least then
		left = EDGE -- too tight (small phones): cover the minimap rather than squash the words
	end
	local w = math.min(touch and CARD_W_TOUCH or CARD_W, math.max(least, band), screen.X - 2 * EDGE)
	local x = math.clamp(screen.X / 2, left + w / 2, math.max(left + w / 2, right - w / 2))
	-- Down: centred on the Stamp zone, but under the Banner zone (which sits under the Goal zone) and
	-- above the Subtitle zone (phones: the Action zone).
	local _, sy, _, sh = zoneBox("Stamp", touch, screen)
	local _, by, _, bh = zoneBox("Banner", touch, screen)
	local _, ly = zoneBox(touch and "Action" or "Subtitle", touch, screen)
	local minTop = by + bh + GAP_Y
	local y = math.clamp(sy + sh / 2 - h / 2, minTop, math.max(minTop, ly - GAP_Y - h))
	card.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	card.Size = UDim2.fromOffset(w, h)
	local tagLabel, line = card:FindFirstChild("Tag"), card:FindFirstChild("Line")
	local accept, decline = card:FindFirstChild("Accept"), card:FindFirstChild("Decline")
	if touch then
		-- One row: [CREW INVITE / <name> wants you in their crew] .... [JOIN] [NO THANKS]
		local reserved = 14 + 10 + JOIN_W + 6 + NO_W + 8 -- the words' left inset, a gap, the two buttons
		tagLabel.TextSize = 13
		tagLabel.Position = UDim2.fromOffset(14, 6)
		tagLabel.Size = UDim2.new(1, -reserved, 0, 14)
		line.TextSize = 13
		line.Position = UDim2.fromOffset(14, 22)
		line.Size = UDim2.new(1, -reserved, 0, 32) -- two lines
		decline.AnchorPoint = Vector2.new(1, 0.5)
		decline.Position = UDim2.new(1, -8, 0.5, 0)
		decline.Size = UDim2.fromOffset(NO_W, buttonH)
		accept.AnchorPoint = Vector2.new(1, 0.5)
		accept.Position = UDim2.new(1, -(8 + NO_W + 6), 0.5, 0)
		accept.Size = UDim2.fromOffset(JOIN_W, buttonH)
	else
		-- Two rows: the tag and the words, then JOIN and NO THANKS side by side.
		tagLabel.TextSize = 14
		tagLabel.Position = UDim2.fromOffset(16, pad)
		tagLabel.Size = UDim2.new(1, -32, 0, 16)
		line.TextSize = 15
		line.Position = UDim2.fromOffset(16, pad + 18)
		line.Size = UDim2.new(1, -32, 0, 36) -- two lines
		for _, b in ipairs({ accept, decline }) do
			b.AnchorPoint = Vector2.new(0, 1)
			b.Size = UDim2.new(0.5, -(16 + 4), 0, buttonH)
			b.Position = UDim2.new(b == accept and 0 or 0.5, b == accept and 16 or 4, 1, -pad)
		end
	end
end

-- The card shows unless a stamp uses its spot or the title screen is up (it keeps its 60 s meanwhile).
local function cardWanted()
	local stamped = HUDController.StampTop ~= nil and HUDController.StampTop() ~= nil
	return not stamped and player:GetAttribute("TitleScreen") ~= true
end

local function button(parent, name, text, kind, onClick)
	local b = Instance.new("TextButton")
	b.Name = name
	Theme.Button(b, kind)
	if kind == "Quiet" then
		b.BackgroundColor3 = C.PanelLight
		b.BackgroundTransparency = 0.15
	end
	b.TextSize = 14
	b.Text = text
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function showInvite(info)
	if type(info) ~= "table" then
		return
	end
	if card then
		card:Destroy()
	end
	card = Instance.new("Frame")
	card.Name = "CrewInvite"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Active = true -- taps on the card don't reach the world behind it
	Theme.Panel(card, 0.2)
	card.Parent = gui
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(0, 8)
	accent.Size = UDim2.new(0, 2, 1, -16)
	accent.BackgroundColor3 = C.Brand
	accent.BorderSizePixel = 0
	accent.Parent = card
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	Theme.Text(tag, 14, "Display")
	tag.TextColor3 = C.Gold
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Size = UDim2.new(1, -32, 0, 16)
	tag.Text = "CREW INVITE"
	tag.Parent = card
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	Theme.Text(line, 15, "Body")
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top -- right under the tag, one line or two
	line.TextWrapped = true
	line.TextTruncate = Enum.TextTruncate.AtEnd
	line.Size = UDim2.new(1, -32, 0, 36)
	line.Text = tostring(info.FromName) .. " wants you in their crew"
	line.Parent = card
	local mine = card
	local function answer(action)
		Remotes.Event("RequestCrew"):FireServer(action)
		if card == mine then
			card:Destroy()
			card = nil
		end
	end
	button(card, "Accept", "JOIN", "Primary", function()
		answer("Accept")
	end)
	button(card, "Decline", "NO THANKS", "Quiet", function()
		answer("Decline")
	end)
	fitCard()
	card.Visible = cardWanted()
	task.delay(INVITE_FOR, function()
		if card == mine then
			card:Destroy()
			card = nil
		end
	end)
end

function CrewClient.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Crew"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the zone map's coordinates (y = 0 is the very top of the screen)
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")
	-- Re-place the card when the screen changes size or the device's input changes.
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCard)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(fitCard)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(fitCard)
	task.spawn(function()
		Remotes.OnClient("CrewInvite", showInvite)
	end)
	player:GetAttributeChangedSignal("FriendBonus"):Connect(function()
		if player:GetAttribute("FriendBonus") then
			NotifyController.Show("A friend is in this server: +10% heist cash!", C.Cash)
		end
	end)
	player:GetAttributeChangedSignal("TitleScreen"):Connect(refreshTags)
	local lastTags, lastCheck = 0, 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastCheck >= CHECK_EVERY then
			lastCheck = now
			-- A big stamp uses the card's spot: step aside until it's gone (the card keeps its 60 s).
			if card then
				local want = cardWanted()
				if card.Visible ~= want then
					card.Visible = want
				end
			end
		end
		if now - lastTags > TAGS_EVERY then
			lastTags = now
			refreshTags()
		end
	end)
end

return CrewClient
