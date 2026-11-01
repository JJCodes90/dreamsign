import SwiftUI

/// Night palette: deep ink, never pure black or white. Calm at 6 AM, legible with one eye open.
enum Palette {
    static let ink = Color(hex: 0x07080F)
    static let night = Color(hex: 0x0E1022)
    static let surface = Color(hex: 0x131628)
    static let surfaceRaised = Color(hex: 0x1C2036)
    static let hairline = Color.white.opacity(0.07)

    static let text = Color(hex: 0xEEECF8)
    static let textSecondary = Color(hex: 0xA6A4C0)
    static let textTertiary = Color(hex: 0x706E8C)

    /// Dreams, lucidity, the app's accent.
    static let iris = Color(hex: 0xA99CFF)
    static let irisDeep = Color(hex: 0x6F5CFF)
    /// Waking, alarms, progress.
    static let dawn = Color(hex: 0xFFB38A)
    static let dawnDeep = Color(hex: 0xFF8466)
    static let mint = Color(hex: 0x7EE2C4)
    static let ember = Color(hex: 0xFF8A80)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Thin rounded numerals for clock faces.
    static func clock(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
}

enum Metrics {
    static let corner: CGFloat = 26
    static let gutter: CGFloat = 20
    /// Minimum height for anything tapped half-asleep.
    static let bigTap: CGFloat = 64
}

/// Splits a time into "7:00" and "AM" (or "07:00" and nil), following the user's 12/24h setting.
enum ClockFormat {
    static func parts(_ time: AlarmTime) -> (main: String, period: String?) {
        parts(time.date())
    }

    static func parts(_ date: Date) -> (main: String, period: String?) {
        let full = date.formatted(.dateTime.hour().minute())
        let main = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        let period = full.replacingOccurrences(of: main, with: "").trimmingCharacters(in: .whitespaces)
        return (main, period.isEmpty ? nil : period)
    }

    static func string(_ time: AlarmTime) -> String {
        time.date().formatted(date: .omitted, time: .shortened)
    }

    /// "6 h 12 min", "45 min", "under a minute"
    static func countdown(to date: Date, from now: Date = .now) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return String(localized: "now") }
        if minutes < 60 { return String(localized: "\(minutes) min") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }
}
