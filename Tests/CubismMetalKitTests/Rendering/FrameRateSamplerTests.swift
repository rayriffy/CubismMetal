import XCTest
@testable import CubismMetalKit

final class FrameRateSamplerTests: XCTestCase {
    func testReportsMeasuredRateAtConfiguredInterval() {
        var sampler = FrameRateSampler(reportInterval: 0.5)

        XCTAssertNil(sampler.recordFrame(at: 0))
        XCTAssertNil(sampler.recordFrame(at: 0.25))
        XCTAssertEqual(sampler.recordFrame(at: 0.5)!, 4, accuracy: 0.0001)
    }

    func testResetAndOutOfOrderTimestampsDoNotProduceBogusRate() {
        var sampler = FrameRateSampler(reportInterval: 0.5)

        XCTAssertNil(sampler.recordFrame(at: 1))
        XCTAssertNil(sampler.recordFrame(at: 0.5))
        XCTAssertNil(sampler.recordFrame(at: 0.75))
        XCTAssertEqual(sampler.recordFrame(at: 1)!, 4, accuracy: 0.0001)
    }
}
