-- RobberBotService (ModuleScript, ServerScriptService.Services.RobberBotService)
-- NPC robbers for cops to chase (owner, Nov 4: "if no one's stealing anything and the game's kind of dead,
-- could there be like a bot playing the game, stealing something? ... I think like 2 bots"). Design and
-- test checklist: launch/14-ROBBER-BOTS.md.
--   * Who and when: up to K.MAX_BOTS, only while a player cop is on duty and really patrolling
--     (ArrestService.IsActiveCop). They step aside for real robbers: bots wanted = K.MAX_BOTS minus the
--     players wanted right now. At most one bot is wanted (or on its way to a crime) per patrolling cop, and
--     two bot crimes are at least K.CRIME_GAP seconds apart. A bot in the middle of a chase is never pulled
--     out; an idle one that isn't needed drives off and vanishes where no player is near (K.VANISH_CLEAR).
--     They appear only on a road K.SPAWN_AWAY+ studs from every player.
--   * Each bot: a plain street car (RaceAIService drives it: the street races' NPC driver) with a posed
--     rider in the driver's seat, and a walking Humanoid body when it's out (Workspace.RobberBots), built
--     like PoliceOfficerService's officers. Its name is on a small "NAME · NPC" tag. Nobody can get in its
--     car; guns and fists don't touch it (not in Workspace.NPCs); it never knocks anyone down.
--   * A life: cruise (K.CRUISE_PACE) -> a crime (K.CRIMES: an ATM, a Glow Mart / Fuel Stop till, rarely
--     Sparkle & Co., or a carjack) -> drive there, park, walk in, do it (the heist's own Hold seconds; 3 s to
--     break into a car) -> flee by car, or on foot once spiked or boxed in -> caught, or away (lie low,
--     K.NEXT_CRIME, then again).
--       - Stores: the silent alarm goes the moment the robbery starts (the site's AlarmUntil and the
--         "HeistAlarm" feed: cops get DISPATCH while the bot is still inside); the clerk's hands go up.
--         The store's own state (ReopenAt, Robbable) is never touched, and a store with a real player within
--         K.CLEAR_RADIUS is never picked: bots don't use up a real robber's store.
--       - Carjack: a parked street car that appeared out of everyone's sight; its alarm rings
--         (CarAlarmUntil) and cops get "BotCarjack" (DISPATCH). The bot's old car is left behind and goes
--         once nobody is near.
--   * Wanted, the way HeatService does it for players (kept here: HeatService only knows players). Stars
--     from the crime; a player cop within K.SIGHT studs with a clear line sees it (or it's near its store's
--     ringing alarm); unseen K.HOLLOW s -> hollow stars; unseen K.ESCAPE_BASE + K.ESCAPE_PER x stars ->
--     away ("Escaped" feed). The record's attributes (Shared.Util.RobberBots) are what LawClient draws the
--     WANTED / LAST SEEN marker, search circle and Suspect Card from. Only player cops see bots: AI patrols
--     leave them alone, so the bounty is a player's.
--   * Caught with the cops' own tools (ArrestService): spikes flatten its tyres (car attribute FlatUntil,
--     CarPhysics slows it), rams push it (ImpactService's CarBump), CuffDriver once its car has stopped
--     (CuffCar), the taser on foot (CanTase / Stun), the Cuff prompt on its body (BotCuffPrompt). Spiked
--     or boxed in with a cop near, it may bail out and run (K.RUN: a little under a player's walk); run
--     down on foot it may put its hands up (K.GIVE_UP_CHANCE).
--   * The arrest pays the cop like a player's (ArrestService.RewardCop): $500 a star + 25% of its bag,
--     VIP bonus, arrest XP, the BOUNTY stamp and the "Arrest" feed. The slot comes back K.RESPAWN later.
-- Public (ArrestService): CuffCar(cop, car) -> ok, why; CanTase(model) -> bool; Stun(model, seconds, cop);
-- CarWanted(car) -> bool. Studio tests (DebugService "call"): Status() -> text; Test(on) shortens every
-- wait and lets bots run without a cop; Crime(id?) -> a crime now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local RobberBots = require(ReplicatedStorage.Shared.Util.RobberBots)
local HeatService = require(ServerScriptService.Services.HeatService)
local ArrestService = require(ServerScriptService.Services.ArrestService)
local RaceAIService = require(ServerScriptService.Services.RaceAIService)

local RobberBotService = {}

local K = {
	MAX_BOTS = 2,
	TICK = 0.2, -- seconds between two decisions (driving is RaceAIService's, every frame)
	SIGHT_EVERY = 0.5,
	MANAGE_EVERY = 1,
	-- Cars: plain street cars (Config.Vehicles) held under a patrol car's 135.
	CARS = { "StreetSedan", "StreetHatch", "StreetPickup" },
	PAINTS = {
		Color3.fromRGB(40, 70, 200), Color3.fromRGB(220, 40, 50), Color3.fromRGB(240, 240, 245), Color3.fromRGB(22, 22, 28),
		Color3.fromRGB(128, 128, 136), Color3.fromRGB(70, 150, 70), Color3.fromRGB(255, 214, 10), Color3.fromRGB(255, 138, 61),
	},
	TOP = 108, -- studs/s flat out (a Sunray Patrol does 135: a cop can always catch up)
	CRUISE_PACE = 0.6, -- x TOP while cruising (about traffic speed)
	LAY_LOW_PACE = 0.8, -- x TOP while wanted but unseen
	LANE = 4, -- studs right of the road's middle line
	SPAWN_Y = 3.2, -- (RaceAIService's grid height: the roads are flat at the ground)
	SPAWN_AWAY = 300, -- studs: never appear this close to a player...
	SPAWN_NEAR_COP = 1600, -- ...but within this of a cop, so they're in play
	VANISH_CLEAR = 250, -- studs: nobody this close when a bot (or a car it left) disappears
	GOAL_REACH = 45, -- studs: a route's end this close counts as reached
	-- Pacing (seconds; Test() shortens them).
	FIRST_CRIME = { 25, 45 },
	NEXT_CRIME = { 50, 90 },
	CRIME_GAP = 45, -- between two bot crimes (any bot)
	RESPAWN = { 60, 100 }, -- a caught bot's slot comes back after this
	NO_COP_LEAVE = 45, -- no cop for this long: idle bots leave
	TO_CRIME_MAX = 120, -- driving to a crime longer than this: forget it
	CAR_LEFT = 180, -- a car a bot left goes once nobody is near, or after this anyway
	-- Crimes.
	CRIMES = {
		{ Kind = "Heist", Heist = "ATM", Weight = 3 },
		{ Kind = "Heist", Heist = "GlowMart", Weight = 3 },
		{ Kind = "Heist", Heist = "FuelStop", Weight = 3 },
		{ Kind = "Heist", Heist = "SparkleCo", Weight = 1 },
		{ Kind = "Carjack", Weight = 2 },
	},
	SITE_MIN = 200, -- studs from the bot to a store it picks...
	SITE_MAX = 1500,
	COP_IDEAL = 550, -- ...preferring one about this far from the nearest cop (time to respond)
	CLEAR_RADIUS = 120, -- a real player this close to a store: not that one
	JACK_HOLD = 3, -- seconds breaking into a car (CarjackService's Break in)
	JACK_ALARM = 8,
	-- On foot.
	WALK = 10,
	RUN = 16, -- (players walk 18: a cop on foot catches a running bot)
	WALK_TIMEOUT = 18, -- seconds to reach the till / the car before giving up on it
	ROB_REACH = 14, -- studs: close enough to rob from when the walk times out
	SPOT_REACH = 2.5,
	BOARD_REACH = 9, -- studs (flat) from its driver's seat: close enough to get in
	SEAT_UP = 1.3, -- a seated R15 rider's root above the seat's top (PoliceOfficerService's SEAT_UP)
	-- Being chased.
	SIGHT = 250, -- HeatService's numbers
	HOLLOW = 8,
	ESCAPE_BASE = 30,
	ESCAPE_PER = 10,
	HOT_ZONE = 60,
	PING_EVERY = 15, -- unseen: a witness calls in where it is this often (LastSeen moves; the escape clock doesn't stop)
	COP_SPOOK = 30, -- a cop on foot this close while it robs: it runs (a patrol car: x 1.5)
	BAIL_RANGE = 150, -- studs: a cop this close to a spiked car...
	BAIL_CHANCE = 0.6, -- ...and it bails out with this chance (once per flat)
	STUCK_RANGE = 60, -- a cop this close while it hardly moves...
	STUCK_TIME = 4, -- ...for this long (moved under STUCK_MOVE studs): it bails out
	STUCK_MOVE = 8,
	BACK_TO_CAR = 120, -- on foot, no cop within this and its car within 150: back to the car
	GIVE_UP_NEAR = 12, -- a cop on foot this close...
	GIVE_UP_CHANCE = 0.35, -- ...and it puts its hands up with this chance (each approach)
	TASED_GIVE_UP = 0.5, -- ...or after a taser hit
	GIVE_UP_LONELY = 8, -- seconds with no cop within 60 before the hands come down again
	-- Cuffs (ArrestService's numbers).
	CUFF_RANGE = 12,
	STILL_FOOT = 10,
	STILL_CAR = 5,
	CAUGHT_SHOW = 4, -- seconds the caught bot stands there with its hands up before it's taken away
	BOUNTY_STAR = 500, -- HeatService.Bounty: $500 a star + 25% of the bag
	BOUNTY_BAG = 0.25,
	-- Looks.
	NAMES = { "Gator Gus", "Slick Vinny", "Mango Mike", "Flip-Flop Frank", "Big Tuna", "Swampy Sal", "Neon Nate", "Turbo Tina" },
	LOOKS = {
		{ Skin = Color3.fromRGB(234, 192, 150), Top = Color3.fromRGB(30, 32, 38), Legs = Color3.fromRGB(40, 60, 120),
			Hat = { "black beanie", Color3.fromRGB(22, 22, 28) }, Mask = { "red bandana", Color3.fromRGB(220, 40, 60) } },
		{ Skin = Color3.fromRGB(160, 110, 75), Top = Color3.fromRGB(110, 110, 118), Legs = Color3.fromRGB(30, 30, 36),
			Hat = { "grey beanie", Color3.fromRGB(120, 120, 128) }, Mask = { "black bandana", Color3.fromRGB(28, 28, 34) } },
		{ Skin = Color3.fromRGB(255, 220, 185), Top = Color3.fromRGB(70, 44, 104), Legs = Color3.fromRGB(60, 60, 70),
			Hat = { "orange beanie", Color3.fromRGB(255, 138, 61) }, Mask = { "black bandana", Color3.fromRGB(28, 28, 34) } },
		{ Skin = Color3.fromRGB(110, 75, 55), Top = Color3.fromRGB(150, 24, 40), Legs = Color3.fromRGB(20, 24, 36),
			Hat = { "black beanie", Color3.fromRGB(22, 22, 28) }, Mask = { "white bandana", Color3.fromRGB(240, 240, 235) } },
	},
	ANIM = {
		idle = "rbxassetid://507766388", walk = "rbxassetid://507777826", run = "rbxassetid://507767714",
	},
}

local S = {
	bots = {}, -- [id] = bot
	slots = {}, -- [slot] = { respawnAt = os.clock() }
	looks = {}, -- body templates (Models), built at Init
	left = {}, -- cars bots left behind: { drive = RaceAIService bot, at = os.clock() }
	lastCrimeAt = -math.huge,
	noCopSince = nil,
	test = false,
	rng = Random.new(),
	recFolder = nil, -- ReplicatedStorage.RobberBots
	bodyFolder = nil, -- Workspace.RobberBots
	feed = nil,
}

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

------------------------------------------------------------------ small things

local function clock()
	return os.clock()
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a, b)
	return (flat(a) - flat(b)).Magnitude
end

local function between(range)
	if S.test then
		return math.min(range[1], 6)
	end
	return S.rng:NextNumber(range[1], range[2])
end

local function setAttr(inst, name, value)
	if inst and inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function aliveRoot(player)
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	return root, hum
end

-- Player cops in the game: { player, root (alive), driving (bool) }.
local function cops()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Side") == "Cop" then
			local root, hum = aliveRoot(p)
			if root then
				table.insert(list, { player = p, root = root, driving = hum.SeatPart ~= nil })
			end
		end
	end
	return list
end

local function activeCopCount()
	if S.test then
		return math.max(1, #cops())
	end
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Side") == "Cop" and ArrestService.IsActiveCop(p) then
			n += 1
		end
	end
	return n
end

local function realWanted()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) > 0 then
			n += 1
		end
	end
	return n
end

-- The nearest living cop to `pos`: their entry from cops() and the flat distance (math.huge if none).
local function nearestCop(pos, list)
	local best, bestD = nil, math.huge
	for _, c in ipairs(list or cops()) do
		local d = flatDist(c.root.Position, pos)
		if d < bestD then
			best, bestD = c, d
		end
	end
	return best, bestD
end

local function playerNear(pos, range)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - pos).Magnitude <= range then
			return true
		end
	end
	return false
end

local function civilianNear(pos, range)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p:GetAttribute("Side") == "Civilian" and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - pos).Magnitude <= range then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ roads

-- The nearest point on any road stretch to `pos` (flat), and the stretch's direction there.
local function nearestRoadPoint(pos)
	local nodes = RoadGraph.Nodes
	local here = flat(pos)
	local bestP, bestD, bestDir
	for i, links in pairs(RoadGraph.Edges) do
		local a = nodes[i]
		if a then
			for j in pairs(links) do
				local b = nodes[j]
				if b and j > i then
					local ab = b - a
					local len2 = ab:Dot(ab)
					local t = len2 > 0 and math.clamp((here - a):Dot(ab) / len2, 0, 1) or 0
					local p = a + ab * t
					local d = (here - p).Magnitude
					if not bestD or d < bestD then
						bestP, bestD, bestDir = p, d, len2 > 0 and ab.Unit or Vector3.zAxis
					end
				end
			end
		end
	end
	return bestP, bestDir
end

-- A road crossing between minD and maxD studs (flat) from `from`, the best of a few random ones by
-- score(node) (higher is better, nil rules it out; no score = any), and its index. nil if none fits.
local function pickNode(from, minD, maxD, score)
	local nodes = RoadGraph.Nodes
	if #nodes == 0 then
		return nil
	end
	local best, bestI, bestScore
	for _ = 1, 40 do
		local i = S.rng:NextInteger(1, #nodes)
		local n = nodes[i]
		local d = flatDist(n, from)
		if d >= minD and d <= maxD then
			local s = score and score(n) or S.rng:NextNumber()
			if s and (not bestScore or s > bestScore) then
				best, bestI, bestScore = n, i, s
			end
		end
	end
	return best, bestI
end

------------------------------------------------------------------ looks

local function addPart(model, head, name, size, offset, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Fabric
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CFrame = head.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = head, p
	weld.Parent = p
	p.Parent = model
end

-- One body per K.LOOKS entry (a hoodie, a beanie and a bandana), in ServerStorage.RobberBotLooks.
local function buildLooks()
	local folder = ServerStorage:FindFirstChild("RobberBotLooks") or Instance.new("Folder")
	folder.Name = "RobberBotLooks"
	folder.Parent = ServerStorage
	for i, look in ipairs(K.LOOKS) do
		local ok, model = pcall(function()
			local desc = Instance.new("HumanoidDescription")
			desc.HeadColor = look.Skin
			desc.LeftArmColor, desc.RightArmColor, desc.TorsoColor = look.Top, look.Top, look.Top
			desc.LeftLegColor, desc.RightLegColor = look.Legs, look.Legs
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if ok and model then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BaseScript") then
					d:Destroy() -- (no Animate script on a server NPC: the tick plays the animations)
				end
			end
			local hum = model:FindFirstChildOfClass("Humanoid")
			local head = model:FindFirstChild("Head")
			if hum and head and head:IsA("BasePart") then
				hum.BreakJointsOnDeath = false
				hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
				hum.NameDisplayDistance = 60
				local h = head.Size
				addPart(model, head, "Beanie", Vector3.new(h.X * 1.04, h.Y * 0.45, h.Z * 1.04), CFrame.new(0, h.Y * 0.4, 0), look.Hat[2])
				addPart(model, head, "Bandana", Vector3.new(h.X * 1.02, h.Y * 0.38, h.Z * 1.02), CFrame.new(0, -h.Y * 0.2, 0), look.Mask[2])
				model.Name = "RobberLook" .. i
				model:SetAttribute("Outfit", look.Hat[1] .. ", " .. look.Mask[1])
				model.Parent = folder
				table.insert(S.looks, model)
			else
				model:Destroy()
			end
		else
			warn("[RobberBotService] couldn't build a look: " .. tostring(model))
		end
	end
end

------------------------------------------------------------------ the record (what devices read)

local function botPos(bot)
	local w = bot.walker
	if w and w.root.Parent then
		return w.root.Position
	end
	local d = bot.drive
	if d and d.chassis.Parent then
		return d.chassis.Position
	end
	return nil
end

-- The Suspect Card: the car while it drives, the outfit on foot (as HeatService.noteClues).
local function noteClues(bot)
	if bot.rider and bot.drive and bot.drive.chassis.Parent then
		local car = bot.drive.car
		setAttr(bot.rec, "SuspectCar", (car:GetAttribute("DisplayName") or "Car") .. " (" .. HeatService.ColorWord(bot.drive.chassis.Color) .. ")")
	elseif bot.walker then
		setAttr(bot.rec, "SuspectOutfit", bot.outfit)
	end
end

local function addHeat(bot, amount)
	local before = bot.heat
	bot.heat = math.clamp(before + amount, 0, 5)
	if before <= 0 and bot.heat > 0 then
		setAttr(bot.rec, "WantedSince", serverNow())
	end
	setAttr(bot.rec, "Heat", bot.heat)
	bot.lastSeenAt = clock()
	local pos = botPos(bot)
	if pos then
		setAttr(bot.rec, "LastSeen", pos)
	end
	noteClues(bot) -- (the store's camera saw them)
end

local function clearHeat(bot)
	bot.heat = 0
	bot.bag = 0
	bot.lastSeenAt = nil
	for _, name in ipairs({ "Heat", "HeatSpotted", "LastSeen", "SuspectCar", "SuspectOutfit", "WantedSince" }) do
		setAttr(bot.rec, name, nil)
	end
end

------------------------------------------------------------------ bodies

local function say(bot, text)
	local w = bot.walker
	local head = w and w.model:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild("Say")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Say"
		gui.Size = UDim2.fromOffset(200, 32)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 80
		gui.Parent = head
		local l = Instance.new("TextLabel")
		l.Name = "Text"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		l.BackgroundTransparency = 0.05
		l.TextColor3 = Color3.fromRGB(20, 20, 28)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = l
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
		pad.Parent = l
	end
	gui.Text.Text = text
	gui.Enabled = true
	w.sayToken = (w.sayToken or 0) + 1
	local token = w.sayToken
	task.delay(2.5, function()
		if w.sayToken == token and gui.Parent then
			gui.Enabled = false
		end
	end)
end

-- The small "NAME · NPC" tag over the car (not on top of walls: a car's hollow stars stay hidden).
local function tagCar(chassis, name)
	local old = chassis:FindFirstChild("RacerName")
	if old then
		old:Destroy() -- (RaceAIService's racer name, drawn through walls)
	end
	local board = Instance.new("BillboardGui")
	board.Name = "BotTag"
	board.Size = UDim2.fromOffset(150, 22)
	board.StudsOffset = Vector3.new(0, 5, 0)
	board.MaxDistance = 90
	board.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextStrokeTransparency = 0.4
	label.Text = name .. " · NPC"
	label.Parent = board
	board.Adornee = chassis
	board.Parent = chassis
end

local function dropRider(bot)
	if bot.rider then
		bot.rider:Destroy()
		bot.rider = nil
	end
end

-- The bot posed in its car's driver's seat (no Humanoid: one welded into a car pushes it about).
local function mountRider(bot)
	dropRider(bot)
	local car = bot.drive and bot.drive.car
	local seat = car and car:FindFirstChild("DriverSeat")
	local template = S.looks[bot.look]
	if not seat or not template then
		return
	end
	local model = template:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:Destroy()
	end
	Instance.new("AnimationController").Parent = model
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	model:PivotTo(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + K.SEAT_UP, 0))
	local w = Instance.new("WeldConstraint")
	w.Part0 = seat
	w.Part1 = root
	w.Parent = root
	model.Name = "BotRider"
	model.Parent = car
	pcall(function()
		require(ServerStorage.Tools.CarBuilder).PlayPose(model, "sit")
	end)
	bot.rider = model
	setAttr(bot.rec, "OnFoot", nil)
	noteClues(bot)
end

-- Beside the car's driver's door, on the ground (PoliceOfficerService's doorSpot).
local function doorSpot(car)
	local chassis = car and car.PrimaryPart
	local seat = car and car:FindFirstChild("DriverSeat")
	if not chassis or not seat then
		return nil
	end
	local cf = chassis.CFrame
	local s = cf:PointToObjectSpace(seat.Position)
	local side = s.X >= 0 and 1 or -1
	local spot = cf * Vector3.new(side * (chassis.Size.X / 2 + 2.2), 0, s.Z)
	losParams.FilterDescendantsInstances = { car, S.bodyFolder }
	local hit = Workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), losParams)
	return Vector3.new(spot.X, hit and hit.Position.Y or (chassis.Position.Y - 2), spot.Z)
end

local function groundAt(pos, ignore)
	losParams.FilterDescendantsInstances = ignore or { S.bodyFolder }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -24, 0), losParams)
	return hit and hit.Position.Y or pos.Y
end

local function dropWalker(bot)
	local w = bot.walker
	if w then
		w.model:Destroy()
		bot.walker = nil
	end
end

local function loadTracks(w)
	local animator = w.hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = w.hum
	end
	w.tracks = {}
	for name, id in pairs(K.ANIM) do
		pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local t = animator:LoadAnimation(anim)
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Movement
			w.tracks[name] = t
		end)
	end
end

-- Idle / walk / run by how fast the body really goes (PoliceOfficerService's animate).
local function animate(w)
	local speed = flat(w.root.AssemblyLinearVelocity).Magnitude
	local want = speed < 0.6 and "idle" or (speed < 12 and "walk" or "run")
	if w.gait ~= want then
		if w.gait and w.tracks[w.gait] then
			w.tracks[w.gait]:Stop(0.2)
		end
		w.gait = want
		if w.tracks[want] then
			w.tracks[want]:Play(0.2)
		end
	end
	local t = w.tracks[want]
	if t and want ~= "idle" then
		t:AdjustSpeed(math.clamp(speed / (want == "run" and 18 or 8), 0.5, 1.6))
	end
end

local cuffBody -- (below: the Cuff prompt's hold on a body)
local holdBegan

-- The bot steps out as a walking body at `at` (feet on the ground), facing `toward`.
local function spawnWalker(bot, at, toward)
	dropWalker(bot)
	local template = S.looks[bot.look]
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
	hum.DisplayName = bot.name .. " · NPC"
	hum.WalkSpeed = K.WALK
	local y = at.Y + hum.HipHeight + root.Size.Y / 2
	local look = flat((toward or at) - at)
	local pos = Vector3.new(at.X, y, at.Z)
	model:PivotTo(CFrame.lookAt(pos, pos + (look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1))))
	model.Name = "RobberBot"
	model:SetAttribute(RobberBots.ATTR, bot.id)
	model.Parent = S.bodyFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local w = { model = model, hum = hum, root = root, gait = nil, moveGoal = nil, moveAt = 0, lastPos = root.Position, lastMoveAt = clock() }
	bot.walker = w
	loadTracks(w)
	ArrestService.BotCuffPrompt(root, bot.name, function(cop)
		return cuffBody(bot, w, cop)
	end, function(cop)
		holdBegan(bot, w, cop)
	end)
	hum.Died:Connect(function()
		if bot.walker == w then
			bot.dead = true -- (nothing should kill it; if something does, the bot simply goes)
		end
	end)
	setAttr(bot.rec, "OnFoot", true)
	noteClues(bot)
	return true
end

local function moveTo(w, pos, speed)
	w.hum.WalkSpeed = speed
	local t = clock()
	if not w.moveGoal or (w.moveGoal - pos).Magnitude > 2 or t - w.moveAt > 1.5 then
		w.moveGoal, w.moveAt = pos, t
		w.hum:MoveTo(pos)
	end
end

local function stopWalking(w)
	if w.moveGoal then
		w.moveGoal = nil
		w.hum:MoveTo(w.root.Position)
	end
end

local function face(w, pos)
	local look = flat(pos - w.root.Position)
	if look.Magnitude > 0.2 then
		local p = w.root.Position
		w.root.CFrame = CFrame.lookAt(p, p + look.Unit)
	end
end

-- Walk a path to `goal` (PathfindingService, worked out in the background; straight there while it's
-- being worked out or if there is none). Returns the flat distance left.
local function startPath(w, goal)
	w.path, w.pathI, w.pathGoal = nil, 1, goal
	local token = {}
	w.pathToken = token
	task.spawn(function()
		local ok, waypoints = pcall(function()
			local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
			path:ComputeAsync(w.root.Position, goal)
			if path.Status ~= Enum.PathStatus.Success then
				return nil
			end
			return path:GetWaypoints()
		end)
		if w.pathToken == token and ok and waypoints and #waypoints > 1 then
			w.path, w.pathI = waypoints, 2
		end
	end)
end

local function followPath(w, speed)
	local goal = w.pathGoal
	if not goal then
		return math.huge
	end
	local left = flatDist(w.root.Position, goal)
	local path = w.path
	local target = goal
	if path then
		while path[w.pathI] and flatDist(w.root.Position, path[w.pathI].Position) < 3 and w.pathI < #path do
			w.pathI += 1
		end
		local wp = path[w.pathI]
		if wp then
			target = wp.Position
			if wp.Action == Enum.PathWaypointAction.Jump then
				w.hum.Jump = true
			end
		end
	end
	moveTo(w, target, speed)
	-- Hardly moving while trying to: hop, and go straight for the goal (not right beside it: that hop put
	-- a bot on its own car's roof).
	local t = clock()
	if (w.root.Position - w.lastPos).Magnitude > 2 then
		w.lastPos, w.lastMoveAt = w.root.Position, t
	elseif t - w.lastMoveAt > 1.5 and left > 10 then
		w.lastMoveAt = t
		w.hum.Jump = true
		w.path = nil
		w.moveGoal = nil
	end
	return left
end

------------------------------------------------------------------ cars

local function newCar(cf, name)
	local d = RaceAIService.Spawn({
		CFrame = cf, Name = name, Legs = { { flat(cf.Position), flat(cf.Position + cf.LookVector * 50) } }, Lane = K.LANE,
		Top = K.TOP, Car = K.CARS[S.rng:NextInteger(1, #K.CARS)], Paint = K.PAINTS[S.rng:NextInteger(1, #K.PAINTS)],
	})
	if not d then
		return nil
	end
	d.car:SetAttribute("RaceBot", nil)
	d.car.Name = "RobberBotCar"
	tagCar(d.chassis, name)
	return d
end

-- Room for a car at `cf` (nothing a car would hit there: RaceAIService's roomAt).
local function carRoom(cf)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { S.bodyFolder }
	pcall(function()
		params.RespectCanCollide = true
	end)
	pcall(function()
		params.CollisionGroup = "Vehicles"
	end)
	return #Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.6, 0), Vector3.new(8, 4, 17), params) == 0
end

-- A car the bot no longer uses: it keeps standing there and goes once nobody's near (manage).
local function leaveCar(d)
	if not d then
		return
	end
	RaceAIService.Done(d)
	d.car:SetAttribute(RobberBots.ATTR, nil)
	local tag = d.chassis:FindFirstChild("BotTag")
	if tag then
		tag:Destroy()
	end
	table.insert(S.left, { drive = d, at = clock() })
end

local function planTo(bot, goal)
	local d = bot.drive
	if not d or not goal then
		return
	end
	local legs = RaceAIService.Plan(nil, d.chassis.Position, { goal })
	RaceAIService.Route(d, legs)
	bot.goal = flat(goal)
	bot.routeAt = clock()
end

local function reached(bot)
	local d = bot.drive
	return bot.goal == nil or (d and flatDist(d.chassis.Position, bot.goal) < K.GOAL_REACH)
end

------------------------------------------------------------------ states

local function setState(bot, state)
	bot.state = state
	bot.stateAt = clock()
end

local function since(bot)
	return clock() - bot.stateAt
end

local function clerkOf(site)
	local npcs = Workspace:FindFirstChild("NPCs")
	for _, m in ipairs(npcs and npcs:GetChildren() or {}) do
		if m:GetAttribute("NPCKind") == "Clerk" and m:GetAttribute("Site") == site.Name then
			return m
		end
	end
	return nil
end

local function clerkHandsDown(bot)
	local c = bot.crime
	if c and c.clerk and c.clerk.Parent and c.clerk:GetAttribute("Pose") == "HandsUp" then
		c.clerk:SetAttribute("Pose", nil)
	end
	if c then
		c.clerk = nil
	end
end

-- Which way a store's counter faces the shop floor (HeistService's counterFront), or nil.
local function counterFront(point)
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(point.Position, 14)) do
		if part.Name == "Counter" and part:IsA("BasePart") then
			local look = flat(part.CFrame.LookVector)
			if look.Magnitude > 0.5 then
				return look.Unit
			end
		end
	end
	return nil
end

-- Every site of a heist type with a RobPoint.
local function sitesOf(heistId)
	local list = {}
	local folder = Workspace:FindFirstChild("Heists")
	for _, site in ipairs(folder and folder:GetChildren() or {}) do
		if site:GetAttribute("HeistId") == heistId then
			local point = site:FindFirstChild("RobPoint", true)
			if point and point:IsA("BasePart") then
				table.insert(list, { site = site, point = point })
			end
		end
	end
	return list
end

-- A crime for this bot, or nil when none fits right now (see the header).
local function pickCrime(bot, copList)
	local pos = botPos(bot)
	if not pos then
		return nil
	end
	-- The rolled crime first, then the others (in case the rolled one has nowhere to happen right now).
	local total = 0
	for _, c in ipairs(K.CRIMES) do
		total += c.Weight
	end
	local roll = S.rng:NextNumber() * total
	local first
	for _, c in ipairs(K.CRIMES) do
		roll -= c.Weight
		if not first and roll <= 0 then
			first = c
		end
	end
	local order = { first or K.CRIMES[1] }
	for _, c in ipairs(K.CRIMES) do
		if c ~= order[1] then
			table.insert(order, c)
		end
	end
	for _, c in ipairs(order) do
		if c.Kind == "Heist" then
			local def = Heists.Types[c.Heist]
			local best, bestScore
			for _, s in ipairs(def and sitesOf(c.Heist) or {}) do
				local at = s.point.Position
				local d = flatDist(at, pos)
				if d >= K.SITE_MIN and d <= K.SITE_MAX and not civilianNear(at, K.CLEAR_RADIUS) then
					local _, copD = nearestCop(at, copList)
					local score = copD == math.huge and S.rng:NextNumber() or -math.abs(copD - K.COP_IDEAL)
					if not bestScore or score > bestScore then
						best, bestScore = s, score
					end
				end
			end
			if best then
				local front = counterFront(best.point)
				local park, roadDir = nearestRoadPoint(best.point.Position)
				if park then
					local toStreet = flat(park - best.point.Position)
					front = front or (toStreet.Magnitude > 0.5 and toStreet.Unit or Vector3.zAxis)
					local spot = best.point.Position + front * 3
					spot = Vector3.new(spot.X, groundAt(spot), spot.Z)
					return {
						kind = "Heist", heist = c.Heist, def = def, site = best.site, point = best.point, spot = spot,
						park = park, roadDir = roadDir, hold = def.Hold, heat = def.Heat,
						payout = S.rng:NextInteger(def.Payout[1], def.Payout[2]),
					}
				end
			end
		else
			-- Carjack: a parked street car somewhere nobody is looking.
			local node, i = pickNode(pos, 250, 900, function(n)
				if playerNear(Vector3.new(n.X, 3, n.Z), K.VANISH_CLEAR) then
					return nil
				end
				local _, copD = nearestCop(n, copList)
				return copD == math.huge and S.rng:NextNumber() or -math.abs(copD - K.COP_IDEAL)
			end)
			-- Halfway along a long enough road from that crossing, by the kerb on the right.
			local j
			for nb in pairs(node and RoadGraph.Edges[i] or {}) do
				local other = RoadGraph.Nodes[nb]
				if other and flatDist(other, node) > 90 and (not j or S.rng:NextNumber() < 0.5) then
					j = nb
				end
			end
			if node and j then
				local b = RoadGraph.Nodes[j]
				local dir = flat(b - node).Unit
				local p = node + (b - node) * 0.5
				local right = Vector3.new(-dir.Z, 0, dir.X)
				local width = RoadGraph.Width(i, j) or 0
				local kerb = math.max(K.LANE + 3, width / 2 - 4)
				local at = Vector3.new(p.X, K.SPAWN_Y, p.Z) + right * kerb
				local cf = CFrame.lookAt(at, at + dir)
				local victim = carRoom(cf) and newCar(cf, "Parked car")
				if victim then
					local tag = victim.chassis:FindFirstChild("BotTag")
					if tag then
						tag:Destroy() -- (a parked car, nobody's yet)
					end
					victim.car.Name = "ParkedCar"
					-- The bot pulls up in the lane a few car lengths behind it.
					return {
						kind = "Carjack", victim = victim, park = flat(at - dir * 26 - right * (kerb - K.LANE)),
						hold = K.JACK_HOLD, heat = 1, payout = 0,
					}
				end
			end
		end
	end
	return nil
end

local function dropCrime(bot)
	local c = bot.crime
	if not c then
		return
	end
	clerkHandsDown(bot)
	if c.victim and c.victim ~= bot.drive then
		leaveCar(c.victim) -- (goes once nobody's near: never vanishes in front of a cop)
	end
	bot.crime = nil
end

-- Out of the car as a walking body beside the driver's door; the car is told to stop.
local function getOut(bot, toward)
	local d = bot.drive
	if not d then
		return false
	end
	RaceAIService.Done(d)
	local at = doorSpot(d.car)
	dropRider(bot)
	return spawnWalker(bot, at, toward)
end

local function getIn(bot)
	dropWalker(bot)
	mountRider(bot)
end

-- A flee route: a crossing 400-900 studs off, away from the nearest cop.
local function planFlee(bot, copList)
	local pos = botPos(bot)
	if not pos then
		return
	end
	local cop = nearestCop(pos, copList)
	local away = cop and flat(pos - cop.root.Position)
	away = away and away.Magnitude > 1 and away.Unit or nil
	local goal = pickNode(pos, 400, 900, function(n)
		local dir = flat(n - pos)
		local s = S.rng:NextNumber() * 0.4
		if away and dir.Magnitude > 1 then
			s += dir.Unit:Dot(away)
		end
		return s
	end)
	if goal then
		planTo(bot, goal)
	end
end

-- A direction to run in on foot: away from `from`, turned a little either way until 20 studs are clear.
local function runDirection(w, from)
	local away = flat(w.root.Position - from)
	away = away.Magnitude > 0.5 and away.Unit or flat(w.root.CFrame.LookVector)
	losParams.FilterDescendantsInstances = { S.bodyFolder, Workspace:FindFirstChild("Vehicles") }
	for _, deg in ipairs({ 0, 30, -30, 60, -60, 90, -90, 135, -135 }) do
		local dir = CFrame.Angles(0, math.rad(deg), 0):VectorToWorldSpace(away)
		if not Workspace:Raycast(w.root.Position, dir * 20, losParams) then
			return dir
		end
	end
	return away
end

local function giveUp(bot, line)
	local w = bot.walker
	if not w then
		return
	end
	stopWalking(w)
	w.model:SetAttribute("Pose", "HandsUp")
	say(bot, line or "Okay, okay! I give up!")
	setState(bot, "Surrender")
end

local removeBot

-- Caught: the cop is paid, everyone hears, and the bot stands with its hands up a moment before it goes.
local function arrest(bot, cop)
	local stars = bot.heat
	local bounty = K.BOUNTY_STAR * stars + math.floor(bot.bag * K.BOUNTY_BAG)
	ArrestService.RewardCop(cop, bounty, stars, bot.name)
	pcall(function()
		require(ServerScriptService.Services.Telemetry).Custom(cop, "BotArrest", stars)
	end)
	S.feed:FireAllClients("Arrest", { Name = bot.name, Cop = cop.DisplayName })
	clearHeat(bot)
	dropCrime(bot)
	if not bot.walker then
		getOut(bot, cop.Character and cop.Character:GetPivot().Position)
	end
	local w = bot.walker
	if w then
		stopWalking(w)
		w.model:SetAttribute("Pose", "HandsUp")
		local prompt = w.root:FindFirstChild("CuffPrompt")
		if prompt then
			prompt:Destroy()
		end
		say(bot, "Aw man... busted!")
	end
	local slot = S.slots[bot.slot]
	if slot then
		slot.respawnAt = clock() + between(K.RESPAWN)
	end
	setState(bot, "Caught")
end

------------------------------------------------------------------ cuffs and taser (ArrestService)

local function botOfCar(car)
	for _, bot in pairs(S.bots) do
		if bot.drive and bot.drive.car == car then
			return bot
		end
	end
	return nil
end

local function botOfBody(model)
	for _, bot in pairs(S.bots) do
		if bot.walker and bot.walker.model == model then
			return bot
		end
	end
	return nil
end

local function stunned(bot)
	return (bot.stunUntil or 0) > clock()
end

-- The Cuff prompt on a bot's body (a full hold by a cop who can act: ArrestService checked that).
cuffBody = function(bot, w, cop)
	if bot.walker ~= w or bot.heat <= 0 or bot.state == "Caught" then
		return false
	end
	local copRoot = aliveRoot(cop)
	if not copRoot or (copRoot.Position - w.root.Position).Magnitude > K.CUFF_RANGE then
		return false
	end
	if not stunned(bot) and bot.state ~= "Surrender" and flat(w.root.AssemblyLinearVelocity).Magnitude >= K.STILL_FOOT then
		return false, "CuffTooFast"
	end
	arrest(bot, cop)
	return true
end

-- A cop starts holding the cuffs on it: sometimes it gives up right there.
holdBegan = function(bot, w, _cop)
	if bot.walker == w and bot.heat > 0 and not stunned(bot) and (bot.state == "OnFoot" or bot.state == "Crime")
		and S.rng:NextNumber() < K.GIVE_UP_CHANCE then
		giveUp(bot)
	end
end

function RobberBotService.CuffCar(cop, car)
	local bot = botOfCar(car)
	local seat = car:FindFirstChild("DriverSeat")
	if not bot or not bot.rider or bot.heat <= 0 or not seat or bot.state == "Caught" then
		return false
	end
	local copRoot = aliveRoot(cop)
	if not copRoot or (copRoot.Position - seat.Position).Magnitude > K.CUFF_RANGE then
		return false
	end
	local chassis = car.PrimaryPart
	if not chassis or chassis.AssemblyLinearVelocity.Magnitude >= K.STILL_CAR then
		return false, "CuffTooFast"
	end
	arrest(bot, cop)
	return true
end

function RobberBotService.CarWanted(car)
	local bot = botOfCar(car)
	return bot ~= nil and bot.rider ~= nil and bot.heat > 0
end

function RobberBotService.CanTase(model)
	local bot = botOfBody(model)
	return bot ~= nil and bot.heat > 0 and not stunned(bot) and bot.state ~= "Caught" and bot.walker.hum.Health > 0
end

function RobberBotService.Stun(model, seconds, _cop)
	local bot = botOfBody(model)
	if not bot then
		return
	end
	local w = bot.walker
	seconds = math.clamp(tonumber(seconds) or 3, 0.5, 6)
	bot.stunUntil = clock() + seconds
	stopWalking(w)
	w.model:SetAttribute("Pose", nil)
	local ok = pcall(function()
		require(ReplicatedStorage.Shared.Util.Ragdoll).Start(w.model, Vector3.new(0, 4, 0), { Seconds = seconds, NoCap = true })
	end)
	if not ok then
		w.hum.PlatformStand = true
		task.delay(seconds, function()
			if w.hum.Parent then
				w.hum.PlatformStand = false
			end
		end)
	end
	say(bot, "ZZZT!")
end

------------------------------------------------------------------ the brain

local function crimeAllowed(bot, copCount)
	if bot.leaving or copCount <= 0 then
		return false
	end
	if clock() - S.lastCrimeAt < (S.test and 5 or K.CRIME_GAP) then
		return false
	end
	local busy = 0
	for _, other in pairs(S.bots) do
		if other ~= bot and (other.heat > 0 or other.crime ~= nil) then
			busy += 1
		end
	end
	return busy < copCount and busy + realWanted() < K.MAX_BOTS
end

local function finishCrime(bot, share)
	local c = bot.crime
	if not c then
		return
	end
	local pay = math.floor(c.payout * share)
	if Workspace:GetAttribute("IsNight") then
		pay = math.floor(pay * 1.25)
	end
	bot.bag += pay
	clerkHandsDown(bot)
end

local function startCrime(bot)
	local c = bot.crime
	local w = bot.walker
	stopWalking(w)
	if c.kind == "Heist" then
		face(w, c.point.Position)
		local site = c.site
		-- The silent alarm, at once (players get a head start; bots give the cops theirs).
		if site.Parent then
			site:SetAttribute("AlarmUntil", serverNow() + Heists.AlarmSeconds)
			S.feed:FireAllClients("HeistAlarm", { Type = c.heist, Site = site.Name, Position = site:GetPivot().Position })
		end
		local clerk = clerkOf(site)
		if clerk and clerk:GetAttribute("Pose") == nil then
			clerk:SetAttribute("Pose", "HandsUp")
			c.clerk = clerk
		end
		say(bot, c.heist == "ATM" and "Come on, come on..." or "Hands up! Fill the bag!")
	else
		local victim = c.victim
		face(w, victim.chassis.Position)
		victim.car:SetAttribute("CarAlarmUntil", serverNow() + K.JACK_ALARM)
		S.feed:FireAllClients("BotCarjack", { Name = bot.name, Position = victim.chassis.Position })
		say(bot, "Nice ride...")
	end
	addHeat(bot, c.heat)
	bot.crimeEnds = clock() + c.hold
	setState(bot, "Crime")
end

-- The carjack done: the bot is in the stolen car, its old one left behind.
local function takeVictim(bot)
	local c = bot.crime
	local victim = c.victim
	c.victim = nil
	leaveCar(bot.drive)
	bot.drive = victim
	victim.car.Name = "RobberBotCar"
	victim.car:SetAttribute(RobberBots.ATTR, bot.id)
	victim.car:SetAttribute("CarAlarmUntil", nil)
	tagCar(victim.chassis, bot.name)
	RaceAIService.Release(victim)
	getIn(bot)
end

local ON_FOOT = { WalkIn = true, Crime = true, WalkBack = true, OnFoot = true, Surrender = true }
local DRIVING = { Cruise = true, Leave = true, ToCrime = true, Parking = true, Flee = true }

local function tickBot(bot, copList, copCount)
	local w = bot.walker
	local d = bot.drive
	local pos = botPos(bot)
	if bot.dead or not pos or (not w and (not d or not d.chassis.Parent or not d.car.Parent)) then
		removeBot(bot)
		return
	end
	if w then
		animate(w)
		if w.root.Position.Y < -20 then
			removeBot(bot) -- (fell out of the world)
			return
		end
	end
	if stunned(bot) then
		return
	end
	local cop, copD = nearestCop(pos, copList)
	local state = bot.state
	-- Each state's body: a walker on foot, the car to drive. Lost one somehow: carry on with what's there.
	if ON_FOOT[state] and not w then
		if d and d.car.Parent then
			mountRider(bot)
			setState(bot, bot.heat > 0 and "Flee" or "Cruise")
			bot.goal = nil
		else
			removeBot(bot)
		end
		return
	end
	if DRIVING[state] and (not d or not d.car.Parent) then
		if w then
			setState(bot, bot.heat > 0 and "OnFoot" or "Vanish")
		else
			removeBot(bot)
		end
		return
	end

	if state == "Cruise" or state == "Leave" then
		if d and reached(bot) then
			planTo(bot, pickNode(pos, 400, 1100))
		end
		if d then
			RaceAIService.SetPace(d, K.CRUISE_PACE)
		end
		if state == "Leave" then
			if not playerNear(pos, K.VANISH_CLEAR) then
				removeBot(bot)
			end
			return
		end
		if clock() >= bot.nextCrimeAt and crimeAllowed(bot, copCount) then
			local crime = pickCrime(bot, copList)
			if crime then
				bot.crime = crime
				S.lastCrimeAt = clock()
				setState(bot, "ToCrime")
				planTo(bot, crime.park)
			else
				bot.nextCrimeAt = clock() + 10
			end
		end
	elseif state == "ToCrime" then
		local c = bot.crime
		local stale = c.kind == "Heist" and civilianNear(c.point.Position, K.CLEAR_RADIUS)
		if stale or since(bot) > K.TO_CRIME_MAX or (c.victim and not c.victim.car.Parent) then
			dropCrime(bot)
			bot.nextCrimeAt = clock() + 20
			setState(bot, "Cruise")
			bot.goal = nil
			return
		end
		local toPark = flatDist(d.chassis.Position, c.park)
		RaceAIService.SetPace(d, toPark < 150 and 0.5 or K.CRUISE_PACE)
		if toPark < 30 or reached(bot) then
			RaceAIService.Done(d)
			setState(bot, "Parking")
		end
	elseif state == "Parking" then
		if d.chassis.AssemblyLinearVelocity.Magnitude < 2 or since(bot) > 4 then
			local c = bot.crime
			local spot = c.kind == "Heist" and c.spot or doorSpot(c.victim.car)
			if not spot or not getOut(bot, spot) then
				dropCrime(bot)
				bot.nextCrimeAt = clock() + 20
				setState(bot, "Cruise")
				bot.goal = nil
				return
			end
			c.walkTo = spot
			startPath(bot.walker, spot)
			setState(bot, "WalkIn")
		end
	elseif state == "WalkIn" then
		local c = bot.crime
		local left = followPath(w, K.WALK)
		if left < K.SPOT_REACH or (since(bot) > K.WALK_TIMEOUT and left < K.ROB_REACH) then
			startCrime(bot)
		elseif since(bot) > K.WALK_TIMEOUT then
			dropCrime(bot) -- (couldn't get there: no crime, back to the car)
			bot.nextCrimeAt = clock() + 20
			startPath(w, doorSpot(d.car) or pos)
			setState(bot, "WalkBack")
		elseif c.kind == "Carjack" and not c.victim.car.Parent then
			dropCrime(bot)
			startPath(w, doorSpot(d.car) or pos)
			setState(bot, "WalkBack")
		end
	elseif state == "Crime" then
		local c = bot.crime
		local spooked = cop and copD < K.COP_SPOOK * (cop.driving and 1.5 or 1)
		local share = math.clamp(1 - (bot.crimeEnds - clock()) / c.hold, 0, 1)
		if clock() >= bot.crimeEnds then
			finishCrime(bot, 1)
			if c.kind == "Carjack" then
				takeVictim(bot)
				bot.crime = nil
				setState(bot, "Flee")
				planFlee(bot, copList)
			else
				bot.crime = nil
				startPath(w, doorSpot(d.car) or pos)
				setState(bot, "WalkBack")
			end
		elseif spooked then
			-- A cop walked in: run with what it has (a taser hit ends it in afterStun).
			finishCrime(bot, c.kind == "Heist" and share or 0)
			dropCrime(bot)
			say(bot, "Cops! I'm outta here!")
			setState(bot, "OnFoot")
		end
	elseif state == "WalkBack" then
		local door = d and d.car.Parent and doorSpot(d.car)
		if not door then
			setState(bot, "OnFoot")
			return
		end
		if (w.pathGoal and (w.pathGoal - door).Magnitude > 6) or not w.pathGoal then
			startPath(w, door)
		end
		local left = followPath(w, bot.heat > 0 and K.RUN or K.WALK)
		-- At the car: anywhere beside it gets it in (from behind the car it used to bump it and hop on top).
		local seat = d.car:FindFirstChild("DriverSeat")
		local atCar = seat ~= nil and flatDist(w.root.Position, seat.Position) < K.BOARD_REACH
		if bot.heat > 0 and cop and copD < 40 and left > 25 and not atCar then
			setState(bot, "OnFoot") -- (a cop between it and the car: run)
		elseif left < 4 or atCar or (since(bot) > K.WALK_TIMEOUT and left < 40) then
			getIn(bot)
			if bot.heat > 0 then
				setState(bot, "Flee")
				planFlee(bot, copList)
			else
				setState(bot, "Cruise")
				bot.goal = nil
			end
		elseif since(bot) > K.WALK_TIMEOUT * 2 then
			setState(bot, bot.heat > 0 and "OnFoot" or "Vanish")
		end
	elseif state == "Flee" then
		if bot.heat <= 0 then
			bot.nextCrimeAt = clock() + between(K.NEXT_CRIME)
			setState(bot, "Cruise")
			bot.goal = nil
			return
		end
		local seen = bot.rec:GetAttribute("HeatSpotted") == true
		RaceAIService.SetPace(d, seen and 1 or K.LAY_LOW_PACE)
		if reached(bot) or (cop and copD < 250 and clock() - bot.routeAt > 4
			and bot.goal and (bot.goal - flat(pos)):Dot(flat(cop.root.Position - pos)) > 0) then
			planFlee(bot, copList)
		end
		-- Spiked with a cop close: maybe bail out (once per flat).
		local flatUntil = d.car:GetAttribute("FlatUntil")
		if type(flatUntil) == "number" and flatUntil > serverNow() and bot.flatSeen ~= flatUntil then
			bot.flatSeen = flatUntil
			if cop and copD < K.BAIL_RANGE and S.rng:NextNumber() < K.BAIL_CHANCE then
				getOut(bot, cop.root.Position)
				say(bot, "Forget the car!")
				setState(bot, "OnFoot")
				return
			end
		end
		-- Boxed in (hardly moving with a cop close): out and run.
		local t = clock()
		if not bot.stuckMark or (d.chassis.Position - bot.stuckMark).Magnitude > K.STUCK_MOVE or not cop or copD > K.STUCK_RANGE then
			bot.stuckMark, bot.stuckAt = d.chassis.Position, t
		elseif t - bot.stuckAt > K.STUCK_TIME then
			bot.stuckMark = nil
			getOut(bot, cop.root.Position)
			say(bot, "I'm out!")
			setState(bot, "OnFoot")
		end
	elseif state == "OnFoot" then
		if bot.heat <= 0 then
			local door = d and d.car.Parent and doorSpot(d.car)
			if door and flatDist(door, pos) < 200 then
				startPath(w, door)
				setState(bot, "WalkBack")
			else
				setState(bot, "Vanish")
			end
			return
		end
		local door = d and d.car.Parent and doorSpot(d.car)
		local carFlat = d and (d.car:GetAttribute("FlatUntil") or 0) > serverNow()
		if (not cop or copD > K.BACK_TO_CAR) and door and not carFlat and flatDist(door, pos) < 150 then
			startPath(w, door)
			setState(bot, "WalkBack")
			return
		end
		if cop and copD < K.GIVE_UP_NEAR and not cop.driving then
			if clock() - (bot.giveUpRollAt or 0) > 6 then
				bot.giveUpRollAt = clock()
				if S.rng:NextNumber() < K.GIVE_UP_CHANCE then
					giveUp(bot)
					return
				end
			end
		end
		local from = cop and cop.root.Position or bot.rec:GetAttribute("LastSeen") or (pos - w.root.CFrame.LookVector)
		if typeof(from) ~= "Vector3" then
			from = pos - w.root.CFrame.LookVector
		end
		local dir = runDirection(w, from)
		moveTo(w, w.root.Position + dir * 25, K.RUN)
		local t = clock()
		if (w.root.Position - w.lastPos).Magnitude > 2 then
			w.lastPos, w.lastMoveAt = w.root.Position, t
		elseif t - w.lastMoveAt > 1.2 then
			w.lastMoveAt = t
			w.hum.Jump = true
			w.moveGoal = nil
		end
	elseif state == "Surrender" then
		stopWalking(w)
		if bot.heat <= 0 then
			w.model:SetAttribute("Pose", nil)
			setState(bot, "OnFoot")
			return
		end
		if cop and copD < 60 then
			bot.lonelySince = nil
		else
			bot.lonelySince = bot.lonelySince or clock()
			if clock() - bot.lonelySince > K.GIVE_UP_LONELY then
				bot.lonelySince = nil
				w.model:SetAttribute("Pose", nil)
				setState(bot, "OnFoot")
			end
		end
	elseif state == "Caught" then
		if since(bot) > K.CAUGHT_SHOW then
			removeBot(bot)
		end
	elseif state == "Vanish" then
		if w then
			stopWalking(w)
		end
		if not playerNear(pos, K.VANISH_CLEAR) then
			removeBot(bot)
		end
	end
end

-- After a taser hit: up again, and often it gives up.
local function afterStun(bot)
	if bot.wasStunned and not stunned(bot) then
		bot.wasStunned = false
		-- Zapped at the till: the robbery ends with what it had taken so far (the clerk's hands come down).
		if bot.state == "Crime" and bot.crime then
			local c = bot.crime
			finishCrime(bot, c.kind == "Heist" and math.clamp(1 - (bot.crimeEnds - clock()) / c.hold, 0, 1) or 0)
			dropCrime(bot)
			setState(bot, "OnFoot")
		end
		if bot.walker and bot.heat > 0 and bot.state ~= "Caught" then
			if S.rng:NextNumber() < K.TASED_GIVE_UP then
				giveUp(bot, "Ow! Okay, okay!")
			elseif bot.state ~= "Surrender" then
				setState(bot, "OnFoot")
			end
		end
	elseif stunned(bot) then
		bot.wasStunned = true
	end
end

------------------------------------------------------------------ seen or not (HeatService's rules)

local function canSee(fromPos, target, ignore)
	local to = target.Position - fromPos
	if to.Magnitude > K.SIGHT then
		return false
	end
	losParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(fromPos, to, losParams)
	return hit == nil or hit.Instance:IsDescendantOf(target.Parent)
end

local function sightTick(copList)
	local ignore = { Workspace:FindFirstChild("Vehicles"), S.bodyFolder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local alarms = {}
	local folder = Workspace:FindFirstChild("Heists")
	for _, site in ipairs(folder and folder:GetChildren() or {}) do
		if serverNow() < (site:GetAttribute("AlarmUntil") or 0) then
			table.insert(alarms, site:GetPivot().Position)
		end
	end
	local t = clock()
	for _, bot in pairs(S.bots) do
		local target = (bot.walker and bot.walker.root) or (bot.drive and bot.drive.chassis)
		if bot.heat > 0 and target and target.Parent and bot.state ~= "Caught" then
			local spotted = false
			for _, c in ipairs(copList) do
				if canSee(c.root.Position + Vector3.new(0, 2, 0), target, ignore) then
					spotted = true
					break
				end
			end
			if not spotted then
				for _, at in ipairs(alarms) do
					if (target.Position - at).Magnitude < K.HOT_ZONE then
						spotted = true
						break
					end
				end
			end
			if spotted then
				bot.lastSeenAt = t
				setAttr(bot.rec, "LastSeen", target.Position)
				setAttr(bot.rec, "HeatSpotted", true)
				noteClues(bot)
			else
				bot.lastSeenAt = bot.lastSeenAt or t
				local unseen = t - bot.lastSeenAt
				if unseen > K.HOLLOW then
					setAttr(bot.rec, "HeatSpotted", false)
				end
				-- A witness calls it in: the search circle moves to where it is (it stays hollow).
				if unseen > K.HOLLOW and t - math.max(bot.lastSeenAt, bot.pingAt or 0) > K.PING_EVERY then
					bot.pingAt = t
					setAttr(bot.rec, "LastSeen", target.Position)
				end
				if unseen > K.ESCAPE_BASE + K.ESCAPE_PER * bot.heat then
					clearHeat(bot)
					S.feed:FireAllClients("Escaped", { Name = bot.name })
				end
			end
		end
	end
end

------------------------------------------------------------------ coming and going

local function usedNames()
	local used = {}
	for _, bot in pairs(S.bots) do
		used[bot.name] = true
	end
	return used
end

removeBot = function(bot)
	if S.bots[bot.id] ~= bot then
		return
	end
	S.bots[bot.id] = nil
	dropCrime(bot)
	dropWalker(bot)
	dropRider(bot)
	if bot.drive then
		leaveCar(bot.drive)
		bot.drive = nil
	end
	if bot.rec then
		bot.rec:Destroy()
	end
	local slot = S.slots[bot.slot]
	if slot and bot.state ~= "Caught" then
		slot.respawnAt = math.max(slot.respawnAt or 0, clock() + (S.test and 3 or 20))
	end
end

-- A new bot in this slot, on a road out of every player's sight (nil if there's nowhere right now).
local function spawnBot(slot, copList)
	if #S.looks == 0 or #RoadGraph.Nodes == 0 then
		return nil
	end
	local start = pickNode(Vector3.zero, 0, math.huge, function(n)
		local here = Vector3.new(n.X, 0, n.Z)
		if playerNear(here + Vector3.new(0, 3, 0), K.SPAWN_AWAY) then
			return nil
		end
		local _, copD = nearestCop(here, copList)
		if copD ~= math.huge and copD > K.SPAWN_NEAR_COP then
			return nil
		end
		return copD == math.huge and S.rng:NextNumber() or -math.abs(copD - 800)
	end)
	if not start then
		return nil
	end
	local p, dir = nearestRoadPoint(start)
	if not p or not dir then
		return nil
	end
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local at = Vector3.new(p.X, K.SPAWN_Y, p.Z) + right * K.LANE
	local names = {}
	local used = usedNames()
	for _, n in ipairs(K.NAMES) do
		if not used[n] then
			table.insert(names, n)
		end
	end
	local name = names[S.rng:NextInteger(1, math.max(1, #names))] or "Robber"
	local d = newCar(CFrame.lookAt(at, at + dir), name)
	if not d then
		return nil
	end
	local id = "Bot" .. slot
	d.car:SetAttribute(RobberBots.ATTR, id)
	RaceAIService.Release(d)
	RaceAIService.SetPace(d, K.CRUISE_PACE)
	local look = S.rng:NextInteger(1, #S.looks)
	local rec = Instance.new("Configuration")
	rec.Name = id
	rec:SetAttribute("DisplayName", name)
	rec.Parent = S.recFolder
	local bot = {
		id = id, slot = slot, name = name, look = look, outfit = S.looks[look]:GetAttribute("Outfit") or "dark hoodie",
		rec = rec, drive = d, heat = 0, bag = 0, state = "Cruise", stateAt = clock(), goal = nil, routeAt = 0,
		nextCrimeAt = clock() + between(K.FIRST_CRIME),
	}
	S.bots[id] = bot
	mountRider(bot)
	return bot
end

-- Once a second: how many bots there should be, the cars they left, the stand-down when nobody is a cop.
local function manage(copList)
	local copCount = activeCopCount()
	if copCount > 0 then
		S.noCopSince = nil
	elseif not S.noCopSince then
		S.noCopSince = clock()
	end
	local want = copCount > 0 and math.max(0, K.MAX_BOTS - realWanted()) or 0
	local live, idle, leaving = 0, {}, {}
	for _, bot in pairs(S.bots) do
		if bot.state == "Leave" then
			table.insert(leaving, bot)
		elseif bot.state ~= "Vanish" and bot.state ~= "Caught" then
			live += 1
			if bot.state == "Cruise" and bot.heat <= 0 and not bot.crime then
				table.insert(idle, bot)
			end
		end
	end
	for _, bot in ipairs(leaving) do
		if live < want then
			bot.leaving = false
			setState(bot, "Cruise") -- (needed again after all)
			live += 1
		end
	end
	-- Too many: idle ones drive off (straight away for a real robber; after a while with no cop at all).
	local noCopLong = S.noCopSince ~= nil and clock() - S.noCopSince > (S.test and 5 or K.NO_COP_LEAVE)
	if live > want and (copCount > 0 or noCopLong) then
		for _, bot in ipairs(idle) do
			if live <= want then
				break
			end
			bot.leaving = true
			setState(bot, "Leave")
			live -= 1
		end
	end
	-- Too few: one new bot per pass, in a free slot whose wait is over.
	if live < want then
		for slot = 1, K.MAX_BOTS do
			S.slots[slot] = S.slots[slot] or { respawnAt = 0 }
			local taken = S.bots["Bot" .. slot] ~= nil
			if not taken and clock() >= S.slots[slot].respawnAt then
				if spawnBot(slot, copList) then
					break
				end
			end
		end
	end
	-- Cars bots left behind go once nobody is near (or after CAR_LEFT anyway).
	for i = #S.left, 1, -1 do
		local e = S.left[i]
		local chassis = e.drive.chassis
		if not chassis.Parent or not playerNear(chassis.Position, 150) or clock() - e.at > K.CAR_LEFT then
			RaceAIService.Remove(e.drive)
			table.remove(S.left, i)
		end
	end
end

------------------------------------------------------------------ Studio tests

function RobberBotService.Status()
	local lines = { "test=" .. tostring(S.test) .. " cops=" .. activeCopCount() .. " realWanted=" .. realWanted() }
	for id, bot in pairs(S.bots) do
		local pos = botPos(bot)
		table.insert(lines, string.format("%s %s state=%s heat=%d bag=%d spotted=%s crime=%s pos=%s", id, bot.name, bot.state,
			bot.heat, bot.bag, tostring(bot.rec:GetAttribute("HeatSpotted")), bot.crime and (bot.crime.heist or bot.crime.kind) or "-",
			pos and string.format("%.0f,%.0f", pos.X, pos.Z) or "?"))
	end
	return table.concat(lines, " | ")
end

-- The live bot tables, read-only, for a Studio test script to follow (never used by the game).
function RobberBotService.Peek()
	return S.bots
end

function RobberBotService.Test(on)
	S.test = on == true
	return RobberBotService.Status()
end

-- A crime as soon as one fits (the first idle bot, or bot `id`).
function RobberBotService.Crime(id)
	for bid, bot in pairs(S.bots) do
		if (id == nil or bid == id) and bot.state == "Cruise" then
			bot.nextCrimeAt = 0
			S.lastCrimeAt = -math.huge
			return bid
		end
	end
	return nil
end

------------------------------------------------------------------ start

function RobberBotService.Init()
	S.feed = Remotes.Event("Feed")
	S.recFolder = ReplicatedStorage:FindFirstChild(RobberBots.FOLDER) or Instance.new("Folder")
	S.recFolder.Name = RobberBots.FOLDER
	S.recFolder.Parent = ReplicatedStorage
	S.bodyFolder = Workspace:FindFirstChild(RobberBots.FOLDER) or Instance.new("Folder")
	S.bodyFolder.Name = RobberBots.FOLDER
	S.bodyFolder.Parent = Workspace
	task.spawn(buildLooks)
	task.spawn(function()
		local lastSight, lastManage = 0, 0
		while true do
			task.wait(K.TICK)
			local ok, err = pcall(function()
				local copList = cops()
				local t = clock()
				if t - lastManage >= K.MANAGE_EVERY then
					lastManage = t
					manage(copList)
				end
				if t - lastSight >= K.SIGHT_EVERY then
					lastSight = t
					sightTick(copList)
				end
				local copCount = activeCopCount()
				for _, bot in pairs(S.bots) do
					local okBot, errBot = pcall(function()
						afterStun(bot)
						tickBot(bot, copList, copCount)
					end)
					if not okBot then
						warn("[RobberBotService] " .. tostring(bot.id) .. " (" .. tostring(bot.state) .. "): " .. tostring(errBot))
						pcall(removeBot, bot)
					end
				end
			end)
			if not ok then
				warn("[RobberBotService] " .. tostring(err))
			end
		end
	end)
end

return RobberBotService
