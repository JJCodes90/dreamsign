import SwiftData
import SwiftUI
import UIKit

/// Drives one wake-up: steps in order, chain deferral while active, completion.
@MainActor
@Observable
final class WakeFlowModel {
    let session: WakeSession
    private(set) var index = 0
    private(set) var enforcedComplete = false
    var savedEntry: DreamEntry?
    @ObservationIgnored private var lastPing = Date.distantPast

    init(session: WakeSession) {
        self.session = session
    }

    var current: WakeSession.Step? {
        session.steps.indices.contains(index) ? session.steps[index] : nil
    }

    var enforcedTotal: Int { session.steps.filter(\.isEnforced).count }
    var enforcedDone: Int { session.steps.prefix(index).filter(\.isEnforced).count }

    var dawnProgress: Double {
        enforcedTotal == 0 ? 1 : Double(enforcedDone) / Double(enforcedTotal)
    }

    func begin() async {
        await AlarmCoordinator.shared.beginWake(session.occurrence)
    }

    /// Any sign of life pushes the next ring back (throttled here and in the planner).
    func activity() {
        guard !enforcedComplete, Date.now.timeIntervalSince(lastPing) > 15 else { return }
        lastPing = .now
        let id = session.occurrence.id
        Task { await AlarmCoordinator.shared.noteActivity(id) }
    }

    func advance(app: AppModel, context: ModelContext) async {
        index += 1
        guard !enforcedComplete, !session.steps.dropFirst(index).contains(where: \.isEnforced) else { return }
        enforcedComplete = true
        app.wakeFinishedAt = .now
        await AlarmCoordinator.shared.completeWake(session.occurrence)
        if session.disablesAlarm, let alarm = app.alarm(session.occurrence.alarmID, context) {
            alarm.isEnabled = false
            try? context.save()
        }
        await app.syncAlarms(context)
    }
}

struct WakeFlowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var flow: WakeFlowModel

    init(session: WakeSession) {
        _flow = State(initialValue: WakeFlowModel(session: session))
    }

    var body: some View {
        ZStack {
            DawnBackground(progress: flow.dawnProgress, stayNight: flow.session.kind == .wbtb)

            VStack(spacing: 0) {
                if flow.enforcedTotal > 1, !flow.enforcedComplete {
                    StepDots(total: flow.enforcedTotal, done: flow.enforcedDone)
                        .padding(.top, 10)
                }
                stepView
                    .id(flow.current?.id ?? "done")
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 24)), removal: .opacity))
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)
        }
        .animation(.smooth(duration: 0.55), value: flow.index)
        .simultaneousGesture(TapGesture().onEnded { flow.activity() })
        .task { await flow.begin() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .interactiveDismissDisabled()
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private var stepView: some View {
        switch flow.current {
        case .challenge(let challenge)?:
            challengeView(challenge)
        case .confirm?:
            ConfirmAwakeView { advance() }
        case .mild?:
            MILDView(minutes: flow.session.mildMinutes, dreamText: flow.savedEntry?.isNoRecall == false ? flow.savedEntry?.text : nil) {
                advance()
            }
        case .backToSleep?:
            BackToSleepView { app.endWake() }
        case nil:
            WakeCompleteView(session: flow.session, entry: flow.savedEntry) { app.endWake() }
        }
    }

    @ViewBuilder
    private func challengeView(_ challenge: Challenge) -> some View {
        switch challenge.kind {
        case .shake:
            ShakeChallengeView(target: challenge.shakeCount, onActivity: { flow.activity() }) { advance() }
        case .math:
            MathChallengeView(difficulty: challenge.mathDifficulty, target: challenge.mathProblems,
                              onActivity: { flow.activity() }) { advance() }
        case .journal:
            JournalChallengeView(minimumWords: challenge.journalWords,
                                 source: flow.session.kind == .wbtb ? .wbtb : .alarm,
                                 draftKey: flow.session.occurrence.id,
                                 onActivity: { flow.activity() }) { entry in
                flow.savedEntry = entry
                advance()
            }
        }
    }

    private func advance() {
        Task { await flow.advance(app: app, context: context) }
    }
}

// MARK: - Pieces

struct ChallengeHeader: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct StepDots: View {
    let total: Int
    let done: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { step in
                Capsule()
                    .fill(step < done ? Palette.mint : step == done ? Palette.text : Palette.text.opacity(0.2))
                    .frame(width: step == done ? 28 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.4), value: done)
        .accessibilityElement()
        .accessibilityLabel("Step \(min(done + 1, total)) of \(total)")
    }
}

private struct ConfirmAwakeView: View {
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ChallengeHeader(title: "Are you up?", subtitle: "Sit up, feet on the floor.")
            Spacer()
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 90, weight: .light))
                .foregroundStyle(LinearGradient(colors: [Palette.dawn, Palette.dawnDeep], startPoint: .top, endPoint: .bottom))
            Spacer()
            Button("I'm up", action: onConfirm)
                .buttonStyle(.big)
        }
    }
}

/// Small shake used for wrong answers.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 12
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}
