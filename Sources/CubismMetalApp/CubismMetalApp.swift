import AppKit
import Darwin
import Foundation
import SwiftUI
import CubismMetalKit

@main
struct CubismMetalApplication: App {
    @NSApplicationDelegateAdaptor(CubismMetalAppDelegate.self) private var appDelegate
    @StateObject private var viewer = ViewerController()

    init() {
        CommandLineValidation.exitIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ViewerWindow(viewer: viewer, appDelegate: appDelegate)
                .background(WindowChromeConfigurator().allowsHitTesting(false))
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Model…") {
                    viewer.openModelPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Canvas") {
                Button("Zoom In") {
                    viewer.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    viewer.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Divider()

                Button("Reset View") {
                    viewer.resetCanvasViewport()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

@MainActor
final class CubismMetalAppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    private var openHandler: (([URL]) -> Void)?

    func installOpenHandler(_ handler: @escaping ([URL]) -> Void) {
        openHandler = handler
        guard !pendingURLs.isEmpty else { return }

        let urls = pendingURLs
        pendingURLs.removeAll()
        handler(urls)
    }

    func application(_: NSApplication, open urls: [URL]) {
        forward(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        forward(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: .success)
    }

    private func forward(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let openHandler {
            openHandler(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }
}

enum CommandLineValidation {
    static func exitIfRequested(arguments: [String] = CommandLine.arguments) {
        if let flagIndex = arguments.firstIndex(of: "--validate-core") {
            let valueIndex = arguments.index(after: flagIndex)
            guard valueIndex < arguments.endIndex, valueIndex == arguments.index(before: arguments.endIndex) else {
                print("INVALID --validate-core expects exactly one .model3.json or .moc3 path")
                exit(64)
            }

            let openedURL = URL(fileURLWithPath: arguments[valueIndex]).standardizedFileURL
            do {
                let session = try CubismModelLoader().load(openedURL: openedURL)
                let frame = try session.advance(by: 1.0 / 60.0)
                print("CORE VALID \(openedURL.path) drawables=\(frame.drawables.count) motions=\(session.motions.count) core=\(session.coreVersion)")
                exit(0)
            } catch {
                print("CORE INVALID \(openedURL.path): \(error.localizedDescription)")
                exit(1)
            }
        }

        if arguments.contains("--validate-renderer") {
            guard arguments.count == 2 else {
                print("INVALID --validate-renderer accepts no additional arguments")
                exit(64)
            }

            do {
                try MetalRenderer.validateBundledShaders()
                print("RENDERER VALID")
                exit(0)
            } catch {
                print("RENDERER INVALID: \(error.localizedDescription)")
                exit(1)
            }
        }

        guard let flagIndex = arguments.firstIndex(of: "--validate") else { return }

        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex, valueIndex == arguments.index(before: arguments.endIndex) else {
            print("INVALID --validate expects exactly one .model3.json or .moc3 path")
            exit(64)
        }

        let openedURL = URL(fileURLWithPath: arguments[valueIndex]).standardizedFileURL
        do {
            let manifest = try CubismModelManifest.load(openedURL: openedURL)
            try validateAssets(in: manifest)
            print("VALID \(openedURL.path) motions=\(manifest.motions.count) textures=\(manifest.textureURLs.count)")
            exit(0)
        } catch {
            print("INVALID \(openedURL.path): \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func validateAssets(in manifest: CubismModelManifest) throws {
        let fileManager = FileManager.default
        let assetURLs = [manifest.mocURL]
            + manifest.textureURLs
            + manifest.motions.map(manifest.resolvedMotionURL(for:))

        for assetURL in assetURLs where !fileManager.fileExists(atPath: assetURL.path) {
            throw ValidationError.missingAsset(assetURL)
        }
    }

    private enum ValidationError: LocalizedError {
        case missingAsset(URL)

        var errorDescription: String? {
            switch self {
            case let .missingAsset(url):
                "Missing referenced asset: \(url.path)"
            }
        }
    }
}
