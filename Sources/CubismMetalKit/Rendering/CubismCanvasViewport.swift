import CoreGraphics
import simd

/// User-controlled view state layered over the renderer's model-fit transform.
/// Translation lives in Metal clip space, making pan feel identical at every
/// window size and backing scale.
public struct CubismCanvasViewport: Sendable, Equatable {
    public static let minimumZoom: Float = 0.25
    public static let maximumZoom: Float = 12

    public private(set) var zoom: Float = 1
    public private(set) var translation = SIMD2<Float>(repeating: 0)

    public init() {}

    public mutating func pan(by delta: CGSize, in canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              delta.width.isFinite, delta.height.isFinite
        else { return }

        translation += SIMD2<Float>(
            Float(delta.width / canvasSize.width * 2),
            Float(delta.height / canvasSize.height * 2)
        )
    }

    /// Zooms around a view-space point, preserving the model point below the
    /// cursor instead of pulling the content toward the canvas center.
    public mutating func zoom(by factor: Float, around point: CGPoint, in canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              factor.isFinite, factor > 0
        else { return }

        let newZoom = min(max(zoom * factor, Self.minimumZoom), Self.maximumZoom)
        guard newZoom != zoom else { return }

        let anchor = SIMD2<Float>(
            Float(point.x / canvasSize.width * 2 - 1),
            Float(point.y / canvasSize.height * 2 - 1)
        )
        translation = anchor - (anchor - translation) * (newZoom / zoom)
        zoom = newZoom
    }

    public mutating func reset() {
        zoom = 1
        translation = SIMD2<Float>(repeating: 0)
    }

    func applying(to transform: simd_float4x4) -> simd_float4x4 {
        let viewportTransform = simd_float4x4(columns: (
            SIMD4<Float>(zoom, 0, 0, 0),
            SIMD4<Float>(0, zoom, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, 0, 1)
        ))
        return viewportTransform * transform
    }
}
