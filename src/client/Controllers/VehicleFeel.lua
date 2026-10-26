-- VehicleFeel (ModuleScript, StarterPlayerScripts.Controllers.VehicleFeel)
-- Cars that move and light up like a console game. Looks only, all on this device: nothing here touches
-- the physics, the camera or the server.
--   * Body lean: every land car has a "BodyRoot" part joined to its chassis by the Motor6D "BodyJoint"
--     (CarBuilder.AddBodyJoint), carrying everything you only look at. For the nearest cars (MAX_BODIES,
--     fewer in Performance mode) BodyJoint.Transform is set every frame from three damped springs
--     (2.5 Hz, damping 0.55: one overshoot, settled in about half a second):
--       roll    out of a corner, from the sideways pull (turn rate x speed), up to 4 degrees
--       pitch   nose down under braking, tail down pulling away, from how the forward speed changes, up
--               to 2.5 degrees
--       heave   one bounce when the chassis is jolted up or down harder than gravity (a kerb, a landing)
--     Your own car reads DriveController.Status; other cars are judged by their chassis' motion (smoothed
--     harder, since it arrives in network steps). The chase camera follows the chassis, so the body
--     visibly moves inside a steady picture. Cars without the joint (boats, older models) are left alone.
--     A model's attribute BodyLean (0-1) scales the lean (bodies with their tyres baked in get less).
--   * Lights (parts named Headlight / Taillight, any car in Workspace.Vehicles):
--       in the dark (Workspace attribute IsNight, or Raining) a car that is being driven, or was until
--       LIGHTS_LINGER seconds ago, has glowing warm-white headlights and dim red taillights; parked cars
--       and daylight leave them unlit.
--       Brake lights (day or night): bright red while the car brakes. Your own car: the pedal against the
--       motion, or the handbrake (DriveController.Status / Input). Other cars: losing speed quickly.
--       Reverse: the taillights turn white while the car backs up.
--       Real light: only the MAX_BEAMS nearest lit cars get a SpotLight (one wide beam from between the
--       headlights, no shadows); the rest just glow.
--       Police light bars (LightBarRed / LightBarBlue): steady as built, and flashing red / blue in turn
--       while the siren is on (car attribute Siren, or an AI patrol with a target: the same test
--       SoundClient uses for the siren's sound, which is not touched here). The nearest of them also throw
--       a coloured PointLight at night.
--   * Driver pose (cars within POSE_RANGE): the driver's hands follow the steering and the local driver's
--     head follows the camera. Uses PoseClient when that controller exists (looked for softly, every few
--     seconds until found; it must be started by ClientMain to draw anything):
--       PoseClient.Play(character, "DriverHands", { Steer = n, Speed = studs/s })   both Set every frame
--       PoseClient.Play(character, "LookAt", { Yaw = degrees, Pitch = degrees, MaxYaw = 110 })   the local
--         driver only: where the camera looks, seen from the car (left is positive), Set every frame
--     Each returns a handle with :Set(key, value), :Stop(fade) and :IsPlaying(). Without PoseClient (or
--     when it can't pose that body, or a call fails) a simple pose of our own: arms forward and turning
--     with the wheel, the waist leaning into the corner, the neck toward the camera. Ours is written as
--     joint Transforms after the animations each frame (PreSimulation), for Motor6D and
--     AnimationConstraint joints alike, and never onto a joint PoseClient is posing for us.
--   * VehicleFeel.Overlay: a small pose layer for the LOCAL character, for InteractClient's getting in
--     and out. Set the numbers, they are drawn every frame:
--       Reach   0-1  one hand out toward a door handle, and a slight lean. With PoseClient and a Target
--                    the arm is its "Point" pose ({ Point = Target, Hand = "Right" | "Left" }, stopped
--                    when Reach starts to fall); otherwise the arm is simply raised forward.
--       Side    1 = right hand, -1 = left
--       Target  world point the hand reaches for (optional)
--       Duck    0-1  bent forward at the waist and hips (ducking through a door, or straightening up
--                    after stepping out)
--     With PoseClient the lean and the duck are drawn by a pose of ours registered into it ("CarDuck",
--     PoseClient.Register, settings Bend / Tip in radians), so it alone writes those joints; without it
--     we turn the waist and hips ourselves.
-- Other controllers:
--   VehicleFeel.Init()                       starts it (safe to call twice; InteractClient calls it too)
--   VehicleFeel.Lean(car) -> roll, pitch, heave   the body's lean right now (radians, radians, studs)
--   VehicleFeel.Kick(car, pitch, roll, heave)     nudge a car's body springs (radians/s, radians/s,
--                                                 studs/s): a gear change, a crash, a landing
--   VehicleFeel.IsBraking(car) -> bool            are its brake lights on (nearest cars only)?
--   VehicleFeel.LightsOn(car) -> bool             are its headlights on?

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local VehicleFeel = {}

VehicleFeel.Overlay = {
	Reach = 0,
	Side = 1,
	Target = nil,
	Duck = 0,
}

-- How many cars get the full treatment (nearest to the camera first).
local MAX_BODIES, MAX_BODIES_PERF = 10, 5 -- body lean, brake lights, driver pose
local MAX_BEAMS, MAX_BEAMS_PERF = 6, 3 -- real headlight beams
local BODY_RANGE = 260 -- studs from the camera
local BEAM_RANGE = 300
local LIGHT_RANGE = 450 -- lamps of cars further than this are left as they are
local POSE_RANGE = 110 -- nobody can see a driver's hands from further away
local SCAN_EVERY = 0.25 -- seconds between looks at which cars are near

-- Body springs.
local SPRING = 2 * math.pi * 2.5 -- rad/s
local SPRING2 = SPRING * SPRING
local DAMP2 = 2 * 0.55 * SPRING
local ROLL_MAX = math.rad(4)
local PITCH_MAX = math.rad(2.5)
local ROLL_GAIN = math.rad(4) / 90 -- full roll at 90 studs/s^2 of sideways pull
local PITCH_GAIN = math.rad(2.5) / 110 -- full nose-dive at 110 studs/s^2 of braking
local HEAVE_MAX = 0.32 -- studs the body may ride up or down on its springs
local JOLT, JOLT_FAR = 230, 420 -- studs/s^2: a vertical jolt harder than this bounces the body (others' cars: noisier)
local JOLT_GAIN = 0.6
local JOLT_CAP = 8 -- studs/s: the most one frame's jolt counts for
local MAX_STEP = 1 / 30

-- Lights.
local LIGHTS_LINGER = 12 -- seconds a car's lights stay on after its driver gets out
local BRAKE_DECEL = 18 -- studs/s^2: another car losing speed faster than this is braking (coasting loses 10)
local BRAKE_HOLD = 0.25 -- seconds its brake lights stay on after that (no flicker)
local FLASH_RATE = 5 -- light bar swaps per second
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local HEAD_ON = Color3.fromRGB(255, 244, 214)
local HEAD_OFF = Color3.fromRGB(214, 216, 220)
local TAIL_OFF = Color3.fromRGB(128, 20, 30)
local TAIL_DIM = Color3.fromRGB(135, 16, 26)
local TAIL_BRAKE = Color3.fromRGB(255, 30, 42)
local TAIL_REVERSE = Color3.fromRGB(250, 248, 240)
local BAR_RED = Color3.fromRGB(255, 50, 60)
local BAR_BLUE = Color3.fromRGB(60, 120, 255)

-- Driver pose (our own, when PoseClient isn't there): radians.
local ARM_UP = math.rad(58) -- upper arms forward, to the wheel
local ARM_IN = math.rad(11) -- ...and a little toward each other
local ARM_STEER = math.rad(16) -- one hand down, the other up, at full lock
local ELBOW = math.rad(20)
local WAIST_STEER = math.rad(6) -- leaning into the turn at full lock
local NECK_MAX = math.rad(70)
-- Getting in and out (VehicleFeel.Overlay).
local REACH_ARM = math.rad(62)
local REACH_IN = math.rad(8)
local REACH_ELBOW = math.rad(14)
local REACH_LEAN = math.rad(9)
local DUCK_LEAN = math.rad(26)
local DUCK_TIP = math.rad(8)

-- PoseClient's pose names (see the header), and the one we add to it ourselves (registerDuck).
local POSE_HANDS, POSE_LOOK, POSE_REACH = "DriverHands", "LookAt", "Point"
local POSE_DUCK = "CarDuck"
local LOOK_MAX_YAW = 110 -- degrees the driver's head (and then chest) may turn after the camera
local LOOK_PITCH_SHARE = 0.5 -- the chase camera looks down at the car: the head follows only this much of that

local IDENTITY = CFrame.identity

local DriveController = { Status = {}, Input = {} } -- the real one is required in Init
local SettingsClient = nil
local PoseClient = nil -- found by findPoseClient
local poseCheckedAt = -math.huge
local poseBroken = {} -- [pose name] = true: PoseClient refused it once, so our own pose is used from then on

local started = false
local night, raining = false, false
local recs = {} -- [car Model] = record (strong keys: dropped by scan when the car is gone)
local order = {} -- scratch: every record, nearest first
local active = {} -- the nearest MAX_BODIES records, for the per-frame work
local rigs = {} -- [character Model] = its joints (dropped by scan when the character is gone)
local scanAccum = SCAN_EVERY
local lastWarn = 0

local overlayOn = false -- VehicleFeel.Overlay is being drawn...
local overlayChar = nil -- ...on this character
local overlayRig = nil -- its joints, once we have turned one ourselves (to let them go afterwards)
local reachHandle = nil -- PoseClient's handle for the reaching arm, while it reaches
local reachSpent = false -- that arm has been let go and is fading out (until Reach is back at 0)
local lastReach = 0 -- Overlay.Reach last frame (to see it start falling)
local duckHandle = nil -- PoseClient's handle for our "CarDuck" pose, while it plays
local duckOwn = false -- no PoseClient for it this time: we turn the waist and hips ourselves

------------------------------------------------------------------ poses on joints

-- R15 joints by the part they live in. Under the Avatar Joint Upgrade they are AnimationConstraints
-- instead of Motor6Ds; both have a Transform the animations write, which is all we use.
local JOINTS = {
	waist = { "UpperTorso", "Waist" },
	neck = { "Head", "Neck" },
	root = { "LowerTorso", "Root" },
	rs = { "RightUpperArm", "RightShoulder" },
	ls = { "LeftUpperArm", "LeftShoulder" },
	re = { "RightLowerArm", "RightElbow" },
	le = { "LeftLowerArm", "LeftElbow" },
}

local function jointOf(char, partName, jointName)
	local part = char:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and (joint:IsA("Motor6D") or joint.ClassName == "AnimationConstraint") then
		return joint
	end
	return nil
end

-- A character's joints, found once (nil until its body has arrived, or if it isn't an R15 body).
local function rigOf(char)
	local rig = rigs[char]
	if rig then
		return rig
	end
	local waist = jointOf(char, "UpperTorso", "Waist")
	if not waist then
		return nil
	end
	rig = { last = {}, base = {} }
	for key, path in pairs(JOINTS) do
		rig[key] = jointOf(char, path[1], path[2])
	end
	rigs[char] = rig
	return rig
end

-- Turn one joint by `offset` on top of whatever the animations gave it this frame. The animations write a
-- joint's Transform before PreSimulation, but only for joints they move: one they leave alone still holds
-- what we wrote last frame, so that case is recognised (the value is still exactly ours) and the offset is
-- applied to the same base again instead of piling up.
local function turn(rig, key, offset)
	local joint = rig[key]
	if not joint then
		return
	end
	local now = joint.Transform
	local base = now
	if now == rig.last[key] then
		base = rig.base[key]
	end
	local out = base * offset
	joint.Transform = out
	rig.base[key] = base
	rig.last[key] = out
end

-- Let go of every joint we were turning: one that nothing else has written since goes back to its base.
local function letGo(rig)
	for key, last in pairs(rig.last) do
		local joint = rig[key]
		if joint and joint.Parent and joint.Transform == last then
			joint.Transform = rig.base[key]
		end
	end
	table.clear(rig.last)
	table.clear(rig.base)
end

-- Our own pose inside PoseClient: the lean and the duck of getting in (VehicleFeel.Overlay), so that with
-- PoseClient there, it alone writes those joints. Settings: Bend (radians forward at the waist), Tip
-- (radians forward from the hips). Written with PoseClient.Kit, as its own poses are.
local function registerDuck()
	local kit = PoseClient.Kit
	local joint = type(kit) == "table" and kit.Joint or nil
	if type(PoseClient.Register) ~= "function" or type(joint) ~= "table" or type(kit.add) ~= "function"
		or not joint.Waist or not joint.Root then
		poseBroken[POSE_DUCK] = true
		return
	end
	local add, waist, root = kit.add, joint.Waist, joint.Root
	local ok, done = pcall(PoseClient.Register, POSE_DUCK, {
		FadeIn = 0, FadeOut = 0.08, Priority = 40,
		Body = function(c, st, w)
			local bend, tip = tonumber(st.p.Bend) or 0, tonumber(st.p.Tip) or 0
			if bend == bend and bend ~= 0 then
				add(c, waist, CFrame.Angles(-bend, 0, 0), w)
			end
			if tip == tip and tip ~= 0 then
				add(c, root, CFrame.Angles(-tip, 0, 0), w)
			end
		end,
	})
	if not ok or done == false then
		poseBroken[POSE_DUCK] = true
	end
end

-- PoseClient, once it exists (another controller, written separately; it may not be there at all).
local function findPoseClient(now)
	if PoseClient or now - poseCheckedAt < 3 then
		return
	end
	poseCheckedAt = now
	local module = script.Parent:FindFirstChild("PoseClient")
	if not module then
		return
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" and type(mod.Play) == "function" then
		PoseClient = mod
		registerDuck()
	end
end

-- Start one of PoseClient's poses. Returns its handle, or nil when PoseClient isn't there, can't pose
-- this body (it then hands back a handle that isn't playing: not an R15 body, not in the world yet) or
-- the call went wrong (that pose is then never asked for again). nil means: use our own pose.
local function playPose(char, name, params)
	if not PoseClient or poseBroken[name] then
		return nil
	end
	local ok, handle = pcall(PoseClient.Play, char, name, params)
	if not ok or type(handle) ~= "table" or type(handle.Set) ~= "function" or type(handle.Stop) ~= "function" then
		poseBroken[name] = true
		return nil
	end
	if type(handle.IsPlaying) == "function" then
		local okPlaying, playing = pcall(handle.IsPlaying, handle)
		if okPlaying and playing ~= true then
			return nil
		end
	end
	return handle
end

local function stopPose(handle, fade)
	if handle then
		pcall(handle.Stop, handle, fade)
	end
end

------------------------------------------------------------------ records

local function newRec(car, chassis)
	return {
		car = car,
		chassis = chassis,
		seat = nil, -- DriverSeat, found by scan
		joint = nil, -- BodyJoint; false = looked several times, this car has none
		jointTries = 0,
		lean = 1,
		steerRate = 1.9,
		dist = math.huge,
		active = false,
		fresh = true, -- no last frame to compare with yet
		resting = true, -- the joint sits at identity and nothing is moving
		roll = 0, rollV = 0, pitch = 0, pitchV = 0, heave = 0, heaveV = 0,
		fwd = 0, lastFwd = 0, lastVy = 0, accel = 0,
		steer = 0,
		driven = false, drivenAt = -math.huge, siren = false,
		braking = false, brakeUntil = 0,
		lamps = false, -- lamp lists found?
		heads = nil, tails = nil, bars = nil,
		headOn = nil, tailMode = nil, barPhase = nil,
		beam = nil, beamOn = false, barLight = nil,
		pose = nil, -- { hum, char, hands, look, rig } while a driver is posed
	}
end

local function endPose(rec)
	local pose = rec.pose
	if not pose then
		return
	end
	rec.pose = nil
	stopPose(pose.hands, 0.2)
	stopPose(pose.look, 0.2)
	if pose.rig then
		letGo(pose.rig)
	end
end

-- Back to rest: the body level, the springs still, the driver's pose let go.
local function settle(rec)
	rec.roll, rec.rollV, rec.pitch, rec.pitchV, rec.heave, rec.heaveV = 0, 0, 0, 0, 0, 0
	rec.accel, rec.fresh, rec.braking, rec.brakeUntil = 0, true, false, 0
	local joint = rec.joint
	if joint and joint.Parent and not rec.resting then
		joint.Transform = IDENTITY
	end
	rec.resting = true
	endPose(rec)
end

------------------------------------------------------------------ lights

-- A car's lamps, found once: { part, off material, off colour } for Headlight / Taillight parts you can
-- see (a mesh body hides the greybox ones), and its light bar halves with the look they were built with.
local function findLamps(rec)
	rec.lamps = true
	local heads, tails, bars = {}, {}, {}
	for _, d in ipairs(rec.car:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local name = d.Name
			if name == "Headlight" or name == "Taillight" then
				-- Unlit: the look it came with, unless that already glows (CarBuilder builds lamps lit).
				local glows = d.Material == NEON
				local lamp = {
					part = d,
					material = glows and PLASTIC or d.Material,
					color = glows and (name == "Headlight" and HEAD_OFF or TAIL_OFF) or d.Color,
				}
				table.insert(name == "Headlight" and heads or tails, lamp)
			elseif name == "LightBarRed" or name == "LightBarBlue" then
				local c = d.Color
				table.insert(bars, {
					part = d, material = d.Material, color = c, red = name == "LightBarRed",
					dark = Color3.new(c.R * 0.3, c.G * 0.3, c.B * 0.3),
				})
			end
		end
	end
	rec.heads, rec.tails, rec.bars = heads, tails, bars
end

local function look(part, material, color)
	if part.Material ~= material then
		part.Material = material
	end
	if part.Color ~= color then
		part.Color = color
	end
end

local function setHeads(rec, on)
	rec.headOn = on
	for _, lamp in ipairs(rec.heads) do
		if on then
			look(lamp.part, NEON, HEAD_ON)
		else
			look(lamp.part, lamp.material, lamp.color)
		end
	end
end

local function setTails(rec, mode)
	rec.tailMode = mode
	for _, lamp in ipairs(rec.tails) do
		if mode == "brake" then
			look(lamp.part, NEON, TAIL_BRAKE)
		elseif mode == "reverse" then
			look(lamp.part, NEON, TAIL_REVERSE)
		elseif mode == "dim" then
			look(lamp.part, NEON, TAIL_DIM)
		else
			look(lamp.part, lamp.material, lamp.color)
		end
	end
end

-- Light bar: phase 0 = steady as built, 1 = red lit / blue dark, 2 = the other way round.
local function setBars(rec, phase)
	rec.barPhase = phase
	for _, bar in ipairs(rec.bars) do
		local lit = phase == 0 or (phase == 1) == bar.red
		if lit then
			look(bar.part, bar.material, bar.color)
		else
			look(bar.part, PLASTIC, bar.dark)
		end
	end
	local glow = rec.barLight
	if glow then
		local on = phase ~= 0 and rec.beamOn
		if glow.Enabled ~= on then
			glow.Enabled = on
		end
		if on then
			glow.Color = phase == 1 and BAR_RED or BAR_BLUE
		end
	end
end

-- One wide beam from between the headlights, on the body (so it dips with the nose). Made the first time
-- this car is one of the nearest lit ones; switched off, not destroyed, when it isn't.
local function makeBeam(rec)
	local chassis = rec.chassis
	local joint = rec.joint
	local host = (joint and joint.Part1) or chassis
	local pos = Vector3.new(0, 0.2, -chassis.Size.Z / 2 - 0.5)
	if #rec.heads > 0 then
		local sum = Vector3.zero
		for _, lamp in ipairs(rec.heads) do
			sum += chassis.CFrame:PointToObjectSpace(lamp.part.Position)
		end
		local mid = sum / #rec.heads
		pos = Vector3.new(0, mid.Y, mid.Z - 0.4)
	end
	local att = Instance.new("Attachment")
	att.Name = "NCHeadBeam"
	att.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(-5), 0, 0) -- looking ahead (-Z), a little down
	att.Parent = host
	local beam = Instance.new("SpotLight")
	beam.Name = "Beam"
	beam.Face = Enum.NormalId.Front
	beam.Angle = 78
	beam.Range = 64
	beam.Brightness = 2.4
	beam.Color = HEAD_ON
	beam.Shadows = false
	beam.Enabled = false
	beam.Parent = att
	rec.beam = beam
	-- Police: a glow from the light bar too (coloured and switched by setBars).
	local bar = rec.bars[1]
	if bar then
		local glow = Instance.new("PointLight")
		glow.Name = "NCBarGlow"
		glow.Range = 26
		glow.Brightness = 2.2
		glow.Shadows = false
		glow.Enabled = false
		glow.Parent = bar.part
		rec.barLight = glow
	end
end

local function setBeam(rec, on)
	if on and not rec.beam then
		makeBeam(rec)
	end
	rec.beamOn = on
	local beam = rec.beam
	if beam and beam.Enabled ~= on then
		beam.Enabled = on
	end
	if not on and rec.barLight and rec.barLight.Enabled then
		rec.barLight.Enabled = false
	end
end

-- Your own car's gas pedal, -1..1 (DriveController.Status.Throttle, else the phone pedals, else the seat).
local function ownThrottle(status, rec)
	local t = status.Throttle
	if type(t) == "number" then
		return t
	end
	t = DriveController.Input.Throttle
	if type(t) == "number" then
		return t
	end
	local seat = rec.seat
	return (seat and seat:IsA("VehicleSeat")) and seat.ThrottleFloat or 0
end

-- Work out one car's lamps and switch whichever changed. near: one of the nearest cars (brake and
-- reverse lights are judged every frame); far cars only glow or don't. status: DriveController.Status
-- when this is the car you are driving.
local function lights(rec, now, near, status, dark)
	if not rec.lamps then
		findLamps(rec)
	end
	local on = dark and (rec.driven or now - rec.drivenAt < LIGHTS_LINGER)
	local braking, reversing = false, false
	if near then
		if status then
			local throttle = ownThrottle(status, rec)
			local speed = type(status.Speed) == "number" and status.Speed or rec.fwd
			-- The pedal against the motion (either way), or the handbrake while rolling.
			braking = (throttle < -0.1 and speed > 2) or (throttle > 0.1 and speed < -2)
				or (DriveController.Input.Handbrake == true and math.abs(speed) > 2)
			reversing = speed < -1.5 and throttle < -0.05
		elseif rec.driven then
			if rec.accel < -BRAKE_DECEL and rec.fwd > 3 then
				rec.brakeUntil = now + BRAKE_HOLD
			end
			braking = now < rec.brakeUntil
			reversing = rec.fwd < -3
		end
	end
	rec.braking = braking
	if on ~= rec.headOn then
		setHeads(rec, on)
	end
	local mode = reversing and "reverse" or (braking and "brake" or (on and "dim" or "off"))
	if mode ~= rec.tailMode then
		setTails(rec, mode)
	end
	if #rec.bars > 0 then
		local phase = 0
		if rec.siren then
			phase = math.floor(now * FLASH_RATE) % 2 + 1
		end
		if phase ~= rec.barPhase then
			setBars(rec, phase)
		end
	end
end

------------------------------------------------------------------ body lean

-- One frame of a car's body springs. real: the time since the last frame, as it really was (a slow frame
-- is a long one: dividing a change in speed by anything shorter would read as a harder brake or a
-- harder bump than there was, and gravity alone would look like a kerb on a phone at 20 frames a second).
-- own: the car you are driving (its motion is exact here; other cars' arrives in network steps and is
-- smoothed harder).
local function body(rec, real, own)
	local chassis = rec.chassis
	local cf = chassis.CFrame
	local vel = chassis.AssemblyLinearVelocity
	local up = cf.UpVector
	local fwd = vel:Dot(cf.LookVector)
	local vy = vel.Y
	if rec.fresh then
		rec.fresh = false
		rec.lastFwd, rec.lastVy, rec.accel = fwd, vy, 0
	end
	local gain = math.clamp((fwd - rec.lastFwd) / real, -400, 400)
	local jolt = (vy - rec.lastVy) / real
	rec.lastFwd, rec.lastVy, rec.fwd = fwd, vy, fwd
	rec.accel += (gain - rec.accel) * (1 - math.exp(-real * (own and 16 or 8)))

	local joint = rec.joint
	if not joint then
		return
	end
	local lean = rec.lean
	local wantRoll, wantPitch = 0, 0
	if up.Y > 0.5 then -- (on its side or its roof there is nothing to lean against)
		-- Turning right pulls the car to its right (turn rate x speed): the body rolls out, to the left,
		-- which is a positive angle about the car's length. Speeding up lifts the nose (positive), braking
		-- drops it.
		local pull = -chassis.AssemblyAngularVelocity:Dot(up) * fwd
		wantRoll = math.clamp(pull * ROLL_GAIN, -ROLL_MAX, ROLL_MAX) * lean
		wantPitch = math.clamp(rec.accel * PITCH_GAIN, -PITCH_MAX, PITCH_MAX) * lean
	end
	-- A jolt up leaves the body behind for a moment (it sinks on its springs, then comes back once).
	local hard = math.abs(jolt) - (own and JOLT or JOLT_FAR)
	if hard > 0 then
		local kick = math.min(hard * real, JOLT_CAP) * JOLT_GAIN * lean
		rec.heaveV -= jolt > 0 and kick or -kick
	end

	-- The springs are stepped in pieces of MAX_STEP at most (a longer step would overshoot and ring); a
	-- slow frame takes a few of them, a long hitch four and no more (the body just catches up later).
	local steps = math.clamp(math.ceil(real / MAX_STEP - 0.001), 1, 4)
	local dt = math.min(real / steps, MAX_STEP)
	local roll, rollV = rec.roll, rec.rollV
	local pitch, pitchV = rec.pitch, rec.pitchV
	local heave, heaveV = rec.heave, rec.heaveV
	for _ = 1, steps do
		rollV += (SPRING2 * (wantRoll - roll) - DAMP2 * rollV) * dt
		roll += rollV * dt
		pitchV += (SPRING2 * (wantPitch - pitch) - DAMP2 * pitchV) * dt
		pitch += pitchV * dt
		heaveV += (-SPRING2 * heave - DAMP2 * heaveV) * dt
		heave += heaveV * dt
		if heave > HEAVE_MAX then
			heave, heaveV = HEAVE_MAX, math.min(heaveV, 0)
		elseif heave < -HEAVE_MAX then
			heave, heaveV = -HEAVE_MAX, math.max(heaveV, 0)
		end
	end
	-- (a kick from outside must never tip the body further than a hard corner would)
	roll = math.clamp(roll, -ROLL_MAX * 1.6, ROLL_MAX * 1.6)
	pitch = math.clamp(pitch, -PITCH_MAX * 1.8, PITCH_MAX * 1.8)
	rec.roll, rec.rollV, rec.pitch, rec.pitchV, rec.heave, rec.heaveV = roll, rollV, pitch, pitchV, heave, heaveV

	-- Standing still and level: write the rest pose once, then nothing until something moves.
	if math.abs(roll) < 1e-4 and math.abs(pitch) < 1e-4 and math.abs(heave) < 1e-3
		and math.abs(rollV) < 1e-3 and math.abs(pitchV) < 1e-3 and math.abs(heaveV) < 1e-2 then
		if not rec.resting then
			rec.resting = true
			joint.Transform = IDENTITY
		end
	else
		rec.resting = false
		joint.Transform = CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, roll)
	end
end

------------------------------------------------------------------ which cars

local function byDistance(a, b)
	return a.dist < b.dist
end

local function performance()
	if SettingsClient == nil then
		local module = script.Parent:FindFirstChild("SettingsClient")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		SettingsClient = ok and type(mod) == "table" and mod or false
	end
	if not SettingsClient or type(SettingsClient.Get) ~= "function" then
		return false
	end
	local ok, on = pcall(SettingsClient.Get, "Performance")
	return ok and on == true
end

-- Four times a second: which cars exist, how far they are, who gets the per-frame work and the beams.
local function scan(now)
	local folder = Workspace:FindFirstChild("Vehicles")
	local camera = Workspace.CurrentCamera
	if not folder or not camera then
		return
	end
	findPoseClient(now)
	local camPos = camera.CFrame.Position
	for _, car in ipairs(folder:GetChildren()) do
		if not recs[car] and car:IsA("Model") and car.PrimaryPart then
			recs[car] = newRec(car, car.PrimaryPart)
		end
	end
	table.clear(order)
	for car, rec in pairs(recs) do
		local chassis = car.PrimaryPart
		if car.Parent ~= folder or not chassis then
			-- Gone (our lights went with it), or no longer a car on the road.
			endPose(rec)
			if car.Parent then
				settle(rec)
				if rec.beam and rec.beam.Parent then
					rec.beam.Parent:Destroy() -- the attachment and its light
				end
				if rec.barLight then
					rec.barLight:Destroy()
				end
			end
			recs[car] = nil
		else
			rec.chassis = chassis
			rec.dist = (chassis.Position - camPos).Magnitude
			if rec.joint == nil then
				local root = car:FindFirstChild("BodyRoot")
				local joint = root and root:FindFirstChild("BodyJoint")
				if joint and joint:IsA("Motor6D") then
					rec.joint = joint
					local lean = car:GetAttribute("BodyLean")
					rec.lean = type(lean) == "number" and math.clamp(lean, 0, 1) or 1
				else
					rec.jointTries += 1
					if rec.jointTries > 20 then
						rec.joint = false -- a boat, or a car from before body joints: stop looking
					end
				end
			end
			if not rec.seat or rec.seat.Parent ~= car then
				local seat = car:FindFirstChild("DriverSeat")
				rec.seat = (seat and (seat:IsA("VehicleSeat") or seat:IsA("Seat"))) and seat or nil
				local rate = car:GetAttribute("SteerRate")
				rec.steerRate = type(rate) == "number" and rate > 0.1 and rate or 1.9
			end
			local ai = car:GetAttribute("AIPolice") == true
			rec.driven = ai or car:GetAttribute("DriverUserId") ~= nil
			if rec.driven then
				rec.drivenAt = now
			end
			rec.siren = car:GetAttribute("Siren") == true or (ai and car:GetAttribute("AITarget") ~= nil)
			table.insert(order, rec)
		end
	end
	table.sort(order, byDistance)
	local perf = performance()
	local maxBodies = perf and MAX_BODIES_PERF or MAX_BODIES
	local maxBeams = perf and MAX_BEAMS_PERF or MAX_BEAMS
	local dark = night or raining
	local beams = 0
	table.clear(active)
	for i, rec in ipairs(order) do
		local near = i <= maxBodies and rec.dist < BODY_RANGE
		if near then
			if not rec.active then
				rec.active = true
				rec.fresh = true
			end
			table.insert(active, rec)
		else
			if rec.active then
				rec.active = false
				settle(rec)
			end
			if rec.dist < LIGHT_RANGE then
				lights(rec, now, false, nil, dark) -- far cars: glow or not, at this slower pace
			end
		end
		local beam = rec.headOn == true and beams < maxBeams and rec.dist < BEAM_RANGE
		if beam then
			beams += 1
		end
		if beam ~= rec.beamOn then
			setBeam(rec, beam)
		end
	end
	-- Characters that left: forget their joints.
	for char in pairs(rigs) do
		if not char.Parent then
			rigs[char] = nil
		end
	end
end

------------------------------------------------------------------ every frame

local function frame(dt)
	local now = os.clock()
	scanAccum += dt
	if scanAccum >= SCAN_EVERY then
		scanAccum = 0
		scan(now)
	end
	local status = DriveController.Status
	local ownCar = status.Driving and status.Car or nil
	-- (the frame's real length, however long: body() only ever divides by it and caps what it steps)
	local real = math.max(dt, 1 / 240)
	local dark = night or raining
	for _, rec in ipairs(active) do
		if rec.chassis.Parent then -- (destroyed since the last scan: the next scan drops it)
			local own = rec.car == ownCar
			body(rec, real, own)
			lights(rec, now, true, own and status or nil, dark)
		end
	end
end

-- The steering of the car you drive, -1..1 (right is positive), or nil when this device can't tell.
local function ownSteer(status, seat)
	local s = status.Steer
	if type(s) == "number" then
		return s
	end
	s = DriveController.Input.Steer
	if type(s) == "number" then
		return s
	end
	if seat and seat:IsA("VehicleSeat") and seat.SteerFloat ~= 0 then
		return seat.SteerFloat
	end
	return nil
end

-- One driver's pose for this frame.
local function driverPose(rec, hum, own, status, camera, dt)
	local char = hum.Parent
	if not char then
		return
	end
	local pose = rec.pose
	if not pose then
		pose = { hum = hum, char = char }
		pose.hands = playPose(char, POSE_HANDS, { Steer = rec.steer, Speed = rec.fwd })
		if own and camera then
			pose.look = playPose(char, POSE_LOOK, { Yaw = 0, Pitch = 0, MaxYaw = LOOK_MAX_YAW })
		end
		rec.pose = pose
	end
	-- How far the wheel is turned: the real input for your own car, else read off how the car turns.
	local chassis = rec.chassis
	local want = own and ownSteer(status, rec.seat) or nil
	if not want then
		want = math.clamp(-chassis.AssemblyAngularVelocity:Dot(chassis.CFrame.UpVector) / rec.steerRate, -1, 1)
		if rec.fwd < -1 then
			want = -want -- backing up, the car turns the other way for the same wheel
		end
	end
	rec.steer += (want - rec.steer) * (1 - math.exp(-dt * 10))
	local steer = rec.steer

	-- (Speed lets PoseClient's driver fidget only while the car stands still.)
	local hands = pose.hands
	if hands and not (pcall(hands.Set, hands, "Steer", steer) and pcall(hands.Set, hands, "Speed", rec.fwd)) then
		poseBroken[POSE_HANDS] = true
		stopPose(hands, 0)
		pose.hands = nil
	end
	-- Where the camera looks, seen from the car: a heading (0 straight ahead, growing to the left) and
	-- how far up. Your own car only.
	local yaw, pitch = nil, 0
	if own and camera then
		local dir = chassis.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
		yaw = math.atan2(-dir.X, -dir.Z)
		pitch = math.asin(math.clamp(dir.Y, -1, 1)) * LOOK_PITCH_SHARE
	end
	local look = pose.look
	if look and yaw and not (pcall(look.Set, look, "Yaw", math.deg(yaw)) and pcall(look.Set, look, "Pitch", math.deg(pitch))) then
		poseBroken[POSE_LOOK] = true
		stopPose(look, 0)
		pose.look = nil
	end
	if pose.hands then
		return -- PoseClient poses this driver: nothing of ours on the same joints
	end
	-- Our own simple pose, all of it (two writers on one joint could pile up their turns).
	if pose.look then
		stopPose(pose.look, 0.1)
		pose.look = nil
	end
	local rig = pose.rig or rigOf(char)
	if not rig then
		return
	end
	pose.rig = rig
	-- Leaning into the turn (to the right is a negative angle about the body's front-to-back axis).
	-- Arms: an arm hangs down its part's -Y; a positive angle about X swings it forward, and an angle
	-- about Z (applied first) tips it sideways: negative brings the right arm in, positive the left.
	-- Turning right, the right hand goes down and the left one up.
	turn(rig, "waist", CFrame.Angles(0, 0, -steer * WAIST_STEER))
	turn(rig, "rs", CFrame.Angles(ARM_UP - steer * ARM_STEER, 0, -ARM_IN))
	turn(rig, "ls", CFrame.Angles(ARM_UP + steer * ARM_STEER, 0, ARM_IN))
	turn(rig, "re", CFrame.Angles(ELBOW, 0, 0))
	turn(rig, "le", CFrame.Angles(ELBOW, 0, 0))
	if yaw then
		-- The head toward where the camera looks, as far as a neck goes.
		local neck = pose.neck or 0
		neck += (math.clamp(yaw, -NECK_MAX, NECK_MAX) - neck) * (1 - math.exp(-dt * 8))
		pose.neck = neck
		turn(rig, "neck", CFrame.Angles(0, neck, 0))
	end
end

-- VehicleFeel.Overlay on the local character (getting in and out).
local function overlay()
	local o = VehicleFeel.Overlay
	local reach = type(o.Reach) == "number" and math.clamp(o.Reach, 0, 1) or 0
	local duck = type(o.Duck) == "number" and math.clamp(o.Duck, 0, 1) or 0
	if reach < 0.002 then
		-- No hand out (any more): PoseClient's arm, if it was reaching, comes down.
		if reachHandle then
			stopPose(reachHandle, 0.15)
			reachHandle = nil
		end
		reachSpent, lastReach = false, 0
	end
	local char = player.Character
	local idle = reach < 0.002 and duck < 0.002
	if overlayOn and (idle or char ~= overlayChar) then
		-- Done, or a new character: let go of everything held on the old one.
		overlayOn, duckOwn = false, false
		stopPose(reachHandle, 0.15)
		reachHandle = nil
		stopPose(duckHandle, 0.08)
		duckHandle = nil
		if overlayRig then
			letGo(overlayRig)
			overlayRig = nil
		end
	end
	if idle or not char then
		return
	end
	overlayOn, overlayChar = true, char
	local right = o.Side ~= -1
	local rig = nil -- the character's joints, only if we end up turning one ourselves

	-- The hand: PoseClient's pointing arm if it's there and we know where the handle is, else our own arm
	-- raised forward. PoseClient's arm is started once and let go as soon as Reach starts to fall (its own
	-- fade brings it down); from then on nothing of ours goes on that arm either.
	local posed = false
	if reach >= 0.002 then
		if reachSpent then
			posed = true
		elseif typeof(o.Target) == "Vector3" then
			if not reachHandle then
				reachHandle = playPose(char, POSE_REACH, {
					Point = o.Target, Hand = right and "Right" or "Left", Duration = 4, FadeIn = 0.2, FadeOut = 0.15,
				})
			end
			if reachHandle then
				if reach < lastReach - 0.001 then
					stopPose(reachHandle, 0.15)
					reachHandle = nil
					reachSpent = true
				elseif not pcall(reachHandle.Set, reachHandle, "Point", o.Target) then
					poseBroken[POSE_REACH] = true
					stopPose(reachHandle, 0)
					reachHandle = nil
				end
				posed = reachHandle ~= nil or reachSpent
			end
		end
		lastReach = reach
		if not posed then
			-- The arm forward and a little across the body (see driverPose for the angles' directions).
			rig = rigOf(char)
			if rig then
				turn(rig, right and "rs" or "ls", CFrame.Angles(REACH_ARM * reach, 0, (right and -1 or 1) * REACH_IN * reach))
				turn(rig, right and "re" or "le", CFrame.Angles(REACH_ELBOW * reach, 0, 0))
			end
		end
	end

	-- The lean and the duck: bending forward, mostly at the waist, a little from the hips (the whole body
	-- tips, the feet stay where they are). Our "CarDuck" pose inside PoseClient when that is there (then it
	-- alone writes those joints), else our own turns (forward is a negative angle about the body's right axis).
	local bend = REACH_LEAN * reach + DUCK_LEAN * duck
	local tip = DUCK_TIP * duck
	if not duckHandle and not duckOwn then
		duckHandle = playPose(char, POSE_DUCK, { Bend = bend, Tip = tip })
		duckOwn = duckHandle == nil
	end
	if duckHandle and not (pcall(duckHandle.Set, duckHandle, "Bend", bend) and pcall(duckHandle.Set, duckHandle, "Tip", tip)) then
		poseBroken[POSE_DUCK] = true
		stopPose(duckHandle, 0)
		duckHandle = nil
		duckOwn = true
	end
	if duckOwn then
		rig = rig or rigOf(char)
		if rig then
			turn(rig, "waist", CFrame.Angles(-bend, 0, 0))
			if tip > 0 then
				turn(rig, "root", CFrame.Angles(-tip, 0, 0))
			end
		end
	end
	if rig then
		overlayRig = rig
	end
end

-- After the animations, before the physics: drivers' poses and the local overlay.
local function poses(dt)
	local status = DriveController.Status
	local ownCar = status.Driving and status.Car or nil
	local camera = Workspace.CurrentCamera
	for _, rec in ipairs(active) do
		local seat = rec.seat
		local hum = nil
		if seat and rec.dist < POSE_RANGE and seat.Parent then
			hum = seat.Occupant
		end
		if rec.pose and rec.pose.hum ~= hum then
			endPose(rec) -- got out, or someone else is at the wheel now
		end
		if hum then
			driverPose(rec, hum, rec.car == ownCar, status, camera, dt)
		end
	end
	overlay()
end

------------------------------------------------------------------ for other controllers

function VehicleFeel.Lean(car)
	local rec = recs[car]
	if not rec then
		return 0, 0, 0
	end
	return rec.roll, rec.pitch, rec.heave
end

function VehicleFeel.Kick(car, pitch, roll, heave)
	local rec = recs[car]
	if not rec or not rec.active or not rec.joint then
		return
	end
	rec.pitchV += math.clamp(tonumber(pitch) or 0, -2, 2)
	rec.rollV += math.clamp(tonumber(roll) or 0, -2, 2)
	rec.heaveV += math.clamp(tonumber(heave) or 0, -6, 6)
	rec.resting = false
end

function VehicleFeel.IsBraking(car)
	local rec = recs[car]
	return rec ~= nil and rec.braking == true
end

function VehicleFeel.LightsOn(car)
	local rec = recs[car]
	return rec ~= nil and rec.headOn == true
end

local function guarded(fn, dt)
	local ok, err = pcall(fn, dt)
	if not ok and os.clock() - lastWarn > 5 then
		lastWarn = os.clock()
		warn("[VehicleFeel] " .. tostring(err))
	end
end

function VehicleFeel.Init()
	if started then
		return
	end
	started = true
	local module = script.Parent:WaitForChild("DriveController", 5)
	if module then
		local ok, mod = pcall(require, module)
		if ok and type(mod) == "table" and type(mod.Status) == "table" and type(mod.Input) == "table" then
			DriveController = mod
		end
	end
	local function dusk()
		night = Workspace:GetAttribute("IsNight") == true
		raining = Workspace:GetAttribute("Raining") == true
	end
	dusk()
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(dusk)
	Workspace:GetAttributeChangedSignal("Raining"):Connect(dusk)
	-- A new character: nothing of the old one's overlay carries over.
	player.CharacterAdded:Connect(function()
		local o = VehicleFeel.Overlay
		o.Reach, o.Duck, o.Target = 0, 0, nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		guarded(frame, dt)
	end)
	RunService.PreSimulation:Connect(function(dt)
		guarded(poses, dt)
	end)
end

return VehicleFeel
