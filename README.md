# Helriders

Top-down arcade roguelike for phones. Build one armored, Twisted Metal-style rig from scavenged parts, crew it, and run missions through a ruined, zombie-choked city for scrap and better parts. No microtransactions.

The full design is in [docs/DESIGN.md](docs/DESIGN.md). It is the source of truth.

## Play the latest build (Android)

Every push to `main` builds a fresh APK.

1. On your phone, open **[helriders.apk (latest build)](https://github.com/Asmogius/helriders-game/releases/download/latest-build/helriders.apk)** while signed in to GitHub (the repo is private).
2. Open the downloaded file. The first time, Android asks you to allow installs from your browser. Allow it.
3. Later builds install over the top. Your phone keeps one copy.

All builds are listed on the [latest-build release page](https://github.com/Asmogius/helriders-game/releases/tag/latest-build). The build number appears in the top-right corner of the game, next to the FPS counter.

## Current state: Phase 3 prototype

The day loop works: open **COMMS**, take one of today's jobs, tune your rig in the **Garage**, tap **DEPLOY**, and come back with what you extracted. One job per day. Progress is saved on the phone.

### Comms

- Three jobs a day, each with a type, a difficulty of **1 to 6 skulls**, what's in the block, and its pay. Tap a card, then **TAKE JOB**. The board stays the same all day and changes when the day ends.
- Each district's board rolls inside its skull band: Outer Blocks 1-4, Midtown 2-5, Industrial 3-6, Core 4-6.
- A job can pay a schematic from its type's pool. Odds by skulls 1-6: 0 / 15 / 30 / 50 / 75 / 100%. Courier only pays one for a gold time; a Hunt Elite always drops one.
- Job types:
  - **Clear:** kill every shambler, Hunter and Outrider on the list (1 skull: 30 shamblers and a Hunter; 6 skulls: 50 shamblers, 2 Hunters, 2 Outriders). Pays Riot Plating, Spiked Ram Plate or the Scattergun.
  - **Survive:** hold out for 2:00 to 3:00 while the crowd grows; Hunters and Outriders arrive on a schedule. Pays Structural Bracing, Belt Feed, the Patched V8 or Emergency Patch.
  - **Hunt:** a named Elite Outrider (gold stripe, 1.6x to 2.5x armor). Wreck it and grab the Rare schematic it always drops (Bulwark Frame, Diesel Block, Half-Track, Composite Plating, Heavy MG, Advanced Targeting, Mine Dropper).
  - **Courier:** 5 to 7 checkpoints in order. Gold, silver and bronze par times pay 100%, 75% and 50%; late pays 25%. Gold can pay the Courier Frame, Turbo Four or Off-Road Tires.
- Every job ends the day: success, wreck, or closing the app mid-run (that costs the day, nothing else).
- **Districts** along the bottom fill with your parts score (extracted schematics: Uncommon 2, Rare 4). Midtown opens at 40.
- **Comms upgrades:** Wider Net (a 4th and 5th job), Better Leads (+15% pay per level).

### Garage

- Slot tags sit around the rig: chassis, engine, drive, armor, then the weapon, internal and utility slots the chassis has (Scrap Frame 1/2/1, Courier 1/1/2, Bulwark 2/2/1). Tap a tag, or the slot's ring on the rig, to open that slot.
- 27 parts in all: 3 frames, 4 engines, 4 drives, 5 armors, 4 weapons, 5 internals, 2 utilities. Internals can change the build by a percentage (Coolant Loop fire rate +15%, Belt Feed damage +12%, Advanced Targeting lock range +25% and turret aim +20%).
- Two budgets under the rig: **POWER LOAD** against the engine's output and **WEIGHT LOAD** against the frame's capacity. Going over either one cuts speed and acceleration; both together stack.
- A sheet of part cards slides up. **Tap a card once** to compare it on the full stat sheet: every number, with the change in green (better) or red (worse). Speed and acceleration include any overload. **Tap it again** to fit it.
- **Scrap is the only currency.** Owning a schematic lets you build that part for scrap. **Common parts are free.** A part you take off goes to storage and goes back on for free.
- **PRESETS** saves up to three builds. Loading one builds whatever you don't have on hand.
- **UPGRADES:** Fabrication Discount (cheaper parts), Loot Quality (better schematic odds from Outriders), Salvage Yield (more scrap from kills).
- **Wrecks** destroy the rig and every part on it, cost a scrap penalty of 25% of the lost build's value, and lose the run's loot. Schematics and storage survive. **REBUILD** puts your last build back together; if you can't afford it, you get a free all-Common starter rig.
- Research, Saloon, Inn and Comms tabs are placeholders for now.

### Mission

- **Left thumb:** drive. Point where you want to go. Pull behind you while slow to reverse. Hard turns at speed drift.
- **Right thumb:** aim the turret. Push past halfway to fire. Manual aim always overrides lock. Fixed guns point where the rig points and fire on any push. With two weapons (Bulwark), both fire together.
- **LOCK button** (above the right stick): toggles target lock. While on, the turret picks the most dangerous target in range, leads it, and fires by itself. Priority: a Hunter on your hull, then enemy rigs, then Hunters, then the nearest shambler.
- **Lock comes from a part.** The Targeting Computer schematic sits in one of the chassis's internal slots, and the weapon has to support lock (the turret does, fixed guns don't). Without both, there's no LOCK button.
- **Power** works like Armored Core's energy load. Every installed part draws power all the time, against the engine's output. The thin bar under armor shows the total. The starter rig sits at exactly 100/100, and the Targeting Computer is 25 of that, so lock is a build decision. Pull the computer to free 25 power for something else. Go over budget and the rig is overloaded: acceleration and top speed drop until the build fits again. Switching lock on or off costs nothing extra.
- **Weight** works the same way against the frame's capacity. The starter weighs 85 of 100; Riot Plating takes it to 105 and slows it down.
- **Utility buttons** sit left of LOCK, one per utility part, with a cooldown sweep. **Emergency Patch** restores 35 armor (25 s). **Mine Dropper** drops 3 mines behind you (15 s); each arms after 0.5 s, does 60 damage in a small blast when anything hostile touches it, and lasts 20 s. Your mines never hurt you.
- **Ramming:** fast hits kill shamblers and Hunters. Slow pushes get you clogged in the crowd.
- **Hunter:** it pulses red before it leaps. If it latches on, it chews armor until you crush it into a wall, scrape it along one, or shoot it.
- **Outrider:** a fast enemy rig with forward guns that makes strafing passes. Wreck it and it drops a schematic you don't own yet, or a scrap cache once you have them all. Drive over the crate to grab it.
- Edge arrows point at off-screen threats: red for the Outrider, rust for the Hunter, cyan for salvage, orange for the last few shamblers.
- Success banks the run's kill scrap, the job's pay and any schematics. A wreck loses them.

Shamblers spawn in packs from off-screen, path around buildings, block the rig, and chip armor on contact. Parking gets you swarmed. Keep moving.

## Tech

| | |
|---|---|
| Engine | Godot 4.7.2, GDScript |
| Renderer | Compatibility (OpenGL ES 3) for 2020-era Android phones |
| Target | Stable 30 fps on 3–4 GB Android phones, 60 fps mid-range |
| Build | GitHub Actions: import, three headless tests, debug APK, publish |

Performance choices so far:

- Bullets, particles and ground stains each live in one node with packed arrays, so there's one draw pass and no per-object nodes.
- Zombies come from a fixed pool of 28, and one director loop steers all of them.
- Zombies don't collide with each other. A cheap separation pass spaces them out instead.
- Pathing uses Godot's native `AStarGrid2D` on a 40 px grid. Each zombie re-plans a few times a second, and only when a building blocks its line of sight.
- The static arena is drawn once.

## Layout

```
docs/DESIGN.md          design briefing (source of truth)
project.godot           engine settings (Compatibility renderer, landscape)
scenes/garage.tscn      start screen (runs scripts/garage.gd)
scenes/mission.tscn     the mission (runs scripts/mission.gd)
scripts/
  garage.gd             Garage: slots, part cards, stat sheet, presets, upgrades
  comms.gd              Comms: job board, districts, Comms upgrades
  missions.gd           daily board and per-job setup (types, skulls, pay)
  profile.gd            save game (autoload "Profile"): scrap, schematics, rig, economy rules
  ui_theme.gd           shared menu look
  mission.gd            builds and runs any job type
  tuning.gd             all balance numbers, colors, collision layers
  vehicle.gd            any rig: drift handling, weapons, lock-on, ramming, armor
  enemy_rig.gd          Outrider AI (extends vehicle.gd)
  hostile.gd            shared base for shamblers and Hunters
  zombie.gd             pooled shambler
  hunter.gd             the Hunter: chase, pounce, latch
  zombie_director.gd    zombie pool, pack spawning, steering
  nav_grid.gd           A* grid for pathing around buildings
  bullet_pool.gd        every bullet, both teams, in one node
  mine_pool.gd          every mine from the Mine Dropper, in one node
  fx.gd / splats.gd     particles and ground stains
  parts.gd              part schematics (power, weight, slots), drop pools, starter loadout
  loadout.gd            turns a loadout (parts in slots) into rig stats
  pickup.gd             salvage crates
  lock_reticle.gd       brackets on the locked target
  arena.gd              the city block and its collision
  chase_camera.gd       follow camera
  hud.gd                HUD, lock and utility buttons, banners, results card, threat arrows
  thumb_stick.gd        floating touch joystick
tests/smoke_test.gd     headless mission test, run in CI
tests/garage_test.gd    headless Garage and economy test, run in CI
tests/missions_test.gd  headless board, districts and mission-type test, run in CI
.github/workflows/      Android build
ci/debug.keystore       debug-only signing key (see below)
```

## Run it locally (with a computer)

```sh
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s res://tests/smoke_test.gd
godot --headless --fixed-fps 60 --path . -s res://tests/garage_test.gd
godot --headless --fixed-fps 60 --path . -s res://tests/missions_test.gd
godot --path .   # play on desktop; mouse acts as a single touch
```

## Signing

`ci/debug.keystore` is a **debug-only** key with the standard `android` / `androiddebugkey` credentials. It's committed so every build has the same signature and installs over the last one. A Play Store release will need a separate private key stored as a GitHub secret, never in the repo.

## Roadmap to the vertical slice

From DESIGN §13:

- [x] Twin-stick controls, drift handling, turret, ramming
- [x] Shamblers with pooling, spawn packs, contact damage
- [x] Clear objective, wreck sequence, results card, quick restart
- [x] Android build pipeline
- [x] Target lock button (per-weapon lock range)
- [x] Hunter zombie (fast, latches for damage over time)
- [x] One enemy vehicle (Outrider) that drops a part
- [x] Parts, slots and an Armored Core-style power budget (lock needs the Targeting Computer)
- [x] Garage screen: swap parts between runs, presets, upgrades, saved progress
- [x] Comms screen: daily job board with Clear, Survive, Hunt and Courier; districts
- [x] First parts batch: 18 new schematics, weight, two hardpoints, pellets, Emergency Patch and Mine Dropper, 1-6 skull jobs
- [ ] Driver + Gunner crew with passive and triggered abilities
- [ ] Pixel-voxel art pipeline (voxel models rendered to sprite sheets)
- [ ] Pause menu with Low / Medium / High / Ultra presets
