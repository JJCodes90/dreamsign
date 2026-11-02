import SwiftData
import SwiftUI

struct JournalView: View {
    @Query(sort: \DreamEntry.createdAt, order: .reverse) private var entries: [DreamEntry]
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var composing = false
    @State private var showingWorld = Showcase.screen == "dream-world"
    @State private var selection: DreamEntry?

    /// Optional filter when opened from Insights.
    var sign: DreamSign?

    private var filtered: [DreamEntry] {
        let base = sign.map { sign in entries.filter { $0.signs.contains { $0.key == sign.key } } } ?? entries
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter { entry in
            entry.text.localizedStandardContains(query) || entry.signs.contains { $0.name.localizedStandardContains(query) }
        }
    }

    private struct MorningSection: Identifiable {
        let morning: Date
        let entries: [DreamEntry]
        var id: Date { morning }
    }

    private var sections: [MorningSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { JournalStats.morning(of: $0.createdAt, calendar: calendar) }
        return grouped.keys.sorted(by: >).map { MorningSection(morning: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        if sign != nil {
            // Pushed from Insights, inside its navigation stack.
            decorated(List { rows })
                .navigationDestination(for: DreamEntry.self) { JournalEntryView(entry: $0) }
        } else {
            // A stack when closed; list and entry side by side on the open inner display.
            NavigationSplitView {
                decorated(List(selection: $selection) { rows })
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
            } detail: {
                if let selection {
                    JournalEntryView(entry: selection, onDelete: { self.selection = nil })
                        .id(selection.id)
                } else {
                    JournalPlaceholder(isEmpty: entries.isEmpty)
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    @ViewBuilder
    private var rows: some View {
        if entries.isEmpty {
            EmptyJournal { composing = true }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        ForEach(sections) { section in
            Section {
                ForEach(section.entries) { entry in
                    NavigationLink(value: entry) {
                        JournalRow(entry: entry)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Palette.hairline)
                    .swipeActions {
                        Button(role: .destructive) { delete(entry) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            } header: {
                Text(MorningLabel.text(for: section.morning))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .textCase(nil)
            }
        }
    }

    private func decorated(_ list: some View) -> some View {
        list
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NightBackground())
            .navigationTitle(sign?.name ?? String(localized: "Journal"))
            .searchable(text: $search, prompt: "Dreams, people, places")
            .toolbar {
                if sign == nil {
                    ToolbarItem(placement: .secondaryAction) {
                        Button { showingWorld = true } label: { Label("Dream world", systemImage: "circle.hexagongrid") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { composing = true } label: { Label("New Entry", systemImage: "square.and.pencil") }
                    }
                }
            }
            .sheet(isPresented: $composing) {
                EntryEditorView(entry: nil)
            }
            .sheet(isPresented: $showingWorld) {
                NavigationStack {
                    DreamWorldView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(role: .close) { showingWorld = false }
                            }
                        }
                }
            }
    }

    private func delete(_ entry: DreamEntry) {
        if selection == entry { selection = nil }
        withAnimation {
            context.delete(entry)
            try? context.save()
        }
    }
}

private struct JournalPlaceholder: View {
    let isEmpty: Bool

    var body: some View {
        ZStack {
            NightBackground()
            VStack(spacing: 12) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.iris)
                Text(isEmpty ? "Your first dream will show up here" : "Choose a dream")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

enum MorningLabel {
    static func text(for morning: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(morning) { return String(localized: "This morning") }
        if calendar.isDateInYesterday(morning) { return String(localized: "Yesterday") }
        let sameYear = calendar.isDate(morning, equalTo: .now, toGranularity: .year)
        return morning.formatted(sameYear ? .dateTime.weekday(.wide).month(.abbreviated).day()
                                          : .dateTime.month(.abbreviated).day().year())
    }
}

struct JournalRow: View {
    let entry: DreamEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.textTertiary)
                if entry.isLucid {
                    Chip(text: String(localized: "Lucid"), symbol: "sparkles", tint: Palette.iris)
                }
                if entry.isNoRecall {
                    Chip(text: String(localized: "No recall"), symbol: "cloud.fog", tint: Palette.textSecondary)
                }
                if entry.isNightmare {
                    Chip(text: String(localized: "Nightmare"), symbol: "bolt.heart", tint: Palette.ember)
                }
                if entry.source == .wbtb {
                    Image(systemName: "moon.stars")
                        .font(.caption)
                        .foregroundStyle(Palette.iris.opacity(0.8))
                        .accessibilityLabel("Lucid window")
                }
            }
            Text(entry.text)
                .font(.body)
                .foregroundStyle(entry.isNoRecall ? Palette.textSecondary : Palette.text)
                .lineLimit(3)
            if !entry.signs.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(entry.signs.sorted { $0.name < $1.name }) { sign in
                            Chip(text: sign.name, symbol: sign.category.symbol, tint: Palette.dawn)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct EmptyJournal: View {
    var onCompose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Palette.iris)
            Text("Your dreams will live here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("Entries from your wake-ups save automatically. Anything else that comes back to you, add it here.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Write an entry", action: onCompose)
                .buttonStyle(.quiet)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    JournalView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
