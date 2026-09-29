#!/usr/bin/env python3
"""
Dev tooling: synthesises the tiny UI sounds shipped with the Referral System.

Pure standard-library (wave + math), mono 22050 Hz 16-bit, short and quiet so
they work as micro-interaction feedback without being annoying.
"""
import math
import os
import struct
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "referral_system", "assets", "sounds")
RATE = 22050


def envelope(i, n, attack=0.01, release=0.35):
    t = i / float(n)
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (1.0 - t) / release)
    return max(0.0, min(a, r))


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples)
        w.writeframes(frames)
    print("%-14s %6d bytes" % (name, os.path.getsize(path)))


def tone(freq, dur, gain=1.0, glide_to=None, attack=0.008, release=0.4):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        f = freq if glide_to is None else freq + (glide_to - freq) * (i / float(n))
        out.append(gain * envelope(i, n, attack, release) * math.sin(2 * math.pi * f * i / RATE))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def copy_sound():
    # soft two-step blip: "click" then confirmation
    return mix(tone(1180, 0.055, 0.55, glide_to=940),
               [0.0] * int(RATE * 0.045) + tone(1560, 0.075, 0.5, glide_to=1320))


def reward_sound():
    # rising major arpeggio, gentle
    seq = [523.25, 659.25, 783.99, 1046.5]
    tracks = []
    for i, f in enumerate(seq):
        pad = [0.0] * int(RATE * 0.075 * i)
        tracks.append(pad + tone(f, 0.30, 0.45, attack=0.006, release=0.55))
    return mix(*tracks)


def error_sound():
    return mix(tone(320, 0.13, 0.5, glide_to=220), tone(240, 0.16, 0.32, glide_to=170))


def open_sound():
    return tone(520, 0.14, 0.35, glide_to=880, attack=0.01, release=0.6)


if __name__ == "__main__":
    write_wav("copy.wav", copy_sound())
    write_wav("reward.wav", reward_sound())
    write_wav("error.wav", error_sound())
    write_wav("open.wav", open_sound())
