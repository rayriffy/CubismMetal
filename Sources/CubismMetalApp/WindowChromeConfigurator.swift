import AppKit
import SwiftUI

/// Keeps the system titlebar and toolbar outside the Metal content area. SwiftUI
/// windows can otherwise adopt a transparent full-size content view, letting a
/// canvas (or another window behind it) show through the chrome.
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
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
    }
}
