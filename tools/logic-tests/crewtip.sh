#!/bin/bash
# When the crew tip ("WAY MORE MONEY ... team up with anyone in this server") may come up: Util/CrewTip's
# timing rules on a virtual clock. Pure logic, so it needs no prelude. Every line should read PASS.
H="$(cd "$(dirname "$0")" && pwd)"
L="${LUAU:-luau}" # the Luau CLI (github.com/luau-lang/luau releases); set LUAU to its path
ROOT="$H/../.."
OUT="${TMPDIR:-${TEMP:-/tmp}}/theft-logic-tests"
mkdir -p "$OUT"

read -r -d '' SCENARIO <<'EOF'
local fails = 0
local function check(name, got, want)
	if got == want then
		print("PASS " .. name)
	else
		fails += 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
end
local T = CrewTip

do -- timed: FIRST seconds in, then every GAP
	local s = T.new(100)
	check("timed: nothing before FIRST", T.Due(s, 100 + T.FIRST - 1, true), nil)
	check("timed: due at FIRST", T.Due(s, 100 + T.FIRST, true), "timed")
	check("timed: not while not ready", T.Due(s, 100 + T.FIRST, false), nil)
	T.Shown(s, "timed", 100 + T.FIRST)
	check("timed: not again before GAP", T.Due(s, 100 + T.FIRST + T.GAP - 1, true), nil)
	check("timed: again after GAP", T.Due(s, 100 + T.FIRST + T.GAP, true), "timed")
end

do -- payout: a big cash gain after the session settles, held HOLD seconds for a free moment
	local s = T.new(0)
	T.Payout(s, 5000, T.SETTLE - 1)
	check("payout: the save's first cash is no payout", T.Due(s, T.SETTLE, true), nil)
	T.Payout(s, T.PAYOUT - 1, 70)
	check("payout: a small gain is ignored", T.Due(s, 71, true), nil)
	T.Payout(s, 2500, 70)
	check("payout: waits while busy", T.Due(s, 75, false), nil)
	check("payout: shows once free", T.Due(s, 80, true), "payout")
	T.Shown(s, "payout", 80)
	T.Payout(s, 2500, 80 + T.PAYOUT_GAP - 1)
	check("payout: not again within PAYOUT_GAP", T.Due(s, 80 + T.PAYOUT_GAP, true), nil)
	T.Payout(s, 2500, 80 + T.PAYOUT_GAP)
	check("payout: again after PAYOUT_GAP", T.Due(s, 80 + T.PAYOUT_GAP + 1, true), "payout")
	local s2 = T.new(0)
	T.Payout(s2, 2500, 100)
	check("payout: dropped after HOLD if never free", T.Due(s2, 100 + T.HOLD + 1, true), nil)
	check("payout: the drop clears it", s2.pending, nil)
end

do -- MAX: timed and payout tips stop after MAX a session
	local s = T.new(0)
	local t = T.FIRST
	for i = 1, T.MAX do
		check("max: tip " .. i .. " shows", T.Due(s, t, true), "timed")
		T.Shown(s, "timed", t)
		t += T.GAP
	end
	check("max: no timed tip past MAX", T.Due(s, t, true), nil)
	T.Payout(s, 9000, t + T.PAYOUT_GAP)
	check("max: no payout tip past MAX", T.Due(s, t + T.PAYOUT_GAP + 1, true), nil)
end

do -- LATER twice: timed and payout tips stop; asked-for ones still come
	local s = T.new(0)
	T.Shown(s, "timed", T.FIRST)
	T.Later(s, T.FIRST + 2)
	check("later: one LATER, the next still comes", T.Due(s, T.FIRST + 2 + T.GAP, true), "timed")
	T.Shown(s, "timed", T.FIRST + 2 + T.GAP)
	T.Later(s, T.FIRST + 4 + T.GAP)
	local after = T.FIRST + 4 + 3 * T.GAP
	check("later: two LATERs stop timed tips", T.Due(s, after, true), nil)
	T.Payout(s, 9000, after)
	check("later: ...and payout tips", T.Due(s, after + 1, true), nil)
	T.NeedCrew(s, after + 2)
	check("later: The Big Score refusing still shows it", T.Due(s, after + 3, true), "asked")
end

do -- asked: The Big Score needs a crew
	local s = T.new(0)
	T.NeedCrew(s, 5)
	check("asked: shows at once, even early in the session", T.Due(s, 6, true), "asked")
	T.Shown(s, "asked", 6)
	check("asked: doesn't count toward MAX", s.shown, 0)
	T.NeedCrew(s, 6 + T.ASKED_GAP - 5)
	check("asked: not again within ASKED_GAP", T.Due(s, 6 + T.ASKED_GAP - 4, true), nil)
	check("asked: again once ASKED_GAP is over", T.Due(s, 6 + T.ASKED_GAP, true), "asked")
	local s2 = T.new(0)
	T.NeedCrew(s2, 100)
	T.Payout(s2, 9000, 101)
	check("asked: a payout doesn't replace it", s2.pending, "asked")
	check("asked: waits while the phone is up", T.Due(s2, 102, false), nil)
	check("asked: gone after HOLD", T.Due(s2, 100 + T.HOLD + 1, true), nil)
	check("asked: the timed tip still counts from the session start", T.Due(s2, T.FIRST, true), "timed")
end

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
EOF

F="$OUT/crewtip.luau"
{
	echo "local CrewTip = (function()"
	cat "$ROOT/src/shared/Util/CrewTip.lua"
	echo "end)()"
	echo "$SCENARIO"
} > "$F"
"$L" "$F"
