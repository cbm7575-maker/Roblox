-- CombatClient (ModuleScript, StarterPlayerScripts.Controllers.CombatClient)
-- Your side of fights: fists and guns. CombatService decides every hit, every round in the magazine
-- and every dollar; this file only asks and shows. Kid-safe: nothing gory, nobody is gone for good,
-- people are KNOCKED OUT and get back up. Numbers and gun stats live in Config.Combat.
--   * Tools from the Roblox backpack: Fists (hotbar 1) and the guns you own (2 and up) for citizens, the
--     Service Pistol for cops. Switch with the hotbar keys or the gamepad bumpers (Roblox's own), or the
--     weapon wheel (WeaponWheel: hold Tab / D-pad left). On a phone the hotbar is hidden (it would cover
--     the weapon readout) and the WEAPON button does it: tap = next tool, hold 0.4 s = the weapon wheel
--     (without WeaponWheel: a list with PUT AWAY). While the wheel is open nothing fires or swings and
--     the mouse is not locked to the crosshair (CombatClient.SetWheelOpen).
--   * Fists (click / tap / R2): a straight right, then a left (PoseClient's "Point" pose thrown for a
--     third of a second; without PoseClient the Animate script's old slash). A pedestrian in front of you
--     falls over, runs off and drops a wallet (PedClient, this device only); you turn to face the nearest
--     player in reach you could hit, and the server is asked ("Punch", them).
--   * A gun is "out" while its Tool is in your hand, you are on foot and on your feet (not swimming,
--     not at home) and no panel is open (phone, gun shop, dealer card, house buy card, dressing room,
--     side picker). Fists don't swing behind one of those either. While it is out:
--       - It is held low in both hands (PoseClient "LowReady") and comes up to the eye (PoseClient "Aim",
--         pointed where the camera looks, kicked by every shot) while you aim or fire and for 0.8 s after
--         the last shot; it goes back down for the reload. PoseClient.Broadcast tells everyone else which
--         of the two to show, and ("Aim", pitch, raised) tells the server where it points (Tool attributes
--         AimPitch / AimUp, when Config.Combat has them) so other devices can tip the arms up and down.
--         Roblox's own one-arm tool hold is switched off while the pose does the holding. Without
--         PoseClient the plain Roblox hold shows.
--       - You run and turn freely with the gun low. While it is raised your body faces the crosshair
--         (AutoRotate off, only while standing, running or jumping) and you walk at Config Aim.WalkSpeed
--         (LocomotionClient.SetCap("aim", n)).
--       - The camera sits over your shoulder and no further than 10 studs back, 6 while aiming
--         (LocomotionClient.RequestCameraOffset / RequestFov own Humanoid.CameraOffset and the FOV; without
--         that controller this file writes them itself). A crosshair marks the middle of the screen and,
--         on a keyboard, the mouse is locked to it; hold Left Alt to free the cursor for a click on the
--         HUD. Everything is put back the moment the gun stops being out.
--       - FIRE: left mouse / R2 / the FIRE button (hold for automatic guns; dragging the thumb that
--         holds FIRE turns the camera). AIM (zoom to FOV 50): hold right mouse / L2, or the AIM toggle
--         on touch; on touch and gamepad pressing it also swings the camera onto the nearest player you
--         could hit within Config Aim.LockAngle of the crosshair. RELOAD: R / gamepad X (taken from GET
--         IN only when there is something to reload) / the RELOAD button, and by itself when the
--         magazine runs dry.
--       - The shot goes where the crosshair points, snapping to a player you could hit who is within a
--         few degrees of it and in plain sight (cops only snap to citizens with 2+ stars). The client
--         sends ("Fire", gunId, aimPoint, thatPlayer) and nothing else: no ammo, damage or victim.
--       - Your own shot shows at once: muzzle flash, a tracer, a dust-and-sparks puff where it lands
--         (a white puff on a body, never red), the shot sound, a little camera kick. Shotgun pellets
--         are drawn from this device's own dice; the server rolls the real ones. Pedestrians are hit
--         here too (PedClient.ShotAt) and everyone on the sidewalk reacts (PedClient.Scare; while you
--         aim, PedClient.AimedAt makes the close ones put their hands up).
--       - Ammo is guessed ahead of the server (Tool attribute Ammo) so the counter never lags, and put
--         right again 0.4 s (plus your ping) after your last shot. A reload (Tool attribute ReloadUntil)
--         tilts the gun in your hand and fills a small bar; no firing until it clears.
--       - In a safe zone, in passive mode, just after spawning or while swimming nothing is shown or
--         counted: one ask per trigger pull goes to the server so its toast can say why.
--   * Effects from the server (CombatFx): other players' shots (flash, tracers, puffs, the sound at their
--     muzzle) and reloads, punches (thud, a white puff, the puncher's arm), a faint white flash (at most
--     twice a second, however fast the hits come) and a red bar toward whoever hit you, the hit marker
--     when your shot counted (white; blue when armor took it all, gold for a knockout), toasts for
--     grabbed or returned cash. Whoever is hit flinches and brings a hand to the spot (PoseClient
--     "Flinch" + "HandToHit"), on every device that saw it.
--   * Big moments go through HUDController.Stamp (one queue, so two never overlap): KNOCKOUT, bounties,
--     YOU BAILED. Being knocked out is a short scene of its own: the fall at real speed, then after
--     about a second the picture drains to grey with a slight blur (local Lighting effects
--     "NCKnockedOut" / "NCKnockedOutBlur", on top of ImpactClient's lighter grey) and a low drone
--     (optional sound key "KnockedOut"), then "KNOCKED OUT" with who did it and what you dropped; the
--     grey lifts when you are back up.
--   * HUD (ScreenGui "CombatHUD", flat street look, every piece in its Theme zone):
--       - Vitals zone (under the minimap): HEALTH (left) and ARMOR (right) bars, while you are hurt or
--         armored, for 4 s after a change, and always with a gun in hand.
--       - Pills zone (under the cash): SAFE ZONE / PASSIVE.
--       - Corner zone (bottom right on a PC, bottom centre on a phone; the car cluster has it while
--         driving, when tools are put away): "Ammo", the weapon's name and "12 / ∞". On a phone the
--         RELOAD and WEAPON buttons sit beside it.
--       - Phone: FIRE and AIM sit above Roblox's jump button, left of the side column (LawClient.SideSlot)
--         and under the Buttons zone. Direct children Ammo / Fire / Aim / Reload / Weapon keep their
--         names: LawClient and AmbienceClient look them up.
--       - Crosshair; a small health bar over hurt players within 80 studs (green, thin blue armor line).
--   * Coast Arms: the counter prompt ("Browse") opens the shop panel: every gun with damage / fire rate
--     / range bars and a price, OWNED or rank lock, and body armor. BUY sends ("GunShopBuy", itemId); the
--     server checks distance, cash, rank and ownership, and what you bought is confirmed on the panel's
--     bottom line. The panel closes on X / B, when you walk away, sit, get knocked out, change sides or
--     respawn.
--   * Tools are put away when you sit in a car, go into your home, get knocked over or get tasered.
--   * The Roblox backpack (hotbar) shows only for citizens and cops on foot with a keyboard or gamepad,
--     outside homes, the side picker and the shop panel, so it never covers the speed gauge, LEAVE HOME
--     or KEEP MY SIDE. The dressing room (WardrobeUI) hides and restores it itself.
-- Other controllers are looked up softly (other(name)): PoseClient, LocomotionClient, ImpactClient,
-- DriveUI, PhoneUI, WardrobeUI, DealerClient, HouseClient. The game still works when one is missing.
-- For other controllers: CombatClient.GunOut() (the camera, crosshair and mouse are in gun mode right
-- now), CombatClient.IsShopOpen(). For WeaponWheel: CombatClient.Weapons() (what the hands can switch
-- to), Equipped() (the key of the one in hand), EquipKey(key) (the same equip as the WEAPON button and
-- the hotbar keys), CanSwitch() (may the tools be used right now?) and SetWheelOpen(on).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local SoundClient = require(script.Parent:WaitForChild("SoundClient"))
local PedClient = require(script.Parent:WaitForChild("PedClient"))

local player = Players.LocalPlayer

local CombatClient = {}

local C = Theme.Color

-- Constants, all in one table: a Luau function (this file's top level counts as one) can hold 200
-- local variables at most, and this file once ran into that.
local K = {}
K.FLASH = Color3.fromRGB(255, 255, 255) -- the hit flash: plain white and faint
K.FLASH_GAP = 0.5 -- seconds between two hit flashes at least (never a strobe, however fast the hits come)
K.ATTR = Combat.ToolAttribute or "NCCombat"
K.GUN_ATTR = Combat.GunAttribute or "GunId"
K.AMMO_ATTR = Combat.AmmoAttribute or "Ammo"
K.RELOAD_ATTR = Combat.ReloadAttribute or "ReloadUntil"
-- Looks only, kept by the server for everyone else's view of a held tool (nil when this build of
-- Config.Combat has none: then nothing is sent or read).
K.AIM_ATTR = Combat.AimAttribute
K.AIMUP_ATTR = Combat.AimUpAttribute
K.SWING_ATTR = Combat.SwingAttribute
K.FISTS = Combat.Fists
K.GUN_ORDER = Combat.GunOrder or {}
K.AIM = Combat.Aim or {}
K.SHOP = Combat.Shop or {}
K.ARMOR_ITEM = Combat.ArmorItem or {}
K.ARMOR_MAX = Combat.ArmorMax or 100
K.DAZE_MAX = Combat.DazeMax or 100

K.SHOULDER = K.AIM.Shoulder or Vector3.new(1.75, 0.4, 0)
K.ZOOM_FOV = K.AIM.ZoomFOV or 50
K.NORMAL_FOV = K.AIM.NormalFOV or 70
K.ZOOM_TIME = K.AIM.ZoomTime or 0.15
K.AIM_WALK = K.AIM.WalkSpeed or 12 -- studs/s while the gun is raised (never 10 or less: the police take that for standing still)
K.STRAFE_HOLD = K.AIM.StrafeHold or 0.8 -- seconds the gun stays raised after the last shot
K.LOCK_ANGLE = K.AIM.LockAngle or 20 -- degrees: touch / gamepad AIM swings onto a target this close to the crosshair
K.LOCK_TIME = K.AIM.LockTime or 0.25
K.TOUCH_LOOK = K.AIM.TouchLook or 0.3 -- degrees the camera turns per pixel the thumb on FIRE drags
-- Camera distance with a gun out (studs): never first person (the shoulder offset would sit beside the
-- head), never far away, closer while aiming.
K.ZOOM_MIN = K.AIM.ZoomMin or 4
K.ZOOM_MAX = K.AIM.ZoomMax or 10
K.ZOOM_AIM = K.AIM.ZoomAim or 6
K.TRACER_TIME = (Combat.Fx and Combat.Fx.TracerTime) or 0.06
K.MAX_TRACERS = (Combat.Fx and Combat.Fx.MaxTracers) or 24
K.MAX_IMPACTS = 24 -- pooled puffs (a shotgun uses 8 at once)
K.TRACER_COLOR = Color3.fromRGB(255, 232, 170)
K.FX_CULL = 400 -- studs: shots this far from the camera at both ends aren't drawn
K.SHOT_LIFE = 2 -- seconds a shot Sound may live (SoundClient.Play's 4th argument)
K.DRAW_TIME = Combat.DrawTime or 0.2 -- seconds after pulling a gun out before it fires
K.RELOAD_GRACE = 0.6 -- seconds we wait for the server to start a reload we asked for
K.AMMO_SETTLE = 0.4 -- seconds (plus the ping) after our last shot before the server's count replaces our guess
K.SHOP_PROMPT = K.SHOP.Prompt or "GunShopBrowse"
K.SHOP_W, K.SHOP_TOP, K.SHOP_ROW = 430, 48, 56 -- shop panel: design width, header height, row height
K.SHOP_NOTE = 26 -- ...and the line at its bottom that confirms a purchase
K.VITALS_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Linear)
K.SWING_TIME = 0.32 -- seconds a punch's arm is out
K.REACT_GAP = 0.3 -- seconds between two flinches on one body (automatic fire lands a dozen hits a second)
K.POSE_RANGE = 120 -- studs: other players' swings and aim are only shown this close
K.AIM_SEND = 0.12 -- seconds between two ("Aim", ...) messages at least (the server takes 10 a second)
-- The knocked-out scene (seconds after the knockout): the fall plays at real speed first.
K.KO_DRAIN_AT = 0.9 -- the colour starts draining...
K.KO_DRAIN = 0.6 -- ...over this long
K.KO_STAMP_AT = 1.5 -- the words
K.KO_BLUR = 5 -- BlurEffect.Size: slight
K.PAD_RELOAD = "NC_GunReload" -- ContextActionService action: gamepad X while a gun is out

local mode = "keyboard" -- "keyboard" | "gamepad" | "touch": which buttons and hints show

local gui
local ui = {} -- every HUD object, by name (buildHud)
local fx = { tracers = {}, impacts = {}, nextTracer = 1, nextImpact = 1, live = 0 } -- pooled world effects
fx.params = RaycastParams.new() -- what bullets and the aim ray are cast with
fx.params.FilterType = Enum.RaycastFilterType.Exclude
fx.params.IgnoreWater = true
local bars = {} -- [Player] = { gui, fill, armor }
local shop = { open = false, rows = {}, lastBuy = 0 }

-- The gun in hand.
local gunTool, gun -- the Tool and its Config.Combat.Guns table (nil: no gun in hand)
local gunOut = false -- see the header: camera, crosshair, mouse lock and inputs are live
local triggerHeld, holdAim, aimToggle = false, false, false
local ammo = 0 -- our guess of the magazine
-- Everything else that has to be remembered, in one table (see K).
local S = {
	hooked = setmetatable({}, { __mode = "k" }), -- [Tool] = true once Activated is connected
	slashTracks = setmetatable({}, { __mode = "k" }), -- [Humanoid] = AnimationTrack (the old slash)
	lazy = {}, -- [name] = another controller's module (required when first needed), false if missing
	rng = Random.new(), -- this device's own dice (what our shotgun pellets look like)
	actionRemote = nil, buyRemote = nil,
	lastSwing = 0, swings = 0, -- os.clock() of our last punch, and how many we have thrown (odd = right hand)
	seenSwing = setmetatable({}, { __mode = "k" }), -- [Player] = the Swing count of their Fists we last showed
	reactAt = setmetatable({}, { __mode = "k" }), -- [character] = os.clock() it last flinched
	-- the gun in hand
	gunMuzzle = nil, -- its Muzzle attachment
	gunConns = {},
	aimHum = nil, -- the humanoid whose gun mode this is
	easeHum = nil, -- the humanoid whose camera offset is easing back to zero (no LocomotionClient)
	mouseLocked = false,
	ammoSettled = true, -- ammo is the server's number, not our guess
	lastShotAt = -math.huge, nextFireAt = 0,
	reloadAskedAt = nil, -- os.clock() we sent "Reload" (nil once the server has started it)
	emptyClicked = false,
	reloadMotion = nil, -- { weld, c0, t0, dur } while the reload plays
	recoilKick = 0, recoilSettle = 0, -- degrees still to kick up / to come back down
	crossKick = 0, lastGap = -1, hitUntil = 0, hitShown = false, hitColor = nil,
	lastScare = 0, lastShell = 0, lastAimedAt = 0,
	-- how it is held, and what everyone else was told
	lowPose = nil, aimPose = nil, -- PoseClient handles on our own character
	shownPose = nil, -- the pose name PoseClient.Broadcast last took
	sentPitch = nil, sentUp = false, sentAt = 0, -- the last ("Aim", pitch, raised) sent
	poseRetryAt = 0, -- os.clock(): a body PoseClient couldn't pose isn't tried again before this
	raised = false, wasAiming = false,
	lockPart = nil, lockUntil = 0, -- AIM's swing onto a target (touch / gamepad)
	lookX = 0, lookY = 0, -- pixels the thumb on FIRE has dragged since the last frame
	camOn = false, fovOn = false, capOn = false, -- what LocomotionClient is holding for us right now
	fovAim = false, -- ...and whether that FOV is the zoom (true) or the quick way back to normal
	-- The player's own camera distances (and where they had the view), put back when the gun goes away;
	-- zoomPending = { min, max, was } while that put-back is still under way, zoomToken guards it.
	zoomMin = nil, zoomMax = nil, zoomWas = nil, zoomPending = nil, zoomToken = 0,
	aimWas = nil, -- how far back the view sat before AIM pulled it in
	padBound = false,
	fistsOut = false, -- Fists are in our hand (the readout shows their name)
	-- HUD
	vitalsUntil = 0, armorDropAt = 0, lastArmor = 0, lastFlash = 0,
	hitDrawn = nil, -- the colour the hit marker was last drawn in
	hints = 0, hintToken = 0, koToken = 0, noteToken = 0,
	koColor = nil, koBlur = nil, -- the knocked-out scene's Lighting effects (made when first needed)
	weaponDown = nil, -- os.clock() the WEAPON button went down (nil once it counted as a hold)
	listOpen = false, othersAt = 0,
	wheelOpen = false, -- WeaponWheel is up: no shots or swings, the mouse stays free (SetWheelOpen)
}

local refreshAmmoHud, refreshTouch, showVitals, closeShop -- (defined further down)

------------------------------------------------------------------ helpers

local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function money(n)
	return HUDController.Money(n)
end

local function myBody()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	return char, hum, root
end

local function sameCrew(p)
	local crew = player:GetAttribute("Crew")
	return crew ~= nil and crew == p:GetAttribute("Crew")
end

-- Could the server let us hit this player right now? (Attributes only; the server checks for real.)
local function hittable(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and hum.SeatPart == nil and not sameCrew(p) and Combat.Hittable(p, now())
end

-- Would a shot from this gun count on them? (A cop's Service Pistol only works on wanted citizens.)
local function gunTarget(p, g)
	if not hittable(p) then
		return false
	end
	local stars = g.MinStars
	if stars then
		return p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) >= stars
	end
	return true
end

-- Things that would stop the server from letting us fight at all (we still ask: it explains why).
local function selfBlocked(hum)
	local t = now()
	return hum.SeatPart ~= nil or hum:GetState() == Enum.HumanoidStateType.Swimming -- (no fighting from the water)
		or player:GetAttribute("InSafeZone") == true or player:GetAttribute("InHome") == true
		or player:GetAttribute("Passive") == true
		or (player:GetAttribute("SpawnSafeUntil") or 0) > t or (player:GetAttribute("KnockedUntil") or 0) > t
		or (player:GetAttribute("StunnedUntil") or 0) > t
end

local function send(...)
	local args = table.pack(...)
	task.spawn(function()
		S.actionRemote = S.actionRemote or Remotes.Event("CombatAction")
		S.actionRemote:FireServer(table.unpack(args, 1, args.n))
	end)
end

-- Another controller's module, or nil if it isn't there (never an error: they start before us, and
-- none of them needs us).
local function other(name)
	local m = S.lazy[name]
	if m == nil then
		local ok, res = pcall(require, script.Parent:FindFirstChild(name))
		m = (ok and type(res) == "table") and res or false
		S.lazy[name] = m
	end
	return m or nil
end

-- Call another controller's function if both are there. A missing controller, a missing function or an
-- error inside it all give nil: the fight goes on without that bit of polish.
local function ask(name, fn, ...)
	local m = other(name)
	local f = m and m[fn]
	if type(f) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(f, ...)
	if not ok then
		return nil
	end
	return a, b
end

-- How far back Roblox's own camera wants to sit (no argument), or put it `set` studs back (true if that
-- worked). Its PlayerModule isn't a public API, so every step is checked and any surprise gives nil:
-- callers have another way. (The distance measured off the camera itself is no good for this: a wall
-- behind the player shortens it for a moment.)
local function camDistance(set)
	local ok, result = pcall(function()
		local scripts = player:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		local cameras = module and require(module):GetCameras()
		local active = cameras and cameras.activeCameraController
		if not active then
			return nil
		end
		if set then
			active:SetCameraToSubjectDistance(set)
			return true
		end
		return active:GetCameraToSubjectDistance()
	end)
	if ok and (result == true or (type(result) == "number" and result == result)) then
		return result
	end
	return nil
end

-- A Theme zone in our full-screen ScreenGui's pixels: left, top, width, height.
local function zoneRect(name, touch)
	local z = Theme.Zone(name, touch)
	local view = gui.AbsoluteSize
	local w = z.Size.X.Scale * view.X + z.Size.X.Offset
	local h = z.Size.Y.Scale * view.Y + z.Size.Y.Offset
	return z.Pos.X.Scale * view.X + z.Pos.X.Offset - z.Anchor.X * w, z.Pos.Y.Scale * view.Y + z.Pos.Y.Offset - z.Anchor.Y * h, w, h
end

-- "touch", "gamepad" or "keyboard", the same way InteractClient decides it.
local function readMode()
	local driveUI = other("DriveUI")
	if driveUI and type(driveUI.IsTouch) == "function" and driveUI.IsTouch() then
		return "touch"
	end
	if string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad" then
		return "gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	return "keyboard"
end

-- Does this part stop a bullet? The same rule as the server: solid or visible parts do, invisible
-- walk-through parts don't, smoke clouds (Workspace.Smoke) do.
local function blocks(inst)
	if inst.CanCollide or inst.Transparency < 0.95 then
		return true
	end
	local smoke = Workspace:FindFirstChild("Smoke")
	return smoke ~= nil and inst:IsDescendantOf(smoke)
end

-- Where a ray first really hits something (a body or a blocking part): the point, the surface normal
-- and the player it belongs to (nil for the world). Nothing at all when the way is clear. Hats and
-- hair are passed through, as on the server (a big hat must not catch the shot or the aim).
local function solidHit(from, vector, ignore)
	local left = vector.Magnitude
	if left < 0.05 then
		return nil
	end
	local dir = vector.Unit
	local list = table.clone(ignore)
	for _ = 1, 8 do
		fx.params.FilterDescendantsInstances = list
		local hit = Workspace:Raycast(from, dir * left, fx.params)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		if not inst:FindFirstAncestorOfClass("Accessory") then
			local model = inst:FindFirstAncestorOfClass("Model")
			local body = model and Players:GetPlayerFromCharacter(model) or nil
			if body or blocks(inst) then
				return hit.Position, hit.Normal, body
			end
		end
		table.insert(list, inst)
		left -= (hit.Position - from).Magnitude
		from = hit.Position
		if left <= 0.05 then
			return nil
		end
	end
	return from, nil, nil -- too many see-through parts in a row: call it blocked here
end

-- What our shots pass through: our own body, the camera's local effects and dropped cash (as on the
-- server), plus `extra` (the target's body, when checking the way to them).
local function shotIgnore(char, extra)
	local list = { char, Workspace.CurrentCamera }
	local dropped = Workspace:FindFirstChild("DroppedBags")
	if dropped then
		table.insert(list, dropped)
	end
	-- Pedestrians: PedClient decides who a shot hits (ShotAt / Under), from where they stand. Their
	-- torsos DO stop a ray (a Humanoid keeps CanCollide on, so CanQuery = false counts for nothing),
	-- and a bullet that stopped on one ended half a stud short of the middle ShotAt measures to: it did
	-- not count. Only shots passing just beside a walker knocked them over, never one dead on target.
	local walkers = Workspace:FindFirstChild("Peds")
	if walkers then
		table.insert(list, walkers)
	end
	if extra then
		table.insert(list, extra)
	end
	return list
end

-- Turn our character to face a point (flat), so the swing goes where we aimed.
local function face(root, pos)
	local look = flat(pos - root.Position)
	if look.Magnitude > 0.2 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
end

-- A CFrame at `pos` looking along `dir`. (Straight up or down, lookAt needs a sideways "up".)
local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir, math.abs(dir.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis)
end

------------------------------------------------------------------ effects

local function ensureFx()
	if fx.folder and fx.folder.Parent then
		return
	end
	-- First use, or the camera was replaced and took the old folder with it: start the pools again.
	table.clear(fx.tracers)
	table.clear(fx.impacts)
	fx.nextTracer, fx.nextImpact, fx.live = 1, 1, 0
	local folder = Instance.new("Folder")
	folder.Name = "NCCombatFx"
	folder.Parent = Workspace.CurrentCamera -- local-only parts
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new()
	anchor.Parent = folder
	fx.folder, fx.anchor = folder, anchor
end

-- One frame of a tracer: a bright streak whose head runs from the muzzle to where the shot ended.
-- k = 0..1 through its life.
local function placeTracer(t, k)
	local head = t.len * (0.35 + 0.65 * k)
	local tail = math.max(0, head - math.max(t.len * 0.35, 10))
	local seg = head - tail
	local part = t.part
	part.Size = Vector3.new(0.09, 0.09, seg)
	part.CFrame = facing(t.from + t.dir * (tail + seg / 2), t.dir)
	part.Transparency = 0.1 + 0.6 * k
end

-- A tracer from `from` to `to`. The parts are pooled (MAX_TRACERS at most; the oldest is reused).
local function tracer(from, to)
	local v = to - from
	local len = v.Magnitude
	if len < 1.5 then
		return
	end
	ensureFx()
	local i = fx.nextTracer
	local t = fx.tracers[i]
	if not t then
		local p = Instance.new("Part")
		p.Name = "Tracer"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = K.TRACER_COLOR
		p.Parent = fx.folder
		t = { part = p, live = false }
		fx.tracers[i] = t
	end
	fx.nextTracer = i % K.MAX_TRACERS + 1
	if not t.live then
		t.live = true
		fx.live += 1
	end
	t.from, t.dir, t.len, t.t0 = from, v / len, len, os.clock()
	placeTracer(t, 0)
end

local function updateTracers()
	if fx.live <= 0 then
		return
	end
	local t = os.clock()
	for _, tr in ipairs(fx.tracers) do
		if tr.live then
			local k = (t - tr.t0) / K.TRACER_TIME
			if k >= 1 then
				tr.live = false
				fx.live -= 1
				tr.part.Transparency = 1 -- parked, ready for the next shot
			else
				placeTracer(tr, k)
			end
		end
	end
end

local function emitter(parent, name, texture, color)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Rate = 0 -- only ever :Emit()
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = parent
	return e
end

-- Where a shot landed: dust and a few sparks on the world, a small white puff on a body (never red).
-- `normal` points back out of what was hit. Pooled attachments: the particles stay where they were born.
local function impact(pos, normal, onBody)
	ensureFx()
	local i = fx.nextImpact
	local rec = fx.impacts[i]
	if not rec then
		local att = Instance.new("Attachment")
		att.Name = "Impact"
		att.Parent = fx.anchor
		local dust = emitter(att, "Dust", "rbxasset://textures/particles/smoke_main.dds", Color3.fromRGB(196, 186, 170))
		dust.Transparency = NumberSequence.new(0.5, 1)
		dust.Size = NumberSequence.new(0.5, 1.8)
		dust.Lifetime = NumberRange.new(0.35, 0.6)
		dust.Speed = NumberRange.new(3, 7)
		dust.SpreadAngle = Vector2.new(50, 50)
		dust.Drag = 3
		local sparks = emitter(att, "Sparks", "rbxasset://textures/particles/sparkles_main.dds", Color3.fromRGB(255, 222, 150))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.3, 0)
		sparks.Lifetime = NumberRange.new(0.1, 0.22)
		sparks.Speed = NumberRange.new(14, 26)
		sparks.SpreadAngle = Vector2.new(55, 55)
		sparks.Acceleration = Vector3.new(0, -40, 0)
		local puff = emitter(att, "Puff", "rbxasset://textures/particles/smoke_main.dds", Color3.fromRGB(238, 238, 238))
		puff.Transparency = NumberSequence.new(0.35, 1)
		puff.Size = NumberSequence.new(0.4, 1.1)
		puff.Lifetime = NumberRange.new(0.2, 0.35)
		puff.Speed = NumberRange.new(2, 5)
		puff.SpreadAngle = Vector2.new(70, 70)
		rec = { att = att, dust = dust, sparks = sparks, puff = puff }
		fx.impacts[i] = rec
	end
	fx.nextImpact = i % K.MAX_IMPACTS + 1
	-- Emitters throw along the attachment's +Y: tip it over so +Y is the normal.
	rec.att.WorldCFrame = facing(pos, normal) * CFrame.Angles(math.rad(-90), 0, 0)
	if onBody then
		rec.puff:Emit(5)
	else
		rec.dust:Emit(4)
		rec.sparks:Emit(5)
	end
end

-- The gun Tool in a character's hand, if any.
local function gunToolOf(char)
	for _, c in ipairs(char and char:GetChildren() or {}) do
		if c:IsA("Tool") and c:GetAttribute(K.ATTR) == "Gun" then
			return c
		end
	end
	return nil
end

local function muzzleOf(tool)
	local m = tool and tool:FindFirstChild("Muzzle", true)
	return (m and m:IsA("Attachment")) and m or nil
end

-- Where a tracer leaves this gun: its Muzzle attachment, or (a gun model that came without one) the
-- barrel end of its Handle, whose -Z is the barrel. nil when the tool isn't in the world.
local function muzzleSpot(tool, muzzle)
	if muzzle and muzzle.Parent then
		return muzzle.WorldPosition
	end
	local handle = tool and tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") and handle:IsDescendantOf(Workspace) then
		return (handle.CFrame * CFrame.new(0, 0, -handle.Size.Z / 2)).Position
	end
	return nil
end

-- The Muzzle attachment's own Flash emitter and Light (CombatService builds both into every gun).
local function muzzleFlash(muzzle)
	if not muzzle then
		return
	end
	local burst = muzzle:FindFirstChild("Flash")
	if burst and burst:IsA("ParticleEmitter") then
		burst:Emit(3)
	end
	local light = muzzle:FindFirstChild("Light")
	if light and light:IsA("PointLight") then
		light.Enabled = true
		task.delay(0.05, function()
			light.Enabled = false
		end)
	end
end

-- We were hit: the screen blinks faintly. alpha = the frame's transparency at its brightest (0.8 for a
-- bullet, 0.65 for a punch). At most one every K.FLASH_GAP seconds whatever lands: an automatic gun
-- hits a dozen times a second, and a screen that strobes is a real risk for some players.
local function flash(alpha)
	local frame = ui.flash
	local t = os.clock()
	if not frame or t - S.lastFlash < K.FLASH_GAP then
		return
	end
	S.lastFlash = t
	frame.Visible = true
	frame.BackgroundTransparency = alpha or 0.65
	local tw = TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
	tw.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			frame.Visible = false
		end
	end)
	tw:Play()
end

------------------------------------------------------------------ bodies (PoseClient, when it is there)

-- Someone was hit and the server said so: they jolt the way the hit was going and, if their hands are
-- free, bring one to the spot. Looks only, on this device; every device that saw the hit does the
-- same. dir = the way the hit travelled, point = where it landed (either may be nil).
local function hitReact(char, dir, point)
	local t = os.clock()
	if not char or t - (S.reactAt[char] or 0) < K.REACT_GAP then
		return -- (automatic fire: one jolt at a time)
	end
	S.reactAt[char] = t
	ask("PoseClient", "Play", char, "Flinch", { Direction = dir })
	if gunToolOf(char) then
		return -- both hands are on a gun: the jolt is enough
	end
	local part, best
	if typeof(point) == "Vector3" then
		for _, p in ipairs(char:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				local d = (p.Position - point).Magnitude
				if not best or d < best then
					part, best = p, d
				end
			end
		end
	end
	part = part or char:FindFirstChild("UpperTorso")
	if part then
		ask("PoseClient", "Play", char, "HandToHit", { Part = part, Point = point })
	end
end

-- A punch on any character: a straight right, then a left (count: odd = right). PoseClient's "Point"
-- pose, thrown for a third of a second, reads as a jab. at = what it is thrown at (a world point; nil
-- = straight ahead). False when it can't be shown here (no PoseClient, an odd body).
local function throwPunch(char, count, at)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	if typeof(at) ~= "Vector3" then
		at = root.Position + root.CFrame.LookVector * 4 + Vector3.new(0, 1, 0)
	end
	local handle = ask("PoseClient", "Play", char, "Point", {
		Hand = count % 2 == 1 and "Right" or "Left", Point = at,
		Duration = K.SWING_TIME, FadeIn = 0.06, FadeOut = 0.16, Priority = 75,
	})
	return handle ~= nil and handle:IsPlaying()
end

-- Roblox's Animate script holds any Tool with a Handle in one arm stuck straight out ("toolnone").
-- While our poses do the holding it only muddies the blend, so its track is stopped (on our own
-- character: that reaches everyone). The Animate script starts it again by itself with the next tool.
local function dropToolHold(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animate = char:FindFirstChild("Animate")
	local holder = animate and animate:FindFirstChild("toolnone")
	local anim = holder and holder:FindFirstChildOfClass("Animation")
	local id = anim and anim.AnimationId or nil
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local a = track.Animation
		if a and ((id ~= nil and a.AnimationId == id) or string.lower(a.Name) == "toolnoneanim" or string.lower(a.Name) == "toolnone") then
			track:Stop(0.15)
		end
	end
end

-- How our own gun is held, every frame while it is out: low in both hands, and up at the eye, pointed
-- where the camera looks, while `raised`. Everyone else is told which of the two to show
-- (PoseClient.Broadcast: the "Pose" player attribute) and, when the server keeps the looks-only Tool
-- attributes, where the gun points. Without PoseClient nothing happens: Roblox's tool hold shows.
local function holdStep(char, cam, raised, t)
	local pose = other("PoseClient")
	if not pose or type(pose.Play) ~= "function" then
		return
	end
	local low = S.lowPose
	if not low or not low:IsPlaying() then
		if t < (S.poseRetryAt or 0) then
			return
		end
		low = pose.Play(char, "LowReady") -- (kept under "Aim" too: the arms never fall back to the walk between the two)
		S.lowPose = low
		if not low:IsPlaying() then
			S.poseRetryAt = t + 1 -- a body PoseClient can't pose: look again in a moment, not every frame
			return
		end
	end
	local look = cam.CFrame.LookVector
	if raised then
		local aim = S.aimPose
		if not aim or not aim:IsPlaying() then
			aim = pose.Play(char, "Aim")
			S.aimPose = aim
		end
		aim:Set("Point", cam.CFrame.Position + look * 300)
	else
		S.aimPose = nil
		-- (asked of PoseClient, not of our handle: its own copy of a broadcast can start one late)
		local aim = type(pose.Get) == "function" and pose.Get(char, "Aim") or nil
		if aim then
			aim:Stop()
		end
	end
	local name = raised and "Aim" or "LowReady"
	if type(pose.Broadcast) == "function" then
		if S.shownPose ~= name then
			if pose.Broadcast(name, true) then
				S.shownPose, S.shownAt = name, t
			end
		elseif t - (S.shownAt or 0) > 1.5 and player:GetAttribute(pose.Attribute or "Pose") ~= name then
			-- The server never took it (its rate limit, a lost message), so everyone else still sees the
			-- other stance: say it again.
			S.shownAt = t
			pose.Broadcast(name, true)
		end
	end
	-- Where it points, in steps of 2 degrees, only when something changed and never faster than the
	-- server listens.
	if K.AIMUP_ATTR and t - S.sentAt >= K.AIM_SEND then
		local pitch = math.floor(math.deg(math.asin(math.clamp(look.Y, -1, 1))) / 2 + 0.5) * 2
		if raised ~= S.sentUp or (raised and pitch ~= S.sentPitch) then
			S.sentUp, S.sentPitch, S.sentAt = raised, pitch, t
			send("Aim", pitch, raised)
		end
	end
end

-- The gun stopped being out: both poses end, here and for everyone else.
local function holdEnd()
	for _, key in ipairs({ "lowPose", "aimPose" }) do
		local handle = S[key]
		S[key] = nil
		if handle then
			handle:Stop()
		end
	end
	local shown = S.shownPose
	S.shownPose = nil
	if shown then
		ask("PoseClient", "Broadcast", shown, false)
	end
	if S.sentUp then
		S.sentUp, S.sentPitch = false, nil
		send("Aim", 0, false)
	end
end

-- Ten times a second: what other players' hands are doing, as far as the server's looks-only Tool
-- attributes say. A gun that PoseClient shows raised (its broadcast "Aim") is tipped up or down to
-- where it really points; a Fists tool whose Swing count went up throws that punch.
local function watchOthers()
	local pose = other("PoseClient")
	if not pose or type(pose.Get) ~= "function" or not (K.AIM_ATTR or K.SWING_ATTR) then
		return
	end
	local camPos = Workspace.CurrentCamera.CFrame.Position
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p ~= player and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - camPos).Magnitude <= K.POSE_RANGE then
			for _, c in ipairs(char:GetChildren()) do
				if c:IsA("Tool") then
					local kind = c:GetAttribute(K.ATTR)
					if kind == "Gun" and K.AIM_ATTR then
						local aim = pose.Get(char, "Aim")
						if aim then
							aim:Set("Pitch", tonumber(c:GetAttribute(K.AIM_ATTR)) or 0)
						end
					elseif kind == "Fists" and K.SWING_ATTR then
						local count = tonumber(c:GetAttribute(K.SWING_ATTR)) or 0
						local seen = S.seenSwing[p]
						S.seenSwing[p] = count
						if seen and count > seen then
							throwPunch(char, count, nil)
						end
					end
					break
				end
			end
		end
	end
end

------------------------------------------------------------------ fists

-- Only when the punch can't be posed (throwPunch: no PoseClient, an odd body):
-- the default Animate script's sword slash. A tool with a Handle gets it the classic way (a
-- "toolanim" StringValue the Animate script picks up); the Animate script ignores handle-less tools
-- like Fists, so for those we play its own "toolslash" animation (R6 or R15) straight on the Animator.
local function playSlash(char, tool)
	if tool:FindFirstChild("Handle") then
		local v = Instance.new("StringValue")
		v.Name = "toolanim"
		v.Value = "Slash"
		v.Parent = tool
		task.delay(1, function()
			v:Destroy() -- (the Animate script normally removes it first)
		end)
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local track = S.slashTracks[hum]
	if not track then
		local animate = char:FindFirstChild("Animate")
		local holder = animate and animate:FindFirstChild("toolslash")
		local anim = holder and holder:FindFirstChildOfClass("Animation")
		if not anim then
			return
		end
		track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		S.slashTracks[hum] = track
	end
	track:Play(0.05)
end

-- The player we're punching at: within reach and roughly in front, hittable ones first, then nearest.
-- Also returns whether that player looks hittable.
local function punchTarget(root)
	local look = flat(root.CFrame.LookVector)
	look = look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1)
	local best, bestD, bestOk
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p ~= player and p.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if r then
			local rel = r.Position - root.Position
			local d = flat(rel).Magnitude
			if d <= K.FISTS.Range and math.abs(rel.Y) < 6 and (d < 1 or flat(rel).Unit:Dot(look) > 0) then
				local ok = hittable(p)
				if not best or (ok and not bestOk) or (ok == bestOk and d < bestD) then
					best, bestD, bestOk = p, d, ok
				end
			end
		end
	end
	return best, bestOk == true
end

local function punch(tool)
	local t = os.clock()
	if t - S.lastSwing < K.FISTS.Cooldown then
		return
	end
	S.lastSwing = t
	local char, hum, root = myBody()
	if not char or hum.SeatPart then
		send("Punch", nil) -- the server explains (in a car)
		return
	end
	-- Pedestrians only live on this device: knock one over right here (never in a safe zone). They're
	-- judged by where we faced when we swung, before we turn toward any player.
	local look = root.CFrame.LookVector
	if not selfBlocked(hum) and PedClient.KnockNear(root.Position, look) then
		local at = root.Position + flat(look) * 3 + Vector3.new(0, 1, 0)
		SoundClient.Play("Punch", at)
		impact(at, -look, true) -- a small white puff where it landed
	end
	local target, ok = punchTarget(root)
	local r = ok and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if r then
		face(root, r.Position) -- only toward someone we could actually hit
	end
	-- The arm: a right, then a left, toward whoever we turned to (the old slash if it can't be posed).
	S.swings += 1
	if not throwPunch(char, S.swings, r and (r.Position + Vector3.new(0, 1, 0)) or nil) then
		playSlash(char, tool)
	end
	send("Punch", target) -- (an unhittable one too: the server explains why)
end

------------------------------------------------------------------ what state are we in

-- TeamUI's full-screen side picker (its KEEP MY SIDE button sits at the bottom centre).
local function pickerOpen()
	local picker = ui.picker
	if not picker or not picker.Parent then
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local teamGui = pg and pg:FindFirstChild("TeamUI")
		picker = teamGui and teamGui:FindFirstChild("Picker") or nil
		ui.picker = picker
	end
	if not picker or not picker:IsA("GuiObject") or not picker.Visible then
		return false
	end
	local teamGui = picker.Parent
	return not (teamGui:IsA("ScreenGui") and not teamGui.Enabled)
end

-- Is one of the other controllers' panels open? (pcall: one that failed to start must not stop us.)
local function controllerOpen(name)
	local m = other(name)
	if not m or type(m.IsOpen) ~= "function" then
		return false
	end
	local ok, open = pcall(m.IsOpen)
	return ok and open == true
end

-- A panel that needs the mouse and the screen: a gun is never "out" behind one.
-- (The house buy card too: with a pistol in hand the mouse stayed locked to the crosshair behind it, so
-- BUY and CANCEL couldn't be clicked and the click went off as a shot at the house.)
local function panelOpen()
	return shop.open or pickerOpen() or controllerOpen("PhoneUI") or controllerOpen("WardrobeUI") or controllerOpen("DealerClient")
		or controllerOpen("HouseClient")
end

-- Knocked over (by the server, or by a traffic car on this device only) or tasered.
local function downNow()
	local t = now()
	if (player:GetAttribute("KnockedUntil") or 0) > t or (player:GetAttribute("StunnedUntil") or 0) > t then
		return true
	end
	local impactClient = other("ImpactClient")
	return impactClient ~= nil and type(impactClient.IsKnocked) == "function" and impactClient.IsKnocked() == true
end

-- May the combat tools be used at all right now? Citizens and cops on foot, not at home, not picking a side.
local function hotbarWanted()
	local side = player:GetAttribute("Side")
	local _, hum = myBody()
	return (side == "Civilian" or side == "Cop") and hum ~= nil and hum.SeatPart == nil
		and player:GetAttribute("InHome") ~= true and not pickerOpen()
end

------------------------------------------------------------------ guns: ammo, reload, fire

-- Rounds in the magazine, as the server last said.
local function magazine()
	local a = gunTool and gunTool:GetAttribute(K.AMMO_ATTR)
	return type(a) == "number" and a or (gun and gun.Mag or 0)
end

-- How long after our last shot the server's count is surely about that shot too: a fixed beat plus
-- the trip there and back (on a slow connection the counter would jump up and down otherwise).
local function settleTime()
	local ok, ping = pcall(player.GetNetworkPing, player)
	return K.AMMO_SETTLE + ((ok and type(ping) == "number") and math.clamp(ping * 2, 0, 1) or 0)
end

-- No firing from the moment we ask for a reload until the server's ReloadUntil clears (or RELOAD_GRACE
-- passes without it ever appearing: the server said no).
local function reloading()
	if not gunTool then
		return false
	end
	local t = gunTool:GetAttribute(K.RELOAD_ATTR)
	if type(t) == "number" then
		return t > now() - 1 -- (the server clears it at the end; a stale one never locks the gun)
	end
	return S.reloadAskedAt ~= nil and os.clock() - S.reloadAskedAt < K.RELOAD_GRACE
end

local function stopReloadMotion()
	local m = S.reloadMotion
	S.reloadMotion = nil
	if m and m.weld and m.weld.Parent then
		m.weld.C0 = m.c0
	end
end

-- The reload, on this device only: the gun tips down and rolls in the hand, then comes back. It moves
-- the RightGrip weld Roblox makes for a held Tool (changes to it never leave this device).
local function startReloadMotion(seconds)
	stopReloadMotion()
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	local weld = hand and hand:FindFirstChild("RightGrip")
	if weld and not weld:IsA("Weld") then
		weld = nil
	end
	S.reloadMotion = { weld = weld, c0 = weld and weld.C0 or nil, t0 = os.clock(), dur = math.max(seconds, 0.2) }
	ui.reloadFill.Size = UDim2.fromScale(0, 1) -- (aimStep fills it)
end

local function requestReload()
	local g = gun
	if not gunOut or not g or not gunTool or reloading() then
		return
	end
	if math.min(ammo, magazine()) >= g.Mag then
		return -- full already
	end
	S.reloadAskedAt = os.clock()
	send("Reload", g.Id)
	ui.reloadFill.Size = UDim2.fromScale(0, 1) -- (empty until the server starts it)
	refreshAmmoHud()
end

-- Where the shot goes: the torso of a player we could hit who is within the assist angle of the
-- screen's middle, in range and in plain sight (nearest to the middle wins), else whatever the middle
-- of the screen points at. Returns the point and that player (or nil). within: another angle than the
-- device's aim assist (the wide one AIM's swing uses on touch and gamepad).
local function aimPoint(char, from, g, within)
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	local dir = ray.Direction.Unit
	local origin = ray.Origin
	local assist = within or (mode == "touch" and K.AIM.AssistTouch) or (mode == "gamepad" and K.AIM.AssistGamepad)
		or K.AIM.AssistMouse or 1.5
	local best, bestAngle, bestPos
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p ~= player and p.Character
		local torso = c and (c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso") or c:FindFirstChild("HumanoidRootPart"))
		if torso and torso:IsA("BasePart") and (torso.Position - from).Magnitude <= g.Range and gunTarget(p, g) then
			local v = torso.Position - origin
			-- (ahead of our head: never someone standing between the camera and us)
			if v.Magnitude > 0.1 and (torso.Position - from):Dot(dir) > 0 then
				local angle = math.deg(math.acos(math.clamp(v.Unit:Dot(dir), -1, 1)))
				if angle <= assist and (not bestAngle or angle < bestAngle)
					and solidHit(from, torso.Position - from, shotIgnore(char, c)) == nil then
					best, bestAngle, bestPos = p, angle, torso.Position -- (never snaps through a wall)
				end
			end
		end
	end
	if best then
		return bestPos, best
	end
	-- Start the aim ray level with our head, so a wall behind the camera can't catch the shot.
	local skip = math.max(0, (from - origin):Dot(dir))
	local start = origin + dir * skip
	local hit = solidHit(start, dir * 400, shotIgnore(char))
	-- A pedestrian under the crosshair, in front of whatever solid thing the ray ends on: the shot is
	-- aimed at them (PedClient.Under says why it missed without this). Citizens only, like the knock itself.
	if player:GetAttribute("Side") == "Civilian" and type(PedClient.Under) == "function" then
		local reach = hit and (hit - start).Magnitude or 400
		local ped = PedClient.Under(start, dir, reach)
		if ped and (ped - from).Magnitude <= g.Range then
			return ped, nil, true -- (third: a walker is under the crosshair, in the camera's plain sight)
		end
	end
	return hit or (origin + dir * (skip + 400)), nil
end

-- One pull of the trigger (first = true) or one tick of an automatic gun held down.
local function tryFire(first)
	local g, tool = gun, gunTool
	if not gunOut or not g or not tool then
		return
	end
	local t = os.clock()
	if t < S.nextFireAt then
		-- A pull that comes a moment before a one-shot-per-pull gun is ready is kept and fired the instant
		-- it is (aimStep). Mashing the Coast 9 faster than it fires used to lose every second click.
		if first and not g.Auto and S.nextFireAt - t <= 0.15 then
			S.queuedAt = S.nextFireAt
		end
		return
	end
	S.queuedAt = nil -- (this pull is the shot: nothing is left waiting)
	local char, hum, root = myBody()
	if not char then
		return
	end
	local head = char:FindFirstChild("Head")
	local from = (head and head:IsA("BasePart")) and head.Position or (root.Position + Vector3.new(0, 1.5, 0))
	if selfBlocked(hum) then
		-- Safe zone, passive, just spawned, swimming: nothing is shown and no round is counted. One ask
		-- per pull (never per automatic tick), so the server's toast says why.
		if first then
			S.nextFireAt = t + g.Interval
			send("Fire", g.Id, (aimPoint(char, from, g)), nil)
		end
		return
	end
	if reloading() then
		return
	end
	if ammo <= 0 then
		if not S.emptyClicked then
			S.emptyClicked = true
			SoundClient.Play("GunEmpty")
		end
		requestReload()
		return
	end
	-- Keep a held automatic gun on its beat: its next shot is timed from when this one was due, not from
	-- the frame it happened to land on. A fresh pull always waits the whole interval (the server gives a
	-- one-shot gun like the Gatorbite no early second shot, so drawing one would be a lie).
	if first or t - S.nextFireAt >= g.Interval then
		S.nextFireAt = t + g.Interval
	else
		S.nextFireAt += g.Interval
	end
	ammo -= 1
	S.lastShotAt, S.ammoSettled = t, false

	-- The body snaps round to the crosshair for the shot (aimStep keeps it there while the gun is up).
	local camLook = flat(Workspace.CurrentCamera.CFrame.LookVector)
	if camLook.Magnitude > 0.05 then
		face(root, root.Position + camLook)
	end
	local aim, target, sighted = aimPoint(char, from, g)
	local dir = aim - from
	if dir.Magnitude < 0.5 then
		dir = root.CFrame.LookVector -- (the server does the same for an aim point inside our head)
	end
	dir = dir.Unit

	-- Our own shot, drawn right away: the same rays the server casts (head -> aim, the gun's range),
	-- starting at the muzzle for the eye.
	local civilian = player:GetAttribute("Side") == "Civilian"
	local ignore = shotIgnore(char)
	local muzzle = S.gunMuzzle
	local start = muzzleSpot(tool, muzzle) or from
	muzzleFlash(muzzle)
	local thud = false
	for _ = 1, g.Pellets or 1 do
		local d = Combat.SpreadDir(dir, g.Spread or 0, S.rng)
		local pos, normal, body = solidHit(from, d * g.Range, ignore)
		local to = pos or (from + d * g.Range)
		local onBody = body ~= nil
		if civilian then
			-- PedClient finds a pedestrian along the shot and knocks them over (shot rays pass through them).
			-- sighted: the crosshair's own ray reached a walker (aim is their middle). The bullet leaves from
			-- the head, 2.3 studs left of and 0.7 below that ray: a post, a corner, a fence or the roof of our
			-- own car must not stop it short of the walker the camera sees.
			local reach = (to - from).Magnitude
			if sighted and not body then
				reach = math.max(reach, math.min(g.Range, (aim - from).Magnitude + 1))
			end
			local ped = PedClient.ShotAt(from, d, reach)
			if ped then
				to, pos, normal, onBody = ped, ped, nil, true
			end
		end
		tracer(start, to)
		if pos then
			impact(to, normal or -d, onBody)
			if not onBody and not thud then
				thud = true -- (one landing sound per pull, even for a shotgun)
				SoundClient.Play("BulletHit", to, nil, K.SHOT_LIFE)
			end
		end
	end
	SoundClient.Play(g.Sound, nil, nil, K.SHOT_LIFE)
	if t - S.lastShell > 0.15 then
		S.lastShell = t
		local feet = root.Position - Vector3.new(0, 2.5, 0)
		task.delay(0.3, function()
			SoundClient.Play("GunShell", feet, 0.6, K.SHOT_LIFE) -- (silent until Config.Sounds has the key)
		end)
	end
	S.recoilKick += (g.Recoil or 0.6) * ((holdAim or aimToggle) and 0.7 or 1)
	S.crossKick = math.min(S.crossKick + 4, 10)
	if S.aimPose then
		S.aimPose:Set("Recoil", 1) -- the arms kick too (PoseClient takes it once)
	end
	if t - S.lastScare >= 1 then
		S.lastScare = t
		PedClient.Scare(root.Position)
	end
	send("Fire", g.Id, aim, target)
	if ammo <= 0 then
		-- The last round: the reload starts by itself. (The server gets the shot first: remote calls
		-- arrive in the order they were sent.)
		S.emptyClicked = true
		requestReload()
	end
	refreshAmmoHud()
end

------------------------------------------------------------------ tools

local function hookTool(tool)
	if S.hooked[tool] or not tool:IsA("Tool") or tool:GetAttribute(K.ATTR) ~= "Fists" then
		return -- (guns never use Activated: they are ManualActivationOnly, so a camera drag can't fire one)
	end
	S.hooked[tool] = true
	tool.Activated:Connect(function()
		-- Never behind a panel: with Fists in hand, every drag across the dressing room's picture (the
		-- way to spin it) also threw a punch. A click there is for the panel. (Nor with the weapon wheel
		-- up: R2 or a click there is for picking.)
		if panelOpen() or S.wheelOpen then
			return
		end
		punch(tool)
	end)
end

local function watchContainer(container)
	for _, c in ipairs(container:GetChildren()) do
		hookTool(c)
	end
	container.ChildAdded:Connect(hookTool)
end

local function putAway()
	local _, hum = myBody()
	if hum then
		hum:UnequipTools()
	end
end

-- Our combat tools, in the Backpack and in the hand: Fists first, then the guns in shop order (the same
-- order as the hotbar). Second result: the one in the hand, or nil.
local function combatTools()
	local list = {}
	local held
	local char = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, holder in ipairs({ backpack or false, char or false }) do
		if holder then
			for _, c in ipairs(holder:GetChildren()) do
				if c:IsA("Tool") and c:GetAttribute(K.ATTR) ~= nil then
					table.insert(list, c)
					if holder == char then
						held = c
					end
				end
			end
		end
	end
	local function rank(tool)
		if tool:GetAttribute(K.ATTR) == "Fists" then
			return 0
		end
		return table.find(K.GUN_ORDER, tool:GetAttribute(K.GUN_ATTR)) or 99
	end
	table.sort(list, function(a, b)
		return rank(a) < rank(b)
	end)
	return list, held
end

-- What other controllers call a combat tool (WeaponWheel's slots): "Fists", or its gun id.
local function toolKey(tool)
	if tool:GetAttribute(K.ATTR) == "Fists" then
		return "Fists"
	end
	local id = tool:GetAttribute(K.GUN_ATTR)
	return type(id) == "string" and id or tool.Name
end

-- Hold this tool (nil: put everything away).
local function equip(tool)
	local _, hum = myBody()
	if not hum or hum.SeatPart then
		return
	end
	if tool and tool.Parent then
		hum:EquipTool(tool)
	else
		hum:UnequipTools()
	end
	SoundClient.Play("Click")
end

-- WEAPON tapped: the next tool after the one in hand (Fists first when the hands are empty). With a
-- single tool (a cop's Service Pistol) the tap draws it and puts it away again.
local function cycleWeapon()
	local list, held = combatTools()
	if #list == 0 then
		return
	end
	if #list == 1 and held then
		equip(nil)
		return
	end
	equip(list[(table.find(list, held) or 0) % #list + 1])
end

local function closeWeaponList()
	S.listOpen = false
	local list = ui.list
	if not list then
		return
	end
	list.Visible = false
	ui.backdrop.Visible = false
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
end

-- WEAPON held: every tool by name, the one in hand lit, and PUT AWAY.
local function openWeaponList()
	local list = ui.list
	local tools = combatTools()
	if not list or #tools == 0 then
		return
	end
	closeWeaponList()
	local char = player.Character
	local function row(text, order, lit, pick)
		local b = Instance.new("TextButton")
		b.Name = "Row"
		b.LayoutOrder = order
		b.Size = UDim2.new(1, 0, 0, Theme.Touch)
		b.Text = text
		Theme.Button(b, lit and "Primary" or "Quiet")
		b.FontFace = Theme.Font.Display
		b.TextSize = 16
		b.ZIndex = 6
		b.Parent = list
		b.Activated:Connect(function()
			closeWeaponList()
			pick()
		end)
	end
	for i, tool in ipairs(tools) do
		row(string.upper(tool.Name), i, tool.Parent == char, function()
			equip(tool)
		end)
	end
	row("PUT AWAY", #tools + 1, false, function()
		equip(nil)
	end)
	local height = (#tools + 1) * (Theme.Touch + 4) - 4 + 8
	list.Size = UDim2.fromOffset(168, height)
	ui.listScale.Scale = math.min(1, (gui.AbsoluteSize.Y - 16) / height) -- (a short phone with five tools)
	list.Visible = true
	ui.backdrop.Visible = true
	S.listOpen = true
end

-- The Roblox hotbar sits at the bottom centre, over every ScreenGui: show it only when the combat
-- tools can be used (a citizen or a cop on foot, not at home, not picking a side, not at the shop
-- counter). Hiding it also switches off the number keys, so nobody equips a tool from a car seat.
-- Never on a phone: bottom centre is the Corner zone there (the weapon readout), the phone hotbar
-- only shows three of the five tools anyway, and the WEAPON button reaches them all.
local function updateBackpack()
	if controllerOpen("WardrobeUI") then
		return -- the dressing room hides the hotbar and puts it back itself
	end
	local want = hotbarWanted() and not shop.open and mode ~= "touch"
	local ok, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
	if ok and on ~= want then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, want)
	end
end

------------------------------------------------------------------ HUD: building it

-- A Theme label (white, soft shadow). kind = "Display" | "Body" | "Bold".
local function label(parent, name, size, kind, text)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text or ""
	Theme.Text(l, size, kind)
	l.Parent = parent
	return l
end

-- A round touch button: flat and dark, white text, a thin ring so it reads over a bright street.
local function touchButton(name, text, textSize)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	Theme.Button(b, "Quiet")
	b.AutoButtonColor = false
	b.FontFace = Theme.Font.Display
	b.TextSize = textSize
	b.Visible = false
	b.ZIndex = 3
	Theme.Corners(b).CornerRadius = UDim.new(0.5, 0)
	local ring = Instance.new("UIStroke")
	ring.Color = C.Text
	ring.Thickness = 1.5
	ring.Transparency = 0.5
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = b
	b.Parent = gui
	return b
end

-- Hold-style button: onChange(true) while a finger (or the mouse) holds it, onChange(false) when the
-- last one lets go. Each touch is followed by its own InputObject until it lifts or is cancelled, even
-- if it slid off the button first (as DriveUI's pedals do), so FIRE can never stay stuck on.
-- onDrag(dx, dy), if given, gets the pixels a holding finger moved: a touch that starts on a button is
-- never seen by Roblox's camera, so FIRE turns the camera itself with them.
local function holdable(b, onChange, onDrag)
	local active = {} -- [InputObject] = { its connections }
	local down = false
	local function set(on)
		if on ~= down then
			down = on
			b.BackgroundTransparency = on and 0.05 or 0.35
			onChange(on)
		end
	end
	local function release(input)
		local conns = active[input]
		if conns then
			for _, conn in ipairs(conns) do
				conn:Disconnect()
			end
			active[input] = nil
		end
		if next(active) == nil then
			set(false)
		end
	end
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) and not active[input] then
			local conns = {
				input:GetPropertyChangedSignal("UserInputState"):Connect(function()
					local st = input.UserInputState
					if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
						release(input)
					end
				end),
			}
			if onDrag and t == Enum.UserInputType.Touch then
				local last = input.Position
				table.insert(conns, input:GetPropertyChangedSignal("Position"):Connect(function()
					local pos = input.Position
					onDrag(pos.X - last.X, pos.Y - last.Y)
					last = pos
				end))
			end
			active[input] = conns
			set(true)
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			release(input)
		end
	end)
end

local function buildHud()
	gui = Instance.new("ScreenGui")
	gui.Name = "CombatHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 3 -- over the HUD (0), under the mission intro (4, HUDController's own) and the phone (5)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- SAFE ZONE / PASSIVE: small flat tags in the Pills zone, under the cash, right-aligned like
	-- everything else in that corner (placeHud puts the row).
	local pills = Instance.new("Frame")
	pills.Name = "Pills"
	pills.BackgroundTransparency = 1
	pills.ZIndex = 2
	pills.Parent = gui
	ui.pills = pills
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = pills
	local function pill(name, text, color, order)
		local l = label(pills, name, 12, "Bold", text)
		l.LayoutOrder = order
		l.Size = UDim2.fromScale(0, 1)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.TextColor3 = color
		l.Visible = false
		Theme.Panel(l)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 9), UDim.new(0, 9)
		pad.Parent = l
		return l
	end
	ui.safePill = pill("SafeZone", "SAFE ZONE", C.Health, 1)
	ui.passivePill = pill("Passive", "PASSIVE", C.Text, 2)

	local flashFrame = Instance.new("Frame")
	flashFrame.Name = "HitFlash"
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundColor3 = K.FLASH
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Active = false
	flashFrame.Visible = false
	flashFrame.ZIndex = 1
	flashFrame.Parent = gui
	ui.flash = flashFrame

	-- Crosshair, in the exact middle (IgnoreGuiInset, like ViewportPointToRay): four short strokes that
	-- open a little with every shot, a centre dot, and four diagonal strokes for the hit marker.
	local cross = Instance.new("Frame")
	cross.Name = "Crosshair"
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromOffset(60, 60)
	cross.BackgroundTransparency = 1
	cross.Visible = false
	cross.ZIndex = 3
	cross.Parent = gui
	ui.cross = cross
	local function mark(name, w, h, anchor, rotation)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = anchor
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = C.Text
		f.BorderSizePixel = 0
		f.Rotation = rotation or 0
		local edge = Instance.new("UIStroke")
		edge.Color = C.Shadow
		edge.Thickness = 1
		edge.Transparency = 0.45
		edge.Parent = f
		f.Parent = cross
		return f
	end
	ui.marks = {
		mark("Left", 7, 2, Vector2.new(1, 0.5)),
		mark("Right", 7, 2, Vector2.new(0, 0.5)),
		mark("Up", 2, 7, Vector2.new(0.5, 1)),
		mark("Down", 2, 7, Vector2.new(0.5, 0)),
	}
	mark("Dot", 2, 2, Vector2.new(0.5, 0.5))
	ui.hits = {}
	for i, angle in ipairs({ 45, 135, 225, 315 }) do
		local h = mark("Hit" .. i, 9, 2, Vector2.new(0.5, 0.5), angle)
		local r = math.rad(angle)
		h.Position = UDim2.new(0.5, math.floor(math.cos(r) * 11 + 0.5), 0.5, math.floor(math.sin(r) * 11 + 0.5))
		h.Visible = false
		ui.hits[i] = h
	end

	-- Where the hit came from: a short red bar on a ring round the middle, turned toward the attacker.
	local ring = Instance.new("Frame")
	ring.Name = "HitFrom"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(190, 190)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 2
	ring.Parent = gui
	local fromBar = Instance.new("Frame")
	fromBar.Name = "Bar"
	fromBar.AnchorPoint = Vector2.new(0.5, 0)
	fromBar.Position = UDim2.fromScale(0.5, 0)
	fromBar.Size = UDim2.fromOffset(54, 5)
	fromBar.BackgroundColor3 = C.Danger
	fromBar.BackgroundTransparency = 1
	fromBar.BorderSizePixel = 0
	Theme.Corners(fromBar, 2)
	fromBar.Parent = ring
	ui.hitRing, ui.hitBar = ring, fromBar

	-- The weapon readout (Corner zone; placeHud puts it): the name of what is in your hand, "12 / ∞" for
	-- a gun, and a thin bar that fills while reloading.
	local ammoPanel = Instance.new("Frame")
	ammoPanel.Name = "Ammo"
	ammoPanel.Size = UDim2.fromOffset(150, 52)
	ammoPanel.BackgroundTransparency = 1
	ammoPanel.Visible = false
	ammoPanel.ZIndex = 2
	ammoPanel.Parent = gui
	ui.ammo = ammoPanel
	ui.gunName = label(ammoPanel, "Gun", 12, "Bold", "")
	ui.gunName.Size = UDim2.new(1, 0, 0, 14)
	ui.gunName.TextColor3 = C.Dim
	ui.gunName.TextXAlignment = Enum.TextXAlignment.Right
	ui.gunName.TextTruncate = Enum.TextTruncate.AtEnd
	ui.ammoText = label(ammoPanel, "Count", 28, "Display", "")
	ui.ammoText.Position = UDim2.fromOffset(0, 14)
	ui.ammoText.Size = UDim2.new(1, 0, 0, 30)
	ui.ammoText.TextXAlignment = Enum.TextXAlignment.Right
	local reloadBar, reloadFill = Theme.Bar(ammoPanel, C.Text)
	reloadBar.Name = "Reload"
	reloadBar.AnchorPoint = Vector2.new(0, 1)
	reloadBar.Position = UDim2.fromScale(0, 1)
	reloadBar.Size = UDim2.new(1, 0, 0, 4)
	reloadBar.Visible = false
	reloadFill.Size = UDim2.fromScale(0, 1)
	ui.reloadBar, ui.reloadFill = reloadBar, reloadFill

	-- HEALTH and ARMOR, side by side in the Vitals zone under the minimap: health on the left (the
	-- wider one), armor on the right. placeHud puts the strip, refreshVitals fills the bars.
	local vitals = Instance.new("Frame")
	vitals.Name = "Vitals"
	vitals.BackgroundTransparency = 1
	vitals.Visible = false
	vitals.ZIndex = 2
	vitals.Parent = gui
	local healthBar, healthFill = Theme.Bar(vitals, C.Health)
	healthBar.Name = "Health"
	healthBar.AnchorPoint = Vector2.new(0, 0.5)
	healthBar.Position = UDim2.fromScale(0, 0.5)
	healthBar.Size = UDim2.new(0.6, -2, 1, -4)
	local armorBar, armorFill = Theme.Bar(vitals, C.Armor)
	armorBar.Name = "Armor"
	armorBar.AnchorPoint = Vector2.new(1, 0.5)
	armorBar.Position = UDim2.fromScale(1, 0.5)
	armorBar.Size = UDim2.new(0.4, -2, 1, -4)
	armorFill.Size = UDim2.fromScale(0, 1)
	ui.vitals, ui.healthFill, ui.armorFill = vitals, healthFill, armorFill

	-- Controls, shown the first couple of times a gun comes out on a keyboard or gamepad (showHint).
	local hint = Instance.new("Frame")
	hint.Name = "GunHint"
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -24, 1, -84) -- just above the readout (placeHud)
	hint.Size = UDim2.fromOffset(0, 30)
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.Visible = false
	hint.ZIndex = 2
	Theme.Panel(hint)
	hint.Parent = gui
	local hintRow = Instance.new("UIListLayout")
	hintRow.FillDirection = Enum.FillDirection.Horizontal
	hintRow.VerticalAlignment = Enum.VerticalAlignment.Center
	hintRow.SortOrder = Enum.SortOrder.LayoutOrder
	hintRow.Padding = UDim.new(0, 6)
	hintRow.Parent = hint
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft, hintPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 10)
	hintPad.Parent = hint
	ui.hint = hint

	-- Touch: FIRE (hold; a drag of the same thumb turns the camera), AIM (toggle), RELOAD, WEAPON (tap =
	-- next, hold = the weapon wheel, or the list without it). placeHud puts them.
	ui.fire = touchButton("Fire", "FIRE", 18)
	holdable(ui.fire, function(on)
		triggerHeld = on
		if on then
			tryFire(true)
		end
	end, function(dx, dy)
		S.lookX += dx
		S.lookY += dy
	end)
	ui.aim = touchButton("Aim", "AIM", 15)
	ui.aim.Activated:Connect(function()
		aimToggle = not aimToggle
		refreshTouch()
	end)
	ui.reload = touchButton("Reload", "RELOAD", 11)
	ui.reload.Activated:Connect(requestReload)
	ui.weapon = touchButton("Weapon", "WEAPON", 11)
	holdable(ui.weapon, function(on)
		if on then
			local stamp = os.clock()
			S.weaponDown = stamp
			task.delay(0.4, function()
				if S.weaponDown == stamp then -- still held: the weapon wheel (the list without WeaponWheel)
					S.weaponDown = nil
					if ask("WeaponWheel", "OpenTouch") ~= true then
						openWeaponList()
					end
				end
			end)
		elseif S.weaponDown then
			S.weaponDown = nil
			cycleWeapon()
		end
	end)

	-- The weapon list (middle of the screen), and a see-through sheet behind it so a tap anywhere else
	-- closes it.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ListBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = gui
	backdrop.Activated:Connect(closeWeaponList)
	local list = Instance.new("Frame")
	list.Name = "WeaponList"
	list.AnchorPoint = Vector2.new(0.5, 0.5)
	list.Position = UDim2.fromScale(0.5, 0.5)
	list.Size = UDim2.fromOffset(168, 100)
	list.Visible = false
	list.ZIndex = 6
	Theme.Panel(list, 0.25)
	list.Parent = gui
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop, listPad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
	listPad.PaddingLeft, listPad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
	listPad.Parent = list
	local listScale = Instance.new("UIScale")
	listScale.Parent = list
	ui.backdrop, ui.list, ui.listScale = backdrop, list, listScale
end

------------------------------------------------------------------ HUD: keeping it right

local function refreshHud()
	local side = player:GetAttribute("Side")
	local show = side == "Civilian" or side == "Cop"
	ui.safePill.Visible = show and player:GetAttribute("InSafeZone") == true
	ui.passivePill.Visible = show and player:GetAttribute("Passive") == true
end

-- Put every piece in its Theme zone for the device in hand (see the header).
local function placeHud()
	local touch = mode == "touch"
	Theme.Place(ui.pills, "Pills", touch)
	Theme.Place(ui.vitals, "Vitals", touch)
	local cx, cy, cw, ch = zoneRect("Corner", touch)
	local bottom = math.floor(cy + ch)
	ui.ammo.AnchorPoint = Vector2.new(1, 1)
	if not touch then
		-- The Corner zone's own corner: free on foot (the car cluster only shows while driving).
		local right = math.floor(cx + cw)
		ui.ammo.Position = UDim2.fromOffset(right, bottom)
		ui.ammo.Size = UDim2.fromOffset(150, 52)
		ui.hint.Position = UDim2.fromOffset(right, bottom - 60)
		return
	end
	local size = gui.AbsoluteSize
	local k = math.clamp(math.min(size.X, size.Y) / 400, 1, 1.4)
	local fire, aim, small = math.floor(72 * k), math.floor(56 * k), math.floor(48 * k)
	local gap = 8
	-- Phone, Corner zone (bottom centre): the readout, then WEAPON and RELOAD on its right. The buttons
	-- stay right of the left 40% of the screen, where Roblox's thumbstick listens.
	local weaponX = math.max(math.floor(cx) + 100 + gap, math.ceil(size.X * 0.4) + 4)
	ui.ammo.Position = UDim2.fromOffset(weaponX - gap, bottom)
	ui.ammo.Size = UDim2.fromOffset(100, 52)
	ui.weapon.Size = UDim2.fromOffset(small, small)
	ui.weapon.Position = UDim2.fromOffset(weaponX, bottom - small)
	ui.reload.Size = UDim2.fromOffset(small, small)
	ui.reload.Position = UDim2.fromOffset(weaponX + small + gap, bottom - small)

	-- Roblox's touch jump button, in our ScreenGui's pixels: left, top. The real one when it exists; else
	-- where Roblox puts it (70 px on phones, 120 px on tablets).
	local function jumpCorner()
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local touchGui = pg and pg:FindFirstChild("TouchGui")
		local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
		local jump = frame and frame:FindFirstChild("JumpButton")
		if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 10 then
			local p = jump.AbsolutePosition - gui.AbsolutePosition
			return p.X, p.Y
		end
		local tiny = math.min(size.X, size.Y) <= 500
		local b = tiny and 70 or 120
		return size.X - (b * 1.5 - 10), size.Y - (tiny and (b + 20) or b * 1.75)
	end
	-- FIRE and AIM for the right thumb: just above the jump button, left of the side column (LawClient's
	-- situational tiles hug the right edge, 52 px wide) and under the Buttons zone. On a short phone the
	-- gaps above and below FIRE shrink before anything may touch; if it still can't fit under the
	-- Buttons zone the pair moves left of that zone.
	local _, jy = jumpCorner()
	local bx, by, bw, bh = zoneRect("Buttons", true)
	local right = math.floor(bx + bw) - 52 - gap
	local room = jy - (by + bh) - fire -- pixels left over for the gap above FIRE and the gap below it
	local fireBottom = math.floor(jy) - math.clamp(math.floor(room / 2), 2, gap)
	if room < 4 then
		right = math.floor(bx) - gap
		fireBottom = math.floor(jy) - gap
	end
	local fireX = right - fire
	ui.fire.Size = UDim2.fromOffset(fire, fire)
	ui.fire.Position = UDim2.fromOffset(fireX, fireBottom - fire)
	ui.aim.Size = UDim2.fromOffset(aim, aim)
	ui.aim.Position = UDim2.fromOffset(fireX - gap - aim, fireBottom - aim)
end

local function refreshVitals()
	local health = Combat.Health(player) / K.DAZE_MAX
	local armor = Combat.ArmorOf(player) / K.ARMOR_MAX
	TweenService:Create(ui.healthFill, K.VITALS_TWEEN, { Size = UDim2.fromScale(health, 1) }):Play()
	TweenService:Create(ui.armorFill, K.VITALS_TWEEN, { Size = UDim2.fromScale(armor, 1) }):Play()
	ui.healthFill.BackgroundColor3 = health < 0.3 and C.Danger or C.Health
end

-- The strip shows while you're hurt or armored, for 4 s after either changed, and with a gun in hand.
-- (Roblox's own health bar is off: HUDController.) Never over the first-join title screen.
showVitals = function()
	local side = player:GetAttribute("Side")
	ui.vitals.Visible = (side == "Civilian" or side == "Cop") and player:GetAttribute("TitleScreen") ~= true
		and ((player:GetAttribute("Daze") or 0) > 0 or Combat.ArmorOf(player) > 0 or os.clock() < S.vitalsUntil
			or gunTool ~= nil)
end

refreshAmmoHud = function()
	local g = gun
	local armed = gunOut and g ~= nil
	ui.ammo.Visible = armed or S.fistsOut == true
	if not armed then
		-- Fists in hand: only the name (on a phone there is no hotbar to say so).
		ui.gunName.Text = string.upper(K.FISTS.Name or "Fists")
		ui.ammoText.Text = ""
		ui.reloadBar.Visible = false
		return
	end
	local busy = reloading()
	ui.gunName.Text = string.upper(g.Name)
	ui.ammoText.Text = tostring(math.max(ammo, 0)) .. " / ∞"
	ui.ammoText.TextColor3 = (ammo <= 0 and not busy) and C.Danger or C.Text
	ui.ammoText.TextTransparency = busy and 0.5 or 0
	ui.reloadBar.Visible = busy
	for _, m in ipairs(ui.marks) do
		m.BackgroundTransparency = busy and 0.6 or 0 -- the crosshair dims: no shot until the reload is done
	end
end

refreshTouch = function()
	local touch = mode == "touch"
	local out = touch and gunOut
	ui.fire.Visible = out
	ui.aim.Visible = out
	ui.reload.Visible = out
	-- WEAPON is there whenever the tools can be used: it is how a phone gets from fists to a gun.
	local switch = touch and hotbarWanted() and not downNow() and not panelOpen() and (gunTool ~= nil or #combatTools() > 0)
	ui.weapon.Visible = switch
	if not switch and S.listOpen then
		closeWeaponList()
	end
	-- AIM is a toggle on touch: lit while zoomed.
	ui.aim.BackgroundColor3 = aimToggle and C.Text or C.Panel
	ui.aim.BackgroundTransparency = aimToggle and 0.1 or 0.35
	ui.aim.TextColor3 = aimToggle and C.Panel or C.Text
end

-- Key caps for the gun controls, the first two times a gun comes out (touch has labelled buttons).
local function showHint()
	if mode == "touch" or S.hints >= 2 then
		return
	end
	S.hints += 1
	local hint = ui.hint
	for _, c in ipairs(hint:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local pad = mode == "gamepad"
	local pairsList = { { pad and "R2" or "LMB", "FIRE" }, { pad and "L2" or "RMB", "AIM" }, { pad and "X" or "R", "RELOAD" } }
	if not pad then
		table.insert(pairsList, { "ALT", "CURSOR" }) -- (hold it to click the HUD with a gun out)
	end
	if other("WeaponWheel") then
		table.insert(pairsList, { pad and "D-PAD LEFT" or "TAB", "WEAPONS" }) -- (hold it: the weapon wheel)
	end
	for i, pair in ipairs(pairsList) do
		Theme.Key(hint, pair[1]).LayoutOrder = i * 2 - 1
		local word = label(hint, "Word", 13, "Bold", pair[2])
		word.LayoutOrder = i * 2
		word.Size = UDim2.fromOffset(0, 22)
		word.AutomaticSize = Enum.AutomaticSize.X
	end
	hint.Visible = true
	S.hintToken += 1
	local token = S.hintToken
	task.delay(8, function()
		if S.hintToken == token then
			hint.Visible = false
		end
	end)
end

------------------------------------------------------------------ the gun in hand

local function onAmmoChanged()
	local a = magazine()
	if os.clock() - S.lastShotAt >= settleTime() then
		ammo, S.ammoSettled = a, true
	else
		ammo = math.min(ammo, a) -- shots still on their way to the server: never count back up yet
	end
	refreshAmmoHud()
end

local function onReloadChanged()
	local tool = gunTool
	if not tool then
		return
	end
	local t = tool:GetAttribute(K.RELOAD_ATTR)
	if type(t) == "number" then
		-- The server started the reload: the motion and the sound start now.
		S.reloadAskedAt = nil
		startReloadMotion(t - now())
		SoundClient.Play("GunReload")
	else
		-- Done (or cancelled by putting the gun away): the magazine is whatever the server says.
		stopReloadMotion()
		S.reloadAskedAt = nil
		S.emptyClicked = false
		ammo, S.ammoSettled = magazine(), true
	end
	refreshAmmoHud()
end

-- A tool went into or out of our hand.
local function refreshGun()
	local char = player.Character
	local tool = gunToolOf(char)
	local g = tool and Combat.ToolGun(tool) or nil
	if not g then
		tool = nil
	end
	local fists = false
	if not tool and char then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") and c:GetAttribute(K.ATTR) == "Fists" then
				fists = true
				break
			end
		end
	end
	local fistsChanged = fists ~= (S.fistsOut == true)
	S.fistsOut = fists
	if tool == gunTool then
		if fistsChanged then
			refreshAmmoHud()
		end
		return
	end
	for _, c in ipairs(S.gunConns) do
		c:Disconnect()
	end
	table.clear(S.gunConns)
	stopReloadMotion()
	gunTool, gun = tool, g
	S.gunMuzzle = muzzleOf(tool)
	triggerHeld, holdAim, aimToggle = false, false, false
	S.reloadAskedAt, S.emptyClicked = nil, false
	S.queuedAt = nil
	S.lastShotAt, S.ammoSettled = -math.huge, true
	if tool then
		ammo = magazine()
		S.nextFireAt = os.clock() + K.DRAW_TIME
		table.insert(S.gunConns, tool:GetAttributeChangedSignal(K.AMMO_ATTR):Connect(onAmmoChanged))
		table.insert(S.gunConns, tool:GetAttributeChangedSignal(K.RELOAD_ATTR):Connect(onReloadChanged))
	end
	refreshVitals()
	showVitals()
	refreshAmmoHud()
	refreshTouch()
end

-- Gamepad X with a gun out. X is also GET IN / JACK (InteractClient) and the button of every prompt,
-- so the press is only taken (sunk: nobody else sees it) when there is something to reload. With a
-- full magazine it passes straight through.
local function padReload(_, state)
	if state == Enum.UserInputState.Begin and gunOut and gun and not reloading() and math.min(ammo, magazine()) < gun.Mag then
		requestReload()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function enterGunOut(hum)
	gunOut = true
	S.aimHum, S.easeHum = hum, nil
	S.lastGap = -1
	S.raised, S.wasAiming, S.lockPart = false, false, nil
	S.lookX, S.lookY = 0, 0
	S.nextFireAt = math.max(S.nextFireAt, os.clock() + 0.1)
	-- The camera over the shoulder: LocomotionClient owns Humanoid.CameraOffset and keeps it out of
	-- walls. (Without that controller aimStep writes the offset itself.)
	local loco = other("LocomotionClient")
	S.camOn = loco ~= nil and type(loco.RequestCameraOffset) == "function" and type(loco.ReleaseCameraOffset) == "function"
	if S.camOn then
		pcall(loco.RequestCameraOffset, "Gun", K.SHOULDER, 10, 12)
	end
	-- ...and close: never first person, never far away. The player's own limits (and where they had the
	-- view) are remembered for exitGunOut. A place locked to first person is left alone.
	S.zoomToken = (S.zoomToken or 0) + 1 -- (a put-back still on its way is called off: see exitGunOut)
	local pending = S.zoomPending
	S.zoomPending = nil
	local zmin = pending and pending[1] or player.CameraMinZoomDistance
	local zmax = pending and pending[2] or player.CameraMaxZoomDistance
	if zmax >= K.ZOOM_MIN then
		local cam = Workspace.CurrentCamera
		S.zoomMin, S.zoomMax = zmin, zmax
		S.zoomWas = pending and pending[3] or camDistance()
			or (cam and (cam.CFrame.Position - cam.Focus.Position).Magnitude or nil)
		local far = math.min(zmax, math.max(K.ZOOM_MAX, zmin))
		local near = math.clamp(K.ZOOM_MIN, math.min(zmin, far), far)
		-- (in this order the nearest limit is never above the farthest one, whatever they were)
		player.CameraMinZoomDistance = math.min(player.CameraMinZoomDistance, near)
		player.CameraMaxZoomDistance = far
		player.CameraMinZoomDistance = near
	end
	if not S.padBound then
		S.padBound = true
		ContextActionService:BindActionAtPriority(K.PAD_RELOAD, padReload, false, 3000, Enum.KeyCode.ButtonX)
	end
	showHint()
end

-- The gun stopped being out: everything it changed is put back, once.
local function exitGunOut()
	gunOut = false
	triggerHeld, holdAim, aimToggle = false, false, false
	S.recoilKick, S.recoilSettle, S.crossKick = 0, 0, 0
	S.queuedAt = nil
	S.raised, S.wasAiming, S.lockPart = false, false, nil
	S.lookX, S.lookY = 0, 0
	holdEnd()
	local hum = S.aimHum
	S.aimHum = nil
	if hum and hum.Parent then
		hum.AutoRotate = true
	end
	local loco = other("LocomotionClient")
	if S.camOn then
		S.camOn = false
		ask("LocomotionClient", "ReleaseCameraOffset", "Gun")
	elseif hum and hum.Parent then
		S.easeHum = hum -- (aimStep slides the camera offset back to zero over a few frames)
	end
	if S.fovOn then
		S.fovOn, S.fovAim = false, false
		ask("LocomotionClient", "ReleaseFov", "Gun") -- (it eases the view back to its own FOV)
	elseif not loco then
		local cam = Workspace.CurrentCamera
		if cam then
			cam.FieldOfView = K.NORMAL_FOV
		end
	end
	if S.capOn then
		S.capOn = false
		ask("LocomotionClient", "SetCap", "aim", nil)
	end
	if S.mouseLocked then
		S.mouseLocked = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	if S.padBound then
		S.padBound = false
		ContextActionService:UnbindAction(K.PAD_RELOAD)
	end
	-- The camera distance: the player's own limits again, and the view back where they had it. Roblox's
	-- camera is told so directly when that works (camDistance); else, if they had it further out (or
	-- closer in) than a gun allows, both limits sit on that distance for a moment first: the camera only
	-- moves by itself when its limits say so.
	if S.zoomMax then
		local zmin, zmax, was = S.zoomMin, S.zoomMax, S.zoomWas
		S.zoomMin, S.zoomMax, S.zoomWas, S.aimWas = nil, nil, nil, nil
		local back = was and math.clamp(was, zmin, zmax) or nil
		if back and camDistance() ~= nil then
			player.CameraMaxZoomDistance = zmax
			player.CameraMinZoomDistance = zmin
			camDistance(back)
		elseif back and (back > K.ZOOM_MAX + 0.5 or back < K.ZOOM_MIN - 0.5) then
			S.zoomPending = { zmin, zmax, was }
			if back > player.CameraMaxZoomDistance then
				player.CameraMaxZoomDistance = back
				player.CameraMinZoomDistance = back
			else
				player.CameraMinZoomDistance = back
				player.CameraMaxZoomDistance = back
			end
			S.zoomToken = (S.zoomToken or 0) + 1
			local token = S.zoomToken
			task.delay(0.2, function()
				if S.zoomToken == token and S.zoomPending then
					S.zoomPending = nil
					player.CameraMaxZoomDistance = zmax
					player.CameraMinZoomDistance = zmin
				end
			end)
		else
			player.CameraMaxZoomDistance = zmax
			player.CameraMinZoomDistance = zmin
		end
	end
	S.hintToken += 1
	ui.hint.Visible = false
end

-- Every frame, right after the camera: is the gun out, and if so the over-the-shoulder camera, how the
-- gun is held, the body's facing, the mouse lock, the zoom, the recoil, automatic fire and the crosshair.
local function aimStep(dt)
	if gunTool and gunTool.Parent ~= player.Character then
		refreshGun() -- (it left our hand without a ChildRemoved we saw: a respawn)
	end
	local char, hum, root = myBody()
	-- (Not in the water: nothing could be fired there anyway. Not at home: the hotbar is hidden there,
	-- so nothing could put the gun away again.)
	local want = gunTool ~= nil and char ~= nil and hum.SeatPart == nil and not downNow() and not panelOpen()
		and player:GetAttribute("InHome") ~= true and hum:GetState() ~= Enum.HumanoidStateType.Swimming
	if gunOut and (not want or hum ~= S.aimHum) then
		exitGunOut()
	end
	if want and not gunOut then
		enterGunOut(hum)
	end
	if ui.cross.Visible ~= gunOut then
		ui.cross.Visible = gunOut
		refreshAmmoHud()
		refreshTouch()
	end
	if not gunOut then
		local h = S.easeHum
		if h then
			if h.Parent and h.CameraOffset.Magnitude > 0.02 then
				h.CameraOffset = h.CameraOffset:Lerp(Vector3.zero, 1 - math.exp(-dt * 14))
			else
				if h.Parent then
					h.CameraOffset = Vector3.zero
				end
				S.easeHum = nil
			end
		end
		return
	end

	local cam = Workspace.CurrentCamera
	local t = os.clock()
	local g = gun
	local aiming = holdAim or aimToggle
	-- "Up": aiming, firing, or just fired. The body turns to the crosshair and walks; the gun itself
	-- comes up too, except during the reload.
	local up = aiming or triggerHeld or t - S.lastShotAt < K.STRAFE_HOLD
	local raised = up and not reloading()
	S.raised = raised

	-- Camera over the shoulder. LocomotionClient does it when it is there (asked in enterGunOut); else
	-- the offset is written here, turned from the view's frame into the body's (they differ whenever the
	-- body doesn't face where the camera looks).
	if not S.camOn then
		local right = cam.CFrame.RightVector
		local back = right:Cross(Vector3.yAxis)
		local wantOffset = root.CFrame:VectorToObjectSpace(right * K.SHOULDER.X + Vector3.yAxis * K.SHOULDER.Y + back * K.SHOULDER.Z)
		local offset = hum.CameraOffset
		if (offset - wantOffset).Magnitude > 0.01 then
			hum.CameraOffset = offset:Lerp(wantOffset, 1 - math.exp(-dt * 12))
		end
	end
	-- ...and close, closer still while aiming (the farthest the camera may sit). Letting go of AIM
	-- puts the view back where it was, when Roblox's camera can be told so.
	if S.zoomMax then
		if aiming and not S.wasAiming then
			S.aimWas = camDistance() -- (read before the limit below pulls the view in)
		end
		local far = math.max(math.min(S.zoomMax, aiming and K.ZOOM_AIM or K.ZOOM_MAX), player.CameraMinZoomDistance)
		if math.abs(player.CameraMaxZoomDistance - far) > 0.01 then
			player.CameraMaxZoomDistance = far
		end
		if S.wasAiming and not aiming and S.aimWas then
			camDistance(math.clamp(S.aimWas, player.CameraMinZoomDistance, far))
			S.aimWas = nil
		end
	end

	-- With the gun low you run and turn as always. While it is up the body faces where the camera looks
	-- (only while it stands, runs or jumps: never on a ladder) and you walk.
	local state = hum:GetState()
	local turn = up and (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics
		or state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Landed)
	if hum.AutoRotate == turn then
		hum.AutoRotate = not turn
	end
	if turn then
		local look = flat(cam.CFrame.LookVector)
		if look.Magnitude > 0.05 then
			look = look.Unit
			if root.CFrame.LookVector:Dot(look) < 0.9999 then
				local p = root.Position
				root.CFrame = CFrame.lookAt(p, p + look)
			end
		end
	end
	if up ~= S.capOn then
		S.capOn = up
		ask("LocomotionClient", "SetCap", "aim", up and K.AIM_WALK or nil)
	end

	-- Keyboard and mouse: the mouse is locked to the crosshair (and turns the camera without a button
	-- held). Holding Left Alt frees it, so the HUD's buttons can still be clicked with a gun out; so does
	-- the weapon wheel (its cursor picks the slot).
	if mode == "keyboard" and not S.wheelOpen and not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if not S.mouseLocked then
			S.mouseLocked = true
			UserInputService.MouseIconEnabled = false
		end
	elseif S.mouseLocked then
		S.mouseLocked = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end

	-- Zoom. LocomotionClient owns the on-foot FOV: it is asked for the zoom while aiming and for the
	-- quick way back afterwards, then let go (so its sprint FOV works with a gun out too).
	local loco = other("LocomotionClient")
	if loco and type(loco.RequestFov) == "function" and type(loco.ReleaseFov) == "function" then
		if aiming then
			if not S.fovAim then
				S.fovOn, S.fovAim = true, true
				pcall(loco.RequestFov, "Gun", K.ZOOM_FOV, 10, 3 / K.ZOOM_TIME)
			end
		elseif S.fovOn then
			if S.fovAim then
				S.fovAim = false
				pcall(loco.RequestFov, "Gun", K.NORMAL_FOV, 10, 3 / K.ZOOM_TIME)
			elseif cam.FieldOfView >= K.NORMAL_FOV - 0.5 then
				S.fovOn = false
				pcall(loco.ReleaseFov, "Gun")
			end
		end
	else
		local wantFov = aiming and K.ZOOM_FOV or K.NORMAL_FOV
		local fov = cam.FieldOfView
		if math.abs(fov - wantFov) > 0.05 then
			cam.FieldOfView = fov + (wantFov - fov) * (1 - math.exp(-dt * 3 / K.ZOOM_TIME))
		end
	end

	-- Touch and gamepad: pressing AIM swings the view onto the nearest player you could hit who is
	-- close to the crosshair (a mouse aims itself). Camera turns made here carry over: Roblox's camera
	-- takes its next look from the camera's own CFrame.
	if aiming and not S.wasAiming and mode ~= "keyboard" and g then
		local head = char:FindFirstChild("Head")
		local _, who = aimPoint(char, (head and head:IsA("BasePart")) and head.Position or root.Position, g, K.LOCK_ANGLE)
		local body = who and who.Character
		S.lockPart = body and (body:FindFirstChild("UpperTorso") or body:FindFirstChild("HumanoidRootPart")) or nil
		S.lockUntil = t + K.LOCK_TIME * 2.5
	end
	S.wasAiming = aiming
	local lock = S.lockPart
	if lock then
		local to = lock.Position - cam.CFrame.Position
		if aiming and t < S.lockUntil and lock.Parent and to.Magnitude > 1 and math.abs(to.Unit.Y) < 0.98 then
			local cf = cam.CFrame
			cam.CFrame = cf:Lerp(CFrame.lookAt(cf.Position, lock.Position), 1 - math.exp(-dt * 3 / K.LOCK_TIME))
		else
			S.lockPart = nil
		end
	end
	-- Touch: the thumb holding FIRE turns the camera (Roblox's camera never sees a touch that began on a
	-- button). Less per pixel while zoomed, in step with the FOV; never past straight up or down.
	if S.lookX ~= 0 or S.lookY ~= 0 then
		local k = math.rad(K.TOUCH_LOOK) * math.clamp(cam.FieldOfView / K.NORMAL_FOV, 0.4, 1)
		local cf = cam.CFrame
		local pitchNow = math.asin(math.clamp(cf.LookVector.Y, -1, 1))
		local pitch = math.clamp(pitchNow - S.lookY * k, -1.39, 1.39) - pitchNow
		cam.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, -S.lookX * k, 0) * cf.Rotation * CFrame.Angles(pitch, 0, 0)
		S.lookX, S.lookY = 0, 0
		S.lockPart = nil -- the thumb has taken over
	end

	-- Recoil: the kick goes up fast and most of it settles back, so holding an automatic climbs a little.
	if S.recoilKick > 0.001 or S.recoilSettle > 0.001 then
		local kick = S.recoilKick * math.min(1, dt * 30)
		S.recoilKick -= kick
		S.recoilSettle += kick * 0.6
		local down = S.recoilSettle * math.min(1, dt * 7)
		S.recoilSettle -= down
		local net = kick - down
		if net < 0 or cam.CFrame.LookVector.Y < 0.9 then
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(net), 0, 0)
		end
	end

	-- How the gun is held, here and for everyone else. (Looks only: a fault in there never ends gun mode.)
	local held, why = pcall(holdStep, char, cam, raised, t)
	if not held and t - (S.poseWarnAt or 0) > 10 then
		S.poseWarnAt = t
		warn("[CombatClient] holding the gun: " .. tostring(why))
	end
	-- Pedestrians you point a raised gun at put their hands up (PedClient decides who and how many).
	if aiming and t - S.lastAimedAt >= 0.5 and type(PedClient.AimedAt) == "function" then
		S.lastAimedAt = t
		local head = char:FindFirstChild("Head")
		pcall(PedClient.AimedAt, (head and head:IsA("BasePart")) and head.Position or root.Position, cam.CFrame.LookVector)
	end

	-- Ammo: the server's count replaces our guess once our shots have surely arrived.
	if not S.ammoSettled and t - S.lastShotAt >= settleTime() then
		ammo, S.ammoSettled = magazine(), true
		refreshAmmoHud()
	end
	if S.reloadAskedAt and t - S.reloadAskedAt >= K.RELOAD_GRACE then
		S.reloadAskedAt = nil -- the server never started it: the gun is free again
		refreshAmmoHud()
	end
	if ammo > 0 then
		S.emptyClicked = false
	end

	-- Automatic guns keep firing while the trigger is held.
	if triggerHeld and g and g.Auto then
		tryFire(false)
	elseif S.queuedAt and t >= S.queuedAt then
		S.queuedAt = nil
		tryFire(true) -- the pull that came a moment early (tryFire kept it)
	end

	-- The reload: the gun tilts in the hand, the bar under the ammo fills.
	local m = S.reloadMotion
	if m then
		local k = (t - m.t0) / m.dur
		if k >= 1 then
			stopReloadMotion()
		else
			if m.weld and m.weld.Parent then
				local e = math.sin(k * math.pi)
				m.weld.C0 = m.c0 * CFrame.Angles(math.rad(-40) * e, 0, math.rad(25) * e) * CFrame.new(0, -0.25 * e, 0)
			end
			ui.reloadFill.Size = UDim2.fromScale(k, 1)
		end
	end

	-- Crosshair: the strokes open with each shot and close again; tighter while zoomed.
	S.crossKick *= math.exp(-dt * 12)
	local gapNow = math.floor((aiming and 4 or 7) + S.crossKick + 0.5)
	if gapNow ~= S.lastGap then
		S.lastGap = gapNow
		local marks = ui.marks
		marks[1].Position = UDim2.new(0.5, -gapNow, 0.5, 0)
		marks[2].Position = UDim2.new(0.5, gapNow, 0.5, 0)
		marks[3].Position = UDim2.new(0.5, 0, 0.5, -gapNow)
		marks[4].Position = UDim2.new(0.5, 0, 0.5, gapNow)
	end
	-- The hit marker: white, blue when armor took it all, gold for a knockout (onFx sets S.hitColor).
	local hitNow = t < S.hitUntil
	if hitNow ~= S.hitShown or (hitNow and S.hitColor ~= S.hitDrawn) then
		S.hitShown, S.hitDrawn = hitNow, S.hitColor
		for _, h in ipairs(ui.hits) do
			h.Visible = hitNow
			h.BackgroundColor3 = S.hitColor or C.Text
		end
	end
end

------------------------------------------------------------------ health bars over other players

local function removeBar(p)
	local b = bars[p]
	if b then
		b.gui:Destroy()
		bars[p] = nil
	end
end

local function barFor(p, head)
	local b = bars[p]
	if b then
		if b.gui.Adornee ~= head then
			b.gui.Adornee = head
		end
		return b
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "NCHealth_" .. p.UserId
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(64, 8) -- pixels, so it's just as readable 80 studs away
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.SizeOffset = Vector2.new(0, 2.7) -- ~20 px higher: clear of a crewmate's name tag (CrewClient)
	bb.MaxDistance = Combat.BarRange
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = C.Panel
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	Theme.Corners(back, 2)
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = C.Health
	fill.BorderSizePixel = 0
	Theme.Corners(fill, 2)
	fill.Parent = back
	-- Armor: a thin blue line along the bottom.
	local armor = Instance.new("Frame")
	armor.Name = "Armor"
	armor.AnchorPoint = Vector2.new(0, 1)
	armor.Position = UDim2.fromScale(0, 1)
	armor.Size = UDim2.new(0, 0, 0, 2)
	armor.BackgroundColor3 = C.Armor
	armor.BorderSizePixel = 0
	armor.ZIndex = 2
	armor.Parent = back
	bb.Parent = gui.Parent -- PlayerGui (a BillboardGui there draws on its Adornee)
	b = { gui = bb, fill = fill, armor = armor }
	bars[p] = b
	return b
end

-- A bar over every other player who is hurt and close. (Your own health is the strip on your HUD.)
local function updateBars()
	local _, _, root = myBody()
	local center = root and root.Position or Workspace.CurrentCamera.CFrame.Position
	for _, p in ipairs(Players:GetPlayers()) do
		local daze = p:GetAttribute("Daze")
		local head = p ~= player and p.Character and p.Character:FindFirstChild("Head")
		if type(daze) == "number" and daze > 0 and head and head:IsA("BasePart") and (head.Position - center).Magnitude <= Combat.BarRange then
			local health = Combat.Health(p) / K.DAZE_MAX
			local b = barFor(p, head)
			b.fill.Size = UDim2.fromScale(health, 1)
			b.fill.BackgroundColor3 = health < 0.3 and C.Danger or C.Health
			b.armor.Size = UDim2.new(Combat.ArmorOf(p) / K.ARMOR_MAX, 0, 0, 2)
		else
			removeBar(p)
		end
	end
	for p in pairs(bars) do
		if p.Parent ~= Players then
			removeBar(p)
		end
	end
end

------------------------------------------------------------------ Coast Arms: the shop panel

local function buy(id)
	local t = os.clock()
	if t - shop.lastBuy < 1 then -- (CombatService answers one BUY a second: a faster one would be dropped unsaid)
		return -- (the server takes one purchase a second)
	end
	shop.lastBuy = t
	SoundClient.Play("Click")
	task.spawn(function()
		S.buyRemote = S.buyRemote or Remotes.Event("GunShopBuy")
		S.buyRemote:FireServer(id)
	end)
end

-- Prices, OWNED, rank locks and the armor bar, from our own attributes (Guns, Armor, Cash, CivRank).
local function refreshShop()
	if not shop.gui then
		return
	end
	local cash = player:GetAttribute("Cash") or 0
	shop.cash.Text = money(cash)
	for _, row in ipairs(shop.rows) do
		local b = row.button
		local text, kind
		if row.gun then
			if Combat.Owns(player, row.id) then
				text, kind = "OWNED", "off"
			elseif not Combat.RankOk(player, row.gun) then
				text, kind = "RANK " .. tostring(row.gun.Rank or 1), "locked"
			end
		else
			local armor = Combat.ArmorOf(player)
			row.fill.Size = UDim2.fromScale(armor / K.ARMOR_MAX, 1)
			if armor >= K.ARMOR_MAX then
				text, kind = "FULL", "off"
			end
		end
		if not text then
			text, kind = money(row.price), cash >= row.price and "buy" or "poor"
		end
		row.kind = kind
		b.Text = text
		Theme.Button(b, kind == "buy" and "Primary" or "Quiet")
		b.FontFace = Theme.Font.Display
		if kind == "poor" then
			b.TextColor3 = C.Danger -- (still a button: the server's toast says "not enough cash")
		elseif kind == "locked" then
			b.TextColor3 = C.Gold -- (still a button: the toast says which rank it needs)
		elseif kind == "off" then
			b.TextColor3 = C.Dim
		end
		b.AutoButtonColor = kind ~= "off"
		b.Selectable = kind ~= "off"
		if kind == "off" and GuiService.SelectedObject == b then
			GuiService.SelectedObject = shop.close -- (a gamepad just bought this one)
		end
	end
end

local function fitShop()
	if not shop.gui then
		return
	end
	local vp = Workspace.CurrentCamera.ViewportSize
	shop.scale.Scale = math.min(1, (vp.X - 16) / K.SHOP_W, (vp.Y - 16) / shop.height)
end

local function buildShop()
	local sg = Instance.new("ScreenGui")
	sg.Name = "GunShop"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = 6 -- over the phone (5), under the toasts (20)
	sg.Enabled = false
	sg.Parent = player:WaitForChild("PlayerGui")

	local guns = {}
	for _, id in ipairs(K.GUN_ORDER) do
		local g = Combat.Gun(id)
		if g then
			table.insert(guns, g)
		end
	end
	local height = K.SHOP_TOP + (#guns + 1) * (K.SHOP_ROW + 4) + K.SHOP_NOTE

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(K.SHOP_W, height)
	panel.Active = true -- taps on the panel never fall through to the game
	Theme.Panel(panel, 0.15)
	panel.Parent = sg
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = label(panel, "Title", 22, "Display", string.upper(K.SHOP.Name or "Coast Arms"))
	title.Position = UDim2.fromOffset(14, 0)
	title.Size = UDim2.fromOffset(200, K.SHOP_TOP)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local cash = label(panel, "Cash", 18, "Display", "")
	cash.AnchorPoint = Vector2.new(1, 0)
	cash.Position = UDim2.new(1, -58, 0, 0)
	cash.Size = UDim2.fromOffset(150, K.SHOP_TOP)
	cash.TextXAlignment = Enum.TextXAlignment.Right
	cash.TextColor3 = C.Cash
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -4, 0, 2)
	close.Size = UDim2.fromOffset(Theme.Touch, Theme.Touch)
	close.Text = "X"
	Theme.Button(close, "Quiet")
	close.FontFace = Theme.Font.Display
	close.TextSize = 18
	close.Parent = panel
	close.Activated:Connect(function()
		closeShop()
	end)

	local rows = {}
	-- One row: the name and a small line under it on the left, bars in the middle, the BUY button on the right.
	local function addRow(index, id, name, sub, price, g)
		local row = Instance.new("Frame")
		row.Name = id
		row.Position = UDim2.fromOffset(8, K.SHOP_TOP + (index - 1) * (K.SHOP_ROW + 4))
		row.Size = UDim2.new(1, -16, 0, K.SHOP_ROW)
		row.BackgroundColor3 = C.PanelLight
		row.BackgroundTransparency = 0.45
		row.BorderSizePixel = 0
		Theme.Corners(row)
		row.Parent = panel
		local nameLabel = label(row, "Name", 18, "Display", string.upper(name))
		nameLabel.Position = UDim2.fromOffset(10, 6)
		nameLabel.Size = UDim2.fromOffset(150, 22)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		local subLabel = label(row, "Sub", 11, "Body", sub)
		subLabel.Position = UDim2.fromOffset(10, 30)
		subLabel.Size = UDim2.fromOffset(150, 16)
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.TextColor3 = C.Dim
		local b = Instance.new("TextButton")
		b.Name = "Buy"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -6, 0.5, 0)
		b.Size = UDim2.fromOffset(100, K.SHOP_ROW - 8) -- 48 px: a full touch target even on a short phone
		b.TextSize = 17
		b.Text = ""
		b.Parent = row
		local rec = { id = id, gun = g, price = price, button = b, kind = "off" }
		b.Activated:Connect(function()
			if rec.kind ~= "off" then
				buy(id)
			end
		end)
		rows[index] = rec
		return row, rec
	end
	local function statBar(row, line, tag, value, color)
		local y = 9 + (line - 1) * 15
		local tagLabel = label(row, "Tag" .. line, 10, "Body", tag)
		tagLabel.Position = UDim2.fromOffset(168, y - 4)
		tagLabel.Size = UDim2.fromOffset(40, 12)
		tagLabel.TextXAlignment = Enum.TextXAlignment.Left
		tagLabel.TextColor3 = C.Dim
		local bar, fill = Theme.Bar(row, color)
		bar.Position = UDim2.fromOffset(210, y)
		bar.Size = UDim2.fromOffset(92, 5)
		fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
		return fill
	end
	for i, g in ipairs(guns) do
		local sub = string.upper(g.Class or "GUN") .. (g.Auto and " · AUTO" or "") .. " · MAG " .. tostring(g.Mag)
		local row = addRow(i, g.Id, g.Name, sub, g.Price or 0, g)
		local damage, rate, range = Combat.Stats(g)
		statBar(row, 1, "DMG", damage, C.Text)
		statBar(row, 2, "RATE", rate, C.Text)
		statBar(row, 3, "RANGE", range, C.Text)
	end
	local armorRow, armorRec = addRow(#guns + 1, K.ARMOR_ITEM.Id or "Armor", K.ARMOR_ITEM.Name or "Body Armor", "TAKES THE HITS FIRST",
		K.ARMOR_ITEM.Price or 1500, nil)
	armorRec.fill = statBar(armorRow, 2, "ARMOR", 0, C.Armor)

	-- The bottom line: what you just bought and how to get at it. (A stamp would sit behind this panel.)
	local note = label(panel, "Note", 13, "Bold", "")
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, 14, 1, -4)
	note.Size = UDim2.new(1, -28, 0, K.SHOP_NOTE - 8)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextTruncate = Enum.TextTruncate.AtEnd
	shop.note = note

	shop.gui, shop.panel, shop.scale, shop.cash, shop.close = sg, panel, scale, cash, close
	shop.rows, shop.height = rows, height
end

-- Too far from the counter, sitting, down, not a citizen any more, or the phone came out: it closes.
local function watchShop()
	if not shop.open then
		return
	end
	local char, hum, root = myBody()
	if not char or hum.SeatPart or downNow() or player:GetAttribute("Side") ~= "Civilian" or controllerOpen("PhoneUI")
		or (root.Position - shop.at).Magnitude > (K.SHOP.BuyRange or 14) + 1 then
		closeShop()
	end
end

closeShop = function()
	if not shop.open then
		return
	end
	shop.open = false
	shop.gui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(shop.gui) then
		GuiService.SelectedObject = nil
	end
	updateBackpack()
	refreshTouch()
end

-- The counter's "Browse" prompt was triggered.
local function openShop(prompt)
	if shop.open then
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" then
		NotifyController.Show(NotifyController.Messages.GunShopCivOnly or "Coast Arms only sells to free-roam players.", nil, "info")
		return
	end
	local char, hum, root = myBody()
	if not char or hum.SeatPart or downNow() then
		return
	end
	if not shop.gui then
		buildShop()
	end
	local spot = prompt and prompt.Parent
	if spot and spot:IsA("BasePart") then
		shop.at = spot.Position
	elseif spot and spot:IsA("Attachment") then
		shop.at = spot.WorldPosition
	else
		shop.at = root.Position
	end
	-- The phone and the dealer card would sit on top of (or under) it: put them away.
	for _, name in ipairs({ "PhoneUI", "DealerClient" }) do
		local m = other(name)
		if m and type(m.Close) == "function" then
			pcall(m.Close)
		end
	end
	shop.open = true
	shop.note.Text = ""
	fitShop()
	refreshShop()
	shop.gui.Enabled = true
	SoundClient.Play("Click")
	updateBackpack()
	refreshTouch()
	if mode == "gamepad" then
		-- Start on the first thing that can be bought (A buys, B closes).
		local first = shop.close
		for _, row in ipairs(shop.rows) do
			if row.kind ~= "off" then
				first = row.button
				break
			end
		end
		GuiService.SelectedObject = first
	end
end

local function onPromptShown(prompt)
	if prompt.Name == K.SHOP_PROMPT then
		ui.shopPrompt = prompt
		prompt.ActionText = player:GetAttribute("Side") == "Civilian" and "Browse" or "Free roam only"
	elseif prompt.Name == "BagGrab" and player:GetAttribute("Side") == "Cop" then
		prompt.ActionText = "Return to bank" -- (this device only: cops hand dropped cash in)
	end
end

------------------------------------------------------------------ server effects

-- Turn the red bar toward where a hit came from (as the camera sees it) and let it fade.
local function hitFrom(pos)
	local _, _, root = myBody()
	if typeof(pos) ~= "Vector3" or not root or not ui.hitRing then
		return
	end
	local cam = Workspace.CurrentCamera.CFrame
	local rel = flat(pos - root.Position)
	local ahead = flat(cam.LookVector)
	if rel.Magnitude < 0.5 or ahead.Magnitude < 0.05 then
		return
	end
	ui.hitRing.Rotation = math.deg(math.atan2(rel:Dot(cam.RightVector), rel:Dot(ahead.Unit))) -- 0 = ahead, 90 = to the right
	ui.hitBar.BackgroundTransparency = 0.1
	TweenService:Create(ui.hitBar, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
end

-- Knocked out by another player (the server's "KO"), as a short scene of its own: the fall plays at
-- real speed, then the colour drains out of the picture with a slight blur and a low drone, then the
-- words (HUDController's stamp: a big Display line on a dark band). The picture comes back when we are
-- on our feet again (our own KnockedUntil, server time). ImpactClient's lighter grey for every
-- knock-down runs underneath; this only ever adds to it, and both lift as we get up.
local function koScene(title, sub)
	S.koToken += 1
	local token = S.koToken
	task.delay(K.KO_DRAIN_AT, function()
		if S.koToken ~= token then
			return
		end
		local color = S.koColor
		if not color or not color.Parent then
			color = Instance.new("ColorCorrectionEffect")
			color.Name = "NCKnockedOut"
			color.Parent = Lighting -- made on this device: nobody else sees it
			S.koColor = color
		end
		local blur = S.koBlur
		if not blur or not blur.Parent then
			blur = Instance.new("BlurEffect")
			blur.Name = "NCKnockedOutBlur"
			blur.Size = 0
			blur.Parent = Lighting
			S.koBlur = blur
		end
		color.Enabled, blur.Enabled = true, true
		local drain = TweenInfo.new(K.KO_DRAIN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(color, drain, { Saturation = -1, Contrast = 0.15 }):Play()
		TweenService:Create(blur, drain, { Size = K.KO_BLUR }):Play()
		SoundClient.Play("KnockedOut") -- (the drone: silent until Config.Sounds has the key)
	end)
	task.delay(K.KO_STAMP_AT, function()
		if S.koToken == token then
			HUDController.Stamp(title, sub)
		end
	end)
	-- Back up: the picture returns. Looked at a few times a second (the server may stretch a knockout),
	-- and over after 15 s whatever happens.
	task.spawn(function()
		local started = os.clock()
		task.wait(K.KO_STAMP_AT)
		while S.koToken == token and os.clock() - started < 15 do
			local downUntil = player:GetAttribute("KnockedUntil")
			if type(downUntil) ~= "number" or downUntil - now() <= 0.05 then
				break
			end
			task.wait(0.2)
		end
		if S.koToken ~= token then
			return -- a newer knockout has the effects now
		end
		local color, blur = S.koColor, S.koBlur
		local back = TweenInfo.new(0.5)
		if color then
			TweenService:Create(color, back, { Saturation = 0, Contrast = 0 }):Play()
		end
		if blur then
			TweenService:Create(blur, back, { Size = 0 }):Play()
		end
		task.wait(0.55)
		if S.koToken == token then
			if color then
				color.Enabled = false
			end
			if blur then
				blur.Enabled = false
			end
		end
	end)
end

-- "-$250 bag · -$40 wallet" (or nil when nothing was dropped).
local function lossText(info)
	local bag = tonumber(info.Dropped) or 0
	local wallet = tonumber(info.Wallet) or 0
	local parts = {}
	if bag > 0 then
		table.insert(parts, "-" .. money(bag) .. " bag")
	end
	if wallet > 0 then
		table.insert(parts, "-" .. money(wallet) .. " wallet")
	end
	return #parts > 0 and table.concat(parts, " · ") or nil, bag + wallet
end

-- How to get at a gun you just bought, in this device's words.
local function drawHint()
	if mode == "gamepad" then
		return "LB / RB to draw it, R2 to fire"
	elseif mode == "touch" then
		return "Tap WEAPON to draw it"
	end
	return "Number keys to draw it, click to fire"
end

-- CombatFx: ("Hit", info) ("Punch", attacker, victim, pos) ("Shot", shooter, gunId, origin, ends, onBody)
-- ("HitMark", info) ("Reload", shooter, gunId) ("KO", info) ("KOd", info) ("Fled", info) ("Grabbed", info)
-- ("Returned", info) ("Bought", info)
local function onFx(kind, a, b, c, d, e)
	if kind == "Hit" and type(a) == "table" then
		local byGun = a.Kind == "Gun"
		flash(byGun and 0.8 or 0.65)
		hitFrom(a.From)
		if byGun then
			-- A shot stopped by armor is a dull thump; without armor, the same soft thud as a punch.
			local armored = Combat.ArmorOf(player) > 0 or os.clock() - S.armorDropAt < 0.5
			SoundClient.Play(armored and "BodyArmor" or "Punch", nil, armored and 1 or 0.6)
		end
		-- Our own body takes it, on our own screen too.
		local char, _, root = myBody()
		if char and typeof(a.From) == "Vector3" then
			local away = flat(root.Position - a.From)
			local dir = away.Magnitude > 0.1 and away.Unit or nil
			hitReact(char, dir, root.Position + Vector3.new(0, 0.8, 0) - (dir or Vector3.zero) * 0.5)
		end
	elseif kind == "Punch" then
		if typeof(c) == "Vector3" then
			-- c = where the punched player stands. A thud, a small white puff, and their flinch.
			local attacker = typeof(a) == "Instance" and a:IsA("Player") and a or nil
			local victim = typeof(b) == "Instance" and b:IsA("Player") and b or nil
			local from = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
			local dir = from and flat(c - from.Position) or Vector3.zero
			dir = dir.Magnitude > 0.1 and dir.Unit or nil
			local at = c + Vector3.new(0, 1, 0)
			SoundClient.Play("Punch", c)
			impact(at - (dir or Vector3.zero) * 0.6, dir and -dir or Vector3.yAxis, true)
			if victim and victim.Character then
				hitReact(victim.Character, dir, at)
			end
			-- The puncher's arm, when the server keeps no Swing count to show it from (watchOthers).
			if not K.SWING_ATTR and attacker and attacker ~= player and attacker.Character then
				local count = (S.seenSwing[attacker] or 0) + 1
				S.seenSwing[attacker] = count
				throwPunch(attacker.Character, count, at)
			end
		end
	elseif kind == "Shot" then
		local g = Combat.Gun(b)
		if a == player or not g or typeof(c) ~= "Vector3" or type(d) ~= "table" then
			return -- (we drew our own already)
		end
		local first = d[1]
		local camPos = Workspace.CurrentCamera.CFrame.Position
		if typeof(first) ~= "Vector3" or ((c - camPos).Magnitude > K.FX_CULL and (first - camPos).Magnitude > K.FX_CULL) then
			return
		end
		-- From their gun's muzzle if their character is streamed in here, else from the server's origin.
		local shooter = typeof(a) == "Instance" and a:IsA("Player") and a or nil
		local tool = gunToolOf(shooter and shooter.Character)
		local muzzle = muzzleOf(tool)
		local from = muzzleSpot(tool, muzzle) or c
		muzzleFlash(muzzle)
		SoundClient.Play(g.Sound, from, nil, K.SHOT_LIFE)
		for i = 1, math.min(#d, 12) do
			local to = d[i]
			if typeof(to) == "Vector3" then
				tracer(from, to)
				local v = to - c
				local onBody = type(e) == "table" and e[i] == true
				-- A shot that hit nothing ends in the air at the gun's full range: no puff there.
				if v.Magnitude > 0.5 and (onBody or v.Magnitude < g.Range - 0.5) then
					impact(to, -v.Unit, onBody)
				end
				if onBody then
					-- Whoever stands where it landed takes it: a jolt, a hand to the spot.
					local best, bestD
					for _, p in ipairs(Players:GetPlayers()) do
						local r = p ~= shooter and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
						local dist = r and (r.Position - to).Magnitude
						if dist and dist < 5 and (not bestD or dist < bestD) then
							best, bestD = p, dist
						end
					end
					if best then
						local push = flat(v)
						hitReact(best.Character, push.Magnitude > 0.1 and push.Unit or nil, to)
					end
				end
			end
		end
		-- Pedestrians on this device run from anyone's gunfire (only a scare: no wallets, no heat).
		local _, _, root = myBody()
		if root and (c - root.Position).Magnitude < 90 and os.clock() - S.lastScare >= 1 then
			S.lastScare = os.clock()
			PedClient.Scare(c)
		end
	elseif kind == "HitMark" and type(a) == "table" then
		-- Our shot counted: the hit marker (aimStep draws it). No floating numbers: the marker's colour
		-- says what happened.
		local down = a.Down == true
		S.hitUntil = os.clock() + (down and 0.35 or 0.18)
		S.hitColor = down and C.Gold or (a.ArmorOnly == true and C.Armor or nil)
		if typeof(a.Pos) == "Vector3" then
			if a.ArmorOnly == true then
				SoundClient.Play("BodyArmor", a.Pos, 0.8)
			end
			local victim = typeof(a.Victim) == "Instance" and a.Victim:IsA("Player") and a.Victim or nil
			local _, _, root = myBody()
			if victim and victim.Character and root then
				local push = flat(a.Pos - root.Position)
				hitReact(victim.Character, push.Magnitude > 0.1 and push.Unit or nil, a.Pos)
			end
		end
	elseif kind == "Reload" then
		local shooter = typeof(a) == "Instance" and a:IsA("Player") and a or nil
		local r = shooter and shooter ~= player and shooter.Character and shooter.Character:FindFirstChild("HumanoidRootPart")
		if r then
			SoundClient.Play("GunReload", r.Position)
		end
	elseif kind == "KO" and type(a) == "table" then
		local by = "by " .. tostring(a.By or "someone")
		if type(a.Gun) == "string" and a.Gun ~= "" then
			by ..= " · " .. a.Gun
		end
		local loss = lossText(a)
		koScene("KNOCKED OUT", loss and (by .. "\n" .. loss) or (by .. "\nBack up in a moment"))
	elseif kind == "KOd" and type(a) == "table" then
		local name = tostring(a.Name or "They")
		local bounty = math.floor(tonumber(a.Bounty) or 0)
		local _, onGround = lossText(a)
		local sub = name .. (a.Fled and " bailed out" or " is down")
		if onGround > 0 then
			sub ..= " · " .. money(onGround) .. " on the ground"
		end
		if bounty > 0 then
			HUDController.Stamp("+" .. money(bounty) .. (a.BountyKind == "Vigilante" and " VIGILANTE PAY" or " BOUNTY"), sub, C.Cash)
			SoundClient.Play("Cash")
		else
			HUDController.Stamp(a.Fled and "THEY BAILED" or "KNOCKOUT", sub) -- (a reset mid-fight counts)
		end
	elseif kind == "Fled" and type(a) == "table" then
		local loss = lossText(a)
		HUDController.Stamp("YOU BAILED", "You left mid-fight" .. (loss and ("\n" .. loss) or ""))
	elseif kind == "Grabbed" and type(a) == "table" then
		local amount = tonumber(a.Amount) or 0
		local left = tonumber(a.Left) or 0
		local stars = math.floor(tonumber(a.Stars) or 0) -- stars really added (none at the fighting cap)
		local what = a.Kind == "Wallet" and "wallet" or "bag"
		local text
		if a.Stolen then
			text = "You grabbed a " .. what .. ": " .. money(amount) .. "! "
				.. (stars > 0 and ("Stolen cash: +" .. stars .. (stars == 1 and " star." or " stars.")) or "(stolen cash)")
		else
			text = "You got " .. money(amount) .. " of your cash back!"
		end
		if left > 0 then
			text ..= " Bag full: " .. money(left) .. " is still on the ground."
		end
		NotifyController.Show(text, C.Gold, "money")
		SoundClient.Play("Cash")
	elseif kind == "Returned" and type(a) == "table" then
		local reward = tonumber(a.Reward) or 0
		NotifyController.Show(reward > 0 and ("Dropped cash returned to the bank. +" .. money(reward) .. " evidence reward!")
			or "Dropped cash returned to the bank.", C.Cash, "money")
		SoundClient.Play("Cash")
	elseif kind == "Bought" and type(a) == "table" then
		refreshShop()
		local g = Combat.Gun(a.Item)
		local title = string.upper(g and g.Name or K.ARMOR_ITEM.Name or "Body Armor")
		local sub = "Armor full: it takes the hits first"
		if g then
			sub = a.Passive == true and "Turn passive mode off (PHONE > SETTINGS) to use it" or drawHint()
		end
		if shop.open and shop.note then
			-- On the shop panel's own bottom line: a stamp would be drawn behind the panel.
			shop.note.Text = title .. " · " .. sub
			shop.note.TextColor3 = g and C.Cash or C.Armor
			S.noteToken += 1
			local token = S.noteToken
			task.delay(6, function()
				if S.noteToken == token and shop.note then
					shop.note.Text = ""
				end
			end)
		else
			HUDController.Stamp(title, sub, not g and C.Armor or nil)
		end
		SoundClient.Play(g and "Cash" or (K.ARMOR_ITEM.Sound or "BodyArmor"))
	end
end

------------------------------------------------------------------ init

-- The device in hand changed (keyboard, gamepad, touch): different buttons, hints and spots. A held
-- trigger is let go: its release would come from a device we no longer listen to.
local function checkMode()
	local m = readMode()
	if m == mode then
		return
	end
	mode = m
	triggerHeld, holdAim, aimToggle = false, false, false
	S.lookX, S.lookY = 0, 0
	closeWeaponList()
	placeHud()
	refreshVitals()
	updateBackpack() -- (the hotbar goes away on a phone and comes back with a keyboard or gamepad)
	refreshTouch()
end

local function watchCharacter(char)
	for _, c in ipairs(char:GetChildren()) do
		hookTool(c)
	end
	-- Tools move between the Backpack and the character when they are drawn or put away.
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			hookTool(c)
			task.defer(refreshGun)
		end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then
			task.defer(refreshGun)
		end
	end)
	task.defer(refreshGun)
	closeShop()
	closeWeaponList()
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if hum.SeatPart then
				hum:UnequipTools() -- no fighting from a car seat
			end
			updateBackpack()
			refreshTouch()
		end)
	end
	updateBackpack()
	refreshTouch()
end

local function watchPlayer(p)
	p:GetAttributeChangedSignal("Daze"):Connect(updateBars)
	p:GetAttributeChangedSignal("Armor"):Connect(updateBars)
end

-- Four times a second: the things that don't need a frame.
local function slowTick()
	updateBars()
	updateBackpack() -- (also catches the dressing room putting the hotbar back in a car)
	checkMode()
	if mode == "touch" then
		placeHud() -- (Roblox's jump button can turn up after us)
	end
	refreshTouch()
	showVitals()
	watchShop()
	-- While our pose holds the gun, Roblox's own one-arm hold stays switched off.
	if gunOut and S.lowPose and S.lowPose:IsPlaying() and player.Character then
		dropToolHold(player.Character)
	end
	-- A zoom that outlived its gun: the dressing room remembers the camera's FOV when it opens and puts
	-- it back when it closes, so opening it while zoomed would leave the zoom on. Only without
	-- LocomotionClient: it owns the on-foot FOV, eases a leftover back itself, and uses the FOVs between
	-- the zoom and normal for its idle camera.
	local cam = Workspace.CurrentCamera
	if not gunOut and cam and cam.CameraType == Enum.CameraType.Custom and not other("LocomotionClient") then
		local fov = cam.FieldOfView
		if fov >= K.ZOOM_FOV - 0.5 and fov < K.NORMAL_FOV - 0.5 then
			cam.FieldOfView = K.NORMAL_FOV
		end
	end
end

function CombatClient.GunOut()
	return gunOut
end

function CombatClient.IsShopOpen()
	return shop.open
end

-- What the hands can switch to, in hotbar order (Fists first, then the guns in shop order), for
-- WeaponWheel: { Key = "Fists" | a gun id, Name, Class (guns), Ammo (rounds in the magazine, as the
-- readout shows them), Mag (a full one), Reloading, Held (in the hand right now) }.
function CombatClient.Weapons()
	local list, held = combatTools()
	local out = {}
	for _, tool in ipairs(list) do
		local g = Combat.ToolGun(tool)
		local entry = { Key = toolKey(tool), Name = tool.Name, Held = tool == held }
		if g then
			local a = tool:GetAttribute(K.AMMO_ATTR)
			if tool == gunTool then
				a = math.max(ammo, 0) -- (our guess, ahead of the server: the same number as the readout)
			end
			local r = tool:GetAttribute(K.RELOAD_ATTR)
			entry.Name, entry.Class, entry.Mag = g.Name, g.Class, g.Mag
			entry.Ammo = type(a) == "number" and a or g.Mag
			entry.Reloading = type(r) == "number" and r > now()
		elseif entry.Key == "Fists" then
			entry.Name = K.FISTS.Name or tool.Name
		end
		table.insert(out, entry)
	end
	return out
end

-- The key (see Weapons) of the tool in hand, or nil with empty hands.
function CombatClient.Equipped()
	local _, held = combatTools()
	return held and toolKey(held) or nil
end

-- May the tools be switched right now? A citizen or a cop on foot and on their feet, not at home, not
-- picking a side, no panel open (phone, gun shop, dressing room, dealer card, house buy card).
function CombatClient.CanSwitch()
	return hotbarWanted() and not downNow() and not panelOpen()
end

-- Hold the tool with this key (see Weapons); "None" or nil puts everything away. The same equip as the
-- WEAPON button and its list (with the click). True if it was done or already so.
function CombatClient.EquipKey(key)
	if not CombatClient.CanSwitch() then
		return false
	end
	local list, held = combatTools()
	if key == nil or key == "None" then
		if held then
			equip(nil)
		end
		return true
	end
	for _, tool in ipairs(list) do
		if toolKey(tool) == key then
			if tool ~= held then
				equip(tool)
			end
			return true
		end
	end
	return false
end

-- WeaponWheel is up (true) or gone (false). While it is up a held trigger or AIM is let go and nothing
-- fires, swings or zooms, and aimStep leaves the mouse free (as with Left Alt) so the wheel's cursor
-- can point; the gun stays out, so its camera doesn't move. Closing hands the mouse back next frame.
function CombatClient.SetWheelOpen(on)
	S.wheelOpen = on == true
	if S.wheelOpen then
		triggerHeld, holdAim = false, false
		S.queuedAt = nil
	end
end

function CombatClient.Init()
	-- Each remote is fetched in its own thread: one the server hasn't made yet never holds the rest up.
	task.spawn(function()
		S.actionRemote = Remotes.Event("CombatAction")
	end)
	task.spawn(function()
		S.buyRemote = Remotes.Event("GunShopBuy")
	end)
	mode = readMode()
	buildHud()
	placeHud()
	refreshHud()
	S.lastArmor = Combat.ArmorOf(player)
	refreshVitals()
	updateBackpack()
	Remotes.OnClient("CombatFx", onFx)

	for _, name in ipairs({ "InSafeZone", "Passive", "Side" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshHud)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		placeHud()
		fitShop()
	end)
	for _, name in ipairs({ "Side", "InHome" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if player:GetAttribute("InHome") == true then
				putAway() -- the hotbar is hidden at home: nothing else could put a gun away in there
			end
			updateBackpack()
			refreshTouch()
		end)
	end
	for _, name in ipairs({ "KnockedUntil", "StunnedUntil" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			local t = player:GetAttribute(name)
			if type(t) == "number" and t > now() then
				putAway() -- nobody holds a gun while seeing stars
			end
		end)
	end
	-- Health and armor: the strip shows for a few seconds after either changes.
	player:GetAttributeChangedSignal("Daze"):Connect(function()
		S.vitalsUntil = os.clock() + 4
		refreshVitals()
		showVitals()
	end)
	player:GetAttributeChangedSignal("Armor"):Connect(function()
		local armor = Combat.ArmorOf(player)
		if armor < S.lastArmor then
			S.armorDropAt = os.clock() -- (a hit the armor took: onFx picks the armor sound)
		end
		S.lastArmor = armor
		S.vitalsUntil = os.clock() + 4
		refreshVitals()
		showVitals()
		refreshShop()
	end)
	for _, name in ipairs({ "Guns", "Cash", "CivRank" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if shop.open then
				refreshShop()
			end
		end)
	end
	player:GetAttributeChangedSignal("Side"):Connect(function()
		closeShop()
		showVitals()
		local prompt = ui.shopPrompt
		if prompt and prompt.Parent then
			prompt.ActionText = player:GetAttribute("Side") == "Civilian" and "Browse" or "Free roam only"
		end
	end)

	-- Fists arrive in the Backpack (a new one every spawn) and move to the character when held.
	player.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then
			watchContainer(c)
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(backpack)
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(removeBar)

	ProximityPromptService.PromptShown:Connect(onPromptShown)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if prompt == ui.shopPrompt then
			ui.shopPrompt = nil
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == K.SHOP_PROMPT then
			openShop(prompt)
		end
	end)

	-- Gun controls. They only do anything while a gun is out (tryFire, requestReload and the zoom all
	-- check), so on foot with empty hands, in a car or behind a panel these keys are nobody's.
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		local kind = input.UserInputType
		if shop.open then
			if key == Enum.KeyCode.ButtonB or (key == Enum.KeyCode.X and not processed) then
				closeShop()
			end
			return
		end
		if not gunOut or S.wheelOpen then
			return -- (with the weapon wheel up a click or R2 is for picking, not for a shot)
		end
		if kind == Enum.UserInputType.MouseButton1 then
			-- (not with Left Alt held: the cursor is free then, and the click is for the HUD)
			if not processed and mode ~= "touch" and not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
				triggerHeld = true
				tryFire(true)
			end
		elseif key == Enum.KeyCode.ButtonR2 then
			triggerHeld = true
			tryFire(true)
		elseif kind == Enum.UserInputType.MouseButton2 then
			if not processed then
				holdAim = true
			end
		elseif key == Enum.KeyCode.ButtonL2 then
			holdAim = true
		elseif key == Enum.KeyCode.R and not processed then
			requestReload() -- (gamepad X is bound while a gun is out: padReload)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2 then
			if mode ~= "touch" or key == Enum.KeyCode.ButtonR2 then
				triggerHeld = false -- (on touch the FIRE button lets go by itself)
			end
		elseif kind == Enum.UserInputType.MouseButton2 or key == Enum.KeyCode.ButtonL2 then
			holdAim = false
		end
	end)
	-- Alt-tab with the trigger down: the release never arrives.
	UserInputService.WindowFocusReleased:Connect(function()
		triggerHeld, holdAim = false, false
	end)
	UserInputService.LastInputTypeChanged:Connect(checkMode)

	-- After Roblox's camera (and the driving and dressing-room cameras, which run at Camera + 1).
	local lastWarn = 0
	RunService:BindToRenderStep("NC_CombatAim", Enum.RenderPriority.Camera.Value + 3, function(dt)
		local ok, err = pcall(aimStep, dt)
		if not ok then
			if gunOut then
				pcall(exitGunOut) -- never leave the mouse locked or the body turned off behind an error
			end
			if os.clock() - lastWarn > 5 then
				lastWarn = os.clock()
				warn("[CombatClient] " .. tostring(err))
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		updateTracers()
		-- Ten times a second: other players' arms (their aim, their punches).
		local t = os.clock()
		if t - S.othersAt >= 0.1 then
			S.othersAt = t
			local ok, err = pcall(watchOthers)
			if not ok and t - lastWarn > 5 then
				lastWarn = t
				warn("[CombatClient] " .. tostring(err))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(slowTick)
			if not ok then
				warn("[CombatClient] " .. tostring(err))
			end
		end
	end)
end

return CombatClient
