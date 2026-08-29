import AppKit
import SwiftUI

/// Keeps the Metal canvas below the system's Liquid Glass titlebar and toolbar.
/// The chrome can remain translucent because it sees only the window's adaptive
/// background, never the detail renderer or another window behind it.
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context _: Context) -> WindowChromeView {
        WindowChromeView()
    }

    func updateNSView(_ nsView: WindowChromeView, context _: Context) {
        nsView.configureWindow()
    }
}

final class WindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
    }
}
