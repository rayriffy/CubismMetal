import AppKit
import MetalKit
import SwiftUI
import CubismMetalKit

struct MetalCanvas: NSViewRepresentable {
    @ObservedObject var viewer: ViewerController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = InteractiveMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.025, green: 0.035, blue: 0.06, alpha: 1).cgColor

        guard let renderer = MetalRenderer(view: view) else {
            viewer.rendererSetupFailed()
            return view
        }

        context.coordinator.renderer = renderer
        view.onPan = { [weak renderer, weak view] delta in
            guard let view else { return }
            renderer?.panCanvas(by: delta, in: view.bounds.size)
        }
        view.onZoom = { [weak renderer, weak view] factor, point in
            guard let view else { return }
            renderer?.zoomCanvas(by: factor, around: point, in: view.bounds.size)
        }
        view.onResetViewport = { [weak renderer] in
            renderer?.resetCanvasViewport()
        }
        viewer.attach(renderer: renderer)
        return view
    }

    func updateNSView(_: MTKView, context _: Context) {}

    static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
        coordinator.renderer?.setFrameSource(nil)
        nsView.delegate = nil
    }

    final class Coordinator {
        var renderer: MetalRenderer?
    }
}
