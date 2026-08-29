import Foundation
import simd

/// A loader that turns a selected `.model3.json` (or a `.moc3` with a matching
/// sibling manifest) into a Metal-renderable Cubism frame source.
public struct CubismModelLoader {
    public let coreLibraryURL: URL?
    public let autoplayFirstMotion: Bool

    private let environment: [String: String]

    public init(
        coreLibraryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        autoplayFirstMotion: Bool = true
    ) {
        self.coreLibraryURL = coreLibraryURL
        self.environment = environment
        self.autoplayFirstMotion = autoplayFirstMotion
    }

    public func load(openedURL: URL) throws -> CubismModelSession {
        try load(manifest: CubismModelManifest.load(openedURL: openedURL))
    }

    public func load(manifest: CubismModelManifest) throws -> CubismModelSession {
        let coreLibrary = try CubismCoreLibrary(
            libraryURL: coreLibraryURL,
            environment: environment
        )
        return try CubismModelSession(
            manifest: manifest,
            coreLibrary: coreLibrary,
            autoplayFirstMotion: autoplayFirstMotion
        )
    }
}

/// A retained, in-place Cubism Core model.
///
/// Instances are intentionally single-render-thread objects. Call `advance(by:)`
/// serially on the same executor that supplies snapshots to `MetalRenderer`.
public final class CubismModelSession: CubismFrameSource {
    public let manifest: CubismModelManifest
    public let displayName: String
    public let coreLibraryURL: URL
    public let coreVersion: UInt32
    public let motions: [CubismMotionOption]

    public private(set) var selectedMotionID: String?
    public var loopsMotion = true
    public private(set) var currentParameterValues: [String: Float] = [:]
    public private(set) var currentDrawableEvaluations: [CubismDrawableEvaluation] = []

    private let coreLibrary: CubismCoreLibrary
    private let mocStorage: CubismAlignedStorage
    private let modelStorage: CubismAlignedStorage
    private let moc: UnsafeMutableRawPointer
    private let model: UnsafeMutableRawPointer
    private let textureURLs: [URL]
    private let parameterIndexes: [String: Int]
    private let partIndexes: [String: Int]
    private let motionURLs: [String: URL]

    private var activeMotion: CubismMotion?
    private var motionElapsedTime: TimeInterval = 0
    private var drawableStaticMetadata: [DrawableStaticMetadata] = []
    private var drawableVertices: [[SIMD2<Float>]] = []

    private struct DrawableStaticMetadata {
        let identifier: String
        let textureIndex: Int
        let textureURL: URL?
        let constantFlags: UInt8
        let rawBlendMode: Int?
        let maskIndices: [Int]
        let maskSourceIdentifiers: [String]
        let uvs: [SIMD2<Float>]
        let indices: [UInt16]
    }

    init(
        manifest: CubismModelManifest,
        coreLibrary: CubismCoreLibrary,
        autoplayFirstMotion: Bool
    ) throws {
        let mocData = try Data(contentsOf: manifest.mocURL)
        guard !mocData.isEmpty else {
            throw CubismCoreModelError.emptyMoc(manifest.mocURL)
        }
        guard mocData.count <= Int(UInt32.max) else {
            throw CubismCoreModelError.mocTooLarge(manifest.mocURL)
        }

        let retainedMocStorage = CubismAlignedStorage(
            copying: mocData,
            alignment: CubismCoreConstants.mocAlignment
        )
        let mocSize = UInt32(mocData.count)
        if let hasMocConsistency = coreLibrary.abi.hasMocConsistency,
           hasMocConsistency(retainedMocStorage.pointer, mocSize) == 0 {
            throw CubismCoreModelError.inconsistentMoc(manifest.mocURL)
        }
        guard let revivedMoc = coreLibrary.abi.reviveMocInPlace(retainedMocStorage.pointer, mocSize) else {
            throw CubismCoreModelError.couldNotReviveMoc(manifest.mocURL)
        }

        let requiredModelSize = coreLibrary.abi.getSizeofModel(UnsafeRawPointer(revivedMoc))
        guard requiredModelSize > 0 else {
            throw CubismCoreModelError.invalidModelAllocation(manifest.mocURL)
        }
        let retainedModelStorage = CubismAlignedStorage(
            byteCount: Int(requiredModelSize),
            alignment: CubismCoreConstants.modelAlignment
        )
        guard let initializedModel = coreLibrary.abi.initializeModelInPlace(
            UnsafeRawPointer(revivedMoc),
            retainedModelStorage.pointer,
            requiredModelSize
        ) else {
            throw CubismCoreModelError.invalidModelAllocation(manifest.mocURL)
        }
        if let getOffscreenCount = coreLibrary.abi.getOffscreenCount,
           getOffscreenCount(UnsafeRawPointer(initializedModel)) > 0 {
            throw CubismCoreModelError.unsupportedOffscreenComposition(manifest.mocURL)
        }

        let parameterIDs = try Self.readIDs(
            coreLibrary.abi.getParameterIDs(UnsafeRawPointer(initializedModel)),
            count: coreLibrary.abi.getParameterCount(UnsafeRawPointer(initializedModel)),
            kind: "parameter"
        )
        let partIDs = try Self.readIDs(
            coreLibrary.abi.getPartIDs(UnsafeRawPointer(initializedModel)),
            count: coreLibrary.abi.getPartCount(UnsafeRawPointer(initializedModel)),
            kind: "part"
        )

        self.manifest = manifest
        self.coreLibrary = coreLibrary
        mocStorage = retainedMocStorage
        modelStorage = retainedModelStorage
        moc = revivedMoc
        model = initializedModel
        textureURLs = manifest.textureURLs
        parameterIndexes = Self.indexes(for: parameterIDs)
        partIndexes = Self.indexes(for: partIDs)
        motions = manifest.motionOptions
        motionURLs = Dictionary(
            uniqueKeysWithValues: manifest.motions.map { motion in
                (motion.id, manifest.resolvedMotionURL(for: motion))
            }
        )
        displayName = manifest.sourceURL.deletingPathExtension().lastPathComponent
        coreLibraryURL = coreLibrary.libraryURL
        coreVersion = coreLibrary.version

        coreLibrary.abi.updateModel(initializedModel)
        currentParameterValues = try readParameterValues()

        if autoplayFirstMotion, let firstMotionID = motions.first?.id {
            try selectMotion(id: firstMotionID)
        }
    }

    public func selectMotion(id: String?) throws {
        guard let id else {
            selectedMotionID = nil
            activeMotion = nil
            motionElapsedTime = 0
            return
        }
        guard let url = motionURLs[id] else {
            throw CubismCoreModelError.unknownMotion(id)
        }

        let motion = try CubismMotion.load(from: url)
        selectedMotionID = id
        activeMotion = motion
        motionElapsedTime = 0
    }

    public func advance(by deltaTime: TimeInterval) throws -> CubismFrameSnapshot {
        if let activeMotion {
            if deltaTime.isFinite {
                motionElapsedTime += max(0, deltaTime)
            }
            try apply(activeMotion)
        }

        coreLibrary.abi.updateModel(model)
        let evaluation = try evaluateFrame()
        currentParameterValues = try readParameterValues()
        currentDrawableEvaluations = evaluation.drawables
        coreLibrary.abi.resetDrawableDynamicFlags?(model)
        return evaluation.snapshot
    }

    private func apply(_ motion: CubismMotion) throws {
        let values = motion.evaluate(at: motionElapsedTime, looping: loopsMotion)
        var parameterValues: UnsafeMutablePointer<Float>?
        var partOpacities: UnsafeMutablePointer<Float>?

        for value in values {
            switch value.target {
            case .parameter:
                guard let index = parameterIndexes[value.id] else { continue }
                if parameterValues == nil {
                    parameterValues = coreLibrary.abi.getParameterValues(model)
                }
                guard let parameterValues else {
                    throw CubismCoreModelError.invalidCoreData("parameter value buffer is unavailable")
                }
                parameterValues[index] = value.value
            case .partOpacity:
                guard let index = partIndexes[value.id] else { continue }
                if partOpacities == nil {
                    partOpacities = coreLibrary.abi.getPartOpacities(model)
                }
                guard let partOpacities else {
                    throw CubismCoreModelError.invalidCoreData("part opacity buffer is unavailable")
                }
                partOpacities[index] = value.value
            case .model, .unknown:
                // Model-level curves require a higher-level behavior contract.
                // Parameter and part curves still evaluate without the SDK Framework.
                continue
            }
        }
    }

    private func evaluateFrame() throws -> (
        snapshot: CubismFrameSnapshot,
        drawables: [CubismDrawableEvaluation]
    ) {
        let modelPointer = UnsafeRawPointer(model)
        let drawableCount = try Self.validatedCount(
            coreLibrary.abi.getDrawableCount(modelPointer),
            kind: "drawable"
        )
        guard let identifiers = coreLibrary.abi.getDrawableIDs(modelPointer),
              let constantFlags = coreLibrary.abi.getDrawableConstantFlags(modelPointer),
              let dynamicFlags = coreLibrary.abi.getDrawableDynamicFlags(modelPointer),
              let textureIndices = coreLibrary.abi.getDrawableTextureIndices(modelPointer),
              let opacities = coreLibrary.abi.getDrawableOpacities(modelPointer),
              let maskCounts = coreLibrary.abi.getDrawableMaskCounts(modelPointer),
              let masks = coreLibrary.abi.getDrawableMasks(modelPointer),
              let vertexCounts = coreLibrary.abi.getDrawableVertexCounts(modelPointer),
              let vertexPositions = coreLibrary.abi.getDrawableVertexPositions(modelPointer),
              let vertexUVs = coreLibrary.abi.getDrawableVertexUVs(modelPointer),
              let indexCounts = coreLibrary.abi.getDrawableIndexCounts(modelPointer),
              let indices = coreLibrary.abi.getDrawableIndices(modelPointer) else {
            throw CubismCoreModelError.invalidCoreData("one or more drawable buffers are unavailable")
        }

        let renderOrders: UnsafePointer<Int32>?
        if let getRenderOrders = coreLibrary.abi.getRenderOrders {
            renderOrders = getRenderOrders(modelPointer)
        } else {
            renderOrders = coreLibrary.abi.getDrawableRenderOrders?(modelPointer) ?? nil
        }
        guard let renderOrders else {
            throw CubismCoreModelError.invalidCoreData("render order buffer is unavailable")
        }

        let explicitBlendModes = coreLibrary.abi.getDrawableBlendModes?(modelPointer)
        let rebuildStaticMetadata = drawableStaticMetadata.count != drawableCount
        if rebuildStaticMetadata {
            drawableStaticMetadata.removeAll(keepingCapacity: true)
            drawableStaticMetadata.reserveCapacity(drawableCount)
            drawableVertices.removeAll(keepingCapacity: true)
            drawableVertices.reserveCapacity(drawableCount)
        }

        var evaluations: [CubismDrawableEvaluation] = []
        evaluations.reserveCapacity(drawableCount)
        var snapshots: [CubismDrawableSnapshot] = []
        snapshots.reserveCapacity(drawableCount)

        for index in 0 ..< drawableCount {
            let vertexCount = try Self.validatedCount(vertexCounts[index], kind: "vertex")
            let dynamic = dynamicFlags[index]
            let metadata: DrawableStaticMetadata
            let vertices: [SIMD2<Float>]

            if rebuildStaticMetadata {
                guard let identifierPointer = identifiers[index] else {
                    throw CubismCoreModelError.invalidCoreData("drawable \(index) has no identifier")
                }
                let indexCount = try Self.validatedCount(indexCounts[index], kind: "index")
                let maskCount = try Self.validatedCount(maskCounts[index], kind: "mask")
                let maskIndices = try Self.readMasks(masks[index], count: maskCount)
                let maskSourceIdentifiers: [String] = maskIndices.compactMap { maskIndex -> String? in
                    guard maskIndex >= 0, maskIndex < drawableCount,
                          let maskIdentifier = identifiers[maskIndex] else {
                        return nil
                    }
                    return String(cString: maskIdentifier)
                }
                let textureIndex = Int(textureIndices[index])
                metadata = DrawableStaticMetadata(
                    identifier: String(cString: identifierPointer),
                    textureIndex: textureIndex,
                    textureURL: textureURLs.indices.contains(textureIndex) ? textureURLs[textureIndex] : nil,
                    constantFlags: constantFlags[index],
                    rawBlendMode: explicitBlendModes.map { Int($0[index]) },
                    maskIndices: maskIndices,
                    maskSourceIdentifiers: maskSourceIdentifiers,
                    uvs: try Self.readVector2Values(
                        vertexUVs[index],
                        count: vertexCount,
                        kind: "vertex UV"
                    ),
                    indices: try Self.readIndices(indices[index], count: indexCount)
                )
                vertices = try Self.readVector2Values(
                    vertexPositions[index],
                    count: vertexCount,
                    kind: "vertex position"
                )
                drawableStaticMetadata.append(metadata)
                drawableVertices.append(vertices)
            } else {
                metadata = drawableStaticMetadata[index]
                guard metadata.uvs.count == vertexCount else {
                    throw CubismCoreModelError.invalidCoreData("drawable \(index) changed its static vertex count")
                }
                if dynamic & CubismCoreConstants.vertexPositionsDidChange != 0 {
                    vertices = try Self.readVector2Values(
                        vertexPositions[index],
                        count: vertexCount,
                        kind: "vertex position"
                    )
                    drawableVertices[index] = vertices
                } else {
                    vertices = drawableVertices[index]
                }
            }

            let snapshot = CubismDrawableSnapshot(
                identifier: metadata.identifier,
                textureURL: metadata.textureURL,
                vertices: vertices,
                uvs: metadata.uvs,
                indices: metadata.indices,
                opacity: opacities[index],
                renderOrder: Int(renderOrders[index]),
                blendMode: Self.blendMode(
                    explicitValue: metadata.rawBlendMode,
                    constantFlags: metadata.constantFlags
                ),
                maskSourceIdentifiers: metadata.maskSourceIdentifiers,
                isInvertedMask: metadata.constantFlags & CubismCoreConstants.invertedMask != 0,
                isVisible: dynamic & CubismCoreConstants.visible != 0
            )
            snapshots.append(snapshot)
            evaluations.append(
                CubismDrawableEvaluation(
                    index: index,
                    identifier: metadata.identifier,
                    textureIndex: metadata.textureIndex,
                    constantFlags: metadata.constantFlags,
                    dynamicFlags: dynamic,
                    rawBlendMode: metadata.rawBlendMode,
                    maskIndices: metadata.maskIndices,
                    snapshot: snapshot
                )
            )
        }

        var sizeInPixels = [Float](repeating: 0, count: 2)
        var originInPixels = [Float](repeating: 0, count: 2)
        var pixelsPerUnit: Float = 0
        sizeInPixels.withUnsafeMutableBytes { sizeBytes in
            originInPixels.withUnsafeMutableBytes { originBytes in
                coreLibrary.abi.readCanvasInfo(
                    modelPointer,
                    sizeBytes.baseAddress,
                    originBytes.baseAddress,
                    &pixelsPerUnit
                )
            }
        }
        let denominator = pixelsPerUnit.isFinite && pixelsPerUnit > 0 ? pixelsPerUnit : 1
        let canvasSize = SIMD2<Float>(
            sizeInPixels[0] / denominator,
            sizeInPixels[1] / denominator
        )
        let canvasOrigin = SIMD2<Float>(
            originInPixels[0] / denominator,
            originInPixels[1] / denominator
        )
        guard canvasSize.x.isFinite,
              canvasSize.y.isFinite,
              canvasOrigin.x.isFinite,
              canvasOrigin.y.isFinite
        else {
            throw CubismCoreModelError.invalidCoreData("canvas information is not finite")
        }

        return (
            CubismFrameSnapshot(
                canvasSize: canvasSize,
                canvasOrigin: canvasOrigin,
                drawables: snapshots
            ),
            evaluations
        )
    }

    private func readParameterValues() throws -> [String: Float] {
        guard let values = coreLibrary.abi.getParameterValues(model) else {
            throw CubismCoreModelError.invalidCoreData("parameter value buffer is unavailable")
        }
        var result: [String: Float] = [:]
        result.reserveCapacity(parameterIndexes.count)
        for (identifier, index) in parameterIndexes {
            result[identifier] = values[index]
        }
        return result
    }

    private static func indexes(for identifiers: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($0.element, $0.offset) })
    }

    private static func readIDs(
        _ values: UnsafePointer<UnsafePointer<CChar>?>?,
        count: Int32,
        kind: String
    ) throws -> [String] {
        let validCount = try validatedCount(count, kind: kind)
        guard validCount == 0 || values != nil else {
            throw CubismCoreModelError.invalidCoreData("\(kind) identifiers are unavailable")
        }
        return try (0 ..< validCount).map { index in
            guard let identifier = values?[index] else {
                throw CubismCoreModelError.invalidCoreData("\(kind) \(index) has no identifier")
            }
            return String(cString: identifier)
        }
    }

    private static func validatedCount(_ value: Int32, kind: String) throws -> Int {
        guard value >= 0 else {
            throw CubismCoreModelError.invalidCoreData("\(kind) count is negative")
        }
        return Int(value)
    }

    private static func readVector2Values(
        _ values: UnsafeRawPointer?,
        count: Int,
        kind: String
    ) throws -> [SIMD2<Float>] {
        guard count == 0 || values != nil else {
            throw CubismCoreModelError.invalidCoreData("\(kind) buffer is unavailable")
        }
        guard let values else { return [] }
        let floats = values.assumingMemoryBound(to: Float.self)
        return (0 ..< count).map { index in
            SIMD2<Float>(floats[index * 2], floats[index * 2 + 1])
        }
    }

    private static func readIndices(
        _ values: UnsafePointer<UInt16>?,
        count: Int
    ) throws -> [UInt16] {
        guard count == 0 || values != nil else {
            throw CubismCoreModelError.invalidCoreData("triangle index buffer is unavailable")
        }
        guard let values else { return [] }
        return Array(UnsafeBufferPointer(start: values, count: count))
    }

    private static func readMasks(_ values: UnsafePointer<Int32>?, count: Int) throws -> [Int] {
        guard count == 0 || values != nil else {
            throw CubismCoreModelError.invalidCoreData("mask buffer is unavailable")
        }
        guard let values else { return [] }
        return Array(UnsafeBufferPointer(start: values, count: count)).map(Int.init)
    }

    private static func blendMode(explicitValue: Int?, constantFlags: UInt8) -> CubismBlendMode {
        switch explicitValue.map({ $0 & 0xFF }) {
        case 1, 3, 4:
            .additive
        case 2, 6, 7, 8:
            .multiplicative
        default:
            if constantFlags & CubismCoreConstants.additiveBlend != 0 {
                .additive
            } else if constantFlags & CubismCoreConstants.multiplicativeBlend != 0 {
                .multiplicative
            } else {
                .normal
            }
        }
    }
}
