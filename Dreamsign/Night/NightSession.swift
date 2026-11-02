import AVFoundation
import CoreMotion
import Foundation
import Observation

/// Tonight's choices, remembered between nights.
enum NightPreferences {
    private static let defaults = UserDefaults.standard

    static var soundscape: Soundscape {
        get { Soundscape(rawValue: defaults.string(forKey: "night.soundscape") ?? "") ?? .rain }
        set { defaults.set(newValue.rawValue, forKey: "night.soundscape") }
    }

    static var sleepTimerMinutes: Int {
        get { defaults.object(forKey: "night.timer") as? Int ?? 45 }
        set { defaults.set(newValue, forKey: "night.timer") }
    }

    static var cuesTonight: Bool {
        get { Showcase.isActive || defaults.bool(forKey: "night.cues") }
        set { defaults.set(newValue, forKey: "night.cues") }
    }

    static var lucidWindowTonight: Bool {
        get { Showcase.isActive || defaults.bool(forKey: "night.lucidWindow") }
        set { defaults.set(newValue, forKey: "night.lucidWindow") }
    }

    /// Key of the dream sign chosen as tonight's intention.
    static var intentionSign: String? {
        get { defaults.string(forKey: "night.sign") }
        set { defaults.set(newValue, forKey: "night.sign") }
    }

    static let timerOptions = [15, 30, 45, 60, 0]

    static func timerTitle(_ minutes: Int) -> String {
        minutes == 0 ? String(localized: "All night") : String(localized: "\(minutes) min")
    }
}

/// Lucidity-cue setup: how loud, and whether the cue has been trained.
enum CueSettings {
    private static let defaults = UserDefaults.standard

    static var volume: Double {
        get { defaults.object(forKey: "cues.volume") as? Double ?? 0.18 }
        set { defaults.set(newValue, forKey: "cues.volume") }
    }

    static var lastTrained: Date? {
        get { defaults.object(forKey: "cues.trained") as? Date }
        set { defaults.set(newValue, forKey: "cues.trained") }
    }

    static var sessions: Int {
        get { defaults.integer(forKey: "cues.sessions") }
        set { defaults.set(newValue, forKey: "cues.sessions") }
    }

    static var isTrained: Bool { Showcase.isActive || lastTrained != nil }
}

/// Plays a night: a generated soundscape that fades on a timer, quiet lucidity cues in the
/// late-night window, and a soft lead-in that rises into the morning alarm. Audio keeps the
/// app running in the background; AlarmKit still rings the alarm itself.
@MainActor
@Observable
final class NightSession {
    static let shared = NightSession()

    private(set) var plan: NightPlan?
    private(set) var startedAt: Date?
    private(set) var cuesPlayed = 0
    var isRunning: Bool { plan != nil }

    @ObservationIgnored private var audio: NightAudioEngine?
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var lastMovement: Date?
    @ObservationIgnored private var lastBurst: Date?
    @ObservationIgnored private var heldUntil: Date?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    func start(_ plan: NightPlan) {
        stop()
        guard !Showcase.isActive else {
            self.plan = plan
            startedAt = .now
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        let engine = NightAudioEngine(soundscape: plan.soundscape)
        guard engine.start() else { return }
        audio = engine
        self.plan = plan
        startedAt = .now
        cuesPlayed = 0
        lastBurst = nil
        lastMovement = nil
        if plan.cues != nil { startMotion() }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
            guard ended else { return }
            MainActor.assumeIsolated {
                try? AVAudioSession.sharedInstance().setActive(true)
                _ = self?.audio?.start()
            }
        }
        tick = Task { [weak self] in
            while !Task.isCancelled {
                self?.step(now: .now)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        tick?.cancel()
        tick = nil
        audio?.stop()
        audio = nil
        motion.stopAccelerometerUpdates()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if plan != nil, !Showcase.isActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        plan = nil
        startedAt = nil
    }

    /// No cues for a while (someone's awake for a lucid window).
    func holdCues(for seconds: TimeInterval) {
        heldUntil = Date.now.addingTimeInterval(seconds)
    }

    private func step(now: Date) {
        guard let plan, let startedAt, let audio else { return }
        if now >= plan.endDate(startedAt: startedAt) {
            stop()
            return
        }
        audio.setSoundscapeLevel(plan.soundscapeLevel(at: now, startedAt: startedAt))
        audio.setLeadIn(plan.leadInLevel(at: now))
        if let cues = plan.cues,
           cues.shouldStartBurst(now: now, lastBurst: lastBurst, lastMovement: lastMovement, heldUntil: heldUntil) {
            lastBurst = now
            audio.playCue(times: cues.burst, spacing: cues.burstSpacing, volume: cues.volume)
            cuesPlayed += cues.burst
        }
    }

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.2
        motion.startAccelerometerUpdates(to: OperationQueue()) { [weak self] data, _ in
            guard let a = data?.acceleration else { return }
            // At rest the magnitude is ~1 g; turning over in bed shows up as a clear jolt.
            let jolt = abs(sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 1)
            guard jolt > 0.08 else { return }
            Task { @MainActor in self?.lastMovement = .now }
        }
    }
}

/// The audio graph: generated soundscape + cue and lead-in players.
@MainActor
final class NightAudioEngine {
    private let engine = AVAudioEngine()
    private let noise: SoundscapeRenderer
    private let cuePlayer = AVAudioPlayerNode()
    private let leadInPlayer = AVAudioPlayerNode()
    private var cueBuffer: AVAudioPCMBuffer?
    private var leadInBuffer: AVAudioPCMBuffer?
    private var leadInPlaying = false

    init(soundscape: Soundscape) {
        noise = SoundscapeRenderer(kind: soundscape)
        cueBuffer = Self.load("Cue")
        leadInBuffer = Self.load("Sunrise")

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let renderer = noise
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let sample = renderer.next()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.attach(cuePlayer)
        engine.attach(leadInPlayer)
        engine.connect(cuePlayer, to: engine.mainMixerNode, format: cueBuffer?.format ?? format)
        engine.connect(leadInPlayer, to: engine.mainMixerNode, format: leadInBuffer?.format ?? format)
        engine.mainMixerNode.outputVolume = 0.6
    }

    @discardableResult
    func start() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    func stop() {
        cuePlayer.stop()
        leadInPlayer.stop()
        engine.stop()
    }

    func setSoundscapeLevel(_ level: Double) {
        noise.setTarget(Float(level), over: 1)
    }

    func setLeadIn(_ level: Double?) {
        guard let level else {
            if leadInPlaying { leadInPlayer.stop(); leadInPlaying = false }
            return
        }
        if !leadInPlaying, let leadInBuffer {
            leadInPlayer.scheduleBuffer(leadInBuffer, at: nil, options: .loops)
            leadInPlayer.play()
            leadInPlaying = true
        }
        leadInPlayer.volume = Float(level)
    }

    func playCue(times: Int, spacing: TimeInterval, volume: Double) {
        guard let cueBuffer else { return }
        cuePlayer.volume = Float(volume)
        if !cuePlayer.isPlaying { cuePlayer.play() }
        let rate = cueBuffer.format.sampleRate
        guard let now = cuePlayer.lastRenderTime.flatMap({ cuePlayer.playerTime(forNodeTime: $0) }) else {
            for _ in 0..<times { cuePlayer.scheduleBuffer(cueBuffer, at: nil) }
            return
        }
        for index in 0..<times {
            let start = now.sampleTime + AVAudioFramePosition((0.3 + Double(index) * spacing) * rate)
            cuePlayer.scheduleBuffer(cueBuffer, at: AVAudioTime(sampleTime: start, atRate: rate))
        }
    }

    private static func load(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        try? file.read(into: buffer)
        return buffer
    }
}

/// Render-thread noise generator: rain (pink noise + droplets), ocean (swelling brown noise)
/// or plain brown noise. Only fade targets are touched from outside the audio callback.
final class SoundscapeRenderer: @unchecked Sendable {
    private let kind: Soundscape
    private var seed: UInt32 = 0x2545_F491
    private var brown: Float = 0
    private var pink: (Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0)
    private var drop: Float = 0
    private var dropLevel: Float = 0
    private var lastWhite: Float = 0
    private var phase: Double = 0
    private var gain: Float = 0
    private var target: Float = 0
    private var step: Float = 0

    init(kind: Soundscape) { self.kind = kind }

    func setTarget(_ value: Float, over seconds: TimeInterval) {
        target = value
        step = max(abs(value - gain), 0.0001) / Float(max(seconds, 0.05) * 44_100)
    }

    private func white() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    func next() -> Float {
        if gain < target { gain = min(gain + step, target) } else if gain > target { gain = max(gain - step, target) }
        guard gain > 0.0001 else { return 0 }
        let w = white()
        var sample: Float
        switch kind {
        case .off:
            return 0
        case .brown:
            brown = (brown + 0.02 * w) / 1.02
            sample = brown * 3.2
        case .ocean:
            brown = (brown + 0.02 * w) / 1.02
            phase += 1 / (44_100 * 9.5)
            if phase > 1 { phase -= 1 }
            let swell = Float(pow((sin(phase * 2 * .pi) + 1) / 2, 2))
            sample = brown * 3.4 * (0.25 + 0.75 * swell)
        case .rain:
            // Paul Kellet's pink-noise filter.
            pink.0 = 0.99886 * pink.0 + w * 0.0555179
            pink.1 = 0.99332 * pink.1 + w * 0.0750759
            pink.2 = 0.96900 * pink.2 + w * 0.1538520
            pink.3 = 0.86650 * pink.3 + w * 0.3104856
            pink.4 = 0.55000 * pink.4 + w * 0.5329522
            pink.5 = -0.7616 * pink.5 - w * 0.0168980
            let p = (pink.0 + pink.1 + pink.2 + pink.3 + pink.4 + pink.5 + pink.6 + w * 0.5362) * 0.09
            pink.6 = w * 0.115926
            // Occasional droplets: short, bright, quickly decaying ticks.
            if dropLevel < 0.01, white() > 0.9993 { dropLevel = 0.15 + 0.25 * abs(white()) }
            drop = (w - lastWhite) * dropLevel
            dropLevel *= 0.9965
            lastWhite = w
            sample = p * 0.8 + drop * 0.35
        }
        return sample * gain
    }
}
