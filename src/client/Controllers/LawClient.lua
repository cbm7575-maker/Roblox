-- LawClient (ModuleScript, StarterPlayerScripts.Controllers.LawClient)
-- Client side of the wanted system, police tools and prison:
--   * Which prompts you see: Cuff (cops, on wanted players and wanted drivers), Vent (prisoners).
--   * Cops: TASER (T) and SPIKES (G) buttons; markers for wanted players at their LastSeen spot:
--     a red beacon while spotted, a search circle (150 + 50 per star) while hollow.
--   * Taser zap beams, stun flash, and the big stamps: CAUGHT! (with a mugshot headline),
--     BOUNTY +$X, BREAKOUT!
--   * Prisoners: release countdown and the breakout hint.
-- The server checks every action; this file only shows things and asks.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local LawClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local ORANGE = Color3.fromRGB(255, 138, 61)
local RED = Color3.fromRGB(255, 60, 60)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne
local TASER_RANGE = 32

-- Kid-safe "Florida Man" headlines for the mugshot stamp.
local HEADLINES = {
	"Local Legend Arrested for Stealing 400 Rubber Ducks",
	"Suspect Claims a Gator 'Made Them Do It'",
	"Beach Bandit Busted Mid-Sunburn",
	"Driver Pulled Over for Excessive Neon",
	"Getaway Foiled by Flip-Flop Malfunction",
	"Robber Caught Paying for Snacks With Stolen Cash",
	"Man Tries to Outrun Police on a Pool Noodle",
	"Suspect Blames Flamingo for Wrong Turn",
}

local gui, taserButton, spikeButton, prisonLabel
local markers = {} -- [player] = { beacon = Part, circle = Part }
local markerFolder

local function now()
	return Workspace:GetServerTimeNow()
end

local function side()
	return player:GetAttribute("Side")
end

local function isWanted(p)
	return p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) > 0
end

local function myRoot()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return char and char:FindFirstChild("HumanoidRootPart"), hum
end

local function makeButton(name, text, color, pos)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = pos
	b.Size = UDim2.fromScale(0.11, 0.11)
	b.SizeConstraint = Enum.SizeConstraint.RelativeYY
	b.BackgroundColor3 = DARK
	b.BackgroundTransparency = 0.2
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = color
	b.Text = text
	b.Visible = false
	b.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.25, 0), UDim.new(0.25, 0)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.1, 0), UDim.new(0.1, 0)
	pad.Parent = b
	return b
end

-- Nearest wanted player on foot in range, preferring whoever is in front of the camera.
local function taserTarget()
	local root = myRoot()
	if not root then
		return nil
	end
	local camLook = Workspace.CurrentCamera.CFrame.LookVector
	local best, bestScore
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and isWanted(p) and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 and not h.SeatPart then
				local offset = r.Position - root.Position
				local dist = offset.Magnitude
				if dist <= TASER_RANGE then
					local facing = offset.Unit:Dot(camLook)
					local score = dist - facing * 12
					if not bestScore or score < bestScore then
						best, bestScore = p, score
					end
				end
			end
		end
	end
	return best
end

local function fireTaser()
	local target = taserTarget()
	if target then
		Remotes.Event("RequestTaser"):FireServer(target)
	else
		NotifyController.Show("No wanted suspect in taser range.", CYAN)
	end
end

local function dropSpikes()
	Remotes.Event("RequestSpike"):FireServer()
end

local function onAction(name, state)
	if state ~= Enum.UserInputState.Begin or side() ~= "Cop" then
		return Enum.ContextActionResult.Pass
	end
	if name == "NC_Taser" then
		fireTaser()
	elseif name == "NC_Spike" then
		dropSpikes()
	end
	return Enum.ContextActionResult.Sink
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "LawUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	taserButton = makeButton("Taser", "TASER", CYAN, UDim2.new(1, -20, 0.36, 0))
	spikeButton = makeButton("Spikes", "SPIKES", CYAN, UDim2.new(1, -20, 0.5, 0))
	taserButton.Activated:Connect(fireTaser)
	spikeButton.Activated:Connect(dropSpikes)

	prisonLabel = Instance.new("TextLabel")
	prisonLabel.Name = "Prison"
	prisonLabel.AnchorPoint = Vector2.new(0.5, 0)
	prisonLabel.Position = UDim2.new(0.5, 0, 0, 60)
	prisonLabel.Size = UDim2.fromScale(0.5, 0.09)
	prisonLabel.BackgroundColor3 = DARK
	prisonLabel.BackgroundTransparency = 0.2
	prisonLabel.Font = FONT
	prisonLabel.TextScaled = true
	prisonLabel.TextColor3 = ORANGE
	prisonLabel.Visible = false
	prisonLabel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.3, 0)
	c.Parent = prisonLabel
	local p = Instance.new("UIPadding")
	p.PaddingTop, p.PaddingBottom = UDim.new(0.12, 0), UDim.new(0.12, 0)
	p.Parent = prisonLabel

	markerFolder = Instance.new("Folder")
	markerFolder.Name = "WantedMarkers"
	markerFolder.Parent = Workspace.CurrentCamera -- local-only parts

	ContextActionService:BindAction("NC_Taser", onAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction("NC_Spike", onAction, false, Enum.KeyCode.G)
end

local function marker(p)
	local m = markers[p]
	if m then
		return m
	end
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.Transparency = 1
	beacon.Size = Vector3.new(1, 1, 1)
	beacon.Parent = markerFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 64)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.MaxDistance = 2000
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextScaled = true
	t.TextStrokeTransparency = 0.2
	t.Parent = bb
	bb.Parent = beacon
	local circle = Instance.new("Part")
	circle.Name = "SearchCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Anchored = true
	circle.CanCollide = false
	circle.CanQuery = false
	circle.CanTouch = false
	circle.Material = Enum.Material.Neon
	circle.Color = RED
	circle.Transparency = 0.85
	circle.Parent = markerFolder
	m = { beacon = beacon, label = t, circle = circle }
	markers[p] = m
	return m
end

local function clearMarker(p)
	local m = markers[p]
	if m then
		m.beacon:Destroy()
		m.circle:Destroy()
		markers[p] = nil
	end
end

local function updateMarkers()
	local amCop = side() == "Cop"
	for _, p in ipairs(Players:GetPlayers()) do
		local lastSeen = p:GetAttribute("LastSeen")
		if amCop and p ~= player and isWanted(p) and typeof(lastSeen) == "Vector3" then
			local m = marker(p)
			local heat = p:GetAttribute("Heat") or 1
			local spotted = p:GetAttribute("HeatSpotted") == true
			local pos = lastSeen
			-- While spotted, follow the real character if it's streamed in (smoother than LastSeen).
			if spotted and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				pos = p.Character.HumanoidRootPart.Position
			end
			m.beacon.Position = pos
			-- Suspect Card: whatever the cameras and cops have seen.
			local clues = {}
			if p:GetAttribute("SuspectCar") then
				table.insert(clues, p:GetAttribute("SuspectCar"))
			end
			if p:GetAttribute("SuspectOutfit") then
				table.insert(clues, p:GetAttribute("SuspectOutfit"))
			end
			m.label.Text = (spotted and "WANTED " or "LAST SEEN ") .. string.rep("★", heat)
				.. (#clues > 0 and ("\n" .. table.concat(clues, " / ")) or "")
			m.label.TextColor3 = spotted and RED or ORANGE
			local radius = 150 + 50 * heat
			m.circle.Transparency = spotted and 1 or 0.85
			m.circle.Size = Vector3.new(1, radius * 2, radius * 2)
			m.circle.CFrame = CFrame.new(lastSeen.X, 0.3, lastSeen.Z) * CFrame.Angles(0, 0, math.rad(90))
		else
			clearMarker(p)
		end
	end
	for p in pairs(markers) do
		if not p.Parent then
			clearMarker(p)
		end
	end
end

local function setPrompt(prompt, show)
	if prompt and prompt.Enabled ~= show then
		prompt.Enabled = show
	end
end

local function updatePrompts()
	local amCop = side() == "Cop"
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		setPrompt(root and root:FindFirstChild("CuffPrompt"), amCop and p ~= player and isWanted(p))
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, car in ipairs(vehicles:GetChildren()) do
			local seat = car:FindFirstChild("DriverSeat")
			local driverId = car:GetAttribute("DriverUserId")
			local driver = driverId and Players:GetPlayerByUserId(driverId)
			setPrompt(seat and seat:FindFirstChild("CuffDriver"), amCop and driver ~= nil and driver ~= player and isWanted(driver))
			-- Hot cars: only citizens can pick the lock, and only before someone has stolen it.
			setPrompt(seat and seat:FindFirstChild("PickLockPrompt"), side() == "Civilian" and car:GetAttribute("ThiefUserId") == nil)
		end
	end
	local city = Workspace:FindFirstChild("City")
	local vent = city and city:FindFirstChild("PrisonVent", true)
	setPrompt(vent and vent:FindFirstChild("VentPrompt"), side() == "Prisoner" and vent:GetAttribute("Open") ~= true)
end

local function updateUI()
	local amCop = side() == "Cop"
	local root, hum = myRoot()
	local onFoot = hum ~= nil and hum.SeatPart == nil
	taserButton.Visible = amCop and onFoot
	spikeButton.Visible = amCop
	spikeButton.Text = "SPIKES x" .. tostring(player:GetAttribute("SpikeCharges") or 0)
	if side() == "Prisoner" then
		local left = math.max(0, math.floor((player:GetAttribute("ReleaseAt") or 0) - now()))
		prisonLabel.Visible = true
		prisonLabel.Text = string.format("RELEASE IN %d:%02d  -  or pry open the south-wall vent and swim for it!", left // 60, left % 60)
	else
		prisonLabel.Visible = false
	end
	-- Stunned: keep the character down on this device while the server's stun lasts.
	if hum then
		local stunned = (player:GetAttribute("StunnedUntil") or 0) > now()
		if hum.PlatformStand ~= stunned and not hum.SeatPart then
			hum.PlatformStand = stunned
		end
	end
end

local function zap(cop, target)
	local a = cop.Character and cop.Character:FindFirstChild("HumanoidRootPart")
	local b = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not a or not b then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Parent = a
	local a1 = Instance.new("Attachment")
	a1.Parent = b
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = ColorSequence.new(CYAN)
	beam.LightEmission = 1
	beam.Width0, beam.Width1 = 0.4, 0.4
	beam.CurveSize0, beam.CurveSize1 = 2, -2
	beam.FaceCamera = true
	beam.Parent = a
	task.delay(0.35, function()
		beam:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
	if target == player then
		NotifyController.Show("ZAPPED! You're stunned.", CYAN)
	end
end

function LawClient.Init()
	build()
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				updatePrompts()
				updateMarkers()
				updateUI()
			end)
			if not ok then
				warn("[LawClient] " .. tostring(err))
			end
			task.wait(0.2)
		end
	end)
	Remotes.OnClient("TaserFx", zap)
	Remotes.OnClient("Caught", function(info)
		HUDController.Stamp("CAUGHT!", HEADLINES[math.random(1, #HEADLINES)], PINK)
	end)
	Remotes.OnClient("BountyEarned", function(info)
		HUDController.Stamp("BOUNTY", "+" .. HUDController.Money(info.Amount) .. " for catching " .. info.Name, CYAN)
	end)
	Remotes.OnClient("BrokeOut", function()
		HUDController.Stamp("BREAKOUT!", "You're wanted again. Run!", ORANGE)
	end)
end

return LawClient
