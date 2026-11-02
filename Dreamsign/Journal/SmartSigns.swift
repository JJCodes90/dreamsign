import FoundationModels
import SwiftData
import SwiftUI

// MARK: - Apple Intelligence

@Generable
struct GeneratedReading {
    @Guide(description: "A short, evocative title for the dream, two to five words, no quotation marks")
    var title: String
    @Guide(description: "Up to five elements of this dream that could recur in other dreams: people, places, or strange things that happened",
           .maximumCount(5))
    var signs: [GeneratedSign]
}

@Generable
struct GeneratedSign {
    @Guide(description: "The element in one to four words, the way the dreamer would name it")
    var name: String
    @Guide(description: "person, place, or theme (an object, event or something impossible)")
    var category: GeneratedCategory
}

@Generable
enum GeneratedCategory {
    case person, place, theme
}

/// Reads a dream with the on-device model when Apple Intelligence is on, and falls back to
/// word rules otherwise. Nothing leaves the iPhone either way.
@MainActor
enum DreamReader {
    static var modelAvailable: Bool {
        guard !Showcase.isActive else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func read(_ text: String, known: [KnownSign], tagged: Set<String>) async -> DreamReading {
        let heuristic = HeuristicSignReader().read(text, known: known, tagged: tagged)
        guard modelAvailable, text.split(separator: " ").count >= 6 else {
            return Showcase.isActive ? DreamReading(title: "The flooded school", signs: heuristic.signs) : heuristic
        }
        do {
            let session = LanguageModelSession {
                """
                You help someone keep a dream journal for lucid dreaming. Dream signs are recurring \
                people, places and impossible events that can remind a dreamer they are dreaming. \
                Only use elements that appear in the dream. Keep names short.
                """
            }
            var request = "Dream: \(text)"
            if !known.isEmpty {
                request += "\nSigns from earlier dreams: \(known.prefix(30).map(\.name).joined(separator: ", "))"
            }
            let prompt = Prompt { request }
            let reading = try await session.respond(to: prompt, generating: GeneratedReading.self).content
            let byKey = Dictionary(known.map { (DreamSign.key(for: $0.name), $0) }, uniquingKeysWith: { a, _ in a })
            var signs: [SignSuggestion] = heuristic.signs.filter { $0.earlierCount > 0 }
            for sign in reading.signs {
                let name = sign.name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                guard !name.isEmpty, name.count <= 40 else { continue }
                let key = DreamSign.key(for: name)
                guard !tagged.contains(key), !signs.contains(where: { $0.id == key }) else { continue }
                let existing = byKey[key]
                signs.append(SignSuggestion(name: existing?.name ?? name.prefix(1).uppercased() + name.dropFirst(),
                                            category: existing?.category ?? sign.category.category,
                                            earlierCount: existing?.count ?? 0))
            }
            let title = reading.title.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'. ").union(.whitespacesAndNewlines))
            return DreamReading(title: title.isEmpty ? nil : title, signs: Array(signs.prefix(5)), usedModel: true)
        } catch {
            return heuristic
        }
    }
}

private extension GeneratedCategory {
    var category: DreamSignCategory {
        switch self {
        case .person: .person
        case .place: .place
        case .theme: .theme
        }
    }
}

// MARK: - Card

/// Suggested title and dream signs for an entry, each one tap to accept.
struct SuggestedSignsCard: View {
    @Bindable var entry: DreamEntry
    @Query private var signs: [DreamSign]
    @Environment(\.modelContext) private var context
    @State private var reading: DreamReading?
    @State private var loading = true

    private var tagged: Set<String> { Set(entry.signs.map(\.key)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.iris)
                Text("POSSIBLE DREAM SIGNS")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.iris)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }

            if let title = reading?.title, entry.customTitle.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggested title").font(.caption).foregroundStyle(Palette.textTertiary)
                        Text(title).font(.headline).foregroundStyle(Palette.text)
                    }
                    Spacer()
                    Button("Use") {
                        entry.customTitle = title
                        try? context.save()
                    }
                    .buttonStyle(.quiet)
                }
                Divider().overlay(Palette.hairline)
            }

            if let suggestions = reading?.signs, !suggestions.isEmpty {
                ForEach(suggestions) { suggestion in
                    row(suggestion)
                    if suggestion.id != suggestions.last?.id { Divider().overlay(Palette.hairline) }
                }
            } else if !loading {
                Text("Nothing stood out this time. Tag your own below.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }

            Label(reading?.usedModel == true ? "Apple Intelligence, on this iPhone." : "Suggested on this iPhone.",
                  systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
        }
        .card(tint: Palette.iris)
        .task(id: entry.text) {
            loading = true
            let known = signs.map { KnownSign(name: $0.name, category: $0.category, count: $0.entries.filter { $0.id != entry.id }.count) }
            reading = await DreamReader.read(entry.text, known: known, tagged: [])
            loading = false
        }
        .sensoryFeedback(.success, trigger: entry.signs.count)
    }

    private func row(_ suggestion: SignSuggestion) -> some View {
        let added = tagged.contains(suggestion.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.name).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                Text(detail(suggestion)).font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            if added {
                Label("Added", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.mint)
            } else {
                Button("Add") { add(suggestion) }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Palette.iris))
                    .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
    }

    private func detail(_ suggestion: SignSuggestion) -> String {
        let base = suggestion.category.title
        if suggestion.earlierCount > 0 {
            return String(localized: "\(base) · in \(suggestion.earlierCount) earlier dreams")
        }
        if let note = suggestion.note { return "\(base) · \(note)" }
        return String(localized: "\(base) · new")
    }

    private func add(_ suggestion: SignSuggestion) {
        let sign = signs.first { $0.key == suggestion.id } ?? {
            let created = DreamSign(name: suggestion.name, category: suggestion.category)
            context.insert(created)
            return created
        }()
        if !entry.signs.contains(where: { $0.key == sign.key }) { entry.signs.append(sign) }
        try? context.save()
    }
}
