import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        @Bindable var model = model
        Group {
            if let screen = Showcase.screen, Showcase.tab == nil {
                ShowcaseRoot(screen: screen)
            } else if onboarded || Showcase.isActive {
                TabView(selection: $model.tab) {
                    Tab("Alarms", systemImage: "alarm.fill", value: AppModel.Tab.alarms) { AlarmsView() }
                    Tab("Journal", systemImage: "book.closed.fill", value: AppModel.Tab.journal) { JournalView() }
                    Tab("Insights", systemImage: "chart.bar.fill", value: AppModel.Tab.insights) { InsightsView() }
                    Tab("Learn", systemImage: "graduationcap.fill", value: AppModel.Tab.learn) { LearnView() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .fullScreenCover(item: $model.wake) { session in
                    WakeFlowView(session: session)
                }
            } else {
                OnboardingView { onboarded = true }
            }
        }
        .task {
            guard !Showcase.isActive else { return }
            model.coordinator.startObserving()
            await model.becameActive(context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.becameActive(context) }
            case .background: AppModel.scheduleBackgroundRefresh()
            default: break
            }
        }
        .onChange(of: model.coordinator.alertingIDs) { _, ringing in
            if !ringing.isEmpty { model.presentWakeIfNeeded(context) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await model.coordinator.resync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            Task { await model.coordinator.resync() }
        }
    }
}
