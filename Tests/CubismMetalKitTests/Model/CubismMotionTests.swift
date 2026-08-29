import Foundation
import XCTest
@testable import CubismMetalKit

final class CubismMotionTests: XCTestCase {
    func testEvaluatesAllCompactSegmentKinds() throws {
        let motion = try CubismMotion(data: Data(motionJSON.utf8))

        XCTAssertEqual(motion.metadata.duration, 2)
        XCTAssertFalse(motion.metadata.loop)
        XCTAssertEqual(
            try XCTUnwrap(motion.value(for: .parameter, id: "Linear", at: 0.5)),
            2.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(motion.value(for: .parameter, id: "Bezier", at: 0.5)),
            5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(motion.value(for: .parameter, id: "Stepped", at: 0.5)),
            3,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(motion.value(for: .parameter, id: "InverseStepped", at: 0.5)),
            7,
            accuracy: 0.0001
        )
    }

    func testLoopsByDefaultAndCanClampAtDuration() throws {
        let motion = try CubismMotion(data: Data(motionJSON.utf8))

        XCTAssertEqual(motion.playbackTime(for: 2.25), 0.25, accuracy: 0.0001)
        XCTAssertEqual(motion.playbackTime(for: 2.25, looping: false), 2, accuracy: 0.0001)
        XCTAssertEqual(
            try XCTUnwrap(motion.value(for: .parameter, id: "Linear", at: 2.25)),
            1.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(motion.value(for: .parameter, id: "Linear", at: 2.25, looping: false)),
            10,
            accuracy: 0.0001
        )
    }

    func testRejectsUnknownCompactSegmentType() {
        let invalidJSON = """
        {
          "Version": 3,
          "Meta": { "Duration": 1, "Fps": 60 },
          "Curves": [{
            "Target": "Parameter", "Id": "ParamAngleX", "Segments": [0, 0, 99, 1, 1]
          }]
        }
        """

        XCTAssertThrowsError(try CubismMotion(data: Data(invalidJSON.utf8))) { error in
            guard case CubismMotionError.invalidSegmentType(let curveID, let value) = error else {
                return XCTFail("Expected invalid segment type, got \(error)")
            }
            XCTAssertEqual(curveID, "ParamAngleX")
            XCTAssertEqual(value, 99)
        }
    }

    private var motionJSON: String {
        """
        {
          "Version": 3,
          "Meta": {
            "Duration": 2,
            "Fps": 60,
            "Loop": false,
            "AreBeziersRestricted": true
          },
          "Curves": [
            {
              "Target": "Parameter", "Id": "Linear",
              "Segments": [0, 0, 0, 2, 10]
            },
            {
              "Target": "Parameter", "Id": "Bezier",
              "Segments": [0, 0, 1, 0.3333333333, 0, 0.6666666667, 10, 1, 10]
            },
            {
              "Target": "Parameter", "Id": "Stepped",
              "Segments": [0, 3, 2, 1, 7]
            },
            {
              "Target": "Parameter", "Id": "InverseStepped",
              "Segments": [0, 3, 3, 1, 7]
            }
          ]
        }
        """
    }
}
