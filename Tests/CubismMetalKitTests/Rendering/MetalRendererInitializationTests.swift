import AppKit
import MetalKit
import XCTest
@testable import CubismMetalKit

@MainActor
final class MetalRendererInitializationTests: XCTestCase {
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
