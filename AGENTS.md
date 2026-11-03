# Working on Helriders (for AI agents: Claude, Grok, others)

The owner works from a phone and has no computer, so nobody opens the Godot editor. Every change must be correct as plain text and verified headless. CI is the only build machine.

## Source of truth

- `docs/DESIGN.md` is the design. Systems marked "locked" are locked. Enemy vehicle archetypes are the main open area.
- `scripts/tuning.gd` holds every balance number, color and collision layer. Tune there, not inside gameplay scripts.
- `scripts/parts.gd` holds part schematics (stats, slots, power, weight), the drop pools and the starter loadout. Part numbers were approved by the owner in the "Helriders: New Parts Draft" doc; don't change them without asking. `scripts/loadout.gd` is the only place that combines parts into rig stats (weapons list, internal modifiers, abilities, power and weight budgets). Player capabilities come from parts and crew: for example, lock exists only with the Advanced Targeting Computer in an internal slot and a weapon whose `lock_range` > 0, and a turret aims only with a seated Gunner or a targeting computer.
- Utility parts are abilities: `vehicle.gd` `use_ability(i)` runs them, `hud.gd` shows a button each. A new utility needs a case there and, if it spawns things, a pooled single-node drawer like `mine_pool.gd`.
- Crew: `scripts/crew.gd` holds the eight classes, specialties and their abilities, rarities, level curve, passives, injury debuffs and perks (numbers approved in the "Helriders: Crew Draft" and "Helriders: Crew Expansion Draft" docs; don't change them without asking). `Crew.compute_mods()` is the only place crew turn into rig modifiers; the Garage stat sheet and `vehicle.gd` both call it. `profile.gd` owns the roster, seats (Driver, Gunner, open seats with one of each class), perk offers and picks, Saloon offers, XP and rest; `vehicle.gd` applies crew live (`set_crew`, `crew_mod()`, `use_crew_ability`, `injure_crew`). A new ability needs a case in `Crew._apply_active` (timed modifiers) or `vehicle.use_crew_ability` (instant effects), or `mission._on_crew_ability` if it reaches past the rig. Crew abilities fire from the HUD crew wheel (`hud.open_crew_wheel`, `pick_crew`), which slows the game while open; utilities keep their own buttons.

- Research: a level belongs to the schematic (`Profile.levels`). `Parts.at_level()` is the only per-level math; `Loadout.build(loadout, levels)` applies it, so game code builds the player's rig with `profile.build_stats()` and shows parts with `profile.part(id)`. Numbers (growth, max levels, costs, daily cap, the two Research upgrades) live in `tuning.gd` and were agreed with the owner; don't change them without asking. `scripts/research.gd` is the station screen.

- Expeditions and the Inn and Saloon upgrade tracks: rules in `profile.gd` (Expeditions section; `_advance_expeditions()` runs from `finish_day()`), numbers in `tuning.gd` (agreed with the owner; don't change them without asking), screens in `inn.gd` and `saloon.gd`. Station upgrade panels for the Inn and Saloon use `upgrade_panel.gd`. Tests force rolls with `Profile.roll_override`.

- `scripts/profile.gd` (autoload `Profile`) is the save game: scrap, schematics, storage, the rig, presets, upgrades. Every change saves to `user://`. Economy rules agreed with the owner are listed at the top of that file; don't change them without asking.

## Engine rules

- **Godot 4.7.2**, pinned in `.github/workflows/android.yml` and `project.godot` features. Bump both together.
- **Compatibility renderer only** (`gl_compatibility`). Don't switch to Forward+ or Mobile (Vulkan). Older Android Vulkan drivers are unreliable and the target is 2020-era 3–4 GB phones.
- **Code-first scenes.** Nodes are built in GDScript (`garage.gd` and `mission.gd` assemble their screens). Keep `.tscn` files minimal. Hand-written scene files with resource IDs break silently without an editor.
- **Static typing everywhere.** Use `:=` or explicit types. Values from a `Dictionary` need an explicit type (`var x: float = d.key`), because `:=` can't infer from a Variant.
- **`preload` constants instead of `class_name`**, for example `const Zombie := preload("res://scripts/zombie.gd")`. They work in headless runs before the class cache exists, and they can be used as types.
- **Don't shadow native classes.** Godot 4.7 has a native `VirtualJoystick`, which is why ours is `ThumbStick`. Import fails on a clash.
- Commit the `.uid` and `.import` files Godot generates next to scripts and assets.

## Performance rules (mobile budget)

- Caps from the design: 25–30 zombies (`ZOMBIE_CAP`), at most 3 enemy vehicles, limited projectiles.
- Pool everything that spawns in combat. Don't call `new()` or `queue_free()` in the combat loop.
- Many small things go in one node with packed arrays and one `_draw()`, like `bullet_pool.gd`, `fx.gd` and `splats.gd`. Never one node per bullet or particle.
- Swarms are steered from one loop (`zombie_director.gd`), not a script per zombie.
- Collision layers: world = 1, player rig = 2, zombie/hunter = 4, enemy rig = 8. Zombies don't collide with each other.
- Pathing: ask `nav_grid.gd` for the next waypoint a few times a second (staggered), never every tick. It skips A* when there's a clear line.
- Static art is drawn once. Only call `queue_redraw()` when something changes.

## How enemies are built

- Anything shootable that isn't a rig extends `hostile.gd` (`take_hit`, `is_targetable`, `lock_priority`, `died`). Pool it.
- Enemy rigs extend `vehicle.gd` and only decide stick inputs (`drive_input`, `fire_trigger`), the way `enemy_rig.gd` (Outrider) and `bulwark_rig.gd` (Bulwark) do. They share the player's driving model, so builds feel the same on both sides. Their flat stat sheets live in `tuning.gd` (`OUTRIDER`, `BULWARK`). Armor that blunts hits implements `deflects(at)` so bullets throw grey sparks.
- Bullets carry a team (`bullet_pool.gd`). Each team's ray mask decides what it can hit, so nobody shoots their own side.
- New mission-level enemies get a `spawn_*` function in `mission.gd` that tests can call directly (`auto_spawn_specials = false`).
- Mission types and their tables live in `tuning.gd` (`MISSIONS`, six entries per stat, one per skull 1-6); `missions.gd` builds the daily board inside the district's skull band; `mission.gd` runs any type. Tests set `mission_override` to run a specific mission and `apply_rig()` to swap the player's build mid-run.
- Schematic drop pools by source are `Parts.DROP_POOLS`. Drops never repeat a schematic the player owns.

## Verify before pushing

```sh
godot --headless --path . --import                  # must print no "SCRIPT ERROR"
godot --headless --fixed-fps 60 --path . -s res://tests/smoke_test.gd   # must end "SMOKE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/garage_test.gd  # must end "GARAGE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/missions_test.gd # must end "MISSIONS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/crew_test.gd     # must end "CREW TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/research_test.gd # must end "RESEARCH TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/expedition_test.gd # must end "EXPEDITION TEST PASSED"
```

- Tests must call `Profile.new_game()` with `persist = false` first, so they never touch a real save.

- Godot's import exits 0 even with script errors, so read the output.
- Extend `tests/smoke_test.gd` when you add a core mechanic (new enemy, lock-on, part swap). It drives the game by setting `hud.left_stick.output` and `hud.right_stick.output` directly.
- For visual checks without a GPU: `xvfb-run godot --rendering-driver opengl3 ...` with a script that saves `root.get_texture().get_image()` to PNG.

## Build and delivery

Pushing to `main` runs `.github/workflows/android.yml`. It imports the project, runs the smoke test, exports a debug APK, and replaces the `latest-build` release. The owner installs from:
https://github.com/Asmogius/helriders-game/releases/download/latest-build/helriders.apk

If the workflow fails, the owner gets no build. Check the run and fix it before moving on.
