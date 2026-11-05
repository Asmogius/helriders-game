# HD-2D look test (prototype)

Prototype only. Cameron asked for this without the screen-edge blur. **Depth of field was cut on 2026-11-05.** There is no blur pass and no switch that can turn one on. Do not add it back without asking.

The branch targets `main` (the 45° sheets from PR #70 are already there). Rigs and zombies are **1 px per voxel**. `sprites_hd` (2 px) is not used. Map sheets were not re-rendered at 45°. Colours in this prototype are hardcoded in `look_stack.gd`. It does not read `tuning.gd`, and the night ambient is not brown `#512b11`.

## What the shots are

Same frozen Crossroads fight (player rig, Bulwark, four zombies, a fire burst):

| File | Look |
|---|---|
| `day_before.png` | Stock fight. No CanvasModulate, no lights, no grade. |
| `day_after.png` | Day stack: key light, warm headlights, fire, muzzle, vignette. |
| `night_before.png` | Cool ambient + grade only. No point lights. |
| `night_after.png` | Cool night plus warm headlights, muzzle and fire. |
| `looktest_day_night.gif` | Those four stills, in that order. |

Night ambient is `Color(0.40, 0.46, 0.60)` — blue above red, bright enough that the street still reads. Fire, muzzle and headlights stay warm (`#ff7a24`, `#ffedc7`, `#ffd694`). The grade mixes the original hue back in on bright pixels so those pools are not painted blue. The hottest pixel of each pool still clips to white; the fringe around it stays warm.

## How to run

```sh
godot --path . res://scenes/looktest_fight.tscn
xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_looktest.gd -- concepts/looktest
godot --headless --path . -s res://tests/looktest_test.gd
```

The fight scene freezes AI and physics after the pose. It does not change combat code.

## Compatibility / Android cost

Renderer is the project's `gl_compatibility` (GLES3). There is no Forward+ and no 2D HDR, so there is no `WorldEnvironment` glow. Bloom is a handful of pre-blurred additive sprites.

Measured on the capture that shipped with this branch (xvfb, llvmpipe — a ceiling, not a phone frame time). From `concepts/looktest/perf.txt`:

| Shot | Draw calls | Point lights |
|---|---|---|
| day_before / night_before | 27 | 0 |
| day_after / night_after | 31 | 4 |

The stack adds 4 draw calls (27 → 31) for the lights, halo sprites and the grade rect together. The grade is the one backbuffer copy. The extra draws versus the earlier capture are the shadow and lights sheets that landed on main.

| Piece | Full-screen passes | Notes |
|---|---|---|
| World + sprites | 0 extra | Normal canvas draw. Nearest-filter sheets, unchanged. |
| CanvasModulate | 0 | Ambient multiply / light ambient. One colour. |
| PointLight2D × 3 or 4 | 0 extra passes | Compatibility lights the canvas item in its own fragment shader. There is no deferred light buffer. **The ground is one big canvas item**, so every light that overlaps the map is evaluated for every visible ground pixel. Four small loops, not four copies of the frame. |
| LightOccluder2D | not used | Each occluder is an extra shadow pass. Skipped on Android, including this prototype. |
| Grade + vignette + height fog | **1** | `hint_screen_texture` forces **one BackBufferCopy** of the colour buffer. That copy is the expensive part on a tiled phone GPU: the tile buffer is flushed and the whole frame is read back. The height fog is a colour mix, not a blur. |
| Screen-edge blur | removed | Cameron cut it. The grade shader samples the screen once. |
| Bloom halos + lamp dots | 0 extra | A few `Sprite2D`s. Dots are 3×2 nearest pixels. Halos are a baked gaussian. |

**Full-screen post is 1 pass and 1 backbuffer copy**, on both low and high. The cap asked for was 2–3.

Light count:

- Pool of **8** `PointLight2D`s. High turns on at most **4** (sun/moon key, headlights, fire, muzzle). Low turns on at most **3** and replaces the headlight light with one additive oval.
- Requests farther than ~980 px from the camera are dropped.
- No shadows.

What this does **not** prove: frame time on a 2020 3–4 GB phone. Software GL draw calls will not match a Mali/Adreno tile cost. The honest risk is the backbuffer copy, then the ground fragment evaluating 3–4 lights. Low should ship as: 3 lights, headlight sprite, grade copy kept.

## Out of scope

Normal maps, `DirectionalLight2D` (without normals it is a flat add, so the key is a camera-locked `PointLight2D` pool from the upper left), shadow sheets, gameplay, `tuning.gd`, export presets. The screen-edge blur stays out until Cameron asks for it again.
