import AppKit
import MetalKit

/// An MTKView with the direct-manipulation behaviour expected from a canvas.
/// Gesture deltas stay in AppKit points; the renderer converts them to clip
/// space using the current view bounds.
@MainActor
final class InteractiveMetalView: MTKView {
    var onPan: ((CGSize) -> Void)?
    var onZoom: ((Float, CGPoint) -> Void)?
    var onResetViewport: (() -> Void)?

    private var lastDragLocation: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        defer { lastDragLocation = location }
        guard let lastDragLocation else { return }

        onPan?(CGSize(
            width: location.x - lastDragLocation.x,
            height: location.y - lastDragLocation.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
        NSCursor.openHand.set()
        super.mouseUp(with: event)
    }

    override func magnify(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        onZoom?(Float(exp(event.magnification)), location)
    }

    override func scrollWheel(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }

        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.008 : 0.12
        let location = convert(event.locationInWindow, from: nil)
        onZoom?(Float(exp(delta * sensitivity)), location)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command) else {
            super.keyDown(with: event)
            return
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch event.charactersIgnoringModifiers {
        case "+", "=":
            onZoom?(1.2, center)
        case "-", "_":
            onZoom?(1 / 1.2, center)
        case "0":
            onResetViewport?()
        default:
            super.keyDown(with: event)
        }
    }
}
