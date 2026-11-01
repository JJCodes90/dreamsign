import SwiftData
import SwiftUI

@main
struct DreamsignApp: App {
    @State private var model = AppModel()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WakeAlarm.self, DreamEntry.self, DreamSign.self)
        } catch {
            fatalError("Could not open the Dreamsign store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .fontDesign(.rounded)
                .tint(Palette.iris)
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await AlarmCoordinator.shared.resync()
            AppModel.scheduleBackgroundRefresh()
        }
    }
}
