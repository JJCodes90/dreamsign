import Foundation
import HealthKit
import Observation

/// Optional: nights from Apple Health (read only), to see how sleep length relates to recall.
@MainActor
@Observable
final class SleepHealth {
    static let shared = SleepHealth()

    enum Status: Equatable {
        case notConnected, connected
        case unavailable(String)
    }

    private(set) var status: Status
    private(set) var nights: [SleepNight] = []
    private let store = HKHealthStore()
    private let connectedKey = "health.sleep.connected"

    private init() {
        if Showcase.isActive {
            status = .connected
            nights = Self.sampleNights()
        } else if !HKHealthStore.isHealthDataAvailable() {
            status = .unavailable(String(localized: "Health isn't available on this device."))
        } else {
            status = UserDefaults.standard.bool(forKey: connectedKey) ? .connected : .notConnected
        }
    }

    var averageAsleep: Double? { average(\.asleepMinutes) }
    var averageREM: Double? {
        let withREM = nights.filter { $0.remMinutes > 0 }
        guard !withREM.isEmpty else { return nil }
        return withREM.map(\.remMinutes).reduce(0, +) / Double(withREM.count)
    }

    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
            UserDefaults.standard.set(true, forKey: connectedKey)
            status = .connected
            await refresh()
        } catch {
            status = .unavailable(String(localized: "Sleep data needs a build signed with Health access (TestFlight or App Store)."))
        }
    }

    func refresh() async {
        guard status == .connected, !Showcase.isActive else { return }
        let start = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return }
        let mapped = samples.compactMap { sample -> SleepSample? in
            let stage: SleepStage
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .asleepREM: stage = .rem
            case .asleepCore, .asleepDeep, .asleepUnspecified: stage = .asleep
            case .awake: stage = .awake
            case .inBed: stage = .inBed
            default: return nil
            }
            return SleepSample(start: sample.startDate, end: sample.endDate, stage: stage)
        }
        nights = SleepNights.summarize(mapped, calendar: .current)
    }

    private func average(_ key: KeyPath<SleepNight, Double>) -> Double? {
        guard !nights.isEmpty else { return nil }
        return nights.map { $0[keyPath: key] }.reduce(0, +) / Double(nights.count)
    }

    private static func sampleNights() -> [SleepNight] {
        var random = SeededRandomNumberGenerator(seed: 5)
        let calendar = Calendar.current
        return (1...21).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { return nil }
            let asleep = Double.random(in: 340...500, using: &random)
            return SleepNight(morning: day, asleepMinutes: asleep, remMinutes: asleep * Double.random(in: 0.19...0.25, using: &random))
        }
    }
}

extension SleepHealth {
    static func hoursText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return String(localized: "\(total / 60)h \(total % 60)m")
    }
}
