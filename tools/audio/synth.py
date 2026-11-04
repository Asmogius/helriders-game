#!/usr/bin/env python3
"""Procedural first-pass audio for Helriders (original, generated in-repo).

Usage: python3 tools/audio/synth.py   (needs numpy and ffmpeg with libvorbis)
Writes .ogg files into res://audio/. Deterministic (fixed seeds).
Music loops are exactly N bars long so they loop seamlessly, and the three
combat layers share length and tempo so they stay sample-synced.
"""
import os, subprocess, tempfile, wave
import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio")
rng = np.random.default_rng(1337)


def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def env(n, a=0.002, d=0.2):
    t = np.arange(n) / SR
    return np.minimum(t / a, 1.0) * np.exp(-t / d)


def dist(x, k=3.0):
    return np.tanh(k * x) / np.tanh(k)


def place(buf, snd, at):
    i = int(at * SR) % len(buf)
    n = min(len(snd), len(buf) - i)
    buf[i:i + n] += snd[:n]
    if n < len(snd):  # wrap tail so the loop is seamless
        buf[:len(snd) - n] += snd[n:]


def kick(d=0.35):
    t = t_of(d); f = 45 + 90 * np.exp(-t / 0.04)
    return dist(np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.001, 0.12), 2.5)


def metal(d=0.25, f0=None):
    t = t_of(d); f0 = f0 or rng.uniform(300, 700)
    ratios = [1.0, 1.47, 2.09, 2.76, 3.41, 4.07]
    s = sum(np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6)) for r in ratios) / len(ratios)
    s += 0.4 * rng.standard_normal(len(t)) * np.exp(-t / 0.01)
    return s * env(len(t), 0.0005, d / 4)


def hat(d=0.06):
    t = t_of(d); n = rng.standard_normal(len(t))
    n = np.diff(n, prepend=0)  # crude highpass
    return 0.5 * n * env(len(t), 0.0005, 0.015)


def saw(f, t, detune=0.0):
    ph = (f * (1 + detune) * t) % 1.0
    return 2 * ph - 1


def lowpass(x, a):
    y = np.empty_like(x); acc = 0.0
    # simple one-pole; vectorised via cumulative trick is overkill here
    for i in range(len(x)):
        acc += a * (x[i] - acc); y[i] = acc
    return y


def drone(sec, f, amt=0.15):
    t = t_of(sec)
    s = saw(f, t) + saw(f, t, 0.006) + 0.5 * saw(f * 1.5, t, -0.004)
    s = lowpass(s / 2.5, 0.02)
    lfo = 0.7 + 0.3 * np.sin(2 * np.pi * t / sec)  # one cycle per loop: seamless
    return amt * s * lfo


def bass_line(sec, bpm, notes, amt=0.35):
    beat = 60 / bpm; buf = np.zeros(int(sec * SR))
    for k, n in enumerate(notes):
        if n is None:
            continue
        f = 55 * 2 ** (n / 12); d = beat * 0.9
        t = t_of(d)
        s = dist(saw(f, t) * env(len(t), 0.005, 0.25), 4.0)
        place(buf, amt * lowpass(s, 0.08), k * beat / 2)
    return buf


def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1
    return x / m * peak


def write_ogg(name, x, q=4):
    os.makedirs(os.path.dirname(os.path.join(OUT, name)), exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    path = os.path.join(OUT, name)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), "-map_metadata", "-1", "-fflags", "+bitexact", path], check=True)
    os.remove(tmp)
    print("wrote", os.path.relpath(path, ROOT), f"{len(x)/SR:.2f}s")


def drums(sec, bpm, kicks, metals, hats):
    beat = 60 / bpm; step = beat / 4; buf = np.zeros(int(sec * SR))
    steps = int(round(sec / step))
    for s in range(steps):
        p = s % 16
        if p in kicks: place(buf, 0.9 * kick(), s * step)
        if p in metals: place(buf, 0.35 * metal(), s * step)
        if p in hats: place(buf, 0.25 * hat(), s * step)
    return buf


# --- Music -------------------------------------------------------------------
BPM = 92
BAR = 4 * 60 / BPM
COMBAT_SEC = 8 * BAR          # all three combat layers share this length

# Yard Idle: low drone, slow metallic ticks, no drums to speak of.
yard_sec = 8 * 4 * 60 / 70
yard = drone(yard_sec, 41.2, 0.5) + drone(yard_sec, 61.7, 0.15)
for i in range(16):
    place(yard, 0.12 * metal(0.6, 220 + 40 * (i % 3)), i * yard_sec / 16 + 0.1)
write_ogg("music/yard_idle.ogg", norm(yard, 0.6))

# Street Clear (low): drone + sparse kick.
low = drone(COMBAT_SEC, 41.2, 0.5) + drums(COMBAT_SEC, BPM, {0, 10}, set(), set())
write_ogg("music/combat_street_clear.ogg", norm(low, 0.6))

# Contact (mid): distorted bass + metal percussion. Played on top of low.
mid = bass_line(COMBAT_SEC, BPM, ([0, None, 0, None, 3, None, 0, -2] * 2) * 4 * 1) \
    + drums(COMBAT_SEC, BPM, set(), {4, 12}, {2, 6, 10, 14})
write_ogg("music/combat_contact.ogg", norm(mid, 0.55))

# Crossfire (high): driving kicks, busier metal, detuned stab. On top of mid.
hi = drums(COMBAT_SEC, BPM, {0, 3, 8, 11}, {4, 7, 12, 15}, set(range(0, 16, 1)))
t = t_of(COMBAT_SEC)
stab = 0.12 * dist(saw(110 * 2 ** (1 / 12), t, 0.01) * (np.sin(2 * np.pi * BPM / 60 * 2 * t) > 0.6), 3)
hi += lowpass(stab, 0.1)
write_ogg("music/combat_crossfire.ogg", norm(hi, 0.55))

# Courier: tighter pulse (16ths on a muted note), replaces Contact on Courier jobs.
cour = bass_line(COMBAT_SEC, BPM, [0] * 64, 0.25) + drums(COMBAT_SEC, BPM, set(), {8}, set(range(0, 16, 2)))
write_ogg("music/combat_courier_pulse.ogg", norm(cour, 0.5))

# Wreck: near silence + drone (one-shot, ~6 s, fades out).
w_sec = 6.0; wd = drone(w_sec, 36.7, 0.5) * np.exp(-t_of(w_sec) / 3.0)
write_ogg("music/wreck_drone.ogg", norm(wd, 0.5))

# --- Effects -----------------------------------------------------------------
# Courier checkpoint: dry double metal tick.
c = np.zeros(int(0.35 * SR)); place(c, metal(0.2, 880), 0); place(c, metal(0.2, 1175), 0.09)
write_ogg("sfx/courier_checkpoint.ogg", norm(c, 0.7))
# Courier route done: three rising ticks.
c = np.zeros(int(0.6 * SR))
for i, f in enumerate([660, 880, 1175]): place(c, metal(0.25, f), i * 0.1)
write_ogg("sfx/courier_complete.ogg", norm(c, 0.7))
# Courier timer warning: low dry blip.
tt = t_of(0.15); write_ogg("sfx/courier_warning.ogg", norm(dist(np.sin(2 * np.pi * 220 * tt) * env(len(tt), 0.002, 0.05), 3), 0.6))
# Wreck hit: distorted boom + metal debris.
b = np.zeros(int(1.4 * SR)); place(b, kick(0.9) * 1.2, 0)
nz = rng.standard_normal(int(1.2 * SR)) * env(int(1.2 * SR), 0.001, 0.3); place(b, 0.6 * lowpass(nz, 0.15), 0)
for i in range(6): place(b, 0.3 * metal(0.3), 0.05 + i * rng.uniform(0.05, 0.15))
write_ogg("sfx/wreck_hit.ogg", norm(dist(b, 2), 0.85))
# Enemy rig wrecked: shorter crunch.
b = np.zeros(int(0.7 * SR)); place(b, kick(0.4), 0)
for i in range(3): place(b, 0.35 * metal(0.2), 0.03 + i * 0.06)
write_ogg("sfx/rig_wrecked.ogg", norm(dist(b, 2), 0.75))
# Results: dry confirmation (two low clean tones, no swell).
tt = t_of(0.5); r = np.zeros(int(0.7 * SR))
place(r, np.sin(2 * np.pi * 330 * tt) * env(len(tt), 0.002, 0.08), 0)
place(r, np.sin(2 * np.pi * 247 * tt) * env(len(tt), 0.002, 0.12), 0.12)
write_ogg("sfx/results_confirm.ogg", norm(r, 0.6))
