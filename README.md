# Theft Miami Coast

Open-world free-roam driving game set in Port Solana (heists, police chases, homes, guns). It started
as Neon Coast, which is why the place file and some folders still carry that name. Plan, build steps and changelog:
`DesignDoc.lua` (also `ServerStorage.DesignDoc` in the place).

## Layout

| Path | Becomes in Studio |
|---|---|
| `src/client/` | `StarterPlayer.StarterPlayerScripts` |
| `src/server/Services/`, `src/server/Main.server.lua` | `ServerScriptService` |
| `src/server/Tools/` | `ServerStorage.Tools` (edit-time tools) |
| `src/shared/` | `ReplicatedStorage.Shared` |
| `DesignDoc.lua` | `ServerStorage.DesignDoc` |
| `NeonCoast.rbxl` | the place: map, art, car bodies and all scripts |

`*.server.lua` = Script, `*.client.lua` = LocalScript, other `*.lua` = ModuleScript.

## Files to Studio (DevSync)

1. `python tools/manifest.py` rebuilds `manifest.json` (git-ignored).
2. `python -m http.server 34999 --bind 127.0.0.1` from this folder.
3. In Studio (HttpService.HttpEnabled on): `print(require(game.ServerStorage.Tools.DevSync).Run())`.
   It creates or updates every changed script and never deletes anything.

`tools/DevSync.lua` is a copy of that helper. It is not in the manifest; paste it into
`ServerStorage.Tools.DevSync` if a place doesn't have it yet.

## Studio to files

`python tools/extract_rbxl.py NeonCoast.rbxl` writes every script in the place back to `src/` and
`DesignDoc.lua` (needs `pip install lz4 zstandard`). Use it after saving the place if you edited
scripts in Studio, then commit.

Scripts are kept with LF line endings (`.gitattributes`) so their SHA-1 matches the `SyncSha`
DevSync stamps in Studio.

## Launch

`launch/` holds the step-by-step launch kit, in order: private publish and phone test, Creator Hub
passes and cash packs (with icons in `launch/icons/`), the friends test plan, store page copy,
maturity questionnaire answers with the steps for going public, the playtest lists for the latest
updates (6 and 7), and the Nov 3 pre-ads audit (8: Creator Hub fixes, five test passes, publishing).

## Logic tests

`tools/logic-tests/` checks DataService's save locking and retries and ShopService's receipts and pass
checks against stand-in Roblox services with a virtual clock (no Studio needed). It needs the Luau CLI
(github.com/luau-lang/luau releases): `LUAU=path/to/luau.exe bash tools/logic-tests/datastore.sh`, and
the same for `shop.sh`. `coastguard.sh` runs AIPoliceService in a stand-in world (ocean, prison moat,
pier, beach) and checks the Coast Guard boats and the hand-over between boats and patrol cars. Every
line should read PASS. They don't replace a play test.
