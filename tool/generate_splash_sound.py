#!/usr/bin/env python3
"""Generate assets/sfx/splash.wav — the splash-screen logo sting.

Synthesised rather than recorded, for the same reason assets/icon/ is
generated: the sound has to land *on* the splash animation, so its timing
lives next to the numbers it must match. `IMPACT` below is the contract —
lib/ui/splash_screen.dart plays this file at animation t=0 and lands the logo
tile at the same offset.

    python3 tool/generate_splash_sound.py

Stdlib only. Layers, in the order you hear them:

    0.00s  riser    filtered noise sweeping up      -> anticipation
    0.30s  impact   low sine drop                   -> the tile landing
    0.30s  chime    detuned Cmaj bell partials      -> the brand accent
    0.30s  tail     feedback delay on the chime     -> room, then silence

Tuning it means editing the layer functions and re-running — the .wav is build
output, not a source file. Anything that replaces it has to keep its transient
at IMPACT, or the logo's spring and the hit come apart.
"""

import math
import os
import random
import struct
import wave

SR = 44100
DURATION = 1.30
IMPACT = 0.30  # keep in sync with _kImpact in lib/ui/splash_screen.dart

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx", "splash.wav")

N = int(SR * DURATION)


def riser():
    """Noise through a lowpass that opens up, swelling into the impact."""
    rng = random.Random(7)
    out = [0.0] * N
    lp = 0.0
    hp_prev_in = 0.0
    hp_prev_out = 0.0
    for i in range(N):
        t = i / SR
        # Cutoff climbs until the impact, so the noise brightens as it swells.
        openness = min(t / IMPACT, 1.0)
        alpha = 0.015 + 0.42 * openness ** 2
        lp += alpha * (rng.uniform(-1.0, 1.0) - lp)
        # One-pole highpass (~250 Hz) keeps the riser out of the impact's way.
        hp = 0.965 * (hp_prev_out + lp - hp_prev_in)
        hp_prev_in, hp_prev_out = lp, hp
        if t < IMPACT:
            env = (t / IMPACT) ** 2.2
        else:
            env = math.exp(-(t - IMPACT) / 0.055)
        out[i] = hp * env * 0.34
    return out


def impact():
    """Sine dropping 130 -> 48 Hz: the weight under the logo landing."""
    out = [0.0] * N
    phase = 0.0
    for i in range(N):
        t = i / SR - IMPACT
        if t < 0:
            continue
        freq = 48.0 + 82.0 * math.exp(-t / 0.045)
        phase += 2 * math.pi * freq / SR
        attack = min(t / 0.004, 1.0)  # 4 ms ramp, or it clicks
        out[i] = math.sin(phase) * math.exp(-t / 0.115) * attack * 0.52
    return out


# (ratio to C5, amplitude, decay tau, pan) — a Cmaj triad spread over two
# octaves. Alternating pans give the bell some width without a stereo effect.
PARTIALS = [
    (1.0000, 1.00, 0.60, 0.42),   # C5
    (1.2599, 0.62, 0.52, 0.60),   # E5
    (1.4983, 0.70, 0.48, 0.38),   # G5
    (2.0000, 0.46, 0.38, 0.64),   # C6
    (2.5198, 0.26, 0.30, 0.34),   # E6
    (3.0000, 0.18, 0.24, 0.66),   # G6
    (4.0000, 0.09, 0.16, 0.50),   # C7 — just the strike's sparkle
]
ROOT = 523.25  # C5


def chime():
    """Bell partials, returned pre-panned as (left, right)."""
    left = [0.0] * N
    right = [0.0] * N
    for index, (ratio, amp, tau, pan) in enumerate(PARTIALS):
        # A couple of cents of detune per partial stops it sounding synthetic.
        freq = ROOT * ratio * (2 ** (((index % 2) * 2 - 1) * 2.5 / 1200))
        start = int(SR * IMPACT)
        for i in range(start, N):
            t = (i - start) / SR
            attack = min(t / 0.003, 1.0)
            v = math.sin(2 * math.pi * freq * t) * math.exp(-t / tau) * attack * amp * 0.20
            left[i] += v * (1.0 - pan)
            right[i] += v * pan
    return left, right


def tail(left, right):
    """Three delay taps — a hint of room so the chime dissolves, not stops."""
    for tap in range(1, 4):
        delay = int(SR * 0.085 * tap)
        gain = 0.40 ** tap
        # Taps cross channels, which widens the tail as it fades.
        for i in range(delay, N):
            left[i] += right[i - delay] * gain
            right[i] += left[i - delay] * gain * 0.9
    return left, right


def main():
    mono = riser()
    low = impact()
    left, right = tail(*chime())
    for i in range(N):
        shared = mono[i] + low[i]
        left[i] += shared
        right[i] += shared

    peak = max(max(abs(v) for v in left), max(abs(v) for v in right)) or 1.0
    gain = 0.89 / peak  # ≈ -1 dBFS; leaves headroom for lossy re-encodes
    fade_in = int(SR * 0.005)
    fade_out = int(SR * 0.12)
    frames = bytearray()
    for i in range(N):
        env = 1.0
        if i < fade_in:
            env = i / fade_in
        elif i > N - fade_out:
            env = 0.5 * (1 + math.cos(math.pi * (i - (N - fade_out)) / fade_out))
        for channel in (left, right):
            sample = int(max(-1.0, min(1.0, channel[i] * gain * env)) * 32767)
            frames += struct.pack("<h", sample)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with wave.open(OUT, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(bytes(frames))
    print(f"wrote {OUT} ({len(frames) / 1024:.0f} KiB, {DURATION:.2f}s)")


if __name__ == "__main__":
    main()
