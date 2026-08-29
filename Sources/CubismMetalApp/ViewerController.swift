import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import CubismMetalKit

@MainActor
final class ViewerController: ObservableObject {
    @Published private(set) var modelURL: URL?
    @Published private(set) var modelTitle = "No model loaded"
    @Published private(set) var motionOptions: [CubismMotionOption] = []
    @Published private(set) var selectedMotionID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var rendererUnavailable = false
    @Published var loopsMotion = true {
        didSet {
            activeFrameSource?.loopsMotion = loopsMotion
        }
    }
    @Published var targetFrameRate: MetalRenderer.TargetFrameRate = .sixty {
        didSet {
            renderer?.setTargetFrameRate(targetFrameRate)
        }
    }

    private static let lastModelDirectoryKey = "CubismMetal.lastModelDirectory"

    private let logger = Logger(subsystem: "com.rayriffy.CubismMetal", category: "Viewer")
    private var activeFrameSource: CubismFrameSource?
    private weak var renderer: MetalRenderer?
    private var didScheduleInitialOpen = false
    private var hasRequestedModelLoad = false
    private var isApplyingMotionSelection = false

    var hasModel: Bool { activeFrameSource != nil }
    var hasBundledCore: Bool { CubismCoreLibrary.bundledLibraryURL() != nil }

    var coreRuntimeStatus: String {
        hasBundledCore ? "Bundled" : "Missing from app"
    }

    var coreRuntimeDetail: String {
        if let url = CubismCoreLibrary.bundledLibraryURL() {
            return url.path
        }
        return "Build with Vendor/CubismCore/libLive2DCubismCore.dylib"
    }

    var modelPath: String? {
        modelURL?.path
    }

    var rendererStatus: String {
        if rendererUnavailable { return "Metal unavailable" }
        guard renderer != nil else { return "Preparing Metal" }
        return "Metal · \(targetFrameRate.label)"
    }

    var motionSelection: Binding<String?> {
        Binding(
            get: { self.selectedMotionID },
            set: { self.selectMotion(id: $0) }
        )
    }

    func attach(renderer: MetalRenderer) {
        rendererUnavailable = false
        self.renderer = renderer
        renderer.setTargetFrameRate(targetFrameRate)
        renderer.onError = { [weak self] error in
            self?.showRuntimeError(error)
        }
        renderer.setFrameSource(activeFrameSource)
    }

    func rendererSetupFailed() {
        rendererUnavailable = true
        errorMessage = "Metal setup failed. This Mac needs a supported Metal device before a Cubism model can render."
    }

    func showInitialOpenPanelIfNeeded() {
        guard !didScheduleInitialOpen else { return }
        didScheduleInitialOpen = true

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !self.hasRequestedModelLoad else { return }
            self.openModelPanel()
        }
    }

    func openModelPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Live2D Cubism Model"
        panel.message = "Choose a .model3.json manifest or a .moc3 file with its sibling manifest."
        panel.prompt = "Open Model"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, Self.moc3Type]
        let filter = ModelOpenPanelFilter()
        panel.delegate = filter
        panel.directoryURL = lastModelDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(openedURL: url)
    }

    func open(urls: [URL]) {
        guard let url = urls.first else { return }
        load(openedURL: url)
        if urls.count > 1, modelURL == url.standardizedFileURL {
            errorMessage = "Opened \(url.lastPathComponent). This viewer displays one model at a time; the remaining \(urls.count - 1) file(s) were not opened."
        }
    }

    func load(openedURL: URL) {
        let normalizedURL = openedURL.standardizedFileURL
        guard !isLoading else { return }
        if normalizedURL == modelURL, hasModel { return }

        hasRequestedModelLoad = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            logger.info("Opening Live2D model \(normalizedURL.path, privacy: .public)")
            let newFrameSource = try CubismModelLoader().load(openedURL: normalizedURL)
            newFrameSource.loopsMotion = loopsMotion

            activeFrameSource = newFrameSource
            modelURL = normalizedURL
            modelTitle = newFrameSource.displayName
            motionOptions = newFrameSource.motions
            selectedMotionID = newFrameSource.selectedMotionID
            renderer?.setFrameSource(newFrameSource)
            persistLastDirectory(for: normalizedURL)
            logger.info("Loaded \(newFrameSource.displayName, privacy: .public) with Core \(newFrameSource.coreVersion, privacy: .public)")
        } catch {
            logger.error("Failed to load \(normalizedURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showLoadError(error, openedURL: normalizedURL)
        }
    }

    func selectMotion(id: String?) {
        guard !isApplyingMotionSelection, let activeFrameSource else { return }
        guard id != selectedMotionID else { return }

        let previousMotionID = selectedMotionID
        isApplyingMotionSelection = true
        defer { isApplyingMotionSelection = false }

        do {
            try activeFrameSource.selectMotion(id: id)
            selectedMotionID = activeFrameSource.selectedMotionID
            errorMessage = nil
        } catch {
            selectedMotionID = previousMotionID
            errorMessage = "Could not select that motion. \(error.localizedDescription)"
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func zoomIn() {
        renderer?.zoomCanvas(by: 1.2)
    }

    func zoomOut() {
        renderer?.zoomCanvas(by: 1 / 1.2)
    }

    func resetCanvasViewport() {
        renderer?.resetCanvasViewport()
    }

    private var lastModelDirectory: URL? {
        guard let path = UserDefaults.standard.string(forKey: Self.lastModelDirectoryKey) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func persistLastDirectory(for modelURL: URL) {
        UserDefaults.standard.set(
            modelURL.deletingLastPathComponent().path,
            forKey: Self.lastModelDirectoryKey
        )
    }

    private func showLoadError(_ error: Error, openedURL: URL) {
        if let coreError = error as? CubismCoreLibraryError,
           coreError == .sdkLibraryPathNotConfigured {
            errorMessage = "This CubismMetal build is missing the bundled Core runtime. Add the official SDK dylib at Vendor/CubismCore/libLive2DCubismCore.dylib, then rebuild the app."
            return
        }
        let currentModelNote = hasModel ? " The current model remains on screen." : ""
        errorMessage = "Could not load \(openedURL.lastPathComponent). \(error.localizedDescription)\(currentModelNote) Check the model folder and Cubism Core runtime setup."
    }

    private func showRuntimeError(_ error: Error) {
        errorMessage = "Metal could not render the current model. \(error.localizedDescription) Check the model assets and Cubism Core runtime setup."
    }

    private static var moc3Type: UTType {
        UTType(filenameExtension: "moc3") ?? .data
    }

    fileprivate static func supportsModelInput(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        return filename.hasSuffix(".model3.json") || url.pathExtension.lowercased() == "moc3"
    }
}

private final class ModelOpenPanelFilter: NSObject, NSOpenSavePanelDelegate {
    func panel(_: Any, shouldEnable url: URL) -> Bool {
        url.hasDirectoryPath || ViewerController.supportsModelInput(url)
    }
}
