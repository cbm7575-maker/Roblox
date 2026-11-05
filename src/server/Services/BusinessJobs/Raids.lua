-- Raids (ModuleScript, ServerScriptService.Services.BusinessJobs.Raids)
-- POLICE RAIDS on a business's dirty cash (PRD section 5, pillar 3; every number in Config.Businesses.Raid). Shared by
-- the job modules whose building can be raided: the Backlot Print Shop (M3: its dirty stock) and the Afterglow
-- Nightclub's back room (M5: the card game's dirty cash). This is the M3 raid code taken out of PrintShop.lua as it
-- was, with the few things that differ per building handed in by Raids.Register (the spec below). It is not a job
-- module itself: BusinessService never loads it (no business has the Style "Raids"); PrintShop and Nightclub
-- require it and call it from their own hooks (Init, Second, State, Alarms, PlayerLeft, Debug).
--
-- PER BUILDING (Raids.Register(id, spec); spec fields, all optional but cap):
--   cap(level) -> the stock's cap (the warrant odds grow towards it: Businesses.WarrantChance)
--   minDirty      $ in stock before a warrant can be issued (default Raid.MinDirty)
--   stock(entry) -> the dirty cash in stock (default entry.dirty)
--   breachHold(level) -> seconds a cop holds BREACH (default Businesses.BreachHold: the Print Shop's armored door)
--   breach        lot-space spot a cop breaches at (default Layout.Door); the prompt hangs breachOut studs in
--                 front of it (lot -Z) at breachUp studs high
--   search        lot-space spot a cop searches at (default Layout.Search); its prompt searchUp studs high
--   face          lot-space spot the AI officers face while searching
--   wayIn         lot-space points the AI officers walk through to their stand spots (Layout.RaidStand); {} = straight
--   pathIn        lot-space points the AI officers walk after the breach, before the search spot
--   words         { place (the feed's "Backlot Print Shop"), stuff ("in fake bills"), searchObject ("The presses"),
--                   inSay ("We're in! Search the presses!"), heldSay ("Step away from the presses!") }
--
-- THE STORY (unchanged from M3; see PrintShop's header for the long version). Per owner and building (clocks by UserId,
-- never an Instance key: the Nov 4 Studio lesson): the first warrant roll at Raid.MinPlay of their play clock, then one
-- every Check; a raid's end pushes the next one Gap away. A roll happens with minDirty+ in their stock, the owner a
-- living citizen in the server, no raid at the building (nor in the SiteGap after one) and no raid on that owner
-- anywhere else, and hits at Businesses.WarrantChance(stock, level, cap, minDirty). At most one raid per building.
--   * A PLAYER RAID when an eligible cop is in the server: BizBreachPrompt at the breach spot, then BizSearchPrompt at
--     the search spot, both timed here (PromptButtonHoldBegan -> Triggered). The search SEIZES all of that owner's
--     stock; every eligible cop at the lot gets Businesses.RaidReward.
--   * AN AI RAID otherwise: a police car pulls up at Layout.RaidCar, AIOfficers officers walk to Layout.RaidStand;
--     their breach and search clocks only run while nobody holds the door; a search takes Businesses.AISeizeAmount.
--   * THE OWNER AND CREW: BusinessResult Raid / RaidBreached / RaidSeized / RaidHeld / RaidOver; holding the door =
--     an owner or crewmate inside (Businesses.Inside: Layout.Inside). Held off: HeldBonus + Empire XP RaidHeld.
--   * Everyone sees the raids through ReplicatedStorage attribute BizRaids (JSON, keyed by business id).
--
-- API: Raids.Init(A), Raids.Register(id, spec), Raids.Second(id, dt, A), Raids.State(player, id), Raids.Alarms(player,
-- id), Raids.PlayerLeft(player, id), Raids.Debug(player, cmd, id, value, A) (cmd "raid" | "endraid"; nil when not one
-- of these or not a registered building), Raids.Registered(id), Raids.OnSite(id) (the raid there, or nil), Raids.Issue.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Businesses = require(ReplicatedStorage.Shared.Config.Businesses)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local Raids = {}

local RA = Businesses.Raid
local E = Businesses.Empire

local K = {
	SEAT_UP = 3.4, -- a car's pivot above the lot's ground (as BusinessService)
	WALK = 11, -- studs/s an AI officer walks at
	CAR_IN = 2.5, -- seconds the AI police car takes to pull up
	SAY_GAP = 6, -- seconds between two shouts from a waiting AI officer
}

local S = {
	A = nil, -- BusinessService's Api (Init / every hook)
	inited = false,
	specs = {}, -- [business id] = its spec (Register)
	raids = {}, -- [business id] = the raid there (at most one per building)
	owners = {}, -- [business id] = { [UserId] = { nextAt = play seconds of their next warrant roll } } (never Instance keys)
	siteFree = {}, -- [business id] = os.clock() before which no new warrant there (Raid.SiteGap)
	json = nil, -- the last BizRaids sent
	feed = nil, -- the Feed remote
}

local DEFAULT_WORDS = {
	place = "business", stuff = "in dirty cash", searchObject = "The stash", inSay = "We're in! Search the place!",
	heldSay = "Step away from the stash!",
}

------------------------------------------------------------------ small helpers

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function money(n)
	return S.A and S.A.money(n) or ("$" .. tostring(math.floor(n)))
end

local function serverAt(clockAt)
	return Workspace:GetServerTimeNow() + (clockAt - os.clock())
end

local function rootOf(p)
	local char = p and p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil, hum
	end
	return char:FindFirstChild("HumanoidRootPart"), hum
end

-- On foot within `range` (flat) of a lot-space spot, and on the same floor.
local function onFootAt(p, def, spot, range)
	local root, hum = rootOf(p)
	if not root or not hum or hum.SeatPart then
		return false
	end
	local at = Businesses.At(def, spot)
	return flat(root.Position - at).Magnitude <= range and math.abs(root.Position.Y - at.Y) < 12
end

local function studioCop(p)
	return RunService:IsStudio() and p ~= nil and Workspace:GetAttribute("BizTestCop") == p.Name
end

local function specOf(id)
	return S.specs[id]
end

local function wordsOf(rec)
	local spec = specOf(rec.id)
	local w = spec and spec.words or nil
	return setmetatable(w or {}, { __index = DEFAULT_WORDS })
end

local function stockOf(rec, entry)
	local spec = specOf(rec.id)
	if spec and type(spec.stock) == "function" then
		return spec.stock(entry)
	end
	return entry and (entry.dirty or 0) or 0
end

------------------------------------------------------------------ who's who

local function arrestService()
	return S.A and S.A.service("ArrestService")
end

-- A cop who may serve this owner's warrant: on duty and playing (or the Studio test cop), never the owner or their crew.
local function eligibleCop(p, owner)
	local A = S.A
	if p == owner or p.Parent ~= Players or A.sameCrew(owner, p) or not A.alive(p) then
		return false
	end
	if studioCop(p) then
		return true
	end
	if p:GetAttribute("Side") ~= "Cop" then
		return false
	end
	local as = arrestService()
	return not (as and type(as.IsActiveCop) == "function") or as.IsActiveCop(p) == true
end

local function copsFor(owner)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if eligibleCop(p, owner) then
			table.insert(list, p)
		end
	end
	return list
end

-- The owner and their crewmates in the server.
local function crewOf(owner)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p == owner or S.A.sameCrew(owner, p) then
			table.insert(list, p)
		end
	end
	return list
end

-- Everyone a raid's news goes to: owner, crew, the cops sent (and any eligible cop now).
local function involved(rec)
	local list, seen = {}, {}
	for _, p in ipairs(crewOf(rec.owner)) do
		seen[p.UserId] = "Crew"
		table.insert(list, p)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if not seen[p.UserId] and (rec.cops[p.UserId] or eligibleCop(p, rec.owner)) then
			seen[p.UserId] = "Cop"
			table.insert(list, p)
		end
	end
	return list, seen
end

local function roleOf(rec, p)
	if p == rec.owner then
		return "Owner"
	elseif S.A.sameCrew(rec.owner, p) then
		return "Crew"
	end
	return "Cop"
end

local function tell(rec, kind, fields)
	local list = involved(rec)
	for _, p in ipairs(list) do
		local info = { Kind = kind, Id = rec.id, Role = roleOf(rec, p), Owner = rec.ownerId, OwnerName = rec.ownerName, Ai = rec.ai }
		for k, v in pairs(fields or {}) do
			info[k] = v
		end
		S.A.result(p, info)
	end
end

local function feedPost(text)
	if S.feed then
		S.feed:FireAllClients("Event", { Text = text })
	end
end

------------------------------------------------------------------ publish

local function publish()
	local all = {}
	for id, rec in pairs(S.raids) do
		local cops = {}
		for uid in pairs(rec.cops) do
			table.insert(cops, uid)
		end
		local share = 0
		if rec.ai then
			share = rec.stage == "search" and rec.search / RA.AISearch or rec.breach / RA.AIBreach
		end
		all[id] = { o = rec.ownerId, n = rec.ownerName, s = rec.stage, u = math.floor(serverAt(rec.untilAt) * 10) / 10, ai = rec.ai,
			b = math.floor(math.clamp(share, 0, 1) * 20) / 20, h = rec.holding == true, c = cops }
	end
	local json = HttpService:JSONEncode(all)
	if json ~= S.json then
		S.json = json
		ReplicatedStorage:SetAttribute("BizRaids", json)
	end
end

------------------------------------------------------------------ the AI unit

local function clearUnit(rec)
	local unit = rec.unit
	rec.unit = nil
	if not unit then
		return
	end
	for _, o in ipairs(unit.officers) do
		o.gone = true
		if o.model.Parent then
			S.A.fadeOut(o.model, 0.8)
		end
	end
	local folder = unit.folder
	task.delay(1.5, function()
		if folder.Parent then
			folder:Destroy()
		end
	end)
end

-- An officer for the AI raid: one of PoliceOfficerService's looks (or a plain navy one), anchored, unhittable.
local function newOfficer(parent, at, face, A)
	local ok, model = pcall(function()
		local folder = ServerStorage:FindFirstChild("OfficerTemplates")
		local list = folder and folder:GetChildren() or {}
		local pick = #list > 0 and list[A.rng:NextInteger(1, #list)] or nil
		if pick and pick:IsA("Model") and pick:FindFirstChild("HumanoidRootPart") then
			return pick:Clone()
		end
		local desc = Instance.new("HumanoidDescription")
		local navy = Color3.fromRGB(28, 42, 78)
		desc.HeadColor = Color3.fromRGB(205, 160, 120)
		desc.LeftArmColor, desc.RightArmColor, desc.TorsoColor = navy, navy, navy
		desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(20, 24, 36), Color3.fromRGB(20, 24, 36)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		model:Destroy()
		return nil
	end
	hum.DisplayName = "Police"
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 60
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	model.Name = "BizRaidOfficer"
	root.Anchored = true
	local y = hum.HipHeight + root.Size.Y / 2 + 0.2
	model:PivotTo(CFrame.lookAt(at + Vector3.new(0, y, 0), Vector3.new(face.X, at.Y + y, face.Z)))
	model.Parent = parent
	local o = { model = model, root = root, hum = hum, y = y, token = 0 }
	pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://507766388" -- (Roblox's stock R15 idle)
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
	return o
end

-- Walk an officer along world points (anchored, tweened), then stand facing `face`.
local function walk(o, points, face)
	o.token += 1
	o.arrived = false
	local token = o.token
	local walkTrack
	pcall(function()
		walkTrack = require(ServerStorage.Tools.CarBuilder).PlayPose(o.model, "walk")
	end)
	task.spawn(function()
		local from = o.root.Position
		for _, p in ipairs(points) do
			local to = Vector3.new(p.X, p.Y + o.y, p.Z)
			local d = (to - from).Magnitude
			if d > 0.5 and o.model.Parent and o.token == token then
				local tween = TweenService:Create(o.root, TweenInfo.new(d / K.WALK, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + (to - from).Unit) })
				tween:Play()
				tween.Completed:Wait()
			end
			from = to
		end
		if walkTrack then
			pcall(function()
				walkTrack:Stop()
			end)
		end
		if o.model.Parent and o.token == token and face then
			o.root.CFrame = CFrame.lookAt(o.root.Position, Vector3.new(face.X, o.root.Position.Y, face.Z))
		end
		o.arrived = o.token == token
	end)
end

-- The breach spot (lot space) for this building: the spec's, else the door.
local function breachSpot(rec)
	local spec = specOf(rec.id)
	return (spec and spec.breach) or rec.def.Layout.Door
end

-- The AI raid pulls up: the car glides in to Layout.RaidCar, the officers get out and walk to their stand spots.
local function spawnUnit(rec, A)
	local def = rec.def
	local L = def.Layout
	local spec = specOf(rec.id) or {}
	local root = Workspace:FindFirstChild("BizRaid")
	if not root then
		root = Instance.new("Folder")
		root.Name = "BizRaid"
		root.Parent = Workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = "Raid_" .. def.Id
	folder.Parent = root
	local unit = { folder = folder, officers = {}, sayAt = 0 }
	rec.unit = unit
	local f = Businesses.Frame(def)
	local park = f * CFrame.new(L.RaidCar.X, K.SEAT_UP, L.RaidCar.Z) * CFrame.Angles(0, math.rad(90), 0)
	local okCar, car = pcall(function()
		return require(ServerStorage.Tools.CarBuilder).Build("SunrayPatrol")
	end)
	if okCar and car and car.PrimaryPart then
		car.Name = "BizRaidCar"
		car:SetAttribute("BizRaidCar", true)
		car:SetAttribute("Siren", true)
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				d.Disabled = true
			end
		end
		-- It comes in off the street, then turns into its spot.
		local from = Businesses.At(def, Vector3.new(L.RaidCar.X + 24, 0, -44)) + Vector3.new(0, K.SEAT_UP, 0)
		local start = CFrame.lookAt(from, Vector3.new(park.Position.X, from.Y, park.Position.Z))
		car:PivotTo(start)
		car.Parent = folder
		unit.car = car
		task.spawn(function()
			local t0 = os.clock()
			while car.Parent and os.clock() - t0 < K.CAR_IN do
				local a = (os.clock() - t0) / K.CAR_IN
				local ease = 1 - (1 - a) * (1 - a)
				-- (the position slides in; it only turns to the kerb over the last third)
				car:PivotTo(CFrame.new(start.Position:Lerp(park.Position, ease)) * start.Rotation:Lerp(park.Rotation, math.clamp((a - 0.66) * 3, 0, 1)))
				task.wait(1 / 20)
			end
			if car.Parent then
				car:PivotTo(park)
			end
		end)
	end
	local door = Businesses.At(def, breachSpot(rec))
	task.delay(K.CAR_IN + 0.3, function()
		if rec.unit ~= unit or rec.done then
			return
		end
		for i = 1, RA.AIOfficers do
			local stand = L.RaidStand[(i - 1) % #L.RaidStand + 1]
			local out = Businesses.At(def, L.RaidCar + Vector3.new(i == 1 and -2 or 2, 0, 5))
			local o = newOfficer(folder, Vector3.new(out.X, 0.2, out.Z), door, A)
			if o then
				table.insert(unit.officers, o)
				local pts = {}
				for _, v in ipairs(spec.wayIn or {}) do
					table.insert(pts, Businesses.At(def, v) + Vector3.new(0, 0.2, 0))
				end
				table.insert(pts, Businesses.At(def, stand) + Vector3.new(0, 0.2, 0))
				walk(o, pts, door)
				if i == 1 then
					A.say(o, "POLICE! Open up, we have a warrant!", 3)
				end
			end
		end
	end)
end

-- The AI officers go in to the search spot (after their breach).
local function unitInside(rec)
	local unit = rec.unit
	if not unit then
		return
	end
	local def = rec.def
	local spec = specOf(rec.id) or {}
	local search = spec.search or def.Layout.Search
	local face = spec.face or (def.Layout.Stations and def.Layout.Stations[3]) or search
	for i, o in ipairs(unit.officers) do
		local pts = {}
		for _, v in ipairs(spec.pathIn or {}) do
			table.insert(pts, Businesses.At(def, v) + Vector3.new(0, 0.35, 0))
		end
		table.insert(pts, Businesses.At(def, search + Vector3.new(i == 1 and -1.5 or 1.5, 0, 0)) + Vector3.new(0, 0.35, 0))
		walk(o, pts, Businesses.At(def, face))
	end
	if unit.officers[1] then
		S.A.say(unit.officers[1], wordsOf(rec).inSay, 2.5)
	end
end

------------------------------------------------------------------ the prompts (player raids)

-- A prompt hold the server times itself (as ArrestService's cuffs): onDone(cop) after a full hold.
local function timedPrompt(prompt, hold, onDone)
	local began = {} -- [UserId] = os.clock()
	prompt.PromptButtonHoldBegan:Connect(function(p)
		began[p.UserId] = os.clock()
	end)
	prompt.PromptButtonHoldEnded:Connect(function(p)
		local t = began[p.UserId]
		if t and os.clock() - t < hold - RA.HoldSlack then
			began[p.UserId] = nil -- (let go early: that hold is void)
		end
	end)
	prompt.Triggered:Connect(function(p)
		local t = began[p.UserId]
		began[p.UserId] = nil
		local held = t and os.clock() - t
		if held and held >= hold - RA.HoldSlack and held <= hold + 3 and RateLimit.Allow(p, "BizRaidPrompt", 1, 2) then
			onDone(p)
		end
	end)
end
Raids.TimedPrompt = timedPrompt -- (the Nightclub's back-room WASH hold is timed the same way)

local function dropPrompts(rec)
	for _, k in ipairs({ "breachPoint", "searchPoint" }) do
		local point = rec[k]
		rec[k] = nil
		if point and point.Parent then
			point:Destroy()
		end
	end
end

local seize, breached -- (forward: the prompts call them)

local function addPrompt(rec, key, spot, height, action, object, hold, onDone)
	local A = S.A
	local site = A.site(rec.id)
	if not site or not site.model.Parent then
		return
	end
	local f = Businesses.Frame(rec.def)
	local point = A.Build.holder(site.model, key == "breachPoint" and "RaidBreachPoint" or "RaidSearchPoint", f,
		spot + Vector3.new(0, height, 0), Vector3.new(2, 2, 1))
	local prompt = A.Build.prompt(point, key == "breachPoint" and "BizBreachPrompt" or "BizSearchPrompt", action, object, 10)
	prompt.HoldDuration = hold
	prompt:SetAttribute("BusinessId", rec.id)
	timedPrompt(prompt, hold, onDone)
	rec[key] = point
end

local function copAt(cop, rec, spot)
	return eligibleCop(cop, rec.owner) and onFootAt(cop, rec.def, spot, RA.CopRange)
end

local function breachPrompt(rec)
	local spec = specOf(rec.id) or {}
	local at = breachSpot(rec)
	addPrompt(rec, "breachPoint", at + Vector3.new(0, 0, -(spec.breachOut or 0.8)), spec.breachUp or 4, "Breach", "Raid warrant", rec.hold,
		function(cop)
			if rec.done or rec.ai or rec.stage ~= "warrant" or not copAt(cop, rec, at) then
				return
			end
			rec.cops[cop.UserId] = true
			breached(rec, cop)
		end)
end

local function searchPrompt(rec)
	local spec = specOf(rec.id) or {}
	local at = spec.search or rec.def.Layout.Search
	addPrompt(rec, "searchPoint", at, spec.searchUp or 3.5, "Search", wordsOf(rec).searchObject, RA.SearchHold, function(cop)
		if rec.done or rec.ai or rec.stage ~= "search" or not copAt(cop, rec, at) then
			return
		end
		rec.cops[cop.UserId] = true
		seize(rec, cop)
	end)
end

------------------------------------------------------------------ the story

local function ownerClock(id, uid)
	S.owners[id] = S.owners[id] or {}
	local o = S.owners[id][uid]
	if not o then
		o = { nextAt = RA.MinPlay }
		S.owners[id][uid] = o
	end
	return o
end

local function endRaid(rec, how)
	if rec.done then
		return
	end
	local A = S.A
	rec.done = true
	S.raids[rec.id] = nil
	dropPrompts(rec)
	clearUnit(rec)
	S.siteFree[rec.id] = os.clock() + RA.SiteGap
	local o = ownerClock(rec.id, rec.ownerId)
	local play = A.play(rec.owner) or 0
	o.nextAt = math.max(o.nextAt, play + RA.Gap)
	local words = wordsOf(rec)
	if how == "Held" then
		local bonus = math.floor(RA.HeldBonus * Businesses.RateScale)
		local crewBonus = math.floor(RA.CrewHeldBonus * Businesses.RateScale)
		if rec.owner.Parent == Players then
			EconomyService.AddCash(rec.owner, bonus, "bizraidheld:" .. rec.id)
			A.addEmpireXP(rec.owner, E.XP.RaidHeld)
			local entry = A.owned(rec.owner, rec.id)
			if entry then
				entry.lifetime += bonus
			end
		end
		for _, p in ipairs(crewOf(rec.owner)) do
			if p ~= rec.owner then
				if (rec.inside[p.UserId] or 0) >= RA.HeldMin then
					EconomyService.AddCash(p, crewBonus, "bizraidheld:" .. rec.id)
					A.addEmpireXP(p, E.XP.RaidHeld)
					A.result(p, { Kind = "RaidHeld", Id = rec.id, Role = "Crew", Owner = rec.ownerId, OwnerName = rec.ownerName, Bonus = crewBonus,
						XP = E.XP.RaidHeld, Ai = rec.ai })
				else
					A.result(p, { Kind = "RaidHeld", Id = rec.id, Role = "Crew", Owner = rec.ownerId, OwnerName = rec.ownerName, Bonus = 0, XP = 0,
						Ai = rec.ai })
				end
			end
		end
		A.result(rec.owner, { Kind = "RaidHeld", Id = rec.id, Role = "Owner", Owner = rec.ownerId, OwnerName = rec.ownerName, Bonus = bonus,
			XP = E.XP.RaidHeld, Ai = rec.ai })
		local _, roles = involved(rec)
		for _, p in ipairs(Players:GetPlayers()) do
			if roles[p.UserId] == "Cop" then
				A.result(p, { Kind = "RaidOver", Id = rec.id, Role = "Cop", Owner = rec.ownerId, OwnerName = rec.ownerName, Why = "Held" })
			end
		end
		feedPost(rec.ownerName .. " held off a police raid on the " .. words.place .. "!")
		Telemetry.Custom(rec.owner, "BizRaidHeld_" .. (rec.ai and "AI" or "PvP"), math.floor(rec.defended))
	elseif how == "Expired" or how == "Gone" then
		tell(rec, "RaidOver", { Why = how })
		Telemetry.Custom(rec.owner, "BizRaid" .. how .. "_" .. (rec.ai and "AI" or "PvP"), 1)
	end
	if rec.owner.Parent == Players then
		A.pushState(rec.owner)
	end
	A.refreshAlarms()
	publish()
end

-- THE SEARCH IS DONE: the stock is seized (player raid: the cops at the lot get the reward).
seize = function(rec, searcher)
	if rec.done then
		return
	end
	local A = S.A
	local entry = A.owned(rec.owner, rec.id)
	local stock = math.floor(stockOf(rec, entry))
	local amount = rec.ai and Businesses.AISeizeAmount(stock) or stock
	if entry then
		entry.dirty = math.max(0, (entry.dirty or 0) - amount)
	end
	if not rec.ai then
		local cops = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p == searcher or (eligibleCop(p, rec.owner) and A.atLot(p, rec.def)) then
				table.insert(cops, p)
			end
		end
		local each = Businesses.RaidReward(amount, #cops)
		for _, cop in ipairs(cops) do
			rec.cops[cop.UserId] = true
			EconomyService.AddCash(cop, each, "bizraid:" .. rec.id)
			A.result(cop, { Kind = "RaidSeized", Id = rec.id, Role = "Cop", Owner = rec.ownerId, OwnerName = rec.ownerName, Amount = amount,
				Reward = each, Ai = false })
			A.progressEvent(cop, "BizRaid", amount)
			Telemetry.Custom(cop, "BizRaidReward_" .. rec.id, each)
		end
	end
	for _, p in ipairs(crewOf(rec.owner)) do
		A.result(p, { Kind = "RaidSeized", Id = rec.id, Role = p == rec.owner and "Owner" or "Crew", Owner = rec.ownerId, OwnerName = rec.ownerName,
			Amount = amount, Ai = rec.ai })
	end
	local words = wordsOf(rec)
	feedPost(string.format("Police raided %s's %s and seized %s %s!", rec.ownerName, words.place, money(amount), words.stuff))
	Telemetry.Custom(rec.owner, "BizRaidSeized_" .. (rec.ai and "AI" or "PvP"), amount)
	endRaid(rec, "Seized")
end

-- THE DOOR IS BREACHED: on to the search (the warrant stretched to SearchMin from now).
breached = function(rec, cop)
	if rec.done or rec.stage ~= "warrant" then
		return
	end
	rec.stage = "search"
	rec.untilAt = math.max(rec.untilAt, os.clock() + RA.SearchMin)
	if rec.breachPoint then
		rec.breachPoint:Destroy()
		rec.breachPoint = nil
	end
	if rec.ai then
		unitInside(rec)
	else
		searchPrompt(rec)
	end
	tell(rec, "RaidBreached", { Until = serverAt(rec.untilAt), By = cop and cop.DisplayName or nil })
	publish()
end

-- Issue a warrant at `def` on this owner (opts: ai = force the AI raid, seconds = its length).
local function issue(owner, def, opts)
	local A = S.A
	opts = opts or {}
	local spec = specOf(def.Id) or {}
	local level = A.levelOf(owner, def)
	local cops = copsFor(owner)
	local hold = type(spec.breachHold) == "function" and spec.breachHold(level) or Businesses.BreachHold(level)
	local rec = {
		id = def.Id, def = def, owner = owner, ownerId = owner.UserId, ownerName = owner.DisplayName, level = level,
		stage = "warrant", ai = opts.ai == true or #cops == 0, untilAt = os.clock() + (opts.seconds or RA.Warrant), startAt = os.clock(),
		defended = 0, inside = {}, breach = 0, search = 0, cops = {}, hold = hold,
	}
	S.raids[def.Id] = rec
	if rec.ai then
		rec.arriveAt = os.clock() + math.min(RA.AIArrive, (opts.seconds or RA.Warrant) * 0.2)
	else
		for _, c in ipairs(cops) do
			rec.cops[c.UserId] = true
		end
		breachPrompt(rec)
	end
	tell(rec, "Raid", { Until = serverAt(rec.untilAt), Hold = rec.hold, Warrant = opts.seconds or RA.Warrant })
	A.refreshAlarms()
	publish()
	Telemetry.Custom(owner, "BizRaidWarrant_" .. (rec.ai and "AI" or "PvP"), level)
	return rec
end
Raids.Issue = issue

-- Once a second, one raid: who's holding the door, the AI's clocks, the warrant running out.
local function raidTick(rec, dt)
	local A = S.A
	if rec.owner.Parent ~= Players then
		endRaid(rec, "Gone")
		return
	end
	local now = os.clock()
	-- Holding the door: the owner or a crewmate inside.
	local holding = false
	for _, p in ipairs(crewOf(rec.owner)) do
		local root = rootOf(p)
		if root and Businesses.Inside(rec.def, root.Position) then
			holding = true
			rec.inside[p.UserId] = (rec.inside[p.UserId] or 0) + dt
		end
	end
	rec.holding = holding
	if holding then
		rec.defended += dt
	end
	-- A player raid with no eligible cop left before the breach turns into an AI one.
	if not rec.ai and rec.stage == "warrant" and #copsFor(rec.owner) == 0 then
		rec.ai = true
		rec.arriveAt = now + math.min(RA.AIArrive, math.max(5, (rec.untilAt - now) * 0.2))
		dropPrompts(rec)
		tell(rec, "Raid", { Until = serverAt(rec.untilAt), Hold = rec.hold, Switched = true })
	end
	if rec.ai then
		if not rec.unit and now >= (rec.arriveAt or now) then
			spawnUnit(rec, A)
		end
		local unit = rec.unit
		local ready = unit ~= nil and #unit.officers > 0 and unit.officers[1].arrived == true
		if ready then
			if holding then
				if now - unit.sayAt >= K.SAY_GAP then
					unit.sayAt = now
					A.say(unit.officers[1], rec.stage == "warrant" and "Open the door! Police!" or wordsOf(rec).heldSay, 2.5)
				end
			elseif rec.stage == "warrant" then
				rec.breach += dt
				if rec.breach >= RA.AIBreach then
					breached(rec, nil)
				end
			else
				rec.search += dt
				if rec.search >= RA.AISearch then
					seize(rec, nil)
					return
				end
			end
		end
	end
	if now >= rec.untilAt then
		endRaid(rec, rec.defended >= RA.HeldMin and "Held" or "Expired")
	end
end

-- Is this owner the target of a raid somewhere already?
local function ownerRaided(uid)
	for _, rec in pairs(S.raids) do
		if rec.ownerId == uid then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ the hooks the job modules call

function Raids.Init(A)
	S.A = A
	if S.inited then
		return
	end
	S.inited = true
	S.feed = Remotes.Event("Feed")
	ReplicatedStorage:SetAttribute("BizRaids", "{}")
	S.json = "{}"
end

-- A building that can be raided (see the header for the spec).
function Raids.Register(id, spec)
	S.specs[id] = spec or {}
end

function Raids.Registered(id)
	return S.specs[id] ~= nil
end

function Raids.OnSite(id)
	return S.raids[id]
end

-- Once a second for one building: the warrant rolls on its owners, and the raid there.
function Raids.Second(id, dt, A)
	S.A = A
	local def = Businesses.ById[id]
	local spec = specOf(id)
	if not def or not spec then
		return
	end
	if def.Enabled and A.site(def.Id) and not S.raids[def.Id] and os.clock() >= (S.siteFree[def.Id] or 0) then
		local minDirty = spec.minDirty or RA.MinDirty
		for _, p in ipairs(Players:GetPlayers()) do
			local entry = A.owned(p, def.Id)
			local play = A.play(p)
			if entry and play and not S.raids[def.Id] then
				local o = ownerClock(def.Id, p.UserId)
				if play >= o.nextAt then
					o.nextAt = play + RA.Check
					local dirty = stockOf({ id = def.Id }, entry)
					local cap = type(spec.cap) == "function" and spec.cap(entry.level) or nil
					if p:GetAttribute("Side") == "Civilian" and A.alive(p) and dirty >= minDirty and not ownerRaided(p.UserId)
						and A.rng:NextNumber() < Businesses.WarrantChance(dirty, entry.level, cap, minDirty) then
						issue(p, def)
					end
				end
			end
		end
	end
	local rec = S.raids[id]
	if rec then
		local ok, err = pcall(raidTick, rec, dt)
		if not ok then
			warn("[Raids] raid: " .. tostring(err))
			endRaid(rec, "Expired") -- (one broken raid never sticks)
		end
	end
	publish()
end

-- The raid on this player's stock at this building, for BusinessState (nil: none).
function Raids.State(player, id)
	local rec = S.raids[id]
	if rec and rec.ownerId == player.UserId then
		return { Stage = rec.stage, Until = serverAt(rec.untilAt), Ai = rec.ai }
	end
	return nil
end

-- The raid at this building, if this player is part of it (their BizAlarm: the map flashes).
function Raids.Alarms(player, id)
	local rec = S.raids[id]
	if rec and (player == rec.owner or (S.A and S.A.sameCrew(rec.owner, player)) or rec.cops[player.UserId] or eligibleCop(player, rec.owner)) then
		return { id }
	end
	return {}
end

function Raids.PlayerLeft(player, id)
	local rec = S.raids[id]
	if rec and rec.owner == player then
		if rec.stage == "search" then
			seize(rec, nil) -- (no dodging a search by quitting)
		else
			endRaid(rec, "Gone")
		end
	end
	if S.owners[id] then
		S.owners[id][player.UserId] = nil
	end
end

-- Studio: "raid" (a warrant on your stock at this building now; value "ai" or seconds) and "endraid". nil = not ours.
function Raids.Debug(player, cmd, id, value, A)
	S.A = A
	if cmd ~= "raid" and cmd ~= "endraid" then
		return nil
	end
	local def = Businesses.ById[id or ""]
	local spec = specOf(id or "")
	if not def or not spec then
		return nil
	end
	local entry = A.owned(player, def.Id)
	if not entry then
		return "doesn't own " .. def.Id .. " (give it first)"
	end
	if cmd == "endraid" then
		local rec = S.raids[def.Id]
		if not rec then
			return "no raid on"
		end
		endRaid(rec, "Expired")
		return "raid ended"
	end
	if S.raids[def.Id] then
		return "a raid is on already at " .. def.Id
	end
	entry.dirty = math.max(entry.dirty or 0, spec.minDirty or RA.MinDirty)
	local seconds = tonumber(value)
	local rec = issue(player, def, { ai = value == "ai", seconds = seconds and math.clamp(seconds, 20, 600) or nil })
	A.pushState(player)
	local n = 0
	for _ in pairs(rec.cops) do
		n += 1
	end
	return string.format("raid warrant at %s (%s, %ds, %d cop(s) sent)", def.Id, rec.ai and "AI" or "player cops", math.floor(rec.untilAt - os.clock()), n)
end

return Raids
