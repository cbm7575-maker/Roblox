-- Animations (ModuleScript, ReplicatedStorage.Shared.Config.Animations)
-- The one place for every character animation id, the on-foot feel numbers and the on-foot sounds.
-- Every id below is a Roblox-published locomotion pack, checked loading in Studio on 2026-10-05, and may
-- be played in any experience. Pack names stay in this file only: never show them in the UI.
-- Anything beyond these walk / run / idle sets is made procedurally (LocomotionClient), not as assets.
--   Animations.Sets[name]         { idle, idle2, walk, run, jump, fall, climb, swim, swimidle } numeric ids;
--                                 a set may leave slots out. Sets: Player (what players move with),
--                                 Community, Rthro, Stylish, Elder, Sports, Default (Roblox's own R15).
--   Animations.FallbackOf[name]   the set a missing slot is taken from (default "Default"). A slot that
--                                 no set in the chain has is nil: AnimationService then leaves the
--                                 Animate script's own (stock R15) animation in that slot.
--   Animations.PlayerSet          the set every player character gets (AnimationService)
--   Animations.SideSets           optional set per player attribute "Side" (e.g. Cop = "Sports"); empty =
--                                 everyone uses PlayerSet
--   Animations.Get(set, slot) -> number?        the id, following the fallback chain
--   Animations.Asset(set, slot) -> string?      "rbxassetid://<id>"
--   Animations.Resolve(set) -> { [slot] = "rbxassetid://..." }   cached; do not edit the table you get
--   Animations.Pick(seed?, district?) -> set    a ped's walk set, weighted by district (PedWeights);
--                                 the same seed always gives the same set
--   Animations.PedVariation(seed?) -> { Speed, Height, Width }   per-ped track speed and body scales
--   Animations.DistrictAt(x, z) -> name?        the district at a world spot (a copy of CityGen.Districts)
--   Animations.AnimatePaths       how slots map onto the R15 Animate script's values
--   Animations.Locomotion         LocomotionClient's numbers: speeds (as shares of the base speed: Run is
--                                 only the base they were tuned at, the real base is the character's own
--                                 starting WalkSpeed), the sprint keys (SprintHold / SprintToggle),
--                                 stamina, lean, landings, the hands-on-knees pose (Pose), the one-time
--                                 sprint tip (Tip) and the on-foot camera (Camera)
--   Animations.Sounds             footsteps by floor kind, landing thuds and the out-of-breath loop
--                                 (all ProSoundEffects "(SFX)" assets; found with the asset search on
--                                 2026-10-05). Config/Sounds.lua is SoundClient's; these are played by
--                                 LocomotionClient itself.

local Animations = {}

Animations.Slots = { "idle", "idle2", "walk", "run", "jump", "fall", "climb", "swim", "swimidle" }

Animations.Sets = {
	-- Roblox's own R15 set: the fallback for every other set. Only the three slots that were checked are
	-- listed; the other slots fall through to nil, which keeps the Animate script's stock value (the same
	-- default R15 animation), so nothing is lost.
	Default = { idle = 507766388, walk = 507777826, run = 507767714 },
	-- The most realistic motion-captured set: the player's own, and a common ped walk downtown.
	Community = {
		idle = 122257458498464, idle2 = 102357151005774, walk = 122150855457006, run = 82598234841035,
		jump = 75290611992385, fall = 98600215928904, climb = 88763136693023, swim = 133308483266208,
		swimidle = 109346520324160,
	},
	-- Grounded, a little heavier; a full set (the Player set borrows its climb / swim if Community's go).
	Rthro = {
		idle = 10921258489, idle2 = 10921259953, walk = 10921269718, run = 10921261968, jump = 10921263860,
		fall = 10921262864, climb = 10921257536, swim = 10921264784, swimidle = 10921265698,
	},
	-- A confident street walk (beach and marina crowds).
	Stylish = {
		idle = 10921272275, idle2 = 10921273958, walk = 10921283326, run = 10921276116, jump = 10921279832,
		fall = 10921278648,
	},
	-- A slower, hunched gait for older pedestrians.
	Elder = { idle = 10921101664, walk = 10921111375, run = 10921104374 },
	-- Athletic (joggers; later cops on foot).
	Sports = { idle = 18537376492, walk = 18537392113, run = 18537384940, jump = 18537380791, fall = 18537367238 },
}

-- The player's set: the Community motion capture, with Rthro filling any slot it lacks (if a Community
-- id ever stops loading, delete it above and the Rthro one is used instead).
Animations.Sets.Player = table.clone(Animations.Sets.Community)

Animations.FallbackOf = {
	Player = "Rthro",
	Community = "Default",
	Rthro = "Default",
	Stylish = "Default",
	Elder = "Default",
	Sports = "Default",
}

Animations.PlayerSet = "Player"

-- Optional: a different set by the player attribute "Side" (AnimationService watches it). Left empty on
-- purpose for now; for example Cop = "Sports" makes cops jog athletically, Prisoner = "Default".
Animations.SideSets = {}

-- R15 Animate script: StringValue folder -> its Animation children, in slot order. "idle" holds two
-- (Animation1 = idle, Animation2 = idle2, picked by their Weight values).
Animations.AnimatePaths = {
	{ Folder = "idle", Children = { "Animation1", "Animation2" }, Slots = { "idle", "idle2" } },
	{ Folder = "walk", Children = { "WalkAnim" }, Slots = { "walk" } },
	{ Folder = "run", Children = { "RunAnim" }, Slots = { "run" } },
	{ Folder = "jump", Children = { "JumpAnim" }, Slots = { "jump" } },
	{ Folder = "fall", Children = { "FallAnim" }, Slots = { "fall" } },
	{ Folder = "climb", Children = { "ClimbAnim" }, Slots = { "climb" } },
	{ Folder = "swim", Children = { "Swim" }, Slots = { "swim" } },
	{ Folder = "swimidle", Children = { "SwimIdle" }, Slots = { "swimidle" } },
}
-- Weight of the main idle and of the second (fidget) idle: the fidget plays about 1 time in 10.
Animations.IdleWeights = { 9, 1 }

------------------------------------------------------------------ peds

-- How likely each set is for a pedestrian, by district (CityGen names). Beach and marina crowds stroll
-- (more Stylish and Elder), downtown and the docks walk with purpose (more Community and Rthro).
Animations.PedWeights = {
	Default = { Community = 30, Rthro = 30, Stylish = 15, Elder = 10, Sports = 5, Default = 10 },
	SolanaHeights = { Community = 40, Rthro = 35, Stylish = 10, Elder = 5, Sports = 5, Default = 5 }, -- downtown
	RustwaterDocks = { Community = 35, Rthro = 35, Stylish = 5, Elder = 10, Sports = 5, Default = 10 },
	PalmHills = { Community = 25, Rthro = 25, Stylish = 15, Elder = 15, Sports = 15, Default = 5 }, -- suburbs, joggers
	FlamingoBeach = { Community = 15, Rthro = 15, Stylish = 30, Elder = 25, Sports = 10, Default = 5 },
	LighthouseKey = { Community = 15, Rthro = 15, Stylish = 30, Elder = 25, Sports = 10, Default = 5 },
	MarinaRow = { Community = 20, Rthro = 20, Stylish = 30, Elder = 20, Sports = 5, Default = 5 },
	SaltmarshIsland = { Community = 25, Rthro = 30, Stylish = 5, Elder = 20, Sports = 5, Default = 15 },
	GatorGlades = { Community = 25, Rthro = 30, Stylish = 5, Elder = 20, Sports = 5, Default = 15 },
	GladesSouth = { Community = 25, Rthro = 30, Stylish = 5, Elder = 20, Sports = 5, Default = 15 },
	GladesSouthWest = { Community = 25, Rthro = 30, Stylish = 5, Elder = 20, Sports = 5, Default = 15 },
	GladesSouthEast = { Community = 25, Rthro = 30, Stylish = 5, Elder = 20, Sports = 5, Default = 15 },
}

-- Per-ped variety: track speed and body scales are picked inside these ranges.
Animations.PedRanges = {
	Speed = { 0.9, 1.1 }, -- AnimationTrack:AdjustSpeed
	Height = { 0.92, 1.08 }, -- BodyHeightScale
	Width = { 0.85, 1.2 }, -- BodyWidthScale
}

-- A copy of CityGen.Districts (ServerStorage.Tools.CityGen, server-only) so clients can tell where a ped
-- stands: { name, x0, x1, z0, z1 }, first match wins (same rule as ArtGen). Keep in step with CityGen.
Animations.Districts = {
	{ "GatorGlades", -2000, -900, -2000, 850 },
	{ "GladesSouthWest", -2000, -1900, 850, 2000 },
	{ "GladesSouthEast", -950, -900, 850, 2000 },
	{ "GladesSouth", -1900, -950, 1900, 2000 },
	{ "SaltmarshIsland", -1750, -1100, 1000, 1700 },
	{ "PalmHills", -900, 1000, -2000, -850 },
	{ "SolanaHeights", -900, 1000, -850, 600 },
	{ "RustwaterDocks", -900, 450, 600, 2000 },
	{ "MarinaRow", 450, 1500, 600, 2000 },
	{ "FlamingoBeach", 1000, 1500, -2000, 600 },
	{ "LighthouseKey", 2100, 2450, -1550, -1150 },
}

------------------------------------------------------------------ on-foot feel (LocomotionClient)

Animations.Locomotion = {
	-- Speeds (studs/s), written for a base speed of Run. The REAL base is never this number: it is the
	-- speed the character spawns with (StarterPlayer.CharacterWalkSpeed, 18 in this place), or the player
	-- attribute "MoveBase" while that is set. Every speed below is scaled by base / Run, so the sprint is
	-- always 26 / 16 of the base (about 29 here). Walking is the analog stick part-way (the Humanoid slows
	-- by itself).
	-- Play-test rule: nothing may make the player slower than that base or delay the first step, except
	-- being out of breath. So there is no start ramp and no slow-down after a landing; the push-off and
	-- the landing show in the body (lean, squash), not in the speed.
	Run = 16,
	Sprint = 26,
	ExhaustedSpeed = 12, -- a winded jog while out of breath: slower than a run, but above the 10 studs/s at which a cop may cuff you
	SprintEase = 0.18, -- seconds (time constant) for run <-> sprint changes
	-- Letting go above BrakeMin keeps some momentum: a braking step or two. It sits just over Run on
	-- purpose, so only a sprint carries on and an ordinary run still stops where you let go.
	BrakeMin = 17,
	BrakeTime = { 0.25, 0.45 }, -- braking time at BrakeMin .. at Sprint
	BrakeCurve = 2, -- how sharply the braking speed falls away (1 = evenly, 2 = most of it at once)
	-- Sprint input. Hold keys sprint while they are down; toggle keys (and the touch SPRINT tile) switch it
	-- on until you stop or run out of breath. Gamepad: B is free on foot (it only leaves cars and closes
	-- panels). L3 is TutorialClient's SHOW ME shortcut: once that moves, add ButtonL3 to SprintToggle.
	SprintHold = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB },
	SprintToggle = {},
	-- Shown once per session (a toast) to someone who has run for TipAfter seconds without sprinting.
	Tip = { keyboard = "Hold SHIFT to sprint.", gamepad = "Hold B to sprint.", touch = "Tap SPRINT to run faster." },
	TipAfter = 6,
	-- Stamina (0..100).
	Stamina = 100,
	Drain = 8, -- per second while sprinting
	Refill = 12, -- per second otherwise...
	RefillDelay = 0.4, -- ...starting this long after the sprint ends
	Tired = 25, -- under this the sprint slows and the bar turns orange
	BreathAt = 12, -- under this you can hear yourself breathe (Sounds.Breath)
	TiredSprintShare = 0.35, -- at 0 stamina the sprint only adds this share of its extra speed
	ExhaustTime = 1.5, -- seconds out of breath at 0 (winded jog; hands on knees when you stop) before sprinting is allowed again
	ResprintAt = 10, -- ...and at least this much stamina back
	-- Lean (degrees).
	RollMax = 8, -- into turns
	RollGain = 0.16, -- degrees of roll per (stud/s x rad/s) of speed x turn rate
	PitchJog = 3, -- forward lean at Run
	PitchSprint = 8, -- forward lean at Sprint
	AccelPitch = 3, -- extra forward lean while speeding up, at most
	BrakePitch = 4, -- lean back while braking, at most
	-- Landing (studs of drop from the top of the jump / fall).
	LandLight = 5, -- a little knee dip from here...
	LandSquash = 10, -- ...a full squash and a thud from here...
	LandRagdoll = 28, -- ...a short tumble from here
	SquashTime = 0.25,
	LandDip = 0.25, -- studs the camera dips with a full squash
	RagdollTime = 1.6, -- seconds on the ground after a big fall (RagdollService allows 0.5 to 4)
	-- Procedural poses (degrees, at full strength; applied on top of whatever animation is playing).
	Pose = {
		-- Out of breath: bent over with the hands on the knees.
		Hip = 12, -- the hips tip forward...
		Waist = 34, -- ...and the chest folds over them
		Neck = 16, -- the head lifts a little to look ahead
		Knee = 20, -- knee bend
		Shoulder = 20, -- the arms reach forward to the thighs...
		ShoulderIn = 10, -- ...and in toward the knees
		Elbow = 12,
		Heave = 2.5, -- the chest rises and falls this much...
		HeaveRate = 1.6, -- ...this many times a second
		Slump = 6, -- standing still while short of breath (stamina under Tired): a slight forward slump
		-- Landing squash.
		SquashKnee = 38,
		SquashWaist = 10,
	},
	-- Shift lock (Roblox's own mouse lock) moves off Left Shift, which is sprint here.
	ShiftLockKeys = "LeftControl,RightShift",
	-- Camera (on foot only; DriveController owns the car camera).
	Camera = {
		BaseFov = 70, -- the on-foot field of view when nothing else asks for one
		Shoulder = Vector3.new(1.2, 0, 0), -- over the right shoulder (X right of the view, Y up, Z back)
		ShoulderEase = 8, -- per second
		SprintFov = 6, -- added to the FOV while sprinting (70 -> 76)
		FovEase = 4, -- per second
		BobWalk = 0.03, -- studs of head bob per step at walking pace...
		BobJog = 0.05, -- ...at Run...
		BobSprint = 0.07, -- ...at Sprint
		IdleAfter = 30, -- seconds without any input before the idle camera drifts
		IdleFov = 55,
		IdleYaw = 4, -- degrees per second of slow drift around you
		IdleIn = 2.5, -- seconds (time constant) to settle into the idle camera
		IdleOut = 0.08, -- seconds (time constant) to hand control back (well inside 0.3 s)
		Recenter = true, -- gamepad and touch: swing back behind you while you move...
		RecenterAfter = 1.2, -- ...this long after your last camera input
		RecenterTime = 0.9, -- seconds (time constant)
		RecenterMaxRate = 45, -- degrees per second at most (gentle: the stick is camera-relative, so a fast swing bends a straight run into a circle)
		RecenterMaxAngle = 75, -- only while you head mostly forward: a sidestep or a back-pedal leaves the view alone
	},
}

------------------------------------------------------------------ sounds (LocomotionClient)

-- Footsteps: no plain single human footsteps exist in the ProSoundEffects catalogue, so each floor kind
-- uses the closest short impact, cut to its first Length seconds (Sound.PlaybackRegion) and played
-- quietly at the stepping foot. Ids rotate per step so a run of steps doesn't sound like a machine.
--   Ids       variants (one is picked per step)
--   Volume    at Run (walking is quieter, sprinting a little louder)
--   Pitch     PlaybackSpeed; PitchVar = +- share per step
--   Length    seconds of the asset that are played
--   Muffle    dB cut to the highs (an EqualizerSoundEffect), for soft ground
local STOMPS = { 9114523161, 9114523351, 9114523345, 9114523358, 9114523636, 9114523612, 9114523629 } -- Foot Stomp 1-7 (0.9 s each, a shoe on a hard carpeted floor)
Animations.Sounds = {
	Footsteps = {
		Hard = { Ids = STOMPS, Volume = 0.22, Pitch = 1.12, PitchVar = 0.06, Length = 0.3 }, -- concrete, pavement, asphalt, stone, plastic
		Grass = { Ids = STOMPS, Volume = 0.15, Pitch = 0.9, PitchVar = 0.06, Length = 0.26, Muffle = -14 }, -- grass, ground, mud, fabric (closest: a muffled stomp)
		Sand = { Ids = { 9118768199, 9118768256, 9118768193 }, Volume = 0.16, Pitch = 1.05, PitchVar = 0.1, Length = 0.3 }, -- Sand Impacts 6, 4, 5 (0.8-1.0 s, loose sand hits)
		Wood = { Ids = { 9120882831, 9120882898, 9120882327, 9120882508 }, Volume = 0.1, Pitch = 0.82, PitchVar = 0.06, Length = 0.2 }, -- Wood Hit Boards Hit Wooden Fence 10, 12, 1, 6 (0.8 s each)
		Metal = { Ids = { 9118209193 }, Volume = 0.1, Pitch = 1.05, PitchVar = 0.06, Length = 0.22 }, -- Robot Footsteps 3 (1.7 s, boxy metal steps)
		Water = { Ids = { 9125702987, 9125703168, 9125702419 }, Volume = 0.22, Pitch = 1.1, PitchVar = 0.1, Length = 0.4 }, -- Mud Puddle Splash Shallow Water Impacts Hits 16, 18, 7 (0.8-1.9 s)
	},
	-- Floor material -> footstep kind. Anything not listed is "Hard".
	FloorKind = {
		[Enum.Material.Grass] = "Grass", [Enum.Material.LeafyGrass] = "Grass", [Enum.Material.Ground] = "Grass",
		[Enum.Material.Mud] = "Grass", [Enum.Material.Snow] = "Grass", [Enum.Material.Fabric] = "Grass",
		[Enum.Material.Sand] = "Sand", [Enum.Material.Salt] = "Sand",
		[Enum.Material.Wood] = "Wood", [Enum.Material.WoodPlanks] = "Wood", [Enum.Material.Cardboard] = "Wood",
		[Enum.Material.Metal] = "Metal", [Enum.Material.DiamondPlate] = "Metal", [Enum.Material.CorrodedMetal] = "Metal",
		[Enum.Material.Foil] = "Metal",
		[Enum.Material.Water] = "Water",
	},
	-- Landings: both feet down hard (10+ studs), and the heavy thud of a big fall (28+).
	Land = { Id = 9114523161, Volume = 0.45, Pitch = 0.72, Length = 0.45 }, -- Foot Stomp 1, pitched down
	BigLand = { Id = 9118733086, Volume = 0.6, Pitch = 0.8, Length = 0.8 }, -- Rubber Mat Hits Drops Impacts 9 (1.2 s dull drop)
	-- Out of breath (stamina under Locomotion.BreathAt, or exhausted): a panting loop that fades in and
	-- out, kept UNDER the footsteps and muffled hard (Muffle takes the voice out and leaves breath noise).
	-- The asset is "Gasps Male Deep Breaths Fast Pants Frightened 11" (9.7 s): a voiced, scared-sounding
	-- take, the closest the catalogue search gave. TO DO (owner): listen to it on a phone and swap in a
	-- neutral breathing take if it still sounds scared; Volume = 0 switches it off meanwhile.
	Breath = { Id = 9125573009, Volume = 0.12, Muffle = -12 },
	MinDistance = 12, -- studs: full volume up to here (about where the third-person camera sits)...
	MaxDistance = 45, -- ...and footsteps roll off to nothing by here
}

------------------------------------------------------------------ helpers

local SLOT_SET = {}
for _, slot in ipairs(Animations.Slots) do
	SLOT_SET[slot] = true
end

function Animations.Get(setName, slot)
	if not SLOT_SET[slot] then
		return nil
	end
	local name = setName
	for _ = 1, 8 do -- (a fallback loop in the config can't hang the game)
		local set = Animations.Sets[name]
		local id = set and set[slot]
		if type(id) == "number" and id > 0 then
			return id
		end
		if name == "Default" then
			return nil
		end
		name = Animations.FallbackOf[name] or "Default"
	end
	return nil
end

function Animations.Asset(setName, slot)
	local id = Animations.Get(setName, slot)
	return id and ("rbxassetid://" .. id) or nil
end

local resolved = {}
function Animations.Resolve(setName)
	local name = Animations.Sets[setName] and setName or "Default"
	local r = resolved[name]
	if not r then
		r = {}
		for _, slot in ipairs(Animations.Slots) do
			r[slot] = Animations.Asset(name, slot)
		end
		resolved[name] = r
	end
	return r
end

-- Is this a set name we know?
function Animations.Has(setName)
	return type(setName) == "string" and Animations.Sets[setName] ~= nil
end

local PICK_ORDER = { "Community", "Rthro", "Stylish", "Elder", "Sports", "Default" }

function Animations.Pick(seed, district)
	local weights = Animations.PedWeights[district or ""] or Animations.PedWeights.Default
	local total = 0
	for _, name in ipairs(PICK_ORDER) do
		total += weights[name] or 0
	end
	if total <= 0 then
		return "Default"
	end
	local roll = (seed and Random.new(math.floor(seed) % 2147483647):NextNumber() or math.random()) * total
	for _, name in ipairs(PICK_ORDER) do
		roll -= weights[name] or 0
		if roll < 0 then
			return name
		end
	end
	return "Default"
end

function Animations.PedVariation(seed)
	local rng = seed and Random.new((math.floor(seed) + 7919) % 2147483647) or Random.new()
	local r = Animations.PedRanges
	return {
		Speed = rng:NextNumber(r.Speed[1], r.Speed[2]),
		Height = rng:NextNumber(r.Height[1], r.Height[2]),
		Width = rng:NextNumber(r.Width[1], r.Width[2]),
	}
end

function Animations.DistrictAt(x, z)
	for _, d in ipairs(Animations.Districts) do
		if x >= d[2] and x <= d[3] and z >= d[4] and z <= d[5] then
			return d[1]
		end
	end
	return nil
end

return Animations
