import Foundation
import simd

public enum CubismBlendMode: Sendable, Equatable {
    case normal
    case additive
    case multiplicative
}

public struct CubismMotionOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let group: String
    public let displayName: String

    public init(id: String, group: String, displayName: String) {
        self.id = id
        self.group = group
        self.displayName = displayName
    }
}

public struct CubismDrawableSnapshot: Sendable {
    public let identifier: String
    public let textureURL: URL?
    public let vertices: [SIMD2<Float>]
    public let uvs: [SIMD2<Float>]
    public let indices: [UInt16]
    public let opacity: Float
    public let renderOrder: Int
    public let blendMode: CubismBlendMode
    public let maskSourceIdentifiers: [String]
    public let isInvertedMask: Bool
    public let isVisible: Bool

    public init(
        identifier: String,
        textureURL: URL?,
        vertices: [SIMD2<Float>],
        uvs: [SIMD2<Float>],
        indices: [UInt16],
        opacity: Float,
        renderOrder: Int,
        blendMode: CubismBlendMode = .normal,
        maskSourceIdentifiers: [String] = [],
        isInvertedMask: Bool = false,
        isVisible: Bool = true
    ) {
        self.identifier = identifier
        self.textureURL = textureURL
        self.vertices = vertices
        self.uvs = uvs
        self.indices = indices
        self.opacity = opacity
        self.renderOrder = renderOrder
        self.blendMode = blendMode
        self.maskSourceIdentifiers = maskSourceIdentifiers
        self.isInvertedMask = isInvertedMask
        self.isVisible = isVisible
    }

    public var isRenderable: Bool {
        isVisible
            && opacity > 0
            && textureURL != nil
            && vertices.count == uvs.count
            && !vertices.isEmpty
            && !indices.isEmpty
    }
}

public struct CubismFrameSnapshot: Sendable {
    public let canvasSize: SIMD2<Float>
    /// The Cubism Core canvas center, normalized from pixels into model units.
    public let canvasOrigin: SIMD2<Float>
    public let drawables: [CubismDrawableSnapshot]

    public init(canvasSize: SIMD2<Float>, drawables: [CubismDrawableSnapshot]) {
        self.init(canvasSize: canvasSize, canvasOrigin: .zero, drawables: drawables)
    }

    public init(
        canvasSize: SIMD2<Float>,
        canvasOrigin: SIMD2<Float>,
        drawables: [CubismDrawableSnapshot]
    ) {
        self.canvasSize = canvasSize
        self.canvasOrigin = canvasOrigin
        self.drawables = drawables
    }

    public var visibleDrawablesInRenderOrder: [CubismDrawableSnapshot] {
        drawables
            .filter(\.isRenderable)
            .sorted { $0.renderOrder < $1.renderOrder }
    }

    public var bounds: CubismBounds? {
        let points = drawables.lazy
            .filter(\.isVisible)
            .flatMap(\.vertices)
        return CubismBounds(points: points)
    }

    /// Immutable canvas extents in the same model-space coordinates as drawable vertices.
    public var canvasBounds: CubismBounds {
        CubismBounds(
            minimum: SIMD2<Float>(-canvasOrigin.x, canvasOrigin.y - canvasSize.y),
            maximum: SIMD2<Float>(canvasSize.x - canvasOrigin.x, canvasOrigin.y)
        )
    }
}

public struct CubismBounds: Sendable, Equatable {
    public let minimum: SIMD2<Float>
    public let maximum: SIMD2<Float>

    public init(minimum: SIMD2<Float>, maximum: SIMD2<Float>) {
        self.minimum = simd_min(minimum, maximum)
        self.maximum = simd_max(minimum, maximum)
    }

    public init?<S: Sequence>(points: S) where S.Element == SIMD2<Float> {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }

        var minimum = first
        var maximum = first
        while let point = iterator.next() {
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }

        self.minimum = minimum
        self.maximum = maximum
    }

    public var center: SIMD2<Float> { (minimum + maximum) * 0.5 }
    public var size: SIMD2<Float> { maximum - minimum }
}

public protocol CubismFrameSource: AnyObject {
    var displayName: String { get }
    var motions: [CubismMotionOption] { get }
    var selectedMotionID: String? { get }
    var loopsMotion: Bool { get set }

    func selectMotion(id: String?) throws
    func advance(by deltaTime: TimeInterval) throws -> CubismFrameSnapshot
}

public enum CubismRuntimeError: LocalizedError, Sendable, Equatable {
    case unavailable(String)
    case invalidAsset(String)
    case unsupported(String)
    case loadingFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .invalidAsset(message), let .unsupported(message), let .loadingFailed(message):
            message
        }
    }
}
