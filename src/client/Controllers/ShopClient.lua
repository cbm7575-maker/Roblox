-- ShopClient (ModuleScript, StarterPlayerScripts.Controllers.ShopClient)
-- Purchase moments (pass unlocked, cash pack delivered), the daily streak reward, and the [VIP] chat tag
-- for any player with the VIP pass (TextChatService prefix, local display only). It builds no screens
-- of its own: the moments are HUDController stamps and toasts, in the Theme's colours (gold = a reward
-- or unlock, green = cash), and the chat tags use the same two (gold [VIP], quiet grey rank title).
-- The SHOP page itself lives in the phone (PhoneUI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local ShopClient = {}

local C = Theme.Color
local VIP_HEX = "#" .. C.Gold:ToHex()
local TITLE_HEX = "#" .. C.Dim:ToHex()

function ShopClient.Init()
	Remotes.OnClient("PassGranted", function(key)
		for _, pass in ipairs(Shop.Passes) do
			if pass.Key == key then
				HUDController.Stamp(string.upper(pass.Name) .. " UNLOCKED", pass.Perk, C.Gold)
			end
		end
	end)
	Remotes.OnClient("CashPackGranted", function(cash)
		HUDController.Stamp("CASH DELIVERED", "+" .. HUDController.Money(cash), C.Cash)
	end)
	Remotes.OnClient("DailyReward", function(r)
		task.wait(1.5)
		HUDController.Stamp("DAY " .. r.Streak .. " STREAK", "+" .. HUDController.Money(r.Cash)
			.. "  ·  come back tomorrow for " .. HUDController.Money(r.Next), C.Gold)
		if r.Unlocked then
			task.wait(3)
			NotifyController.Show("7-day streak! Streak Sunset paint unlocked in your Garage.", C.Gold, "success")
		end
	end)
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		local prefix = message.PrefixText
		if sender and sender:GetAttribute("Title") then
			prefix = '<font color="' .. TITLE_HEX .. '">[' .. sender:GetAttribute("Title") .. ']</font> ' .. prefix
		end
		if sender and sender:GetAttribute("Pass_VIP") then
			prefix = '<font color="' .. VIP_HEX .. '">[VIP]</font> ' .. prefix
		end
		props.PrefixText = prefix
		return props
	end
end

return ShopClient
