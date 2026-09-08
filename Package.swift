// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindageEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "WindageEngine", targets: ["WindageEngine"]),
        // **The sample is a product, not a test fixture.** `swift run WindageSample` is the first
        // thing somebody who cloned this repo should be able to do.
        .executable(name: "WindageSample", targets: ["WindageSample"]),
    ],
    targets: [
        .target(
            name: "WindageEngine",
            // Declared so SwiftPM synthesises `Bundle.module`, which the HUD pipeline loads its
            // shaders from. Xcode compiles the .metal into the same bundle as `default.metallib`;
            // SwiftPM's CLI does not compile Metal at all, which is why `swift test` can build the
            // package but cannot exercise anything needing a GPU.
            resources: [.copy("HUDShaders.metal")],
            swiftSettings: [
                // Matches the game targets: everything is main-actor by default unless it says
                // otherwise. Engine types that must run off the main thread say `nonisolated`
                // explicitly, which is a decision worth having to write down.
                .defaultIsolation(MainActor.self)
            ]
        ),
        // A complete, deliberately dull game built against the engine's **public API only**.
        //
        // It is the standing check that the engine is usable by someone who did not write it: if
        // the sample cannot be built without reaching inside, the API is wrong. It found its first
        // one immediately — `swift build` compiles no Metal, so nothing that loaded a default
        // library could start outside Xcode. See `ShaderLibrary`.
        .executableTarget(
            name: "WindageSample",
            dependencies: ["WindageEngine"],
            // `.copy` and not `.process`: the shader **source** has to survive into the bundle so it
            // can be compiled at runtime when no metallib exists.
            resources: [.copy("SampleShaders.metal"), .copy("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "WindageEngineTests",
            dependencies: ["WindageEngine"]
        )
    ]
)
