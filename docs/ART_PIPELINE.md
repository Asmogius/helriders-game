# Art pipeline: pixel-voxel sprites (draft)

Roadmap item "Pixel-voxel art pipeline (voxel models rendered to sprite sheets)".
Draft for review; nothing in the game uses these sprites yet.

## How it works
1. **Models** are voxel grids at **1 voxel = 1 px**, so a hull is about 64x36 voxels,
   the size `vehicle.gd` already uses. They are defined in code (`tools/art/models.py`)
   with `box()`, `wheel()` (round tyre, tread blocks, hub on the outer face) and
   `rivets()`. MagicaVoxel `.vox` files also load (`--vox file.vox`, as one chunk).
   Axes: x = forward (nose), y = right, z = up. Hull and turret are separate models,
   because turrets aim on their own.
2. **Chunks**: each model is a set of named parts (Scrap Frame: wheels, chassis, cab,
   front_plate, rear_plates; Outrider: wheels, chassis, cockpit, guns; turret: mount,
   barrel), all on the same grid. Each chunk gets its own sheet, using the same frame
   size and centre as the composite, for the wreck ("voxel plates explode").
3. **Palette** is fixed (`tools/art/palette.py`): the `scripts/tuning.gd` colours, with
   3 shades each (lit top, mid, dark side). Light colours (cyan, orange, enemy red,
   elite gold) give off their own light and never shade.
4. **Renderer** (`tools/art/voxel_render.py`, Python + numpy + Pillow): straight-on
   (orthographic) view, camera tilted 45 degrees off straight-down, z-buffered, no
   anti-aliasing, 1 px near-black outline all round.
5. **Sheets**: **32 headings** (11.25 degrees each), 8 columns x 4 rows; frame i =
   heading i x 11.25 degrees clockwise from +x. Frames are square (Scrap Frame 90 px,
   Outrider 92, turret 44). The frame centre is the footprint centre at ground level.
6. **Metadata** `<model>.json`: `sheet`, `frame_w/h`, `columns`, `directions`,
   `px_per_voxel`, `tilt_deg`, and `chunks.<name>` = `{sheet, voxels, offsets}`.
   `offsets[i]` is the chunk's pixel centroid relative to the frame centre at heading
   i: spawn the piece there and fling it outward along it.
7. **Godot**: `.png.import` uses lossless compression with no mipmaps.
   `scripts/directional_sprite.gd` (Sprite2D, nearest filter, never rotated) has
   `load_meta(json)`, `heading` -> `frame`, `chunk_texture(name)` and
   `chunk_offset(name)`. `tests/art_sheet_test.gd` checks sheet sizes and frame
   selection across all 32 headings, including jitter and wrap-around.

```sh
pip install numpy pillow
python3 tools/art/voxel_render.py   # all models -> art/sprites/
python3 tools/art/preview.py        # previews -> art/previews/ (Godot ignores this folder)
godot --headless --path . --import
godot --headless --path . -s res://tests/art_sheet_test.gd
```

## Samples
| | |
|---|---|
| Scrap Frame, 32 headings (3x) | ![](../art/previews/scrap_frame_x3.png) |
| Scrap Frame chunks pulled apart (4x) | ![](../art/previews/scrap_frame_chunks_x4.png) |
| Outrider, 32 headings (3x) | ![](../art/previews/outrider_x3.png) |
| Outrider chunks (4x) | ![](../art/previews/outrider_chunks_x4.png) |
| Pintle turret (3x) | ![](../art/previews/pintle_turret_x3.png) |

## In game
- **Anchor:** each frame's centre is the footprint centre at ground level, which is the rig's collision centre. Every sheet's JSON has a `ground_centre` point that projects to (0, 0) at all headings.
- **Points:** `points.<name>` gives 32 pixel offsets, one per heading.
  - Hulls: `turret_mount` (one weapon), or `mount_a` and `mount_b` (two weapons, Bulwark Frame).
  - Turret: `pivot` and `muzzle`.
- **Hulls:** `vehicle.gd` draws the Scrap Frame and Bulwark Frame from their sheets, and `enemy_rig.gd` draws the plain Outrider. Every other rig keeps the code-drawn look.
- **Turrets:** each turret sheet picks its frame from its own aim and sits on its mount. Bullets still start from the unchanged gameplay pivot.
- **Wreck:** every chunk except the chassis is flung outward from its offset for this heading. Each piece spins and fades over 1.4 s. The hull switches to the darkened chassis sheet, and fire, dust and the crew-haul flow are unchanged. A revive restores the full sheet.
- **Part layers (voxel):** chassis models have a core (chassis, cab, rear plates, skirts) plus part layers, each built for that chassis's size:
  - `drive:` street wheels, off-road tires, sport wheels, half-track
  - `armor:` scrap, riot, spiked ram, composite, Outrider light plating, cowcatcher ram
  - extras: `nose_guns`, `nose_guns_hot`, `patch_kit`, `mine_rack`, `sensor_dish`, `roll_cage` (the cage is fitted to that chassis's cab)
  - A layer is rendered together with the core, using per-pixel owner ids, and keeps only the pixels the layer actually shows. So it stacks on the core sheet with the core's occlusion baked in, with the same frame and the same ground anchor.
  - `art_layers()` in `vehicle.gd` picks the layers from the equipped parts. A part without its own sheet uses the stock sheet for its slot.
- **Wreck pieces:** layers split into pieces, one per wheel or track, each with its own per-heading offsets. A wreck flings the core chunks (all but the chassis) plus every piece of the fitted layers. The hull switches to `<model>__chassis_burnt.png`, a soot palette where the lights go darker than the hull.
- **Sheets per chassis:** `<model>__core.png` (the hull sprite), `<model>.png` (composite with the stock parts, for previews), `__<chunk>.png`, `__L_<layer>.png` and `__L_<layer>__<piece>.png`.
- **Old part marks (replaced by the voxel layers above):** `art_marks()` reads the equipped parts and draws small overlays on the deck for:
  - drive: half-track, off-road tires, sport wheels
  - front armor: anything other than Scrap Plating
  - nose guns, white-hot while Overcharge or Deadeye is active
  - patch kit, mine rack, sensor dish, roll cage
- **Overcharge on turrets:** turret art shows a white-hot glow at its `muzzle` point.
- **Captures:** `tools/art/capture_mission.gd` and `tools/art/capture_showcase.gd` take screenshots under Xvfb.

## Decided (Cameron, 2026-11-04: Ebbtide standard)
45 degree tilt (was 30, changed to match Ebbtide's high oblique camera; every Art sheet re-rendered); 32 headings; tuning.gd colours with 3 shades; 1 px per voxel with
finer models at ~64x36 on screen; near-black outline all round; separate chunk sheets
for the wreck.

## Open
- Layers stack in a fixed order (drive, armor, extras), so where two layers overlap the later one always wins.
- No art yet for the Courier Frame, the other enemy rigs, or weapons other than the pintle.
- Chunks render on their own, so a chunk sheet shows faces that the composite hides
  (correct for flying debris).
- Hull and turret pivots: the turret mount point per heading isn't in the metadata yet.

## Art lookup by id (content models)
Art is found **by id**: something with id `X` wears `res://art/sprites/X.json` (plus its sheets) if that file exists, otherwise it keeps the code-drawn look. Nothing else needs registering.

| Kind | Where the id comes from | Placement |
|---|---|---|
| Chassis | `look.chassis` (parts id) | hull sheet + part layers (drive, armor, extras) |
| Turret weapon | the weapon's part id (`gun_stats[i].id`; "" = `pintle_turret`) | ring `pivot` on the hull's `turret_mount` / `mount_a` / `mount_b`, frame from its aim |
| Fixed weapon | the weapon's part id | rear `pivot` on the hull's `nose_mount`, frame from the hull heading; replaces the stock `nose_guns` layer |
| Utility | `shock_pulse` in `look.utility` | `shock_emitter` hull layer |
| Enemy rig | `art_id()` in `enemy_rig.gd` ("outrider"); a subclass overrides it | hull sheet; a Hunt elite (`make_elite`) adds the `elite_trim` layer |

Sheets that already ship for ids from the unmerged content branch (Proposal 01):
- **Rigs:**
  - `torcher`: rear `fuel_tank` chunk, `weak_spot` and `muzzle` points
  - `sludger`: `tank` chunk, `turret_mount` for its lobber
- **Weapons:**
  - fixed: `rivet_gun`, `flame_sprayer`
  - turrets: `acid_lobber`, `arc_projector`

These pick up art automatically:
- A weapon picks up its art as soon as its part id exists in `parts.gd`.
- A rig picks up its art once its script returns its id from `art_id()`, e.g. `func art_id() -> String: return "torcher"`.

Every enemy hull has an `elite_trim` layer (gold spine stripe and nose chevron).

**Enemy colours:** enemy red `#F23D29`, acid `#99F240`, goop `#E0A458` and elite gold `#FFC740`. `tests/art_content_test.gd` fails if an enemy sheet contains cyan `#40D1E0`, push orange `#ED7A2B`, shield `#8CBFFF` or truck `#73D980`.

**Export:** `export_presets.cfg` includes `art/sprites/*.json`, so the APK ships the metadata.


## Enemy rigs and weapon scale (PR #15)

| Rig script | art id | body (px) | notes |
|---|---|---|---|
| enemy_rig.gd | outrider | 74x32 | elite_trim when is_elite() |
| bulwark_rig.gd | bulwark | 84x46 | armored plow; `windup_glow` layer before a ram (contract below) |
| gunner_rig.gd | gunner | 74x40 | turret `gunner_rig` on turret_mount |
| scrapper_rig.gd | scrapper | 62x32 | dropper tray chunk |
| scrapper_gunner_rig.gd | scrapper_gunner | 64x34 | turret gun id `scrapper` -> sheet `scrapper_turret` (ART_WEAPON_ALIASES) |
| convoy_rig.gd | convoy | 96x46 | ram + nose guns baked into the hull; hitch point; `windup_glow` on the ram (inherits the Bulwark contract) |
| convoy_trailer.gd | convoy_trailer | 70x40 | `_art_meta_path()` override; turret `convoy_turret` |
| patcher_rig.gd | patcher | 66x34 | `winch` point; cable/hook/revive drawn over the sheet |

Every enemy hull has an `elite_trim` layer (except the trailer), wreck chunks
and frames centred on the ground footprint. Collision is unchanged (capsule
from body_len/body_wid). Weapons are modelled at 1 px per voxel like the hulls:
turret rings ~21 px, muzzles where the old code-drawn barrels ended
(pintle 30.5 px from the pivot, Gunner burst 34 px). Review shot:
`tools/art/capture_enemies.gd` -> `art/previews/capture_enemies.png`.


### Bulwark pre-ram wind-up contract

The art reads these from the Bulwark rig, **only if present** (`has_method` /
`has_signal`), so the art works with or without Content's wind-up state:

| Member | Type | Meaning |
|---|---|---|
| `is_winding_up()` | `-> bool` | true while the rig winds up for a ram; the glow shows only then |
| `windup_progress()` | `-> float` 0..1 | how far along (clamped; if missing, 1.0 while winding up) |
| `signal windup_started` | optional | restarts the pulse phase so each wind-up starts the same |

Art side (bulwark_rig.gd): layer `windup_glow` (slot `state`) is the whole plow
recoloured enemy red with a white-hot leading edge (no reserved colours).
`art_layer_modulate()` fades it from alpha ~0.25-0.5 at progress 0 to ~1.0 at 1,
pulsing at 2 Hz -> 7 Hz. Helpers: `art_winding_up()`, `art_windup_progress()`.
The old always-on attack-mode `charge_glow` was removed: the Bulwark is in
ATTACK almost all the time, so it would glow constantly and drown out the
warning. Stub: `tests/stubs/bulwark_windup_stub.gd`. Shot:
`tools/art/capture_windup.gd` -> `art/previews/capture_bulwark_windup.png`.

**Convoy:** convoy_rig.gd extends bulwark_rig.gd, so it inherits the same hook
and contract; its sheet has its own `windup_glow` (the ram). The signal is
connected in bulwark_rig.gd `_ready()` behind an `is_connected` guard, so
subclasses that call `super()` connect it exactly once. Content will not add a
`_ready()` to bulwark_rig.gd. The glow's white-hot is a 1-voxel top seam on
the leading edge only; spikes heat to enemy red. Stub:
`tests/stubs/convoy_windup_stub.gd`. Shot: `capture_windup.gd -- out.png convoy`
-> `art/previews/capture_convoy_windup.png`.

## Baked cast shadows (Ebbtide plan phase 1, Cameron 2026-11-04)
- One team sun: `voxel_render.LIGHT = (-0.45, -0.55, 0.70)` (screen x right, y down, z up): light from the upper-left, shadows fall down-right.
- Ground offset per voxel of height: `SHADOW_DIR = (0.643, 0.786)`; on screen at 45 deg tilt that is (+0.643, +0.556) px per voxel.
- Every model with a `chassis` chunk gets `<name>__shadow.png`: same 32-heading, 8-column layout, its own square frame (`meta.shadow.frame_w`), centre = ground centre, opaque `SHADOW_RGB (20,11,6)`, drawn at `meta.shadow.alpha` 0.5.
- `directional_sprite.gd` adds it as a `Shadow` child (`show_behind_parent`), synced to the frame. Turrets and weapons have none (they sit on the hull, inside its shadow).
