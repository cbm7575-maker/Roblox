-- BigScoreService (ModuleScript, ServerScriptService.Services.BigScoreService)
-- The Big Score: a six-step crew heist (Config.Heists.BigScore), one run at a time per server.
--   * Start: "Start" on RequestBigScore (the phone). The asker must be a Civilian of free-roam rank MinRank
--     or more, not wanted, not on a mission, race or job shift (attributes Mission, RacingId, JobKind) and
--     past their own cooldown; their crew (CrewService) must bring CrewMin Civilians past their cooldowns
--     (Studio: 1). The roster is the asker plus those crewmates, CrewMax at most. "Quit" takes you off it.
--   * Steps (player attribute "BigScore" = the step while on the roster; ReplicatedStorage attribute
--     "BigScoreBusy" = true while a crew runs it):
--       1 Hack the armored van at the Ironclad depot (hold VanHold on its lock): the hacker gets VanHeat
--         stars (the van's reported stolen) and is seated. From then on only the crew sits in it: anyone
--         else is put straight back out, like CarBoostService's hot cars. The driver owns its physics, and
--         a crew member with no stars who takes the wheel gets VanHeat too.
--       2 Drive it to the street outside the Gold Reserve's gate (within StreetRadius of Street).
--       3 Hold both gate consoles (ConsoleHold each). Both must finish within ConsoleSync seconds of each
--         other (Studio, crew of one: StudioSoloSync), else the older one clears and the crew is told
--         ("BigScoreSync"); the same player finishing both doesn't count (bar Studio's crew of one). Done:
--         the gate slides open behind the wall.
--       4 Hold the drill (DrillHold) to start it: the alarm rings (AlarmHeat stars for every crew member
--         within AlarmRange of the vault, Feed "BigScoreAlarm") and the drill turns only while a crew
--         member on foot (and up: not knocked down or tasered) is within DrillRange of it. DrillTime seconds
--         of turning rolls the vault door open.
--       5 Grab a bar from the pile (GrabHold; one at a time, welded to the hand, player attribute
--         CarryingGold; a crew member with no stars who grabs one gets AlarmHeat) and load it at the van's
--         LoadPoint (LoadHold, with the van within LoadRange of the vault door). A bar goes back on the pile
--         if its carrier sits down, is knocked down (KnockedUntil), dies, leaves, stops being a Civilian or
--         wanders CarryLeash studs off.
--       6 Starts by itself once the van is LeaveRadius studs from the reserve with gold in it (or all of it
--         is loaded): drive it into the Hideout pad (HideoutService.IsInside) while no cop can see the
--         driver ("BigScoreLoseCops" every few seconds until then).
--   * Pass: pot = bars x BarValue x (1 + MemberBonus per member beyond 2) x NightBonus after dark, split
--     evenly between the roster members still in the server (a VIP's own cut +25%). Banked Cash (it's
--     safe), Heist XP of tier XPTier, +1 BigHeists (once their save has loaded), heat cleared for members
--     inside the pad, Feed "BigScoreDone", then Cooldown each and the van goes after a few seconds.
--   * Fail: the time limit, the van lost (destroyed, removed, sunk), nobody left on the roster who is in
--     the server and a Civilian (arrested members stay on the roster and still get a cut of a pass; one
--     who joins the police is taken off it), or, before the gate opens, fewer than two roster members left
--     in the server (one can't hold both consoles; not Studio's crew of one). FailCooldown for the roster.
--   * Every hold is timed here (PromptButtonHoldBegan -> Triggered, like CarBoostService's pick-lock):
--     crew only ("BigScoreNotYours"), Civilian, alive, up (not knocked down or tasered), on foot
--     ("GetOutFirst"), in reach. The world's prompts are switched on only during their own step.
--   * Remotes: BigScoreEvent (server -> each roster member): "State" (on every change, and every second
--     while the drill runs; a member carrying a bar gets the van as their Target), "Loaded", "Done",
--     "Failed". Feed "BigScoreStarted" / "BigScoreAlarm" / "BigScoreDone". Notify BigScore* keys, plus
--     MissionBusy and GetOutFirst. Player attribute BigScoreReadyAt = the server time of their next start
--     (kept by UserId and in their save as data.bigScoreReadyAt, so rejoining this server or another
--     doesn't skip it).
--   * World: built at Init in Workspace.BigScore (models IroncladDepot, GoldReserve), everything anchored;
--     the reserve's two cameras are eyes (HeatService.RegisterEye); the depot's two are dressing (an eye
--     sees all round for 250 studs, and the Hideout pad is next door). The van is a CarBuilder "ArmoredVan"
--     in Workspace.Vehicles (attribute BigScoreVan), built at the start of each run. After a run the gold
--     goes back at once, but the gate and the vault only close once nobody is inside the reserve (they'd be
--     shut in; anyone who slips in while the gate slides shut opens it again). A close still waiting when
--     the next crew is through the gate gives up (that run opens both anyway).
--   * Studio: BigScoreService.Debug(player, what) skips ahead: "start" (this player alone, no crew, rank or
--     cooldown checks), "van", "gate", "drill", "load" (4 bars), "deliver", "reset". Each one runs the
--     steps before it first. Through DebugService: ["call","BigScoreService","Debug","$me","van"].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)
local HeatService = require(ServerScriptService.Services.HeatService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local BigScoreService = {}

local CFG = Heists.BigScore

-- Constants (one table keeps this file far from Luau's 200-locals limit).
local K = {
	TICK = 0.25, -- seconds between checks of the run
	HOLD_SLACK = 0.4, -- a hold may reach us this much short of its length (network jitter)
	HOLD_KEEP = 3, -- seconds past its length a finished hold still counts (then it's stale)
	REACH_SLACK = 6, -- studs past a prompt's reach the holder may stand (lag)
	END_DELAY = 5, -- seconds the van stays after a run
	LOSE_COPS_GAP = 4, -- seconds between two "lose the cops first" toasts at the Hideout
	SUNK_Y = 0.2, -- a van chassis below this sank or fell out of the world (as CarBoostService judges it)
	FLOOR_Y = -0.04, -- centre of 0.2-thick paving: its top sits at 0.06 (as Art.HeistFronts lays it)
	VAULT_R = 8, -- the round vault door's radius (it covers the 10 x 12 doorway's corners)
	VAULT_ROLL = 17, -- studs the door rolls north along the facade to open
	GATE_SLIDE = 21, -- studs the gate slides north behind the wall to open
	BAR_SIZE = Vector3.new(1.6, 0.5, 0.8),
	-- The building inside the reserve's wall: { x1, x2, z1, z2, height }; the vault room inside it, its
	-- east wall (with the doorway) and the doorway's size.
	BUILDING = { 160, 262, -1614, -1542, 22 },
	VAULT_ROOM = { 232, 260, -1596, -1560, 14 }, -- inside: x1, x2, z1, z2, ceiling
	DOOR_W = 10,
	DOOR_H = 12,
	-- What each step says (Text / Hint on the client; Name = TargetName).
	STEPS = {
		{ Text = "Hack the armored van", Name = "Ironclad depot",
			Hint = "It's parked in the Ironclad depot at the port. Hold its lock to hack it." },
		{ Text = "Drive the van to the Gold Reserve", Name = "Gold Reserve",
			Hint = "The van's been reported stolen! Get it to the reserve's gate, north of downtown." },
		{ Text = "Hold both gate consoles at once", Name = "Gate consoles",
			Hint = "One of you on each console: both must finish within %d seconds of each other." },
		{ Text = "Drill the vault", Name = "Vault drill",
			Hint = "Start the drill. It only turns while one of you stands next to it.",
			Running = "Alarm! Keep someone next to the drill until the vault opens.",
			Stopped = "The drill stopped: stand next to it to keep it turning!" },
		{ Text = "Load the gold into the van (%d/%d)", Name = "Gold pile",
			Hint = "Carry the bars out to the van. Leave whenever you like: the Hideout pays for every bar loaded." },
		{ Text = "Get the van to the Hideout", Name = "Hideout",
			Hint = "Lose the cops before you pull in. Everyone on the crew gets a cut." },
	},
	-- Colours (ArtKit / Look 3.0 neighbours)
	ASPHALT = Color3.fromRGB(58, 58, 66),
	CONCRETE = Color3.fromRGB(196, 190, 186),
	STONE = Color3.fromRGB(214, 206, 190),
	STONE_LIGHT = Color3.fromRGB(232, 226, 214),
	STONE_DARK = Color3.fromRGB(176, 168, 154),
	GRANITE = Color3.fromRGB(96, 92, 90),
	STEEL = Color3.fromRGB(120, 128, 140),
	MESH = Color3.fromRGB(150, 156, 164),
	DARK = Color3.fromRGB(40, 42, 48),
	BOARD = Color3.fromRGB(26, 28, 32),
	VAULT_STEEL = Color3.fromRGB(150, 156, 166),
	GLASS = Color3.fromRGB(40, 56, 84),
	WOOD = Color3.fromRGB(150, 110, 70),
	PAINT = Color3.fromRGB(232, 232, 226),
	WHITE = Color3.fromRGB(245, 245, 240),
	YELLOW = Color3.fromRGB(255, 214, 10),
	GOLD = Color3.fromRGB(255, 196, 60),
	RED = Color3.fromRGB(255, 60, 60),
	AMBER = Color3.fromRGB(255, 176, 50),
	GREEN = Color3.fromRGB(110, 242, 196),
	ALARM_OFF = Color3.fromRGB(90, 34, 36),
	LAMP = Color3.fromRGB(255, 236, 200),
}

-- The run (one at a time). carry: [player] = { bar = the Part in their hand, slot = its pile index }.
local S = {
	active = false,
	step = 0,
	roster = {}, -- Players
	van = nil,
	vanPrompts = {}, -- hack, drive, ride, load
	endsAt = 0,
	consoleA = nil, -- server time each console was finished (step 3)
	consoleB = nil,
	consoleBy = {}, -- [key] = the player who finished that console (one player can't do both)
	drill = 0, -- 0..1
	drillStarted = false,
	drilling = false, -- turning right now (somebody next to it)
	drillPushAt = 0, -- os.clock() of the last State while drilling
	alarmUntil = nil,
	bars = 0, -- loaded into the van
	carry = {},
	hideout = nil, -- step 6: the Hideout pad
	targetAt = nil, -- step 1: where the van was in the last State
	loseCopsAt = {}, -- [player] = os.clock() of their last "lose the cops" toast
	readyAt = {}, -- [userId] = server time they may start / join again
}

-- The world (Init builds it): the parts and prompts the run changes, and where things go.
local W = {
	ready = false,
	eyes = {},
	alarmLights = {},
	console = {}, -- [key] = pedestal part
	consolePrompt = {},
	consoleScreen = {},
	pileBars = {},
	vaultParts = {}, -- { part, offset from the door's shut CFrame }
	vaultAt = 0, -- studs the door has rolled
	vaultToken = 0,
	vaultIsOpen = false,
	gateIsOpen = false,
	resetPending = false,
	closingUntil = nil, -- os.clock() the gate's slide shut ends (tick re-opens it if somebody slips in)
	depotY = 0,
	reserveY = 0,
}

local R = {} -- remotes: event (BigScoreEvent), feed, notify

local function now()
	return Workspace:GetServerTimeNow()
end

-- Services whose own requires reach far (required when used, not at load).
local function svc(name)
	return require(ServerScriptService.Services[name])
end

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A living character's humanoid and root part, or nil.
local function body(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then
		return nil
	end
	return hum, root
end

-- Knocked down or tasered at server time t (as VehicleService's isDown judges it)?
local function down(p, t)
	return (p:GetAttribute("KnockedUntil") or 0) > t or (p:GetAttribute("StunnedUntil") or 0) > t
end

------------------------------------------------------------------ the world

local function part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- Dressing: nothing collides with it, rays and touches pass through it, and it casts no shadow
-- unless `props` says so.
local function deco(parent, name, size, cf, color, material, props)
	local all = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	for k, v in pairs(props or {}) do
		all[k] = v
	end
	return part(parent, name, size, cf, color, material, all)
end

-- Oswald letters on one face of a part, lit the same by day and night. top / height: the band of the face
-- (0-1) the text fills.
local function label(board, face, text, color, top, height)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label" .. face.Name
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local words = Instance.new("TextLabel")
	words.Size = UDim2.fromScale(0.92, height or 0.8)
	words.Position = UDim2.fromScale(0.04, top or 0.1)
	words.BackgroundTransparency = 1
	words.Font = Enum.Font.Oswald
	words.TextScaled = true
	words.TextColor3 = color
	words.Text = text
	words.Parent = gui
	gui.Parent = board
	return gui
end

-- A prompt, switched off until its step (refreshPrompts).
local function newPrompt(parent, name, action, object, hold, range)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold
	pp.MaxActivationDistance = range
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.Enabled = false
	pp.Parent = parent
	return pp
end

-- The ground's height under (x, z): what a short ray down from 6 studs meets, if that's near 0 (a roof or
-- a sign above the spot doesn't count; both sites are on flat ground at 0).
local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local skip = {}
	for _, name in ipairs({ "Vehicles", "BigScore" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(skip, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	local hit = Workspace:Raycast(Vector3.new(x, 6, z), Vector3.new(0, -12, 0), params)
	if hit and math.abs(hit.Position.Y) <= 3 then
		return hit.Position.Y
	end
	return 0
end

-- A security camera at `pos` looking toward `look`. pole: stands on its own steel pole; else it hangs off a
-- wall bracket behind it. watches: a HeatService eye too (Init registers it). An eye sees all round, for
-- 250 studs, whichever way the camera points, so a camera near a place where the wanted must not be seen
-- (the Hideout) is dressing only.
local function camera(parent, pos, look, pole, groundAt, watches)
	if pole then
		part(parent, "CameraPole", Vector3.new(0.5, pos.Y - groundAt - 0.4, 0.5),
			CFrame.new(pos.X, (pos.Y - 0.4 + groundAt) / 2, pos.Z), K.STEEL, Enum.Material.Metal)
	end
	local cf = CFrame.lookAt(pos, Vector3.new(look.X, pos.Y - 4, look.Z))
	local eye = part(parent, "CameraEye", Vector3.new(0.9, 0.9, 1.8), cf, K.DARK, Enum.Material.Metal, { CanCollide = false })
	deco(eye, "Lens", Vector3.new(0.5, 0.5, 0.1), cf * CFrame.new(0, 0, -0.95), K.RED, Enum.Material.Neon)
	if not pole then
		deco(eye, "Bracket", Vector3.new(0.3, 0.3, 1.6), cf * CFrame.new(0, 0, 1.4), K.STEEL, Enum.Material.Metal)
	end
	if watches then
		table.insert(W.eyes, eye)
	end
	return eye
end

-- The Ironclad depot: an asphalt lot inside a low steel fence (open gate on the south side), a garage with
-- roll-up doors along the back, a guard booth, the sign and two cameras. The van parks in the yellow bay.
local function buildDepot(folder)
	local m = Instance.new("Model")
	m.Name = "IroncladDepot"
	-- Built at its design spot (Config.Heists BigScore.Design), then moved to the real one (DepotCF).
	local D = CFG.Design
	local r = D.DepotRect
	local x1, x2, z1, z2 = r[1], r[2], r[3], r[4]
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local real = (CFG.DepotCF * CFrame.new(cx, 0, cz)).Position
	local g = groundY(real.X, real.Z)
	W.depotY = g
	local gate = D.DepotGateX
	m.PrimaryPart = part(m, "Lot", Vector3.new(x2 - x1, 0.2, z2 - z1), CFrame.new(cx, g + K.FLOOR_Y, cz), K.ASPHALT,
		Enum.Material.Asphalt, { CastShadow = false })
	-- Bays: the van's boxed in yellow, plain white lines either side.
	local v = D.VanSpot
	local top = g + 0.08
	for _, dx in ipairs({ -6, 6 }) do
		deco(m, "BayLine", Vector3.new(0.4, 0.05, 20), CFrame.new(v.X + dx, top, v.Z), K.YELLOW)
	end
	for _, dz in ipairs({ -10, 10 }) do
		deco(m, "BayLine", Vector3.new(12.4, 0.05, 0.4), CFrame.new(v.X, top, v.Z + dz), K.YELLOW)
	end
	for _, dx in ipairs({ -42, -24, 24, 42 }) do
		deco(m, "BayLine", Vector3.new(0.4, 0.05, 20), CFrame.new(v.X + dx, top, v.Z), K.PAINT)
	end
	-- Garage along the back fence: three roll-up doors facing the lot. Low and short of the corners, so the
	-- corner cameras see over it into the lot.
	part(m, "Garage", Vector3.new(94, 10, 14), CFrame.new(v.X, g + 5, z1 + 9), K.CONCRETE, Enum.Material.Concrete)
	part(m, "GarageRoof", Vector3.new(96, 0.8, 16), CFrame.new(v.X, g + 10.4, z1 + 9.5), K.DARK, Enum.Material.Metal)
	for _, dx in ipairs({ -30, 0, 30 }) do
		local door = deco(m, "RollUpDoor", Vector3.new(14, 8, 0.3), CFrame.new(v.X + dx, g + 4, z1 + 16.1), K.STEEL,
			Enum.Material.Metal)
		local tex = Instance.new("Texture")
		tex.Texture = Textures.RollUpDoor
		tex.Face = Enum.NormalId.Back
		tex.StudsPerTileU = 14
		tex.StudsPerTileV = 8
		tex.Parent = door
	end
	-- Low fence: concrete plinth, steel posts about every 12 studs, a see-through steel mesh, a top rail.
	local runs = { { x1, z1, x2, z1 }, { x1, z1, x1, z2 }, { x2, z1, x2, z2 }, { x1, z2, gate[1], z2 }, { gate[2], z2, x2, z2 } }
	for _, run in ipairs(runs) do
		local ax, az, bx, bz = run[1], run[2], run[3], run[4]
		local alongX = math.abs(bx - ax) > math.abs(bz - az)
		local len = math.abs(alongX and bx - ax or bz - az)
		local mx, mz = (ax + bx) / 2, (az + bz) / 2
		local function rail(name, h, y, thick, color, material, props)
			local size = alongX and Vector3.new(len, h, thick) or Vector3.new(thick, h, len)
			return part(m, name, size, CFrame.new(mx, g + y, mz), color, material, props)
		end
		rail("FencePlinth", 1.2, 0.6, 0.8, K.CONCRETE, Enum.Material.Concrete)
		rail("FenceMesh", 6.8, 4.6, 0.2, K.MESH, Enum.Material.Metal, { Transparency = 0.55, CastShadow = false })
		rail("FenceRail", 0.35, 8, 0.35, K.STEEL, Enum.Material.Metal)
		local n = math.max(1, math.floor(len / 12 + 0.5))
		for i = 0, n do
			local a = i / n
			part(m, "FencePost", Vector3.new(0.5, 8.2, 0.5), CFrame.new(ax + (bx - ax) * a, g + 4.1, az + (bz - az) * a),
				K.STEEL, Enum.Material.Metal)
		end
	end
	-- Guard booth by the gate: concrete base, a glass band, a flat roof.
	local bx, bz = 550, 100
	part(m, "Booth", Vector3.new(8, 3.5, 8), CFrame.new(bx, g + 1.75, bz), K.CONCRETE, Enum.Material.Concrete)
	part(m, "BoothGlass", Vector3.new(7.6, 3.6, 7.6), CFrame.new(bx, g + 5.3, bz), K.GLASS, Enum.Material.Glass,
		{ Transparency = 0.35 })
	part(m, "BoothRoof", Vector3.new(9.4, 0.8, 9.4), CFrame.new(bx, g + 7.5, bz), K.DARK, Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			deco(m, "BoothPost", Vector3.new(0.5, 3.6, 0.5), CFrame.new(bx + sx * 3.8, g + 5.3, bz + sz * 3.8), K.DARK,
				Enum.Material.Metal)
		end
	end
	-- The sign, inside the fence west of the gate (it stands taller than the fence, facing the street).
	local sx, sz = gate[1] - 14, z2 - 3
	for _, dx in ipairs({ -10, 10 }) do
		part(m, "SignPost", Vector3.new(0.6, 13, 0.6), CFrame.new(sx + dx, g + 6.5, sz), K.STEEL, Enum.Material.Metal)
	end
	local board = part(m, "Sign", Vector3.new(24, 5, 0.5), CFrame.new(sx, g + 10.5, sz), K.BOARD, Enum.Material.Metal)
	label(board, Enum.NormalId.Back, "IRONCLAD ARMORED", K.WHITE)
	label(board, Enum.NormalId.Front, "IRONCLAD ARMORED", K.WHITE)
	-- Yellow bollards at the gate's edges.
	for _, x in ipairs(gate) do
		part(m, "Bollard", Vector3.new(3, 0.9, 0.9), CFrame.new(x, g + 1.5, z2 - 1.5) * CFrame.Angles(0, 0, math.rad(90)),
			K.YELLOW, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
	-- Cameras on poles in the back corners: dressing, not eyes (the Hideout pad is just past the back fence,
	-- and an eye there would keep everyone on it "seen", so nobody could bank).
	for _, x in ipairs({ x1 + 4, x2 - 4 }) do
		camera(m, Vector3.new(x, g + 12, z1 + 4), Vector3.new(cx, g, cz), true, g, false)
	end
	m:PivotTo(CFG.DepotCF * m:GetPivot())
	m.Parent = folder
end

-- The Solana Gold Reserve: a walled compound with a sliding gate (east), two gate consoles on the
-- sidewalk outside it, a concrete driveway to the van bay, and the reserve building with the vault room,
-- its round door, the drill rig and the gold pile.
local function buildReserve(folder)
	local m = Instance.new("Model")
	m.Name = "GoldReserve"
	-- Built at its design spot (Config.Heists BigScore.Design: gate on the east), then turned and moved to
	-- the real one (ReserveCF) at the end, with the CFrames the gate and the vault door move between.
	local D = CFG.Design
	local r = D.ReserveRect
	local x1, x2, z1, z2 = r[1], r[2], r[3], r[4]
	local c = D.ReserveCenter
	local g = groundY(CFG.ReserveCenter.X, CFG.ReserveCenter.Z)
	W.reserveY = g
	local gz = D.ReserveGateZ
	local gateZ = (gz[1] + gz[2]) / 2
	local function block(name, ax, bx, ay, by, az, bz, color, material, props)
		return part(m, name, Vector3.new(bx - ax, by - ay, bz - az), CFrame.new((ax + bx) / 2, g + (ay + by) / 2, (az + bz) / 2),
			color, material, props)
	end
	-- Perimeter wall: concrete, 9 tall, a cap and pillars; the gate gap is on the east side.
	local runs = { { x1, z1, x2, z1 }, { x1, z2, x2, z2 }, { x1, z1, x1, z2 }, { x2, z1, x2, gz[1] }, { x2, gz[2], x2, z2 } }
	for _, run in ipairs(runs) do
		local ax, az, bx, bz = run[1], run[2], run[3], run[4]
		local alongX = math.abs(bx - ax) > math.abs(bz - az)
		local len = math.abs(alongX and bx - ax or bz - az) + 1 -- +1 closes the corners
		local mid = CFrame.new((ax + bx) / 2, g + 4.5, (az + bz) / 2)
		part(m, "Wall", alongX and Vector3.new(len, 9, 1) or Vector3.new(1, 9, len), mid, K.STONE, Enum.Material.Concrete)
		deco(m, "WallCap", alongX and Vector3.new(len + 0.4, 0.5, 1.5) or Vector3.new(1.5, 0.5, len + 0.4),
			mid * CFrame.new(0, 4.75, 0), K.STONE_LIGHT, Enum.Material.Concrete)
		local n = math.max(1, math.floor(len / 24 + 0.5))
		for i = 0, n do
			local a = i / n
			deco(m, "WallPillar", Vector3.new(1.8, 9.6, 1.8), CFrame.new(ax + (bx - ax) * a, g + 4.8, az + (bz - az) * a),
				K.STONE_DARK, Enum.Material.Concrete)
		end
	end
	for _, z in ipairs(gz) do
		part(m, "GatePillar", Vector3.new(2, 10.5, 2), CFrame.new(x2, g + 5.25, z), K.STONE_DARK, Enum.Material.Concrete)
	end
	W.gateLight = deco(m, "GateLight", Vector3.new(1, 0.6, 1), CFrame.new(x2, g + 10.8, gz[1]), K.RED, Enum.Material.Neon)
	-- The gate: a steel panel just inside the wall line; it blocks the van until it slides north behind
	-- the wall (setGate).
	W.gateShutCF = CFrame.new(x2 - 1.6, g + 4.5, gateZ)
	W.gateOpenCF = W.gateShutCF * CFrame.new(0, 0, -K.GATE_SLIDE)
	W.gate = part(m, "Gate", Vector3.new(0.8, 9, 20.5), W.gateShutCF, K.STEEL, Enum.Material.DiamondPlate)
	label(W.gate, Enum.NormalId.Right, "AUTHORIZED VEHICLES ONLY", K.YELLOW, 0.36, 0.28)
	deco(m, "GateTrack", Vector3.new(0.5, 0.12, 44), CFrame.new(x2 - 1.6, g + 0.08, gateZ - 11), K.DARK, Enum.Material.Metal)
	-- Driveway: from the street, through the gate, to the vault.
	local fx = D.VaultDoorPos.X -- the building's east facade
	local driveEnd = x2 + 12
	part(m, "Driveway", Vector3.new(driveEnd - fx, 0.2, 24), CFrame.new((fx + driveEnd) / 2, g + K.FLOOR_Y, gateZ), K.CONCRETE,
		Enum.Material.Concrete, { CastShadow = false })
	m.PrimaryPart = m:FindFirstChild("Driveway")
	-- The van bay (GPS target for parking): an invisible marker over yellow lines.
	local bay = D.VanBayPos
	W.vanBay = part(m, "VanBay", Vector3.new(12, 0.2, 20), CFrame.new(bay.X, g + 0.1, bay.Z), K.YELLOW, Enum.Material.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	for _, dx in ipairs({ -6, 6 }) do
		deco(m, "BayLine", Vector3.new(0.4, 0.05, 20), CFrame.new(bay.X + dx, g + 0.08, bay.Z), K.YELLOW)
	end
	for _, dz in ipairs({ -10, 10 }) do
		deco(m, "BayLine", Vector3.new(12.4, 0.05, 0.4), CFrame.new(bay.X, g + 0.08, bay.Z + dz), K.YELLOW)
	end
	-- Gate consoles on the sidewalk, screens toward the street: red = locked, amber = this one's done,
	-- green = the gate is open (refreshPrompts).
	for _, key in ipairs({ "A", "B" }) do
		local pos = D["Console" .. key .. "Pos"]
		local box = part(m, "Console" .. key, Vector3.new(1.6, 3.4, 2.2), CFrame.new(pos.X, g + 1.7, pos.Z), K.DARK, Enum.Material.Metal,
			{ CanCollide = false })
		W.consoleScreen[key] = deco(box, "Screen", Vector3.new(0.2, 1.3, 1.8), CFrame.new(pos.X + 0.85, g + 2.6, pos.Z), K.RED,
			Enum.Material.Neon)
		label(box, Enum.NormalId.Right, "GATE " .. key, K.WHITE, 0.62, 0.22)
		W.console[key] = box
		W.consolePrompt[key] = newPrompt(box, "ConsolePrompt", "Override gate", "Gate console " .. key, CFG.ConsoleHold, 8)
	end
	-- The building: solid wings around the vault room, the vault's east wall with the doorway.
	local b, v = K.BUILDING, K.VAULT_ROOM
	local h = b[5]
	local dz1, dz2 = c.Z - K.DOOR_W / 2, c.Z + K.DOOR_W / 2
	block("Wing", b[1], v[1], 0, h, b[3], b[4], K.STONE, Enum.Material.Concrete)
	block("Wing", v[1], fx, 0, h, b[3], v[3], K.STONE, Enum.Material.Concrete)
	block("Wing", v[1], fx, 0, h, v[4], b[4], K.STONE, Enum.Material.Concrete)
	block("VaultWall", v[2], fx, 0, h, v[3], dz1, K.STONE, Enum.Material.Concrete)
	block("VaultWall", v[2], fx, 0, h, dz2, v[4], K.STONE, Enum.Material.Concrete)
	block("VaultWall", v[2], fx, K.DOOR_H, h, dz1, dz2, K.STONE, Enum.Material.Concrete)
	block("VaultRoof", v[1], v[2], v[5], h, v[3], v[4], K.STONE, Enum.Material.Concrete)
	block("VaultFloor", v[1], fx, -0.14, 0.06, v[3], v[4], K.STEEL, Enum.Material.DiamondPlate)
	-- Inside the vault: steel-plate walls and ceiling, the doorway lined in dark steel, two lamps.
	local vcx, vcz = (v[1] + v[2]) / 2, (v[3] + v[4]) / 2
	local vw, vd, vh = v[2] - v[1], v[4] - v[3], v[5]
	local linings = { -- { size, centre }: north wall, south wall, west wall, ceiling
		{ Vector3.new(vw, vh, 0.2), Vector3.new(vcx, vh / 2, v[3] + 0.1) },
		{ Vector3.new(vw, vh, 0.2), Vector3.new(vcx, vh / 2, v[4] - 0.1) },
		{ Vector3.new(0.2, vh, vd), Vector3.new(v[1] + 0.1, vh / 2, vcz) },
		{ Vector3.new(vw, 0.2, vd), Vector3.new(vcx, vh - 0.1, vcz) },
	}
	for _, l in ipairs(linings) do
		deco(m, "VaultLining", l[1], CFrame.new(l[2].X, g + l[2].Y, l[2].Z), K.STEEL, Enum.Material.DiamondPlate)
	end
	local jambX, jambW = (v[2] + fx) / 2, fx - v[2]
	for _, z in ipairs({ dz1 + 0.15, dz2 - 0.15 }) do
		deco(m, "DoorLining", Vector3.new(jambW, K.DOOR_H, 0.3), CFrame.new(jambX, g + K.DOOR_H / 2, z), K.DARK, Enum.Material.Metal)
	end
	deco(m, "DoorLining", Vector3.new(jambW, 0.3, K.DOOR_W), CFrame.new(jambX, g + K.DOOR_H - 0.15, c.Z), K.DARK, Enum.Material.Metal)
	for _, dz in ipairs({ -9, 9 }) do
		local lamp = deco(m, "VaultLamp", Vector3.new(3, 0.3, 3), CFrame.new(vcx, g + vh - 0.35, vcz + dz), K.LAMP, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 0.4 -- (Realistic lighting: stronger whites the vault and its door out)
		light.Color = K.LAMP
		light.Parent = lamp
	end
	-- Facade: a granite base (either side of the door), a cornice, the name board, two alarm lights and
	-- two cameras on the corners.
	deco(m, "Base", Vector3.new(0.4, 2, dz1 - b[3]), CFrame.new(fx + 0.2, g + 1, (b[3] + dz1) / 2), K.GRANITE, Enum.Material.Granite)
	deco(m, "Base", Vector3.new(0.4, 2, b[4] - dz2), CFrame.new(fx + 0.2, g + 1, (dz2 + b[4]) / 2), K.GRANITE, Enum.Material.Granite)
	deco(m, "Cornice", Vector3.new(1.2, 1.4, b[4] - b[3] + 1.2), CFrame.new(fx + 0.6, g + h - 0.7, (b[3] + b[4]) / 2), K.STONE_LIGHT,
		Enum.Material.Concrete)
	local board = part(m, "NameBoard", Vector3.new(0.6, 4, 44), CFrame.new(fx + 0.3, g + 17.5, c.Z), K.BOARD, Enum.Material.Metal)
	label(board, Enum.NormalId.Right, "SOLANA GOLD RESERVE", K.GOLD)
	for _, dz in ipairs({ -24, 24 }) do
		table.insert(W.alarmLights, deco(m, "AlarmLight", Vector3.new(0.8, 1.4, 1.4), CFrame.new(fx + 0.5, g + 17.5, c.Z + dz),
			K.ALARM_OFF, Enum.Material.Metal))
	end
	for _, z in ipairs({ b[3] + 1, b[4] - 1 }) do
		camera(m, Vector3.new(fx + 1.6, g + 16, z), Vector3.new(x2, g, gateZ), false, g, true)
	end
	-- The round vault door, standing on the facade over the doorway (its lower rim sits below the
	-- paving). It rolls north along the wall to open (setVault); the ring, hub, spokes and bolts ride along.
	W.vaultShut = CFrame.new(fx + 1.0, g + K.DOOR_H / 2, c.Z)
	local door = part(m, "VaultDoor", Vector3.new(1.6, K.VAULT_R * 2, K.VAULT_R * 2), W.vaultShut, K.VAULT_STEEL, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder, Reflectance = 0.05 })
	table.insert(W.vaultParts, { door, CFrame.new() })
	local function rider(name, size, offset, color, props)
		table.insert(W.vaultParts, { deco(m, name, size, W.vaultShut * offset, color, Enum.Material.Metal, props), offset })
	end
	rider("VaultRing", Vector3.new(0.3, 13, 13), CFrame.new(0.9, 0, 0), K.STEEL, { Shape = Enum.PartType.Cylinder })
	rider("VaultHub", Vector3.new(0.9, 2.6, 2.6), CFrame.new(1.4, 0, 0), K.VAULT_STEEL, { Shape = Enum.PartType.Cylinder })
	for i = 0, 2 do
		rider("VaultSpoke", Vector3.new(0.4, 0.5, 7), CFrame.new(1.5, 0, 0) * CFrame.Angles(math.rad(60 * i), 0, 0), K.VAULT_STEEL)
	end
	for i = 0, 7 do
		local a = math.rad(45 * i + 22.5)
		rider("VaultBolt", Vector3.new(0.5, 0.9, 0.9), CFrame.new(1.0, math.cos(a) * 7.1, math.sin(a) * 7.1), K.GOLD,
			{ Shape = Enum.PartType.Cylinder })
	end
	-- The drill rig, aimed at the door (none of it collides: it stands in the doorway's path).
	local d = D.DrillPos
	deco(m, "DrillBase", Vector3.new(3, 0.3, 3), CFrame.new(d.X + 0.5, g + 0.15, d.Z), K.DARK, Enum.Material.Metal)
	deco(m, "DrillStand", Vector3.new(0.8, 3.6, 0.8), CFrame.new(d.X + 0.5, g + 2.1, d.Z), K.DARK, Enum.Material.Metal)
	W.drill = part(m, "Drill", Vector3.new(3, 1.4, 1.4), CFrame.new(d.X, g + 4.4, d.Z), K.YELLOW, Enum.Material.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false })
	local bitX = d.X - 2.3
	local bit = deco(m, "DrillBit", Vector3.new(1.8, 0.4, 0.4), CFrame.new(bitX, g + 4.4, d.Z), K.STEEL, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder })
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(fx + 2.1 - bitX, 0, 0) -- on the door's face (its ring), where the bit bites
	tip.Parent = bit
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(K.GOLD, K.AMBER)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.18, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Rate = 40
	sparks.EmissionDirection = Enum.NormalId.Right
	sparks.Enabled = false
	sparks.Parent = tip
	W.sparks = sparks
	W.drillPrompt = newPrompt(W.drill, "DrillPrompt", "Drill the vault", "Vault drill", CFG.DrillHold, 10)
	-- The gold: bars stacked on a pallet in the vault, bottom layer first (a grab takes the top one).
	local gp = D.GoldPilePos
	W.pile = part(m, "GoldPile", Vector3.new(6, 0.5, 4), CFrame.new(gp.X, g + 0.31, gp.Z), K.WOOD, Enum.Material.WoodPlanks)
	local layer = 0
	while #W.pileBars < CFG.Bars do
		local cols = math.max(1, 3 - layer)
		for col = 1, cols do
			for row = 1, 2 do
				if #W.pileBars < CFG.Bars then
					local x = (col - (cols + 1) / 2) * 1.7
					local z = (row - 1.5) * 0.9
					local bar = deco(W.pile, "Bar" .. (#W.pileBars + 1), K.BAR_SIZE,
						CFrame.new(gp.X + x, g + 0.81 + layer * 0.5, gp.Z + z), K.GOLD, Enum.Material.Metal,
						{ Reflectance = 0.2, CastShadow = true })
					table.insert(W.pileBars, bar)
				end
			end
		end
		layer += 1
	end
	local glint = Instance.new("PointLight")
	glint.Color = K.GOLD
	glint.Range = 10
	glint.Brightness = 0.8
	glint.Parent = W.pile
	W.grabPrompt = newPrompt(W.pile, "GrabPrompt", "Grab gold bar", "Gold", CFG.GrabHold, 10)
	local move = CFG.ReserveCF
	m:PivotTo(move * m:GetPivot())
	W.gateShutCF, W.gateOpenCF = move * W.gateShutCF, move * W.gateOpenCF
	W.vaultShut = move * W.vaultShut
	m.Parent = folder
end

local function buildWorld()
	local old = Workspace:FindFirstChild("BigScore")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "BigScore"
	buildDepot(folder)
	buildReserve(folder)
	folder.Parent = Workspace
end

------------------------------------------------------------------ the roster and what it's told

-- A toast at most every 3 s (GetOutFirst shares its limit with the other services' "get out" toasts).
local function toast(p, key)
	local bucket = key == "GetOutFirst" and "GetOutFirstToast" or "BigScoreToast"
	if RateLimit.Allow(p, bucket, 1 / 3, 1) then
		R.notify:FireClient(p, key)
	end
end

local function onRoster(p)
	return S.active and table.find(S.roster, p) ~= nil
end

-- Every roster member still in the server.
local function members()
	local list = {}
	for _, p in ipairs(S.roster) do
		if p.Parent == Players then
			table.insert(list, p)
		end
	end
	return list
end

local function tell(kind, info)
	for _, p in ipairs(members()) do
		R.event:FireClient(p, kind, info)
	end
end

local function tellNotify(key)
	for _, p in ipairs(members()) do
		R.notify:FireClient(p, key)
	end
end

local function crewNames()
	local list = {}
	for _, p in ipairs(members()) do
		table.insert(list, p.DisplayName)
	end
	return table.concat(list, ", ")
end

-- The next start this player is allowed (never moved earlier by a shorter cooldown). Saved too
-- (data.bigScoreReadyAt, os.time seconds, like PrisonService's jailUntil), so another server keeps it.
local function setReady(p, at)
	at = math.max(at, S.readyAt[p.UserId] or 0)
	S.readyAt[p.UserId] = at
	if p.Parent == Players then
		p:SetAttribute("BigScoreReadyAt", at)
	end
	local data = svc("DataService").Get(p)
	if data then
		data.bigScoreReadyAt = os.time() + math.ceil(at - now())
	end
end

-- Studio, crew of one: that one player may do both gate consoles (StudioSoloSync).
local function soloGate()
	return RunService:IsStudio() and #S.roster <= 1
end

local function syncWindow()
	if soloGate() then
		return CFG.StudioSoloSync or CFG.ConsoleSync
	end
	return CFG.ConsoleSync
end

-- Bars still lying on the pile, and the top one (the next a grab takes).
local function pileCount()
	local n = 0
	for _, bar in ipairs(W.pileBars) do
		if bar.Transparency < 1 then
			n += 1
		end
	end
	return n
end

local function topBar()
	for i = #W.pileBars, 1, -1 do
		if W.pileBars[i].Transparency < 1 then
			return i
		end
	end
	return nil
end

-- What the van's gold pays right now (see the header).
local function potNow()
	local n = #members()
	local pot = S.bars * CFG.BarValue * (1 + CFG.MemberBonus * math.max(0, n - 2))
	if Workspace:GetAttribute("IsNight") then
		pot *= CFG.NightBonus
	end
	return math.floor(pot)
end

local function loadPoint()
	return S.van and S.van:FindFirstChild("LoadPoint")
end

-- The step's objective spot for the GPS and the marker.
local function stepTarget()
	local step = S.step
	if step == 1 then
		local chassis = S.van and S.van.PrimaryPart
		return chassis and chassis.Position or Vector3.new(CFG.VanSpot.X, W.depotY, CFG.VanSpot.Z)
	elseif step == 2 then
		return Vector3.new(CFG.Street.X, W.reserveY, CFG.Street.Z)
	elseif step == 3 then
		local a, b = CFG.ConsoleAPos, CFG.ConsoleBPos
		return Vector3.new((a.X + b.X) / 2, W.reserveY, (a.Z + b.Z) / 2)
	elseif step == 4 then
		return W.drill and W.drill.Position
	elseif step == 5 then
		return W.pile and W.pile.Position
	end
	return S.hideout and S.hideout.Position or nil
end

local function stepInfo()
	local def = K.STEPS[S.step]
	local text, hint = def.Text, def.Hint
	if S.step == 3 then
		hint = string.format(def.Hint, syncWindow())
	elseif S.step == 4 and S.drillStarted then
		hint = S.drilling and def.Running or def.Stopped
	elseif S.step == 5 then
		text = string.format(def.Text, S.bars, CFG.Bars)
	end
	local list = {}
	for _, p in ipairs(members()) do
		table.insert(list, { UserId = p.UserId, Name = p.DisplayName })
	end
	local t = now()
	return {
		Step = S.step, Total = #K.STEPS, Text = text, Hint = hint, Target = stepTarget(), TargetName = def.Name,
		Members = list, Bars = S.bars, BarsTotal = CFG.Bars, BarValue = CFG.BarValue, VanValue = potNow(),
		EndsAt = S.endsAt, ConsoleA = S.consoleA, ConsoleB = S.consoleB, SyncWindow = syncWindow(),
		Drill = S.drill, Drilling = S.drilling, AlarmUntil = (S.alarmUntil and S.alarmUntil > t) and S.alarmUntil or nil,
		CanDeliver = S.bars >= 1,
	}
end

-- "State" to every member. During loading, a member carrying a bar is pointed at the van instead.
local function push()
	if not S.active or not K.STEPS[S.step] then
		return
	end
	local base = stepInfo()
	local lp = loadPoint()
	for _, p in ipairs(members()) do
		local info = base
		if S.step == 5 and S.carry[p] and lp then
			info = table.clone(base)
			info.Target = lp.Position
			info.TargetName = "Armored van"
		end
		R.event:FireClient(p, "State", info)
	end
	S.drillPushAt = os.clock()
	S.targetAt = S.step == 1 and base.Target or nil
end

-- Each prompt is on only during its own step (the server checks everything again on Triggered); the
-- console screens show where the gate stands (during step 3 a gate a pending reset left open isn't green:
-- the consoles still want holding).
local function refreshPrompts()
	local step = S.active and S.step or 0
	local function on(prompt, yes)
		if prompt and prompt.Parent and prompt.Enabled ~= yes then
			prompt.Enabled = yes
		end
	end
	for key, pp in pairs(W.consolePrompt) do
		local done = S["console" .. key] ~= nil
		on(pp, step == 3 and not done)
		local screen = W.consoleScreen[key]
		if screen then
			screen.Color = (W.gateIsOpen and step ~= 3 and K.GREEN) or (done and step == 3 and K.AMBER) or K.RED
		end
	end
	on(W.drillPrompt, step == 4 and not S.drillStarted)
	on(W.grabPrompt, step == 5 and pileCount() > 0)
	local vp = S.vanPrompts
	on(vp.drive, step >= 2)
	on(vp.ride, step >= 2)
	on(vp.load, step == 5)
end

------------------------------------------------------------------ gold bars

-- The bar leaves this player's hand: back on the pile (toPile), or into the van.
local function dropBar(p, toPile)
	local c = S.carry[p]
	if not c then
		return
	end
	S.carry[p] = nil
	if c.bar.Parent then
		c.bar:Destroy()
	end
	local slot = W.pileBars[c.slot]
	if toPile and slot then
		slot.Transparency = 0
		refreshPrompts() -- the pile may have been empty (Grab switched off): it has a bar again
	end
	if p.Parent == Players then
		p:SetAttribute("CarryingGold", nil)
	end
end

-- A gold bar in the right hand (R15 RightHand, R6 Right Arm), else held against the chest.
local function giveBar(p, slot)
	local char = p.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	local holder = hand or (char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")))
	if not holder then
		return false
	end
	local bar = Instance.new("Part")
	bar.Name = "GoldBar"
	bar.Size = K.BAR_SIZE
	bar.Color = K.GOLD
	bar.Material = Enum.Material.Metal
	bar.Reflectance = 0.2
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CanTouch = false
	bar.Massless = true
	local weld = Instance.new("Weld")
	weld.Part0 = holder
	weld.Part1 = bar
	weld.C0 = hand and CFrame.new(0, -holder.Size.Y / 2 - 0.2, -0.2) * CFrame.Angles(0, math.rad(90), 0)
		or CFrame.new(0, -0.5, -holder.Size.Z / 2 - 0.45)
	weld.Parent = bar
	bar.CFrame = holder.CFrame * weld.C0
	bar.Parent = char
	S.carry[p] = { bar = bar, slot = slot }
	p:SetAttribute("CarryingGold", true)
	return true
end

------------------------------------------------------------------ gate, vault, reset

local function setGate(open)
	if not W.gate or W.gateIsOpen == open then
		return
	end
	W.gateIsOpen = open
	local info = TweenInfo.new(open and 3 or 4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	TweenService:Create(W.gate, info, { CFrame = open and W.gateOpenCF or W.gateShutCF }):Play()
	if W.gateLight then
		W.gateLight.Color = open and K.GREEN or K.RED
	end
end

-- The door `d` studs along its roll: moved north and turned like a wheel, its fittings with it.
local function placeVault(d)
	local cf = W.vaultShut * CFrame.new(0, 0, -d) * CFrame.Angles(-d / K.VAULT_R, 0, 0)
	for _, rec in ipairs(W.vaultParts) do
		rec[1].CFrame = cf * rec[2]
	end
end

local function setVault(open)
	if not W.vaultShut or W.vaultIsOpen == open then
		return
	end
	W.vaultIsOpen = open
	W.vaultToken += 1
	local token, from, to = W.vaultToken, W.vaultAt, open and K.VAULT_ROLL or 0
	local seconds = open and 4 or 3
	task.spawn(function()
		local t0 = os.clock()
		while token == W.vaultToken do
			local a = math.min(1, (os.clock() - t0) / seconds)
			W.vaultAt = from + (to - from) * a * a * (3 - 2 * a)
			placeVault(W.vaultAt)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Nobody (and no car but a Big Score van) inside the reserve's wall? A finished run's van is going anyway;
-- the running one's only counts in the gateway (a close before its crew opens the gate would slide into it).
local function areaClear()
	local r = CFG.ReserveRect
	local function inside(pos)
		return pos.X > r[1] - 4 and pos.X < r[2] + 4 and pos.Z > r[3] - 4 and pos.Z < r[4] + 4
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and inside(root.Position) then
			return false
		end
	end
	local cars = Workspace:FindFirstChild("Vehicles")
	for _, car in ipairs(cars and cars:GetChildren() or {}) do
		local pos = car.PrimaryPart and car.PrimaryPart.Position
		if pos and not car:GetAttribute("BigScoreVan") and inside(pos) then
			return false
		end
		if pos and car == S.van and W.gateShutCF and (pos - W.gateShutCF.Position).Magnitude < 22 then
			return false
		end
	end
	return true
end

-- force: shut even with somebody inside. Else the gate's slide is watched (tick): anyone who slips in
-- while it closes opens it again (nobody can reach the vault room in that time).
local function closeReserve(force)
	W.resetPending = false
	W.closingUntil = (not force and W.gateIsOpen) and os.clock() + 4 or nil
	setGate(false)
	setVault(false)
end

-- Gold back on the pile at once; the gate and the vault close now if nobody's inside (or `force`), else
-- as soon as the reserve is empty (tick).
local function resetWorld(force)
	for _, bar in ipairs(W.pileBars) do
		bar.Transparency = 0
	end
	if force or areaClear() then
		closeReserve(force)
	else
		W.resetPending = true
	end
	refreshPrompts()
end

------------------------------------------------------------------ steps

-- The Hideout pad nearest `from`.
local function nearestHideout(from)
	local best, bestD
	local spawns = Workspace:FindFirstChild("Spawns")
	for _, m in ipairs(spawns and spawns:GetChildren() or {}) do
		if m:IsA("Model") and m.Name == "Hideout" and m.PrimaryPart then
			local d = flatDist(m.PrimaryPart.Position, from)
			if not bestD or d < bestD then
				best, bestD = m.PrimaryPart, d
			end
		end
	end
	return best
end

local function setStep(n)
	S.step = n
	if n == 6 then
		-- Bars still in hands can't go in now: back on the pile.
		for p in pairs(S.carry) do
			dropBar(p, true)
		end
		local chassis = S.van and S.van.PrimaryPart
		S.hideout = nearestHideout(chassis and chassis.Position or CFG.ReserveCenter)
		if not S.hideout then
			warn("[BigScoreService] no Hideout in Workspace.Spawns: the van can't be delivered")
		end
	end
	for _, p in ipairs(members()) do
		p:SetAttribute("BigScore", n)
	end
	refreshPrompts()
	push()
end

-- The common checks for every Big Score prompt: on the roster of the running heist, a Civilian, alive,
-- up (not knocked down or tasered), on foot and within `reach` of `at`. Returns the humanoid and root
-- part, or nil (after a toast saying why, when there's one to give).
local function ready(p, at, reach)
	if not onRoster(p) then
		toast(p, "BigScoreNotYours")
		return nil
	end
	if p:GetAttribute("Side") ~= "Civilian" then
		return nil
	end
	local hum, root = body(p)
	if not hum or down(p, now()) then
		return nil
	end
	if hum.SeatPart then
		toast(p, "GetOutFirst")
		return nil
	end
	if not at or not at.Parent or (root.Position - at.Position).Magnitude > reach then
		return nil
	end
	return hum, root
end

-- Times a prompt's hold here: fn(player, held) on Triggered, held = true when the hold really ran its
-- length (a hold let go early is void, and an old one can't be kept for later).
local function wireHold(prompt, hold, fn)
	local began = setmetatable({}, { __mode = "k" })
	local slack = math.min(K.HOLD_SLACK, hold * 0.5)
	prompt.PromptButtonHoldBegan:Connect(function(p)
		began[p] = os.clock()
	end)
	prompt.PromptButtonHoldEnded:Connect(function(p)
		local b = began[p]
		if b and os.clock() - b < hold - slack then
			began[p] = nil
		end
	end)
	prompt.Triggered:Connect(function(p)
		local b = began[p]
		began[p] = nil
		local held = b and os.clock() - b
		fn(p, held ~= nil and held >= hold - slack and held <= hold + K.HOLD_KEEP)
	end)
end

-- Somebody with no stars doing the crime gets the step's stars (a crewmate who kept clear of the hack or
-- the alarm can't carry the gold and drive it home untouchable).
local function heatUp(p, stars)
	if (p:GetAttribute("Heat") or 0) <= 0 then
		HeatService.Add(p, stars, "bigscore")
	end
end

-- Step 1 done: the lock's open, Drive / Ride take over from the Hack prompt.
local function hackDone()
	local hack = S.vanPrompts.hack
	S.vanPrompts.hack = nil
	if hack then
		hack:Destroy()
	end
	if S.van then
		S.van:SetAttribute("Hacked", true)
	end
	setStep(2)
end

local function gateDone()
	setGate(true)
	setStep(4)
end

-- The drill starts and the alarm rings. withHeat: the alarm's stars for the crew nearby (not for the
-- Studio skip).
local function startDrill(withHeat)
	S.drillStarted = true
	S.alarmUntil = now() + CFG.AlarmSeconds
	local door = W.vaultShut and W.vaultShut.Position or CFG.VaultDoorPos
	if withHeat then
		for _, p in ipairs(members()) do
			local _, root = body(p)
			if root and (root.Position - door).Magnitude <= CFG.AlarmRange then
				HeatService.Add(p, CFG.AlarmHeat, "bigscore")
			end
		end
	end
	R.feed:FireAllClients("BigScoreAlarm", { Position = door })
	refreshPrompts()
	push()
end

local function drillDone()
	S.drill = 1
	S.drilling = false
	setVault(true)
	setStep(5)
end

-- One more bar in the van (by: who loaded it, for the crew's toast).
local function loadBar(by)
	S.bars += 1
	if S.van then
		S.van:SetAttribute("BigScoreBars", S.bars)
	end
	tell("Loaded", { Bars = S.bars, VanValue = potNow(), By = by })
	if S.bars >= CFG.Bars then
		setStep(6)
	else
		refreshPrompts()
		push()
	end
end

------------------------------------------------------------------ the van

local function onHack(p, held)
	local seat = S.van and S.van:FindFirstChild("DriverSeat")
	local hum = ready(p, seat, 10 + K.REACH_SLACK)
	if not hum or not held or S.step ~= 1 then
		return
	end
	HeatService.Add(p, CFG.VanHeat, "bigscore")
	hackDone()
	if not seat.Occupant then
		seat:Sit(hum)
	end
end

local function onLoad(p, held)
	local lp = loadPoint()
	local hum = ready(p, lp, CFG.LoadReach + 4)
	if not hum or not held or S.step ~= 5 then
		return
	end
	if not S.carry[p] then
		return -- nothing in hand (BigScoreNoBars reads "no gold left on the pile", which isn't it)
	end
	local chassis = S.van.PrimaryPart
	if not chassis or flatDist(chassis.Position, CFG.VaultDoorPos) > CFG.LoadRange then
		toast(p, "BigScoreVanFar")
		return
	end
	dropBar(p, false)
	loadBar(p.DisplayName)
end

-- "Drive" / "Ride": the crew gets in (after the hack), on foot, in reach, the seat free.
local function onBoard(p, seat)
	local hum = ready(p, seat, 12 + K.REACH_SLACK)
	if not hum or S.step < 2 or seat.Occupant then
		return
	end
	seat:Sit(hum)
end

-- Only the crew sits in the van once it's hacked; anyone else is put straight back out (like
-- CarBoostService's hot cars). The driver gets the van's physics (and VanHeat if they have no stars: it's
-- reported stolen); sitting down puts a carried bar back.
local function onVanSeat(car, seat)
	local occupant = seat.Occupant
	local p = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
	local isDriver = seat.Name == "DriverSeat"
	local chassis = car.PrimaryPart
	if p and S.van == car and S.step >= 2 and onRoster(p) and p:GetAttribute("Side") == "Civilian" then
		dropBar(p, true)
		if isDriver then
			heatUp(p, CFG.VanHeat)
		end
		if isDriver and chassis then
			car:SetAttribute("DriverUserId", p.UserId)
			pcall(function()
				chassis:SetNetworkOwner(p)
			end)
		end
		push()
	elseif occupant then
		local sw = seat:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
	elseif isDriver then
		car:SetAttribute("DriverUserId", nil)
		task.delay(1.5, function()
			if car.Parent and seat.Occupant == nil and chassis then
				pcall(function()
					chassis:SetNetworkOwner(nil)
				end)
			end
		end)
	end
end

-- Where the van parks at the depot: its bay, or a free one beside it; nose toward the gate (the depot's
-- own +Z, turned with it by DepotMove.Turn; a car's front is its -Z).
local function vanSpot(car)
	local ride = car:GetAttribute("RideHeight") or 3.3
	local v = CFG.VanSpot
	local rot = CFG.DepotCF.Rotation
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local cars = Workspace:FindFirstChild("Vehicles")
	params.FilterDescendantsInstances = cars and { cars } or {}
	local function bay(dx)
		local p = v + rot:VectorToWorldSpace(Vector3.new(dx, 0, 0))
		return CFrame.new(p.X, W.depotY + ride + 0.2, p.Z) * rot * CFrame.Angles(0, math.pi, 0)
	end
	for _, dx in ipairs({ 0, -24, 24, -42, 42 }) do
		local cf = bay(dx)
		if #Workspace:GetPartBoundsInBox(cf, Vector3.new(10, 6, 17), params) == 0 then
			return cf
		end
	end
	return bay(0)
end

-- Build and park the van: no Drive / Ride prompts of its own (nobody owns it), the Hack prompt on the
-- driver's seat, and an invisible LoadPoint at its back doors with the Load prompt.
local function spawnVan()
	local car = CarBuilder.Build("ArmoredVan")
	car.Name = "ArmoredVan"
	car:SetAttribute("BigScoreVan", true)
	local glow = car:FindFirstChild("Underglow")
	if glow then
		glow:Destroy() -- an armored van, not a street racer
	end
	local chassis = car.PrimaryPart
	local seat = car:FindFirstChild("DriverSeat")
	local pseat = car:FindFirstChild("PassengerSeat")
	for _, s in ipairs({ seat, pseat }) do
		for _, name in ipairs({ "DrivePrompt", "RidePrompt" }) do
			local old = s and s:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
	end
	local hack = newPrompt(seat, "HackPrompt", "Hack the lock", "Armored van", CFG.VanHold, 10)
	hack.Enabled = true
	local drive = newPrompt(seat, "VanDrivePrompt", "Drive", "Armored van", 0, 12)
	local ride = pseat and newPrompt(pseat, "VanRidePrompt", "Ride", "Armored van", 0, 12)
	local lp = Instance.new("Part")
	lp.Name = "LoadPoint"
	lp.Size = Vector3.new(4, 3, 1)
	lp.Transparency = 1
	lp.CanCollide = false
	lp.CanQuery = false
	lp.CanTouch = false
	lp.Massless = true
	lp.CollisionGroup = "Vehicles"
	lp.CFrame = chassis.CFrame * CFrame.new(0, 0.5, chassis.Size.Z / 2 + 1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = lp
	weld.Parent = lp
	lp.Parent = car
	local load = newPrompt(lp, "LoadPrompt", "Load gold", "Armored van", CFG.LoadHold, CFG.LoadReach)
	car:PivotTo(vanSpot(car))
	car.Parent = Workspace.Vehicles
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	S.van = car
	S.vanPrompts = { hack = hack, drive = drive, ride = ride, load = load }
	wireHold(hack, CFG.VanHold, onHack)
	wireHold(load, CFG.LoadHold, onLoad)
	drive.Triggered:Connect(function(p)
		onBoard(p, seat)
	end)
	if ride then
		ride.Triggered:Connect(function(p)
			onBoard(p, pseat)
		end)
	end
	for _, s in ipairs({ seat, pseat }) do
		s:GetPropertyChangedSignal("Occupant"):Connect(function()
			onVanSeat(car, s)
		end)
	end
end

-- Everyone out of the van's seats.
local function emptyVan(car)
	for _, name in ipairs({ "DriverSeat", "PassengerSeat" }) do
		local seat = car:FindFirstChild(name)
		local hum = seat and seat.Occupant
		if hum then
			local sw = seat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy()
			end
			hum.Sit = false
		end
	end
end

------------------------------------------------------------------ the end of a run

-- One more big heist for this player (only once their save has loaded, or the load would overwrite it).
local function addBigHeist(p)
	if not p:GetAttribute("DataLoaded") then
		return
	end
	local n = (p:GetAttribute("BigHeists") or 0) + 1
	p:SetAttribute("BigHeists", n)
	Telemetry.Custom(p, "BigHeist_BigScore", n)
end

-- Clears the run (no pay, no cooldowns: pass / fail see to those). The van goes after END_DELAY.
local function endRun()
	for p in pairs(S.carry) do
		dropBar(p, true)
	end
	for _, p in ipairs(members()) do
		p:SetAttribute("BigScore", nil)
	end
	local van = S.van
	S.active = false
	S.step = 0
	S.roster = {}
	S.van = nil
	S.vanPrompts = {}
	S.consoleA, S.consoleB, S.consoleBy = nil, nil, {}
	S.drill, S.drillStarted, S.drilling = 0, false, false
	S.alarmUntil = nil
	S.bars = 0
	S.hideout = nil
	S.targetAt = nil
	S.loseCopsAt = {}
	ReplicatedStorage:SetAttribute("BigScoreBusy", nil)
	if van then
		emptyVan(van)
		for _, d in ipairs(van:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				d.Enabled = false
			end
		end
		task.delay(K.END_DELAY, function()
			if van.Parent then
				van:Destroy()
			end
		end)
	end
	resetWorld(false)
end

local function fail(reason)
	if not S.active then
		return
	end
	local t = now()
	for _, p in ipairs(members()) do
		setReady(p, t + CFG.FailCooldown)
		R.event:FireClient(p, "Failed", { Reason = reason })
		Telemetry.Custom(p, "BigScoreFailed", S.step)
	end
	endRun()
end

-- Delivered: the pot, split evenly between the members still here (see the header).
local function pass()
	local list = members()
	local pot = potNow()
	local share = math.floor(pot / math.max(1, #list))
	local xp = ((Progression.XP and Progression.XP.Heist) or 40) * CFG.XPTier
	local crew = crewNames()
	local bars = S.bars
	local t = now()
	local HideoutService = svc("HideoutService")
	for _, p in ipairs(list) do
		local cut = share
		if p:GetAttribute("Pass_VIP") then
			cut = math.floor(cut * (1 + Shop.VIPCashBonus))
		end
		EconomyService.AddCash(p, cut, "bigscore")
		local ok, err = pcall(svc("ProgressService").Event, p, "Heist", CFG.XPTier)
		if not ok then
			warn("[BigScoreService] XP: " .. tostring(err))
		end
		addBigHeist(p)
		Telemetry.Custom(p, "BigScore", cut)
		local _, root = body(p)
		if root and HideoutService.IsInside(root.Position) then
			HeatService.Clear(p, "hideout")
		end
		setReady(p, t + CFG.Cooldown)
		R.event:FireClient(p, "Done", { Cut = cut, XP = xp, Total = pot, Bars = bars, Crew = #list })
	end
	R.feed:FireAllClients("BigScoreDone", { Total = pot, Crew = crew })
	endRun()
end

-- Is anyone left to carry on? Fails the run (and says false) when not: nobody on the roster, or nobody
-- on it who's in the server and a Civilian (arrested members stay on the roster, but can't carry it).
local function crewLeft()
	if #S.roster == 0 then
		fail("The crew split up")
		return false
	end
	for _, p in ipairs(members()) do
		if p:GetAttribute("Side") == "Civilian" then
			return true
		end
	end
	fail(#members() > 0 and "The whole crew got cuffed" or "The crew split up")
	return false
end

-- Off the roster (quit, or joined the police): their own "Failed", FailCooldown, out of the van.
local function removeMember(p, reason)
	local i = table.find(S.roster, p)
	if not i then
		return
	end
	table.remove(S.roster, i)
	dropBar(p, true)
	if p.Parent == Players then
		p:SetAttribute("BigScore", nil)
		setReady(p, now() + CFG.FailCooldown)
		R.event:FireClient(p, "Failed", { Reason = reason })
		local hum = body(p)
		local seat = hum and hum.SeatPart
		if seat and S.van and seat:IsDescendantOf(S.van) then
			local sw = seat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy()
			end
			hum.Sit = false
		end
	end
	if crewLeft() then
		push()
	end
end

------------------------------------------------------------------ the world's prompts

local function onConsole(p, key, held)
	local hum = ready(p, W.console[key], 8 + K.REACH_SLACK)
	if not hum or not held or S.step ~= 3 then
		return
	end
	local t = now()
	local other = key == "A" and "B" or "A"
	S["console" .. key] = t
	S.consoleBy[key] = p
	if S.consoleA and S.consoleB then
		-- Both by the same player (a client holding the two prompts at once) doesn't count, bar Studio's
		-- crew of one.
		if math.abs(S.consoleA - S.consoleB) <= syncWindow() and (S.consoleBy[other] ~= p or soloGate()) then
			gateDone()
			return
		end
		-- The other console was done too long ago (or by this same player): it clears, this one stands.
		S["console" .. other] = nil
		tellNotify("BigScoreSync")
	end
	refreshPrompts()
	push()
end

local function onDrill(p, held)
	local hum = ready(p, W.drill, 10 + K.REACH_SLACK)
	if not hum or not held or S.step ~= 4 or S.drillStarted then
		return
	end
	startDrill(true)
end

local function onGrab(p, held)
	local hum = ready(p, W.pile, 10 + K.REACH_SLACK)
	if not hum or not held or S.step ~= 5 then
		return
	end
	if S.carry[p] then
		toast(p, "BigScoreCarrying")
		return
	end
	local slot = topBar()
	if not slot then
		toast(p, "BigScoreNoBars")
		return
	end
	W.pileBars[slot].Transparency = 1
	if not giveBar(p, slot) then
		W.pileBars[slot].Transparency = 0
		return
	end
	heatUp(p, CFG.AlarmHeat)
	refreshPrompts()
	push()
end

------------------------------------------------------------------ the run's clock

local function tick(dt)
	local t = now()
	-- The facade's alarm lights flash while the alarm rings; the drill sparks while it turns.
	local ringing = S.alarmUntil ~= nil and t < S.alarmUntil
	local lit = ringing and math.floor(os.clock() * 2) % 2 == 0
	for _, light in ipairs(W.alarmLights) do
		local color = lit and K.RED or K.ALARM_OFF
		if light.Color ~= color then
			light.Color = color
			light.Material = lit and Enum.Material.Neon or Enum.Material.Metal
		end
	end
	if W.sparks and W.sparks.Enabled ~= (S.active and S.drilling) then
		W.sparks.Enabled = S.active and S.drilling
	end
	-- Somebody slipped in while the gate slid shut: it opens again, and closes once they've gone.
	if W.closingUntil then
		if os.clock() >= W.closingUntil then
			W.closingUntil = nil
		elseif not areaClear() then
			W.closingUntil = nil
			setGate(true)
			W.resetPending = true
			refreshPrompts()
		end
	end
	-- A reset waiting for the reserve to empty (while the next crew is still outside: up to the consoles).
	if W.resetPending and (not S.active or S.step <= 3) and areaClear() then
		closeReserve()
		refreshPrompts()
	end
	if not S.active then
		return
	end
	if t >= S.endsAt then
		fail("Time's up")
		return
	end
	local van = S.van
	local chassis = van and van.Parent and van.PrimaryPart
	if not chassis or chassis.Position.Y < K.SUNK_Y then
		fail("The van was lost")
		return
	end
	-- Joining the police takes you off the roster (prisoners stay on it).
	for i = #S.roster, 1, -1 do
		local p = S.roster[i]
		if p and p.Parent == Players and p:GetAttribute("Side") == "Cop" then
			removeMember(p, "You joined the police")
			if not S.active then
				return
			end
		end
	end
	if not crewLeft() then
		return
	end
	-- Before the gate opens, one member left in the server can't hold both consoles (bar Studio's crew of one).
	if S.step <= 3 and #members() < 2 and not soloGate() then
		fail("Not enough crew left for the gate")
		return
	end
	local changed = false
	-- Carried bars go back to the pile when their carrier can't carry them on (knocked down counts: in
	-- this game nobody dies, so a knockout is the fall that loses the bar).
	local pilePos = W.pile and W.pile.Position
	for p, c in pairs(S.carry) do
		local hum, root = body(p)
		local keep = p.Parent == Players and table.find(S.roster, p) ~= nil and p:GetAttribute("Side") == "Civilian"
			and (p:GetAttribute("KnockedUntil") or 0) <= t
			and hum ~= nil and hum.SeatPart == nil and c.bar.Parent ~= nil and p.Character ~= nil
			and c.bar:IsDescendantOf(p.Character) and (not pilePos or (root.Position - pilePos).Magnitude <= CFG.CarryLeash)
		if not keep then
			dropBar(p, true)
			changed = true
		end
	end
	local step = S.step
	if step == 1 then
		-- Somebody shoved the parked van: the marker follows it.
		if S.targetAt and (chassis.Position - S.targetAt).Magnitude > 8 then
			changed = true
		end
	elseif step == 2 then
		if flatDist(chassis.Position, CFG.Street) <= CFG.StreetRadius then
			setStep(3)
			return
		end
	elseif step == 3 then
		local w = syncWindow()
		for _, key in ipairs({ "A", "B" }) do
			local at = S["console" .. key]
			if at and t - at > w then
				S["console" .. key] = nil
				tellNotify("BigScoreSync")
				changed = true
			end
		end
	elseif step == 4 and S.drillStarted then
		local near = false
		for _, p in ipairs(members()) do
			local hum, root = body(p)
			if hum and not hum.SeatPart and not down(p, t) and p:GetAttribute("Side") == "Civilian" and W.drill
				and flatDist(root.Position, W.drill.Position) <= CFG.DrillRange then
				near = true
				break
			end
		end
		if near ~= S.drilling then
			S.drilling = near
			changed = true
		end
		if near then
			S.drill = math.min(1, S.drill + dt / CFG.DrillTime)
		end
		if S.drill >= 1 then
			drillDone()
			return
		end
		if os.clock() - S.drillPushAt >= 1 then
			changed = true
		end
	elseif step == 5 then
		local away = flatDist(chassis.Position, CFG.ReserveCenter) >= CFG.LeaveRadius
		if S.bars >= CFG.Bars or (S.bars >= 1 and away) then
			setStep(6)
			return
		end
	elseif step == 6 then
		-- Delivered: the chassis on the Hideout pad with a crew member driving whom no cop can see.
		local seat = van:FindFirstChild("DriverSeat")
		local occupant = seat and seat.Occupant
		local driver = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if driver and table.find(S.roster, driver) and svc("HideoutService").IsInside(chassis.Position) then
			if not driver:GetAttribute("HeatSpotted") then
				pass()
				return
			end
			local last = S.loseCopsAt[driver]
			if not last or os.clock() - last >= K.LOSE_COPS_GAP then
				S.loseCopsAt[driver] = os.clock()
				R.notify:FireClient(driver, "BigScoreLoseCops")
			end
		end
	end
	if changed then
		refreshPrompts()
		push()
	end
end

------------------------------------------------------------------ starting

-- Can this player start a run? The roster, or nil and the Notify key that says why not.
local function canStart(p)
	if p:GetAttribute("Side") ~= "Civilian" then
		return nil, "BigScoreCivOnly"
	end
	if S.active or not W.ready then
		return nil, "BigScoreBusy"
	end
	if (p:GetAttribute("Heat") or 0) > 0 then
		return nil, "BigScoreWanted"
	end
	if p:GetAttribute("Mission") or p:GetAttribute("RacingId") or p:GetAttribute("JobKind") then
		return nil, "MissionBusy"
	end
	if (p:GetAttribute("CivRank") or 1) < CFG.MinRank then
		return nil, "BigScoreRank"
	end
	local t = now()
	if t < (S.readyAt[p.UserId] or 0) then
		return nil, "BigScoreCooldown"
	end
	local roster = { p }
	local crew = svc("CrewService").CrewOf(p)
	for _, mate in ipairs(crew and crew.members or {}) do
		if #roster >= CFG.CrewMax then
			break
		end
		-- Crewmates busy with a mission, race or job shift stay out of this run (they'd get two strips).
		local busy = mate:GetAttribute("Mission") or mate:GetAttribute("RacingId") or mate:GetAttribute("JobKind")
		if mate ~= p and mate.Parent == Players and mate:GetAttribute("Side") == "Civilian" and not busy
			and t >= (S.readyAt[mate.UserId] or 0) then
			table.insert(roster, mate)
		end
	end
	if #roster < CFG.CrewMin then
		return nil, "BigScoreNeedCrew"
	end
	return roster
end

-- Step 1 for this roster: the van parked at the depot, the gold on the pile. False if the van couldn't be
-- built (nothing started then).
local function startRun(roster)
	if not W.ready then
		return false
	end
	S.consoleA, S.consoleB, S.consoleBy = nil, nil, {}
	S.drill, S.drillStarted, S.drilling = 0, false, false
	S.alarmUntil = nil
	S.bars = 0
	S.carry = {}
	S.loseCopsAt = {}
	S.hideout = nil
	resetWorld(false)
	local ok, err = pcall(spawnVan)
	if not ok then
		warn("[BigScoreService] van: " .. tostring(err))
		if S.van then
			S.van:Destroy()
			S.van = nil
		end
		return false
	end
	S.active = true
	S.roster = roster
	S.endsAt = now() + CFG.TimeLimit
	ReplicatedStorage:SetAttribute("BigScoreBusy", true)
	for _, p in ipairs(roster) do
		Telemetry.Custom(p, "BigScoreStart", #roster)
	end
	R.feed:FireAllClients("BigScoreStarted", { Crew = crewNames() })
	setStep(1)
	return true
end

local function onRequest(p, action)
	if not RateLimit.Allow(p, "BigScore", 1, 2) or type(action) ~= "string" then
		return
	end
	if action == "Quit" then
		if onRoster(p) then
			removeMember(p, "You quit the heist")
		end
		return
	end
	if action ~= "Start" then
		return
	end
	local roster, why = canStart(p)
	if not roster then
		R.notify:FireClient(p, why)
		return
	end
	if not startRun(roster) then
		R.notify:FireClient(p, "BigScoreBusy")
	end
end

------------------------------------------------------------------ Studio test hook

-- A server move of the van: VehicleGuard is told first, the server holds its physics for the jump, and the
-- driver gets them back after (as VehicleGuard's own snap-back does).
local function moveVan(cf)
	local van = S.van
	local chassis = van and van.PrimaryPart
	if not chassis then
		return
	end
	svc("VehicleGuard").Allow(van, 3)
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	van:PivotTo(cf)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	task.delay(0.6, function()
		local seat = van:FindFirstChild("DriverSeat")
		local occupant = seat and seat.Occupant
		local p = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if van.Parent and p then
			pcall(function()
				chassis:SetNetworkOwner(p)
			end)
		end
	end)
end

local function debugLoad(n)
	for _ = 1, n do
		local slot = S.step == 5 and topBar()
		if not slot then
			return
		end
		W.pileBars[slot].Transparency = 1
		loadBar("Studio")
	end
end

-- The tester rides along with a van the Studio hook moved: into its driver's seat, if they're on foot
-- and it's free.
local function seatTester(player)
	local seat = S.van and S.van:FindFirstChild("DriverSeat")
	local hum = typeof(player) == "Instance" and player:IsA("Player") and body(player)
	if seat and hum and not hum.SeatPart and not seat.Occupant then
		seat:Sit(hum)
	end
end

-- Studio only (see the header). Returns where the run stands.
function BigScoreService.Debug(player, what)
	if not RunService:IsStudio() then
		return "Studio only"
	end
	if what == "reset" or what == "start" then
		if S.active then
			endRun()
		end
		-- "reset" shuts the gate and the vault even with someone inside; "start" waits for them as usual.
		resetWorld(what == "reset")
		if what == "reset" then
			return "reset"
		end
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return "no player"
		end
		if not startRun({ player }) then
			return "start failed (see the output)"
		end
		return "step 1"
	end
	local want = ({ van = 3, gate = 4, drill = 5, load = 5, deliver = 6 })[what]
	if not want then
		return "unknown: " .. tostring(what)
	end
	if not S.active then
		return "not running: call start first"
	end
	if S.step == 1 then
		hackDone()
	end
	local ride = S.van and S.van:GetAttribute("RideHeight") or 3.3
	if S.step == 2 then
		local spot = Vector3.new(CFG.Street.X, W.reserveY + ride + 0.3, CFG.Street.Z)
		local toGate = (CFG.ReserveCenter - CFG.Street) * Vector3.new(1, 0, 1)
		moveVan(CFrame.lookAt(spot, spot + toGate.Unit)) -- nose toward the gate
		setStep(3)
		seatTester(player)
	end
	if S.step == 3 and want >= 4 then
		gateDone()
	end
	if S.step == 4 and want >= 5 then
		if not S.drillStarted then
			startDrill(false)
		end
		drillDone()
	end
	if what == "load" then
		debugLoad(4)
	elseif what == "deliver" then
		if S.step == 5 and S.bars == 0 then
			debugLoad(4)
		end
		if S.step == 5 then
			setStep(6)
		end
		-- Delivery needs a crew member driving: the tester is put in the seat (the next tick pays).
		local pad = S.hideout
		if S.step == 6 and pad then
			moveVan(pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + ride + 0.3, 0))
			seatTester(player)
		end
	end
	return string.format("step %d, bars %d", S.step, S.bars)
end

------------------------------------------------------------------ start-up

-- Whether a heist is running, and whether this player is on its roster (for other services).
function BigScoreService.IsRunning()
	return S.active
end

function BigScoreService.OnRoster(player)
	return onRoster(player)
end

local function wireWorld()
	for key, pp in pairs(W.consolePrompt) do
		wireHold(pp, CFG.ConsoleHold, function(p, held)
			onConsole(p, key, held)
		end)
	end
	wireHold(W.drillPrompt, CFG.DrillHold, onDrill)
	wireHold(W.grabPrompt, CFG.GrabHold, onGrab)
	for _, eye in ipairs(W.eyes) do
		HeatService.RegisterEye(eye)
	end
end

function BigScoreService.Init()
	R.event = Remotes.Event("BigScoreEvent")
	R.feed = Remotes.Event("Feed")
	R.notify = Remotes.Event("Notify")
	Remotes.Event("RequestBigScore").OnServerEvent:Connect(onRequest)
	ReplicatedStorage:SetAttribute("BigScoreBusy", nil)
	local ok, err = pcall(function()
		buildWorld()
		wireWorld()
	end)
	W.ready = ok
	if not ok then
		warn("[BigScoreService] world: " .. tostring(err))
	end
	-- A cooldown outlasts leaving and rejoining: this server's (by UserId), or another's (the save).
	Players.PlayerAdded:Connect(function(p)
		local at = S.readyAt[p.UserId]
		if at and at > now() then
			p:SetAttribute("BigScoreReadyAt", at)
		end
	end)
	svc("DataService").OnLoaded(function(p, data)
		local left = (tonumber(data.bigScoreReadyAt) or 0) - os.time()
		if left > 0 then
			setReady(p, now() + left)
		else
			data.bigScoreReadyAt = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		S.loseCopsAt[p] = nil
		dropBar(p, true)
		local i = table.find(S.roster, p)
		if S.active and i then
			table.remove(S.roster, i)
			setReady(p, now() + CFG.FailCooldown)
			if crewLeft() then
				push()
			end
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(K.TICK)
			local clock = os.clock()
			local ok2, err2 = pcall(tick, clock - last)
			last = clock
			if not ok2 then
				warn("[BigScoreService] " .. tostring(err2))
			end
		end
	end)
end

return BigScoreService
