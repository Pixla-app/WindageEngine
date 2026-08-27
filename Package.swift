// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindageEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "WindageEngine", targets: ["WindageEngine"])
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
        .testTarget(
            name: "WindageEngineTests",
            dependencies: ["WindageEngine"]
        )
    ]
)
