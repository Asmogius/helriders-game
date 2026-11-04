# Content Proposal 01 — DRAFT, NOT APPROVED

> **Status: DRAFT.** Nothing here is approved or built. No gameplay code is in this PR. Every number is a first pass for Cameron to accept, change or reject (see **Decisions for Cameron** at the end). Where this doc and `docs/DESIGN.md` disagree, DESIGN.md wins until something here is approved.

## 0. Baseline read (what exists today)

| State | Items |
|---|---|
| **Built** (in code, `scripts/tuning.gd` / `parts.gd` / `crew.gd`) | Outrider, Bulwark, Gunner Rig, Scrapper, Scrapper Gunner, Patcher, Convoy Lead (+ trailer) stat sheets with §14 layers & resist; defense layers; statuses + buildup (typed hit = 2x damage, resist formula `x (100-R)/50`); barrels; ammo/heat (Pintle 28/2 s, Scattergun 6/2.5 s, Burst 6/2.2 s, Twin Guns 6 s heat / 3 s lockout, Heavy MG 8 s / 4 s, Harpoon 1/2.5 s, Mortar 3/4 s); Harpoon, Mortar, Shock Pulse, EMP Computer, Reflex Emitter; lost-crew rehire; Retrieve & Escort; layouts. |
| **Agreed, not built** | Part mods (unlock 3/7/11/18); tiered crew perks concept; keywords + one symbol/animation/color each; Extract or Push (rules only); Gearhead/Conduit/Tinkerer/Poisoner ability numbers; Harpoon/Mortar/Shock Pulse mods ("aren't built yet"). |
| **Unapproved / draft only** | Crew perk table (first draft; many effects un-numbered); part mods "Targeting Computer onward"; keyword symbols/animations/colors; Extract-or-Push timers/odds/skull math; Outrider and Bulwark as full designs (§8 still "archetypes, refine later"); Convoy Lead nose rule re-expression (now done in tuning.gd as a heavy front plate). |

**Anchors used for every number below**
- Time to wreck (focused, standing still): 15/13/11/9/7.5/6 s at skulls 1-6.
- Starter rig effective pool: 150 HP + 3 x 80 armor (only one facing is hit when focused: 150 + 80 = 230) + 30 shield ≈ **260 focused**. So a single focused source must sum to ~17 DPS at 1 skull, ~43 DPS at 6 skulls (with Bulwark Frame + Riot: 270 + 115 + 45 ≈ 430 → ~72 DPS at 6).
- Existing enemy DPS: Outrider 48 raw, Gunner ~20, Bulwark 15 + 80 ram, Scrapper Gunner 10, Convoy 32 + 30.
- Sustained DPS (garage method): magazine = `mag x dmg / (mag / rate + reload)`; heat = `raw x heat_time / (heat_time + lockout)`. Checks: Pintle 28x9/(4+2) = 42 (garage 43); Twin Guns 48x6/9 = 32 ✓.
- Weapon budget by rarity (sustained / power / weight / scrap): Common ~40 / 50 / 15 / 40; Uncommon 30-50 / 35-45 / 10-15 / 80-120; Rare 50-65 / 40-65 / 20-30 / 170-190.

---

## 1. Enemy vehicles (DRAFT)

Column order everywhere: **Shock / Fire / Acid / Toxic / Slime / Goop** (resistance 0-100, 50 = neutral; buildup taken = hit x (100-R)/50).

### 1.1 Outrider — full design (light flanker)

Keeps current built stats; adds behavior, shield step and spawn rules.

| Layer | Value |
|---|---|
| HP | 100 |
| Armor F / S / R | 40 / 40 / 40 (unchanged) |
| Shield | none ≤4 skulls; **25 from 5 skulls** (3 s delay, 5 s refill) — DRAFT |
| Resist | 45 / 50 / 50 / 50 / 35 / 50 (unchanged; weak to SLICK) |
| Speed / turn | 600 / 3.6 (faster than starter 560) |
| Ram | 40 |
| Weapon | Fixed twin guns 8/s x 6 = 48 raw; enemy guns have no ammo limit today. **Proposal:** give it the player's Twin Guns heat (6 s / 3 s) → 32 sustained; restores the "shoot then reposition" rhythm and a readable punish window. |

**Behavior (DRAFT):** 1) *Flank*: orbit at 220-350 px aiming to reach the player's side/rear arc (±45° behind the beam). 2) *Strafe pass*: when in a side/rear arc and in its gun cone (±10°), fire until overheat. 3) *Break*: on overheat or when a facing of its own is stripped, sprint 500-700 px away using a DRIFT turn, then re-flank. 4) *Zombie clearing*: ignores zombies unless one blocks its line (fires through it). 5) At ≤25% HP it disengages toward the nearest Patcher if one is alive.

**Spawn (as built in `MISSIONS`, confirmed):** Clear 1 at 4 skulls, 2 at 5-6; Survive/Escort per event tables; Courier 1 at 5-6; replaced by Convoy Lead per `CONVOY_CHANCE`. Earliest: 45 s or 20 kills.
**Scrap:** 25. **Drops (50% schematic else 20 cache):** Twin Guns, Light Plating, Sport Wheels, Coolant Loop, Shock Pulse. **Add (DRAFT):** Nitro Bottle (§2.3).

### 1.2 Bulwark — full design (heavy frontal rammer)

| Layer | Value |
|---|---|
| HP | 180 |
| Armor F / S / R | 180 / 55 / 50 (the very heavy front plate replaces the half-damage nose) |
| Shield | none (the front plate *is* its defense) — DRAFT: keep none at all skulls |
| Resist | 60 / 60 / 35 / 55 / 70 / 50 (weak to Acid: plate-eaters reward Acid Lobber) |
| Speed / turn | 430 / 1.9 |
| Ram | 80 (+ shove); half the speed loss through shamblers |
| Weapon | 1 fixed light gun 3/s x 5 = 15, no ammo limit (keep) |

**Behavior (DRAFT):** 1) *Line up*: turn to face the player; when within ±15° and 250-700 px, *Charge* for up to 1.5 s at top speed (wind-up: 0.5 s engine roar + headlight flare = telegraph). 2) Hit: 80 ram + shove, back off 0.5 s (built). 3) Miss: overshoots; 1.0 s recovery turn where its sides/rear are exposed (the counterplay window). 4) Uses its gun only while lining up. 5) Shoves zombies aside; ignores them otherwise. 6) Will screen allies: if a Gunner Rig or Patcher is within 400 px and the player is closer to it, it drives to body-block between them.

**Spawn (built):** Clear 1 from 3 skulls (60 s / 25 kills); Survive at 90-150 s; Escort from 4 skulls; Hunt escort from 3 skulls. **Scrap:** 40 (+40 cache if no schematic). **Drops:** Riot Plating, Zed Sled, Structural Bracing, Roll Cage, Harpoon. **Add (DRAFT):** Slag Plating (§2.3).

### 1.3 Refinements / gaps on existing rigs (DRAFT)

| Rig | Gap | Proposal |
|---|---|---|
| Gunner Rig | Shield 30 from 4 skulls — OK. Enemy guns unlimited. | Give it a 6-burst magazine + 2.5 s reload → sustained ~17 DPS; reload is a visible "turret droops" tell. |
| Scrapper | Fire resist 30 but lays oil it can be caught in. | Keep (intended: lighting its own oil is the counter). Add **ignite rule**: Scrapper oil lit within 200 px of the Scrapper also BURNs it (no special-case immunity). |
| Patcher | Survives forever if player ignores it. | Add a soft cap: max **2 revives per job at 1-3 skulls, 3 at 4-6**; was "unlimited" in §14 → needs Cameron's call. |
| Convoy Lead | Shield on cab only. | OK. Trailer gets no shield. Add BURST-friendly trailer weak point: trailer rear 50 → keep. No change. |
| Bulwark / Outrider | No status-rider variants. | See new rigs. |
| All enemy guns | No ammo model. | Adopt per-rig magazine/heat as above (Outrider heat, Gunner magazine, Bulwark/Convoy nose unlimited). |

### 1.4 New rig A — **Torcher** (fire skirmisher)

| Layer | Value |
|---|---|
| HP | 110 |
| Armor F / S / R | 60 / 45 / 35 (fuel tank on the back = weak rear) |
| Shield | none |
| Resist | 45 / **85** / 45 / 50 / 45 / 50 |
| Speed / turn | 540 / 3.2 |
| Ram | 35 |
| Weapon | Fixed flame nozzle: 220 px cone 30°, 10 ticks/s x 3 fire = 30 raw (builds 6 fire/tick → BURNING in ~1.7 s at R 30+15 shield... ~2.4 s at the starter's 45). Heat: 4 s on, 2.5 s lockout → **18 sustained** + BURNING 6/s. |
| Special | Rear-hit for ≥ 40 in 1 s or wreck: **tank rupture** = Fire-barrel blast (140 px, 25 dmg, burning ground 6 s) — hurts zombies and other enemy rigs too. Ignites any oil it drives through. |

**Behavior:** charge to 150-220 px, hose, peel off on lockout. Prefers routes through Scrapper oil. **Spawn:** Clear/Survive from 3 skulls at 30% (45% at 5-6), seeded, named on Comms, takes the Scrapper's slot at 3 skulls and an Outrider's slot at 4+. Never Courier ≤3 skulls. Counts toward the 3-rig cap. **Scrap:** 30. **Drops:** Flame Sprayer, Ceramic Heat Sink, Patched V8, Composite Plating (rare roll 10%) or 30 cache.

### 1.5 New rig B — **Sludger** (acid/goop artillery support)

| Layer | Value |
|---|---|
| HP | 130 |
| Armor F / S / R | 55 / 55 / 45 |
| Shield | 20 from 4 skulls; 35 at 6 |
| Resist | 40 / 45 / **85** / 60 / 60 / **85** |
| Speed / turn | 470 / 2.6 |
| Ram | 40 |
| Weapon | Turret lobber (like the Mortar; 300-900 px; 1.1 s flight). Alternates **Acid shell** (18 dmg, 70 px, leaves 80 px acid puddle 6 s at 25 acid/s) and **Goop shell** (8 dmg, 90 px, +60 goop buildup). Mag 4, 0.8 s interval, 4 s reload → ~10 sustained direct + puddles. Landing circle shown 0.8 s before impact (red-tinted using COL_ENEMY). |

**Behavior:** stays 500-800 px away behind allies or buildings, retreats when the player closes inside 300 px, never rams voluntarily. Goops the player to drag hordes on them. **Spawn:** from 4 skulls, 30%/40%/50% at 4/5/6 in Survive, Escort (targets the truck first), Retrieve rig calls; never Courier/tutorial. **Scrap:** 35. **Drops:** Acid Lobber, Goop Launcher, Slag Plating, EMP-Hardened Computer or 35 cache.

**Hunt Elite multiplier (1.6-2.5x) applies to every layer of both new rigs, as for existing ones.**

---

## 2. New content (DRAFT)

### 2.1 Weapons (4)

| Weapon | Rarity / source | Mount | Ammo | Stats | Raw DPS | **Sustained DPS** | Power / weight / scrap |
|---|---|---|---|---|---|---|---|
| **Rivet Gun** | Common / Clear pool | Fixed | Magazine 12, reload 2.2 s | 4/s x 16 kinetic, speed 1600, spread 2°, pierces 1 shambler | 64 | 12x16 / (3 + 2.2) = **37** | 40 / 15 / 45 |
| **Flame Sprayer** | Uncommon / Torcher | Fixed | Heat 4 s, lockout 2.5 s | 10 ticks/s x 4 fire, 220 px, 30° cone, pierces all | 40 (60 vs zombies) | 40 x 4/6.5 = **25** (37 vs zombies) + BURNING | 35 / 12 / 100 |
| **Acid Lobber** | Uncommon / Sludger | Turret | Magazine 5, 0.5 s interval, reload 2.5 s | 22 acid per glob, 70 px splash, 60 px puddle 4 s (25 acid/s); 250-750 px; lobs over zombies, not buildings | 44 | 5x22 / (2.5 + 2.5) = **22** (33 vs armor) | 40 / 15 / 110 |
| **Arc Projector** | Rare / Hunt Elite pool & Sludger 5% | Turret | Heat 5 s, lockout 3 s | 6/s x 6 shock, 380 px, chains to 1 extra target within 150 px for 50% | 36 (+18 chain) | 36 x 5/8 = **23** (+11 chain; 34 vs shields) | 55 / 20 / 180 |

Buildup check (typed hit = 2x damage): Flame 8 fire/tick → BURNING on a neutral rig in ~1.3 s; Acid glob 44 → CORRODED in ~3 globs; Arc 12 shock/hit → STUNNED in ~1.4 s on a 50-resist rig (enemy STUNNED = 1.2 s, then 3 s afterglow at half buildup, so stun-lock is capped at ~1.2 s per ~4 s). Sustained figures sit under Burst (50) / Pintle (43) because status payloads add value.

**Mods (DRAFT)**

| Weapon | Minor (3) | Major (7) | Signature (11) |
|---|---|---|---|
| Rivet Gun (Common) | Countersunk: +1 pierce | — | — |
| Flame Sprayer (Uncommon) | Wide Nozzle: +10° cone | Napalm Mix: BURNING on rigs lasts +2 s; ignites oil from 300 px | — |
| Acid Lobber (Uncommon) | Sticky Glob: puddles last +2 s | Etch: vs CORRODED rigs, +20% to armor | — |
| Arc Projector (Rare) | Long Arc: +60 px range | Overload Coil: during OVERLOAD the chain hits 2 extra targets | Thunderhead: hitting a STUNNED rig vents 40% heat |

### 2.2 Parts (4)

| Part | Category / rarity / source | Power / weight / scrap | Key stats | Minor (3) | Major (7) | Signature (11) |
|---|---|---|---|---|---|---|
| **Slag Plating** | Armor / Rare / Bulwark, Sludger | 0 / F-R 16, Sides 28 / 170 | 125 per facing; profile Shock Low, Fire High, Acid High, Toxic Medium, Slime/Goop Medium | Fused Seams: +5% armor | Heat Soak: BURNING on you deals 50% less | Molten Skin: RAM on a rig adds 60 fire buildup |
| **Ceramic Heat Sink** | Internal / Uncommon / Torcher | 15 / 5 / 90 | Heat weapons +20% heat time; +5 Fire resist | Fins: idle cool +15% | Vent Purge: overheat lockout -25% | — |
| **Goop Launcher** | Utility / Uncommon / Sludger | 15 / 10 / 100 | 16 s cooldown; lobs a glob up to 500 px: target enemy rig is GOOPED (fills bar) for 6 s, so zombies hunt *it* | Wide Splash: +30% radius (hits 2 rigs) | Bait Shell: GOOPED rigs also take +10% from zombies | — |
| **Nitro Bottle** | Utility / Uncommon / Outrider | 10 / 8 / 90 | 14 s cooldown; +40% top speed and 2x accel for 1.5 s; RAMs during it +25% | Long Burn: +0.5 s | Drift Fuel: ending a DRIFT refunds 3 s cooldown | — |

### 2.3 Chassis / frames (2)

Existing for comparison: Courier 105 HP / 1 hp / 2 ut / 1 int / cap 80 / 610 speed / 1 seat / 90; Scrap 150 / 1 / 1 / 2 / 100 / 560 / 1 / 50; Bulwark 270 / 2 / 1 / 2 / 160 / 500 / 2 / 180.

| Frame | Rarity / source | HP | Hardpoints / utility / internal | Weight cap | Base power | Max speed / turn | Open seats | Scrap |
|---|---|---|---|---|---|---|---|---|
| **Raider Frame** (light-medium) | Uncommon / Retrieve & Outrider elite | 125 | 2 / 1 / 1 | 90 | 14 | 590 / 3.6 | 1 | 120 |
| **Hauler Frame** (heavy) | Epic / Convoy Lead pool | 320 | 2 / 2 / 3 | 200 | 22 | 470 / 2.7 | 3 | 320 |

| Frame | Minor (3) | Major (7) | Signature (11) | Major 2 (14, Epic) |
|---|---|---|---|---|
| Raider | Gun Rack: fixed weapons +5% fire rate | Hit and Run: 2 s after a DRIFT, +15% damage | — | — |
| Hauler | Ballast: +8% max HP | Tow Hitch: RAM on a rig shoves it 50% further | Mobile Workshop: once per mission restore 15% HP | Cargo Bay: kill scrap +10% |

### 2.4 Crew — 3 new specialties (inside existing classes; class count stays 8)

Format follows `crew.gd` `ABILITIES` (`time`, `cooldown`, `effect` scaled by rarity +10%, -1 s cooldown per step; `fixed` doesn't scale).

```gdscript
# DRAFT — not code to merge
"demolisher": {"name": "Demolisher", "ability": "Cook Off", "kind": "cook_off", "time": 5.0, "cooldown": 24.0,
	"effect": {"fire_rider": 0.5}, "fixed": {"barrel_mult": 1.5}},   # Gunner: hits add 50% of damage as fire; barrels you set off +50%
"jammer": {"name": "Jammer", "ability": "Static Burst", "kind": "static_burst", "time": 4.0, "cooldown": 26.0,
	"effect": {"shock_buildup": 60.0}, "fixed": {"radius": 450.0, "shield_off": 1.0}},   # Spotter: rigs in radius get 60 shock, shields stop recharging 4 s
"wrangler": {"name": "Wrangler", "ability": "Chain Drag", "kind": "chain_drag", "time": 3.0, "cooldown": 22.0,
	"effect": {"ram": 0.4}, "fixed": {"latch_range": 260.0}},   # Bruiser: hooks nearest rig, your next RAM within 3 s +40%; tether uses Patcher pop rules
```

| Specialty (class) | Minor | Minor | Major | Major | Signature | Signature |
|---|---|---|---|---|---|---|
| Demolisher (Gunner) | Long Fuse: +1 s | Quick Strike: -15% cooldown | Chain Reaction: barrels set off during it also ignite oil 200 px | Shrapnel: BURST weapons' last round splashes 40 px | Powder Keg: wrecks during it explode like a Fire barrel | Fire Discipline: BURNING enemies take +15% from all your hits |
| Jammer (Spotter) | Wide Band: +75 px | Quick Tune: -15% cooldown | Lingering Static: shields stay down +2 s | Blind Spot: STUNNED rigs lose LOCK-dodging (become MARKED 3 s) | Blackout: Patcher hooks pop and can't re-hook 5 s | Feedback Loop: OVERLOADed enemy weapons overheat instantly |
| Wrangler (Bruiser) | Long Chain: +80 px | Quick Throw: -15% cooldown | Hogtie: dragged rig's turn rate -50% | Slingshot: releasing at speed flings it, RAM damage on wall impact | Bulldog: drag reels to 120 px, then a free RAM | Two Hooks: 2 charges |

**Crew-loss hooks:** all three follow §14 loss rules (return after 3/4/5/6/7 days by rarity, rehire at level 1, perks reset). Wrangler's Chain Drag tether, like the Harpoon, lets go when either rig wrecks; Last Rites applies normally. Injury debuffs (DRAFT): Demolisher injured → fixed weapons spread +30%; Jammer → utility cooldowns +15%; Wrangler → ram dealt -20%.

---

## 3. Unapproved §14 items — draft numbers

### 3.1 Tiered crew perks — numbers for the first-draft table

Principle: Minor ≈ +20% duration or -15% cooldown (already numeric); Major = conditional ~+20-30%; Signature = rule-changer, capped once per mission or by cooldown. Numbers fill in entries left vague in §14:

| Specialty | Perk | Draft number |
|---|---|---|
| Speedster | Open Road | 1% max armor/s to most damaged facing, max 20% per mission |
| Speedster | Afterburn | 50 px wide trail, 3 s, 20 fire buildup/s on contact |
| Speedster | Clean Run | Refund 50% of cooldown if no HP/armor lost during it |
| Bootlegger | Tail Swipe | Rear RAM at 60% of front ram value |
| Bootlegger | Oil Spin | 120 px ring, 8 s, enemy-only |
| Gunslinger | Red Hot | 30% of each shot's damage as fire |
| Gunslinger | Siphon | 10% of damage dealt to shield, max 40 per activation |
| Marksman | Opening Shot | 3x on first shot, once per activation |
| Marksman | Executioner | Below 10% HP *and* stripped facing hit |
| Breacher | Bleed-Through / Rail Line | 20% to HP; Rail Line pierces 1 rig |
| Fixer | Fresh Weld / Hull Patch | -20% 4 s / 5% max HP (the only in-mission HP repair besides Hauler) |
| Gearhead | Afterglow | Boosts fade linearly over 4 s |
| Conduit | Spillover | Half of leftover bonus shield to armor, cap 30 per activation |
| Conduit | Arc Feedback | 30 shock buildup to the shooter per shield hit, 0.5 s per-attacker cooldown |
| Tinkerer | Kamikaze | 25 dmg, 60 px blast each |
| Marker | Weak Point / Shutdown | +50% HP damage / no abilities (Patcher hook, Bulwark charge, Torcher hose) for 3 s |
| Scout | Magnesium / Flashbang | 15 fire buildup/s inside / 1.5 s zombie stun on ignition |
| Field Medic | Last Breath | Once per mission, HP floors at 1, 1 s invulnerable |
| Poisoner | Lingering Cloud / Contagion | 4 s / burst = 120 px, 40 toxic buildup |
| Magpie | Scrap Plating | 2 armor per pickup, cap 30 per mission |
| Salvager | Bounty / Strip Mine | +10 scrap per rig wreck / 1 scrap per 40 armor dealt, cap 25 |
| Bracer | Absorb | Releases 50% of blocked damage as 150 px shock (2x buildup) |
| Breaker | Aftershock / Payback | 50% wave after 1 s / +50% of damage taken in last 3 s, cap +60 |

Pick schedule (approved concept): Minor at picks 3 and 6, Major at 9 and 12, Signature at 15 and 18; each pick offers 3 from (that tier's 2 specialty perks + the 4 shared perks), no repeats. Commons (cap 5) only ever see Minor 3; Uncommon (cap 8) gets both Minors; Rare (11) + one Major; Epic (14) + both Majors; Legendary (17) + one Signature; Mythic (20) all six.

### 3.2 Keyword symbols, animations, fixed colors

**Threat colors already in use (do not reuse):** enemy `#F23D29` (COL_ENEMY), elite `#FFC740` (COL_ELITE), Hunter `#BD5C47`, zombie `#738059`/`#454D3B`, Brute/Tank/Boomer/Slimer `#6B665C`/`#80544D`/`#A8B34D`/`#5C9E80`. UI accents: cyan `#40D1E0` (extraction), orange `#ED7A2B` (push), shield `#8CBFFF`, friendly truck `#73D980`.

**Conflicts found in the built status colors** (`STATUS_COLORS`): STUNNED `#8CCCFF` ≈ shield `#8CBFFF`; BURNING `#FF7326` ≈ orange accent `#ED7A2B`; SLICK `#73D999` ≈ truck `#73D980`/Slimer; GOOPED `#D9D94D` ≈ Boomer/elite gold. Proposal below re-colours those four.

| Keyword | Symbol (12-16 px glyph) | Animation (≤0.4 s, throttled: max 1 per rig per 0.5 s; max 6 on screen) | Color |
|---|---|---|---|
| RAM | Chevron `»` on a bar | Glyph punches forward, 2-frame shake | `#E8E2D0` bone |
| DRIFT | Curved arrow `↺` | Arc sweeps around the rig | `#7A8CFF` periwinkle |
| BURST | Three dots `•••` | Dots pop in sequence | `#FF9EC7` pink |
| MARKED | Crosshair diamond `◇+` | Diamond shrinks onto rig, then pulses 1 Hz | `#FF4FD8` magenta |
| STUNNED | Lightning zig-zag | Jitter + 2 sparks | `#F2F5FF` white-ice (was `#8CCCFF`) |
| OVERLOAD | Gauge needle past red | Needle flick, gauge flashes | `#3D7BFF` electric blue |
| SLICK | Droplet with skid line | Droplet slides sideways | `#2EC4A6` teal (was `#73D999`) |
| BURNING | Flame | Flicker 3 frames loop | `#FF4A8A`? **or** keep orange family `#FF5A1F` — decision (was `#FF7326`) |
| CORRODED | Cracked plate | Crack spreads | `#99F240` (keep) |
| GOOPED | Blob with eyes | Wobble squash | `#C77DFF`? conflicts TOXIC → propose `#E0A458` mustard-brown (was `#D9D94D`) |
| TOXIC | Skull-in-cloud | Cloud puff rises | `#B366E6` (keep) |

On garage cards: the glyph sits in a 20 px chip in the keyword color on the mod line; locked mods show the chip at 40% alpha.

### 3.3 Extract or Push

| Item | Draft |
|---|---|
| Eligibility | 75% of board jobs, seeded per job, hidden until objective done. Never: tutorial, onboarding Clear, the day after a wreck, Courier (timed route; revisit later). Retrieve: push beacon appears once ≥ all non-deep caches taken; extraction point is already the cyan marker. Escort: offered only if the optional site was *not* taken (no double-dipping). |
| Decision | Cyan extract marker and orange push beacon spawn ≥ 600 px apart, both 110 px radius. No timeout; the horde keeps ramping while you choose. |
| Push timer | 60 / 65 / 70 / 75 / 85 / 90 s at skulls 1-6. |
| Skull math | Push plays at min(skulls + 1, 6): zombie cap/ramp/mix of that row. Plus **one extra rig** from the job's rig pool. At 6 skulls: instead of +1 skull, a **second extra rig** (both respect the 3-rig cap; extras queue). |
| End | Timer out → extraction marker re-appears at the push beacon; drive in within 20 s (or it ends automatically when no rigs are alive). |
| Reward | Job pay x1.5 (kill scrap unchanged) + one extra schematic roll at `MISSION_SCHEMATIC_CHANCE[push skulls]` from the job's pool. XP +50%. |
| Failure | Wreck = normal wreck rules (lose job pay, crew lost, penalty). |
| Comms | Card shows nothing in advance; post-job results card shows PUSHED badge. |

### 3.4 Harpoon / Mortar / Shock Pulse mods — numbers

| Part | Minor (3) | Major (7) | Signature (11) |
|---|---|---|---|
| Harpoon (Rare) | Barbed Tip: +20% (36 per zombie), pierce 4 → 5 | Power Winch: reel 100 → 130 px/s, reel-to 200 → 150 px | Wrecking Ball: tethered rig hitting wall/rig/barrel above 250 px/s takes 2x collision damage (min 40) |
| Mortar (Uncommon) | Heavy Charge: blast 90 → 108 px | Cluster Shell: shell splits at apex into 3 bomblets, 70 px apart, 45 px blast, 40% damage each (total 120% if all hit; ~48 sustained ceiling vs crowds) | — |
| Shock Pulse (Uncommon) | Wide Field: 180 → 216 px | Drain Arc: strips 50% of current shield on enemy rigs inside | — |

---

## Decisions for Cameron

All items DRAFT until approved.

1. Outrider: add a 25 shield from 5 skulls and the flank / strafe / break behavior?
2. Give enemy guns ammo: Outrider heat (6 s / 3 s), Gunner Rig magazine (6 bursts / 2.5 s); Bulwark and Convoy nose stay unlimited?
3. Bulwark: charge telegraph (0.5 s), 1.0 s overshoot window, ally-screening; still no shield?
4. Patcher: cap revives at 2 (1-3 skulls) / 3 (4-6) instead of unlimited?
5. Scrapper: no immunity to its own lit oil?
6. New rig Torcher (fire skirmisher, rear tank rupture): stats, 30-45% spawn from 3 skulls, drops?
7. New rig Sludger (acid/goop lobber): stats, 30-50% spawn from 4 skulls, drops?
8. Weapons: Rivet Gun (37 sustained), Flame Sprayer (25), Acid Lobber (22), Arc Projector (23 + chain): ammo, costs, rarity, mods?
9. Parts: Slag Plating, Ceramic Heat Sink, Goop Launcher, Nitro Bottle: stats and mods?
10. Frames: Raider (Uncommon, 125 HP, 2 hardpoints) and Hauler (Epic, 320 HP, 3 seats) — and does Hauler's 3 open seats fit the seat model?
11. Crew: Demolisher (Gunner), Jammer (Spotter), Wrangler (Bruiser) — abilities, perks and injury debuffs?
12. Numbers for the vague first-draft perks (table 3.1) and the rarity → perk-tier reach?
13. Keyword symbols and animations, and the throttle rule (1 per rig / 0.5 s, 6 on screen)?
14. Re-colour four built status colors (STUNNED, SLICK, GOOPED, BURNING) that clash with shield/accent/truck/threat colors — and pick BURNING: pink `#FF4A8A` vs orange `#FF5A1F`?
15. Extract or Push: 75% eligibility, exclusions (tutorial, day after wreck, Courier; Escort only without optional site), timers 60-90 s, +1 skull / +1 rig (6 skulls: +2 rigs), x1.5 pay + schematic roll + 50% XP, no choice timeout?
16. How Push reconciles with Retrieve (beacon after non-deep caches) and Escort (only if optional site skipped)?
17. Harpoon / Mortar / Shock Pulse mod numbers, especially Cluster Shell (3 x 40%, 45 px)?
