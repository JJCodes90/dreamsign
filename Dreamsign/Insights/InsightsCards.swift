import SwiftData
import SwiftUI

/// The month as a grid: how much you remembered each morning, lucid mornings in iris.
struct DreamCalendarCard: View {
    let entries: [DreamEntry]
    @State private var month = Date.now
    private let calendar = Calendar.current

    private var facts: [DreamCalendar.Fact] {
        entries.map { DreamCalendar.Fact(date: $0.createdAt, recalled: !$0.isNoRecall, lucid: $0.isLucid,
                                         words: $0.text.split(whereSeparator: \.isWhitespace).count) }
    }

    var body: some View {
        let days = DreamCalendar.month(containing: month, facts: facts, calendar: calendar)
        let present = days.compactMap { $0 }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
                    .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
            }
            .buttonStyle(.borderless)
            .tint(Palette.iris)

            Text("\(present.filter { $0.level >= .fragment }.count) mornings logged · \(present.filter { $0.level == .lucid }.count) lucid")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)

            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    ForEach(WeekdaySet.displayOrder(for: calendar), id: \.self) { weekday in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<(days.count + 6) / 7, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            if index < days.count, let day = days[index] {
                                cell(day)
                            } else {
                                Color.clear.frame(height: 34)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                legend(color: Palette.iris.opacity(0.22), String(localized: "Fragment"))
                legend(color: Palette.iris.opacity(0.48), String(localized: "Full dream"))
                legend(color: Palette.iris, String(localized: "Lucid"))
            }
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
        }
        .card()
        .sensoryFeedback(.selection, trigger: month)
    }

    private func cell(_ day: DreamDay) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        return Text("\(calendar.component(.day, from: day.date))")
            .font(.caption.weight(day.level == .lucid ? .bold : .semibold).monospacedDigit())
            .foregroundStyle(day.level == .lucid ? Palette.ink : day.level == .none ? Palette.textTertiary : Palette.text)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(fill(day.level), in: .rect(cornerRadius: 9, style: .continuous))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.dawn, lineWidth: 1.5)
                }
            }
            .accessibilityLabel(Text(day.date.formatted(date: .abbreviated, time: .omitted)))
    }

    private func fill(_ level: RecallLevel) -> Color {
        switch level {
        case .none: Palette.surfaceRaised.opacity(0.6)
        case .fragment: Palette.iris.opacity(0.22)
        case .full: Palette.iris.opacity(0.48)
        case .lucid: Palette.iris
        }
    }

    private func legend(color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

/// Recent wins and the next goal.
struct MilestonesRow: View {
    let facts: [JournalStats.EntryFact]

    var body: some View {
        let items = Milestones.highlights(facts, calendar: .current)
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(String(localized: "Milestones"))
            HStack(spacing: 10) {
                ForEach(items) { milestone in
                    tile(milestone)
                }
            }
        }
    }

    private func tile(_ milestone: Milestone) -> some View {
        let tint = milestone.isAchieved ? (milestone.symbol == "flame.fill" ? Palette.dawn : Palette.mint) : Palette.textTertiary
        return VStack(spacing: 4) {
            Image(systemName: milestone.symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(milestone.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(milestone.isAchieved ? Palette.text : Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let date = milestone.achievedAt {
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            } else {
                Text("\(milestone.current)/\(milestone.target)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(milestone.isAchieved ? tint.opacity(0.12) : Palette.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(milestone.isAchieved ? tint.opacity(0.35) : Palette.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: milestone.isAchieved ? [] : [4, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sleep from Apple Health, and whether longer nights bring more recall.
struct SleepCard: View {
    let facts: [JournalStats.EntryFact]
    @State private var health = SleepHealth.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(String(localized: "Sleep · from Health"))
                Text("Optional").font(.caption).foregroundStyle(Palette.textTertiary)
            }
            switch health.status {
            case .connected:
                if let asleep = health.averageAsleep {
                    HStack(spacing: 22) {
                        stat(SleepHealth.hoursText(asleep), "avg asleep", Palette.text)
                        if let rem = health.averageREM {
                            stat(SleepHealth.hoursText(rem), "avg REM", Palette.iris)
                        }
                    }
                    insight
                } else {
                    Text("No sleep recorded in the last four weeks. Sleep with your Apple Watch, or turn on Sleep Focus.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
            case .notConnected:
                Text("See how sleep length and REM relate to what you remember.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
                Button("Connect Health") { Task { await health.connect() } }
                    .buttonStyle(.quiet)
            case .unavailable(let message):
                Text(message).font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        }
        .card()
        .task { await health.refresh() }
    }

    @ViewBuilder
    private var insight: some View {
        if let comparison = SleepNights.recallComparison(health.nights, facts: facts, calendar: .current) {
            let ratio = comparison.shortRate > 0 ? comparison.longRate / comparison.shortRate : 0
            if ratio >= 1.2 {
                Text("You remember \(ratio.formatted(.number.precision(.fractionLength(1))))× more often after 7+ hours.")
                    .font(.subheadline).foregroundStyle(Palette.text)
            } else {
                Text("Recall after 7+ hours: \(comparison.longRate.formatted(.percent.precision(.fractionLength(0)))), shorter nights: \(comparison.shortRate.formatted(.percent.precision(.fractionLength(0)))).")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        } else {
            Text("A few more nights and Dreamsign can compare long and short nights.")
                .font(.footnote).foregroundStyle(Palette.textTertiary)
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}

/// A doorway to the dream world map.
struct DreamWorldLink: View {
    let signCount: Int

    var body: some View {
        NavigationLink {
            DreamWorldView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.iris)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Palette.iris.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your dream world").font(.headline).foregroundStyle(Palette.text)
                    Text("\(signCount) signs, mapped by the dreams they share")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textTertiary)
            }
            .card(tint: Palette.iris)
        }
        .buttonStyle(.plain)
    }
}
