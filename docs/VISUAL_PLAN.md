# Helriders: Visual Upgrade Plan

Written 2026-11-04 from a full look at the game, for the owner and for any agent (Claude, Grok, others) that picks up a task. Each task says what to build, where it goes in the code, and when it counts as done. Gameplay numbers don't change in any of this; it is all looks.

**The goal:** Helriders should look like the game in DESIGN §11: pixel-voxel, gritty urban, muted concrete with cyan and orange lights, and chunky vehicles that read at a glance on a phone. Today the rigs mostly look like that (voxel sheets). Everything around them doesn't yet:
- The garage is text boxes on black.
- Zombies are a few rectangles.
- Effects are square dots.
- Maps are flat grey with lighter squares for buildings.
- Rarity colour shows on some cards but not everywhere.

## For the bot team: how to split this up

This plan goes to a team of agents with specialists. The work is cut into **packages**, each owned by one specialist. A package owns certain files, so parallel PRs don't collide. Read the whole plan once, then work only in your package.

### Packages and owners

| Package | Specialist | Tasks | Owns (only this package edits these) | Needs first |
|---|---|---|---|---|
| **P0 Foundations** | Tools / pipeline lead | V0.1, V1.1, the capture tool, the atlas loader, `rarity_frame.gd` | `scripts/ui_theme.gd` (rarity helpers), `scripts/rarity_frame.gd` (new), `tools/art/capture_all.gd` (new), `scripts/art_atlas.gd` (new) | nothing: **lands first** |
| **P1 Rarity** | UI specialist | V1.2–V1.4 | rarity use in `garage.gd` cards and tags, `research.gd`, `saloon.gd`, `inn.gd`, `crew_card.gd`, `comms.gd` odds line, `game_menu.gd` Database, `hud.gd` banners, `pickup.gd` beam, `tests/rarity_test.gd` | P0 |
| **P2 Effects** | VFX specialist | V4.1–V4.8 | `scripts/fx.gd`, `scripts/fx_glow.gd` (new), `scripts/splats.gd`, effect drawing in `bullet_pool.gd` / `shell_pool.gd`, `tools/art/fx_sheet.py`, `art/fx/` | P0 (atlas loader) |
| **P3 Zombies** | Character artist | V3.1–V3.5 | `tools/art/zombies.py`, `art/zombies/`, zombie drawing in `zombie_director.gd` / `zombie.gd` (`_draw` only, never stats or AI) | P0; uses P2's splat and decal API |
| **P4 Map looks** | Environment artist | V5.1–V5.6, V7 (props, barrels, hazards) | `scripts/arena.gd` drawing, `tools/art/tiles.py`, `tools/art/buildings.py`, `tools/art/props.py`, `art/map/` | P0 |
| **P5 Map layouts** | Level designer | V5.7 (V5.8 only after the owner says yes) | `scripts/layouts.gd` (layout data only), `tests/layouts_test.gd` additions | nothing; coordinate prop kinds with P4 |
| **P6 Garage** | Scene artist plus UI specialist | V2.1–V2.6 | `tools/art/garage_scenes.py`, `tools/art/crew_figures.py`, `art/garage/`, `scripts/garage_ambient.gd` (new), the garage scene layout (backdrops and the pan) | P0, P1 (cards inside scenes use rarity frames) |
| **P7 Interface** | UI specialist | V6.1–V6.5 | `scripts/ui_theme.gd` styles (not the rarity helpers), `hud.gd` look, fonts and icons in `art/ui/` | P0 |

**Shared files** (`garage.gd`, `hud.gd`, `mission.gd`, `tuning.gd`) are touched by several packages:
- keep changes there small and in your own clearly marked section;
- add new code in your own new file and call it from one line in the shared file;
- **colours go in `tuning.gd` only through P0**: ask the P0 owner to add them.

### Rules for every PR

1. **One task (or one tightly related group) per PR**, branched from the latest `main`, titled with its task id, e.g. "V4.3 Weapon muzzle flashes and tracers".
2. **Before you push:** run the full test list in `AGENTS.md` (all suites must pass) and `godot --headless --path . --import` (no SCRIPT ERROR).
3. **The PR body must include:**
   - before/after screenshots from `tools/art/capture_*.gd`;
   - the files touched;
   - a performance note (fight frame time or draw calls on the High preset, where it applies).
4. **No gameplay changes.** That means no stats, timings, collision shapes, AI or numbers in `tuning.gd` beyond colours and art settings. V0.2 (zoom) and V5.8 (breakable cover) wait for the owner's yes.
5. **Fallback stays.** If an art file is missing, the code-drawn look must still work, and tests must not depend on art files existing.
6. **Generated art only.** Generators live in `tools/art/`, write to `art/<area>/` and are committed with their outputs and `.import` files. Log any font or third-party asset and its licence in `docs/ART_CREDITS.md` (create it).
7. **Style gate.** The first PR of P2, P3, P4 and P6 is a **style sample** (see Order of work). Don't roll a look out to everything until the owner approves its sample.
8. **Rebase, don't fight.** If `main` moved, rebase onto it. If your PR conflicts with another package's file, stop and leave a note for the file's owner rather than editing their section.
9. **When a task is done**, tick it in this file (`- [x]`) in the same PR, so the plan shows progress.

### Defaults until the owner answers the open questions

So nobody is blocked, assume these; the owner can overrule any of them:
1. **Style:** pixel-voxel everywhere, the garage included.
2. **Garage navigation:** one panning panorama (V2.3).
3. **Districts:** as written in V5.5; landmarks as listed in V5.7.
4. **Breakable cover:** not built until the owner says yes.
5. **Fonts:** a condensed, readable display font with a light stencil feel; numbers in a clean font. Readability on a phone beats grit.

### Definition of done for the whole plan

- Every task box is ticked.
- `tools/art/capture_all.gd` produces a screenshot set of every screen and fight situation, and the owner has signed it off.
- All suites pass, and the Android build and Windows build both ship.
- A 5-minute fight with 3 rigs, 30 zombies and heavy fire holds 60 fps on the High preset and 30+ on Low on the target phone class.

## Where things stand (what was seen)

| Area | Today | Main gap |
|---|---|---|
| Rigs and weapons | Voxel sprite sheets for the player chassis, every enemy rig and most weapons (`art/sprites`, `tools/art`) | Truck, Hunter, barrels, pickups still code-drawn |
| Garage | One dark screen; the rig on a turntable; stations are panels of cards and text | No sense of place; the rig preview even draws on top of the station screens (bug) |
| Zombies | `zombie.gd` `_draw()`: 5–6 rectangles per kind, flat colours, no animation | No silhouettes, no walk, no death |
| Effects | `fx.gd`: one square per particle; `splats.gd` blood squares | No glow, no smoke, no flash, no shockwave |
| Maps | `arena.gd`: flat concrete, dark road strips, building rectangles with a lighter roof, a few prop boxes; 6 layouts | Reads as grey; no height, no texture, no landmarks, no district identity |
| Rarity | Part cards, crew cards and loot crates have rarity colour | Slot tags, Research list, results card, Database, expedition finds, toasts and banners don't |

## Rules for every visual task

1. **Same engine rules.** Use the Compatibility renderer, code-first scenes and static typing. Pool everything, and keep many small things in one node with one `_draw()`. Nothing in this plan may add `new()` or `queue_free()` to the combat loop.
2. **Art is generated by tools in the repo**, like the voxel rigs (`tools/art/*.py`) and the sounds (`tools/audio/synth.py`).
   - The owner has no computer, so nothing may need an editor or hand painting.
   - New generators go in `tools/art/` and write PNG + JSON into `art/`. Commit both, plus the `.import` files.
3. **Palette.** Use the `tuning.gd` colours (3 shades each, `tools/art/palette.py`). New colours go into `tuning.gd` first. Lights (cyan, orange, enemy red, elite gold, rarity colours) are the only saturated things on screen.
4. **Fallback.** If an art file is missing, the old code-drawn look stays. Tests run without art changes.
5. **Budget** (2020-era 3–4 GB phones, `T.QUALITY` presets):
   - **Fights:** at most about 200 draw calls and 60 fps on High. Low preset: half the particles, no ambient layers.
   - **Garage:** 60 fps with every animation on.
   - **Textures:** atlases, lossless import, no mipmaps for pixel art. Keep the APK under 80 MB.
6. **Proof.** Every visual task ends with before/after screenshots (xvfb capture scripts in `tools/art/`), sent to the owner. The task adds a capture to `tools/art/capture_*.gd` and keeps all test suites passing. The owner approves the look of each first sample before it's rolled out to everything (see Order of work).
7. **Readability first.** On a phone, the player's rig, enemies, pickups and hazards must stand out from the ground at a glance. Decoration stays darker and lower-contrast than anything you can interact with.

---

## V0. Quick fixes (do first, small)

- [x] **V0.1 Rig over station screens (bug).** The garage rig preview's sprites draw at z 1–3, so they show over the Research, Saloon, Inn and Comms screens. Fix: hide `_rig_holder` while a station tab is open (or z-index the station screens above it). Done when a screenshot of each station shows no rig.
- [ ] **V0.2 Fight zoom check.** At `base_zoom 1.3` a fight shows mostly bare ground. Try 1.1–1.15 on a phone-size capture and pick with the owner. Changing the zoom is a camera setting, not a balance number, but ask before changing it.

## V1. Rarity colours everywhere (explicitly asked)

One rule: **anything that has a rarity shows it in its colour, the same way everywhere.** That covers parts and schematics, crew, loot, perks (by tier), and expedition and Saloon offers.

- [x] **V1.1 One source of truth.** Move the rarity colours into `tuning.gd` as `RARITY_COLORS` with all six: Common, Uncommon, Rare, Epic, Legendary, Mythic. `Parts.RARITY_COLORS` and `Crew.color_of` read it.
  - Add `UI.rarity_color(r)`, `UI.rarity_frame(control, r)` (border plus top strip) and `UI.rarity_text(name, r)`: a BBCode colour tag for RichTextLabels.
  - Done when no other file defines a rarity colour.
- [x] **V1.2 Rarity tiers look different, not just tinted.**
  - Common: plain grey frame.
  - Uncommon: green frame.
  - Rare: blue frame plus a soft inner glow.
  - Epic: purple frame plus a slow shimmer sweep.
  - Legendary: gold frame, shimmer and a pulsing corner glint.
  - Mythic: animated colour-cycling frame and sparks.

  Every frame also shows a small rarity pip row (1–6 pips), so the tier reads without colour (colour-blind players). One shared drawer, `rarity_frame.gd`, draws all of this.
- [ ] **V1.3 Apply it to every screen.**
  - **Garage:** slot tags get a frame by the fitted part's rarity; part cards and the stat sheet title already have it.
  - **Research:** list rows get a frame, and the detail panel title takes the colour.
  - **Saloon and Inn:** crew cards already have the strip; upgrade them to V1.2 frames. The rehire card, the perk picker (perk tier colours) and expedition offers and finds get frames too.
  - **Comms:** the schematic odds line shows the best rarity possible in its colour.
  - **Results card:** each "New schematic" line is in its rarity colour, and an Epic or better find gets a short reveal (card flips in with a glint).
  - **Fight:**
    - crates already glow by rarity; add a light beam whose height grows with rarity, so a Legendary drop is visible across the map;
    - the "SCHEMATIC" pickup banner takes the rarity colour.
  - **Database:** entry names in rarity colour (parts and crew).
  - **Toasts and banners** that name a part or crew member colour the name.
- [x] **V1.4 Test.** Add `tests/rarity_test.gd`, checking:
  - every rarity has a colour;
  - every card type (part, crew, perk, offer, crate) asks `UI.rarity_*` for its colour, not a hard-coded one;
  - a capture shows all six tiers side by side for the owner.

## V2. A living garage (explicitly asked)

Make the home base a place with distinct areas you move between: lit, animated and populated by your crew. Tabs stay (they work and tests use them), but each tab opens a **scene**, not a panel.

- [ ] **V2.1 Art method: voxel dioramas.** Build each area as a voxel scene in `tools/art/garage_scenes.py`, using the existing voxel renderer at the same 30° tilt. Render it once to a background PNG at 1280x720 (plus a wider version for widescreen).
  - Moving things (lights, steam, crew, screens, sparks) go on separate overlay sheets and code-drawn layers.
  - This keeps one consistent style with the rigs and needs no hand painting.
- [ ] **V2.2 The areas.** Each area keeps its current controls, re-skinned to sit inside the scene. The data panels become physical things in the room:
  - **Workshop bay (GARAGE):**
    - Look: the rig on a hydraulic lift in the middle; tool walls, tyre stacks, a welding station; work lights in cyan and orange; a roll-up door with the street outside.
    - Life: when you fit a part, a spark shower and an arm swing at that slot; the lift turns the rig.
    - Panel: the slot tags become tags hanging from the lift.
  - **Research bench:**
    - Look: a drafting table with blueprints, a CRT monitor and pinned schematics.
    - Life: the selected part's blueprint lies on the table; researching a level stamps it and the monitor flickers.
    - Panel: the part list becomes a filing drawer of blueprint tabs, in rarity colours (V1).
  - **Saloon:**
    - Look: a bar counter, a jukebox glow, stools.
    - Life: today's hires stand at the bar as small voxel figures in their class colours; picking one walks them forward; the free Driver and Gunner sit at a corner table.
  - **Inn:**
    - Look: bunks along a wall and an expedition map board.
    - Life:
      - resting crew lie in bunks with bandages, and a day counter hangs over each bunk;
      - seated crew stand by the door in their gear;
      - crew on expedition show as pins moving on the map board.
  - **Comms:**
    - Look: a radio desk with a crackling speaker and a district map on the wall.
    - Panel: today's jobs are pinned cards on a cork board; skulls are drawn on the cards; districts light up on the map as they unlock.
    - Life: taking a job tears the card off the board.
- [ ] **V2.3 Moving between areas.** The tabs pan the camera across one wide yard panorama (about 0.4 s ease), so the areas feel connected (workshop, bench, saloon, inn, comms left to right). L1/R1, the tabs and the phone's back button keep working.
- [ ] **V2.4 Ambient life (cheap, always on):**
  - flickering fluorescent tubes; dust motes in light shafts; steam from a pipe;
  - rain or ash outside the roll-up door (by district);
  - a radio murmur light on Comms;
  - a yard dog asleep that wakes when you DEPLOY;
  - time of day: lighting tint shifts every day (dawn / day / dusk / night cycle by day number);
  - the wreck penalty day shows scorch marks and an empty lift.

  All of it is one `garage_ambient.gd` drawer. Low quality turns it off.
- [ ] **V2.5 Crew figures.** The crew in the Saloon, Inn and Workshop are small voxel figures, about 16x24 px, from one figure model. Class shows through palette and props: wrench (Mechanic), med bag (Medic), headset (Spotter) and so on. Rarity shows as a coloured armband. Each figure has 2-frame idle animations, generated in `tools/art/crew_figures.py`. They are also usable in the wreck sequence (crew dragged out by name).
- [ ] **V2.6 Done when:** each area has a capture approved by the owner; every existing test still passes (controls unchanged); the garage holds 60 fps with all ambient layers on a High preset capture.

## V3. Better zombies (explicitly asked)

- [ ] **V3.1 Voxel zombie sheets.** Add `tools/art/zombies.py`: one humanoid voxel model (about 14x10x18 voxels) with parts (head, torso, arms, legs). Render it at **16 headings** with a **4-frame shamble cycle** and a **2-frame lunge/attack**, plus a hit-flash palette. Sheets go into one atlas.
- [ ] **V3.2 The five kinds look like their role:**
  - **Shambler:** ragged clothes in 6 palette variants (random per spawn, so a horde isn't clones); a hunched walk.
  - **Brute:** wide, with scrap plates bolted on (the plates throw grey sparks, as already happens when bullets hit); a heavier walk.
  - **Tank:** huge, about 2x; a roar pose for the wind-up (replaces the red arc), a charge pose and a stumble pose.
  - **Boomer:** bloated, with glowing bile pustules that pulse faster as it nears you; a pop animation.
  - **Slimer:** dripping, translucent green highlights, and a trail that matches the slime decal.
- [ ] **V3.3 Death.** Each kind breaks into 3–5 chunk pieces (the rig wreck chunk pipeline, smaller), flung by the hit direction, plus a blood splat decal that stays (`splats.gd`). A rig running one over flattens it with a different splat.
- [ ] **V3.4 Drawing.** Stay in the single drawer: `zombie_director.gd` draws all zombies from the atlas with `draw_texture_rect_region`, or a MultiMeshInstance2D if profiling says so. No per-zombie nodes for art. Status visuals use the status colours from `tuning.gd`:
  - BURNING: small flames;
  - SLICK: drips;
  - GOOPED: blob;
  - STUNNED: sparks.
- [ ] **V3.5 Done when:** a capture shows all five kinds walking; 30 zombies hold 60 fps on High; the zombie tests still pass (hit circles unchanged).

## V4. Better visual effects (explicitly asked)

- [ ] **V4.1 Particle atlas.** `tools/art/fx_sheet.py` generates one small atlas with:
  - soft smoke puffs (4 sizes), spark streaks, embers, debris chips (rust, steel);
  - blood splats (6); a scorch decal; a shockwave ring; a muzzle-flash star (3 frames); an electric arc segment;
  - acid and slime and goop blobs; dust kicks.

  `fx.gd` keeps its packed arrays and adds a frame index and rotation per particle, drawing regions from the atlas instead of squares.
- [ ] **V4.2 Additive glow layer.** Add a second fx node with `CanvasItemMaterial.BLEND_MODE_ADD` (works in Compatibility) for fire, muzzle flashes, sparks, shock and explosions' cores. That gives glow without lights.
- [ ] **V4.3 Weapons get signature looks:**
  - muzzle flashes sized by weapon;
  - tracers with a short glowing tail (`bullet_pool.gd` draws a streak, not a dot);
  - Scattergun: a cone puff;
  - Heavy MG: brass casings ejected (decals that fade);
  - Flame Sprayer: a real flame stream with embers;
  - Arc Projector: jagged arcs that jump between chain targets;
  - Acid Lobber and Mortar: a shell trail and a splash of the right colour;
  - Harpoon: a cable that sways.
- [ ] **V4.4 Explosions:** in order, a flash frame, a fireball (additive), an expanding shockwave ring, flung debris, then a rising smoke column that drifts. A scorch decal stays. Barrels each get their own colour (fire / acid / toxic / shock / goop).
- [ ] **V4.5 Impacts and feedback:**
  - bullet hits show sparks on armor, dust on walls, blood on zombies;
  - shield hits flash a hex shimmer on the shield bubble (the rig shield colour);
  - rams throw sparks and debris;
  - a hit-stop of 2–3 frames on rig wrecks and Tank charges (a short pause; not a balance change).
- [ ] **V4.6 Rig damage states:** smoke from the engine under 50% HP, fire under 25%, sparks when a facing breaks (armor plate gone on that side). This applies to enemy rigs too: you can see who is hurt.
- [ ] **V4.7 Ambient fight layer:** drifting ash or embers by district, heat shimmer near fire ground, flickering streetlights. Low quality turns it off.
- [ ] **V4.8 Done when:** captures show each weapon's look, an explosion sequence and the damage states; frame time stays inside budget with 3 rigs, 30 zombies and heavy fire on the High preset.

## V5. Better maps: layout and looks (explicitly asked)

**Looks:**
- [ ] **V5.1 Ground from tiles, baked once.** Add `tools/art/tiles.py`: asphalt, cracked concrete, dirt, broken pavement, grass through cracks, road markings, manholes, puddles. Each tile is 64 px with 4 variants. At job start `arena.gd` paints the ground from tiles into one Image, then one texture, so it costs a single draw. Roads get lane lines, crosswalks and potholes.
- [ ] **V5.2 Buildings with height.** Render buildings as voxel blocks at the 30° tilt (`tools/art/buildings.py`): rooftops with clutter, and the south walls visible with windows, doors, signs, fire escapes and a few lit windows. Use modular pieces (roof tiles, wall segments, corners) so each building size in `layouts.gd` can be assembled. Buildings then read as solid blocks instead of lighter squares.
- [ ] **V5.3 Props as voxel sprites:**
  - wrecked cars (several models, burnt and rusty);
  - buses, dumpsters, barriers, fences, streetlights (with light pools), burning barrels;
  - bus stops, shipping containers (Rail Yard), parked wrecks (Parking Lots), market stalls (Plaza).

  Same collision shapes as now, since the layout data stays the source of truth.
- [ ] **V5.4 Decals:** oil stains, blood trails, scorch marks, graffiti on walls, rubble piles. These are static, painted into the baked ground or a static decal layer.
- [ ] **V5.5 Districts look different:** one tileset and colour grade per district, each with its own ambient particles:
  - Outer Blocks: suburban, grass, low houses;
  - Midtown Ruins: collapsed towers, rubble, ash;
  - Industrial Spine: factories, pipes, rail, smoke stacks;
  - Core Collapse: craters, fires, red sky glow.

  Jobs already know their district through their skull band; add a `district` field to the board job for the art.
- [ ] **V5.6 Map edges:** a real boundary (barricade walls of cars and containers, a burning wreck line) instead of a flat grey border.

**Layout:**
- [x] **V5.7 More and better layouts.**
  - Go from 6 to 12 layouts: 3 per district, each with at least 1 landmark.
  - Landmarks: a gas station, a collapsed overpass, a mall car park, a rail bridge, a stadium gate, a factory yard and so on.
  - Each layout should have:
    - a clear landmark for orientation;
    - two or three routes between areas;
    - at least one choke point and one open arena space;
    - barrel clusters placed for combos.
  - Keep the seeded variation (mirroring, nudged props, barricades).
  - Every layout must pass `tests/layouts_test.gd` in every variation.
- [ ] **V5.8 Breakable cover.** Fences, barricades and parked cars break when rammed (debris fx, cleared collision, the nav grid cell reopens). This is a small gameplay touch; agree it with the owner first, since it changes routes.
- [ ] **V5.9 Done when:** a capture of every layout in its district style has the owner's OK; the layouts test passes; a fight on each holds the frame budget.

## V6. Interface polish (supports all of the above)

- [x] **V6.1 Fonts.** Pick one display font (condensed, stencil-like) for titles and one clean font for numbers. Both must have open licences; log them like `AUDIO_CREDITS.md`. Swap them in `ui_theme.gd`. *(One interface font for now; a separate numbers font is pending the owner's decision.)*
- [x] **V6.2 Panels and buttons:** riveted steel panels with worn edges (generated 9-slice textures), buttons with pressed and focus states, cyan and orange accent lines. The controller focus ring and the rarity frames sit on top.
  - Layout grid (serves V6.2): panels and buttons share one spacing from `ui_theme.gd`: `MARGIN` 24, `GAP` 12, `GRID` 8, `BAR_H` 72, `MIN_TOUCH` 64, plus `safe_rect()` (display safe area) and `bottom_bar()` (action bar, buttons at least `MIN_TOUCH`). Capture: `layout_grid.png`.
- [ ] **V6.3 Icons:** a small generated icon set for stats (HP, armor, shield, speed, power, weight, DPS), statuses, part categories and crew classes. Use it in the stat sheet, cards and HUD instead of words where space is tight.
- [ ] **V6.4 HUD:**
  - armor and shield bars styled like gauges;
  - status icons;
  - a cleaner LOCK, crew and utility look (keep the controller and keyboard badges);
  - the touch sticks get a subtle textured look (hidden in mouse-and-keyboard mode on a PC).
- [ ] **V6.5 Transitions:** screen fade or wipe between garage and fight, cards slide in, results counters tick up, a level-up flash on crew cards.

## V7. Remaining code-drawn things to bring to voxel art

Bring these to voxel art (`art_id()` / sheet lookup like the rigs): the salvage truck, Hunter, barrels (5 types), mines, spike strips, oil and slime pools (as decals), loot crates (rarity glow from V1), the Courier Frame's missing parts and the remaining weapon sheets.

---

## Order of work (suggested)

1. **V0** quick fixes, then **V1 rarity colours** (high value, low risk, touches only UI).
2. **Style samples for approval** before mass production, one screenshot each:
   - one garage area (Workshop bay);
   - the Shambler and the Tank;
   - one explosion plus the new tracers;
   - one map corner in Outer Blocks style.

   The owner approves or redirects the look.
3. **V4 effects** (most visible in every fight) and **V3 zombies**.
4. **V5 maps:** looks first (tiles, buildings, props) on the existing 6 layouts, then new layouts and districts.
5. **V2 garage areas** (the most art), one area at a time, Workshop first.
6. **V6 and V7** polish alongside, as each area needs it.

Each step is its own PR, with captures and all suites green. Gameplay numbers never change in a visual PR; anything that touches gameplay (V0.2 zoom, V5.8 breakable cover) needs the owner's yes first.

## Open questions for the owner

1. **Style samples:** pixel-voxel everywhere (garage dioramas and zombies included), as above? Or a hand-drawn 2D look for the garage only?
2. **Garage navigation:** one panning panorama, or separate rooms that fade between each other?
3. **Districts:** is the per-district art direction above right? Do you want any specific landmarks?
4. **Breakable cover (V5.8):** wanted?
5. **Fonts:** a gritty stencil look, or keep a clean modern look for readability?
