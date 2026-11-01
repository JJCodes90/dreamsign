import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(sort: \DreamEntry.createdAt) private var entries: [DreamEntry]
    @Query private var signs: [DreamSign]

    private let calendar = Calendar.current

    private var facts: [JournalStats.EntryFact] {
        entries.map { JournalStats.EntryFact(date: $0.createdAt, recalled: !$0.isNoRecall, lucid: $0.isLucid) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ScrollView { emptyState }
                } else {
                    // One column when closed; two when open — streaks on one side, patterns on the other.
                    FoldAwareSplit(minimumSideWidth: 320) {
                        column { summaryCards }
                    } secondary: {
                        column { patternCards }
                    } stacked: {
                        column {
                            summaryCards
                            patternCards
                        }
                    }
                }
            }
            .background(NightBackground())
            .navigationTitle("Insights")
        }
    }

    @ViewBuilder
    private var summaryCards: some View {
        StreakHero(current: JournalStats.recallStreak(facts, now: .now, calendar: calendar),
                   longest: JournalStats.longestRecallStreak(facts, calendar: calendar))
        HStack(spacing: 12) {
            StatTile(value: "\(entries.count)", label: String(localized: "Entries"))
            StatTile(value: "\(entries.filter(\.isLucid).count)", label: String(localized: "Lucid"))
            StatTile(value: recallRateText, label: String(localized: "Recall"))
        }
    }

    @ViewBuilder
    private var patternCards: some View {
        WeeklyChart(buckets: JournalStats.entriesPerWeek(entries.map(\.createdAt), weeks: 8,
                                                         now: .now, calendar: calendar))
        TopSigns(signs: signs)
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 16) { content() }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
        }
    }

    private var recallRateText: String {
        guard let rate = JournalStats.recallRate(facts, calendar: calendar) else { return "—" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Palette.iris)
            Text("Patterns show up here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("A week of journaling is enough to see your recall streak and the dream signs that keep returning.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 120)
    }
}

private struct StreakHero: View {
    let current: Int
    let longest: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recall streak")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(current)")
                    .font(.system(size: 76, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
                Text(current == 1 ? "morning" : "mornings")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(current > 0 && current >= longest ? "Your best yet." : "Best: \(longest)")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
        }
        .card(tint: Palette.iris)
        .accessibilityElement(children: .combine)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyChart: View {
    let buckets: [JournalStats.WeekBucket]
    @State private var selected: Date?

    private var selectedBucket: JournalStats.WeekBucket? {
        guard let selected else { return nil }
        let calendar = Calendar.current
        return buckets.first { calendar.isDate($0.start, equalTo: selected, toGranularity: .weekOfYear) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Entries per week")
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Spacer()
                if let bucket = selectedBucket {
                    Text("\(bucket.count) · week of \(bucket.start.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Chart(buckets) { bucket in
                BarMark(x: .value("Week", bucket.start, unit: .weekOfYear),
                        y: .value("Entries", bucket.count),
                        width: .ratio(0.55))
                    .foregroundStyle(Palette.iris.opacity(selectedBucket == nil || selectedBucket == bucket ? 1 : 0.35))
                    .cornerRadius(4)
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.hairline)
                    AxisValueLabel().foregroundStyle(Palette.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Entries per week, last 8 weeks")
        }
        .card()
    }
}

private struct TopSigns: View {
    let signs: [DreamSign]

    private struct Ranked: Identifiable {
        let sign: DreamSign
        let count: Int
        var id: String { sign.key }
    }

    private var ranked: [Ranked] {
        let counts = signs.map { JournalStats.SignCount(name: $0.name, count: $0.entries.count) }
        let top = JournalStats.topSigns(counts, limit: 6)
        return top.compactMap { item in
            signs.first { $0.name == item.name }.map { Ranked(sign: $0, count: item.count) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top dream signs")
                .font(.headline)
                .foregroundStyle(Palette.text)
            if ranked.isEmpty {
                Text("Tag recurring people, places and themes in your entries. The ones that keep coming back are your best cues for noticing you're dreaming.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                let maxCount = ranked.map(\.count).max() ?? 1
                ForEach(ranked) { item in
                    NavigationLink {
                        JournalView(sign: item.sign)
                    } label: {
                        SignBar(sign: item.sign, count: item.count, fraction: Double(item.count) / Double(maxCount))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }
}

private struct SignBar: View {
    let sign: DreamSign
    let count: Int
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: sign.category.symbol)
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 16)
                Text(sign.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            GoalBar(progress: fraction, tint: Palette.iris, marksCompletion: false)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sign.name), \(sign.category.title), \(count) entries")
    }
}

#Preview {
    InsightsView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
