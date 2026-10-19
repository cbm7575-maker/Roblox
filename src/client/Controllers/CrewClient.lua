-- CrewClient (ModuleScript, StarterPlayerScripts.Controllers.CrewClient)
-- Crew invites (ACCEPT / NO card), crewmate name tags that show through walls, and the friend-bonus
-- toast. The phone's CREW app sends invites; the minimap draws crewmates (MinimapClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local CrewClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local MINT = Color3.fromRGB(110, 242, 196)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

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
	tag.Size = UDim2.fromOffset(140, 30)
	tag.StudsOffset = Vector3.new(0, 2.6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 1500
	tag.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = PINK
	l.Text = "♦ " .. p.DisplayName
	l.Parent = tag
	local s = Instance.new("UIStroke")
	s.Color = DARK
	s.Thickness = 2
	s.Parent = l
	tag.Adornee = head
	tag.Parent = head -- a local instance: only this player sees it
	tags[p] = tag
	return tag
end

local function refreshTags()
	local mates = {}
	for _, p in ipairs(CrewClient.Crewmates()) do
		mates[p] = true
		tagFor(p)
	end
	for p, tag in pairs(tags) do
		if not mates[p] then
			tag:Destroy()
			tags[p] = nil
		end
	end
end

local function button(parent, text, color, x, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.44, 0, 0, 34)
	b.Position = UDim2.new(x, 0, 1, -44)
	b.BackgroundColor3 = color
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = DARK
	b.Text = text
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	local p = Instance.new("UIPadding")
	p.PaddingTop, p.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	p.Parent = b
	b.Activated:Connect(onClick)
	return b
end

local function showInvite(info)
	if card then
		card:Destroy()
	end
	card = Instance.new("Frame")
	card.Name = "CrewInvite"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 164) -- the toast area, drawn above the toasts (DisplayOrder)
	card.Size = UDim2.fromOffset(320, 120)
	card.BackgroundColor3 = DARK
	card.BackgroundTransparency = 0.1
	card.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = card
	local s = Instance.new("UIStroke")
	s.Color = PINK
	s.Thickness = 3
	s.Parent = card
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(12, 10)
	l.Size = UDim2.new(1, -24, 0, 52)
	l.Font = FONT
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = info.FromName .. " wants you in their crew!"
	l.Parent = card
	local mine = card
	local function answer(action)
		Remotes.Event("RequestCrew"):FireServer(action)
		if card == mine then
			card:Destroy()
			card = nil
		end
	end
	button(card, "JOIN", MINT, 0.04, function()
		answer("Accept")
	end).Name = "Accept"
	button(card, "NO THANKS", Color3.fromRGB(200, 190, 230), 0.52, function()
		answer("Decline")
	end).Name = "Decline"
	task.delay(60, function()
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
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 21 -- above the toasts (20): JOIN / NO THANKS are never covered
	gui.Parent = player:WaitForChild("PlayerGui")
	task.spawn(function()
		Remotes.OnClient("CrewInvite", showInvite)
	end)
	player:GetAttributeChangedSignal("FriendBonus"):Connect(function()
		if player:GetAttribute("FriendBonus") then
			NotifyController.Show("A friend is in this server: +10% heist cash!", MINT)
		end
	end)
	local last = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - last > 1 then
			last = os.clock()
			refreshTags()
		end
	end)
end

return CrewClient
