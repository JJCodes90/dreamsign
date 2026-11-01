import SwiftData
import SwiftUI

struct WakeCompleteView: View {
    let session: WakeSession
    let entry: DreamEntry?
    var onDone: () -> Void

    @Query private var entries: [DreamEntry]
    @State private var tagging = false
    @State private var appeared = false

    private var streak: Int {
        let facts = entries.map { JournalStats.EntryFact(date: $0.createdAt, recalled: !$0.isNoRecall) }
        return JournalStats.recallStreak(facts, now: .now, calendar: .current)
    }

    private var greeting: LocalizedStringKey {
        if session.occurrence.isTest { return "That's the whole flow." }
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }

    var body: some View {
        FoldAwareSplit {
            summary
        } secondary: {
            actions
        }
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.3)) { appeared = true } }
        .sheet(isPresented: $tagging) {
            if let entry { SignTaggerView(entry: entry) }
        }
    }

    private var summary: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 76, weight: .light))
                .foregroundStyle(LinearGradient(colors: [Palette.dawn, Palette.dawnDeep], startPoint: .top, endPoint: .bottom))
                .shadow(color: Palette.dawn.opacity(0.5), radius: 30)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            Text(greeting)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)
            TimelineView(.everyMinute) { context in
                ClockText(date: context.date, size: 30)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: 8) {
                Chip(text: String(localized: "Up in \(upDuration)"), symbol: "alarm", tint: Palette.dawn)
                if streak > 0 {
                    Chip(text: String(localized: "Recall streak \(streak)"), symbol: "moon.stars.fill", tint: Palette.iris)
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 8)
        }
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if let entry, !entry.isNoRecall {
                Button {
                    tagging = true
                } label: {
                    Label("Tag dream signs", systemImage: "tag")
                }
                .buttonStyle(.quiet)
            }
            Button("Done", action: onDone)
                .buttonStyle(.big)
        }
        .readableWidth(420)
    }

    private var upDuration: String {
        let seconds = max(Date.now.timeIntervalSince(session.occurrence.fireDate), 0)
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .narrow, maximumUnitCount: 2))
    }
}
