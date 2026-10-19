-- ShopClient (ModuleScript, StarterPlayerScripts.Controllers.ShopClient)
-- Purchase celebrations (pass unlocked, cash pack delivered), the daily streak reward, and the gold
-- [VIP] chat tag for any player with the VIP pass (TextChatService prefix, local display only).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local ShopClient = {}

local GOLD = Color3.fromRGB(255, 214, 10)
local MINT = Color3.fromRGB(110, 242, 196)

function ShopClient.Init()
	Remotes.OnClient("PassGranted", function(key)
		for _, pass in ipairs(Shop.Passes) do
			if pass.Key == key then
				HUDController.Stamp(string.upper(pass.Name) .. " UNLOCKED", pass.Perk, GOLD)
			end
		end
	end)
	Remotes.OnClient("CashPackGranted", function(cash)
		HUDController.Stamp("CASH DELIVERED", "+" .. HUDController.Money(cash), MINT)
	end)
	Remotes.OnClient("DailyReward", function(r)
		task.wait(1.5)
		HUDController.Stamp("DAY " .. r.Streak .. " STREAK!", "+" .. HUDController.Money(r.Cash)
			.. "  ·  come back tomorrow for " .. HUDController.Money(r.Next), GOLD)
		if r.Unlocked then
			task.wait(3)
			NotifyController.Show("7-day streak! Streak Sunset paint unlocked in your Garage.", GOLD)
		end
	end)
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		local prefix = message.PrefixText
		if sender and sender:GetAttribute("Title") then
			prefix = '<font color="#22E1FF">[' .. sender:GetAttribute("Title") .. ']</font> ' .. prefix
		end
		if sender and sender:GetAttribute("Pass_VIP") then
			prefix = '<font color="#FFD60A">[VIP]</font> ' .. prefix
		end
		props.PrefixText = prefix
		return props
	end
end

return ShopClient
