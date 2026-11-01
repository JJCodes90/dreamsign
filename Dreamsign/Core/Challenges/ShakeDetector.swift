import Foundation

/// Counts shakes from user-acceleration magnitude (gravity removed, in g). Every flick counts:
/// a 3 Hz back-and-forth shake registers ~6 per second.
/// A shake registers on a peak above `threshold`; the next one needs the signal to fall
/// below `release` first (hysteresis) and at least `minimumInterval` to pass, so one
/// vigorous swing never counts twice.
struct ShakeDetector: Sendable {
    var threshold = 1.3
    var release = 0.55
    var minimumInterval: TimeInterval = 0.15

    private var armed = true
    private var lastShake: TimeInterval = -.greatestFiniteMagnitude

    init(threshold: Double = 1.3, release: Double = 0.55, minimumInterval: TimeInterval = 0.15) {
        self.threshold = threshold
        self.release = release
        self.minimumInterval = minimumInterval
    }

    /// Feed one sample; returns true when it completes a shake.
    mutating func process(magnitude: Double, at timestamp: TimeInterval) -> Bool {
        if armed {
            guard magnitude >= threshold, timestamp - lastShake >= minimumInterval else { return false }
            armed = false
            lastShake = timestamp
            return true
        }
        if magnitude <= release { armed = true }
        return false
    }

    static func magnitude(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }
}
