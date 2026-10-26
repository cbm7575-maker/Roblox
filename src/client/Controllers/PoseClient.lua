-- PoseClient (ModuleScript, StarterPlayerScripts.Controllers.PoseClient)
-- Poses made by code, layered on top of whatever animation is playing, for ANY R15 character this device
-- can see: your own, other players', PedClient's walkers. No animation assets: every pose is a function
-- of time that turns joints, so hands tremble, chests breathe and wheels turn.
--
-- How it works
--   * Every frame the Animator writes each joint's Transform. Right after that (RunService.PreSimulation:
--     it fires after animations are stepped and before physics moves the parts, so what we write is what
--     the frame shows and the Animator simply overwrites it next frame) the poses of each tracked
--     character are blended on top: "additive" turns (a lean, a nod) multiply onto the animated value, so
--     the walk still shows through; arms placed by two-bone IK replace it, blended by the pose's weight.
--     Weights ease in and out (FadeIn / FadeOut).
--   * A frame the Animator skipped (Animator.EvaluationThrottled on far-away characters, or nothing
--     playing) still holds what we wrote last time. Each joint remembers its last write: if it is still
--     there, the last animated value is used as the base again, so a pose never stacks onto itself.
--   * Joints are found by name and may be Motor6Ds or, on upgraded avatars, AnimationConstraints (same
--     Transform; C0 / C1 come from their attachments). Nothing but Transform is ever written, so nothing
--     replicates and nothing needs putting back: every device poses what it sees.
--   * Not posed: loose bodies (Shared.Util.Ragdoll), characters further than 160 studs from the camera
--     (90 with the Performance setting; your own character always is), bodies that aren't standard R15.
--   * A loose body is read instead: while its joints are switched off, the built-in "Recover" pose works
--     out, every frame, the Transform that would hold each of them just as the limp body lies (and writes
--     it, so a joint already holds that the instant it is switched back on). Once the body is whole
--     again it blends from there back to the animation over 0.35 s, so going stiff is not a jump. It is
--     started for you: on any player's character when its "Ragdolled" attribute turns true, and through
--     Ragdoll.LimpHook for bodies loosened on this device (PedClient's walkers).
--   * One pose of each name per character. Playing it again retunes it (and restarts a timed one, which
--     carries on from where the body is: see Flinch and HandToHit); any handle to it controls it. Higher
--     Priority is applied later, so it wins where two poses want the same joint.
--
-- API
--   PoseClient.Play(character, poseName, opts?) -> handle      (never nil; a dead handle if it can't play)
--       opts for every pose: FadeIn, FadeOut (seconds), Duration (seconds; stops by itself), Weight
--       (0..1), Priority; the rest are the pose's own settings (below).
--   handle:Stop(fadeTime?)        handle:Set(param, value) -> handle        handle:IsPlaying() -> bool
--   PoseClient.Get(character, poseName) -> handle?     the pose if it is playing (to Set something on a
--                                                      pose somebody else started, e.g. a broadcast one)
--   PoseClient.IsPlaying(character, poseName) -> bool
--   PoseClient.StopAll(character, fadeTime?)
--   PoseClient.Broadcast(poseName, on) -> bool
--       Shows (or ends) a pose on YOUR character for everyone: it plays here at once and asks the server
--       (remote "PoseBroadcast"; RagdollService checks the name and the rate) to set the player attribute
--       "Pose". Every device plays that attribute's pose on that player's character, with default settings
--       (Aim points level ahead unless something Sets "Pitch" on it through PoseClient.Get).
--   PoseClient.Register(name, def)     add a pose: { FadeIn, FadeOut, Duration, Priority, Init(c, st),
--                                      Body(c, st, w, t, dt), Upper(c, st, w, t, dt) } (see POSES), written
--                                      with the tools in PoseClient.Kit
--   PoseClient.Names() -> { string }
--
-- Poses (settings in brackets; Point = a world Vector3, Target = a part / attachment / model to follow)
--   HandsUp       palms open beside the head, a slight lean back, not quite steady
--   Cower         crouched, forearms over the head, shaking
--   Brace         arms thrown over the head for a moment (what Ragdoll plays before a body goes loose)
--   PhoneTalk     phone to the ear; PhoneLook: phone at the chest, head tipped down 15 degrees. Upper
--                 body only (legs keep walking). A small phone is welded into the hand while it plays
--                 (model "NCPoseProp", this device only). [Hand = "Left" for the other hand]
--   Aim           two hands out toward the aim point, chest and head turning with it (pitch clamped to
--                 +-55 degrees, yaw to +-40; a point behind the body keeps the arms on the side they
--                 are on). [Point / Target, or Pitch and Yaw in degrees; Set("Recoil", 1) kicks once]
--   LowReady      two hands holding low in front, muzzle down. Both upper body only: for the gun system.
--   Flinch        a 0.3 s jolt of the root, chest and head. [Direction = the way the hit was travelling
--                 (the body is knocked that way); Strength 0..2; Duration] Play it on every hit: a body
--                 hit again mid-flinch stays flinched and leans round to the new hit, it doesn't start
--                 from upright each time.
--   HandToHit     a hand comes to the spot that was hit and presses it (0.9 s). [Part = a body part or
--                 its name; Point = where on it. A hit arm is held with the other hand] Played again
--                 while it shows, the same hand slides to the new spot; only when that hand's own arm is
--                 the one hit does the other take over (the two cross-fade).
--   DriverHands   both hands at 10 and 2 on a steering wheel in front of the chest; the wheel turns with
--                 Steer and the shoulders follow. [Steer -1..1 (Set it as it changes), MaxAngle (120),
--                 Speed (studs/s: with it, the idle fidget after 6 s only happens when stopped), Wheel = a
--                 real wheel part or attachment (X right, Y up, rim in its XY plane), Radius, WheelTurns =
--                 true if that part already turns with the steering]
--   LookAt        the head turns to a point, within +-70 degrees. [Point / Target, or Yaw and Pitch;
--                 MaxYaw up to 150 (past 72 the chest turns too: looking behind in a car); Rate]
--                 Something almost straight behind (past 140 degrees, whichever way it is given) is
--                 looked at over the shoulder the head is already turned to, until it comes round to the
--                 front again: the head never whips across because the target wobbled past 180.
--   HandsOnKnees  bent over, hands on the thighs, heaving (out of breath)
--   Squash        a landing: knees bend and spring back (0.36 s). [Depth 0..1]
--   Wave          a raised hand waving (2.2 s). [Hand]      Point: an arm points at Point / Target (1.8 s)
--   Recover       (played by this controller itself, see "A loose body" above; nothing to set)
--
-- Also here, because it is the same body: the server's limp falls. Remote "Ragdoll" (RagdollService)
-- makes this device lie your own character down (Ragdoll.Fall / GetUp) and plays Brace on whoever is
-- about to go loose. When your own joints are whole again (the server locks them a little before the
-- get-up) the limbs stop being solid (Ragdoll.Settle), so they can't push the body about while they
-- swing back to the animation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ragdoll = require(ReplicatedStorage.Shared.Util.Ragdoll)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local PoseClient = {}

PoseClient.Attribute = "Pose" -- player attribute naming the pose everyone should see (set by RagdollService)
PoseClient.Remote = "PoseBroadcast"

local RANGE, RANGE_LOW = 160, 90 -- studs from the camera: further away nobody can read a pose
local FALL_FAILSAFE = 6 -- seconds on the ground at most when joints went loose and nobody said for how long

-- The joints of an R15 body, by index (arrays are cheaper than names in the per-frame loop).
local ROOT, WAIST, NECK = 1, 2, 3
local R_SHOULDER, R_ELBOW, R_WRIST = 4, 5, 6
local L_SHOULDER, L_ELBOW, L_WRIST = 7, 8, 9
local R_HIP, R_KNEE, R_ANKLE = 10, 11, 12
local L_HIP, L_KNEE, L_ANKLE = 13, 14, 15
local JOINT_COUNT = 15
local UPPER_COUNT = 9 -- joints 1..9 are needed for any pose; the legs only for crouching ones
local JOINT_NAMES = {
	"Root", "Waist", "Neck",
	"RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle",
}
local JOINT_INDEX = {}
for i, name in ipairs(JOINT_NAMES) do
	JOINT_INDEX[name] = i
end

local IDENTITY = CFrame.new()
local ZERO = Vector3.zero
local UP = Vector3.yAxis
local DOWN = -Vector3.yAxis
local FORWARD = -Vector3.zAxis
local RAD = math.rad
local sin, cos, clamp, exp = math.sin, math.cos, math.clamp, math.exp

local chars = {} -- [character Model] = its record (see track)
local list = {} -- the same records, as an array for the frame loop
local orderCount = 0
local range = RANGE

------------------------------------------------------------------ small maths

local function smooth(x)
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Move `current` toward `target`, the same on any frame rate.
local function approach(current, target, dt, rate)
	return current + (target - current) * (1 - exp(-rate * dt))
end

local function unitOr(v, fallback)
	local m = v.Magnitude
	return m > 1e-4 and v / m or fallback
end

local function finite(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

-- Something almost straight behind is as near to one shoulder as to the other, and the angle to it
-- jumps between +180 and -180 on the smallest wobble (a camera looking back out of a car does it every
-- frame). So past 140 degrees a pose stays on the side it is already turned to (st.yaw, radians; the
-- side the target is on if it isn't turned yet) and keeps that side until the target comes round to the
-- front again. yaw: where the pose wants to turn (radians, not NaN). Returns the yaw to use.
local function sameShoulder(st, yaw)
	if math.abs(yaw) <= RAD(140) then
		st.behind = nil
		return yaw
	end
	local side = st.behind
	if not side then
		local from = math.abs(st.yaw) > RAD(20) and st.yaw or yaw
		side = from < 0 and -1 or 1
		st.behind = side
	end
	return math.abs(yaw) * side
end

------------------------------------------------------------------ blending onto the joints

-- The value joint i starts this frame's blending from: what the Animator wrote, or, if it didn't write
-- this frame (our own last write is still there), what it wrote last time.
local function touch(c, i)
	if c.used[i] then
		return c.cur[i]
	end
	local now = c.joints[i].Transform
	local last = c.written[i]
	local b
	if last and now:FuzzyEq(last, 1e-4) then
		b = c.base[i] or now
	else
		b = now
		c.base[i] = now
	end
	c.used[i] = true
	c.cur[i] = b
	return b
end

-- Turn joint i by `rot` on top of what it has (in its parent part's frame), w = how much of it.
local function add(c, i, rot, w)
	local b = touch(c, i)
	if w <= 0 then
		return
	end
	if w < 0.999 then
		rot = IDENTITY:Lerp(rot, w)
	end
	c.cur[i] = rot * b
end

-- Put joint i at `target`, replacing what it has by the share w.
local function set(c, i, target, w)
	local b = touch(c, i)
	if w <= 0 then
		return
	end
	c.cur[i] = w >= 0.999 and target or b:Lerp(target, w)
end

-- Slide joint i (the Root joint: lowers the whole body onto bent legs).
local function shift(c, i, offset)
	c.cur[i] = touch(c, i) + offset
end

local function rootCF(c)
	local r = c.rootNow
	if not r then
		r = c.root.CFrame
		c.rootNow = r
	end
	return r
end

-- The UpperTorso's place in root space, from this frame's Root and Waist joints as they stand now. Only
-- for Upper functions: by then every pose has had its say about those two joints. Working it out from the
-- joints (not from part CFrames) means it is right before physics has moved anything.
local function torsoInRoot(c)
	local t = c.torsoRel
	if not t then
		t = c.c0[ROOT] * touch(c, ROOT) * c.c1inv[ROOT] * c.c0[WAIST] * touch(c, WAIST) * c.c1inv[WAIST]
		c.torsoRel = t
	end
	return t
end

-- A world point, seen from the UpperTorso.
local function toTorso(c, point)
	return torsoInRoot(c):PointToObjectSpace(rootCF(c):PointToObjectSpace(point))
end

-- Where a pose should look or aim: its Point, or wherever its Target is right now.
local function pointOf(st)
	local p = st.p.Point
	if finite(p) then
		return p
	end
	local target = st.p.Target
	if typeof(target) == "Instance" and target:IsDescendantOf(Workspace) then
		if target:IsA("BasePart") then
			return target.Position
		elseif target:IsA("Attachment") then
			return target.WorldPosition
		elseif target:IsA("Model") then
			return target:GetPivot().Position
		end
	end
	return nil
end

------------------------------------------------------------------ arms and legs

-- Two-bone IK. Puts arm `a`'s wrist on `target` (UpperTorso space) with the elbow out toward `pole`,
-- by the share w. Bone lengths and directions come from the body's own joints, so any body shape works.
-- The elbow folds the forearm toward the front of the arm, which leaves the palm facing the natural way
-- (forward with the hands up, inward with a hand at the ear).
--   wrist: the wrist joint's own turn (default: the hand carries straight on from the forearm)
--   hand:  instead, the way the hand should face, as a rotation in UpperTorso space
local function arm(c, a, target, pole, w, wrist, hand)
	if w <= 0 then
		return
	end
	local v = target - a.pivot
	local d = v.Magnitude
	local dir = d > 1e-4 and v / d or DOWN
	d = clamp(d, a.min, a.max)
	local n = pole - dir * pole:Dot(dir)
	if n.Magnitude < 1e-3 then
		n = dir:Cross(Vector3.xAxis)
		if n.Magnitude < 1e-3 then
			n = dir:Cross(UP)
		end
	end
	n = n.Unit
	local l1, l2 = a.l1, a.l2
	local cosA = clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1)
	local elbow = dir * (l1 * cosA) + n * (l1 * math.sqrt(1 - cosA * cosA))
	local up1 = -elbow.Unit -- (a bone runs down its part: the part's "up" points back along it)
	local fore = unitOr(dir * d - elbow, dir)
	local perp = fore - up1 * fore:Dot(up1)
	local z1 = perp.Magnitude > 1e-4 and -perp.Unit or n
	local x1 = up1:Cross(z1) -- the axis the elbow folds about, shared by both bones
	local upper = CFrame.fromMatrix(ZERO, x1, up1, z1) * a.f1
	local up2 = -fore
	local lower = CFrame.fromMatrix(ZERO, x1, up2, x1:Cross(up2)) * a.f2
	local ts, te = upper, upper:Inverse() * lower
	if not a.plain then
		ts = a.s0 * ts * a.s1
		te = a.e0 * te * a.e1
	end
	set(c, a.s, ts, w)
	set(c, a.e, te, w)
	local tw = wrist or IDENTITY
	if hand then
		tw = lower:Inverse() * hand
		if not a.plain then
			tw = a.w0 * tw * a.w1
		end
	end
	set(c, a.w, tw, w)
end

local CROUCH_MAX = RAD(75) -- how far the thighs swing forward at k = 1

-- Bend the legs by k (0..1) and lower the body by exactly what that shortens them, so the feet stay
-- flat on the ground under the hips. Added onto the animation, so a crouched body can still walk.
-- Returns the thigh angle it used (radians).
local function crouch(c, k, w)
	if not c.legs or k <= 0 or w <= 0 then
		return 0
	end
	local a = clamp(k, 0, 1) * w * CROUCH_MAX
	local lu, ll = c.legUpper, c.legLower
	local b = math.asin(clamp(lu * sin(a) / ll, -0.99, 0.99)) -- the shin leans back to bring the foot under the hip
	shift(c, ROOT, Vector3.new(0, -(lu * (1 - cos(a)) + ll * (1 - cos(b))), 0))
	local hip, knee, ankle = CFrame.Angles(a, 0, 0), CFrame.Angles(-(a + b), 0, 0), CFrame.Angles(b, 0, 0)
	add(c, R_HIP, hip, 1)
	add(c, L_HIP, hip, 1)
	add(c, R_KNEE, knee, 1)
	add(c, L_KNEE, knee, 1)
	add(c, R_ANKLE, ankle, 1)
	add(c, L_ANKLE, ankle, 1)
	return a
end

------------------------------------------------------------------ props

local PHONE_BODY = Color3.fromRGB(26, 27, 30)
local PHONE_SCREEN = Color3.fromRGB(196, 222, 255)

-- A small phone flat against the palm (the side of the hand that faces the body when the arm hangs).
-- Made on this device only. It sits in its own Model, so code that walks the character's body parts
-- never mistakes it for one.
local function makePhone(c, side)
	local hand = side > 0 and c.handR or c.handL
	if not hand or not hand.Parent then
		return nil
	end
	local s = clamp(c.reach / 1.64, 0.7, 1.5) -- (1.64 = the arm length of a blocky body)
	local model = Instance.new("Model")
	model.Name = "NCPoseProp"
	local body = Instance.new("Part")
	body.Name = "Phone"
	body.Size = Vector3.new(0.06, 0.62, 0.32) * s
	body.Color = PHONE_BODY
	body.Material = Enum.Material.SmoothPlastic
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Size = Vector3.new(0.02, 0.54, 0.26) * s
	screen.Color = PHONE_SCREEN
	screen.Material = Enum.Material.Neon
	for _, part in ipairs({ body, screen }) do
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.Parent = model
	end
	local hold = Instance.new("Weld")
	hold.Name = "Hold"
	hold.Part0 = hand
	hold.Part1 = body
	hold.C0 = CFrame.new(-side * (hand.Size.X / 2 + 0.03 * s), -0.04 * s, 0)
	hold.Parent = body
	local face = Instance.new("Weld")
	face.Name = "Face"
	face.Part0 = body
	face.Part1 = screen
	face.C0 = CFrame.new(-side * 0.025 * s, 0, 0) -- on the side away from the palm
	face.Parent = screen
	model.Parent = c.char
	return model
end

local function phoneArm(c, st)
	return st.p.Hand == "Left" and c.armL or c.armR
end

local function phoneProp(c, st)
	return makePhone(c, phoneArm(c, st).side)
end

------------------------------------------------------------------ poses

-- A pose is a table of:
--   FadeIn, FadeOut, Priority, Duration (timed poses stop by themselves)
--   Envelope = true   the pose shapes its own rise and fall over Duration (no fade at the end)
--   Prop(c, st) -> Instance?    something to hold while it plays (destroyed with it)
--   Init(c, st)       once per Play (st.p holds the settings; keep working values on st)
--   Body(c, st, w, t, dt)    first pass: Root, Waist and the legs (use add / shift / crouch)
--   Upper(c, st, w, t, dt)   second pass: Neck and arms (torsoInRoot / toTorso are valid here)
-- c = the character's record, w = this frame's blend weight (0..1), t = seconds since the pose started.
-- Lengths are in units of c.reach (the arm's length), so every body size gets the same pose.
local POSES = {}

-- The way the elbow points in each pose's arm (the `pole` of arm, UpperTorso space), right arm and left.
-- (One table, not twelve locals: a Luau function, and the file itself counts as one, may hold 200.)
local POLE = {
	OUT_R = Vector3.new(1, -0.35, 0.1), OUT_L = Vector3.new(-1, -0.35, 0.1),
	HEAD_R = Vector3.new(1, 0.3, -0.5), HEAD_L = Vector3.new(-1, 0.3, -0.5),
	AIM_R = Vector3.new(0.7, -1, 0.3), AIM_L = Vector3.new(-0.7, -1, 0.3),
	LOW_R = Vector3.new(1, -0.2, 0.6), LOW_L = Vector3.new(-1, -0.2, 0.6),
	DRIVE_R = Vector3.new(0.8, -1, 0.2), DRIVE_L = Vector3.new(-0.8, -1, 0.2),
	KNEES_R = Vector3.new(1, 0.3, 0.4), KNEES_L = Vector3.new(-1, 0.3, 0.4),
}

POSES.HandsUp = {
	FadeIn = 0.25, FadeOut = 0.3, Priority = 40,
	Body = function(c, st, w, t)
		-- Leaning back a little, swaying: nobody holds this still.
		add(c, WAIST, CFrame.Angles(RAD(7) + RAD(1.2) * sin(t * 1.3 + st.seed), 0, RAD(1) * sin(t * 0.7 + st.seed)), w)
	end,
	Upper = function(c, st, w, t)
		local L = c.reach
		local bob = sin(t * 1.3 + st.seed) * 0.02 * L
		local tremble = sin(t * 9 + st.seed) * 0.006 * L
		local y = c.neckPos.Y + 0.34 * L
		arm(c, c.armR, Vector3.new(c.armR.pivot.X + 0.27 * L, y + bob + tremble, -0.09 * L), POLE.OUT_R, w)
		arm(c, c.armL, Vector3.new(c.armL.pivot.X - 0.27 * L, y + bob * 0.8 - tremble, -0.09 * L), POLE.OUT_L, w)
		add(c, NECK, CFrame.Angles(RAD(-4), 0, 0), w)
	end,
}

-- Forearms over the head. shake: how much the hands tremble (studs per arm length).
local function overHead(c, st, w, t, shake)
	local L, n = c.reach, c.neckPos
	local jitter = shake > 0 and sin(t * 11 + st.seed) * shake * L or 0
	local y = n.Y + 0.56 * L
	arm(c, c.armR, Vector3.new(n.X + 0.26 * L, y + jitter, 0.06 * L), POLE.HEAD_R, w)
	arm(c, c.armL, Vector3.new(n.X - 0.26 * L, y - jitter, 0.06 * L), POLE.HEAD_L, w)
end

POSES.Cower = {
	FadeIn = 0.3, FadeOut = 0.35, Priority = 42,
	Body = function(c, st, w, t)
		local breath = sin(t * 2.1 + st.seed)
		crouch(c, 0.72 + 0.03 * breath, w)
		add(c, WAIST, CFrame.Angles(RAD(-32) + RAD(2) * breath, 0, 0), w) -- hunched over
	end,
	Upper = function(c, st, w, t)
		overHead(c, st, w, t, 0.008)
		add(c, NECK, CFrame.Angles(RAD(-22), 0, 0), w) -- chin tucked in
	end,
}

POSES.Brace = {
	Duration = 0.45, FadeIn = 0.08, FadeOut = 0.1, Priority = 90,
	Body = function(c, st, w)
		add(c, WAIST, CFrame.Angles(RAD(-16), 0, 0), w)
	end,
	Upper = function(c, st, w, t)
		overHead(c, st, w, t, 0)
		add(c, NECK, CFrame.Angles(RAD(-18), 0, 0), w)
	end,
}

POSES.PhoneTalk = {
	FadeIn = 0.3, FadeOut = 0.3, Priority = 50,
	Prop = phoneProp,
	Upper = function(c, st, w, t)
		local a = phoneArm(c, st)
		local s, L, n = a.side, c.reach, c.neckPos
		local nod = sin(t * 0.9 + st.seed)
		-- The wrist just below the ear; the elbow hangs down and a little forward.
		arm(c, a, Vector3.new(n.X + s * 0.44 * L, n.Y + (0.13 + 0.006 * nod) * L, -0.14 * L), Vector3.new(s * 0.5, -1, -0.3), w)
		-- The head leans into the phone and nods along now and then.
		add(c, NECK, CFrame.Angles(RAD(2) * nod, 0, RAD(-6) * s), w)
	end,
}

POSES.PhoneLook = {
	FadeIn = 0.3, FadeOut = 0.3, Priority = 50,
	Prop = phoneProp,
	Upper = function(c, st, w, t)
		local a = phoneArm(c, st)
		local s, L, p = a.side, c.reach, a.pivot
		local sway = sin(t * 0.8 + st.seed)
		local flick = math.max(0, sin(t * 2.3 + st.seed)) ^ 8 -- the thumb scrolling: a small jerk every few seconds
		-- In front of the chest, a little to the hand's side. The hand is turned palm up (a quarter twist
		-- at the wrist) and tipped toward the face, so the screen can be read.
		arm(c, a, Vector3.new(p.X - s * 0.36 * L, p.Y - (0.36 - 0.01 * sway) * L, -0.44 * L), Vector3.new(s * 0.45, -1, 0.35), w,
			CFrame.Angles(0, RAD(-90) * s, 0) * CFrame.Angles(0, 0, (RAD(-25) - RAD(4) * flick) * s))
		add(c, NECK, CFrame.Angles(RAD(-15) + RAD(1.5) * sway, RAD(-6) * s, 0), w)
	end,
}

local AIM_PITCH = RAD(55)
local AIM_YAW = RAD(40)

POSES.Aim = {
	FadeIn = 0.15, FadeOut = 0.2, Priority = 60,
	Init = function(c, st)
		st.pitch = st.pitch or 0
		st.yaw = st.yaw or 0
		st.recoil = 0
	end,
	Body = function(c, st, w, t, dt)
		local pitch, yaw = RAD(tonumber(st.p.Pitch) or 0), RAD(tonumber(st.p.Yaw) or 0)
		local point = pointOf(st)
		if point then
			local rel = rootCF(c):PointToObjectSpace(point) - c.aimFromRoot
			local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
			pitch = math.atan2(rel.Y, math.max(flat, 0.5))
			yaw = flat > 0.5 and math.atan2(-rel.X, -rel.Z) or 0
		end
		if pitch ~= pitch or yaw ~= yaw then
			pitch, yaw = 0, 0
		end
		yaw = sameShoulder(st, yaw) -- (an aim point behind the body: the arms don't whip across the front)
		st.pitch = approach(st.pitch, clamp(pitch, -AIM_PITCH, AIM_PITCH), dt, 14)
		st.yaw = approach(st.yaw, clamp(yaw, -AIM_YAW, AIM_YAW), dt, 14)
		-- A shot: Set("Recoil", 1) is taken once, then dies away.
		local kick = tonumber(st.p.Recoil)
		if kick then
			st.p.Recoil = nil
			if kick == kick and kick > 0 then
				st.recoil = math.min(st.recoil + kick, 2)
			end
		end
		st.recoil *= exp(-dt * 12)
		-- The chest takes about half the turn (and breathes); the head and arms do the rest.
		add(c, WAIST, CFrame.fromOrientation(st.pitch * 0.45 + sin(t * 1.1 + st.seed) * RAD(0.5), st.yaw * 0.6, 0), w)
	end,
	Upper = function(c, st, w, t)
		local L = c.reach
		local p = st.pitch + sin(t * 0.9 + st.seed) * RAD(0.4) + st.recoil * RAD(4)
		local y = st.yaw
		local dir = torsoInRoot(c):VectorToObjectSpace(Vector3.new(-sin(y) * cos(p), sin(p), -cos(y) * cos(p)))
		local right = unitOr(dir:Cross(UP), Vector3.xAxis)
		local up = right:Cross(dir)
		local gun = c.aimFrom + dir * ((0.78 - 0.04 * st.recoil) * L)
		-- The gun hand points along the aim whatever the forearm does (fingers = the hand's -Y, grip up).
		arm(c, c.armR, gun, POLE.AIM_R, w, nil, CFrame.fromMatrix(ZERO, right, -dir, -up))
		-- The other hand cups it from the left, a little lower.
		arm(c, c.armL, gun - right * math.max(0.16 * L, c.handW * 0.55) - up * (0.04 * L) - dir * (0.02 * L), POLE.AIM_L, w)
		add(c, NECK, CFrame.fromOrientation(st.pitch * 0.5, st.yaw * 0.35, 0), w)
	end,
}

local LOW_DIR = Vector3.new(0.1, -0.74, -0.66).Unit -- muzzle down and a little ahead
local LOW_RIGHT = LOW_DIR:Cross(UP).Unit
local LOW_UP = LOW_RIGHT:Cross(LOW_DIR)
local LOW_HAND = CFrame.fromMatrix(ZERO, LOW_RIGHT, -LOW_DIR, -LOW_UP)

POSES.LowReady = {
	FadeIn = 0.2, FadeOut = 0.2, Priority = 58,
	Body = function(c, st, w, t)
		add(c, WAIST, CFrame.Angles(RAD(-3) + RAD(0.6) * sin(t * 1.1 + st.seed), 0, 0), w)
	end,
	Upper = function(c, st, w, t)
		local L = c.reach
		local sway = sin(t * 1.1 + st.seed)
		local gun = Vector3.new(0.14 * L, c.armR.pivot.Y - (0.56 - 0.006 * sway) * L, -0.36 * L)
		arm(c, c.armR, gun, POLE.LOW_R, w, nil, LOW_HAND)
		arm(c, c.armL, gun - LOW_RIGHT * math.max(0.16 * L, c.handW * 0.55) - LOW_UP * (0.03 * L), POLE.LOW_L, w)
	end,
}

-- A hit's shape over its time x (0..1): up fast, back slowly.
local function jolt(x)
	if x <= 0 or x >= 1 then
		return 0
	end
	if x < 0.2 then
		return smooth(x / 0.2)
	end
	return 1 - smooth((x - 0.2) / 0.8)
end

-- How far into a flinch the body is at time t of dur (0..1). A flinch that starts while the last one
-- still shows (every hit plays it, and automatic fire lands a hit every tenth of a second) doesn't begin
-- from upright: `carry` is how far the last one had got, and the rise goes on from there. The body then
-- stays flinched under fire instead of shaking back and forth.
local function flinchAmount(carry, t, dur)
	local x = t / dur
	local s = jolt(x)
	if carry > 0 and x < 0.2 then
		s = carry + (1 - carry) * s
	end
	return s
end

POSES.Flinch = {
	Duration = 0.3, Envelope = true, FadeIn = 0, FadeOut = 0.05, Priority = 80,
	Init = function(c, st)
		local d = st.p.Direction
		local rel = finite(d) and c.root.CFrame:VectorToObjectSpace(d) or Vector3.zAxis
		rel = Vector3.new(rel.X, 0, rel.Z)
		rel = rel.Magnitude > 0.05 and rel.Unit or Vector3.zAxis -- (no direction given: knocked backward)
		local strength = tonumber(st.p.Strength) or 1
		strength = strength == strength and clamp(strength, 0, 2) or 1
		st.strength = strength
		-- What the last flinch still shows (st.out for the chest, st.outLate for the head; both nil the
		-- first time), as a share of this one's strength.
		local had = st.out or 0
		st.carry = strength > 0 and math.min(had / strength, 1) or 0
		st.carryLate = strength > 0 and math.min((st.outLate or 0) / strength, 1) or 0
		st.axisGoal = UP:Cross(rel) -- turning about it tips the body the way the hit was going
		st.twistGoal = rel.X * RAD(8) -- and the struck shoulder is carried round
		if had <= 0 or not st.axis then
			st.axis, st.twist = st.axisGoal, st.twistGoal -- (mid-flinch the lean swings round instead: Body)
		end
	end,
	Body = function(c, st, w, t, dt)
		-- A second hit from another side: the lean turns to it quickly, it doesn't jump.
		local k = 1 - exp(-25 * dt)
		st.axis = unitOr(st.axis:Lerp(st.axisGoal, k), st.axisGoal)
		st.twist += (st.twistGoal - st.twist) * k
		local out = flinchAmount(st.carry, t, st.dur or 0.3) * st.strength
		st.out = out
		local s = out * w
		if s > 0 then
			add(c, ROOT, CFrame.fromAxisAngle(st.axis, RAD(4) * s), 1)
			add(c, WAIST, CFrame.fromAxisAngle(st.axis, RAD(13) * s) * CFrame.Angles(0, st.twist * s, 0), 1)
		end
	end,
	Upper = function(c, st, w, t)
		local s = (st.out or 0) * w
		-- The head whips a beat behind the chest.
		local late = flinchAmount(st.carryLate, t - 0.03, st.dur or 0.3) * st.strength
		st.outLate = late
		late *= w
		if late > 0 then
			add(c, NECK, CFrame.fromAxisAngle(st.axis, RAD(11) * late), 1)
		end
		if s > 0 then
			add(c, R_SHOULDER, CFrame.Angles(0, 0, RAD(7) * s), 1) -- the arms jerk out
			add(c, L_SHOULDER, CFrame.Angles(0, 0, RAD(-7) * s), 1)
		end
	end,
}

local CHEST_FRONT = Vector3.new(0, 0.1, -0.5)

POSES.HandToHit = {
	Duration = 0.9, FadeIn = 0.18, FadeOut = 0.3, Priority = 70,
	Init = function(c, st)
		local part = st.p.Part
		if type(part) == "string" then
			part = c.char:FindFirstChild(part)
		end
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(c.char) then
			part = nil
		end
		local point = st.p.Point
		-- Played again while it shows (a second hit), the pose carries on from where it is: st.side is
		-- the arm that is already holding, st.pos where its hand is (UpperTorso space; both nil the
		-- first time).
		local holding = st.side
		local other = nil -- the arm that has to do it this time, when the hit leaves no choice
		st.part = part
		st.fixed = nil
		if part then
			-- Where on that part (kept inside its box), so the hand follows it as the body moves.
			local lp = finite(point) and part.CFrame:PointToObjectSpace(point) or ZERO
			local half = part.Size / 2
			st.spot = Vector3.new(clamp(lp.X, -half.X, half.X), clamp(lp.Y, -half.Y, half.Y), clamp(lp.Z, -half.Z, half.Z))
			local name = part.Name
			if string.find(name, "Arm", 1, true) or string.find(name, "Hand", 1, true) then
				other = string.find(name, "Right", 1, true) and -1 or 1 -- a hit arm is held with the other hand
			end
		else
			st.spot = finite(point) and point or nil
		end
		-- The hand that is already there stays and slides to the new spot. Only when it is its own arm
		-- that was hit does the other one take over: the old hand lets go as the new one arrives (Upper).
		if holding and other and other ~= holding and st.pos then
			st.oldSide, st.oldPos, st.swap = holding, st.pos, 1
			st.pos = nil
		end
		st.side = other or holding
	end,
	Body = function(c, st, w, t, dt)
		-- Curling round the sore spot (eased: a second hit on the other side doesn't jerk the chest across).
		st.lean = approach(st.lean or 0, st.hitSide or 0, dt, 10)
		add(c, WAIST, CFrame.Angles(RAD(-5), 0, RAD(-4) * st.lean), w)
	end,
	Upper = function(c, st, w, t, dt)
		local L = c.reach
		local spot = CHEST_FRONT
		local part = st.part
		if part then
			if part.Parent then
				spot = toTorso(c, part.CFrame:PointToWorldSpace(st.spot))
			end
		elseif st.spot then
			-- A bare world point: pinned to the chest where it was when the pose began.
			if not st.fixed then
				st.fixed = toTorso(c, st.spot)
			end
			spot = st.fixed
		end
		st.hitSide = (spot.X > 0.1 * L and 1) or (spot.X < -0.1 * L and -1) or 0
		if not st.side then
			st.side = spot.X < 0 and -1 or 1
		end
		local a = st.side > 0 and c.armR or c.armL
		-- The hand rests on the body, not in it: a little out from the middle line, and up (the hand
		-- hangs below the wrist). It presses in and out slightly.
		local out = Vector3.new(spot.X, 0, spot.Z)
		out = out.Magnitude > 0.05 and out.Unit or FORWARD
		local goal = spot + out * ((0.1 + 0.008 * sin(t * 5)) * L) + Vector3.new(0, 0.05 * L, 0)
		-- (the first time it is simply there, faded in by w; after another hit it slides across)
		local pos = st.pos
		pos = pos and pos:Lerp(goal, 1 - exp(-14 * dt)) or goal
		st.pos = pos
		local share = 1
		local swap = st.swap
		if swap then
			-- Changing hands (see Init): 0.18 s, the same as the pose's own fade in.
			swap -= dt / 0.18
			if swap > 0 then
				st.swap = swap
				share = 1 - smooth(swap)
				local old = st.oldSide > 0 and c.armR or c.armL
				arm(c, old, st.oldPos, Vector3.new(old.side, -0.6, 0.3), w * (1 - share))
			else
				st.swap, st.oldSide, st.oldPos = nil, nil, nil
			end
		end
		arm(c, a, pos, Vector3.new(a.side, -0.6, 0.3), w * share)
	end,
}

local FIDGET_AFTER, FIDGET_EVERY, FIDGET_TIME = 6, 9, 2.8 -- seconds: stopped this long, then this often, for this long

POSES.DriverHands = {
	FadeIn = 0.35, FadeOut = 0.3, Priority = 45,
	Init = function(c, st)
		st.steer = st.steer or 0
		st.still = 0
		st.fidget = 0
	end,
	Body = function(c, st, w, t, dt)
		local steer = tonumber(st.p.Steer) or 0
		if steer ~= steer then
			steer = 0
		end
		steer = clamp(steer, -1, 1)
		st.steer = approach(st.steer, steer, dt, 10)
		-- Holding still for a while (and stopped, when the caller tells us the speed): now and then the
		-- right hand slides down the wheel, drums on it, and the driver glances out of the window.
		local speed = tonumber(st.p.Speed)
		local idle = math.abs(steer) < 0.08 and (speed == nil or math.abs(speed) < 1)
		st.still = idle and st.still + dt or 0
		local want = 0
		if st.still > FIDGET_AFTER and (st.still - FIDGET_AFTER) % FIDGET_EVERY < FIDGET_TIME then
			want = 1
		end
		st.fidget = approach(st.fidget, want, dt, 3)
		-- Shoulders follow the wheel: the chest turns and leans into the corner a few degrees.
		add(c, WAIST, CFrame.Angles(0, RAD(-7) * st.steer, RAD(-5) * st.steer), w)
	end,
	Upper = function(c, st, w, t)
		local L = c.reach
		-- The wheel in root (seat) space, so the hands stay on it while the chest moves.
		local wheel = c.wheelRest
		local maxAngle = tonumber(st.p.MaxAngle) or 120
		local turn = st.steer * RAD(maxAngle == maxAngle and clamp(maxAngle, 0, 180) or 120)
		local source = st.p.Wheel
		if typeof(source) == "Instance" and source:IsDescendantOf(Workspace) then
			if source:IsA("BasePart") then
				wheel = rootCF(c):ToObjectSpace(source.CFrame)
			elseif source:IsA("Attachment") then
				wheel = rootCF(c):ToObjectSpace(source.WorldCFrame)
			end
			if st.p.WheelTurns == true then
				turn = 0 -- that part turns by itself: the rim points already move
			end
		end
		local r = tonumber(st.p.Radius)
		if not r or r ~= r or r <= 0 then
			r = math.max(0.24 * L, c.handW * 0.62) -- wide enough that blocky hands don't sit inside each other
		end
		local f = st.fidget
		-- Rim angles from the top, clockwise as the driver sees it: 2 o'clock and 10 o'clock.
		local aR = RAD(60) + turn + RAD(95) * f
		local aL = RAD(-60) + turn
		local seen = torsoInRoot(c)
		local drum = f > 0.5 and CFrame.Angles(sin(t * 38) * RAD(5) * f, 0, 0) or nil
		arm(c, c.armR, seen:PointToObjectSpace(wheel * Vector3.new(r * sin(aR), r * cos(aR), 0)), POLE.DRIVE_R, w, drum)
		arm(c, c.armL, seen:PointToObjectSpace(wheel * Vector3.new(r * sin(aL), r * cos(aL), 0)), POLE.DRIVE_L, w)
		if f > 0.01 then
			add(c, NECK, CFrame.Angles(0, RAD(-18) * f, 0), w)
		end
	end,
}

local LOOK_PITCH = RAD(40)
local NECK_YAW = RAD(72) -- as far as a neck turns by itself
local WAIST_YAW = RAD(50)

POSES.LookAt = {
	FadeIn = 0.25, FadeOut = 0.3, Priority = 65,
	Init = function(c, st)
		st.yaw = st.yaw or 0
		st.pitch = st.pitch or 0
	end,
	Body = function(c, st, w, t, dt)
		local yaw, pitch = RAD(tonumber(st.p.Yaw) or 0), RAD(tonumber(st.p.Pitch) or 0)
		local point = pointOf(st)
		if point then
			local rel = rootCF(c):PointToObjectSpace(point) - c.eyeRoot
			local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
			pitch = math.atan2(rel.Y, math.max(flat, 0.3))
			yaw = flat > 0.3 and math.atan2(-rel.X, -rel.Z) or 0
		end
		if yaw ~= yaw or pitch ~= pitch then
			yaw, pitch = 0, 0
		end
		-- Almost straight behind (a point, or a Yaw the caller sets every frame, as VehicleFeel does
		-- from the camera): stay over the same shoulder instead of flipping across.
		yaw = sameShoulder(st, yaw)
		local maxYaw = tonumber(st.p.MaxYaw) or 70
		maxYaw = RAD(maxYaw == maxYaw and clamp(maxYaw, 0, 150) or 70)
		local rate = tonumber(st.p.Rate) or 9
		rate = rate == rate and clamp(rate, 0.5, 40) or 9
		st.yaw = approach(st.yaw, clamp(yaw, -maxYaw, maxYaw), dt, rate)
		st.pitch = approach(st.pitch, clamp(pitch, -LOOK_PITCH, LOOK_PITCH), dt, rate)
		-- Further round than a neck goes, the chest turns too (looking behind in a car).
		local waistYaw = clamp(st.yaw - clamp(st.yaw, -NECK_YAW, NECK_YAW), -WAIST_YAW, WAIST_YAW)
		if waistYaw ~= 0 then
			add(c, WAIST, CFrame.Angles(0, waistYaw, 0), w)
		end
	end,
	Upper = function(c, st, w)
		add(c, NECK, CFrame.fromOrientation(st.pitch, clamp(st.yaw, -NECK_YAW, NECK_YAW), 0), w)
	end,
}

local KNEES_CROUCH = 0.45 -- how far the legs bend (see crouch)
local KNEES_ALONG = 0.62 -- the hands rest this far down the thigh, hip to knee

POSES.HandsOnKnees = {
	FadeIn = 0.4, FadeOut = 0.45, Priority = 30,
	Init = function(c, st)
		st.bend = RAD(62)
		st.thigh = 0
		if c.legs then
			-- Short arms (blocky bodies) can't reach the thighs from a shallow bow: bow further until they do.
			local a = CROUCH_MAX * KNEES_CROUCH
			local thigh = c.c0[R_HIP].Position + Vector3.new(0, -cos(a), -sin(a)) * (c.legUpper * KNEES_ALONG)
			local shoulder = c.armR.pivot - c.c1[WAIST].Position -- from the waist joint, in the chest
			for degrees = 50, 82, 4 do
				st.bend = RAD(degrees)
				local reached = c.c0[WAIST].Position + CFrame.Angles(-st.bend, 0, 0) * shoulder
				if (reached - thigh).Magnitude <= c.armR.max * 0.97 then
					break
				end
			end
		end
	end,
	Body = function(c, st, w, t)
		local breath = sin(t * 5.6 + st.seed) -- most of a breath every second
		st.thigh = crouch(c, KNEES_CROUCH + 0.02 * breath, w)
		add(c, WAIST, CFrame.Angles(-(st.bend or RAD(62)) + RAD(3) * breath, 0, 0), w) -- bent over, back heaving
	end,
	Upper = function(c, st, w, t)
		local breath = sin(t * 5.6 + st.seed)
		if c.legs then
			-- The thighs as the chest sees them (LowerTorso space into UpperTorso space, through the waist).
			local a = st.thigh or 0
			local seen = (c.c0[WAIST] * touch(c, WAIST) * c.c1inv[WAIST]):Inverse()
			local along = Vector3.new(0, -cos(a), -sin(a)) * (c.legUpper * KNEES_ALONG)
			local onTop = Vector3.new(0, sin(a), -cos(a)) * (c.thighHalf + 0.05) -- out of the bone to the front of the leg
			arm(c, c.armR, seen * (c.c0[R_HIP].Position + along + onTop), POLE.KNEES_R, w)
			arm(c, c.armL, seen * (c.c0[L_HIP].Position + along + onTop), POLE.KNEES_L, w)
		end
		add(c, NECK, CFrame.Angles(RAD(22) - RAD(3) * breath, 0, 0), w) -- head up enough to see ahead
	end,
}

POSES.Squash = {
	Duration = 0.36, Envelope = true, FadeIn = 0, FadeOut = 0.05, Priority = 20,
	Body = function(c, st, w, t)
		-- Down in the first fifth of the time, springing back over the rest.
		local x = t / (st.dur or 0.36)
		local e = x < 0.22 and smooth(x / 0.22) or 1 - smooth((x - 0.22) / 0.78)
		local depth = tonumber(st.p.Depth) or 0.6
		st.e = e * (depth == depth and clamp(depth, 0, 1) or 0.6)
		crouch(c, 0.55 * st.e, w)
		add(c, WAIST, CFrame.Angles(RAD(-10) * st.e, 0, 0), w)
	end,
	Upper = function(c, st, w)
		local e = st.e or 0
		add(c, R_SHOULDER, CFrame.Angles(0, 0, RAD(10) * e), w) -- arms out for balance
		add(c, L_SHOULDER, CFrame.Angles(0, 0, RAD(-10) * e), w)
		add(c, NECK, CFrame.Angles(RAD(-5) * e, 0, 0), w)
	end,
}

POSES.Wave = {
	Duration = 2.2, FadeIn = 0.25, FadeOut = 0.3, Priority = 55,
	Upper = function(c, st, w, t)
		local a = st.p.Hand == "Left" and c.armL or c.armR
		local s, L, p = a.side, c.reach, a.pivot
		local swing = sin(t * 10.5)
		arm(c, a, Vector3.new(p.X + s * (0.3 + 0.12 * swing) * L, p.Y + 0.5 * L, -0.12 * L), Vector3.new(s, -0.55, 0.1), w,
			CFrame.Angles(0, 0, RAD(-14) * swing * s)) -- the hand flaps with the forearm
		add(c, NECK, CFrame.Angles(0, 0, RAD(-3) * s), w)
	end,
}

POSES.Point = {
	Duration = 1.8, FadeIn = 0.2, FadeOut = 0.3, Priority = 55,
	Init = function(c, st)
		st.side = nil
	end,
	Upper = function(c, st, w, t)
		local point = pointOf(st)
		local spot = point and toTorso(c, point) or nil
		if not st.side then
			if st.p.Hand == "Left" then
				st.side = -1
			elseif st.p.Hand == "Right" then
				st.side = 1
			else
				st.side = (spot and spot.X < -0.2) and -1 or 1 -- the arm on that side
			end
		end
		local a = st.side > 0 and c.armR or c.armL
		local dir = spot and unitOr(spot - a.pivot, FORWARD) or FORWARD
		if dir.Z > 0 then
			dir = unitOr(Vector3.new(dir.X, dir.Y, 0), FORWARD) -- nobody points through their own back
		end
		local jab = sin(t * 7) * 0.012 * c.reach * math.max(0, 1 - t) -- a couple of jabs, then steady
		arm(c, a, a.pivot + dir * (a.max - 0.02) + Vector3.new(0, jab, 0), Vector3.new(a.side * 0.3, -1, 0.1), w)
		-- The head looks the same way.
		local yaw = clamp(math.atan2(-dir.X, -dir.Z), -RAD(50), RAD(50))
		local pitch = clamp(math.asin(clamp(dir.Y, -1, 1)), -RAD(25), RAD(25))
		add(c, NECK, CFrame.fromOrientation(pitch * 0.5, yaw * 0.7, 0), w)
	end,
}

-- Joints first..last held where the limp body had them (from[i], see readLimp), by the share k.
local function holdLimp(c, from, first, last, k)
	local joints = c.joints
	for i = first, last do
		local f = from[i]
		if f and joints[i] then
			set(c, i, f, k)
		end
	end
end

-- Coming back from a ragdoll. While the body is loose this pose does nothing here: readLimp (the frame
-- loop calls it instead of the poses) keeps st.from = how each loose joint lies and st.at = when it
-- last looked. From the moment the joints are whole again it holds them there and lets go over 0.35 s,
-- so the limbs swing back to the animation (through the get-up) instead of snapping to it in one frame.
-- Highest priority: while it lasts it has the last word on the joints that were loose.
POSES.Recover = {
	FadeIn = 0, FadeOut = 0, Priority = 100,
	Body = function(c, st, w)
		local from = st.from
		local k = (from and st.at) and 1 - smooth((os.clock() - st.at) / 0.35) or 0
		st.k = k
		if k <= 0 then
			st.from = nil
			st.handle:Stop(0) -- back with the animation (or the body was never seen loose): done
			return
		end
		holdLimp(c, from, WAIST, WAIST, k * w)
		holdLimp(c, from, R_HIP, L_ANKLE, k * w)
	end,
	Upper = function(c, st, w)
		local from, k = st.from, (st.k or 0) * w
		if from and k > 0 then
			holdLimp(c, from, R_SHOULDER, L_WRIST, k)
		end
	end,
}

------------------------------------------------------------------ reading a body

-- Where a joint sits in its two parts, the part it moves, and the part that one hangs from. Motor6D or
-- AnimationConstraint.
local function jointFrames(j)
	if j:IsA("Motor6D") then
		local p0, p1 = j.Part0, j.Part1
		if p0 and p1 then
			return j.C0, j.C1, p1, p0
		end
		return nil
	end
	local a0, a1 = j.Attachment0, j.Attachment1
	if a0 and a1 and a1.Parent and a1.Parent:IsA("BasePart") then
		local p0 = a0.Parent
		return a0.CFrame, a1.CFrame, a1.Parent, (p0 and p0:IsA("BasePart")) and p0 or nil
	end
	return nil
end

-- A bone is the line from one joint to the next inside a part. It rarely runs straight down the part
-- (a blocky upper arm hangs from its inner top corner), so the IK works in a frame whose "up" points
-- back along the bone; this is the turn from that frame to the part's own.
local function boneFrame(bone)
	local y = -bone.Unit
	local z = Vector3.zAxis - y * y.Z
	if z.Magnitude < 1e-3 then
		z = Vector3.xAxis:Cross(y)
	end
	z = z.Unit
	return CFrame.fromMatrix(ZERO, y:Cross(z), y, z):Inverse()
end

local function makeArm(c, s, e, w, side)
	local b1 = c.c0[e].Position - c.c1[s].Position -- shoulder to elbow, in the upper arm
	local b2 = c.c0[w].Position - c.c1[e].Position -- elbow to wrist, in the forearm
	local l1, l2 = b1.Magnitude, b2.Magnitude
	if l1 < 0.05 or l2 < 0.05 then
		return nil
	end
	local a = {
		s = s, e = e, w = w, side = side, l1 = l1, l2 = l2,
		min = math.abs(l1 - l2) + 0.02, max = l1 + l2 - 0.01, -- how near and how far the wrist can be
		pivot = c.c0[s].Position, -- the shoulder, in the UpperTorso
		f1 = boneFrame(b1), f2 = boneFrame(b2),
		-- Joints whose own frames are turned inside their parts (none on standard bodies).
		s0 = c.c0[s].Rotation:Inverse(), s1 = c.c1[s].Rotation,
		e0 = c.c0[e].Rotation:Inverse(), e1 = c.c1[e].Rotation,
		w0 = c.c0[w].Rotation:Inverse(), w1 = c.c1[w].Rotation,
	}
	a.plain = a.s0:FuzzyEq(IDENTITY, 1e-4) and a.s1:FuzzyEq(IDENTITY, 1e-4) and a.e0:FuzzyEq(IDENTITY, 1e-4)
		and a.e1:FuzzyEq(IDENTITY, 1e-4) and a.w0:FuzzyEq(IDENTITY, 1e-4) and a.w1:FuzzyEq(IDENTITY, 1e-4)
	return a
end

-- Find the joints and measure the body. Returns false if this isn't (yet) a whole R15 upper body.
local function buildRig(c)
	local char = c.char
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	c.root = root
	local joints = c.joints
	table.clear(joints)
	table.clear(c.jointSet)
	table.clear(c.written)
	table.clear(c.mine)
	table.clear(c.base)
	table.clear(c.p0)
	table.clear(c.p1)
	c.posed = false
	for _, d in ipairs(char:GetDescendants()) do
		local i = JOINT_INDEX[d.Name]
		if i and not joints[i] and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
			joints[i] = d
		end
	end
	local legs = true
	local child = {}
	for i = 1, JOINT_COUNT do
		local j = joints[i]
		local c0, c1, part, parent
		if j then
			c0, c1, part, parent = jointFrames(j)
		end
		if c0 then
			c.c0[i], c.c1[i], c.c1inv[i] = c0, c1, c1:Inverse()
			c.p0[i], c.p1[i] = parent, part
			c.jointSet[j] = true
			child[i] = part
		elseif i <= UPPER_COUNT then
			return false
		else
			legs = false
		end
	end
	local armR = makeArm(c, R_SHOULDER, R_ELBOW, R_WRIST, 1)
	local armL = makeArm(c, L_SHOULDER, L_ELBOW, L_WRIST, -1)
	if not armR or not armL then
		return false
	end
	c.armR, c.armL = armR, armL
	c.handR, c.handL = child[R_WRIST], child[L_WRIST]
	c.handW = c.handR.Size.X
	local L = (armR.l1 + armR.l2 + armL.l1 + armL.l2) / 2
	c.reach = L
	c.neckPos = c.c0[NECK].Position
	if legs then
		c.legUpper = (c.c0[R_KNEE].Position - c.c1[R_HIP].Position).Magnitude
		c.legLower = (c.c0[R_ANKLE].Position - c.c1[R_KNEE].Position).Magnitude
		c.thighHalf = child[R_HIP].Size.Z / 2
		legs = c.legUpper > 0.05 and c.legLower > 0.05
	end
	c.legs = legs
	-- Places in root space with every joint at rest: near enough for deciding where to look or aim.
	local torsoRest = c.c0[ROOT] * c.c1inv[ROOT] * c.c0[WAIST] * c.c1inv[WAIST]
	c.aimFrom = Vector3.new(0.12 * L, c.neckPos.Y - 0.08 * L, 0) -- the sight line starts just right of the chin (UpperTorso space)
	c.aimFromRoot = torsoRest * c.aimFrom
	c.eyeRoot = torsoRest * (c.neckPos + Vector3.new(0, 0.3 * L, 0))
	-- A steering wheel for a body with no car: in front of the chest, its top tipped away.
	c.wheelRest = CFrame.new(torsoRest * Vector3.new(0, -0.1 * L, -0.62 * L)) * CFrame.Angles(RAD(-22), 0, 0)
	c.animator = c.hum:FindFirstChildOfClass("Animator")
	return true
end

------------------------------------------------------------------ tracking characters

-- Hand joint i back to the animation: if what we last wrote is still there, put back what the Animator
-- last wrote (it would otherwise stay posed until the next animated frame).
local function release(c, i)
	local j = c.joints[i]
	local last = c.written[i]
	if j and last and j.Parent and j.Transform:FuzzyEq(last, 1e-4) then
		j.Transform = c.base[i] or IDENTITY
	end
	c.mine[i] = false
	c.written[i] = nil
end

local function releaseAll(c)
	for i = 1, JOINT_COUNT do
		if c.mine[i] then
			release(c, i)
		end
	end
	c.posed = false
end

local function removePose(c, index)
	local st = table.remove(c.poses, index)
	st.alive = false
	if st.prop then
		st.prop:Destroy()
		st.prop = nil
	end
end

local function drop(c)
	if c.dead then
		return
	end
	c.dead = true
	for i = #c.poses, 1, -1 do
		removePose(c, i)
	end
	if c.rigOk and c.char.Parent then
		releaseAll(c)
	end
	for _, conn in ipairs(c.conns) do
		conn:Disconnect()
	end
	if chars[c.char] == c then
		chars[c.char] = nil
	end
	local i = table.find(list, c)
	if i then
		table.remove(list, i)
	end
end

local function track(char)
	local c = chars[char]
	if c then
		return c
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") or hum.RigType ~= Enum.HumanoidRigType.R15
		or not char:IsDescendantOf(Workspace) then
		return nil
	end
	c = {
		char = char, hum = hum, root = root,
		isLocal = Players:GetPlayerFromCharacter(char) == player,
		poses = {}, -- playing poses, lowest Priority first
		joints = {}, jointSet = {}, c0 = {}, c1 = {}, c1inv = {},
		p0 = {}, p1 = {}, -- [i] = the two parts joint i holds together (p1 hangs from p0)
		base = {}, -- [i] = the Animator's last value for joint i
		cur = {}, -- [i] = this frame's value being built
		used = {}, -- [i] = a pose touched joint i this frame
		written = {}, -- [i] = what we last wrote
		mine = {}, -- [i] = we wrote joint i on the last posed frame
		posed = false,
		rigOk = false,
		rigAt = 0, -- os.clock() of the next try at reading the body
		conns = {},
	}
	c.rigOk = buildRig(c)
	table.insert(c.conns, char.AncestryChanged:Connect(function()
		if not char:IsDescendantOf(Workspace) then
			drop(c) -- respawned, recycled or streamed out: its poses go with it
		end
	end))
	table.insert(c.conns, char.DescendantRemoving:Connect(function(d)
		if c.jointSet[d] or d == c.root then
			c.rigOk = false -- a body part was swapped (new clothes): read the body again
			c.rigAt = 0
		end
	end))
	chars[char] = c
	table.insert(list, c)
	return c
end

------------------------------------------------------------------ the frame

local canThrottle = true -- false once this engine turns out not to have Animator.EvaluationThrottled

local function readThrottled(animator)
	return animator.EvaluationThrottled
end

-- Did the Animator skip this character this frame? Then our last write is still on the joints and there
-- is nothing new to pose on top of.
local function throttled(c)
	if not canThrottle then
		return false
	end
	local animator = c.animator
	if not animator or not animator.Parent then
		animator = c.hum:FindFirstChildOfClass("Animator")
		c.animator = animator
		if not animator then
			return false
		end
	end
	local ok, value = pcall(readThrottled, animator)
	if not ok then
		canThrottle = false
		return false
	end
	return value == true
end

-- Move every pose's weight toward where it is going; drop the ones that have faded out.
local function tickPoses(c, now, dt)
	local poses = c.poses
	for i = #poses, 1, -1 do
		local st = poses[i]
		if st.endAt and now >= st.endAt then
			st.endAt = nil
			st.target = 0
		end
		local w, target = st.w, st.target
		if w < target then
			w = st.fadeIn > 0 and math.min(target, w + dt / st.fadeIn) or target
		elseif w > target then
			w = st.fadeOut > 0 and math.max(target, w - dt / st.fadeOut) or target
		end
		st.w = w
		if target <= 0 and w <= 0 then
			removePose(c, i)
		else
			st.blend = w * w * (3 - 2 * w) * st.max
		end
	end
end

local function evaluate(c, now, dt)
	local used, poses = c.used, c.poses
	for i = 1, JOINT_COUNT do
		used[i] = false
	end
	c.rootNow = nil
	c.torsoRel = nil
	for i = 1, #poses do
		local st = poses[i]
		if st.needInit then
			st.needInit = false
			local def = st.def
			if def.Init then
				def.Init(c, st)
			end
			if def.Prop and not st.prop then
				st.prop = def.Prop(c, st)
			end
		end
		local body = st.def.Body
		if body and st.blend > 0 then
			body(c, st, st.blend, now - st.t0, dt)
		end
	end
	c.torsoRel = nil -- (worked out afresh by the first Upper function that asks)
	for i = 1, #poses do
		local st = poses[i]
		local upper = st.def.Upper
		if upper and st.blend > 0 then
			upper(c, st, st.blend, now - st.t0, dt)
		end
	end
	local joints, cur, written, mine = c.joints, c.cur, c.written, c.mine
	for i = 1, JOINT_COUNT do
		if used[i] then
			local out = cur[i]
			local check = out.X + out.Y + out.Z + out.LookVector.X
			if check == check then -- (a broken number must never reach a joint)
				joints[i].Transform = out
				written[i] = out
				mine[i] = true
			end
		elseif mine[i] then
			release(c, i)
		end
	end
	c.posed = true
end

local function findPose(c, poseName)
	for _, st in ipairs(c.poses) do
		if st.name == poseName then
			return st
		end
	end
	return nil
end

-- A loose body: its switched-off joints ignore Transform, so there is nothing to pose. But the
-- "Recover" pose wants to know how the body lies, so that going whole again isn't a jump. For every
-- joint that is switched off right now, work out the Transform that would hold its two parts exactly
-- where they are (a joint puts p1 at p0 * C0 * Transform * C1 inverse), remember it and write it: the
-- joint then already holds the limp pose on the frame it is switched back on, even if the Animator
-- skips that frame here. Does nothing unless "Recover" is playing on this character.
local function readLimp(c, now)
	local st = findPose(c, "Recover")
	if not st then
		return
	end
	local from = st.from
	if not from then
		from = {}
		st.from = from
	end
	-- The "Ragdolled" attribute and the joints' own switches come from the server one after the other
	-- and may land a frame apart. A joint that is already back on while the body still counts as loose
	-- is held where it was last seen (only just now: an old reading is left to blend out).
	local fresh = st.at ~= nil and now - st.at < 0.25
	local read = false
	local joints, p0s, p1s, written = c.joints, c.p0, c.p1, c.written
	for i = WAIST, JOINT_COUNT do
		local j, p0, p1 = joints[i], p0s[i], p1s[i]
		if i ~= NECK and j and p0 and p1 and p0.Parent and p1.Parent then
			local f = nil
			if j.Enabled then
				f = fresh and from[i] or nil
			else
				f = c.c0[i]:Inverse() * p0.CFrame:ToObjectSpace(p1.CFrame) * c.c1[i]
				local check = f.X + f.Y + f.Z + f.LookVector.X
				if check == check then -- (a broken number must never reach a joint)
					from[i] = f
					read = true
				else
					f = nil
				end
			end
			if f then
				-- What is on the joint and isn't ours is the Animator's: where the blend back heads
				-- if this device's Animator has nothing newer by then (the same rule as touch).
				local seen = j.Transform
				local last = written[i]
				if not (last and seen:FuzzyEq(last, 1e-4)) then
					c.base[i] = seen
				end
				j.Transform = f
				written[i] = f
				c.mine[i] = true
				c.posed = true
			end
		end
	end
	if read then
		st.at = now
	end
end

local function stepCharacter(c, now, dt, camPos)
	tickPoses(c, now, dt)
	if #c.poses == 0 then
		drop(c)
		return
	end
	if not c.isLocal and camPos and (c.root.Position - camPos).Magnitude > range then
		if c.posed then
			releaseAll(c)
		end
		return
	end
	if not c.rigOk then
		if now < c.rigAt then
			return
		end
		c.rigAt = now + 0.5
		c.rigOk = buildRig(c)
		if not c.rigOk then
			return
		end
		-- New body parts: whatever was held in the old hand is made again.
		for _, st in ipairs(c.poses) do
			if st.prop then
				st.prop:Destroy()
				st.prop = nil
			end
			st.needInit = true
		end
	end
	if Ragdoll.IsRagdolled(c.char) then
		-- Loose joints ignore Transform: the poses carry on when the body is whole again. Until then
		-- the body is only read, for "Recover".
		readLimp(c, now)
		return
	end
	if throttled(c) then
		return
	end
	evaluate(c, now, dt)
end

local lastWarn = 0
local housekeeping -- (set further down: the once-a-second chores)
local choreAt = 0

local function step(dt)
	local now = os.clock()
	if now >= choreAt then
		choreAt = now + 1
		housekeeping()
	end
	if #list == 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	for i = #list, 1, -1 do
		local c = list[i]
		local ok, err = pcall(stepCharacter, c, now, dt, camPos)
		if not ok then
			-- One broken pose mustn't stop the others (or come back sixty times a second).
			if now - lastWarn > 5 then
				lastWarn = now
				warn("[PoseClient] " .. tostring(err))
			end
			drop(c)
		end
	end
end

------------------------------------------------------------------ API

local Handle = {}
Handle.__index = Handle

function Handle:Stop(fadeTime)
	local st = self._st
	if st and st.alive then
		local fade = tonumber(fadeTime)
		if fade and fade == fade then
			st.fadeOut = math.max(fade, 0)
		end
		st.target = 0
		st.endAt = nil
	end
end

function Handle:Set(param, value)
	local st = self._st
	if st and st.alive then
		st.p[param] = value
	end
	return self
end

function Handle:IsPlaying()
	local st = self._st
	return st ~= nil and st.alive == true and st.target > 0
end

local DEAD = setmetatable({}, Handle) -- what Play hands back when it can't play: every method does nothing
local NO_OPTS = table.freeze({})
local running = false

-- The frame loop starts with Init, or with the first pose if somebody plays one before that.
local function start()
	if not running then
		running = true
		RunService.PreSimulation:Connect(step)
	end
end

local function byPriority(a, b)
	if a.priority ~= b.priority then
		return a.priority < b.priority
	end
	return a.order < b.order
end

function PoseClient.Play(character, poseName, opts)
	local def = POSES[poseName]
	if not def or typeof(character) ~= "Instance" or not character:IsA("Model") then
		return DEAD
	end
	local c = track(character)
	if not c then
		return DEAD
	end
	start()
	opts = type(opts) == "table" and opts or NO_OPTS
	local now = os.clock()
	local st = findPose(c, poseName)
	local priority = tonumber(opts.Priority) or def.Priority or 50
	local resort = false
	if not st then
		orderCount += 1
		st = {
			name = poseName, def = def, alive = true,
			w = 0, blend = 0, target = 1, max = 1,
			p = {}, -- the pose's settings (opts, then whatever is Set)
			seed = math.random() * 10, -- so two characters never move in step
			order = orderCount, t0 = now,
		}
		st.handle = setmetatable({ _st = st }, Handle)
		table.insert(c.poses, st)
		resort = true
	elseif st.priority ~= priority then
		resort = true
	end
	for key, value in pairs(opts) do
		st.p[key] = value
	end
	local weight = tonumber(opts.Weight) or 1
	st.max = weight == weight and clamp(weight, 0, 1) or 1
	st.fadeIn = math.max(tonumber(opts.FadeIn) or def.FadeIn or 0.2, 0)
	st.fadeOut = math.max(tonumber(opts.FadeOut) or def.FadeOut or 0.25, 0)
	st.priority = priority
	st.target = 1
	local duration = tonumber(opts.Duration) or def.Duration
	if duration and duration == duration and duration > 0 then
		st.t0 = now -- a timed pose starts over
		st.dur = duration
		st.endAt = now + (def.Envelope and duration or math.max(duration - st.fadeOut, 0))
	else
		st.dur = nil
		st.endAt = nil
	end
	st.needInit = true
	if resort then
		table.sort(c.poses, byPriority)
	end
	return st.handle
end

function PoseClient.Get(character, poseName)
	local c = chars[character]
	local st = c and findPose(c, poseName)
	if st and st.target > 0 then
		return st.handle
	end
	return nil
end

function PoseClient.IsPlaying(character, poseName)
	return PoseClient.Get(character, poseName) ~= nil
end

function PoseClient.StopAll(character, fadeTime)
	local c = chars[character]
	if not c then
		return
	end
	for _, st in ipairs(c.poses) do
		st.handle:Stop(fadeTime)
	end
end

function PoseClient.Register(name, def)
	if type(name) ~= "string" or type(def) ~= "table" then
		return false
	end
	POSES[name] = def
	return true
end

-- The tools the built-in poses are written with, for poses added through Register.
--   Joint.<name> -> index (Root, Waist, Neck, RightShoulder ... LeftAnkle)
--   add(c, joint, rotation, w)   set(c, joint, transform, w)   shift(c, joint, offset)
--   arm(c, c.armR | c.armL, wristTarget, elbowPole, w, wristTurn?, handRotation?)   (UpperTorso space)
--   crouch(c, k, w) -> thigh angle       pointOf(st) -> Vector3?
--   rootCF(c)   torsoInRoot(c)   toTorso(c, worldPoint)   (the last two in Upper functions only)
PoseClient.Kit = {
	Joint = JOINT_INDEX,
	add = add, set = set, shift = shift, arm = arm, crouch = crouch, pointOf = pointOf,
	rootCF = rootCF, torsoInRoot = torsoInRoot, toTorso = toTorso,
}

function PoseClient.Names()
	local names = {}
	for name in pairs(POSES) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

------------------------------------------------------------------ poses everyone sees

local showing = {} -- [Player] = { name, char, handle }: the pose their "Pose" attribute asks for
local wanted = nil -- the pose we asked the server to show on us (shown here without waiting for it)
local poseRemote
local syncToken = 0
local lastAsk, lastAskOn, lastAskAt = nil, nil, 0 -- the last request sent (name, on, os.clock())

-- Make `plr`'s character show the pose `name` (nil = none). again: it was asked for afresh, so a pose
-- that is already showing starts over (a second wave).
local function showShared(plr, name, again)
	local rec = showing[plr]
	local char = plr.Character
	if rec then
		if rec.name == name and rec.char == char then
			-- Already showing it. A pose that runs out by itself (a wave) is shown once per request, so it
			-- isn't started again just because the attribute is still there.
			if not again and (rec.handle:IsPlaying() or POSES[name].Duration) then
				return
			end
		else
			rec.handle:Stop()
		end
		showing[plr] = nil
	end
	if name and char and POSES[name] then
		local handle = PoseClient.Play(char, name)
		if handle:IsPlaying() then
			showing[plr] = { name = name, char = char, handle = handle }
		end
	end
end

local function refreshShared(plr, again)
	local name = wanted
	if plr ~= player then
		name = plr:GetAttribute(PoseClient.Attribute)
	end
	showShared(plr, type(name) == "string" and name or nil, again)
end

local function send(name, on)
	if poseRemote then
		poseRemote:FireServer(name, on)
	end
end

-- A request can be dropped (the rate limit, or the remote wasn't there yet): look again in a moment and
-- ask once more if the server still shows something else.
local function syncSoon(tries)
	syncToken += 1
	local token = syncToken
	task.delay(1.2, function()
		if token ~= syncToken then
			return
		end
		local have = player:GetAttribute(PoseClient.Attribute)
		if have == wanted then
			return
		end
		if wanted then
			send(wanted, true)
		elseif type(have) == "string" then
			send(have, false)
		end
		if tries > 1 then
			syncSoon(tries - 1)
		end
	end)
end

function PoseClient.Broadcast(poseName, on)
	if type(poseName) ~= "string" or not POSES[poseName] then
		return false
	end
	on = on ~= false
	local now = os.clock()
	if lastAsk == poseName and lastAskOn == on and now - lastAskAt < 1 then
		return true -- the same request again within a second (a caller asking every frame): already on its way
	end
	local have = player:GetAttribute(PoseClient.Attribute)
	if on then
		if wanted == poseName and have == poseName and not POSES[poseName].Duration then
			local rec = showing[player]
			if rec and rec.name == poseName and rec.handle:IsPlaying() then
				return true -- already showing, and the server already knows
			end
		end
		wanted = poseName
	else
		if wanted ~= poseName and have ~= poseName then
			return true -- nothing to switch off
		end
		if wanted == poseName then
			wanted = nil
		end
	end
	lastAsk, lastAskOn, lastAskAt = poseName, on, now
	refreshShared(player, on)
	send(poseName, on)
	syncSoon(2)
	return true
end

------------------------------------------------------------------ limp falls (the server's ragdolls)

local attrFall = nil -- our own character, when it lay down only because its joints went loose
local bodies = {} -- [Player] = { char, conn }: the body whose "Ragdolled" attribute we are listening to (see watchBody)

-- The server's word on a knock-down (remote "Ragdoll"). "Down": whoever it is braces if there is a
-- brace, and if it is us we lie down for `seconds` (a new time if we already do: a tumble we started
-- ourselves is on the server's clock from here). "Up": ours ends now.
local function onRagdoll(char, kind, seconds, impulse, brace)
	if typeof(char) ~= "Instance" or not char:IsA("Model") then
		return -- (too far away to exist on this device)
	end
	if kind == "Down" then
		brace = tonumber(brace) or 0
		if brace == brace and brace > 0 then
			PoseClient.Play(char, "Brace", { Duration = math.min(brace, 1) + 0.15 })
		end
		if char == player.Character then
			seconds = tonumber(seconds) or 2.5
			if seconds ~= seconds then
				seconds = 2.5
			end
			attrFall = nil
			Ragdoll.Fall(char, clamp(seconds, 0.3, 12), typeof(impulse) == "Vector3" and impulse or nil)
		end
	elseif kind == "Up" and char == player.Character then
		attrFall = nil
		Ragdoll.GetUp(char)
	end
end

-- A player's joints went loose, or whole again (the character attribute "Ragdolled", which the server
-- sets and every device sees).
local function limpChanged(plr, char)
	if plr.Character ~= char then
		return
	end
	local limp = char:GetAttribute(Ragdoll.Attribute) == true
	if limp then
		-- Anybody's body: read how it lies while it is loose, so that going whole again isn't a jump.
		PoseClient.Play(char, "Recover")
	end
	if plr ~= player then
		return
	end
	if limp then
		-- Normally the "Down" message has us lying down already; if it never came, lie down anyway:
		-- standing on loose legs looks far worse.
		if not Ragdoll.IsDown(char) and Ragdoll.Fall(char, FALL_FAILSAFE) then
			attrFall = char
		end
		return
	end
	-- Whole again, a moment before the get-up. The limbs stop being solid now: stiff once more and
	-- swinging back to the animation, a solid leg that straightens into a wall would shove the body.
	Ragdoll.Settle(char)
	if attrFall == char then
		attrFall = nil
		Ragdoll.GetUp(char)
	end
end

-- Listen to the body `plr` has now. Called whenever that may have changed (and once a second by
-- housekeeping: a body can arrive late or be made again by streaming without any signal); it does
-- nothing while the body is still the one being listened to.
local function watchBody(plr)
	local char = plr.Character
	local rec = bodies[plr]
	if not rec then
		rec = {} -- (kept even while they have no body: it marks the player as one we look after)
		bodies[plr] = rec
	elseif rec.char == char then
		return
	end
	if rec.conn then
		rec.conn:Disconnect()
		rec.conn = nil
	end
	rec.char = char
	if plr == player then
		attrFall = nil -- (that was the old body's)
	end
	if not char then
		return
	end
	rec.conn = char:GetAttributeChangedSignal(Ragdoll.Attribute):Connect(function()
		limpChanged(plr, char)
	end)
	if char:GetAttribute(Ragdoll.Attribute) == true then
		limpChanged(plr, char) -- already loose when we first see it
	end
end

local function watchPlayer(plr)
	plr:GetAttributeChangedSignal(PoseClient.Attribute):Connect(function()
		local again = true
		if plr == player then
			-- The server has the last word (it may also set a pose itself, or refuse ours). When it only
			-- confirms what we already show, the pose isn't started over.
			local value = plr:GetAttribute(PoseClient.Attribute)
			value = type(value) == "string" and value or nil
			local rec = showing[plr]
			again = not (rec and rec.name == value)
			wanted = value
		end
		refreshShared(plr, again)
	end)
	plr.CharacterAdded:Connect(function()
		if plr == player then
			wanted = nil -- (the server clears the attribute for a new body too)
			lastAsk = nil
		end
		watchBody(plr)
		task.defer(refreshShared, plr)
	end)
	watchBody(plr)
	refreshShared(plr)
end

-- Once a second: the pose range follows the Performance setting, shared poses are put right for anyone
-- whose body arrived late (a respawn, streaming in) or whose pose was stopped by something else, and
-- every player's present body is the one listened to for going limp.
housekeeping = function()
	local low = false
	local module = script.Parent:FindFirstChild("SettingsClient")
	if module then
		local ok, value = pcall(function()
			return require(module).Get("Performance")
		end)
		low = ok and value == true
	end
	range = low and RANGE_LOW or RANGE
	for _, plr in ipairs(Players:GetPlayers()) do
		if bodies[plr] then
			watchBody(plr) -- (only players watchPlayer has taken on: nothing is wired before Init)
		end
		if showing[plr] or plr == player and wanted or plr:GetAttribute(PoseClient.Attribute) ~= nil then
			refreshShared(plr)
		end
	end
end

------------------------------------------------------------------ init

function PoseClient.Init()
	-- Fetched in its own thread: the client version of Remotes.Event waits for the server to make it.
	task.spawn(function()
		poseRemote = Remotes.Event(PoseClient.Remote)
	end)
	Remotes.OnClient("Ragdoll", onRagdoll)
	-- Ragdolls started on this device (PedClient's walkers, and our own tumble) brace through us too...
	Ragdoll.BraceHook = function(char, seconds)
		PoseClient.Play(char, "Brace", { Duration = seconds + 0.15 })
	end
	-- ...and a body loosened on this device is read while it is loose, like the players' (limpChanged).
	Ragdoll.LimpHook = function(char)
		PoseClient.Play(char, "Recover")
	end
	-- (watchPlayer also listens to each player's body going limp: watchBody)
	for _, plr in ipairs(Players:GetPlayers()) do
		watchPlayer(plr)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(plr)
		showing[plr] = nil
		local rec = bodies[plr]
		bodies[plr] = nil
		if rec and rec.conn then
			rec.conn:Disconnect()
		end
	end)
	start()
end

return PoseClient
