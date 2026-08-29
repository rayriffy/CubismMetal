import Foundation
import XCTest
@testable import CubismMetalKit

final class CubismCoreLibraryTests: XCTestCase {
    func testFrameSnapshotUsesCanvasOriginForStableCanvasBounds() {
        let legacySnapshot = CubismFrameSnapshot(
            canvasSize: SIMD2<Float>(4, 6),
            drawables: []
        )
        XCTAssertEqual(legacySnapshot.canvasOrigin, .zero)
        XCTAssertEqual(legacySnapshot.canvasBounds.minimum, SIMD2<Float>(0, -6))
        XCTAssertEqual(legacySnapshot.canvasBounds.maximum, SIMD2<Float>(4, 0))

        let snapshot = CubismFrameSnapshot(
            canvasSize: SIMD2<Float>(4, 6),
            canvasOrigin: SIMD2<Float>(1.5, 4),
            drawables: []
        )
        XCTAssertEqual(snapshot.canvasBounds.minimum, SIMD2<Float>(-1.5, -2))
        XCTAssertEqual(snapshot.canvasBounds.maximum, SIMD2<Float>(2.5, 4))
    }

    func testExplicitURLWinsOverEnvironment() throws {
        let expected = URL(fileURLWithPath: "/tmp/libLive2DCubismCore.dylib")
        let discovered = try CubismCoreLibrary.configuredLibraryURL(
            libraryURL: expected,
            environment: [
                CubismCoreLibrary.environmentVariable: "/tmp/Live2DCubismCore.dylib",
            ]
        )

        XCTAssertEqual(discovered, expected.standardizedFileURL)
    }

    func testEnvironmentPathIsUsedWhenNoURLIsInjected() throws {
        let expected = URL(fileURLWithPath: "/tmp/libLive2DCubismCore.dylib")
        let discovered = try CubismCoreLibrary.configuredLibraryURL(
            environment: [CubismCoreLibrary.environmentVariable: expected.path]
        )

        XCTAssertEqual(discovered, expected.standardizedFileURL)
    }

    func testBundledLibraryIsFoundBeforeEnvironment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubismCoreBundleTests-\(UUID().uuidString).app", isDirectory: true)
        let bundledDirectory = root.appendingPathComponent("CubismCore", isDirectory: true)
        let bundledLibrary = bundledDirectory.appendingPathComponent("libLive2DCubismCore.dylib")
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try Data().write(to: bundledLibrary)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(
            CubismCoreLibrary.bundledLibraryURL(resourceURL: root, frameworksURL: nil),
            bundledLibrary
        )
        let discovered = try CubismCoreLibrary.configuredLibraryURL(
            environment: [CubismCoreLibrary.environmentVariable: "/tmp/other.dylib"],
            bundleResourceURL: root,
            bundleFrameworksURL: nil
        )
        XCTAssertEqual(discovered, bundledLibrary)
    }

    func testMissingConfigurationExplainsSDKRequirement() {
        XCTAssertThrowsError(
            try CubismCoreLibrary.configuredLibraryURL(environment: [:])
        ) { error in
            XCTAssertEqual(error as? CubismCoreLibraryError, .sdkLibraryPathNotConfigured)
            XCTAssertTrue(error.localizedDescription.contains("missing from this app build"))
        }
    }

    func testEditorBundlePathIsRejectedBeforeItCanLoad() {
        let editorURL = URL(
            fileURLWithPath: "/Applications/Live2D Cubism 5.3/res/libLive2DCubismCore.dylib"
        )

        XCTAssertThrowsError(
            try CubismCoreLibrary.configuredLibraryURL(libraryURL: editorURL)
        ) { error in
            XCTAssertEqual(
                error as? CubismCoreLibraryError,
                .editorBundleLibraryRejected(editorURL.standardizedFileURL)
            )
        }
    }

    func testUnexpectedDylibNameIsRejectedBeforeItCanLoad() {
        let unrelatedURL = URL(fileURLWithPath: "/tmp/libUnrelated.dylib")

        XCTAssertThrowsError(
            try CubismCoreLibrary.configuredLibraryURL(libraryURL: unrelatedURL)
        ) { error in
            XCTAssertEqual(
                error as? CubismCoreLibraryError,
                .unexpectedLibraryFilename(unrelatedURL.standardizedFileURL)
            )
        }
    }

    func testLive2DJNIRuntimeNameIsAccepted() throws {
        let jniURL = URL(fileURLWithPath: "/tmp/libLive2DCubismCoreJNI.dylib")
        let discovered = try CubismCoreLibrary.configuredLibraryURL(libraryURL: jniURL)
        XCTAssertEqual(discovered, jniURL.standardizedFileURL)
    }

    func testMissingConfiguredFileDoesNotAttemptToLoadAnything() {
        let missingURL = URL(
            fileURLWithPath: "/tmp/cubism-metal-tests/libLive2DCubismCore.dylib"
        )

        XCTAssertThrowsError(try CubismCoreLibrary(libraryURL: missingURL)) { error in
            XCTAssertEqual(
                error as? CubismCoreLibraryError,
                .libraryNotFound(missingURL.standardizedFileURL)
            )
        }
    }
}
