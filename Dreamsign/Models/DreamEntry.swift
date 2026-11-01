import Foundation
import SwiftData

enum EntrySource: String, Codable, Sendable {
    case alarm, wbtb, manual
}

enum DreamSignCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case person, place, theme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .person: String(localized: "Person")
        case .place: String(localized: "Place")
        case .theme: String(localized: "Theme")
        }
    }

    var plural: String {
        switch self {
        case .person: String(localized: "People")
        case .place: String(localized: "Places")
        case .theme: String(localized: "Themes")
        }
    }

    var symbol: String {
        switch self {
        case .person: "person.fill"
        case .place: "mappin"
        case .theme: "sparkle"
        }
    }
}

enum DreamMood: String, Codable, CaseIterable, Identifiable, Sendable {
    case joyful, calm, curious, strange, anxious, scared, sad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .joyful: String(localized: "Joyful")
        case .calm: String(localized: "Calm")
        case .curious: String(localized: "Curious")
        case .strange: String(localized: "Strange")
        case .anxious: String(localized: "Anxious")
        case .scared: String(localized: "Scared")
        case .sad: String(localized: "Sad")
        }
    }

    var symbol: String {
        switch self {
        case .joyful: "sun.max"
        case .calm: "leaf"
        case .curious: "binoculars"
        case .strange: "questionmark.diamond"
        case .anxious: "waveform.path.ecg"
        case .scared: "bolt"
        case .sad: "cloud.rain"
        }
    }
}

/// Remembers the technique practiced most recently, so the next morning's entries can be
/// credited to it and Insights can show what's working.
enum TechniqueLog {
    private static let techniqueKey = "technique.last"
    private static let dateKey = "technique.at"

    static func record(_ technique: WBTBTechnique) {
        UserDefaults.standard.set(technique.rawValue, forKey: techniqueKey)
        UserDefaults.standard.set(Date.now, forKey: dateKey)
    }

    /// The technique practiced within the last 10 hours, if any.
    static var recent: WBTBTechnique? {
        guard let raw = UserDefaults.standard.string(forKey: techniqueKey),
              let date = UserDefaults.standard.object(forKey: dateKey) as? Date,
              Date.now.timeIntervalSince(date) < 10 * 3600
        else { return nil }
        return WBTBTechnique(rawValue: raw)
    }
}

@Model
final class DreamEntry {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date.now
    var text: String = ""
    /// "First thoughts on waking" entry — no dream recalled.
    var isNoRecall: Bool = false
    var isLucid: Bool = false
    var sourceRaw: String = EntrySource.manual.rawValue
    var signs: [DreamSign] = []
    /// 0 = not rated, 1…5.
    var vividness: Int = 0
    var moodRaw: String = ""
    var isNightmare: Bool = false
    /// Technique practiced the night this dream happened ("" = none).
    var techniqueRaw: String = ""

    init(text: String, createdAt: Date = .now, isNoRecall: Bool = false, source: EntrySource = .manual) {
        id = UUID()
        self.text = text
        self.createdAt = createdAt
        self.isNoRecall = isNoRecall
        sourceRaw = source.rawValue
        techniqueRaw = TechniqueLog.recent?.rawValue ?? ""
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

    var mood: DreamMood? {
        get { DreamMood(rawValue: moodRaw) }
        set { moodRaw = newValue?.rawValue ?? "" }
    }

    var technique: WBTBTechnique? { WBTBTechnique(rawValue: techniqueRaw) }

    var title: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespaces)
    }
}

@Model
final class DreamSign {
    /// Normalized name, unique across signs ("Grandma" == "grandma").
    @Attribute(.unique) var key: String = ""
    var name: String = ""
    var categoryRaw: String = DreamSignCategory.theme.rawValue
    var createdAt: Date = Date.now
    @Relationship(inverse: \DreamEntry.signs) var entries: [DreamEntry] = []

    init(name: String, category: DreamSignCategory) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed
        key = DreamSign.key(for: trimmed)
        categoryRaw = category.rawValue
        createdAt = .now
    }

    var category: DreamSignCategory {
        get { DreamSignCategory(rawValue: categoryRaw) ?? .theme }
        set { categoryRaw = newValue.rawValue }
    }

    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
