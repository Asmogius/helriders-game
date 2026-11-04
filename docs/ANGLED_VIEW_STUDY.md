# Angled view study (30° tilt for the whole fight)

Prototype branch `art/zombie-tilt-proto`, awaiting Cameron's review. Based on reading
`scripts/mission.gd` (scene setup), `scripts/arena.gd`, `scripts/chase_camera.gd`,
`scripts/directional_sprite.gd`, `scripts/zombie.gd`, `scripts/hud.gd` and `tools/art/voxel_render.py`.

## What the prototype changes

- Zombie sheets (Shambler, Tank) now render through a local copy of `render_frame` with
  the face-culling sign fixed (`view = (0, +sin t, cos t)`), as in the garage sample.
  The shared renderer draws the north (far) sides and drops the south (near) sides, so
  zombies showed their backs/insides and read flat. With the fix they show a front,
  side and height at the rigs' 30°. Same 16 headings picked from `rotation` (which
  already follows movement), 1.8x scale, six clothing palettes. Atlas stays 1664x1870.
- Nothing else: `zombie.gd`, collision, hit circles, speed and AI are untouched.
- Before/after: `art/previews/zombie_tilt_before.png`, `zombie_tilt_after.png`
  (same `capture_zombies_sample.gd` scene: player rig, 10 Shamblers, 3 Tanks).

Note: the rigs themselves have the same culling bug in the shared renderer. Fixing
`voxel_render.py` and re-rendering all 572 rig sheets is the single biggest "reads as
angled" win and is art-only, but it re-renders every vehicle, so it needs its own PR.

## How the fight is built today

- `mission.gd` adds nodes in tree order: arena (z -10), splats (z -5), hazards,
  markers (z 1), mines, barrels, pickups, zombies, player rig, enemy rigs, hunters,
  bullets/shells (z 4), fx (z 5), reticle/keywords (z 6), camera, HUD. There is no
  y-sorting anywhere; draw order is tree order plus fixed `z_index`.
- `arena.gd` draws the whole map in one `_draw` pass: flat concrete, roads, cracks,
  then buildings as flat rects (wall colour, inset roof, clutter) with a fixed
  +16,+16 drop shadow for fake height, props as rotated rects. Collision is
  axis-aligned boxes from `layouts.gd`.
- `chase_camera.gd` is a rotation-locked Camera2D (`ignore_rotation`), look-ahead and
  speed zoom. No projection: world = screen up to zoom.
- Rigs use `DirectionalSprite` (32 headings, never rotated); zombies use the P0 atlas.
- Aim: touch stick gives a direction; mouse uses `get_global_mouse_position()`;
  edge arrows use `get_canvas_transform()`. There is no minimap today.

## What "angled" needs, item by item

| Item | Work | Kind |
|---|---|---|
| Rig sheets | fix shared renderer sign, re-render all sheets, re-check turret/mount points | art-only |
| Zombies | this prototype; extend to Brute, Boomer, Slimer | art-only (P3) |
| Map ground tiles | V5.1 baked texture; ground is flat so no tilt change needed beyond foreshortened details | art-only (P4) |
| Buildings | V5.2 voxel blocks at 30°: roof drawn shifted up by `h*sin30`, south wall visible below it; footprint stays the collision rect | art (P4), plus draw-order work below |
| Props / cover | voxel sprites, same collision boxes (V5.3); props are rotated so they need heading sheets or 8-16 baked rotations | art-only (P4) |
| Shadows | replace +16,+16 offsets with shadows cast "north-west" consistent with LIGHT; per-sprite blob shadow under rigs/zombies | art-only |
| FX | muzzle flashes, explosions, smoke should rise (offset up-screen by height); splats/decals stay flat | mostly art (P2); projectile visual height offset is a small draw change |
| UI markers | reticle, lock, status rings, HP bars: anchor at ground point vs. sprite top; edge arrows unchanged | small code (P7/P1 `hud.gd`, `lock_reticle.gd`) |
| Drawing order | tall things must y-sort: put buildings/props/rigs/zombies/hunters under one `y_sort_enabled` Node2D, origin at the ground point (already true for sheets). Arena must split into a flat ground layer and per-building sprite nodes | engine/scene change (`mission.gd`, `arena.gd`) |
| Occlusion | rigs north of a tall building get hidden by its wall/roof. Options: fade the building to ~35% alpha when the player (or a lock target) is inside its "shadow" rect (cheap, a per-building rect test per frame); or a cutaway roof sprite. Recommend fade + a silhouette outline of the rig | engine/scene change |
| Collision / hitboxes | can stay top-down: all physics is on the ground plane and sprites are anchored at the footprint centre. Only visual mismatch: bullets hitting a tall sprite's upper part pass "through"; acceptable, or raise bullet visuals by a fixed height | no gameplay change needed |
| Camera | keep rotation-locked 2D camera (the art carries the tilt). Optionally lead the camera ~10% more up-screen since tall south walls hide what's north; zoom unchanged | small code |
| Aim / input | world is still ground plane, so stick directions are correct. Mouse aim: cursor points at a sprite's body, which sits ~h*sin30 above its ground point; add a pick offset (aim at ground point under the cursor + raise ~10 px) or auto-snap to nearest target | small code (`mission._kbm_input`) |
| Minimap | none exists; if added (UI), draw it top-down from layout data, unaffected | n/a |

## Performance / atlas size (mobile, GLES3 compat)

- Zombie atlas unchanged (1664x1870, under the 2048 limit). 32 headings would not fit
  one 2048 atlas with 6 variants; keep 16 or split per kind.
- Buildings as modular pieces (roof, wall segments, corners) ~1-2 atlases of 1024-2048.
  Baking each building into one sprite at job start keeps draw calls low; ~20-40
  building sprites + props per map is fine on 2020 phones.
- Y-sorting a few hundred zombies: Godot y_sort is a per-frame sort of canvas items;
  zombies already draw individually, so cost is minor. Building fade is per-building
  alpha, no shaders needed.

## Art-only vs beyond art

- **Art-only:** renderer culling fix + rig re-render, zombie sheets (all kinds), tiles,
  building/prop/cover voxel sprites, shadows, FX sheets.
- **Beyond art (engine/scene code, no gameplay numbers):** splitting `arena.gd` into
  ground + y-sorted building/prop nodes, y-sort container in `mission.gd`, occlusion fade,
  marker anchoring, mouse-aim pick offset, optional camera lead.
- **Gameplay:** none required; collision, hit circles, speeds and AI stay top-down.

## Packages affected

- **P4 Map looks:** buildings, props, cover, shadows, arena split (largest share).
- **P5 Map layouts:** layout data unchanged, but very tall buildings near south edges of
  routes need checking for occlusion of choke points; add a building `height` field.
- **UI P0:** atlas loader for building/prop atlases; shared renderer fix.
- **UI P1:** rarity beams/pickup markers anchored above sprites.
- **UI P7:** HUD markers, reticle, status rings offset; fade/silhouette look.
- Also P2 (FX height) and P3 (remaining zombie kinds).

## Rough effort

- Renderer fix + rig re-render + checks: 0.5-1 day.
- Remaining zombie kinds: 1 day.
- Buildings/props/cover voxel art (modular): 3-5 days.
- Arena split, y-sort, occlusion fade, marker anchoring, aim offset: 2-3 days + tests.
- FX/shadow pass: 1-2 days.
- Total: about 2 working weeks for one agent, or about 1 week split across P3/P4/P7.
