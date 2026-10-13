//
//  UIColor.swift
//  WindageEngine
//

import simd

/// A color authored for the **interface**, not for the scene.
///
/// **The distinction this type exists to make explicit.** Scene colors are radiance: unbounded,
/// linear, and tone mapped on the way to the screen — a scene color of `#00C2FF` will not arrive as
/// `#00C2FF`, because an exposure and a filmic curve stand between it and the drawable, by design.
/// Interface colors are the opposite: they are a *specification*, and a brand cyan must land on the
/// screen as exactly that cyan.
///
/// So a `UIColor` is authored in sRGB (the space hex codes live in) and converted to linear once,
/// here. The drawable is an `_srgb` format, so the GPU re-encodes on write and the value round-trips
/// exactly — provided the interface is drawn **after** tone mapping. `HUDRenderer` is what makes
/// that ordering structural rather than something each title has to remember.
public nonisolated struct UIColor: Sendable, Equatable {

    /// As authored, sRGB-encoded, 0...1 per channel.
    public let srgb: SIMD4<Float>

    /// What the shader writes. Linear, so the `_srgb` drawable encodes back to ``srgb`` exactly.
    public let linear: SIMD4<Float>

    public init(srgb: SIMD4<Float>) {
        self.srgb = srgb
        self.linear = SIMD4(UIColor.toLinear(srgb.x),
                            UIColor.toLinear(srgb.y),
                            UIColor.toLinear(srgb.z),
                            srgb.w)   // alpha is not gamma-encoded
    }

    /// From a hex literal, the way brand colors are actually written down: `UIColor(hex: 0x00C2FF)`.
    public init(hex: UInt32, alpha: Float = 1) {
        self.init(srgb: SIMD4(Float((hex >> 16) & 0xFF) / 255,
                              Float((hex >> 8) & 0xFF) / 255,
                              Float(hex & 0xFF) / 255,
                              alpha))
    }

    public func withAlpha(_ alpha: Float) -> UIColor {
        UIColor(srgb: SIMD4(srgb.x, srgb.y, srgb.z, alpha))
    }

    /// The real sRGB transfer function, not a 2.2 approximation. The two differ most in the darks,
    /// which is exactly where a HUD's translucent panels live.
    public static func toLinear(_ channel: Float) -> Float {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    public static let clear = UIColor(srgb: .zero)
    public static let white = UIColor(hex: 0xFFFFFF)
    public static let black = UIColor(hex: 0x000000)
}
