import Darwin
import Foundation
import simd
import CubismMetalKit

@main
enum CubismMetalVerification {
    static func main() {
        do {
            try verifyManifestResolution()
            try verifyMotionPlayback()
            try verifyStableCanvasBounds()
            print("cubism-metal verification runner passed")
        } catch {
            fputs("verification failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func verifyManifestResolution() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubismMetalVerification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let mocURL = directory.appendingPathComponent("Character.moc3")
        let manifestURL = directory.appendingPathComponent("Character.model3.json")
        try Data([0, 1, 2]).write(to: mocURL)
        try manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)

        let manifest = try CubismModelManifest.load(openedURL: mocURL)
        try require(manifest.sourceURL == manifestURL, "standalone MOC3 did not resolve its sibling manifest")
        try require(manifest.mocURL == mocURL, "manifest MOC3 path did not resolve relatively")
        try require(manifest.textureURLs.map(\.lastPathComponent) == ["texture_00.png"], "texture references did not resolve")
        try require(manifest.motionOptions.map(\.group) == ["Idle"], "motion group was not enumerated")
    }

    private static func verifyMotionPlayback() throws {
        let motion = try CubismMotion(data: Data(motionJSON.utf8))
        try require(approximately(motion.value(for: .parameter, id: "ParamAngleX", at: 0.5), 2.5), "linear motion evaluation is wrong")
        try require(approximately(motion.value(for: .parameter, id: "ParamAngleX", at: 2.25), 1.25), "default motion looping is wrong")
        try require(approximately(motion.value(for: .parameter, id: "ParamAngleX", at: 2.25, looping: false), 10), "non-looping motion did not clamp")
    }

    private static func verifyStableCanvasBounds() throws {
        let frame = CubismFrameSnapshot(
            canvasSize: SIMD2<Float>(4, 6),
            canvasOrigin: SIMD2<Float>(1.5, 4),
            drawables: []
        )
        try require(frame.canvasBounds.minimum == SIMD2<Float>(-1.5, -2), "canvas minimum is unstable")
        try require(frame.canvasBounds.maximum == SIMD2<Float>(2.5, 4), "canvas maximum is unstable")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw VerificationFailure(message: message) }
    }

    private static func approximately(_ value: Float?, _ expected: Float, tolerance: Float = 0.0001) -> Bool {
        guard let value else { return false }
        return abs(value - expected) <= tolerance
    }

    private static let manifestJSON = """
    {
      "Version": 3,
      "FileReferences": {
        "Moc": "Character.moc3",
        "Textures": ["textures/texture_00.png"],
        "Motions": { "Idle": [{ "File": "motions/idle.motion3.json" }] }
      }
    }
    """

    private static let motionJSON = """
    {
      "Version": 3,
      "Meta": { "Duration": 2, "Fps": 60, "Loop": false },
      "Curves": [{
        "Target": "Parameter", "Id": "ParamAngleX",
        "Segments": [0, 0, 0, 2, 10]
      }]
    }
    """
}

private struct VerificationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

