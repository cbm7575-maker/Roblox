-- HeistService (ModuleScript, ServerScriptService.Services.HeistService)
-- Runs every heist site in Workspace.Heists (models with a HeistId attribute and a RobPoint part).
--   * Rotation: Heists.OpenCount heist TYPES are open at a time; each stays open 4-6 minutes, then
--     another takes its place. The bank is a server event every 15 minutes with a warning first.
--   * Robbing: hold the Rob prompt for the type's Hold time. The server times the hold itself
--     (PromptButtonHoldBegan -> Triggered), checks side, distance and on-foot, then pays into the bag.
--   * Each robbed site cools down; the alarm reaches cops after the head start (Heists.AlarmDelay).
-- Site attributes (read by clients): Robbable, ReopenAt, AlarmUntil (server time, GetServerTimeNow).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local HeistService = {}

local sitesByType = {} -- [typeId] = { site models }
local typeOpen = {} -- [typeId] = true while open in rotation
local typeCloseAt = {} -- [typeId] = server time it leaves the rotation
local typeRestUntil = {} -- [typeId] = server time before which it can't reopen
local holdStart = {} -- [site] = { [userId] = os.clock() }
local rng = Random.new()

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

local function onRobbed(player, site, def)
	local typeId = site:GetAttribute("HeistId")
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
	local fits = EconomyService.AddCarried(player, payout, "heist:" .. typeId)
	require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "Heist", def.Tier)
	require(ServerScriptService.Services.Telemetry).Custom(player, "Heist_" .. typeId, fits)
	addHeat(player, def.Heat)
	player:SetAttribute("Heists", (player:GetAttribute("Heists") or 0) + 1)
	site:SetAttribute("ReopenAt", now() + def.Cooldown)
	site:SetAttribute("PrepUntil", nil)
	site:SetAttribute("PrepBy", nil)
	site:SetAttribute("LastRobbedBy", player.UserId)
	refreshSite(site)
	heistResult:FireClient(player, { Type = typeId, Payout = fits, BagFull = fits < payout })
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
			if not began or os.clock() - began < prep.Hold - 0.4 or not siteRobbable(site) then
				return
			end
			if def.MinRank and (player:GetAttribute("CivRank") or 1) < def.MinRank then
				notify:FireClient(player, "BankNeedsRank")
				return
			end
			site:SetAttribute("PrepUntil", now() + prep.Window)
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
		holdStart[site][player.UserId] = os.clock()
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
		if def.Prep then
			local by = site:GetAttribute("PrepBy")
			local mine = by ~= nil and (by == player:GetAttribute("Crew") or by == "u" .. player.UserId)
			if not mine or (site:GetAttribute("PrepUntil") or 0) < now() then
				notify:FireClient(player, "NeedPrep_" .. typeId)
				return
			end
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or hum.SeatPart or not root then
			return
		end
		if (root.Position - point.Position).Magnitude > 16 then
			return
		end
		-- The server times the hold; a client that skips it gets nothing.
		if not began or os.clock() - began < def.Hold - 0.4 then
			return
		end
		if not siteRobbable(site) then
			return
		end
		onRobbed(player, site, def)
	end)
	site:SetAttribute("HeistType", typeId)
	site:SetAttribute("Display", def.Display)
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
	end)
end

return HeistService
