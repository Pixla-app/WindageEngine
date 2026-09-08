//
//  main.swift
//  WindageSample
//
//  **A plain SwiftPM executable, on purpose.** `swift run WindageSample` and it opens — no Xcode
//  project, no scheme, no signing. That is how somebody who just cloned this repo will first try to
//  run it, and if that does not work the engine is not something other people can build with.
//

import AppKit
import MetalKit
import WindageEngine

/// The window's view: hands keyboard and mouse to `InputState` and the drawable to `FrameRenderer`.
///
/// The engine deliberately owns none of this. A window, a responder chain and a capture policy are
/// decisions an application makes, and an engine that made them for you would be a framework.
final class SampleView: MTKView {
    weak var game: SampleGame?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { game?.input.setMouseCaptured(false); return }   // esc releases
        game?.input.keyDown(event.keyCode)
    }
    override func keyUp(with event: NSEvent) { game?.input.keyUp(event.keyCode) }

    override func mouseDown(with event: NSEvent) { game?.input.setMouseCaptured(true) }
    override func mouseMoved(with event: NSEvent) { deliver(event) }
    override func mouseDragged(with event: NSEvent) { deliver(event) }

    private func deliver(_ event: NSEvent) {
        game?.input.addMouseDelta(x: Float(event.deltaX), y: Float(event.deltaY))
    }
}

// **Unbuffered, so `swift run WindageSample | tee log` shows anything at all.** Swift's `print`
// goes to a fully-buffered stdout when it is not a terminal, and a sample whose diagnostics vanish
// the moment you pipe it is a sample that cannot be debugged by the person trying to learn from it.
setbuf(stdout, nil)

let application = NSApplication.shared
application.setActivationPolicy(.regular)

guard let device = MTLCreateSystemDefaultDevice() else {
    print("WindageSample: no Metal device")
    exit(1)
}

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                      styleMask: [.titled, .closable, .resizable, .miniaturizable],
                      backing: .buffered, defer: false)
window.title = "\(Engine.name) \(Engine.version) — sample"
window.center()
window.acceptsMouseMovedEvents = true

guard let engine = FrameRenderer(device: device) else {
    print("WindageSample: this GPU does not support Metal 4")
    exit(1)
}

let view = SampleView(frame: window.contentLayoutRect, device: device)
view.colorPixelFormat = FrameRenderer.colorPixelFormat
view.depthStencilPixelFormat = FrameRenderer.depthPixelFormat
// **The view hosts the layer; it does not drive frames.** `CAMetalDisplayLink` does, and leaving
// MetalKit's own timer running as well would ask for two frames' worth of work per frame.
view.isPaused = true
view.enableSetNeedsDisplay = false
window.contentView = view

guard let game = SampleGame(engine: engine) else { exit(1) }
engine.game = game
engine.clearColor = MTLClearColor(red: 0.42, green: 0.55, blue: 0.70, alpha: 1)
view.game = game

guard let metalLayer = view.layer as? CAMetalLayer else {
    print("WindageSample: the view has no CAMetalLayer")
    exit(1)
}
let displayLink = engine.makeDisplayLink(for: metalLayer)
displayLink.add(to: .main, forMode: .common)

game.viewportChanged(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height))

// Reported so an automated check can capture *this* window rather than the whole screen.
print("WindageSample: window \(window.windowNumber)")

window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)
application.activate(ignoringOtherApps: true)
application.run()
