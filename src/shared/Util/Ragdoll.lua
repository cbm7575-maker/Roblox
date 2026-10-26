-- Ragdoll (ModuleScript, ReplicatedStorage.Shared.Util.Ragdoll)
-- R15 bodies that go limp on demand and stand back up. Kid-safe: nobody is hurt, a limp body is only a
-- fall, and it always gets up again.
--
-- A fall has two halves, and they may run on different machines:
--   * The JOINTS go loose. Whoever owns the model's instances does this, so everyone sees it: the server
--     for a player's character (and its own NPCs), this device for models it made itself (PedClient's
--     walkers). Two kinds of body are handled, joint by joint, by looking at what is really in the
--     character (so it doesn't matter whether StarterPlayer.AvatarJointUpgrade is on):
--       - Upgraded joints: the joint (an AnimationConstraint, or a Motor6D) already has a
--         BallSocketConstraint between the same two parts. The joint is switched off (.Enabled) and the
--         built-in socket takes over; switched back on afterwards. Root, Neck and Waist stay stiff.
--       - Old joints: a plain Motor6D. It is switched off (never removed, so C0 / C1 come back exactly) and
--         a BallSocketConstraint "NCRagdoll" with its own two Attachments holds the parts together, plus a
--         NoCollisionConstraint between the two neighbours (they overlap at the joint). Root and Neck stay
--         stiff: a body without its neck joint counts as gone, and here nobody is ever gone.
--       The pieces are made once per character and only switched on and off after that.
--     Socket limits are written as "the middle of what this joint can do" plus a cone and a twist either
--     way (see LIMITS), so elbows and knees fold the right way and arms don't swing through the chest.
--   * The BODY falls. The device that simulates the character does this (a player's own device for
--     their character; whoever made the model otherwise): Humanoid state Physics (with GettingUp
--     switched off so it stays down), limbs set to collide so they rest on the ground, the push, and
--     GettingUp at the end. The moment the joints are whole again the limbs stop being solid
--     (Ragdoll.Settle), so a leg that straightens into a wall or a kerb can't shove the body about.
-- The character attribute "Ragdolled" (true while the joints are loose) is set by whoever loosened them;
-- from the server it reaches every device, so Ragdoll.IsRagdolled works everywhere.
-- Going whole again is not a jump on screen when PoseClient runs on the device: it reads the limp pose
-- off the body every frame and blends it back into the animation afterwards (its "Recover" pose;
-- Ragdoll.LimpHook starts that for bodies loosened here). Without PoseClient the limbs snap back.
--
-- API
--   Ragdoll.Start(character, impulse?, opts?) -> bool        (short form: Ragdoll.Start(character, seconds))
--       impulse: the velocity (studs/s) the body leaves with; the torso also gets a spin that tips the
--         head the same way. nil = it keeps moving as it was, and tips over along that motion (a body
--         that is already down is left as it lies).
--       opts.Seconds   stop by itself after this long (without it, call Ragdoll.Stop)
--       opts.Brace     true: the body falls stiff for Ragdoll.BraceTime (0.3 s) first, arms over the head
--                      (Ragdoll.BraceHook, set by PoseClient, plays that pose), then goes loose
--       opts.Spin      Vector3 angular velocity instead of the automatic one
--       opts.OnStop    function(character) when it ends (not when the model is destroyed, and not for
--                      your own character). A second Start on a body that is already down replaces it:
--                      the latest caller is the one waiting for it to get up.
--       opts.NoCap     true: don't count against the cap
--       opts.JointsOnly   your own character only. true: don't lie down here, only ask the server for
--                      the loose joints. For a caller that already does the fall itself and decides when
--                      the body stands (ImpactClient's traffic knock): for that fall this module looks
--                      after the limbs' collisions and leaves standing the body up to the caller. Ask
--                      for a little less than your own time on the ground (take the round trip off):
--                      the joints must be whole again before you stand the body up.
--     Where it runs decides what it does:
--       server, a player's character   joints only. Use RagdollService.KnockDown instead: it also tells
--                                      the player's device to fall and get up.
--       server, any other model        joints and the fall
--       client, a model made here      joints and the fall, at most Ragdoll.Cap() at once (4 on phones,
--                                      8 elsewhere); false when the cap is reached, so the caller can do
--                                      something cheaper
--       client, your own character     lies down here at once (the fall is this device's; waiting for an
--                                      answer would leave it standing for a round trip first) and asks
--                                      the server for the loose joints (remote "RagdollSelf":
--                                      RagdollService checks it; Ragdoll.SelfSeconds unless opts.Seconds,
--                                      at most Ragdoll.SelfMaxSeconds), so everyone sees them. If the
--                                      server says no (asked too often, tasered) it is still a stiff
--                                      tumble that gets up by itself. false, and nothing happens, when it
--                                      can't fall (seated, swimming, tasered) or RagdollService isn't
--                                      running. Already lying down (a knock-down, or your own
--                                      Ragdoll.Fall just before): true, the body is left as it lies and
--                                      only the joints are asked for. For a tumble after a big fall.
--       client, someone else's         false
--   Ragdoll.Stop(character) -> bool           whole again and getting up (same rules about who may). On
--                                             your own character it asks the server, and ends at once a
--                                             tumble the server hasn't answered yet.
--   Ragdoll.IsRagdolled(character) -> bool    joints loose right now, on any device
--   Ragdoll.Fall(character, seconds?, impulse?, opts?) -> bool
--   Ragdoll.GetUp(character) -> bool
--   Ragdoll.Settle(character) -> bool
--       Only the body half, on this device (PoseClient calls them for your own character: Fall / GetUp
--       when the server says so, Settle when the joints are whole again and the limbs should stop being
--       solid though the body still lies there). Fall: never while seated, swimming or tasered; called
--       on a body that is already down it is a new time, and a new shove only if an impulse is given.
--       GetUp only stands a body that is still lying down: one that something else already stood up
--       (ImpactClient's own timer) is left alone, so nobody gets up twice.
--   Ragdoll.IsDown(character) -> bool         this device has it lying in the Physics state
--   Ragdoll.Stagger(character, seconds?, strength?) -> bool
--       A short "powered" wobble: arm and leg joints follow the animation with only `strength` (0.25) of
--       their force for `seconds` (0.4). Upgraded bodies only (it needs AnimationConstraints); false on
--       old bodies, where PoseClient's Flinch pose is the stand-in. Server for players' characters.
--   Ragdoll.Count() / Ragdoll.Cap()           capped ragdolls running on this device / the limit
--   Ragdoll.Mode(character) -> "Upgrade" | "Legacy" | nil     which kind of joints this body has
--   Ragdoll.UpgradeSetting() -> string?       what the place asked for (logs only; never decides anything)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ragdoll = {}

local IS_SERVER = RunService:IsServer()
local STATE = Enum.HumanoidStateType

Ragdoll.Attribute = "Ragdolled"
Ragdoll.BraceTime = 0.3 -- seconds of stiff fall with the arms up before the joints go loose
Ragdoll.CapMobile = 4
Ragdoll.CapPC = 8
Ragdoll.MaxPush = 150 -- studs/s: a bigger impulse is shortened to this
Ragdoll.SelfRemote = "RagdollSelf" -- made by RagdollService
Ragdoll.SelfSeconds = 1.6 -- a tumble a player starts on their own character, when no time is given...
Ragdoll.SelfMaxSeconds = 4 -- ...and the longest one (RagdollService uses the same two numbers)
Ragdoll.BraceHook = nil -- function(character, seconds): PoseClient puts its "Brace" pose here
Ragdoll.LimpHook = nil -- function(character): a body was loosened on this device (PoseClient's "Recover")

local MADE = "NCRagdoll" -- the name of every instance this module adds to a character
local SPIN = 6 -- rad/s: how fast the torso tips over along the push (the same as ImpactClient's stiff fall)
local FRICTION = 6 -- a little drag in each socket, so limbs settle instead of swinging on
local STAGGER_TORQUE = 400 -- used when an upgraded joint has no finite force of its own to scale
local NO_OPTS = table.freeze({})

------------------------------------------------------------------ joint limits

local RAD = math.rad

local function rx(degrees)
	return CFrame.Angles(RAD(degrees), 0, 0)
end

local function rz(degrees)
	return CFrame.Angles(0, 0, RAD(degrees))
end

-- A ball socket limits two things: how far its attachments' X axes may lean apart (the cone) and how
-- far one may turn about that axis (the twist). So each joint says which way its sockets' X axis points
-- in the part...
local ALONG_LIMB = rz(-90) -- X = the part's -Y: down the arm or leg
local ALONG_SPINE = rz(90) -- X = the part's +Y
local HINGE = CFrame.new() -- X = the part's X: the axis an elbow or knee folds about

-- ...and where the middle of its range is: Mid is what the joint's Transform would be there. Forward
-- is a turn about +X (an arm or thigh swinging to the front, an elbow folding); a knee folds the other
-- way. Out to the side is +Z for right limbs and -Z for left ones. Cone and Twist are degrees either
-- side of Mid, the same both ways, so nothing here depends on which way the engine counts a twist.
local LIMITS = {
	Waist = { Frame = ALONG_SPINE, Mid = rx(-8), Cone = 22, Twist = 18 },
	RightShoulder = { Frame = ALONG_LIMB, Mid = rz(40) * rx(15), Cone = 70, Twist = 40 },
	LeftShoulder = { Frame = ALONG_LIMB, Mid = rz(-40) * rx(15), Cone = 70, Twist = 40 },
	RightElbow = { Frame = HINGE, Mid = rx(65), Cone = 8, Twist = 65 }, -- straight .. folded 130 degrees
	LeftElbow = { Frame = HINGE, Mid = rx(65), Cone = 8, Twist = 65 },
	RightWrist = { Frame = ALONG_LIMB, Mid = CFrame.new(), Cone = 30, Twist = 20 },
	LeftWrist = { Frame = ALONG_LIMB, Mid = CFrame.new(), Cone = 30, Twist = 20 },
	RightHip = { Frame = ALONG_LIMB, Mid = rz(8) * rx(25), Cone = 50, Twist = 25 },
	LeftHip = { Frame = ALONG_LIMB, Mid = rz(-8) * rx(25), Cone = 50, Twist = 25 },
	RightKnee = { Frame = HINGE, Mid = rx(-62), Cone = 8, Twist = 62 }, -- straight .. folded back 124 degrees
	LeftKnee = { Frame = HINGE, Mid = rx(-62), Cone = 8, Twist = 62 },
	RightAnkle = { Frame = ALONG_LIMB, Mid = CFrame.new(), Cone = 20, Twist = 15 },
	LeftAnkle = { Frame = ALONG_LIMB, Mid = CFrame.new(), Cone = 20, Twist = 15 },
}

-- The fifteen joints of an R15 body. Anything else (a gun's Motor6D, accessory welds) is left alone.
local STANDARD = { Root = true, Neck = true }
for name in pairs(LIMITS) do
	STANDARD[name] = true
end
local RIGID = { Root = true, Neck = true } -- never loosened
local RIGID_UPGRADE = { Waist = true } -- also kept stiff on upgraded bodies (their own socket limits are unknown)
local STAGGER = {
	RightShoulder = true, LeftShoulder = true, RightElbow = true, LeftElbow = true,
	RightHip = true, LeftHip = true, RightKnee = true, LeftKnee = true,
}

------------------------------------------------------------------ state

-- [character] = {
--   character, hum, root (HumanoidRootPart), parts (its body parts), conn,
--   rig        { list = { { joint, p0, p1, socket, apart, builtIn, ... } }, upgraded } once built
--   limp       the joints are loose (this machine loosened them)
--   pending    bracing: the joints go loose in a moment
--   simulate   this machine also does the fall for this ragdoll
--   down       this machine has the body in the Physics state (downAt = os.clock() when it went down)
--   settled    still down, but the limbs are no longer solid (the joints are whole again)
--   selfFall   down because the player asked (Start on their own character) and the server hasn't answered
--   askedAt    os.clock() of the last "ragdoll me" sent to the server for this body
--   hostUntil  os.clock() until which somebody else has this body down and stands it up (JointsOnly)
--   collide    { [part] = CanCollide before the fall }
--   token, stopToken, fallToken   only the latest timer of each kind counts
--   counted    it takes one place under the cap
--   onStop
-- }
local entries = {}
local capped = 0
local staggers = {} -- [character] = { saved = { [joint] = { IsKinematic, MaxTorque } }, token }
local selfRemote

------------------------------------------------------------------ helpers

-- A finite Vector3 no longer than `limit`, or nil.
local function clean(v, limit)
	if typeof(v) ~= "Vector3" or v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
		return nil
	end
	local m = v.Magnitude
	if m == math.huge then
		return nil
	end
	if m > limit then
		v = v.Unit * limit
	end
	return v
end

-- The Humanoid of a living R15 model in the world, or nil.
local function usable(character)
	if typeof(character) ~= "Instance" or not character:IsA("Model") or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R15 or hum.Health <= 0 then
		return nil
	end
	return hum
end

-- The two parts a joint holds together and where the joint sits in each (C0 / C1), for both kinds.
local function ends(joint)
	if joint:IsA("Motor6D") then
		local p0, p1 = joint.Part0, joint.Part1
		if p0 and p1 then
			return p0, p1, joint.C0, joint.C1
		end
		return nil
	end
	local a0, a1 = joint.Attachment0, joint.Attachment1
	local p0, p1 = a0 and a0.Parent, a1 and a1.Parent
	if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
		return p0, p1, a0.CFrame, a1.CFrame
	end
	return nil
end

-- Does this constraint join exactly these two parts?
local function between(constraint, p0, p1)
	local a0, a1 = constraint.Attachment0, constraint.Attachment1
	local q0, q1 = a0 and a0.Parent, a1 and a1.Parent
	return (q0 == p0 and q1 == p1) or (q0 == p1 and q1 == p0)
end

local function forget(character)
	local e = entries[character]
	if not e then
		return
	end
	entries[character] = nil
	staggers[character] = nil
	if e.conn then
		e.conn:Disconnect()
	end
	if e.counted then
		e.counted = false
		capped -= 1
	end
end

local function refreshParts(e)
	local parts = e.parts
	table.clear(parts)
	for _, child in ipairs(e.character:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
end

local function entryOf(character, hum)
	local e = entries[character]
	if e then
		return e
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	e = { character = character, hum = hum, root = root, parts = {}, token = 0, stopToken = 0, fallToken = 0 }
	e.conn = character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			forget(character) -- gone (respawn, a walker recycled): nothing left to put back
		end
	end)
	entries[character] = e
	return e
end

------------------------------------------------------------------ the joints

-- A socket of our own for one old joint: its two Attachments sit on the joint, turned so the limits in
-- LIMITS mean what they say. With the joint's Transform at spec.Mid the two Attachments line up exactly.
local function makeSocket(rec, spec, c0, c1)
	local a0 = Instance.new("Attachment")
	a0.Name = MADE
	a0.CFrame = c0 * spec.Mid * spec.Frame
	a0.Parent = rec.p0
	local a1 = Instance.new("Attachment")
	a1.Name = MADE
	a1.CFrame = c1 * spec.Frame
	a1.Parent = rec.p1
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = MADE
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = true
	socket.UpperAngle = spec.Cone
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -spec.Twist
	socket.TwistUpperAngle = spec.Twist
	socket.Restitution = 0
	socket.MaxFrictionTorque = FRICTION
	socket.Enabled = false -- until the body goes limp
	socket.Parent = rec.p1
	rec.socket = socket
end

-- Find the body's joints and get a socket ready for each one that may go loose. Returns false when
-- there is nothing to loosen (not a standard R15 body).
local function buildRig(e)
	local character = e.character
	-- Pieces from an older build (a body part was swapped under us) go first.
	for _, d in ipairs(character:GetDescendants()) do
		if d.Name == MADE then
			d:Destroy()
		end
	end
	local joints, sockets, aparts = {}, {}, {}
	for _, d in ipairs(character:GetDescendants()) do
		if STANDARD[d.Name] and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
			table.insert(joints, d)
		elseif d:IsA("BallSocketConstraint") then
			table.insert(sockets, d)
		elseif d:IsA("NoCollisionConstraint") then
			table.insert(aparts, d)
		end
	end
	local rig = { list = {}, upgraded = false }
	for _, joint in ipairs(joints) do
		local name = joint.Name
		local p0, p1, c0, c1 = ends(joint)
		if p0 and not RIGID[name] then
			local rec = { joint = joint, p0 = p0, p1 = p1 }
			for _, s in ipairs(sockets) do
				if between(s, p0, p1) then
					rec.socket = s
					rec.builtIn = true
					rig.upgraded = true
					break
				end
			end
			if not (rec.builtIn and RIGID_UPGRADE[name]) then
				if not rec.socket then
					makeSocket(rec, LIMITS[name], c0, c1)
				end
				for _, a in ipairs(aparts) do
					if (a.Part0 == p0 and a.Part1 == p1) or (a.Part0 == p1 and a.Part1 == p0) then
						rec.apart = a
						rec.apartBuiltIn = true
						break
					end
				end
				if not rec.apart then
					local apart = Instance.new("NoCollisionConstraint")
					apart.Name = MADE
					apart.Part0 = p0
					apart.Part1 = p1
					apart.Enabled = false
					apart.Parent = p1
					rec.apart = apart
				end
				table.insert(rig.list, rec)
			end
		end
	end
	e.rig = rig
	return #rig.list > 0
end

-- Is everything we found (or made) still in the character? Changing clothes or body parts replaces them.
local function rigValid(rig)
	if #rig.list == 0 then
		return false
	end
	for _, rec in ipairs(rig.list) do
		if not rec.joint.Parent or not rec.socket.Parent or not rec.apart.Parent or not rec.p0.Parent or not rec.p1.Parent then
			return false
		end
	end
	return true
end

-- Loosen or lock every joint. Returns false if the body has no joints we can loosen.
local function setLimp(e, on)
	if on then
		if e.limp then
			return true
		end
		if not e.rig or not rigValid(e.rig) then
			if not buildRig(e) then
				return false
			end
		end
		for _, rec in ipairs(e.rig.list) do
			-- The socket first, so the two parts are never held by nothing.
			rec.socketWas = rec.socket.Enabled
			rec.socket.Enabled = true
			rec.apartWas = rec.apart.Enabled
			rec.apart.Enabled = true
			rec.jointWas = rec.joint.Enabled
			rec.joint.Enabled = false
		end
		e.limp = true
		e.character:SetAttribute(Ragdoll.Attribute, true)
		local hook = Ragdoll.LimpHook
		if hook then
			task.spawn(hook, e.character)
		end
		return true
	end
	if not e.limp then
		return true
	end
	e.limp = false
	for _, rec in ipairs(e.rig.list) do
		-- The joint first, for the same reason. (Pieces that were swapped out meanwhile are skipped.)
		if rec.joint.Parent then
			rec.joint.Enabled = rec.jointWas ~= false
		end
		if rec.socket.Parent then
			rec.socket.Enabled = rec.builtIn == true and rec.socketWas == true
		end
		if rec.apart.Parent then
			rec.apart.Enabled = rec.apartBuiltIn == true and rec.apartWas == true
		end
	end
	if e.character.Parent then
		e.character:SetAttribute(Ragdoll.Attribute, nil)
	end
	return true
end

------------------------------------------------------------------ the fall

-- Limbs normally pass through the world (the Humanoid keeps the body up by itself). Lying down they
-- have to rest on it, and the root box has to get out of the way or the body would lie on that instead.
local function setCollide(e, on)
	if on then
		local saved = e.collide
		if not saved then
			saved = {}
			e.collide = saved
		end
		for _, part in ipairs(e.parts) do
			if part.Parent then
				if saved[part] == nil then
					saved[part] = part.CanCollide
				end
				part.CanCollide = part ~= e.root
			end
		end
		return
	end
	local saved = e.collide
	e.collide = nil
	if saved then
		for part, was in pairs(saved) do
			if part.Parent then
				part.CanCollide = was
			end
		end
	end
end

-- How the body is moving right now (a finite velocity, or nil).
local function moving(e)
	local root = e.root
	return root.Parent and clean(root.AssemblyLinearVelocity, Ragdoll.MaxPush) or nil
end

-- Send the body off at `impulse` (every part gets it, so it works whether the joints are loose yet or
-- not) and tip the torso over along it. No impulse: it keeps the speed it has, and `along` (the way it
-- is moving, see moving) is only the way it tips; without that either, it is left as it is.
local function push(e, impulse, spin, along)
	local root = e.root
	if not root.Parent then
		return
	end
	if impulse then
		for _, part in ipairs(e.parts) do
			if part.Parent then
				part.AssemblyLinearVelocity = impulse
			end
		end
	end
	spin = clean(spin, 40)
	local way = impulse or along
	if not spin and way then
		local flat = Vector3.new(way.X, 0, way.Z)
		local m = flat.Magnitude
		if m > 0.5 then
			-- Spinning about (up x direction) makes the head fall the way the body is pushed.
			spin = Vector3.yAxis:Cross(flat / m) * (SPIN * math.min(m / 10, 1))
		end
	end
	if spin then
		for _, part in ipairs(e.parts) do
			if part.Parent and (part == root or part.Name == "UpperTorso" or part.Name == "LowerTorso") then
				part.AssemblyAngularVelocity = spin
			end
		end
	end
end

-- Physics state: the Humanoid stops balancing and stops touching CanCollide, so the body is only a
-- body. GettingUp is switched off or it would stand straight back up.
local function down(e)
	local hum = e.hum
	e.down = true
	e.downAt = os.clock()
	e.settled = nil
	hum:SetStateEnabled(STATE.GettingUp, false)
	hum:ChangeState(STATE.Physics)
	setCollide(e, true)
	-- Once more a moment later, and again after a brace: the change of state can put the limbs'
	-- collisions back to how a standing body has them. (Not once the body has settled: on a short fall
	-- the second of these would make the limbs solid again.)
	local token = e.fallToken
	local function again()
		if entries[e.character] == e and e.down and not e.settled and e.fallToken == token then
			setCollide(e, true)
		end
	end
	task.delay(0.05, again)
	task.delay(Ragdoll.BraceTime + 0.1, again)
end

-- Stand the body up, if it is still lying in our state (Physics). One that something else has stood up
-- already (ImpactClient runs its own timer for the same fall) is left alone: it would get up a second
-- time. sure: don't look at the state (see up).
local function stand(e, sure)
	local hum = e.hum
	if not hum.Parent then
		return
	end
	hum:SetStateEnabled(STATE.GettingUp, true)
	if (sure or hum:GetState() == STATE.Physics) and hum.Health > 0 and not hum.SeatPart then
		hum:ChangeState(STATE.GettingUp)
	end
end

local function up(e)
	if not e.down then
		return
	end
	local hosted = e.hostUntil ~= nil and os.clock() < e.hostUntil
	e.hostUntil = nil
	e.down = false
	e.settled = nil
	e.selfFall = nil
	setCollide(e, false)
	if hosted then
		-- Start(..., { JointsOnly = true }): the caller laid this body down and stands it up by its
		-- own clock. Standing it here as well would be a get-up too early, and then theirs on top.
		-- Only if it still lies there long after (the caller never did) is it stood up from here, so
		-- that no mix-up can leave a body on the ground for good.
		local character = e.character
		task.delay(1.5, function()
			local hum = e.hum
			if entries[character] == e and not e.down and hum.Parent and hum:GetState() == STATE.Physics then
				stand(e, true)
			end
		end)
		return
	end
	-- (Right after lying down the Humanoid may not have changed state yet: then it is ours for sure.)
	stand(e, os.clock() - (e.downAt or 0) < 0.25)
end

-- Stop after `seconds`. longer: an earlier, later-ending timer is kept instead.
local function armStop(e, seconds, longer)
	local at = os.clock() + seconds
	if longer and e.stopAt and e.stopAt >= at then
		return
	end
	e.stopAt = at
	e.stopToken += 1
	local token, character = e.stopToken, e.character
	task.delay(seconds, function()
		if entries[character] == e and e.stopToken == token then
			Ragdoll.Stop(character)
		end
	end)
end

-- Your own character: only the server may loosen it (so everyone sees the same body). This is the
-- remote to ask it with, found without waiting; nil if RagdollService hasn't made it.
local function serverRemote()
	if not selfRemote or not selfRemote.Parent then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = folder and folder:FindFirstChild(Ragdoll.SelfRemote)
		if not remote or not remote:IsA("RemoteEvent") then
			return nil
		end
		selfRemote = remote
	end
	return selfRemote
end

-- Ragdoll.Start on your own character (client). The fall is this device's to do, so it happens now:
-- waiting for the server's answer would leave the body standing for a round trip first, and by then
-- the speed it landed with is gone. The server is only asked for the loose joints, and gets no push to
-- send back (the body would be shoved twice). Its "Down" message then sets the clock again; if it never
-- comes (asked too often, tasered there), this is a stiff tumble that gets up by itself.
local function startOwn(character, hum, seconds, impulse, opts)
	local remote = serverRemote()
	if not remote then
		return false
	end
	local brace = opts.Brace == true
	local e = entries[character]
	if opts.JointsOnly == true then
		-- The caller does the fall itself and stands the body up by its own clock. Until that fall is
		-- over (its time, and a second to spare), the server's "Down" and "Up" only change what is
		-- ours here, the limbs' collisions: up() leaves the Humanoid's state to the caller.
		e = e or entryOf(character, hum)
		if e then
			e.hostUntil = os.clock() + (seconds or Ragdoll.SelfSeconds) + 1
		end
	elseif not (e and e.down) then
		if (Players.LocalPlayer:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
			return false -- tasered: LawClient already holds them down
		end
		local length = math.clamp(seconds or Ragdoll.SelfSeconds, 0.5, Ragdoll.SelfMaxSeconds)
		if not Ragdoll.Fall(character, length, impulse, opts) then
			return false
		end
		e = entries[character]
		if e then
			e.selfFall = true
			e.hostUntil = nil -- this fall is ours to end
		end
		local hook = Ragdoll.BraceHook
		if brace and hook then
			task.spawn(hook, character, Ragdoll.BraceTime)
		end
	end
	-- (Otherwise it is lying down already, by a knock-down, an earlier tumble or the caller's own
	-- Ragdoll.Fall: nothing to add here, only the joints to ask for.)
	-- The server is asked even when the body was down already: it may have been the caller that laid
	-- it down (the server ignores the request while a knock-down of its own runs). At most twice a
	-- second, so a caller that keeps asking while the body lies there sends nothing new.
	local now = os.clock()
	if e then
		if e.askedAt and now - e.askedAt < 0.5 then
			return true
		end
		e.askedAt = now
	end
	remote:FireServer(true, seconds, nil, brace)
	return true
end

------------------------------------------------------------------ API

function Ragdoll.Cap()
	if IS_SERVER then
		return math.huge
	end
	local phone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return phone and Ragdoll.CapMobile or Ragdoll.CapPC
end

function Ragdoll.Count()
	return capped
end

function Ragdoll.Start(character, impulse, opts)
	if type(impulse) == "number" then
		-- The short form, Start(character, seconds): how LocomotionClient asks for its tumble.
		local short = impulse
		impulse = nil
		if type(opts) ~= "table" then
			opts = { Seconds = short }
		elseif opts.Seconds == nil then
			opts = table.clone(opts)
			opts.Seconds = short
		end
	end
	opts = type(opts) == "table" and opts or NO_OPTS
	local hum = usable(character)
	if not hum then
		return false
	end
	impulse = clean(impulse, Ragdoll.MaxPush)
	local seconds = tonumber(opts.Seconds)
	if seconds and (seconds ~= seconds or seconds <= 0) then
		seconds = nil
	end
	local owner = Players:GetPlayerFromCharacter(character)
	if owner and not IS_SERVER then
		if owner ~= Players.LocalPlayer then
			return false
		end
		return startOwn(character, hum, seconds, impulse, opts)
	end
	if hum.SeatPart then
		return false
	end
	local e = entryOf(character, hum)
	if not e then
		return false
	end
	local simulate = owner == nil -- (a player's own device does the fall for their character)
	if e.limp or e.pending then
		-- Already down: a new shove, and it stays down for the longer of the two times.
		if simulate and impulse then
			push(e, impulse, opts.Spin)
		end
		if seconds then
			armStop(e, seconds, true)
		end
		if type(opts.OnStop) == "function" then
			e.onStop = opts.OnStop -- the latest caller is the one waiting for it to get up
		end
		return true
	end
	if not IS_SERVER and opts.NoCap ~= true and not e.counted then
		if capped >= Ragdoll.Cap() then
			return false
		end
		e.counted = true
		capped += 1
	end
	e.token += 1
	local token = e.token
	e.simulate = simulate
	e.onStop = type(opts.OnStop) == "function" and opts.OnStop or nil
	e.stopAt = nil
	refreshParts(e)
	if simulate then
		e.fallToken += 1
		local along = moving(e)
		down(e)
		push(e, impulse, opts.Spin, along)
	end
	if opts.Brace == true then
		-- Stiff for a moment with the arms up (the pose is PoseClient's), then loose.
		e.pending = true
		local hook = Ragdoll.BraceHook
		if hook then
			task.spawn(hook, character, Ragdoll.BraceTime)
		end
		task.delay(Ragdoll.BraceTime, function()
			if entries[character] == e and e.token == token and e.pending then
				e.pending = false
				setLimp(e, true) -- (a body with no joints to loosen just stays stiff until it gets up)
			end
		end)
	elseif not setLimp(e, true) and not simulate then
		-- Nothing happened at all: no joints to loosen, and the fall isn't ours to do.
		if e.counted then
			e.counted = false
			capped -= 1
		end
		return false
	end
	if seconds then
		armStop(e, seconds)
	end
	return true
end

function Ragdoll.Stop(character)
	if typeof(character) ~= "Instance" then
		return false
	end
	if not IS_SERVER then
		local owner = Players:GetPlayerFromCharacter(character)
		if owner then
			if owner ~= Players.LocalPlayer then
				return false
			end
			local own = entries[character]
			if own and own.down and own.selfFall then
				-- A tumble the server hasn't answered (it may have said no): it is only ours, so it
				-- ends here. One the server did take up ends with its "Up" message.
				own.fallToken += 1
				up(own)
			end
			local remote = serverRemote()
			if not remote then
				return false
			end
			remote:FireServer(false)
			return true
		end
	end
	local e = entries[character]
	if not e then
		return false
	end
	local was = e.limp or e.pending or (e.simulate and e.down)
	e.token += 1
	e.stopToken += 1
	e.stopAt = nil
	e.pending = false
	setLimp(e, false)
	if e.simulate then
		e.fallToken += 1
		up(e)
	end
	if e.counted then
		e.counted = false
		capped -= 1
	end
	local done = e.onStop
	e.onStop = nil
	if done and was then
		task.spawn(done, character)
	end
	return was and true or false
end

function Ragdoll.IsRagdolled(character)
	if typeof(character) ~= "Instance" then
		return false
	end
	local e = entries[character]
	if e and e.limp then
		return true
	end
	return character:GetAttribute(Ragdoll.Attribute) == true
end

function Ragdoll.IsDown(character)
	local e = entries[character]
	return e ~= nil and e.down == true
end

-- The body half only, on this device: lie down (Physics state), take the push, get up after `seconds`
-- (nil: when Ragdoll.GetUp is called). Called again while down, it is a new time, and a new shove if
-- an impulse comes with it (without one a body that already lies there is not tipped again).
function Ragdoll.Fall(character, seconds, impulse, opts)
	opts = type(opts) == "table" and opts or NO_OPTS
	local hum = usable(character)
	if not hum or hum.SeatPart or hum.PlatformStand then
		return false -- (PlatformStand: a taser has them down, and LawClient decides when that ends)
	end
	local state = hum:GetState()
	if state == STATE.Swimming or state == STATE.Seated or state == STATE.Dead then
		return false
	end
	local e = entryOf(character, hum)
	if not e then
		return false
	end
	refreshParts(e)
	e.fallToken += 1
	local token = e.fallToken
	local along = not e.down and moving(e) or nil -- a fresh fall tips over the way the body was going
	e.selfFall = nil -- (Ragdoll.Start sets it again when the fall is its own)
	down(e)
	push(e, clean(impulse, Ragdoll.MaxPush), opts.Spin, along)
	seconds = tonumber(seconds)
	if seconds and seconds == seconds then
		task.delay(math.clamp(seconds, 0.1, 30), function()
			if entries[character] == e and e.fallToken == token then
				up(e)
			end
		end)
	end
	return true
end

function Ragdoll.GetUp(character)
	local e = entries[character]
	if not e or not e.down then
		return false
	end
	e.fallToken += 1
	up(e)
	return true
end

-- The joints are whole again but the body still lies there for a moment (the server locks them a
-- little before the get-up). The limbs stop being solid now: they are stiff again and about to swing
-- back to the animation's pose, and a solid leg that straightens into a wall, a kerb or a car would
-- shove the whole body away. The torso and head keep resting on the ground, and the root box stays out
-- of the way until the body stands (up() puts the rest back).
function Ragdoll.Settle(character)
	local e = entries[character]
	if not e or not e.down then
		return false
	end
	e.settled = true
	local saved = e.collide
	if saved then
		for part, was in pairs(saved) do
			if part ~= e.root and part.Parent then
				part.CanCollide = was
			end
		end
	end
	return true
end

function Ragdoll.Stagger(character, seconds, strength)
	local hum = usable(character)
	if not hum then
		return false
	end
	if not IS_SERVER and Players:GetPlayerFromCharacter(character) then
		return false -- only the server may loosen a player's joints
	end
	local e = entryOf(character, hum) -- (also so the saved values are forgotten with the model)
	if not e or e.limp or e.pending then
		return false
	end
	seconds = tonumber(seconds) or 0.4
	strength = tonumber(strength) or 0.25
	if seconds ~= seconds or strength ~= strength then
		return false
	end
	seconds = math.clamp(seconds, 0.1, 1.5)
	strength = math.clamp(strength, 0.05, 1)
	local s = staggers[character]
	if not s then
		local saved = {}
		for _, d in ipairs(character:GetDescendants()) do
			if STAGGER[d.Name] and d:IsA("AnimationConstraint") then
				local ok, was = pcall(function()
					local kinematic, torque = d.IsKinematic, d.MaxTorque
					d.IsKinematic = false
					d.MaxTorque = ((torque > 0 and torque < math.huge) and torque or STAGGER_TORQUE) * strength
					return { kinematic, torque }
				end)
				if ok then
					saved[d] = was
				end
			end
		end
		if next(saved) == nil then
			return false -- an old body (or an engine without those properties)
		end
		s = { saved = saved, token = 0 }
		staggers[character] = s
	end
	s.token += 1
	local token = s.token
	task.delay(seconds, function()
		if staggers[character] ~= s or s.token ~= token then
			return
		end
		staggers[character] = nil
		for joint, was in pairs(s.saved) do
			if joint.Parent then
				pcall(function()
					joint.MaxTorque = was[2]
					joint.IsKinematic = was[1]
				end)
			end
		end
	end)
	return true
end

function Ragdoll.Mode(character)
	if typeof(character) ~= "Instance" then
		return nil
	end
	local found = false
	local sockets, joints = {}, {}
	for _, d in ipairs(character:GetDescendants()) do
		if LIMITS[d.Name] then
			if d:IsA("AnimationConstraint") then
				return "Upgrade"
			elseif d:IsA("Motor6D") then
				found = true
				table.insert(joints, d)
			end
		elseif d:IsA("BallSocketConstraint") and d.Name ~= MADE then
			table.insert(sockets, d)
		end
	end
	for _, joint in ipairs(joints) do
		local p0, p1 = joint.Part0, joint.Part1
		for _, s in ipairs(sockets) do
			if p0 and p1 and between(s, p0, p1) then
				return "Upgrade"
			end
		end
	end
	return found and "Legacy" or nil
end

function Ragdoll.UpgradeSetting()
	for _, service in ipairs({ "StarterPlayer", "Workspace" }) do
		local ok, value = pcall(function()
			return game:GetService(service).AvatarJointUpgrade
		end)
		if ok and value ~= nil then
			return tostring(value)
		end
	end
	return nil
end

return Ragdoll
