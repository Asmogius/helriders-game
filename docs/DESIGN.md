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

5. Success: return with scrap, parts, crew XP (possible injuries). Failure (vehicle destroyed): dramatic wreck, scrap penalty scaled to build cost, assigned crew permanently lost.

6. Land in garage. Upgrade parts via Research, manage roster/injuries/expeditions, upgrade stations, prepare next day.

Persistent power: better parts (rarity + level), higher-level crew you protect, light station upgrades, and district access via weighted parts score.

# 4. Vehicle Customization

Exactly one physical vehicle. Freely editable between missions using owned parts. Presets save full loadouts but only include parts the player currently possesses.

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

Vehicle loss applies a scrap penalty scaled to the cost of the lost build. Chassis/ability to reassemble remains. Parts on the destroyed vehicle are lost (or heavily reduced).

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

Permanent loss: only on vehicle destruction. Free Common basics (Driver, Gunner) always available at Saloon to prevent soft-lock. Expeditions level reserve crew passively.

# 7. Missions, Districts, and Progression

Comms offers clearly labeled missions each day. Most are short single-zone fights. Specials appear less often.

- Standard: Clear, Survive, Hunt.

- Courier: Timed route. Better time = slightly better rewards. Fail time = no/reduced rewards. Generally lower combat risk.

- Escort / Retrieve-and-extract: Primary objective + optional deeper loot for extra risk.

## District Unlock

Districts: Outer Blocks (start) → Midtown Ruins → Industrial Spine → Core Collapse. Gated by collected parts score. Only successfully extracted parts count.

Weighting example: Common 1 pt/level, Uncommon 2, Rare 4, Epic 7, Legendary 12. Thresholds tunable (e.g. 40 / 120 / 300). Progress bar visible on locked districts in Comms. Higher districts raise rarity floor/ceiling of loot and crew.

No forced ending. Core Collapse remains open for continued refinement.

# 8. Combat Design

Arcade top-down. Mobility is a felt stat (turn radius + drift). Builds express immediately. Zombies are shared environmental pressure; enemy vehicles are the primary killers and best part source.

## Zombie Variants

- Shambler: Slow swarm, chip damage, clog movement.

- Brute: Armored, needs sustained fire or ram.

- Tank: Stronger Brute with charge that shoves vehicles.

- Boomer: Bile zone that attracts and frenzies nearby zombies.

- Slimer: Slippery mucus streak; vehicles lose traction.

- Hunter: Fast, latches for DoT. Remove by ramming obstacle, scraping, or shooting.

Agreed details: Brute 200 HP, bullets do half (rams full), speed 70, 8 dmg/s, shoves the rig. Tank 450 HP, bullets half; within 350 it roars for 0.8 s (aim locks for the last 0.3 s), charges at 520 for up to 0.9 s; a hit deals 25 and shoves the rig hard, a miss leaves it stumbling 1.5 s; 8 s cooldown. Boomer 60 HP, speed 60; bursts on death or on reaching the rig into a 140-wide bile pool for 8 s; a rig caught in the burst is marked for 6 s and zombies within 500 rush it at +60% speed, as do zombies in a pool. Slimer 70 HP, speed 95; leaves a 10 s slime trail and a bigger puddle where it dies; rigs on slime keep 35% grip (for 0.5 s after). They mix into hordes by skulls (1: none; 2: Slimers; 3: + Brutes, Boomers; 4+: + Tanks; at 6 skulls about 10% Slimer, 10% Brute, 8% Boomer, up to 2 Tanks); Courier only gets Slimers and Boomers. Scrap: Slimer 3, Boomer 3, Brute 6, Tank 15 plus a 20-scrap crate.

## Enemy Vehicles

Archetypes (refine later): Outrider (light flanker), Bulwark (heavy frontal), Gunner Rig (turret), Scrapper (hazard layer, see §14), Patcher (support, see §14), Convoy Lead (rarer mixed).

Gunner Rig (agreed): a standoff turret rig. 340 armor, speed 500, ram 40. Keeps 350-550 px from the player, circling, backing off when closed on. A slow turret (2.5 rad/s) fires 4-round bursts of 7 every 1.4 s (~20 damage/s); it turns on zombies within 120 px of it first. Clear: 1 from 3 skulls; Survive: one joins the waves from 4 skulls; Hunt: escorts the Elite at 5-6 skulls (when there's room under the 3-rig cap); Courier: from 4 skulls it guards a checkpoint halfway along the route. Pays 30 scrap; drops the Burst Turret, Belt Feed or Coolant Loop, or a 30-scrap cache. Burst Turret (new Uncommon weapon): 4-round bursts of 14 every 0.9 s (~62 DPS), spread 1.5, bullet speed 1800, turret turn 8, lock 600, 40 power, 15 weight, 110 scrap. Spawn with simple roles; react opportunistically (focus damaged targets, screen allies, deal with zombies). Max 3 active. Destroying them is primary source of better parts.

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

## Onboarding

Start with basic pre-built vehicle + two free Common crew. One scripted low-threat Clear teaches stick movement, aim/fire, target lock, and one part swap on return. Subsequent days introduce stations naturally. Clear statement that crew are lost only on vehicle destruction.

# 12. Mobile Performance and Scope

- Target: stable 30 fps on ~2020 3–4 GB Android devices; 60 fps mid-range+. iOS equivalent from iPhone 8 era.

- Caps: 25–30 zombies, max 3 enemy vehicles, limited active zones/projectiles.

- Pause screen: Low / Medium / High / Ultra presets (frame cap, effects, density, shake). Auto-detected default, player override.

- Vertical slice goal: one Outer Blocks Clear, functional Garage + Comms, 4–6 parts across categories, Driver + Gunner, full controls + dramatic wreck + return, 4–7 minute sessions, final-readability pixel-voxel art.

Art pipeline note: modular voxel attachments on shared chassis bases; zombie variants via palette + minor geometry. Keep draw calls and overdraw low.

# 13. Vertical Slice Definition

Prove the loop: Comms select Clear → assign Driver+Gunner → tight urban block with Shamblers, one Hunter, one enemy vehicle → clear → return with scrap + part (possible injury flag) → swap the new part → ready for next day. Must show build feel in first 30 seconds, readable threats, and quick recovery from loss.

This briefing is the source of truth for implementation. Enemy vehicle archetype details are the primary area left for later refinement. All other systems are specified to the level required to begin production of the vertical slice and full game.
# 14. Agreed in Principle — Numbers to Draft

Agreed with the owner on 2026-11-03. **Do not implement until the numbers are drafted and approved.** Where this section changes an earlier one, this section wins.

## Mods and Perks

- Part mods: pre-attached per schematic, visible while locked, unlocked by part level. Tier sets the unlock level: Minor 3, Major 7, Signature 11, Unique 18 (Legendary only). Rarity's max level decides which tiers a part can reach: Common Minor; Uncommon + Major; Rare + Signature; Epic + a second Major at 14; Legendary + Unique. The +4% per level stays. Mods belong to the schematic, like levels.
- Crew perks become tiered conditional mods tied to specialty: Minor at picks 3 and 6, Major at 9 and 12, Signature at 15 and 18. The 4 shared perks stay. Each specialty needs about 2 Minor, 2 Major and 2 Signature perks.
- Keywords connect part mods and crew perks: RAM, DRIFT, BURST, MARKED, STUNNED, OVERLOAD, SLICK, BURNING, CORRODED, GOOPED. Players discover interactions; no named synergies for now.
- Feedback: no floating text. Each keyword has one symbol, one animation and one fixed color (not reusing threat colors), in combat and on garage cards, throttled on busy screens.

## Extract or Push

- After the objective: an extraction marker (cyan) and a push beacon (orange). Driving into one decides.
- Push: 60-90 s at the job's skulls +1 (cap 6; at 6, an extra rig instead), plus one extra rig. Success: scrap x1.5 and one extra schematic roll. A wreck loses everything as usual.
- About 3 in 4 jobs allow it; never the onboarding mission or the day after a wreck. Hidden until the objective is done.

## New Enemy Rigs

- Patcher (support): unarmed. Grappling hook with a physical cable (~400 px) tethers it to an ally it repairs; the ally can drag it. Hook pops on a big hit (>15% max armor in 1 s) or hard physical impact on either rig, or the player ramming the cable at speed. Re-hook: 3 s with a visible wind-up. With no ally alive, revives a wreck at 10% max armor over 4 s, unlimited; any player damage to the Patcher interrupts. A revived rig's uncollected crate goes back into it; one crate's worth of loot per rig per mission. From 3 skulls, only alongside another rig; counts toward the 3-rig cap. Drops repair and self-buff parts.
- Scrapper (hazard layer): unarmed. Lays oil (grip loss like slime; ignited by explosions and fire; burning oil damages everything, player included) and spike strips (temporary speed debuff). Cuts across the player's path; lays hazards behind it when chased. Spawns alone from 2 skulls; counts toward the cap; Courier's signature rig. Drops hazard utilities (Mine Dropper, Oil Slick and Spike Strip droppers) and grip parts.

## Hazards

- The player never damages themselves. Player-placed hazards never hurt the player; only battlefield hazards can (barrels, enemy oil even when the player lit it).
- Barrels: Explosive, Fire, Acid, Slime, Boomer. Shot or rammed; hit everything in range. Fixed spots per layout; type rolled per mission.

## Maps

- Layouts are shared across districts; districts change art and enemy mix. Each job type draws suitable layouts.
- Per-mission variation: blocked roads, shifted props, different spawn sides.
- Target: at least 4 layouts per job type (~12 total), to expand later.

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
