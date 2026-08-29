import Foundation

public enum CubismCoreModelError: LocalizedError, Equatable, Sendable {
    case emptyMoc(URL)
    case mocTooLarge(URL)
    case inconsistentMoc(URL)
    case couldNotReviveMoc(URL)
    case invalidModelAllocation(URL)
    case unsupportedOffscreenComposition(URL)
    case invalidCoreData(String)
    case unknownMotion(String)

    public var errorDescription: String? {
        switch self {
        case let .emptyMoc(url):
            "The Cubism model file is empty: \(url.lastPathComponent)."
        case let .mocTooLarge(url):
            "The Cubism model file is too large for the Core ABI: \(url.lastPathComponent)."
        case let .inconsistentMoc(url):
            "Cubism Core reported that \(url.lastPathComponent) is not a consistent .moc3 file."
        case let .couldNotReviveMoc(url):
            "Cubism Core could not open \(url.lastPathComponent). The model may require a newer official Core library."
        case let .invalidModelAllocation(url):
            "Cubism Core could not create a model instance for \(url.lastPathComponent)."
        case let .unsupportedOffscreenComposition(url):
            "\(url.lastPathComponent) uses Cubism offscreen composition, which this direct Metal renderer does not yet support."
        case let .invalidCoreData(message):
            "Cubism Core returned invalid model data: \(message)"
        case let .unknownMotion(id):
            "The selected Cubism motion is not part of this model: \(id)."
        }
    }
}

/// The complete Core-derived state for one drawable at the instant a frame is
/// evaluated. `snapshot` is renderer-facing; the remaining fields preserve raw
/// Core state for diagnostics and future render-path optimizations.
public struct CubismDrawableEvaluation: Sendable {
    public let index: Int
    public let identifier: String
    public let textureIndex: Int
    public let constantFlags: UInt8
    public let dynamicFlags: UInt8
    public let rawBlendMode: Int?
    public let maskIndices: [Int]
    public let snapshot: CubismDrawableSnapshot
}

enum CubismCoreConstants {
    static let mocAlignment = 64
    static let modelAlignment = 16
    static let additiveBlend: UInt8 = 1 << 0
    static let multiplicativeBlend: UInt8 = 1 << 1
    static let invertedMask: UInt8 = 1 << 3
    static let visible: UInt8 = 1 << 0
}

final class CubismAlignedStorage {
    let pointer: UnsafeMutableRawPointer

    init(byteCount: Int, alignment: Int) {
        precondition(byteCount > 0)
        pointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
    }

    convenience init(copying data: Data, alignment: Int) {
        self.init(byteCount: data.count, alignment: alignment)
        data.withUnsafeBytes { source in
            guard let sourceAddress = source.baseAddress else { return }
            pointer.copyMemory(from: sourceAddress, byteCount: data.count)
        }
    }

    deinit {
        pointer.deallocate()
    }
}
