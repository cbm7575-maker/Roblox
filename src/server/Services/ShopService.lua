-- ShopService (ModuleScript, ServerScriptService.Services.ShopService)
-- Game passes and cash packs (Config.Shop).
--   * Passes: checked on join (UserOwnsGamePassAsync, retried) and after an in-game purchase; owning
--     one sets the player attribute "Pass_<Key>". Perks read that attribute (HeistService, ArrestService,
--     EconomyService, GarageService).
--   * Cash packs: MarketplaceService.ProcessReceipt, idempotent. Each PurchaseId is recorded in the
--     buyer's saved profile (data.receipts) in the same save as the cash, and we only answer
--     PurchaseGranted after that save succeeds. A repeat delivery of a recorded PurchaseId is
--     not paid again, but is still only acknowledged after a successful save (the first save may
--     have failed, leaving the payout in memory only). Buyer not in this server or profile not loaded ->
--     NotProcessedYet (Roblox retries later).
--   * Free for testing and for the game's owner (player attribute "ShopFree" = "Studio" | "Owner",
--     set here, tells the phone to show FREE buttons):
--       Studio (RunService:IsStudio() on the server): every pass and pack is free and instant through
--         RequestShopFree(kind, key), kind = "Pass" | "Product", key = Config.Shop Key.
--       The owner in a live server (the user who owns the game, or rank 255 in the owning group):
--         every pass is granted on join, and cash packs are claimed free through RequestShopFree.
--     Free grants use the same code as purchases: passes set Pass_<Key> and fire PassGranted; packs
--     pay Cash with a "product:<Key>:free" reason and fire CashPackGranted.
--   * Studio: Workspace attribute "TestPasses" (e.g. "VIP,Hypercar") also grants passes on join.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local ShopService = {}

local MAX_RECEIPTS = 100 -- remember this many recent purchase IDs per player

local owners = {} -- [player] = true: the game's owner (checked on join; the server's own record)

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

-- Pay a cash pack (a real receipt, or a free Studio / owner claim).
local function payPack(player, product, free)
	EconomyService.AddCash(player, product.Cash, "product:" .. product.Key .. (free and ":free" or ""))
end

-- Does this player own the game? A user-owned game: its creator. A group game: the group's owner
-- (rank 255). GetRankInGroup is a web call, so it's pcall'd and retried.
local function isOwner(player)
	if game.CreatorId == 0 then
		return false -- unpublished place
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if game.CreatorType == Enum.CreatorType.Group then
		for attempt = 1, 3 do
			local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
			if ok then
				return rank == 255
			end
			task.wait(attempt)
		end
	end
	return false
end

local function checkPasses(player)
	if RunService:IsStudio() then
		player:SetAttribute("ShopFree", "Studio")
	elseif isOwner(player) then
		if player.Parent ~= Players then
			return -- left during the group lookup
		end
		owners[player] = true
		player:SetAttribute("ShopFree", "Owner")
		for _, pass in ipairs(Shop.Passes) do
			grantPass(player, pass) -- the owner's passes are free (quietly, on every join)
		end
		return
	end
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
		-- Already paid out, but maybe only in memory (an earlier save failed): confirm it's saved
		-- before telling Roblox, or a crash before the next autosave loses the purchase for good.
		if not DataService.SaveNow(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	payPack(player, product, false)
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

-- RequestShopFree(kind, key): Studio gets anything free; the owner (live) gets passes and packs free.
-- Everyone else is ignored: they buy through Roblox's own prompt.
local function onFree(player, kind, key)
	if not RateLimit.Allow(player, "ShopFree", 1, 2) or type(kind) ~= "string" or type(key) ~= "string" then
		return
	end
	if not RunService:IsStudio() and not owners[player] then
		return
	end
	if kind == "Pass" then
		local pass = Shop.PassByKey(key)
		if pass then
			grantPass(player, pass, true)
		end
	elseif kind == "Product" then
		local product = Shop.ProductByKey(key)
		if product and DataService.IsLoaded(player) then -- cash before the save loads would be overwritten
			payPack(player, product, true)
			Remotes.Event("CashPackGranted"):FireClient(player, product.Cash)
		end
	end
end

function ShopService.Init()
	Remotes.Event("PassGranted")
	Remotes.Event("CashPackGranted")
	Remotes.Event("RequestShopFree").OnServerEvent:Connect(onFree)
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
	Players.PlayerRemoving:Connect(function(player)
		owners[player] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(checkPasses, p)
	end
end

return ShopService
