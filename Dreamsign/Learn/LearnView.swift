import SwiftData
import SwiftUI

/// Which lessons are done. Kept in UserDefaults — it's tiny and per-device.
@MainActor
@Observable
final class LearnProgress {
    static let shared = LearnProgress()
    private let key = "learn.completed"
    private(set) var completed: Set<String>

    private init() {
        if Showcase.isActive {
            completed = Set(Course.lessons.prefix(4).map(\.id))
        } else {
            completed = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        }
    }

    var fraction: Double { Double(completed.count) / Double(max(Course.lessons.count, 1)) }
    var nextLesson: Lesson? { Course.lessons.first { !completed.contains($0.id) } }

    func isDone(_ lesson: Lesson) -> Bool { completed.contains(lesson.id) }

    func toggle(_ lesson: Lesson) {
        if completed.contains(lesson.id) { completed.remove(lesson.id) } else { completed.insert(lesson.id) }
        UserDefaults.standard.set(Array(completed), forKey: key)
    }

    func next(after lesson: Lesson) -> Lesson? {
        guard let index = Course.lessons.firstIndex(of: lesson), Course.lessons.indices.contains(index + 1) else { return nil }
        return Course.lessons[index + 1]
    }
}

extension PracticeAction: Identifiable {
    var id: String { rawValue }
}

struct LearnView: View {
    @Environment(AppModel.self) private var model
    @State private var progress = LearnProgress.shared
    @State private var selection: String?
    @State private var practice: PracticeAction?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Group {
                    LearnHero(progress: progress) { lesson in selection = lesson.id }
                        .padding(.vertical, 6)
                    SectionHeader("Practice").padding(.top, 8)
                    PracticeGrid { practice = $0 }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: Metrics.gutter, bottom: 6, trailing: Metrics.gutter))

                ForEach(Course.modules) { module in
                    Section {
                        ForEach(module.lessons) { lesson in
                            NavigationLink(value: lesson.id) {
                                LessonRow(lesson: lesson, done: progress.isDone(lesson))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Palette.hairline)
                        }
                    } header: {
                        Text(module.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NightBackground())
            .navigationTitle("Learn")
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            if let id = selection, let lesson = Course.lesson(id) {
                LessonView(lesson: lesson, progress: progress,
                           onPractice: { practice = $0 },
                           onNext: { selection = $0.id })
                    .id(lesson.id)
            } else {
                ZStack {
                    NightBackground()
                    VStack(spacing: 12) {
                        Image(systemName: "graduationcap")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Palette.iris)
                        Text("Pick a lesson")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(item: $practice) { action in
            PracticeHost(action: action)
        }
    }
}

private struct LearnHero: View {
    let progress: LearnProgress
    var onContinue: (Lesson) -> Void

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: progress.fraction, lineWidth: 8, tint: Palette.iris)
                Text("\(progress.completed.count)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your path to lucidity")
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Text("\(progress.completed.count) of \(Course.lessons.count) lessons · \(Course.lessons.reduce(0) { $0 + $1.minutes }) minutes in all")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                if let next = progress.nextLesson {
                    Button { onContinue(next) } label: {
                        Label("Continue: \(next.title)", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.iris)
                    .padding(.top, 2)
                } else {
                    Label("Course complete", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.mint)
                }
            }
            Spacer(minLength: 0)
        }
        .card(tint: Palette.iris)
    }
}

private struct PracticeGrid: View {
    var onSelect: (PracticeAction) -> Void
    private let items: [PracticeAction] = [.realityCheck, .mild, .ssild, .cues, .nightstand]

    var body: some View {
        // A plain Grid: lazy grids inside List rows can send layout into a loop.
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { row in
                GridRow {
                    ForEach(items[row..<min(row + 2, items.count)]) { item in
                        tile(item)
                    }
                }
            }
        }
    }

    private func tile(_ item: PracticeAction) -> some View {
            Button { onSelect(item) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.title3)
                        .foregroundStyle(Palette.iris)
                    Text(item.shortTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                .card(padding: 14)
            }
            .buttonStyle(.plain)
    }
}

extension PracticeAction {
    var shortTitle: String {
        switch self {
        case .journal: String(localized: "Dream journal")
        case .dreamSigns: String(localized: "Dream signs")
        case .realityCheck: String(localized: "Reality check")
        case .mild: String(localized: "MILD")
        case .ssild: String(localized: "SSILD")
        case .wbtb: String(localized: "Lucid window")
        case .nightstand: String(localized: "Nightstand")
        case .cues: String(localized: "Lucidity cues")
        }
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let done: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: done ? "checkmark" : lesson.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(done ? Palette.ink : Palette.iris)
                .frame(width: 38, height: 38)
                .background(Circle().fill(done ? Palette.mint : Palette.iris.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title).foregroundStyle(Palette.text)
                Text("\(lesson.subtitle) · \(lesson.minutes) min")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? Text("Completed") : Text(""))
    }
}

/// Presents a practice tool full screen.
struct PracticeHost: View {
    let action: PracticeAction
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \DreamEntry.createdAt, order: .reverse) private var entries: [DreamEntry]

    var body: some View {
        switch action {
        case .realityCheck:
            RealityCheckView()
        case .mild:
            practiceStage {
                MILDView(minutes: 3, dreamText: entries.first { !$0.isNoRecall }?.text) { dismiss() }
            }
        case .ssild:
            practiceStage {
                SSILDView { dismiss() }
            }
        case .nightstand:
            NightstandView()
        case .cues:
            NavigationStack { CuesView() }
        case .wbtb:
            WBTBSettingsView(plan: model.wbtbPlan(context))
        case .journal, .dreamSigns:
            // Handled by switching tabs before presentation; nothing to show.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func practiceStage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            DawnBackground(progress: 0, stayNight: true)
            content()
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 36)
            Button(role: .close) { dismiss() }
                .buttonStyle(.glass)
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
        }
    }
}

#Preview {
    LearnView()
        .environment(AppModel())
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
