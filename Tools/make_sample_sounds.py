#!/usr/bin/env python3
"""Synthesise the sample's sounds.

**The sample has no asset dependency and this keeps it that way.** Its meshes are hand-written OBJ
files and its sounds are generated here — so somebody who clones this repo can build and run it
without downloading anything, which is the whole point of the sample existing.

They are deliberately plain: a rising blip, a small arpeggio, a falling tone. A sample with good
sound design teaches the reader about the sound design.

Run:  python3 Tools/make_sample_sounds.py
Writes Sources/WindageSample/Resources/*.wav.
"""
import math, pathlib, struct, wave

RATE = 44100
OUT = pathlib.Path("Sources/WindageSample/Resources")


def envelope(i, count, attack=0.01, release=0.35):
    """Fade in fast, out slowly. A tone that starts or stops instantly clicks, and the click is
    louder than the note."""
    t = i / RATE
    total = count / RATE
    rise = min(1.0, t / attack) if attack > 0 else 1.0
    fall = min(1.0, max(0.0, (total - t) / release)) if release > 0 else 1.0
    return rise * fall


def tone(frequencies, seconds, gain=0.35, glide=0.0):
    """Sum of sine partials, optionally gliding up or down over the note."""
    count = int(RATE * seconds)
    samples = []
    for i in range(count):
        t = i / RATE
        value = 0.0
        for index, base in enumerate(frequencies):
            frequency = base * (1.0 + glide * t / seconds)
            # Quieter partials as they climb, so a stack of them stays a note rather than a buzz.
            value += math.sin(2 * math.pi * frequency * t) / (index + 1)
        samples.append(value * gain * envelope(i, count) / len(frequencies))
    return samples


def sequence(notes, gain=0.35):
    """Notes played one after another: (frequencies, seconds)."""
    out = []
    for frequencies, seconds in notes:
        out.extend(tone(frequencies, seconds, gain=gain))
    return out


def write(name, samples):
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)          # mono — the engine spatialises it; a stereo file cannot be
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        handle.writeframes(frames)
    print(f"{path}: {len(samples) / RATE:.2f}s")


OUT.mkdir(parents=True, exist_ok=True)

# Picking a crate up: a short rise, so it reads as a gain rather than an event.
write("pickup", tone([660, 1320], 0.18, gain=0.40, glide=0.35))

# All found: a small major arpeggio. Short — it plays once and the run is over.
write("win", sequence([([523], 0.12), ([659], 0.12), ([784], 0.12), ([1047, 1568], 0.45)], gain=0.32))

# Out of time: the same shape falling, and lower.
write("lose", sequence([([311], 0.16), ([262], 0.16), ([196, 98], 0.55)], gain=0.32))
