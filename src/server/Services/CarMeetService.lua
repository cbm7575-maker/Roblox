-- CarMeetService (ModuleScript, ServerScriptService.Services.CarMeetService)
-- Neon Nights Car Meet (PRD Phase 6): a show lot at Marina Row. Every few minutes a meet runs:
--   * Park your own car on one of the 6 glowing show spots and step out: it's on show.
--   * Other players press "Like" on shown cars (once per car per meet): $150 to the owner each.
--   * NPC fans drop a few likes too, so it pays even in a quiet server.
--   * When the meet ends, the car with the most likes is the Crowd Favourite: +$1,000.
-- The lot is built at start-up if the place doesn't have it (Workspace.Activities.CarMeet).
-- Workspace attributes: CarMeetState ("Idle" | "Soon" | "Live"), CarMeetEndsAt (server time).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local CarMeetService = {}

CarMeetService.Center = Vector3.new(620, 0, 780)
local EVERY = RunService:IsStudio() and 150 or 480 -- seconds between meets
local WARNING = 60
local LENGTH = 180
local LIKE_PAY = 150
local LIKE_CAP = 10 -- paid likes per car per meet
local NPC_CAP = 5
local FAVOURITE_BONUS = 1000

local lot, spots = nil, {}
local shown = {} -- [car] = { owner, likes, npc, likedBy = {}, gui, prompt }
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
	local base = part(lot, Vector3.new(130, 0.3, 90), CFrame.new(c.X, 0.12, c.Z), Color3.fromRGB(46, 44, 60), Enum.Material.Asphalt,
		{ Name = "Lot", CanCollide = true })
	lot.PrimaryPart = base
	-- 6 show spots in two rows, facing the middle aisle.
	local i = 0
	for _, row in ipairs({ -1, 1 }) do
		for k = -1, 1 do
			i += 1
			local pos = Vector3.new(c.X + k * 36, 0.3, c.Z + row * 26)
			local spot = part(lot, Vector3.new(16, 0.1, 26), CFrame.new(pos), i % 2 == 0 and Color3.fromRGB(34, 225, 255) or Color3.fromRGB(255, 62, 165),
				Enum.Material.Neon, { Name = "ShowSpot", CanCollide = false, CanQuery = false, Transparency = 0.55 })
			spot:SetAttribute("Index", i)
			spots[i] = spot
		end
	end
	-- Sign on two posts at the back.
	for _, x in ipairs({ -30, 30 }) do
		part(lot, Vector3.new(1.5, 22, 1.5), CFrame.new(c.X + x, 11, c.Z + 48), Color3.fromRGB(60, 60, 75), Enum.Material.Metal, { Name = "Post" })
	end
	local board = part(lot, Vector3.new(66, 10, 1), CFrame.new(c.X, 24, c.Z + 48), Color3.fromRGB(20, 16, 30), Enum.Material.SmoothPlastic, { Name = "Sign" })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.Brightness = 2.5
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 62, 165)
		label.Text = "NEON NIGHTS CAR MEET"
		label.Parent = gui
		gui.Parent = board
	end
	-- A few lamps.
	for _, x in ipairs({ -60, 60 }) do
		for _, z in ipairs({ -40, 40 }) do
			part(lot, Vector3.new(0.8, 14, 0.8), CFrame.new(c.X + x, 7, c.Z + z), Color3.fromRGB(60, 60, 75), Enum.Material.Metal, { Name = "Lamp" })
			local head = part(lot, Vector3.new(2.5, 0.6, 2.5), CFrame.new(c.X + x, 14.2, c.Z + z), Color3.fromRGB(255, 214, 10), Enum.Material.Neon,
				{ Name = "LampHead", CanCollide = false })
			local light = Instance.new("PointLight")
			light.Range = 40
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(255, 200, 160)
			light.Parent = head
		end
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

local function updateTag(rec)
	if rec.gui then
		rec.gui.Label.Text = "♥ " .. (rec.likes + rec.npc) .. "   " .. (rec.owner.DisplayName or "")
	end
end

local function show(car, owner)
	local chassis = car.PrimaryPart
	local rec = { owner = owner, likes = 0, npc = 0, likedBy = {} }
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
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 62, 165)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Adornee = chassis
	gui.Parent = chassis
	rec.gui = gui
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LikePrompt"
	prompt.ActionText = "Like ♥"
	prompt.ObjectText = (owner.DisplayName or "") .. "'s " .. (car:GetAttribute("DisplayName") or "car")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = chassis
	rec.prompt = prompt
	prompt.Triggered:Connect(function(fan)
		if fan == owner or rec.likedBy[fan] or not shown[car] then
			return
		end
		rec.likedBy[fan] = true
		rec.likes += 1
		updateTag(rec)
		if rec.likes <= LIKE_CAP and owner.Parent then
			EconomyService.AddCash(owner, LIKE_PAY, "carmeet:like")
			Remotes.Event("Notify"):FireClient(owner, "CarMeetLike")
		end
	end)
	shown[car] = rec
	updateTag(rec)
end

local function unshow(car)
	local rec = shown[car]
	shown[car] = nil
	if rec then
		if rec.gui then
			rec.gui:Destroy()
		end
		if rec.prompt then
			rec.prompt:Destroy()
		end
	end
end

local function finish()
	local best, bestLikes
	for car, rec in pairs(shown) do
		local total = rec.likes + rec.npc
		if not bestLikes or total > bestLikes then
			best, bestLikes = rec, total
		end
	end
	if best and best.owner.Parent and bestLikes > 0 then
		EconomyService.AddCash(best.owner, FAVOURITE_BONUS, "carmeet:favourite")
		Remotes.Event("CarMeetResult"):FireClient(best.owner, { Favourite = true, Bonus = FAVOURITE_BONUS })
		feed:FireAllClients("Event", { Text = best.owner.DisplayName .. "'s ride was Crowd Favourite at the car meet!" })
		Telemetry.Custom(best.owner, "CarMeetFavourite", bestLikes)
	end
	for car, rec in pairs(shown) do
		if rec.owner.Parent then
			require(ServerScriptService.Services.ProgressService).Event(rec.owner, "Mission", 40)
		end
		unshow(car)
	end
end

local function runMeet()
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
			for _, rec in pairs(shown) do
				if rec.npc < NPC_CAP and math.random() < 0.7 then
					rec.npc += 1
					updateTag(rec)
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
