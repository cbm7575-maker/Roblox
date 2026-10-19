-- ShopService (ModuleScript, ServerScriptService.Services.ShopService)
-- Game passes and cash packs (Config.Shop).
--   * Passes: checked on join (UserOwnsGamePassAsync, retried) and after an in-game purchase; owning
--     one sets the player attribute "Pass_<Key>". Perks read that attribute (HeistService, ArrestService,
--     EconomyService, GarageService).
--   * Cash packs: MarketplaceService.ProcessReceipt, idempotent. Each PurchaseId is recorded in the
--     buyer's saved profile (data.receipts) in the same save as the cash, and we only answer
--     PurchaseGranted after that save succeeds. A repeat delivery of a recorded PurchaseId is
--     acknowledged without paying again. Buyer not in this server or profile not loaded ->
--     NotProcessedYet (Roblox retries later).
--   * Studio: Workspace attribute "TestPasses" (e.g. "VIP,Hypercar") grants passes for testing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local ShopService = {}

local MAX_RECEIPTS = 100 -- remember this many recent purchase IDs per player

-- announce = true only for a purchase made just now (not the ownership check on every join).
local function grantPass(player, pass, announce)
	if player:GetAttribute("Pass_" .. pass.Key) then
		return
	end
	player:SetAttribute("Pass_" .. pass.Key, true)
	if announce then
		Remotes.Event("PassGranted"):FireClient(player, pass.Key)
	end
end

local function checkPasses(player)
	for _, pass in ipairs(Shop.Passes) do
		if pass.Id ~= 0 then
			for attempt = 1, 3 do
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
				if ok then
					if owns then
						grantPass(player, pass)
					end
					break
				end
				task.wait(attempt)
			end
		end
	end
	if RunService:IsStudio() then
		for key in string.gmatch(Workspace:GetAttribute("TestPasses") or "", "[^,%s]+") do
			for _, pass in ipairs(Shop.Passes) do
				if pass.Key == key then
					grantPass(player, pass)
				end
			end
		end
	end
end

function ShopService.Has(player, key)
	return player:GetAttribute("Pass_" .. key) == true
end

local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player or not DataService.IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = Shop.ProductById(info.ProductId)
	if not product then
		warn("[ShopService] unknown product " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.Get(player)
	data.receipts = data.receipts or {}
	local id = tostring(info.PurchaseId)
	if data.receipts[id] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already paid out
	end
	EconomyService.AddCash(player, product.Cash, "product:" .. product.Key)
	data.receipts[id] = os.time()
	-- Keep the list short: drop the oldest entries.
	local ids = {}
	for k, t in pairs(data.receipts) do
		table.insert(ids, { k = k, t = t })
	end
	if #ids > MAX_RECEIPTS then
		table.sort(ids, function(a, b)
			return a.t < b.t
		end)
		for i = 1, #ids - MAX_RECEIPTS do
			data.receipts[ids[i].k] = nil
		end
	end
	if not DataService.SaveNow(player) then
		-- Cash and receipt are in memory, so a retry in this session won't double-pay; if the server
		-- dies before a save, neither was saved and the retry pays correctly.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Remotes.Event("CashPackGranted"):FireClient(player, product.Cash)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.Init()
	Remotes.Event("PassGranted")
	Remotes.Event("CashPackGranted")
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = Shop.PassById(passId)
		if not purchased or not pass then
			return
		end
		-- Don't trust the signal alone: confirm the purchase with Roblox before granting.
		for attempt = 1, 4 do
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok then
				if owns then
					grantPass(player, pass, true)
				end
				return
			end
			task.wait(attempt)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkPasses, player)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(checkPasses, p)
	end
end

return ShopService
