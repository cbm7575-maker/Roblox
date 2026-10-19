-- EventService (ModuleScript, ServerScriptService.Services.EventService)
-- "Florida moments" (PRD 3.8): every few minutes something odd happens somewhere in Port Solana,
-- announced on the Coast Feed and marked on the minimap (ReplicatedStorage attribute "Events").
--   GatorVisit    a gator wanders into a store; first player to shoo it (hold 2 s) gets $300
--   BeachTreasure three glinting spots on Flamingo Beach; dig each (hold 3 s) for $150-600
--   UFO           night only: a saucer hovers over Gator Glades; wave hello for $500
-- Rewards are server-checked (ProximityPrompt + distance). Kid-safe and silly on purpose.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local EventService = {}

local EVERY = RunService:IsStudio() and 60 or 240 -- seconds between events
local rng = Random.new()
local folder, feed, notify
local active = {} -- [id] = { name, pos, cleanup = fn }
local nextId = 0

local function publish()
	local list = {}
	for _, e in pairs(active) do
		table.insert(list, { n = e.name, x = math.floor(e.pos.X), z = math.floor(e.pos.Z) })
	end
	ReplicatedStorage:SetAttribute("Events", HttpService:JSONEncode(list))
end

local function start(name, pos, seconds, cleanup)
	nextId += 1
	local id = nextId
	active[id] = { name = name, pos = pos, cleanup = cleanup }
	publish()
	task.delay(seconds, function()
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
	pcall(e.cleanup)
	publish()
end

local function reward(player, cash, what)
	EconomyService.AddCash(player, cash, "event:" .. what)
	require(ServerScriptService.Services.ProgressService).Event(player, "FloridaMoment")
	Telemetry.Custom(player, "Event_" .. what, cash)
end

local function prompt(parent, action, object, hold)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = parent
	return p
end

local function near(player, part, range)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - part.Position).Magnitude <= range
end

------------------------------------------------------------------ events

local function gatorVisit()
	local sites = {}
	for _, site in ipairs(Workspace.Heists:GetChildren()) do
		local id = site:GetAttribute("HeistId")
		if id == "GlowMart" or id == "FuelStop" or id == "ClubNova" or id == "SparkleCo" then
			table.insert(sites, site)
		end
	end
	if #sites == 0 then
		return
	end
	local site = sites[rng:NextInteger(1, #sites)]
	local base = site:IsA("Model") and site:GetPivot().Position or site.Position
	local pos = Vector3.new(base.X + rng:NextNumber(-6, 6), 0.2, base.Z + rng:NextNumber(-6, 6))
	local model = Instance.new("Model")
	model.Name = "EventGator"
	local template = ServerStorage:FindFirstChild("ArtAssets") and ServerStorage.ArtAssets:FindFirstChild("Gator")
	local body
	if template then
		body = template:Clone()
		body.Anchored = true
		body.CanCollide = false
		body.Size = body.Size * 3.5
		body.CFrame = CFrame.new(pos + Vector3.new(0, body.Size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		body.Parent = model
	else
		body = Instance.new("Part")
		body.Anchored = true
		body.Size = Vector3.new(3, 2, 9)
		body.Color = Color3.fromRGB(70, 120, 60)
		body.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
		body.Parent = model
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
	id = start("Gator at " .. display, pos, 180, function()
		model:Destroy()
	end)
	feed:FireAllClients("Event", { Text = "A gator just strolled into " .. display .. "! First one to shoo it gets $300." })
end

local function beachTreasure()
	local spots = {}
	local parts = {}
	for i = 1, 3 do
		local pos = Vector3.new(rng:NextNumber(1160, 1440), 0.3, rng:NextNumber(-1750, 450))
		local glint = Instance.new("Part")
		glint.Name = "Treasure"
		glint.Anchored = true
		glint.CanCollide = false
		glint.Shape = Enum.PartType.Ball
		glint.Size = Vector3.new(1.6, 1.6, 1.6)
		glint.Material = Enum.Material.Neon
		glint.Color = Color3.fromRGB(255, 214, 10)
		glint.Position = pos
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(255, 240, 160)
		sparkle.Parent = glint
		glint.Parent = folder
		table.insert(parts, glint)
		table.insert(spots, pos)
		local p = prompt(glint, "Dig", "Something shiny", 3)
		p.Triggered:Connect(function(player)
			if not glint.Parent or not near(player, glint, 16) then
				return
			end
			local cash = rng:NextInteger(3, 12) * 50
			glint:Destroy()
			reward(player, cash, "Treasure")
			notify:FireClient(player, "TreasureFound")
		end)
	end
	local centre = (spots[1] + spots[2] + spots[3]) / 3
	start("Beach treasure", centre, 240, function()
		for _, g in ipairs(parts) do
			g:Destroy()
		end
	end)
	feed:FireAllClients("Event", { Text = "Metal detectors are beeping on Flamingo Beach. Look for something shiny!" })
end

local function ufo()
	local pos = Vector3.new(rng:NextNumber(-1700, -1100), 60, rng:NextNumber(-1200, 600))
	local model = Instance.new("Model")
	model.Name = "EventUFO"
	local disc = Instance.new("Part")
	disc.Anchored = true
	disc.CanCollide = false
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(3, 30, 30)
	disc.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = Color3.fromRGB(190, 200, 220)
	disc.Material = Enum.Material.Metal
	disc.Parent = model
	local dome = Instance.new("Part")
	dome.Anchored = true
	dome.CanCollide = false
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(12, 12, 12)
	dome.Position = pos + Vector3.new(0, 3, 0)
	dome.Color = Color3.fromRGB(110, 242, 196)
	dome.Material = Enum.Material.Neon
	dome.Transparency = 0.2
	dome.Parent = model
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(58, 14, 14)
	beam.CFrame = CFrame.new(pos - Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Color = Color3.fromRGB(110, 242, 196)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.75
	beam.Parent = model
	local base = Instance.new("Part")
	base.Name = "Contact"
	base.Anchored = true
	base.CanCollide = false
	base.Transparency = 1
	base.Size = Vector3.new(4, 4, 4)
	base.Position = Vector3.new(pos.X, 2, pos.Z)
	base.Parent = model
	model.Parent = folder
	local spin = RunService.Heartbeat:Connect(function(dt)
		disc.CFrame = disc.CFrame * CFrame.Angles(dt * 1.5, 0, 0)
	end)
	local waved = {}
	local p = prompt(base, "Wave hello", "???", 1)
	p.Triggered:Connect(function(player)
		if waved[player] or not near(player, base, 18) then
			return
		end
		waved[player] = true
		reward(player, 500, "UFO")
		notify:FireClient(player, "UFOWave")
	end)
	start("Strange lights", pos, 240, function()
		spin:Disconnect()
		model:Destroy()
	end)
	feed:FireAllClients("Event", { Text = "Strange lights over Gator Glades tonight... anyone else seeing this? 👽" })
end

local EVENTS = {
	{ fn = gatorVisit, weight = 3 },
	{ fn = beachTreasure, weight = 3 },
	{ fn = ufo, weight = 2, night = true },
}

function EventService.RunRandom()
	local night = Workspace:GetAttribute("IsNight") == true
	local pool, total = {}, 0
	for _, e in ipairs(EVENTS) do
		if not e.night or night then
			table.insert(pool, e)
			total += e.weight
		end
	end
	local roll = rng:NextNumber(0, total)
	for _, e in ipairs(pool) do
		roll -= e.weight
		if roll <= 0 then
			e.fn()
			return
		end
	end
end

function EventService.Init()
	feed = Remotes.Event("Feed")
	notify = Remotes.Event("Notify")
	folder = Instance.new("Folder")
	folder.Name = "Events"
	folder.Parent = Workspace
	publish()
	task.spawn(function()
		while true do
			task.wait(EVERY)
			if #Players:GetPlayers() > 0 then
				local ok, err = pcall(EventService.RunRandom)
				if not ok then
					warn("[EventService] " .. tostring(err))
				end
			end
		end
	end)
end

return EventService
