# Audio credits

Every audio file in `audio/` is original, generated in this repo by
`tools/audio/synth.py` (Python + numpy, encoded to Ogg Vorbis with ffmpeg/libvorbis).
No samples, loops or third-party recordings are used. License: same as the
project (owner's). Regenerate with `python3 tools/audio/synth.py` (deterministic seed).

First-pass placeholders for DESIGN "Audio / Soundtrack": sparse industrial,
distorted bass, metallic percussion, detuned synths, low drones, no melodic swells.

| File | Use | Length | How it was made | License |
|---|---|---|---|---|
| audio/music/yard_idle.ogg | Garage "Yard Idle" (loop) | 27.4 s, 8 bars @70 | Detuned saw drones (E1 + B1) low-passed, slow LFO, sparse inharmonic metal ticks | Original, generated in-repo |
| audio/music/combat_street_clear.ogg | Combat layer 1, low (loop) | 20.9 s, 8 bars @92 | Saw drone + sparse distorted sine-sweep kick | Original, generated in-repo |
| audio/music/combat_contact.ogg | Combat layer 2, mid (loop, synced) | 20.9 s | Distorted low-passed saw bass line, metal hits, hats | Original, generated in-repo |
| audio/music/combat_crossfire.ogg | Combat layer 3, high (loop, synced) | 20.9 s | Driving kicks, busier metal percussion, 16th hats, gated detuned saw stab | Original, generated in-repo |
| audio/music/combat_courier_pulse.ogg | Replaces layer 2 on Courier jobs | 20.9 s | Tight 8th-note muted bass pulse + hats | Original, generated in-repo |
| audio/music/wreck_drone.ogg | Wreck: near-silence + drone | 6.0 s | Low D1 saw drone, exponential fade | Original, generated in-repo |
| audio/sfx/courier_checkpoint.ogg | Courier checkpoint reached | 0.35 s | Two dry metal ticks | Original, generated in-repo |
| audio/sfx/courier_complete.ogg | Courier route delivered | 0.6 s | Three rising metal ticks | Original, generated in-repo |
| audio/sfx/courier_warning.ogg | Courier par warning (not hooked yet) | 0.15 s | Distorted 220 Hz blip | Original, generated in-repo |
| audio/sfx/wreck_hit.ogg | Player rig wrecked | 1.4 s | Distorted kick boom, filtered noise, metal debris | Original, generated in-repo |
| audio/sfx/rig_wrecked.ogg | Enemy rig wrecked (not hooked yet) | 0.7 s | Short kick + metal crunch | Original, generated in-repo |
| audio/sfx/results_confirm.ogg | Results card: dry confirmation | 0.7 s | Two short clean sine tones (E4, B3) | Original, generated in-repo |
