import SwiftUI
import Combine

struct ContentView: View {

    @State private var looping: Set<SoundEvent> = []
    @State private var voiceCounts: [SoundEvent: Int] = [:]
    @State private var lastFilenames: [SoundEvent: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(SoundEvent.categories, id: \.self) { category in
                    Section(category) {
                        ForEach(SoundEvent.allCases.filter { $0.category == category }) { event in
                            if event.loops {
                                LoopButton(event.displayName, event: event, looping: $looping)
                            } else {
                                SoundButton(event.displayName, event: event,
                                            voiceCount: voiceCounts[event] ?? 0,
                                            lastFilename: lastFilenames[event])
                            }
                        }
                    }
                }

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
