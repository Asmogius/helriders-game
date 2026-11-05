#!/usr/bin/env python3
"""Procedural audio for Helriders (original, generated in-repo). Pass 2.

Usage: python3 tools/audio/synth.py   (needs numpy and ffmpeg with libvorbis)
Writes stereo .ogg files into res://audio/. Deterministic (fixed seeds).

Style (DESIGN "Audio / Soundtrack"): sparse industrial. Distorted bass,
metallic percussion, detuned synths, low drones. No heroic or melodic swells.

Seamless loops: every loop is rendered three times end to end (so filters,
reverb and note tails have settled and wrap round) and the middle copy is kept,
so the last sample flows into the first. The three combat layers (and the
Courier pulse) share tempo and length so they stay sample-synced in game.
"""
import os, subprocess, tempfile, wave
import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio")


# --- building blocks ------------------------------------------------------------

def secs(n):
    return np.arange(n) / SR


def t_of(d):
    return secs(int(d * SR))


def env(n, a=0.003, d=0.2, sustain=0.0):
    t = secs(n)
    return np.minimum(t / a, 1.0) * (sustain + (1 - sustain) * np.exp(-t / d))


def fade_tail(x, ms=8):
    n = min(len(x), int(SR * ms / 1000))
    x = x.copy(); x[-n:] *= np.linspace(1, 0, n)
    return x


def sat(x, k=2.0):
    return np.tanh(k * x) / np.tanh(k)


def onepole(x, a):
    """One-pole low-pass, a in (0,1]; works on 1-D arrays."""
    y = np.empty_like(x); acc = 0.0
    a = np.broadcast_to(np.asarray(a, dtype=float), x.shape)  # cutoff may sweep
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc); y[i] = acc
    return y


def lp(x, hz):
    a = 1 - np.exp(-2 * np.pi * hz / SR)
    return onepole(x, a)


def hp(x, hz):
    return x - lp(x, hz)


def saw(f, t, ph=0.0):
    p = (f * t + ph) % 1.0
    return 2 * p - 1


def supersaw(f, t, spread=0.008, voices=3, rng=None):
    rng = rng or np.random.default_rng(0)
    s = np.zeros_like(t)
    for v in range(voices):
        d = (v - (voices - 1) / 2) * spread
        s += saw(f * (1 + d), t, rng.uniform())
    return s / voices


def place(buf, snd, at, pan=0.0):
    """Add a mono sound into a stereo loop buffer, wrapping past the end."""
    gl, gr = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
    n = len(buf); i = int(round(at * SR)) % n
    snd = snd[: n]
    k = min(len(snd), n - i)
    buf[i:i + k, 0] += gl * snd[:k]; buf[i:i + k, 1] += gr * snd[:k]
    if k < len(snd):
        r = len(snd) - k
        buf[:r, 0] += gl * snd[k:]; buf[:r, 1] += gr * snd[k:]


def room(x, mix=0.18, size=1.0, loop=True):
    """Small metallic room: a few comb filters, wrapped for loops."""
    out = x.copy()
    for ch in range(2):
        wet = np.zeros(len(x))
        for j, ms in enumerate([29.7, 37.1, 41.1, 43.7]):
            d = int(SR * ms * size / 1000) + ch * 23
            g = 0.72
            y = x[:, ch].copy()
            for _ in range(6):  # unrolled feedback, wraps around for loops
                y = g * (np.roll(y, d) if loop else np.concatenate([np.zeros(d), y[:-d]]))
                wet += y
        out[:, ch] += mix * lp(wet / 8, 3500)
    return out


def loop_render(sec, fn):
    """Render fn(buffer_len) three loops long and keep the middle one."""
    n = int(round(sec * SR))
    big = fn(3 * n, 3 * sec)
    return big[n:2 * n]


def norm_rms(x, rms_db, peak=0.95):
    rms = np.sqrt(np.mean(x ** 2)) or 1e-9
    y = x * (10 ** (rms_db / 20) / rms)
    m = np.max(np.abs(y))
    if m > peak:  # soft limit
        y = np.tanh(y / peak * 1.2) * peak / np.tanh(1.2)
    return y


def write_ogg(name, x, q=3):
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q),
                    "-map_metadata", "-1", "-fflags", "+bitexact", path], check=True)
    os.remove(tmp)
    print("wrote", os.path.relpath(path, ROOT), f"{len(x)/SR:.2f}s")


# --- instruments ------------------------------------------------------------------

def kick(rng, vel=1.0, d=0.32):
    t = t_of(d); f = 42 + 70 * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.001, 0.11)
    click = lp(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.004) * 0.3
    return fade_tail(vel * sat(body + click, 1.6))


def metal(rng, vel=1.0, f0=None, d=0.35, bright=4000):
    t = t_of(d); f0 = f0 or rng.uniform(260, 520)
    ratios = [1.0, 1.59, 2.14, 2.83, 3.37, 4.21]
    s = sum(np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6)) * np.exp(-t * (3 + 2 * k) / d)
            for k, r in enumerate(ratios)) / 3
    s += 0.25 * lp(rng.standard_normal(len(t)), bright) * np.exp(-t / 0.006)
    return fade_tail(vel * lp(s * env(len(t), 0.0008, d), bright))


def hat(rng, vel=1.0, d=0.05):
    t = t_of(d); n = hp(rng.standard_normal(len(t)), 6000)
    return fade_tail(vel * 0.6 * lp(n, 11000) * env(len(t), 0.0005, d / 3))


def snare(rng, vel=1.0):
    t = t_of(0.25)
    tone = np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.04)
    nz = lp(hp(rng.standard_normal(len(t)), 900), 6000) * np.exp(-t / 0.07)
    return fade_tail(vel * sat(0.5 * tone + 0.8 * nz, 1.5))


def bass_note(f, d, drive=3.0, cutoff=380, glide=1.0):
    t = t_of(d)
    ff = f * (glide + (1 - glide) * np.exp(-t / 0.03))
    ph = np.cumsum(ff) / SR
    s = 0.6 * (2 * (ph % 1) - 1) + 0.4 * (2 * ((ph * 1.004) % 1) - 1)
    s = sat(lp(s, cutoff * (1 + 2 * np.exp(-t / 0.06))), drive)
    s += 0.5 * np.sin(2 * np.pi * np.cumsum(ff * 0.5) / SR)  # sub
    return fade_tail(s * env(len(t), 0.004, d * 0.7, 0.3))


def drone(n, sec_total, f, rng, cycles=1, cutoff=260):
    t = secs(n)
    s = supersaw(f, t, 0.006, 4, rng) + 0.4 * supersaw(f * 1.498, t, 0.005, 3, rng)
    lfo = 0.65 + 0.35 * np.sin(2 * np.pi * cycles * 3 * t / sec_total)
    l = lp(s * lfo, cutoff); r = lp(np.roll(s, 300) * lfo, cutoff * 1.1)
    return np.stack([l, r], 1) * 0.5


# --- patterns -------------------------------------------------------------------

BPM = 92
BEAT = 60 / BPM
STEP = BEAT / 4
SWING = 0.12 * STEP          # late off-beat 16ths: a slight shuffle
BARS = 8
COMBAT_SEC = BARS * 4 * BEAT
E1 = 41.2                    # key: E, dark Phrygian-ish (E F G A# B)
NOTE = lambda semis: E1 * 2 ** (semis / 12)


def step_time(s):
    return s * STEP + (SWING if s % 2 else 0.0)


def drums(n, total, pattern, rng, inst, base_vel=1.0, pan=0.0, jitter=0.25, fill_every=4, fill=None):
    """pattern: dict step(0-15) -> velocity; fill replaces pattern on fill bars."""
    buf = np.zeros((n, 2)); steps = int(round(total / STEP))
    for s in range(steps):
        bar, p = divmod(s, 16)
        pat = fill if (fill and bar % fill_every == fill_every - 1) else pattern
        if p in pat:
            v = base_vel * pat[p] * (1 - jitter * rng.uniform())
            place(buf, inst(rng, v), step_time(s), pan + rng.uniform(-0.15, 0.15))
    return buf


def bassline(n, total, bars, rng, drive=3.0, gain=0.5):
    """bars: list of 16-step lists (semitones or None), cycled per bar."""
    buf = np.zeros((n, 2)); steps = int(round(total / STEP))
    for s in range(steps):
        bar, p = divmod(s, 16)
        note = bars[bar % len(bars)][p]
        if note is None:
            continue
        L = 1
        while p + L < 16 and bars[bar % len(bars)][p + L] == "-":
            L += 1
        if note == "-":
            continue
        place(buf, gain * bass_note(NOTE(note + 12), L * STEP * 0.95, drive, glide=0.97), step_time(s))
    return buf


_ = None
X = "-"
BASS_A = [0, X, _, 0, _, _, 0, X, _, _, 1, X, _, 0, _, _]
BASS_B = [0, X, _, 0, _, _, 3, X, _, _, 1, X, 0, _, -2, X]
BASS_C = [0, X, X, _, 0, _, _, 0, 6, X, _, 5, X, _, 1, _]
BASS_D = [0, _, 0, _, _, 0, _, _, 3, X, X, _, 1, X, _, _]


def yard_idle():
    sec = 8 * 4 * 60 / 70
    rng = np.random.default_rng(11)
    def fn(n, total):
        rng.bit_generator.state = np.random.default_rng(11).bit_generator.state
        buf = drone(n, total, E1, rng, cycles=3, cutoff=180) * 0.9
        buf += drone(n, total, E1 * 2 * 1.189, rng, cycles=3, cutoff=300) * 0.18  # minor-third haze
        beat = 60 / 70
        for i in range(int(total / beat)):
            if i % 8 in (0, 5) or (i % 16 == 11):
                place(buf, metal(rng, 0.35, rng.choice([196, 233, 262]), 0.9, 2500), i * beat, rng.uniform(-0.7, 0.7))
            if i % 4 == 2:
                place(buf, 0.12 * hat(rng, 1.0, 0.09), i * beat, 0.4)
        for i in range(int(total / (beat * 4))):  # slow heartbeat kick
            place(buf, 0.35 * kick(rng, 1.0, 0.45), i * beat * 4)
        return room(buf, 0.35, 1.6)
    return norm_rms(loop_render(sec, fn), -21)


def combat_layer(kind):
    seed = {"low": 21, "mid": 22, "high": 23, "courier": 24}[kind]
    def fn(n, total):
        rng = np.random.default_rng(seed)
        buf = np.zeros((n, 2))
        if kind == "low":
            buf += drone(n, total, E1, rng, cycles=3, cutoff=220) * 0.8
            buf += drums(n, total, {0: 1.0, 10: 0.6}, rng, kick, 0.9, fill={0: 1.0, 7: 0.5, 10: 0.7, 14: 0.4})
            buf += drums(n, total, {4: 0.5, 12: 0.4}, rng, lambda r, v: metal(r, v, 300, 0.5, 2200), 0.5, pan=-0.3)
            buf = room(buf, 0.25, 1.3)
        elif kind == "mid":
            buf += bassline(n, total, [BASS_A, BASS_A, BASS_B, BASS_C, BASS_A, BASS_A, BASS_B, BASS_D], rng, 3.0, 0.55)
            buf += drums(n, total, {4: 1.0, 12: 1.0}, rng, snare, 0.5, fill={4: 1.0, 12: 1.0, 14: 0.6, 15: 0.8})
            buf += drums(n, total, {2: 0.7, 6: 1.0, 10: 0.7, 14: 1.0, 15: 0.3}, rng, hat, 0.6, pan=0.35)
            buf += drums(n, total, {3: 0.6, 11: 0.5}, rng, metal, 0.35, pan=0.5)
            buf = room(buf, 0.15)
        elif kind == "high":
            buf += drums(n, total, {0: 1.0, 3: 0.6, 8: 0.9, 11: 0.6, 14: 0.4}, rng, kick, 0.8,
                         fill={0: 1.0, 3: 0.6, 6: 0.6, 8: 0.9, 10: 0.7, 12: 0.8, 14: 0.9, 15: 0.9})
            buf += drums(n, total, {p: (0.9 if p % 4 == 0 else 0.45) for p in range(16)}, rng, hat, 0.45, pan=-0.35)
            buf += drums(n, total, {1: 0.6, 7: 0.8, 9: 0.5, 13: 0.9}, rng, metal, 0.4, pan=0.6)
            t = secs(n)
            gate = np.zeros(n)
            for s in range(int(round(total / STEP))):
                if s % 16 in (0, 3, 6, 10, 12):  # syncopated detuned stab, root and b2
                    i = int(step_time(s) * SR); L = int(STEP * 0.7 * SR)
                    gate[i:i + L] = np.exp(-np.arange(min(L, n - i)) / (0.05 * SR))
            note = np.where(((t / (4 * BEAT)).astype(int) % 4) == 3, NOTE(25), NOTE(24))
            stab = sat(supersaw(1, (np.cumsum(note) / SR), 0.012, 3, rng) * 1.0, 2.0)
            stab = lp(stab * gate, 1400) * 0.25
            buf += np.stack([stab, np.roll(stab, 220)], 1)
            buf = room(buf, 0.18)
        elif kind == "courier":
            pulse = [0 if p % 2 == 0 else None for p in range(16)]
            alt = [0, None, 0, None, 0, None, 1, None, 0, None, 0, None, 3, None, 1, None]
            buf += bassline(n, total, [pulse, pulse, pulse, alt], rng, 2.0, 0.45)
            buf += drums(n, total, {p: (0.8 if p % 2 == 0 else 0.35) for p in range(16)}, rng, hat, 0.5, pan=0.3)
            buf += drums(n, total, {4: 0.7, 12: 0.7}, rng, lambda r, v: metal(r, v, 880, 0.15, 6000), 0.35, pan=-0.4)
            buf = room(buf, 0.12)
        return buf
    x = loop_render(COMBAT_SEC, fn)
    # Layers stack in game; set relative levels so the sum stays balanced.
    return norm_rms(x, {"low": -24, "mid": -25, "high": -26, "courier": -25}[kind])


def wreck_drone():
    rng = np.random.default_rng(31)
    sec = 6.0; n = int(sec * SR); t = secs(n)
    d = drone(n, sec, NOTE(-2), rng, cycles=1, cutoff=160)
    d *= (np.minimum(t / 0.8, 1) * np.exp(-t / 3.0))[:, None]
    tick = np.zeros((n, 2)); place(tick, 0.25 * metal(rng, 1, 150, 2.5, 1200), 0.6, -0.4)
    out = room(d + tick, 0.4, 2.0, loop=False)
    return norm_rms(fade_out(out, 0.5), -24)


def fade_out(x, s):
    k = int(s * SR); x = x.copy(); x[-k:] *= np.linspace(1, 0, k)[:, None]; return x


def oneshot(length, items, verb=0.12, rms=-20):
    buf = np.zeros((int(length * SR), 2))
    for snd, at, pan in items:
        snd = snd[: len(buf) - int(at * SR)]
        i = int(at * SR)
        buf[i:i + len(snd), 0] += snd * np.sqrt(0.5 * (1 - pan)); buf[i:i + len(snd), 1] += snd * np.sqrt(0.5 * (1 + pan))
    return norm_rms(fade_out(room(buf, verb, 0.8, loop=False), 0.03), rms, 0.8)


# --- render -----------------------------------------------------------------------

write_ogg("music/yard_idle.ogg", yard_idle())
write_ogg("music/combat_street_clear.ogg", combat_layer("low"))
write_ogg("music/combat_contact.ogg", combat_layer("mid"))
write_ogg("music/combat_crossfire.ogg", combat_layer("high"))
write_ogg("music/combat_courier_pulse.ogg", combat_layer("courier"))
write_ogg("music/wreck_drone.ogg", wreck_drone())

r = np.random.default_rng(41)
write_ogg("sfx/courier_checkpoint.ogg", oneshot(0.45, [(metal(r, 1, 660, 0.3, 3500), 0, -0.2), (metal(r, 0.8, 990, 0.3, 3500), 0.085, 0.2)]))
write_ogg("sfx/courier_complete.ogg", oneshot(0.8, [(metal(r, 0.9, f, 0.35, 3500), i * 0.11, -0.3 + 0.3 * i) for i, f in enumerate([494, 660, 990])]))
tt = t_of(0.18)
blip = lp(sat(np.sin(2 * np.pi * 196 * tt) + 0.3 * np.sin(2 * np.pi * 392 * tt), 1.5), 1800) * env(len(tt), 0.004, 0.05)
write_ogg("sfx/courier_warning.ogg", oneshot(0.4, [(fade_tail(blip), 0, 0), (fade_tail(0.7 * blip), 0.16, 0)], 0.08))
boom = lp(sat(kick(r, 1.2, 1.0) + 0.5 * lp(r.standard_normal(int(SR)) * np.exp(-t_of(1.0) / 0.25), 900), 1.6), 3000)
write_ogg("sfx/wreck_hit.ogg", oneshot(1.6, [(boom, 0, 0)] + [(metal(r, 0.4, None, 0.4, 2500), 0.05 + 0.09 * i + r.uniform(0, 0.05), r.uniform(-0.8, 0.8)) for i in range(6)], 0.22, -16))
crunch = lp(sat(kick(r, 1.0, 0.4), 1.4), 2500)
write_ogg("sfx/rig_wrecked.ogg", oneshot(0.8, [(crunch, 0, 0)] + [(metal(r, 0.45, None, 0.25, 2800), 0.03 + 0.05 * i, r.uniform(-0.6, 0.6)) for i in range(3)], 0.15, -18))
tt = t_of(0.45)
tone = lambda f: fade_tail(np.sin(2 * np.pi * f * tt) * env(len(tt), 0.004, 0.09) + 0.15 * np.sin(4 * np.pi * f * tt) * env(len(tt), 0.002, 0.03))
write_ogg("sfx/results_confirm.ogg", oneshot(0.7, [(tone(330), 0, 0), (tone(247), 0.13, 0)], 0.1))

# --- Combat SFX pass (Bulwark charge, Torcher, Sludger; PRs #16/#17) -------------
r = np.random.default_rng(51)

# Bulwark wind-up: diesel roar revving up over ~0.5 s. Firing pulses (AM) on a
# rising detuned saw, a noisy intake rumble, gentle drive. In game its pitch
# also follows windup_progress().
d = 0.55; tt = t_of(d); n = len(tt)
f = 48 + 52 * (tt / d) ** 1.4
ph = np.cumsum(f) / SR
eng = 0.6 * (2 * (ph % 1) - 1) + 0.4 * (2 * ((ph * 1.01 + 0.3) % 1) - 1)
fire = 0.55 + 0.45 * np.sin(2 * np.pi * ph * 0.5) ** 2          # cylinder pulses
rumble = lp(r.standard_normal(n), 400) * 0.6
roar = sat(lp((eng * fire + rumble) * (0.35 + 0.65 * (tt / d)), 900 + 1400 * tt / d), 2.2)
roar *= np.minimum(tt / 0.03, 1) * np.minimum((d - tt) / 0.04, 1)
write_ogg("sfx/bulwark_windup.ogg", oneshot(d, [(roar, 0, 0)], 0.08, -17))

# Ram impact: heavy low thud, crumpling metal, short scrape.
thud = lp(sat(kick(r, 1.3, 0.6), 1.8), 1500)
scrape = lp(hp(r.standard_normal(int(0.35 * SR)), 1200), 4000) * env(int(0.35 * SR), 0.01, 0.1) * 0.25
write_ogg("sfx/ram_impact.ogg", oneshot(0.8, [(thud, 0, 0), (scrape, 0.03, 0.3)] +
          [(metal(r, 0.5, f0, 0.3, 2200), 0.01 + 0.04 * i, r.uniform(-0.5, 0.5)) for i, f0 in enumerate([140, 210, 175])], 0.15, -16))

# Torcher tank rupture: pressure hiss, then a fuel "whoomph" (noise swelling
# through an opening filter) and crackle.
L = 1.6; n = int(L * SR); tt = secs(n)
hiss = hp(r.standard_normal(int(0.15 * SR)), 3000) * np.linspace(0.2, 0.6, int(0.15 * SR))
whoomph_n = r.standard_normal(n)
cut = 200 + 2200 * np.exp(-((tt - 0.25) / 0.18) ** 2)
whoomph = onepole(whoomph_n, 1 - np.exp(-2 * np.pi * cut / SR)) * np.minimum(tt / 0.08, 1) * np.exp(-tt / 0.45)
boom = lp(kick(r, 1.0, 0.8), 600)
crackle = np.zeros(n)
for _ in range(40):
    i = int(r.uniform(0.15, 1.4) * SR); k = int(0.004 * SR)
    crackle[i:i + k] += r.uniform(0.2, 0.6) * hp(r.standard_normal(k), 2000) * np.exp(-tt[i:i + k] * 0 - np.arange(k) / (0.001 * SR))
crackle *= np.exp(-tt / 0.6)
write_ogg("sfx/torcher_rupture.ogg", oneshot(L, [(hiss, 0, 0), (sat(1.4 * whoomph, 1.5), 0.1, 0), (boom, 0.1, 0), (crackle, 0, 0.3)], 0.25, -15))

# Sludger acid shell fire: hollow mortar "thunk" plus a wet gurgle.
tt = t_of(0.4)
thunk = np.sin(2 * np.pi * np.cumsum(140 * np.exp(-tt / 0.08) + 70) / SR) * env(len(tt), 0.002, 0.07)
pop = lp(r.standard_normal(len(tt)), 1800) * np.exp(-tt / 0.02) * 0.5
gurgle = np.sin(2 * np.pi * np.cumsum(300 + 120 * np.sin(2 * np.pi * 23 * tt)) / SR) * env(len(tt), 0.03, 0.08) * 0.2
write_ogg("sfx/acid_fire.ogg", oneshot(0.45, [(fade_tail(thunk + pop), 0, 0), (fade_tail(gurgle), 0.05, 0.2)], 0.12, -19))

# Acid shell impact: wet splat, then a fizzing sizzle with bubble pops.
L = 1.0; n = int(L * SR); tt = secs(n)
splat = lp(r.standard_normal(int(0.12 * SR)), 1400) * env(int(0.12 * SR), 0.002, 0.03)
sizzle = lp(hp(r.standard_normal(n), 4000), 9000) * np.minimum(tt / 0.05, 1) * np.exp(-tt / 0.35) * 0.35
sizzle *= 0.7 + 0.3 * np.sin(2 * np.pi * 31 * tt)
items = [(splat, 0, 0), (sizzle, 0.02, 0)]
for _ in range(7):  # bubble blips: fast upward chirps
    bd = 0.035; bt = t_of(bd); f0 = r.uniform(500, 1100)
    b = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 2 * bt / bd)) / SR) * env(len(bt), 0.002, 0.01) * 0.25
    items.append((fade_tail(b), r.uniform(0.08, 0.7), r.uniform(-0.6, 0.6)))
write_ogg("sfx/acid_impact.ogg", oneshot(L, items, 0.1, -19))

# --- Weapons and hits pass (playtest: "guns need sound effects") -------------------
# Short, dry and a little different each (the game also jitters pitch per shot).
r = np.random.default_rng(61)


def crack(rng, d, cut, body_hz, body_amt, drive=2.0):
    """A gunshot: sharp noise crack into a pitched body thump, then a tail."""
    tt = t_of(d); n = len(tt)
    noise = rng.standard_normal(n)
    snap = hp(noise, 1500) * np.exp(-tt / 0.006)
    blast = lp(noise, cut) * np.exp(-tt / (d * 0.28))
    body = np.sin(2 * np.pi * np.cumsum(body_hz * (1 + 1.5 * np.exp(-tt / 0.01))) / SR) * np.exp(-tt / (d * 0.22)) * body_amt
    return fade_tail(sat(snap * 0.8 + blast + body, drive))


# Light machine gun (Pintle Turret, Twin Guns, Hood Guns, Burst Turret, enemy MGs).
write_ogg("sfx/gun_light.ogg", oneshot(0.16, [(crack(r, 0.14, 3500, 160, 0.7), 0, 0)], 0.05, -22))
# Heavy MG: lower, chunkier.
write_ogg("sfx/gun_heavy.ogg", oneshot(0.22, [(crack(r, 0.2, 2200, 95, 1.0, 2.4), 0, 0)], 0.06, -21))
# Scattergun: a wide boom with a rattle of pellets.
sg = crack(r, 0.38, 1800, 70, 1.2, 2.6)
rattle = [(fade_tail(hp(r.standard_normal(int(0.01 * SR)), 2500) * 0.25), 0.02 + 0.012 * i, r.uniform(-0.5, 0.5)) for i in range(5)]
write_ogg("sfx/gun_scatter.ogg", oneshot(0.45, [(sg, 0, 0)] + rattle, 0.1, -19))
# Rivet gun: pneumatic punch and a metal clank.
tt = t_of(0.12)
pneu = lp(r.standard_normal(len(tt)), 2500) * np.exp(-tt / 0.02)
write_ogg("sfx/gun_rivet.ogg", oneshot(0.3, [(fade_tail(sat(pneu, 1.5)), 0, 0), (metal(r, 0.7, 320, 0.18, 3000), 0.015, 0.1)], 0.08, -20))
# Flame sprayer: a short roaring whoosh (played as a stream while firing).
d = 0.28; tt = t_of(d)
roar = lp(r.standard_normal(len(tt)), 900 + 700 * np.sin(np.pi * tt / d)) * np.sin(np.pi * tt / d) ** 0.6
write_ogg("sfx/gun_flame.ogg", oneshot(d, [(fade_tail(sat(roar * 1.5, 1.4)), 0, 0)], 0.06, -22))
# Arc projector: an electric zap (buzzing square sweep with crackle).
d = 0.18; tt = t_of(d)
f = 900 * np.exp(-tt / 0.06) + 220
sq = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.4
fizz = hp(r.standard_normal(len(tt)), 3500) * (r.random(len(tt)) > 0.85) * 0.6
zap = (sq + fizz) * env(len(tt), 0.002, 0.05)
write_ogg("sfx/gun_arc.ogg", oneshot(0.22, [(fade_tail(lp(zap, 7000)), 0, 0)], 0.05, -22))
# Harpoon: a heavy twang and the chain paying out.
d = 0.5; tt = t_of(d)
twang = np.sin(2 * np.pi * np.cumsum(180 + 60 * np.exp(-tt / 0.05)) / SR) * np.exp(-tt / 0.12)
chain = [(metal(r, 0.35, r.uniform(1800, 2600), 0.05, 6000), 0.05 + 0.035 * i, 0.2) for i in range(8)]
write_ogg("sfx/harpoon_fire.ogg", oneshot(0.6, [(fade_tail(sat(twang, 1.8)), 0, 0), (crack(r, 0.1, 2000, 120, 0.5), 0, 0)] + chain, 0.1, -19))
# Mortar: a deep hollow "thoomp".
tt = t_of(0.5)
thoomp = np.sin(2 * np.pi * np.cumsum(90 * np.exp(-tt / 0.1) + 45) / SR) * env(len(tt), 0.002, 0.12)
puff = lp(r.standard_normal(len(tt)), 900) * np.exp(-tt / 0.05) * 0.6
write_ogg("sfx/mortar_fire.ogg", oneshot(0.55, [(fade_tail(sat(thoomp + puff, 1.6)), 0, 0)], 0.12, -18))
# Explosion: shells, barrels, mines.
L = 1.1
kb = kick(r, 1.3, 0.9); n = len(kb); tt = secs(n)
bang = lp(sat(kb + 0.8 * lp(r.standard_normal(n) * np.exp(-tt / 0.22), 1200), 1.8), 3500)
debris = [(metal(r, 0.3, None, 0.2, 2600), 0.06 + r.uniform(0, 0.4), r.uniform(-0.8, 0.8)) for _ in range(4)]
write_ogg("sfx/explosion.ogg", oneshot(L, [(bang, 0, 0)] + debris, 0.2, -16))
# Reload: two dry clacks.
write_ogg("sfx/reload.ogg", oneshot(0.35, [(metal(r, 0.6, 700, 0.06, 5000), 0, -0.1), (metal(r, 0.8, 520, 0.08, 4500), 0.16, 0.1)], 0.04, -24))
# Overheat: a venting hiss.
d = 0.7; tt = t_of(d)
vent = lp(hp(r.standard_normal(len(tt)), 2500), 8000) * np.minimum(tt / 0.02, 1) * np.exp(-tt / 0.25)
write_ogg("sfx/overheat.ogg", oneshot(d, [(fade_tail(vent), 0, 0), (metal(r, 0.4, 880, 0.1, 4000), 0, 0)], 0.06, -22))
# Bullet into a zombie: a soft wet thud.
tt = t_of(0.09)
thud = lp(r.standard_normal(len(tt)), 700) * np.exp(-tt / 0.015) + np.sin(2 * np.pi * 110 * tt) * np.exp(-tt / 0.02) * 0.6
write_ogg("sfx/hit_flesh.ogg", oneshot(0.1, [(fade_tail(thud), 0, 0)], 0.02, -26))
# Zombie down: a squelchy splat.
tt = t_of(0.3)
splat = lp(r.standard_normal(len(tt)), 1100) * env(len(tt), 0.002, 0.06)
gl = np.sin(2 * np.pi * np.cumsum(240 - 140 * tt / 0.3) / SR) * env(len(tt), 0.01, 0.07) * 0.4
write_ogg("sfx/zombie_die.ogg", oneshot(0.32, [(fade_tail(splat), 0, 0), (fade_tail(gl), 0.02, 0)], 0.05, -23))
