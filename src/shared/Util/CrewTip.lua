-- CrewTip (ModuleScript, ReplicatedStorage.Shared.Util.CrewTip)
-- When CrewClient's crew tip may come up for a player with no crew. The tip is a card in the crew invite's
-- spot: "MAKE WAY MORE MONEY", what a crew earns on The Big Score, and that anyone in the server can be
-- your crewmate (FIND A CREW opens PHONE > CREW, where everyone here has an INVITE button).
-- Plain logic with no Roblox calls, so tools/logic-tests/crewtip.sh runs it. CrewClient passes os.clock()
-- for `now`, and `ready` when it could show the tip right now. Ready means:
--   * the player has no crew and is in free roam, past the tutorial and not busy;
--   * nothing else is in the card's spot;
--   * someone else in the server is in free roam to team up with.
--   * Timed: FIRST seconds into the session, then at most every GAP seconds.
--   * After a payout: a cash gain of PAYOUT or more (a solo job just paid). It shows within HOLD seconds,
--     once PAYOUT_GAP has passed since the last tip and the session is past SETTLE seconds (the first cash
--     the save loads is no payout).
--   * Asked for: The Big Score refused to start for want of a crew (Notify "BigScoreNeedCrew"). It shows
--     within HOLD seconds, at most every ASKED_GAP seconds.
--   * At most MAX timed and payout tips a session. LATER pressed LATERS times stops them for the session.
--     Asked-for tips still come, because the player went looking for the heist.

local CrewTip = {}

CrewTip.FIRST = 180
CrewTip.GAP = 480
CrewTip.PAYOUT = 1000
CrewTip.PAYOUT_GAP = 240
CrewTip.SETTLE = 60
CrewTip.HOLD = 25
CrewTip.ASKED_GAP = 20
CrewTip.MAX = 3
CrewTip.LATERS = 2

function CrewTip.new(now)
	return { started = now, shown = 0, lastAt = -math.huge, laters = 0, pending = nil, pendingUntil = 0 }
end

-- The player's cash went up by `amount`.
function CrewTip.Payout(s, amount, now)
	if type(amount) ~= "number" or amount < CrewTip.PAYOUT or now - s.started < CrewTip.SETTLE then
		return
	end
	if now - s.lastAt < CrewTip.PAYOUT_GAP or s.pending == "asked" then
		return
	end
	s.pending, s.pendingUntil = "payout", now + CrewTip.HOLD
end

-- The Big Score said it needs a crew.
function CrewTip.NeedCrew(s, now)
	s.pending, s.pendingUntil = "asked", now + CrewTip.HOLD
end

-- What to show now: "asked", "payout", "timed", or nil for nothing.
function CrewTip.Due(s, now, ready)
	if s.pending and now > s.pendingUntil then
		s.pending = nil
	end
	if not ready then
		return nil
	end
	if s.pending == "asked" then
		return now - s.lastAt >= CrewTip.ASKED_GAP and "asked" or nil
	end
	if s.shown >= CrewTip.MAX or s.laters >= CrewTip.LATERS then
		s.pending = nil
		return nil
	end
	if s.pending == "payout" then
		return "payout"
	end
	if now - s.started >= CrewTip.FIRST and now - s.lastAt >= CrewTip.GAP then
		return "timed"
	end
	return nil
end

-- The tip came up (why = what Due returned).
function CrewTip.Shown(s, why, now)
	s.lastAt = now
	s.pending = nil
	if why ~= "asked" then
		s.shown += 1
	end
end

-- LATER was pressed.
function CrewTip.Later(s, now)
	s.laters += 1
	s.lastAt = now
end

return CrewTip
