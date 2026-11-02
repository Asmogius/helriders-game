# Helriders

Top-down arcade roguelike for phones. Build one armored, Twisted Metal-style rig from scavenged parts, crew it, and run missions through a ruined, zombie-choked city for scrap and better parts. No microtransactions.

The full design is in [docs/DESIGN.md](docs/DESIGN.md). It is the source of truth.

## Play the latest build (Android)

Every push to `main` builds a fresh APK.

1. On your phone, open **[helriders.apk (latest build)](https://github.com/Asmogius/helriders-game/releases/download/latest-build/helriders.apk)** while signed in to GitHub (the repo is private).
2. Open the downloaded file. The first time, Android asks you to allow installs from your browser. Allow it.
3. Later builds install over the top. Your phone keeps one copy.

All builds are listed on the [latest-build release page](https://github.com/Asmogius/helriders-game/releases/tag/latest-build). The build number appears in the top-right corner of the game, next to the FPS counter.

## Current state: Phase 1 prototype

One "Clear" mission in an Outer Blocks city block: 40 shamblers, one Hunter, and one enemy rig.

- **Left thumb:** drive. Point where you want to go. Pull behind you while slow to reverse. Hard turns at speed drift.
- **Right thumb:** aim the turret. Push past halfway to fire. Manual aim always overrides lock.
- **LOCK button** (above the right stick): toggles target lock. While on, the turret picks the most dangerous target in range, leads it, and fires by itself. Priority: a Hunter on your hull, then enemy rigs, then Hunters, then the nearest shambler.
- **Ramming:** fast hits kill shamblers and Hunters. Slow pushes get you clogged in the crowd.
- **Hunter:** shows up 25 seconds in (or after 10 kills). It pulses red before it leaps. If it latches on, it chews armor until you crush it into a wall, scrape it along one, or shoot it.
- **Outrider:** a fast enemy rig with forward guns. It arrives 45 seconds in (or after 20 kills) and makes strafing passes. Wreck it and it drops a salvage part; drive over the crate to grab it.
- Edge arrows point at off-screen threats: red for the Outrider, rust for the Hunter, cyan for salvage, orange for the last few shamblers.
- The results card lists salvage you extracted. If you get wrecked, it's lost.

Shamblers spawn in packs from off-screen, path around buildings, block the rig, and chip armor on contact. Parking gets you swarmed. Keep moving.

## Tech

| | |
|---|---|
| Engine | Godot 4.7.2, GDScript |
| Renderer | Compatibility (OpenGL ES 3) for 2020-era Android phones |
| Target | Stable 30 fps on 3–4 GB Android phones, 60 fps mid-range |
| Build | GitHub Actions: import, smoke test, debug APK, publish |

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
scenes/main.tscn        entry scene (just runs scripts/main.gd)
scripts/
  main.gd               builds and runs the mission
  tuning.gd             all balance numbers, colors, collision layers
  vehicle.gd            any rig: drift handling, weapons, lock-on, ramming, armor
  enemy_rig.gd          Outrider AI (extends vehicle.gd)
  hostile.gd            shared base for shamblers and Hunters
  zombie.gd             pooled shambler
  hunter.gd             the Hunter: chase, pounce, latch
  zombie_director.gd    zombie pool, pack spawning, steering
  nav_grid.gd           A* grid for pathing around buildings
  bullet_pool.gd        every bullet, both teams, in one node
  fx.gd / splats.gd     particles and ground stains
  pickup.gd / parts.gd  salvage crates and part definitions
  lock_reticle.gd       brackets on the locked target
  arena.gd              the city block and its collision
  chase_camera.gd       follow camera
  hud.gd                HUD, lock button, banners, results card, threat arrows
  thumb_stick.gd        floating touch joystick
tests/smoke_test.gd     headless test run in CI
.github/workflows/      Android build
ci/debug.keystore       debug-only signing key (see below)
```

## Run it locally (with a computer)

```sh
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s res://tests/smoke_test.gd
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
- [ ] Garage screen: swap a part between runs
- [ ] Comms screen: pick the mission
- [ ] Driver + Gunner crew with passive and triggered abilities
- [ ] Pixel-voxel art pipeline (voxel models rendered to sprite sheets)
- [ ] Pause menu with Low / Medium / High / Ultra presets
