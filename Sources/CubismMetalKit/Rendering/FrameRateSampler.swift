import Foundation

/// Reports a stable frame rate without publishing work for every rendered frame.
struct FrameRateSampler {
    private let reportInterval: TimeInterval
    private var windowStart: TimeInterval?
    private var frameCount = 0

    init(reportInterval: TimeInterval = 0.5) {
        self.reportInterval = reportInterval
    }

    mutating func recordFrame(at timestamp: TimeInterval) -> Double? {
        guard timestamp.isFinite else {
            reset()
            return nil
        }
        guard let windowStart else {
            self.windowStart = timestamp
            return nil
        }
        guard timestamp >= windowStart else {
            reset()
            self.windowStart = timestamp
            return nil
        }

        frameCount += 1
        let elapsed = timestamp - windowStart
        guard elapsed >= reportInterval else { return nil }

        let framesPerSecond = Double(frameCount) / elapsed
        self.windowStart = timestamp
        frameCount = 0
        return framesPerSecond
    }

    mutating func reset() {
        windowStart = nil
        frameCount = 0
    }
}
