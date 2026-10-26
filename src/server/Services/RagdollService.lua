-- RagdollService (ModuleScript, ServerScriptService.Services.RagdollService)
-- The one way to knock a player's character limp so that everyone sees it, plus the check on the poses
-- players show each other. Kid-safe: a limp body is only a fall; it always gets back up, unhurt.
--   * RagdollService.KnockDown(player, seconds, impulse, reason, opts?) -> bool
--       The character falls for `seconds` (0.5-10, default 2.5) and leaves at `impulse` (a velocity in
--       studs/s, at most 80; nil = it keeps moving as it was). Returns false when it can't fall right
--       now: seated, swimming, tasered (StunnedUntil: LawClient already holds them down), not an R15
--       body, gone. Called on someone already down, it is a new shove and the longer time wins.
--       reason: a word for what did it. RagdollService.Reasons[reason].Brace = true means "they saw it
--       coming": the body first falls stiff for 0.3 s with the arms over the head (every device plays
--       PoseClient's "Brace" pose), then goes loose. "car", "fall" and "bail" brace; "punch", "shot",
--       "ko" and "self" don't. opts.Brace (true / false) overrides the reason.
--     How it works (Shared.Util.Ragdoll has the details):
--       - Here: the joints go loose (Ragdoll.Start), which every device sees, and the loose parts are
--         handed to the player's device (network owner) so the fall is smooth for them. The joints lock
--         again 0.2 s before the end, so the body is whole when it stands up. That is not a jump on
--         screen: every device's PoseClient reads the limp pose off the body while it is loose and blends
--         it back into the animation over 0.35 s (its "Recover" pose), which runs on through the get-up.
--       - On the player's device: remote "Ragdoll" (character, "Down", seconds, impulse, braceSeconds)
--         makes PoseClient call Ragdoll.Fall (Physics state, the push) and stand up after `seconds`;
--         (character, "Up") ends it early. With a brace the "Down" message goes to everyone, for the pose.
--         When the joints lock, that device also stops the limbs being solid (Ragdoll.Settle), so they
--         can't shove the body about in those last 0.2 s on the ground.
--       - Ends early when the character sits down, respawns or leaves.
--     What this does NOT do: it never sets KnockedUntil, pays, heats or shows a caption. Callers keep
--     doing that. ImpactService's knock-down (cars, and CombatService's knockouts through it) sets
--     KnockedUntil, fires its own "Knockdown" remote (ImpactClient: the fall, the dazed marks, the
--     caption) and then calls KnockDown here inside a pcall: if this service is missing or fails, the
--     fall is today's stiff tip-over and nothing else changes.
--   * RagdollService.GetUp(player) -> bool        end a knock-down now
--   * RagdollService.IsDown(player) -> bool
--   * RagdollService.Stagger(player, seconds?, strength?) -> bool   Ragdoll.Stagger on their character
--     (a short loose-limbed wobble; upgraded avatar joints only, false otherwise)
--   * Remote "RagdollSelf" (client -> server: on, seconds?, impulse?, brace?): "ragdoll me", sent by
--     Ragdoll.Start / Ragdoll.Stop on a player's own character (a tumble after a long drop, or the
--     loose joints for a traffic-car knock their device is already doing). Their device has usually
--     lain the body down already and sends no impulse (it gave the push itself; one that is sent is cut
--     to 45), so the "Down" answer only sets the clock. Ragdoll.SelfSeconds (1.6) when no time is sent,
--     at most Ragdoll.SelfMaxSeconds (4), one every 2 s (two in a row at most); it gives nothing (no
--     KnockedUntil, no immunity) and only a ragdoll the player started can be ended by them. A request
--     that is refused gets no answer: their device's own fall just runs out.
--   * Poses everyone should see: remote "PoseBroadcast" (client -> server: poseName, on) sets or clears
--     the player attribute "Pose" (a name from RagdollService.Poses; at most 4 a second). Every device's
--     PoseClient plays that pose on the player's character. Looks only. The attribute is cleared when
--     the character respawns. RagdollService.SetPose(player, poseName?) does the same from the server
--     (hands up during an arrest, say).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ragdoll = require(ReplicatedStorage.Shared.Util.Ragdoll)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local RagdollService = {}

local DEFAULT_SECONDS = 2.5
local MIN_SECONDS, MAX_SECONDS = 0.5, 10
local LOCK_EARLY = 0.2 -- the joints lock this long before the time is up
local MAX_PUSH = 80 -- studs/s
-- "Ragdoll me" without a time, and the longest one. Ragdoll's own numbers: the player's device times
-- the fall it starts by them, so the two must agree.
local SELF_SECONDS = tonumber(Ragdoll.SelfSeconds) or 1.6
local SELF_MAX_SECONDS = tonumber(Ragdoll.SelfMaxSeconds) or 4
local SELF_MAX_PUSH = 45
local WATCH_EVERY = 0.2 -- seconds between checks for "sat down / respawned / left"
local NO_CAP = table.freeze({ NoCap = true })

RagdollService.PoseAttribute = "Pose"

-- The poses a player may show everyone (PoseClient has them all; one-off reactions such as Flinch are
-- played by whoever sees the hit and never need a broadcast). true = held until it is switched off; a
-- number = it runs out by itself after that many seconds (PoseClient's own Duration for it), and the
-- attribute is cleared then, so asking for it again is news again.
RagdollService.Poses = {
	HandsUp = true, Cower = true, PhoneTalk = true, PhoneLook = true, Aim = true, LowReady = true,
	HandsOnKnees = true, Wave = 2.2, Point = 1.8,
}

-- What a reason means for the fall. Unknown reasons fall without a brace.
RagdollService.Reasons = {
	car = { Brace = true },
	fall = { Brace = true },
	bail = { Brace = true }, -- jumping out of a moving car
	punch = { Brace = false },
	shot = { Brace = false },
	ko = { Brace = false },
	self = { Brace = false },
}

-- [player] = { char, hum, token, limp (joints loose now), limpAt / endAt (os.clock), own (the player
-- started it themselves), reason }
local active = {}
local poseToken = {} -- [player] = a count: only the latest timed pose clears the attribute
local remote

-- A finite Vector3 no longer than `limit`, or nil.
local function cleanPush(v, limit)
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

local function lockJoints(rec)
	if rec.limp then
		rec.limp = false
		local ok, err = pcall(Ragdoll.Stop, rec.char)
		if not ok then
			warn("[RagdollService] " .. tostring(err))
		end
	end
end

local function goLimp(player, rec)
	if active[player] ~= rec or rec.limp then
		return
	end
	local char = rec.char
	if not char:IsDescendantOf(Workspace) then
		return
	end
	local ok, started = pcall(Ragdoll.Start, char, nil, NO_CAP)
	if not ok then
		warn("[RagdollService] " .. tostring(started))
		return
	end
	if not started then
		return -- no joints to loosen: their device still does the (stiff) fall
	end
	rec.limp = true
	-- The loose parts belong to the player's device, like the rest of their body. (The root keeps
	-- whatever owner it had; anchored bodies refuse, which is fine.)
	for _, part in ipairs(char:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part.Anchored then
			pcall(part.SetNetworkOwner, part, player)
		end
	end
end

local function finish(player, rec)
	if active[player] ~= rec then
		return
	end
	active[player] = nil
	rec.token += 1
	lockJoints(rec)
	if player.Parent == Players and rec.char.Parent then
		remote:FireClient(player, rec.char, "Up")
	end
end

-- (Re)start the two timers: joints lock a little early, then the knock-down is over.
local function arm(player, rec, seconds)
	rec.endAt = os.clock() + seconds
	rec.token += 1
	local token = rec.token
	task.delay(math.max(seconds - LOCK_EARLY, 0.05), function()
		if active[player] == rec and rec.token == token then
			lockJoints(rec)
		end
	end)
	task.delay(seconds, function()
		if active[player] == rec and rec.token == token then
			finish(player, rec)
		end
	end)
end

function RagdollService.KnockDown(player, seconds, impulse, reason, opts)
	if not remote or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	seconds = tonumber(seconds) or DEFAULT_SECONDS
	if seconds ~= seconds then
		seconds = DEFAULT_SECONDS
	end
	seconds = math.clamp(seconds, MIN_SECONDS, MAX_SECONDS)
	impulse = cleanPush(impulse, MAX_PUSH)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not char:IsDescendantOf(Workspace) or hum.Health <= 0 or hum.SeatPart
		or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end
	if hum:GetState() == Enum.HumanoidStateType.Swimming then
		return false -- their own device wouldn't lie down in water either (Ragdoll.Fall)
	end
	if (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
		return false
	end
	local now = os.clock()
	local rec = active[player]
	if rec and rec.char == char then
		-- Already down: the longer time wins, and their device gets the new shove.
		rec.own = false
		local left = rec.endAt - now
		if seconds > left then
			arm(player, rec, seconds)
		else
			seconds = math.max(left, 0.1)
		end
		if not rec.limp and now >= rec.limpAt then
			goLimp(player, rec) -- (it had just locked, a moment before getting up)
		end
		remote:FireClient(player, char, "Down", seconds, impulse, 0)
		return true
	end
	if rec then
		finish(player, rec) -- (a record of their last body)
	end
	local brace
	if type(opts) == "table" and opts.Brace ~= nil then
		brace = opts.Brace == true
	else
		local known = RagdollService.Reasons[reason]
		brace = known ~= nil and known.Brace == true
	end
	if seconds < Ragdoll.BraceTime + LOCK_EARLY + 0.2 then
		brace = false -- too short a fall to spend 0.3 s of it stiff
	end
	local braceTime = brace and Ragdoll.BraceTime or 0
	rec = { char = char, hum = hum, token = 0, limp = false, limpAt = now + braceTime, endAt = now + seconds,
		own = false, reason = reason }
	active[player] = rec
	if brace then
		remote:FireAllClients(char, "Down", seconds, impulse, braceTime) -- everyone plays the brace pose
		task.delay(braceTime, goLimp, player, rec)
	else
		remote:FireClient(player, char, "Down", seconds, impulse, 0)
		goLimp(player, rec)
	end
	arm(player, rec, seconds)
	return true
end

function RagdollService.GetUp(player)
	local rec = active[player]
	if not rec then
		return false
	end
	finish(player, rec)
	return true
end

function RagdollService.IsDown(player)
	return active[player] ~= nil
end

function RagdollService.Stagger(player, seconds, strength)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or active[player] then
		return false
	end
	local char = player.Character
	if not char then
		return false
	end
	local ok, result = pcall(Ragdoll.Stagger, char, seconds, strength)
	return ok and result == true
end

-- Write the "Pose" attribute (nil clears it). A pose that runs out by itself takes the attribute with it.
local function setPose(player, poseName)
	local attribute = RagdollService.PoseAttribute
	if player:GetAttribute(attribute) ~= poseName then
		player:SetAttribute(attribute, poseName)
	end
	local token = (poseToken[player] or 0) + 1
	poseToken[player] = token
	local seconds = poseName and RagdollService.Poses[poseName]
	if type(seconds) == "number" then
		task.delay(seconds + 0.3, function()
			if poseToken[player] == token and player.Parent == Players and player:GetAttribute(attribute) == poseName then
				player:SetAttribute(attribute, nil)
			end
		end)
	end
end

function RagdollService.SetPose(player, poseName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	if poseName ~= nil and (type(poseName) ~= "string" or not RagdollService.Poses[poseName]) then
		return false
	end
	setPose(player, poseName)
	return true
end

-- "Ragdoll me" / "that's enough" from a player's own device.
local function onSelf(player, on, seconds, impulse, brace)
	if on == false then
		local rec = active[player]
		if rec and rec.own then
			finish(player, rec) -- only a fall they started themselves
		end
		return
	end
	if on ~= true or active[player] then
		return
	end
	if not RateLimit.Allow(player, "RagdollSelf", 0.5, 2) then
		return
	end
	seconds = tonumber(seconds) or SELF_SECONDS
	if seconds ~= seconds then
		seconds = SELF_SECONDS
	end
	seconds = math.clamp(seconds, MIN_SECONDS, SELF_MAX_SECONDS)
	if RagdollService.KnockDown(player, seconds, cleanPush(impulse, SELF_MAX_PUSH), "self", { Brace = brace == true }) then
		local rec = active[player]
		if rec then
			rec.own = true
		end
	end
end

local function onPose(player, poseName, on)
	if not RateLimit.Allow(player, "PoseBroadcast", 4, 6) then
		return
	end
	if type(poseName) ~= "string" or not RagdollService.Poses[poseName] then
		return
	end
	if on == true then
		setPose(player, poseName)
	elseif player:GetAttribute(RagdollService.PoseAttribute) == poseName then
		setPose(player, nil)
	end
end

local function watch()
	for player, rec in pairs(active) do
		local hum = rec.hum
		if player.Parent ~= Players or player.Character ~= rec.char or not rec.char:IsDescendantOf(Workspace)
			or not hum.Parent or hum.Health <= 0 or hum.SeatPart then
			finish(player, rec)
		end
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function()
		setPose(player, nil) -- a new body starts with no pose
	end)
	player.CharacterRemoving:Connect(function(char)
		local rec = active[player]
		if rec and rec.char == char then
			finish(player, rec)
		end
	end)
end

function RagdollService.Init()
	remote = Remotes.Event("Ragdoll")
	Remotes.Event(Ragdoll.SelfRemote).OnServerEvent:Connect(onSelf)
	Remotes.Event("PoseBroadcast").OnServerEvent:Connect(onPose)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local rec = active[player]
		if rec then
			finish(player, rec)
		end
		poseToken[player] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if next(active) == nil then
			acc = 0
			return
		end
		acc += dt
		if acc < WATCH_EVERY then
			return
		end
		acc = 0
		local ok, err = pcall(watch)
		if not ok then
			warn("[RagdollService] " .. tostring(err))
		end
	end)
end

return RagdollService
