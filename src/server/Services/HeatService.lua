-- HeatService (ModuleScript, ServerScriptService.Services.HeatService)
-- The wanted system, GTA 6 style: cops only know what they've seen. Tunables: Config.Police.
--   Heat 1-5 (player attribute "Heat") comes from crimes; only citizens get heat.
--   Eyes: player cops, AI police cars and roadblocks (RegisterEye). A suspect is seen when an eye within
--     250 studs has a clear line of sight (cars and characters never block it; walls and smoke do), or
--     near a heist site with a live alarm. While seen: HeatSpotted = true and LastSeen follows them.
--   Unseen for 8 s -> hollow stars (HeatSpotted = false): the police only know the search circle around
--     LastSeen (attributes SearchX, SearchZ, SearchR). The escape countdown runs (attributes EscapeEnd =
--     server time the stars clear if they stay unseen, EscapeTotal = the full window at the current
--     rate, so (EscapeEnd - now) / EscapeTotal is the bar's fill). It runs twice as fast outside the
--     circle. At 0: heat gone ("You lost the cops!"). All five attributes are nil while spotted.
--   At 4+ stars the helicopter re-centres the circle on them every 20 s while hollow (not "seen").
--   Crimes found here: ramming a police car (+1, 20 s cooldown; hits confirmed by our own check or
--     VehicleDamageService.CarHit) and evading (+1 per 60 s of continuous seen-and-moving chase, up to
--     4 stars). Neither applies to a TutorialChase player.
-- Bounty for arresting someone = $500 per star + 25% of their carried cash.
-- API for other services:
--   Add(player, amount, reason)     a crime was seen: more heat, and it counts as a sighting
--   Reduce(player, amount, reason)  Clear(player, reason)   GetHeat(player)   Bounty(player)
--   IsSeen(player) -> bool          an eye sees them right now (or a crime just happened)
--   LastSeenPos(player) -> Vector3? the spot the police know about
--   LastSeenAgo(player) -> seconds since any eye saw them (math.huge if never)
--   SeenAgo(player, who) -> seconds since `who` (a cop Player or an eye BasePart) saw them
--   SearchArea(player) -> center, radius while hollow (nil while spotted)
--   EngagedCops(player) -> count, { cops } near them (400 studs) or who saw them in the last 20 s
--   Ping(player, pos) -> a tip-off (tracker, helicopter): moves LastSeen without counting as seen
--   RegisterEye(part) / UnregisterEye(part)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Disguises = require(ReplicatedStorage.Shared.Config.Disguises)
local Police = require(ReplicatedStorage.Shared.Config.Police)

local HeatService = {}

-- Suspect Card (attributes on the wanted player, shown to cops):
--   SuspectOutfit - their look (hat + mask) when a camera or cop last saw them on foot
--   SuspectCar    - their car and its colour when a cop last saw them driving
-- Changing the look at a wardrobe or respraying the car while unseen clears that clue (DisguiseService).
local COLOR_WORDS = {
	{ "pink", Color3.fromRGB(255, 62, 165) }, { "cyan", Color3.fromRGB(34, 225, 255) },
	{ "purple", Color3.fromRGB(123, 47, 255) }, { "orange", Color3.fromRGB(255, 138, 61) },
	{ "yellow", Color3.fromRGB(255, 214, 10) }, { "mint", Color3.fromRGB(110, 242, 196) },
	{ "white", Color3.fromRGB(240, 240, 245) }, { "black", Color3.fromRGB(22, 22, 28) },
	{ "grey", Color3.fromRGB(128, 128, 136) }, { "red", Color3.fromRGB(220, 40, 50) },
	{ "blue", Color3.fromRGB(40, 70, 200) }, { "green", Color3.fromRGB(70, 150, 70) },
}
function HeatService.ColorWord(c)
	local best, bestD = "grey", math.huge
	for _, w in ipairs(COLOR_WORDS) do
		local o = w[2]
		local d = (c.R - o.R) ^ 2 + (c.G - o.G) ^ 2 + (c.B - o.B) ^ 2
		if d < bestD then
			best, bestD = w[1], d
		end
	end
	return best
end

function HeatService.LookOf(player)
	return Disguises.Describe(player:GetAttribute("LookHat"), player:GetAttribute("LookMask"))
end

local function noteClues(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local car = hum and hum.SeatPart and hum.SeatPart.Parent
	if car and car.PrimaryPart and car:GetAttribute("NCVehicle") then
		local text = (car:GetAttribute("DisplayName") or car.Name) .. " (" .. HeatService.ColorWord(car.PrimaryPart.Color) .. ")"
		if player:GetAttribute("SuspectCar") ~= text then
			player:SetAttribute("SuspectCar", text)
		end
	else
		local look = HeatService.LookOf(player)
		if player:GetAttribute("SuspectOutfit") ~= look then
			player:SetAttribute("SuspectOutfit", look)
		end
	end
end

local SIGHT_RANGE = Police.SightRange
local HOLLOW_AFTER = Police.HollowAfter
local HOT_ZONE = 60
local CHECK_EVERY = 0.4
local SEEN_FRESH = CHECK_EVERY * 1.5 + 0.1 -- IsSeen: a sighting this recent counts as "now"
local RAM_EVERY = 0.1

local lastSeenAt = {} -- [player] = os.clock() of the last sighting (or crime)
local lastSeenPos = {} -- [player] = Vector3 the police know about
local written = {} -- [player] = the LastSeen value this service last wrote (to spot outside pings)
local lastPing = {} -- [player] = os.clock()
local escapeLeft = {} -- [player] = seconds of unseen countdown left (at the inside-the-circle rate)
local chaseFor = {} -- [player] = seconds of continuous seen-and-moving chase (evading)
local ramAt = {} -- [player] = os.clock() of their last ramming crime
local sightings = {} -- [player] = { [cop Player or eye BasePart] = os.clock() } (weak keys)
local eyes = {} -- [BasePart] = true: extra eyes (AI police cars, roadblocks)

local notify, feed

local function now()
	return Workspace:GetServerTimeNow()
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function setAttr(player, key, value)
	if player:GetAttribute(key) ~= value then
		player:SetAttribute(key, value)
	end
end

local function clearEscape(player)
	escapeLeft[player] = nil
	for _, key in ipairs({ "EscapeEnd", "EscapeTotal", "SearchX", "SearchZ", "SearchR" }) do
		setAttr(player, key, nil)
	end
end

local function forget(player)
	lastSeenAt[player] = nil
	lastSeenPos[player] = nil
	written[player] = nil
	lastPing[player] = nil
	escapeLeft[player] = nil
	chaseFor[player] = nil
	sightings[player] = nil
end

local function progress()
	return require(ServerScriptService.Services.ProgressService)
end

function HeatService.GetHeat(player)
	return player:GetAttribute("Heat") or 0
end

function HeatService.Bounty(player)
	return 500 * HeatService.GetHeat(player) + math.floor((player:GetAttribute("Carried") or 0) * 0.25)
end

local function setLastSeen(player, pos)
	lastSeenPos[player] = pos
	written[player] = pos
	setAttr(player, "LastSeen", pos)
end

-- Someone saw them (an eye, a camera, a witness): solid stars, the escape countdown stops.
local function markSeen(player, root, clock)
	lastSeenAt[player] = clock
	if root then
		setLastSeen(player, root.Position)
	end
	noteClues(player)
	setAttr(player, "HeatSpotted", true)
	clearEscape(player)
end

-- A crime was seen (store camera, witness, a cop car rammed): add heat and mark where it happened.
function HeatService.Add(player, amount, reason)
	if player:GetAttribute("Side") ~= "Civilian" then
		return
	end
	local heat = math.clamp(HeatService.GetHeat(player) + amount, 0, 5)
	player:SetAttribute("Heat", heat)
	player:SetAttribute("HeatReason", reason)
	if heat > 0 then
		markSeen(player, rootOf(player), os.clock())
	end
end

function HeatService.Clear(player, reason)
	player:SetAttribute("Heat", 0)
	player:SetAttribute("HeatSpotted", false)
	player:SetAttribute("LastSeen", nil)
	player:SetAttribute("SuspectOutfit", nil)
	player:SetAttribute("SuspectCar", nil)
	clearEscape(player)
	forget(player)
end

-- Drop some heat (disguise change, respray). Reaching 0 counts as losing the cops.
function HeatService.Reduce(player, amount, reason)
	local before = HeatService.GetHeat(player)
	local heat = math.max(0, before - amount)
	if heat == 0 then
		if before > 0 then
			progress().Event(player, "Escape", before)
		end
		HeatService.Clear(player, reason)
		notify:FireClient(player, "LostTheCops")
	else
		player:SetAttribute("Heat", heat)
		if escapeLeft[player] then
			escapeLeft[player] = math.min(escapeLeft[player], Police.EscapeWindow(heat))
		end
	end
end

-- A tip-off (GPS tracker, helicopter): the police learn where they are, but nobody "sees" them.
function HeatService.Ping(player, pos)
	if HeatService.GetHeat(player) > 0 and typeof(pos) == "Vector3" then
		setLastSeen(player, pos)
	end
end

function HeatService.RegisterEye(part)
	eyes[part] = true
end

function HeatService.UnregisterEye(part)
	eyes[part] = nil
end

function HeatService.IsSeen(player)
	local t = lastSeenAt[player]
	return t ~= nil and os.clock() - t <= SEEN_FRESH
end

function HeatService.LastSeenPos(player)
	return lastSeenPos[player]
end

function HeatService.LastSeenAgo(player)
	local t = lastSeenAt[player]
	return t and os.clock() - t or math.huge
end

function HeatService.SeenAgo(player, who)
	local list = sightings[player]
	local t = list and list[who]
	return t and os.clock() - t or math.huge
end

function HeatService.SearchArea(player)
	local heat = HeatService.GetHeat(player)
	local center = lastSeenPos[player]
	if heat <= 0 or not center or player:GetAttribute("HeatSpotted") then
		return nil, nil
	end
	return center, Police.SearchRadius(heat)
end

function HeatService.EngagedCops(player)
	local list = {}
	local root = rootOf(player)
	for _, cop in ipairs(Players:GetPlayers()) do
		if cop ~= player and cop:GetAttribute("Side") == "Cop" then
			local copRoot = rootOf(cop)
			local near = root and copRoot and (copRoot.Position - root.Position).Magnitude <= Police.EngageRange
			if near or HeatService.SeenAgo(player, cop) <= Police.EngageMemory then
				table.insert(list, cop)
			end
		end
	end
	return #list, list
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

local function canSee(fromPos, target)
	local toTarget = target.Position - fromPos
	if toTarget.Magnitude > SIGHT_RANGE then
		return false
	end
	local hit = Workspace:Raycast(fromPos, toTarget, losParams)
	return hit == nil or hit.Instance:IsDescendantOf(target.Parent)
end

local function escaped(player, heat)
	progress().Event(player, "Escape", heat)
	HeatService.Clear(player, "escaped")
	notify:FireClient(player, "LostTheCops")
	player:SetAttribute("Evasions", (player:GetAttribute("Evasions") or 0) + 1)
	feed:FireAllClients("Escaped", { Name = player.DisplayName })
end

local function tick(dt)
	-- Everything that isn't a wall: characters, cars and roadblock cars never block sight.
	local exclude = {}
	for _, name in ipairs({ "Vehicles", "Roadblocks" }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	local copEyes = {} -- { pos, who }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(exclude, p.Character)
		end
		if p:GetAttribute("Side") == "Cop" then
			local root = rootOf(p)
			if root then
				table.insert(copEyes, { pos = root.Position + Vector3.new(0, 2, 0), who = p })
			end
		end
	end
	for part in pairs(eyes) do
		if part.Parent then
			table.insert(copEyes, { pos = part.Position + Vector3.new(0, 3, 0), who = part })
		else
			eyes[part] = nil
		end
	end
	losParams.FilterDescendantsInstances = exclude

	local alarms = {}
	local heists = Workspace:FindFirstChild("Heists")
	for _, site in ipairs(heists and heists:GetChildren() or {}) do
		if now() < (site:GetAttribute("AlarmUntil") or 0) then
			table.insert(alarms, site:GetPivot().Position)
		end
	end

	local clock = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local heat = HeatService.GetHeat(player)
		if heat > 0 and player:GetAttribute("Side") ~= "Civilian" then
			HeatService.Clear(player, "role")
			continue
		end
		if heat <= 0 then
			if lastSeenAt[player] or player:GetAttribute("EscapeEnd") or player:GetAttribute("SearchR") then
				clearEscape(player)
				forget(player) -- heat dropped to 0 somewhere else
			end
			continue
		end
		local root = rootOf(player)
		if not root then
			continue -- dead or respawning: the clocks wait
		end
		local pos = root.Position
		-- Someone else moved LastSeen (a car tracker): that's the new search centre.
		local attr = player:GetAttribute("LastSeen")
		if typeof(attr) == "Vector3" and attr ~= written[player] then
			lastSeenPos[player] = attr
			written[player] = attr
		end

		local seen = false
		local saw = sightings[player]
		for _, eye in ipairs(copEyes) do
			if eye.who ~= player and canSee(eye.pos, root) then
				if not saw then
					saw = setmetatable({}, { __mode = "k" })
					sightings[player] = saw
				end
				saw[eye.who] = clock
				seen = true
			end
		end
		if not seen then
			for _, at in ipairs(alarms) do
				if (pos - at).Magnitude < HOT_ZONE then
					seen = true
					break
				end
			end
		end

		local tutorial = player:GetAttribute("TutorialChase") == true
		if seen then
			markSeen(player, root, clock)
			-- Evading: every minute of continuous chase on the move is another star (up to 4).
			local v = root.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > Police.EvadeMinSpeed then
				chaseFor[player] = (chaseFor[player] or 0) + dt
				if chaseFor[player] >= Police.EvadeSeconds then
					chaseFor[player] = 0
					if heat < Police.EvadeMaxStars and not tutorial then
						HeatService.Add(player, 1, "evading")
						notify:FireClient(player, "EvadingArrest")
					end
				end
			end
		else
			local since = clock - (lastSeenAt[player] or clock)
			if not lastSeenAt[player] then
				lastSeenAt[player] = clock -- heat set without a sighting: start counting from now
			end
			if player:GetAttribute("HeatSpotted") and since > HOLLOW_AFTER then
				player:SetAttribute("HeatSpotted", false)
				chaseFor[player] = nil
				lastPing[player] = clock
			end
			if not player:GetAttribute("HeatSpotted") then
				-- The helicopter: at 4+ stars it finds them again every 20 s (a tip-off, not a sighting).
				lastPing[player] = lastPing[player] or clock
				if heat >= Police.PingStars and not tutorial and clock - lastPing[player] > Police.PingEvery then
					lastPing[player] = clock
					setLastSeen(player, pos)
				end
				local window = Police.EscapeWindow(heat)
				local left = math.min(escapeLeft[player] or window, window)
				local center = lastSeenPos[player] or pos
				local radius = Police.SearchRadius(heat)
				local outside = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z).Magnitude > radius
				local rate = outside and Police.OutsideRate or 1
				left -= dt * rate
				if left <= 0 then
					escaped(player, heat)
				else
					escapeLeft[player] = left
					local finish = now() + left / rate
					local shown = player:GetAttribute("EscapeEnd")
					if typeof(shown) ~= "number" or math.abs(shown - finish) > 0.25 then
						player:SetAttribute("EscapeEnd", finish)
					end
					setAttr(player, "EscapeTotal", window / rate)
					setAttr(player, "SearchX", math.floor(center.X + 0.5))
					setAttr(player, "SearchZ", math.floor(center.Z + 0.5))
					setAttr(player, "SearchR", radius)
				end
			end
		end
	end
end

-- Ramming: a civilian's car driving into a police car (AI, or with a cop at the wheel). Two sources,
-- both judged on the velocities from before the hit (who was moving into whom):
--   * VehicleDamageService.CarHit (when that service exists): a confirmed car-on-car hit.
--   * Our own 10 Hz check: the cars touching now and their closing speed (along the same line) dropping
--     hard, so near misses don't count.
-- The 20 s cooldown per player keeps the two from counting one hit twice.
local carHist = setmetatable({}, { __mode = "k" }) -- [car] = up to 3 samples { pos, vel, clock }, newest first

-- Pure maths (testable): did the civilian drive into the cop fast enough? (positions/velocities before)
function HeatService._RamBlame(civPos0, civVel0, copPos0, copVel0)
	local rel = Vector3.new(copPos0.X - civPos0.X, 0, copPos0.Z - civPos0.Z)
	if rel.Magnitude < 0.1 then
		return false, 0
	end
	local n = rel.Unit
	local civIn = civVel0:Dot(n) -- the civilian moving at the cop
	local copIn = -copVel0:Dot(n) -- the cop moving at the civilian
	local closing = civIn + copIn
	return closing >= Police.RamSpeed and civIn >= copIn, closing
end

-- The same plus the hit itself: their closing speed along that line dropped hard.
function HeatService._RamCheck(civPos0, civVel0, copPos0, copVel0, civVel1, copVel1)
	local blame, closing = HeatService._RamBlame(civPos0, civVel0, copPos0, copVel0)
	if not blame then
		return false
	end
	local rel = Vector3.new(copPos0.X - civPos0.X, 0, copPos0.Z - civPos0.Z)
	local n = rel.Unit
	local after = civVel1:Dot(n) - copVel1:Dot(n)
	return after < closing * 0.5
end

local function isCopCar(car)
	return car:GetAttribute("Police") == true and (car:GetAttribute("AIPolice") == true or car:GetAttribute("DriverUserId") ~= nil)
end

-- The civilian at the wheel (not a tutorial chase), if any.
local function civDriver(car)
	if car:GetAttribute("Police") == true then
		return nil
	end
	local id = car:GetAttribute("DriverUserId")
	local p = id and Players:GetPlayerByUserId(id)
	if p and p:GetAttribute("Side") == "Civilian" and p:GetAttribute("TutorialChase") ~= true then
		return p
	end
	return nil
end

local function canRam(driver)
	return os.clock() - (ramAt[driver] or -math.huge) > Police.RamCooldown
end

local function rammed(driver)
	ramAt[driver] = os.clock()
	HeatService.Add(driver, 1, "ramming")
	notify:FireClient(driver, "RammedCop")
end

local function sampleBefore(car, t)
	for _, sample in ipairs(carHist[car] or {}) do
		if sample.clock <= t then
			return sample
		end
	end
	return nil
end

local function onCarHit(car, other)
	if typeof(car) ~= "Instance" or typeof(other) ~= "Instance" or not car:IsA("Model") or not other:IsA("Model") then
		return
	end
	local driver = civDriver(car)
	if not driver or not isCopCar(other) or not canRam(driver) then
		return
	end
	-- The hit happened within the last damage sample (1/12 s): judge on samples from before it.
	local clock = os.clock()
	local a, b = sampleBefore(car, clock - 0.12), sampleBefore(other, clock - 0.12)
	if a and b and clock - a.clock < 0.5 and clock - b.clock < 0.5 and HeatService._RamBlame(a.pos, a.vel, b.pos, b.vel) then
		rammed(driver)
	end
end

local function ramTick()
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	local clock = os.clock()
	local cops, civs = {}, {}
	for _, car in ipairs(folder:GetChildren()) do
		if car:IsA("Model") and car.PrimaryPart then
			if isCopCar(car) then
				table.insert(cops, car)
			elseif car:GetAttribute("Police") ~= true and car:GetAttribute("DriverUserId") ~= nil then
				table.insert(civs, car)
			end
		end
	end
	if #cops > 0 then
		for _, civ in ipairs(civs) do
			local chassis = civ.PrimaryPart
			local hist = carHist[civ]
			local prev = hist and hist[1]
			local driver = civDriver(civ)
			if chassis and prev and clock - prev.clock < 0.3 and driver and canRam(driver) then
				for _, cop in ipairs(cops) do
					local copChassis = cop.PrimaryPart
					local copHist = carHist[cop]
					local copPrev = copHist and copHist[1]
					if copChassis and copPrev and clock - copPrev.clock < 0.3 then
						-- Touching now? (the civilian's centre within a car length of the cop's box)
						local rel = copChassis.CFrame:PointToObjectSpace(chassis.Position)
						local reach = chassis.Size.Z / 2 + 1.5
						if math.abs(rel.X) <= copChassis.Size.X / 2 + reach and math.abs(rel.Z) <= copChassis.Size.Z / 2 + reach
							and math.abs(rel.Y) < 8
							and HeatService._RamCheck(prev.pos, prev.vel, copPrev.pos, copPrev.vel, chassis.AssemblyLinearVelocity,
								copChassis.AssemblyLinearVelocity) then
							rammed(driver)
							break
						end
					end
				end
			end
		end
	end
	for _, list in ipairs({ cops, civs }) do
		for _, car in ipairs(list) do
			local chassis = car.PrimaryPart
			if chassis then
				local hist = carHist[car] or {}
				table.insert(hist, 1, { pos = chassis.Position, vel = chassis.AssemblyLinearVelocity, clock = clock })
				hist[4] = nil
				carHist[car] = hist
			end
		end
	end
end

function HeatService.Init()
	notify = Remotes.Event("Notify")
	feed = Remotes.Event("Feed")
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(CHECK_EVERY)
			local t = os.clock()
			local dt = math.min(t - last, 1)
			last = t
			local ok, err = pcall(tick, dt)
			if not ok then
				warn("[HeatService] " .. tostring(err))
			end
		end
	end)
	-- Confirmed car-on-car hits from VehicleDamageService (optional: our own check covers the rest).
	local damageModule = ServerScriptService.Services:FindFirstChild("VehicleDamageService")
	if damageModule then
		local ok, VehicleDamageService = pcall(require, damageModule)
		if ok and type(VehicleDamageService) == "table" and VehicleDamageService.CarHit then
			VehicleDamageService.CarHit:Connect(function(car, other)
				local fine, err = pcall(onCarHit, car, other)
				if not fine then
					warn("[HeatService] carhit " .. tostring(err))
				end
			end)
		end
	end
	task.spawn(function()
		while true do
			task.wait(RAM_EVERY)
			local ok, err = pcall(ramTick)
			if not ok then
				warn("[HeatService] ram " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		forget(p)
		ramAt[p] = nil
	end)
end

return HeatService
