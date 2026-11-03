#!/bin/bash
# ShopService logic tests: prelude + stubs + ShopService source (as a function) + scenario.
H="$(cd "$(dirname "$0")" && pwd)"
L="${LUAU:-luau}" # the Luau CLI (github.com/luau-lang/luau releases); set LUAU to its path
SRC="${1:-$H/../../src/server/Services/ShopService.lua}" # another copy of ShopService.lua to test, if given
OUT="${TMPDIR:-${TEMP:-/tmp}}/theft-logic-tests"
mkdir -p "$OUT"

STUBS='
Enum = {
	ProductPurchaseDecision = { NotProcessedYet = "NotProcessedYet", PurchaseGranted = "PurchaseGranted" },
	CreatorType = { User = "User", Group = "Group" },
}
game.CreatorId = 999
game.CreatorType = "User"
local remotes = {}
local Remotes = { __module = true }
function Remotes.Event(name)
	remotes[name] = remotes[name] or { OnServerEvent = newSignal(), FireClient = function() end }
	return remotes[name]
end
local RateLimit = { __module = true, Allow = function() return true end }
SHOPCFG = { __module = true,
	Passes = { { Key = "VIP", Id = 42, Price = 499, Name = "VIP" } },
	Products = { { Key = "Cash1", Id = 7, Price = 49, Cash = 5000 } },
	Offers = {},
}
function SHOPCFG.PassByKey(k) for _, p in ipairs(SHOPCFG.Passes) do if p.Key == k then return p end end end
function SHOPCFG.PassById(id) for _, p in ipairs(SHOPCFG.Passes) do if p.Id == id then return p end end end
function SHOPCFG.ProductByKey(k) for _, p in ipairs(SHOPCFG.Products) do if p.Key == k then return p end end end
function SHOPCFG.ProductById(id) for _, p in ipairs(SHOPCFG.Products) do if p.Id == id then return p end end end
local rs = game:GetService("ReplicatedStorage")
rs.Shared = { Config = { Shop = SHOPCFG, Vehicles = { __module = true, List = {} } }, Util = { Remotes = Remotes, RateLimit = RateLimit } }
PROFILES = {}
SAVE_RESULTS = {}
SAVES = 0
local DS = { __module = true }
function DS.IsLoaded(p) return PROFILES[p] ~= nil end
function DS.Get(p) return PROFILES[p] end
function DS.SaveNow(p) SAVES += 1 task.wait(0.1) local r = table.remove(SAVE_RESULTS, 1) if r == nil then r = true end return r end
local sss = game:GetService("ServerScriptService")
sss.Services.DataService = DS
sss.Services.Telemetry = { __module = true, Custom = function() end }
MS = game:GetService("MarketplaceService")
MS.PromptGamePassPurchaseFinished = newSignal()
OWNS_CALLS = 0
OWNS_FAIL_UNTIL = 0
function MS:UserOwnsGamePassAsync(userId, passId)
	OWNS_CALLS += 1
	task.wait(0.05)
	if clock() < OWNS_FAIL_UNTIL then error("HTTP 500 (scripted)") end
	return true
end
'

scenario() {
	local name="$1" body="$2"
	local f="$OUT/shop_$name.luau"
	{
		cat "$H/prelude.luau"
		echo "$STUBS"
		echo "local ShopService = (function()"
		cat "$SRC"
		echo "end)()"
		echo "ShopService.Init()"
		echo 'local function receipt(pid) local out task.spawn(function() out = MS.ProcessReceipt({ PlayerId = 1, ProductId = 7, PurchaseId = pid }) end) runUntil(clock() + 5) return out end'
		echo "$body"
		echo 'if ERRORS then print("FAIL coroutine errors: " .. ERRORS) end'
	} > "$f"
	echo "== $name"
	"$L" "$f" 2>&1
}

scenario receipt_failed_save_then_repeat '
local p = newPlayer(1)
OWNS_FAIL_UNTIL = -1
join(p)
runUntil(1)
PROFILES[p] = {}
SAVE_RESULTS = { false, false, true }
check("1st delivery, save fails: not yet", receipt("A") == "NotProcessedYet")
check("paid once", p:GetAttribute("Cash") == 5000, p:GetAttribute("Cash"))
check("repeat, save still failing: not yet", receipt("A") == "NotProcessedYet")
check("not paid twice", p:GetAttribute("Cash") == 5000, p:GetAttribute("Cash"))
check("repeat, save works: granted", receipt("A") == "PurchaseGranted")
check("still paid once", p:GetAttribute("Cash") == 5000, p:GetAttribute("Cash"))
check("later repeat: granted without saving", (function() local s = SAVES local r = receipt("A") return r == "PurchaseGranted" and SAVES == s end)())
check("new purchase pays again", receipt("B") == "PurchaseGranted" and p:GetAttribute("Cash") == 10000, p:GetAttribute("Cash"))'

scenario receipt_saved_receipt_from_earlier_session '
local p = newPlayer(1)
join(p)
runUntil(1)
PROFILES[p] = { receipts = { A = 1 } }
local s = SAVES
check("granted, no save, no pay", receipt("A") == "PurchaseGranted" and SAVES == s and (p:GetAttribute("Cash") or 0) == 0)'

scenario receipt_not_loaded '
local p = newPlayer(1)
join(p)
runUntil(1)
check("not loaded: not yet", receipt("A") == "NotProcessedYet")'

scenario pass_check_recovers_after_outage '
OWNS_FAIL_UNTIL = 90 -- Roblox fails to answer for the first 90 s
local p = newPlayer(1)
join(p)
runUntil(30)
check("no pass while Roblox is down", p:GetAttribute("Pass_VIP") ~= true)
runUntil(200)
check("pass granted once Roblox answers", p:GetAttribute("Pass_VIP") == true, OWNS_CALLS)'

scenario pass_check_gives_up_eventually '
OWNS_FAIL_UNTIL = 100000
local p = newPlayer(1)
join(p)
runUntil(2000)
local calls = OWNS_CALLS
runUntil(4000)
check("stops asking after 5 rounds", OWNS_CALLS == calls and calls == 15, calls)'
