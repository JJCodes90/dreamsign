import AVFoundation
import Foundation

/// Audio for the night flows: a calm on-device voice for MILD and SSILD, and a generated
/// brown-noise soundscape for falling back asleep. Everything is synthesized locally.
@MainActor
protocol SleepAudioPlaying: AnyObject {
    func beginMILDGuidance()
    func mildPhaseChanged(to phase: MILDPhase)
    func beginSSILDGuidance()
    func ssildCue(_ sense: SSILDSense, slow: Bool)
    func beginSleepSoundscape()
    func stopAll()
}

enum MILDPhase: Int, CaseIterable, Sendable {
    case recall, intend, visualize
}

enum SSILDSense: Int, CaseIterable, Sendable {
    case sight, sound, touch
}

enum AudioPreferences {
    static let voiceKey = "audio.voiceGuidance"
    static let soundscapeKey = "audio.sleepSounds"

    static var voice: Bool { UserDefaults.standard.object(forKey: voiceKey) as? Bool ?? true }
    static var soundscape: Bool { UserDefaults.standard.object(forKey: soundscapeKey) as? Bool ?? true }
}

@MainActor
final class SleepAudio: SleepAudioPlaying {
    static var shared: any SleepAudioPlaying = SleepAudio()

    private let speech = AVSpeechSynthesizer()
    private let noise = BrownNoise()

    func beginMILDGuidance() {
        say(String(localized: "Settle in, and breathe slowly. Let's set your intention."))
    }

    func mildPhaseChanged(to phase: MILDPhase) {
        switch phase {
        case .recall: say(String(localized: "Recall the dream you just had. Every detail you can."))
        case .intend: say(String(localized: "Next time I'm dreaming, I'll recognize I'm dreaming."))
        case .visualize: say(String(localized: "See yourself back in the dream. Notice something odd. And realize: this is a dream."))
        }
    }

    func beginSSILDGuidance() {
        say(String(localized: "Close your eyes. We'll move your attention through your senses. Don't expect anything."))
    }

    func ssildCue(_ sense: SSILDSense, slow: Bool) {
        switch (sense, slow) {
        case (.sight, false): say(String(localized: "Sight."))
        case (.sound, false): say(String(localized: "Sound."))
        case (.touch, false): say(String(localized: "Touch."))
        case (.sight, true): say(String(localized: "Sight. Notice the darkness behind your eyelids."))
        case (.sound, true): say(String(localized: "Sound. Listen to whatever is there, even silence."))
        case (.touch, true): say(String(localized: "Touch. Feel the weight of your body, and anything unusual."))
        }
    }

    func beginSleepSoundscape() {
        guard AudioPreferences.soundscape else { return }
        activateSession()
        noise.start(fadeIn: 4, playFor: 30 * 60, fadeOut: 60)
    }

    func stopAll() {
        speech.stopSpeaking(at: .word)
        noise.stop()
    }

    private func say(_ text: String) {
        guard AudioPreferences.voice, !Showcase.isActive else { return }
        activateSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
        utterance.pitchMultiplier = 0.92
        utterance.volume = 0.75
        utterance.preUtteranceDelay = 0.2
        utterance.voice = Self.calmVoice
        speech.stopSpeaking(at: .word)
        speech.speak(utterance)
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// The best installed voice for the user's language (premium / enhanced when available).
    private static let calmVoice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }()
}

/// Soft brown noise (integrated white noise) generated in real time, with gentle fades.
@MainActor
final class BrownNoise {
    private var engine: AVAudioEngine?
    private let state = NoiseState()
    private var fadeTask: Task<Void, Never>?

    func start(fadeIn: TimeInterval, playFor duration: TimeInterval, fadeOut: TimeInterval) {
        stop()
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let state = state
        state.reset()
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let sample = state.next()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
        do {
            try engine.start()
        } catch {
            return
        }
        self.engine = engine
        state.setTarget(1, over: fadeIn)
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.state.setTarget(0, over: fadeOut)
            try? await Task.sleep(for: .seconds(fadeOut + 1))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        fadeTask?.cancel()
        fadeTask = nil
        engine?.stop()
        engine = nil
    }
}

/// Render-thread state. Only touched from the audio callback, apart from fade targets.
private final class NoiseState: @unchecked Sendable {
    private var last: Float = 0
    private var seed: UInt32 = 0x9E37_79B9
    private var gain: Float = 0
    private var target: Float = 0
    private var step: Float = 0

    func reset() {
        last = 0
        gain = 0
        target = 0
    }

    func setTarget(_ value: Float, over seconds: TimeInterval) {
        target = value
        step = abs(value - gain) / Float(max(seconds, 0.1) * 44_100)
    }

    func next() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        let white = Float(seed) / Float(UInt32.max) * 2 - 1
        last = (last + 0.02 * white) / 1.02
        if gain < target { gain = min(gain + step, target) } else if gain > target { gain = max(gain - step, target) }
        return last * 3.2 * gain
    }
}
