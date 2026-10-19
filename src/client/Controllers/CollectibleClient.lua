-- CollectibleClient (ModuleScript, StarterPlayerScripts.Controllers.CollectibleClient)
-- The Gus hunt on this device. CollectibleService owns the rules and the money; this only shows it.
--   * Figurines you already found (player attribute GusFoundIds) are hidden for you: their parts go
--     invisible (LocalTransparencyModifier), the prompt and the light switch off. Workspace.Collectibles
--     streams in and out, so every model is checked again whenever it (or a part of it) arrives.
--   * Detector: within 40 studs of a figurine you haven't found, its pedestal glow pulses and a soft
--     beep plays from its direction, quicker as you get closer (checked 4 times a second).
--   * GusFound: "GUS FOUND! 12/40" stamps; bigger ones (and confetti) for a finished district and for
--     the last figurine.
-- For the phone: CollectibleClient.Count() -> found, total; CollectibleClient.Hint(id) ->
-- "Solana Heights: behind the Coastal Bank"; CollectibleClient.NextHint() -> hint, id for the nearest
-- figurine you haven't found yet (nil when you have them all).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Collectibles = require(ReplicatedStorage.Shared.Config.Collectibles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local SoundClient = require(script.Parent:WaitForChild("SoundClient"))

local player = Players.LocalPlayer

local CollectibleClient = {}

local GATOR = Color3.fromRGB(120, 230, 100)
local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local GOLD = Color3.fromRGB(255, 214, 10)

local RANGE = 40 -- detector range (studs)
local TICK = 0.25 -- seconds between detector checks (4 Hz)
local PING_NEAR, PING_FAR = 0.8, 2 -- seconds between beeps right beside it / at the edge of the range
local PULSE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local BIG = { Big = true } -- stamp option: HUDController draws it larger when it supports it

local folder
local found = {} -- [id] = true, from GusFoundIds
local tracked = {} -- [model] = { id, model, pos, glow, light, bright, pulse, lightPulse }
local byId = {} -- [id] = record

------------------------------------------------------------------ hiding found figurines

local function readFound()
	found = {}
	for id in string.gmatch(player:GetAttribute("GusFoundIds") or "", "[^,]+") do
		found[id] = true
	end
end

local function stopPulse(rec)
	if rec.pulse then
		rec.pulse:Cancel()
		rec.pulse = nil
		if rec.glow then
			rec.glow.Transparency = 0
		end
	end
	if rec.lightPulse then
		rec.lightPulse:Cancel()
		rec.lightPulse = nil
		if rec.light then
			rec.light.Brightness = rec.bright or 0.7
		end
	end
end

local function startPulse(rec)
	if not rec.pulse and rec.glow and rec.glow.Parent then
		rec.pulse = TweenService:Create(rec.glow, PULSE, { Transparency = 0.75 })
		rec.pulse:Play()
	end
	if not rec.lightPulse and rec.light and rec.light.Parent then
		rec.lightPulse = TweenService:Create(rec.light, PULSE, { Brightness = 2.2 })
		rec.lightPulse:Play()
	end
end

local function applyTo(inst, hide)
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = hide and 1 or 0
	elseif inst:IsA("ProximityPrompt") then
		inst.Enabled = not hide
	elseif inst:IsA("Light") then
		inst.Enabled = not hide
	end
end

-- Remember the bits the detector animates (only called for freshly arrived instances).
local function note(rec, inst)
	if inst.Name == "Glow" and inst:IsA("BasePart") then
		rec.glow = inst
	elseif inst:IsA("PointLight") then
		rec.light = inst
		rec.bright = inst.Brightness
	end
end

local function apply(rec)
	local hide = found[rec.id] == true
	if hide then
		stopPulse(rec)
	end
	for _, d in ipairs(rec.model:GetDescendants()) do
		applyTo(d, hide)
	end
end

local function track(model)
	if tracked[model] or not model:IsA("Model") then
		return tracked[model]
	end
	local id = model:GetAttribute("Id")
	local rec = { id = typeof(id) == "string" and id or model.Name, model = model }
	local pos = model:GetAttribute("Pos")
	rec.pos = typeof(pos) == "Vector3" and pos or model:GetPivot().Position
	for _, d in ipairs(model:GetDescendants()) do
		note(rec, d)
	end
	tracked[model] = rec
	byId[rec.id] = rec
	apply(rec)
	return rec
end

local function untrack(model)
	local rec = tracked[model]
	if not rec then
		return
	end
	stopPulse(rec)
	tracked[model] = nil
	if byId[rec.id] == rec then
		byId[rec.id] = nil
	end
end

-- The figurine model (a direct child of the folder) that `inst` belongs to.
local function topModel(inst)
	local m = inst
	while m and m.Parent ~= folder do
		m = m.Parent
	end
	return m
end

local function attach(f)
	folder = f
	f.DescendantAdded:Connect(function(d)
		local model = topModel(d)
		if not model then
			return
		end
		if model == d or not tracked[model] then
			track(model)
		else
			-- A late part of a model we already know (non-atomic streaming): hide it too if needed.
			local rec = tracked[model]
			note(rec, d)
			applyTo(d, found[rec.id] == true)
		end
	end)
	f.ChildRemoved:Connect(untrack)
	for _, m in ipairs(f:GetChildren()) do
		track(m)
	end
end

------------------------------------------------------------------ detector

local lastPing = 0

local function rootPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function scan()
	-- Only once the server has published your finds (GusTotal is set with GusFoundIds), so the
	-- detector never beeps at a figurine you found in an earlier session while your save loads.
	local here = player:GetAttribute("GusTotal") ~= nil and rootPosition() or nil
	local best, bestD
	for model, rec in pairs(tracked) do
		local d = math.huge
		if here and not found[rec.id] and model.Parent then
			d = (rec.pos - here).Magnitude
		end
		if d <= RANGE then
			startPulse(rec)
			if not bestD or d < bestD then
				best, bestD = rec, d
			end
		else
			stopPulse(rec)
		end
	end
	if best and bestD then
		local t = math.clamp(bestD / RANGE, 0, 1)
		local now = os.clock()
		if now - lastPing >= PING_NEAR + (PING_FAR - PING_NEAR) * t then
			lastPing = now
			SoundClient.Play("Countdown", best.pos + Vector3.new(0, 2, 0), 0.3 + 0.35 * (1 - t))
		end
	end
end

------------------------------------------------------------------ moments

-- A neon ring that bursts out of the pedestal when you pick a figurine up.
local function pop(id)
	local rec = byId[id]
	if not rec or not rec.pos then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "GusPop"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = GATOR
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(rec.pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 14, 14), Transparency = 1 }):Play()
	task.delay(0.7, function()
		ring:Destroy()
	end)
end

-- Gus-coloured confetti for the big ones (a district finished, all of them found).
local function confetti()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GusConfetti"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = playerGui
	local colors = { GATOR, PINK, CYAN, GOLD }
	for i = 1, 28 do
		local bit = Instance.new("Frame")
		bit.BorderSizePixel = 0
		bit.BackgroundColor3 = colors[i % #colors + 1]
		bit.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22))
		local x = math.random()
		bit.Position = UDim2.fromScale(x, -0.05)
		bit.Rotation = math.random(0, 360)
		bit.Parent = gui
		TweenService:Create(bit, TweenInfo.new(1.4 + math.random() * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.2, 1.05),
			Rotation = bit.Rotation + math.random(-360, 360),
		}):Play()
	end
	task.delay(2.4, function()
		gui:Destroy()
	end)
end

local function stamp(title, sub, color, big)
	if big then
		-- Extra option for a larger stamp; ignored by a HUDController that doesn't know it.
		local stampWithOptions: any = HUDController.Stamp
		stampWithOptions(title, sub, color, BIG)
	else
		HUDController.Stamp(title, sub, color)
	end
end

local function onFound(info)
	if type(info) ~= "table" or type(info.Id) ~= "string" then
		return
	end
	-- Hide it right away (the GusFoundIds attribute follows from the server).
	found[info.Id] = true
	local rec = byId[info.Id]
	if rec then
		pop(info.Id)
		apply(rec)
	end
	local count = tonumber(info.Count) or 0
	local total = tonumber(info.Total) or #Collectibles.Spots
	local district = tostring(info.District or "")
	local inDistrict = string.format("%s %d/%d", district, tonumber(info.DistrictCount) or 0, tonumber(info.DistrictTotal) or 0)
	local cash = "+" .. HUDController.Money(tonumber(info.Cash) or 0)
	if info.DistrictDone then
		stamp("DISTRICT DONE! " .. count .. "/" .. total, cash .. " · " .. inDistrict, GOLD, true)
		SoundClient.Play("Success")
		confetti()
	else
		stamp("GUS FOUND! " .. count .. "/" .. total, cash .. " · " .. inDistrict, GATOR, false)
		SoundClient.Play("Checkpoint")
	end
	if info.AllDone then
		stamp("ALL " .. total .. " FOUND!", "Gator Green paint unlocked", GOLD, true)
	end
end

------------------------------------------------------------------ API

function CollectibleClient.Count()
	return player:GetAttribute("GusFound") or 0, player:GetAttribute("GusTotal") or #Collectibles.Spots
end

function CollectibleClient.Hint(id)
	local s = Collectibles.ById[id]
	return s and (s.District .. ": " .. s.Hint) or nil
end

function CollectibleClient.NextHint()
	local here = rootPosition() or Vector3.zero
	local best, bestD
	for _, s in ipairs(Collectibles.Spots) do
		if not found[s.Id] then
			local d = (Vector2.new(s.X, s.Z) - Vector2.new(here.X, here.Z)).Magnitude
			if not bestD or d < bestD then
				best, bestD = s, d
			end
		end
	end
	if not best then
		return nil, nil
	end
	return CollectibleClient.Hint(best.Id), best.Id
end

function CollectibleClient.Init()
	readFound()
	player:GetAttributeChangedSignal("GusFoundIds"):Connect(function()
		readFound()
		for _, rec in pairs(tracked) do
			apply(rec)
		end
	end)

	local f = Workspace:FindFirstChild("Collectibles")
	if f then
		attach(f)
	else
		local conn
		conn = Workspace.ChildAdded:Connect(function(child)
			if child.Name == "Collectibles" and child:IsA("Folder") and not folder then
				conn:Disconnect()
				attach(child)
			end
		end)
	end

	Remotes.OnClient("GusFound", onFound)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(scan)
			if not ok then
				warn("[CollectibleClient] " .. tostring(err))
				task.wait(5)
			end
		end
	end)
end

return CollectibleClient
