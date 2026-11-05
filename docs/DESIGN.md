# Helriders — Design Briefing

Implementation-ready design document for a top-down arcade roguelike mobile game. The player assembles a crew and builds one customizable Twisted Metal-style armored vehicle to run missions in a gritty urban zombie wasteland, extracting parts and scrap. No microtransactions.

All systems below are locked unless explicitly marked for later refinement.

# 1. High-Level Vision

Core fantasy: Armored Core-style vehicle building applied to wheeled wasteland machines, experienced through readable top-down arcade combat. The garage is the persistent progression layer; combat is how you feed it. Crew are a supporting but higher-stakes investment.

Session target: 4–7 minutes from mission select to back in the garage. Daily structure (one mission per day) keeps the management layer relevant without slowing the action.

# 2. Setting and Tone

Years after a city-wide collapse. Ruined streets, collapsed infrastructure, and rival scavenger crews compete for salvage while zombie hordes move through the districts. The player runs a fortified garage compound (core workshop + Saloon + Inn) on the edge of a safer zone and pushes deeper for better parts.

Tone is harsh, industrial, and opportunistic. Vehicles are scavenged and weaponized, not heroic. Atmosphere is rust, concrete dust, practical cyan/orange lighting, engine noise, and constant risk calculation. Dark practicality is welcome; clean military sci-fi or grand prophecy is not.

# 3. Core Loop

1. Start day in garage. Stations refresh as appropriate.

2. Open Comms Hub. Choose 1 of 3+ clearly labeled missions.

3. Assign crew from Inn roster to vehicle roles. Load or edit preset.

4. Launch. Top-down combat against zombies + enemy vehicles.

5. Success: return with scrap, parts, crew XP (possible injuries). Failure (vehicle destroyed): dramatic wreck, rig and its parts lost (rebuild it), assigned crew permanently lost. No scrap penalty (removed 2026-11-05).

6. Land in garage. Upgrade parts via Research, manage roster/injuries/expeditions, upgrade stations, prepare next day.

Persistent power: better parts (rarity + level), higher-level crew you protect, light station upgrades, and district access via weighted parts score.

# 4. Vehicle Customization

Exactly one physical vehicle. Freely editable between missions using owned parts. Presets save full loadouts but only include parts the player currently possesses. Each of the three presets can be named (up to 18 characters; empty shows P1 / P2 / P3).

## Part Categories and Tradeoffs

- Chassis/Frame: Light/Medium/Heavy. Sets hardpoint count, mass capacity, crew slots, base mobility ceiling.

- Power Plant/Engine: Power budget. Overload reduces mobility or disables systems. Affects acceleration.

- Drive System: Wheels/tracks/hybrids. Directly drives turn radius, drift amount, and recovery. Primary mobility feel.

- Armor Sections: Front/side/rear (roof optional). Weight lowers mobility. Front-heavy favors ramming; flanks become vulnerable.

- Weapon Hardpoints: Fixed (aim with vehicle), turrets (fire while moving), ramming/spikes. Limited by chassis + power.

- Utility Slots: Smoke, mines, speed burst, emergency repair, etc. Lower power draw.

- Internal Systems: Cooling, ammo feeds, targeting, structural bracing. Passive modifiers, occupy internal capacity.

Example builds for testing: Light Flanker (high mobility, fixed guns, smoke), Heavy Rammer (mass + front plate + spikes), Balanced Turret Boat (medium mobility, dual turrets).

## Research and Leveling

Research Station only levels parts the player already owns. Blueprints/new part types come from mission loot, enemy vehicle destruction, or Saloon purchases.

Max level by rarity: Common 5, Uncommon 8, Rare 12, Epic 16, Legendary 20. Unique Legendary bonus unlocks at high or max level. Station upgrades improve scrap cost efficiency and leveling speed only—they do not raise the cap.

Agreed details: a level belongs to the schematic, so every copy you build has it and a wreck never removes it. Each level past 1 adds +4% to the part's main stats (internals grow their modifier, utilities cool down faster); power draw and weight never change. A level costs a rarity base (Common 15, Uncommon 30, Rare 60, Epic 110, Legendary 180) x the level being bought. Levelling is instant, capped at 3 levels per day. Station upgrades: Bench Discount (-10% per step, 3 steps) and Second Shift (+1 level per day, 2 steps). Levels don't change build cost or the wreck penalty.

Vehicle loss costs no scrap (the penalty was removed 2026-11-05; T.WRECK_PENALTY = 0). Chassis/ability to reassemble remains. Parts on the destroyed vehicle are lost (or heavily reduced).

# 5. Garage Systems and UI

Navigation: persistent footer tabs — Garage, Research, Saloon, Inn, Comms. Active tab highlighted with cyan/orange accent. All interactables clearly framed or glowing.

## Station Details

- Garage (core): Centered rotatable vehicle with outlined hardpoints. Part inventory sheet. Preset buttons. Upgrade panel for cost efficiency, max part level influence (via rarity), loot quality.

- Research: Select owned part, spend scrap to level. Shows cost, current/max level, stat preview.

- Saloon: Hire cards (free Common basics always present). Upgrades: more options, better rarity odds, higher starting level, lower cost.

- Inn: Roster with assign/rest status. Expeditions for reserve crew (passive scrap + crew XP, failure = reduced/no reward, no crew loss). Upgrades: more slots, XP share, rest time reduction, late small cheat-death chance, expedition capacity/success. Unlocks early-midgame.

  Agreed expedition details: the board opens after 3 successful missions and offers 3 named trips a day (one 1-2, one 3-4, one 5-6 skulls), each lasting 1-3 days. Send 1-6 benched crew; their total level against the trip's recommended level (3/6/10/15/21/28) sets the odds: 70% at the mark, +4% per level over (max 95%), -8% per level under (min 5%). Success pays scrap (20/30/42/56/72/90 by skulls, x1/x1.8/x2.5 for 1/2/3 days) and skulls x days XP split among the team; about 1 in 4 trips offers a schematic or recruit chance (3% per skull per day). Failure brings back 25% of the scrap and half the XP, and each member has a 25% injury chance. Nobody is lost. Inn upgrades: Bunkhouse (+1 roster), Drill Yard (idle crew get 25%/50% of mission XP), Infirmary (-1 rest day), Second Team (+1 expedition out at once), Scout Network (+5% odds), Last Rites (once Industrial Spine is open: 10%/20% per seated crew member to survive a wreck, injured for 3 days). Saloon upgrades: Back Room (+1 offer), Word Gets Around (+5% Rare, +2% Epic per step), Seasoned Hands (hires start at level 2/3), House Credit (-10% prices).

- Comms: Daily mission board with clear labels and threat/reward. District progress bars. Upgrades: better mission quality, more choices.

All stations use short upgrade tracks and the single scrap currency. No secondary resources.

# 6. Crew System

Eight classes (expanded with the owner's approval; exact numbers live in the "Helriders: Crew Draft" and "Helriders: Crew Expansion Draft" docs and `scripts/crew.gd`). Driver and Gunner have their own seats. Mechanic, Spotter, Engineer, Medic, Scavenger and Bruiser take a frame's open seats, one of each class aboard (Courier 1, Scrap Frame 1, Bulwark 2). Higher rarity = higher level cap, better passive, stronger ability, and more perks.

## Abilities (Common baseline; improve with level and rarity)

Each class has a passive, and each hire rolls a specialty within the class that sets their triggered ability.

- Driver: Passive turn/grip. Wheelman: Hard Line (handling boost; Epic+ speed spike). Speedster: Floor It. Bootlegger: Bootleg Turn.

- Gunner: Passive spread/turret aim (Epic+ lock range). Gunslinger: Overcharge. Marksman: Deadeye. Breacher: Piercing Rounds.

- Mechanic: Passive damage reduction. Fixer (renamed from Patcher; code rename pending): Field Repair (armor, throws off Hunters; Epic+ short damage reduction). Welder: Weld Plates.

- Spotter: Passive utility cooldowns. Marker: Mark (damage amp on the priority target). Scout: Flare (slow and amp shamblers nearby).

- Engineer: Passive power output. Overclocker: Overclock. Tinkerer: Reroute.

- Medic: Passive crew injury chance. Field Medic: Field Dressing. Combat Medic: Stim.

- Scavenger: Passive kill scrap and schematic odds. Magpie: Magnet. Salvager: Gold Rush.

- Bruiser: Passive ram dealt and taken. Bracer: Brace. Breaker: Shockwave.

Leveling: level caps 5 / 8 / 11 / 14 / 17 / 20 by rarity. XP is the job's skulls, split among the crew on the rig. At every 3rd level the player picks 1 of 3 random perks from the class's pool (4 shared + 4 class perks), no repeats.

In a mission, crew abilities fire from a crew wheel. The fight slows to 25% while it's open; the player picks an ability or closes it, and the wheel has a short cooldown.

Injury: a small chance on a big hit during a fight. An injured crew member loses their passive, perks and ability for the run, and the rig takes a class-specific penalty. Must rest in Inn for a set number of days (Inn upgrades can shorten). Cannot be assigned or sent on expeditions while resting.

Permanent loss: only on vehicle destruction. Free Common basics (Driver, Gunner) always available at Saloon to prevent soft-lock, even with a full roster: agreed with the owner (audit, 2026-11-04), the free hire fits one over the roster cap; while over, nothing else joins until someone leaves. Expeditions level reserve crew passively.

# 7. Missions, Districts, and Progression

Comms offers clearly labeled missions each day. Most are short single-zone fights. Specials appear less often.

- Standard: Clear, Survive, Hunt.

- Courier: Timed route. Better time = slightly better rewards. Fail time = no/reduced rewards. Generally lower combat risk.

- Escort / Retrieve-and-extract: Primary objective + optional deeper loot for extra risk.

  Retrieve (agreed; built. To be reconciled with §14 Extract or Push, since Retrieve already ends at its own extraction point): 3/3/4/4/5/5 caches around the block by skulls; leave through the extraction point (at the start, counts once you've left it) whenever you like with at least one. Danger climbs a step per cache grabbed and every 40 s: +2 zombies alive, +5% zombie speed, and at danger 2/4/6 a rig is called in (up to 0/1/1/2/2/3 by skulls). The farthest cache is the deep cache, guarded by a Gunner Rig: it counts double toward pay and carries a sure schematic. Pay = reward x (30% + 70% x caches brought out); every cache is ~1.3x a Clear. Pool: Turbo Four, Off-Road Tires, Oil Slick, Mine Dropper.

  Escort (agreed; built. To be reconciled with §14 Extract or Push): a friendly salvage truck (400 armor at 3 skulls, scaled by skull with the enemy-damage multiplier: 340 at 1, 780 at 5-6, agreed in the 2026-11-04 audit; speed 230, no guns) drives to 2/2/3/3/3/3 sites by skulls and works each for 20 s while you defend it; zombies and enemy rigs go for it. After the first site the driver radios (the game pauses) offering an extra, risky site: 30 s of work, a big wave and a rig, +60% pay and a sure schematic. The truck wrecked = job failed: the day passes, no job pay, kill scrap and the salvage you picked up kept (not a clear), no wreck penalty. Pays like Survive. Pool: Structural Bracing, Riot Plating, Emergency Patch, Burst Turret.

## District Unlock

Districts: Outer Blocks (start) → Midtown Ruins → Industrial Spine → Core Collapse. Gated by collected parts score. Only successfully extracted parts count.

Weighting example: Common 1 pt/level, Uncommon 2, Rare 4, Epic 7, Legendary 12. Thresholds tunable (e.g. 40 / 120 / 300). Progress bar visible on locked districts in Comms. Higher districts raise rarity floor/ceiling of loot and crew.

No forced ending. Core Collapse remains open for continued refinement.

## Night (agreed with the owner 2026-11-05; built, PR #79)

Night is rolled once per job from its seed and saved with the job (`night`). Comms shows a NIGHT badge before you take the job. The night colour is blue #2a3550 everywhere, the world grade and the NIGHT badge included (`COL_NIGHT_WORLD`; Cameron 2026-11-05). Only zombies and Hunters change at night: speed x1.1 (Hunters x1.1), damage x1.1, +4 alive at the start, faster ramp, bigger packs, earlier Tanks and Hunter, a horde surge every 35 s (4 s, warned 1.5 s before). Enemy rigs don't change. Rewards: pay x1.3 (stacks with any district's pay), kill scrap x1.25 rounded up, schematic chance +0.10, crew XP x1.25. Numbers are in `tuning.gd` (`NIGHT_*`).

Who gets night, first match wins:
1. Core Collapse: always night, no exceptions (above every rule below).
2. The tutorial: always day.
3. 1 skull, or before the first 3 clears: day.
4. Escort: day below 5 skulls, night at 5-6.
5. Courier: 50/50.
6. Outer Blocks Survive and Hunt at 4 skulls: night.
7. District chance (Outer Blocks 10%, Midtown 35%, Industrial 60%), +25% for Survive and Hunt (capped at 100%).

Board night share after 3 clears: Outer Blocks ~21%, Midtown ~43%, Industrial ~64%, Core 100%. A job saved before night existed rolls once on load from the same seed.

# 8. Combat Design

Arcade top-down. Mobility is a felt stat (turn radius + drift). Builds express immediately. Zombies are shared environmental pressure; enemy vehicles are the primary killers and best part source.

## Zombie Variants

- Shambler: Slow swarm, chip damage, clog movement.

- Brute: Armored, needs sustained fire or ram.

- Tank: Stronger Brute with charge that shoves vehicles.

- Boomer: Bile zone that attracts and frenzies nearby zombies.

- Slimer: Slippery mucus streak; vehicles lose traction.

- Hunter: Fast, latches for DoT. Remove by ramming obstacle, scraping, or shooting.

Agreed details: Brute 200 HP, bullets do half (rams full), speed 62, 8 dmg/s, shoves the rig. Tank 450 HP, bullets half; within 350 it roars for 0.8 s (aim locks for the last 0.3 s), charges at 520 for up to 0.9 s; a hit deals 25 and shoves the rig hard, a miss leaves it stumbling 1.5 s; 8 s cooldown. Boomer 60 HP, speed 53; bursts on death or on reaching the rig into a 140-wide bile pool for 8 s; a rig caught in the burst is marked for 6 s and zombies within 500 rush it at +60% speed, as do zombies in a pool. Slimer 70 HP, speed 84; leaves a 10 s slime trail and a bigger puddle where it dies; rigs on slime keep 35% grip (for 0.5 s after). They mix into hordes by skulls (1: none; 2: Slimers; 3: + Brutes, Boomers; 4+: + Tanks; at 6 skulls about 10% Slimer, 10% Brute, 8% Boomer, up to 2 Tanks); Courier only gets Slimers and Boomers. Scrap: Slimer 3, Boomer 3, Brute 6, Tank 15 plus a 20-scrap crate.

## Enemy Vehicles

Archetypes (refine later): Outrider (light flanker), Bulwark (heavy frontal), Gunner Rig (turret), Scrapper (hazard layer, see §14), Patcher (support, see §14), Convoy Lead (rarer mixed).

Gunner Rig (agreed): a standoff turret rig. 340 armor, speed 440, ram 40. Keeps 350-550 px from the player, circling, backing off when closed on. A slow turret (2.5 rad/s) fires 4-round bursts of 7 every 1.4 s (~20 damage/s); it turns on zombies within 120 px of it first. Clear: 1 from 3 skulls; Survive: one joins the waves from 4 skulls; Hunt: escorts the Elite at 5-6 skulls (when there's room under the 3-rig cap); Courier: from 4 skulls it guards a checkpoint halfway along the route. Pays 30 scrap; drops the Burst Turret, Belt Feed or Coolant Loop, or a 30-scrap cache. Burst Turret (new Uncommon weapon): 4-round bursts of 14 every 0.9 s (~62 DPS), spread 1.5, bullet speed 1800, turret turn 8, lock 600, 40 power, 15 weight, 110 scrap.

Scrapper Gunner (agreed 2026-11-04; the original Scrapper, kept as a slightly harder variant of §14's unarmed Scrapper): HP 110, 45 armor a facing, speed 510, the original weak turret (~10 damage/s); every 4 s it lays a mine, oil or a spike strip in turn. From 4 skulls, half the jobs that bring a Scrapper bring a Scrapper Gunner instead (seeded per job, named on Comms). Pays 35 scrap; drops from the Scrapper's pool. Spike strips (both Scrappers and the Spike Strip Dropper): rigs crossing them drive 30% slower for 3 s; zombies on them take 10 damage a second and move at half speed. The Spike Strip Dropper costs 90 scrap to build; the Oil Slick Dropper lays enemy-only oil; the Scrapper Gunner shares the Scrapper's drop pool at the same odds (all confirmed by the owner 2026-11-04). As first built, the Scrapper was: a fast, light trap layer. 200 armor, speed 580, ram 30. Weaves across the road ahead of the player 250-400 px out and every 6 s drops a trap behind it, alternating: a mine (40 damage in a 70 radius, arms in 0.6 s, lasts 25 s; zombies set it off too, enemy rigs don't) and an oil slick (140 wide, 15 s; rigs keep 35% grip, zombies move at half speed). One weak turret: 5 damage, 2 shots/s. Clear: 1 from 2 skulls (the first enemy rig players meet); Courier: 1 from 2 skulls; Survive: one joins the waves from 3 skulls; Hunt: none. Pays 25 scrap; drops the Oil Slick, Mine Dropper or Off-Road Tires, or a 25-scrap cache. Oil Slick (new Uncommon utility): 90 scrap, 10 power, 10 weight, every 14 s, pours a 140-wide slick behind the rig for 12 s; it only catches enemies; the player's rig never slides on its own oil (§14).

Convoy Lead (agreed; an elite enemy, not a boss; built). In §14's defense layers the cab is HP 200, front 250 (the plow: a very heavy front plate in place of the old half-damage nose), sides 70, rear 60, plus a 30 shield from 4 skulls; the trailer is HP 120, front 50, sides 65, rear 50 (350 total). An armored semi with a front ram, towing a short trailer with a heavy turret on a hitch. Cab 650 armor (total), speed 370, turn 1.5, ram 120; the ram on the nose takes half damage. It hunts and rams like a slower Bulwark. The trailer swings on the hitch (folding at most 80 degrees) and has its own 350 armor (the layers above); its turret (~30 damage/s, turn 2) can't fire through the cab (the 90 degrees facing it), so two small fixed nose guns (~32 damage/s) cover the front. Shooting the trailer off drops a 30-scrap crate and the cab drives on 15% faster; wrecking the cab takes the trailer too, pays 60 scrap and drops from its pool (Heavy MG Turret, Composite Plating, Diesel Block, Half-Track, Cowcatcher Ram, Hood Guns) or a 60-scrap cache. Counts as one rig toward the cap. Clear and Survive at 4+ skulls: 35% of jobs (50% at 6), seeded per job and shown on Comms, in an Outrider's place; Hunt escort at 5-6 skulls at the same odds; never in Courier. New Rare parts: Cowcatcher Ram (front only, armor 124, ram 170, weight 22, 180 scrap) and Hood Guns (fixed, 8 shots/s of 7, ~56 DPS, 40 power, 20 weight, 170 scrap). Spawn with simple roles; react opportunistically (focus damaged targets, screen allies, deal with zombies). Max 3 active. Destroying them is primary source of better parts.

# 9. Controls, Camera, and HUD

- Left virtual joystick: acceleration, braking/reverse, steering. Mobility scales responsiveness and drift.

- Right aim stick: independent aiming for fixed weapons and turret influence.

- Target lock button: toggles lock. Range and whether lock is available are per-weapon stats.

- Utility button(s).

Camera: tight slightly angled top-down, light dynamic zoom on speed or multi-vehicle threats, subtle look-ahead. Rotation-locked by default for clarity.

Combat HUD minimal: joysticks in corners, lock/utility on right, thin armor/power bar, small reticle and cooldown pips. Vehicle remains visual focus.

# 10. Economy

Single currency: scrap. Spent on part leveling, station upgrades, crew hires, and vehicle-loss penalties. Income from missions (scaled to threat), enemy vehicle destruction (best parts), expeditions (trickle). Early upgrades fast; later ones optional polish. Free basics + reassembly prevent soft-locks.

# 11. Presentation

## Visual

Pixel-voxel style. Chunky modular vehicles and parts. Gritty urban Twisted Metal aesthetic. High contrast: cyan/orange edge lights and accents so vehicles pop against muted concrete and wreckage. Strong silhouettes for build and role readability on mobile.

## Audio / Soundtrack

Sparse industrial. Distorted bass, metallic percussion, detuned synths, low drones. Garage: low-energy “Yard Idle”. Combat layers: Street Clear (low) → Contact (mid) → Crossfire (high), crossfading. Special: tighter pulse for Courier, near-silence + drone for wreck, dry confirmation for results. No heroic or melodic swells.

## Wreck Sequence

Dramatic and short: final hit, voxel plates explode, fire/dust, zombies swarm inside and haul crew out. Then results card and one-tap return. Injury on success is lighter (icon + rest timer only).

**Built (2026-11-04).** Agreed with the owner: about 4 s, and a tap skips to the results card; everyone aboard is shown dragged out the same way, names in red (who Last Rites saved is told on the card). Gap-fillers: the final hit plays at 30% speed for the first 0.8 s; plates, a fireball and dust burst off, the wreck keeps burning; six Shamblers close in from about 280 px; crew are hauled out one every 0.7 s; sticks, buttons and hints disappear as it starts.

## Onboarding

Start with basic pre-built vehicle + two free Common crew. One scripted low-threat Clear teaches stick movement, aim/fire, target lock, and one part swap on return. Subsequent days introduce stations naturally. Clear statement that crew are lost only on vehicle destruction.

**Built (2026-11-04).** Agreed with the owner: the tutorial is optional and lives in MENU only (TUTORIAL; replayable). It runs on a loaner rig and crew (the starter build with an Advanced Targeting Computer, so lock-on can be taught), costs no day, pays nothing and keeps nothing; then a guided garage tour (fit the salvaged part, then Comms, the Inn, the Saloon and Research, ending on "crew are lost only if your rig is wrecked") on a sandbox copy that's put back afterwards. Gap-fillers: the Training Run is five steps (drive 350 px; shoot four Shamblers; turn LOCK on, then four more; wreck a softened Outrider at 60% toughness; drive over its crate, a Riot Plating schematic); the loaner can't be wrecked (a killing blow patches it up) and swaps the Junk V6 and Junk Emitter for a Patched V8 to carry the computer; the pause menu offers LEAVE TUTORIAL; closing the app mid-tutorial doesn't bring you back to it; what you meet in it still counts toward the Database; DEPLOY is blocked during the tour.

# 12. Mobile Performance and Scope

- Target: stable 30 fps on ~2020 3–4 GB Android devices; 60 fps mid-range+. iOS equivalent from iPhone 8 era.

- Caps: 25–30 zombies, max 3 enemy vehicles, limited active zones/projectiles.

- Pause screen: Low / Medium / High / Ultra presets (frame cap, effects, density, shake). Auto-detected default, player override.
- **Pause menu built (2026-11-04).** Agreed with the owner: a job has no way back to the garage; quitting the game or closing the app mid-job puts you back into the same job at the next launch, the fight reset and nothing lost (no day passes). The menu has RESUME, RESTART JOB (two taps; same as a reset), SETTINGS, DATABASE and QUIT GAME; the garage's MENU button has SETTINGS, DATABASE, QUIT GAME and CLOSE. The Database lists parts, crew specialties, enemies, hazards and statuses, districts and job types; anything the player hasn't met is censored. Gap-fillers: Low 30 fps, 40% effects and splats, 60% shake; Medium 30 fps, 70%; High 60 fps, 85% effects; Ultra no cap, everything; the first guess goes by the phone's core count (4 or fewer Low, 6 Medium, more High); settings also hold a screen-shake switch and Music and Effects volumes, live once audio exists, and live in their own file so they survive a new game; the II button sits top right; the phone's back button opens the menu (and steps back through it); the app going to the background pauses the job; "met" means owned or picked up (parts), on your roster (crew), seen in a fight (enemies), caught in or blown up near you (hazards, statuses), unlocked (districts) and played (jobs).

- Vertical slice goal: one Outer Blocks Clear, functional Garage + Comms, 4–6 parts across categories, Driver + Gunner, full controls + dramatic wreck + return, 4–7 minute sessions, final-readability pixel-voxel art.

Art pipeline note: modular voxel attachments on shared chassis bases; zombie variants via palette + minor geometry. Keep draw calls and overdraw low.

# 13. Vertical Slice Definition

Prove the loop: Comms select Clear → assign Driver+Gunner → tight urban block with Shamblers, one Hunter, one enemy vehicle → clear → return with scrap + part (possible injury flag) → swap the new part → ready for next day. Must show build feel in first 30 seconds, readable threats, and quick recovery from loss.

This briefing is the source of truth for implementation. Enemy vehicle archetype details are the primary area left for later refinement. All other systems are specified to the level required to begin production of the vertical slice and full game.
# 14. Agreed in Principle — Numbers to Draft

Agreed with the owner on 2026-11-03. **Do not implement until the numbers are drafted and approved.** Where this section changes an earlier one, this section wins.

## Controller

A PlayStation-style pad (any pad Godot maps) works alongside touch. The first pad press switches to controller mode; touching the screen switches back.

- Fight: left stick drives. Right stick aims; a light push only turns the turret, as on the touch stick. R2 fires (with the stick centred, it fires the last way you aimed; the Mortar keeps the stick's push for range). Square / Triangle / Circle fire utilities 1-3. R1 toggles LOCK. L1 opens the crew wheel: point with a stick, Cross picks. Options pauses and resumes.
- Menus: every screen (garage, stations, Comms, part cards, Inn, Saloon, pause menu) is driven by D-pad or left stick to move, Cross to press and Circle to back out (closes the part sheet or panel, or returns to the garage from a station). L1 / R1 switch stations. Options opens MENU. A cyan ring marks the focused button. While a panel is open, focus stays inside it.
- Button mapping (Settings > CONTROLLER BUTTONS): every fight action (fire, utilities 1-3, LOCK, crew wheel, pause) can go on any pad button, L2 or R2. A button already in use swaps over. The sticks can swap (left aims, right drives). RESET TO DEFAULT restores the layout above. Menus keep the D-pad, Cross, Circle and L1 / R1, and Cross always picks in the crew wheel. HUD badges, hints and tutorial tips follow the mapping.

## Windows

The game also builds for Windows: every build on main attaches helriders-windows.zip (one helriders.exe) next to the APK. With a controller it plays exactly as on the phone. Settings has DISPLAY: WINDOWED / FULLSCREEN (F11 or Alt+Enter also flip it, saved), and Esc is the back button. Mouse and keyboard: WASD or the arrow keys drive (the rig turns toward the way you press, like the left stick); the turret follows the mouse; hold the left button to fire (the Mortar lands where you point); right click toggles LOCK (with LOCK on and no click, the turret is left to the lock); Q / E / F fire utilities 1-3; Tab opens the crew wheel (point and click, or press 1-4; right click closes it); Esc pauses. The game switches to mouse-and-keyboard wording as soon as you use them and back on a pad press. Keys aren't rebindable yet.

## Mods and Perks

- Part mods: pre-attached per schematic, visible while locked, unlocked by part level. Tier sets the unlock level: Minor 3, Major 7, Signature 11, Unique 18 (Legendary only). Rarity's max level decides which tiers a part can reach: Common Minor; Uncommon + Major; Rare + Signature; Epic + a second Major at 14; Legendary + Unique. The +4% per level stays. Mods belong to the schematic, like levels.
- Crew perks become tiered conditional mods tied to specialty: Minor at picks 3 and 6, Major at 9 and 12, Signature at 15 and 18. The 4 shared perks stay. Each specialty needs about 2 Minor, 2 Major and 2 Signature perks.
- Keywords connect part mods and crew perks: RAM, DRIFT, BURST, MARKED, STUNNED, OVERLOAD, SLICK, BURNING, CORRODED, GOOPED. Players discover interactions; no named synergies for now.
- Feedback: no floating text. Each keyword has one symbol, one animation and one fixed color (not reusing threat colors), in combat and on garage cards, throttled on busy screens.
- **Built (2026-11-04).** The owner approved the bots' numbers and asked for the remaining items with gap-filler definitions:
  - **DRIFT** is a sideways slide over 140 px/s while rolling over 150 px/s; it counts when the slide dies down, if it lasted 0.4 s.
  - **OVERLOAD** is a heat gun at 75% or more of its bar, before it locks hot. Enemy heat guns can be OVERLOADed too.
  - **Now wired:** Hit and Run (+15% damage for 2 s after a DRIFT), Drift Fuel (3 s off the Nitro Bottle), Clean Exit (1 s off Hard Line), Overload Coil (the arc chain hits 2 extra targets), Feedback Loop (Static Burst locks OVERLOADed enemy guns hot), Mobile Workshop (15% HP back the first time HP falls under 30%, once per mission).
  - **Keyword popups:** one pooled drawer (`keyword_fx.gd`), the symbol over the rig for 0.7 s, at most once per keyword per rig every 0.5 s and 6 on screen. They fire for RAM (yours), DRIFT, BURST (yours), MARKED, OVERLOAD and the six statuses. Garage part cards show a colored chip per keyword mod, 40% while locked.
  - **Also built:**
    - the Outrider's heat bar under it (outlined while OVERLOADed);
    - an Outrider at 25% HP runs to a live Patcher until it's back to 45%, and its break-off turn slides (grip cut to 30% for 0.5 s);
    - a Bulwark body-blocks for a Gunner Rig or Patcher within 400 px when you're closer to that ally than to it;
    - barrels you set off during the Demolisher's Cook Off hit 50% harder;
    - in Retrieve the Sludger arrives with the first danger step that calls a rig, not on a timer.

## Extract or Push

- After the objective: an extraction marker (cyan) and a push beacon (orange). Driving into one decides.
- Push: 60-90 s at the job's skulls +1 (cap 6; at 6, an extra rig instead), plus one extra rig. Success: scrap x1.5 and one extra schematic roll. A wreck loses everything as usual.
- About 1 in 3 jobs (33%, `PUSH_CHANCE` 0.33) allow it; never the onboarding mission or the day after a wreck. Hidden until the objective is done.

## New Enemy Rigs

- Patcher (support): unarmed. Grappling hook with a physical cable (~400 px) tethers it to an ally it repairs; the ally can drag it. Hook pops on a big hit (>15% max armor in 1 s) or hard physical impact on either rig, or the player ramming the cable at speed. Re-hook: 3 s with a visible wind-up. With no ally alive, revives a wreck at 10% max armor over 4 s, up to 3 times per job (`PATCHER_MAX_REVIVES`); any player damage to the Patcher interrupts. A revived rig's uncollected crate goes back into it; one crate's worth of loot per rig per mission. From 3 skulls, only alongside another rig; counts toward the 3-rig cap. Drops repair and self-buff parts.
- Scrapper (hazard layer): unarmed. Lays oil (grip loss like slime; ignited by explosions and fire; burning oil damages everything, player included) and spike strips (temporary speed debuff). Cuts across the player's path; lays hazards behind it when chased. Spawns alone from 2 skulls; counts toward the cap; Courier's signature rig. Drops hazard utilities (Mine Dropper, Oil Slick and Spike Strip droppers) and grip parts.

## Hazards

- The player never damages themselves. Player-placed hazards never hurt the player; only battlefield hazards can (barrels, enemy oil even when the player lit it).
- Barrels: Explosive, Fire, Acid, Slime, Boomer. Shot or rammed; hit everything in range. Fixed spots per layout; type rolled per mission.

## Maps

- Layouts are shared across districts; districts change art and enemy mix. Each job type draws suitable layouts.
- Per-mission variation: blocked roads, shifted props, different spawn sides.
- Target: at least 4 layouts per job type (~12 total), to expand later.
- **Built (2026-11-04).** Agreed with the owner: six layouts for the beta, every district looking the same for now. Crossroads (all jobs), Main Drag (Clear, Courier, Retrieve, Escort), Parking Lots (Clear, Survive, Hunt, Escort), Back Alleys (Clear, Hunt, Courier, Retrieve), Rail Yard (Clear, Survive, Courier, Escort) and Plaza (Clear, Survive, Hunt, Retrieve): at least four per job type. Gap-fillers: every layout is the same size as the old block; board jobs get a layout and a variation from their seed (the Comms card names the map); a variation mirrors left-right and/or top-bottom (each half the time), nudges props up to 50 px, barricades one or two roads from each layout's list of safe spots, and has zombies come from two or three of the four sides; maps go in the Database's Places tab once played; jobs from before layouts, and the tutorial, use the Crossroads as drawn. Every layout and 25 variations each are checked headless: every stop, barrel spot, spawn point and the Escort truck's spot is open and reachable from the start.

## New Weapons

- Harpoon: Rare, Bulwark drop, fixed mount. Tethers rigs only; pierces several zombies; sets off barrels. Mass decides who is pulled. Tether breaks by the Patcher rules; firing again releases.
- Mortar: Uncommon, Gunner Rig drop, turret. Lobs over buildings; long range, slow shells, minimum range. Stick push sets distance (landing circle); LOCK aims at the predicted position.
- Shock Pulse: utility. Short-range shock burst around the rig, long cooldown. Shock is a damage type other parts can carry (e.g., a Shock Mortar).

## Status, Resistance, Shields, Damage Types

- Every status uses buildup: hits fill a bar that drains over time and triggers the status when full. Shock -> STUNNED, Fire -> BURNING, Acid -> CORRODED (increased damage taken), Slime -> SLICK, Goop -> GOOPED.
- Every rig (player and enemy) has a resistance per status. Player resistances come from armor parts (each armor type has a profile) and internals (e.g., an EMP-hardened computer).
- HUD: player buildup bars next to the armor bar, shown only while building. Enemy rigs: small bar under the rig while building. Zombies: none.
- Shields: recharging layer, usually much lower than armor, recovering after a delay. Better shields: higher max, shorter delay and/or faster recharge. From internal-slot generators: light but power-hungry. Armor is heavy; only specialized armor costs power. An active shield adds bonus resistance to every status. Some enemy rigs have shields.
- Damage types: Kinetic (bullets, rams) all-round; Shock bonus vs. shields; Acid bonus vs. armor; Fire bonus vs. zombies and spreads between them.

## Combat Contract and Loss

- Time to wreck (focused, standing still): 15 / 13 / 11 / 9 / 7.5 / 6 s at skulls 1-6. Anchor damage numbers to this.
- **Balanced (2026-11-04).** Agreed with the owner: the target describes a build that fits the skull (a starter at 1-2, a mid build at 3-4, a late build at 5-6). `tools/balance/balance_report.gd` measures it: the whole Clear roster spawned around a parked rig, mean of 5 runs. To hit it, enemy rigs' guns and rams, zombies and Hunters deal ×0.85 / 0.95 / 1.0 / 1.1 / 1.95 / 1.95 of their damage at skulls 1-6 (`T.ENEMY_DAMAGE_BY_SKULL`; a Hunt Elite keeps its own table), and hordes at skulls 1-2 are 20% / 10% smaller (`T.HORDE_SCALE_BY_SKULL`). Result: 14.5 / 12.8 / 10.6 / 8.9 / 7.8 / 6.6 s. Consequence: the step from 4 to 5 skulls is steep (a mid build at 5 lasts about 3 s), so 5-6 skull jobs ask for late gear.
- Rig loss is minor: the day after a wreck, the player can rebuild close to their last build and run the same skull level.
- Lost crew return: after 3 days (Uncommon), +1 day per rarity step (Rare 4, Epic 5, Legendary 6, Mythic 7), they enter a rehire pool at level 1 with the same specialty and rarity (perks reset).
- Saloon rehire section: one extra card a day, drawn at random from the rehire pool. A rehire can be dismissed permanently, which returns them to the general hire pool.
- Rehire price: 20% below a normal hire of that rarity. Saloon upgrade Old Faces: 3 steps, each a further 10% off (max 50%).
- **Built (2026-11-04).** Agreed with the owner: lost Commons don't come back (the Saloon always has free ones); Old Faces costs 150 / 350 / 700; Seasoned Hands and House Credit apply to rehires too (House Credit stacks on the rehire discount). Gap-fillers: the return days count from the day after the wreck; the rehire card sits at the end of the Saloon row, marked BACK, with SEND AWAY next to HIRE; hiring or sending away spends the day's card (a new one comes tomorrow if anyone else is waiting); Last Rites survivors aren't lost; the wreck card says who may turn up again and when; the Saloon notes how many lost crew are still on the way. Agreed with the owner: a hire or rehire that starts above level 1 (Seasoned Hands) still leaves every perk pick it skipped to the player; nothing is picked for them.

## Part Mods: First Draft (test-build parts)

Spiked Ram Plate is renamed Zed Sled (code rename pending). Unlock levels: Minor 3, Major 7, Signature 11.

| Part | Minor | Major | Signature |
|---|---|---|---|
| Zed Sled (Uncommon armor) | Cowcatcher: shamblers hit by a RAM are flung aside; half the speed loss per shambler | Breaker Bar: RAM on a rig adds heavy shock buildup; full speed nearly fills it | - |
| Half-Track (Rare drive) | Grouser Plates: SLICK builds 50% slower | Dug In: when not DRIFTING, Tank and Bulwark shoves move you far less | Neutral Steer: turn on the spot at a standstill |
| Diesel Block (Rare engine) | Low-End Torque: +20% acceleration below half speed | Load Bearer: armor parts weigh 15% less | Dead Weight: counts as 15% heavier in collision damage |
| Scattergun Turret (Uncommon) | Point Blank: +20% damage within 150 px | Slug Round: vs STUNNED, fires one heavy slug | - |
| Outrider Twin Guns (Uncommon) | Laser sight on the fixed guns | +15% fire rate | - |
| Outrider Sport Wheels (Uncommon) | Quick Grip: regain grip 25% faster after a drift | 10% less incoming damage while DRIFTING | - |
| Outrider Light Plating (Uncommon) | Low Profile: shield recharge delay 20% shorter | 10% of max armor added to max shield | - |
| Turbo Four (Uncommon engine) | Spool-Up: +10% top speed after 2 s at full throttle | Blow-Off Valve: +25% speed for 2 s when the shield breaks | - |
| Burst Turret (Uncommon) | Tight Grouping: 25% tighter spread per BURST | Live Tip: last round of each BURST deals shock | - |
| Heavy MG Turret (Rare) | Spin-Up: fire rate climbs to +20% over 3 s | Suppression: rig under fire 2 s drives 20% slower, turret turns half as fast | Tracer Belt: every 5th round is incendiary |
| Advanced Targeting Computer (Rare) | Fast Solve: LOCK range +10% | Priority Override: LOCK takes MARKED and STUNNED first | Weak Point Solver: locked turrets aim at exposed sides or rear, +20% damage |

## Defense Layers: Shield, Directional Armor, HP

Replaces the single armor pool (§4 Armor Sections, §8 Bulwark front rule).

**Built (2026-11-04).** Agreed gap-fillers: the starter carries Scrap Plating on all three slots and the Junk Emitter (100/100 power, 95/100 weight); old saves copy their one plate to all three slots (a front-only ram plate to the front only). Structural Bracing gives +25 max HP (and keeps +15 ram). Cowcatcher Ram: front only, 124 armor, front-slot weight 22. Convoy Lead cab: HP 200, front 250, sides 70, rear 60, shield 30 from 4 skulls; trailer: HP 120, front 50, sides 65, rear 50 (350 in total, not the 300 it had). The salvage truck: HP 120, 70 on every facing. Enemy shields recharge like the Junk Emitter (3 s delay, ~5 s refill). Capacitor Bank and Flux Coil arrived with the Patcher; the Reflex Emitter with the new weapons.

- Three layers for player and enemy rigs: shield (recharges) -> armor (directional, never regenerates) -> HP (structure; zero = wreck).
- HP comes from the chassis, plus some parts that raise max HP (e.g., Structural Bracing).
- Three armor slots: Front, Sides (one part covers both flanks), Rear. Any armor part fits any slot except front-only ram plates (Zed Sled). All count against weight.
- Hit facing: four 90-degree arcs (front, left, right, rear). A hit drains that arc's armor; a stripped facing passes hits to HP. Status buildup ignores facing.
- Explosions: full damage to the nearest facing plus 25% to each adjacent facing. Splash never reduces HP while any armor remains; HP takes damage only from direct hits on a stripped facing, or from splash once all armor is gone.
- Repairs restore armor only, most damaged facing first. HP restores only between missions (rare part/perk exceptions later).
- Enemy rigs use the same model. The Bulwark's half-damage front becomes a very heavy front plate.
- HUD: a small top-down rig icon. Plates show each facing's armor, a ring shows the shield, the central body block drains as HP drops. Buildup bars beside it, only while building.

## Ammo Models

- Each weapon uses a magazine (fire until empty, then reload) or heat (firing fills a bar; at max it overheats and locks until the bar drains to empty). Assignment per weapon: to decide.

## Crew Perks: First Draft

| Specialty | Minor | Minor | Major | Major | Signature | Signature |
|---|---|---|---|---|---|---|
| Wheelman (Hard Line) | Long Line: +20% duration | Sure Footing: SLICK builds 50% slower during it | Clean Exit: ending a DRIFT during it takes 1 s off cooldown | Threading: shamblers brushed aside without slowing you | Immovable Line: no shoves from Tank or Bulwark during it | Racing Line: each near-miss shot extends it 0.5 s |
| Speedster (Floor It) | Deep Tank: +20% duration | Quick Fuse: -15% cooldown | Battering Speed: RAMs +30% during it | Open Road: above 80% top speed, restore 1% max armor/s | Afterburn: burning trail (fire, BURNING, ignites oil) | Clean Run: no damage taken -> half cooldown refunded |
| Bootlegger (Bootleg Turn) | Tight Swing: -15% cooldown | Shake Off: throws off a latched Hunter | Tail Swipe: rear counts as a RAM while swinging | About Face: fixed guns +25% for 2 s after | Double Back: 2 charges | Oil Spin: enemy-only oil ring |
| Gunslinger (Overcharge) | Hot Barrels: +1 s | Quick Draw: -15% cooldown | Bottomless: no ammo use or heat during it | Red Hot: shots also deal fire, build BURNING | Siphon: 10% of damage refills shield | Full Auto: turrets turn 2x fast, no spread |
| Marksman (Deadeye) | Steady Aim: +1 s | Deep Breath: -15% cooldown | Plate Splitter: +30% damage to armor during it | Called Shot: +50% vs MARKED | Opening Shot: first shot triple damage | Executioner: wrecks rigs below 10% HP |
| Breacher (Piercing Rounds) | Long Burn: +1 s | Deeper Cuts: pierce 4 | Overpenetration: +10% per target passed | Bleed-Through: 20% of armor hits go to HP | Rail Line: pierces rigs too | Acid Core: pierced targets take acid, build CORRODED |
| Fixer (Field Repair) | Spare Parts: +20% repair | Quick Wrench: -15% cooldown | Kickstart: skips shield recharge delay | Fresh Weld: repaired facing -20% damage for 4 s | Full Rebuild: once per mission, fully restores a stripped facing | Hull Patch: also restores 5% max HP |
| Gearhead (Tune-Up) | Fine Tuning: +1 s | Spare Time: -15% cooldown | Tight Servos: turrets +25% turn, LOCK +10% | Clean Lines: status buildup drains 2x | Crew Tune: halves other crew cooldowns | Afterglow: boosts fade over 4 s |
| Conduit (Power Divert) | Clean Routing: +1 s | Capacitor: -15% cooldown | Insulated Feed: shield status bonus doubled | Spillover: half leftover bonus shield -> armor (capped) | Arc Feedback: shield hits shock the shooter | Grid Priority: utility cooldowns 2x during it |
| Tinkerer (Scrap Drones) | Longer Leash: +2 s | Spare Rotors: -15% cooldown | Third Wheel: 3 drones | Bait Drones: zombies prefer drones | Kamikaze: expiring drones dive and explode | Copycat: drones use your weapon's damage type and keywords |
| Marker (Mark) | Lingering Mark: +2 s | Quick Spot: -15% cooldown | Exposed: MARKED shields stop recharging | Pass It On: Mark jumps on kill | Weak Point: +50% to HP on a MARKED rig's stripped facing | Shutdown: MARKED rigs can't use abilities |
| Scout (Flare) | Bright Flare: +100 px | Slow Fade: +2 s | Pinned: Hunters inside can't pounce | Magnesium: Flare burns (BURNING) | Signal Flare: rigs inside become MARKED | Flashbang: ignition stuns zombies inside |
| Field Medic (Field Dressing) | Clean Bandage: half rest days | Quick Kit: -15% cooldown | Back in It: treated crew's ability ready | Second Kit: 2 charges | Full Recovery: no rest days | Last Breath: once per mission, a lethal hit leaves 1 HP |
| Poisoner (Miasma) | Thick Fumes: +2 s | Quick Vent: -15% cooldown | Lingering Cloud: cloud stays 4 s | Caustic Gas: also builds CORRODED | Contagion: TOXIC zombies burst and spread it | Neurotoxin: TOXIC rigs -25% speed, half turret turn |
| Magpie (Magnet) | Wide Pull: +200 px | Sticky Fingers: -15% cooldown | Scrap Plating: 2 armor per salvage pulled | Snatch: steals a wreck's crate before a revive | Shrapnel Storm: pulled salvage damages enemies | Second Look: pulled rig crate rolls twice |
| Salvager (Gold Rush) | Long Haul: +2 s | Quick Count: -15% cooldown | Bounty: rig wrecks drop bonus scrap | Strip Mine: armor damage knocks loose scrap | Jackpot: rig wrecks always drop a schematic | Safe Deposit: Gold Rush scrap survives a wreck |
| Bracer (Brace) | Firm Stance: +1 s | Quick Set: -15% cooldown | Shell: no splash spill during it | Counterweight: 25% heavier in collisions | Juggernaut: RAMs don't slow you, rigs go flying | Absorb: blocked damage released as a shock wave |
| Breaker (Shockwave) | Wider Blast: +50 px | Quick Reset: -15% cooldown | Live Wire: deals shock | Clear Out: hurls zombies, throws off Hunter | Aftershock: second half-strength wave after 1 s | Payback: +50% of damage taken in the last 3 s |

## Specialty Changes and New Status

- Welder -> Gearhead (Mechanic). Ability Tune-Up: 6 s of +15% speed, +15% fire rate, shield recharges with no delay.
- Overclocker -> Conduit (Engineer). Ability Power Divert: for 6 s, unused power budget becomes extra shield, which keeps recharging under fire.
- Tinkerer (Engineer): ability changes from Reroute to Scrap Drones: 2 orbiting drones for 10 s that shoot nearby enemies and draw some zombie attention.
- Combat Medic -> Poisoner (Medic). Ability Miasma: 6 s toxic cloud, 250 px around the rig; own rig immune.
- TOXIC (new status, 11th keyword): buildup like the others; damage over time that bypasses armor to HP, blocked by a raised shield, never takes a rig below 10% max HP.
- Armor never exceeds a facing's max; repair past the cap is lost.

## Ammo Assignment (first pass, case by case)

Pintle Turret: magazine. Outrider Twin Guns: heat. Scattergun Turret: magazine. Heavy MG Turret: heat. Burst Turret: magazine. Harpoon: magazine (1). Mortar: small magazine.

## New Parts (first pass)

Shield sizes are relative to a medium frame's front armor.

| Part | Rarity / source | Power / weight | Key stats | Minor | Major | Signature |
|---|---|---|---|---|---|---|
| Junk Emitter (shield) | Common / start | 25 / 5 | ~20% shield, 3 s delay, refill ~5 s | Static Skin: shield up -> SLICK and GOOPED build 25% slower | - | - |
| Capacitor Bank (shield) | Uncommon / Patcher | 35 / 5 | ~40% shield, 4 s delay, refill ~6 s | Deep Cells: +10% max shield | Discharge: breaking releases a short shock pulse | - |
| Flux Coil (shield) | Uncommon / Patcher | 30 / 5 | ~25% shield, 2.5 s delay, refill ~1 s | Clean Coil: delay -0.3 s | Surge: full recharge adds +20% over max for 3 s | - |
| Reflex Emitter (shield) | Rare / Hunt Elite | 40 / 5 | ~25% shield, 1 s delay, refill ~3 s | Quick Reset: delay -0.2 s | Second Skin: first break each mission refills to 50% | Phase Cycle: recharges under fire while DRIFTING |
| EMP-Hardened Computer | Uncommon / Gunner Rig | 30 / 5 | Aims turrets without a Gunner (no LOCK); High shock resistance | Faraday Cage: STUNNED 30% shorter | Grounded: no shock bonus against your shield | - |
| Harpoon (fixed weapon) | Rare / Bulwark | 40 / 20 | Mag 1, 2.5 s reload, 600 px range, 500 px cable | Barbed Tip: +20% to pierced zombies | Power Winch: reel 30% faster | Wrecking Ball: tethered rig slammed into wall, rig or barrel takes 2x collision damage |
| Mortar (turret) | Uncommon / Gunner Rig | 45 / 25 | Mag 3, 4 s reload, 300-1200 px, ~1.2 s flight, 90 px blast | Heavy Charge: +20% blast radius | Cluster Shell: splits into 3 blasts | - |
| Shock Pulse (utility) | Uncommon / Outrider | 20 / 10 | 18 s cooldown, 180 px, heavy shock buildup | Wide Field: +20% radius | Drain Arc: strips 50% of enemy shields | - |
| Oil Slick Dropper (utility) | Uncommon / Scrapper | 15 / 15 | 14 s cooldown, 12 s oil pool, enemy-only | Wide Spill: +25% pool size | Pilot Light: self-ignites after 2 s | - |
| Spike Strip Dropper (utility) | Uncommon / Scrapper | 15 / 15 | 12 s cooldown, 15 s strip; rigs slowed, zombies hurt and slowed | Long Strip: +30% length | Shredder: crossing rigs take armor damage | - |

## Armor Resistance Profiles

| Armor | Shock | Fire | Acid | Toxic | Slime / Goop |
|---|---|---|---|---|---|
| Scrap Plating | Low | Low | Low | Low | Low |
| Outrider Light Plating | Medium | Low | Low | Medium | Medium |
| Riot Plating | High | Medium | Low | Low | Medium |
| Zed Sled (front only) | Low | Medium | Medium | Low | High |
| Composite Plating (costs power) | Medium | High | High | Medium | Low |

## Part Mods: Remaining Existing Parts

Approved one by one through Pintle Turret; Targeting Computer onward were finished by Claude at the owner's request and await review.

| Part | Minor | Major | Signature |
|---|---|---|---|
| Scrap Frame (Common; HP medium-low) | Spare Bolts: +5% max HP | - | - |
| Courier Frame (Uncommon; HP low) | Deep Pockets: utility cooldowns -10% | Low Rider: above half speed, side hits -20% | - |
| Bulwark Frame (Rare; HP high) | Reinforced Ribs: +8% max HP | Crew Bunker: crew injury chance -25% | Command Deck: crew ability cooldowns -15% |
| Junk V6 (Common) | Spare Pistons: +5% acceleration | - | - |
| Patched V8 (Uncommon) | Big Block: +5% power output | Backfire: letting off at full speed blasts flame out the back (fire, ignites oil), once per 6 s | - |
| Street Wheels (Common) | Fresh Tread: +5% grip | - | - |
| Off-Road Tires (Uncommon) | Chunky Tread: +10% grip in hard turns | All-Terrain: ground hazards affect you 50% less | - |
| Scrap Plating (Common) | Easy Patch: +10% repair on its facings | - | - |
| Riot Plating (Uncommon) | Riot Grille: zombies clawing it take light damage | Hard Shell: -15% kinetic damage to its facing | - |
| Composite Plating (Rare) | Layered: +5% armor on its facings | Neutralizer: CORRODED and TOXIC last 30% shorter | Reactive Layer: once per mission per facing, a stripping hit leaves 25% |
| Pintle Turret (Common) | Steady Mount: -10% spread | - | - |
| Targeting Computer (Common) | Quick Track: turret turn +5% | - | - |
| Coolant Loop (Uncommon) | Chill Lines: heat builds 10% slower | Flash Cool: overheats end 40% faster | - |
| Belt Feed (Uncommon) | Fast Feed: reloads 10% faster | Extended Belt: magazines +25% | - |
| Structural Bracing (Uncommon; now raises max HP) | Cross Braces: a further +5% max HP | Load Path: collision damage taken -15% | - |
| Roll Cage (Uncommon) | Padding: injured crew rest 1 day less | Safety Cell: splash damage can't injure crew | - |
| Emergency Patch (Rare) | Bigger Patch: +20% armor restored | Quick Fit: -20% cooldown | Full Spread: also restores half the amount to every other facing |
| Mine Dropper (Rare) | Wide Blast: +20% blast radius | Extra Mine: drops 4 mines | Seeker Mines: armed mines creep toward the nearest enemy rig |

## Numbers: First Pass

Finding: today's starter dies in ~5 s standing still at 1 skull (~32 DPS from 8 shamblers + a latched Hunter vs 150 armor). These values hit the 15 s target; enemy damage unchanged.

| Frame | HP |
|---|---|
| Courier Frame | 105 |
| Scrap Frame | 150 |
| Bulwark Frame | 270 |

| Armor part | Armor per facing | Front/Rear slot weight | Sides slot weight |
|---|---|---|---|
| Outrider Light Plating | 62 | 7 | 12 |
| Zed Sled (front only) | 71 | 15 | - |
| Scrap Plating | 80 | 12 | 21 |
| Riot Plating | 115 | 18 | 33 |
| Composite Plating | 142 | 17 (+4 power) | 30 (+7 power) |

| Shield | Max | Delay | Full refill |
|---|---|---|---|
| Junk Emitter | 30 | 3 s | ~5 s |
| Flux Coil | 45 | 2.5 s | ~1 s |
| Reflex Emitter | 45 | 1 s | ~3 s |
| Capacitor Bank | 75 | 4 s | ~6 s |

**Built (2026-11-04)**, with these agreed gap-fillers: Shock does +50% to shields, Acid +50% to armor plates, Fire +50% to zombies. The player's resistances add up from parts: a base of 30, plus each fitted plate's profile (Low +5, Medium +10, High +15; three Scrap plates = 45), plus any chassis or accessory bonus, capped at 95 (an active shield still adds +15, cap 100). The Cowcatcher Ram uses the Zed Sled's profile. Zombies are neutral (50). Slime, oil and fire ground build 25/s inside; a Boomer's burst fills GOOPED like the Boomer barrel. Burning zombies set off others within 50 px at 50 fire buildup a second. Barrel blasts reach 140 px (Boomer 160 px); the slime pool is 160 px across; a Fire barrel's ground burns ~100 px around it. Seven barrels per job on twelve fixed spots of the current block.

Status bars: always 100 points. Resistance 0-100; buildup taken = hit buildup x (100 - resistance) / 50 (0 = x2, 50 = x1, 100 = immune). Resistance from parts: `STATUS_RESIST_BASE` 30, plus `STATUS_RESIST_STEP` per fitted plate (Low +5, Medium +10, High +15), capped at `STATUS_RESIST_CAP` 95. Active shield +15 (cap 100). Drain 15/s after 1.5 s without buildup; after a trigger, buildup 50% slower for 3 s.

| Status | Lasts | On rigs | On zombies |
|---|---|---|---|
| STUNNED | 1.2 s | Can't drive, fire or turn turrets | 2 s frozen |
| BURNING | 5 s | 6/s across facings (splash rule) | 15/s, spreads on touch |
| CORRODED | 6 s | +25% damage taken | Same |
| TOXIC | 8 s | 4/s to HP, floor 10%, shield blocks | 4/s |
| SLICK | 3 s | Grip 35% | Slowed |
| GOOPED | 6 s | Zombies within 500 px rush at +60% | Frenzied |

Enemy rigs (same total toughness as today). Shields from 4 skulls: Gunner Rigs carry 30. Hunt Elite 1.6-2.5x applies to every layer.

| Rig | HP | Front | Each side | Rear | Shock | Fire | Acid | Toxic | Slime | Goop |
|---|---|---|---|---|---|---|---|---|---|---|
| Outrider | 100 | 40 | 40 | 40 | 45 | 50 | 50 | 50 | 35 | 50 |
| Gunner Rig | 120 | 60 | 55 | 55 | 35 | 55 | 50 | 50 | 55 | 50 |
| Bulwark | 180 | 180 | 55 | 50 | 60 | 60 | 35 | 55 | 70 | 50 |
| Scrapper | 90 | 35 | 35 | 35 | 50 | 30 | 50 | 50 | 90 | 50 |
| Patcher | 80 | 30 | 30 | 30 | 35 | 50 | 50 | 40 | 50 | 50 |

Patcher: speed 475; cable 400 px; repairs 12 armor/s to the ally's most damaged facing; hook range 450 px; re-hook 3 s; revive 4 s to 10% HP; 35 scrap. Never repairs itself (self-repair reserved for possible stronger enemies).

**Patcher built (2026-11-04).** Agreed with the owner: the chance a job brings one rises with skulls (25% at 3, 40% at 4, 55% at 5, 70% at 6; only in jobs with another rig; seeded per job and named on Comms; at most one). It drops the Capacitor Bank, Flux Coil, Emergency Patch or Structural Bracing (or a 35-scrap cache); both shields cost 110 scrap. Gap-fillers: every hook throw has the 3 s wind-up (sight blocked pauses it; drifting well out of reach restarts it); a hard crash is a wall impact over 335 px/s; ramming the cable needs over 300 px/s; a revived rig comes back at 10% of HP and of each facing, shield empty; any damage to the Patcher (not only yours) restarts a revive; it doesn't revive the Convoy Lead or another Patcher; a revived rig wrecked again counts as a kill but pays no more scrap, and drops the crate it took back (if any); it rolls in once another rig is in the fight (or when no more rigs are due, so a Clear can always finish).

Scrapper: speed 510; one hazard every 3 s, alternating oil and spikes; max 6 active (oldest vanish first); oil 90 px wide, 12 s; spike strip 120 px long, 15 s, crossing rigs -30% speed for 3 s; 25 scrap.

**New weapons built (2026-11-04).** Agreed with the owner: Harpoon 45 damage to a rig and 30 to each zombie it pierces (up to 4), 170 scrap; Mortar 60 per shell (full at the center, half at the edge), 120 scrap; Shock Pulse 15 damage plus the 90 shock buildup, 90 scrap; EMP-Hardened Computer 90 scrap; Reflex Emitter 160 scrap. The Mortar fires while the right stick is held: the push walks the landing circle from 300 to 1200 px, and it lobs a shell whenever one is ready. Gap-fillers: the Mortar fires a shell every 0.6 s from its magazine (about 35 damage/s over a full magazine and reload); the Harpoon's spear starts at the hull, stops at walls, and sets off barrels on the way; its cable reels in at 100 px/s down to 200 px, and "mass" is hull size (a bigger rig gets pulled less); it pops like the Patcher's hook (over 15% of either rig's max in 1 s, or a wall crash over 335 px/s), and it lets go when either rig is wrecked; the EMP-Hardened Computer adds +15 shock resistance (the High step); the Shock Pulse leaves barrels alone. Drop sources: Harpoon from the Bulwark, Mortar and EMP-Hardened Computer from the Gunner Rig, Shock Pulse from the Outrider, Reflex Emitter from the Hunt Elite. Mods (Barbed Tip, Power Winch, Wrecking Ball, Heavy Charge, Cluster Shell, Wide Field, Drain Arc) are built (`mods.gd`).

Ammo: Pintle Turret 28 rounds, 2 s reload. Scattergun 6 shells, 2.5 s. Burst Turret 6 bursts, 2.2 s. Outrider Twin Guns overheat after 6 s nonstop, 3 s lockout, cool 25%/s idle. Heavy MG overheats after 8 s, 4 s lockout, cools 20%/s idle. Harpoon 1 shot, 2.5 s. Mortar 3 shells, 4 s.

**Ammo built (2026-11-04).** Agreed with the owner: ammo and heat show as rings around the fire stick, one per weapon (magazines drain and refill grey while reloading; heat fills orange to red). Gap-fillers: a magazine only reloads when it runs dry (no manual or idle reload); a Burst Turret's magazine counts bursts; heat fills so 6 s (Twin Guns) or 8 s (Heavy MG) of nonstop fire overheats it whatever the fire rate, and an overheated gun drains to empty over its lockout before it fires again; the garage's DPS is now sustained DPS, counting reloads and lockouts (Pintle 43, Burst Turret 50, Twin Guns 32); the Hood Guns and enemy rigs' guns have no ammo limit for now.

Barrels: 20 HP; any ram sets them off; blasts chain. Explosive: 140 px, 60 damage, strong shove. Fire: 140 px, 25 damage, ground burns 6 s (heavy BURNING buildup, ignites oil). Acid: 140 px, 20 damage + 80 acid buildup. Slime: 160 px pool, 10 s. Boomer: 160 px, fills the GOOPED bar instantly.

Buildup per hit: a typed hit adds 2x its damage as buildup, before resistance (~50 damage triggers at neutral). Fixed amounts: Shock Pulse 90; Zed Sled Breaker Bar full-speed ram 80; Acid barrel 80; Miasma, fire ground and slime pools 25/s inside.

New crew abilities (Common baseline; rarity +10% effect and duration, -1 s cooldown per step):

| Ability | Effect | Duration | Cooldown |
|---|---|---|---|
| Tune-Up (Gearhead) | +15% speed, +15% fire rate, no shield recharge delay | 6 s | 22 s |
| Power Divert (Conduit) | +1 shield per unused power point (cap 80), recharges under fire | 6 s | 24 s |
| Scrap Drones (Tinkerer) | 2 drones, 20 HP each, 4-damage shots 3x/s | 10 s | 26 s |
| Miasma (Poisoner) | 250 px cloud, 25 TOXIC buildup/s | 6 s | 22 s |
