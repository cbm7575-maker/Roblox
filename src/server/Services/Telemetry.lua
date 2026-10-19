-- Telemetry (ModuleScript, ServerScriptService.Services.Telemetry)
-- Roblox Analytics (Creator Hub > Analytics) in one place. Every call is pcall-wrapped: analytics
-- must never break gameplay.
--   Telemetry.Economy(player, amount, balance, reason)  cash in (+) or out (-), from EconomyService
--   Telemetry.Funnel(player, step, name)                 onboarding funnel (first session)
--   Telemetry.Custom(player, name, value)                gameplay events (heists, arrests, escapes...)
-- Economy transaction types come from the reason prefix (see TYPES).

local AnalyticsService = game:GetService("AnalyticsService")

local Telemetry = {}

-- Transaction type names (looked up safely: a renamed enum item must not break the economy).
local function kind(name)
	local ok, value = pcall(function()
		return Enum.AnalyticsEconomyTransactionType[name].Name
	end)
	return ok and value or name
end
local GAMEPLAY = kind("Gameplay")
local TYPES = { -- reason prefix -> transaction type
	product = kind("IAP"),
	buycar = kind("Shop"),
	paint = kind("Shop"),
	rims = kind("Shop"),
	underglow = kind("Shop"),
	tutorial = kind("Onboarding"),
	daily = kind("TimedReward"),
}

function Telemetry.Economy(player, amount, balance, reason)
	reason = tostring(reason or "other")
	if reason == "debug" or amount == 0 then
		return
	end
	local prefix, item = reason:match("^([^:]+):?(.*)$")
	local transaction = TYPES[prefix] or GAMEPLAY
	pcall(function()
		AnalyticsService:LogEconomyEvent(player,
			amount > 0 and Enum.AnalyticsEconomyFlowType.Source or Enum.AnalyticsEconomyFlowType.Sink,
			"Cash", math.abs(amount), balance, transaction, item ~= "" and item or prefix)
	end)
end

function Telemetry.Funnel(player, step, name)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

function Telemetry.Custom(player, name, value)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

return Telemetry
