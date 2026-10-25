-- WeaponClient (ModuleScript, StarterPlayerScripts.Controllers.WeaponClient)
-- Guns on screen (Config.Weapons; the server, WeaponService, decides every hit).
--   * Aim: with a mouse, at the cursor; on touch and gamepad, at the crosshair in the middle of the
--     screen. While a gun is out (on foot) your character turns to face where you aim.
--   * Fire: click (hold for the Riptide SMG), the FIRE button on touch, R2 on a gamepad. Reload: R,
--     the RELOAD button, or by itself when the magazine runs dry.
--   * This device finds what each bullet hits (pedestrians are skipped: they're never hurt) and sends
--     it with WeaponFire; tracers, muzzle flashes and sounds play here at once. Other players' shots
--     arrive as WeaponShot; WeaponHit(downed) flashes the hit marker.
--   * HUD: ammo, a health bar (bottom centre, while hurt or holding a gun), a red flash when hurt, the PASSIVE
--     button next to CAR (citizens on foot), and a small shield over passive players' heads.
--   * The gun store screen opens when the server says so (WeaponStore, from the counter prompt).
--     Buying: BuyWeapon(id), tap twice to confirm.
--   * Messages from the server: WeaponNotice(key, arg) (texts in NOTICES below).
-- Sounds: Config.Sounds PistolShot / SMGShot / ShotgunShot / RifleShot / GunReload / GunEmpty. While
-- one's Id is 0 the stand-in named by its Fallback plays instead (sped up, cut short).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local WeaponClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local GOLD = Color3.fromRGB(255, 214, 10)
local MINT = Color3.fromRGB(110, 242, 196)
local RED = Color3.fromRGB(255, 70, 70)
local DARK = Color3.fromRGB(18, 14, 30)
local GREY = Color3.fromRGB(150, 150, 170)
local FONT = Enum.Font.FredokaOne

local NOTICES = {
	PassiveCitizens = { "Only citizens can go PASSIVE (police on duty can't).", CYAN },
	PassiveWanted = { "Lose the cops first: you can't go PASSIVE while wanted.", RED },
	PassiveFight = { "You were just in a fight. PASSIVE in %s s.", GOLD },
	PassiveCooldown = { "PASSIVE can be switched on again in %s s.", GOLD },
	PassiveOn = { "PASSIVE on: nobody can shoot you, and you can't shoot.", MINT },
	PassiveOff = { "PASSIVE off: you can shoot and be shot. Hitting players brings the police.", PINK },
	PassiveLost = { "You're wanted, so PASSIVE is off.", RED },
	ShotTip = { "Being shot? Tap PASSIVE (next to CAR) and nobody can hurt you.", CYAN },
	StoreCitizens = { "Go off duty to buy guns (PHONE > JOBS).", CYAN },
	StoreTooFar = { "Walk up to the counter to buy.", GOLD },
	StoreOwned = { "You already own the %s.", GOLD },
	StoreRank = { "Reach citizen rank %s to buy this one.", GOLD },
	StoreCash = { "You need $%s for this one.", RED },
	StoreBought = { "Bought the %s! Pick it from your backpack (number keys, or tap it).", MINT },
	Takedown = { "You took down %s.", PINK },
}

local fireEvent, reloadEvent, buyEvent, passiveEvent
local gui, crosshair, hitMark, ammoLabel, healthFrame, healthFill, healthLabel, flash
local passiveButton, fireButton, reloadButton
local storeGui, storePanel, storeList
local storeArmed = {} -- [id] = os.clock() of the first tap (tap again within 3 s to buy)

local mags = setmetatable({}, { __mode = "k" }) -- [Tool] = shots left
local reloading = setmetatable({}, { __mode = "k" }) -- [Tool] = os.clock() the reload ends
local lastShot = setmetatable({}, { __mode = "k" }) -- [Tool] = os.clock()
local equipped -- { tool, def } while a gun is in hand
local holding = false -- trigger held (auto guns keep firing)
local rotated = false -- we turned AutoRotate off
local lastHurtFlash = 0
local lastPassiveTip = 0
local rng = Random.new()

------------------------------------------------------------------ helpers

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 12)
	c.Parent = obj
end

local function stroke(obj, color, t)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = t or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function label(parent, text, size, pos, color, anchor)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.AnchorPoint = anchor or Vector2.new(0, 0)
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = parent
	return l
end

local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function phoneOpen()
	local module = script.Parent:FindFirstChild("PhoneUI")
	local ok, phone = pcall(require, module)
	return ok and type(phone) == "table" and phone.IsOpen and phone.IsOpen() or false
end

local function myParts()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	if hum and hum.Health > 0 and root and head then
		return char, hum, root, head
	end
	return nil, nil, nil, nil
end

-- "mouse" (aim at the cursor) or "center" (touch, gamepad: aim at the crosshair).
local function aimMode()
	local t = UserInputService:GetLastInputType()
	if t == Enum.UserInputType.Touch or t.Name:sub(1, 7) == "Gamepad" then
		return "center"
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "center"
	end
	return "mouse"
end

local function screenAimPoint()
	local cam = Workspace.CurrentCamera
	if aimMode() == "mouse" then
		return UserInputService:GetMouseLocation()
	end
	return cam.ViewportSize / 2
end

------------------------------------------------------------------ sounds

local function soundIn(key, parent)
	local def = Sounds.Effects[key]
	if not def or not parent then
		return nil
	end
	local s = parent:FindFirstChild("NC_" .. key)
	if s then
		return s
	end
	local src, speed, cut = def, 1, nil
	if def.Id == 0 then
		src = def.Fallback and Sounds.Effects[def.Fallback]
		speed, cut = def.Speed or 1, def.Cut
	end
	if not src or src.Id == 0 then
		return nil
	end
	s = Instance.new("Sound")
	s.Name = "NC_" .. key
	s.SoundId = "rbxassetid://" .. src.Id
	s.Volume = def.Volume or 0.5
	s.PlaybackSpeed = speed
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 500
	pcall(function()
		s.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Effects")
	end)
	if cut then
		s:SetAttribute("Cut", cut)
	end
	s.Parent = parent
	return s
end

local function play(key, parent)
	local s = soundIn(key, parent)
	if not s then
		return
	end
	s.TimePosition = 0
	s:Play()
	local cut = s:GetAttribute("Cut")
	if cut then
		local token = os.clock()
		s:SetAttribute("Token", token)
		task.delay(cut, function()
			if s.Parent and s:GetAttribute("Token") == token then
				s:Stop()
			end
		end)
	end
end

------------------------------------------------------------------ effects (pooled parts)

local fxFolder
local tracers, tracerAt = {}, 0
local puffs, puffAt = {}, 0
local TRACERS, PUFFS = 48, 24

local function fxPart(shape)
	if not fxFolder or not fxFolder.Parent then
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "NCGunFX"
		fxFolder.Parent = Workspace.CurrentCamera
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	if shape then
		p.Shape = shape
	end
	p.Parent = fxFolder
	return p
end

local function tracer(a, b, color)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	tracerAt = tracerAt % TRACERS + 1
	local p = tracers[tracerAt]
	if not p or not p.Parent then
		p = fxPart()
		tracers[tracerAt] = p
	end
	p.Size = Vector3.new(0.09, 0.09, len)
	p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
	p.Color = color
	p.Transparency = 0.15
	TweenService:Create(p, TweenInfo.new(0.12), { Transparency = 1 }):Play()
end

local function puff(pos, color)
	puffAt = puffAt % PUFFS + 1
	local p = puffs[puffAt]
	if not p or not p.Parent then
		p = fxPart(Enum.PartType.Ball)
		puffs[puffAt] = p
	end
	p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.CFrame = CFrame.new(pos)
	p.Color = color
	p.Transparency = 0.2
	TweenService:Create(p, TweenInfo.new(0.18), { Transparency = 1, Size = Vector3.new(1.2, 1.2, 1.2) }):Play()
end

local function muzzleOf(tool)
	local handle = tool and tool:FindFirstChild("Handle")
	local m = handle and handle:FindFirstChild("Muzzle")
	if m and m:IsA("Attachment") then
		return m.WorldPosition, handle
	end
	return handle and handle.Position or nil, handle
end

local function flashMuzzle(handle, color)
	if not handle then
		return
	end
	local light = handle:FindFirstChild("NC_Flash")
	if not light then
		light = Instance.new("PointLight")
		light.Name = "NC_Flash"
		light.Range = 10
		light.Brightness = 3
		light.Shadows = false
		light.Enabled = false
		light.Parent = handle
	end
	light.Color = color
	light.Enabled = true
	task.delay(0.05, function()
		light.Enabled = false
	end)
end

local function shotEffects(def, tool, from, ends)
	local muzzle, handle = muzzleOf(tool)
	local start = muzzle or from
	for _, e in ipairs(ends) do
		tracer(start, e, def.Color)
		puff(e, def.Color)
	end
	flashMuzzle(handle, def.Color)
	if handle then
		play(def.Sound, handle)
	end
end

------------------------------------------------------------------ raycasts

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function baseIgnore()
	local list = { Workspace.CurrentCamera }
	if player.Character then
		table.insert(list, player.Character)
	end
	for _, name in ipairs({ "Peds", "PedsIdle" }) do -- pedestrians are never hurt: shoot past them
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

local function characterOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model and model:FindFirstChildOfClass("Humanoid") and model or nil
end

-- First thing a bullet stops at: anything solid, or any part of a character (limbs and hats count).
local function cast(origin, dir, dist)
	local ignore = baseIgnore()
	for _ = 1, 6 do
		rayParams.FilterDescendantsInstances = ignore
		local r = Workspace:Raycast(origin, dir * dist, rayParams)
		if not r then
			return nil
		end
		if r.Instance.CanCollide or characterOf(r.Instance) then
			return r
		end
		table.insert(ignore, r.Instance) -- leaves, glow, signs: fly through
	end
	return nil
end

-- Where the player is aiming in the world (from the camera, starting level with the character).
local function aimPoint(head, range)
	local cam = Workspace.CurrentCamera
	local p = screenAimPoint()
	local ray = cam:ViewportPointToRay(p.X, p.Y)
	local along = math.max(0, (head.Position - ray.Origin):Dot(ray.Direction))
	local origin = ray.Origin + ray.Direction * along
	local r = cast(origin, ray.Direction, range + 60)
	return r and r.Position or origin + ray.Direction * (range + 60)
end

local function spread(dir, degrees)
	if degrees <= 0 then
		return dir
	end
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local roll = rng:NextNumber() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

------------------------------------------------------------------ firing

local updateAmmo

local function startReload()
	local e = equipped
	if not e then
		return
	end
	local tool, def = e.tool, e.def
	if reloading[tool] or (mags[tool] or def.Mag) >= def.Mag then
		return
	end
	local done = os.clock() + def.Reload
	reloading[tool] = done
	reloadEvent:FireServer(def.Id)
	local _, handle = muzzleOf(tool)
	play("GunReload", handle)
	updateAmmo()
	task.delay(def.Reload, function()
		if reloading[tool] == done then
			reloading[tool] = nil
			mags[tool] = def.Mag
			updateAmmo()
		end
	end)
end

local function fire()
	local e = equipped
	if not e or phoneOpen() then
		return
	end
	local tool, def = e.tool, e.def
	local _, hum, root, head = myParts()
	if not hum or hum.SeatPart then
		return
	end
	if player:GetAttribute("Passive") == true then
		if os.clock() - lastPassiveTip > 3 then
			lastPassiveTip = os.clock()
			NotifyController.Show("PASSIVE is on: tap PASSIVE (next to CAR) to fight.", MINT)
		end
		return
	end
	local t = os.clock()
	if t - (lastShot[tool] or 0) < 1 / def.Rate or reloading[tool] then
		return
	end
	if (mags[tool] or 0) <= 0 then
		local _, handle = muzzleOf(tool)
		lastShot[tool] = t
		play("GunEmpty", handle)
		startReload()
		return
	end
	lastShot[tool] = t
	mags[tool] -= 1
	local origin = head.Position
	local target = aimPoint(head, def.Range)
	local base = target - origin
	if base.Magnitude < 1 then
		base = root.CFrame.LookVector
	end
	base = base.Unit
	local shots, ends = {}, {}
	for _ = 1, def.Pellets do
		local dir = spread(base, def.Spread)
		local r = cast(origin, dir, def.Range)
		local hitAt = r and r.Position or origin + dir * def.Range
		table.insert(shots, { e = hitAt, p = r and r.Instance or nil })
		table.insert(ends, hitAt)
	end
	fireEvent:FireServer(def.Id, origin, shots)
	shotEffects(def, tool, origin, ends)
	if mags[tool] <= 0 then
		startReload()
	end
	updateAmmo()
end

-- Others' shots: tracers from their gun, sound at the gun.
local function onShot(shooter, id, origin, ends)
	local def = Weapons.ById[id]
	if not def or shooter == player or typeof(origin) ~= "Vector3" or type(ends) ~= "table" then
		return
	end
	local char = typeof(shooter) == "Instance" and shooter:IsA("Player") and shooter.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("WeaponId") ~= id then
		tool = nil
	end
	local clean = {}
	for _, e in ipairs(ends) do
		if typeof(e) == "Vector3" then
			table.insert(clean, e)
		end
	end
	shotEffects(def, tool, origin, clean)
end

------------------------------------------------------------------ HUD

local function onHit(downed)
	hitMark.Visible = true
	hitMark.TextColor3 = downed and RED or Color3.new(1, 1, 1)
	hitMark.Text = downed and "✕  DOWN" or "✕"
	local token = os.clock()
	hitMark:SetAttribute("Token", token)
	task.delay(downed and 0.8 or 0.15, function()
		if hitMark:GetAttribute("Token") == token then
			hitMark.Visible = false
		end
	end)
end

updateAmmo = function()
	local e = equipped
	if not e then
		ammoLabel.Visible = false
		return
	end
	local tool, def = e.tool, e.def
	ammoLabel.Visible = true
	if reloading[tool] then
		ammoLabel.Text = def.Name .. "  ·  RELOADING"
		ammoLabel.TextColor3 = GOLD
	else
		local n = mags[tool] or def.Mag
		ammoLabel.Text = def.Name .. "  ·  " .. n .. " / " .. def.Mag
		ammoLabel.TextColor3 = n == 0 and RED or Color3.new(1, 1, 1)
	end
end

local function refreshHealth()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		healthFrame.Visible = false
		return
	end
	local frac = hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
	healthFrame.Visible = (frac < 0.999 or equipped ~= nil) and hum.Health > 0
	healthFill.Size = UDim2.fromScale(frac, 1)
	healthFill.BackgroundColor3 = frac > 0.5 and MINT or frac > 0.25 and GOLD or RED
	healthLabel.Text = math.ceil(hum.Health) .. " HP"
end

local function hurtFlash()
	if os.clock() - lastHurtFlash < 0.15 then
		return
	end
	lastHurtFlash = os.clock()
	flash.BackgroundTransparency = 0.7
	TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

local function refreshPassive()
	local on = player:GetAttribute("Passive") == true
	local _, hum = myParts()
	passiveButton.Visible = player:GetAttribute("Side") == "Civilian" and hum ~= nil and hum.SeatPart == nil
	passiveButton.Text = on and "PASSIVE ✓" or "PASSIVE"
	passiveButton.TextColor3 = on and DARK or MINT
	passiveButton.BackgroundColor3 = on and MINT or DARK
end

local function refreshButtons()
	local _, hum = myParts()
	local show = equipped ~= nil and hum ~= nil and hum.SeatPart == nil
	local touch = UserInputService.TouchEnabled
	fireButton.Visible = show and touch
	reloadButton.Visible = show and touch
	crosshair.Visible = show
	if not show then
		holding = false
	end
	local h = gui.AbsoluteSize.Y
	local b = math.floor(math.clamp(h * 0.17, 64, 120))
	local copShift = player:GetAttribute("Side") == "Cop" and math.floor(h * 0.11) + 12 or 0
	fireButton.Size = UDim2.fromOffset(b, b)
	fireButton.Position = UDim2.new(1, -24 - copShift, 0.6, 0)
	reloadButton.Size = UDim2.fromOffset(math.floor(b * 0.6), math.floor(b * 0.6))
	reloadButton.Position = UDim2.new(1, -24 - copShift - b - 10, 0.6, math.floor(b * 0.2))
	ammoLabel.Position = touch and UDim2.new(1, -24 - copShift, 0.6, -math.floor(b / 2) - 34)
		or UDim2.new(1, -24, 1, -24)
	ammoLabel.AnchorPoint = touch and Vector2.new(1, 0) or Vector2.new(1, 1)
	-- Health: above the backpack bar on foot, above DriveUI's speed gauge (0.13H tall, 18 px up) seated.
	local seated = hum ~= nil and hum.SeatPart ~= nil
	healthFrame.Position = seated and UDim2.new(0.5, 0, 1, -(26 + math.floor(h * 0.13))) or UDim2.new(0.5, 0, 1, -84)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, hum == nil or hum.SeatPart == nil)
	end)
	refreshPassive()
	refreshHealth()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "WeaponUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2 -- under the phone (5): its backdrop covers FIRE while it's open
	gui.Parent = player:WaitForChild("PlayerGui")

	flash = Instance.new("Frame")
	flash.Name = "HurtFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = RED
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.Parent = gui

	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(28, 28)
	crosshair.BackgroundTransparency = 1
	crosshair.Visible = false
	crosshair.Parent = gui
	for _, spec in ipairs({ { 0.5, 0, 2, 8 }, { 0.5, 1, 2, 8 }, { 0, 0.5, 8, 2 }, { 1, 0.5, 8, 2 } }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(spec[1], spec[2])
		bar.Position = UDim2.fromScale(spec[1], spec[2])
		bar.Size = UDim2.fromOffset(spec[3], spec[4])
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.Parent = crosshair
		stroke(bar, DARK, 1)
	end
	hitMark = label(crosshair, "✕", UDim2.fromOffset(90, 26), UDim2.new(0.5, 0, 0.5, 0), Color3.new(1, 1, 1), Vector2.new(0.5, 0.5))
	hitMark.TextStrokeTransparency = 0.3
	hitMark.Visible = false

	ammoLabel = label(gui, "", UDim2.fromOffset(240, 28), UDim2.new(1, -24, 1, -24), Color3.new(1, 1, 1), Vector2.new(1, 1))
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
	ammoLabel.TextStrokeTransparency = 0.4
	ammoLabel.Visible = false

	healthFrame = Instance.new("Frame")
	healthFrame.Name = "Health"
	healthFrame.AnchorPoint = Vector2.new(0.5, 1) -- bottom centre, above the backpack (refreshButtons)
	healthFrame.Position = UDim2.new(0.5, 0, 1, -84)
	healthFrame.Size = UDim2.fromOffset(220, 16)
	healthFrame.BackgroundColor3 = DARK
	healthFrame.BackgroundTransparency = 0.2
	healthFrame.Visible = false
	healthFrame.Parent = gui
	corner(healthFrame, UDim.new(0.5, 0))
	healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BorderSizePixel = 0
	healthFill.BackgroundColor3 = MINT
	healthFill.Parent = healthFrame
	corner(healthFill, UDim.new(0.5, 0))
	healthLabel = label(healthFrame, "100 HP", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(1, 1, 1))
	healthLabel.TextStrokeTransparency = 0.3
	healthLabel.ZIndex = 2

	passiveButton = Instance.new("TextButton")
	passiveButton.Name = "PassiveButton"
	passiveButton.Position = UDim2.fromOffset(108, 188) -- next to CAR (HUDController: 16..100, y 188)
	passiveButton.Size = UDim2.fromOffset(96, 40)
	passiveButton.BackgroundColor3 = DARK
	passiveButton.BackgroundTransparency = 0.15
	passiveButton.Font = FONT
	passiveButton.TextScaled = true
	passiveButton.TextColor3 = MINT
	passiveButton.Text = "PASSIVE"
	passiveButton.Parent = gui
	corner(passiveButton, UDim.new(0.5, 0))
	stroke(passiveButton, MINT, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = passiveButton
	passiveButton.Activated:Connect(function()
		passiveEvent:FireServer(player:GetAttribute("Passive") ~= true)
	end)

	local function round(name, text, color)
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.BackgroundColor3 = DARK
		b.BackgroundTransparency = 0.15
		b.Font = FONT
		b.TextScaled = true
		b.TextColor3 = color
		b.Text = text
		b.AutoButtonColor = true
		b.Visible = false
		b.Parent = gui
		corner(b, UDim.new(0.5, 0))
		stroke(b, color, 3)
		local p = Instance.new("UIPadding")
		p.PaddingTop, p.PaddingBottom = UDim.new(0.3, 0), UDim.new(0.3, 0)
		p.PaddingLeft, p.PaddingRight = UDim.new(0.15, 0), UDim.new(0.15, 0)
		p.Parent = b
		return b
	end
	fireButton = round("FireButton", "FIRE", PINK)
	reloadButton = round("ReloadButton", "RELOAD", GOLD)
	fireButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			fire()
		end
	end)
	fireButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = false
		end
	end)
	reloadButton.Activated:Connect(startReload)
end

------------------------------------------------------------------ the store screen

local function closeStore()
	if storeGui then
		storeGui.Enabled = false
	end
end

local refreshStore

local function buildStore()
	storeGui = Instance.new("ScreenGui")
	storeGui.Name = "GunStoreUI"
	storeGui.ResetOnSpawn = false
	storeGui.IgnoreGuiInset = true
	storeGui.DisplayOrder = 15 -- over the phone and the role badge, under the toasts (20)
	storeGui.Enabled = false
	storeGui.Parent = player:WaitForChild("PlayerGui")

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Parent = storeGui
	backdrop.Activated:Connect(closeStore)

	storePanel = Instance.new("Frame")
	storePanel.Name = "Panel"
	storePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	storePanel.Position = UDim2.fromScale(0.5, 0.5)
	storePanel.Size = UDim2.new(0.92, 0, 0.86, 0)
	storePanel.BackgroundColor3 = DARK
	storePanel.Active = true -- taps on the panel never reach the backdrop
	storePanel.Parent = storeGui
	corner(storePanel, UDim.new(0, 18))
	stroke(storePanel, PINK, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 560)
	limit.Parent = storePanel

	local heading = label(storePanel, Weapons.Store.Name:upper(), UDim2.new(1, -110, 0, 34), UDim2.fromOffset(16, 10), PINK)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local sub = label(storePanel, "Bought guns are yours for good. Infinite ammo.", UDim2.new(1, -110, 0, 18),
		UDim2.fromOffset(16, 46), GREY)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = Color3.fromRGB(40, 34, 60)
	close.Font = FONT
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "✕"
	close.Parent = storePanel
	corner(close, UDim.new(0.5, 0))
	close.Activated:Connect(closeStore)

	storeList = Instance.new("ScrollingFrame")
	storeList.Name = "List"
	storeList.Position = UDim2.fromOffset(12, 74)
	storeList.Size = UDim2.new(1, -24, 1, -86)
	storeList.BackgroundTransparency = 1
	storeList.BorderSizePixel = 0
	storeList.ScrollBarThickness = 6
	storeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	storeList.CanvasSize = UDim2.new()
	storeList.Parent = storePanel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = storeList
end

local function statBar(parent, name, frac, y, color)
	local l = label(parent, name, UDim2.fromOffset(56, 14), UDim2.new(0, 12, 0, y), GREY)
	l.TextXAlignment = Enum.TextXAlignment.Left
	local back = Instance.new("Frame")
	back.Position = UDim2.new(0, 70, 0, y + 3)
	back.Size = UDim2.new(0.5, -82, 0, 8)
	back.BackgroundColor3 = Color3.fromRGB(44, 40, 64)
	back.BorderSizePixel = 0
	back.Parent = parent
	corner(back, UDim.new(0.5, 0))
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(frac, 0.05, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, UDim.new(0.5, 0))
end

refreshStore = function()
	if not storeList then
		return
	end
	for _, c in ipairs(storeList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local owned = {}
	for id in string.gmatch(player:GetAttribute("OwnedWeapons") or "", "[^,]+") do
		owned[id] = true
	end
	local cash = player:GetAttribute("Cash") or 0
	local rank = player:GetAttribute("CivRank") or 1
	local cop = player:GetAttribute("Side") == "Cop"
	local maxDps, maxRange = 0, 0
	for _, def in ipairs(Weapons.List) do
		maxDps = math.max(maxDps, def.Damage * def.Pellets * def.Rate)
		maxRange = math.max(maxRange, def.Range)
	end
	for _, def in ipairs(Weapons.List) do
		if not def.CopOnly then
			local card = Instance.new("Frame")
			card.Name = def.Id
			card.LayoutOrder = def.Order
			card.Size = UDim2.new(1, -8, 0, 112)
			card.BackgroundColor3 = Color3.fromRGB(30, 24, 48)
			card.Parent = storeList
			corner(card)
			stroke(card, def.Color, 2)
			local title = label(card, def.Name, UDim2.new(0.6, -12, 0, 26), UDim2.fromOffset(12, 8), def.Color)
			title.TextXAlignment = Enum.TextXAlignment.Left
			local kind = label(card, def.Kind .. "  ·  " .. def.Blurb, UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 36), GREY)
			kind.TextXAlignment = Enum.TextXAlignment.Left
			statBar(card, "POWER", def.Damage * def.Pellets * def.Rate / maxDps, 60, def.Color)
			statBar(card, "RANGE", def.Range / maxRange, 80, def.Color)

			local b = Instance.new("TextButton")
			b.Name = "Buy"
			b.AnchorPoint = Vector2.new(1, 1)
			b.Position = UDim2.new(1, -12, 1, -12)
			b.Size = UDim2.new(0.42, 0, 0, 40)
			b.Font = FONT
			b.TextScaled = true
			b.AutoButtonColor = true
			b.Parent = card
			corner(b, UDim.new(0.5, 0))
			local p = Instance.new("UIPadding")
			p.PaddingTop, p.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
			p.Parent = b
			local armed = storeArmed[def.Id] and os.clock() - storeArmed[def.Id] < 3
			if owned[def.Id] then
				b.Text = "OWNED ✓"
				b.BackgroundColor3 = Color3.fromRGB(40, 70, 60)
				b.TextColor3 = MINT
			elseif cop then
				b.Text = "OFF DUTY ONLY"
				b.BackgroundColor3 = Color3.fromRGB(44, 40, 64)
				b.TextColor3 = GREY
			elseif rank < (def.MinRank or 1) then
				b.Text = "🔒 RANK " .. def.MinRank
				b.BackgroundColor3 = Color3.fromRGB(44, 40, 64)
				b.TextColor3 = GREY
			else
				b.Text = armed and "TAP TO CONFIRM" or ("BUY $" .. money(def.Price))
				b.BackgroundColor3 = cash >= def.Price and def.Color or Color3.fromRGB(60, 50, 70)
				b.TextColor3 = cash >= def.Price and DARK or GREY
			end
			b.Activated:Connect(function()
				if owned[def.Id] then
					NotifyController.Show("Pick the " .. def.Name .. " from your backpack (number keys, or tap it).", MINT)
					return
				end
				if cop or rank < (def.MinRank or 1) then
					return
				end
				if cash < def.Price then
					NotifyController.Show("You need $" .. money(def.Price) .. " for the " .. def.Name .. ".", RED)
					return
				end
				if storeArmed[def.Id] and os.clock() - storeArmed[def.Id] < 3 then
					storeArmed[def.Id] = nil
					buyEvent:FireServer(def.Id)
				else
					storeArmed[def.Id] = os.clock()
					task.delay(3.1, refreshStore)
				end
				refreshStore()
			end)
		end
	end
end

local function openStore()
	if not storeGui then
		buildStore()
	end
	table.clear(storeArmed)
	refreshStore()
	storeGui.Enabled = true
	-- Close it when they walk away from the counter.
	task.spawn(function()
		local origin = Weapons.Store.Position
		while storeGui.Enabled do
			local _, _, root = myParts()
			if not root or (root.Position - origin).Magnitude > 40 then
				closeStore()
				break
			end
			task.wait(0.5)
		end
	end)
end

------------------------------------------------------------------ overhead PASSIVE shields

local function tagCharacter(p)
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = head:FindFirstChild("NC_Passive")
	local on = p:GetAttribute("Passive") == true
	if on and not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "NC_Passive"
		tag.Size = UDim2.fromOffset(28, 28)
		tag.StudsOffset = Vector3.new(0, 2.4, 0)
		tag.MaxDistance = 120
		tag.LightInfluence = 0
		local l = label(tag, "🛡", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), MINT)
		l.TextStrokeTransparency = 0.4
		tag.Parent = head
	elseif not on and tag then
		tag:Destroy()
	end
end

local function watchPlayer(p)
	if p == player then
		return
	end
	p:GetAttributeChangedSignal("Passive"):Connect(function()
		tagCharacter(p)
	end)
	p.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 10)
		tagCharacter(p)
	end)
	tagCharacter(p)
end

------------------------------------------------------------------ equip tracking

local function onCharacter(char)
	equipped = nil
	holding = false
	rotated = false
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	local lastHealth = hum.Health
	hum.HealthChanged:Connect(function(h)
		if h < lastHealth - 0.5 then
			hurtFlash()
		end
		lastHealth = h
		refreshHealth()
	end)
	hum.Seated:Connect(function()
		task.defer(refreshButtons)
	end)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			local def = Weapons.ById[c:GetAttribute("WeaponId") or ""]
			if def then
				if mags[c] == nil then
					mags[c] = def.Mag
				end
				equipped = { tool = c, def = def }
				updateAmmo()
				refreshButtons()
			end
		end
	end)
	char.ChildRemoved:Connect(function(c)
		if equipped and equipped.tool == c then
			equipped = nil
			holding = false
			updateAmmo()
			refreshButtons()
		end
	end)
	refreshButtons()
end

-- Every frame: crosshair position, facing the aim, auto fire.
local function step()
	local e = equipped
	local _, hum, root, head = myParts()
	if not e or not hum or hum.SeatPart then
		if rotated and hum then
			hum.AutoRotate = true
		end
		rotated = false
		return
	end
	local p = screenAimPoint()
	crosshair.Position = UDim2.fromOffset(p.X, p.Y)
	if phoneOpen() then
		holding = false
		return
	end
	-- Face where you aim (only turning, never moving).
	local target = aimPoint(head, e.def.Range)
	local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	if flat.Magnitude > 2 then
		if not rotated then
			hum.AutoRotate = false
			rotated = true
		end
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.01 or flatLook.Unit:Dot(flat.Unit) < 0.9995 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end
	if holding and e.def.Auto then
		fire()
	end
end

function WeaponClient.Init()
	fireEvent = Remotes.Event("WeaponFire")
	reloadEvent = Remotes.Event("WeaponReload")
	buyEvent = Remotes.Event("BuyWeapon")
	passiveEvent = Remotes.Event("SetPassive")
	build()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) -- our own bar (left column)
	end)

	Remotes.OnClient("WeaponShot", onShot)
	Remotes.OnClient("WeaponHit", onHit)
	Remotes.OnClient("WeaponStore", openStore)
	Remotes.OnClient("WeaponNotice", function(key, arg)
		local n = NOTICES[key]
		if not n then
			return
		end
		local text = n[1]
		if text:find("%%s") then
			local value = arg
			if key == "StoreCash" and type(arg) == "number" then
				value = money(arg)
			end
			text = string.format(text, tostring(value or ""))
		end
		NotifyController.Show(text, n[2])
		if key == "StoreBought" or key == "StoreOwned" then
			refreshStore()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not equipped then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding = true
			fire()
		elseif input.KeyCode == Enum.KeyCode.R then
			startReload()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding = false
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		if equipped then
			refreshButtons()
		end
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshButtons)
	RunService:BindToRenderStep("NCWeapons", Enum.RenderPriority.Camera.Value + 1, step)

	for _, a in ipairs({ "Passive", "Side" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshButtons)
	end
	for _, a in ipairs({ "OwnedWeapons", "Cash", "CivRank", "Side" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			if storeGui and storeGui.Enabled then
				refreshStore()
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

return WeaponClient
