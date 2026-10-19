# 1. Private publish and phone driving test

Do this first: game passes and products can only be created for a published experience, and the
phone test needs one too. New experiences start private, so nobody else can join yet.

## Before you publish (in Studio)

1. Open `NeonCoast.rbxl`, sync the latest scripts (see the main README: `python tools/manifest.py`,
   `python -m http.server 34999 --bind 127.0.0.1`, then `require(game.ServerStorage.Tools.DevSync).Run()`
   in the command bar), and save (Ctrl+S).
2. **Pick the owner account.** Whoever publishes owns the game, its passes and its Robux. Your PRD
   names **NightShift_Dev** as the account to verify, but the place file's lock shows Studio signed in
   as **TCTRADES_CHRIS**. Sign into the one that should own Neon Coast before publishing.
3. The settings scripts can't change (from the design doc's "UserOnly" list):

| Where | Setting |
|---|---|
| Game Settings > Avatar | R15 only (also needed for the higher DevEx rate on US adult purchases) |
| Lighting (Explorer) > Properties | Lighting style: Realistic |
| Workspace > Properties > Streaming | StreamingIntegrityMode = PauseOutsideLoadedArea, StreamingMinRadius = 256 |
| Game Settings > Places (after publishing) | Max players 30 |

`HttpService.HttpEnabled` was turned on for DevSync. Nothing in the live game makes HTTP calls,
so leaving it on is harmless; turn it off if you prefer.

## Publish

File > **Publish to Roblox** > create a new experience named **Neon Coast**. Keep it **Private**.
Then copy the experience's link from the Creator Hub; you'll play it from your phone.

## Phone driving test (about 20 minutes)

Play the private game from the Roblox app on your phone, signed in as the owner. Hold the phone
sideways. For each line, write **OK** or what felt wrong.

**Turn on the numbers first:** in the Roblox menu > Settings, switch on Performance Stats if your
phone shows that option (the target is 30+ fps). Typing `/console` in chat opens the Developer
Console: screenshot any red errors.

| # | Test | What to look for |
|---|---|---|
| 1 | Walk to your car and press Drive | Prompt easy to hit? You sit in the driver's seat? |
| 2 | Hold **GAS** from a stop | Pulls away at once, speed gauge climbs |
| 3 | Steer with the thumbstick, slow (town streets) | Too twitchy, too slow, or right? |
| 4 | Steer at top speed (Highway 1) | Stable, or snaps/wobbles? |
| 5 | **BRAKE**, then hold it to reverse | Stops in a sensible distance, reverses |
| 6 | **DRIFT** through a corner | Slides, then grips again when you let go |
| 7 | **NITRO** on a straight | Boost is obvious, bar drains and refills |
| 8 | GAS + steering + NITRO together with two thumbs | Any button too small, too close, or under your thumb by accident? |
| 9 | Jump off a stunt ramp, land upside down | **FLIP** button appears and works |
| 10 | **EXIT** | You get out cleanly next to the car |
| 11 | Camera in tight streets and tunnels | Clips through walls? Too close or too far? |
| 12 | Drive fast across the whole map | Stutters, freezes, or empty unloaded areas? |
| 13 | Open the phone (Garage, GPS, Shop) | Readable? Buttons big enough? Anything off-screen? |
| 14 | Rob Glow Mart (hold ROB), escape, bank at the Hideout | Whole loop works with touch only |
| 15 | Night time and a rain storm (12-minute day cycle) | Does the frame rate drop? |

## What to send me

- Your phone model.
- The table with OK / notes, especially lines 3, 4 and 8. "Steering too fast at low speed" is
  enough: each car's feel is a handful of numbers in `Config/Vehicles.lua` that I can tune.
- Screenshots of any red `/console` errors and the fps you saw.
