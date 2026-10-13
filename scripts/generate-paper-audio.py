#!/usr/bin/env python3
"""Generate Lantern's original, deterministic mono paper-friction samples (MIT)."""
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parent.parent
RATE = 22050


def generate(name, duration, seed):
    rng = random.Random(seed)
    low = 0.0
    samples = []
    count = round(RATE * duration)
    for index in range(count):
        t = index / count
        noise = rng.uniform(-1, 1)
        low = 0.82 * low + 0.18 * noise
        # Soft friction, gently varying pressure, no impact or reverberation.
        envelope = math.sin(math.pi * t) ** 1.5
        pressure = 0.65 + 0.35 * math.sin(2 * math.pi * (3 * t + t * t)) ** 2
        value = (0.7 * low + 0.12 * noise) * envelope * pressure * 0.4
        samples.append(struct.pack("<h", round(value * 32767)))
    with wave.open(str(ROOT / "assets" / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(samples))


if __name__ == "__main__":
    generate("paper-map-open.wav", 0.420, 18273)
    generate("paper-map-close.wav", 0.320, 18274)
