import SwiftData
import SwiftUI

struct JournalEntryView: View {
    @Bindable var entry: DreamEntry
    /// In a split view, clears the selection instead of popping.
    var onDelete: (() -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var tagging = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.text)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { entry.isLucid.toggle() }
                        try? context.save()
                    } label: {
                        Label(entry.isLucid ? "Lucid" : "Mark lucid", systemImage: entry.isLucid ? "sparkles" : "sparkle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(entry.isLucid ? Palette.ink : Palette.iris)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(entry.isLucid ? Palette.iris : Palette.iris.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: entry.isLucid) { _, lucid in lucid }
                    if entry.isNoRecall {
                        Chip(text: String(localized: "No recall"), symbol: "cloud.fog", tint: Palette.textSecondary)
                    }
                }

                Text(entry.text)
                    .font(.title3)
                    .lineSpacing(6)
                    .foregroundStyle(entry.isNoRecall ? Palette.textSecondary : Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader("Dream signs")
                        Button { tagging = true } label: {
                            Label("Tag", systemImage: "tag")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.quiet)
                    }
                    if entry.signs.isEmpty {
                        Text("Tag the people, places and themes that keep coming back. They become your cues to notice you're dreaming.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        FlowLayout {
                            ForEach(entry.signs.sorted { $0.name < $1.name }) { sign in
                                Chip(text: sign.name, symbol: sign.category.symbol, tint: Palette.dawn)
                            }
                        }
                    }
                }
                .card()
            }
            .padding(Metrics.gutter)
        }
        .background(NightBackground(stars: false))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $editing) { EntryEditorView(entry: entry) }
        .sheet(isPresented: $tagging) { SignTaggerView(entry: entry) }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let doomed = entry
                if let onDelete { onDelete() } else { dismiss() }
                context.delete(doomed)
                try? context.save()
            }
        }
    }

    private var subtitle: String {
        let time = entry.createdAt.formatted(date: .omitted, time: .shortened)
        switch entry.source {
        case .alarm: return String(localized: "\(time) · on waking")
        case .wbtb: return String(localized: "\(time) · lucid window")
        case .manual: return time
        }
    }
}

struct EntryEditorView: View {
    let entry: DreamEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var createdAt: Date
    @State private var isLucid: Bool
    @State private var isNoRecall: Bool
    @FocusState private var focused: Bool

    init(entry: DreamEntry?) {
        self.entry = entry
        _text = State(initialValue: entry?.text ?? "")
        _createdAt = State(initialValue: entry?.createdAt ?? .now)
        _isLucid = State(initialValue: entry?.isLucid ?? false)
        _isNoRecall = State(initialValue: entry?.isNoRecall ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .focused($focused)
                        .font(.title3)
                        .frame(minHeight: 240)
                        .scrollContentBackground(.hidden)
                }
                Section {
                    Toggle("Lucid", isOn: $isLucid).tint(Palette.iris)
                    Toggle("No dream — just first thoughts", isOn: $isNoRecall).tint(Palette.iris)
                    DatePicker("When", selection: $createdAt, in: ...Date.now)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NightBackground(stars: false))
            .navigationTitle(entry == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .prominentConfirm) {
                    Button(role: .confirm, action: save)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { if entry == nil { focused = true } }
        }
    }

    private func save() {
        let target = entry ?? {
            let created = DreamEntry(text: "", source: .manual)
            context.insert(created)
            return created
        }()
        target.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        target.createdAt = createdAt
        target.isLucid = isLucid
        target.isNoRecall = isNoRecall
        try? context.save()
        dismiss()
    }
}

struct SignTaggerView: View {
    @Bindable var entry: DreamEntry
    @Query(sort: \DreamSign.name) private var signs: [DreamSign]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: DreamSignCategory = .theme

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matching: [DreamSign] {
        trimmed.isEmpty ? signs : signs.filter { $0.name.localizedStandardContains(trimmed) }
    }

    private var canCreate: Bool {
        !trimmed.isEmpty && !signs.contains { $0.key == DreamSign.key(for: trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Section("New dream sign") {
                        Picker("Kind", selection: $category) {
                            ForEach(DreamSignCategory.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Button(action: create) {
                            Label("Add “\(trimmed)”", systemImage: "plus.circle.fill")
                                .foregroundStyle(Palette.iris)
                        }
                    }
                }
                ForEach(DreamSignCategory.allCases) { kind in
                    let items = matching.filter { $0.category == kind }
                    if !items.isEmpty {
                        Section(kind.plural) {
                            ForEach(items) { sign in
                                Button { toggle(sign) } label: { row(sign) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if signs.isEmpty, trimmed.isEmpty {
                    Section {
                        Text("Type something that keeps showing up in your dreams — “Grandma”, “my old school”, “teeth falling out”.")
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NightBackground(stars: false))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Person, place, or theme")
            .navigationTitle("Dream Signs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .prominentConfirm) { Button(role: .confirm) { dismiss() } }
            }
        }
        .sensoryFeedback(.selection, trigger: entry.signs.count)
    }

    private func row(_ sign: DreamSign) -> some View {
        let tagged = entry.signs.contains { $0.key == sign.key }
        return HStack(spacing: 12) {
            Image(systemName: sign.category.symbol)
                .foregroundStyle(Palette.dawn)
                .frame(width: 24)
            Text(sign.name).foregroundStyle(Palette.text)
            Spacer()
            Text("\(sign.entries.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
            Image(systemName: tagged ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(tagged ? Palette.iris : Palette.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(tagged ? .isSelected : [])
    }

    private func toggle(_ sign: DreamSign) {
        if let index = entry.signs.firstIndex(where: { $0.key == sign.key }) {
            entry.signs.remove(at: index)
        } else {
            entry.signs.append(sign)
        }
        try? context.save()
    }

    private func create() {
        let sign = DreamSign(name: trimmed, category: category)
        context.insert(sign)
        entry.signs.append(sign)
        try? context.save()
        query = ""
    }
}
