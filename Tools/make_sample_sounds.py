#!/usr/bin/env python3
"""Synthesise the sample's sounds.

**The sample has no asset dependency and this keeps it that way.** Its meshes are hand-written OBJ
files and its sounds are generated here — so somebody who clones this repo can build and run it
without downloading anything, which is the whole point of the sample existing.

They are deliberately plain: a rising blip, a small arpeggio, a falling tone, and footsteps made of
filtered noise. A sample with good sound design teaches the reader about the sound design.

Run:  python3 Tools/make_sample_sounds.py
Writes Sources/WindageSample/Resources/*.wav.
"""
import math, pathlib, random, struct, wave

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


# --- Footsteps -------------------------------------------------------------------------------------
#
# **Three of each, because one repeated is a machine gun.** The ear hears an identical sample
# played twice a second as a mechanism, not as feet; three that differ slightly, played in an order
# that does not repeat every three, is enough to stop it. Seeded, so running this again writes the
# same files and the diff is empty.

def lowpass(samples, cutoff):
    """One pole. `cutoff` in Hz."""
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def bandpass(samples, low, high):
    """The difference of two low-passes: crude, and enough for a scuff."""
    return [h - l for h, l in zip(lowpass(samples, high), lowpass(samples, low))]


def footfall(seed, seconds, thump_hz, thump_gain, noise_low, noise_high, noise_gain, decay, peak):
    """A thump — the heel — and a burst of filtered noise — the sole on the surface.

    **Normalised to `peak`, not scaled by a gain.** The first pass multiplied its way to the level
    and clipped the landings and every stone step — a clipped footstep is a click with a sound
    attached, and the click is what the ear hears."""
    rng = random.Random(seed)
    count = int(RATE * seconds)
    # Filtered twice: a one-pole filter leaks everything above its cutoff at 6 dB an octave, and
    # dirt filtered once still hissed like gravel.
    noise = bandpass([rng.uniform(-1, 1) for _ in range(count)], noise_low, noise_high)
    noise = lowpass(noise, noise_high)
    wobble = 1 + rng.uniform(-0.08, 0.08)          # no two heels the same pitch
    out = []
    for i in range(count):
        t = i / RATE
        body = math.exp(-t / decay)
        heel = math.sin(2 * math.pi * thump_hz * wobble * t) * math.exp(-t / (decay * 0.6))
        # A 2 ms rise: an instant start clicks, and the click is louder than the step.
        rise = min(1.0, t / 0.002)
        out.append(rise * (heel * thump_gain + noise[i] * noise_gain * body))
    loudest = max(abs(v) for v in out) or 1
    return [v * peak / loudest for v in out]


# Dirt: muffled, a soft low heel and a dull crunch. Stone: a harder heel and a bright scuff.
for n in range(3):
    write(f"step_dirt_{n}", footfall(100 + n, 0.16, 85, 0.9, 250, 1100, 5.0, 0.045, 0.6))
    write(f"step_stone_{n}", footfall(200 + n, 0.14, 140, 0.7, 1500, 6000, 3.4, 0.028, 0.6))

# Landings: the same surfaces, heavier, longer, and lower.
write("land_dirt", footfall(300, 0.32, 55, 1.2, 200, 900, 5.0, 0.09, 0.8))
write("land_stone", footfall(400, 0.28, 90, 1.0, 1200, 5500, 3.6, 0.06, 0.8))


def ringing(samples, hz, gain, decay, seed):
    """A resonance under a footfall: a board's hollow note, a plate's ring. **Added, not the whole
    sound** — a foot on wood is still a foot, and a pure tone on its own reads as a bell."""
    wobble = 1 + random.Random(seed).uniform(-0.05, 0.05)
    out = [v + gain * math.sin(2 * math.pi * hz * wobble * i / RATE) * math.exp(-(i / RATE) / decay)
           for i, v in enumerate(samples)]
    loudest = max(abs(v) for v in out) or 1
    peak = max(abs(v) for v in samples) or 1
    return [v * peak / loudest for v in out]


# Wood — the ruins' landing: a hollow board, the heel lower and longer than stone, the scuff in the
# middle of the range, and a short boom under it. Metal — a brazier someone jumped onto: a hard heel,
# a bright scrape, and a ring that outlasts the step.
for n in range(3):
    write(f"step_wood_{n}", ringing(footfall(500 + n, 0.18, 110, 1.0, 500, 2600, 2.6, 0.04, 0.6), 190, 0.5, 0.06, 510 + n))
    write(f"step_metal_{n}", ringing(footfall(600 + n, 0.22, 160, 0.6, 2500, 8000, 2.0, 0.03, 0.6), 620, 0.35, 0.12, 610 + n))
write("land_wood", ringing(footfall(700, 0.34, 80, 1.2, 400, 2200, 3.0, 0.08, 0.8), 150, 0.6, 0.1, 710))
write("land_metal", ringing(footfall(800, 0.36, 120, 0.9, 2000, 7000, 2.4, 0.06, 0.8), 540, 0.5, 0.2, 810))
