import Darwin
import Foundation
import OSLog

/// Errors emitted while locating or opening the separately distributed Cubism
/// Core dynamic library.
///
/// Release builds embed the licensed Core dylib inside the app bundle. The
/// environment variable and explicit URL remain developer-only diagnostics.
public enum CubismCoreLibraryError: LocalizedError, Equatable, Sendable {
    case sdkLibraryPathNotConfigured
    case nonFileLibraryURL(URL)
    case editorBundleLibraryRejected(URL)
    case unexpectedLibraryFilename(URL)
    case libraryNotFound(URL)
    case libraryIsDirectory(URL)
    case libraryCouldNotOpen(URL, String)
    case missingRequiredSymbol(String, URL)

    public var errorDescription: String? {
        switch self {
        case .sdkLibraryPathNotConfigured:
            "Cubism Core is missing from this app build. Add the licensed libLive2DCubismCore.dylib to Vendor/CubismCore and rebuild."
        case let .nonFileLibraryURL(url):
            "Cubism Core must be a local SDK dylib, not \(url.absoluteString)."
        case let .editorBundleLibraryRejected(url):
            "\(url.path) appears to be an Editor-installed Cubism runtime. Bundle the licensed Core dylib with this app instead."
        case let .unexpectedLibraryFilename(url):
            "\(url.lastPathComponent) is not a recognized Cubism Core dylib name. Configure the official SDK's libLive2DCubismCore.dylib."
        case let .libraryNotFound(url):
            "The configured Cubism Core dylib does not exist at \(url.path)."
        case let .libraryIsDirectory(url):
            "The configured Cubism Core path is a directory: \(url.path)."
        case let .libraryCouldNotOpen(url, message):
            "Could not open Cubism Core at \(url.path): \(message)"
        case let .missingRequiredSymbol(symbol, url):
            "\(url.lastPathComponent) is not a compatible Cubism Core dylib; it is missing \(symbol). Use a matching official SDK for Native Core library."
        }
    }
}

/// A dynamically opened, licensed Cubism Core dylib.
///
/// The bridge first resolves the build-embedded runtime. It never searches the
/// system or the Cubism Editor; developer overrides stay available for local
/// diagnostics only.
public final class CubismCoreLibrary {
    public static let environmentVariable = "CUBISM_CORE_LIBRARY_PATH"
    public static let acceptedLibraryFilenames: Set<String> = [
        "libLive2DCubismCore.dylib",
        "libLive2DCubismCoreJNI.dylib",
        "Live2DCubismCore.dylib",
    ]

    public let libraryURL: URL
    public let version: UInt32

    private static let logger = Logger(
        subsystem: "com.rayriffy.CubismMetal",
        category: "CubismCore"
    )
    private let dynamicLibrary: CubismDynamicLibrary
    let abi: CubismCoreABI

    /// Finds the official Core dylib embedded by the app build. End users do
    /// not need to configure this path themselves.
    public static func bundledLibraryURL(
        resourceURL: URL? = Bundle.main.resourceURL,
        frameworksURL: URL? = Bundle.main.privateFrameworksURL,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [resourceURL?.appendingPathComponent("CubismCore", isDirectory: true), frameworksURL]
            .compactMap { $0 }
            .flatMap { directory in
                acceptedLibraryFilenames.map { directory.appendingPathComponent($0) }
            }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Resolves an explicitly supplied Core library URL without opening it.
    ///
    /// An injected URL wins over the environment, which makes application
    /// configuration and tests deterministic.
    public static func configuredLibraryURL(
        libraryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        bundleFrameworksURL: URL? = Bundle.main.privateFrameworksURL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let configuredURL: URL
        let source: String
        let isBundledRuntime: Bool
        if let libraryURL {
            configuredURL = libraryURL
            source = "developer override"
            isBundledRuntime = false
        } else if let bundledLibrary = bundledLibraryURL(
            resourceURL: bundleResourceURL,
            frameworksURL: bundleFrameworksURL,
            fileManager: fileManager
        ) {
            configuredURL = bundledLibrary
            source = "app bundle"
            isBundledRuntime = true
        } else if let rawPath = environment[environmentVariable], !rawPath.isEmpty {
            configuredURL = URL(
                fileURLWithPath: (rawPath as NSString).expandingTildeInPath
            )
            source = "environment"
            isBundledRuntime = false
        } else {
            throw CubismCoreLibraryError.sdkLibraryPathNotConfigured
        }

        guard configuredURL.isFileURL else {
            throw CubismCoreLibraryError.nonFileLibraryURL(configuredURL)
        }

        let normalizedURL = configuredURL.standardizedFileURL
        // The build-controlled app bundle is the only supported embedded
        // runtime location. Reject Editor paths supplied by developer overrides
        // or the environment, but never reject our own app's resources merely
        // because their path contains a `.app` component.
        if !isBundledRuntime && isEditorRuntime(normalizedURL) {
            throw CubismCoreLibraryError.editorBundleLibraryRejected(normalizedURL)
        }
        guard acceptedLibraryFilenames.contains(normalizedURL.lastPathComponent) else {
            throw CubismCoreLibraryError.unexpectedLibraryFilename(normalizedURL)
        }
        logger.info("Resolved Cubism Core from \(source, privacy: .public): \(normalizedURL.path, privacy: .public)")
        return normalizedURL
    }

    private static func isEditorRuntime(_ url: URL) -> Bool {
        let components = url.pathComponents
        if components.contains(where: { $0.hasSuffix(".app") }) {
            return true
        }

        return zip(components, components.dropFirst()).contains { parent, child in
            parent == "Applications" && child.hasPrefix("Live2D Cubism ")
        }
    }

    /// Opens the explicitly configured Core dylib and resolves its C ABI.
    public init(
        libraryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        let resolvedURL = try Self.configuredLibraryURL(
            libraryURL: libraryURL,
            environment: environment
        )

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
            throw CubismCoreLibraryError.libraryNotFound(resolvedURL)
        }
        guard !isDirectory.boolValue else {
            throw CubismCoreLibraryError.libraryIsDirectory(resolvedURL)
        }

        let openedLibrary = try CubismDynamicLibrary(url: resolvedURL)
        let resolvedABI = try CubismCoreABI(
            handle: openedLibrary.handle,
            libraryURL: resolvedURL
        )

        self.libraryURL = resolvedURL
        dynamicLibrary = openedLibrary
        abi = resolvedABI
        version = resolvedABI.getVersion()
        Self.logger.info("Loaded Cubism Core version \(self.version, privacy: .public) from \(resolvedURL.path, privacy: .public)")
    }
}

private final class CubismDynamicLibrary {
    let handle: UnsafeMutableRawPointer

    init(url: URL) throws {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "dynamic loader returned no diagnostic"
            throw CubismCoreLibraryError.libraryCouldNotOpen(url, message)
        }
        self.handle = handle
    }

    deinit {
        dlclose(handle)
    }
}
