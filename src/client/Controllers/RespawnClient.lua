-- RespawnClient (ModuleScript, StarterPlayerScripts.Controllers.RespawnClient)
-- The death screen. Whenever our body dies (shot dead, Esc > Reset, a long fall) the fall plays, the
-- colour drains out of the picture with a slight blur and the low drone, then:
--     YOU DIED                       (Theme.Font.Big, the stamps' headline look)
--     Shot by Name · Coast 9         (when a gun did it: CombatFx "Killed"; its Cause when it has one:
--                                     "Run over by Name", "Hit by Sunray Patrol", "Shot by the police")
--     -$250 bag · -$40 wallet        (what fell out, when anything did)
--     [ RESPAWN ]                    (from Combat.Death.RespawnAfter seconds after the death)
--     Respawning in 7                (RespawnService brings us back by itself at Combat.Death.AutoRespawn)
-- RESPAWN, Space, Enter or gamepad A send remote RequestRespawn; RespawnService loads the new body (our
-- side's spawn, or inside our home). The screen goes the moment a new body arrives, whoever loaded it:
-- shot dead with police right there is an arrest (ArrestService), and the new body is in prison before
-- the screen ever shows (it waits SHOW_AT for that).
-- Times are read from the player attribute DiedAt (server time, set by RespawnService); until it
-- arrives they count from our own clock.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local SoundClient = require(script.Parent:WaitForChild("SoundClient"))

local RespawnClient = {}

local player = Players.LocalPlayer
local DEATH = Combat.Death
local DRAIN_AT = 0.9 -- seconds after the death: the colour starts draining (as a knockout's: CombatClient)...
local DRAIN = 0.6 -- ...over this long
local BLUR = 5
local SHOW_AT = 1.2 -- the words and the button
local CAUSE_FRESH = 3 -- seconds: a "Killed" message this close to the death is what killed us
local RETRY = 2.5 -- seconds: ask again if no new body came
local KEYS = { [Enum.KeyCode.Space] = true, [Enum.KeyCode.Return] = true, [Enum.KeyCode.ButtonA] = true }

local requestRespawn
local gui, ui
local color, blur
local token = 0 -- one per death: a newer death or a new body ends the older one's threads
local dead = nil -- the body we're showing the screen for (nil = not showing)
local cause = nil -- { info = CombatFx "Killed" table, at = os.clock() }
local askedAt = -math.huge

local function now()
	return Workspace:GetServerTimeNow()
end

-- Server time this body died (DiedAt), or our own guess until it arrives.
local function diedAt(fallback)
	local t = player:GetAttribute("DiedAt")
	return type(t) == "number" and t or fallback
end

local function label(parent, name, font, maxSize, color3)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = UDim2.new(1, -32, 0, maxSize + 6)
	Theme.Text(l, nil, "Body")
	l.FontFace = font
	l.TextScaled = true
	l.TextColor3 = color3 or Theme.Color.Text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = math.min(14, maxSize)
	limit.Parent = l
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "RespawnUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20 -- over the HUD and the title screen's layer
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- A dark band across the middle so the words read over any street.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0, 0.5)
	band.Position = UDim2.fromScale(0, 0.5)
	band.Size = UDim2.fromScale(1, 0.62)
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BorderSizePixel = 0
	band.Parent = gui
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = band

	local touch = Theme.IsTouch()
	local title = label(gui, "Title", Theme.Font.Big, touch and 64 or 96, Theme.Color.Text)
	title.Position = UDim2.new(0.5, 0, 0.5, touch and -110 or -150)
	title.Text = "YOU DIED"
	local stroke = title:FindFirstChild("Shadow")
	stroke.Thickness = touch and 3 or 4
	stroke.Transparency = 0
	stroke.Color = Theme.Ink

	local cause1 = label(gui, "Cause", Theme.Font.Display, touch and 20 or 26)
	cause1.Position = UDim2.new(0.5, 0, 0.5, touch and -38 or -46)
	local loss = label(gui, "Loss", Theme.Font.Display, touch and 17 or 21, Theme.Color.Danger)
	loss.Position = UDim2.new(0.5, 0, 0.5, touch and -12 or -14)

	local button = Instance.new("TextButton")
	button.Name = "Respawn"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0.5, touch and 22 or 28)
	button.Size = UDim2.fromOffset(240, math.max(Theme.Touch, 56))
	button.Text = "RESPAWN"
	Theme.Button(button, "Primary")
	button.FontFace = Theme.Font.Display
	button.TextSize = 28
	button.Parent = gui

	local countdown = label(gui, "Countdown", Theme.Font.Body, touch and 15 or 16, Theme.Color.Dim)
	countdown.Position = UDim2.new(0.5, 0, 0.5, touch and 88 or 96)

	ui = { title = title, cause = cause1, loss = loss, button = button, countdown = countdown }
	button.Activated:Connect(function()
		RespawnClient.Respawn()
	end)
end

-- The picture drains to grey (and comes back with `on` false). Made on this device: nobody else sees it.
local function grey(on)
	if on then
		if not color or not color.Parent then
			color = Instance.new("ColorCorrectionEffect")
			color.Name = "NCDead"
			color.Parent = Lighting
		end
		if not blur or not blur.Parent then
			blur = Instance.new("BlurEffect")
			blur.Name = "NCDeadBlur"
			blur.Size = 0
			blur.Parent = Lighting
		end
		color.Enabled, blur.Enabled = true, true
		local drain = TweenInfo.new(DRAIN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(color, drain, { Saturation = -1, Contrast = 0.15, Brightness = -0.05 }):Play()
		TweenService:Create(blur, drain, { Size = BLUR }):Play()
		return
	end
	if color then
		color.Saturation, color.Contrast, color.Brightness = 0, 0, 0
		color.Enabled = false
	end
	if blur then
		blur.Size = 0
		blur.Enabled = false
	end
end

local function hide()
	token += 1
	dead = nil
	cause = nil -- (what killed the last body never names this one's death)
	if gui then
		gui.Enabled = false
	end
	grey(false)
end

-- "-$250 bag · -$40 wallet", or "" when nothing fell out.
local function lossText(info)
	local parts = {}
	local bag = tonumber(info and info.Dropped) or 0
	local wallet = tonumber(info and info.Wallet) or 0
	if bag > 0 then
		table.insert(parts, "-" .. HUDController.Money(bag) .. " bag")
	end
	if wallet > 0 then
		table.insert(parts, "-" .. HUDController.Money(wallet) .. " wallet")
	end
	return table.concat(parts, " · ")
end

local function hint()
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "A"
	elseif Theme.IsTouch() then
		return nil
	end
	return "SPACE"
end

local function show(char, myToken, startedAt)
	if not gui then
		build()
	end
	local info = cause and os.clock() - cause.at <= CAUSE_FRESH + SHOW_AT and cause.info or nil
	if info and type(info.Cause) == "string" and info.Cause ~= "" then
		ui.cause.Text = info.Cause -- (the server's own words: "Run over by Name", "Hit by Sunray Patrol"...)
	elseif info then
		local by = "Shot by " .. tostring(info.By or "someone")
		if type(info.Gun) == "string" and info.Gun ~= "" then
			by ..= " · " .. info.Gun
		end
		ui.cause.Text = by
	else
		ui.cause.Text = ""
	end
	ui.loss.Text = lossText(info)
	gui.Enabled = true
	SoundClient.Play("KnockedOut")
	-- The button wakes up at RespawnAfter; the line under it counts down to the automatic respawn.
	while token == myToken and dead == char do
		local since = now() - diedAt(startedAt)
		local ready = since >= DEATH.RespawnAfter
		local waiting = os.clock() - askedAt < RETRY
		ui.button.Active = ready and not waiting
		ui.button.AutoButtonColor = ready and not waiting
		ui.button.BackgroundTransparency = ready and 0.05 or 0.5
		ui.button.Text = waiting and "RESPAWNING..." or "RESPAWN"
		local left = math.max(0, math.ceil(DEATH.AutoRespawn - since))
		local key = hint()
		ui.countdown.Text = (ready and key and ("Press " .. key .. " to respawn  ·  ") or "")
			.. (left > 0 and ("Respawning in " .. left) or "Respawning...")
		task.wait(0.1)
	end
end

local function onDied(char)
	if player.Character ~= char then
		return
	end
	token += 1
	local myToken = token
	dead = char
	askedAt = -math.huge
	local startedAt = now()
	task.delay(DRAIN_AT, function()
		if token == myToken and dead == char and player.Character == char then
			grey(true)
		end
	end)
	task.delay(SHOW_AT, function()
		if token == myToken and dead == char and player.Character == char then
			show(char, myToken, startedAt)
		end
	end)
end

local function onCharacter(char)
	hide()
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	hum.Died:Connect(function()
		onDied(char)
	end)
	if hum.Health <= 0 then
		onDied(char)
	end
end

-- Ask for the new body (RESPAWN, Space, Enter, gamepad A). Nothing until RespawnAfter, and once per
-- RETRY seconds.
function RespawnClient.Respawn()
	if not dead or not requestRespawn or os.clock() - askedAt < RETRY then
		return
	end
	local at = player:GetAttribute("DiedAt")
	if type(at) ~= "number" or now() - at < DEATH.RespawnAfter then
		return -- (RespawnService refuses it before then anyway)
	end
	askedAt = os.clock()
	requestRespawn:FireServer()
end

function RespawnClient.IsDead()
	return dead ~= nil
end

function RespawnClient.Init()
	-- (Waited for in its own thread: the controllers after this one never wait on RespawnService.)
	task.spawn(function()
		requestRespawn = Remotes.Event("RequestRespawn")
	end)
	Remotes.OnClient("CombatFx", function(kind, a)
		if kind == "Killed" and type(a) == "table" then
			cause = { info = a, at = os.clock() }
		end
	end)
	-- (Not "processed": the controls' jump binding may claim Space. Only typing in a box is left alone.)
	UserInputService.InputBegan:Connect(function(input)
		if dead and gui and gui.Enabled and KEYS[input.KeyCode] and not UserInputService:GetFocusedTextBox() then
			RespawnClient.Respawn()
		end
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return RespawnClient
