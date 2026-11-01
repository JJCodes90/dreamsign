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

    init(text: String, createdAt: Date = .now, isNoRecall: Bool = false, source: EntrySource = .manual) {
        id = UUID()
        self.text = text
        self.createdAt = createdAt
        self.isNoRecall = isNoRecall
        sourceRaw = source.rawValue
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

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
