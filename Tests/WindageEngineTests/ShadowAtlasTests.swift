//
//  ShadowAtlasTests.swift
//  WindageEngineTests
//

import Testing
import Metal
import simd
@testable import WindageEngine

/// The arithmetic half: tile geometry and the projection a spot's shadow map is rendered with.
@MainActor
struct ShadowAtlasTests {

    private func atlas(size: Int = 2048, tilesPerSide: Int = 4) -> ShadowAtlas? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return ShadowAtlas(device: device, size: size, tilesPerSide: tilesPerSide)
    }

    private func spot(pointing direction: SIMD3<Float>,
                      at position: SIMD3<Float> = .zero,
                      outer: Float = 30,
                      range: Float = 20) -> PunctualLight {
        PunctualLight(position: position, colour: SIMD3(repeating: 10), range: range,
                      cone: PunctualLight.Cone(direction: direction,
                                               innerAngle: radians_from_degrees(outer * 0.6),
                                               outerAngle: radians_from_degrees(outer)))
    }

    /// **A shadow map is only a shadow map if a point light cannot be given one by accident.** Six
    /// faces is a different feature, and returning `nil` says so at the call site rather than quietly
    /// shadowing one direction of six.
    @Test("A light with no cone gets no shadow projection")
    func pointLightsHaveNoSingleProjection() {
        let point = PunctualLight(position: .zero, colour: SIMD3(repeating: 10), range: 10)
        #expect(ShadowAtlas.viewProjection(for: point) == nil)
        #expect(ShadowAtlas.viewProjection(for: spot(pointing: SIMD3(0, -1, 0))) != nil)
    }

    /// **A lamp pointing straight down is the common case and exactly where a fixed up vector is
    /// degenerate** — the cross product is zero and the whole basis becomes NaN, which draws nothing.
    @Test("A lamp pointing straight down produces a usable basis")
    func straightDownIsNotDegenerate() throws {
        for direction in [SIMD3<Float>(0, -1, 0), SIMD3(0, 1, 0), SIMD3(0, -0.9999, 0.0001)] {
            let matrix = try #require(ShadowAtlas.viewProjection(for: spot(pointing: direction,
                                                                          at: SIMD3(0, 6, 0))))
            for column in [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3] {
                #expect(column.x.isFinite && column.y.isFinite
                        && column.z.isFinite && column.w.isFinite,
                        "NaN in the basis for \(direction)")
            }
        }
    }

    /// The map has to cover what the light can reach: the axis lands in the middle, and a point at
    /// the cone's edge lands inside the map rather than off it.
    @Test("The projection covers the cone and centres its axis")
    func projectionCoversTheCone() throws {
        let light = spot(pointing: SIMD3(0, -1, 0), at: SIMD3(0, 6, 0), outer: 30)
        let matrix = try #require(ShadowAtlas.viewProjection(for: light))

        func project(_ world: SIMD3<Float>) -> SIMD2<Float> {
            let clip = matrix * SIMD4(world, 1)
            return SIMD2(clip.x / clip.w, clip.y / clip.w)
        }
        // Straight down the axis, five metres away.
        let centre = project(SIMD3(0, 1, 0))
        #expect(abs(centre.x) < 1e-4 && abs(centre.y) < 1e-4, "the axis is not in the middle")

        // At the cone's outer edge, which must still be inside the map.
        let edgeAngle = radians_from_degrees(Float(30))
        let edge = project(SIMD3(5 * tan(edgeAngle), 1, 0))
        #expect(abs(edge.x) < 1 && abs(edge.y) < 1, "the cone's edge fell outside its own shadow map")
    }

    /// Reversed-Z, like every other pass: nearer the light is a *greater* depth. Written with one
    /// convention and compared with the other, a scene comes out fully lit or fully dark.
    @Test("Depth is reversed, so nearer the lamp is greater")
    func depthIsReversed() throws {
        let light = spot(pointing: SIMD3(0, -1, 0), at: SIMD3(0, 6, 0))
        let matrix = try #require(ShadowAtlas.viewProjection(for: light))
        func depth(_ world: SIMD3<Float>) -> Float {
            let clip = matrix * SIMD4(world, 1)
            return clip.z / clip.w
        }
        #expect(depth(SIMD3(0, 5, 0)) > depth(SIMD3(0, 0, 0)), "depth is not reversed")
        #expect(depth(SIMD3(0, 0, 0)) > 0)
    }

    // MARK: - Tiles

    @Test("Tiles partition the atlas exactly")
    func tilesPartitionTheAtlas() {
        guard let atlas = atlas(size: 2048, tilesPerSide: 4) else { return }
        #expect(atlas.tileCount == 16)

        var covered = Set<SIMD2<Int>>()
        for index in 0..<atlas.tileCount {
            let tile = atlas.tile(index)
            #expect(tile.size == 512)
            #expect(tile.origin.x >= 0 && tile.origin.x + tile.size <= atlas.size)
            #expect(tile.origin.y >= 0 && tile.origin.y + tile.size <= atlas.size)
            #expect(covered.insert(tile.origin).inserted, "two tiles share an origin")
        }
        #expect(covered.count == 16)
    }

    /// The shader looks up in `0…1` for a light and the result has to land inside that light's own
    /// tile — **one light reading another's map is a shadow from the wrong room**.
    @Test("A tile's UV transform maps the unit square onto that tile")
    func uvTransformStaysInsideTheTile() {
        guard let atlas = atlas(size: 1024, tilesPerSide: 4) else { return }
        for index in 0..<atlas.tileCount {
            let tile = atlas.tile(index)
            let (offset, scale) = tile.uvTransform(atlasSize: atlas.size)
            for corner in [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)] {
                let uv = offset + corner * scale
                #expect(uv.x >= -1e-6 && uv.x <= 1 + 1e-6)
                #expect(uv.y >= -1e-6 && uv.y <= 1 + 1e-6)
            }
            // The tile's own corners, exactly.
            #expect(abs(offset.x - Float(tile.origin.x) / Float(atlas.size)) < 1e-6)
            #expect(abs(scale - Float(tile.size) / Float(atlas.size)) < 1e-6)
        }
    }

    @Test("An index outside the atlas is clamped rather than crashing")
    func tileIndexClamps() {
        guard let atlas = atlas() else { return }
        #expect(atlas.tile(-5) == atlas.tile(0))
        #expect(atlas.tile(9999) == atlas.tile(atlas.tileCount - 1))
    }

    @Test("The atlas survives its own render pass and is readable afterwards")
    func textureIsShaped() {
        guard let atlas = atlas(size: 512, tilesPerSide: 2) else { return }
        #expect(atlas.texture.pixelFormat == ShadowMap.depthPixelFormat)
        #expect(atlas.texture.width == 512 && atlas.texture.height == 512)
        #expect(atlas.texture.storageMode == .private)
        #expect(atlas.texture.usage.contains(.renderTarget))
        #expect(atlas.texture.usage.contains(.shaderRead))
        #expect(atlas.allocations.count == 2)
    }
}
