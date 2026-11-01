import Foundation

/// Bundled alarm sounds (28 s, escalating within the file) plus the system alarm.
enum AlarmSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, dawn, tide, beacon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Classic")
        case .dawn: String(localized: "Dawn")
        case .tide: String(localized: "Tide")
        case .beacon: String(localized: "Beacon")
        }
    }

    var detail: String {
        switch self {
        case .system: String(localized: "The system alarm")
        case .dawn: String(localized: "Soft chimes that slowly rise")
        case .tide: String(localized: "Warm, steady, insistent")
        case .beacon: String(localized: "Loud — for very deep sleep")
        }
    }

    /// File in the main bundle; `nil` uses the system alarm sound.
    var fileName: String? {
        switch self {
        case .system: nil
        case .dawn: "Dawn.wav"
        case .tide: "Tide.wav"
        case .beacon: "Beacon.wav"
        }
    }

    var previewURL: URL? {
        guard let fileName else { return nil }
        return Bundle.main.url(forResource: (fileName as NSString).deletingPathExtension, withExtension: "wav")
    }
}
