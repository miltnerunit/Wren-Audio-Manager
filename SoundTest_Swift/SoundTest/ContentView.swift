import SwiftUI
import Combine

struct ContentView: View {

    // Tracks which looping sounds are currently active
    @State private var looping: Set<SoundEvent> = []
    @State private var voiceCounts: [SoundEvent: Int] = [:]
    @State private var lastFilenames: [SoundEvent: String] = [:]

    @ViewBuilder
    func soundBtn(_ label: String, event: SoundEvent) -> some View {
        SoundButton(label, event: event, voiceCount: voiceCounts[event] ?? 0, lastFilename: lastFilenames[event])
    }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Tile Interactions
                Section("Tile Interactions") {
                    soundBtn("Tile Pick Up", event: .tilePickUp)
                    // 4 random-no-repeat variations — tap repeatedly to hear cycling
                    soundBtn("Tile Drop (×8 random)", event: .tileDrop)
                    Button("↺ Reset Tile Drop pool") {
                        AudioManager.shared.resetShufflePool(.tileDrop)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // 4 sequential variations — each tap advances the counter
                    soundBtn("Tile Place (×8 seq)", event: .tilePlace)
                }

                // MARK: UI
                Section("UI") {
                    soundBtn("Tap",          event: .uiTap)
                    soundBtn("Modal Open",   event: .uiModalOpen)
                    soundBtn("Modal Close",  event: .uiModalClose)
                }

                // MARK: Game
                Section("Game") {
                    soundBtn("Success", event: .gameSuccess)
                    soundBtn("Error",   event: .gameError)
                }

                // MARK: Rewards (voice-limited to 1)
                Section("Rewards (voice limit = 1)") {
                    soundBtn("Reward 1", event: .reward1)
                    soundBtn("Reward 2", event: .reward2)
                    soundBtn("Reward 3", event: .reward3)
                    soundBtn("Reward 4", event: .reward4)
                }

                // MARK: Looping
                Section("Looping") {
                    LoopButton("Ambient (loop)", event: .loopAmbient, looping: $looping)
                }

                // MARK: Stop All
                Section {
                    Button(role: .destructive) {
                        AudioManager.shared.stopAll()
                        looping.removeAll()
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("AudioManager Test")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                for event in SoundEvent.allCases where event.maxVoices > 1 {
                    voiceCounts[event] = AudioManager.shared.activeVoiceCount(for: event)
                }
                for event in SoundEvent.allCases where event.variationCount > 1 {
                    if let name = AudioManager.shared.lastPlayedFilename[event.rawValue] {
                        lastFilenames[event] = name
                    }
                }
            }
        }
    }
}


// MARK: - One-shot button

private struct SoundButton: View {
    let label: String
    let event: SoundEvent
    var voiceCount: Int = 0
    var lastFilename: String? = nil

    init(_ label: String, event: SoundEvent, voiceCount: Int = 0, lastFilename: String? = nil) {
        self.label = label
        self.event = event
        self.voiceCount = voiceCount
        self.lastFilename = lastFilename
    }

    var body: some View {
        Button {
            AudioManager.shared.play(event)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label)
                    Spacer()
                    if event.maxVoices > 1 {
                        Text("\(voiceCount)/\(event.maxVoices)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(voiceCount == event.maxVoices ? .red : .secondary)
                    }
                }
                if let name = lastFilename {
                    Text(name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}


// MARK: - Loop toggle button

private struct LoopButton: View {
    let label: String
    let event: SoundEvent
    @Binding var looping: Set<SoundEvent>

    init(_ label: String, event: SoundEvent, looping: Binding<Set<SoundEvent>>) {
        self.label = label
        self.event = event
        self._looping = looping
    }

    private var isActive: Bool { looping.contains(event) }

    var body: some View {
        Button {
            if isActive {
                AudioManager.shared.stop(event)
                looping.remove(event)
            } else {
                AudioManager.shared.play(event)
                looping.insert(event)
            }
        } label: {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: isActive ? "stop.circle.fill" : "play.circle")
                    .foregroundStyle(isActive ? .red : .accentColor)
            }
        }
    }
}


#Preview {
    ContentView()
}
