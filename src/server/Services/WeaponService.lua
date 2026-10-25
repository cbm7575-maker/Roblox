-- WeaponService (ModuleScript, ServerScriptService.Services.WeaponService)
-- Guns (Config.Weapons): the Shoreline Arms gun store, owned guns, shots, damage, PASSIVE mode.
--   * Store: built from parts at server start (HouseBuilder's kit) at Config.Weapons.Store, under
--     Workspace.City.Landmarks.ShorelineArms (MapService lists it for the GPS). Its counter prompt
--     opens the store on that player's screen (remote WeaponStore); BuyWeapon(id) buys, checked here:
--     citizens only, within Store.Reach of the counter, citizen rank (CivRank), cash.
--   * Owned guns are saved in data.weapons = { owned = { [id] = true }, passive = bool } and mirrored
--     to the player attribute "OwnedWeapons" (comma list of ids). Every spawn gives the right Tools:
--     citizens their owned guns, police on duty the Duty Pistol only, prisoners nothing.
--     Each Tool has attribute WeaponId; its Handle has an Attachment "Muzzle".
--   * Shots (remote WeaponFire(id, origin, shots), shots = { { e = end Vector3, p = hit BasePart? } },
--     one per pellet): the shooter's device finds what it hit; the server checks the gun is in hand,
--     the fire rate, the magazine (WeaponReload(id) refills it after Reload seconds), the start point
--     (near the shooter's head), the range, that the hit point is on the part it names, and that no
--     wall stands between. Then WeaponService.CanDamage decides (see Config.Weapons for the rules).
--     Everyone within SHOT_SEND_RANGE sees the tracers (WeaponShot to clients); the shooter gets
--     WeaponHit(downed) for the hit marker.
--   * PASSIVE (remote SetPassive(bool), player attribute "Passive"): saved; can't be turned on while
--     wanted, within CombatLock of a fight, or within PassiveCooldown of the last switch. Heat turns
--     it off. Police on duty are never passive (the saved choice comes back when they go off duty).
--   * SpawnShield (player attribute, server time): nobody can hurt you until then (ends if you fire).
--   * Health comes back after RegenDelay seconds without being hurt (on top of Roblox's slow regen).
--   * Going down after a hit: the kill feed ("Takedown" on the Feed remote, unless they were wanted:
--     the arrest post covers that), +TakedownHeat for a citizen shooter. A wanted suspect hit by a
--     cop counts as that cop's arrest (ArrestService.CreditTakedown).
--   * Messages to the shooter / target go through the WeaponNotice(key, arg) remote (WeaponClient
--     has the texts).
-- Pedestrians are client-side and never hit; bullets pass through them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local HeatService = require(ServerScriptService.Services.HeatService)
local HouseBuilder = require(ServerScriptService.Services.HouseBuilder)

local WeaponService = {}

local SHOT_SEND_RANGE = 700 -- studs: players farther than this from a shot don't get its tracer

local noticeEvent, shotEvent, hitEvent, storeEvent, feed
local states = {} -- [player] = per-player state (see state())
local lastHit = {} -- [victim] = { by = Player, at = os.clock(), wanted = bool }
local counter -- the store counter (BasePart the purchase distance is measured from)

local function now()
	return Workspace:GetServerTimeNow()
end

local function state(player)
	local s = states[player]
	if not s then
		s = {
			mags = {}, -- [id] = shots left
			reloadUntil = {}, -- [id] = os.clock() the reload finishes
			lastShotAt = {}, -- [id] = os.clock() of the last accepted shot
			lastFire = -math.huge,
			lastHurt = -math.huge,
			lastHeat = -math.huge,
			lastCopCarHeat = -math.huge,
			lastToggle = -math.huge,
		}
		states[player] = s
	end
	return s
end

local function notice(player, key, arg)
	noticeEvent:FireClient(player, key, arg)
end

-- data.weapons, created on first use (nil until the save has loaded).
local function saved(player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	if type(data.weapons) ~= "table" then
		data.weapons = {}
	end
	local w = data.weapons
	if type(w.owned) ~= "table" then
		w.owned = {}
	end
	return w
end

function WeaponService.Owns(player, id)
	local w = saved(player)
	return w ~= nil and w.owned[id] == true
end

local function mirror(player)
	local w = saved(player)
	if not w then
		return
	end
	local ids = {}
	for _, def in ipairs(Weapons.List) do
		if w.owned[def.Id] then
			table.insert(ids, def.Id)
		end
	end
	player:SetAttribute("OwnedWeapons", table.concat(ids, ","))
end

local function alive(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return char, hum
	end
	return nil, nil
end

------------------------------------------------------------------ who can hurt whom

local function wanted(player)
	return player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) > 0
end

-- Can `attacker` hurt `victim` right now? (Config.Weapons explains the rules.)
function WeaponService.CanDamage(attacker, victim)
	if attacker == victim or not attacker or not victim then
		return false
	end
	local a, v = attacker:GetAttribute("Side"), victim:GetAttribute("Side")
	if a == "Prisoner" or v == "Prisoner" or a == nil or v == nil then
		return false
	end
	if attacker:GetAttribute("Passive") == true or victim:GetAttribute("Passive") == true then
		return false
	end
	if (victim:GetAttribute("SpawnShield") or 0) > now() then
		return false
	end
	if a == "Cop" then
		return wanted(victim) -- police only stop wanted suspects
	end
	return true
end

------------------------------------------------------------------ the tools

local function smooth(p)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

-- Gun shapes in the Handle's frame: -Z is the barrel's way, +Y up (how Roblox holds a Tool with the
-- default grip). Each entry: { size, offset, colour key, material, name }. Grip = where the hand is.
local DARK = Color3.fromRGB(34, 34, 42)
local GREY = Color3.fromRGB(70, 72, 84)
local SHAPES = {
	Pistol = {
		handle = Vector3.new(0.32, 0.42, 1.25),
		grip = CFrame.new(0, -0.45, 0.36),
		muzzle = Vector3.new(0, 0.06, -0.78),
		parts = {
			{ Vector3.new(0.28, 0.75, 0.38), CFrame.new(0, -0.5, 0.36) * CFrame.Angles(math.rad(-12), 0, 0), "dark" },
			{ Vector3.new(0.34, 0.08, 1.0), CFrame.new(0, 0.12, -0.05), "accent", Enum.Material.Neon },
			{ Vector3.new(0.16, 0.16, 0.18), CFrame.new(0, 0.06, -0.69), "grey" },
		},
	},
	SMG = {
		handle = Vector3.new(0.36, 0.5, 1.7),
		grip = CFrame.new(0, -0.45, 0.42),
		muzzle = Vector3.new(0, 0.08, -1.34),
		parts = {
			{ Vector3.new(0.28, 0.7, 0.36), CFrame.new(0, -0.5, 0.42) * CFrame.Angles(math.rad(-10), 0, 0), "dark" },
			{ Vector3.new(0.24, 0.8, 0.3), CFrame.new(0, -0.6, -0.3), "dark" },
			{ Vector3.new(0.18, 0.18, 0.5), CFrame.new(0, 0.08, -1.08), "grey" },
			{ Vector3.new(0.2, 0.3, 0.6), CFrame.new(0, 0, 1.12), "grey" },
			{ Vector3.new(0.38, 0.08, 1.4), CFrame.new(0, 0.16, 0), "accent", Enum.Material.Neon },
		},
	},
	Shotgun = {
		handle = Vector3.new(0.38, 0.48, 1.2),
		grip = CFrame.new(0, -0.42, 0.36),
		muzzle = Vector3.new(0, 0.08, -2.62),
		parts = {
			{ Vector3.new(0.22, 0.22, 2.0), CFrame.new(0, 0.08, -1.58), "grey" },
			{ Vector3.new(0.32, 0.3, 0.7), CFrame.new(0, -0.14, -1.3), "accent", Enum.Material.Neon },
			{ Vector3.new(0.3, 0.5, 1.1), CFrame.new(0, -0.16, 1.12) * CFrame.Angles(math.rad(8), 0, 0), "dark" },
			{ Vector3.new(0.26, 0.6, 0.34), CFrame.new(0, -0.45, 0.36) * CFrame.Angles(math.rad(-10), 0, 0), "dark" },
		},
	},
	Rifle = {
		handle = Vector3.new(0.34, 0.46, 1.5),
		grip = CFrame.new(0, -0.42, 0.46),
		muzzle = Vector3.new(0, 0.06, -3.0),
		parts = {
			{ Vector3.new(0.16, 0.16, 2.2), CFrame.new(0, 0.06, -1.86), "grey" },
			{ Vector3.new(0.22, 0.22, 0.9), CFrame.new(0, 0.42, -0.1), "dark" },
			{ Vector3.new(0.24, 0.24, 0.06), CFrame.new(0, 0.42, -0.57), "accent", Enum.Material.Neon },
			{ Vector3.new(0.3, 0.5, 1.2), CFrame.new(0, -0.12, 1.32), "dark" },
			{ Vector3.new(0.26, 0.6, 0.34), CFrame.new(0, -0.45, 0.46) * CFrame.Angles(math.rad(-10), 0, 0), "dark" },
			{ Vector3.new(0.22, 0.45, 0.35), CFrame.new(0, -0.42, -0.3), "accent", Enum.Material.Neon },
		},
	},
}
SHAPES["Police pistol"] = SHAPES.Pistol

local function makeTool(def)
	local shape = SHAPES[def.Kind] or SHAPES.Pistol
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.ToolTip = def.Kind
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true -- WeaponClient handles the trigger (click, FIRE button, R2)
	tool.Grip = shape.grip
	tool:SetAttribute("WeaponId", def.Id)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = shape.handle
	handle.Color = DARK
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CastShadow = false
	handle.CFrame = CFrame.new()
	smooth(handle)
	handle.Parent = tool
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = shape.muzzle
	muzzle.Parent = handle
	local colors = { dark = DARK, grey = GREY, accent = def.Color }
	for i, spec in ipairs(shape.parts) do
		local p = Instance.new("Part")
		p.Name = "Piece" .. i
		p.Size = spec[1]
		p.CFrame = spec[2]
		p.Color = colors[spec[3]] or DARK
		p.Material = spec[4] or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		smooth(p)
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end
	return tool
end

local function ourTools(player)
	local list = {}
	for _, holder in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if holder then
			for _, t in ipairs(holder:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("WeaponId") then
					table.insert(list, t)
				end
			end
		end
	end
	return list
end

local function giveTool(player, id)
	local def = Weapons.ById[id]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not def or not backpack then
		return
	end
	for _, t in ipairs(ourTools(player)) do
		if t:GetAttribute("WeaponId") == id then
			return
		end
	end
	local s = state(player)
	s.mags[id] = def.Mag
	s.reloadUntil[id] = nil
	makeTool(def).Parent = backpack
end

-- The right guns for this player's side (called on every spawn and side change).
local function refreshTools(player)
	local side = player:GetAttribute("Side")
	local want = {}
	if side == "Cop" then
		want[Weapons.CopWeapon] = true
	elseif side == "Civilian" then
		local w = saved(player)
		for _, def in ipairs(Weapons.List) do
			if w and not def.CopOnly and w.owned[def.Id] then
				want[def.Id] = true
			end
		end
	end
	for _, t in ipairs(ourTools(player)) do
		if not want[t:GetAttribute("WeaponId")] then
			t:Destroy()
		end
	end
	for _, def in ipairs(Weapons.List) do
		if want[def.Id] then
			giveTool(player, def.Id)
		end
	end
end

------------------------------------------------------------------ PASSIVE

local function setPassive(player, on)
	if (player:GetAttribute("Passive") == true) ~= on then
		player:SetAttribute("Passive", on)
	end
	if on then
		local _, hum = alive(player)
		if hum then
			hum:UnequipTools()
		end
	end
end

-- The attribute follows the side: police and prisoners are never passive; citizens get their saved
-- choice back (unless they're wanted).
local function syncPassive(player)
	local w = saved(player)
	local on = player:GetAttribute("Side") == "Civilian" and w ~= nil and w.passive == true
		and (player:GetAttribute("Heat") or 0) <= 0
	setPassive(player, on)
end

local function onSetPassive(player, on)
	if type(on) ~= "boolean" or not RateLimit.Allow(player, "Passive", 1, 2) then
		return
	end
	local w = saved(player)
	if not w or on == (player:GetAttribute("Passive") == true) then
		return
	end
	local s = state(player)
	local t = os.clock()
	if on then
		if player:GetAttribute("Side") ~= "Civilian" then
			return notice(player, "PassiveCitizens")
		end
		if (player:GetAttribute("Heat") or 0) > 0 then
			return notice(player, "PassiveWanted")
		end
		local fight = Weapons.CombatLock - (t - math.max(s.lastFire, s.lastHurt))
		if fight > 0 then
			return notice(player, "PassiveFight", math.ceil(fight))
		end
		local wait = Weapons.PassiveCooldown - (t - s.lastToggle)
		if wait > 0 then
			return notice(player, "PassiveCooldown", math.ceil(wait))
		end
	end
	s.lastToggle = t
	w.passive = on
	setPassive(player, on)
	notice(player, on and "PassiveOn" or "PassiveOff")
end

------------------------------------------------------------------ shots and damage

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true -- only solid things stop a bullet (not leaves, signs or glow)

-- No wall between a and b? (Characters and cars don't count: the shooter's own ray already stopped
-- at the first one it met.)
local function clearLine(a, b)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in ipairs({ "Vehicles", "Roadblocks" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	losParams.FilterDescendantsInstances = list
	local dir = b - a
	local dist = dir.Magnitude
	if dist < 1.5 then
		return true
	end
	return Workspace:Raycast(a, dir.Unit * (dist - 1), losParams) == nil
end

local function playerOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model) or nil
end

local function carOf(part)
	local folder = Workspace:FindFirstChild("Vehicles")
	local a = part
	while a and a.Parent ~= folder do
		a = a.Parent
	end
	return folder and a or nil
end

local function finite(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e5 and math.abs(v.Y) < 1e5 and math.abs(v.Z) < 1e5
end

local function crime(attacker, s, t)
	if attacker:GetAttribute("Side") == "Civilian" and t - s.lastHeat >= Weapons.AssaultCooldown then
		s.lastHeat = t
		HeatService.Add(attacker, Weapons.AssaultHeat, "assault")
	end
end

-- Returns hit (bool), downed (bool).
local function hurt(attacker, victim, amount)
	if not WeaponService.CanDamage(attacker, victim) then
		return false, false
	end
	local _, hum = alive(victim)
	if not hum then
		return false, false
	end
	local t = os.clock()
	local wasWanted = wanted(victim)
	lastHit[victim] = { by = attacker, at = t, wanted = wasWanted }
	state(victim).lastHurt = t
	if attacker:GetAttribute("Side") == "Cop" and wasWanted then
		require(ServerScriptService.Services.ArrestService).CreditTakedown(victim, attacker)
	end
	crime(attacker, state(attacker), t)
	if not victim:GetAttribute("ShotTip") then
		victim:SetAttribute("ShotTip", true) -- once a session: how to opt out
		notice(victim, "ShotTip")
	end
	hum:TakeDamage(amount)
	return true, hum.Health <= 0
end

local function shootCar(attacker, car, amount)
	if car:GetAttribute("AIPolice") then
		local s = state(attacker)
		local t = os.clock()
		if attacker:GetAttribute("Side") == "Civilian" and t - s.lastCopCarHeat >= Weapons.CopCarCooldown then
			s.lastCopCarHeat = t
			HeatService.Add(attacker, Weapons.CopCarHeat, "shot a police car")
		elseif attacker:GetAttribute("Side") ~= "Civilian" then
			return -- police don't shoot up their own cars
		end
	else
		-- A player's car only takes hits while its driver could (passive drivers, parked cars: no).
		local seat = car:FindFirstChild("DriverSeat")
		local occupant = seat and seat:IsA("VehicleSeat") and seat.Occupant
		local driver = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if not driver or not WeaponService.CanDamage(attacker, driver) then
			return
		end
		crime(attacker, state(attacker), os.clock())
	end
	local ok, err = pcall(function()
		require(ServerScriptService.Services.VehicleDamageService).Damage(car, amount, "shot")
	end)
	if not ok then
		warn("[WeaponService] car damage: " .. tostring(err))
	end
end

local function onFire(player, id, origin, shots)
	if type(id) ~= "string" or not finite(origin) or type(shots) ~= "table" then
		return
	end
	local def = Weapons.ById[id]
	local char, hum = alive(player)
	local head = char and char:FindFirstChild("Head")
	if not def or not hum or not head or hum.SeatPart then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute("WeaponId") ~= id or player:GetAttribute("Passive") == true then
		return
	end
	local side = player:GetAttribute("Side")
	if side == "Prisoner" or (def.CopOnly and side ~= "Cop") or (not def.CopOnly and side ~= "Civilian") then
		return
	end
	if (player:GetAttribute("StunnedUntil") or 0) > now() then
		return -- tased
	end
	local s = state(player)
	local t = os.clock()
	if t - (s.lastShotAt[id] or -math.huge) < 0.5 / def.Rate then
		return -- two shots at once (the rate bucket alone would allow a burst of 2)
	end
	local reloadEnd = s.reloadUntil[id]
	if reloadEnd then
		if reloadEnd > t + 0.15 then
			return -- still reloading
		end
		s.mags[id] = def.Mag -- the reload is done (its timer may not have run yet)
		s.reloadUntil[id] = nil
	end
	if (s.mags[id] or 0) <= 0 then
		return
	end
	if not RateLimit.Allow(player, "Fire_" .. id, def.Rate * Weapons.RateSlack, 2) then
		return
	end
	s.mags[id] -= 1
	s.lastShotAt[id] = t
	s.lastFire = t
	if player:GetAttribute("SpawnShield") then
		player:SetAttribute("SpawnShield", nil)
	end
	if (origin - head.Position).Magnitude > Weapons.MaxOriginOffset or not clearLine(head.Position, origin) then
		origin = head.Position -- never start a shot on the far side of a wall
	end

	local ends = {}
	local victims = {} -- [player] = damage
	local cars = {} -- [car] = hits
	for i = 1, math.min(#shots, def.Pellets) do
		local shot = shots[i]
		local e = type(shot) == "table" and shot.e
		if finite(e) then
			local dir = e - origin
			local dist = dir.Magnitude
			if dist > def.Range then
				e = origin + dir.Unit * def.Range
				dist = def.Range
			end
			table.insert(ends, e)
			local part = shot.p
			if dist > 0.1 and typeof(part) == "Instance" and part:IsA("BasePart") and part:IsDescendantOf(Workspace)
				and (part.Position - e).Magnitude <= part.Size.Magnitude / 2 + Weapons.HitSlack and clearLine(origin, e)
				and clearLine(e, part.Position) then -- the hit point must be on the target, not on a wall in front
				local victim = playerOf(part)
				if victim and victim ~= player then
					local mult = part.Name == "Head" and def.HeadMult or 1
					victims[victim] = (victims[victim] or 0) + def.Damage * mult
				elseif not victim then
					local car = carOf(part)
					if car then
						cars[car] = (cars[car] or 0) + (def.Pellets > 1 and 0.4 or 1)
					end
				end
			end
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		local root = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - origin).Magnitude <= SHOT_SEND_RANGE then
			shotEvent:FireClient(p, player, id, origin, ends)
		end
	end

	local anyHit, anyDown = false, false
	for victim, amount in pairs(victims) do
		local hit, down = hurt(player, victim, amount)
		anyHit = anyHit or hit
		anyDown = anyDown or down
	end
	for car, hits in pairs(cars) do
		shootCar(player, car, hits * Weapons.CarDamage)
	end
	if anyHit then
		hitEvent:FireClient(player, anyDown)
	end
end

local function onReload(player, id)
	if type(id) ~= "string" or not RateLimit.Allow(player, "Reload", 2, 3) then
		return
	end
	local def = Weapons.ById[id]
	local s = states[player]
	if not def or not s or s.mags[id] == nil or s.mags[id] >= def.Mag or s.reloadUntil[id] then
		return
	end
	local done = os.clock() + def.Reload
	s.reloadUntil[id] = done
	task.delay(def.Reload, function()
		if states[player] == s and s.reloadUntil[id] == done then
			s.mags[id] = def.Mag
			s.reloadUntil[id] = nil
		end
	end)
end

------------------------------------------------------------------ the store

local function onBuy(player, id)
	if type(id) ~= "string" or not RateLimit.Allow(player, "BuyWeapon", 1, 2) then
		return
	end
	local def = Weapons.ById[id]
	if not def or def.CopOnly then
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" then
		return notice(player, "StoreCitizens")
	end
	local char = alive(player)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not counter or not root or (root.Position - counter.Position).Magnitude > Weapons.Store.Reach then
		return notice(player, "StoreTooFar")
	end
	local w = saved(player)
	if not w then
		return -- save still loading
	end
	if w.owned[id] then
		return notice(player, "StoreOwned", def.Name)
	end
	if (player:GetAttribute("CivRank") or 1) < (def.MinRank or 1) then
		return notice(player, "StoreRank", def.MinRank)
	end
	if not EconomyService.Spend(player, def.Price, "weapon:" .. id) then
		return notice(player, "StoreCash", def.Price)
	end
	w.owned[id] = true
	mirror(player)
	giveTool(player, id)
	notice(player, "StoreBought", def.Name)
	task.spawn(DataService.SaveNow, player)
	local ok, err = pcall(function()
		require(ServerScriptService.Services.TutorialService).Advance(player, "gun")
	end)
	if not ok then
		warn("[WeaponService] tutorial: " .. tostring(err))
	end
end

-- The store: a neon-trimmed shop on the plaza (kit frame: -Z = the front, toward the spawn).
local function buildStore()
	local cfg = Weapons.Store
	local city = Workspace:FindFirstChild("City")
	local parent = city and city:FindFirstChild("Landmarks") or city or Workspace
	local old = parent:FindFirstChild("ShorelineArms")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "ShorelineArms"
	local lot = CFrame.new(cfg.Position) * CFrame.Angles(0, math.rad(cfg.Yaw or 0), 0)
	local k = HouseBuilder.NewKit(model, lot, 4242)
	local C, M, rgb = HouseBuilder.C, HouseBuilder.M, HouseBuilder.rgb
	local PINK, CYAN = rgb(255, 62, 165), rgb(34, 225, 255)
	local wall, trim = rgb(40, 36, 56), rgb(24, 22, 34)
	local X, Z0, Z1, H = 15, -10, 12, 14

	-- Pavement apron, floor, walls (a wide doorway and two shop windows in the front), roof.
	k:Solid(-X - 3, 0, Z0 - 7, X + 3, 0.3, Z1 + 2, C.Concrete, M.Concrete, { n = "Apron" })
	k:Solid(-X, 0.3, Z0, X, 0.5, Z1, rgb(58, 54, 70), M.SmoothPlastic, { n = "Floor" })
	k:Walls4(-X, Z0, X, Z1, 0.5, H, 1, wall, M.Concrete, {
		front = {
			{ 12, 18, 0.5, 9.5 },
			{ 2, 10, 3, 10, glass = C.DarkGlass },
			{ 20, 28, 3, 10, glass = C.DarkGlass },
		},
		back = {}, left = {}, right = {},
	})
	k:FlatRoof(-X - 0.5, Z0 - 0.5, X + 0.5, Z1 + 0.5, H, trim, M.SmoothPlastic, 1.5, trim, M.SmoothPlastic)
	-- Neon trim along the roofline and round the doorway.
	k:Neon(-X - 0.6, H - 0.4, Z0 - 0.7, X + 0.6, H, Z0 - 0.6, PINK)
	k:Neon(-3.2, 0.5, Z0 - 0.7, -3, 9.7, Z0 - 0.6, CYAN)
	k:Neon(3, 0.5, Z0 - 0.7, 3.2, 9.7, Z0 - 0.6, CYAN)
	k:Neon(-3.2, 9.5, Z0 - 0.7, 3.2, 9.7, Z0 - 0.6, CYAN)
	-- A pink canopy over the doorway (cantilevered: nothing to bump into on the pavement).
	k:Solid(-6, 10.2, Z0 - 4, 6, 10.7, Z0 - 0.5, PINK, M.SmoothPlastic, { n = "Canopy" })
	k:Neon(-6, 10, Z0 - 4.05, 6, 10.2, Z0 - 3.95, CYAN)
	-- Signs: over the door (toward the spawn) and on the back wall (toward Solana Ave).
	k:Banner(0, H + 3.6, Z0 - 1.15, 0, 26, 4.5, cfg.Name:upper(), PINK, { back = trim })
	k:Banner(0, H + 3.6, Z1 + 1.15, 180, 26, 4.5, cfg.Name:upper(), PINK, { back = trim })
	k:Banner(-9, 11.2, Z0 - 0.6, 0, 8, 1.4, "GUNS · OPEN 24/7", CYAN, { back = trim })
	k:Solid(-X - 0.5, H + 1, Z0 - 1, X + 0.5, H + 6, Z0 - 0.6, trim, M.SmoothPlastic, { n = "SignBoard" })
	k:Solid(-X - 0.5, H + 1, Z1 + 0.6, X + 0.5, H + 6, Z1 + 1, trim, M.SmoothPlastic, { n = "SignBoard" })

	-- Inside: the counter across the room, a wall rack behind it, lights and posters.
	k:Solid(-9, 0.5, 3, 9, 4, 5, rgb(120, 86, 60), M.Wood, { n = "Counter" })
	k:Box(-9, 4, 3, 9, 4.3, 5, rgb(30, 30, 36), M.SmoothPlastic, { n = "CounterTop" })
	k:Box(-8, 4.3, 3.4, 8, 5.6, 4.6, C.Glass, M.Glass, { n = "Case", t = 0.6 })
	k:Box(-12, 3, Z1 - 0.7, 12, 12, Z1 - 0.5, rgb(30, 28, 40), M.SmoothPlastic, { n = "Rack" })
	for i, def in ipairs(Weapons.List) do
		if not def.CopOnly then
			local x = -9 + (i - 1) * 6
			k:Neon(x - 2, 9.2 - i % 2 * 3, Z1 - 0.9, x + 2, 9.6 - i % 2 * 3, Z1 - 0.7, def.Color)
			k:Box(x - 1.6, 9.7 - i % 2 * 3, Z1 - 0.95, x + 1.6, 10.3 - i % 2 * 3, Z1 - 0.75, rgb(20, 20, 26), M.SmoothPlastic, { n = "Display" })
		end
	end
	k:Banner(0, 13, Z1 - 0.9, 180, 20, 1.6, "PASSIVE players can't be shot. Switch it next to PHONE.", CYAN, { back = trim })
	k:Light(-7, H - 0.3, -2, C.Warm, 22, 1.2)
	k:Light(7, H - 0.3, -2, C.Warm, 22, 1.2)
	k:Light(0, H - 0.3, 8, PINK, 20, 1)
	k:Plant(-X + 2, 0.5, Z0 + 2)
	k:Plant(X - 2, 0.5, Z0 + 2)

	-- The prompt hangs over the counter (shoppers face the rack across it).
	local promptPart = k:Part(Vector3.new(2, 2, 2), 0, 5, 2, C.Black, M.SmoothPlastic, { n = "StorePrompt", t = 1 })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StorePrompt"
	prompt.ActionText = "Browse guns"
	prompt.ObjectText = cfg.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart
	prompt.Triggered:Connect(function(player)
		if player:GetAttribute("Side") == "Prisoner" then
			return
		end
		storeEvent:FireClient(player)
	end)
	counter = promptPart

	model:SetAttribute("Parts", k.stats.parts)
	model.Parent = parent
	return model
end

------------------------------------------------------------------ players

local function onDied(victim)
	local rec = lastHit[victim]
	lastHit[victim] = nil
	if not rec or os.clock() - rec.at > Weapons.TakedownMemory or rec.by.Parent ~= Players then
		return
	end
	local killer = rec.by
	if killer:GetAttribute("Side") == "Civilian" then
		HeatService.Add(killer, Weapons.TakedownHeat, "takedown")
	end
	notice(killer, "Takedown", victim.DisplayName)
	if not rec.wanted then -- a wanted player who goes down is arrested: ArrestService posts that
		local char = victim.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		feed:FireAllClients("Takedown", {
			Name = victim.DisplayName, By = killer.DisplayName, UserId = victim.UserId,
			ByUserId = killer.UserId, Position = root and root.Position or nil,
		})
	end
end

local function onCharacter(player, char)
	player:SetAttribute("SpawnShield", now() + Weapons.SpawnShield)
	lastHit[player] = nil
	local s = state(player)
	s.lastHurt = -math.huge
	local hum = char:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		hum.Died:Connect(function()
			onDied(player)
		end)
		-- Guns away when you sit down (drive, ride).
		hum.Seated:Connect(function(active)
			if active then
				hum:UnequipTools()
			end
		end)
	end
	if player.Character ~= char then
		return
	end
	player:WaitForChild("Backpack", 5)
	if player.Character == char then
		refreshTools(player)
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	-- Roblox makes a new Backpack for every spawn: fill it as soon as it appears.
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			task.defer(function()
				if player.Parent == Players and child.Parent == player then
					refreshTools(player)
				end
			end)
		end
	end)
	player:GetAttributeChangedSignal("Side"):Connect(function()
		task.defer(function()
			if player.Parent == Players then
				syncPassive(player)
				refreshTools(player)
			end
		end)
	end)
	player:GetAttributeChangedSignal("Heat"):Connect(function()
		if (player:GetAttribute("Heat") or 0) > 0 and player:GetAttribute("Passive") == true then
			local w = saved(player)
			if w then
				w.passive = false
			end
			setPassive(player, false)
			notice(player, "PassiveLost")
		end
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function regenLoop()
	local STEP = 0.5
	while true do
		task.wait(STEP)
		local t = os.clock()
		for player, s in pairs(states) do
			if t - s.lastHurt >= Weapons.RegenDelay then
				local _, hum = alive(player)
				if hum and hum.Health < hum.MaxHealth then
					hum.Health = math.min(hum.MaxHealth, hum.Health + Weapons.RegenPerSecond * STEP)
				end
			end
		end
	end
end

function WeaponService.Init()
	noticeEvent = Remotes.Event("WeaponNotice")
	shotEvent = Remotes.Event("WeaponShot")
	hitEvent = Remotes.Event("WeaponHit")
	storeEvent = Remotes.Event("WeaponStore")
	feed = Remotes.Event("Feed")
	Remotes.Event("WeaponFire").OnServerEvent:Connect(onFire)
	Remotes.Event("WeaponReload").OnServerEvent:Connect(onReload)
	Remotes.Event("BuyWeapon").OnServerEvent:Connect(onBuy)
	Remotes.Event("SetPassive").OnServerEvent:Connect(onSetPassive)

	local ok, err = pcall(buildStore)
	if not ok then
		warn("[WeaponService] gun store not built: " .. tostring(err))
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastHit[player] = nil
	end)
	DataService.OnLoaded(function(player)
		mirror(player)
		syncPassive(player)
		refreshTools(player)
	end)
	task.spawn(regenLoop)
end

return WeaponService
