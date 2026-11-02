import AVFoundation
import Speech
import SwiftUI

/// Speech-to-text for the journal, on the iPhone only (never Apple's servers). Keeps going
/// across pauses: when the recognizer finishes a segment, a new one starts seamlessly.
@MainActor
@Observable
final class DreamDictation {
    enum Status: Equatable {
        case idle, listening, paused
        case unavailable(String)
    }

    private(set) var status: Status = .idle
    /// Recent input levels, 0…1, oldest first — for the waveform.
    private(set) var levels: [Float] = Array(repeating: 0, count: 48)
    private(set) var startedAt: Date?

    /// Called with the full text (what was there before plus everything heard).
    @ObservationIgnored var onText: ((String) -> Void)?

    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var base = ""
    @ObservationIgnored private var segment = ""
    @ObservationIgnored private var generation = 0
    /// Segments in a row that ended in an error without any words — stops a restart loop.
    @ObservationIgnored private var emptyFailures = 0

    /// On-device recognition exists for the current language.
    static var isSupported: Bool {
        SFSpeechRecognizer(locale: .current)?.supportsOnDeviceRecognition ?? false
    }

    var isListening: Bool { status == .listening }
    var isActive: Bool { status == .listening || status == .paused }

    func start(appendingTo existing: String) async {
        guard !isActive else { return }
        guard !Showcase.isActive else {
            status = .listening
            startedAt = Date.now.addingTimeInterval(-48)
            levels = (0..<48).map { index in index < 26 ? Float(0.25 + 0.6 * abs(sin(Double(index) * 0.9))) : 0.08 }
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.supportsOnDeviceRecognition else {
            status = .unavailable(String(localized: "On-device speech isn't available for your language yet."))
            return
        }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAllowed, micAllowed else {
            status = .unavailable(String(localized: "Allow the microphone and speech recognition for Dreamsign in Settings."))
            return
        }
        self.recognizer = recognizer
        base = existing
        segment = ""
        startedAt = .now
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try beginCapture()
            status = .listening
        } catch {
            teardown()
            status = .unavailable(String(localized: "The microphone couldn't start. Try again."))
        }
    }

    func pause() {
        guard status == .listening else { return }
        endSegment()
        engine.pause()
        status = .paused
    }

    func resume() {
        guard status == .paused else { return }
        do {
            try engine.start()
            beginRecognition()
            status = .listening
        } catch {
            stop()
        }
    }

    func stop() {
        guard isActive else { return }
        endSegment()
        teardown()
        status = .idle
    }

    // MARK: Internals

    private func beginCapture() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.currentRequest?.append(buffer)
            let level = Self.level(of: buffer)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.push(level) } }
        }
        engine.prepare()
        try engine.start()
        beginRecognition()
    }

    /// Read from the audio thread; replaced only on the main thread between segments.
    @ObservationIgnored nonisolated(unsafe) private var currentRequest: SFSpeechAudioBufferRecognitionRequest?

    private func beginRecognition() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request
        currentRequest = request
        generation += 1
        let current = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, current == self.generation else { return }
                    if let text, !text.isEmpty { self.segment = text; self.emptyFailures = 0; self.publish() }
                    if failed, text == nil {
                        self.emptyFailures += 1
                        if self.emptyFailures >= 3 {
                            self.stop()
                            self.status = .unavailable(String(localized: "Couldn't hear anything. Try again, or type instead."))
                            return
                        }
                    }
                    if isFinal || failed {
                        // The recognizer ended this segment (a long pause, or its own limit): carry on.
                        self.commitSegment()
                        if self.status == .listening { self.beginRecognition() }
                    }
                }
            }
        }
    }

    private func endSegment() {
        generation += 1
        currentRequest = nil
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        commitSegment()
    }

    private func commitSegment() {
        guard !segment.isEmpty else { return }
        base = Self.join(base, segment)
        segment = ""
        publish()
    }

    private func publish() {
        onText?(Self.join(base, segment))
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        currentRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    static func join(_ a: String, _ b: String) -> String {
        guard !a.isEmpty else { return b }
        guard !b.isEmpty else { return a }
        return a.last?.isWhitespace == true ? a + b : a + " " + b
    }

    private nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += data[index] * data[index] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        // Speech sits roughly between -50 and -10 dBFS.
        let db = 20 * log10(max(rms, 1e-6))
        return min(max((db + 50) / 40, 0), 1)
    }
}

/// Live bars from the microphone level.
struct DictationWaveform: View {
    var levels: [Float]
    var tint: Color = Palette.iris

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(levels[index] > 0.1 ? tint : Palette.surfaceRaised)
                    .frame(width: 4, height: max(6, CGFloat(levels[index]) * 40))
            }
        }
        .frame(height: 44)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

/// The transcript with known dream signs highlighted.
struct HighlightedTranscript: View {
    var text: String
    var signs: [String]

    var body: some View {
        Text(attributed)
            .font(.title3)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = Palette.text
        for name in signs where name.count > 1 {
            var start = result.startIndex
            while start < result.endIndex,
                  let range = result[start...].range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) {
                result[range].foregroundColor = Palette.iris
                result[range].backgroundColor = Palette.iris.opacity(0.2)
                start = range.upperBound
            }
        }
        return result
    }

    /// Known signs mentioned in `text`.
    static func mentioned(_ signs: [String], in text: String) -> [String] {
        signs.filter { $0.count > 1 && text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// A microphone toggle that appends dictation to a text binding (journal editor).
struct DictationButton: View {
    @Binding var text: String
    @State private var dictation = DreamDictation()

    var body: some View {
        Button {
            if dictation.isActive {
                dictation.stop()
            } else {
                dictation.onText = { text = $0 }
                Task { await dictation.start(appendingTo: text) }
            }
        } label: {
            Image(systemName: dictation.isActive ? "stop.circle.fill" : "mic.fill")
                .symbolEffect(.pulse, isActive: dictation.isListening)
        }
        .accessibilityLabel(dictation.isActive ? Text("Stop dictation") : Text("Dictate"))
        .onDisappear { dictation.stop() }
    }
}
