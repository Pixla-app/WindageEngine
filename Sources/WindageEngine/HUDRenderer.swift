//
//  HUDRenderer.swift
//  WindageEngine
//

import Metal
import simd

/// Draws the interface, **after** the scene has been tone mapped.
///
/// **The ordering is the point of this type.** A HUD drawn inside the scene's shading would go
/// through exposure and a filmic curve like everything else, and a brand colour would arrive on
/// screen desaturated and shifted — quietly, with nothing to indicate why. `FrameRenderer` calls
/// `GameLoop.encodeHUD` after the scene, and this renderer's pipeline applies no curve, so a
/// ``UIColor`` lands as the exact value it was authored as.
///
/// **What this is not.** There is no layout, no text, no widgets and no event handling. It draws
/// coloured rectangles and lines in screen space, which is enough for a reticle, a bar, a panel or a
/// marker. Text and layout arrive when a title actually needs them and can show what shape they
/// should be — the same extract-when-proven rule as everything else here.
public final class HUDRenderer {

    /// Vertices reserved per frame in flight. Two triangles per rectangle.
    public static let maxVerticesPerFrame = 8192

    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let argumentTable: MTL4ArgumentTable
    private let vertexBuffer: MTLBuffer

    /// Screen-space geometry accumulated this frame, in normalised device coordinates.
    private var vertices: [Vertex] = []
    private var viewportSize = SIMD2<Float>(1, 1)

    private struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
        var color: SIMD4<Float>
    }

    /// The glyph sheet, which also supplies the opaque texel solid shapes sample.
    public let font: FontAtlas

    private static let vertexStride = MemoryLayout<Vertex>.stride

    public init?(device: MTLDevice, font: FontAtlas? = nil) {
        guard let atlas = font ?? FontAtlas(device: device) else {
            print("WindageEngine: unable to build the font atlas")
            return nil
        }
        self.font = atlas

        do {
            // The engine's own shaders, compiled into the package's resource bundle.
            let library = try device.makeDefaultLibrary(bundle: .module)
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "pgeHUDVertex"
            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "pgeHUDFragment"

            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[0].offset = MemoryLayout<Vertex>.offset(of: \.position)!
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float2
            // Taken from the type, never hand-computed. `SIMD4<Float>` is 16-byte aligned, so this
            // is 16 and not the 8 that "two floats then a colour" suggests — and getting it wrong
            // does not fail, it feeds the shader garbage. Here that read as alpha ≈ 0 and the whole
            // interface silently drew nothing.
            vertexDescriptor.attributes[1].offset = MemoryLayout<Vertex>.offset(of: \.uv)!
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.attributes[2].format = .float4
            vertexDescriptor.attributes[2].offset = MemoryLayout<Vertex>.offset(of: \.color)!
            vertexDescriptor.attributes[2].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = HUDRenderer.vertexStride
            vertexDescriptor.layouts[0].stepFunction = .perVertex

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = "HUDPipeline"
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = fragmentFunction
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.rasterSampleCount = 1
            descriptor.colorAttachments[0].pixelFormat = FrameRenderer.colorPixelFormat
            // Premultiplied alpha, so translucent panels composite over the scene correctly.
            descriptor.colorAttachments[0].blendingState = .enabled
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            pipelineState = try compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("WindageEngine: unable to build HUD pipeline: \(error)")
            return nil
        }

        // The interface sits in front of everything and occludes nothing.
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.depthState = depthState

        guard let buffer = device.makeBuffer(
            length: HUDRenderer.vertexStride * HUDRenderer.maxVerticesPerFrame * FrameRenderer.maxFramesInFlight,
            options: [.storageModeShared]) else { return nil }
        buffer.label = "HUDVertices"
        vertexBuffer = buffer

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 2
        tableDescriptor.maxTextureBindCount = 1
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor) else { return nil }
        argumentTable = table
    }

    public var allocations: [any MTLAllocation] { [vertexBuffer, font.texture] }

    // MARK: - Building a frame

    /// Clears the frame and sets the coordinate space.
    ///
    /// Coordinates are **points with the origin at the top left**, matching how interfaces are
    /// normally described, and are converted to device coordinates here rather than at every call
    /// site.
    public func begin(viewportSize: SIMD2<Float>) {
        vertices.removeAll(keepingCapacity: true)
        self.viewportSize = SIMD2(max(viewportSize.x, 1), max(viewportSize.y, 1))
    }

    public func rect(x: Float, y: Float, width: Float, height: Float, color: UIColor) {
        guard color.srgb.w > 0, width > 0, height > 0 else { return }
        let topLeft = toDevice(SIMD2(x, y))
        let bottomRight = toDevice(SIMD2(x + width, y + height))

        let a = SIMD2(topLeft.x, topLeft.y)
        let b = SIMD2(bottomRight.x, topLeft.y)
        let c = SIMD2(bottomRight.x, bottomRight.y)
        let d = SIMD2(topLeft.x, bottomRight.y)

        for corner in [a, b, c, a, c, d] {
            vertices.append(Vertex(position: corner, uv: font.whiteTexelUV, color: color.linear))
        }
    }

    /// A line of a given thickness, as a rotated quad.
    public func line(from start: SIMD2<Float>, to end: SIMD2<Float>, thickness: Float, color: UIColor) {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0, color.srgb.w > 0 else { return }

        let direction = delta / length
        let normal = SIMD2(-direction.y, direction.x) * (thickness * 0.5)

        let corners = [start + normal, end + normal, end - normal, start - normal].map(toDevice)
        for index in [0, 1, 2, 0, 2, 3] {
            vertices.append(Vertex(position: corners[index], uv: font.whiteTexelUV, color: color.linear))
        }
    }

    /// An unfilled rectangle, drawn as four edges.
    public func stroke(x: Float, y: Float, width: Float, height: Float, thickness: Float, color: UIColor) {
        rect(x: x, y: y, width: width, height: thickness, color: color)
        rect(x: x, y: y + height - thickness, width: width, height: thickness, color: color)
        rect(x: x, y: y, width: thickness, height: height, color: color)
        rect(x: x + width - thickness, y: y, width: thickness, height: height, color: color)
    }

    /// Draws a line of text with its **left edge and baseline** at `x, y`.
    ///
    /// Baseline rather than top edge, because that is the line the eye reads along: two readouts at
    /// the same baseline look aligned even when one contains a comma or a lowercase descender, and
    /// two aligned by their top edges do not.
    @discardableResult
    public func text(_ string: String, x: Float, y: Float, pointSize: Float, color: UIColor) -> Float {
        guard color.srgb.w > 0 else { return width(of: string, pointSize: pointSize) }
        let scale = pointSize / Float(FontAtlas.rasterHeight)
        var penX = x

        for character in string {
            guard let glyph = font.glyph(for: character) else { continue }
            let w = glyph.size.x * scale
            let h = glyph.size.y * scale

            if w > 0 && h > 0 {
                // Bearing is measured from the baseline upward, screen coordinates run downward.
                let left = penX + glyph.bearing.x * scale
                let top = y - (glyph.bearing.y + glyph.size.y) * scale

                let topLeft = toDevice(SIMD2(left, top))
                let bottomRight = toDevice(SIMD2(left + w, top + h))
                let uv0 = glyph.uvOrigin
                let uv1 = glyph.uvOrigin + glyph.uvSize

                // `uvOrigin` is already the glyph's top-left in texture space, so this maps
                // straight across with no flip.
                let corners = [
                    (SIMD2(topLeft.x, topLeft.y), SIMD2(uv0.x, uv0.y)),
                    (SIMD2(bottomRight.x, topLeft.y), SIMD2(uv1.x, uv0.y)),
                    (SIMD2(bottomRight.x, bottomRight.y), SIMD2(uv1.x, uv1.y)),
                    (SIMD2(topLeft.x, bottomRight.y), SIMD2(uv0.x, uv1.y))
                ]
                for index in [0, 1, 2, 0, 2, 3] {
                    vertices.append(Vertex(position: corners[index].0,
                                           uv: corners[index].1,
                                           color: color.linear))
                }
            }
            penX += glyph.advance * scale
        }
        return penX - x
    }

    /// Width of a string without drawing it, for right-aligning or laying out a panel behind it.
    public func width(of string: String, pointSize: Float) -> Float {
        font.width(of: string, pointSize: pointSize)
    }

    /// A filled ring — an annulus — approximated with `segments` quads.
    ///
    /// With a large enough outer radius this is a circular vignette, which is how a scope's sight
    /// picture gets its surround. Drawn as a strip of quads rather than a triangle fan so it needs
    /// no index buffer and no separate primitive type: the whole interface stays one draw call.
    public func ring(centre: SIMD2<Float>,
                     innerRadius: Float,
                     outerRadius: Float,
                     segments: Int = 96,
                     color: UIColor) {
        guard outerRadius > innerRadius, segments >= 3, color.srgb.w > 0 else { return }
        let step = (2 * Float.pi) / Float(segments)

        for index in 0..<segments {
            let a0 = Float(index) * step
            let a1 = Float(index + 1) * step
            let d0 = SIMD2(cos(a0), sin(a0))
            let d1 = SIMD2(cos(a1), sin(a1))

            let corners = [
                centre + d0 * innerRadius,
                centre + d1 * innerRadius,
                centre + d1 * outerRadius,
                centre + d0 * outerRadius
            ].map(toDevice)

            for corner in [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]] {
                vertices.append(Vertex(position: corner, uv: font.whiteTexelUV, color: color.linear))
            }
        }
    }

    /// Points, origin top-left, to normalised device coordinates.
    private func toDevice(_ point: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2((point.x / viewportSize.x) * 2 - 1,
              1 - (point.y / viewportSize.y) * 2)
    }

    // MARK: - Drawing

    public func draw(into encoder: MTL4RenderCommandEncoder, frameSlot: Int) {
        guard !vertices.isEmpty else { return }
        let count = min(vertices.count, HUDRenderer.maxVerticesPerFrame)
        let offset = HUDRenderer.vertexStride * HUDRenderer.maxVerticesPerFrame * frameSlot

        vertexBuffer.contents().advanced(by: offset)
            .withMemoryRebound(to: Vertex.self, capacity: count) { destination in
                for index in 0..<count { destination[index] = vertices[index] }
            }

        encoder.pushDebugGroup("HUD")
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setArgumentTable(argumentTable, stages: .vertex)
        encoder.setArgumentTable(argumentTable, stages: .fragment)
        argumentTable.setAddress(vertexBuffer.gpuAddress + UInt64(offset), index: 0)
        argumentTable.setTexture(font.texture.gpuResourceID, index: 0)
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: count)
        encoder.popDebugGroup()
    }
}
