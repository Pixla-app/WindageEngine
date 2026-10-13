---
title: Recorded frames
description: Draw a frame with no window using FrameRenderer.render(into:), and compare it pixel by pixel against a recorded one with Tools/frames.py.
---
A renderer can only be judged by looking at it, and a screenshot someone looked at once protects nothing afterwards. `FrameRenderer.render(into:)` draws a frame into a texture of your own, with no window. The sample's `Tools/frames.py` uses it to draw a set of recorded viewpoints and compare each one, pixel by pixel, against the frame kept for it. That makes shadows, the tone map and the lights something a check can fail on.

## Drawing a frame into a texture {#render-into}

```swift
public func render(into texture: MTLTexture, interpolation: Float = 0)
```

It runs the same passes in the same order as a displayed frame: the pre-passes, the scene into its HDR target, then the tone map and the interface. What comes out is what a player would have seen. It **waits for the GPU** before returning, so you can read the texture straight away.

The texture needs `FrameRenderer.colorPixelFormat` and `.renderTarget`. To read it back, it also needs shared or managed storage, and like everything else the GPU reads, it has to be in the residency set. This is the sample's version, trimmed:

```swift
let width = 640, height = 400
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: FrameRenderer.colorPixelFormat, width: width, height: height, mipmapped: false)
descriptor.usage = [.renderTarget, .shaderRead]
descriptor.storageMode = .shared
guard let texture = engine.device.makeTexture(descriptor: descriptor) else { return false }
engine.residencySet.addAllocation(texture)
engine.commitResidency()
viewportSizeChanged(width: width, height: height)
engine.render(into: texture)

var bgra = [UInt8](repeating: 0, count: width * height * 4)
bgra.withUnsafeMutableBytes {
    texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
}
```

The bytes are BGRA. The sample swaps them to RGBA and writes a PNG with `NSBitmapImageRep`. Comparing frames is only one use: a thumbnail or a photo a game saves also wants the frame the game draws, without a drawable to draw it into.

## The same picture every time {#deterministic}

A comparison only means something if both runs draw the **same** frame. The sample makes sure of that through environment variables:

- `WINDAGE_SAMPLE_FRAME=<path>` draws one frame to a PNG and quits. The window is never shown, and nothing has been simulated yet, so the clock is full, no crate has been collected, and the lifts and turntable are where the level puts them.
- `WINDAGE_SAMPLE_LEVEL` and `WINDAGE_SAMPLE_CAMERA=x,y,z,yaw,pitch` choose the viewpoint, with angles in degrees. A camera placed this way flies, because a body under a raised camera would fall to the ground before the first frame.
- The engine's [splash](splash.html) is off for these frames unless one asks for it, because a splash over every frame would test the splash and never the scene.

```sh
WINDAGE_SAMPLE_CHECK=frame-courtyard WINDAGE_SAMPLE_FRAME=/tmp/courtyard.png \
WINDAGE_SAMPLE_LEVEL=0 WINDAGE_SAMPLE_CAMERA="0,2.5,11,0,-12" swift run WindageSample
```

## Checking every frame {#check}

`Tools/frames.json` lists the viewpoints: the ruins from above, the lintel at eye height, the courtyard, the turntable, and the splash. Each has a `level`, a `camera` and a `shows` line saying what it is there to guard. The recorded frames are in `Tools/frames/`.

```sh
python3 Tools/frames.py            # draw every frame and compare
python3 Tools/frames.py ruins      # the frames whose names contain "ruins"
python3 Tools/frames.py --record   # draw them and write them in as the recorded frames
```

**A frame fails when more than 0.5% of its pixels differ by more than 5 in any channel.** That allows a GPU its last bit but doesn't let a shadow move. A frame can set a tighter `tolerance` of its own, and the splash has to. It is a small flat drawing, where moving the mark's curve by 4% of its height changes a quarter of a percent of the frame. That is well inside the scene's half percent, so the splash checks with a channel tolerance of 2 and no differing pixels at all.

After `--record`, **look at the new frames before committing them.** A recorded frame should change when the renderer changes, and the reason goes in the CHANGELOG. What the record guards is that someone looked.

## Every shadow was a frame stale {#stale-shadows}

The first frame drawn this way found a bug that had been there all along. **Metal 4 tracks no hazards between passes.** The scene pass sampled shadow maps that an earlier pass in the same command buffer was still writing, and nothing told the GPU to wait.

In play it looked right, because the previous frame's shadow maps were there to sample. Every shadow was simply one frame stale. The very first frame had nothing in those maps yet, and it came out differently on every run: once as a black scene, once blotched in cluster-sized squares. Two consumer barriers fixed it, one making the scene wait for the shadows and one making the tone map wait for the scene. Since then, four runs of the same frame produce the same bytes. A game can't see this bug, and a test that draws no pixels can't either. A frame drawn twice and compared shows it.

## A check is only a check if it fails {#fails}

Each frame was tested against a deliberate break. Switching the sample's tone map from ACES to Reinhard fails all four scene frames, with 98% of pixels changed. Drawing nothing into the sun's shadow maps fails all four too, with 5.5 to 7.6% of the courtyard changed. Two other changes moved nothing, and a change that moves nothing proves nothing. One was `ToneMapping`'s default curve, which the sample overrides. The other was the constant depth bias at 25 times its value, too small to see against a cascade's depth range.

The engine runs three checks on itself before a change is called done: `swift test`, [the walks](walks.html) and these frames. Your game can use the same approach with its own viewpoints. `render(into:)` is the engine's part. `Tools/frames.py` is the sample's, and is plain Python with no dependencies to copy from.
