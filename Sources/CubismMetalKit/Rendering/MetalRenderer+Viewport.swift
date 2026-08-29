import CoreGraphics

extension MetalRenderer {
    /// Pans by an AppKit view-space delta. Positive deltas move the model in
    /// the same direction as the user's drag.
    public func panCanvas(by delta: CGSize, in canvasSize: CGSize) {
        canvasViewport.pan(by: delta, in: canvasSize)
    }

    /// Applies a cursor-anchored zoom factor from pinch, scroll, or keyboard
    /// interaction. The viewport bounds prevent runaway precision loss.
    public func zoomCanvas(by factor: Float, around point: CGPoint, in canvasSize: CGSize) {
        canvasViewport.zoom(by: factor, around: point, in: canvasSize)
    }

    public func resetCanvasViewport() {
        canvasViewport.reset()
    }
}
