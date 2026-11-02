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

    /// Sensitivity 0…1 → detector. 0 needs a vigorous shake (1.7 g), 1 counts a gentle
    /// wobble (0.6 g). The default, 0.6, is about 1.04 g.
    init(sensitivity: Double) {
        let s = min(max(sensitivity, 0), 1)
        let threshold = 1.7 - 1.1 * s
        self.init(threshold: threshold, release: threshold * 0.45, minimumInterval: 0.15)
    }

    static let defaultSensitivity = 0.6

    static func magnitude(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }
}
