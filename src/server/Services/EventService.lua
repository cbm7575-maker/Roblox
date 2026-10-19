-- EventService (ModuleScript, ServerScriptService.Services.EventService)
-- "Florida moments" (PRD 3.8): every few minutes something odd happens somewhere in Port Solana,
-- announced on the Coast Feed and marked on the minimap (ReplicatedStorage attribute "Events": JSON
-- list of { n = name, x, z }, one entry per marker; an event can have several, like the treasure).
--   GatorVisit    a gator wanders into a store; first player to shoo it (hold 2 s) gets $300
--   BeachTreasure three glinting spots on Flamingo Beach; dig each (hold 3 s) for $150-600; it ends
--                 when the last one is dug
--   UFO           night only (by the clock): a saucer hovers over Gator Glades; wave hello for $500
--   Performer     day only: a street drummer at Solana Plaza; watch the show (hold 3 s) for $100 once
--   BeachParty    night only: neon, music and dancers by the pier; join the party (hold 2 s) for $150 once
--   Flamingo      a flamingo runs loose on Flamingo Beach; first to catch it (it runs, then tires) gets $250
--   LostTourist   a lost tourist somewhere in town; first to give directions (hold 1.5 s) gets $200
-- Rewards are server-checked (ProximityPrompt + distance, once per player where it says so). Kid-safe and
-- silly on purpose. Moments come every ~4 minutes with some jitter, more often in fuller servers, at most
-- MAX_ACTIVE at once and never two of the same kind. Day/night moments end when the sky turns.
-- Props the clients animate: event peds (Models with attributes Anim + Lines, PedClient), parts with
-- Spin / Disco (SkyClient) and MusicId (SoundClient); Models with Obstacle = true are ones ambient
-- traffic stops for (TrafficClient).
--   EventService.RunRandom(name?) starts a random moment that fits right now, or the named one
--   ("GatorVisit", "BeachTreasure", "UFO", "Performer", "BeachParty", "Flamingo", "LostTourist") even if
--   it doesn't (Studio testing). EventService.Finish(id) ends one.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local EventService = {}

local EVERY = RunService:IsStudio() and 60 or 240 -- average seconds between events (one player)
local JITTER = 0.3 -- +-30%
local MAX_ACTIVE = 3
local DAWN, DUSK = 5.75, 18.25 -- clock hours where Workspace.IsNight flips (WorldService)

local rng = Random.new()
local folder, feed, notify
local active = {} -- [id] = { name, kind, pos, markers?, cleanup, conns }
local nextId = 0

local PINK = Color3.fromRGB(255, 62, 165)
local MINT = Color3.fromRGB(110, 242, 196)
local GOLD = Color3.fromRGB(255, 214, 10)

local function publish()
	local list = {}
	for _, e in pairs(active) do
		if e.markers then
			for _, p in ipairs(e.markers) do
				table.insert(list, { n = e.name, x = math.floor(p.X), z = math.floor(p.Z) })
			end
		else
			table.insert(list, { n = e.name, x = math.floor(e.pos.X), z = math.floor(e.pos.Z) })
		end
	end
	ReplicatedStorage:SetAttribute("Events", HttpService:JSONEncode(list))
end

local function start(kind, name, pos, seconds, cleanup, markers)
	nextId += 1
	local id = nextId
	active[id] = { kind = kind, name = name, pos = pos, markers = markers, cleanup = cleanup, conns = {} }
	publish()
	task.delay(math.max(seconds, 5), function()
		EventService.Finish(id)
	end)
	return id
end

function EventService.Finish(id)
	local e = active[id]
	if not e then
		return
	end
	active[id] = nil
	for _, c in ipairs(e.conns) do
		c:Disconnect()
	end
	pcall(e.cleanup)
	publish()
end

local function reward(player, cash, what)
	EconomyService.AddCash(player, cash, "event:" .. what)
	require(ServerScriptService.Services.ProgressService).Event(player, "FloridaMoment")
	Telemetry.Custom(player, "Event_" .. what, cash)
end

local function prompt(parent, action, object, hold, range)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = range or 14
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = parent
	return p
end

local function near(player, part, range)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - part.Position).Magnitude <= range
end

local function part(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

-- Ground height at (x, z), never players, cars or event props. By default only the district ground
-- tiles and terrain count (so nothing lands on a beach umbrella); withArt = true also counts pavements
-- and plazas, from just above head height down.
local function groundAt(x, z, fallback, withArt)
	local list: { Instance } = { Workspace.Terrain }
	local city = Workspace:FindFirstChild("City")
	local ground = city and city:FindFirstChild("Ground")
	if withArt and city then
		table.insert(list, city)
	elseif ground then
		table.insert(list, ground)
	end
	groundParams.FilterDescendantsInstances = list
	local top = withArt and 6 or 60
	local hit = Workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -top - 60, 0), groundParams)
	return hit and hit.Position.Y or fallback or 0
end

-- Seconds until the sky turns (night = true: until dawn).
local function timeLeft(night)
	local ok, s = pcall(function()
		return require(ServerScriptService.Services.WorldService).SecondsUntil(night and DAWN or DUSK)
	end)
	return ok and type(s) == "number" and s or 240
end

local function clock()
	local ok, c = pcall(function()
		return require(ServerScriptService.Services.WorldService).Clock()
	end)
	return ok and type(c) == "number" and c or game:GetService("Lighting").ClockTime
end

local function isNight()
	return Workspace:GetAttribute("IsNight") == true
end

-- End the event when day turns to night (night = false) or night to day (night = true).
local function endWithSky(id, night)
	local e = active[id]
	if e then
		table.insert(e.conns, Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
			if isNight() ~= night then
				EventService.Finish(id)
			end
		end))
	end
end

local function radioTrack(stationName, trackName)
	for _, station in ipairs(Sounds.Radio or {}) do
		if station.Name == stationName then
			for _, t in ipairs(station.Tracks) do
				if t.Name == trackName then
					return t.Id
				end
			end
			return station.Tracks[1] and station.Tracks[1].Id
		end
	end
	return nil
end

-- A pedestrian prop standing at `cf` (ground level, facing its look vector). PedClient plays `anim`
-- ("idle", "dance", "dance2", "dance3", "cheer", "wave", "point") and has it say lines from
-- Config.PedLines[lines] now and then.
local function makePed(parent, cf, anim, lines)
	local templates = ReplicatedStorage:FindFirstChild("PedTemplates")
	local list = templates and templates:GetChildren() or {}
	local model
	if #list > 0 then
		model = list[rng:NextInteger(1, #list)]:Clone()
	else
		local ok, m = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if not ok or not m then
			return nil
		end
		model = m
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	root.Anchored = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	model.Name = "EventPed"
	model:SetAttribute("Anim", anim)
	model:SetAttribute("Lines", lines)
	model:PivotTo(cf + Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0))
	model.Parent = parent
	return model
end

local function billboard(adornee, text, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 60)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(18, 14, 30)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
	return gui
end

------------------------------------------------------------------ events

local function gatorVisit()
	local heists = Workspace:FindFirstChild("Heists")
	local sites = {}
	for _, site in ipairs(heists and heists:GetChildren() or {}) do
		local id = site:GetAttribute("HeistId")
		if id == "GlowMart" or id == "FuelStop" or id == "ClubNova" or id == "SparkleCo" then
			table.insert(sites, site)
		end
	end
	if #sites == 0 then
		return false
	end
	local site = sites[rng:NextInteger(1, #sites)]
	local base = site:IsA("Model") and site:GetPivot().Position or (site :: BasePart).Position
	local pos = Vector3.new(base.X + rng:NextNumber(-6, 6), 0.2, base.Z + rng:NextNumber(-6, 6))
	local model = Instance.new("Model")
	model.Name = "EventGator"
	local template = ServerStorage:FindFirstChild("ArtAssets") and ServerStorage.ArtAssets:FindFirstChild("Gator")
	local body
	if template and template:IsA("BasePart") then
		body = template:Clone()
		body.Anchored = true
		body.CanCollide = false
		body.Size = body.Size * 3.5
		body.CFrame = CFrame.new(pos + Vector3.new(0, body.Size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		body.Parent = model
	else
		body = part(model, Vector3.new(3, 2, 9), CFrame.new(pos + Vector3.new(0, 1, 0)), Color3.fromRGB(70, 120, 60))
	end
	model.PrimaryPart = body
	model.Parent = folder
	local display = site:GetAttribute("Display") or "a store"
	local p = prompt(body, "Shoo the gator", "Gator", 2)
	local id
	p.Triggered:Connect(function(player)
		if not active[id] or not near(player, body, 18) then
			return
		end
		reward(player, 300, "Gator")
		feed:FireAllClients("EventDone", { Name = player.DisplayName, Text = "shooed the gator out of " .. display })
		EventService.Finish(id)
	end)
	id = start("GatorVisit", "Gator at " .. display, pos, 180, function()
		model:Destroy()
	end)
	feed:FireAllClients("Event", { Text = "A gator just strolled into " .. display .. "! First one to shoo it gets $300." })
	return true
end

local function beachTreasure()
	local markers = {}
	local parts = {}
	local id
	for _ = 1, 3 do
		local x, z = rng:NextNumber(1160, 1440), rng:NextNumber(-1750, 450)
		local pos = Vector3.new(x, groundAt(x, z, 0) + 0.3, z)
		local glint = part(folder, Vector3.new(1.6, 1.6, 1.6), CFrame.new(pos), GOLD, Enum.Material.Neon,
			{ Name = "Treasure", Shape = Enum.PartType.Ball })
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(255, 240, 160)
		sparkle.Parent = glint
		table.insert(parts, glint)
		table.insert(markers, pos)
		local p = prompt(glint, "Dig", "Something shiny", 3)
		p.Triggered:Connect(function(player)
			if not active[id] or not glint.Parent or not near(player, glint, 16) then
				return
			end
			local cash = rng:NextInteger(3, 12) * 50
			glint:Destroy()
			local i = table.find(markers, pos)
			if i then
				table.remove(markers, i)
			end
			reward(player, cash, "Treasure")
			notify:FireClient(player, "TreasureFound")
			if #markers == 0 then
				feed:FireAllClients("EventDone", { Name = player.DisplayName, Text = "dug up the last treasure on Flamingo Beach" })
				EventService.Finish(id)
			else
				publish()
			end
		end)
	end
	id = start("BeachTreasure", "Beach treasure", markers[1], 240, function()
		for _, g in ipairs(parts) do
			g:Destroy()
		end
	end, markers)
	feed:FireAllClients("Event", { Text = "Metal detectors are beeping on Flamingo Beach. Look for something shiny!" })
	return true
end

local function ufo()
	local left = timeLeft(true)
	local pos = Vector3.new(rng:NextNumber(-1700, -1100), 60, rng:NextNumber(-1200, 600))
	local model = Instance.new("Model")
	model.Name = "EventUFO"
	-- The disc spins on each client (SkyClient, attribute Spin), not every server frame.
	part(model, Vector3.new(3, 30, 30), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(190, 200, 220),
		Enum.Material.Metal, { Name = "Disc", Shape = Enum.PartType.Cylinder }):SetAttribute("Spin", 1.5)
	part(model, Vector3.new(12, 12, 12), CFrame.new(pos + Vector3.new(0, 3, 0)), MINT, Enum.Material.Neon,
		{ Name = "Dome", Shape = Enum.PartType.Ball, Transparency = 0.2 })
	part(model, Vector3.new(58, 14, 14), CFrame.new(pos - Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)), MINT,
		Enum.Material.Neon, { Name = "Beam", Shape = Enum.PartType.Cylinder, Transparency = 0.75 })
	local base = part(model, Vector3.new(4, 4, 4), CFrame.new(pos.X, groundAt(pos.X, pos.Z, 0) + 2, pos.Z), Color3.new(1, 1, 1),
		nil, { Name = "Contact", Transparency = 1 })
	model.Parent = folder
	local waved = {}
	local p = prompt(base, "Wave hello", "???", 1)
	local id
	p.Triggered:Connect(function(player)
		if not active[id] or waved[player] or not near(player, base, 18) then
			return
		end
		waved[player] = true
		reward(player, 500, "UFO")
		notify:FireClient(player, "UFOWave")
	end)
	id = start("UFO", "Strange lights", pos, math.min(240, left - 3), function()
		model:Destroy()
	end)
	endWithSky(id, true)
	feed:FireAllClients("Event", { Text = "Strange lights over Gator Glades tonight... anyone else seeing this? 👽" })
	return true
end

local function performer()
	local left = timeLeft(false)
	local x, z = -15, -202 -- Solana Plaza, north of the fountain, facing it
	local y = groundAt(x, z, 0.1, true)
	local model = Instance.new("Model")
	model.Name = "EventPerformer"
	local face = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, -250))
	part(model, Vector3.new(0.2, 9, 9), face * CFrame.Angles(0, 0, math.rad(90)) + Vector3.new(0, 0.06, 0), PINK, Enum.Material.Neon,
		{ Name = "Stage", Shape = Enum.PartType.Cylinder, Transparency = 0.35, CanQuery = false })
	-- A drum and the hat for tips, in front of the performer.
	part(model, Vector3.new(1.6, 2.4, 2.4), face * CFrame.new(-2.2, 1.2, -1.2) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(34, 225, 255), Enum.Material.SmoothPlastic, { Name = "Drum", Shape = Enum.PartType.Cylinder })
	local hat = part(model, Vector3.new(0.6, 1.6, 1.6), face * CFrame.new(1.8, 0.3, -2.6) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(40, 30, 50), Enum.Material.SmoothPlastic, { Name = "TipHat", Shape = Enum.PartType.Cylinder })
	hat:SetAttribute("MusicId", (Sounds.EventMusic or {}).Performer or radioTrack("Gator Radio", "Be Steel My Beating Drum"))
	billboard(hat, "🥁", GOLD)
	makePed(model, face, "dance2", "Performer")
	model.Parent = folder
	local watched = {}
	local p = prompt(hat, "Watch the show", "Street performer", 3)
	local id
	p.Triggered:Connect(function(player)
		if not active[id] or watched[player] or not near(player, hat, 18) then
			return
		end
		watched[player] = true
		reward(player, 100, "Performer")
		notify:FireClient(player, "PerformerTip")
	end)
	id = start("Performer", "Street performer", Vector3.new(x, y, z), math.min(200, left - 3), function()
		model:Destroy()
	end)
	endWithSky(id, false)
	feed:FireAllClients("Event", { Text = "A street drummer is pulling a crowd at Solana Plaza. Come watch the show!" })
	return true
end

local function beachParty()
	local left = timeLeft(true)
	local cx, cz = 1395, -455 -- on the sand beside the pier entrance
	local y = groundAt(cx, cz, 0)
	local c = Vector3.new(cx, y, cz)
	local model = Instance.new("Model")
	model.Name = "EventBeachParty"
	-- Dance floor: 3 x 3 glowing tiles cycling colours (SkyClient Disco).
	for i = -1, 1 do
		for k = -1, 1 do
			part(model, Vector3.new(7.6, 0.2, 7.6), CFrame.new(c + Vector3.new(i * 8, 0.1, k * 8)), PINK, Enum.Material.Neon,
				{ Name = "Floor", Transparency = 0.25, CanQuery = false }):SetAttribute("Disco", true)
		end
	end
	-- Light poles with coloured lamps.
	for _, corner in ipairs({ Vector3.new(-15, 0, -15), Vector3.new(15, 0, -15), Vector3.new(-15, 0, 15), Vector3.new(15, 0, 15) }) do
		part(model, Vector3.new(0.6, 12, 0.6), CFrame.new(c + corner + Vector3.new(0, 6, 0)), Color3.fromRGB(40, 36, 56),
			Enum.Material.Metal, { Name = "Pole" })
		local lamp = part(model, Vector3.new(1.6, 1.6, 1.6), CFrame.new(c + corner + Vector3.new(0, 12.4, 0)), MINT, Enum.Material.Neon,
			{ Name = "Lamp", Shape = Enum.PartType.Ball })
		lamp:SetAttribute("Disco", true)
		local light = Instance.new("PointLight")
		light.Range = 28
		light.Brightness = 1.6
		light.Color = Color3.fromRGB(255, 120, 200)
		light.Parent = lamp
	end
	-- DJ booth at the back of the floor (music source and the prompt), facing the dancers.
	local booth = part(model, Vector3.new(6, 3.4, 3), CFrame.lookAt(c + Vector3.new(0, 1.7, -17), c + Vector3.new(0, 1.7, 0)),
		Color3.fromRGB(24, 20, 36), Enum.Material.SmoothPlastic, { Name = "DJBooth" })
	local trim = part(model, Vector3.new(6.2, 0.4, 3.2), booth.CFrame * CFrame.new(0, 1.8, 0), PINK, Enum.Material.Neon,
		{ Name = "BoothTrim" })
	trim:SetAttribute("Disco", true)
	booth:SetAttribute("MusicId", (Sounds.EventMusic or {}).BeachParty or radioTrack("Palm 99", "Dance With You"))
	billboard(booth, "🎶", PINK)
	makePed(model, CFrame.lookAt(c + Vector3.new(0, 0, -19.5), c), "dance", "Party")
	local moves = { "dance", "dance2", "dance3", "cheer" }
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local p = c + Vector3.new(math.cos(a) * rng:NextNumber(3, 9), 0, math.sin(a) * rng:NextNumber(3, 9))
		makePed(model, CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z)), moves[rng:NextInteger(1, #moves)], "Party")
	end
	model.Parent = folder
	local joined = {}
	local p = prompt(booth, "Join the party", "Beach party", 2, 16)
	local id
	p.Triggered:Connect(function(player)
		if not active[id] or joined[player] or not near(player, booth, 22) then
			return
		end
		joined[player] = true
		reward(player, 150, "BeachParty")
		notify:FireClient(player, "PartyJoined")
	end)
	id = start("BeachParty", "Beach party", c, math.min(220, left - 3), function()
		model:Destroy()
	end)
	endWithSky(id, true)
	feed:FireAllClients("Event", { Text = "Beach party by the pier tonight! Neon, music and dancing. Everyone's invited!" })
	return true
end

-- The beach sand (x, z) where the flamingo may roam.
local BEACH_MIN, BEACH_MAX = Vector2.new(1100, -1730), Vector2.new(1470, 420)

local function flamingo()
	local x, z = rng:NextNumber(1150, 1420), rng:NextNumber(-1500, 200)
	local y = groundAt(x, z, 0)
	local model = Instance.new("Model")
	model.Name = "EventFlamingo"
	-- One anchored root that moves; the look is welded to it.
	local root = part(model, Vector3.new(2, 4.6, 2), CFrame.new(x, y + 2.3, z), Color3.new(1, 1, 1), nil,
		{ Name = "Root", Transparency = 1 })
	local template = ServerStorage:FindFirstChild("ArtAssets") and ServerStorage.ArtAssets:FindFirstChild("FlamingoStatue")
	if template and template:IsA("BasePart") then
		local body = template:Clone()
		body.Anchored = false
		body.CanCollide = false
		body.CanQuery = false
		body.Massless = true
		body.Size = body.Size * (4.6 / math.max(body.Size.Y, 1))
		body.CFrame = root.CFrame
		body.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = root, body
		weld.Parent = root
	else
		local pink = Color3.fromRGB(255, 120, 190)
		local bits = {
			part(model, Vector3.new(1.6, 1.4, 2.4), root.CFrame * CFrame.new(0, 0.6, 0), pink, nil, { Name = "Body" }),
			part(model, Vector3.new(0.4, 2, 0.4), root.CFrame * CFrame.new(0, 2, -0.9), pink, nil, { Name = "Neck" }),
			part(model, Vector3.new(0.7, 0.7, 0.9), root.CFrame * CFrame.new(0, 3, -1.1), pink, nil, { Name = "Head" }),
			part(model, Vector3.new(0.2, 1.9, 0.2), root.CFrame * CFrame.new(0, -1.2, 0), Color3.fromRGB(230, 90, 150), nil, { Name = "Leg" }),
		}
		for _, b in ipairs(bits) do
			b.Anchored = false
			b.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = root, b
			weld.Parent = root
		end
	end
	model.PrimaryPart = root
	model:SetAttribute("Obstacle", true) -- traffic stops for it (TrafficClient)
	model.Parent = folder
	billboard(root, "🦩", PINK).StudsOffset = Vector3.new(0, 4.5, 0)
	local p = prompt(root, "Catch the flamingo", "Runaway flamingo", 0.5, 11)
	local id
	p.Triggered:Connect(function(player)
		if not active[id] or not near(player, root, 15) then
			return
		end
		reward(player, 250, "Flamingo")
		notify:FireClient(player, "FlamingoCaught")
		feed:FireAllClients("EventDone", { Name = player.DisplayName, Text = "caught the runaway flamingo" })
		EventService.Finish(id)
	end)
	-- It wanders; when someone comes close it runs (a bit slower than a player), then gets tired.
	local state, stateUntil = "wander", 0
	local target = Vector3.new(x, y, z)
	local baseY = y + 2.3
	local acc = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 20 then
			return
		end
		local step = acc
		acc = 0
		local now = os.clock()
		local here = root.Position
		local flat = Vector3.new(here.X, 0, here.Z)
		local chaser, chaserD
		for _, plr in ipairs(Players:GetPlayers()) do
			local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				local d = (Vector3.new(r.Position.X, 0, r.Position.Z) - flat).Magnitude
				if d < 26 and (not chaserD or d < chaserD) then
					chaser, chaserD = r, d
				end
			end
		end
		if state == "tired" and now > stateUntil then
			state = "wander"
		end
		if state ~= "tired" and chaser then
			if state ~= "flee" then
				state, stateUntil = "flee", now + 3
			elseif now > stateUntil then
				state, stateUntil = "tired", now + 2.5
			end
		elseif state == "flee" then
			state = "wander"
		end
		local dir, speed = Vector3.zero, 0
		if state == "flee" and chaser then
			local away = flat - Vector3.new(chaser.Position.X, 0, chaser.Position.Z)
			dir = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
			speed = 13
		elseif state == "wander" then
			local to = Vector3.new(target.X, 0, target.Z) - flat
			if to.Magnitude < 3 then
				target = Vector3.new(math.clamp(here.X + rng:NextNumber(-40, 40), BEACH_MIN.X, BEACH_MAX.X), 0,
					math.clamp(here.Z + rng:NextNumber(-40, 40), BEACH_MIN.Y, BEACH_MAX.Y))
			else
				dir = to.Unit
				speed = 5
			end
		end
		if speed > 0 then
			local nx = math.clamp(here.X + dir.X * speed * step, BEACH_MIN.X, BEACH_MAX.X)
			local nz = math.clamp(here.Z + dir.Z * speed * step, BEACH_MIN.Y, BEACH_MAX.Y)
			local moved = Vector3.new(nx - here.X, 0, nz - here.Z)
			local look = moved.Magnitude > 0.01 and moved.Unit or root.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude < 0.01 then
				look = Vector3.new(0, 0, -1)
			end
			-- A little bob while it runs.
			local bob = state == "flee" and math.abs(math.sin(now * 14)) * 0.4 or 0
			local pos = Vector3.new(nx, baseY + bob, nz)
			root.CFrame = CFrame.lookAt(pos, pos + look.Unit)
		end
		-- Keep the minimap marker roughly on it.
		local e = active[id]
		if e and (e.pos - here).Magnitude > 25 then
			e.pos = here
			publish()
		end
	end)
	id = start("Flamingo", "Runaway flamingo", root.Position, 240, function()
		conn:Disconnect()
		model:Destroy()
	end)
	feed:FireAllClients("Event", { Text = "A flamingo escaped from the beach show and is running loose on Flamingo Beach! Catch it for $250." })
	return true
end

local TOURIST_SPOTS = {
	{ x = -15, z = -286, where = "Solana Plaza" },
	{ x = 200, z = -1486, where = "the Palm Hills shops" },
	{ x = 710, z = 974, where = "the Marina Row promenade" },
	{ x = 1072, z = -1600, where = "the beach boardwalk" },
	{ x = -224, z = 24, where = "the taxi stand" },
}

local function lostTourist()
	local spot = TOURIST_SPOTS[rng:NextInteger(1, #TOURIST_SPOTS)]
	local y = groundAt(spot.x, spot.z, 0, true)
	local pos = Vector3.new(spot.x, y, spot.z)
	local model = Instance.new("Model")
	model.Name = "EventTourist"
	local face = CFrame.lookAt(pos, pos + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) + Vector3.new(0.01, 0, 0))
	local ped = makePed(model, face, "point", "Tourist")
	-- A big paper map in their hands and a sun hat.
	part(model, Vector3.new(2.4, 1.6, 0.1), face * CFrame.new(0, 3.6, -1.3) * CFrame.Angles(math.rad(-20), 0, 0),
		Color3.fromRGB(250, 240, 200), nil, { Name = "Map", CanQuery = false })
	part(model, Vector3.new(0.3, 3, 3), face * CFrame.new(0, 6.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 214, 120),
		nil, { Name = "SunHat", Shape = Enum.PartType.Cylinder, CanQuery = false })
	local spotPart = part(model, Vector3.new(3, 5, 3), face + Vector3.new(0, 2.5, 0), Color3.new(1, 1, 1), nil,
		{ Name = "Ask", Transparency = 1 })
	billboard(spotPart, "?", GOLD).StudsOffset = Vector3.new(0, 4.5, 0)
	if not ped then
		part(model, Vector3.new(1.6, 5, 1), face + Vector3.new(0, 2.5, 0), Color3.fromRGB(255, 150, 130), nil, { Name = "Body" })
	end
	model.Parent = folder
	local p = prompt(spotPart, "Give directions", "Lost tourist", 1.5)
	local id
	p.Triggered:Connect(function(player)
		if not active[id] or not near(player, spotPart, 18) then
			return
		end
		reward(player, 200, "Tourist")
		notify:FireClient(player, "TouristHelped")
		feed:FireAllClients("EventDone", { Name = player.DisplayName, Text = "helped a lost tourist find the beach" })
		EventService.Finish(id)
	end)
	id = start("LostTourist", "Lost tourist", pos, 180, function()
		model:Destroy()
	end)
	feed:FireAllClients("Event", { Text = "A lost tourist near " .. spot.where .. " is turning their map upside down. First helper gets $200!" })
	return true
end

-- when(): can it start right now? (time of day by the clock)
local EVENTS = {
	{ name = "GatorVisit", fn = gatorVisit, weight = 3 },
	{ name = "BeachTreasure", fn = beachTreasure, weight = 3 },
	{ name = "UFO", fn = ufo, weight = 2, when = function()
		local c = clock()
		return (c >= 19 or c < 4.5) and isNight() and timeLeft(true) > 60
	end },
	{ name = "Performer", fn = performer, weight = 2, when = function()
		local c = clock()
		return c >= 8 and c < 17 and not isNight() and timeLeft(false) > 60
	end },
	{ name = "BeachParty", fn = beachParty, weight = 3, when = function()
		return isNight() and timeLeft(true) > 60
	end },
	{ name = "Flamingo", fn = flamingo, weight = 2 },
	{ name = "LostTourist", fn = lostTourist, weight = 2 },
}

local function running(name)
	for _, e in pairs(active) do
		if e.kind == name then
			return true
		end
	end
	return false
end

function EventService.RunRandom(name)
	if name then
		for _, e in ipairs(EVENTS) do
			if e.name == name and not running(name) then
				return e.fn()
			end
		end
		return false
	end
	local pool, total = {}, 0
	for _, e in ipairs(EVENTS) do
		if not running(e.name) and (not e.when or e.when()) then
			table.insert(pool, e)
			total += e.weight
		end
	end
	local roll = rng:NextNumber(0, total)
	for _, e in ipairs(pool) do
		roll -= e.weight
		if roll <= 0 then
			return e.fn()
		end
	end
	return false
end

local function activeCount()
	local n = 0
	for _ in pairs(active) do
		n += 1
	end
	return n
end

function EventService.Init()
	feed = Remotes.Event("Feed")
	notify = Remotes.Event("Notify")
	folder = Workspace:FindFirstChild("Events") or Instance.new("Folder")
	folder.Name = "Events"
	folder.Parent = Workspace
	publish()
	task.spawn(function()
		while true do
			-- More players, more moments (up to about twice as often), with jitter.
			local players = #Players:GetPlayers()
			local scale = 1 + math.clamp(players - 1, 0, 16) * 0.07
			task.wait(EVERY / scale * rng:NextNumber(1 - JITTER, 1 + JITTER))
			if #Players:GetPlayers() > 0 and activeCount() < MAX_ACTIVE then
				local ok, err = pcall(EventService.RunRandom)
				if not ok then
					warn("[EventService] " .. tostring(err))
				end
			end
		end
	end)
end

return EventService
