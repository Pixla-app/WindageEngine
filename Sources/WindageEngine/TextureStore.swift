//
//  TextureStore.swift
//  WindageEngine
//

import Foundation
import Metal
import MetalKit
import simd

public enum TextureStoreError: Error, CustomStringConvertible, Sendable {
    case notFound(String)
    case loadFailed(String, underlying: any Error)
    case fallbackUnavailable

    public var description: String {
        switch self {
        case .notFound(let name): "no texture named \(name) in the bundle"
        case .loadFailed(let name, let underlying): "could not load \(name) — \(underlying)"
        case .fallbackUnavailable: "the device would not allocate a 1×1 fallback texture"
        }
    }
}

/// Loads textures once and hands the same one back after that.
///
/// **The GPU half of ``Material``**, split off for the same reason `RigLoader` is split from
/// `MeshLoader`: reading what a material *says* needs no device, and turning that into memory on a
/// GPU does. Everything with a convention in it lives on the other side of that line and is
/// testable; this side is a cache and a loader.
///
/// ### The cache is the point, not a nicety
///
/// A scene's meshes share their maps — every crate in a level names the same file. Loading it per
/// mesh costs the decode, the upload and the mipmap generation each time, and then holds N copies of
/// the same texture in GPU memory. Keyed by file **and by how it is being read**, because the same
/// image genuinely can be wanted both ways.
///
/// ### Main-actor, deliberately
///
/// It holds mutable state, and textures are loaded while a level loads rather than from a render
/// thread. Making it `nonisolated` would buy background loading at the price of locking the cache,
/// and nothing here has asked for that yet.
public final class TextureStore {

    private struct Key: Hashable {
        let source: TextureSource
        let isColor: Bool
    }

    private let device: MTLDevice
    private let loader: MTKTextureLoader
    private var cache: [Key: MTLTexture] = [:]

    /// A 1×1 opaque white, for binding where a material has no map.
    ///
    /// **So that a shader can always sample.** The alternative is a shader that branches on whether
    /// a texture exists, or a second pipeline compiled without it — one costs a branch per fragment
    /// and the other doubles the pipelines in the game. White multiplies to nothing, so the
    /// material's own colour comes through untouched.
    public let white: MTLTexture

    /// A 1×1 flat normal — (0.5, 0.5, 1) — meaning "no perturbation".
    ///
    /// Not the same fallback as ``white``: a white pixel decodes to the normal (1, 1, 1), which
    /// tilts every surface diagonally and lights the whole scene wrongly.
    public let flatNormal: MTLTexture

    public init?(device: MTLDevice) {
        self.device = device
        self.loader = MTKTextureLoader(device: device)
        guard let white = TextureStore.makePixel(device: device, colour: SIMD4(255, 255, 255, 255),
                                                 label: "White 1×1"),
              let normal = TextureStore.makePixel(device: device, colour: SIMD4(128, 128, 255, 255),
                                                  label: "Flat Normal 1×1") else { return nil }
        self.white = white
        self.flatNormal = normal
    }

    private static func makePixel(device: MTLDevice, colour: SIMD4<UInt8>, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        // Shared rather than private: it is four bytes, and `replace(region:)` on a private texture
        // would need a blit and a command buffer at start-up for nothing.
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        var pixel = colour
        withUnsafeBytes(of: &pixel) { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: 4)
        }
        return texture
    }

    /// The fallback for a slot that a material does not fill.
    public func fallback(for slot: TextureSlot) -> MTLTexture {
        slot == .normal ? flatNormal : white
    }

    /// Loads a texture, or returns the one already loaded.
    ///
    /// - Parameter isColor: whether to decode sRGB on the way in. Take it from
    ///   ``TextureSlot/isColor`` rather than deciding per call site — that is the whole reason it is
    ///   a property of the slot.
    @discardableResult
    public func texture(_ source: TextureSource,
                        isColor: Bool,
                        bundle: Bundle = .main) throws -> MTLTexture {
        let key = Key(source: source, isColor: isColor)
        if let cached = cache[key] { return cached }

        let url: URL
        switch source {
        case .url(let value):
            url = value
        case .named(let name):
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            guard let found = bundle.url(forResource: stem, withExtension: ext.isEmpty ? nil : ext) else {
                throw TextureStoreError.notFound(name)
            }
            url = found
        }

        // **Mipmaps are not optional for anything seen at an angle.** A ground plane sampled at one
        // level aliases into a shimmering mess as the camera moves, and it is the single most
        // obvious difference between "textured" and "textured properly".
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .generateMipmaps: NSNumber(value: true),
            .SRGB: NSNumber(value: isColor),
        ]

        do {
            let texture = try loader.newTexture(URL: url, options: options)
            texture.label = url.lastPathComponent
            cache[key] = texture
            return texture
        } catch {
            throw TextureStoreError.loadFailed(url.lastPathComponent, underlying: error)
        }
    }

    /// Every map a material names, with anything missing or unloadable filled in by ``fallback(for:)``.
    ///
    /// **Never throws.** A missing texture should draw the object in a plain colour and say so once,
    /// not stop a level loading — a level that will not open because one map is misspelled is a
    /// worse failure than a crate that is the wrong shade.
    public func textures(for material: Material,
                         bundle: Bundle = .main,
                         reportingTo report: ((String) -> Void)? = nil) -> [TextureSlot: MTLTexture] {
        var result: [TextureSlot: MTLTexture] = [:]
        for slot in TextureSlot.allCases {
            guard let source = material[slot] else {
                result[slot] = fallback(for: slot)
                continue
            }
            do {
                result[slot] = try texture(source, isColor: slot.isColor, bundle: bundle)
            } catch {
                report?("material '\(material.name)' \(slot.rawValue): \(error)")
                result[slot] = fallback(for: slot)
            }
        }
        return result
    }

    /// Everything loaded so far, for the residency set.
    ///
    /// **A texture the GPU cannot reach is not a black object — it is garbage that looks like a
    /// shader bug.** Call this after loading a level's materials and commit residency.
    public var allocations: [MTLResource] { Array(cache.values) + [white, flatNormal] }
}
