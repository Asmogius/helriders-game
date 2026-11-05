# Audio credits

Every audio file in `audio/` is original, generated in this repo by
`tools/audio/synth.py` (Python + numpy, encoded to stereo Ogg Vorbis q3 with
ffmpeg/libvorbis). No samples, loops or third-party recordings are used.
License: same as the project (owner's). Regenerate with
`python3 tools/audio/synth.py` (fixed seeds, so output is repeatable).

Pass 2 (2026-11-03): stereo, room reverb, swing and velocity variation, bar-to-bar
variation and fills, loops rendered three times with the middle kept so they wrap
cleanly, layer levels set so all three combat layers together peak around -3 dBFS,
softer filtered SFX. Style per DESIGN "Audio / Soundtrack".

Key E (E, F, G, A#, B), 92 BPM for combat, 70 BPM for the garage.

| File | Use | Length | How it was made | License |
|---|---|---|---|---|
| audio/music/yard_idle.ogg | Garage "Yard Idle" (loop) | 27.4 s, 8 bars @70 | Detuned supersaw drone on E1 + minor-third haze, low-passed with slow LFO; sparse panned inharmonic metal hits, a soft heartbeat kick every bar, large metallic room | Original, generated in-repo |
| audio/music/combat_street_clear.ogg | Combat layer 1, low (loop) | 20.9 s, 8 bars @92 | E1 drone, kick on 1 and the "and" of 3 with a fill every 4th bar, dull metal backbeat | Original, generated in-repo |
| audio/music/combat_contact.ogg | Combat layer 2, mid (loop, synced) | 20.9 s | Distorted saw+sub bass riff (four bar variants, slight glide), snare backbeat with fills, swung hats, metal accents | Original, generated in-repo |
| audio/music/combat_crossfire.ogg | Combat layer 3, high (loop, synced) | 20.9 s | Driving syncopated kicks with fills, 16th hats, busier metal, gated detuned stab (root / b2) | Original, generated in-repo |
| audio/music/combat_courier_pulse.ogg | Replaces layer 2 on Courier jobs | 20.9 s | Tight 8th-note bass pulse with a variation bar, 8th hats, high dry ticks | Original, generated in-repo |
| audio/music/wreck_drone.ogg | Wreck: near-silence + drone | 6.0 s | Low D drone swelling in and decaying, one distant metal toll, big room | Original, generated in-repo |
| audio/sfx/courier_checkpoint.ogg | Courier checkpoint reached | 0.45 s | Two filtered metal ticks (E5, B5) | Original, generated in-repo |
| audio/sfx/courier_complete.ogg | Courier route delivered | 0.8 s | Three rising filtered metal ticks | Original, generated in-repo |
| audio/sfx/courier_warning.ogg | Courier par tier slipped | 0.4 s | Soft low double blip (G3) | Original, generated in-repo |
| audio/sfx/wreck_hit.ogg | Player rig wrecked | 1.6 s | Low-passed kick boom + filtered noise, scattered metal debris, room | Original, generated in-repo |
| audio/sfx/rig_wrecked.ogg | Enemy rig wrecked | 0.8 s | Short low-passed crunch + three metal hits | Original, generated in-repo |
| audio/sfx/results_confirm.ogg | Results card: dry confirmation | 0.7 s | Two short clean tones (E4, B3) | Original, generated in-repo |

## Combat SFX pass (Bulwark charge, Torcher, Sludger)

Same tool, same license (original, generated in-repo by `tools/audio/synth.py`).

| File | Use | Length | How it was made | License |
|---|---|---|---|---|
| audio/sfx/bulwark_windup.ogg | Bulwark charge wind-up (pitch also follows `windup_progress()` in game, 0.9x to 1.25x) | 0.55 s | Detuned saw engine rising 48 to 100 Hz with cylinder-pulse AM, low-passed noise rumble, opening filter, soft drive, crescendo | Original, generated in-repo |
| audio/sfx/ram_impact.ogg | Bulwark rams the player | 0.8 s | Low-passed driven kick thud, three low metal hits, short filtered scrape | Original, generated in-repo |
| audio/sfx/torcher_rupture.ogg | Torcher's fuel tank ruptures | 1.6 s | Pressure hiss, noise "whoomph" through a swelling filter, low boom, decaying fire crackle | Original, generated in-repo |
| audio/sfx/acid_fire.ogg | Sludger lobs a shell | 0.45 s | Pitch-dropping sine "thunk" + noise pop, wobbling wet gurgle | Original, generated in-repo |
| audio/sfx/acid_impact.ogg | Acid shell (or Acid Lobber glob) lands | 1.0 s | Low-passed wet splat, fizzing high-passed sizzle, random rising bubble blips | Original, generated in-repo |
| audio/sfx/gun_light.ogg | Light guns: Pintle Turret, Twin Guns, Hood Guns, Burst Turret, enemy MGs | 0.16 s | High-passed noise snap into a low-passed blast and a falling 160 Hz body, saturated | Original, generated in-repo |
| audio/sfx/gun_heavy.ogg | Heavy MG Turret | 0.22 s | As gun_light, darker and lower (95 Hz body), more drive | Original, generated in-repo |
| audio/sfx/gun_scatter.ogg | Scattergun Turret | 0.45 s | Wide low boom plus five short pellet rattles, panned | Original, generated in-repo |
| audio/sfx/gun_rivet.ogg | Rivet Gun | 0.3 s | Pneumatic noise punch and a metal clank | Original, generated in-repo |
| audio/sfx/gun_flame.ogg | Flame Sprayer, Torcher (streams while firing) | 0.28 s | Low-passed noise whoosh with a swelling filter | Original, generated in-repo |
| audio/sfx/gun_arc.ogg | Arc Projector | 0.18 s | Falling square-wave buzz with sparse crackle | Original, generated in-repo |
| audio/sfx/harpoon_fire.ogg | Harpoon | 0.6 s | Pitched twang, a short crack, eight chain-link ticks | Original, generated in-repo |
| audio/sfx/mortar_fire.ogg | Mortar launch | 0.55 s | Falling sine "thoomp" with a low noise puff | Original, generated in-repo |
| audio/sfx/explosion.ogg | Shells, barrels and mines going off | 1.1 s | Kick boom plus low-passed noise, four scattered metal debris hits | Original, generated in-repo |
| audio/sfx/reload.ogg | Player magazine runs dry and reloads | 0.35 s | Two dry metal clacks | Original, generated in-repo |
| audio/sfx/overheat.ogg | Player heat gun overheats | 0.7 s | Venting high-passed hiss and a metal ping | Original, generated in-repo |
| audio/sfx/hit_flesh.ogg | Bullet hits a zombie | 0.1 s | Soft low-passed noise thud with a 110 Hz knock | Original, generated in-repo |
| audio/sfx/zombie_die.ogg | Zombie killed | 0.32 s | Squelchy low-passed splat and a falling gurgle | Original, generated in-repo |
