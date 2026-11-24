import AudioToolbox
import SwiftUI

/// Settings -> Chat -> Message sound. Tapping a sound selects it and plays it once; the choice
/// applies to the next chat push straight away (`NotificationService` reads `ChatSound.current`).
struct ChatSoundPickerView: View {
    @State private var selected = ChatSound.current
    @State private var player = SoundPreviewPlayer()

    var body: some View {
        List {
            Section {
                ForEach(ChatSound.allCases) { sound in
                    Button {
                        selected = sound
                        ChatSound.current = sound
                        player.play(sound)
                    } label: {
                        HStack {
                            Text(sound.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if sound == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    // Plain row text like a system picker, not link-coloured.
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sound == selected ? .isSelected : [])
                }
            } footer: {
                Text("Tap a sound to hear it. It plays for new chat messages; other notifications keep the phone's sound.")
            }
        }
        .navigationTitle("Message sound")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }
}

/// Plays a bundled chat sound once, the way a notification would (respects the silent switch).
@MainActor
final class SoundPreviewPlayer {
    private var soundID: SystemSoundID = 0

    func play(_ sound: ChatSound) {
        stop()
        guard
            let name = sound.fileName,
            let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "caf")
        else { return }
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        AudioServicesPlaySystemSound(soundID)
    }

    func stop() {
        guard soundID != 0 else { return }
        AudioServicesDisposeSystemSoundID(soundID)
        soundID = 0
    }
}
