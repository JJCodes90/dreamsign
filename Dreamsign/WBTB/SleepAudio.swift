import Foundation

/// Audio hooks for the WBTB flow. Intentionally silent for now — swap `SleepAudio.shared`
/// for a real implementation (guided MILD narration, a sleep soundscape) later.
@MainActor
protocol SleepAudioPlaying: AnyObject {
    /// Called when the MILD rehearsal starts. `phase` changes every 20 s: recall → intend → visualize.
    func beginMILDGuidance()
    func mildPhaseChanged(to phase: MILDPhase)
    /// Called on the back-to-sleep screen.
    func beginSleepSoundscape()
    func stopAll()
}

enum MILDPhase: Int, CaseIterable, Sendable {
    case recall, intend, visualize
}

@MainActor
final class SleepAudio: SleepAudioPlaying {
    static var shared: any SleepAudioPlaying = SleepAudio()

    func beginMILDGuidance() {}
    func mildPhaseChanged(to phase: MILDPhase) {}
    func beginSleepSoundscape() {}
    func stopAll() {}
}
