-- CarMeetService (ModuleScript, ServerScriptService.Services.CarMeetService)
-- Neon Nights Car Meet (PRD Phase 6): a show lot at Marina Row. Every few minutes a meet runs:
--   * Park your own car on one of the 6 show spots (painted bays) and step out: it's on show.
--   * Other players press "Like" on shown cars (once per owner per meet): $150 to the owner each.
--   * NPC fans drop a few likes too, so it pays even in a quiet server.
--   * Likes are kept per owner for the whole meet, so re-parking doesn't reset them (or the caps).
--   * When the meet ends, the owner with the most likes is the Crowd Favourite: +$1,000.
-- The lot is built at start-up (Workspace.Activities.CarMeet, replacing any copy in the place).
-- Its look follows Look 3.0 (Tools.Look3): dark asphalt with white bay lines and a concrete kerb, steel
-- floodlight poles, a dark sign board with white letters, a charcoal DJ tent. The meet's one accent colour
-- (pink) is kept to trim: the tent's thin valance, two feather flags, the sign's rule. The neon (sign
-- outline, an LED strip at the head of each show bay, string lights, the DJ booth) is dark metal by day
-- and only glows after dark (tag "NightNeon", attribute NeonColor), and the floodlights only light up
-- after dark (tag "NightLamp", attribute LampColor): SkyClient switches both on every client. The show
-- spots are invisible triggers over the paint.
-- All the dressing stays inside the lot's old outline (CombatService's safe zone is the model's
-- bounding box) and nothing new collides.
-- Workspace attributes: CarMeetState ("Idle" | "Soon" | "Live"), CarMeetEndsAt (server time).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local CarMeetService = {}

CarMeetService.Center = Vector3.new(620, 0, 780)
local EVERY = RunService:IsStudio() and 150 or 480 -- seconds between meets
local WARNING = 60
local LENGTH = 180
local LIKE_PAY = 150
local LIKE_CAP = 10 -- paid likes per owner per meet
local NPC_CAP = 5
local FAVOURITE_BONUS = 1000

-- Look 3.0 colours (Tools.Look3).
local ASPHALT = Color3.fromRGB(54, 54, 58)
local PAINT = Color3.fromRGB(232, 232, 226)
local KERB = Color3.fromRGB(176, 174, 168)
local STEEL = Color3.fromRGB(96, 100, 106) -- galvanised floodlight poles
local DARK = Color3.fromRGB(58, 60, 66) -- frames and housings; also unlit neon (SkyClient's day colour)
local BOARD = Color3.fromRGB(26, 28, 32)
local PINK = Color3.fromRGB(255, 62, 165) -- the meet's one accent colour
local CYAN = Color3.fromRGB(34, 225, 255) -- (night glow only)
local FESTOON = Color3.fromRGB(255, 206, 140)
local FLOOD = Color3.fromRGB(255, 236, 214)
local LAMP_DAY = Color3.fromRGB(226, 226, 220) -- a lamp lens by day (SkyClient's NightLamp day colour)

local lot, spots = nil, {}
local meetRecs = {} -- [owner UserId] = { owner, likes, npc, likedBy = {} }, kept for the whole meet
local shown = {} -- [car] = { rec, gui, prompt } for cars on a show spot right now
local feed

local function now()
	return Workspace:GetServerTimeNow()
end

local function part(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- Dressing: nothing collides with it, rays and touches pass through it, and it casts no shadow
-- unless `props` says so.
local function detail(parent, name, size, cf, color, material, props)
	local all = { Name = name, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	for k, v in pairs(props or {}) do
		all[k] = v
	end
	return part(parent, size, cf, color, material, all)
end

-- Look 3.0 neon: dark metal by day, glows in `color` after dark (SkyClient).
local function nightNeon(p, color)
	p.Material = Enum.Material.Metal
	p.Color = DARK
	p:SetAttribute("NeonColor", color)
	CollectionService:AddTag(p, "NightNeon")
	return p
end

-- A lamp lens: pale by day, lit in `color` after dark along with the Light inside it (SkyClient).
local function nightLamp(p, color)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = LAMP_DAY
	p:SetAttribute("LampColor", color)
	CollectionService:AddTag(p, "NightLamp")
	return p
end

local function buildLot()
	local acts = Workspace:FindFirstChild("Activities") or Instance.new("Folder")
	acts.Name = "Activities"
	acts.Parent = Workspace
	lot = acts:FindFirstChild("CarMeet")
	if lot then
		lot:Destroy()
	end
	lot = Instance.new("Model")
	lot.Name = "CarMeet"
	local c = CarMeetService.Center
	local base = part(lot, Vector3.new(130, 0.3, 90), CFrame.new(c.X, 0.12, c.Z), ASPHALT, Enum.Material.Asphalt,
		{ Name = "Lot", CanCollide = true, CastShadow = false })
	lot.PrimaryPart = base
	local top = 0.27 -- the lot's surface
	-- A concrete kerb round the edge (dressing only: cars still meet the lot's own low edge).
	for _, sz in ipairs({ -1, 1 }) do
		detail(lot, "Kerb", Vector3.new(130, 0.34, 0.8), CFrame.new(c.X, 0.28, c.Z + sz * 44.6), KERB, Enum.Material.Concrete)
	end
	for _, sx in ipairs({ -1, 1 }) do
		detail(lot, "Kerb", Vector3.new(0.8, 0.34, 88.4), CFrame.new(c.X + sx * 64.6, 0.28, c.Z), KERB, Enum.Material.Concrete)
	end
	-- 6 show spots in two rows, facing the middle aisle. The spots are invisible triggers: what shows is
	-- the paint (white bay lines) and an LED strip at the head of each bay that glows pink or cyan at night.
	local i = 0
	for _, row in ipairs({ -1, 1 }) do
		for k = -1, 1 do
			i += 1
			local pos = Vector3.new(c.X + k * 36, 0.3, c.Z + row * 26)
			local glow = i % 2 == 0 and CYAN or PINK
			local spot = part(lot, Vector3.new(16, 0.1, 26), CFrame.new(pos), glow, Enum.Material.SmoothPlastic,
				{ Name = "ShowSpot", CanCollide = false, CanQuery = false, Transparency = 1, CastShadow = false })
			spot:SetAttribute("Index", i)
			spots[i] = spot
			for _, x in ipairs({ -8, 8 }) do
				detail(lot, "BayLine", Vector3.new(0.4, 0.05, 26), CFrame.new(pos.X + x, top + 0.03, pos.Z), PAINT)
			end
			detail(lot, "BayLine", Vector3.new(16.4, 0.05, 0.4), CFrame.new(pos.X, top + 0.03, pos.Z + row * 13), PAINT)
			nightNeon(detail(lot, "BayGlow", Vector3.new(15, 0.06, 0.3), CFrame.new(pos.X, top + 0.03, pos.Z + row * 13.8), DARK), glow)
		end
	end
	-- Dashed centre line down the aisle (the dash texture repeats along the part's X).
	local dash = detail(lot, "AisleLine", Vector3.new(100, 0.05, 0.6), CFrame.new(c.X, top + 0.03, c.Z), PAINT, nil, { Transparency = 1 })
	local dashTex = Instance.new("Texture")
	dashTex.Name = "Dash"
	dashTex.Face = Enum.NormalId.Top
	dashTex.Texture = Textures.Zebra
	dashTex.StudsPerTileU = 14
	dashTex.StudsPerTileV = 0.6
	dashTex.Parent = dash
	-- Sign on two steel posts at the back: a dark board with white letters, outlined in pink neon that
	-- only glows at night (four strips wrapping the board's edges, so both faces get it).
	for _, x in ipairs({ -30, 30 }) do
		part(lot, Vector3.new(1.5, 22, 1.5), CFrame.new(c.X + x, 11, c.Z + 48), DARK, Enum.Material.Metal, { Name = "Post" })
	end
	local board = part(lot, Vector3.new(66, 10, 1), CFrame.new(c.X, 24, c.Z + 48), BOARD, Enum.Material.Metal, { Name = "Sign" })
	for _, y in ipairs({ -4.75, 4.75 }) do
		nightNeon(detail(lot, "SignNeon", Vector3.new(65.4, 0.3, 1.3), CFrame.new(c.X, 24 + y, c.Z + 48), DARK), PINK)
	end
	for _, x in ipairs({ -32.75, 32.75 }) do
		nightNeon(detail(lot, "SignNeon", Vector3.new(0.3, 9.2, 1.3), CFrame.new(c.X + x, 24, c.Z + 48), DARK), PINK)
	end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.Brightness = 1
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.9, 0.58)
		label.Position = UDim2.fromScale(0.05, 0.1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Oswald
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(245, 245, 240)
		label.Text = "NEON NIGHTS CAR MEET"
		label.Parent = gui
		local rule = Instance.new("Frame")
		rule.BorderSizePixel = 0
		rule.BackgroundColor3 = PINK
		rule.Size = UDim2.fromScale(0.3, 0.025)
		rule.Position = UDim2.fromScale(0.35, 0.71)
		rule.Parent = gui
		local small = Instance.new("TextLabel")
		small.Size = UDim2.fromScale(0.8, 0.14)
		small.Position = UDim2.fromScale(0.1, 0.77)
		small.BackgroundTransparency = 1
		small.Font = Enum.Font.GothamBold
		small.TextScaled = true
		small.TextColor3 = Color3.fromRGB(196, 198, 204)
		small.Text = "MARINA ROW  ·  SHOW YOUR RIDE"
		small.Parent = gui
		gui.Parent = board
	end
	-- Four floodlight poles on concrete footings: pale lenses under dark housings by day, they light the
	-- lot after dark (SkyClient).
	for _, x in ipairs({ -60, 60 }) do
		for _, z in ipairs({ -40, 40 }) do
			part(lot, Vector3.new(0.8, 14, 0.8), CFrame.new(c.X + x, 7, c.Z + z), STEEL, Enum.Material.Metal, { Name = "Lamp" })
			detail(lot, "Footing", Vector3.new(1.6, 1, 1.6), CFrame.new(c.X + x, 0.5, c.Z + z), KERB, Enum.Material.Concrete)
			detail(lot, "LampHousing", Vector3.new(3, 0.5, 3), CFrame.new(c.X + x, 14.75, c.Z + z), DARK, Enum.Material.Metal)
			local head = part(lot, Vector3.new(2.5, 0.6, 2.5), CFrame.new(c.X + x, 14.2, c.Z + z), LAMP_DAY, Enum.Material.SmoothPlastic,
				{ Name = "LampHead", CanCollide = false, CastShadow = false })
			nightLamp(head, FLOOD)
			local light = Instance.new("SpotLight")
			light.Name = "Flood"
			light.Face = Enum.NormalId.Bottom
			light.Angle = 120
			light.Range = 48
			light.Brightness = 2.2
			light.Color = FLOOD
			light.Shadows = false
			light.Enabled = false -- SkyClient switches it on after dark
			light.Parent = head
		end
	end
	-- String lights between the poles along both rows: a dark cable by day, warm bulbs at night.
	for _, z in ipairs({ -40, 40 }) do
		local a = Vector3.new(c.X - 60, 13.4, c.Z + z)
		local mid = Vector3.new(c.X, 11.6, c.Z + z)
		local b = Vector3.new(c.X + 60, 13.4, c.Z + z)
		for _, seg in ipairs({ { a, mid }, { mid, b } }) do
			local p0, p1 = seg[1], seg[2]
			nightNeon(detail(lot, "StringLights", Vector3.new(0.16, 0.16, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), DARK), FESTOON)
		end
	end
	-- A DJ tent beside the east end of the north row: charcoal canopy with a thin pink valance (a skirt
	-- round its edge, so the underside is the charcoal roof), a draped table facing the lot, two speakers.
	local tent = CFrame.new(c.X + 54, top, c.Z + 26)
	for _, x in ipairs({ -4.8, 4.8 }) do
		for _, z in ipairs({ -4.8, 4.8 }) do
			detail(lot, "TentLeg", Vector3.new(0.3, 8.6, 0.3), tent * CFrame.new(x, 4.3, z), DARK, Enum.Material.Metal)
		end
	end
	detail(lot, "TentRoof", Vector3.new(10.6, 0.4, 10.6), tent * CFrame.new(0, 8.8, 0), Color3.fromRGB(44, 46, 52), Enum.Material.Fabric,
		{ CastShadow = true })
	for _, s in ipairs({ -1, 1 }) do
		detail(lot, "TentValance", Vector3.new(10.4, 0.8, 0.1), tent * CFrame.new(0, 8.2, s * 5.15), PINK, Enum.Material.Fabric)
		detail(lot, "TentValance", Vector3.new(0.1, 0.8, 10.2), tent * CFrame.new(s * 5.15, 8.2, 0), PINK, Enum.Material.Fabric)
	end
	detail(lot, "DJTable", Vector3.new(2.4, 2.8, 6), tent * CFrame.new(-2.6, 1.4, 0), Color3.fromRGB(28, 28, 32), Enum.Material.Fabric)
	detail(lot, "Decks", Vector3.new(1.6, 0.3, 4), tent * CFrame.new(-2.6, 2.95, 0), DARK, Enum.Material.Metal)
	nightNeon(detail(lot, "DJGlow", Vector3.new(0.1, 0.25, 5.6), tent * CFrame.new(-3.85, 2.3, 0), DARK), CYAN)
	for _, z in ipairs({ -4.2, 4.2 }) do
		detail(lot, "Speaker", Vector3.new(2, 4.4, 2), tent * CFrame.new(-2.6, 2.2, z), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic)
	end
	-- Two feather flags in the meet's colour beside the sign.
	for _, x in ipairs({ -50, 50 }) do
		detail(lot, "FlagPole", Vector3.new(0.3, 12, 0.3), CFrame.new(c.X + x, 6, c.Z + 46.5), Color3.fromRGB(200, 200, 204), Enum.Material.Metal)
		detail(lot, "Flag", Vector3.new(2.4, 8, 0.1), CFrame.new(c.X + x + 1.35, 7.6, c.Z + 46.5), PINK, Enum.Material.Fabric)
	end
	lot.Parent = acts
end

-- Which show spot (if any) is this parked car on?
local function spotOf(car)
	local chassis = car.PrimaryPart
	if not chassis then
		return nil
	end
	for i, spot in ipairs(spots) do
		local rel = spot.CFrame:PointToObjectSpace(chassis.Position)
		if math.abs(rel.X) < 10 and math.abs(rel.Z) < 15 and math.abs(rel.Y) < 8 then
			return i
		end
	end
	return nil
end

local function updateTag(entry)
	if entry.gui then
		entry.gui.Label.Text = "♥ " .. (entry.rec.likes + entry.rec.npc) .. "   " .. (entry.rec.owner.DisplayName or "")
	end
end

local function show(car, owner)
	local chassis = car.PrimaryPart
	-- Reuse this owner's record from earlier in the meet: getting in and out mustn't reset likes or caps.
	local rec = meetRecs[owner.UserId] or { likes = 0, npc = 0, likedBy = {} }
	rec.owner = owner -- the current Player object, in case they rejoined
	meetRecs[owner.UserId] = rec
	local entry = { rec = rec }
	local gui = Instance.new("BillboardGui")
	gui.Name = "MeetTag"
	gui.Size = UDim2.fromOffset(180, 34)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.MaxDistance = 250
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Oswald
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 62, 165)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Adornee = chassis
	gui.Parent = chassis
	entry.gui = gui
	-- The Like bubble is for everybody but the owner: a server can't hide a prompt from one player, so
	-- LawClient switches it off on the owner's own device (there it did nothing and took the E key, so E
	-- no longer got them back into their own car). The owner's press is still ignored below.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LikePrompt"
	prompt.ActionText = "Like ♥"
	prompt.ObjectText = (owner.DisplayName or "") .. "'s " .. (car:GetAttribute("DisplayName") or "car")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = chassis
	entry.prompt = prompt
	prompt.Triggered:Connect(function(fan)
		if fan == owner or rec.likedBy[fan.UserId] or shown[car] ~= entry then
			return
		end
		rec.likedBy[fan.UserId] = true -- by UserId, so rejoining doesn't give a fresh like
		rec.likes += 1
		updateTag(entry)
		if rec.likes <= LIKE_CAP and owner.Parent then
			EconomyService.AddCash(owner, LIKE_PAY, "carmeet:like")
			Remotes.Event("Notify"):FireClient(owner, "CarMeetLike")
		end
	end)
	shown[car] = entry
	updateTag(entry)
end

local function unshow(car)
	local entry = shown[car]
	shown[car] = nil
	if entry then
		if entry.gui then
			entry.gui:Destroy()
		end
		if entry.prompt then
			entry.prompt:Destroy()
		end
	end
end

local function finish()
	-- Rank every owner who showed a car this meet, even if they're back in the driver's seat now.
	local best, bestLikes
	for _, rec in pairs(meetRecs) do
		local total = rec.likes + rec.npc
		if rec.owner.Parent and (not bestLikes or total > bestLikes) then
			best, bestLikes = rec, total
		end
	end
	if best and bestLikes > 0 then
		EconomyService.AddCash(best.owner, FAVOURITE_BONUS, "carmeet:favourite")
		Remotes.Event("CarMeetResult"):FireClient(best.owner, { Favourite = true, Bonus = FAVOURITE_BONUS })
		feed:FireAllClients("Event", { Text = best.owner.DisplayName .. "'s ride was Crowd Favourite at the car meet!" })
		Telemetry.Custom(best.owner, "CarMeetFavourite", bestLikes)
	end
	for car, entry in pairs(shown) do
		if entry.rec.owner.Parent then
			require(ServerScriptService.Services.ProgressService).Event(entry.rec.owner, "Mission", 40)
		end
		unshow(car)
	end
	table.clear(meetRecs)
end

local function runMeet()
	table.clear(meetRecs)
	Workspace:SetAttribute("CarMeetState", "Soon")
	feed:FireAllClients("Event", { Text = "Car meet at Marina Row in 1 minute! Bring your best ride (GPS > FUN)." })
	task.wait(WARNING)
	Workspace:SetAttribute("CarMeetState", "Live")
	Workspace:SetAttribute("CarMeetEndsAt", now() + LENGTH)
	feed:FireAllClients("Event", { Text = "The Neon Nights car meet is ON at Marina Row: park on a show spot and collect likes!" })
	local ends = os.clock() + LENGTH
	local lastFans = os.clock()
	while os.clock() < ends do
		-- Parked, driverless own cars on a spot are on show; anything else comes off.
		local vehicles = Workspace:FindFirstChild("Vehicles")
		for _, car in ipairs(vehicles and vehicles:GetChildren() or {}) do
			local owner = Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
			local onSpot = owner and not car:GetAttribute("DriverUserId") and not car:GetAttribute("Boat") and spotOf(car)
			if onSpot and not shown[car] then
				show(car, owner)
			elseif not onSpot and shown[car] then
				unshow(car)
			end
		end
		for car in pairs(shown) do
			if not car.Parent then
				unshow(car)
			end
		end
		-- NPC fans.
		if os.clock() - lastFans > 15 then
			lastFans = os.clock()
			for _, entry in pairs(shown) do
				local rec = entry.rec
				if rec.npc < NPC_CAP and math.random() < 0.7 then
					rec.npc += 1
					updateTag(entry)
					if rec.owner.Parent then
						EconomyService.AddCash(rec.owner, LIKE_PAY, "carmeet:fan")
						Remotes.Event("Notify"):FireClient(rec.owner, "CarMeetFan")
					end
				end
			end
		end
		task.wait(1)
	end
	finish()
	Workspace:SetAttribute("CarMeetState", "Idle")
end

function CarMeetService.Init()
	feed = Remotes.Event("Feed")
	Remotes.Event("CarMeetResult")
	buildLot()
	Workspace:SetAttribute("CarMeetState", "Idle")
	task.spawn(function()
		while true do
			task.wait(EVERY)
			if #Players:GetPlayers() > 0 then
				local ok, err = pcall(runMeet)
				if not ok then
					warn("[CarMeetService] " .. tostring(err))
					Workspace:SetAttribute("CarMeetState", "Idle")
				end
			end
		end
	end)
end

-- Studio test hook (DebugService): start a meet now.
function CarMeetService.StartNow()
	task.spawn(runMeet)
end

return CarMeetService
