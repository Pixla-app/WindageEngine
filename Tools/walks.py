#!/usr/bin/env python3
"""Run every walk the handoff documents, and fail on any that no longer does what it was measured doing.

A walk proves a feature once, the day it is measured; after that it is a claim in a document, and a
change to a level can quietly make it false — 0.13.0's slider was put across the walk 0.12.1 was measured
by, and nothing noticed until it was re-run by hand a version later. So the walks are data
(Tools/walks.json) and this runs them all.

Each runs as a check (WINDAGE_SAMPLE_CHECK=<the walk's name>): no window, no keyboard, no sound, and its
own saves, named after the walk and cleared — so it runs while somebody works, a player's rebinding cannot
fail it, and walks running at the same time do not clear each other's settings. **Four at a time**, since
each is a whole game with a Metal device and an environment to build; a walk's result is its step count,
not the clock, so running them together changes nothing but the wall time. The engine keeps time
with the window never shown (FrameRenderer.runsWhileHidden, from its first tick), so a walk takes its own
length and a few seconds to start.

    python3 Tools/walks.py            every walk
    python3 Tools/walks.py piston     the walks whose names contain "piston"
    python3 Tools/walks.py --record   every expectation with what the walk gives now
    python3 Tools/walks.py --serial   one at a time, rather than four at once

A walk may say it is `like` another — same script, same recorded numbers — and change one thing about how
it is run. That is how "crate behind the splash" checks that the engine's splash takes nothing from the
game underneath it: same walk, same numbers, with `WINDAGE_SAMPLE_SPLASH=1`.

A walk may name the step **rates** it has to hold at — the course walk runs at 30, 60, 120 and 240 steps
a second and must give one set of numbers. Its segments are whole steps of the slowest (multiples of
1/30 s), because a key can only be held for a whole number of steps: 0.75 s at thirty a second is 0.733
or 0.767, and 10 cm of walking is the difference.

**A recorded number is changed deliberately, with its reason in the CHANGELOG** — the world the walk goes
through changed, and this is what it does now. `--record` is for reading those off; it writes nothing.
The tolerance is wide enough (2 cm) to let a real change hide, which is the point of looking.

Exit status 0 when every expectation holds, 1 otherwise. Positions are compared to the walk report's two
decimals, so a feet expectation allows the tolerance plus half a centimetre of rounding. Footsteps and
their surfaces must match exactly; the head bob, printed to a millimetre, may differ by one; a landing's
impact, printed to a tenth of a metre a second, by a tenth; the eye's dip, printed in whole centimetres,
not at all.
"""
import json, os, pathlib, re, subprocess, sys, threading, time
from concurrent import futures

ROOT = pathlib.Path(__file__).resolve().parent.parent
SAMPLE = ROOT / ".build/debug/WindageSample"
WALK_LINE = re.compile(r"walk '([^']+)' → feet \(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\), highest ([-0-9.]+)")
LOOK_LINE = re.compile(r"look '([^']+)' → view turned ([-0-9.]+)° right, ([-0-9.]+)° up")


def run(walk, rate=None):
    """The sample's log for one walk: launched as a check, stopped half a second after the last segment
    reports — the lines that follow it (footsteps, a gap) arrive in that time.

    `rate` steps the simulation that often a second instead of the engine's 120 — a walk that declares
    `rates` is run once at each, and every number it records has to hold at all of them."""
    name = re.sub(r"[^a-z]+", "-", walk["name"]) + (f"-{rate:g}" if rate else "")
    env = dict(os.environ, WINDAGE_SAMPLE_CHECK=name,
               WINDAGE_SAMPLE_LEVEL=str(walk["level"]), WINDAGE_SAMPLE_WALK=walk["script"])
    if rate:
        env["WINDAGE_SAMPLE_RATE"] = f"{rate:g}"
    if walk.get("splash"):
        env["WINDAGE_SAMPLE_SPLASH"] = "1"
    tokens = walk["script"].split()
    last, times = f"walk '{tokens[-1]}'", tokens.count(tokens[-1])   # a label can come more than once
    seconds = sum(float(t.split(":")[1]) for t in walk["script"].split()
                  if not t.startswith(("yaw:", "pitch:", "mousex:", "mousey:")))
    process = subprocess.Popen([str(SAMPLE)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines = []
    reader = threading.Thread(target=lambda: lines.extend(iter(process.stdout.readline, "")), daemon=True)
    reader.start()
    deadline, finished = time.time() + seconds + 30, None
    while time.time() < deadline:
        if finished is None and sum(last in l for l in list(lines)) >= times:
            finished = time.time()
        if finished is not None and time.time() > finished + 0.5:
            break
        time.sleep(0.05)
    process.kill()
    process.wait()
    return [l.rstrip("\n") for l in lines]


def check(walk, lines, tolerance):
    """Each expectation against the log: what it wanted, what it got, and whether that holds."""
    results = []
    # Each segment's report, and the indented lines that follow it: footsteps, surfaces, the head bob.
    segments = []
    for l in lines:
        m = WALK_LINE.search(l)
        if m:
            segments.append((m.group(1), [float(m.group(i)) for i in (2, 3, 4)], float(m.group(5)), []))
        elif segments and l.startswith("WindageSample:     "):
            segments[-1][3].append(l)
    # The view's turns, which a segment reports only when it turned at all: a stick inside its dead zone
    # says nothing, and nothing is what `[0, 0]` expects.
    looks = [(m.group(1), [float(m.group(2)), float(m.group(3))])
             for m in (LOOK_LINE.search(l) for l in lines) if m]
    for want in walk["expect"]:
        if "look" in want:
            hits = [l for l in looks if l[0] == want["look"]]
            n = want.get("occurrence", 1)
            turned = hits[n - 1][1] if len(hits) >= n else [0.0, 0.0]
            # Degrees, recorded to the hundredth: a hundredth either way is the rounding.
            ok = all(abs(a - b) <= 0.01 + 1e-6 for a, b in zip(turned, want["turned"]))
            results.append((f"the view turned, '{want['look']}'", want["turned"], turned, ok))
        elif "after" in want:
            hits = [s for s in segments if s[0] == want["after"]]
            n = want.get("occurrence", len(hits) if want.get("last") else 1)
            got = hits[n - 1] if len(hits) >= n else None
            if "feet" in want:
                ok = got is not None and all(abs(a - b) <= tolerance + 0.005 for a, b in zip(got[1], want["feet"]))
                results.append((f"feet after '{want['after']}'" + (f" #{n}" if "occurrence" in want else ""),
                                want["feet"], got[1] if got else None, ok))
            if "highest" in want:
                ok = got is not None and abs(got[2] - want["highest"]) <= tolerance + 0.005
                results.append((f"highest in '{want['after']}' #{n}", want["highest"], got[2] if got else None, ok))
            heard = "\n".join(got[3]) if got else ""
            where = f"'{want['after']}'" + (f" #{n}" if "occurrence" in want else "")
            if "footsteps" in want:
                m = re.search(r"(\d+) footsteps?", heard)
                count = int(m.group(1)) if m else None
                results.append((f"footsteps in {where}", want["footsteps"], count, count == want["footsteps"]))
            if "on" in want:
                m = re.search(r"footsteps? on ([a-z ]+?)(?:,|$)", heard, re.M)
                surfaces = sorted(m.group(1).split(" and ")) if m else []
                results.append((f"surfaces in {where}", sorted(want["on"]), surfaces, surfaces == sorted(want["on"])))
            if "landed" in want:
                # Printed to a tenth of a metre a second; a tenth either way is the rounding.
                m = re.search(r"landed at ([0-9.]+) m/s", heard)
                speed = float(m.group(1)) if m else None
                ok = speed is not None and abs(speed - want["landed"]) <= 0.05 + 1e-6
                results.append((f"landed at, {where}", want["landed"], speed, ok))
            if "dip" in want:
                m = re.search(r"eye dipped ([0-9]+) cm", heard)
                dip = int(m.group(1)) if m else None
                results.append((f"the eye's dip in {where}, cm", want["dip"], dip, dip == want["dip"]))
            if "bob" in want:
                # Printed to a millimetre, so a millimetre either way is the rounding, not a change.
                m = re.search(r"head bob ([0-9.]+) cm up and down, ([0-9.]+) cm side to side", heard)
                bob = [float(m.group(1)), float(m.group(2))] if m else ([0.0, 0.0] if "no head bob" in heard else None)
                ok = bob is not None and all(abs(a - b) <= 0.1 + 1e-6 for a, b in zip(bob, want["bob"]))
                results.append((f"head bob in {where}, cm", want["bob"], bob, ok))
        elif "line" in want:
            hits = [l for l in lines if want["line"] in l]
            line = (hits[-1] if want.get("last") else hits[0]) if hits else None
            m = re.search(want["pattern"], line) if line else None
            value = float(m.group(1)) if m else None
            ok = value is not None and abs(value - want["value"]) <= tolerance
            results.append((f"'{want['line']}'", want["value"], value, ok))
    return results


def main():
    spec = json.loads((ROOT / "Tools/walks.json").read_text())
    # A walk may say it is `like` another: same level, same script, same expectations, changing only
    # what it declares itself. One set of numbers, so the two cannot be corrected apart.
    by_name = {w["name"]: w for w in spec["walks"]}
    for walk in spec["walks"]:
        if "like" in walk:
            for key, value in by_name[walk["like"]].items():
                walk.setdefault(key, value)
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    recording = "--record" in sys.argv
    walks = [w for w in spec["walks"] if not names or any(n in w["name"] for n in names)]
    built = subprocess.run(["swift", "build", "--product", "WindageSample"], cwd=ROOT, capture_output=True, text=True)
    if built.returncode != 0:
        print(built.stdout[-2000:], built.stderr[-2000:])
        return 1
    # A walk that names `rates` is one job per rate, each having to give the same recorded numbers.
    jobs = [(w, r) for w in walks for r in (w.get("rates") or [None])]

    def walked(job):
        walk, rate = job
        started = time.time()
        results = check(walk, run(walk, rate), spec["tolerance"])
        return walk, rate, results, time.time() - started

    started = time.time()
    if "--serial" in sys.argv:
        done = [walked(j) for j in jobs]
    else:
        # Four: each walk is a whole game, and this machine has other work to do.
        with futures.ThreadPoolExecutor(max_workers=4) as pool:
            done = list(pool.map(walked, jobs))

    failed = 0
    for walk, rate, results, took in done:
        bad = [r for r in results if not r[3]]
        failed += bool(bad)
        label = walk["name"] + (f" @{rate:g}/s" if rate else "")
        print(f"{'ok  ' if not bad else 'FAIL'} {label:<16} {len(results) - len(bad)}/{len(results)}"
              f"  ({took:.1f} s; recorded {walk['recorded']})")
        for what, wanted, got, ok in results:
            if not ok or recording:
                print(f"    {'   ' if ok else '!! '}{what}: recorded {wanted}, now {got}")
    print(f"{len(jobs) - failed} of {len(jobs)} runs as recorded, in {time.time() - started:.0f} s")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
