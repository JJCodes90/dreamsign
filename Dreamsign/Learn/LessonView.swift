import SwiftUI

struct LessonView: View {
    let lesson: Lesson
    let progress: LearnProgress
    var onPractice: (PracticeAction) -> Void
    var onNext: (Lesson) -> Void

    @Environment(AppModel.self) private var model

    private var moduleTitle: String {
        Course.modules.first { $0.lessons.contains(lesson) }?.title ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                }
                if let action = lesson.practice {
                    practiceCard(action)
                }
                if !lesson.sources.isEmpty {
                    sources
                }
                footer
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
            .readableWidth(660)
        }
        .background(NightBackground(stars: false))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(lesson.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { progress.toggle(lesson) } label: {
                    Label(progress.isDone(lesson) ? "Completed" : "Mark Complete",
                          systemImage: progress.isDone(lesson) ? "checkmark.circle.fill" : "checkmark.circle")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: lesson.symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.iris)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Palette.iris.opacity(0.14)))
                .shadow(color: Palette.iris.opacity(0.4), radius: 18)
            Text(moduleTitle.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 6)
            Text(lesson.title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.text)
            Text("\(lesson.subtitle) · \(lesson.minutes) min read")
                .font(.title3)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func practiceCard(_ action: PracticeAction) -> some View {
        Button {
            switch action {
            case .journal: model.tab = .alarms
            case .dreamSigns: model.tab = .journal
            default: onPractice(action)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: action.symbol)
                    .font(.title2)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Palette.dawn))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try it tonight")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.dawn)
                    Text(action.title)
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.textTertiary)
            }
            .card(tint: Palette.dawn)
        }
        .buttonStyle(.plain)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Sources")
            ForEach(lesson.sources) { source in
                Link(destination: source.url) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                        Text(source.text)
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var footer: some View {
        let done = progress.isDone(lesson)
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.35)) { progress.toggle(lesson) }
            } label: {
                Label(done ? "Completed" : "Mark as complete", systemImage: done ? "checkmark.seal.fill" : "checkmark")
            }
            .buttonStyle(.big(done ? Palette.mint : Palette.iris))
            .sensoryFeedback(.success, trigger: done) { _, isDone in isDone }

            if done, let next = progress.next(after: lesson) {
                Button { onNext(next) } label: {
                    Label("Next: \(next.title)", systemImage: "arrow.right")
                }
                .buttonStyle(.quiet)
            }
        }
        .padding(.top, 10)
    }
}

private struct BlockView: View {
    let block: LessonBlock

    var body: some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            Text(text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        case .steps(let steps):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Palette.iris))
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                        Text(step)
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .card()
        case .tip(let text):
            Callout(symbol: "lightbulb.fill", title: String(localized: "Tip"), text: text, tint: Palette.mint)
        case .science(let text):
            Callout(symbol: "flask.fill", title: String(localized: "The science"), text: text, tint: Palette.iris)
        case .caution(let text):
            Callout(symbol: "exclamationmark.triangle.fill", title: String(localized: "Good to know"), text: text, tint: Palette.dawn)
        case .fact(let value, let label):
            HStack(alignment: .center, spacing: 16) {
                Text(value)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Palette.text, Palette.iris], startPoint: .top, endPoint: .bottom))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(tint: Palette.iris)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct Callout: View {
    let symbol: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .lineSpacing(4)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16, tint: tint)
    }
}
