import Metal
import XCTest
@testable import CubismMetalKit

final class CubismRenderColorPipelineTests: XCTestCase {
    func testTextureLoadingUsesSRGBDecoding() {
        XCTAssertTrue(MetalRenderer.texturesUseSRGB)
    }

    func testNormalBlendUsesPremultipliedSourceColor() {
        XCTAssertEqual(
            MetalRenderer.blendState(for: .normal),
            CubismBlendState(
                sourceRGB: .one,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        )
    }

    func testAdditiveAndMultiplicativeBlendStatesMatchCubismSemantics() {
        XCTAssertEqual(
            MetalRenderer.blendState(for: .additive),
            CubismBlendState(
                sourceRGB: .sourceAlpha,
                destinationRGB: .one,
                sourceAlpha: .one,
                destinationAlpha: .one
            )
        )
        XCTAssertEqual(
            MetalRenderer.blendState(for: .multiplicative),
            CubismBlendState(
                sourceRGB: .destinationColor,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .zero,
                destinationAlpha: .one
            )
        )
    }
}
