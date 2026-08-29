import Foundation

/// A decoded `.model3.json` descriptor rooted at its on-disk location.
///
/// Cubism model descriptors reference all companion assets with paths relative
/// to the descriptor itself. This type keeps those raw paths intact and offers
/// resolved file URLs for the native runtime.
public struct CubismModelManifest: Sendable, Equatable {
    public let version: Int
    public let fileReferences: CubismModelFileReferences
    public let groups: [CubismModelGroup]
    public let hitAreas: [CubismHitArea]
    public let sourceURL: URL

    public init(data: Data, sourceURL: URL) throws {
        let descriptor = try JSONDecoder().decode(Descriptor.self, from: data)
        version = descriptor.version
        fileReferences = descriptor.fileReferences
        groups = descriptor.groups
        hitAreas = descriptor.hitAreas
        self.sourceURL = sourceURL.standardizedFileURL
    }

    public static func load(from url: URL) throws -> Self {
        try Self(data: Data(contentsOf: url), sourceURL: url)
    }

    /// Loads a primary `.model3.json` input or finds the matching sibling
    /// manifest when the user selects a standalone `.moc3` file.
    public static func load(openedURL: URL, fileManager: FileManager = .default) throws -> Self {
        let filename = openedURL.lastPathComponent.lowercased()
        if filename.hasSuffix(".model3.json") {
            return try load(from: openedURL)
        }

        guard openedURL.pathExtension.lowercased() == "moc3" else {
            throw CubismModelManifestError.unsupportedInput(openedURL)
        }
        guard let manifestURL = try CubismModelLocator.siblingManifestURL(
            for: openedURL,
            fileManager: fileManager
        ) else {
            throw CubismModelManifestError.companionManifestNotFound(openedURL)
        }
        return try load(from: manifestURL)
    }

    public var mocURL: URL {
        resolvedURL(for: fileReferences.moc)
    }

    public var textureURLs: [URL] {
        fileReferences.textures.map(resolvedURL(for:))
    }

    /// Motion references flattened into a deterministic group/name order.
    public var motions: [CubismModelMotion] {
        fileReferences.motions
            .keys
            .sorted()
            .flatMap { group in
                fileReferences.motions[group, default: []].enumerated().map { index, reference in
                    CubismModelMotion(group: group, index: index, reference: reference)
                }
            }
    }

    /// Presentation-ready choices for the native viewer's motion menu.
    public var motionOptions: [CubismMotionOption] {
        motions.map {
            CubismMotionOption(id: $0.id, group: $0.group, displayName: $0.displayName)
        }
    }

    public func resolvedMotionURL(for motion: CubismModelMotion) -> URL {
        resolvedURL(for: motion.reference.file)
    }

    /// Resolves a Cubism asset path relative to this `.model3.json` file.
    public func resolvedURL(for reference: String) -> URL {
        if reference.hasPrefix("/") {
            return URL(fileURLWithPath: reference).standardizedFileURL
        }
        return URL(
            fileURLWithPath: reference,
            relativeTo: sourceURL.deletingLastPathComponent()
        ).standardizedFileURL
    }
}

public enum CubismModelManifestError: LocalizedError, Sendable, Equatable {
    case unsupportedInput(URL)
    case companionManifestNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedInput(url):
            "Expected a .model3.json or .moc3 file, received \(url.lastPathComponent)."
        case let .companionManifestNotFound(url):
            "No .model3.json sibling references \(url.lastPathComponent)."
        }
    }
}

/// Common `FileReferences` entries in the Cubism 3 model descriptor.
public struct CubismModelFileReferences: Decodable, Sendable, Equatable {
    public let moc: String
    public let textures: [String]
    public let motions: [String: [CubismModelMotionReference]]
    public let expressions: [CubismModelExpressionReference]
    public let physics: String?
    public let pose: String?
    public let userData: String?
    public let displayInfo: String?

    private enum CodingKeys: String, CodingKey {
        case moc = "Moc"
        case textures = "Textures"
        case motions = "Motions"
        case expressions = "Expressions"
        case physics = "Physics"
        case pose = "Pose"
        case userData = "UserData"
        case displayInfo = "DisplayInfo"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moc = try container.decode(String.self, forKey: .moc)
        textures = try container.decodeIfPresent([String].self, forKey: .textures) ?? []
        motions = try container.decodeIfPresent([String: [CubismModelMotionReference]].self, forKey: .motions) ?? [:]
        expressions = try container.decodeIfPresent([CubismModelExpressionReference].self, forKey: .expressions) ?? []
        physics = try container.decodeIfPresent(String.self, forKey: .physics)
        pose = try container.decodeIfPresent(String.self, forKey: .pose)
        userData = try container.decodeIfPresent(String.self, forKey: .userData)
        displayInfo = try container.decodeIfPresent(String.self, forKey: .displayInfo)
    }
}

public struct CubismModelMotionReference: Decodable, Sendable, Hashable {
    public let file: String
    public let sound: String?
    public let fadeInTime: TimeInterval?
    public let fadeOutTime: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case file = "File"
        case sound = "Sound"
        case fadeInTime = "FadeInTime"
        case fadeOutTime = "FadeOutTime"
    }
}

public struct CubismModelExpressionReference: Decodable, Sendable, Hashable {
    public let name: String
    public let file: String

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case file = "File"
    }
}

public struct CubismModelMotion: Identifiable, Hashable, Sendable {
    public let id: String
    public let group: String
    public let index: Int
    public let reference: CubismModelMotionReference

    public init(group: String, index: Int, reference: CubismModelMotionReference) {
        id = "\(group)#\(index):\(reference.file)"
        self.group = group
        self.index = index
        self.reference = reference
    }

    public var displayName: String {
        reference.file
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: ".motion3.json", with: "")
            ?? reference.file
    }
}

public struct CubismModelGroup: Decodable, Sendable, Equatable {
    public let target: String
    public let name: String
    public let ids: [String]

    private enum CodingKeys: String, CodingKey {
        case target = "Target"
        case name = "Name"
        case ids = "Ids"
    }
}

public struct CubismHitArea: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

/// Finds a `.model3.json` descriptor that explicitly references a selected
/// standalone `.moc3` file. No `.moc3` binary parsing is needed for discovery.
public enum CubismModelLocator {
    public static func siblingManifestURL(
        for moc3URL: URL,
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard moc3URL.pathExtension.lowercased() == "moc3" else { return nil }

        let normalizedMocURL = moc3URL.standardizedFileURL
        let directory = normalizedMocURL.deletingLastPathComponent()
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.lowercased().hasSuffix(".model3.json") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for candidate in candidates {
            guard let manifest = try? CubismModelManifest.load(from: candidate) else { continue }
            if manifest.mocURL.standardizedFileURL == normalizedMocURL {
                return candidate
            }
        }
        return nil
    }
}

private extension CubismModelManifest {
    struct Descriptor: Decodable {
        let version: Int
        let fileReferences: CubismModelFileReferences
        let groups: [CubismModelGroup]
        let hitAreas: [CubismHitArea]

        private enum CodingKeys: String, CodingKey {
            case version = "Version"
            case fileReferences = "FileReferences"
            case groups = "Groups"
            case hitAreas = "HitAreas"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            fileReferences = try container.decode(CubismModelFileReferences.self, forKey: .fileReferences)
            groups = try container.decodeIfPresent([CubismModelGroup].self, forKey: .groups) ?? []
            hitAreas = try container.decodeIfPresent([CubismHitArea].self, forKey: .hitAreas) ?? []
        }
    }
}
