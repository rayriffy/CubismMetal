import SwiftUI
import CubismMetalKit

struct ViewerWindow: View {
    @ObservedObject var viewer: ViewerController
    let appDelegate: CubismMetalAppDelegate

    var body: some View {
        NavigationSplitView {
            ViewerSidebar(viewer: viewer)
        } detail: {
            ZStack {
                MetalCanvas(viewer: viewer)

                if !viewer.hasModel {
                    EmptyCanvasState(viewer: viewer)
                }

                VStack(spacing: 12) {
                    if let errorMessage = viewer.errorMessage {
                        RuntimeErrorBanner(message: errorMessage, dismiss: viewer.dismissError)
                    }
                    Spacer()
                    RenderStatus(viewer: viewer)
                }
                .padding(20)
            }
            .background(Color(red: 0.025, green: 0.035, blue: 0.06))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 620)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: viewer.openModelPanel) {
                    Label("Open Model", systemImage: "folder")
                }

                Picker("Frame rate", selection: $viewer.targetFrameRate) {
                    ForEach(MetalRenderer.TargetFrameRate.allCases) { frameRate in
                        Text(frameRate.label).tag(frameRate)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 144)
            }
        }
        .onAppear {
            appDelegate.installOpenHandler(viewer.open(urls:))
        }
        .onOpenURL { url in
            viewer.open(urls: [url])
        }
        .task {
            viewer.showInitialOpenPanelIfNeeded()
        }
    }
}

private struct ViewerSidebar: View {
    @ObservedObject var viewer: ViewerController

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            List {
                Section("Model") {
                    Label(viewer.modelTitle, systemImage: viewer.hasModel ? "person.crop.rectangle" : "cube.transparent")
                        .lineLimit(1)
                    if let path = viewer.modelPath {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Renderer", value: viewer.rendererStatus)
                }

                Section("Playback") {
                    Toggle("Loop motion", isOn: $viewer.loopsMotion)

                    Picker("Motion", selection: viewer.motionSelection) {
                        Text("No motion").tag(nil as String?)
                        ForEach(viewer.motionOptions) { motion in
                            Text(motion.displayName).tag(Optional(motion.id))
                        }
                    }
                    .disabled(viewer.motionOptions.isEmpty)
                }

                Section("Performance") {
                    Picker("Target", selection: $viewer.targetFrameRate) {
                        ForEach(MetalRenderer.TargetFrameRate.allCases) { frameRate in
                            Text(frameRate.label).tag(frameRate)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button(action: viewer.openModelPanel) {
                        Label("Open Live2D Model…", systemImage: "folder")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.sidebar)
        }
        .frame(minWidth: 248, idealWidth: 280)
    }
}

private struct EmptyCanvasState: View {
    @ObservedObject var viewer: ViewerController

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
            Text(
                viewer.isLoading
                    ? "Loading Live2D model…"
                    : viewer.hasBundledCore ? "Open a Live2D Cubism model" : "Cubism Core is missing"
            )
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(
                viewer.hasBundledCore
                    ? "Choose a .model3.json manifest, or a .moc3 file beside its manifest."
                    : "This build needs the official Core dylib bundled before it can render a model."
            )
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            if viewer.hasBundledCore {
                Button("Open Model…", action: viewer.openModelPanel)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct RuntimeErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .frame(maxWidth: 680)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Runtime error: \(message)")
    }
}

private struct RenderStatus: View {
    @ObservedObject var viewer: ViewerController

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewer.hasModel ? .green : .white.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(viewer.rendererStatus)
            if viewer.hasModel {
                Text(viewer.loopsMotion ? "Looping" : "Play once")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
