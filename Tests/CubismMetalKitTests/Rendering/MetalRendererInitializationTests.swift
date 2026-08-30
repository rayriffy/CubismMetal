import AppKit
import MetalKit
import XCTest
@testable import CubismMetalKit

@MainActor
final class MetalRendererInitializationTests: XCTestCase {
    func testLocatesPackagedShaderInApplicationResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubismMetalShaderTests-\(UUID().uuidString)", isDirectory: true)
        let shaderURL = root
            .appendingPathComponent("CubismMetal_CubismMetalKit.bundle", isDirectory: true)
            .appendingPathComponent("Shaders", isDirectory: true)
            .appendingPathComponent("CubismShaders.metal")
        try FileManager.default.createDirectory(
            at: shaderURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("kernel void shader() {}".utf8).write(to: shaderURL)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(
            MetalRenderer.packagedShaderSourceURL(resourceURL: root),
            shaderURL
        )
    }

    func testInitializesMaskPipeline() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device is available on this Mac.")
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CubismMetalKit/Shaders/CubismShaders.metal")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)

        XCTAssertNoThrow(try MetalRenderer.makeMaskPipeline(device: device, library: library))
    }
}
