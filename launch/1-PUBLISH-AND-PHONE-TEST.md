# 1. Private publish and phone driving test

Do this first: game passes and products can only be created for a published experience, and the
phone test needs one too. A newly published game is closed: only you, people with Edit access and
group members whose role allows it can get in. Releasing it to the public is a separate step
(launch/5), and it happens only when you decide.

## Before you publish (in Studio)

1. Open `NeonCoast.rbxl`, sync the latest scripts (see the main README: `python tools/manifest.py`,
   `python -m http.server 34999 --bind 127.0.0.1`, then `print(require(game.ServerStorage.Tools.DevSync).Run())`
   in the command bar), and save (Ctrl+S).
2. **Publish under NightShift Dev.** The owner gets the game, its passes and its Robux.
   - If NightShift Dev is a **group**: stay signed in as TCTRADES_CHRIS and, in the Publish to Roblox
     window, choose **NightShift Dev** as the creator/owner instead of your own account. In the
     Creator Hub, switch Creations to the group to find the game.
   - If NightShift Dev is a **separate account**: sign Studio into that account before publishing.
   - Roblox's publishing rules fall on the owner, so pick now. In a group game the group owner has to
     meet the age and verification requirements, only the group owner can pay the all-ages fee, and
     every member who publishes needs 2-step verification.
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

**Done Nov 2, 2026 (closed, not released):** THEFT MIAMI COAST, owner NightShift_Dev, place
121416734424826 (https://www.roblox.com/games/121416734424826), universe 10774451152. Team Create and
Data Sharing (Gen AI training) were switched off; Computer, Phone, Tablet and VR are on. Studio now has
the published place open: Ctrl+S saves it to Roblox, so use File > Save to File As > `NeonCoast.rbxl` to
keep the local file (and git) in step, and File > Publish to update the game. From the old local file,
publish with **Update existing experience** so you don't make a second game.

File > **Publish**. In the Game details window, enter the name **THEFT MIAMI COAST**, the genre and the
description (launch/4), add the icon, then click **Save**. This first publish doesn't release the game.
(If you already published it under another name, rename it in the Creator Hub instead.)
Then copy the game's link from the Creator Hub; you'll play it from your phone.

**Careful from here on.** Roblox uses File > Publish for releasing too: **Continue** leads to an age
question, and the **Publish** button after it releases the game to age-checked players 16 and up.
Roblox's docs don't say what that window does on a game that was never released, so when you only
want to update the closed version, first open Creator Dashboard > the game > Publish settings >
Manage Audience > **Manage access**. In the Public tab, **Friends** on limits the game to your friends
and testers. Stop at the age question unless you mean to go live.

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
