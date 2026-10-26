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
--   * Offer analytics: remote OfferEvent(action, key) from OfferClient, action "Shown" | "Tapped" |
--     "Hidden", key a Config.Shop.Offers key or "Showroom_<PassKey>" (only for a pass that an AutoNeon
--     pass car sells, e.g. Showroom_Hypercar: that car's dealer card). Logged as Telemetry.Custom
--     OfferShown_<key> / OfferTapped_<key> / OfferHidden_<key>; a pass bought within
--     OFFER_BUY_WINDOW of tapping that offer's BUY also logs OfferBought_<key>. Analytics only: the
--     purchase itself is always Roblox's prompt, confirmed with UserOwnsGamePassAsync.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local ShopService = {}

local MAX_RECEIPTS = 100 -- remember this many recent purchase IDs per player
local OFFER_BUY_WINDOW = 600 -- seconds: a pass bought this soon after tapping an offer's BUY counts for it

local offerTaps = {} -- [player] = { key = offer key, pass = pass key, t = os.clock() } (the last BUY tapped)

-- The pass an offer key sells: a Shop.Offers key, or "Showroom_<PassKey>". nil for anything else.
local function offerPass(key)
	if type(key) ~= "string" or #key > 40 then
		return nil
	end
	local offer = Shop.Offers[key]
	if offer then
		return offer.Pass
	end
	-- Showroom keys only for a pass that a car on AutoNeon's pass turntable sells (the same filter as
	-- DealershipService's), so a client can't log offers no card ever showed.
	local passKey = string.match(key, "^Showroom_(%w+)$")
	if passKey then
		for _, def in ipairs(Vehicles.List) do
			if def.Pass == passKey and not def.Boat and not def.Police and not def.Hidden then
				return passKey
			end
		end
	end
	return nil
end

-- announce = true only for a purchase made just now (not the ownership check on every join).
local function grantPass(player, pass, announce)
	if player:GetAttribute("Pass_" .. pass.Key) then
		return
	end
	player:SetAttribute("Pass_" .. pass.Key, true)
	if announce then
		Remotes.Event("PassGranted"):FireClient(player, pass.Key)
		local tap = offerTaps[player]
		if tap and tap.pass == pass.Key and os.clock() - tap.t <= OFFER_BUY_WINDOW then
			offerTaps[player] = nil
			Telemetry.Custom(player, "OfferBought_" .. tap.key)
		end
	end
end

local function onOfferEvent(player, action, key)
	if not RateLimit.Allow(player, "Offer", 1, 3) or type(action) ~= "string" then
		return
	end
	local passKey = offerPass(key)
	if not passKey then
		return
	end
	if action == "Shown" then
		Telemetry.Custom(player, "OfferShown_" .. key)
	elseif action == "Tapped" then
		offerTaps[player] = { key = key, pass = passKey, t = os.clock() }
		Telemetry.Custom(player, "OfferTapped_" .. key)
	elseif action == "Hidden" then
		Telemetry.Custom(player, "OfferHidden_" .. key)
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
	Remotes.Event("OfferEvent").OnServerEvent:Connect(onOfferEvent)
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
	Players.PlayerRemoving:Connect(function(p)
		offerTaps[p] = nil
	end)
end

return ShopService
