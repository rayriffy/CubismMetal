import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

@MainActor
public final class MetalRenderer: NSObject, MTKViewDelegate {
    public enum TargetFrameRate: Int, CaseIterable, Identifiable, Sendable {
        case sixty = 60
        case oneTwenty = 120

        public var id: Int { rawValue }
        public var label: String { "\(rawValue) FPS" }
    }

    public private(set) var targetFrameRate: TargetFrameRate = .sixty
    public var onError: ((Error) -> Void)?

    /// Cubism texture PNGs are authored in sRGB. Decode them before blending
    /// into the view's sRGB drawable so translucent layers retain their source
    /// colour instead of receiving a second gamma conversion.
    nonisolated static let texturesUseSRGB = true

    private weak var view: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureLoader: MTKTextureLoader
    private let samplerState: MTLSamplerState
    private let normalPipeline: MTLRenderPipelineState
    private let additivePipeline: MTLRenderPipelineState
    private let multiplicativePipeline: MTLRenderPipelineState
    private let maskedNormalPipeline: MTLRenderPipelineState
    private let maskedAdditivePipeline: MTLRenderPipelineState
    private let maskedMultiplicativePipeline: MTLRenderPipelineState
    private let maskPipeline: MTLRenderPipelineState

    private var frameSource: CubismFrameSource?
    private var textureCache: [URL: MTLTexture] = [:]
    private let frameResources = (0 ..< 3).map { _ in FrameResources() }
    private var nextFrameResourceIndex = 0
    private var lastUpdateTime: CFTimeInterval?
    private var lastReportedError: String?
    var canvasViewport = CubismCanvasViewport()

    public init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }

        self.view = view
        self.device = device
        self.commandQueue = commandQueue
        textureLoader = MTKTextureLoader(device: device)

        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.clearColor = MTLClearColor(red: 0.025, green: 0.035, blue: 0.06, alpha: 1)
        view.framebufferOnly = true

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }
        self.samplerState = samplerState

        do {
            let library = try Self.makeShaderLibrary(device: device)
            normalPipeline = try Self.makePipeline(
                device: device,
                library: library,
                colorFormat: view.colorPixelFormat,
                blendMode: .normal,
                masked: false
            )
            additivePipeline = try Self.makePipeline(
                device: device,
                library: library,
                colorFormat: view.colorPixelFormat,
                blendMode: .additive,
                masked: false
            )
            multiplicativePipeline = try Self.makePipeline(
                device: device,
                library: library,
                colorFormat: view.colorPixelFormat,
                blendMode: .multiplicative,
                masked: false
            )
            maskedNormalPipeline = try Self.makePipeline(
                device: device,
                library: library,
                colorFormat: view.colorPixelFormat,
                blendMode: .normal,
                masked: true
            )
            maskedAdditivePipeline = try Self.makePipeline(
                device: device,
                library: library,
                colorFormat: view.colorPixelFormat,
                blendMode: .additive,
                masked: true
            )
            maskedMultiplicativePipeline = try Self.makePipeline(
                device: device,
                library: library,
                colorFormat: view.colorPixelFormat,
                blendMode: .multiplicative,
                masked: true
            )
            maskPipeline = try Self.makeMaskPipeline(
                device: device,
                library: library
            )
        } catch {
            return nil
        }

        super.init()

        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = targetFrameRate.rawValue
        view.delegate = self
    }

    public func setFrameSource(_ source: CubismFrameSource?) {
        frameSource = source
        canvasViewport.reset()
        textureCache.removeAll(keepingCapacity: true)
        for resources in frameResources {
            resources.geometryBuffers.removeAll(keepingCapacity: true)
            resources.maskTextures.removeAll(keepingCapacity: true)
        }
        lastUpdateTime = nil
        lastReportedError = nil
    }

    public func setTargetFrameRate(_ frameRate: TargetFrameRate) {
        targetFrameRate = frameRate
        view?.preferredFramesPerSecond = frameRate.rawValue
    }

    /// Zooms around the canvas center for app-wide keyboard commands.
    public func zoomCanvas(by factor: Float) {
        guard let view else { return }
        zoomCanvas(
            by: factor,
            around: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
            in: view.bounds.size
        )
    }

    /// Verifies that an app bundle contains a usable Metal shader library.
    /// This is intentionally independent from Cubism Core so packaging can be
    /// checked before a licensed Core runtime is installed.
    nonisolated public static func validateBundledShaders() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CubismRuntimeError.unavailable("No Metal device is available on this Mac.")
        }
        let library = try makeShaderLibrary(device: device)
        guard library.makeFunction(name: "cubismVertex") != nil,
              library.makeFunction(name: "cubismFragment") != nil,
              library.makeFunction(name: "cubismMaskedFragment") != nil,
              library.makeFunction(name: "cubismMaskFragment") != nil
        else {
            throw CubismRuntimeError.loadingFailed("The bundled Metal shader library is incomplete.")
        }
    }

    public func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    public func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let resources = frameResources[nextFrameResourceIndex]
        nextFrameResourceIndex = (nextFrameResourceIndex + 1) % frameResources.count
        let slotSemaphore = resources.availability
        slotSemaphore.wait()
        commandBuffer.addCompletedHandler { _ in
            slotSemaphore.signal()
        }

        defer {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        guard let frameSource else {
            encodeEmptyFrame(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
            return
        }

        do {
            let now = CACurrentMediaTime()
            let deltaTime = min(max(now - (lastUpdateTime ?? now), 0), 1.0 / 15.0)
            lastUpdateTime = now
            let frame = try frameSource.advance(by: deltaTime)
            let didEncode = try encode(
                frame: frame,
                in: view,
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                resources: resources
            )
            lastReportedError = nil
            if !didEncode {
                encodeEmptyFrame(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
            }
        } catch {
            report(error)
            encodeEmptyFrame(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
        }
    }

    private func encodeEmptyFrame(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor
    ) {
        commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)?.endEncoding()
    }

    private func encode(
        frame: CubismFrameSnapshot,
        in view: MTKView,
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        resources: FrameResources
    ) throws -> Bool {
        guard view.drawableSize.width > 0,
              view.drawableSize.height > 0
        else {
            return false
        }

        let transform = canvasViewport.applying(
            to: Self.makeFitTransform(bounds: frame.canvasBounds, drawableSize: view.drawableSize)
        )
        let drawables = frame.visibleDrawablesInRenderOrder
        let sourceDrawablesByID = Dictionary(
            frame.drawables.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let masks = try encodeMasks(
            for: drawables,
            sourceDrawablesByID: sourceDrawablesByID,
            transform: transform,
            drawableSize: view.drawableSize,
            commandBuffer: commandBuffer,
            resources: resources
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw CubismRuntimeError.unavailable("Metal display render encoder could not be created.")
        }
        defer { encoder.endEncoding() }

        for drawable in drawables {
            let maskTexture = drawable.maskSourceIdentifiers.isEmpty
                ? nil
                : masks[MaskKey(identifiers: drawable.maskSourceIdentifiers)]
            try encodeColor(
                drawable,
                transform: transform,
                maskTexture: maskTexture,
                resources: resources,
                encoder: encoder
            )
        }
        return true
    }

    private func encodeMasks(
        for drawables: [CubismDrawableSnapshot],
        sourceDrawablesByID: [String: CubismDrawableSnapshot],
        transform: simd_float4x4,
        drawableSize: CGSize,
        commandBuffer: MTLCommandBuffer,
        resources: FrameResources
    ) throws -> [MaskKey: MTLTexture] {
        var keys: [MaskKey] = []
        var activeKeys = Set<MaskKey>()
        for drawable in drawables where !drawable.maskSourceIdentifiers.isEmpty {
            let key = MaskKey(identifiers: drawable.maskSourceIdentifiers)
            if activeKeys.insert(key).inserted {
                keys.append(key)
            }
        }
        resources.maskTextures = resources.maskTextures.filter { activeKeys.contains($0.key) }

        var frameMasks: [MaskKey: MTLTexture] = [:]
        for key in keys {
            let texture = try maskTexture(for: key, drawableSize: drawableSize, resources: resources)
            try encodeMask(
                key,
                sourceDrawablesByID: sourceDrawablesByID,
                into: texture,
                transform: transform,
                commandBuffer: commandBuffer,
                resources: resources
            )
            frameMasks[key] = texture
        }
        return frameMasks
    }

    private func encodeMask(
        _ key: MaskKey,
        sourceDrawablesByID: [String: CubismDrawableSnapshot],
        into texture: MTLTexture,
        transform: simd_float4x4,
        commandBuffer: MTLCommandBuffer,
        resources: FrameResources
    ) throws {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]!
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        attachment.clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw CubismRuntimeError.unavailable("Metal mask render encoder could not be created.")
        }
        defer { encoder.endEncoding() }

        encoder.label = "Cubism alpha mask"
        encoder.setRenderPipelineState(maskPipeline)
        for identifier in key.identifiers {
            guard let drawable = sourceDrawablesByID[identifier], isMaskRenderable(drawable) else {
                continue
            }
            try encodeGeometry(
                drawable,
                transform: transform,
                opacity: 1,
                maskTexture: nil,
                isInvertedMask: false,
                resources: resources,
                encoder: encoder
            )
        }
    }

    private func maskTexture(
        for key: MaskKey,
        drawableSize: CGSize,
        resources: FrameResources
    ) throws -> MTLTexture {
        let width = max(Int(drawableSize.width.rounded(.up)), 1)
        let height = max(Int(drawableSize.height.rounded(.up)), 1)
        if let texture = resources.maskTextures[key], texture.width == width, texture.height == height {
            return texture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw CubismRuntimeError.unavailable("Metal alpha mask texture allocation failed.")
        }
        resources.maskTextures[key] = texture
        return texture
    }

    private func encodeColor(
        _ drawable: CubismDrawableSnapshot,
        transform: simd_float4x4,
        maskTexture: MTLTexture?,
        resources: FrameResources,
        encoder: MTLRenderCommandEncoder
    ) throws {
        encoder.setRenderPipelineState(pipeline(for: drawable.blendMode, masked: maskTexture != nil))
        try encodeGeometry(
            drawable,
            transform: transform,
            opacity: drawable.opacity,
            maskTexture: maskTexture,
            isInvertedMask: drawable.isInvertedMask,
            resources: resources,
            encoder: encoder
        )
    }

    private func encodeGeometry(
        _ drawable: CubismDrawableSnapshot,
        transform: simd_float4x4,
        opacity: Float,
        maskTexture: MTLTexture?,
        isInvertedMask: Bool,
        resources: FrameResources,
        encoder: MTLRenderCommandEncoder
    ) throws {
        guard let textureURL = drawable.textureURL else { return }
        let texture = try texture(for: textureURL)
        let buffers = updateBuffers(for: drawable, resources: resources)
        var uniforms = Uniforms(transform: transform, opacity: opacity)

        encoder.setVertexBuffer(buffers.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        if let maskTexture {
            var maskUniforms = MaskUniforms(inverted: isInvertedMask ? 1 : 0)
            encoder.setFragmentTexture(maskTexture, index: 1)
            encoder.setFragmentBytes(
                &maskUniforms,
                length: MemoryLayout<MaskUniforms>.stride,
                index: 0
            )
        }
        encoder.setCullMode(.none)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: drawable.indices.count,
            indexType: .uint16,
            indexBuffer: buffers.indexBuffer,
            indexBufferOffset: 0
        )
    }

    private func isMaskRenderable(_ drawable: CubismDrawableSnapshot) -> Bool {
        drawable.textureURL != nil
            && drawable.vertices.count == drawable.uvs.count
            && !drawable.vertices.isEmpty
            && !drawable.indices.isEmpty
    }

    private func updateBuffers(
        for drawable: CubismDrawableSnapshot,
        resources: FrameResources
    ) -> GeometryBuffers {
        let vertices = zip(drawable.vertices, drawable.uvs).map {
            Vertex(position: $0.0, uv: $0.1)
        }
        let vertexByteCount = vertices.count * MemoryLayout<Vertex>.stride
        let indexByteCount = drawable.indices.count * MemoryLayout<UInt16>.stride

        var buffers = resources.geometryBuffers[drawable.identifier]
            ?? GeometryBuffers.make(device: device, vertexByteCount: vertexByteCount, indexByteCount: indexByteCount)
        if buffers.vertexCapacity < vertexByteCount || buffers.indexCapacity < indexByteCount {
            buffers = GeometryBuffers.make(device: device, vertexByteCount: vertexByteCount, indexByteCount: indexByteCount)
        }

        vertices.withUnsafeBytes { source in
            buffers.vertexBuffer.contents().copyMemory(from: source.baseAddress!, byteCount: vertexByteCount)
        }
        drawable.indices.withUnsafeBytes { source in
            buffers.indexBuffer.contents().copyMemory(from: source.baseAddress!, byteCount: indexByteCount)
        }
        resources.geometryBuffers[drawable.identifier] = buffers
        return buffers
    }

    private func texture(for url: URL) throws -> MTLTexture {
        let normalizedURL = url.standardizedFileURL
        if let cached = textureCache[normalizedURL] { return cached }

        let options: [MTKTextureLoader.Option: Any] = [
            .origin: MTKTextureLoader.Origin.bottomLeft,
            .generateMipmaps: false,
            .SRGB: Self.texturesUseSRGB,
        ]
        let texture = try textureLoader.newTexture(URL: normalizedURL, options: options)
        textureCache[normalizedURL] = texture
        return texture
    }

    private func pipeline(for blendMode: CubismBlendMode, masked: Bool) -> MTLRenderPipelineState {
        switch (blendMode, masked) {
        case (.normal, false): normalPipeline
        case (.additive, false): additivePipeline
        case (.multiplicative, false): multiplicativePipeline
        case (.normal, true): maskedNormalPipeline
        case (.additive, true): maskedAdditivePipeline
        case (.multiplicative, true): maskedMultiplicativePipeline
        }
    }

    private func report(_ error: Error) {
        let description = error.localizedDescription
        guard description != lastReportedError else { return }
        lastReportedError = description
        onError?(error)
    }
}
