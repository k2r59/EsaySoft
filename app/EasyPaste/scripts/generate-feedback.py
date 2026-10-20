#!/usr/bin/env python3
"""Original, deterministic MIT-licensed UI sounds; no sampled third-party audio."""
import math
import pathlib
import random
import struct
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent / "Sources/EasyPaste/Resources"
RATE = 22050


def write(name, duration, sample):
    random.seed(3701)
    count = round(duration * RATE)
    values = []
    for index in range(count):
        t = index / RATE
        # Short fade-in and tail prevent PCM discontinuities/clicks at boundaries.
        fade = min(1, t / .0015) * min(1, (duration - t) / .012)
        values.append(max(-.6, min(.6, sample(t) * fade)))
    with wave.open(str(ROOT / f"feedback-{name}.wav"), "wb") as output:
        output.setparams((1, 2, RATE, count, "NONE", "not compressed"))
        output.writeframes(b"".join(struct.pack("<h", round(v * 32767)) for v in values))


write("copy", .065, lambda t: .38 * math.exp(-t * 95) *
      (math.sin(2 * math.pi * 1550 * t) + .18 * math.sin(2 * math.pi * 2400 * t)))


def shutter(t):
    first = math.exp(-t * 130)
    second = math.exp(-(t - .055) * 90) if t >= .055 else 0
    return .45 * (first + .65 * second) * random.uniform(-1, 1) + \
        .10 * (first + second) * math.sin(2 * math.pi * 620 * t)


write("capture", .16, shutter)
