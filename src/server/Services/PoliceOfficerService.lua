-- PoliceOfficerService (ModuleScript, ServerScriptService.Services.PoliceOfficerService)
-- Police officers on foot (owner, Oct 30: the police get out of their cars, chase, shoot when it's
-- called for, and arrest anyone who gives up). AIPoliceService's patrol cars carry them:
--   * Riding: one officer at the wheel, a second in the passenger seat from 3 stars (Board). A rider is a
--     posed statue welded in the seat for everyone to see (no Humanoid: one welded into a car pushes it
--     about; VehicleService.SeatNPC does the same for taxi fares).
--   * Out: once the car has pulled up within K.DISMOUNT studs of the suspect and slowed down, and the
--     suspect is on foot or sitting in a car that has stopped, the officers step out by their doors as
--     real walking officers (Humanoids in Workspace.NPCs, server-owned). The car waits there with its
--     lights on (AIPoliceService.drive holds it while Step says "out"). When the suspect drives off or
--     gets K.REMOUNT studs from the car, they run back and get in, and the car takes up the chase.
--   * What an officer does depends on what the suspect does (step):
--       - Hands up (player attribute Surrender: H / gamepad Y / the HANDS UP tile, LawClient ->
--         RequestSurrender, handled here): they hold fire, walk up and cuff them K.SURRENDER_CUFF seconds
--         after reaching them. A surrender also takes a star off the sentence (ArrestService).
--       - Standing still (or sitting in a stopped car) with no threat: they run up ("POLICE! HANDS
--         UP!") and cuff them after K.CUFF seconds at arm's length (K.CUFF_CAR from the side of the
--         car: walking straight at the driver shoved it down the road): ArrestService.Arrest, as ever.
--       - Running: they chase at K.RUN, a little under a sprinting player.
--       - Hostile (hostileTo): a gun out at 2+ stars, a gun fired in the last K.FIRED_MEMORY seconds, an
--         officer shot or punched by them in the last K.ASSAULT_MEMORY seconds, or 4+ stars. They draw
--         their pistols, keep K.KEEP_NEAR..K.KEEP_FAR studs off with a clear line, and shoot every
--         K.SHOT_GAP seconds; how often a shot lands goes down with distance and a running target
--         (CombatService.PoliceShot does the damage, the shot effects for everyone, and the death: with
--         police right there that is an arrest on the spot, ArrestService.GaveUp). Never at someone in a
--         car seat (players can't be hit there either), in a safe zone, or with their hands up.
--       - A gun out at 1 star: drawn but holding fire ("DROP THE WEAPON!").
--   * Players can shoot and punch them (CombatService routes hits on Workspace.NPCs models with the
--     attribute NPCKind = "Officer" to PoliceOfficerService.NPCHit): K.HEALTH health; fists knock one out
--     for K.PUNCH_DOWN seconds (the limp fall: Shared.Util.Ragdoll), bullets can kill. Either costs stars
--     (CombatService.CrimeHeat; a dead officer is one more real star: HeatService.Add) and turns every
--     officer on that player hostile.
--   * Shouts: a bubble over the head ("POLICE! HANDS UP!"), and the suspect's own toast says how to give
--     up (Notify "PoliceOnFoot", once per patrol).
--   * Walking officers are HeatService eyes, like the patrol cars, and carry the attribute AimTarget
--     (CombatClient's AIM swing can lock onto them). Riders don't (bullets pass through them to the car).
-- Look: navy uniform (body colours), a cap, a gold badge, POLICE on the back, a pistol that shows only
-- when drawn (with Roblox's stock R15 "tool" arm). Four looks are built at start-up (OfficerTemplates in
-- ServerStorage); until they are ready a patrol simply has nobody in it and arrests from the car as before.
-- Public (AIPoliceService): Board(car, count) -> crew or nil, Step(crew, dt, target, info, carSpeed) ->
-- "ride" | "out" | "gone", Remove(crew). CombatService: NPCHit(model, attacker, damage, dir, kind) -> bool.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local HeatService = require(ServerScriptService.Services.HeatService)

local PoliceOfficerService = {}

local K = {
	TICK = 0.1, -- seconds between two decisions (movement in between is the Humanoid's own)
	DISMOUNT = 34, -- studs from the suspect: the officers get out of a car that has pulled up this close...
	DISMOUNT_SPEED = 10, -- ...and slowed below this (studs/s)
	REMOUNT = 75, -- the suspect this far from the car: back in and after them by car
	CAR_GONE = 16, -- studs/s: a suspect's car going faster than this has driven off
	WALK = 9,
	RUN = 19.5, -- (players walk 18 and sprint faster: a sprinter gets away, a walker doesn't)
	CUFF_RANGE = 5.5,
	CUFF_CAR = 2.5, -- studs from the body of a car the suspect sits in: the cuffing is done from beside it
	CUFF = 2.2, -- seconds at arm's length from a suspect who stands still
	SURRENDER_CUFF = 1, -- ...or who has their hands up
	STILL = 7, -- studs/s: slower counts as standing still (a car: under 5)
	SHOOT_RANGE = 90,
	KEEP_NEAR = 14, -- a hostile suspect is kept between these two distances
	KEEP_FAR = 32,
	SHOT_GAP_MIN = 0.85, -- seconds between two shots from one officer
	SHOT_GAP_MAX = 1.35,
	DRAW_TIME = 0.6, -- seconds from drawing the pistol to the first shot
	DAMAGE = 13, -- per hit (armor soaks it first)
	FIRED_MEMORY = 8, -- seconds a suspect who fired a gun stays armed and dangerous
	ASSAULT_MEMORY = 45, -- seconds a suspect who hit an officer stays a target
	HEALTH = 100,
	PUNCH_DOWN = 5, -- seconds a punched-out officer stays down
	DEAD_FOR = 12, -- seconds a dead officer lies there before going
	OFFICER_HEAT_GAP = 10, -- seconds between two "hit an officer" stars for one attacker
	SAY_GAP = 3.5, -- seconds between two shouts from one officer
	RETURN_MAX = 7, -- seconds running back to the car before they're simply put back in
	STUCK = 1, -- seconds barely moving while trying to: jump
	TEMPLATES = 4,
	SEAT_UP = 1.3, -- a seated R15 rider's root above the seat's top (as VehicleService)
	SURRENDER_RANGE = 160, -- studs: police this close to give up to (LawClient shows HANDS UP within 150)
	SURRENDER_MOVE = 8, -- studs/s: hands up and moving faster than this is running, not giving up
	SKIN = {
		Color3.fromRGB(255, 220, 185), Color3.fromRGB(205, 160, 120), Color3.fromRGB(160, 110, 75), Color3.fromRGB(110, 75, 55),
	},
	SHIRT = Color3.fromRGB(28, 42, 78), -- navy
	PANTS = Color3.fromRGB(20, 24, 36),
	ANIM = {
		idle = "rbxassetid://507766388", walk = "rbxassetid://507777826", run = "rbxassetid://507767714",
		aim = "rbxassetid://507768375", -- Roblox's stock R15 "toolnone": the right arm held out front
	},
	SIT = "rbxassetid://2506281703", -- Roblox's stock R15 sit (as CarBuilder.PlayPose)
}

local crews = {} -- every crew from Board, until Remove
local byModel = setmetatable({}, { __mode = "k" }) -- [walking officer Model] = its officer record
local assaultAt = setmetatable({}, { __mode = "k" }) -- [player] = os.clock() they last hit an officer
local officerHeatAt = setmetatable({}, { __mode = "k" }) -- [player] = os.clock() of their last officer star
local templates = {} -- built at Init
local rng = Random.new()
local notify
local npcFolder

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

-- Looked up when first needed: they require us (CombatService), or start after us.
local lazy = {}
local function service(name)
	local m = lazy[name]
	if m == nil then
		local module = ServerScriptService.Services:FindFirstChild(name)
		local ok, res = pcall(function()
			return module and require(module)
		end)
		m = (ok and type(res) == "table") and res or false
		lazy[name] = m
	end
	return m or nil
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

------------------------------------------------------------------ the look

local function deco(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = parent
	w.Part1 = p
	w.Parent = p
	p.Parent = parent.Parent
	return p
end

local function dress(model)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	local hand = model:FindFirstChild("RightHand")
	if head and head:IsA("BasePart") then
		local h = head.Size
		local black = Color3.fromRGB(18, 20, 28)
		deco(head, "CapCrown", Vector3.new(h.X * 1.05, h.Y * 0.32, h.Z * 1.05), head.CFrame * CFrame.new(0, h.Y * 0.42, 0.03), black)
		deco(head, "CapBrim", Vector3.new(h.X * 0.95, 0.08, h.Z * 0.5), head.CFrame * CFrame.new(0, h.Y * 0.3, -h.Z * 0.62), black)
		deco(head, "CapBadge", Vector3.new(0.22, 0.2, 0.04), head.CFrame * CFrame.new(0, h.Y * 0.45, -h.Z * 0.54), Color3.fromRGB(230, 190, 70), Enum.Material.Metal)
	end
	if torso and torso:IsA("BasePart") then
		local s = torso.Size
		deco(torso, "Badge", Vector3.new(0.24, 0.3, 0.05), torso.CFrame * CFrame.new(-s.X * 0.22, s.Y * 0.18, -s.Z / 2 - 0.02), Color3.fromRGB(230, 190, 70), Enum.Material.Metal)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PoliceBack"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		gui.Parent = torso
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 0.4)
		t.Position = UDim2.fromScale(0, 0.15)
		t.Text = "POLICE"
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = Color3.fromRGB(235, 235, 240)
		t.Parent = gui
	end
	if hand and hand:IsA("BasePart") then
		-- The pistol, hidden until drawn. With the "toolnone" arm held out, the hand's -Y points ahead.
		local gun = Instance.new("Part")
		gun.Name = "Pistol"
		gun.Size = Vector3.new(0.2, 0.36, 0.95)
		gun.Color = Color3.fromRGB(30, 30, 34)
		gun.Material = Enum.Material.Metal
		gun.CanCollide = false
		gun.CanQuery = false
		gun.CanTouch = false
		gun.Massless = true
		gun.Transparency = 1
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = gun
		weld.C0 = CFrame.new(0, -0.5, -0.05) * CFrame.Angles(math.rad(-90), 0, 0)
		weld.Parent = gun
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Position = Vector3.new(0, 0.08, -0.5)
		muzzle.Parent = gun
		gun.CFrame = hand.CFrame * weld.C0
		gun.Parent = model
	end
end

local function buildTemplates()
	local folder = ServerStorage:FindFirstChild("OfficerTemplates") or Instance.new("Folder")
	folder.Name = "OfficerTemplates"
	folder.Parent = ServerStorage
	task.spawn(function()
		for i = 1, K.TEMPLATES do
			local ok, model = pcall(function()
				local desc = Instance.new("HumanoidDescription")
				local skin = K.SKIN[(i - 1) % #K.SKIN + 1]
				desc.HeadColor = skin
				desc.LeftArmColor, desc.RightArmColor, desc.TorsoColor = K.SHIRT, K.SHIRT, K.SHIRT
				desc.LeftLegColor, desc.RightLegColor = K.PANTS, K.PANTS
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if ok and model then
				model.Name = "Officer"
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BaseScript") then
						d:Destroy() -- (the Animate script never runs on a server NPC: step plays the animations)
					end
				end
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
					hum.BreakJointsOnDeath = false
					hum.WalkSpeed = K.RUN
				end
				local okDress, err = pcall(dress, model)
				if not okDress then
					warn("[PoliceOfficerService] dressing an officer: " .. tostring(err))
				end
				model.Parent = folder
				table.insert(templates, model)
			else
				warn("[PoliceOfficerService] couldn't build an officer: " .. tostring(model))
			end
		end
	end)
end

------------------------------------------------------------------ riders (posed in the seat)

local function seatOf(car, name)
	local seat = car and car:FindFirstChild(name)
	return (seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat"))) and seat or nil
end

local function newRider(o, car)
	local seat = seatOf(car, o.seatName)
	local template = templates[o.look]
	if not seat or not template then
		return nil
	end
	local model = template:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:Destroy() -- (a Humanoid welded into the car pushes it about)
	end
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false -- (shots pass through to the car)
			d.Massless = true
		end
	end
	model:PivotTo(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + K.SEAT_UP, 0))
	local w = Instance.new("WeldConstraint")
	w.Part0 = seat
	w.Part1 = root
	w.Parent = root
	model.Name = "OfficerRider"
	model.Parent = car
	pcall(function()
		local animator = Instance.new("Animator")
		animator.Parent = controller
		local anim = Instance.new("Animation")
		anim.AnimationId = K.SIT
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0)
	end)
	return model
end

------------------------------------------------------------------ walkers (out of the car)

local function loadTracks(o)
	local animator = o.hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = o.hum
	end
	o.tracks = {}
	for name, id in pairs(K.ANIM) do
		local ok, track = pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local t = animator:LoadAnimation(anim)
			t.Looped = true
			t.Priority = name == "aim" and Enum.AnimationPriority.Action or Enum.AnimationPriority.Movement
			return t
		end)
		if ok then
			o.tracks[name] = track
		end
	end
end

-- Idle / walk / run by how fast the body really goes.
local function animate(o)
	local tracks = o.tracks
	if not tracks then
		return
	end
	local speed = flat(o.root.AssemblyLinearVelocity).Magnitude
	local want = speed < 0.6 and "idle" or (speed < 12 and "walk" or "run")
	if o.gait ~= want then
		if o.gait and tracks[o.gait] then
			tracks[o.gait]:Stop(0.2)
		end
		o.gait = want
		if tracks[want] then
			tracks[want]:Play(0.2)
		end
	end
	local t = tracks[want]
	if t and want ~= "idle" then
		t:AdjustSpeed(math.clamp(speed / (want == "run" and 18 or 8), 0.5, 1.6))
	end
end

local function draw(o, on)
	if o.drawn == on then
		return
	end
	o.drawn = on
	o.drawnAt = os.clock()
	local gun = o.model:FindFirstChild("Pistol")
	if gun then
		gun.Transparency = on and 0 or 1
	end
	local aim = o.tracks and o.tracks.aim
	if aim then
		if on then
			aim:Play(0.15)
		else
			aim:Stop(0.2)
		end
	end
end

local function say(o, text)
	local t = os.clock()
	if o.said == text and t - (o.sayAt or 0) < K.SAY_GAP * 2 then
		return
	end
	if t - (o.sayAt or 0) < K.SAY_GAP then
		return
	end
	o.said, o.sayAt = text, t
	local head = o.model:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild("Shout")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Shout"
		gui.Size = UDim2.fromOffset(200, 34)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 90
		gui.AlwaysOnTop = true
		gui.Parent = head
		local l = Instance.new("TextLabel")
		l.Name = "Text"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundColor3 = Color3.fromRGB(16, 22, 44)
		l.BackgroundTransparency = 0.15
		l.TextColor3 = Color3.fromRGB(255, 255, 255)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = l
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
		pad.Parent = l
	end
	gui.Text.Text = text
	gui.Enabled = true
	local token = t
	task.delay(2.2, function()
		if o.sayAt == token and gui.Parent then
			gui.Enabled = false
		end
	end)
end

-- Where an officer gets out (and back in): beside their door, on the ground.
local function doorSpot(car, seatName)
	local chassis = car and car.PrimaryPart
	local seat = seatOf(car, seatName)
	if not chassis or not seat then
		return nil
	end
	local cf = chassis.CFrame
	local local_ = cf:PointToObjectSpace(seat.Position)
	local side = local_.X >= 0 and 1 or -1
	local spot = cf * Vector3.new(side * (chassis.Size.X / 2 + 2.2), 0, local_.Z)
	losParams.FilterDescendantsInstances = { car, npcFolder }
	local hit = Workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), losParams)
	return Vector3.new(spot.X, (hit and hit.Position.Y or chassis.Position.Y - 2) + 3, spot.Z)
end

local function newWalker(o, car, toward)
	local template = templates[o.look]
	local at = doorSpot(car, o.seatName)
	if not template or not at then
		return false
	end
	local model = template:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		model:Destroy()
		return false
	end
	local look = flat(toward - at)
	model:PivotTo(CFrame.lookAt(at, at + (look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1))))
	model:SetAttribute("NPCKind", "Officer")
	model:SetAttribute("AimTarget", true)
	model.Parent = npcFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	o.model, o.hum, o.root = model, hum, root
	o.muzzle = model:FindFirstChild("Pistol") and model.Pistol:FindFirstChild("Muzzle")
	o.hp = K.HEALTH
	o.gait, o.drawn, o.cuffFor, o.stuckFor = nil, false, 0, 0
	o.nextShot = 0
	loadTracks(o)
	byModel[model] = o
	HeatService.RegisterEye(root)
	return true
end

local function dropWalker(o)
	if o.model then
		byModel[o.model] = nil
		if o.root then
			HeatService.UnregisterEye(o.root)
		end
		o.model:Destroy()
	end
	o.model, o.hum, o.root, o.tracks, o.muzzle = nil, nil, nil, nil, nil
end

local function moveTo(o, pos, speed)
	o.hum.WalkSpeed = speed
	local t = os.clock()
	if not o.moveGoal or (o.moveGoal - pos).Magnitude > 2 or t - (o.moveAt or 0) > 1.5 then
		o.moveGoal, o.moveAt = pos, t
		o.hum:MoveTo(pos)
	end
	o.moving = true
end

local function stop(o)
	if o.moving then
		o.moving = false
		o.moveGoal = nil
		o.hum:MoveTo(o.root.Position)
	end
end

local function face(o, pos)
	local look = flat(pos - o.root.Position)
	if look.Magnitude > 0.2 then
		o.hum.AutoRotate = false
		local p = o.root.Position
		o.root.CFrame = CFrame.lookAt(p, p + look.Unit)
	end
end

------------------------------------------------------------------ what the suspect is doing

local function armed(p)
	local char = p.Character
	for _, c in ipairs(char and char:GetChildren() or {}) do
		if c:IsA("Tool") and c:GetAttribute(Combat.ToolAttribute or "NCCombat") == "Gun" then
			return true
		end
	end
	return false
end

local function hostileTo(p)
	-- (What they did first: hands that go up after shooting at officers don't stop the shooting.)
	local t = os.clock()
	if t - (assaultAt[p] or -math.huge) < K.ASSAULT_MEMORY then
		return true
	end
	local cs = service("CombatService")
	if cs and type(cs.LastAggro) == "function" then
		local at, kind = cs.LastAggro(p)
		if kind == "Gun" and at and t - at < K.FIRED_MEMORY then
			return true
		end
	end
	if p:GetAttribute("Surrender") == true then
		return false
	end
	local heat = HeatService.GetHeat(p)
	return heat >= 4 or (heat >= 2 and armed(p))
end

-- A clear line from the officer's eyes to the suspect's chest?
local function canSee(o, troot, tchar)
	local head = o.model:FindFirstChild("Head")
	local from = (head and head.Position) or (o.root.Position + Vector3.new(0, 1.5, 0))
	losParams.FilterDescendantsInstances = { npcFolder, tchar, Workspace:FindFirstChild("Vehicles") or npcFolder }
	return Workspace:Raycast(from, troot.Position - from, losParams) == nil
end

local function shoot(o, p, troot, tchar, dist, targetSpeed)
	local t = os.clock()
	o.nextShot = t + rng:NextNumber(K.SHOT_GAP_MIN, K.SHOT_GAP_MAX)
	local origin = o.muzzle and o.muzzle.WorldPosition or (o.root.Position + Vector3.new(0, 1.2, 0))
	local chance = math.clamp(0.78 - dist / 115, 0.12, 0.75)
	if targetSpeed > 12 then
		chance *= 0.6 -- a running target is harder to hit
	end
	local hit = rng:NextNumber() < chance
	local aim = troot.Position + Vector3.new(0, 0.5, 0)
	if not hit then
		aim += rng:NextUnitVector() * rng:NextNumber(2.5, 5)
	end
	-- Where the round really ends: the first wall, or the suspect.
	losParams.FilterDescendantsInstances = { npcFolder, Workspace:FindFirstChild("DroppedBags") or npcFolder }
	local v = aim - origin
	local ray = Workspace:Raycast(origin, v.Unit * math.min(v.Magnitude + 6, K.SHOOT_RANGE + 10), losParams)
	local endPos = ray and ray.Position or (origin + v.Unit * (K.SHOOT_RANGE + 10))
	local onBody = hit and ray ~= nil and ray.Instance:IsDescendantOf(tchar)
	local cs = service("CombatService")
	if cs and type(cs.PoliceShot) == "function" then
		local ok, err = pcall(cs.PoliceShot, p, origin, endPos, onBody, K.DAMAGE)
		if not ok then
			warn("[PoliceOfficerService] shot: " .. tostring(err))
		end
	end
end

------------------------------------------------------------------ one officer, one tick

local function arrest(p)
	local arrestService = service("ArrestService")
	if arrestService then
		local ok, err = pcall(arrestService.Arrest, p, nil)
		if not ok then
			warn("[PoliceOfficerService] arrest: " .. tostring(err))
		end
	end
end

local function handsUp(p)
	local ragdoll = service("RagdollService")
	if ragdoll and type(ragdoll.SetPose) == "function" and p:GetAttribute("Pose") ~= "HandsUp" then
		pcall(ragdoll.SetPose, p, "HandsUp")
	end
end

-- ...and down again when the cuffing stops (they ran, the officer went back or went down), unless they
-- put them up themselves (Surrender).
local function handsDown(p)
	local ragdoll = service("RagdollService")
	if ragdoll and type(ragdoll.SetPose) == "function" and p:GetAttribute("Pose") == "HandsUp" and p:GetAttribute("Surrender") ~= true then
		pcall(ragdoll.SetPose, p, nil)
	end
end

local function getUp(o)
	if o.state ~= "Down" or not o.model or not o.model.Parent then
		return
	end
	local ok = pcall(function()
		require(ReplicatedStorage.Shared.Util.Ragdoll).Stop(o.model)
	end)
	if not ok then
		o.hum.PlatformStand = false
	end
	o.hp = math.max(o.hp, 40)
	o.state = "Out"
	o.model:SetAttribute("AimTarget", true)
	if o.root then
		HeatService.RegisterEye(o.root)
	end
end

local function knockDown(o, dir)
	o.state = "Down"
	o.downUntil = os.clock() + K.PUNCH_DOWN
	o.model:SetAttribute("AimTarget", nil)
	if o.root then
		HeatService.UnregisterEye(o.root) -- (out cold: sees nothing)
	end
	draw(o, false)
	stop(o)
	local ok = pcall(function()
		require(ReplicatedStorage.Shared.Util.Ragdoll).Start(o.model, dir * 14 + Vector3.new(0, 10, 0), { NoCap = true })
	end)
	if not ok then
		o.hum.PlatformStand = true
	end
end

local function kill(o, dir)
	o.state = "Dead"
	o.model:SetAttribute("AimTarget", nil)
	o.model:SetAttribute("NPCKind", nil)
	draw(o, false)
	if o.root then
		HeatService.UnregisterEye(o.root)
	end
	pcall(function()
		require(ReplicatedStorage.Shared.Util.Ragdoll).Start(o.model, dir * 16 + Vector3.new(0, 10, 0), { NoCap = true })
	end)
	o.hum.Health = 0
	local model = o.model
	task.delay(K.DEAD_FOR, function()
		if o.model == model then
			byModel[model] = nil
			o.model, o.hum, o.root, o.tracks = nil, nil, nil, nil
		end
		model:Destroy()
	end)
end

-- How far `pos` is from the body of a car (flat, 0 = over it), and where to walk: the door beside the
-- suspect's seat, round the corner on that side first from in front of the car or behind it (straight at
-- the nearest point, an officer behind the car squeezed in between it and the patrol car and stuck there).
local function besideCar(chassis, seat, pos)
	local cf = chassis.CFrame
	local p = cf:PointToObjectSpace(pos)
	local half = chassis.Size / 2
	local near = Vector3.new(math.clamp(p.X, -half.X, half.X), p.Y, math.clamp(p.Z, -half.Z, half.Z))
	local gap = Vector3.new(p.X - near.X, 0, p.Z - near.Z).Magnitude
	local s = cf:PointToObjectSpace(seat.Position)
	local side = s.X < 0 and -1 or 1
	local out = K.CUFF_CAR - 0.5
	local goal = Vector3.new(side * (half.X + out), p.Y, s.Z)
	if side * p.X < half.X and math.abs(p.Z) > half.Z then
		goal = Vector3.new(side * (half.X + out), p.Y, math.sign(p.Z) * (half.Z + out))
	end
	return gap, cf:PointToWorldSpace(goal)
end

local function officerStep(crew, o, dt, p, info, t)
	if o.state == "Down" then
		if t >= o.downUntil then
			getUp(o)
		end
		return
	end
	if o.state ~= "Out" and o.state ~= "Return" then
		return
	end
	local hum, root = o.hum, o.root
	if not root or not root.Parent or hum.Health <= 0 then
		o.state = "Dead"
		return
	end
	animate(o)
	-- Stuck on a kerb or a bench: hop.
	if o.moving and flat(root.AssemblyLinearVelocity).Magnitude < 1.5 then
		o.stuckFor += dt
		if o.stuckFor > K.STUCK then
			o.stuckFor = 0
			hum.Jump = true
		end
	else
		o.stuckFor = 0
	end

	if o.state == "Return" then
		draw(o, false)
		hum.AutoRotate = true
		local door = doorSpot(crew.car, o.seatName)
		if not door or flat(root.Position - door).Magnitude < 5 or t - o.returnAt > K.RETURN_MAX then
			dropWalker(o)
			o.rider = newRider(o, crew.car)
			o.state = "Riding"
		else
			moveTo(o, door, K.RUN)
		end
		return
	end

	local tchar = p.Character
	local troot = tchar and tchar:FindFirstChild("HumanoidRootPart")
	if not troot or not info then
		stop(o)
		return
	end
	local dist = flat(troot.Position - root.Position).Magnitude
	local surrender = p:GetAttribute("Surrender") == true
	local targetSpeed = info.vel.Magnitude
	local los = canSee(o, troot, tchar)
	if crew.hostile and not info.inCar then
		draw(o, true)
		if dist > K.KEEP_FAR or not los then
			hum.AutoRotate = true
			moveTo(o, troot.Position, K.RUN)
		else
			stop(o)
			face(o, troot.Position)
		end
		say(o, "SHOTS FIRED!")
		if los and dist <= K.SHOOT_RANGE and t >= o.nextShot and t - (o.drawnAt or 0) >= K.DRAW_TIME and not o.moving then
			shoot(o, p, troot, tchar, dist, targetSpeed)
		end
		return
	end
	-- Not shooting: arrest them.
	local gunOut = armed(p)
	draw(o, gunOut and not info.inCar)
	-- How far there is to go: to the suspect, or to the side of the car they're in.
	local gap, goal, range = dist, troot.Position, K.CUFF_RANGE
	local thum = tchar:FindFirstChildOfClass("Humanoid")
	local seat = info.inCar and thum and thum.SeatPart
	local chassis = seat and seat.Parent and seat.Parent.PrimaryPart
	if chassis then
		gap, goal = besideCar(chassis, seat, root.Position)
		range = K.CUFF_CAR
	end
	if gap > range then
		hum.AutoRotate = true
		moveTo(o, goal, gap > 12 and K.RUN or K.WALK)
		o.cuffFor = math.max(0, o.cuffFor - dt)
		say(o, surrender and "STAY RIGHT THERE!" or (gunOut and "DROP THE WEAPON!") or "POLICE! HANDS UP!")
		return
	end
	stop(o)
	face(o, troot.Position)
	local still = surrender or (info.inCar and targetSpeed < 5) or (not info.inCar and targetSpeed < K.STILL)
	if still then
		o.cuffFor += dt
		handsUp(p)
		say(o, "YOU'RE UNDER ARREST!")
		if o.cuffFor >= (surrender and K.SURRENDER_CUFF or K.CUFF) then
			o.cuffFor = 0
			arrest(p)
		end
	else
		o.cuffFor = math.max(0, o.cuffFor - dt * 2)
		if o.cuffFor <= 0 then
			handsDown(p)
		end
		say(o, "STOP RIGHT THERE!")
	end
end

------------------------------------------------------------------ public

-- Put `count` officers in this patrol car (driver first, then the passenger seat). nil until the
-- looks are built, or when the car has no seats for them.
function PoliceOfficerService.Board(car, count)
	if #templates == 0 or not car then
		return nil
	end
	local crew = { car = car, officers = {}, out = false, acc = 0, warned = false, hostile = false }
	for i, seatName in ipairs({ "DriverSeat", "PassengerSeat" }) do
		if i > (count or 1) then
			break
		end
		local o = { seatName = seatName, look = rng:NextInteger(1, #templates), state = "Riding" }
		o.rider = newRider(o, car)
		if o.rider then
			table.insert(crew.officers, o)
		end
	end
	if #crew.officers == 0 then
		return nil
	end
	table.insert(crews, crew)
	return crew
end

-- Every patrol frame (AIPoliceService.drive). p: the suspect; info: AIPoliceService's targetInfo (nil
-- with no live body); carSpeed: the patrol car's speed. Returns "ride" (the car drives), "out" (someone
-- is out: the car waits) or "gone" (every officer of this car is down or dead).
function PoliceOfficerService.Step(crew, dt, p, info, carSpeed)
	crew.acc += dt
	if crew.acc < K.TICK then
		return crew.out and "out" or "ride"
	end
	dt, crew.acc = crew.acc, 0
	local car = crew.car
	local chassis = car and car.PrimaryPart
	if not chassis or not car.Parent then
		return "gone"
	end
	local t = os.clock()
	local left = 0 -- officers not dead (a punched-out one gets up again)
	for _, o in ipairs(crew.officers) do
		if o.state == "Riding" or o.state == "Out" or o.state == "Return" or o.state == "Down" then
			left += 1
		end
	end
	if left == 0 then
		return "gone"
	end

	local tchar = p.Character
	local troot = tchar and tchar:FindFirstChild("HumanoidRootPart")
	local targetPos = info and info.pos or (troot and troot.Position)
	local fromCar = targetPos and flat(targetPos - chassis.Position).Magnitude or math.huge
	local drivingOff = info ~= nil and info.inCar and info.vel.Magnitude > K.CAR_GONE

	if not crew.out then
		-- One knocked out and left lying when the others got back in: once he's up, he's back in his seat.
		for _, o in ipairs(crew.officers) do
			if o.state == "Down" and t >= o.downUntil then
				dropWalker(o)
				o.rider = newRider(o, car)
				o.state = "Riding"
			end
		end
		-- All aboard: get out once the car has pulled up next to a suspect on foot or in a stopped car.
		if info and not info.boat and fromCar < K.DISMOUNT and carSpeed < K.DISMOUNT_SPEED and not drivingOff then
			crew.out = true
			for _, o in ipairs(crew.officers) do
				if o.state == "Riding" then
					if o.rider then
						o.rider:Destroy()
						o.rider = nil
					end
					if newWalker(o, car, targetPos) then
						o.state = "Out"
					else
						o.rider = newRider(o, car) -- no room at the door: stays in
					end
				end
			end
			if not crew.warned and p.Parent == Players then
				crew.warned = true
				notify:FireClient(p, "PoliceOnFoot")
			end
		end
		return crew.out and "out" or "ride"
	end

	-- Out: back in when the suspect has driven off or got away from the car.
	if drivingOff or fromCar > K.REMOUNT or not info then
		for _, o in ipairs(crew.officers) do
			if o.state == "Out" then
				o.state = "Return"
				o.returnAt = t
			end
		end
		handsDown(p)
	end
	-- (Never into a safe zone: there they only come to cuff.)
	local cs = service("CombatService")
	local safe = cs ~= nil and type(cs.IsSafe) == "function" and cs.IsSafe(p) == true
	crew.hostile = info ~= nil and not safe and hostileTo(p)
	for _, o in ipairs(crew.officers) do
		local ok, err = pcall(officerStep, crew, o, dt, p, info, t)
		if not ok then
			warn("[PoliceOfficerService] " .. tostring(err))
			if o.state == "Out" or o.state == "Return" then
				dropWalker(o)
				o.rider = newRider(o, car)
				o.state = "Riding"
			end
		end
	end
	-- Everyone who can still ride is back in: drive. (The down and the dead stay behind.)
	local stillOut = 0
	for _, o in ipairs(crew.officers) do
		if o.state == "Out" or o.state == "Return" or (o.state == "Down" and not drivingOff) then
			stillOut += 1
		end
	end
	if stillOut == 0 then
		local anyRiding = false
		for _, o in ipairs(crew.officers) do
			anyRiding = anyRiding or o.state == "Riding"
		end
		if not anyRiding then
			return "gone"
		end
		crew.out = false
		return "ride"
	end
	return "out"
end

-- The car is going: everyone in it or from it goes too (the dead after their time on the ground).
function PoliceOfficerService.Remove(crew)
	if not crew then
		return
	end
	local i = table.find(crews, crew)
	if i then
		table.remove(crews, i)
	end
	for _, o in ipairs(crew.officers) do
		if o.rider then
			o.rider:Destroy()
			o.rider = nil
		end
		if o.state ~= "Dead" then
			dropWalker(o)
		end
		o.state = "Gone"
	end
end

-- A player hit an officer (CombatService): kind "Punch" or "Gun". Returns true if it counted.
function PoliceOfficerService.NPCHit(model, attacker, damage, dir, kind)
	local o = byModel[model]
	if not o or (o.state ~= "Out" and o.state ~= "Return") or typeof(attacker) ~= "Instance" or not attacker:IsA("Player") then
		return false
	end
	if attacker:GetAttribute("Side") ~= "Civilian" then
		return false -- (a cop's stray round)
	end
	damage = tonumber(damage) or 0
	if damage ~= damage or damage <= 0 then
		return false
	end
	local t = os.clock()
	assaultAt[attacker] = t
	local cs = service("CombatService")
	if cs and type(cs.CrimeHeat) == "function" and t - (officerHeatAt[attacker] or -math.huge) >= K.OFFICER_HEAT_GAP then
		officerHeatAt[attacker] = t
		pcall(cs.CrimeHeat, attacker, kind == "Punch" and 1 or 2, "hit_officer", kind ~= "Punch")
	end
	local push = typeof(dir) == "Vector3" and flat(dir) or Vector3.zero
	push = push.Magnitude > 0.05 and push.Unit or flat(o.root.CFrame.LookVector) * -1
	o.hp -= damage
	if o.hp <= 0 then
		if kind == "Punch" then
			o.hp = 0
			knockDown(o, push)
		else
			kill(o, push)
			HeatService.Add(attacker, 1, "officer_down")
		end
	else
		say(o, "OFFICER UNDER FIRE!")
	end
	return true
end

-- Is any walking officer within `range` studs of `pos`? (Giving up near them counts like near a patrol.)
function PoliceOfficerService.Near(pos, range)
	for _, o in pairs(byModel) do
		if o.root and (o.state == "Out" or o.state == "Return") and (o.root.Position - pos).Magnitude <= range then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ giving up (hands up)

local function setSurrender(player, on)
	if player:GetAttribute("Surrender") == (on or nil) then
		return
	end
	player:SetAttribute("Surrender", on or nil)
	local ragdoll = service("RagdollService")
	if ragdoll and type(ragdoll.SetPose) == "function" then
		if on then
			pcall(ragdoll.SetPose, player, "HandsUp")
		elseif player:GetAttribute("Pose") == "HandsUp" then
			pcall(ragdoll.SetPose, player, nil)
		end
	end
end

-- RequestSurrender(on): a wanted citizen on foot puts their hands up (or down again). The tools go
-- away, the hands go up for everyone, and the police come to cuff instead of shooting.
-- Police within `range` studs of `pos`: a player cop, an AI patrol car or an officer on foot.
local function policeNear(pos, range)
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p:GetAttribute("Side") == "Cop" and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - pos).Magnitude <= range then
			return true
		end
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	for _, car in ipairs(vehicles and vehicles:GetChildren() or {}) do
		local chassis = car:GetAttribute("AIPolice") and car.PrimaryPart
		if chassis and (chassis.Position - pos).Magnitude <= range then
			return true
		end
	end
	return PoliceOfficerService.Near(pos, range)
end

local function onSurrender(player, on)
	if not RateLimit.Allow(player, "Surrender", 2, 3) then
		return
	end
	if on ~= true then
		setSurrender(player, false)
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if player:GetAttribute("Side") ~= "Civilian" or HeatService.GetHeat(player) <= 0 or not hum or hum.Health <= 0 or hum.SeatPart then
		return
	end
	local t = serverNow()
	if (player:GetAttribute("KnockedUntil") or 0) > t or (player:GetAttribute("StunnedUntil") or 0) > t then
		return
	end
	-- Only with police to give up to (the HANDS UP tile only shows then too).
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not policeNear(root.Position, K.SURRENDER_RANGE) then
		notify:FireClient(player, "SurrenderNoPolice")
		return
	end
	hum:UnequipTools()
	setSurrender(player, true)
end

function PoliceOfficerService.Init()
	notify = Remotes.Event("Notify")
	npcFolder = Workspace:FindFirstChild("NPCs")
	if not npcFolder then
		npcFolder = Instance.new("Folder")
		npcFolder.Name = "NPCs"
		npcFolder.Parent = Workspace
	end
	buildTemplates()
	Remotes.Event("RequestSurrender").OnServerEvent:Connect(onSurrender)
	-- Hands come down by themselves when there's nothing left to give up to: no stars, a new body, a
	-- seat, or a new side (an arrest makes a prisoner).
	-- Hands up is no shield: a tool back in the hand, a swing or a shot (CombatService clears the
	-- attribute) or walking off puts them down, and the pose with them.
	local function watchBody(player, char)
		char.ChildAdded:Connect(function(c)
			if c:IsA("Tool") then
				setSurrender(player, false)
			end
		end)
	end
	local function watch(player)
		player.CharacterAdded:Connect(function(char)
			setSurrender(player, false)
			watchBody(player, char)
		end)
		if player.Character then
			watchBody(player, player.Character)
		end
		player:GetAttributeChangedSignal("Surrender"):Connect(function()
			local ragdoll = service("RagdollService")
			if player:GetAttribute("Surrender") ~= true and player:GetAttribute("Pose") == "HandsUp" and ragdoll then
				pcall(ragdoll.SetPose, player, nil)
			end
		end)
		player:GetAttributeChangedSignal("Heat"):Connect(function()
			if (player:GetAttribute("Heat") or 0) <= 0 then
				setSurrender(player, false)
			end
		end)
		player:GetAttributeChangedSignal("Side"):Connect(function()
			setSurrender(player, false)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("Surrender") == true then
					local char = p.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					local root = char and char:FindFirstChild("HumanoidRootPart")
					local moving = root and flat(root.AssemblyLinearVelocity).Magnitude > K.SURRENDER_MOVE
					if not hum or hum.Health <= 0 or hum.SeatPart or moving then
						setSurrender(p, false)
					end
				end
			end
		end
	end)
end

return PoliceOfficerService
