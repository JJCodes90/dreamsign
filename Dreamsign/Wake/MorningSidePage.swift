import SwiftData
import SwiftUI

/// What was chosen on the right-hand page, applied when the entry is saved.
struct MorningChoices {
    /// Known signs the person un-ticked (mentioned ones are ticked by default).
    var removed: Set<String> = []
    /// Extra signs ticked: known keys or new suggestion names.
    var added: [SignSuggestion] = []
    var vividness = 0
    var lucid = false

    /// Signs to tag: mentioned known signs (minus removed) plus anything added.
    func selectedKeys(text: String, signs: [DreamSign]) -> Set<String> {
        let mentioned = signs.filter { HeuristicSignReader.mentions(text.lowercased(), $0.name.lowercased()) }.map(\.key)
        return Set(mentioned).subtracting(removed).union(added.map(\.id))
    }

    func apply(to entry: DreamEntry, text: String, signs: [DreamSign], context: ModelContext) {
        let keys = selectedKeys(text: text, signs: signs)
        for key in keys {
            if let sign = signs.first(where: { $0.key == key }) {
                entry.signs.append(sign)
            } else if let suggestion = added.first(where: { $0.id == key }) {
                let sign = DreamSign(name: suggestion.name, category: suggestion.category)
                context.insert(sign)
                entry.signs.append(sign)
            }
        }
        entry.vividness = vividness
        entry.isLucid = lucid
    }
}

/// The right-hand page of the two-page morning: signs as you talk, how it felt, what's next.
struct MorningSidePage: View {
    let text: String
    let signs: [DreamSign]
    let source: EntrySource
    @Binding var choices: MorningChoices
    var canSave: Bool
    var onSave: () -> Void

    private var known: [KnownSign] {
        signs.map { KnownSign(name: $0.name, category: $0.category, count: $0.entries.count) }
    }

    private var suggestions: [SignSuggestion] {
        HeuristicSignReader(limit: 6).read(text, known: known).signs
    }

    var body: some View {
        let selected = choices.selectedKeys(text: text, signs: signs)
        let items = suggestions
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(String(localized: "As you talk"))
                Button("Save dream", action: onSave)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(canSave ? Palette.mint : Palette.surfaceRaised))
                    .buttonStyle(.plain)
                    .disabled(!canSave)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("SIGNS")
                    .font(.caption.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(Palette.iris)
                if items.isEmpty {
                    Text("People, places and odd moments you mention show up here.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(items) { item in
                            let isOn = selected.contains(item.id)
                            Button { toggle(item, isOn: isOn) } label: {
                                Label(item.name, systemImage: isOn ? "checkmark" : "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isOn ? Palette.mint : Palette.iris)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill((isOn ? Palette.mint : Palette.iris).opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }
            }
            .card(padding: 16, tint: Palette.iris)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VIVIDNESS").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Palette.textTertiary)
                    VividnessPicker(value: $choices.vividness)
                }
                .card(padding: 14)
                VStack(alignment: .leading, spacing: 8) {
                    Text("LUCID?").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Palette.textTertiary)
                    Toggle("Lucid", isOn: $choices.lucid)
                        .labelsHidden()
                        .tint(Palette.iris)
                }
                .card(padding: 14)
                .frame(maxWidth: 130)
            }

            nextCard
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .sensoryFeedback(.selection, trigger: selected)
    }

    @ViewBuilder
    private var nextCard: some View {
        let strongest = signs.filter { HeuristicSignReader.mentions(text.lowercased(), $0.name.lowercased()) }
            .max { $0.entries.count < $1.entries.count }
        VStack(alignment: .leading, spacing: 6) {
            if source == .wbtb {
                Text("Next: your lucid window").font(.headline).foregroundStyle(Palette.text)
                Text("Save, then rehearse this dream and drift back while it's fresh.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            } else if let strongest, strongest.entries.count >= 2 {
                Text("\(strongest.name) again").font(.headline).foregroundStyle(Palette.text)
                Text("In \(strongest.entries.count + 1) dreams now — a strong sign to watch for tonight.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            } else {
                Text("Every detail helps").font(.headline).foregroundStyle(Palette.text)
                Text("Where were you? Who was there? What felt off?")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        }
        .card(tint: Palette.dawn)
    }

    private func toggle(_ item: SignSuggestion, isOn: Bool) {
        if isOn {
            if let index = choices.added.firstIndex(where: { $0.id == item.id }) {
                choices.added.remove(at: index)
            } else {
                choices.removed.insert(item.id)
            }
        } else {
            choices.removed.remove(item.id)
            if !choices.selectedKeys(text: text, signs: signs).contains(item.id) { choices.added.append(item) }
        }
    }
}
