-- LocomotionClient (ModuleScript, StarterPlayerScripts.Controllers.LocomotionClient)
-- How moving on foot FEELS, for your own character only: a sprint with stamina, braking steps, a lean
-- into turns, footsteps, landings and the on-foot camera. Numbers live in Shared.Config.Animations
-- (Locomotion, Sounds). Everything here is local to this device: other players see how fast you go
-- (your device moves your character) but not the lean, the poses or the camera.
-- The layer is ON while you are on foot and on your feet, and OFF while seated, swimming, knocked down
-- or tasered (humanoid state; player attributes KnockedUntil / StunnedUntil, server time), inside a home
-- (InHome), on the title screen (TitleScreen), or while another controller holds it off (Suspend).
-- While it is off the character is plain Roblox: walk speed handed back, no poses, no shoulder camera.
--
-- SPEED (Humanoid.WalkSpeed, written last thing before each physics step)
--   * base      the WalkSpeed the character spawned with (StarterPlayer.CharacterWalkSpeed: 18 in this
--               place; read once per body, before we write anything), or the player attribute "MoveBase"
--               (a number; the server or this device may set it) while that is set. Never a number of
--               ours. The speeds in the config are written for a base of 16 (Locomotion.Run) and scale
--               with the real one: sprint = base x 26 / 16 (about 29 here). Status.Base shows it.
--   * THE RULE  control is instant, and nothing here makes the player slower than the base except being
--               out of breath. The first step is at the full base speed (no start ramp), a landing
--               never slows you, and only the sprint's EXTRA speed eases in and out. (Ceilings other
--               code asks for, below, are theirs.)
--   * braking   letting go of a sprint (above 17 x base / 16) keeps a braking step or two (0.25-0.45 s:
--               Humanoid:Move along the heading you were pushing while the speed falls away; new input,
--               a jump or a ledge ends it at once). An ordinary run still stops where you let go. Only
--               speed your own legs made counts: riding a boat deck or a car roof, or being shoved by a
--               bumper, never starts one.
--   * sprint    hold Left Shift or gamepad B (Config SprintHold), or tap the SPRINT tile on touch (a
--               toggle that lets go when you stop). Roblox's shift lock moves to Left Ctrl / Right Shift.
--   * stamina   100. Sprinting drains 8/s, anything else refills 12/s after 0.4 s. Under 25 the sprint
--               slows; under 12 you hear yourself breathe (a quiet, muffled loop). At 0 you are out of
--               breath for at least 1.5 s: no sprint (a held key must be let go and pressed again) and
--               a winded jog at most (12 x base / 16: still above the 10 studs/s at which a cop may cuff
--               you), with a slight hunch while you keep moving and the full hands-on-knees pose when
--               you stop.
--   * SLOWING THE PLAYER DOWN from other code: do NOT write Humanoid.WalkSpeed. Ask instead:
--       player attribute "MoveBase" = n          a different base while it is set (cuffs, carrying a bag)
--       LocomotionClient.SetCap(source, speed)   a ceiling on this device (aiming = 10); nil lifts it
--     A direct write is still honoured so old code keeps working (the server's taser stun writes 0): a
--     value under the base that someone else wrote stays as a ceiling until someone else writes WalkSpeed
--     again. Lifted = the base or more, the speed the body spawned with or more (what the server's stun
--     puts back, even while MoveBase is higher), or the very value we had when they started.
--     Status.Cap / CapBy show what is holding the speed down ("WalkSpeed" = such a direct write).
-- BODY (Motor6D / AnimationConstraint .Transform, multiplied onto the animation after the Animator each
-- frame in PreSimulation; never replicated; a joint we stop posing gets the animation's own pose back)
--   * lean      rolls into turns (up to 8 degrees, about the feet) and pitches forward with speed (3 at a
--               run, 8 at a sprint), a little more while speeding up (the push-off) and back while braking.
--   * landing   a drop of 5+ studs dips the knees; 10+ is a full 0.25 s squash with a thud and a dip of
--               the camera (never a slow-down); 28+ is a short tumble: Shared.Util.Ragdoll.Start(
--               character, push, { Seconds }) asks the server for loose joints that everyone sees
--               (RagdollService), and Ragdoll.Fall lays the body down on this device at once if Start
--               has not done so itself. Without that module: ImpactClient.KnockLocal, else a plain
--               Physics-state fall.
--   * footsteps the foot that comes down plays a quiet 3D step for the floor under it (concrete, grass,
--               sand, wood, metal, water), timed from the feet themselves so any walk set stays in step.
--               Only while the legs walk: none while a boat or a bumper carries you. Roblox's own
--               looping run sound is muted while the layer is on.
-- CAMERA (on foot with Roblox's own camera only; DriveController, the title screen and the dressing room
-- use a Scriptable camera, which is left alone)
--   * Humanoid.CameraOffset has ONE owner: this file. By default a slight over-the-shoulder offset
--     (Config Camera.Shoulder; less when zoomed in, none in first person, shift lock or against a wall)
--     plus a tiny head bob on each step. Other controllers ask through the request stack:
--       LocomotionClient.RequestCameraOffset(source, offset, priority?, rate?)
--       LocomotionClient.ReleaseCameraOffset(source)      (also LocomotionClient.Release)
--     offset is in VIEW space: X right of the view, Y up, Z back toward the viewer (the same as the
--     root's space whenever the body faces where the camera looks). The highest priority wins (ours is
--     0; default 1); among equals, the one that was asked for last (asking again to change the numbers,
--     even every frame, keeps its place). rate = how fast it eases in, per second (default 8). A request
--     is kept out of walls like our own offset, fades to nothing in first person (in full from 2 studs
--     of zoom) and switches the bob off.
--   * FOV: 70, up to 76 with sprint speed. LocomotionClient.RequestFov(source, fov, priority?, rate?) /
--     ReleaseFov(source) work the same way (a gun zoom, the phone).
--   * Idle camera: 30 s without any input and the view drifts slowly round you while the FOV eases to
--     55; any input stops it and the FOV is back well inside 0.3 s.
--   * Gamepad and touch: 1.2 s after your last camera input the view swings gently back behind the way
--     you push the stick, but only while that is within 75 degrees of the view (a sidestep or a
--     back-pedal leaves it alone).
--   * Anything else that still writes CameraOffset or FieldOfView is never fought: we follow its value
--     and only carry on 0.3 s after its last write.
--   * CombatClient's gun camera (while CombatClient.GunOut() is true) may write them itself or use the
--     stacks, and may switch one without the other; each is judged by itself:
--       CameraOffset  left to it while no request is on the offset stack. When the gun comes out we
--                     hand it our offset re-written for the body it has just turned to face the view
--                     (no jump to the other shoulder); when the gun goes away the offset is ours again
--                     at once, and an old "slide back to zero" of its own is overruled (no swing to the
--                     centre and back out).
--       FieldOfView   ours from the start (S.gunFovStack starts out true): it zooms through the FOV
--                     stack and only asks while aiming, so "no request right now" proves nothing, and
--                     waiting for the first aim left a drawn gun's view stuck at the sprint or idle
--                     FOV. A write of its own would still be followed like anyone else's (0.3 s).
--     Once a stack has been used with a gun out, that one is never left to it again this session.
-- HUD (ScreenGui "Locomotion", flat street look): "Stamina", a 3 px bar just under the Vitals zone, only
-- while stamina isn't full; "Sprint", the touch toggle, beside Roblox's jump button (just left of it,
-- bottoms level: the same spot for every role, under CombatClient's FIRE cluster and outside every Theme
-- zone). If something is in the way there (a very narrow phone) it goes to the side column under the
-- Buttons zone instead (LawClient.SideSlot: the lowest free slot).
-- API (all safe to call before Init):
--   LocomotionClient.SetCap(source, speed?)                     see SPEED
--   LocomotionClient.Suspend(source, on)                        hold the whole layer off (a cutscene, a
--                                                               scripted walk to a car door)
--   LocomotionClient.RequestCameraOffset / ReleaseCameraOffset / Release / RequestFov / ReleaseFov
--   LocomotionClient.Stamina() -> now, max
--   LocomotionClient.UseStamina(amount) -> bool                 spend some (a vault, a punch); false if
--                                                               there isn't that much
--   LocomotionClient.IsActive() / IsSprinting() / IsExhausted() -> bool
--   LocomotionClient.Squash(strength?)                          the landing knee dip, 0..1 (default 1)
--   LocomotionClient.OnStep(fn) -> disconnect                   fn(foot "Left" | "Right", floorKind, speed)
--                                                               on every footstep
--   LocomotionClient.Status   { Active, Sprinting, Exhausted, Stamina, Speed, Base, Cap, CapBy, IdleCam }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local LocomotionClient = {}

local L = Animations.Locomotion
local CAM = L.Camera
local POSE = L.Pose
local SND = Animations.Sounds
local C = Theme.Color

LocomotionClient.Status = {
	Active = false, -- the layer is on right now
	Sprinting = false, -- sprinting and spending stamina
	Exhausted = false, -- out of breath (hands on knees)
	Stamina = L.Stamina,
	Speed = 0, -- studs/s over the ground
	Base = L.Run, -- the plain run speed in use (the body's own starting WalkSpeed, or MoveBase)
	Cap = nil, -- the ceiling on the speed, if something set one...
	CapBy = nil, -- ...and who: a SetCap source, or "WalkSpeed" for a direct write
	IdleCam = false, -- the idle camera is drifting
}
local Status = LocomotionClient.Status

local RAD = math.rad
local TAU = math.pi * 2
local UP = Vector3.yAxis
local ZERO = Vector3.zero
local SPRINT_MULT = L.Sprint / L.Run

local INPUT_STEP = "NC_LocoInput" -- after Roblox's controls, before its camera
local CAMERA_STEP = "NC_LocoCamera" -- after the camera, ImpactClient's shake (+2) and CombatClient's aim (+3)
local YIELD_TIME = 0.3 -- seconds we leave CameraOffset / FOV alone after someone else wrote them
local GUARD = 0.6 -- studs kept between the shoulder camera's pivot and a wall
local STEP_HYST = 0.08 -- studs one foot must be under the other before it counts as the planted one
local STEP_MIN_GAP = 0.16 -- seconds between two footsteps at least
local STICK_DEAD = 0.2
local TILE_W = 52 -- the SPRINT tile, as wide as the side column's other tiles

local STATE = Enum.HumanoidStateType
-- On your feet or in the air under your own control.
local RUN_STATES = {
	[STATE.Running] = true, [STATE.RunningNoPhysics] = true, [STATE.Landed] = true,
	[STATE.Jumping] = true, [STATE.Freefall] = true,
}
local GROUND_STATES = { [STATE.Running] = true, [STATE.RunningNoPhysics] = true, [STATE.Landed] = true }
local AIR_STATES = { [STATE.Jumping] = true, [STATE.Freefall] = true }
-- States in which the layer is off.
local DOWN_STATES = {
	[STATE.Swimming] = true, [STATE.Seated] = true, [STATE.Physics] = true, [STATE.Ragdoll] = true,
	[STATE.FallingDown] = true, [STATE.GettingUp] = true, [STATE.PlatformStanding] = true, [STATE.Dead] = true,
}

local GAMEPAD = {}
for i = 1, 8 do
	GAMEPAD[Enum.UserInputType["Gamepad" .. i]] = true
end
local HOLD, TOGGLE = {}, {}
for _, key in ipairs(L.SprintHold or {}) do
	HOLD[key] = true
end
for _, key in ipairs(L.SprintToggle or {}) do
	TOGGLE[key] = true
end

-- Which joint is in which part (R15). Legacy rigs have Motor6Ds there, upgraded ones AnimationConstraints;
-- both have a Transform that the Animator writes every frame.
local JOINT_PART = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	LeftShoulder = "LeftUpperArm", RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm", RightElbow = "RightLowerArm",
	LeftHip = "LeftUpperLeg", RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg", RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot", RightAnkle = "RightFoot",
}

local body = nil -- the character we are driving: { char, hum, root, joints, conns, ... } (bind)
local controls = nil -- Roblox's control module (the stick / keys as the player pushes them), if we could get it
local started = false
local serial = 0 -- orders requests of equal priority

local camReq = {} -- [source] = { offset, priority, rate, at }
local fovReq = {} -- [source] = { fov, priority, rate, at }
local caps = {} -- [source] = speed
local suspends = {} -- [source] = true
local held = {} -- [KeyCode] = true for the sprint keys that are down
local stepListeners = {} -- OnStep callbacks
local lazy = {} -- [name] = another controller's module (required when first needed), false if missing

local gui, bar, fill, tile

-- Everything that changes from frame to frame, in one table (so the file never runs out of locals).
local S = {
	-- what the server and other controllers say
	inHome = false, title = false, knockedUntil = 0, stunnedUntil = 0, suspended = 0,
	moveBase = nil, -- the player attribute "MoveBase", while it is set
	stock = nil, -- the WalkSpeed this body spawned with (bind): the base when MoveBase isn't set
	-- input
	holdCount = 0, toggle = false, needRelease = false, mode = "keyboard",
	lastInputAt = os.clock(), lastCamInputAt = 0, stick2 = 0,
	rawMove = 0, -- how hard the player pushes a direction this frame (0..1)
	-- on foot (simStep)
	active = false, grounded = false, planar = 0, velX = 0, velZ = 0,
	pace = 0, -- the speed your own legs make: never more than the walk speed in use (not a boat's or a shove's)
	-- speed
	wasMoving = false, sprint = 0, sprinting = false, stillSince = 0,
	moveDir = nil, -- the heading the player last pushed (a level unit vector): braking steps carry on along it
	lastSpeed = nil, -- WalkSpeed as we last left it
	foreign = nil, -- a slow-down someone else wrote straight into WalkSpeed...
	preForeign = nil, -- ...and what WalkSpeed was just before they did
	brakeOn = false, brakeT = 0, brakeDur = 0.3, brakeV0 = 0, brakeDir = ZERO,
	-- stamina
	stamina = L.Stamina, lastDrainAt = 0, exhausted = false, exhaustedUntil = 0, fullAt = 0,
	everSprinted = false, ranFor = 0, tipShown = false,
	-- lean and poses
	lastYaw = nil, yawRate = 0, accel = 0, lastPlanar = 0, pitch = 0, roll = 0,
	squashT = nil, squashAmp = 0, squash = 0, exW = 0, tiredW = 0, breathPhase = 0,
	-- jumps and falls
	inAir = false, airPeak = 0, airFrom = ZERO, airActive = false,
	-- footsteps
	stepSide = 0, stepAt = 0, stepPeriod = 0.35, stepLeft = false, bobAmp = 0, bob = 0,
	-- camera
	camView = ZERO, -- the offset we are at, in view space
	offWrite = nil, offForeignAt = -10,
	gunOut = false, -- CombatClient has a gun out (on foot, our kind of camera)
	gunWas = false, -- ...and it was writing CameraOffset itself last frame (no request on the stack)
	gunEase = false, -- ...and since the gun went away it is still sliding "its" offset back to zero
	-- Seen once, true for the session: with a gun out, a request was made on (or taken off) the offset /
	-- the FOV stack. From then on CombatClient is taken to steer that one through the stack, not by
	-- writing it.
	-- The FOV one starts out true. CombatClient only ever zooms through the FOV stack while this
	-- controller is there, and only asks while aiming: waiting to see that first aim left the FOV with
	-- nobody. Draw a gun mid-sprint (or as the first thing after the idle zoom) and the view stayed stuck
	-- wide (or zoomed in) for as long as the gun was out, until the first aim of the session.
	gunOffStack = false, gunFovStack = true,
	fov = nil, fovWrite = nil, fovCam = nil, fovForeignAt = -10,
	idle = 0, idleStrikes = 0, idleFovOff = false,
	-- sound and HUD
	breathVol = 0, barAlpha = 0, barFrac = -1, barColor = nil, tileLit = nil, tileShown = false, nextSlow = 0,
}

------------------------------------------------------------------ helpers

-- Move cur toward target; tc = seconds to cover about two thirds of the way.
local function approach(cur, target, dt, tc)
	if tc <= 0 then
		return target
	end
	return cur + (target - cur) * (1 - math.exp(-dt / tc))
end

-- The plain run speed everything else is a share of: the player attribute "MoveBase" while it is set,
-- else the WalkSpeed this body spawned with (StarterPlayer.CharacterWalkSpeed; never a number of ours).
local function baseSpeed()
	return S.moveBase or S.stock or L.Run
end

-- a - b, wrapped to -pi..pi.
local function angleDiff(a, b)
	local d = (a - b) % TAU
	if d > math.pi then
		d -= TAU
	end
	return d
end

-- Another controller, required softly the first time it is needed (never at load: no require loops).
local function other(name)
	local m = lazy[name]
	if m == nil then
		m = false
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, res = pcall(require, module)
			if ok and type(res) == "table" then
				m = res
			end
		end
		lazy[name] = m
	end
	return m or nil
end

-- A zone's rectangle on a w x h screen: x, y, width, height in pixels.
local function zoneRect(name, touch, w, h)
	local z = Theme.Zone(name, touch)
	local zw = z.Size.X.Scale * w + z.Size.X.Offset
	local zh = z.Size.Y.Scale * h + z.Size.Y.Offset
	return z.Pos.X.Scale * w + z.Pos.X.Offset - z.Anchor.X * zw, z.Pos.Y.Scale * h + z.Pos.Y.Offset - z.Anchor.Y * zh, zw, zh
end

-- The request that wins: highest priority, the newest among equals.
local function top(list)
	local best = nil
	for _, r in pairs(list) do
		if best == nil or r.priority > best.priority or (r.priority == best.priority and r.at > best.at) then
			best = r
		end
	end
	return best
end

------------------------------------------------------------------ sounds

local emitter -- an invisible anchored part, moved to the foot that steps: the 3D sounds play from it
local stepSets = {} -- [floor kind] = { list = { [variant] = Sound }, last = variant }
local shots = {} -- [key] = Sound (landings)
local breath -- the panting loop (flat, this device only)

local function effectsGroup()
	local settings = other("SettingsClient")
	if settings and type(settings.Group) == "function" then
		local ok, group = pcall(settings.Group, "Effects")
		if ok and typeof(group) == "Instance" then
			return group
		end
	end
	return nil
end

local function newSound(name, id, def, parent)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = def.Volume or 0.3
	s.PlaybackSpeed = def.Pitch or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = SND.MinDistance or 12
	s.RollOffMaxDistance = SND.MaxDistance or 45
	s.SoundGroup = effectsGroup()
	if def.Length then
		-- Only the first part of the asset: one hit, not the whole take.
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(0, def.Length)
	end
	if def.Muffle then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 0
		eq.MidGain = def.Muffle / 3
		eq.HighGain = def.Muffle
		eq.Parent = s
	end
	s.Parent = parent
	return s
end

local function ensureEmitter()
	if emitter and emitter.Parent then
		return emitter
	end
	-- First use, or the camera it lived under was replaced (its sounds went with it).
	table.clear(stepSets)
	table.clear(shots)
	local p = Instance.new("Part")
	p.Name = "NCStepEmitter"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = Workspace.CurrentCamera or Workspace -- made on this device: nobody else has it
	emitter = p
	return p
end

-- Take i of a floor kind's footstep, made the first time it is wanted.
local function stepSound(kind, def, i)
	local part = ensureEmitter()
	local set = stepSets[kind]
	if not set then
		set = { list = {}, last = 0 }
		stepSets[kind] = set
	end
	local s = set.list[i]
	if not s or not s.Parent then
		s = newSound("Step" .. kind .. i, def.Ids[i], def, part)
		set.list[i] = s
	end
	return s, set
end

-- One footstep of this floor kind at a world position. gain scales the config volume.
local function playStep(kind, pos, gain)
	local steps = SND.Footsteps
	local def = steps and (steps[kind] or steps.Hard)
	if not def or type(def.Ids) ~= "table" then
		return
	end
	local n = #def.Ids
	if n == 0 then
		return
	end
	-- A different take than last time whenever there is a choice, so a run doesn't sound like a machine.
	local set = stepSets[kind]
	local i = 1
	if n > 1 then
		i = (math.max(set and set.last or 1, 1) - 1 + math.random(1, n - 1)) % n + 1
	end
	local s
	s, set = stepSound(kind, def, i)
	set.last = i
	emitter.CFrame = CFrame.new(pos)
	s.Volume = (def.Volume or 0.2) * gain
	s.PlaybackSpeed = (def.Pitch or 1) * (1 + (math.random() * 2 - 1) * (def.PitchVar or 0))
	s:Play()
end

-- The pavement steps are made a moment after start, so the very first ones aren't late while they load.
local function warmSounds()
	local steps = SND.Footsteps
	local def = steps and steps.Hard
	if def and type(def.Ids) == "table" then
		for i = 1, #def.Ids do
			stepSound("Hard", def, i)
		end
	end
end

-- A one-off (Sounds.Land / Sounds.BigLand) at a world position.
local function playShot(key, pos)
	local def = SND[key]
	if type(def) ~= "table" or not def.Id then
		return
	end
	local part = ensureEmitter()
	local s = shots[key]
	if not s or not s.Parent then
		s = newSound("NC" .. key, def.Id, def, part)
		shots[key] = s
	end
	part.CFrame = CFrame.new(pos)
	s:Play()
end

-- Panting: fades in under BreathAt stamina, loudest when exhausted, fades out as the breath comes back.
-- It sits under the footsteps on purpose (see Sounds.Breath).
local function breathStep(dt, active)
	local def = SND.Breath
	if type(def) ~= "table" or not def.Id or (def.Volume or 0.12) <= 0 then
		return
	end
	local from = L.BreathAt or L.Tired * 0.5
	local want = 0
	if active and (S.exhausted or S.stamina < from) then
		local short = math.clamp((from - S.stamina) / math.max(1, from), 0, 1)
		want = (def.Volume or 0.12) * math.clamp(0.3 + 0.4 * short + (S.exhausted and 0.3 or 0), 0.3, 1)
	end
	if want <= 0 and S.breathVol <= 0 then
		return
	end
	local v = approach(S.breathVol, want, dt, want > S.breathVol and 0.25 or 0.6)
	if want <= 0 and v < 0.01 then
		v = 0
	end
	S.breathVol = v
	if not breath or not breath.Parent then
		if v <= 0 then
			return
		end
		breath = newSound("NCBreath", def.Id, def, SoundService)
		breath.Looped = true
	end
	breath.Volume = v
	if v > 0 then
		if not breath.IsPlaying then
			breath:Play()
		end
	elseif breath.IsPlaying then
		breath:Stop()
	end
end

-- Roblox's own looping run sound (HumanoidRootPart.Running) is silent while our footsteps play, and
-- gets its volume back while the layer is off (inside a home) so walking is never soundless.
local function tameRunSound(b, active)
	local s = b.runSound
	if not s or not s.Parent then
		s = b.root:FindFirstChild("Running")
		if not (s and s:IsA("Sound")) then
			b.runSound = nil
			return
		end
		b.runSound = s
		b.runVolume = s.Volume
	end
	local want = (active and SND.Footsteps ~= nil) and 0 or b.runVolume
	if s.Volume ~= want then
		s.Volume = want
	end
end

------------------------------------------------------------------ joints

-- The joint record for a name, found when first needed and again if the body is rebuilt (an outfit
-- change swaps parts and their joints). nil while the rig has no such joint (R6, a half-loaded body).
local function joint(b, name)
	local rec = b.joints[name]
	if rec then
		if rec.inst.Parent then
			return rec
		end
		b.joints[name] = nil
	end
	local now = os.clock()
	if (b.jointMiss[name] or 0) > now then
		return nil
	end
	local part = b.char:FindFirstChild(JOINT_PART[name])
	local inst = part and part:FindFirstChild(name)
	if inst and (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint")) then
		rec = { inst = inst, base = inst.Transform, last = nil, on = false }
		b.joints[name] = rec
		return rec
	end
	b.jointMiss[name] = now + 0.5 -- (don't search every frame for something that isn't there)
	return nil
end

-- Pose a joint on top of its animation. pre = our offset comes first (in the joint's resting frame: a
-- whole-body lean); otherwise it is applied in the animated joint's own frame (a bend).
-- The Animator writes Transform every frame it evaluates; on a frame it doesn't (throttled, or nothing
-- plays on that joint) the value is still the one we wrote, and we must not stack onto that.
local function setJoint(b, name, offset, pre)
	local rec = joint(b, name)
	if not rec then
		return
	end
	local inst = rec.inst
	local cur = inst.Transform
	if cur ~= rec.last then
		rec.base = cur
	end
	inst.Transform = pre and (offset * rec.base) or (rec.base * offset)
	rec.last = inst.Transform
	rec.on = true
end

-- Stop posing a joint: if nobody has written it since we did, the animation's own pose goes back.
local function freeJoint(b, name)
	local rec = b.joints[name]
	if rec and rec.on then
		rec.on = false
		local inst = rec.inst
		if inst.Parent and rec.last and inst.Transform == rec.last then
			inst.Transform = rec.base
		end
		rec.last = nil
	end
end

-- Hip to ankle, studs (thigh + shin), measured from the rig's own attachments; looked at again every few
-- seconds because outfits change the legs.
local function legLength(b, now)
	if now - b.legAt < 3 then
		return b.legLen
	end
	b.legAt = now
	local function span(partName, a, c)
		local part = b.char:FindFirstChild(partName)
		local p = part and part:FindFirstChild(a)
		local q = part and part:FindFirstChild(c)
		if p and q and p:IsA("Attachment") and q:IsA("Attachment") then
			return (p.Position - q.Position).Magnitude
		end
		return 0.8
	end
	b.legLen = span("LeftUpperLeg", "LeftHipRigAttachment", "LeftKneeRigAttachment")
		+ span("LeftLowerLeg", "LeftKneeRigAttachment", "LeftAnkleRigAttachment")
	return b.legLen
end

------------------------------------------------------------------ landings

-- A fall too big to land: go limp for a moment. Shared.Util.Ragdoll if it is in the game (loose joints
-- that everyone sees), else the knock-down ImpactClient already has, else a plain Physics-state fall.
local function tumble(b)
	local seconds = L.RagdollTime or 1.6
	local char, hum, root = b.char, b.hum, b.root
	local vel = root.AssemblyLinearVelocity
	-- The way the body pitches over: along the run it landed with, else straight ahead.
	local dir = Vector3.new(vel.X, 0, vel.Z)
	local push = root.CFrame.LookVector * 6
	if dir.Magnitude > 2 then
		push = dir.Magnitude > 30 and dir.Unit * 30 or dir
	end

	local util = lazy.RagdollUtil
	if util == nil then
		util = false
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local folder = shared and shared:FindFirstChild("Util")
		local module = folder and folder:FindFirstChild("Ragdoll")
		if module and module:IsA("ModuleScript") then
			local ok, res = pcall(require, module)
			if ok and type(res) == "table" then
				util = res
			end
		end
		lazy.RagdollUtil = util
	end
	if util and type(util.Start) == "function" then
		-- Ragdoll.Start(character, impulse, { Seconds }) on your own character asks the server for the
		-- loose joints (RagdollService checks it and times it). false = it can't happen (no such service,
		-- not a body it knows): then the older fallbacks below take over.
		local ok, asked = pcall(util.Start, char, push, { Seconds = seconds })
		if ok and asked == true then
			-- The fall itself is this device's. If Start has not laid the body down already, do it now:
			-- waiting for the server's answer would leave it standing for a moment after the thud. The
			-- answer then only renews the timer, and if the server says no (asked too often) this is still
			-- a stiff tip-over that gets up by itself after `seconds`.
			if type(util.Fall) == "function" then
				local okDown, isDown = pcall(function()
					return util.IsDown(char)
				end)
				if not (okDown and isDown == true) then
					pcall(util.Fall, char, seconds, push)
				end
			end
			return
		end
	end

	if dir.Magnitude < 1 then
		dir = root.CFrame.LookVector
	end
	local impact = other("ImpactClient")
	if impact and type(impact.KnockLocal) == "function" then
		local ok, res = pcall(impact.KnockLocal, dir, 30)
		if ok and res then
			return
		end
	end

	-- Nothing else in the game does it: stop balancing, tip forward, get up again.
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	flatDir = flatDir.Magnitude > 0.05 and flatDir.Unit or Vector3.new(0, 0, -1)
	hum:SetStateEnabled(STATE.GettingUp, false)
	hum:ChangeState(STATE.Physics)
	root.AssemblyAngularVelocity = UP:Cross(flatDir) * 5
	task.delay(seconds, function()
		if not hum.Parent then
			return
		end
		-- Knocked over for real meanwhile (a car, a punch)? Then ImpactClient decides when we get up.
		if impact and type(impact.IsKnocked) == "function" then
			local ok, down = pcall(impact.IsKnocked)
			if ok and down then
				return
			end
		end
		hum:SetStateEnabled(STATE.GettingUp, true)
		if hum.Health > 0 and not hum.SeatPart and hum:GetState() == STATE.Physics then
			hum:ChangeState(STATE.GettingUp)
		end
	end)
end

-- Back on the ground after dropping `drop` studs from the top of the jump or fall.
local function landed(b, drop)
	if not S.active or not S.airActive or drop ~= drop then
		return
	end
	local root = b.root
	local pos = root.Position
	local away = Vector3.new(pos.X - S.airFrom.X, 0, pos.Z - S.airFrom.Z).Magnitude
	if away > 400 then
		return -- moved by the server meanwhile (a respawn, a door): not a fall
	end
	local feet = pos - Vector3.new(0, b.hum.HipHeight + root.Size.Y / 2, 0)
	if drop >= L.LandRagdoll then
		playShot("BigLand", feet)
		tumble(b)
	elseif drop >= L.LandSquash then
		-- (the weight of it is in the knees, the thud and the camera dip: the speed is never touched)
		S.squashT, S.squashAmp = 0, 1
		playShot("Land", feet)
	elseif drop >= L.LandLight then
		S.squashT = 0
		S.squashAmp = 0.3 + 0.45 * (drop - L.LandLight) / math.max(0.1, L.LandSquash - L.LandLight)
	end
end

local function onState(b, new)
	if body ~= b then
		return
	end
	if AIR_STATES[new] then
		if not S.inAir then
			S.inAir = true
			S.airFrom = b.root.Position
			S.airPeak = S.airFrom.Y
			S.airActive = S.active
		end
	elseif S.inAir then
		S.inAir = false
		if GROUND_STATES[new] then
			landed(b, S.airPeak - b.root.Position.Y)
		end
	end
end

------------------------------------------------------------------ on or off

local function isActive(b, state)
	local hum = b.hum
	if hum.Health <= 0 or hum.SeatPart ~= nil or hum.PlatformStand or DOWN_STATES[state] then
		return false
	end
	if S.inHome or S.title or S.suspended > 0 then
		return false
	end
	if S.knockedUntil > 0 or S.stunnedUntil > 0 then
		local t = Workspace:GetServerTimeNow()
		if S.knockedUntil > t or S.stunnedUntil > t then
			return false
		end
	end
	return true
end

local function setToggle(on)
	if on and (S.exhausted or not S.active) then
		on = false
	end
	S.toggle = on
	if on then
		S.stillSince = os.clock() -- (a moment to get going before it lets go by itself)
	end
end

------------------------------------------------------------------ speed and stamina

local function speedStep(b, dt, now, active, state)
	local hum = b.hum
	local base = baseSpeed()
	local scale = base / L.Run
	local speed = S.planar

	-- Did someone else write WalkSpeed since we last looked? (See the header: it then acts as a ceiling.)
	local cur = hum.WalkSpeed
	local last = S.lastSpeed
	if last and math.abs(cur - last) > 0.011 then
		if S.foreign == nil then
			S.preForeign = last
		end
		-- Lifted = back to the base or more, back to the speed this body spawned with (the server's own
		-- copy of the humanoid never saw our numbers, so "putting it back" after a taser stun writes
		-- exactly that, even while MoveBase is higher), or back to the very value we had.
		if cur >= math.min(base, S.stock or base) - 0.05
			or (S.preForeign and math.abs(cur - S.preForeign) < 0.001) then
			S.foreign, S.preForeign = nil, nil
		else
			S.foreign = cur
		end
	end
	-- The speed our own legs make: never more than the walk speed we last set. A boat's deck, a car roof
	-- or a shove from a bumper moves the body faster than that, and none of it is running.
	local legs = math.min(speed, last or cur)
	local cap, capBy = math.huge, nil
	for source, v in pairs(caps) do
		if v < cap then
			cap, capBy = v, source
		end
	end
	if S.foreign and S.foreign < cap then
		cap, capBy = S.foreign, "WalkSpeed"
	end
	Status.Cap = cap < math.huge and cap or nil
	Status.CapBy = capBy
	Status.Base = base

	local target = base
	local draining = false
	if active then
		local wantMove = S.rawMove > 0.05
		local grounded = hum.FloorMaterial ~= Enum.Material.Air

		-- Letting go at speed: a braking step or two instead of stopping on the spot. Only speed our own legs made
		-- counts (never a deck's or a shove's), and the steps go the way the player was pushing.
		if S.brakeOn then
			S.brakeT += dt
			if wantMove or not grounded or S.brakeT >= S.brakeDur then
				S.brakeOn = false
			end
		elseif S.wasMoving and not wantMove and grounded and GROUND_STATES[state] and S.moveDir
			and cap > legs and legs > L.BrakeMin * scale then
			local slowest = L.BrakeMin * scale
			local share = math.clamp((legs - slowest) / math.max(1, base * SPRINT_MULT - slowest), 0, 1)
			S.brakeOn, S.brakeT, S.brakeV0 = true, 0, legs
			S.brakeDur = L.BrakeTime[1] + (L.BrakeTime[2] - L.BrakeTime[1]) * share
			S.brakeDir = S.moveDir
		end
		S.wasMoving = wantMove
		if wantMove then
			S.stillSince = now
			-- (read after the brake check: while we brake, the humanoid's direction is the one we gave it)
			local md = hum.MoveDirection
			if md.X * md.X + md.Z * md.Z > 0.01 then
				S.moveDir = Vector3.new(md.X, 0, md.Z).Unit
			end
		end

		-- Sprint: only while you really are on the move, have breath left and nothing holds you slower.
		-- The plain base speed is there from the first frame (no start ramp: control is instant); only
		-- the extra speed of the sprint eases in and out.
		local wantSprint = (S.holdCount > 0 or S.toggle) and not S.needRelease
		local canSprint = wantSprint and wantMove and RUN_STATES[state] == true and not S.exhausted
			and S.stamina > 0 and cap > base * 1.05
		S.sprint = approach(S.sprint, canSprint and 1 or 0, dt, L.SprintEase)
		local wind = 1 -- short of breath: the sprint loses its edge
		if S.stamina < L.Tired then
			wind = L.TiredSprintShare + (1 - L.TiredSprintShare) * S.stamina / L.Tired
		end
		target = base * (1 + (SPRINT_MULT - 1) * S.sprint * wind)
		if S.brakeOn then
			target = S.brakeV0 * (1 - S.brakeT / S.brakeDur) ^ (L.BrakeCurve or 2)
			-- Roblox's controls told the humanoid to stand still this frame; we speak after them.
			hum:Move(S.brakeDir, false)
		end
		-- Out of breath is the ONE thing in this file that may take the player under the base speed.
		if S.exhausted then
			target = math.min(target, (L.ExhaustedSpeed or L.Run) * scale)
		end
		draining = canSprint and legs > base * 1.05
		-- The touch toggle lets go by itself once you have stood still for a moment.
		if S.toggle and now - S.stillSince > 0.6 then
			S.toggle = false
		end
	else
		S.sprint = approach(S.sprint, 0, dt, L.SprintEase)
	end
	target = math.max(0, math.min(target, cap))
	if math.abs(cur - target) > 0.01 then
		hum.WalkSpeed = target
	end
	S.lastSpeed = hum.WalkSpeed -- (read back: the engine stores it less exactly than we compute it)

	-- Stamina.
	if draining then
		S.stamina = math.max(0, S.stamina - L.Drain * dt)
		S.lastDrainAt = now
		S.everSprinted = true
		if S.stamina <= 0 then
			S.exhausted, S.exhaustedUntil = true, now + L.ExhaustTime
			S.toggle = false
			S.needRelease = S.holdCount > 0
		end
	elseif S.stamina < L.Stamina and now - S.lastDrainAt >= L.RefillDelay then
		S.stamina = math.min(L.Stamina, S.stamina + L.Refill * dt)
		if S.stamina >= L.Stamina then
			S.fullAt = now
		end
	end
	if S.exhausted and now >= S.exhaustedUntil and S.stamina >= L.ResprintAt then
		S.exhausted = false
	end
	if S.needRelease and S.holdCount == 0 then
		S.needRelease = false
	end
	S.sprinting = draining
end

------------------------------------------------------------------ lean and poses

local function poseStep(b, dt, now, active, state)
	local hum, root = b.hum, b.root
	local base = baseSpeed()
	local scale = base / L.Run
	local planar = S.pace
	local grounded = active and GROUND_STATES[state] == true

	-- How fast the body turns and speeds up, both smoothed (one frame's jitter must not show).
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local rate = S.lastYaw and angleDiff(yaw, S.lastYaw) / dt or 0
	S.lastYaw = yaw
	S.yawRate = approach(S.yawRate, math.clamp(rate, -12, 12), dt, 0.1)
	S.accel = approach(S.accel, (planar - S.lastPlanar) / dt, dt, 0.12)
	S.lastPlanar = planar

	-- Lean (degrees): forward with speed, into turns with speed x turn rate.
	local wantPitch, wantRoll = 0, 0
	if active and RUN_STATES[state] then
		local forward = math.min(planar, math.max(0, S.velX * look.X + S.velZ * look.Z))
		local walk = 6 * scale
		if forward > base then
			local sprintSpan = math.max(0.1, base * SPRINT_MULT - base)
			wantPitch = L.PitchJog + (L.PitchSprint - L.PitchJog) * math.min(1, (forward - base) / sprintSpan)
		elseif forward > walk then
			wantPitch = L.PitchJog * (forward - walk) / math.max(0.1, base - walk)
		end
		if grounded then
			if S.accel > 0 and forward > 1 then
				wantPitch += L.AccelPitch * math.min(1, S.accel / 40) -- leaning into the push-off
			elseif S.accel < 0 and planar > 2 then
				wantPitch -= L.BrakePitch * math.min(1, -S.accel / 50) -- rocking back on the brakes
			end
			-- (not with a gun out: the body then turns with the camera, which isn't a turn of the feet)
			if hum.AutoRotate then
				wantRoll = math.clamp(L.RollGain * planar * S.yawRate, -L.RollMax, L.RollMax)
			end
		else
			wantPitch *= 0.5
		end
	end
	S.pitch = approach(S.pitch, wantPitch, dt, 0.14)
	S.roll = approach(S.roll, wantRoll, dt, 0.16)

	-- Landing squash: down fast, back up slower.
	local squash = 0
	if S.squashT then
		S.squashT += dt
		local u = S.squashT / math.max(0.05, L.SquashTime)
		if u >= 1 or not active then
			S.squashT = nil
		else
			local e = u < 0.3 and u / 0.3 or 1 - (u - 0.3) / 0.7
			squash = e * e * (3 - 2 * e) * S.squashAmp
		end
	end
	S.squash = squash

	-- Out of breath: the full hands-on-knees pose once you stop, only a slight hunch while you jog on.
	-- ("Stopped" is judged against a walking pace, not against the winded jog's own speed.)
	local still = 1 - math.min(1, planar / math.max(1, 6 * scale))
	S.exW = approach(S.exW, (active and S.exhausted) and 1 or 0, dt, S.exhausted and 0.12 or 0.25)
	local short = 0
	if active and not S.sprinting and planar < 3 and S.stamina < L.Tired then
		short = (L.Tired - S.stamina) / L.Tired
	end
	S.tiredW = approach(S.tiredW, short, dt, 0.3)
	local poseW = S.exW * (0.3 + 0.7 * still)
	if poseW < 0.003 then
		poseW = 0
	end
	local tiredW = S.tiredW < 0.003 and 0 or S.tiredW
	local heave = 0
	local breathe = math.max(poseW, tiredW * 0.6)
	if breathe > 0 then
		S.breathPhase = (S.breathPhase + dt * POSE.HeaveRate * TAU) % TAU
		heave = math.sin(S.breathPhase) * POSE.Heave * breathe
	end

	-- Legs: hip forward, knee back twice as far, ankle forward again keeps the foot flat under the hip;
	-- the body comes down by what the bent leg lost in height.
	local knee = RAD(POSE.SquashKnee) * squash + RAD(POSE.Knee) * poseW
	local hipTilt = RAD(POSE.Hip) * poseW
	local drop = 0
	if knee > 0.002 then
		drop = legLength(b, now) * (1 - math.cos(knee))
		local hipCF = CFrame.Angles(knee + hipTilt, 0, 0)
		local kneeCF = CFrame.Angles(-2 * knee, 0, 0)
		local ankleCF = CFrame.Angles(knee, 0, 0)
		setJoint(b, "LeftHip", hipCF, false)
		setJoint(b, "RightHip", hipCF, false)
		setJoint(b, "LeftKnee", kneeCF, false)
		setJoint(b, "RightKnee", kneeCF, false)
		setJoint(b, "LeftAnkle", ankleCF, false)
		setJoint(b, "RightAnkle", ankleCF, false)
	else
		freeJoint(b, "LeftHip")
		freeJoint(b, "RightHip")
		freeJoint(b, "LeftKnee")
		freeJoint(b, "RightKnee")
		freeJoint(b, "LeftAnkle")
		freeJoint(b, "RightAnkle")
	end

	-- The whole body from the root: the lean turns about the feet (so they stay put), then the drop and
	-- the hips tipping forward. (X: a negative angle tips the top forward. Z: positive tips it left.)
	local pitch, roll = RAD(S.pitch), RAD(S.roll)
	if math.abs(pitch) > 0.0009 or math.abs(roll) > 0.0009 or drop > 0.001 or hipTilt > 0.001 then
		-- (turning about a point `legs` below the joint = turn, then shift by turn x legs - legs)
		local legs = Vector3.new(0, hum.HipHeight, 0)
		local turn = CFrame.Angles(-pitch, 0, roll)
		local cf = turn + (turn:VectorToWorldSpace(legs) - legs)
		if drop > 0.001 or hipTilt > 0.001 then
			cf = cf * CFrame.new(0, -drop, 0) * CFrame.Angles(-hipTilt, 0, 0)
		end
		setJoint(b, "Root", cf, true)
	else
		freeJoint(b, "Root")
	end

	-- Chest and head.
	local waist = -(POSE.Waist * poseW + POSE.SquashWaist * squash + POSE.Slump * tiredW * (1 - poseW)) + heave
	if math.abs(waist) > 0.05 then
		setJoint(b, "Waist", CFrame.Angles(RAD(waist), 0, 0), false)
		setJoint(b, "Neck", CFrame.Angles(RAD(POSE.Neck * poseW - heave * 0.5), 0, 0), false)
	else
		freeJoint(b, "Waist")
		freeJoint(b, "Neck")
	end

	-- Arms: forward to the thighs and in toward the knees.
	if poseW > 0 then
		local reach, inward = RAD(POSE.Shoulder * poseW), RAD(POSE.ShoulderIn * poseW)
		local elbow = CFrame.Angles(RAD(POSE.Elbow * poseW), 0, 0)
		setJoint(b, "LeftShoulder", CFrame.Angles(reach, 0, inward), false)
		setJoint(b, "RightShoulder", CFrame.Angles(reach, 0, -inward), false)
		setJoint(b, "LeftElbow", elbow, false)
		setJoint(b, "RightElbow", elbow, false)
	else
		freeJoint(b, "LeftShoulder")
		freeJoint(b, "RightShoulder")
		freeJoint(b, "LeftElbow")
		freeJoint(b, "RightElbow")
	end
end

------------------------------------------------------------------ footsteps

local function footParts(b, now)
	local left, right = b.leftFoot, b.rightFoot
	if left and left.Parent and right and right.Parent then
		return left, right
	end
	b.leftFoot, b.rightFoot = nil, nil
	if now < b.feetMiss then
		return nil, nil
	end
	left, right = b.char:FindFirstChild("LeftFoot"), b.char:FindFirstChild("RightFoot")
	if left and right and left:IsA("BasePart") and right:IsA("BasePart") then
		b.leftFoot, b.rightFoot = left, right
		return left, right
	end
	b.feetMiss = now + 0.5
	return nil, nil
end

local function doStep(b, foot, isLeft, now, speed, base)
	S.stepPeriod = math.clamp(now - S.stepAt, 0.2, 0.6)
	S.stepAt = now
	local run = math.max(1, base)
	local frac = speed / run -- 1 = running pace
	local fast = math.clamp((speed - run) / math.max(0.1, run * (SPRINT_MULT - 1)), 0, 1)
	-- The head bob this step gives the camera (inputStep plays it out).
	if frac < 1 then
		S.bobAmp = CAM.BobWalk + (CAM.BobJog - CAM.BobWalk) * math.clamp((frac - 0.5) / 0.5, 0, 1)
	else
		S.bobAmp = CAM.BobJog + (CAM.BobSprint - CAM.BobJog) * fast
	end
	local kind = (SND.FloorKind and SND.FloorKind[b.hum.FloorMaterial]) or "Hard"
	local pos
	if foot then
		pos = foot.Position - Vector3.new(0, foot.Size.Y / 2, 0)
	else
		pos = b.root.Position - Vector3.new(0, b.hum.HipHeight + b.root.Size.Y / 2, 0)
	end
	playStep(kind, pos, frac < 0.7 and 0.6 or 1 + 0.25 * fast)
	for _, fn in ipairs(stepListeners) do
		pcall(fn, isLeft and "Left" or "Right", kind, speed)
	end
end

-- A step = the moment the other foot becomes the lower one (it has just come down). Timed straight
-- from the animated feet, so it fits every walk set at every speed. If the feet can't be read (an odd
-- rig, an animation that never loaded) steps fall back to a plain rhythm by speed.
local function stepStep(b, now, active, state)
	-- Only while the legs really walk: carried along on a boat deck or nudged by a bumper, the body moves
	-- but the feet don't (rawMove also counts scripted walks; the braking steps are ours).
	if not active or not GROUND_STATES[state] or S.pace < 1.5 or (S.rawMove <= 0.05 and not S.brakeOn) then
		S.stepSide = 0
		return
	end
	local base = baseSpeed()
	local speed = S.pace
	local left, right = footParts(b, now)
	if left then
		local cf = b.root.CFrame
		local d = cf:PointToObjectSpace(left.Position).Y - cf:PointToObjectSpace(right.Position).Y
		local side = 0
		if d < -STEP_HYST then
			side = 1 -- the left foot is down
		elseif d > STEP_HYST then
			side = -1
		end
		if side ~= 0 and side ~= S.stepSide then
			local first = S.stepSide == 0
			S.stepSide = side
			if not first and now - S.stepAt >= STEP_MIN_GAP then
				doStep(b, side == 1 and left or right, side == 1, now, speed, base)
				return
			end
		end
	end
	local every = 1 / (1.6 + 0.08 * speed * L.Run / math.max(1, base))
	if now - S.stepAt > every * 1.8 then
		S.stepLeft = not S.stepLeft
		doStep(b, S.stepLeft and left or right, S.stepLeft, now, speed, base)
	end
end

------------------------------------------------------------------ HUD

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "Locomotion"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 2 -- under CombatClient's HUD (3), the mission intro (4) and the phone (5)
	gui.Parent = player:WaitForChild("PlayerGui")

	bar, fill = Theme.Bar(gui, C.Text)
	bar.Name = "Stamina"
	bar.Visible = false

	-- Touch only. Never selectable: gamepads hold B.
	tile = Instance.new("TextButton")
	tile.Name = "Sprint"
	tile.Text = "SPRINT"
	Theme.Button(tile, "Quiet")
	tile.FontFace = Theme.Font.Display
	tile.TextSize = 13
	tile.Size = UDim2.fromOffset(TILE_W, Theme.Touch)
	tile.Selectable = false
	tile.Visible = false
	Theme.Shadow(tile)
	tile.Parent = gui
	tile.Activated:Connect(function()
		S.lastInputAt = os.clock()
		setToggle(not S.toggle)
	end)
end

-- The stamina bar: 3 px, as wide as the Vitals zone and 2 px under it (CombatClient draws health and
-- armour inside that zone; nothing else uses the strip below it).
local function layout()
	if not gui then
		return
	end
	local z = Theme.Zone("Vitals", Theme.IsTouch())
	local width = z.Size.X.Offset
	bar.AnchorPoint = Vector2.new(0, 0)
	bar.Position = UDim2.new(z.Pos.X.Scale, z.Pos.X.Offset - z.Anchor.X * width,
		z.Pos.Y.Scale, z.Pos.Y.Offset + (1 - z.Anchor.Y) * z.Size.Y.Offset + 2)
	bar.Size = UDim2.fromOffset(width, 3)
	S.nextSlow = 0 -- (the tile is placed again on the next slow tick)
end

-- Roblox's touch jump button in our ScreenGui's pixels: left, top, width, height. The real one when it
-- has been laid out; else where Roblox puts it (70 px on phones, 120 px on tablets: the same rule
-- CombatClient and LawClient use), so the tile doesn't hop when the button comes and goes.
local function jumpRect(w, h, origin)
	local touchGui = gui.Parent:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 10 then
		local p, s = jump.AbsolutePosition - origin, jump.AbsoluteSize
		return p.X, p.Y, s.X, s.Y
	end
	local small = math.min(w, h) <= 500
	local side = small and 70 or 120
	return w - (side * 1.5 - 10), h - (small and (side + 20) or side * 1.75), side, side
end

-- The SPRINT tile's spot (phones and tablets). Its home is beside Roblox's jump button: just left of
-- it, bottoms level, where the right thumb already rests and where every role finds it in the same
-- place. That spot is under CombatClient's FIRE / AIM cluster (which ends above the jump button), right
-- of the Corner zone and well below Action; it is still checked against those zones and against every
-- button other controllers show, and given up if something is there (a very narrow screen).
-- Then: the side column under the Buttons zone, where the other situational tiles live
-- (LawClient.SideSlot knows about the jump button, the pedals and the seated hint). There we take the
-- LOWEST free slot, the one nearest the right thumb, and step aside for any tile another controller
-- shows (LEAVE HOME, WARDROBE, TASER, SPIKES...), measured, so their slot numbers don't matter. No free
-- slot in the column: the first free one of its overflow row.
local function placeTile()
	local size = gui.AbsoluteSize
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then
		return false
	end
	local origin = gui.AbsolutePosition
	-- Visible buttons other controllers parent straight to their ScreenGui: the column's other tiles.
	-- (Not the big ones: a panel's backdrop is not a tile.)
	local blockers = {}
	for _, sg in ipairs(gui.Parent:GetChildren()) do
		if sg ~= gui and sg:IsA("ScreenGui") and sg.Enabled then
			for _, o in ipairs(sg:GetChildren()) do
				if o:IsA("GuiButton") and o.Visible then
					local s = o.AbsoluteSize
					if s.X < w * 0.5 or s.Y < h * 0.5 then
						table.insert(blockers, o)
					end
				end
			end
		end
	end
	local function free(pos, sz)
		for _, o in ipairs(blockers) do
			local p, s = o.AbsolutePosition - origin, o.AbsoluteSize
			if pos.X < p.X + s.X and pos.X + sz.X > p.X and pos.Y < p.Y + s.Y and pos.Y + sz.Y > p.Y then
				return false
			end
		end
		return true
	end
	-- Home: beside the jump button.
	local jx, jy, _, jh = jumpRect(w, h, origin)
	local home = Vector2.new(math.floor(jx) - 8 - TILE_W, math.floor(jy + jh) - Theme.Touch)
	local homeSize = Vector2.new(TILE_W, Theme.Touch)
	local clear = home.X >= 0 and home.Y >= 0 and free(home, homeSize)
	if clear then
		for _, name in ipairs({ "Corner", "Action", "Subtitle" }) do
			local zx, zy, zw, zh = zoneRect(name, true, w, h)
			if home.X < zx + zw and home.X + homeSize.X > zx and home.Y < zy + zh and home.Y + homeSize.Y > zy then
				clear = false
				break
			end
		end
	end
	if clear then
		tile.Position = UDim2.fromOffset(home.X, home.Y)
		tile.Size = UDim2.fromOffset(homeSize.X, homeSize.Y)
		return true
	end
	-- Otherwise: the side column.
	local bx, by, bw, bh = zoneRect("Buttons", true, w, h)
	local right, under = bx + bw, by + bh
	local law = other("LawClient")
	local slot = law and law.SideSlot
	local best, bestSize, spare, spareSize
	for index = 0, 7 do
		local pos, sz
		if type(slot) == "function" then
			local ok, p, s = pcall(slot, gui, index, true)
			if ok and typeof(p) == "Vector2" and typeof(s) == "Vector2" then
				pos, sz = p, s
			end
		end
		if not pos then
			-- No LawClient: our own column at the right edge, down to where Roblox's jump button starts.
			sz = Vector2.new(TILE_W, Theme.Touch)
			pos = Vector2.new(right - TILE_W, under + 8 + index * (Theme.Touch + 6))
			if pos.Y + sz.Y > h - (math.min(w, h) <= 500 and 96 or 216) then
				break
			end
		end
		if free(pos, sz) then
			if math.abs(pos.X + sz.X - right) < 1 and pos.Y >= under then
				if not best or pos.Y > best.Y then
					best, bestSize = pos, sz
				end
			elseif not spare then
				spare, spareSize = pos, sz
			end
		end
	end
	local pos, sz = best or spare, bestSize or spareSize
	if not pos then
		return false
	end
	tile.Position = UDim2.fromOffset(pos.X, pos.Y)
	tile.Size = UDim2.fromOffset(sz.X, sz.Y)
	return true
end

local function tileStep(active)
	if not tile then
		return
	end
	local show = active and Theme.IsTouch() and placeTile()
	if show ~= S.tileShown then
		S.tileShown = show
		tile.Visible = show
	end
end

-- Lit while the toggle is on (like CombatClient's AIM).
local function tileLook()
	if not tile or S.tileLit == S.toggle then
		return
	end
	S.tileLit = S.toggle
	tile.BackgroundColor3 = S.toggle and C.Text or C.Panel
	tile.BackgroundTransparency = S.toggle and 0.1 or 0.35
	tile.TextColor3 = S.toggle and C.Panel or C.Text
end

-- The bar fades in while stamina isn't full and out a moment after it is.
local function barStep(dt, now)
	if not bar then
		return
	end
	local frac = math.clamp(S.stamina / L.Stamina, 0, 1)
	local show = frac < 0.995 or now - S.fullAt < 0.6
	if not show and S.barAlpha <= 0 then
		return
	end
	local alpha = approach(S.barAlpha, show and 1 or 0, dt, show and 0.08 or 0.25)
	if not show and alpha < 0.02 then
		alpha = 0
	end
	S.barAlpha = alpha
	bar.Visible = alpha > 0
	bar.BackgroundTransparency = 1 - 0.65 * alpha
	fill.BackgroundTransparency = 1 - alpha
	if math.abs(frac - S.barFrac) > 0.002 then
		S.barFrac = frac
		fill.Size = UDim2.fromScale(frac, 1)
	end
	local color = (S.exhausted and C.Danger) or (S.stamina < L.Tired and C.Orange) or C.Text
	if color ~= S.barColor then
		S.barColor = color
		fill.BackgroundColor3 = color
	end
end

------------------------------------------------------------------ every physics step

-- Twice a second: the things that don't need a frame.
local function slowTick(b, active)
	tameRunSound(b, active)
	tileStep(active)
	-- One tip, once: someone who has run a while and never sprinted is told how.
	if not S.tipShown and type(L.Tip) == "table" and not S.everSprinted then
		if active and S.rawMove > 0.5 and S.pace > baseSpeed() * 0.8 then
			S.ranFor += 0.5
		end
		if S.ranFor >= (L.TipAfter or 6) then
			S.tipShown = true
			local text = L.Tip[S.mode]
			local notify = other("NotifyController")
			if type(text) == "string" and notify and type(notify.Show) == "function" then
				pcall(notify.Show, text, nil, "info")
			end
		end
	end
end

local function onActiveChanged(b, active)
	if not active then
		S.brakeOn, S.wasMoving = false, false
		S.toggle = false
		S.squashT = nil
	end
	tameRunSound(b, active)
	S.nextSlow = 0
end

-- PreSimulation: after the Animator has posed the body, right before the physics moves it.
local function simStep(dt)
	local b = body
	if not b then
		return
	end
	local hum, root = b.hum, b.root
	if not hum.Parent or not root.Parent then
		return
	end
	dt = math.clamp(dt, 1 / 240, 0.1)
	local now = os.clock()
	local state = hum:GetState()
	local active = isActive(b, state)
	local vel = root.AssemblyLinearVelocity
	S.velX, S.velZ = vel.X, vel.Z
	S.planar = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	S.grounded = GROUND_STATES[state] == true
	if S.inAir then
		local y = root.Position.Y
		if y > S.airPeak then
			S.airPeak = y
		end
	end
	if active ~= S.active then
		S.active = active
		onActiveChanged(b, active)
	end

	speedStep(b, dt, now, active, state)
	-- What the legs are doing, for everything that shows it (lean, steps, bob, FOV): standing on a moving
	-- boat or being shoved by a car is speed over the ground, but not running.
	S.pace = math.min(S.planar, hum.WalkSpeed * math.min(1, hum.MoveDirection.Magnitude) + 2)
	poseStep(b, dt, now, active, state)
	stepStep(b, now, active, state)
	breathStep(dt, active)
	barStep(dt, now)
	tileLook()

	Status.Active = active
	Status.Sprinting = S.sprinting
	Status.Exhausted = S.exhausted
	Status.Stamina = S.stamina
	Status.Speed = S.planar

	if now >= S.nextSlow then
		S.nextSlow = now + 0.5
		slowTick(b, active)
	end
end

------------------------------------------------------------------ camera

-- Is CombatClient's gun camera on? It may write CameraOffset and the FOV itself, or ask for them through
-- the request stack, or one of each (see the header): inputStep and cameraStep work out which.
local function gunOut()
	local combat = other("CombatClient")
	local fn = combat and combat.GunOut
	if type(fn) ~= "function" then
		return false
	end
	local ok, out = pcall(fn)
	return ok and out == true
end

local function onFootCamera(cam, hum)
	return cam.CameraType == Enum.CameraType.Custom and cam.CameraSubject == hum and hum.SeatPart == nil
		and hum.Health > 0 and not S.title
end

-- Render step, after Roblox's controls and before its camera: what the player is pushing, and the
-- camera offset the camera is about to read.
local function inputStep(dt)
	local b = body
	if not b then
		return
	end
	local hum, root = b.hum, b.root
	if not hum.Parent or not root.Parent then
		return
	end
	dt = math.clamp(dt, 1 / 240, 0.1)
	local now = os.clock()

	-- The stick or keys right now. Roblox's control module knows exactly; the humanoid's own direction
	-- adds click-to-move and scripted walks (but while we brake, that direction is ours, not the player's).
	local push = 0
	local c = controls
	if c then
		local ok, v = pcall(c.GetMoveVector, c)
		if ok and typeof(v) == "Vector3" then
			push = math.min(1, v.Magnitude)
		else
			controls = nil
		end
	end
	if not controls or not S.brakeOn then
		push = math.max(push, math.min(1, hum.MoveDirection.Magnitude))
	end
	S.rawMove = push

	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local onFoot = onFootCamera(cam, hum)
	local req = onFoot and top(camReq) or nil
	-- A gun is out. The offset is left to CombatClient only while it writes CameraOffset itself: not
	-- while a request is on the stack, and never again once it has used the stack with a gun out.
	local armed = onFoot and gunOut()
	S.gunOut = armed
	local gun = armed and req == nil and not S.gunOffStack
	local camCF = cam.CFrame
	local right = camCF.RightVector
	local back = right:Cross(UP) -- (the camera never rolls, so its right vector is level and this is a unit)
	local rootCF = root.CFrame

	-- Someone else moved the offset: follow them, and carry on from there once they have stopped.
	local cur = hum.CameraOffset
	local wrote = S.offWrite
	local was = S.gunWas
	S.gunWas = gun
	if gun and not was then
		-- The gun came out after our last write, and CombatClient has turned the body to face the view
		-- since. What we left is in the body's OLD frame: read in the new one it points somewhere else
		-- (the view would jump to the other shoulder for a frame). Hand over the same picture instead:
		-- our view-space offset, written in the body's frame as it is now. Its ease starts from there.
		local v = S.camView
		hum.CameraOffset = rootCF:VectorToObjectSpace(right * v.X + UP * v.Y + back * v.Z)
		cur = hum.CameraOffset
	elseif was and not gun then
		-- The gun went away: the offset is ours again at once (no waiting out the yield), eased from
		-- where the gun camera had it straight to where we want it.
		S.offForeignAt = -10
		S.gunEase = true
	elseif wrote and (cur - wrote).Magnitude > 0.001 then
		-- An older CombatClient slides "its" offset back to zero after the gun went away: every frame it
		-- takes what is there and shrinks it. Following that would swing the view to the centre and back
		-- out again, so a pure shrink of what we wrote is overruled for as long as it keeps coming
		-- (it runs after the camera, we write before it: its value is never on screen).
		local shrink = false
		if S.gunEase then
			local a, c = wrote.Magnitude, cur.Magnitude
			shrink = c < a and cur:Dot(wrote) >= 0.999 * a * c
		end
		if not shrink then
			S.gunEase = false
			S.offForeignAt = now
		end
	else
		S.gunEase = false -- (nobody wrote: that slide is over, or there never was one)
	end
	if gun then
		S.offForeignAt = now
	end
	if now - S.offForeignAt < YIELD_TIME then
		local world = rootCF:VectorToWorldSpace(cur)
		S.camView = Vector3.new(world:Dot(right), world.Y, world:Dot(back))
		S.offWrite = cur
		S.bob = 0
		return
	end

	-- Where the offset should be, in view space.
	local zoom = (camCF.Position - cam.Focus.Position).Magnitude
	local third = math.clamp((zoom - 1.5) / 3, 0, 1) -- 0 in first person, 1 from 4.5 studs out
	local want, rate = ZERO, CAM.ShoulderEase
	if req then
		-- (in full from 2 studs out, none in first person: there an offset would move the eye off the
		-- head, and a gun's shots still leave from the head)
		want, rate = req.offset * math.clamp((zoom - 0.6) / 1.4, 0, 1), req.rate
	elseif onFoot and S.active and CAM.Shoulder and third > 0
		and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		want = CAM.Shoulder * third
	end
	-- Never push the camera's pivot into a wall or a parked car.
	local len = want.Magnitude
	if len > 0.05 then
		local world = right * want.X + UP * want.Y + back * want.Z
		local hit = Workspace:Raycast(rootCF.Position + Vector3.new(0, 1.5, 0), world * ((len + GUARD) / len), b.rayParams)
		if hit then
			local room = math.max(0, hit.Distance - GUARD)
			if room < len then
				want *= room / len
				rate = math.max(rate, 16)
			end
		end
	end
	S.camView = S.camView:Lerp(want, 1 - math.exp(-dt * rate))
	if len <= 0.05 and S.camView.Magnitude < 0.004 then
		S.camView = ZERO
	end

	-- Head bob: one small dip per step, and the landing dip. Third person, our own camera only.
	local bobWant = 0
	if onFoot and S.active and req == nil and third > 0 then
		if S.grounded and S.pace > 1.5 and S.bobAmp > 0 then
			bobWant = -S.bobAmp * math.sin(math.pi * math.min(1, (now - S.stepAt) / S.stepPeriod))
		end
		bobWant -= (L.LandDip or 0.25) * S.squash
		bobWant *= third
	end
	S.bob = approach(S.bob, bobWant, dt, 0.035)
	if bobWant == 0 and math.abs(S.bob) < 0.0005 then
		S.bob = 0
	end

	-- View space -> the root's own space, which is what the humanoid wants.
	local v = S.camView
	local offset = rootCF:VectorToObjectSpace(right * v.X + UP * (v.Y + S.bob) + back * v.Z)
	if (offset - cur).Magnitude > 0.0005 then
		hum.CameraOffset = offset
	end
	S.offWrite = hum.CameraOffset
end

-- Render step, after the camera: the FOV, the idle drift and the swing back behind you.
local function cameraStep(dt)
	local cam = Workspace.CurrentCamera
	local b = body
	if not cam or not b or not b.hum.Parent or not onFootCamera(cam, b.hum) then
		-- Someone else's camera (a car, the title screen, the dressing room): we pick the FOV up again
		-- from wherever they leave it.
		S.fov, S.fovWrite, S.idle = nil, nil, 0
		Status.IdleCam = false
		return
	end
	dt = math.clamp(dt, 1 / 240, 0.1)
	local now = os.clock()
	if S.stick2 > STICK_DEAD then
		S.lastInputAt, S.lastCamInputAt = now, now -- (a stick held still sends no events)
	end
	local fovTop = top(fovReq)
	-- A gun is out and CombatClient zooms by writing the FOV itself: hands off. Judged apart from the
	-- camera offset, so CombatClient may move either one to the request stack without the other. It
	-- only asks for an FOV while aiming, so "no request right now" can't be the test here: instead, once
	-- an FOV has been asked for (or let go of) through the stack with a gun out, the FOV is ours for good.
	-- (S.gunFovStack starts out true, see S: with this CombatClient the FOV is ours from the first draw,
	-- or it would sit frozen at the sprint or idle FOV until the first aim.)
	local gunFov = S.gunOut and fovTop == nil and not S.gunFovStack
	local busy = S.gunOut or fovTop ~= nil or top(camReq) ~= nil

	-- Idle: nothing touched for a long while, standing still.
	local idleOn = CAM.IdleAfter ~= nil and S.active and not busy and S.rawMove <= 0.05 and S.pace < 0.5
		and now - S.lastInputAt >= CAM.IdleAfter
	S.idle = approach(S.idle, idleOn and 1 or 0, dt, idleOn and CAM.IdleIn or CAM.IdleOut)
	if not idleOn and S.idle < 0.002 then
		S.idle = 0
	end
	Status.IdleCam = idleOn

	-- FOV. Someone else's write is followed, never fought.
	local cur = cam.FieldOfView
	if S.fovCam ~= cam or S.fov == nil then
		S.fovCam, S.fov, S.fovWrite = cam, cur, cur
	elseif S.fovWrite and math.abs(cur - S.fovWrite) > 0.02 then
		S.fovForeignAt = now
		-- Something snaps the idle zoom back while nobody touches anything (an older CombatClient tidies
		-- up any FOV between its zoom and 70): after the second time, the idle camera only drifts, for
		-- the rest of the session.
		if idleOn and S.idle > 0.03 and not S.idleFovOff then
			S.idleStrikes += 1
			if S.idleStrikes >= 2 then
				S.idleFovOff = true
			end
		end
	end
	if gunFov then
		S.fovForeignAt = now
	end
	if now - S.fovForeignAt < YIELD_TIME then
		S.fov, S.fovWrite = cur, cur
	else
		local rest = CAM.BaseFov or 70
		local want, rate
		if fovTop then
			want, rate = fovTop.fov, fovTop.rate
		else
			local run = baseSpeed()
			local fast = 0
			if S.active then
				fast = math.clamp((S.pace - run) / math.max(0.1, run * (SPRINT_MULT - 1)), 0, 1)
			end
			want = rest + (CAM.SprintFov or 0) * fast
			if not S.idleFovOff and CAM.IdleFov then
				want += (CAM.IdleFov - rest) * S.idle
			end
			-- Coming out of the idle zoom is quick: the view is the player's again at once.
			rate = (not idleOn and S.fov < rest - 0.3) and 14 or CAM.FovEase
		end
		S.fov += (want - S.fov) * (1 - math.exp(-dt * rate))
		if math.abs(S.fov - want) < 0.01 then
			S.fov = want
		end
		if math.abs(S.fov - cur) > 0.01 then
			cam.FieldOfView = S.fov
		end
		S.fovWrite = cam.FieldOfView
	end

	-- Turning the camera about the point it looks at. Roblox's camera takes its next look from the
	-- camera's own CFrame, so a small turn here carries on into the next frame.
	local turn = 0
	if S.idle > 0 then
		turn += RAD(CAM.IdleYaw or 0) * S.idle * dt
	end
	if CAM.Recenter and S.active and not busy and S.mode ~= "keyboard" and S.rawMove > 0.3 and S.pace > 4
		and now - S.lastCamInputAt > CAM.RecenterAfter
		and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
		and (cam.CFrame.Position - cam.Focus.Position).Magnitude > 1.5 then
		local look = cam.CFrame.LookVector
		-- The way the player pushes, not the way the body travels: walking across a moving boat's deck
		-- must not swing the view round to the boat's heading.
		local head = S.moveDir
		local hx, hz = S.velX, S.velZ
		if head then
			hx, hz = head.X, head.Z
		end
		local diff = angleDiff(math.atan2(-hx, -hz), math.atan2(-look.X, -look.Z))
		if math.abs(diff) < RAD(CAM.RecenterMaxAngle) then
			local most = RAD(CAM.RecenterMaxRate) * dt
			turn += math.clamp(diff * (1 - math.exp(-dt / CAM.RecenterTime)), -most, most)
		end
	end
	if math.abs(turn) > 1e-5 then
		local focus = cam.Focus.Position
		cam.CFrame = CFrame.new(focus) * CFrame.Angles(0, turn, 0) * CFrame.new(-focus) * cam.CFrame
	end
end

------------------------------------------------------------------ input

-- Any real input: the idle camera's clock starts again. Camera input (right stick, a drag on the right
-- of a touch screen) also holds off the swing back behind you.
local function noteInput(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.Accelerometer or t == Enum.UserInputType.Gyro or t == Enum.UserInputType.Focus
		or t == Enum.UserInputType.TextInput then
		return
	end
	local now = os.clock()
	if GAMEPAD[t] then
		local key = input.KeyCode
		if key == Enum.KeyCode.Thumbstick2 then
			local p = input.Position
			S.stick2 = math.sqrt(p.X * p.X + p.Y * p.Y)
			if S.stick2 < STICK_DEAD then
				return -- a resting stick's jitter
			end
			S.lastCamInputAt = now
		elseif key == Enum.KeyCode.Thumbstick1 then
			local p = input.Position
			if p.X * p.X + p.Y * p.Y < STICK_DEAD * STICK_DEAD then
				return
			end
		elseif key == Enum.KeyCode.ButtonL2 or key == Enum.KeyCode.ButtonR2 then
			if input.Position.Z < 0.1 then
				return
			end
		end
	elseif t == Enum.UserInputType.Touch then
		local cam = Workspace.CurrentCamera
		if cam and input.Position.X > cam.ViewportSize.X * 0.4 then
			S.lastCamInputAt = now -- (the left 40% is Roblox's thumbstick)
		end
	end
	S.lastInputAt = now
end

local function readMode(last)
	if typeof(last) ~= "EnumItem" then
		last = UserInputService:GetLastInputType()
	end
	if GAMEPAD[last] then
		S.mode = "gamepad"
	elseif last == Enum.UserInputType.Touch then
		S.mode = "touch"
	elseif last == Enum.UserInputType.Keyboard or last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseButton1 or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseButton3 or last == Enum.UserInputType.MouseWheel then
		S.mode = "keyboard"
	elseif Theme.IsTouch() then
		S.mode = "touch"
	end
end

local function readAttributes()
	S.inHome = player:GetAttribute("InHome") == true
	S.title = player:GetAttribute("TitleScreen") == true
	local knocked, stunned = player:GetAttribute("KnockedUntil"), player:GetAttribute("StunnedUntil")
	S.knockedUntil = type(knocked) == "number" and knocked or 0
	S.stunnedUntil = type(stunned) == "number" and stunned or 0
	local base = player:GetAttribute("MoveBase")
	S.moveBase = (type(base) == "number" and base == base) and math.clamp(base, 0, 60) or nil
end

-- Roblox's control module: the move vector exactly as the player pushes it (keys, stick, thumbstick).
local function findControls()
	local scripts = player:WaitForChild("PlayerScripts", 15)
	local module = scripts and scripts:WaitForChild("PlayerModule", 15)
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, playerModule = pcall(require, module)
	if ok and type(playerModule) == "table" and type(playerModule.GetControls) == "function" then
		local ok2, c = pcall(playerModule.GetControls, playerModule)
		if ok2 and type(c) == "table" and type(c.GetMoveVector) == "function" then
			controls = c
		end
	end
end

-- Left Shift is sprint here: Roblox's own shift lock (if the game and the player have it on) moves to
-- the keys in Config ShiftLockKeys. Its controller reads them from this StringValue.
local function moveShiftLock()
	if not HOLD[Enum.KeyCode.LeftShift] or type(L.ShiftLockKeys) ~= "string" then
		return
	end
	local scripts = player:WaitForChild("PlayerScripts", 15)
	local module = scripts and scripts:WaitForChild("PlayerModule", 15)
	local camera = module and module:WaitForChild("CameraModule", 15)
	local lock = camera and camera:WaitForChild("MouseLockController", 15)
	local keys = lock and lock:WaitForChild("BoundKeys", 15)
	if keys and keys:IsA("StringValue") then
		keys.Value = L.ShiftLockKeys
	end
end

------------------------------------------------------------------ the character

-- A new body (or none): everything that belonged to the old one starts over.
local function resetBodyState()
	S.active, S.grounded = false, false
	S.planar, S.pace, S.velX, S.velZ = 0, 0, 0, 0
	S.wasMoving, S.sprint, S.sprinting = false, 0, false
	S.stock, S.moveDir = nil, nil
	S.lastSpeed, S.foreign, S.preForeign = nil, nil, nil
	S.brakeOn = false
	S.stamina, S.exhausted, S.exhaustedUntil, S.needRelease = L.Stamina, false, 0, false
	S.toggle = false
	S.lastYaw, S.yawRate, S.accel, S.lastPlanar, S.pitch, S.roll = nil, 0, 0, 0, 0, 0
	S.squashT, S.squash, S.exW, S.tiredW = nil, 0, 0, 0
	S.inAir = false
	S.stepSide, S.bob, S.bobAmp = 0, 0, 0
	S.camView, S.offWrite = ZERO, nil
	S.gunOut, S.gunWas, S.gunEase = false, false, false
	S.breathVol = 0
	S.nextSlow = 0
	Status.Active, Status.Sprinting, Status.Exhausted = false, false, false
	Status.Stamina, Status.Speed, Status.Cap, Status.CapBy = L.Stamina, 0, nil, nil
end

local function unbind()
	local b = body
	if not b then
		return
	end
	body = nil
	for _, conn in ipairs(b.conns) do
		conn:Disconnect()
	end
	-- The old body may live on a moment (knocked out, or fading away): leave it as its animations have it.
	for name in pairs(b.joints) do
		freeJoint(b, name)
	end
	local run = b.runSound
	if run and run.Parent and b.runVolume then
		run.Volume = b.runVolume
	end
	if breath and breath.IsPlaying then
		breath:Stop()
	end
	resetBodyState()
	if tile and S.tileShown then
		S.tileShown = false
		tile.Visible = false
	end
end

local function bind(char)
	local hum = char:WaitForChild("Humanoid", 15)
	local root = char:WaitForChild("HumanoidRootPart", 15)
	if not hum or not root or not hum:IsA("Humanoid") or not root:IsA("BasePart") or player.Character ~= char then
		return
	end
	-- The speed this body came with (StarterPlayer.CharacterWalkSpeed: 18 in this place), read before we
	-- write anything of our own: it is the base every other speed is a share of. (Bound a second time to
	-- the same body, WalkSpeed already holds one of our numbers: keep the first reading. A body that is
	-- held at a standstill right now gives nothing to go by: ask the place's setting.)
	local stock = hum.WalkSpeed
	if body and body.hum == hum and body.stock then
		stock = body.stock
	elseif not (stock == stock and stock >= 1 and stock <= 100) then
		local ok, setting = pcall(function()
			return game:GetService("StarterPlayer").CharacterWalkSpeed
		end)
		stock = (ok and type(setting) == "number" and setting >= 1 and setting <= 100) and setting or L.Run
	end
	unbind()
	resetBodyState()
	S.stock = stock
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local b = {
		char = char, hum = hum, root = root,
		joints = {}, jointMiss = {}, conns = {},
		rayParams = params, -- the shoulder camera's wall check
		legLen = 1.6, legAt = -10, feetMiss = 0,
		stock = stock, -- the WalkSpeed it spawned with (also S.stock while this body is ours)
	}
	table.insert(b.conns, hum.StateChanged:Connect(function(_, new)
		onState(b, new)
	end))
	table.insert(b.conns, hum.Died:Connect(function()
		if body == b then
			unbind()
		end
	end))
	body = b
end

------------------------------------------------------------------ API

function LocomotionClient.SetCap(source, speed)
	if source == nil then
		return
	end
	if type(speed) == "number" and speed == speed then
		caps[source] = math.max(0, speed)
	else
		caps[source] = nil
	end
end

function LocomotionClient.Suspend(source, on)
	if source == nil then
		return
	end
	local was = suspends[source] == true
	if on and not was then
		suspends[source] = true
		S.suspended += 1
	elseif not on and was then
		suspends[source] = nil
		S.suspended -= 1
	end
end

function LocomotionClient.RequestCameraOffset(source, offset, priority, rate)
	if source == nil or typeof(offset) ~= "Vector3" or offset.X ~= offset.X or offset.Y ~= offset.Y
		or offset.Z ~= offset.Z then
		return
	end
	if S.gunOut then
		S.gunOffStack = true -- (see S: the gun camera's offset comes through the stack from now on)
	end
	local r = camReq[source]
	if not r then
		-- (its place among equals is fixed when it is first made: asking again every frame to change the
		-- numbers must not keep jumping the queue)
		serial += 1
		r = { at = serial }
		camReq[source] = r
	end
	r.offset = offset
	r.priority = tonumber(priority) or 1
	r.rate = math.clamp(tonumber(rate) or CAM.ShoulderEase, 1, 60)
end

function LocomotionClient.ReleaseCameraOffset(source)
	if source ~= nil and camReq[source] ~= nil then
		if S.gunOut then
			S.gunOffStack = true
		end
		camReq[source] = nil
	end
end
LocomotionClient.Release = LocomotionClient.ReleaseCameraOffset

function LocomotionClient.RequestFov(source, fov, priority, rate)
	if source == nil or type(fov) ~= "number" or fov ~= fov then
		return
	end
	if S.gunOut then
		S.gunFovStack = true -- (see S: the gun's zoom comes through the stack from now on)
	end
	local r = fovReq[source]
	if not r then
		serial += 1
		r = { at = serial }
		fovReq[source] = r
	end
	r.fov = math.clamp(fov, 20, 110)
	r.priority = tonumber(priority) or 1
	r.rate = math.clamp(tonumber(rate) or CAM.FovEase, 1, 60)
end

function LocomotionClient.ReleaseFov(source)
	if source ~= nil and fovReq[source] ~= nil then
		if S.gunOut then
			S.gunFovStack = true
		end
		fovReq[source] = nil
	end
end

function LocomotionClient.Stamina()
	return S.stamina, L.Stamina
end

function LocomotionClient.UseStamina(amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return true
	end
	if S.exhausted or S.stamina < amount then
		return false
	end
	S.stamina -= amount
	S.lastDrainAt = os.clock()
	return true
end

function LocomotionClient.IsActive()
	return S.active
end

function LocomotionClient.IsSprinting()
	return S.sprinting
end

function LocomotionClient.IsExhausted()
	return S.exhausted
end

function LocomotionClient.Squash(strength)
	if not S.active then
		return
	end
	S.squashT = 0
	S.squashAmp = math.clamp(tonumber(strength) or 1, 0, 1)
end

function LocomotionClient.OnStep(fn)
	if type(fn) ~= "function" then
		return function() end
	end
	table.insert(stepListeners, fn)
	return function()
		local i = table.find(stepListeners, fn)
		if i then
			table.remove(stepListeners, i)
		end
	end
end

function LocomotionClient.Init()
	if started then
		return
	end
	started = true
	buildGui()
	layout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(layout)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(layout)

	readAttributes()
	for _, name in ipairs({ "InHome", "TitleScreen", "KnockedUntil", "StunnedUntil", "MoveBase" }) do
		player:GetAttributeChangedSignal(name):Connect(readAttributes)
	end
	-- Other tiles come and go in the side column with these: place ours again at once.
	for _, name in ipairs({ "Side", "InHideout" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			S.nextSlow = 0
		end)
	end

	readMode()
	UserInputService.LastInputTypeChanged:Connect(readMode)
	UserInputService.InputBegan:Connect(function(input, processed)
		noteInput(input)
		if processed then
			return -- typing in chat, or a button took it
		end
		local key = input.KeyCode
		if HOLD[key] then
			if not held[key] then
				held[key] = true
				S.holdCount += 1
			end
		elseif TOGGLE[key] then
			setToggle(not S.toggle)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		if held[key] then
			held[key] = nil
			S.holdCount = math.max(0, S.holdCount - 1)
		end
		if key == Enum.KeyCode.Thumbstick2 then
			S.stick2 = 0
		end
	end)
	UserInputService.InputChanged:Connect(noteInput)
	-- Alt-tabbing away with Shift down never sends the key up.
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held)
		S.holdCount = 0
		S.stick2 = 0
	end)

	task.spawn(findControls)
	task.spawn(moveShiftLock)
	task.delay(3, warmSounds)

	player.CharacterAdded:Connect(function(char)
		task.spawn(bind, char)
	end)
	player.CharacterRemoving:Connect(function(char)
		if body and body.char == char then
			unbind()
		end
	end)
	if player.Character then
		task.spawn(bind, player.Character)
	end

	RunService:BindToRenderStep(INPUT_STEP, Enum.RenderPriority.Input.Value + 5, inputStep)
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 4, cameraStep)
	RunService.PreSimulation:Connect(simStep)
end

return LocomotionClient
