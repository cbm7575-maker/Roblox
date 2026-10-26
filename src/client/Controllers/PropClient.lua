-- PropClient (ModuleScript, StarterPlayerScripts.Controllers.PropClient)
-- Street furniture you can plow through, the way it looks and feels on this device. PropService (server)
-- tags every hydrant, bin, news box, bench, lamp post and signal pole "Breakable" (attribute Kind) and
-- puts them in the collision group "Props", which cars never collide with. Everything below is local.
--   * Driving into one. While you drive (cars, not boats), a few times a second the props near your car
--     are picked out of a grid (never every prop), and every frame those few are tested against the
--     car's box, with a sweep from last frame's place so a fast car can't skip over one.
--       - 12 studs/s or faster: it breaks. The server is told (remote "PropHit": prop, your velocity), the
--         car loses a little speed once (3% for a bin up to 8% for a signal pole, never a dead stop), a
--         quiet crash clunk plays, the picture gets a small punch (2-4 degrees of field of view, which
--         DriveController's camera eases back by itself; the car's body nods through VehicleFeel.Kick
--         when that controller is there), and birds nearby take off (AmbienceClient.Scatter, if there).
--         The prop goes down on your screen at once; if the server doesn't agree within 2.5 s it stands
--         back up, and that prop can't be hit again for 5 s.
--       - Slower: nothing breaks, the car just pushes through.
--       - Any speed: a prop the car is about to touch becomes pass-through on this device only (no
--         collisions, no ray hits) until the car has left. Why: the collision group only lets the car's
--         own parts through. The car's wheel rays (CarPhysics) hit whatever a walker could stand on, so
--         a wheel would land on top of a bench the body is driving through and the spring would kick
--         the car into the air; and the people sitting in the car are welded to it but are not in its
--         group, so the driver's own body would hit a lamp post and stop the car dead.
--   * A knocked-over prop (ours, or anyone's: the server sends "PropHit" back to every device with the
--     time it stays down, and keeps that time in the prop's BrokenUntil attribute):
--       - the standing prop is hidden on this device (LocalTransparencyModifier, no shadow, its lights
--         dark) and can be walked through until BrokenUntil has passed; then it fades back in.
--       - a loose copy takes the hit: unanchored parts thrown along the car's path, up and a little to
--         the side it was struck on, spinning. Lamp posts and signal poles fall over instead (they tip
--         about their foot, which is weighted) and their lamps are dark. The copy tumbles, comes to
--         rest (it is then frozen: no more physics, nothing can trip over it) and fades out after 8 s.
--         Loose copies are in the "Props" group too: they land on the road and bounce off walls, but
--         cars drive through them. While you drive, new copies also never touch the people sitting in
--         your car (a NoCollisionConstraint per pair, gone with the piece), for the same reason as above.
--       - a bin scatters a few bits of litter, a news box a few papers.
--       - a hydrant leaves a tall white-blue spout (a ParticleEmitter) for about 12 s (the prop's
--         SpoutUntil attribute), with a quiet splash.
--     At most 12 loose pieces at a time on a phone or in Performance mode and 30 on a PC (the oldest go
--     first), and 2 / 4 spouts. Hits further than 450 studs from the camera get no loose copy.
--   * Streaming: props come and go with the map. A prop that reaches this device while it is knocked
--     over is simply hidden until its time is up (a hydrant still sprays for what is left). A prop that
--     leaves is put back exactly as the server has it first, so nothing we changed can stick to it.
--   * On foot nothing changes: props are solid and stand where they are.
-- Other controllers and the Studio test tools:
--   PropClient.IsDown(prop) -> bool          is it knocked over on this device right now?
--   PropClient.Preview(kind?) -> bool, name  knock the nearest standing prop (of that Kind, within 250
--                                            studs of the camera) over for a few seconds, on this device
--                                            only. For looking at the effect without a car.
--   PropClient.Status                        { Props, Down, Debris, Smashed }: props known here, knocked
--                                            over now, loose pieces now, props you broke this session

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local DriveController = require(script.Parent:WaitForChild("DriveController"))

local PropClient = {}

PropClient.Status = { Props = 0, Down = 0, Debris = 0, Smashed = 0 }

-- Every number in one table (a file may only hold so many locals).
local K = {
	Tag = "Breakable", -- PropService's tag on everything that can be knocked over
	Group = "Props", -- its collision group: never collides with cars or ambient traffic
	Cell = 48, -- studs: one square of the lookup grid

	-- Driving into props
	MinSpeed = 12, -- studs/s: slower than this the car just pushes through and nothing breaks
	ScanEvery = 0.2, -- seconds between looks at which props are near the car...
	ScanMove = 12, -- ...or sooner, once the car has moved this far
	ScanPad = 14, -- studs around the car that count as near...
	ScanAhead = 0.4, -- ...plus this many seconds of its speed
	HitPad = 0.3, -- studs of slack around the car's box
	JumpStuds = 40, -- moved further than this in one frame: the car was placed, not driven (no sweep)
	SoftPad = 2.5, -- studs around the car's box where props turn pass-through...
	SoftAhead = 0.12, -- ...plus this many seconds of its speed
	SoftHold = 0.4, -- seconds a prop stays pass-through after the car has left

	-- Knocked over
	DownTime = 45, -- seconds (PropService's number; used until the server's own time arrives)
	SpoutTime = 12,
	TimeSlack = 5, -- a server time further ahead than DownTime + this is not believed
	PredictWait = 2.5, -- seconds to wait for the server to agree with a hit we showed at once
	RetryWait = 5, -- after it didn't: seconds before that prop can be hit again
	RiseTime = 0.6, -- seconds a prop takes to fade back in
	PollEvery = 0.25, -- seconds between looks at the props that are down
	PendingBatch = 100, -- props without their main part yet: how many are looked at per poll
	SeeRange = 450, -- studs from the camera: further away a prop just vanishes (no loose copy)

	-- Loose pieces
	CapPhone = 12,
	CapPC = 30,
	DebrisLife = 8, -- seconds before a piece starts to fade...
	DebrisFade = 0.8, -- ...and how long the fade takes
	SettleAfter = 1.2, -- seconds before a piece may be frozen...
	SettleSpeed = 1.5, -- ...once it moves and turns slower than this (studs/s, radians/s)...
	SettleChecks = 3, -- ...this many looks in a row...
	CheckEvery = 0.1, -- ...this far apart
	Floor = -80, -- a piece that falls under this height is gone
	Lift = 0.35, -- studs a copy starts above its prop (props stand a little sunk into the kerb)
	SolidSize = 1, -- parts smaller than this (signal lamps) ride along without colliding
	Friction = 0.6,
	Bounce = 0.2,
	-- A copy leaves a little faster than the car (each kind's Throw), so it lands ahead of the bumper
	-- instead of sinking into the bonnet: the car never collides with it and would drive through it.
	ThrowMin = 14, -- studs/s along the car's path, at least...
	ThrowMax = 240, -- ...and at most
	-- Gravity here is strong (196 studs/s^2): 40 studs/s upward is only a 4 stud hop.
	UpBase = 16, -- studs/s upward, plus the kind's share of the car's speed...
	UpMin = 24, -- ...but at least...
	UpMax = 62, -- ...and at most (about 10 studs high)
	SideThrow = 0.3, -- share of the car's speed a prop struck on a corner gets sideways...
	SideFloor = 35, -- ...counting a slow car as this fast (so the piece still clears the wheels)...
	SideMax = 45, -- ...up to this
	SideJitter = 0.12, -- no two throws quite alike
	SpinGain = 0.06, -- radians/s of spin per stud/s, on top of the kind's own...
	SpinMax = 16, -- ...up to this
	-- Posts tip fast enough for the top to outrun the car: a fast hit slams one flat in a quarter second.
	FallBase = 1, -- radians/s a post starts tipping at, plus...
	FallGain = 0.06, -- ...this per stud/s of the car's speed...
	FallMin = 1.5, -- ...but at least...
	FallMax = 7, -- ...and at most
	FallPush = 0.35, -- share of the car's speed the whole post is shoved along with...
	FallPushMax = 40, -- ...up to this (its foot grips the ground, so that is a few studs)
	FallLean = 0.5, -- how far a post struck on a corner tips to that side
	FootSize = Vector3.new(1, 0.5, 1), -- the hidden weight in a post's base
	FootDensity = 20,
	RiderMax = 16, -- body parts of people in our car that loose pieces are kept off, at most (four people)
	LitterPhone = 2,
	LitterPC = 4,
	SpoutsPhone = 2,
	SpoutsPC = 4,

	-- Feel
	SoundGap = 0.08, -- seconds between crash sounds at most
	FovBase = 1.2, -- degrees of field of view punched out, plus...
	FovGain = 30, -- ...this times the kind's speed loss (a bin 2.1, a signal pole 3.6)
	FovFloor = 55,
	NodBase = 0.2, -- radians/s the nose dips (VehicleFeel.Kick), plus...
	NodGain = 4, -- ...this times the kind's speed loss
	NodRoll = 0.25, -- radians/s of roll for a hit on a corner
	BirdRadius = 30,
	PreviewTime = 6,
	PreviewRange = 250,
}

-- How each Kind behaves.
--   Radius   studs: its footprint (a circle; a bench is three of them in a row, Reach apart)
--   Loss     share of the car's speed lost on a hit (heavier = more)
--   Throw    share of the car's speed its copy flies off with; Up: share that goes upward; Spin: radians/s
--   Fall     tips over about its foot instead of flying (lamp posts, signal poles)
--   Density  how heavy the copy is. All of them are light on purpose: weight makes no difference to how
--            a piece flies or tumbles, only to how hard it shoves a walker it lands on (barely)
--   Sound    volume of the crash clunk (a share of Config.Sounds' Crash)
--   Spout    leaves a water spout; Litter: which K.Litter set it scatters
K.Kinds = {
	Hydrant = { Radius = 0.9, Loss = 0.05, Throw = 1.15, Up = 0.3, Spin = 6, Density = 0.5, Sound = 0.45, Spout = true },
	TrashCan = { Radius = 1.2, Loss = 0.03, Throw = 1.25, Up = 0.34, Spin = 9, Density = 0.25, Sound = 0.3, Litter = "Trash" },
	NewsBox = { Radius = 1.2, Loss = 0.035, Throw = 1.2, Up = 0.3, Spin = 8, Density = 0.3, Sound = 0.32, Litter = "Paper" },
	Bench = { Radius = 1.1, Reach = 2.3, Loss = 0.05, Throw = 1.1, Up = 0.24, Spin = 5, Density = 0.3, Sound = 0.4 },
	StreetLight = { Radius = 0.7, Loss = 0.07, Fall = true, Density = 0.25, Sound = 0.5 },
	TrafficSignal = { Radius = 0.8, Loss = 0.08, Fall = true, Density = 0.25, Sound = 0.55 },
}
-- If a prop's Kind attribute hasn't arrived, its name says what it is (the names PropService goes by).
K.ByName = {
	Hydrant = "Hydrant", TrashCan = "TrashCan", NewsBox = "NewsBox", Bench = "Bench", PlazaBench = "Bench",
	TrafficSignal = "TrafficSignal", StreetLight = "StreetLight",
}
K.Litter = {
	Trash = {
		{ Size = Vector3.new(0.55, 0.55, 0.55), Color = Color3.fromRGB(232, 228, 216), Shape = Enum.PartType.Ball }, -- a ball of paper
		{ Size = Vector3.new(0.7, 0.36, 0.36), Color = Color3.fromRGB(196, 62, 52), Shape = Enum.PartType.Cylinder }, -- a drinks can
		{ Size = Vector3.new(0.7, 0.45, 0.5), Color = Color3.fromRGB(150, 112, 74) }, -- a small box
		{ Size = Vector3.new(0.9, 0.15, 0.65), Color = Color3.fromRGB(236, 232, 222) }, -- a sheet of paper
	},
	Paper = {
		{ Size = Vector3.new(1.1, 0.15, 0.8), Color = Color3.fromRGB(236, 232, 222) },
		{ Size = Vector3.new(1, 0.15, 0.7), Color = Color3.fromRGB(214, 212, 204) },
	},
}

-- Everything that changes, in one table.
--   A prop's record: { Inst, Def, Kind, Pos, Cell, Pts, Y0, Y1 (footprint points and height span, made
--     when it first comes near the car), Until (server time it stays down; nil = standing), Predicted
--     (os.clock of a hit the server hasn't confirmed), RetryAt, Soft / SoftAt (pass-through near the car),
--     Saved (the CanCollide / CanQuery we turned off), Hidden, Lights (brightness we turned down),
--     Shadows (shadows we turned off), Gone (left this device) }
--   A loose piece: { Inst, Root, Parts, Alpha (each part's own transparency), Born, Kick, Calm, CheckAt,
--     Frozen, Com, Base }
local S = {
	recs = {}, -- [prop] = record
	grid = {}, -- [cell key] = { record, ... }
	pending = {}, -- records whose main part isn't on this device yet
	pendingI = 1,
	down = {}, -- [record] = true while it is knocked over here
	rising = {}, -- [record] = os.clock() it started fading back in
	soft = {}, -- [record] = true while it is pass-through because our car is on it
	near = {}, -- records near our car (remade every ScanEvery)
	debris = {}, -- loose pieces, oldest first
	spouts = {}, -- [record] = { Part, Emitters, Until, Born }
	friends = {}, -- other controllers, by name (false = failed to load)
	rng = Random.new(),
	started = false,
	remote = nil,
	folder = nil,
	driving = false,
	box = nil, -- our car's box: { Car, X, Y, Z (half sizes), R (flat radius), Seats }
	prevCf = nil, -- our chassis' CFrame last frame
	scanAt = 0,
	scanPos = nil,
	pollAt = 0,
	soundAt = 0,
	warnAt = 0,
}

------------------------------------------------------------------ helpers

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function safely(fn, a)
	local ok, err = pcall(fn, a)
	if not ok and os.clock() - S.warnAt > 5 then
		S.warnAt = os.clock()
		warn("[PropClient] " .. tostring(err))
	end
end

-- Another controller, asked for only when it is needed and never required to be there (SoundClient,
-- SettingsClient, VehicleFeel, AmbienceClient). nil if it is missing or failed to load.
local function friend(name)
	local got = S.friends[name]
	if got == nil then
		local module = script.Parent:FindFirstChild(name)
		if not module then
			return nil -- not there (yet): ask again next time
		end
		local ok, mod = pcall(require, module)
		got = ok and type(mod) == "table" and mod or false
		S.friends[name] = got
	end
	return got or nil
end

-- Phones, and anyone in Performance mode, get fewer loose pieces.
local function lowEnd()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return true
	end
	local settings = friend("SettingsClient")
	if settings and type(settings.Get) == "function" then
		local ok, perf = pcall(settings.Get, "Performance")
		return ok and perf == true
	end
	return false
end

local function playSound(name, where, volume)
	local now = os.clock()
	if name == "Crash" then
		if now - S.soundAt < K.SoundGap then
			return -- a row of props in one frame is one clunk, not five
		end
		S.soundAt = now
	end
	local sounds = friend("SoundClient")
	if sounds and type(sounds.Play) == "function" then
		pcall(sounds.Play, name, where, volume)
	end
end

local function nearCamera(pos, range)
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - pos).Magnitude < range
end

-- Every part of a prop that is on this device right now (a news box is a single part).
local function partsOf(inst)
	local list = {}
	if inst:IsA("BasePart") then
		list[1] = inst
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- The part a prop is measured from: itself, or a Model's PrimaryPart (PropService sets it). nil while
-- that part hasn't reached this device.
local function mainPart(inst)
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart
	end
	return nil
end

-- Half a part's height in the world, whichever way it is turned (a lamp pole is a cylinder lying
-- along its own X axis).
local function halfHeight(part)
	local cf, size = part.CFrame, part.Size
	return (math.abs(cf.XVector.Y) * size.X + math.abs(cf.YVector.Y) * size.Y + math.abs(cf.ZVector.Y) * size.Z) / 2
end

------------------------------------------------------------------ the grid

local function gridAdd(rec)
	local key = math.floor(rec.Pos.X / K.Cell) * 65536 + math.floor(rec.Pos.Z / K.Cell)
	local cell = S.grid[key]
	if not cell then
		cell = {}
		S.grid[key] = cell
	end
	table.insert(cell, rec)
	rec.Cell = key
end

local function gridRemove(rec)
	local key = rec.Cell
	local cell = key and S.grid[key]
	if cell then
		local i = table.find(cell, rec)
		if i then
			cell[i] = cell[#cell]
			cell[#cell] = nil
		end
		if #cell == 0 then
			S.grid[key] = nil
		end
	end
	rec.Cell = nil
end

------------------------------------------------------------------ a prop's state on this device

-- No collisions and no ray hits, on this device only. What we turn off is remembered so harden can put
-- it back exactly. Safe to call again: parts that arrived since (or were reset) are caught too.
local function soften(rec, parts)
	local saved = rec.Saved
	if not saved then
		saved = {}
		rec.Saved = saved
	end
	for _, part in ipairs(parts or partsOf(rec.Inst)) do
		if part.CanCollide or part.CanQuery then
			if not saved[part] then
				saved[part] = { part.CanCollide, part.CanQuery }
			end
			part.CanCollide = false
			part.CanQuery = false
		end
	end
end

local function harden(rec)
	local saved = rec.Saved
	if saved then
		rec.Saved = nil
		for part, was in pairs(saved) do
			part.CanCollide = was[1]
			part.CanQuery = was[2]
		end
	end
end

-- Solid unless it is knocked over or our car is on it.
local function syncSolid(rec)
	if rec.Until or rec.Soft then
		soften(rec)
	else
		harden(rec)
	end
end

-- Hide the standing prop on this device: invisible, no shadow, its lights dark. The server's own values
-- are never touched (LocalTransparencyModifier), and what we do change is remembered for show.
local function hide(rec, parts)
	rec.Hidden = true
	local lights, shadows = rec.Lights, rec.Shadows
	if not lights then
		lights, shadows = {}, {}
		rec.Lights, rec.Shadows = lights, shadows
	end
	for _, part in ipairs(parts or partsOf(rec.Inst)) do
		if part.LocalTransparencyModifier < 1 then
			part.LocalTransparencyModifier = 1
		end
		if part.CastShadow then -- an unseen part still throws a shadow
			shadows[part] = true
			part.CastShadow = false
		end
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Light") then
				-- Brightness, not Enabled: SkyClient switches Enabled at dusk and dawn.
				if lights[child] == nil then
					lights[child] = child.Brightness
				end
				if child.Brightness ~= 0 then
					child.Brightness = 0
				end
			elseif child:IsA("Decal") then
				child.LocalTransparencyModifier = 1
			end
		end
	end
end

-- Bring it back: alpha 0 = still unseen, 1 = fully there (and everything hide changed is put back).
local function show(rec, alpha)
	local ltm = 1 - alpha
	for _, part in ipairs(partsOf(rec.Inst)) do
		part.LocalTransparencyModifier = ltm
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Decal") then
				child.LocalTransparencyModifier = ltm
			end
		end
	end
	local lights = rec.Lights
	if lights then
		for light, was in pairs(lights) do
			light.Brightness = was * alpha
		end
	end
	if alpha >= 1 then
		local shadows = rec.Shadows
		if shadows then
			for part in pairs(shadows) do
				part.CastShadow = true
			end
		end
		rec.Lights, rec.Shadows = nil, nil
		rec.Hidden = false
	end
end

-- A prop's footprint and height span, worked out once, the first time it comes near the car.
local function ensureGeo(rec)
	if rec.Pts then
		return true
	end
	local main = mainPart(rec.Inst)
	if not main then
		return false
	end
	local centre = main.Position
	local y0, y1 = math.huge, -math.huge
	for _, part in ipairs(partsOf(rec.Inst)) do
		local half = halfHeight(part)
		y0 = math.min(y0, part.Position.Y - half)
		y1 = math.max(y1, part.Position.Y + half)
	end
	local pts = { centre }
	local reach = rec.Def.Reach
	if reach then
		-- A long prop (a bench): three circles along its longer side.
		local cf, size = main.CFrame, main.Size
		local axis = flat(size.X >= size.Z and cf.XVector or cf.ZVector)
		if axis.Magnitude > 0.1 then
			axis = axis.Unit * reach
			pts[2] = centre + axis
			pts[3] = centre - axis
		end
	end
	rec.Pts, rec.Y0, rec.Y1 = pts, y0, y1
	return true
end

------------------------------------------------------------------ hydrant spouts

local function stopSpout(rec)
	local spout = S.spouts[rec]
	if not spout then
		return
	end
	S.spouts[rec] = nil
	for _, emitter in ipairs(spout.Emitters) do
		emitter.Enabled = false
	end
	local part = spout.Part
	task.delay(2, function() -- the drops already in the air fall first
		part:Destroy()
	end)
end

local function debrisFolder()
	local f = S.folder
	if not f or not f.Parent then
		f = Instance.new("Folder")
		f.Name = "PropDebris"
		f.Parent = Workspace
		S.folder = f
	end
	return f
end

-- Water shooting out of the ground where a hydrant stood, until `spoutUntil` (server time).
local function startSpout(rec, spoutUntil)
	local have = S.spouts[rec]
	if have then
		have.Until = spoutUntil
		return
	end
	if not ensureGeo(rec) then
		return
	end
	local low = lowEnd()
	local count, oldest = 0, nil
	for other, spout in pairs(S.spouts) do
		count += 1
		if not oldest or spout.Born < S.spouts[oldest].Born then
			oldest = other
		end
	end
	if oldest and count >= (low and K.SpoutsPhone or K.SpoutsPC) then
		stopSpout(oldest)
	end

	local base = Instance.new("Part")
	base.Name = "Spout"
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CastShadow = false
	base.Transparency = 1
	base.Size = Vector3.new(0.8, 0.4, 0.8)
	base.CFrame = CFrame.new(rec.Pos.X, rec.Y0 + 0.6, rec.Pos.Z)

	local jet = Instance.new("ParticleEmitter")
	jet.Name = "Jet"
	jet.Texture = "rbxasset://textures/particles/smoke_main.dds"
	jet.Color = ColorSequence.new(Color3.fromRGB(236, 246, 255), Color3.fromRGB(172, 216, 255))
	jet.LightEmission = 0.25
	jet.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	jet.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.5, 2.6),
		NumberSequenceKeypoint.new(1, 4.2),
	})
	jet.EmissionDirection = Enum.NormalId.Top
	jet.Speed = NumberRange.new(62, 78) -- with the pull below: about 20 studs up, then back down
	jet.Acceleration = Vector3.new(0, -95, 0)
	jet.Lifetime = NumberRange.new(1.1, 1.5)
	jet.SpreadAngle = Vector2.new(5, 5)
	jet.Drag = 0.4
	jet.Rotation = NumberRange.new(0, 360)
	jet.RotSpeed = NumberRange.new(-60, 60)
	jet.Rate = low and 26 or 55
	jet.Parent = base
	local emitters = { jet }
	if not low then
		-- A low ring of spray where the water comes back down.
		local mist = Instance.new("ParticleEmitter")
		mist.Name = "Mist"
		mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mist.Color = ColorSequence.new(Color3.fromRGB(226, 240, 255))
		mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 5) })
		mist.EmissionDirection = Enum.NormalId.Top
		mist.Speed = NumberRange.new(5, 11)
		mist.SpreadAngle = Vector2.new(80, 80)
		mist.Lifetime = NumberRange.new(0.8, 1.2)
		mist.Rotation = NumberRange.new(0, 360)
		mist.Rate = 10
		mist.Parent = base
		emitters[2] = mist
	end
	base.Parent = debrisFolder()
	S.spouts[rec] = { Part = base, Emitters = emitters, Until = spoutUntil, Born = os.clock() }
	playSound("Splash", base.Position, 0.35)
end

------------------------------------------------------------------ loose pieces

-- What every loose part has in common: it falls, nothing can touch-fire or ray-hit it, and cars drive
-- through it ("Props" group; if that group somehow isn't on this device yet the part stays as it is).
local function dress(part)
	part.Anchored = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = false
	pcall(function()
		part.CollisionGroup = K.Group
	end)
end

-- The solid body parts of everyone sitting in the car we drive. A seated body is welded to its seat,
-- so to the physics it is part of the car; but it is not in the car's collision group, so unlike the
-- car's own parts it would run into a loose piece the car is driving through, and the car would feel
-- it. (Standing props are no trouble: the ones around the car are pass-through, see driveStep.)
local function riderParts()
	local list = {}
	local box = S.box
	if not S.driving or not box then
		return list
	end
	for _, seat in ipairs(box.Seats) do
		local hum = seat.Parent and seat.Occupant
		local char = hum and hum.Parent
		if char then
			for _, d in ipairs(char:GetChildren()) do
				if d:IsA("BasePart") and d.CanCollide and #list < K.RiderMax then
					table.insert(list, d)
				end
			end
		end
	end
	return list
end

-- These loose parts never touch those bodies: one NoCollisionConstraint per pair, kept inside the
-- loose part so it goes when the piece goes. Call it once each part's CanCollide is final.
local function shield(parts, riders)
	if #riders == 0 then
		return
	end
	for _, p in ipairs(parts) do
		if p.CanCollide then
			for _, body in ipairs(riders) do
				local apart = Instance.new("NoCollisionConstraint")
				apart.Part0 = body
				apart.Part1 = p
				apart.Parent = p
			end
		end
	end
end

-- A copy of one part of a prop, standing where the part stands. Plain Parts are made new (no tags,
-- attributes, lights or anything else comes along); anything else is cloned and stripped.
local function copyPart(src)
	local p
	if src.ClassName == "Part" then
		p = Instance.new("Part")
		p.Shape = src.Shape
		p.Size = src.Size
		p.Color = src.Color
		p.Material = src.Material
		p.Reflectance = src.Reflectance
		p.Transparency = src.Transparency
	else
		p = src:Clone()
		-- Before it is parented anywhere: a copy must never count as a prop, a night lamp or a signal.
		for _, tag in ipairs(CollectionService:GetTags(p)) do
			CollectionService:RemoveTag(p, tag)
		end
		for _, child in ipairs(p:GetChildren()) do
			if not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		p.LocalTransparencyModifier = 0
	end
	p.Name = "Piece"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if p.Material == Enum.Material.Neon then
		-- A lit lamp: the light goes out when the post comes down.
		p.Material = Enum.Material.SmoothPlastic
		p.Color = p.Color:Lerp(Color3.new(0, 0, 0), 0.7)
	end
	p.CFrame = src.CFrame + Vector3.new(0, K.Lift, 0)
	dress(p)
	return p
end

-- The whole prop as one loose body: a copy of each visible part, welded to the copy of its main part.
-- Posts that fall over (def.Fall) get a hidden weight in the foot, so they tip about their base.
-- riders: body parts the copy must never touch (riderParts).
local function buildCopy(rec, def, riders)
	local srcMain = mainPart(rec.Inst)
	local model = Instance.new("Model")
	model.Name = "Prop"
	local parts, alpha = {}, {}
	local root = nil
	local mass, moment = 0, Vector3.zero
	local physical = PhysicalProperties.new(def.Density, K.Friction, K.Bounce)
	for _, src in ipairs(partsOf(rec.Inst)) do
		if src.Transparency < 0.98 then
			local p = copyPart(src)
			local size = p.Size
			p.CustomPhysicalProperties = physical
			p.CanCollide = math.max(size.X, size.Y, size.Z) >= K.SolidSize
			p.Parent = model
			table.insert(parts, p)
			table.insert(alpha, p.Transparency)
			if src == srcMain then
				root = p
			end
			local m = def.Density * size.X * size.Y * size.Z
			mass += m
			moment += p.Position * m
		end
	end
	root = root or parts[1]
	if not root then
		model:Destroy()
		return nil
	end
	local base = nil
	if def.Fall then
		local at = root.Position
		base = Vector3.new(at.X, at.Y - halfHeight(root), at.Z)
		local size = K.FootSize
		local foot = Instance.new("Part")
		foot.Name = "Foot"
		foot.Size = size
		foot.Transparency = 1
		foot.CFrame = CFrame.new(base + Vector3.new(0, size.Y / 2, 0))
		foot.CustomPhysicalProperties = PhysicalProperties.new(K.FootDensity, 1, 0, 10, 1) -- grips the ground
		dress(foot)
		foot.CanCollide = true
		foot.Parent = model
		table.insert(parts, foot)
		table.insert(alpha, 1)
		local m = K.FootDensity * size.X * size.Y * size.Z
		mass += m
		moment += foot.Position * m
	end
	for _, p in ipairs(parts) do
		if p ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
		end
	end
	shield(parts, riders)
	model.Parent = debrisFolder()
	return {
		Inst = model, Root = root, Parts = parts, Alpha = alpha, Born = os.clock(), CheckAt = 0, Calm = 0,
		Com = mass > 0 and moment / mass or root.Position, Base = base,
	}
end

-- Send a piece on its way. Set on every part (they are one welded body, so it is the same motion), and
-- kept in piece.Kick so tendDebris can set it once more after the first physics step: a body welded
-- together this very frame may not count as one body yet.
local function launch(piece, lin, ang)
	for _, p in ipairs(piece.Parts) do
		p.AssemblyLinearVelocity = lin
		p.AssemblyAngularVelocity = ang
	end
	piece.Kick = { lin, ang }
end

-- Room for n more pieces under the cap: the oldest go first.
local function makeRoom(n)
	local list = S.debris
	local cap = lowEnd() and K.CapPhone or K.CapPC
	while #list > 0 and #list + n > cap do
		table.remove(list, 1).Inst:Destroy()
	end
end

-- A few small bits thrown out of a bin or a news box, each its own piece.
local function spawnLitter(kind, count, at, vel, riders)
	local shapes = K.Litter[kind]
	if not shapes then
		return
	end
	local rng = S.rng
	local physical = PhysicalProperties.new(0.2, K.Friction, K.Bounce)
	local one = {}
	for i = 1, count do
		local shape = shapes[(i - 1) % #shapes + 1]
		local p = Instance.new("Part")
		p.Name = "Litter"
		if shape.Shape then
			p.Shape = shape.Shape
		end
		p.Size = shape.Size
		p.Color = shape.Color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CustomPhysicalProperties = physical
		p.CFrame = CFrame.new(at + Vector3.new(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0.4, 1.6), rng:NextNumber(-0.7, 0.7)))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
		dress(p)
		p.CanCollide = true
		one[1] = p
		shield(one, riders)
		p.Parent = debrisFolder()
		local piece = { Inst = p, Root = p, Parts = { p }, Alpha = { 0 }, Born = os.clock(), CheckAt = 0, Calm = 0 }
		launch(piece, vel * rng:NextNumber(0.45, 0.95) + Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(10, 22), rng:NextNumber(-9, 9)),
			rng:NextUnitVector() * rng:NextNumber(4, 12))
		table.insert(S.debris, piece)
	end
end

-- The loose copy of a prop that was just hit. vel = the car's flat velocity; side = -1..1, which side
-- of the car's path the prop was struck on (it is thrown, or tips, a little that way).
local function spawnDebris(rec, vel, side)
	local def = rec.Def
	local litter = 0
	if def.Litter then
		litter = lowEnd() and K.LitterPhone or K.LitterPC
	end
	makeRoom(1 + litter)
	local riders = riderParts()
	local piece = buildCopy(rec, def, riders)
	if not piece then
		return
	end
	local speed = vel.Magnitude
	local dir = speed > 0.5 and vel.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	side = math.clamp(side + S.rng:NextNumber(-K.SideJitter, K.SideJitter), -1, 1)
	local out
	if def.Fall then
		-- Turning about (up x lean) makes the top fall toward lean (the same trick as ImpactClient's
		-- knock-down); the centre of mass is moved so that the foot stays where it is.
		local lean = (dir + right * (side * K.FallLean)).Unit
		local ang = Vector3.yAxis:Cross(lean) * math.clamp(K.FallBase + speed * K.FallGain, K.FallMin, K.FallMax)
		out = dir * math.min(speed * K.FallPush, K.FallPushMax)
		launch(piece, ang:Cross(piece.Com - piece.Base) + out, ang)
	else
		out = dir * math.clamp(speed * def.Throw, K.ThrowMin, K.ThrowMax)
			+ right * math.clamp(side * math.max(speed, K.SideFloor) * K.SideThrow, -K.SideMax, K.SideMax)
		launch(piece, out + Vector3.new(0, math.clamp(K.UpBase + speed * def.Up, K.UpMin, K.UpMax), 0),
			S.rng:NextUnitVector() * math.min(def.Spin + speed * K.SpinGain, K.SpinMax))
	end
	table.insert(S.debris, piece)
	if litter > 0 then
		spawnLitter(def.Litter, litter, rec.Pos, out, riders)
	end
	PropClient.Status.Debris = #S.debris
end

local function freeze(piece)
	piece.Frozen = true
	for _, p in ipairs(piece.Parts) do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
	end
end

local function tendDebris(now)
	local list = S.debris
	for i = #list, 1, -1 do
		local piece = list[i]
		local root = piece.Root
		local age = now - piece.Born
		if not root.Parent or age >= K.DebrisLife + K.DebrisFade or root.Position.Y < K.Floor then
			piece.Inst:Destroy()
			table.remove(list, i)
		elseif age >= K.DebrisLife then
			local a = (age - K.DebrisLife) / K.DebrisFade
			for j, p in ipairs(piece.Parts) do
				local own = piece.Alpha[j]
				p.Transparency = own + (1 - own) * a
			end
		else
			local kick = piece.Kick
			if kick then
				piece.Kick = nil
				for _, p in ipairs(piece.Parts) do
					p.AssemblyLinearVelocity = kick[1]
					p.AssemblyAngularVelocity = kick[2]
				end
			elseif not piece.Frozen and age > K.SettleAfter and now >= piece.CheckAt then
				-- Come to rest: stop simulating it. From here on it is only a picture (no collisions, no
				-- ray hits), so nobody trips over it and no wheel rides up on it.
				piece.CheckAt = now + K.CheckEvery
				if root.AssemblyLinearVelocity.Magnitude < K.SettleSpeed and root.AssemblyAngularVelocity.Magnitude < K.SettleSpeed then
					piece.Calm += 1
					if piece.Calm >= K.SettleChecks then
						freeze(piece)
					end
				else
					piece.Calm = 0
				end
			end
		end
	end
	PropClient.Status.Debris = #list
end

------------------------------------------------------------------ knocked over / standing again

-- The prop is down until `downUntil` (server time). vel = the flat velocity of the car that hit it when
-- we saw it happen (it gets a loose copy), nil when it was already down as it reached this device.
-- predicted = our own hit, shown before the server has agreed.
local function knockDown(rec, downUntil, vel, side, predicted)
	local standing = rec.Until == nil
	rec.Until = downUntil
	rec.Predicted = predicted and os.clock() or nil
	if not standing then
		return
	end
	S.rising[rec] = nil
	S.down[rec] = true
	PropClient.Status.Down += 1
	if vel then
		-- Before the prop is hidden (the copy is made from how it looks now). A copy that fails to build
		-- must never stop the prop itself from going down.
		safely(function()
			spawnDebris(rec, vel, side or 0)
		end)
	end
	local parts = partsOf(rec.Inst)
	hide(rec, parts)
	soften(rec, parts)
end

local function standUp(rec)
	if rec.Until == nil then
		return
	end
	rec.Until = nil
	rec.Predicted = nil
	S.down[rec] = nil
	PropClient.Status.Down = math.max(0, PropClient.Status.Down - 1)
	syncSolid(rec) -- solid again, unless our car is standing in it
	S.rising[rec] = os.clock()
end

local function tendRising(now)
	for rec, t0 in pairs(S.rising) do
		local a = math.clamp((now - t0) / K.RiseTime, 0, 1)
		show(rec, a)
		if a >= 1 then
			S.rising[rec] = nil
		end
	end
end

------------------------------------------------------------------ which props exist here

-- Put a record on the grid, once its main part is here. A prop that is already knocked over is hidden
-- straight away (no loose copy: whatever flew off has long gone).
local function place(rec)
	local main = mainPart(rec.Inst)
	if not main then
		table.insert(S.pending, rec)
		return
	end
	rec.Pos = main.Position
	gridAdd(rec)
	local now = Workspace:GetServerTimeNow()
	local downUntil = rec.Inst:GetAttribute("BrokenUntil")
	if type(downUntil) == "number" and downUntil > now then
		knockDown(rec, math.min(downUntil, now + K.DownTime + K.TimeSlack), nil, 0, false)
		local spoutUntil = rec.Inst:GetAttribute("SpoutUntil")
		if rec.Def.Spout and type(spoutUntil) == "number" and spoutUntil > now then
			startSpout(rec, math.min(spoutUntil, now + K.SpoutTime + K.TimeSlack))
		end
	end
end

local function onAdded(inst)
	if S.recs[inst] or not inst:IsDescendantOf(Workspace) then
		return
	end
	local kind = inst:GetAttribute("Kind")
	if type(kind) ~= "string" or not K.Kinds[kind] then
		kind = K.ByName[inst.Name]
	end
	local def = kind and K.Kinds[kind]
	if not def then
		return
	end
	local rec = { Inst = inst, Def = def, Kind = kind }
	S.recs[inst] = rec
	PropClient.Status.Props += 1
	place(rec)
end

-- The prop left this device (streamed out, or lost its tag). Put back everything we changed on it
-- while we can still reach its parts, then forget it.
local function forget(inst)
	local rec = S.recs[inst]
	if not rec then
		return
	end
	S.recs[inst] = nil
	rec.Gone = true -- (lists that still hold it skip it; the pending list drops it on its next pass)
	PropClient.Status.Props = math.max(0, PropClient.Status.Props - 1)
	gridRemove(rec)
	if rec.Until ~= nil then
		rec.Until = nil
		S.down[rec] = nil
		PropClient.Status.Down = math.max(0, PropClient.Status.Down - 1)
	end
	rec.Soft = false
	S.soft[rec] = nil
	S.rising[rec] = nil
	stopSpout(rec)
	harden(rec)
	if rec.Hidden or rec.Lights then
		show(rec, 1)
	end
end

------------------------------------------------------------------ driving into props

-- Our car's box (half sizes), measured once per car the way DriveController measures it: a mesh body
-- can be bigger than the chassis, but is never trusted past 1.5 x it.
local function carBox(car, chassis)
	local box = S.box
	if box and box.Car == car then
		return box
	end
	local size = chassis.Size
	local x, y, z = size.X, size.Y, size.Z
	local ok, extents = pcall(function()
		return car:GetExtentsSize()
	end)
	if ok and typeof(extents) == "Vector3" then
		x = math.clamp(extents.X, size.X, size.X * 1.5)
		z = math.clamp(extents.Z, size.Z, size.Z * 1.5)
		y = math.clamp(extents.Y, size.Y, size.Y * 3)
	end
	-- Its seats, for riderParts (a car reaches a device whole, so they are all here by now).
	local seats = {}
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("Seat") or d:IsA("VehicleSeat") then
			table.insert(seats, d)
		end
	end
	box = { Car = car, X = x / 2, Y = y / 2, Z = z / 2, R = math.sqrt(x * x + z * z) / 2, Seats = seats }
	S.box = box
	S.prevCf = nil
	S.scanPos = nil
	return box
end

-- The props within `reach` studs of `pos`, from the grid, into S.near.
local function gather(pos, reach)
	local near = S.near
	table.clear(near)
	local c = K.Cell
	local limit = (reach + 4) * (reach + 4) -- (+4: a bench reaches past its middle)
	for cx = math.floor((pos.X - reach) / c), math.floor((pos.X + reach) / c) do
		for cz = math.floor((pos.Z - reach) / c), math.floor((pos.Z + reach) / c) do
			local cell = S.grid[cx * 65536 + cz]
			if cell then
				for _, rec in ipairs(cell) do
					local dx, dz = rec.Pos.X - pos.X, rec.Pos.Z - pos.Z
					if dx * dx + dz * dz <= limit and ensureGeo(rec) then
						table.insert(near, rec)
					end
				end
			end
		end
	end
end

-- Does the straight path from (x0, z0) to (x1, z1) pass through the box -hx..hx, -hz..hz? (The prop's
-- path in the car's own frame since last frame: at speed the car covers a few studs between frames.)
local function crosses(x0, z0, x1, z1, hx, hz)
	local t0, t1 = 0, 1
	local dx, dz = x1 - x0, z1 - z0
	if math.abs(dx) < 1e-6 then
		if math.abs(x0) > hx then
			return false
		end
	else
		local a, b = (-hx - x0) / dx, (hx - x0) / dx
		if a > b then
			a, b = b, a
		end
		t0, t1 = math.max(t0, a), math.min(t1, b)
		if t0 > t1 then
			return false
		end
	end
	if math.abs(dz) < 1e-6 then
		if math.abs(z0) > hz then
			return false
		end
	else
		local a, b = (-hz - z0) / dz, (hz - z0) / dz
		if a > b then
			a, b = b, a
		end
		t0, t1 = math.max(t0, a), math.min(t1, b)
		if t0 > t1 then
			return false
		end
	end
	return true
end

-- Props the car has left turn solid again (all of them at once when we stop driving).
local function releaseSoft(now, all)
	for rec in pairs(S.soft) do
		if all or now - (rec.SoftAt or 0) > K.SoftHold then
			rec.Soft = false
			S.soft[rec] = nil
			syncSolid(rec)
		end
	end
end

local function stopDriving()
	S.driving = false
	S.box = nil
	S.prevCf = nil
	S.scanPos = nil
	table.clear(S.near)
	releaseSoft(0, true)
end

-- The bump you feel: a small punch of the field of view (DriveController's camera eases it back by
-- itself over the next quarter second) and a nod of the car's body.
local function kick(car, def, side)
	local camera = Workspace.CurrentCamera
	if camera and DriveController.Status.Driving then
		camera.FieldOfView = math.max(camera.FieldOfView - (K.FovBase + def.Loss * K.FovGain), K.FovFloor)
	end
	local feel = friend("VehicleFeel")
	if feel and type(feel.Kick) == "function" then
		-- (pitch below zero = nose down, the way braking dips it)
		pcall(feel.Kick, car, -(K.NodBase + def.Loss * K.NodGain), side * K.NodRoll, 0)
	end
end

-- Our car just drove through a standing prop fast enough to break it. side = -1..1: where across the
-- car's width the prop was (right is positive).
local function smash(rec, car, chassis, side)
	local def = rec.Def
	local vel = chassis.AssemblyLinearVelocity
	local hitVel = flat(vel)
	-- `side` is in the car's own frame, the pieces are thrown in the frame of its motion: the other way
	-- round when the car backs into something.
	if hitVel.Magnitude > 0.5 then
		local dir = hitVel.Unit
		if chassis.CFrame.RightVector:Dot(Vector3.new(-dir.Z, 0, dir.X)) < 0 then
			side = -side
		end
	end
	local now = Workspace:GetServerTimeNow()
	knockDown(rec, now + K.DownTime, hitVel, side, true)
	if def.Spout then
		startSpout(rec, now + K.SpoutTime)
	end
	if S.remote then
		S.remote:FireServer(rec.Inst, hitVel)
	end
	-- Lose a little speed, once (never the up-and-down part, never a dead stop).
	local keep = 1 - def.Loss
	chassis.AssemblyLinearVelocity = Vector3.new(vel.X * keep, vel.Y, vel.Z * keep)
	PropClient.Status.Smashed += 1
	playSound("Crash", chassis.Position, def.Sound)
	kick(car, def, side)
	local ambience = friend("AmbienceClient")
	if ambience and type(ambience.Scatter) == "function" then
		pcall(ambience.Scatter, rec.Pos, K.BirdRadius)
	end
end

-- Every frame, before the frame's physics (so a prop is already pass-through when the wheel rays are
-- cast): the few props near our car against the car's box.
local function driveStep()
	local status = DriveController.Status
	local car = status.Driving and status.Car
	local chassis = car and car.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) or car:GetAttribute("Boat") == true then
		if S.driving then
			stopDriving()
		end
		return
	end
	S.driving = true
	local now = os.clock()
	local cf = chassis.CFrame
	local pos = cf.Position
	local vel = chassis.AssemblyLinearVelocity
	local speed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	local box = carBox(car, chassis)
	if now - S.scanAt >= K.ScanEvery or not S.scanPos or (pos - S.scanPos).Magnitude > K.ScanMove then
		S.scanAt, S.scanPos = now, pos
		gather(pos, box.R + K.ScanPad + speed * K.ScanAhead)
		releaseSoft(now, false)
	end
	local prev = S.prevCf
	S.prevCf = cf
	local near = S.near
	if #near == 0 then
		return
	end
	if prev and (prev.Position - pos).Magnitude > K.JumpStuds then
		prev = nil
	end
	local bottom, top = pos.Y - box.Y - 2, pos.Y + box.Y + 2 -- (wheels below the box, a roof above it)
	local softPad = K.SoftPad + speed * K.SoftAhead
	local canBreak = speed >= K.MinSpeed
	for _, rec in ipairs(near) do
		-- Props that are already down are pass-through anyway; a car on a bridge misses what is under it.
		if not rec.Gone and rec.Until == nil and rec.Y0 < top and rec.Y1 > bottom then
			local r = rec.Def.Radius
			local hx, hz = box.X + r, box.Z + r
			local close, touching, sideX = false, false, 0
			for _, pt in ipairs(rec.Pts) do
				local lp = cf:PointToObjectSpace(pt)
				local ax, az = math.abs(lp.X), math.abs(lp.Z)
				if ax < hx + softPad and az < hz + softPad then
					close = true
				end
				if canBreak and not touching then
					if ax < hx + K.HitPad and az < hz + K.HitPad then
						touching, sideX = true, lp.X
					elseif prev then
						local lp0 = prev:PointToObjectSpace(pt)
						if crosses(lp0.X, lp0.Z, lp.X, lp.Z, hx, hz) then
							touching, sideX = true, (lp0.X + lp.X) / 2
						end
					end
				end
			end
			if close or touching then
				rec.SoftAt = now
				if not rec.Soft then
					rec.Soft = true
					S.soft[rec] = true
					soften(rec)
				end
			end
			if touching and now >= (rec.RetryAt or 0) then
				smash(rec, car, chassis, math.clamp(sideX / box.X, -1, 1))
			end
		end
	end
end

------------------------------------------------------------------ upkeep

-- A few times a second: props whose time is up stand back up, hits the server never agreed to are
-- taken back, props that are down stay hidden (parts can arrive late), spouts run dry, and props that
-- arrived without their main part are looked at again.
local function poll(now)
	local serverNow = Workspace:GetServerTimeNow()
	for rec in pairs(S.down) do
		if rec.Predicted and now - rec.Predicted > K.PredictWait then
			rec.RetryAt = now + K.RetryWait
			stopSpout(rec)
			standUp(rec)
		elseif serverNow >= rec.Until then
			standUp(rec)
		else
			local parts = partsOf(rec.Inst)
			hide(rec, parts)
			soften(rec, parts)
		end
	end
	for rec, spout in pairs(S.spouts) do
		if serverNow >= spout.Until then
			stopSpout(rec)
		end
	end
	local pending = S.pending
	if #pending > 0 then
		local i = S.pendingI
		for _ = 1, math.min(#pending, K.PendingBatch) do
			if #pending == 0 then
				break
			end
			if i > #pending then
				i = 1
			end
			local rec = pending[i]
			if rec.Gone or mainPart(rec.Inst) then
				pending[i] = pending[#pending]
				pending[#pending] = nil
				if not rec.Gone then
					place(rec)
				end
			else
				i += 1
			end
		end
		S.pendingI = i
	end
end

local function upkeep()
	local now = os.clock()
	if now >= S.pollAt then
		S.pollAt = now + K.PollEvery
		poll(now)
	end
	if next(S.rising) ~= nil then
		tendRising(now)
	end
	if #S.debris > 0 then
		tendDebris(now)
	end
end

------------------------------------------------------------------ the server's word

-- "PropHit" from the server: this prop went down (ours, confirmed, or somebody else's).
local function onServerHit(prop, downUntil, vel, spoutUntil)
	if typeof(prop) ~= "Instance" or type(downUntil) ~= "number" or downUntil ~= downUntil then
		return -- (a prop that isn't on this device arrives as nil: its attribute tells us when it gets here)
	end
	local rec = S.recs[prop]
	if not rec or rec.Gone then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if downUntil <= now then
		return
	end
	downUntil = math.min(downUntil, now + K.DownTime + K.TimeSlack)
	if rec.Until ~= nil then
		-- Already down here (our own hit, shown at once): now it is official.
		rec.Until = downUntil
		rec.Predicted = nil
	elseif rec.Pos then
		local seen = nearCamera(rec.Pos, K.SeeRange)
		local v = (typeof(vel) == "Vector3" and vel.X == vel.X and vel.Z == vel.Z) and flat(vel) or Vector3.zero
		knockDown(rec, downUntil, seen and v or nil, S.rng:NextNumber(-0.3, 0.3), false)
		if seen then
			playSound("Crash", rec.Pos, rec.Def.Sound * 0.8)
		end
	else
		return -- its main part isn't here yet: place() reads the attribute when it is
	end
	if rec.Def.Spout and type(spoutUntil) == "number" and spoutUntil > now then
		startSpout(rec, math.min(spoutUntil, now + K.SpoutTime + K.TimeSlack))
	end
end

------------------------------------------------------------------ for other controllers and tests

function PropClient.IsDown(prop)
	local rec = S.recs[prop]
	return rec ~= nil and rec.Until ~= nil
end

function PropClient.Preview(kind)
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	local at = camera.CFrame.Position
	local best, bestD = nil, K.PreviewRange
	for _, rec in pairs(S.recs) do
		if rec.Pos and rec.Until == nil and (kind == nil or rec.Kind == kind) then
			local d = (rec.Pos - at).Magnitude
			if d < bestD then
				best, bestD = rec, d
			end
		end
	end
	if not best then
		return false
	end
	local dir = flat(camera.CFrame.LookVector)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, -1)
	local now = Workspace:GetServerTimeNow()
	knockDown(best, now + K.PreviewTime, dir * 45, 0, false)
	if best.Def.Spout then
		startSpout(best, now + K.PreviewTime)
	end
	playSound("Crash", best.Pos, best.Def.Sound)
	return true, best.Inst:GetFullName()
end

function PropClient.Init()
	if S.started then
		return
	end
	S.started = true
	-- Fetched in its own thread: the client version of Remotes.Event waits for the server to make it.
	task.spawn(function()
		S.remote = Remotes.Event("PropHit")
	end)
	Remotes.OnClient("PropHit", function(prop, downUntil, vel, spoutUntil)
		local ok, err = pcall(onServerHit, prop, downUntil, vel, spoutUntil)
		if not ok then
			warn("[PropClient] " .. tostring(err))
		end
	end)
	-- Props stream in and out with the map: the tag's signals say when.
	CollectionService:GetInstanceAddedSignal(K.Tag):Connect(function(inst)
		safely(onAdded, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(K.Tag):Connect(function(inst)
		safely(forget, inst)
	end)
	for _, inst in ipairs(CollectionService:GetTagged(K.Tag)) do
		safely(onAdded, inst)
	end
	RunService.RenderStepped:Connect(function()
		safely(driveStep)
	end)
	RunService.Heartbeat:Connect(function()
		safely(upkeep)
	end)
end

return PropClient
