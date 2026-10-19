-- PhoneUI (ModuleScript, StarterPlayerScripts.Controllers.PhoneUI)
-- The in-game phone (PHONE button, P, or D-pad down on a gamepad). Apps:
--   GARAGE    your cars for your current role: DELIVER (spawn), paint $500, rims $800,
--             underglow $3,000 once per car (then free colour swaps; not on boats)
--   AUTONEON  the car dealer: stats, prices, BUY (tap twice to confirm)
--   GPS       races, stunts, jobs, services and heist sites (open ones marked): sets a road route
--   JOBS      switch between citizen and police; phone missions for your side
--   HOMES     safehouses (Config.Properties): price or OWNED / HOME, rent waiting, rank needed,
--             SHOW ME and SET HOME (RequestProperty "SetHome"). Buying and rent happen at the door.
--   GOALS     ranks, Gus figurines found, today's challenges
--   FEED      every Coast Feed post (FeedController.History); the tile shows how many are new
--   SHOP      game passes and cash packs (prices read live from the Creator Hub)
-- The server decides everything (GarageService, VehicleService, PropertyService); this only asks.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MarketplaceService = game:GetService("MarketplaceService")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Missions = require(ReplicatedStorage.Shared.Config.Missions)
local Garage = require(ReplicatedStorage.Shared.Config.Garage)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local FeedController = require(script.Parent:WaitForChild("FeedController"))

local player = Players.LocalPlayer

local PhoneUI = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local GOLD = Color3.fromRGB(255, 214, 10)
local MINT = Color3.fromRGB(110, 242, 196)
local PURPLE = Color3.fromRGB(123, 47, 255)
local ORANGE = Color3.fromRGB(255, 138, 61)
local LAVENDER = Color3.fromRGB(200, 190, 230)
local DARK = Color3.fromRGB(18, 14, 30)
local PANEL = Color3.fromRGB(34, 26, 56)
local WHITE = Color3.new(1, 1, 1)
local FONT = Enum.Font.FredokaOne
local DESIGN_W = 360

local gui, phone, screen, titleLabel, backButton, clockLabel, cashLabel, openButton, fit, homeBar
local page -- current page name
local back -- function to go back, or nil on the home screen
local detailId -- car shown on the Garage detail page
local gpsTab = "Activity"
local confirmBuy = { id = nil, at = 0 }

local money = HUDController.Money

------------------------------------------------------------------ small UI helpers

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 12)
	c.Parent = obj
	return c
end

local function stroke(obj, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function label(parent, text, size, pos, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos or UDim2.new()
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = color or WHITE
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent, text, size, pos, color, onClick)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = color or PINK
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = WHITE
	b.Text = text
	b.Parent = parent
	corner(b, UDim.new(0.3, 0))
	local p = Instance.new("UIPadding")
	p.PaddingTop, p.PaddingBottom = UDim.new(0.18, 0), UDim.new(0.18, 0)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	p.Parent = b
	b.Activated:Connect(function()
		require(script.Parent:WaitForChild("SoundClient")).Play("Click")
	end)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function clear()
	for _, c in ipairs(screen:GetChildren()) do
		c:Destroy()
	end
end

-- A vertical scrolling list filling the screen below `top` (fraction of the screen).
local function list(top)
	local s = Instance.new("ScrollingFrame")
	s.Name = "List"
	s.Size = UDim2.fromScale(1, 1 - top)
	s.Position = UDim2.fromScale(0, top)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.ScrollBarImageColor3 = PINK
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.Parent = screen
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = s
	local p = Instance.new("UIPadding")
	p.PaddingRight = UDim.new(0, 6)
	p.Parent = s
	return s
end

local function row(parent, height, order)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, height)
	f.BackgroundColor3 = PANEL
	f.LayoutOrder = order or 0
	f.Parent = parent
	corner(f)
	return f
end

local function owned()
	local set = {}
	for id in string.gmatch(player:GetAttribute("OwnedCars") or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function customOf(id)
	local s = player:GetAttribute("Custom_" .. id)
	if not s then
		return 0, 0, 0
	end
	local a, b, c = string.match(s, "(%d+),(%d+),?(%d*)")
	return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

-- Player-facing role names (the Side values stay "Civilian" / "Cop" / "Prisoner").
local ROLE = { Civilian = "CITIZEN", Cop = "POLICE", Prisoner = "IN PRISON" }

-- An optional module (another feature may not be in this place yet): nil if missing or broken.
local function optional(parent, name)
	local m = parent:FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, mod = pcall(require, m)
	return ok and type(mod) == "table" and mod or nil
end

local function canDrive(def)
	local side = player:GetAttribute("Side") or "Civilian"
	return (def.Police == true) == (side == "Cop")
end

------------------------------------------------------------------ pages

local show -- forward declaration

local function setHeader(title, backTo)
	titleLabel.Text = title
	page = title
	back = backTo
	backButton.Visible = backTo ~= nil
end

local APPS = {
	{ Name = "GARAGE", Icon = "🚗", Color = PINK, Page = "Garage" },
	{ Name = "AUTONEON", Icon = "🏁", Color = CYAN, Page = "Dealer" },
	{ Name = "GPS", Icon = "📍", Color = MINT, Page = "GPS" },
	{ Name = "JOBS", Icon = "💼", Color = GOLD, Page = "Jobs" },
	{ Name = "HOMES", Icon = "🏠", Color = ORANGE, Page = "Homes" },
	{ Name = "GOALS", Icon = "🏆", Color = GOLD, Page = "Goals" },
	{ Name = "FEED", Icon = "📰", Color = CYAN, Page = "Feed" },
	{ Name = "CREW", Icon = "👥", Color = MINT, Page = "Crew" },
	{ Name = "SHOP", Icon = "🛍️", Color = PURPLE, Page = "Shop" },
	{ Name = "SETTINGS", Icon = "⚙️", Color = LAVENDER, Page = "Settings" },
}

local function homePage()
	setHeader("NEON PHONE", nil)
	local grid = Instance.new("Frame")
	grid.Name = "Apps"
	grid.Size = UDim2.fromScale(1, 0.8)
	grid.Position = UDim2.fromScale(0, 0.04)
	grid.BackgroundTransparency = 1
	grid.Parent = screen
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(0.3, 0.215) -- 3 across, 4 rows
	layout.CellPadding = UDim2.fromScale(0.035, 0.03)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, app in ipairs(APPS) do
		local tile = Instance.new("TextButton")
		tile.Name = app.Page
		tile.LayoutOrder = i
		tile.BackgroundColor3 = PANEL
		tile.Text = ""
		tile.Parent = grid
		corner(tile, UDim.new(0.2, 0))
		stroke(tile, app.Color, 2)
		label(tile, app.Icon, UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0.08), WHITE, Enum.TextXAlignment.Center)
		label(tile, app.Name, UDim2.fromScale(0.9, 0.22), UDim2.fromScale(0.05, 0.68), app.Color, Enum.TextXAlignment.Center)
		tile.Activated:Connect(function()
			show(app.Page)
		end)
		if app.Page == "Feed" and FeedController.Unread > 0 then
			local badge = label(tile, tostring(math.min(FeedController.Unread, 99)), UDim2.fromOffset(28, 28),
				UDim2.new(1, -24, 0, -6), WHITE, Enum.TextXAlignment.Center)
			badge.Name = "Unread"
			badge.BackgroundTransparency = 0
			badge.BackgroundColor3 = PINK
			corner(badge, UDim.new(0.5, 0))
		end
	end
	local tip = label(screen, "Tip: robbing stores makes you Wanted. Lose the cops, then bank your bag at the Hideout!",
		UDim2.fromScale(0.94, 0.12), UDim2.fromScale(0.03, 0.86), Color3.fromRGB(200, 190, 230), Enum.TextXAlignment.Center)
	tip.TextWrapped = true
end

local function statBar(parent, name, value, y, color)
	label(parent, name, UDim2.fromScale(0.3, 0.13), UDim2.fromScale(0.04, y), Color3.fromRGB(200, 190, 230))
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(0.58, 0.07)
	bg.Position = UDim2.fromScale(0.36, y + 0.03)
	bg.BackgroundColor3 = DARK
	bg.Parent = parent
	corner(bg, UDim.new(0.5, 0))
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(value, 0.05, 1), 1)
	fill.BackgroundColor3 = color
	fill.Parent = bg
	corner(fill, UDim.new(0.5, 0))
end

local function garagePage()
	setHeader("GARAGE", "Home")
	local mine = owned()
	local s = list(0.02)
	local n = 0
	for i, def in ipairs(Vehicles.List) do
		if mine[def.Id] and canDrive(def) then
			n += 1
			local r = row(s, 74, i)
			r.Name = def.Id
			local paint = customOf(def.Id)
			local swatch = Instance.new("Frame")
			swatch.Size = UDim2.fromOffset(14, 50)
			swatch.Position = UDim2.fromOffset(10, 12)
			swatch.BackgroundColor3 = paint > 0 and Garage.Paints[paint].Color or def.Color
			swatch.Parent = r
			corner(swatch, UDim.new(0.5, 0))
			label(r, def.DisplayName or def.Id, UDim2.new(0.52, 0, 0, 30), UDim2.fromOffset(32, 8))
			label(r, def.Class, UDim2.new(0.5, 0, 0, 20), UDim2.fromOffset(32, 42), Color3.fromRGB(200, 190, 230))
			button(r, def.Boat and "LAUNCH" or "DELIVER", UDim2.new(0.3, 0, 0, 30), UDim2.new(0.68, 0, 0, 6), PINK, function()
				Remotes.Event("RequestSpawnCar"):FireServer(def.Id)
				PhoneUI.Close()
			end).Name = "Deliver"
			button(r, "STYLE", UDim2.new(0.3, 0, 0, 26), UDim2.new(0.68, 0, 0, 42), PURPLE, function()
				detailId = def.Id
				show("Custom")
			end).Name = "Style"
		end
	end
	if n == 0 then
		label(s, "No cars for this role yet. Visit AUTONEON!", UDim2.new(1, 0, 0, 40), nil, WHITE, Enum.TextXAlignment.Center)
	end
end

local function swatchRow(parent, title, price, items, current, order, onPick)
	local lines = math.ceil(#items / 8)
	local r = row(parent, 40 + lines * 34, order)
	r.Name = title
	label(r, title, UDim2.new(0.6, 0, 0, 24), UDim2.fromOffset(10, 6))
	label(r, price, UDim2.new(0.34, 0, 0, 22), UDim2.new(0.64, -8, 0, 7), GOLD, Enum.TextXAlignment.Right)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -20, 0, lines * 34)
	holder.Position = UDim2.fromOffset(10, 34)
	holder.BackgroundTransparency = 1
	holder.Parent = r
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(28, 28)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder
	for i, item in ipairs(items) do
		local b = Instance.new("TextButton")
		b.Name = "Swatch" .. i
		b.Text = Garage.Allowed(player, item) and "" or "🔒"
		b.TextScaled = true
		b.BackgroundColor3 = item.Color
		b.LayoutOrder = i
		b.Parent = holder
		corner(b, UDim.new(0.5, 0))
		stroke(b, i == current and WHITE or DARK, i == current and 3 or 1)
		b.Activated:Connect(function()
			onPick(i, item)
		end)
	end
end

local function customPage()
	local def = Vehicles.ById[detailId]
	if not def then
		return show("Garage")
	end
	setHeader(string.upper(def.DisplayName or def.Id), "Garage")
	local paint, glow, rim = customOf(def.Id)
	local s = list(0.02)
	swatchRow(s, "Paint", money(Garage.PaintPrice), Garage.Paints, paint, 1, function(i)
		Remotes.Event("RequestPaint"):FireServer(def.Id, i)
	end)
	swatchRow(s, "Rims", money(Garage.RimPrice), Garage.Rims, rim, 2, function(i)
		Remotes.Event("RequestRims"):FireServer(def.Id, i)
	end)
	if not def.Boat then -- no underglow on boats (the server refuses it too)
		local glowPrice = glow > 0 and "FREE SWAP" or money(Garage.UnderglowPrice)
		swatchRow(s, "Underglow", glowPrice, Garage.Glows, glow, 3, function(i)
			Remotes.Event("RequestUnderglow"):FireServer(def.Id, i)
		end)
	end
	local hint = label(s, "Changes show on this car next time it's delivered (or right away if it's out).",
		UDim2.new(1, 0, 0, 36), nil, Color3.fromRGB(200, 190, 230), Enum.TextXAlignment.Center)
	hint.LayoutOrder = 4
	hint.TextWrapped = true
end

local function dealerPage()
	setHeader("AUTONEON", "Home")
	local mine = owned()
	local s = list(0.02)
	for i, def in ipairs(Vehicles.List) do
		if def.Police then
			continue
		end
		local r = row(s, 150, i)
		r.Name = def.Id
		label(r, def.DisplayName or def.Id, UDim2.new(0.6, 0, 0, 28), UDim2.fromOffset(12, 8))
		label(r, def.Class, UDim2.new(0.4, 0, 0, 20), UDim2.new(0.58, -10, 0, 12), def.Color:Lerp(WHITE, 0.55), Enum.TextXAlignment.Right)
		local stats = Instance.new("Frame")
		stats.Size = UDim2.new(1, 0, 0, 80)
		stats.Position = UDim2.fromOffset(0, 36)
		stats.BackgroundTransparency = 1
		stats.Parent = r
		statBar(stats, "Speed", (def.MaxSpeed or 120) / 200, 0.02, PINK)
		statBar(stats, "Accel", (def.AccelRating or 1) / 5, 0.26, CYAN)
		statBar(stats, "Handling", (def.HandlingRating or 1) / 5, 0.5, MINT)
		statBar(stats, "Tough", (def.Toughness or 1) / 5, 0.74, GOLD)
		local text, color, click
		if mine[def.Id] then
			text, color = "OWNED", Color3.fromRGB(70, 60, 100)
		elseif def.Pass then
			text, color = "GAME PASS", PURPLE
			click = function()
				for _, pass in ipairs(Shop.Passes) do
					if pass.Key == def.Pass then
						NotifyController.Show("The " .. (def.DisplayName or def.Id) .. " comes with the " .. pass.Name .. " pass.", PURPLE)
					end
				end
				show("Shop")
			end
		else
			text, color = "BUY " .. money(def.Price or 0), PINK
			click = function(b)
				if confirmBuy.id == def.Id and os.clock() - confirmBuy.at < 4 then
					confirmBuy.id = nil
					Remotes.Event("RequestBuyCar"):FireServer(def.Id)
				else
					confirmBuy.id, confirmBuy.at = def.Id, os.clock()
					b.Text = "TAP TO CONFIRM"
					b.BackgroundColor3 = GOLD
					task.delay(4, function()
						if b.Parent and b.Text == "TAP TO CONFIRM" then
							b.Text = text
							b.BackgroundColor3 = color
						end
					end)
				end
			end
		end
		local b
		b = button(r, text, UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 1, -32), color, click and function()
			click(b)
		end)
		b.Name = "Buy"
	end
end

local GPS_TABS = { { "Activity", "FUN" }, { "Heist", "HEISTS" }, { "Service", "PLACES" } }

local function gpsPage()
	setHeader("GPS", "Home")
	local places = {}
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Places") or "[]")
	end)
	if ok then
		places = decoded
	end
	local open = {}
	for id in string.gmatch(ReplicatedStorage:GetAttribute("OpenHeists") or "", "[^,]+") do
		open[id] = true
	end
	local tabs = Instance.new("Frame")
	tabs.Size = UDim2.fromScale(1, 0.08)
	tabs.Position = UDim2.fromScale(0, 0.01)
	tabs.BackgroundTransparency = 1
	tabs.Parent = screen
	tabs.Name = "Tabs"
	for i, t in ipairs(GPS_TABS) do
		button(tabs, t[2], UDim2.fromScale(0.31, 1), UDim2.fromScale((i - 1) * 0.345, 0), gpsTab == t[1] and PINK or PANEL, function()
			gpsTab = t[1]
			show("GPS")
		end).Name = t[1]
	end
	local top = 0.11
	if GPSClient.Target() then
		button(screen, "CLEAR ROUTE", UDim2.fromScale(1, 0.07), UDim2.fromScale(0, 0.11), Color3.fromRGB(90, 70, 130), function()
			GPSClient.Clear()
			show("GPS")
		end)
		top = 0.2
	end
	local s = list(top)
	local rows = {}
	for _, p in ipairs(places) do
		if p.c == gpsTab then
			local pos = Vector3.new(p.x, 0, p.z)
			table.insert(rows, { p = p, pos = pos, d = GPSClient.Distance(pos) or 0 })
		end
	end
	table.sort(rows, function(a, b)
		if gpsTab == "Heist" and (open[a.p.id] ~= nil) ~= (open[b.p.id] ~= nil) then
			return open[a.p.id] ~= nil
		end
		return a.d < b.d
	end)
	for i, item in ipairs(rows) do
		local p = item.p
		local r = row(s, 48, i)
		r.Name = p.id or p.n
		local nameColor = WHITE
		local status = (p.k and (p.k .. " · ") or "") .. GPSClient.FormatDistance(item.d)
		if p.c == "Heist" then
			nameColor = open[p.id] and MINT or Color3.fromRGB(150, 140, 175)
			status = (open[p.id] and "OPEN · " or "closed · ") .. GPSClient.FormatDistance(item.d)
		end
		label(r, p.n, UDim2.new(0.66, 0, 0, 20), UDim2.fromOffset(10, 6), nameColor)
		label(r, status, UDim2.new(0.66, 0, 0, 15), UDim2.fromOffset(10, 28), Color3.fromRGB(200, 190, 230))
		button(r, "GO", UDim2.new(0.26, 0, 0, 32), UDim2.new(0.72, -6, 0, 8), MINT, function()
			GPSClient.SetTarget(p.n, item.pos)
			PhoneUI.Close()
		end).Name = "Go"
	end
end

local function jobsPage()
	setHeader("JOBS", "Home")
	local s = list(0.02)
	local side = player:GetAttribute("Side") or "Civilian"
	local r = row(s, 90, 1)
	label(r, "You are: " .. (ROLE[side] or ROLE.Civilian), UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 8),
		side == "Cop" and CYAN or PINK)
	button(r, "SWITCH ROLE", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 44), PURPLE, function()
		PhoneUI.Close()
		local TeamUI = require(script.Parent:WaitForChild("TeamUI"))
		if TeamUI.Open then
			TeamUI.Open()
		end
	end)
	local jobs = {
		{ "Taxi driver", "Pick up passengers, drop them off fast for tips.", "Taxi Stand" },
		{ "Street racer", "Beat par on 3 routes. Set a best time!", "Ocean Drive Sprint" },
		{ "Drifter", "Slide through the Drift Zone on Lighthouse Key.", "Drift Zone" },
	}
	-- Phone missions (MissionService): full pay once a day each.
	local done = {}
	for id in string.gmatch(player:GetAttribute("MissionsDone") or "", "[^,]+") do
		done[id] = true
	end
	-- Only your side's missions (Side defaults to "Civilian").
	local mine = {}
	for _, m in ipairs(Missions.List) do
		if (m.Side or "Civilian") == side then
			table.insert(mine, m)
		end
	end
	if #mine > 0 then
		local mh = label(s, "MISSIONS", UDim2.new(1, 0, 0, 22), nil, MINT, Enum.TextXAlignment.Center)
		mh.LayoutOrder = 50
	end
	for i, m in ipairs(mine) do
		local mr = row(s, 96, 50 + i)
		mr.Name = m.Id
		label(mr, m.Name .. (done[m.Id] and "  ✅" or ""), UDim2.new(0.66, 0, 0, 22), UDim2.fromOffset(10, 6), done[m.Id] and MINT or WHITE)
		local b = label(mr, m.Blurb, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 30), Color3.fromRGB(200, 190, 230))
		b.TextWrapped = true
		local share = type(Missions.RepeatShareFor) == "function" and Missions.RepeatShareFor(m) or Missions.RepeatShare
		label(mr, (done[m.Id] and "repeat " or "") .. money(done[m.Id] and math.floor(m.Cash * share) or m.Cash)
			.. (m.NeedsBoat and "  ·  boat" or ""), UDim2.new(0.5, 0, 0, 18), UDim2.new(0, 10, 1, -24), GOLD)
		button(mr, "START", UDim2.new(0.3, 0, 0, 26), UDim2.new(0.68, -6, 1, -32), MINT, function()
			Remotes.Event("RequestMission"):FireServer("Start", m.Id)
			PhoneUI.Close()
		end).Name = "Start"
	end
	for i, j in ipairs(jobs) do
		local jr = row(s, 84, i + 1)
		label(jr, j[1], UDim2.new(0.62, 0, 0, 24), UDim2.fromOffset(10, 6))
		local d = label(jr, j[2], UDim2.new(0.62, 0, 0, 40), UDim2.fromOffset(10, 34), Color3.fromRGB(200, 190, 230))
		d.TextWrapped = true
		button(jr, "GPS", UDim2.new(0.26, 0, 0, 32), UDim2.new(0.72, -6, 0, 26), MINT, function()
			local ok, places = pcall(function()
				return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Places") or "[]")
			end)
			for _, p in ipairs(ok and places or {}) do
				if p.n == j[3] then
					GPSClient.SetTarget(p.n, Vector3.new(p.x, 0, p.z))
					PhoneUI.Close()
					return
				end
			end
		end)
	end
end

------------------------------------------------------------------ shop

local priceCache = {} -- [id] = "R$ 499" (read live: prices are never hard-coded)
local function priceText(id, infoType)
	if id == 0 then
		return "SOON"
	end
	if priceCache[id] then
		return priceCache[id]
	end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	if ok and info and info.PriceInRobux then
		priceCache[id] = "R$ " .. info.PriceInRobux
		return priceCache[id]
	end
	return "BUY"
end

local function shopPage()
	setHeader("SHOP", "Home")
	local s = list(0.02)
	for i, pass in ipairs(Shop.Passes) do
		local r = row(s, 96, i)
		r.Name = pass.Key
		label(r, pass.Icon, UDim2.fromOffset(40, 40), UDim2.fromOffset(8, 10), WHITE, Enum.TextXAlignment.Center)
		label(r, pass.Name, UDim2.new(0.6, 0, 0, 24), UDim2.fromOffset(54, 8), GOLD)
		local perk = label(r, pass.Perk, UDim2.new(1, -64, 0, 30), UDim2.fromOffset(54, 34), Color3.fromRGB(200, 190, 230))
		perk.TextWrapped = true
		local owned = player:GetAttribute("Pass_" .. pass.Key) == true
		local b = button(r, owned and "OWNED" or "…", UDim2.new(0.4, 0, 0, 24), UDim2.new(0.6, -10, 1, -30),
			owned and Color3.fromRGB(70, 60, 100) or PURPLE, function()
				if not owned and pass.Id ~= 0 then
					MarketplaceService:PromptGamePassPurchase(player, pass.Id)
				elseif pass.Id == 0 then
					NotifyController.Show(pass.Name .. " is coming soon!", PURPLE)
				end
			end)
		b.Name = "Buy"
		if not owned then
			task.spawn(function()
				local text = priceText(pass.Id, Enum.InfoType.GamePass)
				if b.Parent then
					b.Text = text
				end
			end)
		end
	end
	local head = label(s, "CASH PACKS", UDim2.new(1, 0, 0, 26), nil, MINT, Enum.TextXAlignment.Center)
	head.LayoutOrder = 50
	for i, product in ipairs(Shop.Products) do
		local r = row(s, 48, 50 + i)
		r.Name = product.Key
		label(r, "💵 " .. money(product.Cash), UDim2.new(0.55, 0, 0, 26), UDim2.fromOffset(10, 11), MINT)
		local b = button(r, "…", UDim2.new(0.36, 0, 0, 30), UDim2.new(0.62, -6, 0, 9), PINK, function()
			if product.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(player, product.Id)
			else
				NotifyController.Show("Cash packs are coming soon!", PINK)
			end
		end)
		b.Name = "Buy"
		task.spawn(function()
			local text = priceText(product.Id, Enum.InfoType.Product)
			if b.Parent then
				b.Text = text
			end
		end)
	end
end

------------------------------------------------------------------ goals: ranks + daily challenges

local function goalsPage()
	setHeader("GOALS", "Home")
	local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
	local s = list(0.02)
	for i, side in ipairs({ "Civilian", "Cop" }) do
		local rank, frac, xp, nextXP = ProgressClient.Progress(side)
		local color = side == "Cop" and CYAN or PINK
		local r = row(s, 86, i)
		r.Name = side
		label(r, ROLE[side] .. "  ·  RANK " .. rank, UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 6), color)
		local bg = Instance.new("Frame")
		bg.Size = UDim2.new(1, -20, 0, 10)
		bg.Position = UDim2.fromOffset(10, 36)
		bg.BackgroundColor3 = DARK
		bg.Parent = r
		corner(bg, UDim.new(0.5, 0))
		local fillBar = Instance.new("Frame")
		fillBar.Size = UDim2.fromScale(math.clamp(frac, 0.02, 1), 1)
		fillBar.BackgroundColor3 = color
		fillBar.Parent = bg
		corner(fillBar, UDim.new(0.5, 0))
		local unlocks = Progression.Unlocks[side == "Cop" and "cop" or "civ"]
		local nextUnlock
		for rr = rank + 1, Progression.MaxRank do
			if unlocks[rr] then
				nextUnlock = "Rank " .. rr .. ": " .. unlocks[rr]
				break
			end
		end
		local info = rank >= Progression.MaxRank and "Max rank!" or (xp .. " / " .. nextXP .. " XP" .. (nextUnlock and ("  ·  next: " .. nextUnlock) or ""))
		local l = label(r, info, UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 52), Color3.fromRGB(200, 190, 230))
		l.TextWrapped = true
	end
	-- Gus the Gator figurines (CollectibleService: GusFound / GusTotal), with a clue for the nearest one.
	local found = player:GetAttribute("GusFound") or 0
	local total = player:GetAttribute("GusTotal") or 40
	local gus = row(s, 86, 5)
	gus.Name = "Gus"
	label(gus, "🐊 Gus figurines  " .. found .. "/" .. total, UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 6), MINT)
	local gbg = Instance.new("Frame")
	gbg.Size = UDim2.new(1, -20, 0, 10)
	gbg.Position = UDim2.fromOffset(10, 36)
	gbg.BackgroundColor3 = DARK
	gbg.Parent = gus
	corner(gbg, UDim.new(0.5, 0))
	local gfill = Instance.new("Frame")
	gfill.Size = UDim2.fromScale(math.clamp(total > 0 and found / total or 0, 0.02, 1), 1)
	gfill.BackgroundColor3 = MINT
	gfill.Parent = gbg
	corner(gfill, UDim.new(0.5, 0))
	local clue = found >= total and "All found! Gator Green paint unlocked." or "Hidden all over Port Solana: $250 each."
	local Collectibles = found < total and optional(script.Parent, "CollectibleClient")
	if Collectibles and type(Collectibles.NextHint) == "function" then
		local ok, hint = pcall(Collectibles.NextHint)
		if ok and type(hint) == "string" and hint ~= "" then
			clue = "Clue: " .. hint
		end
	end
	local cl = label(gus, clue, UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 52), LAVENDER)
	cl.TextWrapped = true
	local head = label(s, "TODAY'S CHALLENGES  ·  $2,000 + 100 XP each", UDim2.new(1, 0, 0, 22), nil, GOLD, Enum.TextXAlignment.Center)
	head.LayoutOrder = 10
	local ok, listData = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Challenges") or "[]")
	end)
	local byId = {}
	for _, c in ipairs(Progression.Challenges) do
		byId[c.Id] = c
	end
	for i, entry in ipairs(ok and listData or {}) do
		local def = byId[entry.id]
		if def then
			local r = row(s, 60, 10 + i)
			local color = def.Side == "Cop" and CYAN or PINK
			label(r, (entry.done and "✅ " or "") .. def.Text, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 6), entry.done and MINT or WHITE)
			local bg = Instance.new("Frame")
			bg.Size = UDim2.new(1, -90, 0, 8)
			bg.Position = UDim2.fromOffset(10, 38)
			bg.BackgroundColor3 = DARK
			bg.Parent = r
			corner(bg, UDim.new(0.5, 0))
			local fillBar = Instance.new("Frame")
			fillBar.Size = UDim2.fromScale(math.clamp(entry.p / def.Goal, 0.02, 1), 1)
			fillBar.BackgroundColor3 = entry.done and MINT or color
			fillBar.Parent = bg
			corner(fillBar, UDim.new(0.5, 0))
			label(r, entry.p .. "/" .. def.Goal, UDim2.new(0, 64, 0, 18), UDim2.new(1, -74, 0, 32), Color3.fromRGB(200, 190, 230),
				Enum.TextXAlignment.Right)
		end
	end
	local foot = label(s, "New challenges every day at midnight (UTC).", UDim2.new(1, 0, 0, 18), nil, Color3.fromRGB(160, 150, 190),
		Enum.TextXAlignment.Center)
	foot.LayoutOrder = 20
end

------------------------------------------------------------------ crew

local function crewPage()
	setHeader("CREW", "Home")
	local s = list(0.02)
	local myCrew = player:GetAttribute("Crew")
	local info = label(s, (myCrew and "Rob together: +20% cash when a crewmate is close." or "Invite players to rob together (+20% cash) and ride in each other's cars.")
		.. (player:GetAttribute("FriendBonus") and "  Friend here: +10%!" or ""), UDim2.new(1, 0, 0, 38), nil,
		Color3.fromRGB(200, 190, 230), Enum.TextXAlignment.Center)
	info.TextWrapped = true
	info.LayoutOrder = 1
	local order = 2
	if myCrew then
		local head = label(s, "YOUR CREW", UDim2.new(1, 0, 0, 22), nil, MINT, Enum.TextXAlignment.Center)
		head.LayoutOrder = order
		order += 1
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("Crew") == myCrew then
				local r = row(s, 40, order)
				order += 1
				label(r, (p == player and "★ " or "♦ ") .. p.DisplayName, UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 8), PINK)
			end
		end
		local leave = button(s, "LEAVE CREW", UDim2.new(1, 0, 0, 32), nil, Color3.fromRGB(90, 70, 130), function()
			Remotes.Event("RequestCrew"):FireServer("Leave")
		end)
		leave.Name = "Leave"
		leave.LayoutOrder = order
		order += 1
	end
	local head2 = label(s, "PLAYERS HERE", UDim2.new(1, 0, 0, 22), nil, GOLD, Enum.TextXAlignment.Center)
	head2.LayoutOrder = order
	order += 1
	local any = false
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and (not myCrew or p:GetAttribute("Crew") ~= myCrew) then
			any = true
			local r = row(s, 48, order)
			r.Name = tostring(p.UserId)
			order += 1
			label(r, p.DisplayName, UDim2.new(0.62, 0, 0, 22), UDim2.fromOffset(10, 5))
			local side = p:GetAttribute("Side") or ""
			label(r, side == "Cop" and "Police" or side == "Prisoner" and "In prison" or "Citizen", UDim2.new(0.62, 0, 0, 16),
				UDim2.fromOffset(10, 27), LAVENDER)
			button(r, "INVITE", UDim2.new(0.3, 0, 0, 32), UDim2.new(0.68, -6, 0, 8), MINT, function()
				Remotes.Event("RequestCrew"):FireServer("Invite", p.UserId)
			end).Name = "Invite"
		end
	end
	if not any then
		local none = label(s, "Nobody else here yet. Invite friends from the Roblox menu!", UDim2.new(1, 0, 0, 36), nil,
			Color3.fromRGB(160, 150, 190), Enum.TextXAlignment.Center)
		none.TextWrapped = true
		none.LayoutOrder = order
	end
end

------------------------------------------------------------------ feed: every Coast Feed post

local function ago(t)
	local d = math.max(0, os.time() - (t or os.time()))
	if d < 60 then
		return "now"
	elseif d < 3600 then
		return (d // 60) .. "m ago"
	end
	return (d // 3600) .. "h ago"
end

local function feedPage()
	setHeader("FEED", "Home")
	FeedController.MarkRead()
	local s = list(0.02)
	local history = FeedController.History
	if #history == 0 then
		local none = label(s, "Nothing yet. Big moments in Port Solana show up here.", UDim2.new(1, 0, 0, 40), nil,
			Color3.fromRGB(160, 150, 190), Enum.TextXAlignment.Center)
		none.TextWrapped = true
		return
	end
	for i = #history, 1, -1 do -- newest first
		local e = history[i]
		local r = row(s, 78, #history - i + 1)
		local accent = Instance.new("Frame")
		accent.Size = UDim2.new(0, 6, 1, -20)
		accent.Position = UDim2.fromOffset(8, 10)
		accent.BackgroundColor3 = e.Color or PINK
		accent.Parent = r
		corner(accent, UDim.new(0.5, 0))
		local t = label(r, e.Text, UDim2.new(1, -36, 0, 46), UDim2.fromOffset(22, 6), WHITE)
		t.TextWrapped = true
		t.TextTruncate = Enum.TextTruncate.AtEnd
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = 13
		limit.MaxTextSize = 18
		limit.Parent = t
		label(r, ago(e.Time), UDim2.new(0.5, 0, 0, 16), UDim2.new(0.5, -12, 1, -22), Color3.fromRGB(160, 150, 190),
			Enum.TextXAlignment.Right)
	end
end

------------------------------------------------------------------ homes: safehouses (PropertyService)

local function homesPage()
	setHeader("HOMES", "Home")
	local s = list(0.02)
	local Properties = optional(ReplicatedStorage.Shared.Config, "Properties")
	if not Properties or type(Properties.List) ~= "table" then
		label(s, "Homes are coming soon!", UDim2.new(1, 0, 0, 40), nil, LAVENDER, Enum.TextXAlignment.Center)
		return
	end
	local mine = {}
	for id in string.gmatch(player:GetAttribute("OwnedProps") or "", "[^,]+") do
		mine[id] = true
	end
	local home = player:GetAttribute("HomeId")
	local rank = player:GetAttribute("CivRank") or 1
	local intro = label(s, "Your own safehouse: respawn there, bank your bag on its pad, earn rent.",
		UDim2.new(1, 0, 0, 36), nil, LAVENDER, Enum.TextXAlignment.Center)
	intro.TextWrapped = true
	intro.LayoutOrder = 0
	for i, def in ipairs(Properties.List) do
		local owned = mine[def.Id] == true
		local r = row(s, 116, i)
		r.Name = tostring(def.Id)
		label(r, tostring(def.Name), UDim2.new(0.62, 0, 0, 24), UDim2.fromOffset(10, 6))
		label(r, tostring(def.District or ""), UDim2.new(0.62, 0, 0, 16), UDim2.fromOffset(10, 32), LAVENDER)
		local status, statusColor
		if home == def.Id then
			status, statusColor = "🏠 HOME", PINK
		elseif owned then
			status, statusColor = "OWNED", MINT
		else
			status, statusColor = money(def.Price or 0), GOLD
		end
		label(r, status, UDim2.new(0.36, 0, 0, 22), UDim2.new(0.64, -10, 0, 8), statusColor, Enum.TextXAlignment.Right)
		local rent = "Rent " .. money(def.Rent or 0) .. "/h"
		local info, infoColor = rent, LAVENDER
		if owned then
			info = rent .. "  ·  waiting " .. money(player:GetAttribute("Rent_" .. def.Id) or 0) .. " (collect at the door)"
			infoColor = MINT
		else
			local need = def.MinRank or 1
			if need > 1 then
				info = rent .. "  ·  rank " .. need .. (rank >= need and " ✓" or " needed")
				infoColor = rank >= need and LAVENDER or ORANGE
			end
		end
		local il = label(r, info, UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 52), infoColor)
		il.TextTruncate = Enum.TextTruncate.AtEnd
		local canSetHome = owned and home ~= def.Id
		button(r, "SHOW ME", UDim2.new(canSetHome and 0.46 or 1, canSetHome and -12 or -20, 0, 32),
			UDim2.new(0, 10, 1, -40), MINT, function()
				if typeof(def.Pos) == "Vector3" then
					GPSClient.SetTarget(tostring(def.Name), def.Pos)
					PhoneUI.Close()
				end
			end).Name = "ShowMe"
		if canSetHome then
			button(r, "SET HOME", UDim2.new(0.46, -12, 0, 32), UDim2.new(0.54, 2, 1, -40), PINK, function()
				Remotes.Event("RequestProperty"):FireServer("SetHome", def.Id)
			end).Name = "SetHome"
		end
	end
	local foot = label(s, "Buy it and collect rent in person, at the door.", UDim2.new(1, 0, 0, 18), nil,
		Color3.fromRGB(160, 150, 190), Enum.TextXAlignment.Center)
	foot.LayoutOrder = 100
end

------------------------------------------------------------------ settings

local function settingsPage()
	setHeader("SETTINGS", "Home")
	local Settings = require(script.Parent:WaitForChild("SettingsClient"))
	local s = list(0.02)
	local function volumeRow(key, title, order)
		local r = row(s, 70, order)
		r.Name = key
		label(r, title, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 6))
		local steps = { 0, 0.25, 0.5, 0.75, 1 }
		for i, v in ipairs(steps) do
			local on = math.abs(Settings.Get(key) - v) < 0.01
			local b = button(r, v == 0 and "OFF" or (math.floor(v * 100) .. "%"), UDim2.new(0.18, 0, 0, 28),
				UDim2.new((i - 1) * 0.2 + 0.01, 0, 0, 34), on and PINK or PANEL, function()
					Settings.Set(key, v)
					show("Settings")
				end)
			b.Name = key .. i
		end
	end
	volumeRow("Music", "📻 Radio volume", 1)
	volumeRow("Effects", "🔊 Sound effects", 2)
	local r = row(s, 86, 3)
	r.Name = "Performance"
	local perf = Settings.Get("Performance")
	label(r, "⚡ Performance mode", UDim2.new(0.62, 0, 0, 22), UDim2.fromOffset(10, 6))
	local d = label(r, "Fewer traffic cars and people. Smoother on older phones.", UDim2.new(1, -20, 0, 32),
		UDim2.fromOffset(10, 32), Color3.fromRGB(200, 190, 230))
	d.TextWrapped = true
	button(r, perf and "ON" or "OFF", UDim2.new(0.28, 0, 0, 26), UDim2.new(0.7, -6, 0, 4), perf and MINT or PANEL, function()
		Settings.Set("Performance", not perf)
		show("Settings")
	end).Name = "Toggle"
	local keys = label(s, "Keys: P phone (gamepad: D-pad down) · E enter/use · F exit · Space drift · Shift nitro · H horn/siren · V radio · R flip",
		UDim2.new(1, 0, 0, 40), nil, Color3.fromRGB(160, 150, 190), Enum.TextXAlignment.Center)
	keys.TextWrapped = true
	keys.LayoutOrder = 4
end

local PAGES = {
	Home = homePage,
	Feed = feedPage,
	Homes = homesPage,
	Settings = settingsPage,
	Crew = crewPage,
	Goals = goalsPage,
	Shop = shopPage,
	Garage = garagePage,
	Custom = customPage,
	Dealer = dealerPage,
	GPS = gpsPage,
	Jobs = jobsPage,
}
local current = "Home"

show = function(name)
	-- Re-showing the same page (after a purchase, say) keeps the scroll position.
	local old = screen:FindFirstChild("List")
	local keep = name == current and old and old.CanvasPosition
	current = name
	clear()
	PAGES[name]()
	local new = screen:FindFirstChild("List")
	if keep and new then
		task.defer(function()
			new.CanvasPosition = keep
		end)
	end
end

------------------------------------------------------------------ phone shell

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Phone"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	openButton = Instance.new("TextButton")
	openButton.Name = "PhoneButton"
	openButton.Position = UDim2.new(0, 108, 0, 188) -- beside the CAR button
	openButton.Size = UDim2.fromOffset(84, 40)
	openButton.BackgroundColor3 = DARK
	openButton.BackgroundTransparency = 0.2
	openButton.Font = FONT
	openButton.TextScaled = true
	openButton.TextColor3 = PINK
	openButton.Text = "PHONE"
	openButton.Parent = gui
	corner(openButton, UDim.new(0.5, 0))
	stroke(openButton, PINK, 2)
	local op = Instance.new("UIPadding")
	op.PaddingTop, op.PaddingBottom = UDim.new(0, 7), UDim.new(0, 7)
	op.PaddingLeft, op.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	op.Parent = openButton
	openButton.Activated:Connect(function()
		PhoneUI.Toggle()
	end)

	-- The phone is laid out at a fixed design width (360) and scaled to the screen with a UIScale,
	-- so text and buttons keep their proportions from a small phone to a big monitor.
	phone = Instance.new("Frame")
	phone.Name = "Body"
	phone.AnchorPoint = Vector2.new(1, 0.5)
	phone.Position = UDim2.new(1, -16, 0.5, 0)
	phone.Size = UDim2.fromOffset(DESIGN_W, 690)
	phone.BackgroundColor3 = DARK
	phone.Visible = false
	phone.Parent = gui
	corner(phone, UDim.new(0, 28))
	stroke(phone, PINK, 3)
	fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = phone

	-- Status bar: clock and cash.
	clockLabel = label(phone, "12:00", UDim2.fromOffset(110, 20), UDim2.fromOffset(28, 18), WHITE)
	cashLabel = label(phone, "$0", UDim2.fromOffset(150, 20), UDim2.fromOffset(DESIGN_W - 178, 18), MINT, Enum.TextXAlignment.Right)

	backButton = button(phone, "‹ BACK", UDim2.fromOffset(96, 34), UDim2.fromOffset(20, 50), PANEL, function()
		if back then
			show(back)
		end
	end)
	backButton.Name = "Back"
	titleLabel = label(phone, "NEON PHONE", UDim2.fromOffset(210, 30), UDim2.fromOffset(DESIGN_W - 230, 52), PINK, Enum.TextXAlignment.Right)

	screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Position = UDim2.fromOffset(20, 96)
	screen.BackgroundTransparency = 1
	screen.ClipsDescendants = true
	screen.Parent = phone

	homeBar = button(phone, "", UDim2.fromOffset(110, 10), UDim2.fromOffset(DESIGN_W / 2 - 55, 660), Color3.fromRGB(80, 70, 110), function()
		if current == "Home" then
			PhoneUI.Close()
		else
			show("Home")
		end
	end)
	homeBar.Name = "HomeBar"
	homeBar:FindFirstChildOfClass("UIPadding"):Destroy()
end

-- Fit the phone to the screen: scale 0.7-1.1 by screen height, then as tall as the screen allows.
local function fitToScreen()
	local vp = Workspace.CurrentCamera.ViewportSize
	local scale = math.clamp(vp.Y / 720, 0.7, 1.1)
	local height = math.min(math.floor(vp.Y * 0.92 / scale), 720)
	fit.Scale = scale
	phone.Size = UDim2.fromOffset(DESIGN_W, height)
	screen.Size = UDim2.fromOffset(DESIGN_W - 40, height - 96 - 40)
	homeBar.Position = UDim2.fromOffset(DESIGN_W / 2 - 55, height - 26)
end

local function refreshStatus()
	local t = Lighting.ClockTime
	local h = math.floor(t)
	local m = math.floor((t - h) * 60)
	local ampm = h >= 12 and "PM" or "AM"
	local h12 = h % 12
	clockLabel.Text = string.format("%d:%02d %s", h12 == 0 and 12 or h12, m, ampm)
	cashLabel.Text = money(player:GetAttribute("Cash") or 0)
end

function PhoneUI.IsOpen()
	return phone.Visible
end

function PhoneUI.Open(pageName)
	if player:GetAttribute("Side") == "Prisoner" then
		NotifyController.Show("Phones are confiscated in prison. Try the vent...", Color3.fromRGB(255, 138, 61))
		return
	end
	fitToScreen()
	phone.Visible = true
	refreshStatus()
	show(pageName or "Home")
	-- Slide up from below, like pulling a phone out of a pocket.
	phone.Position = UDim2.new(1, -16, 1.2, 0)
	TweenService:Create(phone, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(1, -16, 0.5, 0) }):Play()
end

function PhoneUI.Close()
	phone.Visible = false
end

function PhoneUI.Toggle()
	if phone.Visible then
		PhoneUI.Close()
	else
		PhoneUI.Open()
	end
end

function PhoneUI.Init()
	build()
	fitToScreen()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.P or input.KeyCode == Enum.KeyCode.DPadDown then
			PhoneUI.Toggle()
		end
	end)
	-- Keep open pages fresh when the server changes what we own or how our cars look.
	local function maybeRefresh()
		if phone.Visible and (current == "Garage" or current == "Custom" or current == "Dealer" or current == "Shop"
			or current == "Goals" or current == "Crew" or current == "Jobs" or current == "Homes") then
			show(current)
		end
	end
	player.AttributeChanged:Connect(function(name)
		if name == "OwnedCars" or string.sub(name, 1, 7) == "Custom_" or string.sub(name, 1, 5) == "Pass_"
			or string.sub(name, 1, 7) == "Unlock_" or name == "Challenges" or name == "CivXP" or name == "CopXP"
			or name == "Crew" or name == "FriendBonus" or name == "MissionsDone" or name == "GusFound"
			or name == "GusTotal" or name == "OwnedProps" or name == "HomeId" or string.sub(name, 1, 5) == "Rent_"
			or name == "CivRank" then
			maybeRefresh()
		elseif name == "Cash" and phone.Visible then
			refreshStatus()
		elseif name == "Side" then
			openButton.Visible = player:GetAttribute("Side") ~= "Prisoner"
			if player:GetAttribute("Side") == "Prisoner" then
				PhoneUI.Close()
			else
				maybeRefresh()
			end
		end
	end)
	-- Property moments (PropertyService): a stamp for a new home and for rent collected at the door.
	Remotes.OnClient("PropertyEvent", function(kind, info)
		info = type(info) == "table" and info or {}
		if kind == "Bought" then
			HUDController.Stamp("NEW HOME!", tostring(info.Name or "Your place") .. (info.Home and " is your home now" or " is yours"),
				ORANGE)
		elseif kind == "Rent" and type(info.Amount) == "number" then
			HUDController.Stamp("RENT COLLECTED", "+" .. money(info.Amount), MINT)
		end
	end)
	-- Door prompts (Workspace.Properties, attributes PropId / PropAction): only the ones that apply
	-- to this player. The server re-checks every action anyway.
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(function()
				local folder = Workspace:FindFirstChild("Properties")
				if not folder then
					return
				end
				local mine = {}
				for id in string.gmatch(player:GetAttribute("OwnedProps") or "", "[^,]+") do
					mine[id] = true
				end
				local home = player:GetAttribute("HomeId")
				local citizen = player:GetAttribute("Side") == "Civilian"
				for _, pp in ipairs(folder:GetDescendants()) do
					local id = pp:IsA("ProximityPrompt") and pp:GetAttribute("PropId")
					if id then
						local action = pp:GetAttribute("PropAction")
						local on = true
						if action == "Buy" then
							on = citizen and not mine[id]
						elseif action == "SetHome" then
							on = mine[id] == true and home ~= id
						elseif action == "Collect" then
							on = mine[id] == true
						end
						if pp.Enabled ~= on then
							pp.Enabled = on
						end
					end
				end
			end)
		end
	end)
	-- New Coast Feed posts: refresh the FEED page, or the unread badge on the home screen.
	FeedController.OnPost(function()
		if phone.Visible and (current == "Feed" or current == "Home") then
			show(current)
		end
	end)
	Remotes.OnClient("GarageResult", function(result)
		local def = Vehicles.ById[result.Id]
		local name = def and (def.DisplayName or def.Id) or "car"
		if result.Kind == "Bought" then
			HUDController.Stamp("NEW RIDE!", name .. " is in your Garage", PINK)
		elseif result.Kind == "Painted" then
			NotifyController.Show("Fresh paint on your " .. name .. "!", PINK)
		elseif result.Kind == "Rims" then
			NotifyController.Show("New rims on your " .. name .. "!", CYAN)
		elseif result.Kind == "Glow" then
			NotifyController.Show("Underglow set on your " .. name .. "!", PURPLE)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			-- On touch screens the PHONE button sits where the steering thumb goes: hide it while driving.
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local driving = hum ~= nil and hum.SeatPart ~= nil
			openButton.Visible = player:GetAttribute("Side") ~= "Prisoner"
				and not (driving and UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
			if phone.Visible and os.clock() % 5 < 0.5 then
				refreshStatus()
			end
		end
	end)
end

return PhoneUI
