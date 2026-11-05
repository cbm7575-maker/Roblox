# Business jobs: the fun pass (spec)

**What the owner asked:** "Make sure these jobs are fun to do and satisfying."

M1 and M2 work: you can wash a car, deliver one, and run a rush order. But right now they're mostly *holds and taps*. This pass turns each job into a short, replayable game.

**Rules for the whole pass:**
- **The server decides money and XP:** pay, tips, ratings, streaks.
- **The client adds the feel:** sounds, particles, stamps, count-ups.
- **Phone-cheap:** a handful of particles, no new big textures, everything torn down when the job ends.

## Design rules (every job)

1. **Short loops.** One unit of work takes 20–60 s, with a clear goal on the strip.
2. **Skill shows.** Doing it well is visibly better: a rating (★ to ★★★), a medal, a tip.
3. **Streaks.** Good results in a row build a streak that raises tips: ×1.1, ×1.2, up to ×1.3. It shows on the strip ("STREAK ×3") and resets on a bad result. Streak pay is **inside** the job's calibrated $/min average, not on top of it.
4. **Juice on every action.** A sound and a small visual for each tap, hold and finish. A big moment at the end: a stamp, cash counting up, a sparkle.
5. **Variety and surprise.** Customers differ (car type, dirt, name, request), with a rare special customer about 1 in 8 times.
6. **A shift report on END JOB:** jobs done, perfects or ★★★, best streak, $ earned, Empire XP. It's the "one more?" moment.
7. **Never punish harshly.** A bad result still pays the base; only tips and streaks are at stake.

## Car Wash

**Wash bay mini-game** (it stays about 20–30 s):
- **SPRAY / RINSE as timing gauges.**
  - You hold and a gauge fills. Release inside the green "sweet spot" for PERFECT.
  - The server times the hold, and the PERFECT window is in config, e.g. 4.6–5.4 s of a 6 s gauge.
  - PERFECT = full tip share for that step.
  - A water-spray particle from the nozzle and a hiss sound while you hold.
- **SCRUB with dirt types.**
  - Each spot is **mud** (3 taps), **bugs** (2 taps) or **bird mess** (4 taps, worth more).
  - Each tap makes a foam puff and a squeak, and the spot shrinks and fades.
  - The last tap on a spot gives a "pop" sparkle.
- **Finish.**
  - The car gleams (the existing sparkle, plus a quick shine sweep across the body).
  - A rating stamp: ★ / ★★ / ★★★ from perfect steps and time.
  - The customer honks twice as they pull out.
  - "+$X" counts up into the cash.
- **Customers.**
  - Random body colour and car model, with a name on a small tag: "Carla's sedan".
  - About 1 in 8 is special:
    - **Muddy Truck:** more spots, ×1.5 pay;
    - **Classic Car:** must be ★★★ for a big tip;
    - **Wedding Car:** a white car with a JUST MARRIED sign, double tip.
- **Streak:** consecutive ★★★ washes raise the tip (cap ×1.3).

**Detail delivery:**
- The customer car is sometimes a **sports car** ("Handle with care: Vortex"), which gives a bigger tip and costs more per dent.
- A "Dents: 0" counter on the strip that shakes and turns red on a dent.
- **Arrival:** the customer walks out to meet you; a "DELIVERED · NO DENTS" stamp, or "−2 DENTS".
- A ★★★ rating from time and dents.
- The streak counts deliveries with 0 dents.

## Palm Grind: rush orders

- **The order:** a coffee cup icon on the strip with the customer's name and the drink ("Professor Lane · Iced Latte"). The cup's colour drains as the timer runs (hot to cold).
- **Medals per drop:**
  - **GOLD** = within the full-tip window, **SILVER** = within the fade, **BRONZE** = late.
  - A medal stamp at each drop, plus a happy NPC wave or a coffee-cup pop.
- **Multi-drop orders:** "2 / 3 delivered" pips on the strip.
- **Combos:** a gold on every stop of a multi-drop order gives a "PERFECT RUN" bonus.
- **VIP orders** (level 4+): a celebrity name, a gold strip edge, and a "VIP DELIVERED" stamp with confetti.
- **Rush hour:** now and then (config, about every 10 min), a "RUSH HOUR" banner gives 2 minutes of +25% tips at the café, announced to the owner.
- **Streak:** consecutive golds raise the tip (cap ×1.3).

## The shift report (all jobs)

A small card on END JOB, or when the job ends for any reason: "SHIFT REPORT · Suds & Shine", then cars washed, ★★★ count, best streak, deliveries, dents, earned $, Empire XP. It has CONTINUE (start again) and DONE. On phones it's one panel.

## Sounds

Use the existing SoundClient names where they fit (CashIn, Splash, Click, Crash). Add only a few new short sounds, through Config/Sounds.lua the way the game already does: spray hiss, squeak, honk, stamp thump, medal ding.

## What to check in Studio (feel)

- Does each job feel good on the 5th repeat, not just the 1st?
- Is PERFECT reachable but not automatic, about 1 try in 2 for a new player?
- Are the stamps and count-ups readable on a phone, without covering the controls?
- Frame rate: no hitch on the finish effects.

## Fun pass: status (Nov 4, 2026)

**Built locally for the Car Wash and Palm Grind. Not committed, published or tested in Studio.** Still behind `Businesses.Live = false`. The server decides every grade, star, medal, streak, special customer and rush hour; the client only shows them.

**Files:** `Config/Businesses.lua`, `BusinessService.lua`, `BusinessJobs/Coffee.lua`, `BusinessClient.lua`, `tools/logic-tests/businesses.sh`, and 3 lines in the shared `Config/Sounds.lua`. `PrintShop.lua` is untouched.

### What's in

**Car Wash: the wash bay**
- **SPRAY and RINSE are timing gauges.** They work like the Print Shop's: the band is drawn in the HOLD button, the fill turns green inside it, and the hose hisses while you hold. Both gauges and the Print Shop's stations are graded by the same function, `Businesses.GaugeGrade`.
  - SPRAY: OK from 3.5 s, green band 4.6–5.4 s, full at 6 s.
  - RINSE: OK from 3 s, green band 4.0–4.8 s, full at 5.5 s.
  - The server adds 0.15 s of slack at each end of a band. Letting go before the minimum shows TOO EARLY and you hold again.
- **Dirt types.** Mud takes 3 taps, bugs 2, and bird mess 4 (+$30 to the wash). Each tap squeaks and puffs suds, and the spot shrinks and fades. The last tap gives a sparkle pop and a ding.
- **The finish.** A shine sweep and the sparkle, then the ★ / ★★ / ★★★ stamp slams down over the car with the thump. The pay counts up on screen. The AFTER panel shows the pay, the stars and the tip's story. The car honks twice as it pulls out.
- **The rating.** One star for each PERFECT hold, one for a quick wash, and never less than one.
- **The tip** is split in thirds: spray, rinse and quick. PERFECT earns its whole third, OK earns 0.4 of it.
- **Customers.** Each car has a name tag ("Carla's sedan"), a random model and paint.
- **Special customers**, about 1 in 8, rolled on the server:
  - **Muddy Truck:** a pickup with 6–7 spots, ×1.5 on the whole wash.
  - **Classic Car:** ×3 tip, but only on a ★★★ wash.
  - **Wedding Car:** white with a JUST MARRIED board, double tip.
- **Streak:** ★★★ washes in a row pay ×1.0, ×1.1, ×1.2, then ×1.3 on the tip.
- **The phone fix.** SCRUB spots now have 9 places spread around the car. While you scrub, overlapping buttons are pushed apart on screen every frame (only during scrubbing). The buttons are 66 px on a phone.

**Car Wash: detail delivery**
- **Sports cars:** 1 in 5 customer cars is a Voltline, Solana GT or Albatross GT. It tips ×1.5 but every dent costs $100.
- **The line under the strip** shows "DENTS 0". It turns red and shakes on a dent, and shows SPORTS CAR and the streak.
- **At the address:**
  - you're put out of the car;
  - the customer walks out and waves (a few local parts), then the car fades;
  - the server removes the car 3 s later.
- **The stamp:** DELIVERED · NO DENTS (or −2 DENTS), with the stars and the streak.
- **The rating:** a star for arriving on time, two for no dents (one for a single dent).
- **The no-dent streak:** ×1.1 up to ×1.3 on the tip.
- **The shift now goes on after a delivery.** Call your car, drive back, and the AFTER panel (NEXT CAR | DELIVER | END) waits at the lot. It ends by itself after 4 minutes without a new car.

**Palm Grind: rush orders**
- **The strip:** a coffee cup that drains from hot to cold as the clock runs, then the customer and the drink ("PROFESSOR LANE · ICED LATTE").
  - **VIPs:** a made-up celebrity name ("VIP · STELLA STARR") and a gold edge round the strip.
  - **Multi-stop orders:** pips and "1/3 DELIVERED" on the line under it.
- **A medal at every stop:**
  - **GOLD:** 22%+ of the clock left (the full tip);
  - **SILVER:** before 0:00;
  - **BRONZE:** late.
  - Each one gets a medal stamp, and a cup pops up at the door (a ding for GOLD).
- **PERFECT RUN:** +$150 when every stop of a 2+ stop order is GOLD.
- **VIP DELIVERED:** a stamp with a confetti burst (24 particles, one time).
- **Gold streak:** ×1.1 up to ×1.3 on the tip.
- **RUSH HOUR:** about every 10 minutes of the owner's play, 2 minutes of +25% tips at their café. The owner and their crew on the job get a stamp; elsewhere it's a toast. The line under the strip counts it down. It is stored on the owner as the attribute `BizRushHour`.

**The shift report (every business, the Print Shop's summary generalized)**
- A centred card after any end: SHIFT REPORT · SUDS & SHINE, the money counting up, the shift's numbers and the Empire XP.
- CONTINUE starts the same job again if you're at the door, or sets the GPS back to it. DONE closes it.
- On a phone it's one panel, and DONE sits on the left.
- Keys: Enter / Y for CONTINUE, X / B for DONE. It goes by itself after 25 s or when you sit down.

**Sounds** (no new assets: checked ones, pitched): `WashHiss`, `WashSqueak` and `WashPop`. Honk, stamp and ding reuse Horn, Stamp and Checkpoint.

### The numbers (level 1, from the seeded simulations in the logic tests)

| | Before | After |
|---|---|---|
| Wash pay / tip | $420 + $140 (a clean finish) | $430 + up to $165 (thirds), + $30 a bird spot |
| Wash $/min, typical player | ~$1,080 (old 30 s model; ~$1,023 on the new 31.6 s one) | **~$1,148** (all-OK ~$1,074, all-PERFECT ~$1,288) |
| Delivery $/min | ~$1,118 (same model) | **~$1,144** (base unchanged; the sports cars and the streak add it) |
| Rush order / tip | $330 + up to $200, full with 35% left | $320 + up to $150, full (GOLD) with 22% left, + $150 perfect run |
| Rush $/min, one stop | ~$1,243 | **~$1,252** (GOLD ~57% of stops; 2 stops +7.5%, 3 stops +9%) |
| Coffee trickle / register | $80 → $200, $3k → $12k (~9.4 h payback) | **$96 → $240, $3.6k → $14.4k (~7.8 h)** |
| Print Shop trickle / register | $110 → $260, $4k → $15k (~13.6 h) | **$192 → $450, $7k → $26k (~7.8 h)** |
| Car Wash trickle | $60 → $150 (~6.9 h) | unchanged |
| All five at level 5 | ~$1,330/min | ~$1,560/min |

Every bonus is inside these averages: the streaks, the specials, bird mess, rush hour and the perfect runs. For a typical washer the bonuses are about 9% of the wash average.

PERFECT odds: a new player who lets go anywhere between the minimum and full lands one about 44% of the time. Aiming at the green, they land it about 78% of the time.

### Studio helpers (server Command Bar, as in M1)

- `["call","BusinessService","Debug","$me","next","Wedding"]` makes your next wash customer a special one. It also takes `Muddy` and `Classic`; `Sports` makes your next delivery a sports car.
- `["call","BusinessService","Debug","$me","rushhour","",60]` starts a 60 s rush hour at your café now.

### Check by hand in Studio

1. **Feel on the 5th repeat.**
   - The gauges' bands are readable, and PERFECT lands about 1 try in 2 at first and more often later. If it's never or always, move `Wash.Gauge`.
   - The squeak (pitched-up Skid) and the hiss (pitched-up Rain) sound right, not like a tyre and a storm. If not, set their Id to 0 or retune `Pitch`.
2. **The SCRUB spots on a phone (PreviewTouch).**
   - Stand at the side, the front and the back of a 6–7 spot muddy truck: no two buttons overlap.
   - The buttons slide apart smoothly as the camera turns.
3. **The rating stamp and the count-up.** They're readable on a phone and don't cover the HOLD button or the AFTER panel. Watch the frame rate on the finish (sparkle, sweep, stamp).
4. **Special customers.**
   - The muddy truck really is a pickup.
   - The JUST MARRIED board sits on the wedding car's tail (the TrafficModels' front is −Z).
   - The classic car's paint looks right.
5. **The delivery hand-over.**
   - The customer walks to the driver's side, on the ground, and waves.
   - The car fades and is gone after about 3 s, and you can't get back in.
   - Drive back: the AFTER panel shows at the lot, and NEXT CAR / DELIVER work.
6. **Rush orders.**
   - The cup's colour drains.
   - The medal stamps don't hide the clock for too long on a multi-stop order.
   - The VIP confetti shows, and the PERFECT RUN pays.
   - `rushhour` shows the stamp on the job and a toast off it, and tips are +25%.
7. **The shift report** on END JOB, a wanted ending and the 4-minute idle after a delivery.
   - It's centred and fits on a phone.
   - CONTINUE restarts at the door and sets the GPS when you're away.
   - The Print Shop's report shows its old lines.
8. **The old numbers elsewhere (fixed).** `launch/15-BUSINESS-M2-TEST.md`, `launch/17-BUSINESS-M3-TEST.md` and the PRD's M2/M3 status sections now quote the raised trickle, registers and rush pay.
