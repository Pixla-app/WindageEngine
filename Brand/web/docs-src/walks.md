---
title: Scripted walks
description: Play the sample by script — keys, seconds and pad buttons — read where the feet ended up, and check every recorded walk with Tools/walks.py.
---
A scripted walk plays the game from a line of keys and seconds and logs where the feet were at the end of each segment. Unlike "it felt right on the stairs", anyone can repeat it, and `Tools/walks.py` turns the walks into a check that fails when a change moves where they end.

> **This is the sample's tooling, not engine API.** The script reader, the log line and `Tools/walks.py` belong to `WindageSample`. The engine provides the pieces they are built from, listed [at the end](#your-game), and a game that wants the same check builds its own reader on top of them.

## The script {#syntax}

Set `WINDAGE_SAMPLE_WALK` to segments separated by spaces. Each segment is `keys:seconds`:

```sh
WINDAGE_SAMPLE_LEVEL=1 \
WINDAGE_SAMPLE_WALK="wait:0.5 d:0.75 wait:0.5 w:1.0 wait:0.6" swift run WindageSample
```

| Segment | What it does |
| --- | --- |
| `w:1.0` | holds W for one second, then releases it |
| `w+shift:0.8` | holds several keys at once, joined with `+` |
| `space:0.05` | any name `KeyCode(named:)` knows: letters, `space`, `shift`, `up`, `down`, `left`, `right` |
| `wait:1.2` | holds nothing |
| `click:0.1` | starts with a mouse click |
| `yaw:90`, `pitch:-40` | turns the view to that many degrees, and takes no time |
| `mousex:500`, `mousey:-80` | moves the mouse that many points, through the real mouse path |
| `pad.south:0.1` | presses a controller element |
| `pad.lookRight@0.2:1` | holds a stick a fifth of the way over |

The pad elements are `south`, `east`, `west`, `north`, `leftShoulder`, `rightShoulder`, `leftStick`, `rightStick` and `menu`. The d-pad is `up`, `down`, `left` and `right`, the look stick is `lookUp`, `lookDown`, `lookLeft` and `lookRight`, and the move stick is `moveUp`, `moveDown`, `moveLeft` and `moveRight`. A script that names any of them gets a virtual pad for its whole run.

**The keys go through the game, not around it**: the same `keyPressed` a keyboard calls, so the bindings, the settings screen and the editor all see them.

**Segments are whole simulation steps.** Each boundary is measured from the start of the script and lands on the nearest step, so roundings can't add up over a long script. A walk that must hold at several step rates uses whole steps of the slowest one, which means multiples of 1/30 s.

## The log {#log}

When a segment ends, the sample prints where the feet are, the highest they got during the segment, whether they're on the ground, and how high the eye is above them. Indented lines after it describe the same segment. Here is the walk above going up the ruins' stairs:

```log
WindageSample: walk 'w:1.0' → feet (4.50, 1.20, -0.00), highest 1.20, on the ground, eye 1.69 m up
WindageSample:     4 footsteps on dirt and stone and wood
WindageSample:     lift top 0.75 m, feet at 1.20 m
WindageSample:     head bob 2.7 cm up and down, 1.7 cm side to side
```

The indented lines can also report a landing's impact speed and how far the eye dipped. A segment that turned the view prints `look '…' → view turned …° right, …° up`.

## Checking every walk {#check}

`Tools/walks.json` lists the walks the README and the handoff document, each with what it measured. `Tools/walks.py` runs them all:

```sh
python3 Tools/walks.py            # every walk
python3 Tools/walks.py piston     # the walks whose names contain "piston"
python3 Tools/walks.py --record   # print what each walk gives now; writes nothing
python3 Tools/walks.py --serial   # one at a time
```

Each walk runs as a check (`WINDAGE_SAMPLE_CHECK=<name>`), with no window, no keyboard, no sound and its own saves, so it runs while you work and a player's rebinding can't make it fail. Four run at a time. A result depends on the step count, not the clock, so running them together only changes how long the run takes.

A walk entry names its `level` and `script`, and each item under `expect` says which segment it checks (`after`, with an optional `occurrence`) and what to compare:

- `feet` and `highest` must be within the file's `tolerance` of **2 cm**, plus half a centimeter for the log's rounding.
- `footsteps` and the surfaces they were `on` must match exactly.
- `bob` may differ by a millimeter, a `landed` speed by a tenth of a meter per second, and the eye's `dip` not at all.
- `look` checks a view turn, and `line` matches any log line with a regular expression.

2 cm is wide enough for a real change to hide in, so `--record` is there for looking. **A recorded number changes only on purpose, with its reason in the CHANGELOG.**

`like` reuses another walk's script and expectations. "crate behind the splash" uses it to check that the engine's [splash](splash.html) takes nothing from the walk underneath. `rates` runs a walk at several step rates (`WINDAGE_SAMPLE_RATE`). The course walk runs at 30, 60, 120 and 240 steps a second and must give the same numbers at each.

## The same approach in your game {#your-game}

The engine does not ship a script reader. These are the parts the sample's is built on, and each one is public:

- **`KeyCode(named:)`** turns `"W"`, `"space"` or `"shift"` into a key code. Feed the codes through your own key handling, then `InputState.keyDown(_:)` and `keyUp(_:)`.
- **`InputState.useGamepad(_:)`** reads a pad you supply. `GCController.withExtendedGamepad()` makes one whose buttons are set from code. Push its d-pad through `setValueForXAxis(_:yAxis:)`, because setting `dpad.down` as a button is accepted and does nothing.
- **`FrameRenderer.runsWhileHidden`** keeps the [simulation stepping](running-hidden.html) with the window never shown, so a check runs out of the way.
- **`FrameRenderer(device:simulationStepsPerSecond:)`** sets the [step rate](fixed-timestep.html). The fixed timestep is what makes the same keys reach the same place.
- **`CharacterController`** exposes `feet`, `eye`, `isGrounded`, `events` and `groundSolid`, which is everything the log line reports.

The rest is your game's: parse the segments, press and release on the step boundaries, and print what the body did. The sample's `ScriptedWalk`, in `Sources/WindageSample/SampleGame.swift`, is one way to write it.
