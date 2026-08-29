import CoreGraphics
import XCTest
@testable import CubismMetalKit

final class CubismCanvasViewportTests: XCTestCase {
    func testPanConvertsCanvasPointsToClipSpace() {
        var viewport = CubismCanvasViewport()
        viewport.pan(
            by: CGSize(width: 100, height: -50),
            in: CGSize(width: 1_000, height: 500)
        )

        XCTAssertEqual(viewport.translation, SIMD2<Float>(0.2, -0.2))
    }

    func testZoomKeepsCursorAnchorInPlace() {
        var viewport = CubismCanvasViewport()
        viewport.zoom(
            by: 2,
            around: CGPoint(x: 250, y: 300),
            in: CGSize(width: 1_000, height: 600)
        )

        XCTAssertEqual(viewport.zoom, 2)
        XCTAssertEqual(viewport.translation, SIMD2<Float>(0.5, 0))
    }

    func testZoomClampsAndResetRestoresModelFit() {
        var viewport = CubismCanvasViewport()
        let canvasSize = CGSize(width: 800, height: 600)
        viewport.zoom(by: 100, around: CGPoint(x: 400, y: 300), in: canvasSize)
        XCTAssertEqual(viewport.zoom, CubismCanvasViewport.maximumZoom)

        viewport.pan(by: CGSize(width: 40, height: 20), in: canvasSize)
        viewport.reset()
        XCTAssertEqual(viewport.zoom, 1)
        XCTAssertEqual(viewport.translation, .zero)
    }
}
