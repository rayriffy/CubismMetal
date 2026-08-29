import Foundation
import Metal
import simd

struct CubismBlendState: Equatable {
    let sourceRGB: MTLBlendFactor
    let destinationRGB: MTLBlendFactor
    let sourceAlpha: MTLBlendFactor
    let destinationAlpha: MTLBlendFactor
}

extension MetalRenderer {
    nonisolated static func makeShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        guard let url = shaderSourceURL() else {
            throw CubismRuntimeError.loadingFailed("Cubism Metal shader source is missing from the app bundle.")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        return try device.makeLibrary(source: source, options: nil)
    }

    private nonisolated static func shaderSourceURL() -> URL? {
        #if SWIFT_PACKAGE
        if let url = shaderSourceURL(in: .module) {
            return url
        }
        #endif
        return shaderSourceURL(in: .main)
    }

    private nonisolated static func shaderSourceURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "CubismShaders", withExtension: "metal", subdirectory: "Shaders")
            ?? bundle.url(forResource: "CubismShaders", withExtension: "metal")
    }

    static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        colorFormat: MTLPixelFormat,
        blendMode: CubismBlendMode,
        masked: Bool
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cubismVertex")
        descriptor.fragmentFunction = library.makeFunction(
            name: masked ? "cubismMaskedFragment" : "cubismFragment"
        )
        descriptor.colorAttachments[0].pixelFormat = colorFormat

        let blendState = blendState(for: blendMode)
        let color = descriptor.colorAttachments[0]
        color?.isBlendingEnabled = true
        color?.sourceRGBBlendFactor = blendState.sourceRGB
        color?.destinationRGBBlendFactor = blendState.destinationRGB
        color?.sourceAlphaBlendFactor = blendState.sourceAlpha
        color?.destinationAlphaBlendFactor = blendState.destinationAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    nonisolated static func blendState(for blendMode: CubismBlendMode) -> CubismBlendState {
        switch blendMode {
        case .normal:
            CubismBlendState(
                sourceRGB: .one,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        case .additive:
            CubismBlendState(
                sourceRGB: .sourceAlpha,
                destinationRGB: .one,
                sourceAlpha: .one,
                destinationAlpha: .one
            )
        case .multiplicative:
            CubismBlendState(
                sourceRGB: .destinationColor,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .zero,
                destinationAlpha: .one
            )
        }
    }

    static func makeMaskPipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cubismVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cubismMaskFragment")
        descriptor.colorAttachments[0].pixelFormat = .r8Unorm

        let color = descriptor.colorAttachments[0]
        color?.isBlendingEnabled = true
        color?.sourceRGBBlendFactor = .zero
        color?.destinationRGBBlendFactor = .oneMinusSourceColor
        color?.sourceAlphaBlendFactor = .zero
        color?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    static func makeFitTransform(bounds: CubismBounds, drawableSize: CGSize) -> simd_float4x4 {
        let width = max(bounds.size.x, 0.0001)
        let height = max(bounds.size.y, 0.0001)
        let aspect = max(Float(drawableSize.width / drawableSize.height), 0.0001)
        let scale = min(1.8 / height, 1.8 * aspect / width)
        let center = bounds.center

        return simd_float4x4(columns: (
            SIMD4<Float>(scale / aspect, 0, 0, 0),
            SIMD4<Float>(0, scale, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-center.x * scale / aspect, -center.y * scale, 0, 1)
        ))
    }
}
