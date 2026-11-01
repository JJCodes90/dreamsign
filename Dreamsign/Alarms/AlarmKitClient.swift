import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

/// Metadata carried with every Dreamsign alarm (readable by a future Live Activity).
struct DreamsignAlarmMetadata: AlarmMetadata {
    var alarmID: UUID?
    var kind: String
    var ring: Int
}

enum AlarmAuthorization: Equatable {
    case notDetermined, authorized, denied

    init(_ state: AlarmManager.AuthorizationState) {
        switch state {
        case .authorized: self = .authorized
        case .denied: self = .denied
        default: self = .notDetermined
        }
    }
}

/// Thin wrapper over `AlarmManager`: builds configurations and applies planner operations.
@MainActor
final class AlarmKitClient {
    typealias Configuration = AlarmManager.AlarmConfiguration<DreamsignAlarmMetadata>

    struct ApplyResult {
        var failedSchedules: Set<UUID> = []
        var limitReached = false
        var lastError: String?
    }

    /// Follow-up rings past this index switch to the loudest sound.
    static let escalationRing = 5

    private let manager = AlarmManager.shared

    var authorization: AlarmAuthorization { AlarmAuthorization(manager.authorizationState) }

    func requestAuthorization() async -> AlarmAuthorization {
        do {
            return AlarmAuthorization(try await manager.requestAuthorization())
        } catch {
            return authorization
        }
    }

    func authorizationUpdates() -> some AsyncSequence<AlarmManager.AuthorizationState, Never> {
        manager.authorizationUpdates
    }

    func alarmUpdates() -> some AsyncSequence<[Alarm], Never> {
        manager.alarmUpdates
    }

    func snapshot() -> [AlarmSnapshot] {
        let alarms = (try? manager.alarms) ?? []
        return alarms.map { AlarmSnapshot(id: $0.id, isAlerting: $0.state == .alerting) }
    }

    func apply(_ operations: [ChainOperation]) async -> ApplyResult {
        var result = ApplyResult()
        for operation in operations {
            switch operation {
            case .cancel(let id):
                try? manager.cancel(id: id)
            case .stop(let id):
                try? manager.stop(id: id)
            case .schedulePrimary, .scheduleRing:
                guard !result.limitReached else {
                    result.failedSchedules.insert(operation.alarmID)
                    continue
                }
                do {
                    try await schedule(operation)
                } catch {
                    result.failedSchedules.insert(operation.alarmID)
                    result.lastError = error.localizedDescription
                    if let alarmError = error as? AlarmManager.AlarmError, alarmError == .maximumLimitReached {
                        result.limitReached = true
                    }
                }
            }
        }
        return result
    }

    private func schedule(_ operation: ChainOperation) async throws {
        switch operation {
        case .schedulePrimary(let spec):
            let schedule = Alarm.Schedule.relative(.init(
                time: .init(hour: spec.time.hour, minute: spec.time.minute),
                repeats: spec.weekdays.isOneShot ? .never : .weekly(spec.weekdays.localeWeekdays)))
            let configuration = makeConfiguration(
                schedule: schedule, title: Self.title(label: spec.label, kind: spec.kind, ring: 0),
                kind: spec.kind, sound: AlarmSound(rawValue: spec.soundID) ?? .system,
                metadata: DreamsignAlarmMetadata(alarmID: spec.id, kind: spec.kind.rawValue, ring: 0),
                alarmKitID: spec.id)
            _ = try await manager.schedule(id: spec.id, configuration: configuration)

        case .scheduleRing(let request):
            var sound = AlarmSound(rawValue: request.soundID) ?? .system
            if request.kind == .wake, request.index > Self.escalationRing { sound = .beacon }
            let configuration = makeConfiguration(
                schedule: .fixed(request.ring.fireDate),
                title: Self.title(label: request.label, kind: request.kind, ring: request.index),
                kind: request.kind, sound: sound,
                metadata: DreamsignAlarmMetadata(alarmID: request.alarmID, kind: request.kind.rawValue, ring: request.index),
                alarmKitID: request.ring.id)
            _ = try await manager.schedule(id: request.ring.id, configuration: configuration)

        case .cancel, .stop:
            break
        }
    }

    private func makeConfiguration(schedule: Alarm.Schedule, title: LocalizedStringResource, kind: AlarmKind,
                                   sound: AlarmSound, metadata: DreamsignAlarmMetadata, alarmKitID: UUID) -> Configuration {
        let buttonText: LocalizedStringResource = kind == .wbtb ? "Begin" : "Wake Up"
        let open = AlarmButton(text: buttonText, textColor: .white,
                               systemImageName: kind == .wbtb ? "moon.stars.fill" : "sun.horizon.fill")
        // The system supplies the Stop control; it can't be hidden (hence the ring chain).
        let alert = AlarmPresentation.Alert(title: title, secondaryButton: open, secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: metadata,
                                         tintColor: Palette.iris)
        return .alarm(schedule: schedule,
                      attributes: attributes,
                      stopIntent: StopRingIntent(alarmKitID: alarmKitID),
                      secondaryIntent: WakeUpIntent(alarmKitID: alarmKitID),
                      sound: sound.alertSound)
    }

    static func title(label: String, kind: AlarmKind, ring: Int) -> LocalizedStringResource {
        switch (kind, ring) {
        case (_, 0): LocalizedStringResource("\(label)")
        case (.wbtb, _): LocalizedStringResource("Lucid window — tap Begin")
        case (.wake, _): LocalizedStringResource("Not up yet — tap Wake Up")
        }
    }
}

extension AlarmSound {
    var alertSound: AlertConfiguration.AlertSound {
        guard let fileName else { return .default }
        return .named(fileName)
    }
}

extension WeekdaySet {
    var localeWeekdays: [Locale.Weekday] {
        let all: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return calendarWeekdays.map { all[$0 - 1] }
    }
}
