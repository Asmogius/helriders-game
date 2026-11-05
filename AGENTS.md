# Working on Helriders (for AI agents: Claude, Grok, others)

The owner works from a phone and has no computer, so nobody opens the Godot editor. Every change must be correct as plain text and verified headless. CI is the only build machine.

## Source of truth

- `docs/DESIGN.md` is the design. Systems marked "locked" are locked. Enemy vehicle archetypes are the main open area.
- `docs/VISUAL_PLAN.md` is the visual upgrade plan (garage areas, zombies, effects, maps, rarity colours, interface): read its rules before any art or look change, and take tasks from it in its order.
- `scripts/tuning.gd` holds every balance number, color and collision layer. Tune there, not inside gameplay scripts.
- `scripts/parts.gd` holds part schematics (stats, slots, power, weight), the drop pools and the starter loadout. Part numbers were approved by the owner in the "Helriders: New Parts Draft" doc; don't change them without asking. `scripts/loadout.gd` is the only place that combines parts into rig stats (weapons list, internal modifiers, abilities, power and weight budgets). Player capabilities come from parts and crew: for example, lock exists only with the Advanced Targeting Computer in an internal slot and a weapon whose `lock_range` > 0, and a turret aims only with a seated Gunner or a targeting computer.
- Utility parts are abilities: `vehicle.gd` `use_ability(i)` runs them, `hud.gd` shows a button each. A new utility needs a case there and, if it spawns things, a pooled single-node drawer like `mine_pool.gd`.
- Crew: `scripts/crew.gd` holds the eight classes, specialties and their abilities, rarities, level curve, passives, injury debuffs and perks (numbers approved in the "Helriders: Crew Draft" and "Helriders: Crew Expansion Draft" docs; don't change them without asking). `Crew.compute_mods()` is the only place crew turn into rig modifiers; the Garage stat sheet and `vehicle.gd` both call it. `profile.gd` owns the roster (the free Saloon hire, `hire_basic`, may go one over `roster_cap()`: `can_hire_basic()`), seats (Driver, Gunner, open seats with one of each class), perk offers and picks, Saloon offers, XP and rest, and lost crew (`lost` -> `rehire_pool` after `T.LOST_RETURN_DAYS`; `rehire_offer`, `rehire`, `dismiss_rehire`); `vehicle.gd` applies crew live (`set_crew`, `crew_mod()`, `use_crew_ability`, `injure_crew`). A new ability needs a case in `Crew._apply_active` (timed modifiers) or `vehicle.use_crew_ability` (instant effects), or `mission._on_crew_ability` if it reaches past the rig. Crew abilities fire from the HUD crew wheel (`hud.open_crew_wheel`, `pick_crew`), which slows the game while open; utilities keep their own buttons.

- Research: a level belongs to the schematic (`Profile.levels`). `Parts.at_level()` is the only per-level math; `Loadout.build(loadout, levels)` applies it, so game code builds the player's rig with `profile.build_stats()` and shows parts with `profile.part(id)`. Numbers (growth, max levels, costs, daily cap, the two Research upgrades) live in `tuning.gd` and were agreed with the owner; don't change them without asking. `scripts/research.gd` is the station screen.

- Expeditions and the Inn and Saloon upgrade tracks: rules in `profile.gd` (Expeditions section; `_advance_expeditions()` runs from `finish_day()`), numbers in `tuning.gd` (agreed with the owner; don't change them without asking), screens in `inn.gd` and `saloon.gd`. Station upgrade panels for the Inn and Saloon use `upgrade_panel.gd`. Tests force rolls with `Profile.roll_override`.

- Defense layers (§14): every rig has a recharging shield, armor on four facings (`Vehicle.FRONT/LEFT/RIGHT/REAR`) and HP; zero HP wrecks it. Damage goes through `take_damage(amount, from_direction, splash)` (callers pass where the hit came from), repairs through `repair_armor()`. `armor` / `armor_max` remain as computed totals (setting `armor_max` huge makes a rig unkillable in tests). The player's rig has three armor slots (`armor_front`, `armor_sides`, `armor_rear`); `front_only` plates fit the Front only; old saves and old-style loadouts with one `armor` plate get it on all three. Enemy layers live in their stat sheets (`hp`, `front`, `side`, `rear`, optional `shield` from `shield_skulls`).

- Statuses (§14): `status_bars.gd` holds the six bars (shock fire acid toxic slime goop -> STUNNED, BURNING, CORRODED, TOXIC, SLICK, GOOPED) for every rig (`vehicle.status`) and zombie (`zombie.status`). Typed damage passes a `dtype` through `take_hit` / `take_damage` and builds its status; `add_buildup` / `fill_status` for fixed amounts. Rig resistances: enemy sheets give `resist`; the player's come from `Loadout.resistances()` (base 30, plus each plate's profile step, plus chassis/accessory `resist_bonus`; cap 95). Barrels are `barrel.gd`, placed per job at `Arena.BARREL_SPOTS`; fire ground lives in `ground_hazards.gd`.

- Pause menu and Database: `game_menu.gd` (one panel: pause, settings, Database; `in_job` decides RESUME / RESTART JOB). Settings live in their own file (`profile.settings`, `T.QUALITY` presets; the mission applies `fx.density`, `splats.density`, `camera.shake_mult`). A job quit or closed mid-fight resumes at relaunch (`profile.resume_job()`, the garage switches straight to the mission). The optional tutorial: `profile.tutorial_active` makes the next mission the Training Run (`mission.tutorial`, `_tutorial_tick`, loaner `T.TUTORIAL_LOADOUT`); afterwards `profile.begin_tour()` / `end_tour()` run `garage_tour.gd` on a snapshot (`save_data()` / `apply_data()`). Keywords: `vehicle.keyword_pop(kw)` asks for a symbol popup (throttled per rig); `keyword_fx.gd` draws them; DRIFT is `vehicle.end_drift()` / `is_drifting()`, OVERLOAD `_gun_overloaded(i)` / `is_overloaded_gun()`. The Database's contents are `codex.gd`; `profile.discover(category, id)` marks what the player has met; call it where something new is met.

- Controller: `pad.gd` (autoload `Pad`). A pad press sets `Pad.active` (a touch clears it). Buttons go to the topmost visible node in group `pad_modal` (Circle calls its `pad_close` meta Callable), then to the current scene's (or newest root child's) `pad_button(button) -> bool`. Pad turns `focus_mode` on only for visible, enabled buttons (inside the open modal, if any) and draws the focus ring. A scene can turn menu focus off with `pad_wants_focus()` (the mission does while you drive). The mission reads `Pad.stick(left)` and `Pad.r2()` in `_pad_input()`; tests set `Pad.override`. Wording that says "tap" goes through `PadScript.hint(touch, pad)` (preload `pad.gd`) and screens listen to `Pad.mode_changed` to swap it; HUD buttons show a pad badge (`pad_glyph.gd`). Fight buttons are rebindable (Settings > CONTROLLER BUTTONS in `game_menu.gd`): code asks `Pad.binding(action)`, `action_for(code)`, `button_name(action)`, `badge(action)` and `fire_held()` instead of naming buttons; the map lives in `Profile.settings` (`pad_map`, `pad_swap`, saved in the settings file); L2/R2 are codes `Pad.TRIGGER_BASE + axis`. Menus keep D-pad, Cross, Circle and L1/R1. The phone's back button in the garage goes through `garage.go_back()` (menu, top `pad_modal`, part sheet, station, then MENU), the same order Circle uses. The right stick scrolls a panel's text lists and turns the garage rig; sliders take pad focus too. A new overlay panel joins `pad_modal`; its clickable things must be `BaseButton`s so the pad can reach them.

- PC: `Profile.is_desktop()` (not mobile/web). Settings has DISPLAY (windowed/fullscreen, `settings.fullscreen`, applied in `apply_settings()`); F11 or Alt+Enter flips it (`pad.gd`). Esc is the back button: `garage.go_back()`, `mission.go_back()`, and `game_menu` handles Esc itself while the fight is paused. Mouse and keyboard: `Pad.kbm` is the third input scheme (a key, click or mouse move on a PC sets it; a pad press or a touch clears it; `mode_changed` fires for all three). On a PC `Input.emulate_touch_from_mouse` is off, so the mouse never grabs the touch sticks. The fight reads it in `mission._kbm_input()` (WASD/arrows via `Pad.kbm_drive()`, the turret follows the mouse, left click fires, the Mortar lands at the cursor) and `_kbm_event()` (right click LOCK, Q/E/F utilities, Tab and 1-4 the crew wheel); tests set `kbm_mouse_override` / `kbm_fire_override`. `PadScript.hint(touch, pad, mouse)` gives mouse wording (default: tap -> click); `Pad.KBM_BADGES` label the HUD buttons.

- `scripts/profile.gd` (autoload `Profile`) is the save game: scrap, schematics, storage, the rig, presets (with `preset_names`, `rename_preset()`), upgrades. Every change saves to `user://` (written to a .tmp and swapped in, the previous save kept as .bak; an unreadable save loads the .bak or starts fresh with a notice and is kept as .broken; `sanitize_save()` drops fields of the wrong type, so add a new saved field to `_SAVE_TYPES`). Economy rules agreed with the owner are listed at the top of that file; don't change them without asking.

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
- Enemy rigs extend `vehicle.gd` and only decide stick inputs (`drive_input`, `fire_trigger`, and `aim_input` for turrets), the way `enemy_rig.gd` (Outrider), `bulwark_rig.gd` (Bulwark), `gunner_rig.gd` (Gunner Rig), `scrapper_rig.gd` (Scrapper: unarmed §14 hazard layer, built on the Gunner Rig's turret aiming; `scrapper_gunner_rig.gd` is its harder armed variant) `convoy_rig.gd` (Convoy Lead, built on the Bulwark, towing `convoy_trailer.gd`) and `patcher_rig.gd` (Patcher: unarmed support; hooks an ally on a cable and repairs it, revives wrecks through `vehicle.revive()`; the mission pays a revived rig's loot once per job) do. The trailer is a top-level child of the cab with its own armor and turret: it isn't one of the mission's rigs (one rig toward the cap), and `lock_candidates()` adds it by hand. Rigs are built up front, so don't roll dice in `_init` (it shifts every seeded spawn in the job); pick random sides in `_enter_tree`. They share the player's driving model, so builds feel the same on both sides. Their flat stat sheets live in `tuning.gd` (`OUTRIDER`, `BULWARK`, `GUNNER`, `SCRAPPER`, `SCRAPPER_GUNNER`, `CONVOY`, `CONVOY_TRAILER`, `PATCHER`). Enemy mines use a second `mine_pool.gd` with `enemy = true`; oil, spike strips and fire ground live in `ground_hazards.gd` with slime and bile, each tagged with the team that laid it so it never catches its own side (§14: the player's hazards never hurt the player; barrels and slime are neutral and catch everyone). Weapons may fire bursts (`burst`, `burst_rate`; `fire_rate` is then bursts per second). Weapons with `mag` > 0 fire from a magazine and `reload` when it's dry (`vehicle.has_round`, `ammo_left`); heat guns (`heat_time`, `lockout`, `cool`) overheat and lock until the bar drains (`is_overheated`, `heat_of`). `vehicle.weapon_gauges()` feeds the rings on the fire stick (`thumb_stick.set_gauges`). `Loadout.total_dps` is sustained DPS (counts reloads and lockouts). Special weapons carry a `kind`: `"mortar"` lobs shells through `shell_pool.gd` (one pooled drawer; also draws the player's landing circle), `"harpoon"` fires a piercing spear and holds a rig on a `tether.gd` cable. Rig spawns that would pass the 3-rig cap return null and their event retries (`spawn_gunner`). Armor that blunts hits implements `deflects(at)` so bullets throw grey sparks.
- Zombie variants (Shambler, Brute, Tank, Boomer, Slimer) are one pooled `zombie.gd` with a `kind`; stats in `T.ZOMBIE_KINDS`, the horde mix by skulls in `T.ZOMBIE_MIX`. `zombie_director.gd` picks kinds per pack (`set_mix`), lays Slimer trails, pops Boomers and frenzies zombies. Slime and bile live in one pooled drawer, `ground_hazards.gd`; rigs on slime lose grip through `vehicle.set_on_slime()`. Agreed numbers; don't change them without asking.
- Bullets carry a team (`bullet_pool.gd`). Each team's ray mask decides what it can hit, so nobody shoots their own side.
- New mission-level enemies get a `spawn_*` function in `mission.gd` that tests can call directly (`auto_spawn_specials = false`).
- Audio: `music_manager.gd` (autoload `MusicManager`) owns music and one-shot effects: `play_garage()`, `start_combat(courier)`, `set_intensity(0-2)` (three synced combat layers crossfaded by tweens), `play_wreck()`, `end_combat()`, `play_sfx(id)`. Buses `Music` and `Effects` are in `default_bus_layout.tres`; `Profile.apply_settings()` sets their volume. Thresholds and boosts (elite alive, low armor, Survive's last stretch), and the pause duck, live in `tuning.gd` (`MUSIC_*`); `mission.music_boosts()` adds the boosts. Enemy rig wrecks and a slipped Courier par tier play effects. Combat SFX hook in the rigs themselves (so spawned rigs get them too): `bulwark_rig.gd` calls `start_windup`/`stop_windup` (roar pitch follows `windup_progress()`, `T.SFX_WINDUP_PITCH`) and plays `ram_impact` on `rammed_player`; `torcher_rig.rupture()` plays `torcher_rupture`; `sludger_rig._lob` plays `acid_fire`; `shell_pool._burst` plays `acid_impact` for acid shells. `MusicManager.sfx_counts` counts plays for tests. Audio files are generated by `tools/audio/synth.py`; log every file in `docs/AUDIO_CREDITS.md`. Headless runs skip playback.
- Maps: `layouts.gd` holds the six layouts (buildings, props, roads, stops, barrel spots, spawn points, safe barricade spots, which jobs use them) and the seeded variation (`Layouts.build(id, seed)`). `arena.gd` and `nav_grid.gd` read the arena's instance data (`arena.player_start`, `arena.checkpoints`, `arena.barrel_spots`...), never constants. Board jobs carry a `layout`; a new layout must pass the layouts test (`layouts_test.gd`, listed below) (every spot open and reachable in every variation).
- Mission types and their tables live in `tuning.gd` (`MISSIONS`, six entries per stat, one per skull 1-6): Clear, Survive, Hunt, Courier, Retrieve and Escort. `missions.gd` builds the daily board inside the district's skull band; `mission.gd` runs any type. Escort's truck is `friendly_truck.gd` (armor and HP scale by skull through `mission.truck_sheet()`; player team: your bullets pass it, enemy bullets and zombies don't; `zombies.alt_target`). A job can fail without a wreck (`_fail`). The driver's radio call pauses the tree; `hud.show_choice` runs while paused. Tests set `mission_override` to run a specific mission and `apply_rig()` to swap the player's build mid-run.
- Schematic drop pools by source are `Parts.DROP_POOLS`. Drops never repeat a schematic the player owns.

## Verify before pushing

```sh
godot --headless --path . --import                  # must print no "SCRIPT ERROR"
godot --headless --fixed-fps 60 --path . -s res://tests/smoke_test.gd   # must end "SMOKE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/garage_test.gd  # must end "GARAGE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/layout_test.gd   # must end "LAYOUT TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/missions_test.gd # must end "MISSIONS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/crew_test.gd     # must end "CREW TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/research_test.gd # must end "RESEARCH TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/expedition_test.gd # must end "EXPEDITION TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/zombie_test.gd     # must end "ZOMBIE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/zombie_sample_test.gd # must end "ZOMBIE SAMPLE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/gunner_test.gd     # must end "GUNNER TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/scrapper_test.gd   # must end "SCRAPPER TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/convoy_test.gd     # must end "CONVOY TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/jobs_test.gd       # must end "JOBS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/defense_test.gd    # must end "DEFENSE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/status_test.gd     # must end "STATUS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/patcher_test.gd    # must end "PATCHER TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/content_test.gd    # must end "CONTENT TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/mods_test.gd       # must end "MODS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/perks_test.gd      # must end "PERKS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/perks2_test.gd     # must end "PERKS2 TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/weapons_test.gd    # must end "WEAPONS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/rehire_test.gd     # must end "REHIRE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/menu_test.gd       # must end "MENU TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/tutorial_test.gd   # must end "TUTORIAL TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/layouts_test.gd    # must end "LAYOUTS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/art_sheet_test.gd   # must end "art_sheet_test: PASS"
godot --headless --fixed-fps 60 --path . -s res://tests/art_content_test.gd # must end "art_content_test: PASS"
godot --headless --fixed-fps 60 --path . -s res://tests/audio_test.gd      # must end "AUDIO TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/keywords_test.gd   # must end "KEYWORDS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/pad_test.gd        # must end "PAD TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/save_test.gd       # must end "SAVE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/pc_test.gd         # must end "PC TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/missing_part_art_test.gd # must end "MISSING PART ART TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/rarity_test.gd     # must end "RARITY TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/map_style_test.gd  # must end "MAP STYLE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/garage_room_test.gd # must end "GARAGE ROOM TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/preview_scale_test.gd # must end "PREVIEW SCALE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/garage_layout_test.gd # must end "GARAGE LAYOUT TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/fx_sample_test.gd # must end "FX SAMPLE TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/tracer_styles_test.gd # must end "TRACER STYLES TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/transitions_test.gd # must end "TRANSITIONS TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/night_test.gd      # must end "NIGHT TEST PASSED"
godot --headless --fixed-fps 60 --path . -s res://tests/kill_loops_test.gd   # must end "KILL LOOPS TEST PASSED" (one blast hits every zombie in range)
godot --headless --fixed-fps 60 --path . -s res://tests/wreck_and_swarm_test.gd   # must end "WRECK AND SWARM TEST PASSED" (shove through a pack, wreck freezes the fight, free hires match their card)
godot --headless --fixed-fps 60 --path . -s res://tests/abandon_job_test.gd   # must end "ABANDON JOB TEST PASSED" (pause menu gives a job up: day passes, no pay, rig and crew kept)
godot --headless --fixed-fps 60 --path . -s res://tests/crew_seating_test.gd   # must end "CREW SEATING TEST PASSED" (hires seated after a rebuild, no Driver = no DEPLOY)
godot --headless --fixed-fps 60 --path . -s res://tests/escort_truck_test.gd # must end "ESCORT TRUCK TEST PASSED" (truck HP line, low-HP warning, GOOPED pulls the horde)
godot --headless --fixed-fps 60 --path . -s res://tests/saloon_match_test.gd # must end "SALOON MATCH TEST PASSED" (every Saloon card is exactly who you hire)
godot --headless --fixed-fps 60 --path . -s res://tests/tutorial_readability_test.gd # must end "TUTORIAL READABILITY TEST PASSED" (Training Run brightens the arena and rings zombies)
godot --headless --fixed-fps 60 --path . -s res://tests/endless_tuning_test.gd # must end "ENDLESS TUNING TEST PASSED"
```

- Tests must call `Profile.new_game()` with `persist = false` first, so they never touch a real save.

- Godot's import exits 0 even with script errors, so read the output.
- Extend the smoke test (`smoke_test.gd`) when you add a core mechanic (new enemy, lock-on, part swap). It drives the game by setting `hud.left_stick.output` and `hud.right_stick.output` directly.
- For visual checks without a GPU: `xvfb-run godot --rendering-driver opengl3 ...` with a script that saves `root.get_texture().get_image()` to PNG.

## Build and delivery

Pushing to `main` runs `.github/workflows/android.yml`. It imports the project, runs the smoke test, exports a debug APK, and replaces the `latest-build` release. The owner installs from:
https://github.com/Asmogius/helriders-game/releases/download/latest-build/helriders.apk

The same run also exports a Windows build (preset "Windows" in `export_presets.cfg`, one self-contained .exe) and attaches `helriders-windows.zip` to the release; that step is `continue-on-error`, so a Windows failure never blocks the APK. Each build is stamped version 0.1.<run number>. A signed release APK (`helriders-release.apk`) is also built once the repository secrets `ANDROID_RELEASE_KEYSTORE_BASE64`, `ANDROID_RELEASE_KEY_ALIAS` and `ANDROID_RELEASE_KEY_PASSWORD` exist; never commit a release key.

If the workflow fails, the owner gets no build. Check the run and fix it before moving on.

## Cursor Cloud

- `godot` on `PATH` is Godot 4.7.2 (`/usr/local/bin/godot`). Verify with the headless commands above.
- Import may print `Unable to open Android 'build-tools' directory`. The Android SDK is not installed here. That line is a warning: import still succeeds, and the headless tests do not need the SDK. APK and Windows export stay on GitHub Actions.
- Rendered checks use the installed `xvfb`: `xvfb-run -a godot --rendering-driver opengl3 --path . ...`. There is no sound card; Godot falls back to the dummy audio driver.
- `python3` has numpy and Pillow, and `ffmpeg` encodes Vorbis, for `tools/art` and `tools/audio/synth.py`.
