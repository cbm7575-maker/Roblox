-- ImpactClient (ModuleScript, StarterPlayerScripts.Controllers.ImpactClient)
-- Bumps you can feel, kid-friendly (nobody ever gets hurt or loses health):
--   * Driving: your device owns your car's physics, so every frame it looks for the first touch with
--     another car (Workspace.Vehicles) or another player on foot (1 s cooldown per thing hit).
--       - Another car, closing faster than 20 studs/s: if you drove into it you keep only 40-55% of
--         your speed (less the more head-on). Crash sound and a little camera shake either way.
--         Someone else's device (or the server) simulates that car, so on yours it's an immovable wall
--         that would still stop you dead or bounce you back, and it only moves on your screen once
--         your car's shove has reached its owner and come back (about 0.15-0.5 s). So for 0.35 s your
--         car keeps at least 70% of the speed it kept (never more than that; it lets go if you brake
--         or a wall stops you), and:
--           . Fairly straight into a car that isn't driving at you (parked, slower, crossing) and has
--             room to be shoved (no wall right behind it, not held for a race start): that car and
--             anyone in it turn pass-through on this device only. You sink into it only as deep as
--             your wheel rays allow (3.6 studs at most, less for street bodies and angled hits),
--             going in at a pace (under that 70% if need be)
--             that uses the depth up just as it should start moving, so you keep rolling instead of
--             stopping dead. Then you follow it as it's shoved, never through it. After ~0.4 s
--             (longer on a laggy server) you ease back out of it, and its old collision groups come
--             back once the cars are clear: 2.5 s after the hit at most, whatever happens, also on
--             parts that streamed out or were destroyed.
--           . A side-swipe, head-on into a car driving at you too, or a car that can't be shoved: no
--             pass-through. You slide along it (your heading minus the part going into it), or glance
--             off to your side of it.
--           . AI patrol cars (AIPolice) stay solid walls with no push.
--       - A person on foot: your car loses about 25% of its speed and the server is told (ImpactHit);
--         ImpactService checks it and knocks them over.
--   * Knocked over (server "Knockdown", or a traffic car through ImpactClient.KnockLocal): your
--     character tips over, the dazed marks circle your head, and you get back up after ~2.5 s (a
--     server knockout while you're already down stretches that to its own time). Never while seated
--     or swimming (CombatService doesn't count a knockout on a swimmer either).
--     Uses the Physics humanoid state, so nothing else (taser stun, seats) fights over PlatformStand.
--     On your own screen, in the flat "street" look (Shared.Util.Theme): a bright colourless flash that
--     settles into a greyed-out picture while you're down (ColorCorrectionEffect "NCImpactFlash", local
--     only, eased back when you get up), and a caption in the Subtitle zone (ScreenGui "ImpactFx"):
--     KNOCKED DOWN in Display, a thin rule, "Back on your feet in a moment" under it, fading in and
--     out. Not for combat knockouts (Config.Combat.KOSeconds or longer): CombatClient stamps KNOCKED OUT
--     for those, and a knockout landing while the caption is up fades it out. Not on the first-join
--     title screen (player attribute TitleScreen), and not while something else already speaks in the
--     Subtitle zone (TutorialClient's guide step "Tutorial.Next", MissionClient's "Mission.Step"): the
--     flash and the grey picture still show it.
--   * Dazed marks over anyone whose KnockedUntil attribute (server time) is in the future: three small
--     white dots with a soft shadow ("NCDizzy" BillboardGui) circling the head, the far ones fainter.
--   * No physics shoves between cars and people at speed. A device that doesn't simulate the other
--     side treats it as solid and immovable: the driver's car would stop dead against a person, and
--     the person's device would fling them off a car. So when a car closes in fast (over 20 studs/s)
--     on someone on foot, that character goes into the "Traffic" collision group (never collides
--     with "Vehicles", like PedClient's walkers) on this device only, until ~0.6 s after the car is
--     clear. Driving: other players near our car. On foot: our own character near any car. The
--     scripted knock-down is then the only reaction. Slow bumps stay ordinary physics.
-- Other controllers: ImpactClient.IsKnocked(), ImpactClient.KnockLocal(dir, speed).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local DriveController = require(script.Parent:WaitForChild("DriveController"))
local SoundClient = require(script.Parent:WaitForChild("SoundClient"))

local player = Players.LocalPlayer

local ImpactClient = {}

local HIT_COOLDOWN = 1 -- seconds before the same car or person can count as a new hit
local CAR_HIT_SPEED = 20 -- closing speed (studs/s) that counts as a crash
local CAR_KEEP_GLANCING, CAR_KEEP_HEADON = 0.55, 0.4 -- share of your speed kept after hitting a car
local PERSON_HIT_SPEED = 20
local PERSON_KEEP = 0.75
local PERSON_MARGIN = 1.5 -- studs around the chassis that count as touching someone
local KNOCK_TIME = 2.5
local KO_SECONDS = tonumber(Combat.KOSeconds) or 5 -- a knock this long is a combat knockout (CombatClient's stamp)
local IMMUNE_AFTER = 2 -- after getting up, local knocks (traffic) wait this long
local SHAKE_TIME = 0.35
local GHOST_GROUP = "Ghost" -- never collides with "Vehicles" or "Traffic" walkers (CarBuilder.EnsureGroups)
local GHOST_HOLD = 0.6 -- seconds a character stays pass-through after the last close call
local GHOST_MARGIN = 4 -- studs around a car's box, plus more the faster it closes in
local PUSH_TIME = 0.35 -- seconds after driving into a car that your car keeps a minimum speed
local PUSH_FLOOR = 0.7 -- that minimum, as a share of the speed you kept
local GLANCE_MIN = 0.35 -- nearly head-on (no pass-through): still glance off sideways at this share
local GHOST_DIRECT = 0.6 -- pass-through only when more than this share of your motion goes into it
-- A car coming at us faster than this (studs/s) counts as driving into us too. Half of the 8 studs/s
-- "drove into it" test, so two drivers' devices never both make the other car pass-through.
local ONCOMING = 4
local CAR_GHOST_TIME = 0.4 -- seconds at least that a car you drove into stays pass-through here
local CAR_GHOST_MAX = 2.5 -- hard limit after the last hit, even if the cars still overlap
-- Deepest (studs) our car may sink into a pass-through car. Normally our wheel rays' inset toward it
-- less 0.2 (2.4 on normal bodies, 1.2 on street ones), so they stay over the road. Nose or tail into
-- its nose or tail, while those rays start below its roof (inside or under its box, where they can't
-- hit it), SINK_PAST_WHEELS more: its seats are in its middle, so there's nothing there to land on.
local MAX_SINK = 3.6
local SINK_PAST_WHEELS = 1.2
-- Seconds from touching that car until it moves on our screen: our car has to reach whoever shoves it
-- and the result has to come back. 2 x GetNetworkPing (about a round trip) plus this for server steps
-- and interpolation, twice over when another player drives it (server, their device, and back).
local REACT_EXTRA, REACT_MIN, REACT_MAX = 0.15, 0.15, 0.5
local BACK_OUT = 5 -- studs/s at most that we ease back out of a car whose pass-through is ending
local CLEAR_GAP = 0.3 -- studs apart we ease out to; collisions come back from 0.1 apart

local lastHit = setmetatable({}, { __mode = "k" }) -- [car model or Player] = os.clock()
local hitRemote
local shakeUntil, shakeAmp = 0, 0
local knocked = nil -- { hum, endAt = os.clock() to get up, timers } while this character is on the ground
local safeUntil = 0
local stars = {} -- list of { gui, labels (the dots), endAt }
local fx = { token = 0 } -- the knocked-down look: effect, gui, frame, title, rule, sub (see knockFx)

------------------------------------------------------------------ helpers

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- How far a car box (cf, half = half its size) reaches from its centre along flat direction n.
local function extent(cf, half, n)
	return math.abs(flat(cf.RightVector):Dot(n)) * half.X + math.abs(flat(cf.LookVector):Dot(n)) * half.Z
end

-- How two car boxes sit on the ground plane (separating axis test on the four side directions).
-- Returns the side direction from A toward B with the widest gap (for touching boxes, the face they
-- meet on; nil if every axis is degenerate) and that gap in studs (negative: overlapping that deep).
local function boxGap(cfA, halfA, cfB, halfB)
	local d = flat(cfB.Position - cfA.Position)
	local bestAxis, bestGap = nil, -math.huge
	for _, v in ipairs({ cfA.RightVector, cfA.LookVector, cfB.RightVector, cfB.LookVector }) do
		local axis = flat(v)
		if axis.Magnitude > 0.05 then
			axis = axis.Unit
			local along = d:Dot(axis)
			local gap = math.abs(along) - extent(cfA, halfA, axis) - extent(cfB, halfB, axis)
			if gap > bestGap then
				bestAxis, bestGap = along < 0 and -axis or axis, gap
			end
		end
	end
	return bestAxis, bestGap
end

-- Do two car boxes overlap on the ground plane, with `margin` studs of slack? (Heights only need to
-- be roughly level.)
local function boxesTouch(cfA, halfA, cfB, halfB, margin)
	if math.abs(cfA.Position.Y - cfB.Position.Y) > halfA.Y + halfB.Y + 3 then
		return false
	end
	local _, gap = boxGap(cfA, halfA, cfB, halfB)
	return gap <= margin
end

local function shake(amount)
	shakeAmp = math.max(amount, os.clock() < shakeUntil and shakeAmp or 0)
	shakeUntil = os.clock() + SHAKE_TIME
end

-- Runs right after DriveController's chase camera, which rebuilds the camera every frame, so the
-- offset never builds up.
local function shakeStep()
	local left = shakeUntil - os.clock()
	if left <= 0 or not DriveController.Status.Driving then
		return
	end
	local k = shakeAmp * (left / SHAKE_TIME)
	local camera = Workspace.CurrentCamera
	camera.CFrame = camera.CFrame
		* CFrame.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
		* CFrame.Angles(0, 0, (math.random() - 0.5) * k * 0.06)
end

------------------------------------------------------------------ dazed marks

local DAZE_DOTS = 3

-- (The names "showStars" / "stars" stay from the old cartoon stars; they're small white dots now.)
local function showStars(char, seconds)
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or seconds <= 0 then
		return
	end
	local endAt = os.clock() + seconds
	for _, s in ipairs(stars) do
		if s.gui.Parent == head then
			s.endAt = math.max(s.endAt, endAt)
			return
		end
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NCDizzy"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(60, 22)
	gui.StudsOffset = Vector3.new(0, 2.1, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local dots = {}
	for i = 1, DAZE_DOTS do
		local d = Instance.new("Frame")
		d.Name = "Star" .. i
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(6, 6)
		d.BackgroundColor3 = Theme.Color.Text
		d.BorderSizePixel = 0
		Theme.Corners(d).CornerRadius = UDim.new(0.5, 0)
		local edge = Instance.new("UIStroke")
		edge.Name = "Shadow"
		edge.Color = Theme.Color.Shadow
		edge.Thickness = 1
		edge.Transparency = 0.5
		edge.Parent = d
		d.Parent = gui
		dots[i] = d
	end
	gui.Parent = head
	table.insert(stars, { gui = gui, labels = dots, endAt = endAt })
end

-- The dots circle the head on a flat ellipse; the ones "behind" are smaller and fainter. They fade out
-- at the end.
local function animateStars()
	local now = os.clock()
	for i = #stars, 1, -1 do
		local s = stars[i]
		if not s.gui.Parent or now >= s.endAt then
			s.gui:Destroy()
			table.remove(stars, i)
		else
			local fade = math.clamp((0.4 - (s.endAt - now)) / 0.4, 0, 1)
			for j, d in ipairs(s.labels) do
				local a = now * 3 + j * (math.pi * 2 / #s.labels)
				local depth = math.sin(a)
				local px = 5 + 2 * depth
				d.Position = UDim2.fromScale(0.5 + 0.4 * math.cos(a), 0.5 + 0.22 * depth)
				d.Size = UDim2.fromOffset(px, px)
				d.ZIndex = depth > 0 and 2 or 1
				local base = depth > 0 and 0.1 or 0.45
				d.BackgroundTransparency = base + (1 - base) * fade
				d.Shadow.Transparency = 0.5 + 0.5 * fade
			end
		end
	end
end

------------------------------------------------------------------ the knocked-down look (your own screen)

local function buildFx()
	if fx.gui and fx.gui.Parent then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ImpactFx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2 -- under CombatClient's HUD (3), the mission intro (4) and the phone (5)
	gui.Parent = pg
	-- Text straight on the screen, shadowed: Display title, a thin rule, a small line under it.
	local frame = Instance.new("Frame")
	frame.Name = "KnockedDown"
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Text = "KNOCKED DOWN"
	Theme.Text(title, 26, "Display")
	title.Parent = frame
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Size = UDim2.fromOffset(160, 1)
	rule.BackgroundColor3 = Theme.Color.Text
	rule.BorderSizePixel = 0
	rule.Parent = frame
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Text = "Back on your feet in a moment"
	Theme.Text(sub, 13, "Body")
	sub.TextColor3 = Theme.Color.Dim
	sub.Parent = frame
	fx.gui, fx.frame, fx.title, fx.rule, fx.sub = gui, frame, title, rule, sub
end

local function fadeCaption(show, seconds)
	local info = TweenInfo.new(seconds)
	for _, l in ipairs({ fx.title, fx.sub }) do
		TweenService:Create(l, info, { TextTransparency = show and 0 or 1 }):Play()
		TweenService:Create(l.Shadow, info, { Transparency = show and 0.45 or 1 }):Play()
	end
	TweenService:Create(fx.rule, info, { BackgroundTransparency = show and 0.4 or 1 }):Play()
end

-- Pieces of other controllers that live in the Subtitle zone (ScreenGui, frame).
local SUBTITLE_PIECES = { { "Tutorial", "Next" }, { "Mission", "Step" } }

-- Is one of those showing inside the Subtitle zone right now? (The tutorial's frame is also its GOAL
-- strip at the top of the screen, so the box is checked, not just whether it shows.)
local function subtitleTaken(touch)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	for _, path in ipairs(SUBTITLE_PIECES) do
		local g = pg and pg:FindFirstChild(path[1])
		local o = g and g:FindFirstChild(path[2])
		if g and g:IsA("ScreenGui") and g.Enabled and o and o:IsA("GuiObject") and o.Visible then
			local sc = g.AbsoluteSize
			local z = Theme.Zone("Subtitle", touch)
			local zw = z.Size.X.Scale * sc.X + z.Size.X.Offset
			local zh = z.Size.Y.Scale * sc.Y + z.Size.Y.Offset
			local zx = z.Pos.X.Scale * sc.X + z.Pos.X.Offset - z.Anchor.X * zw
			local zy = z.Pos.Y.Scale * sc.Y + z.Pos.Y.Offset - z.Anchor.Y * zh
			-- (both guis ignore the top inset, so the piece's box is measured from its gui's own corner)
			local p, s = o.AbsolutePosition - g.AbsolutePosition, o.AbsoluteSize
			if p.X < zx + zw and p.X + s.X > zx and p.Y < zy + zh and p.Y + s.Y > zy then
				return true
			end
		end
	end
	return false
end

-- Just went down for `seconds`: flash, grey, and (unless it's a combat knockout, or the Subtitle zone
-- is taken) the caption.
local function knockFx(seconds)
	fx.token += 1
	local effect = fx.effect
	if not effect or not effect.Parent then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "NCImpactFlash"
		effect.Parent = Lighting -- made on this device: nobody else sees it
		fx.effect = effect
	end
	effect.Enabled = true
	effect.Brightness, effect.Saturation, effect.Contrast = 0.3, -1, 0.15
	TweenService:Create(effect, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0, Saturation = -0.6, Contrast = 0.08 }):Play()
	if seconds >= KO_SECONDS - 0.01 or player:GetAttribute("TitleScreen") == true then
		return
	end
	local touch = Theme.IsTouch()
	if subtitleTaken(touch) then
		return
	end
	buildFx()
	if not fx.frame then
		return
	end
	Theme.Place(fx.frame, "Subtitle", touch)
	local big = touch and 22 or 26
	fx.title.TextSize = big
	fx.title.Size = UDim2.new(1, 0, 0, big + 2)
	fx.rule.Position = UDim2.new(0.5, 0, 0, big + 5)
	fx.sub.Position = UDim2.fromOffset(0, big + 8)
	fx.sub.Size = UDim2.new(1, 0, 0, 16)
	fx.title.TextTransparency, fx.sub.TextTransparency, fx.rule.BackgroundTransparency = 1, 1, 1
	fx.title.Shadow.Transparency, fx.sub.Shadow.Transparency = 1, 1
	fx.frame.Visible = true
	fadeCaption(true, 0.25)
end

-- Back up (or gone): colour back and the caption out.
local function endKnockFx()
	fx.token += 1
	local token = fx.token
	local effect = fx.effect
	if effect and effect.Enabled then
		TweenService:Create(effect, TweenInfo.new(0.5), { Brightness = 0, Saturation = 0, Contrast = 0 }):Play()
	end
	if fx.frame and fx.frame.Visible then
		fadeCaption(false, 0.35)
	end
	task.delay(0.55, function()
		if fx.token ~= token then
			return -- knocked down again meanwhile
		end
		if effect then
			effect.Enabled = false
		end
		if fx.frame then
			fx.frame.Visible = false
		end
	end)
end

------------------------------------------------------------------ being knocked over

local function recover()
	local k = knocked
	if not k then
		return
	end
	knocked = nil
	endKnockFx()
	local hum = k.hum
	if hum.Parent then
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		if hum.Health > 0 and not hum.SeatPart then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

-- Get up after `seconds`, unless the time on the ground was stretched again since (only the latest
-- timer counts).
local function recoverAt(k, seconds)
	local n = (k.timers or 0) + 1
	k.timers = n
	task.delay(seconds, function()
		if knocked == k and k.timers == n then
			recover()
		end
	end)
end

-- Tip this player's character over along `dir` for `seconds`. Returns true if it happened (or it was
-- already down: then it stays down for the longer of the two).
local function knock(dir, speed, seconds)
	local down = knocked
	if down then
		-- Already on the ground (a traffic car clipped us just before a server knockout): stay down as
		-- long as the server says, so we don't stand up while everyone still sees us seeing stars.
		local endAt = os.clock() + seconds
		if endAt > down.endAt then
			down.endAt = endAt
			safeUntil = math.max(safeUntil, endAt + IMMUNE_AFTER)
			recoverAt(down, seconds)
			if seconds >= KO_SECONDS - 0.01 and fx.frame and fx.frame.Visible then
				fadeCaption(false, 0.2) -- a combat knockout: CombatClient's KNOCKED OUT stamp takes over
			end
		end
		return true
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 or hum.SeatPart or hum.PlatformStand then
		return false -- never while seated, or while a taser already has you down
	end
	local st = hum:GetState()
	if st == Enum.HumanoidStateType.Swimming or st == Enum.HumanoidStateType.Dead or st == Enum.HumanoidStateType.Seated then
		return false
	end
	dir = flat(dir)
	if dir.Magnitude < 0.05 then
		dir = flat(-root.CFrame.LookVector)
	end
	dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.new(0, 0, 1)
	local k = { hum = hum, endAt = os.clock() + seconds }
	knocked = k
	safeUntil = os.clock() + seconds + IMMUNE_AFTER
	-- Physics state: the humanoid stops balancing, so a small push and a spin tip it over. GettingUp
	-- is switched off so it stays down until we say so.
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	-- A little hop along the car's path: enough to see, never a launch.
	local push = math.clamp(speed * 0.25, 10, 22)
	root.AssemblyLinearVelocity = dir * push + Vector3.new(0, 14, 0)
	-- Spinning about (up x dir) makes the head fall toward dir.
	root.AssemblyAngularVelocity = Vector3.yAxis:Cross(dir) * 6
	showStars(char, seconds)
	knockFx(seconds)
	recoverAt(k, seconds)
	return true
end

function ImpactClient.IsKnocked()
	return knocked ~= nil
end

-- Ambient traffic (TrafficClient) clipped us: same fall, only on this device.
function ImpactClient.KnockLocal(dir, speed)
	if os.clock() < safeUntil or typeof(dir) ~= "Vector3" then
		return false
	end
	local fell = knock(dir, tonumber(speed) or 30, KNOCK_TIME)
	if fell then
		-- Loose joints for everyone (RagdollService checks it). JointsOnly: knock() above already has the
		-- body down and recover() stands it up, so Ragdoll only loosens the joints and never stands it.
		-- The server is asked for a little less than KNOCK_TIME (the trip there and back), so the joints
		-- are whole again just before we get up.
		pcall(function()
			require(ReplicatedStorage.Shared.Util.Ragdoll).Start(player.Character, nil, {
				Seconds = math.max(KNOCK_TIME + 0.1 - player:GetNetworkPing(), 0.5),
				Brace = true,
				JointsOnly = true,
			})
		end)
	end
	return fell
end

------------------------------------------------------------------ cars passing through people

local ghosts = {} -- [character Model] = { untilT = os.clock() it ends, parts = { [BasePart] = old group } }

-- Let cars pass through this character, on this device only (the change never replicates).
local function ghost(char, seconds)
	local g = ghosts[char]
	if not g then
		g = { untilT = 0, parts = {} }
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				g.parts[d] = d.CollisionGroup
				d.CollisionGroup = GHOST_GROUP
			end
		end
		ghosts[char] = g
	end
	g.untilT = math.max(g.untilT, os.clock() + seconds)
end

local function unghostExpired()
	local now = os.clock()
	for char, g in pairs(ghosts) do
		if now >= g.untilT or not char.Parent then
			ghosts[char] = nil
			for part, old in pairs(g.parts) do
				if part.Parent and part.CollisionGroup == GHOST_GROUP then
					part.CollisionGroup = old
				end
			end
		end
	end
end

-- Is this car (box cf/half, moving at carVel as this device sees it) about to run into the person
-- at `root`? `already`: they're pass-through now; keep them so while the car still overlaps them.
local function closeCall(cf, half, carVel, root, dt, already)
	local rel = cf:PointToObjectSpace(root.Position)
	if rel.Y < -half.Y - 3 or rel.Y > half.Y + 5 then
		return false
	end
	local dx, dz = math.abs(rel.X) - half.X, math.abs(rel.Z) - half.Z
	if already and dx < 1.5 and dz < 1.5 then
		return true -- turning collisions back on inside the car would pop them out
	end
	local relVel = flat(carVel - root.AssemblyLinearVelocity)
	local speed = relVel.Magnitude
	if speed <= PERSON_HIT_SPEED or flat(carVel).Magnitude <= PERSON_HIT_SPEED / 2 then
		return false -- slow bumps (and running into a parked car) stay ordinary physics
	end
	local margin = GHOST_MARGIN + speed * (dt * 2 + 0.05)
	if dx > margin or dz > margin then
		return false
	end
	if dx < 0.5 and dz < 0.5 then
		return true -- touching already
	end
	local toThem = flat(root.Position - cf.Position)
	return toThem.Magnitude < 0.1 or relVel:Dot(toThem.Unit) > 0 -- closing in, not moving apart
end

-- On foot: any car (another player's, a hot car, an AI patrol) closing in on us fast. Its physics
-- isn't ours, so here it would fling us: let it pass through; the server's Knockdown does the fall.
local function guardSelf(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local folder = Workspace:FindFirstChild("Vehicles")
	if not hum or not root or not folder or hum.Health <= 0 or hum.SeatPart then
		return
	end
	for _, car in ipairs(folder:GetChildren()) do
		local chassis = car:IsA("Model") and car.PrimaryPart
		if chassis and (chassis.Position - root.Position).Magnitude < 60
			and closeCall(chassis.CFrame, chassis.Size / 2, chassis.AssemblyLinearVelocity, root, dt, ghosts[char] ~= nil) then
			ghost(char, GHOST_HOLD)
		end
	end
end

------------------------------------------------------------------ pushing on after hitting a car

-- [car Model] = { untilT = end of the sinking-in part, endAt = hard limit, by = our car, n = flat unit
-- direction we hit it in, react = seconds (reactTime), reactAt = os.clock() it should move on our
-- screen (set on first touch), parts = { [BasePart] = old group } }
local carGhosts = {}
local push = nil -- { car = our car, untilT, dir = flat unit direction, speed = floor, cap = speed kept, lastAlong }
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true
wallParams.RespectCanCollide = true

-- Put the parts of `model` that aren't pass-through yet into the ghost group, remembering their old
-- group. (A rider's parts already in it belong to a people ghost above; that one puts them back.)
local function ghostParts(g, model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not g.parts[d] and d.CollisionGroup ~= GHOST_GROUP then
			g.parts[d] = d.CollisionGroup
			d.CollisionGroup = GHOST_GROUP
		end
	end
end

-- Let our car (byCar) pass through `other` and whoever sits in it, on this device only (the change
-- never replicates). n: the flat direction we hit it in. `react`: seconds from touching it until it
-- should move on our screen.
local function ghostCar(other, byCar, n, react)
	local now = os.clock()
	local g = carGhosts[other]
	if not g then
		g = { untilT = 0, endAt = 0, parts = {} }
		carGhosts[other] = g
	end
	g.by = byCar
	g.n = n
	g.react = react
	g.reactAt = nil -- the clock starts when the cars touch (limitSink)
	g.untilT = math.max(g.untilT, now + CAR_GHOST_TIME)
	g.endAt = math.max(g.endAt, now + CAR_GHOST_MAX)
	ghostParts(g, other)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p ~= player and p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(other) then
			ghostParts(g, char) -- its driver and passengers would be solid posts sticking out of it
		end
	end
end

local function restoreCar(g)
	for part, old in pairs(g.parts) do
		-- Also parts that streamed out or were destroyed (if one streams back in, it's right again).
		pcall(function()
			if part.CollisionGroup == GHOST_GROUP then
				local person = ghosts[part:FindFirstAncestorOfClass("Model")]
				if person then
					person.parts[part] = old -- a rider who got out and is pass-through as a person now
				else
					part.CollisionGroup = old
				end
			end
		end)
	end
end

-- Keep a car pass-through while our car still overlaps it (turning collisions back on inside it would
-- throw the cars apart; limitSink eases us out first), but never past its hard limit, once it's gone,
-- or once we drive it ourselves.
local function keepGhost(car, g, now)
	if now >= g.endAt or not car.Parent or car == DriveController.Status.Car then
		return false
	end
	if now < g.untilT then
		return true
	end
	local a, b = g.by and g.by.PrimaryPart, car.PrimaryPart
	return a ~= nil and b ~= nil and a:IsDescendantOf(Workspace) and b:IsDescendantOf(Workspace)
		and boxesTouch(a.CFrame, a.Size / 2, b.CFrame, b.Size / 2, 0.1)
end

local function unghostCars()
	local now = os.clock()
	for car, g in pairs(carGhosts) do
		local ok, keep = pcall(keepGhost, car, g, now)
		if not ok or not keep then
			carGhosts[car] = nil
			restoreCar(g)
		end
	end
end

-- Is the driver braking against the way the car rolls?
local function braking(chassis, car)
	local throttle = DriveController.Input.Throttle
	if throttle == nil then
		local seat = car:FindFirstChild("DriverSeat")
		throttle = seat and seat:IsA("VehicleSeat") and seat.ThrottleFloat or 0
	end
	local fwd = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
	return (fwd > 2 and throttle < -0.05) or (fwd < -2 and throttle > 0.05)
end

-- Seconds from touching `other` until it should start moving on our screen (see REACT_EXTRA).
local function reactTime(other)
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	if not ok or type(ping) ~= "number" or ping ~= ping then
		ping = 0.1
	end
	-- Parked: the server shoves it. Someone drives it: their device does, one more trip away.
	local hops = other:GetAttribute("DriverUserId") ~= nil and 2 or 1
	return math.clamp(hops * (2 * math.clamp(ping, 0, 0.5) + REACT_EXTRA), REACT_MIN, REACT_MAX)
end

-- Studs `oc` (a car's chassis) can be shoved along flat direction n before it meets a wall or other
-- solid scenery (math.huge if nothing within `reach` studs). 0 if it's anchored (a race start).
local function roomBehind(oc, n, reach)
	if oc.Anchored then
		return 0
	end
	local cf, half = oc.CFrame, oc.Size / 2
	-- Along its own floor, so the road rising ahead of it doesn't count as a wall.
	local up = cf.UpVector
	local d = n - up * n:Dot(up)
	if d.Magnitude < 0.1 then
		return math.huge
	end
	d = d.Unit
	local s = up:Cross(d)
	local ext = math.abs(d:Dot(cf.RightVector)) * half.X + math.abs(d:Dot(cf.LookVector)) * half.Z
	local across = math.abs(s:Dot(cf.RightVector)) * half.X + math.abs(s:Dot(cf.LookVector)) * half.Z
	-- Cars, people and smoke can move or be passed through; only scenery counts.
	local ignore = {}
	for _, name in ipairs({ "Vehicles", "Traffic", "Peds", "Smoke" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	wallParams.FilterDescendantsInstances = ignore
	local best = math.huge
	-- Through its middle and near both sides. Off-centre, its face along the ray is at most `ext` away,
	-- so the room found there is never more than the real room.
	for _, k in ipairs({ 0, -0.7, 0.7 }) do
		local hit = Workspace:Raycast(cf.Position + s * (across * k), d * (ext + reach), wallParams)
		if hit then
			best = math.min(best, hit.Distance - ext)
		end
	end
	return best
end

-- How deep (studs) our car may sink into `oc` along flat direction n (see MAX_SINK).
local function sinkBudget(chassis, oc, n)
	local att = chassis:FindFirstChild("WheelFL")
	if not att or not att:IsA("Attachment") then
		return 0
	end
	local cf, half = chassis.CFrame, chassis.Size / 2
	local ax, az = math.abs(att.Position.X), math.abs(att.Position.Z)
	local nr, nl = n:Dot(flat(cf.RightVector)), n:Dot(flat(cf.LookVector))
	-- How far our leading wheel rays sit behind our box's leading face, along n.
	local inset = (half.X - ax) * math.abs(nr) + (half.Z - az) * math.abs(nl)
	local budget = inset - 0.2
	local ocf, ohalf = oc.CFrame, oc.Size / 2
	if math.abs(nl) > 0.8 and math.abs(n:Dot(flat(ocf.LookVector))) > 0.8 then
		-- Nose or tail into its nose or tail. Front wheels lead when we go in nose first (front is -Z).
		local z = nl > 0 and -az or az
		local top = ohalf.Y - 0.25
		local a = ocf:PointToObjectSpace(cf * Vector3.new(ax, att.Position.Y, z))
		local b = ocf:PointToObjectSpace(cf * Vector3.new(-ax, att.Position.Y, z))
		if a.Y < top and b.Y < top then
			-- Rays that start inside its box (or under it) never hit it, so they can go a little past its end.
			budget = inset + SINK_PAST_WHEELS
		end
	end
	-- Never near its middle, however short it is.
	return math.clamp(math.min(budget, extent(ocf, ohalf, n) - 1), 0, MAX_SINK)
end

-- We drove into `other` (oc = its chassis) at myFlat and kept `keep` of it: set up the push (see the
-- header), making `other` pass-through if we're about to shove it rather than meet it head-on.
local function startPush(chassis, car, other, oc, myFlat, dir, keep)
	local kept = myFlat.Magnitude * keep
	local u = myFlat.Unit
	local n = boxGap(chassis.CFrame, chassis.Size / 2, oc.CFrame, oc.Size / 2) or dir -- the face we hit
	local into = u:Dot(n)
	local oncoming = flat(oc.AssemblyLinearVelocity):Dot(dir) < -ONCOMING
	local pushDir, share
	if into > GHOST_DIRECT and not oncoming and roomBehind(oc, n, 1) > 0.5 then
		-- Parked, slower or crossing, with room to be shoved: its own device (or the server) shoves it
		-- once we're in (limitSink paces how fast we go in).
		ghostCar(other, car, n, reactTime(other))
		pushDir, share = u, 1
	else
		-- Slide along it: our heading minus the part going into it. (Also a car that can't be shoved:
		-- pinned against a wall, or anchored for a race start.)
		local slide = u - n * math.max(into, 0)
		if slide.Magnitude >= GLANCE_MIN then
			pushDir, share = slide.Unit, slide.Magnitude
		else
			-- Nearly head-on into a car driving at us too (or straight into one that can't be shoved):
			-- glance off to our side of it. The other driver's device picks the opposite side (or its
			-- own right, as we do), so the cars part.
			local side = flat(chassis.Position - oc.Position)
			side -= n * side:Dot(n)
			if side.Magnitude < 0.3 then
				side = flat(chassis.CFrame.RightVector)
				side -= n * side:Dot(n)
			end
			if side.Magnitude < 0.05 then
				return
			end
			pushDir, share = side.Unit, GLANCE_MIN
		end
	end
	push = { car = car, untilT = os.clock() + PUSH_TIME, dir = pushDir, speed = kept * PUSH_FLOOR * share, cap = kept }
end

-- The push, on our car's ground velocity v: at least push.speed along push.dir, never faster than the
-- speed kept after the hit. Lets go early if something else (a wall, a post) stopped the car since
-- last frame, or the driver brakes.
local function applyPush(v, chassis, car)
	local p = push
	if not p then
		return v
	end
	if p.car ~= car or os.clock() >= p.untilT then
		push = nil
		return v
	end
	local along = v:Dot(p.dir)
	if (p.lastAlong and along < p.lastAlong * 0.4 and p.lastAlong - along > 4) or braking(chassis, car) then
		push = nil
		return v
	end
	if along < p.speed then
		v += p.dir * (p.speed - along)
	end
	if v.Magnitude > p.cap then
		v = v.Unit * p.cap
	end
	return v
end

-- How fast our car may move into a pass-through car (g = its carGhosts entry), on ground velocity v,
-- along g.n (the way we hit it). On our screen it only moves once our shove has reached its owner and
-- come back (g.react after the cars touch), so until then it's a wall we may sink into by sinkBudget
-- studs (less if a wall behind it leaves it less room). We go in at a pace that uses that depth up
-- just as it should start moving, so we keep rolling instead of stopping dead, then follow it as it's
-- shoved: we shove it but never drive through it. Once its pass-through is ending (g.untilT), we ease
-- back out to CLEAR_GAP, no faster than BACK_OUT, so its collisions never come back while the cars
-- overlap. Only ever takes speed away, except that gentle ease out.
local function limitSink(v, chassis, other, g, now, dt)
	local oc = other.PrimaryPart
	if not oc or not oc:IsDescendantOf(Workspace) then
		return v
	end
	local cf, half = chassis.CFrame, chassis.Size / 2
	local ocf, ohalf = oc.CFrame, oc.Size / 2
	if math.abs(ocf.Position.Y - cf.Position.Y) > half.Y + ohalf.Y + 1 then
		return v
	end
	local n = g.n
	local axis, sep = boxGap(cf, half, ocf, ohalf)
	if not axis or (sep > 0 and math.abs(axis:Dot(n)) < 0.7) then
		return v -- beside it rather than behind it (it was knocked aside, or we're passing it): free
	end
	-- How far apart the cars are along n (negative: that deep into it). Measured along the way we hit
	-- it, not the shallowest way out, so an off-centre hit can't slide us along its side inside it.
	local gap = flat(ocf.Position - cf.Position):Dot(n) - extent(cf, half, n) - extent(ocf, ohalf, n)
	local step = math.max(dt, 1 / 240)
	local limit = -CLEAR_GAP -- ending: back out until the cars are clear
	local left = 0 -- seconds until it should move on our screen
	if now < g.untilT then
		if gap <= 0 and not g.reactAt then
			-- First touch: it should start moving on our screen in g.react. Stay pass-through till then.
			g.reactAt = now + g.react
			g.untilT = math.max(g.untilT, g.reactAt + 0.1)
		end
		left = g.reactAt and g.reactAt - now or g.react
		local budget = sinkBudget(chassis, oc, n)
		limit = math.min(budget, math.max(roomBehind(oc, n, budget + 0.5) - 0.3, 0))
	end
	local away = math.max(flat(oc.AssemblyLinearVelocity):Dot(n), 0)
	local room = limit + gap -- studs we may still go into it (negative: we're too deep)
	local allowed
	if room >= 0 then
		-- Spread what's left over the time until it should move on our screen (after that, a frame
		-- ahead, so we stop right at the limit instead of overshooting it).
		allowed = away + room / math.max(left, step)
	else
		allowed = away + math.max(room / step, -BACK_OUT)
	end
	local into = v:Dot(n)
	if into > allowed then
		v -= n * (into - allowed)
	end
	return v
end

------------------------------------------------------------------ hitting things while driving

local prevChassis, prevVel = nil, Vector3.zero -- our car's velocity at the end of last frame

-- Slow our car so its ground speed is at most `keep` x its speed before the bump. If the physics
-- bounce already slowed it more than that, leave it alone (never speed a car back up).
local function slowTo(chassis, before, keep)
	local vel = chassis.AssemblyLinearVelocity
	local speed = flat(vel).Magnitude
	local want = flat(before).Magnitude * keep
	if speed > want and speed > 0.01 then
		local k = want / speed
		chassis.AssemblyLinearVelocity = Vector3.new(vel.X * k, vel.Y, vel.Z * k)
	end
end

local function hitCar(chassis, car, other, oc, before, closing, toOther)
	local myFlat = flat(before)
	local dir = toOther.Unit
	if myFlat:Dot(dir) > 8 then
		-- We drove into it: lose a big chunk of speed (more when it's head-on), but never stop dead.
		-- (If it drove into us, we only feel it: sound and shake.)
		push = nil -- only a push this hit starts may follow it (an older one would undo this slow-down)
		local headOn = myFlat.Magnitude > 1 and math.clamp(myFlat.Unit:Dot(dir), 0, 1) or 0
		local keep = CAR_KEEP_GLANCING - (CAR_KEEP_GLANCING - CAR_KEEP_HEADON) * headOn
		slowTo(chassis, before, keep)
		if not other:GetAttribute("AIPolice") then
			startPush(chassis, car, other, oc, myFlat, dir, keep)
		end
	end
	SoundClient.Play("Crash", chassis.Position)
	shake(0.35 + 0.45 * math.clamp(closing / 100, 0, 1))
end

local function hitPerson(chassis, before, victim)
	push = nil -- a new bump takes over from any push, so the push can't undo this slow-down
	slowTo(chassis, before, PERSON_KEEP)
	SoundClient.Play("Crash", chassis.Position, 0.45)
	shake(0.2)
	if hitRemote then
		hitRemote:FireServer(victim)
	end
end

local function isDown(p)
	local t = Workspace:GetServerTimeNow()
	return (p:GetAttribute("KnockedUntil") or 0) > t or (p:GetAttribute("StunnedUntil") or 0) > t
end

local function checkHits(dt)
	local status = DriveController.Status
	local car = status.Driving and status.Car
	local chassis = car and car.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) then
		prevChassis = nil
		push = nil
		return
	end
	local now = os.clock()
	local cf = chassis.CFrame
	local half = chassis.Size / 2
	-- How fast we were going into this frame: if the physics already bounced us off something this
	-- step, last frame's velocity is the one that says how hard we hit.
	local before = chassis.AssemblyLinearVelocity
	if prevChassis == chassis and flat(prevVel).Magnitude > flat(before).Magnitude then
		before = prevVel
	end
	local myFlat = flat(before)

	-- Other cars (players', hot cars, AI patrols). Far or streamed-out ones have no PrimaryPart here.
	local folder = Workspace:FindFirstChild("Vehicles")
	if folder then
		for _, other in ipairs(folder:GetChildren()) do
			local oc = other ~= car and other:IsA("Model") and other.PrimaryPart
			if oc and now - (lastHit[other] or 0) > HIT_COOLDOWN then
				local toOther = flat(oc.Position - cf.Position)
				if toOther.Magnitude < half.Magnitude + oc.Size.Magnitude / 2 + 8 and toOther.Magnitude > 0.1 then
					local closing = (myFlat - flat(oc.AssemblyLinearVelocity)):Dot(toOther.Unit)
					-- Look a frame ahead so we catch it just before the bodies meet.
					local margin = 0.75 + math.max(closing, 0) * dt * 1.5
					if closing > CAR_HIT_SPEED and boxesTouch(cf, half, oc.CFrame, oc.Size / 2, margin) then
						lastHit[other] = now
						hitCar(chassis, car, other, oc, before, closing, toOther)
					end
				end
			end
		end
	end

	-- People on foot. Their devices own their characters, so to our car they're solid posts: the car
	-- passes through them on this device (ghost, a bit before contact) and the knock-down is the whole
	-- reaction. Boats don't knock swimmers over (but still pass through them).
	local boat = car:GetAttribute("Boat")
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p ~= player and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and not hum.SeatPart then
			if closeCall(cf, half, before, root, dt, ghosts[char] ~= nil) then
				ghost(char, GHOST_HOLD)
			end
			if not boat and now - (lastHit[p] or 0) > HIT_COOLDOWN and not isDown(p) then
				local rel = cf:PointToObjectSpace(root.Position)
				local speed = (myFlat - flat(root.AssemblyLinearVelocity)).Magnitude
				local margin = PERSON_MARGIN + speed * dt
				if speed > PERSON_HIT_SPEED and math.abs(rel.X) < half.X + margin and math.abs(rel.Z) < half.Z + margin
					and rel.Y > -half.Y - 3 and rel.Y < half.Y + 5 then
					local toThem = flat(root.Position - cf.Position)
					-- Only when the car is moving into them (not just sliding past alongside).
					if toThem.Magnitude > 0.1 and myFlat:Dot(toThem.Unit) > 8 then
						lastHit[p] = now
						hitPerson(chassis, before, p)
					end
				end
			end
		end
	end

	-- After driving into a car: the push, then how fast we may go into a pass-through car.
	local vel = chassis.AssemblyLinearVelocity
	local v = applyPush(flat(vel), chassis, car)
	for other, g in pairs(carGhosts) do
		if g.by == car then
			v = limitSink(v, chassis, other, g, now, dt)
		end
	end
	if push then
		push.lastAlong = v:Dot(push.dir) -- what we left it at, so next frame can tell if a wall stopped it
	end
	if v ~= flat(vel) then
		chassis.AssemblyLinearVelocity = Vector3.new(v.X, vel.Y, v.Z)
	end
	prevChassis, prevVel = chassis, chassis.AssemblyLinearVelocity
end

------------------------------------------------------------------ init

local function watchPlayer(p)
	p:GetAttributeChangedSignal("KnockedUntil"):Connect(function()
		local t = p:GetAttribute("KnockedUntil")
		if typeof(t) == "number" then
			local left = t - Workspace:GetServerTimeNow()
			if left > 0 then
				showStars(p.Character, math.min(left, 5))
			end
		end
	end)
end

function ImpactClient.Init()
	-- Fetched in its own thread: the client version of Remotes.Event waits for the server to make it.
	task.spawn(function()
		hitRemote = Remotes.Event("ImpactHit")
	end)
	Remotes.OnClient("Knockdown", function(dir, speed, seconds)
		if typeof(dir) ~= "Vector3" or dir.X ~= dir.X or dir.Z ~= dir.Z then
			return
		end
		speed = tonumber(speed) or 30
		seconds = tonumber(seconds) or KNOCK_TIME
		if speed ~= speed or seconds ~= seconds then
			return
		end
		knock(dir, speed, math.clamp(seconds, 0.5, 6)) -- combat knockouts last 5 s
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	player.CharacterAdded:Connect(function()
		if knocked then
			knocked = nil -- the old humanoid is gone; the new one starts with every state enabled
			endKnockFx()
		end
	end)

	RunService:BindToRenderStep("NC_ImpactShake", Enum.RenderPriority.Camera.Value + 2, shakeStep)
	RunService.RenderStepped:Connect(function()
		if #stars > 0 then
			animateStars()
		end
	end)
	local lastWarn = 0
	local function safely(fn, dt)
		local ok, err = pcall(fn, dt)
		if not ok and os.clock() - lastWarn > 5 then
			lastWarn = os.clock()
			warn("[ImpactClient] " .. tostring(err))
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		-- Sat down (hot car pick-lock, a server seat) or gone while knocked over: stand straight up.
		local k = knocked
		if k and (not k.hum.Parent or k.hum.SeatPart or k.hum.Health <= 0) then
			recover()
		end
		safely(checkHits, dt)
		safely(guardSelf, dt)
		-- These always run, so no person or car stays pass-through if a check above fails.
		safely(unghostExpired)
		safely(unghostCars)
	end)
end

return ImpactClient
