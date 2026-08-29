import Foundation

/// A parsed `.motion3.json` animation. It evaluates metadata and curves only;
/// applying values to a decoded `.moc3` model remains the runtime's job.
public struct CubismMotion: Sendable, Equatable {
    public let version: Int
    public let metadata: CubismMotionMetadata
    public let curves: [CubismMotionCurve]
    public let userData: [CubismMotionUserData]

    public init(data: Data) throws {
        let raw = try JSONDecoder().decode(RawMotion.self, from: data)
        version = raw.version
        metadata = raw.metadata
        curves = try raw.curves.map(CubismMotionCurve.init(raw:))
        userData = raw.userData
    }

    public static func load(from url: URL) throws -> Self {
        try Self(data: Data(contentsOf: url))
    }

    /// Converts elapsed playback time to a point within the exported motion.
    /// Viewer playback loops by default; pass `false` to stop at the final
    /// pose, independent of the optional `Meta.Loop` export flag.
    public func playbackTime(for elapsedTime: TimeInterval, looping: Bool = true) -> TimeInterval {
        guard metadata.duration > 0, metadata.duration.isFinite else { return 0 }
        guard elapsedTime.isFinite else { return looping ? 0 : metadata.duration }

        let nonNegativeTime = max(0, elapsedTime)
        guard looping else { return min(nonNegativeTime, metadata.duration) }
        return nonNegativeTime.truncatingRemainder(dividingBy: metadata.duration)
    }

    public func evaluate(
        at elapsedTime: TimeInterval,
        looping: Bool = true
    ) -> [CubismMotionValue] {
        let time = playbackTime(for: elapsedTime, looping: looping)
        return curves.map {
            CubismMotionValue(
                target: $0.target,
                id: $0.id,
                value: $0.value(at: time, areBeziersRestricted: metadata.areBeziersRestricted)
            )
        }
    }

    public func value(
        for target: CubismMotionCurveTarget,
        id: String,
        at elapsedTime: TimeInterval,
        looping: Bool = true
    ) -> Float? {
        evaluate(at: elapsedTime, looping: looping)
            .first { $0.target == target && $0.id == id }?
            .value
    }
}

public struct CubismMotionMetadata: Decodable, Sendable, Equatable {
    public let duration: TimeInterval
    public let fps: Double
    public let loop: Bool
    public let areBeziersRestricted: Bool
    public let fadeInTime: TimeInterval?
    public let fadeOutTime: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case duration = "Duration"
        case fps = "Fps"
        case loop = "Loop"
        case areBeziersRestricted = "AreBeziersRestricted"
        case fadeInTime = "FadeInTime"
        case fadeOutTime = "FadeOutTime"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        fps = try container.decode(Double.self, forKey: .fps)
        loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        areBeziersRestricted = try container.decodeIfPresent(Bool.self, forKey: .areBeziersRestricted) ?? false
        fadeInTime = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeInTime)
        fadeOutTime = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeOutTime)
    }
}

public enum CubismMotionCurveTarget: Sendable, Equatable, Hashable {
    case model
    case parameter
    case partOpacity
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "Model": self = .model
        case "Parameter": self = .parameter
        case "PartOpacity": self = .partOpacity
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .model: "Model"
        case .parameter: "Parameter"
        case .partOpacity: "PartOpacity"
        case let .unknown(value): value
        }
    }
}

public struct CubismMotionCurve: Sendable, Equatable {
    public let target: CubismMotionCurveTarget
    public let id: String
    public let fadeInTime: TimeInterval?
    public let fadeOutTime: TimeInterval?
    public let initialPoint: CubismMotionPoint
    public let segments: [CubismMotionSegment]

    public func value(at time: TimeInterval, areBeziersRestricted: Bool) -> Float {
        guard let segment = segments.first(where: { time < $0.end.time }) else {
            return segments.last?.end.value ?? initialPoint.value
        }
        return segment.value(at: time, areBeziersRestricted: areBeziersRestricted)
    }
}

public struct CubismMotionPoint: Sendable, Equatable {
    public let time: TimeInterval
    public let value: Float
}

public enum CubismMotionSegmentKind: Int, Sendable, Equatable {
    case linear = 0
    case bezier = 1
    case stepped = 2
    case inverseStepped = 3
}

public struct CubismMotionSegment: Sendable, Equatable {
    public let kind: CubismMotionSegmentKind
    public let start: CubismMotionPoint
    public let controlPoint1: CubismMotionPoint?
    public let controlPoint2: CubismMotionPoint?
    public let end: CubismMotionPoint

    fileprivate func value(at time: TimeInterval, areBeziersRestricted: Bool) -> Float {
        switch kind {
        case .linear:
            return interpolate(from: start, to: end, at: time)
        case .bezier:
            guard let controlPoint1, let controlPoint2 else { return end.value }
            let parameter = areBeziersRestricted
                ? normalizedTime(from: start.time, to: end.time, at: time)
                : bezierParameter(
                    from: start.time,
                    control1: controlPoint1.time,
                    control2: controlPoint2.time,
                    to: end.time,
                    at: time
                )
            return cubic(
                start.value,
                controlPoint1.value,
                controlPoint2.value,
                end.value,
                parameter
            )
        case .stepped:
            return start.value
        case .inverseStepped:
            return end.value
        }
    }
}

public struct CubismMotionValue: Sendable, Equatable {
    public let target: CubismMotionCurveTarget
    public let id: String
    public let value: Float
}

public struct CubismMotionUserData: Decodable, Sendable, Equatable {
    public let time: TimeInterval
    public let value: String

    private enum CodingKeys: String, CodingKey {
        case time = "Time"
        case value = "Value"
    }
}

public enum CubismMotionError: LocalizedError, Sendable, Equatable {
    case emptySegments(curveID: String)
    case incompleteSegment(curveID: String)
    case invalidSegmentType(curveID: String, value: Double)
    case nonMonotonicEndTime(curveID: String)

    public var errorDescription: String? {
        switch self {
        case let .emptySegments(curveID):
            "Motion curve \(curveID) has no initial point."
        case let .incompleteSegment(curveID):
            "Motion curve \(curveID) ends in an incomplete segment."
        case let .invalidSegmentType(curveID, value):
            "Motion curve \(curveID) uses unsupported segment type \(value)."
        case let .nonMonotonicEndTime(curveID):
            "Motion curve \(curveID) has a segment ending before its start."
        }
    }
}

private struct RawMotion: Decodable {
    let version: Int
    let metadata: CubismMotionMetadata
    let curves: [RawCurve]
    let userData: [CubismMotionUserData]

    private enum CodingKeys: String, CodingKey {
        case version = "Version"
        case metadata = "Meta"
        case curves = "Curves"
        case userData = "UserData"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        metadata = try container.decode(CubismMotionMetadata.self, forKey: .metadata)
        curves = try container.decode([RawCurve].self, forKey: .curves)
        userData = try container.decodeIfPresent([CubismMotionUserData].self, forKey: .userData) ?? []
    }
}

private struct RawCurve: Decodable {
    let target: String
    let id: String
    let fadeInTime: TimeInterval?
    let fadeOutTime: TimeInterval?
    let segments: [Double]

    private enum CodingKeys: String, CodingKey {
        case target = "Target"
        case id = "Id"
        case fadeInTime = "FadeInTime"
        case fadeOutTime = "FadeOutTime"
        case segments = "Segments"
    }
}

private extension CubismMotionCurve {
    init(raw: RawCurve) throws {
        let parsed = try Self.parseSegments(raw.segments, curveID: raw.id)
        target = CubismMotionCurveTarget(rawValue: raw.target)
        id = raw.id
        fadeInTime = raw.fadeInTime
        fadeOutTime = raw.fadeOutTime
        initialPoint = parsed.initialPoint
        segments = parsed.segments
    }

    static func parseSegments(
        _ flatSegments: [Double],
        curveID: String
    ) throws -> (initialPoint: CubismMotionPoint, segments: [CubismMotionSegment]) {
        guard flatSegments.count >= 2 else {
            throw CubismMotionError.emptySegments(curveID: curveID)
        }

        var cursor = 0
        func nextPoint() throws -> CubismMotionPoint {
            guard cursor + 1 < flatSegments.count else {
                throw CubismMotionError.incompleteSegment(curveID: curveID)
            }
            let point = CubismMotionPoint(time: flatSegments[cursor], value: Float(flatSegments[cursor + 1]))
            guard point.time.isFinite, point.value.isFinite else {
                throw CubismMotionError.incompleteSegment(curveID: curveID)
            }
            cursor += 2
            return point
        }

        var current = try nextPoint()
        let initialPoint = current
        var parsedSegments: [CubismMotionSegment] = []

        while cursor < flatSegments.count {
            let rawKind = flatSegments[cursor]
            cursor += 1
            guard rawKind.isFinite, rawKind.rounded() == rawKind,
                  let kind = CubismMotionSegmentKind(rawValue: Int(rawKind)) else {
                throw CubismMotionError.invalidSegmentType(curveID: curveID, value: rawKind)
            }

            let controlPoint1: CubismMotionPoint?
            let controlPoint2: CubismMotionPoint?
            let end: CubismMotionPoint
            if kind == .bezier {
                controlPoint1 = try nextPoint()
                controlPoint2 = try nextPoint()
                end = try nextPoint()
            } else {
                controlPoint1 = nil
                controlPoint2 = nil
                end = try nextPoint()
            }

            guard end.time >= current.time else {
                throw CubismMotionError.nonMonotonicEndTime(curveID: curveID)
            }
            parsedSegments.append(
                CubismMotionSegment(
                    kind: kind,
                    start: current,
                    controlPoint1: controlPoint1,
                    controlPoint2: controlPoint2,
                    end: end
                )
            )
            current = end
        }

        return (initialPoint, parsedSegments)
    }
}

private func normalizedTime(from start: TimeInterval, to end: TimeInterval, at time: TimeInterval) -> Double {
    guard end > start else { return 1 }
    return min(1, max(0, (time - start) / (end - start)))
}

private func interpolate(from start: CubismMotionPoint, to end: CubismMotionPoint, at time: TimeInterval) -> Float {
    start.value + (end.value - start.value) * Float(normalizedTime(from: start.time, to: end.time, at: time))
}

private func bezierParameter(
    from start: TimeInterval,
    control1: TimeInterval,
    control2: TimeInterval,
    to end: TimeInterval,
    at time: TimeInterval
) -> Double {
    guard time > start else { return 0 }
    guard time < end else { return 1 }

    var low = 0.0
    var high = 1.0
    for _ in 0 ..< 20 {
        let middle = (low + high) * 0.5
        if cubic(start, control1, control2, end, middle) < time {
            low = middle
        } else {
            high = middle
        }
    }
    return (low + high) * 0.5
}

private func cubic(_ start: Double, _ control1: Double, _ control2: Double, _ end: Double, _ t: Double) -> Double {
    let inverse = 1 - t
    return inverse * inverse * inverse * start
        + 3 * inverse * inverse * t * control1
        + 3 * inverse * t * t * control2
        + t * t * t * end
}

private func cubic(_ start: Float, _ control1: Float, _ control2: Float, _ end: Float, _ t: Double) -> Float {
    Float(cubic(Double(start), Double(control1), Double(control2), Double(end), t))
}
