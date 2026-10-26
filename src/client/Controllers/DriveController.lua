-- DriveController (ModuleScript, StarterPlayerScripts.Controllers.DriveController)
-- Drives the car the local player is sitting in (their device owns the car's physics).
-- The physics itself lives in Shared.Util.CarPhysics (also used by the AI police on the server);
-- this controller gathers input, runs the physics every step, and handles the chase camera,
-- wheel visuals and the drive actions (handbrake, nitro, exit, flip).
-- Input: the VehicleSeat's ThrottleFloat/SteerFloat (keyboard, gamepad and touch through Roblox's
-- default controls) unless DriveController.Input overrides them (phone pedals, DriveUI).
--   * Keyboard steering is eased: A / D give -1 / 0 / 1, so the wheel is turned toward that at a
--     speed-sensitive rate (quick when slow, calmer when fast, quickest back to centre and while the
--     handbrake is held). Sticks and the phone thumbstick are already smooth and pass straight through.
--   * Drifting (CarPhysics has the model): handbrake + steer swings the tail out, then throttle +
--     steering into the turn holds the slide; counter-steering or letting go ends it.
--     Status.SlipAngle / Status.Drifting say how it's going.
--   * Chase camera: low and close at rest (further back and higher behind a tall body: a van, a truck),
--     backs off with speed, looks into corners (and along the slide in a drift), stays out of walls and
--     out of the car. Near top speed and on nitro it hums a little (a small wobble, CAM_HUM). Free look:
--     hold the right mouse button, use the right stick, or drag on the right-hand side of a touch screen;
--     1.5 s after you let go it eases back behind the car. Stunt jumps (player attribute InStunt) get a
--     lazier, wider camera with no hum.
--   * Wheels (looks only): they ride the suspension and spin; the front ones show the steering, and
--     in a slide they swing round toward where the car is really going (the counter-steer look).
--   * Live tuning: the server can change the car's attributes while you sit in it; the physics, the
--     camera and Status pick the new numbers up on the next step (Cfg is CarPhysics' live table).
--   * Getting out never depends on the drive state: F (keyboard), E when no "hold E" prompt is showing,
--     B (gamepad) and DriveUI's EXIT all call DriveController.Exit() from ANY seat. The keys are read
--     straight from UserInputService (not ContextActionService), so no later binding (the weapon wheel,
--     combat, the phone) can take them over. The seat is Humanoid.SeatPart, or the seat a weld still
--     joins to the root part when the humanoid has lost track of it (that case used to give up on the
--     spot). Still in the same seat 0.7 s after asking: ask again and stand up here as well.
--     Studio only: a press in a car that does nothing says why in the Output (Roblox's menu open, a text
--     box has the keyboard, pressed again too soon, just sat down), and so does a seat that still holds
--     you 1.6 s after asking (the server's reason if it gave one, the seat's welds, the jump state), so
--     the next "F stopped working" explains itself.
--   * A car can reach this device in pieces (the server may sit you in a car it spawned a moment ago):
--     driving starts as soon as everything CarPhysics needs has arrived, and keeps trying until then.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local CarPhysics = require(ReplicatedStorage.Shared.Util.CarPhysics)

local player = Players.LocalPlayer

local DriveController = {}

-- Other controllers (phone buttons, HUD) read and write this.
DriveController.Input = {
	Throttle = nil, -- -1..1, overrides the seat when set
	Steer = nil, -- -1..1
	Handbrake = false,
	Nitro = false,
}
DriveController.Status = {
	Driving = false,
	Speed = 0, -- studs/s, forward
	Throttle = 0, -- -1..1: the gas pedal the physics used this step (SoundClient: engine load and launch revs)
	Steer = 0, -- -1..1: the eased steering the physics used this step (VehicleFeel: the driver's hands)
	MaxSpeed = 0,
	NitroFuel = 1, -- 0..1
	NitroActive = false,
	NitroEmpty = false, -- nitro held with the gas down but nothing to burn (SoundClient's one click)
	Flat = false,
	SlipAngle = 0, -- degrees between the nose and the direction of travel (0 when slow or airborne)
	Drifting = false, -- sliding the way the drift zone scores it (cars, nose first, 12-80 degrees, over 30 studs/s)
	Car = nil,
}
-- os.clock() until which the get-out keys do nothing: InteractClient sets it for half a second when its
-- acted get-in sits you down, so a late second press meant to skip ahead doesn't put you straight back out.
DriveController.NoExitUntil = 0

local WHEELS = CarPhysics.Wheels
local FRONT = { FL = true, FR = true }
local ACTIONS = { "NC_Handbrake", "NC_Nitro", "NC_Flip" }
local CAMERA_STEP = "NC_DriveCamera"

-- Keyboard steering: how fast the wheel turns (full lock = 1), per second.
local STEER_IN_SLOW = 8 -- at a standstill: full lock in about 0.12 s
local STEER_IN_FAST = 3.5 -- at top speed: about 0.3 s, so a tap is a lane change, not a swerve
local STEER_BACK = 10 -- back to centre, the other way, or flicking into a drift

-- Chase camera
local CAM_DIST = 13.5 -- studs from the car at rest (a long car or boat: its half diagonal + 3.5; a tall one: CAM_TALL_*)
-- A tall body (a van's roof): the rest view clears CAM_ROOF studs over the chassis centre at a car's tail
-- (every car is under it, the boxiest SUV only just). Each stud of roof above that (up to CAM_TALL_MAX)
-- lifts the camera and the point it looks at by CAM_TALL_LIFT and backs it off by CAM_TALL_BACK.
-- (Estimated from the mesh proportions: if an ordinary car's camera moves, raise CAM_ROOF.)
local CAM_ROOF = 5
local CAM_TALL_LIFT = 1
local CAM_TALL_BACK = 2.5
local CAM_TALL_MAX = 3
local CAM_DIST_SPEED = 5.5 -- more at top speed
local CAM_ELEVATION = math.rad(18) -- how far above the car's level the camera sits (the road must show over the roof)
local CAM_ANCHOR_UP = 1.6 -- the point the camera circles, above the chassis centre
local CAM_LOOK_UP = 2.6 -- the camera looks at a point this high...
local CAM_LOOK_AHEAD = 8 -- ...and this far past the car
local CAM_TURN = 6 -- per second: how fast the camera swings round behind the car
local CAM_LEAD = 0.3 -- seconds of turning the camera looks ahead in a corner
local CAM_LEAD_MAX = 0.45 -- radians
local CAM_FOLLOW = 24 -- per second: how tightly the camera's position follows (stunt jumps: 2)
local LOOK_HOLD = 1.5 -- seconds after free look stops before the camera eases back
local LOOK_RETURN = 4 -- per second
local MOUSE_SENS = 0.0045 -- radians per pixel
local TOUCH_SENS = 0.006
local STICK_YAW, STICK_PITCH = 2.6, 1.6 -- radians per second at full stick
local LOOK_PITCH_MIN = math.rad(3) - CAM_ELEVATION -- never under the road
local LOOK_PITCH_MAX = math.rad(65) - CAM_ELEVATION
-- Speed hum: past this share of top speed the camera starts to wobble, up to CAM_HUM studs flat out,
-- plus CAM_HUM_NITRO while the nitro burns (math.noise swings about half of that either way).
local CAM_HUM_FROM = 0.7
local CAM_HUM = 0.1
local CAM_HUM_NITRO = 0.08

-- Front wheels (looks only): full steering lock, and how far they may swing toward the travel
-- direction in a slide (radians).
local WHEEL_LOCK = 0.45
local WHEEL_SLIDE_LOCK = 0.6

local state = nil
local exitRemote = nil
local startToken = 0 -- bumps on every seat change; a waiting start gives up when it no longer matches
-- [prompt] = true while it's on screen (E gets you out only when none of them uses E). Weak keys: a prompt
-- destroyed while it showed (so its PromptHidden never came) can't stay here for the rest of the session.
local promptsShown = setmetatable({}, { __mode = "k" })
local STUDIO = RunService:IsStudio()
local exitRefusal = nil -- the server's reason when it found no seat to get us out of (CarExitSpot(nil, why))

-- Where a prompt is (its part or attachment), or nil.
local function promptAt(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

-- Is a prompt that E would trigger on screen right now? Asked of the prompts themselves, not of a count
-- of PromptShown / PromptHidden: one that was destroyed or streamed out, switched off, hidden by
-- PromptGate (MaxActivationDistance 0), or out of its own reach of us is forgotten here even if its
-- PromptHidden never came, so E can't get stuck belonging to a prompt that isn't there. Prompts on
-- another key (Cuff is Q) never block E.
local function ePromptShowing()
	if not ProximityPromptService.Enabled then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local found = false
	for prompt in pairs(promptsShown) do
		local at = prompt.Parent and promptAt(prompt)
		local near = not (root and at) or (at - root.Position).Magnitude <= prompt.MaxActivationDistance + 4
		if prompt.Enabled and prompt.MaxActivationDistance > 0 and prompt:IsDescendantOf(Workspace) and near then
			if prompt.KeyboardKeyCode == Enum.KeyCode.E then
				found = true
			end
		else
			promptsShown[prompt] = nil
		end
	end
	return found
end
local lastExit = 0

-- Everything CarPhysics and the wheel visuals read. A car spawned a moment ago may still be arriving.
local NEEDED = { "NCVehicle", "MaxSpeed", "Accel", "SpringHz", "RestLength", "WheelRadius" }
local function carReady(car)
	local chassis = car and car:IsA("Model") and car.PrimaryPart
	if not chassis then
		return false
	end
	for _, a in ipairs(NEEDED) do
		if car:GetAttribute(a) == nil then
			return false
		end
	end
	if not chassis:FindFirstChild("DriveForce") or not chassis:FindFirstChild("BodyTorque") then
		return false
	end
	for _, name in ipairs(WHEELS) do
		if not chassis:FindFirstChild("Wheel" .. name) or not chassis:FindFirstChild("Force" .. name) then
			return false
		end
	end
	return true
end

-- The seat's ThrottleFloat / SteerFloat come from Roblox's control scripts, and those can miss a seat
-- the server put you in (the car that "won't drive until you get out and back in"). So whenever the
-- seat reads zero, the keys, triggers and sticks are read directly.
local K = Enum.KeyCode
local controls = nil -- Roblox's ControlModule (the phone thumbstick), found on first use
local function rawInput()
	if UserInputService:GetFocusedTextBox() then
		return 0, 0
	end
	local t, st = 0, 0
	if UserInputService:IsKeyDown(K.W) or UserInputService:IsKeyDown(K.Up) then
		t += 1
	end
	if UserInputService:IsKeyDown(K.S) or UserInputService:IsKeyDown(K.Down) then
		t -= 1
	end
	if UserInputService:IsKeyDown(K.D) or UserInputService:IsKeyDown(K.Right) then
		st += 1
	end
	if UserInputService:IsKeyDown(K.A) or UserInputService:IsKeyDown(K.Left) then
		st -= 1
	end
	if UserInputService.GamepadEnabled then
		for _, input in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if input.KeyCode == K.ButtonR2 then
				t += input.Position.Z
			elseif input.KeyCode == K.ButtonL2 then
				t -= input.Position.Z
			elseif input.KeyCode == K.Thumbstick1 and math.abs(input.Position.X) > 0.15 then
				st += input.Position.X
			end
		end
	end
	if st == 0 and UserInputService.TouchEnabled then
		if controls == nil then
			local ok, c = pcall(function()
				return require(player.PlayerScripts:WaitForChild("PlayerModule", 1)):GetControls()
			end)
			controls = ok and c or false
		end
		if controls then
			local x = controls:GetMoveVector().X
			if math.abs(x) > 0.15 then
				st = x
			end
		end
	end
	return math.clamp(t, -1, 1), math.clamp(st, -1, 1)
end

local function steerKeyDown()
	return UserInputService:IsKeyDown(K.A) or UserInputService:IsKeyDown(K.D)
		or UserInputService:IsKeyDown(K.Left) or UserInputService:IsKeyDown(K.Right)
end

-- Keys steer in jumps (-1, 0, 1), which made the car twitch: turn the wheel toward the key instead.
-- A stick or the phone thumbstick (anything that isn't a held steering key) passes through untouched.
local function easeSteer(s, raw, dt, handbrake)
	if raw ~= 0 then
		s.KeySteer = math.abs(raw) == 1 and steerKeyDown()
	end
	if not s.KeySteer then
		s.SteerOut = raw
		return raw
	end
	local cur = s.SteerOut
	local rate
	if raw == 0 or raw * cur < 0 or handbrake then
		rate = STEER_BACK
	else
		local frac = math.clamp(math.abs(s.Phys.FwdSpeed) / s.Cfg.MaxSpeed, 0, 1)
		rate = STEER_IN_SLOW + (STEER_IN_FAST - STEER_IN_SLOW) * frac
	end
	if cur < raw then
		cur = math.min(raw, cur + rate * dt)
	else
		cur = math.max(raw, cur - rate * dt)
	end
	s.SteerOut = cur
	return cur
end

local function physicsStep(dt)
	local s = state
	if not s then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not s.Chassis:IsDescendantOf(Workspace) or not hum or hum.SeatPart ~= s.Seat then
		-- (why, for the Output window: when the seat is still ours, watchCharacter's safety net starts again)
		DriveController.LastStop = not hum and "no humanoid"
			or (hum.SeatPart ~= s.Seat and ("seat is now " .. tostring(hum.SeatPart)) or "chassis left the Workspace")
		DriveController.Stop()
		return
	end
	local i = DriveController.Input
	local phys = s.Phys
	local throttle, steer = i.Throttle or s.Seat.ThrottleFloat, i.Steer or s.Seat.SteerFloat
	if throttle == 0 or steer == 0 then
		local rt, rs = rawInput()
		throttle = (throttle == 0 and i.Throttle == nil) and rt or throttle
		steer = (steer == 0 and i.Steer == nil) and rs or steer
	end
	if i.Steer == nil then
		steer = easeSteer(s, steer, dt, i.Handbrake)
	end
	local step = s.StepInput -- one table for the whole drive: nothing new to collect every step
	step.Throttle, step.Steer, step.Handbrake, step.Nitro = throttle, steer, i.Handbrake, i.Nitro
	CarPhysics.Step(phys, dt, step)
	local status = DriveController.Status
	status.Speed = phys.FwdSpeed
	status.Throttle = throttle
	status.Steer = steer
	status.MaxSpeed = s.Cfg.MaxSpeed
	status.NitroFuel = phys.NitroFuel
	status.NitroActive = phys.NitroOn
	status.NitroEmpty = phys.NitroEmpty == true
	status.Flat = phys.Flat
	status.SlipAngle = phys.SlipAngle
	status.Drifting = phys.Drifting
end

-- a - b, the short way round (-pi..pi)
local function angleDiff(a, b)
	return (a - b + math.pi) % (2 * math.pi) - math.pi
end

-- Camera and wheel visuals (every frame)
local function renderStep(dt)
	local s = state
	if not s then
		return
	end
	local phys = s.Phys
	local chassis = s.Chassis
	local cfg = s.Cfg
	local camera = Workspace.CurrentCamera
	local cf = chassis.CFrame
	local pos = cf.Position
	local look = cf.LookVector
	local vel = chassis.AssemblyLinearVelocity
	local flatSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	local speedFrac = math.clamp(flatSpeed / cfg.MaxSpeed, 0, 1.2)
	-- Stunt jumps: a lazier, wider camera while airborne feels like slow motion.
	local inStunt = player:GetAttribute("InStunt") == true

	-- Which way the camera faces (a heading: 0 looks along -Z, growing to the left). Mostly the car's
	-- nose, plus part of the way toward where the car is really going (so a drift shows the car
	-- sideways), plus a little ahead of the turn so you see into the corner.
	local carYaw = s.CarYaw
	if look.X * look.X + look.Z * look.Z > 0.01 then
		carYaw = math.atan2(-look.X, -look.Z)
		s.CarYaw = carYaw
	end
	local travel, sliding = 0, 0
	if flatSpeed > 20 then
		local off = angleDiff(math.atan2(-vel.X, -vel.Z), carYaw)
		if math.abs(off) < 1.37 then -- moving nose first (within about 78 degrees of it)
			sliding = math.clamp((math.deg(math.abs(off)) - 8) / 20, 0, 1)
			travel = off * (0.3 + 0.3 * sliding)
		end
	end
	local lead = math.clamp(chassis.AssemblyAngularVelocity.Y * (CAM_LEAD - 0.2 * sliding), -CAM_LEAD_MAX, CAM_LEAD_MAX)
		* math.clamp(phys.FwdSpeed / 30, 0, 1)
	s.CamYaw += angleDiff(carYaw + travel + lead, s.CamYaw) * (1 - math.exp(-dt * (inStunt and 2 or CAM_TURN)))

	-- Free look: right mouse button, right stick, or a finger dragged on the right of the screen
	-- (the stick and the finger are tracked by the connections made in Start).
	local looking = false
	if UserInputService.MouseEnabled and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		and not UserInputService:GetFocusedTextBox() then
		s.MouseLocked = true
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCurrentPosition then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
		local delta = UserInputService:GetMouseDelta()
		s.LookYaw -= delta.X * MOUSE_SENS
		s.LookPitch += delta.Y * MOUSE_SENS
		looking = true
	elseif s.MouseLocked then
		s.MouseLocked = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	if s.StickX ~= 0 or s.StickY ~= 0 then
		s.LookYaw -= s.StickX * STICK_YAW * dt
		s.LookPitch -= s.StickY * STICK_PITCH * dt
		looking = true
	end
	local finger = s.LookTouch
	if finger then
		local st = finger.UserInputState
		if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
			s.LookTouch = nil -- the lift was missed (app switch): don't hold the view forever
		else
			looking = true
		end
	end
	if looking then
		s.LookIdle = 0
	else
		s.LookIdle += dt
		if s.LookIdle > LOOK_HOLD then
			local back = 1 - math.exp(-dt * LOOK_RETURN)
			s.LookYaw -= s.LookYaw * back
			s.LookPitch -= s.LookPitch * back
		end
	end
	s.LookYaw = angleDiff(s.LookYaw, 0)
	s.LookPitch = math.clamp(s.LookPitch, LOOK_PITCH_MIN, LOOK_PITCH_MAX)

	-- Where the camera sits: on a circle round the car, further out the faster it goes. The height
	-- follows the body softly so the suspension's bounce doesn't shake the picture.
	local yaw = s.CamYaw + s.LookYaw
	local elevation = CAM_ELEVATION + s.LookPitch
	local dirX, dirZ = -math.sin(yaw), -math.cos(yaw)
	local distWant = s.DistRest + CAM_DIST_SPEED * speedFrac + (inStunt and 3 or 0)
	s.CamDist += (distWant - s.CamDist) * (1 - math.exp(-dt * 3))
	s.CamY += (pos.Y - s.CamY) * (1 - math.exp(-dt * 10))
	local baseY = s.CamY
	local dist = s.CamDist
	local back = dist * math.cos(elevation)
	local origin = Vector3.new(pos.X, baseY + CAM_LOOK_UP + s.Lift, pos.Z)
	local target = Vector3.new(pos.X - dirX * back, baseY + CAM_ANCHOR_UP + s.Lift + dist * math.sin(elevation), pos.Z - dirZ * back)
	-- Keep the camera out of walls.
	local toCam = target - origin
	local hit = Workspace:Raycast(origin, toCam, s.CamParams)
	if hit then
		target = origin + toCam.Unit * math.max(hit.Distance - 1.2, 0.5)
		-- A wall right behind the car would push the camera into the cabin: go over the roof instead.
		local hx, hz = target.X - pos.X, target.Z - pos.Z
		local inside = s.Radius + 1 - math.sqrt(hx * hx + hz * hz)
		if inside > 0 then
			target = Vector3.new(target.X, math.max(target.Y, baseY + s.RoofUp + 1 + inside * 0.3), target.Z)
		end
	end
	-- Lazy at once when a stunt starts, back to tight over about a second after the landing.
	if inStunt then
		s.CamRate = 2
	else
		s.CamRate += (CAM_FOLLOW - s.CamRate) * (1 - math.exp(-dt * 3))
	end
	s.CamPos = s.CamPos and s.CamPos:Lerp(target, 1 - math.exp(-dt * s.CamRate)) or target
	-- Look past the car along the camera's own heading (less far when looking down from above).
	local ahead = CAM_LOOK_AHEAD * math.clamp(1 - s.LookPitch / 0.7, 0.2, 1)
	local lookAt = Vector3.new(pos.X + dirX * ahead, baseY + CAM_LOOK_UP + s.Lift, pos.Z + dirZ * ahead)
	-- Near top speed and on nitro the picture hums a little, so flat out feels fast: a small wobble of
	-- the camera itself (s.CamPos stays smooth, and the wall check's 1.2 stud margin covers it).
	local camAt = s.CamPos
	local buzz = math.clamp((speedFrac - CAM_HUM_FROM) / (1 - CAM_HUM_FROM), 0, 1) * CAM_HUM
		+ (phys.NitroOn and CAM_HUM_NITRO or 0)
	if buzz > 0 and not inStunt then
		local t = os.clock() * 23
		camAt += Vector3.new(math.noise(t, 1.7) * buzz, math.noise(t, 5.3) * buzz, math.noise(t, 9.1) * buzz)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(camAt, lookAt)
	local fov = 70 + 12 * math.min(speedFrac, 1) + (phys.NitroOn and 8 or 0) + (inStunt and 12 or 0)
	camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-dt * 4))

	-- Wheels: follow the suspension, steer, spin. Mesh bodies can have bigger or smaller wheels than
	-- the physics radius, so each wheel uses its own size (s.WheelR).
	s.Spin = (s.Spin + phys.FwdSpeed / (s.WheelR or cfg.WheelRadius) * dt) % (math.pi * 2)
	-- The front wheels show the steering, except in a slide: as the tyres let go (phys.Slide) they swing
	-- round to point where the car is really going, the counter-steer look of a real drift.
	local wheelSteer = -phys.Steer * WHEEL_LOCK
	if phys.Slide > 0 then
		local along = vel:Dot(look)
		if along > 5 then
			-- (positive = left, like wheelSteer: in a slide to the right the car moves left of its nose)
			local aim = math.clamp(math.atan2(-vel:Dot(cf.RightVector), along), -WHEEL_SLIDE_LOCK, WHEEL_SLIDE_LOCK)
			wheelSteer += (aim - wheelSteer) * phys.Slide
		end
	end
	for _, name in ipairs(WHEELS) do
		local hub = s.Hubs[name]
		if hub then
			local base = s.WheelBase[name]
			local hitW = phys.Hits[name]
			local r = s.WheelR or cfg.WheelRadius
			local drop = hitW and (hitW.Distance - r) or (cfg.RestLength + cfg.WheelRadius - r)
			local steerAng = FRONT[name] and wheelSteer or 0
			-- Hub.C0 holds the rest position; Transform adds suspension travel, steering and spin.
			hub.Transform = CFrame.new(0, (s.AttY - drop) - base.Y, 0) * CFrame.Angles(0, steerAng, 0) * CFrame.Angles(-s.Spin, 0, 0)
		end
	end
end

local function onAction(name, inputState)
	if not state then
		return Enum.ContextActionResult.Pass
	end
	local held = inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.Change
	if name == "NC_Handbrake" then
		DriveController.Input.Handbrake = held
	elseif name == "NC_Nitro" then
		DriveController.Input.Nitro = held
	elseif name == "NC_Flip" and inputState == Enum.UserInputState.Begin then
		DriveController.Flip()
	end
	return Enum.ContextActionResult.Sink
end

-- Studio only: a get-out press in a car that did nothing, and why (see the header).
local function noExit(why)
	if STUDIO then
		warn("[DriveController] the get-out key did nothing: " .. why)
	end
end

-- The seat holding the local character, as (humanoid, seat, welded): Humanoid.SeatPart, or when the
-- humanoid has lost track of it while a weld still holds the body (welded = true), the seat that weld
-- joins to the root part. (humanoid, nil) on foot.
local function mySeat()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil, nil, false
	end
	if hum.SeatPart then
		return hum, hum.SeatPart, false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		for _, j in ipairs(root:GetJoints()) do
			if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
				local other = j.Part0 == root and j.Part1 or j.Part0
				if other and (other:IsA("Seat") or other:IsA("VehicleSeat")) then
					return hum, other, true
				end
			end
		end
	end
	return hum, nil, false
end

-- Studio only: everything about a seat that still holds us after asking to get out.
local function stuckReport(hum, seat)
	local welds = 0
	for _, j in ipairs(seat:GetChildren()) do
		if j:IsA("JointInstance") and j.Name == "SeatWeld" then
			welds += 1
		end
	end
	local car = seat.Parent
	return string.format("[DriveController] still held by %s 1.6 s after asking to get out; server: %s; SeatWelds in that seat: %d;"
		.. " Humanoid.SeatPart = %s; state %s, jumping %s, JumpHeight %.1f; car %s%s",
		seat:GetFullName(), exitRefusal or "no refusal (it stepped us out, or the request never arrived)", welds,
		tostring(hum.SeatPart), tostring(hum:GetState()), hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) and "on" or "off",
		hum.JumpHeight, tostring(car and car.Name), (car and car:GetAttribute("OwnerUserId") == player.UserId) and " (yours)" or "")
end

-- Get out of whatever seat the character is in (driver, passenger, any seat). The server steps you out
-- beside your door. Still in that seat 0.7 s later (a lost or refused request, an odd seat): ask again and
-- stand up here as well. Returns true when it asked.
function DriveController.Exit()
	local hum, seat, welded = mySeat()
	if not hum or not seat then
		return false
	end
	local now = os.clock()
	if now - lastExit < 0.3 then
		noExit("pressed again within 0.3 s")
		return false
	end
	-- Just sat down through InteractClient's acted get-in: a second press that was meant to skip ahead
	-- must not get us straight back out (InteractClient sets this for half a second).
	if now < (DriveController.NoExitUntil or 0) then
		noExit(string.format("you sat down a moment ago (the key works again in %.2f s)", DriveController.NoExitUntil - now))
		return false
	end
	lastExit = now
	exitRefusal = nil
	if welded and STUDIO then
		warn("[DriveController] Humanoid.SeatPart is nil, but a weld holds you to " .. seat:GetFullName() .. ": asking the server anyway")
	end
	if exitRemote then
		exitRemote:FireServer()
	end
	local token = startToken -- (bumps on every seat change: out and back into the same seat is not "still seated")
	local function stillIn()
		local h, sNow = mySeat()
		return h == hum and sNow == seat and startToken == token and hum.Parent ~= nil and hum.Health > 0
	end
	task.delay(0.7, function()
		if not stillIn() then
			return
		end
		if exitRemote then
			exitRemote:FireServer() -- (a request can be lost, or come in behind a burst)
		end
		if hum.SeatPart == seat then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			hum.Sit = false
			hum.Jump = true
		end
	end)
	if STUDIO then
		task.delay(1.6, function()
			if stillIn() then
				warn(stuckReport(hum, seat))
			end
		end)
	end
	return true
end

-- Put an upside-down or stuck car back on its wheels.
function DriveController.Flip()
	local s = state
	if not s then
		return
	end
	local chassis = s.Chassis
	if chassis.CFrame.UpVector.Y > 0.5 or chassis.AssemblyLinearVelocity.Magnitude > 15 then
		return
	end
	local flat = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
	flat = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
	local p = chassis.Position + Vector3.new(0, 4, 0)
	s.Car:PivotTo(CFrame.lookAt(p, p + flat))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
end

function DriveController.Start(seat)
	local car = seat.Parent
	if state or not carReady(car) then
		return
	end
	local chassis = car.PrimaryPart
	local camParams = RaycastParams.new()
	camParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { car, player.Character, Workspace.Vehicles, Workspace:FindFirstChild("Smoke") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character) -- passengers (and anyone else) never push the camera in
		end
	end
	camParams.FilterDescendantsInstances = ignore
	camParams.IgnoreWater = true

	-- The car's footprint, for a camera that never ends up inside it. A mesh body can be bigger than
	-- the chassis (never trust it past 1.5 x, in case something odd is welded on).
	local size = chassis.Size
	local extents = car:GetExtentsSize()
	local width = math.clamp(extents.X, size.X, size.X * 1.5)
	local length = math.clamp(extents.Z, size.Z, size.Z * 1.5)
	local radius = math.sqrt(width * width + length * length) / 2
	-- The real roof (the top of the car's box, over the chassis centre): a tall body lifts the camera.
	local box = car:GetBoundingBox()
	local roof = chassis.CFrame:PointToObjectSpace(box.Position).Y + extents.Y / 2
	local tall = math.clamp(roof - CAM_ROOF, 0, CAM_TALL_MAX)
	local distRest = math.max(CAM_DIST, radius + 3.5) + tall * CAM_TALL_BACK
	local look = chassis.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local s = {
		Car = car,
		Seat = seat,
		Chassis = chassis,
		Cfg = nil, -- set below, with Phys
		Phys = nil,
		StepInput = {},
		SteerOut = 0, -- the eased steering sent to the physics
		KeySteer = false, -- is a key (not a stick) steering right now?
		CamParams = camParams,
		Hubs = {},
		WheelBase = {},
		Spin = 0,
		CamPos = nil,
		CamYaw = yaw,
		CarYaw = yaw,
		CamY = chassis.Position.Y,
		CamRate = CAM_FOLLOW,
		Radius = radius,
		RoofUp = math.max(size.Y / 2 + 2.8, extents.Y * 0.6, roof), -- roof height above the chassis centre
		Lift = tall * CAM_TALL_LIFT, -- camera and look point raised over a tall body (0 for a car)
		DistRest = distRest,
		CamDist = distRest,
		LookYaw = 0, -- free look, on top of the chase heading
		LookPitch = 0,
		LookIdle = LOOK_HOLD,
		StickX = 0,
		StickY = 0,
		LookTouch = nil, -- the finger that is dragging the view
		MouseLocked = false,
	}
	for _, name in ipairs(WHEELS) do
		local wheel = car:FindFirstChild("Wheel" .. name)
		local hub = wheel and wheel:FindFirstChild("Hub")
		if hub then
			s.Hubs[name] = hub
			s.WheelBase[name] = wheel:GetAttribute("Offset") or hub.C0.Position
			s.WheelR = wheel.Size.Y / 2
		end
	end
	s.AttY = chassis:FindFirstChild("WheelFL").Position.Y
	-- Made last, once nothing above can fail any more: it listens to the car's attributes until Stop.
	s.Phys = CarPhysics.New(car, { player.Character })
	s.Cfg = s.Phys.Cfg -- CarPhysics' own table: it follows the car's attributes live (tune-ups)
	state = s

	-- Free look from the right stick and from a finger on the right-hand side of the screen (the left is
	-- Roblox's thumbstick; taps on buttons arrive as "processed" and are left alone).
	s.InputConns = {
		UserInputService.InputChanged:Connect(function(input)
			if input.KeyCode == K.Thumbstick2 then
				local p = input.Position
				s.StickX = math.abs(p.X) > 0.2 and p.X or 0
				s.StickY = math.abs(p.Y) > 0.2 and p.Y or 0
			elseif input == s.LookTouch then
				local d = input.Delta
				s.LookYaw -= d.X * TOUCH_SENS
				s.LookPitch += d.Y * TOUCH_SENS
			end
		end),
		UserInputService.InputBegan:Connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.Touch and not processed and not s.LookTouch
				and input.Position.X > Workspace.CurrentCamera.ViewportSize.X * 0.4 then
				s.LookTouch = input
			end
		end),
		UserInputService.InputEnded:Connect(function(input)
			if input == s.LookTouch then
				s.LookTouch = nil
			elseif input.KeyCode == K.Thumbstick2 then
				s.StickX, s.StickY = 0, 0
			end
		end),
	}

	s.PhysicsConn = RunService.PreSimulation:Connect(physicsStep)
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, renderStep)
	ContextActionService:BindActionAtPriority("NC_Handbrake", onAction, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority("NC_Nitro", onAction, false, 3000, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("NC_Flip", onAction, false, 3000, Enum.KeyCode.R, Enum.KeyCode.DPadUp)
	-- No jumping while seated: jumping throws the driver out (gamepad A, the phone jump button).
	-- Roblox hides its own jump button when the Jumping state is off. Exit uses F / B / EXIT.
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	DriveController.Status.Driving = true
	DriveController.Status.Car = car
end

function DriveController.Stop()
	local s = state
	if not s then
		return
	end
	state = nil
	if s.PhysicsConn then
		s.PhysicsConn:Disconnect()
	end
	for _, conn in ipairs(s.InputConns or {}) do
		conn:Disconnect()
	end
	if s.MouseLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default -- free look was on: give the mouse back
	end
	RunService:UnbindFromRenderStep(CAMERA_STEP)
	for _, a in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(a)
	end
	CarPhysics.Zero(s.Phys)
	local i = DriveController.Input
	i.Handbrake, i.Nitro = false, false
	local status = DriveController.Status
	status.Driving, status.Car, status.Speed, status.NitroActive, status.Flat = false, nil, 0, false, false
	status.NitroEmpty = false
	status.Throttle = 0
	status.Steer = 0
	status.SlipAngle, status.Drifting = 0, false
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		camera.CameraSubject = hum
	end
end

local function watchCharacter(character)
	local hum = character:WaitForChild("Humanoid")
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		-- Always stop first, so switching straight from one seat to another can't leave stale state.
		DriveController.Stop()
		startToken += 1
		local token = startToken
		local seat = hum.SeatPart
		-- No jumping out of any seat of a car, the passenger's as well as the driver's (Space, gamepad A,
		-- the phone jump button): a jump let go of a passenger inside the body, and they left through the
		-- roof of a car that might be moving instead of stepping out beside their door (F / E / B / EXIT).
		-- A passenger never reaches Start, and Stop does nothing for one, so it is set here on every seat
		-- change, after the Stop above (which switches jumping back on): off in a car, on again the moment
		-- the seat clears. A bench or a couch is no car and keeps its jump.
		local seatCar = seat and seat.Parent
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,
			not (seatCar and seatCar:IsA("Model") and seatCar:GetAttribute("NCVehicle") == true))
		if not (seat and seat:IsA("VehicleSeat") and seat.Name == "DriverSeat") then
			return
		end
		-- Start now, or as soon as the whole car has reached this device (give up after 20 s).
		local t0 = os.clock()
		while token == startToken and hum.SeatPart == seat and seat.Parent do
			if carReady(seat.Parent) then
				local ok, err = pcall(DriveController.Start, seat)
				if ok and state then
					return
				elseif not ok then
					warn("[DriveController] start failed, retrying: " .. tostring(err))
				end
			end
			if os.clock() - t0 > 20 then
				warn("[DriveController] the car never finished loading")
				return
			end
			task.wait(0.1)
		end
	end)
	hum.Died:Connect(DriveController.Stop)
	-- The safety net. Driving is meant to be on exactly while this character sits at the wheel, but the
	-- start above only runs when the seat CHANGES: if driving stops for any other reason while the seat
	-- stays the same (the car reached this device in pieces and a part blinked out, the 20 s above ran
	-- out, something stopped it for one frame), nothing would ever start it again and the car would sit
	-- dead until the player got out and back in. So a few times a second: at the wheel of a whole car and
	-- not driving means start.
	task.spawn(function()
		local said = false
		while hum.Parent do
			task.wait(0.25)
			local seat = hum.SeatPart
			if not state and hum.Health > 0 and seat and seat:IsA("VehicleSeat") and seat.Name == "DriverSeat"
				and carReady(seat.Parent) then
				task.wait(0.15) -- (the start above gets the first go: it is on a 0.1 s beat)
				if not state and hum.SeatPart == seat and hum.Health > 0 and carReady(seat.Parent) then
					local ok, err = pcall(DriveController.Start, seat)
					if not said then
						said = true
						warn("[DriveController] driving was off at the wheel of " .. seat.Parent.Name .. ": started again"
							.. (ok and "" or (" (failed: " .. tostring(err) .. ")"))
							.. " | last stop: " .. tostring(DriveController.LastStop or "not by the physics step"))
					end
				end
			end
		end
	end)
end

function DriveController.Init()
	exitRemote = Remotes.Event("RequestExitCar")
	-- The server's answer to getting out: where to stand, beside the door. This device runs our body, so
	-- it puts it there itself, the moment the seat has let go here. (The server's own move often lost
	-- to the seat letting go: the body stood up where it sat and came out through the roof.)
	Remotes.OnClient("CarExitSpot", function(spot, why)
		if typeof(spot) ~= "CFrame" then
			-- No seat to get out of, as far as the server could tell (kept for the Studio report).
			exitRefusal = type(why) == "string" and why or "refused"
			if STUDIO then
				warn("[DriveController] the server didn't step you out: " .. exitRefusal)
			end
			return
		end
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not hum or not root or not root:IsA("BasePart") then
			return
		end
		-- (held: SeatPart, or a seat weld this device still has; moving the root while welded would move the car)
		local function held()
			local _, seat = mySeat()
			return seat ~= nil
		end
		local t0 = os.clock()
		while held() and os.clock() - t0 < 0.6 do
			RunService.Heartbeat:Wait()
		end
		-- (only a step: never across the map on a late or stray message)
		if not held() and hum.Health > 0 and root.Parent and (root.Position - spot.Position).Magnitude < 40 then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = spot
		end
	end)
	-- Getting out, from any seat, whatever the drive state: F / gamepad B, and E when no prompt is up.
	ProximityPromptService.PromptShown:Connect(function(prompt)
		promptsShown[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		promptsShown[prompt] = nil
	end)
	-- Roblox's own menu (Esc / Start): the gamepad B that backs out of it, or an F or E pressed behind it,
	-- also reached us and put you out of a car that then rolled on without you. So no getting out by key
	-- while that menu is up, nor in the moment after it shuts (it can shut on the press itself, before the
	-- press gets here). Not by the "processed" flag: PhoneUI counts on B still getting you out of the car
	-- while the phone has the selection. EXIT on screen is not a key and is never held back.
	local GuiService = game:GetService("GuiService")
	local menuShutAt = 0
	GuiService.MenuClosed:Connect(function()
		menuShutAt = os.clock()
	end)
	UserInputService.InputBegan:Connect(function(input)
		local key = input.KeyCode
		if key ~= Enum.KeyCode.F and key ~= Enum.KeyCode.ButtonB and key ~= Enum.KeyCode.E then
			return
		end
		local _, seat = mySeat()
		if not seat then
			return -- on foot: these keys are InteractClient's (GET IN, JACK...)
		end
		if GuiService.MenuIsOpen or os.clock() - menuShutAt < 0.2 then
			noExit("Roblox's menu is open, or shut a moment ago")
			return
		end
		local box = UserInputService:GetFocusedTextBox()
		if box then
			noExit("a text box has the keyboard (" .. box:GetFullName() .. "): click the game first")
			return
		end
		if key == Enum.KeyCode.E and ePromptShowing() then
			return -- E belongs to the bubble on screen (it did its own thing)
		end
		DriveController.Exit()
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

return DriveController
