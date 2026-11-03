#!/bin/bash
# Builds one Luau file per scenario: prelude + DataService source (as a function) + scenario, and runs it.
H="$(cd "$(dirname "$0")" && pwd)"
L="${LUAU:-luau}" # the Luau CLI (github.com/luau-lang/luau releases); set LUAU to its path
SRC="${1:-$H/../../src/server/Services/DataService.lua}" # another copy of DataService.lua to test, if given
OUT="${TMPDIR:-${TEMP:-/tmp}}/theft-logic-tests"
mkdir -p "$OUT"

scenario() {
	local name="$1" body="$2"
	local f="$OUT/ds_$name.luau"
	{
		cat "$H/prelude.luau"
		echo "local DataService = (function()"
		cat "$SRC"
		echo "end)()"
		echo "DataService.Init()"
		echo "local function writesFor(key, after) local n = 0 for _, w in ipairs(STORE.writes) do if w.key == key and w.t > (after or -1) then n += 1 end end return n end"
		echo "local function lastWrite(key) local last for _, w in ipairs(STORE.writes) do if w.key == key then last = w end end return last end"
		echo "$body"
		echo 'if ERRORS then print("FAIL coroutine errors: " .. ERRORS) end'
		echo 'for _, l in ipairs(LOG) do print("  log: " .. l) end'
	} > "$f"
	echo "== $name"
	"$L" "$f" 2>&1
}

scenario normal_join_leave '
local p = newPlayer(1)
join(p)
runUntil(5)
check("loaded", p:GetAttribute("DataLoaded") == true)
check("locked by this server", STORE.data.p_1.lock and STORE.data.p_1.lock.job == "jobA")
p:SetAttribute("Cash", 500)
leave(p)
runUntil(20)
check("one write on leave", writesFor("p_1", 5) == 1, writesFor("p_1", 5))
check("released with cash", STORE.data.p_1.lock == nil and STORE.data.p_1.cash == 500, STORE.data.p_1.cash)
check("profile dropped", DataService.Get(p) == nil)'

scenario shutdown_dedupe '
local a, b = newPlayer(1), newPlayer(2)
join(a) join(b)
runUntil(5)
a:SetAttribute("Cash", 111) b:SetAttribute("Cash", 222)
-- Shutdown: BindToClose and PlayerRemoving fire together.
runClose()
leave(a) leave(b)
runUntil(40)
check("one final write for a", writesFor("p_1", 5) == 1, writesFor("p_1", 5))
check("one final write for b", writesFor("p_2", 5) == 1, writesFor("p_2", 5))
check("both released", STORE.data.p_1.lock == nil and STORE.data.p_2.lock == nil)
check("cash saved", STORE.data.p_1.cash == 111 and STORE.data.p_2.cash == 222)'

scenario leave_save_retried '
local p = newPlayer(1)
join(p)
runUntil(5)
p:SetAttribute("Cash", 777)
STORE.failNext = 5 -- the first round (4 tries) fails, and the first try of the retry
leave(p)
runUntil(15)
check("profile kept while retrying", DataService.Get(p) ~= nil)
runUntil(60)
check("saved after retry", STORE.data.p_1.cash == 777 and STORE.data.p_1.lock == nil, STORE.data.p_1.cash)
check("profile dropped after", DataService.Get(p) == nil)
local gaveUp = false for _, l in ipairs(LOG) do if l:find("gave up") then gaveUp = true end end
check("did not give up", not gaveUp)'

scenario leave_save_gives_up '
local p = newPlayer(1)
join(p)
runUntil(5)
STORE.failNext = 1000
leave(p)
runUntil(200)
local gaveUp = false for _, l in ipairs(LOG) do if l:find("gave up") then gaveUp = true end end
check("gave up with a warning", gaveUp)
check("profile dropped", DataService.Get(p) == nil)'

scenario lock_fresh_elsewhere_stolen_after_20s '
STORE.data.p_1 = { cash = 100, lock = { job = "jobB", time = os.time() } }
local p = newPlayer(1)
join(p)
runUntil(15)
check("still waiting at 15 s", p:GetAttribute("DataLoaded") ~= true)
runUntil(30)
check("taken over by 30 s", p:GetAttribute("DataLoaded") == true and p:GetAttribute("Cash") == 100)
check("now locked by this server", STORE.data.p_1.lock.job == "jobA")'

scenario lock_released_by_other_server '
STORE.data.p_1 = { cash = 100, lock = { job = "jobB", time = os.time() } }
local p = newPlayer(1)
join(p)
runUntil(6)
STORE.data.p_1.lock = nil -- the other server finished its last save
runUntil(12)
check("loaded soon after the release", p:GetAttribute("DataLoaded") == true)'

scenario left_during_load_unlocks '
STORE.latency = 2
local p = newPlayer(1)
join(p)
runUntil(1)
leave(p)
runUntil(20)
check("lock given back", STORE.data.p_1 and STORE.data.p_1.lock == nil)
check("no profile", DataService.Get(p) == nil)'

scenario autosave_retry_after_leave_no_relock '
local p = newPlayer(1)
join(p)
runUntil(59.9)
STORE.failNext = 1 -- the autosave at 60 s fails once, then retries after 1 s
runUntil(60.3)
leave(p)
runUntil(90)
check("final state released", STORE.data.p_1.lock == nil, lastWrite("p_1").lock)'

scenario save_now_still_locks_while_playing '
local p = newPlayer(1)
join(p)
runUntil(5)
task.spawn(function() OKSAVE = DataService.SaveNow(p) end)
runUntil(10)
check("SaveNow true", OKSAVE == true)
check("still locked while playing", STORE.data.p_1.lock and STORE.data.p_1.lock.job == "jobA")'

scenario other_server_owns_record_cancelled '
local p = newPlayer(1)
join(p)
runUntil(5)
STORE.data.p_1.lock = { job = "jobB", time = os.time() } -- another server took it over
leave(p)
runUntil(60)
check("did not clobber", STORE.data.p_1.lock.job == "jobB")
check("no retries for a cancelled save", writesFor("p_1", 5) == 0)'
