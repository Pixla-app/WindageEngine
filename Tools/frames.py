#!/usr/bin/env python3
"""Draw the sample's recorded viewpoints and compare each against the frame recorded for it.

**A renderer can only be judged by looking at it** — which is why every capability here was judged by a
screenshot, and why nothing guarded any of them: `swift test` draws no pixel, and the walk check draws
none either. This draws them, with no window and nobody watching, and compares.

    python3 Tools/frames.py            every frame
    python3 Tools/frames.py ruins      the frames whose names contain "ruins"
    python3 Tools/frames.py --record   draw them and write them in as the recorded frames

**A recorded frame changes only with a reason in the CHANGELOG.** The picture is meant to change when the
renderer changes; the point of keeping it is that somebody looked at the new one and said so.

A frame is drawn before any simulation step, with the check's own saves, so it is the same picture every
time: the clock full, no crate collected, the lifts and turntable where the level puts them. Two frames
are the same if no more than `pixels` of them differ by more than `channel` in any channel (the numbers
are in Tools/frames.json) — a GPU is allowed its last bit, but not a shadow.
"""
import json, os, pathlib, re, subprocess, sys, zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SAMPLE = ROOT / ".build/debug/WindageSample"
RECORDED = ROOT / "Tools/frames"


def read_png(path):
    """Width, height and RGBA bytes. Ours are 8-bit RGBA and not interlaced; anything else is refused."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    at, width, height, pixels = 8, 0, 0, b""
    while at < len(data):
        length = int.from_bytes(data[at:at + 4], "big")
        kind = data[at + 4:at + 8]
        chunk = data[at + 8:at + 8 + length]
        if kind == b"IHDR":
            width, height = int.from_bytes(chunk[:4], "big"), int.from_bytes(chunk[4:8], "big")
            assert chunk[8] == 8 and chunk[9] == 6 and chunk[12] == 0, f"{path}: not plain 8-bit RGBA"
        elif kind == b"IDAT":
            pixels += chunk
        at += length + 12
    raw = zlib.decompress(pixels)
    out = bytearray(width * height * 4)
    stride, previous = width * 4, bytearray(width * 4)
    for y in range(height):
        filter_kind = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            left = row[x - 4] if x >= 4 else 0
            up = previous[x]
            corner = previous[x - 4] if x >= 4 else 0
            if filter_kind == 1: row[x] = (row[x] + left) & 0xFF
            elif filter_kind == 2: row[x] = (row[x] + up) & 0xFF
            elif filter_kind == 3: row[x] = (row[x] + (left + up) // 2) & 0xFF
            elif filter_kind == 4:
                estimate = left + up - corner
                dl, du, dc = abs(estimate - left), abs(estimate - up), abs(estimate - corner)
                nearest = left if dl <= du and dl <= dc else (up if du <= dc else corner)
                row[x] = (row[x] + nearest) & 0xFF
        out[y * stride:(y + 1) * stride] = row
        previous = row
    return width, height, bytes(out)


def draw(frame, path):
    """Draws one viewpoint into `path`. Returns what the sample said if it failed."""
    env = dict(os.environ,
               WINDAGE_SAMPLE_CHECK="frame-" + re.sub(r"[^a-z]+", "-", frame["name"]),
               WINDAGE_SAMPLE_FRAME=str(path),
               WINDAGE_SAMPLE_LEVEL=str(frame["level"]),
               WINDAGE_SAMPLE_CAMERA=frame["camera"])
    done = subprocess.run([str(SAMPLE)], env=env, capture_output=True, text=True, timeout=120)
    return None if done.returncode == 0 and path.exists() else (done.stdout + done.stderr)[-400:]


def compare(drawn, recorded, channel):
    """How many pixels differ by more than `channel`, and the worst difference of all."""
    width, height, mine = read_png(drawn)
    theirWidth, theirHeight, theirs = read_png(recorded)
    if (width, height) != (theirWidth, theirHeight):
        return None, f"{width}×{height} against the recorded {theirWidth}×{theirHeight}"
    differing, worst = 0, 0
    for i in range(0, len(mine), 4):
        for c in range(3):
            gap = abs(mine[i + c] - theirs[i + c])
            worst = max(worst, gap)
            if gap > channel:
                differing += 1
                break
    return (differing / (width * height), worst), None


def main():
    spec = json.loads((ROOT / "Tools/frames.json").read_text())
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    recording = "--record" in sys.argv
    frames = [f for f in spec["frames"] if not names or any(n in f["name"] for n in names)]
    built = subprocess.run(["swift", "build", "--product", "WindageSample"], cwd=ROOT, capture_output=True, text=True)
    if built.returncode != 0:
        print(built.stdout[-2000:], built.stderr[-2000:])
        return 1
    RECORDED.mkdir(exist_ok=True)
    failed = 0
    for frame in frames:
        recorded = RECORDED / f"{frame['name']}.png"
        drawn = recorded if recording else pathlib.Path(f"/tmp/windage-frame-{frame['name']}.png")
        trouble = draw(frame, drawn)
        if trouble:
            print(f"FAIL {frame['name']:<20} could not be drawn: {trouble}")
            failed += 1
            continue
        if recording:
            print(f"drew {frame['name']:<20} {frame['shows']}")
            continue
        if not recorded.exists():
            print(f"FAIL {frame['name']:<20} has no recorded frame — draw one with --record and look at it")
            failed += 1
            continue
        measured, trouble = compare(drawn, recorded, spec["tolerance"]["channel"])
        if trouble:
            print(f"FAIL {frame['name']:<20} {trouble}")
            failed += 1
            continue
        share, worst = measured
        ok = share <= spec["tolerance"]["pixels"]
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {frame['name']:<20} {share * 100:5.2f}% of pixels differ"
              f" (worst channel {worst}); {frame['shows']}")
        if not ok:
            print(f"       drawn: {drawn}")
    if recording:
        print(f"{len(frames)} frames written to Tools/frames — look at them before committing")
        return 0
    print(f"{len(frames) - failed} of {len(frames)} frames as recorded")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
