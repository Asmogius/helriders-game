# Night Zombie Tuning (APPROVED)

**Status: APPROVED by Cameron on 2026-11-04 (PR #69), implemented in `content/night-zombies`.** The numbers below are the approved values. The one change since approval: `NIGHT_ZOMBIE_DPS_MULT` was trimmed so the 85% wreck-time floor holds (see "Balance check").

## Cameron's decisions
1. Outer Blocks has a 10% night chance. No night at 1 skull or before the first 3 clears (`NIGHT_MIN_SKULLS` 2, `NIGHT_MIN_CLEARS` 3).
2. No aggro radius. Zombies keep chasing from anywhere.
3. The horde surge is in, as drafted.
4. The night pay bonus stacks on top of Core Collapse's pay.
5. All four rewards stay: pay x1.3, kill scrap x1.25 rounded up, schematic chance +0.10, crew XP x1.25. XP goes through a new `xp_mult` argument on `Profile.bank_crew()`.
6. Only zombies (and Hunters) change at night. Enemy rigs stay the same.
7. The headlight look waits on an Art mockup and isn't built. The night colour was #512b11; Art has since moved `COL_NIGHT_WORLD` to #2a3550 on main, and `COL_NIGHT` follows it. Maps, UI and Art own the palette.
8. Job cards show a night icon before the player takes the job.
- Courier jobs are 50/50 night outside Core Collapse (`NIGHT_CHANCE_COURIER`); Core Couriers are always night (Cameron, 2026-11-05).
- 2026-11-05: `NIGHT_ZOMBIE_DPS_MULT` 1.10 approved; `NIGHT_ZOMBIE_SPEED_MULT` 1.10 approved (the code had 1.15; Head Dev's note said "from 1.05", which matched neither, so 1.15 -> 1.10 is the change made).
- The night roll is saved with the job (`job.night`, kept by `_clean_mission` on load).

## Request
Zombies more dangerous and aggressive at night. Night is rolled per job, weighted by district: Outer Blocks mostly day, Midtown ~35% night, Industrial ~60%, Core Collapse always night.

## What exists today (origin/main)
- **No night/day system in code.** `git grep night` on main and all open branches finds only `COL_GARAGE_STREET_NIGHT` (garage backdrop colour) and "tonight" comments about crew rest. The per-job night roll is new.
- **No aggro radius or leash for zombies.** `zombie_director.gd::_steer()` makes every active zombie chase the player (or the nearer `alt_target`, or a bait within `BILE_MARK_RANGE`) from anywhere on the map, re-planning every 0.35-0.55 s. "Aggression" therefore has to be expressed as speed, damage, density, spawn pressure and frenzy, not a sight radius — unless we add one (see Open Questions).
- Existing levers: `zombie_director.speed_bonus` (used by Retrieve), `zombie.frenzy` (Bile, x`BILE_FRENZY`), `ENEMY_DAMAGE_BY_SKULL`, `HORDE_SCALE_BY_SKULL`, `ZOMBIE_CAP`, `ZOMBIE_RAMP_SECONDS`, `HORDE_SIZE`, `ZOMBIE_MIX`.

### Current values
| Const | Value | Notes |
|---|---|---|
| `SHAMBLER_SPEED` | 85.0 | brute 70, tank 75, boomer 60, slimer 95 (`ZOMBIE_KINDS`) |
| `SHAMBLER_DPS` | 3.0 | brute/tank 8.0, slimer 3.0, boomer 0 |
| `SHAMBLER_HP` | 40.0 | brute 200, tank 450, boomer 60, slimer 70 |
| `HUNTER_SPEED` | 250.0 | rig does 560 |
| `HUNTER_DPS` | 8.0 | latched |
| `HUNTER_SPAWN_TIME` / `_KILLS` | 25.0 s / 10 | |
| `ZOMBIE_START` | 12 | alive at start |
| `ZOMBIE_CAP` | 28 | DESIGN §12 cap 25-30 (hard perf limit) |
| `ZOMBIE_RAMP_SECONDS` | 4.0 | +1 alive every N s |
| `HORDE_SIZE` | Vector2i(3, 6) | pack size |
| `SPAWN_MIN_DISTANCE` | 850.0 | spawns off-screen |
| `BILE_MARK_RANGE` | 500.0 | |
| `BILE_FRENZY` | 1.6 | speed mult while frenzied |
| `TANK_PACK_CHANCE` / `TANK_EARLIEST` | 0.3 / 30.0 s | `TANKS_PER_MISSION` [0,0,0,1,1,2] |
| `TANK_CHARGE_RANGE` | 350.0 | |
| `RETRIEVE_SPEED_STEP` | 0.05 | precedent for a speed mult |
| `ENEMY_DAMAGE_BY_SKULL` | [0.85, 0.95, 1.0, 1.1, 1.95, 1.95] | combat contract: wreck in 15/13/11/9/7.5/6 s |
| `HORDE_SCALE_BY_SKULL` | [0.8, 0.9, 1.0, 1.0, 1.0, 1.0] | |
| `SCRAP_PER_KILL` | 2 | per-kind `scrap` in `ZOMBIE_KINDS` |
| `MISSIONS.*.reward` | e.g. clear [60,72,84,98,114,130] | |
| `MISSION_SCHEMATIC_CHANCE` | [0.0, 0.15, 0.30, 0.50, 0.75, 1.0] | |
| `DISTRICTS` | outer_blocks [1,4], midtown [2,5], industrial [3,6], core [4,6] | skull bands |

## New consts in `scripts/tuning.gd` (approved)
```gdscript
# --- Night (proposal; DESIGN §14 pending) -----------------------------------
# Chance a job rolls night, by DISTRICTS index.
const NIGHT_CHANCE_BY_DISTRICT := [0.10, 0.35, 0.60, 1.0]   # Outer Blocks 10% (Cameron)
const NIGHT_ZOMBIE_SPEED_MULT := 1.10     # approved 2026-11-05 (was 1.15); shambler 75 -> ~83
const NIGHT_HUNTER_SPEED_MULT := 1.10     # 250 -> 275
const NIGHT_ZOMBIE_DPS_MULT := 1.10       # approved 1.20, trimmed for the 85% floor; shambler 3.0 -> 3.6, brute/tank 8 -> 9.6
const NIGHT_ZOMBIE_HP_MULT := 1.0         # unchanged: night is faster/meaner, not spongier
const NIGHT_ZOMBIE_START_BONUS := 4       # 12 -> 16 alive at start
const NIGHT_RAMP_SECONDS := 3.0           # vs ZOMBIE_RAMP_SECONDS 4.0
const NIGHT_HORDE_SIZE := Vector2i(4, 7)  # vs (3, 6)
# ZOMBIE_CAP stays 28 at night (DESIGN §12 perf cap). Pressure comes from refill rate, not count.
const NIGHT_HUNTER_SPAWN_TIME := 15.0     # vs 25.0 (kills trigger unchanged)
const NIGHT_TANK_EARLIEST := 20.0         # vs 30.0
const NIGHT_TANK_PACK_CHANCE := 0.4       # vs 0.3 (TANKS_PER_MISSION cap unchanged)
const NIGHT_BILE_MARK_RANGE := 650.0      # vs 500: Boomer bile draws from farther in the dark
# Horde behaviour: "night surge" - every N s the director frenzies the
# horde (zombie.frenzy, x BILE_FRENZY) for a short burst, telegraphed by a howl + HUD pulse.
const NIGHT_SURGE_EVERY := 35.0         
const NIGHT_SURGE_TIME := 4.0           
const NIGHT_SURGE_WARN := 1.5             # audio/HUD telegraph before it lands
# Fairness: night must not break the combat contract by more than this.
const NIGHT_WRECK_TIME_FLOOR := 0.85      # night time-to-wreck >= 85% of day's at same skulls
# Rewards
const NIGHT_PAYOUT_MULT := 1.30           # job reward (MISSIONS.*.reward)
const NIGHT_KILL_SCRAP_MULT := 1.25       # per-kill scrap, rounded up (shambler 2 -> 3)
const NIGHT_SCHEMATIC_BONUS := 0.10       # + to MISSION_SCHEMATIC_CHANCE, cap 1.0
const NIGHT_XP_MULT := 1.25               # crew mission XP
```
Effective night speed = base x `NIGHT_ZOMBIE_SPEED_MULT` x existing `speed_bonus` (Retrieve) x `BILE_FRENZY` when frenzied; multipliers stack multiplicatively. Night DPS stacks on top of `ENEMY_DAMAGE_BY_SKULL`.

Original estimate: +20% DPS and +15% speed on contact pressure cuts time-to-wreck by ~15-20%, i.e. a 3-skull night job plays near a 4-skull day job. If the balance report shows night under `NIGHT_WRECK_TIME_FLOOR`, trim `NIGHT_ZOMBIE_DPS_MULT` first (speed is the "aggressive" feel; damage is the punishing part).

## Per-district notes
| District | Skulls | Night chance | Notes |
|---|---|---|---|
| Outer Blocks | 1-4 | 0.10 | Onboarding district. Suggest **no night on the first 3 clears** (reuse `EXPEDITION_UNLOCK_CLEARS`-style gate) and never at 1 skull, so the vertical slice (§13) stays a day Clear. |
| Midtown Ruins | 2-5 | 0.35 | First real night exposure. Tight streets: faster shamblers clog harder, keep `NIGHT_HORDE_SIZE` as proposed. |
| Industrial Spine | 3-6 | 0.60 | Night is the norm; reward mult makes it the scrap district. Watch 6-skull night (already x1.95 damage). Option: cap night DPS mult at 1.10 at 5-6 skulls. |
| Core Collapse | 4-6 | 1.0 | Always night, so night is baked into its difficulty: suggest Core uses night *behaviour* (speed, surge, spawn rate) but `NIGHT_PAYOUT_MULT` is folded into its base economy rather than stacked, or the gap to Industrial gets too large. Open question. |

Comms must show the night icon on the job card *before* the player commits (like Convoy Lead and Scrapper Gunner, which are seeded per job and named on Comms). Seed the night roll with the job so restarts/relaunches (§12 pause menu) keep the same time of day.

## Rewards tie-in
- `NIGHT_PAYOUT_MULT` 1.30 on job pay; `NIGHT_KILL_SCRAP_MULT` 1.25 on kill scrap; +0.10 schematic chance; `NIGHT_XP_MULT` 1.25. (Approved.)
- Courier at night: apply pay mult to `COURIER_TIER_PAY` result, not to par times (par stays fair).
- Expeditions: out of scope (no live combat), unless Cameron wants night expeditions to raise injury odds.
- Economy (§10) risk: Industrial at 60% night raises average income ~18% (0.6 x 30%). Fine if Research/part costs are meant to be reached faster there; otherwise lower the payout mult to 1.20.

## Risk / balance notes (Android at night)
- **Visibility is the real risk.** Phones in sunlight / low brightness, ~2020 devices on Low preset. Night must darken the *ground*, not the threats:
  - Keep zombies readable: `COL_ZOMBIE_EYE` should get an emissive/brighter variant at night (idea: `COL_ZOMBIE_EYE_NIGHT`, not built), and silhouettes need to keep ~3:1 contrast against night ground (cf. the `COL_OB_GRASS` ~1.9:1 note vs `COL_ZOMBIE_DARK` — that is already low for day).
  - Headlight cone + rig light radius rather than full-screen dark; no real-time shadows (perf, §12). Use a palette swap/modulate, not extra lights per zombie.
  - Hunter windup (`HUNTER_WINDUP` 0.35 s) and Tank roar (`TANK_WINDUP` 0.8 s) must stay fully visible/audible at night; consider *not* shortening any telegraph at night.
  - Off-screen threat arrows (like `STRAGGLER_ARROWS`) for packs approaching from the dark.
- Low preset must look the same in gameplay terms (no dark-only-on-High exploit or penalty).
- Surge must be telegraphed (`NIGHT_SURGE_WARN`) so it reads as a pattern, not random spikes.
- `ZOMBIE_CAP` unchanged keeps perf flat; the faster ramp means the cap is hit sooner, so test frame time at cap on a Low device.
- Accessibility: settings toggle "brighter nights" (gameplay unchanged) is worth considering.

## Open questions for Cameron (answered; see "Cameron's decisions")
1. Outer Blocks night chance: 10% OK, and should night be blocked for the first N clears / at 1 skull?
2. Add a real **aggro radius + leash** for zombies at night (today they all chase from anywhere)? E.g. day zombies wander until within an aggro radius, night ones always chase. That is a day-time behaviour change too, so it needs its own approval.
3. Approve the "night surge" horde frenzy, or keep night to flat multipliers only?
4. Core Collapse is always night: stack the night reward mult on it, or fold it into Core's base pay?
5. Reward mix: 1.30 pay / 1.25 kill scrap / +10% schematic / 1.25 XP — all, some, or lower?
6. Should enemy rigs (Outrider, Gunner, etc.) change at night too, or zombies only?
7. Visual: is a headlight cone/rig light acceptable art direction, and who owns the night palette (art branch)?
8. Night icon on the Comms card — required before accepting a job? (Proposed: yes.)

## Balance check (tools/balance/balance_report.gd, 15 runs a cell, 2026-11-04)
Day time-to-wreck is in the report's FOCUSED table. With the approved x1.20 damage, night came in at 61-92% of day, and 13 cells were under the 85% floor. Following the rule (trim damage first), `NIGHT_ZOMBIE_DPS_MULT` is now **1.10**. Even at 1.00 the floor still failed in some cells. A run with no speed or damage boost at all still showed 77-144% swings at 4-6 skulls, so those cells are mostly run-to-run noise from fights of 2-7 s. That's why the report now does 15 runs a cell instead of 5. Every district average clears the floor (86-95%). Three single cells don't: mid 3 skulls 83%, mid 4 skulls 85% (just under), starter 6 skulls 80%. The 3-skull dip comes from the x1.15 zombie speed. Fixing it means trimming speed, which needs Cameron.

```
== NIGHT TIME-TO-WRECK, mean of 15 runs (same roster at night; floor 85% of day)
  starter n      12.9    11.4     7.5     6.1     2.9     1.9
  starter n/d      90%     90%     88%     89%    120%     80%
  mid n          14.7    13.0     8.6     7.4     2.9     2.7
  mid n/d         91%     91%     83%     85%    108%     88%
  late n         23.2    20.1    15.5    13.8     6.5     6.5
  late n/d        91%     90%     89%     93%     95%     88%
  floor check: FAIL starter 6 skulls (80%), mid 3 skulls (83%), mid 4 skulls (85%)

== DAY VS NIGHT BY DISTRICT (skulls weighted by SKULL_WEIGHTS inside the band; Clear kill scrap)
  district           night%   build    ttw day  ttw night  ratio   income day  income night  expected
  Outer Blocks          10%   starter     11.1        9.9    90%          219           283       225
  Outer Blocks          10%   mid         12.9       11.4    88%          219           283       225
  Outer Blocks          10%   late        20.6       18.7    91%          219           283       225
  Midtown Ruins         35%   starter      8.1        7.4    91%          283           356       308
  Midtown Ruins         35%   mid          9.7        8.5    87%          283           356       308
  Midtown Ruins         35%   late        16.2       14.7    91%          283           356       308
  Industrial Spine      60%   starter      5.4        5.0    92%          341           423       390
  Industrial Spine      60%   mid          6.7        5.8    86%          341           423       390
  Industrial Spine      60%   late        12.3       11.2    91%          341           423       390
  Core Collapse        100%   starter      3.7        3.5    95%          373           462       462
  Core Collapse        100%   mid          4.6        4.2    91%          373           462       462
  Core Collapse        100%   late         9.4        8.7    92%          373           462       462
```
Income per job is job pay plus Clear kill scrap, now counting Hunters, weighted over each district's skull band. "Expected" is day income blended with the district's night chance.

## Final precedence (2026-11-05, Cameron: "Core is always night with no exceptions")
1. Core Collapse: always night, every job type, above the tutorial, 1-skull and first-3-clears rules.
2. Tutorial: day. (The tutorial has no layout and always runs in the Outer Blocks Crossroads, so it is never in Core.)
3. 1 skull, or fewer than 3 clears: day.
4. Escort: day below 5 skulls, night at 5-6.
5. Courier: 50/50.
6. Outer Blocks Survive and Hunt at 4 skulls: night.
7. District chance (10/35/60%), +25% for Survive and Hunt, capped at 1.0.

Old saves: a job with no `night` flag rolls once on load from `helriders-night-<seed>`. A saved flag wins, except in Core, which is always night.
