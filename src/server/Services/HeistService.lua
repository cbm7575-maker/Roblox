-- HeistService (ModuleScript, ServerScriptService.Services.HeistService)
-- Runs every heist site in Workspace.Heists (models with a HeistId attribute and a RobPoint part).
--   * Rotation: Heists.OpenCount heist TYPES are open at a time; each stays open 4-6 minutes, then
--     another takes its place. The bank is a server event every 15 minutes with a warning first.
--     A type leaving the rotation (or the bank event ending) shuts its sites for NEW holds only: a hold
--     already running finishes and is paid, unless somebody else emptied that site first.
--   * Robbing: hold the Rob prompt for the type's Hold time. The server times the hold itself
--     (PromptButtonHoldBegan -> Triggered), checks side, distance and on-foot, then pays into the bag.
--   * Each robbed site cools down; the alarm reaches cops after the head start (Heists.AlarmDelay).
--   * Rank-locked heists (MinRank, e.g. the bank): the rank check comes first on both prompts, so a
--     low-rank player who taps the "Rank 3 needed" prompt (HeistClient relabels it) is told why.
--   * Prep (bank fuse box, yacht panel): the main hold only has to START inside the prep window, so
--     the prep is checked when the hold begins (a vault hold already running keeps it). A fresh prep
--     is protected from other crews for PREP_LOCK seconds (time to walk to the vault); after that
--     anyone may redo it. Nobody can refresh their own live prep, so no one can hold the panel
--     forever. Tapping a locked panel says why (HeistClient relabels it "Done" / "Taken").
--   * Big heists (Heists.BigTier: Coastal Bank, Sea Dream) are crew work. The helpers are the robber's
--     Civilian crewmates within Heists.BigCrewRange studs when the robbery pays (cops and prisoners
--     don't count). Each of them and the robber add 1 to the saved stat "BigHeists" (player attribute,
--     DataService), which unlocks the heist-locked cars (Config.Vehicles UnlockHeists, checked by
--     GarageService).
--   * Crew cuts (big heists with 1+ helpers): the pot is the payout as worked out for the robber (night,
--     the robber's VIP, CrewService.BonusFor) x (1 + Heists.CrewShareBonus per helper). Everyone gets
--     floor(pot / (1 + helpers)) in their own bag, and each bag can fill up on its own. Each helper also
--     gets the heist's heat (they were there) and a HeistResult of their own. Only the robber gets the
--     heist XP, the Heists count and the challenge progress (ProgressService.Event is called for the
--     robber alone). Solo robberies and tier 1-2 heists pay exactly what they always did.
--   * HeistResult to the robber: { Type, Payout (what fit), BagFull, LeftBehind (what didn't), Wanted,
--     Crew (1 + helpers) }. A helper's has the same fields plus Cut = true and From (the robber's
--     DisplayName).
-- Site attributes (read by clients): Robbable, ReopenAt, AlarmUntil (server time, GetServerTimeNow),
--   MinRank (free-roam rank needed, if any), PrepUntil / PrepBy / PrepLockUntil (the live prep).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local HeistService = {}

local sitesByType = {} -- [typeId] = { site models }
local typeOpen = {} -- [typeId] = true while open in rotation
local typeCloseAt = {} -- [typeId] = server time it leaves the rotation
local typeRestUntil = {} -- [typeId] = server time before which it can't reopen
local holdStart = {} -- [site] = { [userId] = { t = os.clock(), prepOk = prep was theirs when the hold began, open = the site was robbable then } }
local rng = Random.new()
local PREP_LOCK = 45 -- seconds a fresh prep can't be redone by another crew (capped at the window)
local prepToastAt = {} -- [userId] = os.clock() of the last "PrepTaken" / "PrepAlreadyDone" toast

local feed, notify, heistResult

local function now()
	return Workspace:GetServerTimeNow()
end

-- HeatService is optional until step 2.4; this keeps heists working either way.
local function addHeat(player, amount)
	local ok, HeatService = pcall(require, ServerScriptService.Services:FindFirstChild("HeatService"))
	if ok and HeatService and HeatService.Add then
		HeatService.Add(player, amount, "heist")
	else
		player:SetAttribute("Heat", math.min(5, (player:GetAttribute("Heat") or 0) + amount))
	end
end

local function siteRobbable(site)
	local typeId = site:GetAttribute("HeistId")
	return typeOpen[typeId] == true and now() >= (site:GetAttribute("ReopenAt") or 0)
end

-- True while this site's prep was done by this player or their crew and its window is still open.
local function prepIsMine(site, player)
	local by = site:GetAttribute("PrepBy")
	local mine = by ~= nil and (by == player:GetAttribute("Crew") or by == "u" .. player.UserId)
	return mine and (site:GetAttribute("PrepUntil") or 0) >= now()
end

-- Why a prep panel said no; at most one toast every 3 s, so tapping the panel can't stack them.
local function prepRefused(player, key)
	local t = os.clock()
	if t - (prepToastAt[player.UserId] or -math.huge) >= 3 then
		prepToastAt[player.UserId] = t
		notify:FireClient(player, key)
	end
end

local function refreshSite(site)
	-- The prompt stays enabled on the server; each client shows it only to robbers when the site is
	-- Robbable (HeistClient). Triggered re-checks everything here.
	local robbable = siteRobbable(site)
	if site:GetAttribute("Robbable") ~= robbable then
		site:SetAttribute("Robbable", robbable)
	end
end

local function setTypeOpen(typeId, open)
	typeOpen[typeId] = open or nil
	for _, site in ipairs(sitesByType[typeId] or {}) do
		site:SetAttribute("TypeOpen", open)
		refreshSite(site)
	end
end

-- Keep OpenCount rotating heist types open.
local function rotate()
	local t = now()
	local openCount = 0
	for typeId, def in pairs(Heists.Types) do
		if not def.Event and typeOpen[typeId] then
			if t >= (typeCloseAt[typeId] or math.huge) then
				setTypeOpen(typeId, false)
				typeRestUntil[typeId] = t + 90
			else
				openCount += 1
			end
		end
	end
	local candidates = {}
	for typeId, def in pairs(Heists.Types) do
		if not def.Event and not typeOpen[typeId] and sitesByType[typeId] and t >= (typeRestUntil[typeId] or 0) then
			table.insert(candidates, typeId)
		end
	end
	while openCount < Heists.OpenCount and #candidates > 0 do
		local typeId = table.remove(candidates, rng:NextInteger(1, #candidates))
		typeCloseAt[typeId] = t + rng:NextInteger(240, 360)
		setTypeOpen(typeId, true)
		openCount += 1
		feed:FireAllClients("HeistOpen", { Type = typeId })
	end
	for _, sites in pairs(sitesByType) do
		for _, site in ipairs(sites) do
			refreshSite(site)
		end
	end
end

-- The bank opens as a server-wide event.
local function bankLoop()
	local sites = sitesByType.CoastalBank
	if not sites then
		return
	end
	local first = game:GetService("RunService"):IsStudio() and 90 or Heists.BankEvery
	local opensAt = now() + first
	ReplicatedStorage:SetAttribute("BankOpensAt", opensAt)
	while true do
		task.wait(1)
		local t = now()
		if not typeOpen.CoastalBank and t >= opensAt - Heists.BankWarning and not ReplicatedStorage:GetAttribute("BankWarned") then
			ReplicatedStorage:SetAttribute("BankWarned", true)
			feed:FireAllClients("BankSoon", { OpensAt = opensAt })
		end
		if not typeOpen.CoastalBank and t >= opensAt then
			typeCloseAt.CoastalBank = t + Heists.BankOpenFor
			for _, site in ipairs(sites) do
				site:SetAttribute("ReopenAt", 0)
			end
			setTypeOpen("CoastalBank", true)
			feed:FireAllClients("BankOpen", {})
		elseif typeOpen.CoastalBank and (t >= typeCloseAt.CoastalBank or not siteRobbable(sites[1])) then
			setTypeOpen("CoastalBank", false)
			opensAt = t + Heists.BankEvery
			ReplicatedStorage:SetAttribute("BankOpensAt", opensAt)
			ReplicatedStorage:SetAttribute("BankWarned", false)
		end
	end
end

-- One more big heist for this player (only once their save has loaded, or the load would overwrite it).
local function addBigHeist(p, typeId)
	if not p:GetAttribute("DataLoaded") then
		return
	end
	local n = (p:GetAttribute("BigHeists") or 0) + 1
	p:SetAttribute("BigHeists", n)
	require(ServerScriptService.Services.Telemetry).Custom(p, "BigHeist_" .. typeId, n)
end

-- The robber's helpers on a big heist: every Civilian crewmate within BigCrewRange studs of them right
-- now (on the fuse box, at the door). Cops and prisoners don't count. Empty for a robber with no crew.
local function bigHelpers(player)
	local helpers = {}
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local crew = require(ServerScriptService.Services.CrewService).CrewOf(player)
	if not root or not crew then
		return helpers
	end
	for _, mate in ipairs(crew.members) do
		local r = mate ~= player and mate:GetAttribute("Side") == "Civilian" and mate.Character
			and mate.Character:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - root.Position).Magnitude <= Heists.BigCrewRange then
			table.insert(helpers, mate)
		end
	end
	return helpers
end

-- The robber and every helper get the credit.
local function creditBigHeist(player, typeId, helpers)
	addBigHeist(player, typeId)
	for _, mate in ipairs(helpers) do
		addBigHeist(mate, typeId)
	end
end

-- A helper's cut of a big heist: into their own bag (it may not all fit), the heist's heat, and a
-- result stamp of their own. No XP: that stays with the robber.
local function payCut(mate, robber, typeId, def, cut, crewSize)
	local fits = EconomyService.AddCarried(mate, cut, "heistcut:" .. typeId)
	require(ServerScriptService.Services.Telemetry).Custom(mate, "HeistCut_" .. typeId, fits)
	addHeat(mate, def.Heat)
	heistResult:FireClient(mate, {
		Type = typeId, Payout = fits, BagFull = fits < cut, LeftBehind = cut - fits,
		Wanted = (mate:GetAttribute("Heat") or 0) > 0, Crew = crewSize, Cut = true, From = robber.DisplayName,
	})
end

local function onRobbed(player, site, def)
	local typeId = site:GetAttribute("HeistId")
	local big = def.Tier == Heists.BigTier
	local payout = rng:NextInteger(def.Payout[1], def.Payout[2])
	-- Neon nights: heists pay 25% more after dark (WorldService sets IsNight).
	if Workspace:GetAttribute("IsNight") then
		payout = math.floor(payout * 1.25)
	end
	if player:GetAttribute("Pass_VIP") then
		payout = math.floor(payout * (1 + Shop.VIPCashBonus))
	end
	-- Crewmate nearby +20%, friend in the server +10% (CrewService).
	local bonus = require(ServerScriptService.Services.CrewService).BonusFor(player)
	if bonus > 0 then
		payout = math.floor(payout * (1 + bonus))
	end
	-- Big heist with crew helping: the pot grows by CrewShareBonus per helper and is split evenly (the
	-- helpers are looked for once, here, so the cuts and the BigHeists credit go to the same people).
	local helpers = big and bigHelpers(player) or {}
	local crewSize = 1 + #helpers
	if #helpers > 0 then
		local pot = payout * (1 + (Heists.CrewShareBonus or 0.5) * #helpers)
		payout = math.floor(pot / crewSize)
	end
	local fits = EconomyService.AddCarried(player, payout, "heist:" .. typeId)
	require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "Heist", def.Tier)
	require(ServerScriptService.Services.Telemetry).Custom(player, "Heist_" .. typeId, fits)
	addHeat(player, def.Heat)
	player:SetAttribute("Heists", (player:GetAttribute("Heists") or 0) + 1)
	if big then
		creditBigHeist(player, typeId, helpers)
	end
	site:SetAttribute("ReopenAt", now() + def.Cooldown)
	site:SetAttribute("PrepUntil", nil)
	site:SetAttribute("PrepBy", nil)
	site:SetAttribute("PrepLockUntil", nil)
	site:SetAttribute("LastRobbedBy", player.UserId)
	refreshSite(site)
	heistResult:FireClient(player, {
		Type = typeId, Payout = fits, BagFull = fits < payout, LeftBehind = payout - fits,
		Wanted = (player:GetAttribute("Heat") or 0) > 0, Crew = crewSize,
	})
	for _, mate in ipairs(helpers) do
		payCut(mate, player, typeId, def, payout, crewSize)
	end
	feed:FireAllClients("HeistStarted", { Type = typeId, Site = site.Name })
	-- Head start, then the alarm goes out to the cops.
	task.delay(Heists.AlarmDelay, function()
		if site.Parent then
			site:SetAttribute("AlarmUntil", now() + Heists.AlarmSeconds)
			feed:FireAllClients("HeistAlarm", { Type = typeId, Site = site.Name, Position = site:GetPivot().Position })
		end
	end)
end

local function hookSite(site)
	local typeId = site:GetAttribute("HeistId")
	local def = Heists.Types[typeId]
	local point = site:FindFirstChild("RobPoint", true)
	if not def or not point then
		warn("[HeistService] site " .. site.Name .. " is missing a type or a RobPoint")
		return
	end
	sitesByType[typeId] = sitesByType[typeId] or {}
	table.insert(sitesByType[typeId], site)
	holdStart[site] = {}

	local prompt = point:FindFirstChild("RobPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "RobPrompt"
	prompt.ActionText = "Rob"
	prompt.ObjectText = def.Display
	prompt.HoldDuration = def.Hold
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = true
	prompt.Parent = point

	-- Prep step (bank fuse box, yacht alarm panel): must be done first, by you or a crewmate.
	if def.Prep then
		local prep = def.Prep
		local panel = site:FindFirstChild("PrepPanel") or Instance.new("Part")
		panel.Name = "PrepPanel"
		panel.Anchored = true
		panel.CanCollide = false
		panel.Size = Vector3.new(3, 4, 0.8)
		panel.CFrame = CFrame.lookAt(prep.Pos, prep.Pos + prep.Facing)
		panel.Color = Color3.fromRGB(40, 44, 60)
		panel.Material = Enum.Material.Metal
		panel.Parent = site
		local light = panel:FindFirstChild("Light") or Instance.new("Part")
		light.Name = "Light"
		light.Anchored = true
		light.CanCollide = false
		light.Size = Vector3.new(2.2, 0.5, 0.2)
		light.CFrame = panel.CFrame * CFrame.new(0, 1.2, -0.5)
		light.Material = Enum.Material.Neon
		light.Color = Color3.fromRGB(255, 60, 60)
		light.Parent = panel
		local pp = panel:FindFirstChild("PrepPrompt") or Instance.new("ProximityPrompt")
		pp.Name = "PrepPrompt"
		pp.ActionText = prep.Action
		pp.ObjectText = prep.Object
		pp.HoldDuration = prep.Hold
		pp.MaxActivationDistance = 10
		pp.RequiresLineOfSight = false
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.Parent = panel
		local prepStart = {}
		pp.PromptButtonHoldBegan:Connect(function(player)
			prepStart[player.UserId] = os.clock()
		end)
		pp.Triggered:Connect(function(player)
			local began = prepStart[player.UserId]
			prepStart[player.UserId] = nil
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if player:GetAttribute("Side") ~= "Civilian" or not root or (root.Position - panel.Position).Magnitude > 16 then
				return
			end
			-- On foot only, like the vault itself. (PromptGate hides this prompt from anyone seated; this is
			-- for a hold begun just before sitting down, and for clients that skip the gate.)
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then
				return
			end
			if hum.SeatPart then
				if RateLimit.Allow(player, "GetOutFirstToast", 1 / 3, 1) then
					notify:FireClient(player, "GetOutFirst")
				end
				return
			end
			-- Rank first: a tap on the relabelled "Rank 3 needed" prompt explains why.
			if def.MinRank and (player:GetAttribute("CivRank") or 1) < def.MinRank then
				notify:FireClient(player, "BankNeedsRank")
				return
			end
			if not siteRobbable(site) then
				return
			end
			-- Checked before the hold time so a tap on the relabelled "Done" / "Taken" prompt explains.
			-- Your own live prep can't be refreshed (that would keep the panel locked forever); another
			-- crew's is off limits only while it's fresh, then anyone may take it over.
			if (site:GetAttribute("PrepUntil") or 0) > now() then
				if prepIsMine(site, player) then
					prepRefused(player, "PrepAlreadyDone")
					return
				end
				if now() < (site:GetAttribute("PrepLockUntil") or 0) then
					prepRefused(player, "PrepTaken")
					return
				end
			end
			if not began or os.clock() - began < prep.Hold - 0.4 then
				return
			end
			site:SetAttribute("PrepUntil", now() + prep.Window)
			site:SetAttribute("PrepLockUntil", now() + math.min(PREP_LOCK, prep.Window))
			site:SetAttribute("PrepBy", player:GetAttribute("Crew") or ("u" .. player.UserId))
			light.Color = Color3.fromRGB(110, 242, 196)
			Remotes.Event("HeistPrep"):FireClient(player, { Text = prep.Done })
			task.delay(prep.Window, function()
				if (site:GetAttribute("PrepUntil") or 0) <= now() then
					light.Color = Color3.fromRGB(255, 60, 60)
				end
			end)
		end)
	end

	prompt.PromptButtonHoldBegan:Connect(function(player)
		holdStart[site][player.UserId] = {
			t = os.clock(), prepOk = def.Prep ~= nil and prepIsMine(site, player), open = siteRobbable(site),
		}
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		task.defer(function()
			holdStart[site][player.UserId] = nil
		end)
	end)
	prompt.Triggered:Connect(function(player)
		local began = holdStart[site][player.UserId]
		holdStart[site][player.UserId] = nil
		if player:GetAttribute("Side") ~= "Civilian" then
			return
		end
		if def.MinRank and (player:GetAttribute("CivRank") or 1) < def.MinRank then
			notify:FireClient(player, "BankNeedsRank")
			return
		end
		-- The hold only has to start inside the prep window, so what was true then counts (for a hold
		-- that really just ran its length), or a prep a crewmate finished during the hold.
		local prepAtStart = began ~= nil and began.prepOk and os.clock() - began.t < def.Hold + 5
		if def.Prep and not prepAtStart and not prepIsMine(site, player) then
			notify:FireClient(player, "NeedPrep_" .. typeId)
			return
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or not root then
			return
		end
		if hum.SeatPart then
			-- Sitting in a car (a hold begun just before sitting down): say so, not nothing.
			if RateLimit.Allow(player, "GetOutFirstToast", 1 / 3, 1) then
				notify:FireClient(player, "GetOutFirst")
			end
			return
		end
		if (root.Position - point.Position).Magnitude > 16 then
			return
		end
		-- The server times the hold; a client that skips it gets nothing.
		if not began or os.clock() - began.t < def.Hold - 0.4 then
			return
		end
		-- A store shuts for NEW holds only. Its type could leave the rotation (or the bank event end) in
		-- the middle of a hold, and the robber got nothing and no reason why: a hold that began while the
		-- site was open, and really just ran its length, is still paid. The site's own cooldown counts
		-- as always, so a second robber on a till somebody just emptied goes home with nothing.
		local openAtStart = began.open and os.clock() - began.t < def.Hold + 5
		if not siteRobbable(site) and not (openAtStart and now() >= (site:GetAttribute("ReopenAt") or 0)) then
			return
		end
		onRobbed(player, site, def)
	end)
	site:SetAttribute("HeistType", typeId)
	site:SetAttribute("Display", def.Display)
	site:SetAttribute("MinRank", def.MinRank) -- nil for heists anyone can do
	refreshSite(site)
end

function HeistService.IsAlarmActive(site)
	return now() < (site:GetAttribute("AlarmUntil") or 0)
end

function HeistService.Init()
	feed = Remotes.Event("Feed")
	notify = Remotes.Event("Notify")
	heistResult = Remotes.Event("HeistResult")
	Remotes.Event("HeistPrep")
	for _, site in ipairs(Workspace.Heists:GetChildren()) do
		if site:GetAttribute("HeistId") then
			hookSite(site)
		end
	end
	task.spawn(function()
		while true do
			rotate()
			task.wait(Heists.RotateEvery)
		end
	end)
	-- Cooldowns end on their own; re-check sites every second so prompts re-enable on time.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, sites in pairs(sitesByType) do
				for _, site in ipairs(sites) do
					refreshSite(site)
				end
			end
		end
	end)
	task.spawn(bankLoop)
	Players.PlayerRemoving:Connect(function(player)
		for _, map in pairs(holdStart) do
			map[player.UserId] = nil
		end
		prepToastAt[player.UserId] = nil
	end)
end

return HeistService
