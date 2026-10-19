-- RateLimit (ModuleScript, ReplicatedStorage.Shared.Util.RateLimit)
-- Per-player token buckets for remotes. Server-side use:
--   if not RateLimit.Allow(player, "Taser", 2) then return end   -- at most ~2 per second, burst 2
-- Buckets for a player are dropped when they leave.

local Players = game:GetService("Players")

local RateLimit = {}

local buckets = {} -- [player] = { [key] = { tokens, last } }

function RateLimit.Allow(player, key, perSecond, burst)
	burst = burst or math.max(1, perSecond)
	local byKey = buckets[player]
	if not byKey then
		byKey = {}
		buckets[player] = byKey
	end
	local now = os.clock()
	local b = byKey[key]
	if not b then
		b = { tokens = burst, last = now }
		byKey[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * perSecond)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RateLimit
