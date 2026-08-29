import Foundation
import XCTest
@testable import CubismMetalKit

final class CubismModelManifestTests: XCTestCase {
    func testLoadsFileReferencesAndResolvesRelativeAssets() throws {
        let directory = try makeTemporaryDirectory()
        let modelDirectory = directory.appendingPathComponent("Character", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let manifestURL = modelDirectory.appendingPathComponent("Character.model3.json")
        try fixtureManifest(moc: "Character.moc3").write(to: manifestURL, atomically: true, encoding: .utf8)

        let manifest = try CubismModelManifest.load(from: manifestURL)

        XCTAssertEqual(manifest.version, 3)
        XCTAssertEqual(manifest.mocURL.path, modelDirectory.appendingPathComponent("Character.moc3").path)
        XCTAssertEqual(
            manifest.textureURLs.map(\.path),
            [
                modelDirectory.appendingPathComponent("textures/texture_00.png").path,
                modelDirectory.appendingPathComponent("textures/texture_01.png").path,
            ]
        )
        XCTAssertEqual(manifest.motions.map(\.group), ["Idle", "TapBody"])
        XCTAssertEqual(manifest.motions.map(\.displayName), ["idle", "tap"])
        XCTAssertEqual(manifest.motionOptions.map(\.group), ["Idle", "TapBody"])

        let tapMotion = try XCTUnwrap(manifest.motions.first { $0.group == "TapBody" })
        XCTAssertEqual(
            manifest.resolvedMotionURL(for: tapMotion).path,
            modelDirectory.appendingPathComponent("motions/tap.motion3.json").path
        )
        XCTAssertEqual(tapMotion.reference.sound, "sounds/tap.wav")
        XCTAssertEqual(tapMotion.reference.fadeInTime, 0.15)
    }

    func testMoc3InputFindsOnlyManifestThatReferencesIt() throws {
        let directory = try makeTemporaryDirectory()
        let mocURL = directory.appendingPathComponent("Loose.moc3")
        try Data([0, 1, 2]).write(to: mocURL)
        try fixtureManifest(moc: "Other.moc3").write(
            to: directory.appendingPathComponent("A-unrelated.model3.json"),
            atomically: true,
            encoding: .utf8
        )
        let matchingManifestURL = directory.appendingPathComponent("B-matching.model3.json")
        try fixtureManifest(moc: "Loose.moc3").write(
            to: matchingManifestURL,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            try CubismModelLocator.siblingManifestURL(for: mocURL)?.resolvingSymlinksInPath(),
            matchingManifestURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            try CubismModelManifest.load(openedURL: mocURL).sourceURL.resolvingSymlinksInPath(),
            matchingManifestURL.resolvingSymlinksInPath()
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CubismModelManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func fixtureManifest(moc: String) -> String {
        """
        {
          "Version": 3,
          "FileReferences": {
            "Moc": "\(moc)",
            "Textures": ["textures/texture_00.png", "textures/texture_01.png"],
            "Motions": {
              "TapBody": [{
                "File": "motions/tap.motion3.json",
                "Sound": "sounds/tap.wav",
                "FadeInTime": 0.15,
                "FadeOutTime": 0.25
              }],
              "Idle": [{ "File": "motions/idle.motion3.json" }]
            }
          },
          "Groups": [{ "Target": "Parameter", "Name": "EyeBlink", "Ids": ["ParamEyeLOpen"] }],
          "HitAreas": [{ "Id": "HitAreaHead", "Name": "Head" }]
        }
        """
    }
}
