-- Signals (ModuleScript, ReplicatedStorage.Shared.Util.Signals)
-- The traffic-signal cycle every device shares: SkyClient lights the lamps, TrafficClient obeys them.
-- 14 s green then 3 s amber for roads running along X, then the same for roads along Z (the other
-- axis is red meanwhile). Timed from the server clock, so every player sees the same lights.
--   Signals.Phase([t]) -> axis ("X" | "Z") that has green or amber now, amber (bool)
--   Signals.AxisOf(dir) -> "X" | "Z": the axis of a road running along `dir` (same rule as Restyle)
--   Signals.State(axis) -> "Green" | "Amber" | "Red" for a road on that axis right now

local Workspace = game:GetService("Workspace")

local Signals = {}

Signals.Green = 14 -- seconds
Signals.Amber = 3

function Signals.Phase(t)
	local half = Signals.Green + Signals.Amber
	local tc = (t or Workspace:GetServerTimeNow()) % (2 * half)
	return tc < half and "X" or "Z", (tc % half) >= Signals.Green
end

function Signals.AxisOf(dir)
	return math.abs(dir.X) > math.abs(dir.Z) and "X" or "Z"
end

function Signals.State(axis)
	local on, amber = Signals.Phase()
	if on ~= axis then
		return "Red"
	end
	return amber and "Amber" or "Green"
end

return Signals
