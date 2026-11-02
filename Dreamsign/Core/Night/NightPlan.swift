import Foundation

/// Falling-asleep sound, generated on the phone.
enum Soundscape: String, Codable, CaseIterable, Identifiable, Sendable {
    case rain, ocean, brown, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: String(localized: "Rain")
        case .ocean: String(localized: "Ocean")
        case .brown: String(localized: "Brown noise")
        case .off: String(localized: "Off")
        }
    }

    var symbol: String {
        switch self {
        case .rain: "cloud.rain.fill"
        case .ocean: "water.waves"
        case .brown: "waveform"
        case .off: "speaker.slash.fill"
        }
    }
}

/// When lucidity cues play. Cues come in short bursts during the late-night window, when
/// REM periods are longest, and go quiet for a while after any movement (likely waking).
/// Based on targeted lucidity reactivation (Carr et al., 2020), without the lab's EEG timing.
struct CuePlan: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
    /// Seconds between the start of one burst and the next.
    var interval: TimeInterval = 240
    /// Cues per burst.
    var burst = 3
    var burstSpacing: TimeInterval = 10
    var quietAfterMovement: TimeInterval = 600
    /// 0…1, relative to the phone's media volume.
    var volume: Double = 0.18

    /// The last two hours before waking, ending 15 minutes before the alarm.
    static func window(beforeWake wake: Date) -> (start: Date, end: Date) {
        (wake.addingTimeInterval(-135 * 60), wake.addingTimeInterval(-15 * 60))
    }

    func contains(_ date: Date) -> Bool { date >= start && date <= end }

    func shouldStartBurst(now: Date, lastBurst: Date?, lastMovement: Date?, heldUntil: Date? = nil) -> Bool {
        guard contains(now) else { return false }
        if let heldUntil, now < heldUntil { return false }
        if let lastMovement, now.timeIntervalSince(lastMovement) < quietAfterMovement { return false }
        if let lastBurst, now.timeIntervalSince(lastBurst) < interval { return false }
        return true
    }
}

/// Everything a night of audio needs: what plays, for how long, and what it rises into.
struct NightPlan: Hashable, Sendable {
    var soundscape: Soundscape
    /// Minutes at full level before the soundscape fades; 0 = all night.
    var sleepTimerMinutes: Int
    /// The alarm the night ends in. A soft lead-in rises in the last minutes before it.
    var riseInto: Date?
    var cues: CuePlan?

    static let fadeIn: TimeInterval = 20
    static let fadeOut: TimeInterval = 300
    static let leadIn: TimeInterval = 180
    /// Without an alarm, cues or timer, the night ends after this long.
    static let longestNight: TimeInterval = 11 * 3600

    /// Soundscape gain 0…1.
    func soundscapeLevel(at now: Date, startedAt: Date) -> Double {
        guard soundscape != .off else { return 0 }
        let elapsed = now.timeIntervalSince(startedAt)
        var level = min(max(elapsed / Self.fadeIn, 0), 1)
        if sleepTimerMinutes > 0 {
            let fadeStart = Double(sleepTimerMinutes) * 60
            level *= 1 - min(max((elapsed - fadeStart) / Self.fadeOut, 0), 1)
        }
        if let riseInto {
            // Crossfade into the lead-in.
            let leadStart = riseInto.addingTimeInterval(-Self.leadIn)
            level *= 1 - min(max(now.timeIntervalSince(leadStart) / Self.leadIn, 0), 1)
        }
        return level
    }

    /// Lead-in gain 0…1 while it plays, nil otherwise.
    func leadInLevel(at now: Date) -> Double? {
        guard let riseInto else { return nil }
        let leadStart = riseInto.addingTimeInterval(-Self.leadIn)
        guard now >= leadStart, now <= riseInto.addingTimeInterval(60) else { return nil }
        let progress = min(now.timeIntervalSince(leadStart) / Self.leadIn, 1)
        return max(0.05, pow(progress, 1.5)) * 0.9
    }

    /// When the night's audio can stop.
    func endDate(startedAt: Date) -> Date {
        if let riseInto { return riseInto.addingTimeInterval(90) }
        var end = startedAt
        if sleepTimerMinutes > 0 {
            end = startedAt.addingTimeInterval(Double(sleepTimerMinutes) * 60 + Self.fadeOut + 5)
        } else if soundscape != .off {
            end = startedAt.addingTimeInterval(Self.longestNight)
        }
        if let cues { end = max(end, cues.end.addingTimeInterval(60)) }
        return min(end, startedAt.addingTimeInterval(Self.longestNight))
    }
}
