import AVFoundation
import SwiftUI

struct SoundPickerView: View {
    @Binding var selection: AlarmSound

    var body: some View {
        List {
            Section {
                ForEach(AlarmSound.allCases) { sound in
                    Button {
                        selection = sound
                        SoundPreviewer.shared.play(sound)
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sound.title).foregroundStyle(Palette.text)
                                Text(sound.detail).font(.subheadline).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            if sound == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.iris)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sound == selection ? .isSelected : [])
                }
            } footer: {
                Text("Alarms play at your Ringer and Alerts volume — iOS doesn't let apps raise it. Classic is the system alarm sound and the most dependable; custom sounds can play only once, or quietly, on some iOS versions. Follow-up rings always use Classic.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(NightBackground(stars: false))
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { SoundPreviewer.shared.stop() }
    }
}

/// Plays bundled alarm sounds for preview, even with the ringer switch on silent.
@MainActor
final class SoundPreviewer {
    static let shared = SoundPreviewer()
    private var player: AVAudioPlayer?

    func play(_ sound: AlarmSound) {
        stop()
        guard let url = sound.previewURL else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.7
        player?.play()
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
