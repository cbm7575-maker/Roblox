-- DriveController (ModuleScript, StarterPlayerScripts.Controllers.DriveController)
-- Drives the car the local player is sitting in (their device owns the car's physics).
-- The physics itself lives in Shared.Util.CarPhysics (also used by the AI police on the server);
-- this controller gathers input, runs the physics every step, and handles the chase camera,
-- wheel visuals and the drive actions (handbrake, nitro, exit, flip).
-- Input: the VehicleSeat's ThrottleFloat/SteerFloat (keyboard, gamepad and touch through Roblox's
-- default controls) unless DriveController.Input overrides them (phone pedals, DriveUI).
-- Crashes (a sudden loss of horizontal speed the brakes and tyres can't explain; landings only lose
-- vertical speed) give a crash sound, a short camera shake and gamepad rumble. The damage itself is
-- the server's (VehicleDamageService); Status.Health / Stalled / Limp mirror the car's state.
-- Getting out: F, gamepad B or EXIT (DriveUI), the same for drivers and passengers. F has two routes on
-- purpose: a ContextActionService action while you sit in any car seat, and a raw keyboard fallback
-- that fires even if something else already handled the key (only a focused text box, i.e. typing in
-- chat, stops it). Each press asks the server (RequestExitCar), once more after 0.8 s if you're still in
-- the same seat; the server answers ExitedCar and this device lets go of the seat as well.
-- Status.Riding = true while you sit as a passenger (DriveUI shows EXIT). A half-second check re-arms
-- driving / riding if a seat change was ever missed (a slow-streaming car, a respawn mid-ride).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local HapticService = game:GetService("HapticService")
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
	Riding = false, -- in a passenger seat (or a driver seat whose car hasn't fully arrived yet)
	Speed = 0, -- studs/s, forward
	MaxSpeed = 0,
	NitroFuel = 1, -- 0..1
	NitroActive = false,
	NitroEmpty = false, -- nitro held but the tank has nothing to give
	Flat = false,
	Health = 100, -- the car's Health attribute (0-100)
	Stalled = false,
	Limp = false,
	Car = nil,
}

local WHEELS = CarPhysics.Wheels
local FRONT = { FL = true, FR = true }
local ACTIONS = { "NC_Handbrake", "NC_Nitro", "NC_Exit", "NC_Flip" }
local CAMERA_STEP = "NC_DriveCamera"

local CRASH_MIN = 8 -- studs/s of unexplained speed loss that counts as a crash
local CRASH_GAP = 0.35 -- seconds between crash effects
local JUMP_STUDS = 5 -- moved this far off its predicted path: a teleport (flip, race reset), not a crash

local state = nil
local exitRemote = nil
local rumbleToken = 0
local ridingSeat = nil -- the seat while Status.Riding
local exitAt, exitSeat = 0, nil -- the last exit request and the seat it was for

local function setRumble(strength)
	local pad = Enum.UserInputType.Gamepad1
	pcall(function()
		if not UserInputService:GetGamepadConnected(pad) or not HapticService:IsMotorSupported(pad, Enum.VibrationMotor.Large) then
			return
		end
		HapticService:SetMotor(pad, Enum.VibrationMotor.Large, strength)
		HapticService:SetMotor(pad, Enum.VibrationMotor.Small, strength * 0.6)
	end)
end

local function rumble(strength)
	rumbleToken += 1
	local token = rumbleToken
	setRumble(strength)
	task.delay(0.12 + 0.25 * strength, function()
		if token == rumbleToken then
			setRumble(0)
		end
	end)
end

-- Sound, shake and rumble for a crash of `hit` studs/s.
local function crash(s, hit)
	s.LastCrash = os.clock()
	local strength = math.clamp(hit / 60, 0.2, 1)
	s.Shake = math.max(s.Shake, strength)
	pcall(function()
		require(script.Parent.SoundClient).Play("Crash", s.Chassis, 0.4 + 0.8 * strength)
	end)
	rumble(strength)
end

-- Did the car just hit something? Compares this step's velocity with the last one.
local function detectCrash(s, phys, dt)
	local chassis = s.Chassis
	local vel = chassis.AssemblyLinearVelocity
	local pos = chassis.Position
	local prevVel, prevPos = s.LastVel, s.LastPos
	s.LastVel, s.LastPos = vel, pos
	if not prevVel or chassis.Anchored then
		return
	end
	if (pos - (prevPos + (prevVel + vel) * (dt / 2))).Magnitude > JUMP_STUDS then
		return -- moved by a script
	end
	local h0 = Vector3.new(prevVel.X, 0, prevVel.Z)
	local h1 = Vector3.new(vel.X, 0, vel.Z)
	local look = chassis.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	local slide = fwd.Magnitude > 0.2 and math.abs(h0:Dot(fwd.Unit:Cross(Vector3.yAxis))) or h0.Magnitude
	local excess = CarPhysics.ImpactExcess(h0.Magnitude, h1.Magnitude, prevVel.Magnitude, vel.Magnitude, slide, dt,
		s.Cfg.Brake or 120, s.Cfg.TireFriction or 1.7, phys.Flat, 2)
	-- A crash can spread over a few steps: add them up, fading fast.
	s.CrashAcc = s.CrashAcc * math.exp(-dt * 10) + excess
	if s.CrashAcc > CRASH_MIN and os.clock() - s.LastCrash > CRASH_GAP then
		crash(s, s.CrashAcc)
		s.CrashAcc = 0
	end
end

local function physicsStep(dt)
	local s = state
	if not s then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not s.Chassis:IsDescendantOf(Workspace) or not hum or hum.SeatPart ~= s.Seat then
		DriveController.Stop()
		return
	end
	local i = DriveController.Input
	local phys = s.Phys
	CarPhysics.Step(phys, dt, {
		Throttle = i.Throttle or s.Seat.ThrottleFloat,
		Steer = i.Steer or s.Seat.SteerFloat,
		Handbrake = i.Handbrake,
		Nitro = i.Nitro,
	})
	detectCrash(s, phys, dt)
	local status = DriveController.Status
	status.Speed = phys.FwdSpeed
	status.MaxSpeed = s.Cfg.MaxSpeed
	status.NitroFuel = phys.NitroFuel
	status.NitroActive = phys.NitroOn
	status.NitroEmpty = phys.NitroEmpty == true
	status.Flat = phys.Flat
	status.Health = phys.Health
	status.Stalled = phys.Stalled
	status.Limp = phys.Limp
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
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	flat = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
	local vel = chassis.AssemblyLinearVelocity
	local velFlat = Vector3.new(vel.X, 0, vel.Z)
	local speedFrac = math.clamp(velFlat.Magnitude / cfg.MaxSpeed, 0, 1.2)

	-- Look slightly along the direction of travel so drifts show the car sliding.
	local dir = flat
	if velFlat.Magnitude > 20 and velFlat.Unit:Dot(flat) > 0.2 then
		dir = (flat * 0.7 + velFlat.Unit * 0.3).Unit
	end
	local dist = 13.5 + speedFrac * 5
	local height = 5.2 + speedFrac * 1.2
	local target = pos - dir * dist + Vector3.new(0, height, 0)
	local lookAt = pos + flat * 8 + Vector3.new(0, 2.2, 0)
	-- Keep the camera out of walls (never people: the ignore list picks up riders who sat down later).
	if os.clock() - (s.CamListAt or 0) > 1 then
		s.CamListAt = os.clock()
		local ignore = { s.Car, Workspace:FindFirstChild("Vehicles"), Workspace:FindFirstChild("Smoke") }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		s.CamParams.FilterDescendantsInstances = ignore
	end
	local toCam = target - lookAt
	local hit = Workspace:Raycast(lookAt, toCam, s.CamParams)
	if hit then
		target = hit.Position - toCam.Unit * 1.2
	end
	-- Stunt jumps: a lazier, wider camera while airborne feels like slow motion.
	local inStunt = player:GetAttribute("InStunt") == true
	local alpha = 1 - math.exp(-dt * (inStunt and 2 or 8))
	s.CamPos = s.CamPos and s.CamPos:Lerp(target, alpha) or target
	camera.CameraType = Enum.CameraType.Scriptable
	-- Crash shake: a short jolt that dies away (never fed back into the camera's own smoothing).
	local shake = CFrame.identity
	if s.Shake > 0.02 then
		s.Shake *= math.exp(-dt * 7)
		local a, t = s.Shake, os.clock() * 37
		shake = CFrame.new(math.noise(t, 0.31) * a * 1.4, math.noise(t, 7.13) * a * 1.1, 0)
			* CFrame.Angles(0, 0, math.noise(t, 13.7) * a * 0.06)
	else
		s.Shake = 0
	end
	camera.CFrame = CFrame.lookAt(s.CamPos, lookAt) * shake
	local fov = 70 + 14 * math.min(speedFrac, 1) + (phys.NitroOn and 8 or 0) + (inStunt and 12 or 0)
	camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-dt * 4))

	-- Wheels: follow the suspension, steer, spin. Mesh bodies can have bigger or smaller wheels than
	-- the physics radius, so each wheel uses its own size (s.WheelR).
	s.Spin = (s.Spin + phys.FwdSpeed / (s.WheelR or cfg.WheelRadius) * dt) % (math.pi * 2)
	for _, name in ipairs(WHEELS) do
		local hub = s.Hubs[name]
		if hub then
			local base = s.WheelBase[name]
			local hitW = phys.Hits[name]
			local r = s.WheelR or cfg.WheelRadius
			local drop = hitW and (hitW.Distance - r) or (cfg.RestLength + cfg.WheelRadius - r)
			local steerAng = FRONT[name] and -phys.Steer * 0.45 or 0
			-- Hub.C0 holds the rest position; Transform adds suspension travel, steering and spin.
			hub.Transform = CFrame.new(0, (s.AttY - drop) - base.Y, 0) * CFrame.Angles(0, steerAng, 0) * CFrame.Angles(-s.Spin, 0, 0)
		end
	end
end

local function onAction(name, inputState)
	if name == "NC_Exit" then
		-- Drivers and passengers alike.
		if inputState == Enum.UserInputState.Begin then
			DriveController.Exit()
		end
		return Enum.ContextActionResult.Sink
	end
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

-- Is this one of our cars' seats (driver or passenger)?
local function carSeat(seat)
	local car = seat and seat.Parent
	return car ~= nil and car:GetAttribute("NCVehicle") == true and (seat:IsA("VehicleSeat") or seat:IsA("Seat"))
end

local function myHumanoid()
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

-- Get out (F / B / EXIT). The server finds the seat, puts you beside the car and answers ExitedCar.
function DriveController.Exit()
	local hum = myHumanoid()
	local seat = hum and hum.SeatPart
	if not hum or not seat or not exitRemote then
		return
	end
	local now = os.clock()
	if now - exitAt < 0.25 then
		return -- one press, two routes (CAS and the keyboard fallback)
	end
	exitAt, exitSeat = now, seat
	exitRemote:FireServer()
	task.delay(0.8, function()
		if exitAt == now and hum.Parent and hum.SeatPart == seat then
			if RunService:IsStudio() then
				warn("[DriveController] still in " .. seat:GetFullName() .. " 0.8 s after asking to get out; asking again")
			end
			exitAt = os.clock()
			exitRemote:FireServer() -- still in the same seat: ask once more
		end
	end)
end

local function startRiding(seat)
	ridingSeat = seat
	DriveController.Status.Riding = true
	ContextActionService:BindActionAtPriority("NC_Exit", onAction, false, 3000, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
end

local function stopRiding()
	if not ridingSeat then
		return
	end
	ridingSeat = nil
	DriveController.Status.Riding = false
	if not state then
		ContextActionService:UnbindAction("NC_Exit")
	end
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
	s.LastVel = nil -- not a crash
end

function DriveController.Start(seat)
	local car = seat.Parent
	if state or not car or not car:GetAttribute("NCVehicle") or not car.PrimaryPart then
		return false
	end
	local chassis = car.PrimaryPart
	if not chassis:FindFirstChild("WheelFL") or not chassis:FindFirstChild("DriveForce") then
		return false -- not all here yet (streaming): refresh() tries again
	end
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

	local s = {
		Car = car,
		Seat = seat,
		Chassis = chassis,
		Cfg = car:GetAttributes(),
		Phys = CarPhysics.New(car, { player.Character }),
		CamParams = camParams,
		Hubs = {},
		WheelBase = {},
		Spin = 0,
		CamPos = nil,
		LastVel = nil,
		LastPos = nil,
		CrashAcc = 0,
		LastCrash = 0,
		Shake = 0,
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
	state = s

	s.PhysicsConn = RunService.PreSimulation:Connect(physicsStep)
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, renderStep)
	ContextActionService:BindActionAtPriority("NC_Handbrake", onAction, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority("NC_Nitro", onAction, false, 3000, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("NC_Exit", onAction, false, 3000, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority("NC_Flip", onAction, false, 3000, Enum.KeyCode.R, Enum.KeyCode.DPadUp)
	-- No jumping while seated: jumping throws the driver out (gamepad A, the phone jump button).
	-- Roblox hides its own jump button when the Jumping state is off. Exit uses F / B / EXIT.
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	DriveController.Status.Driving = true
	DriveController.Status.Car = car
	return true
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
	status.Health, status.Stalled, status.Limp = 100, false, false
	rumbleToken += 1
	setRumble(0)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		camera.CameraSubject = hum
	end
end

-- Match driving / riding to the seat the character is in now. Always stop first, so switching straight
-- from one seat to another (or a respawn) can't leave stale state.
local function refresh()
	local hum = myHumanoid()
	local seat = hum and hum.Health > 0 and hum.SeatPart or nil
	if state and seat == state.Seat then
		return
	end
	if ridingSeat and seat == ridingSeat and not (seat:IsA("VehicleSeat") and seat.Name == "DriverSeat") then
		return
	end
	DriveController.Stop()
	stopRiding()
	if seat and seat:IsA("VehicleSeat") and seat.Name == "DriverSeat" then
		if DriveController.Start(seat) then
			return
		end
		if RunService:IsStudio() then
			warn("[DriveController] driver seat of " .. tostring(seat.Parent) .. " but the car isn't ready to drive yet; F / EXIT still work")
		end
	end
	if seat and carSeat(seat) then
		startRiding(seat) -- a passenger (or a driver whose car is still streaming in): F / EXIT still work
	end
end

-- The server let go of us (any seat): make sure this device does too.
local function onExited(spot)
	local hum = myHumanoid()
	if not hum then
		return
	end
	local seat = hum.SeatPart
	local asked = seat ~= nil and seat == exitSeat
	if seat and not asked then
		return -- already in another seat (put out of one car, straight into the next)
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if seat and root and root:IsA("BasePart") then
		for _, j in ipairs(root:GetJoints()) do
			if j:IsA("JointInstance") and j.Name == "SeatWeld" then
				j:Destroy()
			end
		end
	end
	hum.Sit = false
	if hum:GetState() == Enum.HumanoidStateType.Seated then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if asked and root and root:IsA("BasePart") and typeof(spot) == "CFrame" and (root.Position - spot.Position).Magnitude > 4 then
		root.CFrame = spot
	end
	exitSeat = nil
	refresh()
end

local function watchCharacter(character)
	local hum = character:WaitForChild("Humanoid")
	hum:GetPropertyChangedSignal("SeatPart"):Connect(refresh)
	hum.Died:Connect(function()
		DriveController.Stop()
		stopRiding()
	end)
	refresh()
end

function DriveController.Init()
	exitRemote = Remotes.Event("RequestExitCar")
	Remotes.OnClient("ExitedCar", onExited)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	-- Keyboard fallback for F: fires even when another binding or a prompt already took the key; not
	-- while typing in a text box (chat).
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.F or UserInputService:GetFocusedTextBox() then
			return
		end
		local hum = myHumanoid()
		if hum and carSeat(hum.SeatPart) then
			DriveController.Exit()
		end
	end)
	-- Safety net: twice a second, re-arm driving / riding if a seat change was missed.
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + 0.5
		local hum = myHumanoid()
		local seat = hum and hum.Health > 0 and hum.SeatPart or nil
		local want = seat ~= nil and carSeat(seat)
		local have = (state ~= nil and state.Seat == seat) or (ridingSeat ~= nil and ridingSeat == seat)
		if want ~= have or (ridingSeat and seat == ridingSeat and seat:IsA("VehicleSeat") and seat.Name == "DriverSeat") then
			local ok, err = pcall(refresh)
			if not ok then
				warn("[DriveController] " .. tostring(err))
			end
		end
	end)
end

return DriveController
