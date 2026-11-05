# 16 · More cops from 3 stars, a police helicopter at 5 (LIVE as v12)

Owner, Nov 4 2026: "If you have 3 stars, I think there should be more cops trying to get you … I think if
you have 4 stars, there should be a helicopter after you. With the cops." Then: "If you think the
helicopters are too much for 4 stars, then make the helicopters only for 5 stars … I trust your judgment."

**Decision: the helicopter comes at 5 stars.**
- A Coastal Bank or Sea Dream job gives 3 stars, and jacking a getaway car adds 1. So 4 stars is the
  usual getaway from the biggest heists, and that now already brings 4 patrol cars and 8 officers.
- A helicopter on top would make the best payouts close to impossible to drive away from.
- Reaching 5 stars takes going on a rampage after that (shooting officers, more carjacks). The helicopter
  is what tops it off.
- So each star adds something: 3 cars, then 4, then 5 plus the helicopter.

## What changed

### AI patrol cars per wanted player

| Stars | Before | Now |
|---|---|---|
| 1-2 | 1 (only with no player cop on duty) | same |
| 3 | 2 | **3** |
| 4 | 3 | **4** |
| 5 | 3 | **5** + helicopter |

- From 3 stars the cars come **3 s apart instead of 6**, so the pack arrives together.
- Each car still carries 2 officers from 3 stars. A 3-star stop now means 6 officers on foot.
- Server cap: 8 AI cars in all (was 6).
- Unchanged:
  - 2+ player cops on duty still means no AI cars.
  - The head start (8 s at 3 stars, 4 s at 4+) is the same.
  - Coast Guard boats keep their old count (max 3).

### The police helicopter (5 stars)

- **One per wanted player at 5 stars, max 2 on the server.** It comes 4 s into the chase from about 700
  studs away, so you hear it before it sees you. The player gets a toast: "Police helicopter incoming!
  Hide from it (tunnels, bridges, garages) or outrun it."
- **Looks:** navy and white, POLICE down both sides, a spinning rotor, red and blue beacons flashing in turn,
  and a rotor sound (on the Effects volume slider).
- **At night it has a searchlight.** The light sits on you while it can see you and sweeps the spot where it
  lost you while it searches.
- **It's a cop "eye" with a longer reach (350 studs; a patrol car's is 250).** While it sees you, your stars
  stay solid and the LOSING THEM meter doesn't run.
- **It never arrests anyone.** It only watches. So it comes even when player cops are on duty, and the
  sightings help them.

**How to get away from it:**
- **Break its line of sight:** a tunnel, an overpass, a parking garage, indoors. It then circles where it
  last saw you, not where you are.
- **Outrun it:** it flies at 85% of your car's top speed at most. A fast car on an open road pulls away.
- If it falls more than 1,200 studs behind for 20 s, it gives up and flies off. A new one comes only once
  the cops spot you again.
- It also leaves when you drop below 5 stars, get caught, switch side or leave the game.

It flies about 90 studs over you and stays at least 35 studs above any roof, so it climbs over downtown's
200-stud towers instead of flying through them.

## How it's built

- `src/server/Services/AIPoliceService.lua`: the car counts (CARS_BY_STARS), the faster arrivals
  (SPAWN_GAP_HOT) and MAX_TOTAL.
- `src/server/Services/PoliceHeliService.lua` (new, in Main after AIPoliceService):
  - It flies one invisible, untouchable part per helicopter in Workspace.PoliceAir.
  - Attributes on that part: AITarget, Lock, Aim, Leaving.
  - All the tuning numbers are at the top of the file.
- `src/client/Controllers/PoliceHeliClient.lua` (new, in ClientMain after AmbienceClient): each device builds
  the look, rotor, beacons, searchlight and sound and glides it after the server's part.
- `src/server/Services/HeatService.lua`: `RegisterEye(part, range)`. An eye can now see further than 250.
  Every existing caller is unchanged.
- `src/client/Controllers/NotifyController.lua`: the "PoliceHeli" toast.

## Test status (Nov 4 2026)

**Offline** (Luau CLI, no Studio):
- Every changed file compiles. Lint output is the same as before.
- `tools/logic-tests/coastguard.sh`: 46 PASS, including 12 new checks:
  - 3 / 4 / 5 cars arriving 3 s apart;
  - the server cap of 8;
  - one player cop on duty: still 3 cars at 3 stars;
  - two player cops on duty: the AI cars leave.
- `tools/logic-tests/policeheli.sh` (new): 51 PASS. It covers:
  - no helicopter at 4 stars;
  - the head start and the arrival;
  - tracking a slower car;
  - being outrun by a faster one;
  - searching after you hide;
  - the climb over the tower;
  - leaving when stars drop, on arrest and when the player leaves;
  - the cap of 2;
  - coming even with player cops on duty;
  - Reset Character;
  - HeatService's eye reach.
- The other suites still pass: datastore, shop, crew, robber bots, businesses.

**Studio** (Nov 5, a scratch copy holding v11's police-side scripts + these 7, saves off):
- HeliTest: 12/12 PASS.
  - 3 / 4 / 5 patrol cars, arriving 3 s apart.
  - No helicopter at 3 or 4 stars.
  - At 5 stars it comes, locks on and hovers 92 studs up; only one.
  - Down to 4 stars it turns away and is gone.
  - No warnings or errors from the police scripts.
- HeliTestClient: the look draws (22 parts), the rotor sound loads and plays, and at night the beam and
  ground light are on. Screenshots by day and by night look right (POLICE livery, rotor, beacon, searchlight).
- The Coast Guard session's CGTest, run in the same copy:
  - P1-P5 PASS: chase, then arrest when stopped; swimmer; ashore → patrol car; beached boat; 3 boats at 4★,
    avg frame 16.7 ms.
  - P6 (marina piers) didn't really run (a setup bug in that test). That session is re-running it.
  - 0 script errors.

## Publishing (owner go-ahead given Nov 5: "Only publish what's in this chat")

**Status: LIVE as v12** (Nov 5 2026, 18:57 UTC, published from the live place; no server restart, so new
servers pick it up).
- Built on v11: v10 (the Coast Guard) + the robber bots.
- Before the sync, a check of the live place passed ("[POLICECHECK] ALL OK"): all 5 shared scripts matched
  byte for byte.
- The sync added exactly the 7 scripts below: 5 UPD, 2 NEW, each read back "ok".
- The Studio log said "Publish succeeded for placeId 121416734424826 … Add publish notes to v12".
(On the first try Claude's Studio access was declined twice. The owner allowed it later the same day.)

### What gets published

Only these 7 scripts, each built on its live copy (v10, and v11's Main for Main):
- AIPoliceService, HeatService, NotifyController;
- ClientMain + one line, Main + one line;
- the new PoliceHeliService and PoliceHeliClient.

They're staged in `C:\Users\cbm75\AppData\Local\Temp\claude\8a3654c3af3bfee8\5f507b99-dc37-48ce-b3db-848f53c1ba7f\scratchpad\publish`:
- `manifest.json` lists them;
- `before/` holds the v10 copies that the live place must match first.

Other sessions' unpublished lines in ClientMain and Main (businesses, robber bots) are **not** included.

### Steps (Claude does these when Studio access is allowed; or do them by hand)

1. Make sure nobody else is publishing.
2. Make sure the file server is up: <http://127.0.0.1:35123/manifest.json> should load. If it doesn't, start it with
   `python -m http.server 35123 --bind 127.0.0.1 --directory "C:\Users\cbm75\AppData\Local\Temp\claude\8a3654c3af3bfee8\5f507b99-dc37-48ce-b3db-848f53c1ba7f\scratchpad\publish"`.
3. Open the **live** place: `RobloxStudioBeta.exe -task EditPlace -placeId 121416734424826 -universeId 10774451152`.
4. View > Command Bar. Paste this, press Enter, then click **Continue** on the HttpService warning:
   ```lua
   local H=game:GetService("HttpService") local B="http://127.0.0.1:35123/" local m=H:JSONDecode(H:GetAsync(B.."manifest.json",true)) local r={} local bad=0 for _,e in ipairs(m) do local n=game for s in e.parent:gmatch("[^%.]+") do if n then n=(n==game) and game:GetService(s) or n:FindFirstChild(s) end end local sc=n and n:FindFirstChild(e.name) local ok,want=pcall(function() return H:GetAsync(B.."before/"..e.file,true) end) if not ok then want=nil end local st if want==nil then st=sc and "EXISTS-ALREADY" or "new-ok" else st=sc and (sc.Source==want and "match" or "DIFFERENT") or "MISSING" end if st~="match" and st~="new-ok" then bad+=1 end table.insert(r,e.name.."="..st) end print("[POLICECHECK] "..(bad==0 and "ALL OK " or ("PROBLEMS "..bad.." "))..game.PlaceId.." "..table.concat(r,"  "))
   ```
   The Output must say `[POLICECHECK] ALL OK 121416734424826`. If it says PROBLEMS, stop: the live place
   isn't v10 any more.
5. Paste this and press Enter:
   ```lua
   local H=game:GetService("HttpService") local B="http://127.0.0.1:35123/" local m=H:JSONDecode(H:GetAsync(B.."manifest.json",true)) local r={} local function at(path) local n=game for s in path:gmatch("[^%.]+") do if n==game then n=game:GetService(s) else local c=n:FindFirstChild(s) if not c then c=Instance.new("Folder") c.Name=s c.Parent=n end n=c end end return n end for _,e in ipairs(m) do local par=at(e.parent) local sc=par:FindFirstChild(e.name) local was=sc and "UPD" or "NEW" if not sc then sc=Instance.new(e.class) sc.Name=e.name end local src=H:GetAsync(B..e.file,true) sc.Source=src sc:SetAttribute("SyncSha",e.sha) sc.Parent=par table.insert(r,was.." "..e.name..(sc.Source==src and " ok" or " MISMATCH")) end print("[POLICESYNC] LIVE "..game.PlaceId.." "..table.concat(r,", "))
   ```
   The Output must say `[POLICESYNC] LIVE …` with every entry ending in `ok`. There are 5 UPD and 2 NEW
   (PoliceHeliService, PoliceHeliClient).
6. Quick check (optional): press F5 and give yourself 5 stars from the Server Command Bar:
   `workspace:SetAttribute("NCCmd", '["heat","$me",5]')`.
   This place saves to the real DataStore, so don't change cash, cars or homes while testing. Then stop.
7. File > Publish to Roblox. **Don't restart servers.** New servers pick it up.

## Studio test checklist

Give yourself stars with the debug command: in the Command Bar, set Workspace's `NCCmd` attribute to
`["heat","$me",3]` (or 4, or 5). For night, use `["clock",22]`. To count helicopters, use
`["call","PoliceHeliService","Count"]`. The answer lands in Workspace's `NCResult` attribute.

1. **3 stars:** after about 8 s, 3 patrol cars arrive close together (sirens, minimap blips). Stop the car:
   up to 6 officers get out.
2. **4 stars:** a 4th car comes, and no helicopter.
3. **5 stars:** a 5th car comes. About 4-10 s in, you hear the rotor, then the helicopter flies in. You
   get the "Police helicopter incoming!" toast once.
4. **Its look:** POLICE on both sides, the rotor spinning, red and blue flashing, white blink on the fin.
   It glides smoothly with no stutter or jumping.
5. **Driving around:** it follows about 90 studs up, a little behind. Downtown it climbs over the towers
   and doesn't clip through them.
6. **At night** (`["clock",22]`): the searchlight beam and the lit circle stay on you.
7. **Hiding:** drive into a tunnel or garage or under an overpass and wait. The stars go hollow, the
   helicopter circles where you went in, and its light sweeps there. Drive out in the open near it and it
   locks back on.
8. **Outrunning:** in the fastest car, on a long straight road, it falls behind and loses you.
9. **Leaving:** get arrested, or lose a star to drop to 4 (disguise / respray). It turns away and flies off. No
   errors in the Output.
10. **On a phone (Performance mode):** the beam shows but no ground light, and the frame rate holds with
    the helicopter and 5 cars around.

## Tuning knobs (if it feels too hard or too easy)

- **Cars per star:** `CARS_BY_STARS = { 1, 1, 3, 4, 5 }` in AIPoliceService.
- **How fast the cars arrive:** `SPAWN_GAP_HOT = 3`.
- **In PoliceHeliService:**
  - `SIGHT = 350`: how far the helicopter sees. Lower makes it easier to lose.
  - `SPEED_SHARE = 0.85`: its speed as a share of your car's top speed.
  - `HOVER = 90`: how high above you it flies.
  - `STARS = 5`: the stars that bring it (4 would put it on every big-heist getaway).
  - `MAX_HELIS = 2`: the most helicopters on the server.
