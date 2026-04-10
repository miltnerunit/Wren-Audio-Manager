import AVFoundation

// MARK: - Variation Mode

/// Controls how a sound event cycles through its delivered variations.
enum VariationMode {
    /// Plays variations in order, wrapping back to 1 after the last.
    case sequential
    /// Plays a random variation, never repeating the same one twice in a row.
    case random
}


// MARK: - Sound Events

enum SoundEvent: String, CaseIterable {

    // MARK: Tile Interactions
    case tilePickUp         = "tilePickUp"
    case tileDrop           = "tileDrop"            // 8 variations, random no-repeat
    case tilePlace          = "tilePlace"           // 4 variations, sequential

    // MARK: UI
    case uiTap              = "uiTap"
    case uiModalOpen        = "uiModalOpen"
    case uiModalClose       = "uiModalClose"

    // MARK: Game
    case gameSuccess        = "gameSuccess"
    case gameError          = "gameError"

    // MARK: Rewards (voice limit: 1)
    case reward1            = "reward1"
    case reward2            = "reward2"
    case reward3            = "reward3"
    case reward4            = "reward4"

    // MARK: Looping
    case loopAmbient        = "loopAmbient"         // looping — stop() to end


    // MARK: - Voice Pool Configuration

    /// Maximum simultaneous voices for this event.
    /// When the limit is reached, the oldest playing voice is stolen.
    var maxVoices: Int {
        switch self {

        // Rewards: never overlap
        case .reward1,
             .reward2,
             .reward3,
             .reward4:
            return 1

        // Looping sounds: one instance at a time
        case .loopAmbient:
            return 1

        // Rapid-fire tile interactions: allow stacking
        case .tileDrop,
             .tilePlace:
            return 8

        case .tilePickUp:
            return 4

        // Everything else: sensible default
        default:
            return 3
        }
    }

    /// Whether this event loops until explicitly stopped.
    var loops: Bool {
        switch self {
        case .loopAmbient:
            return true
        default:
            return false
        }
    }

    /// Number of delivered variation files for this event.
    /// Variations are named [rawValue]_1.wav, [rawValue]_2.wav, etc.
    /// Events with variationCount == 1 use [rawValue].wav directly.
    var variationCount: Int {
        switch self {
        case .tileDrop:     return 8
        case .tilePlace:    return 8
        default:            return 1
        }
    }

    /// How variations are selected on each play call.
    var variationMode: VariationMode {
        switch self {
        case .tilePlace:    return .sequential  // cycles 1 → 2 → 3 → 4 → 1
        case .tileDrop:     return .random      // random, never repeats last played
        default:            return .random
        }
    }

    /// File extension
    var fileExtension: String { "wav" }
}


// MARK: - Voice

/// A single playback voice: one AVAudioPlayerNode + scheduling state.
private final class Voice {
    let node: AVAudioPlayerNode
    var isPlaying: Bool = false
    var startedAt: Date = .distantPast
    var soundEvent: SoundEvent?
    var connectedFormat: AVAudioFormat?

    init(node: AVAudioPlayerNode) {
        self.node = node
    }
}


// MARK: - AudioManager

final class AudioManager {

    // MARK: Singleton
    static let shared = AudioManager()
    private init() {
        setupEngine()
    }

    // MARK: Private State
    private let engine = AVAudioEngine()

    /// Per-event voice pools: [SoundEvent.rawValue: [Voice]]
    private var voicePools: [String: [Voice]] = [:]

/// Cached AVAudioPCMBuffers — each file is read from disk exactly once.
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]

    /// Active looping voices, keyed by event rawValue.
    private var loopingVoices: [String: Voice] = [:]

    /// Sequential variation counters, keyed by event rawValue.
    /// Increments on each play call for .sequential events, wraps at variationCount.
    private var sequentialCounters: [String: Int] = [:]

    /// Timestamp of the last play call for sequential events.
    /// Used to auto-reset the counter when a new sequence begins after a gap.
    private var lastSequentialPlayTime: [String: Date] = [:]

    /// Inactivity threshold before a sequential counter resets (seconds).
    private let sequentialResetInterval: TimeInterval = 1.5

    /// Remaining shuffle pool for .random events. Exhausted then reshuffled.
    private var randomShufflePool: [String: [Int]] = [:]

    /// Last played variation index for .random events (no-repeat across reshuffle boundary).
    private var lastRandomVariation: [String: Int] = [:]

    /// Last resolved filename per event, for display/debugging.
    private(set) var lastPlayedFilename: [String: String] = [:]


    // MARK: - Engine Setup

    private func setupEngine() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.preloadAllBuffers()
            DispatchQueue.main.async { self?.warmUpEngine() }
        }
    }

    private func preloadAllBuffers() {
        for event in SoundEvent.allCases {
            if event.variationCount > 1 {
                for i in 1...event.variationCount {
                    _ = loadBuffer(filename: "\(event.rawValue)_\(i)", ext: event.fileExtension)
                }
            } else {
                _ = loadBuffer(filename: event.rawValue, ext: event.fileExtension)
            }
        }
    }

    private func warmUpEngine() {
        for event in SoundEvent.allCases {
            let filename = event.variationCount > 1 ? "\(event.rawValue)_1" : event.rawValue
            let cacheKey = "\(filename).\(event.fileExtension)"
            guard let format = bufferCache[cacheKey]?.format else { continue }
            let voices = (0..<event.maxVoices).map { _ in makeVoice(format: format) }
            voicePools[event.rawValue] = voices
        }
        try? engine.start()
        // Warm all nodes after engine is running
        for pool in voicePools.values {
            for voice in pool { voice.node.play() }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard !engine.isRunning else { return }
        try? engine.start()
    }


    // MARK: - Public API

    /// Play a sound event.
    /// Variation selection (sequential or random-no-repeat) is handled automatically.
    /// - Parameters:
    ///   - event: The sound to play.
    ///   - maxVoices: Override the event's default voice limit if needed.
    func play(_ event: SoundEvent, maxVoices: Int? = nil) {
        let limit = maxVoices ?? event.maxVoices
        let filename = resolveFilename(for: event)

        guard let buffer = loadBuffer(filename: filename, ext: event.fileExtension) else {
            print("[AudioManager] Could not load buffer for \(filename)")
            return
        }

        let voice = acquireVoice(for: event, limit: limit)
        schedule(buffer: buffer, on: voice, event: event, loops: event.loops)
    }

    /// Stop a looping sound event.
    /// Call this from the animation completion handler that ends the loop.
    func stop(_ event: SoundEvent) {
        guard event.loops,
              let voice = loopingVoices[event.rawValue] else { return }
        voice.node.stop()
        if engine.isRunning { voice.node.play() }
        voice.isPlaying = false
        loopingVoices.removeValue(forKey: event.rawValue)
    }

    /// Reset the shuffle pool for a random event back to a fresh unplayed state.
    /// For testing only — verifies no-repeat behavior across the reshuffle boundary.
    func resetShufflePool(_ event: SoundEvent) {
        randomShufflePool[event.rawValue] = nil
        lastRandomVariation[event.rawValue] = nil
    }

    /// Number of voices currently playing for a given event.
    func activeVoiceCount(for event: SoundEvent) -> Int {
        voicePools[event.rawValue]?.filter { $0.isPlaying }.count ?? 0
    }

    /// Stop all sounds immediately.
    /// Call on app backgrounding or any hard reset.
    func stopAll() {
        for pool in voicePools.values {
            for voice in pool {
                voice.node.stop()
                if engine.isRunning { voice.node.play() }
                voice.isPlaying = false
            }
        }
        loopingVoices.removeAll()
    }


    // MARK: - Private: Variation Resolution

    private func resolveFilename(for event: SoundEvent) -> String {
        guard event.variationCount > 1 else { return event.rawValue }

        let filename: String
        switch event.variationMode {
        case .sequential:
            filename = nextSequentialVariation(for: event)
        case .random:
            filename = nextRandomVariation(for: event)
        }
        lastPlayedFilename[event.rawValue] = filename
        return filename
    }

    private func nextSequentialVariation(for event: SoundEvent) -> String {
        let key = event.rawValue
        let now = Date()
        if let last = lastSequentialPlayTime[key],
           now.timeIntervalSince(last) > sequentialResetInterval {
            sequentialCounters[key] = 0
        }
        lastSequentialPlayTime[key] = now
        let current = sequentialCounters[key] ?? 0
        let next = (current % event.variationCount) + 1  // 1 → 2 → … → N → 1
        sequentialCounters[key] = next
        return "\(event.rawValue)_\(next)"
    }

    private func nextRandomVariation(for event: SoundEvent) -> String {
        let key = event.rawValue

        if randomShufflePool[key] == nil || randomShufflePool[key]!.isEmpty {
            var fresh = Array(1...event.variationCount).shuffled()
            // If the first pick after reshuffle matches the last played, swap it with another
            if let last = lastRandomVariation[key], fresh.first == last, fresh.count > 1 {
                let swapIndex = Int.random(in: 1..<fresh.count)
                fresh.swapAt(0, swapIndex)
            }
            randomShufflePool[key] = fresh
        }

        let chosen = randomShufflePool[key]!.removeFirst()
        lastRandomVariation[key] = chosen
        return "\(event.rawValue)_\(chosen)"
    }


    // MARK: - Private: Voice Pool Management

    private func acquireVoice(for event: SoundEvent, limit: Int) -> Voice {
        let key = event.rawValue

        if voicePools[key] == nil {
            voicePools[key] = (0..<limit).map { _ in makeVoice() }
        }

        var pool = voicePools[key]!

        while pool.count < limit {
            pool.append(makeVoice())
        }

        if let free = pool.first(where: { !$0.isPlaying }) {
            voicePools[key] = pool
            return free
        }

        // All voices busy — steal the oldest
        let oldest = pool.min(by: { $0.startedAt < $1.startedAt })!
        oldest.node.stop()
        if engine.isRunning { oldest.node.play() }
        oldest.isPlaying = false
        voicePools[key] = pool
        return oldest
    }

    private func makeVoice(format: AVAudioFormat? = nil) -> Voice {
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        let voice = Voice(node: node)
        voice.connectedFormat = format
        return voice
    }


    // MARK: - Private: Scheduling

    private func schedule(
        buffer: AVAudioPCMBuffer,
        on voice: Voice,
        event: SoundEvent,
        loops: Bool
    ) {
        voice.isPlaying = true
        voice.startedAt = Date()
        voice.soundEvent = event

        let options: AVAudioPlayerNodeBufferOptions = loops ? .loops : []

        if !engine.isRunning {
            try? engine.start()
        }

        // Only reconnect if the format has changed (mono vs stereo switch)
        if voice.connectedFormat?.channelCount != buffer.format.channelCount {
            engine.disconnectNodeOutput(voice.node)
            engine.connect(voice.node, to: engine.mainMixerNode, format: buffer.format)
            voice.connectedFormat = buffer.format
        }

        voice.node.scheduleBuffer(buffer, at: nil, options: options) { [weak voice] in
            voice?.isPlaying = false
        }

        if !voice.node.isPlaying {
            voice.node.play()
        }

        if loops {
            loopingVoices[event.rawValue] = voice
        }
    }


    // MARK: - Private: Buffer Loading

    private func loadBuffer(filename: String, ext: String) -> AVAudioPCMBuffer? {
        let cacheKey = "\(filename).\(ext)"

        if let cached = bufferCache[cacheKey] { return cached }

        guard let url = Bundle.main.url(forResource: filename, withExtension: ext) else {
            print("[AudioManager] File not found in bundle: \(cacheKey)")
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else { return nil }
            try file.read(into: buffer)
            bufferCache[cacheKey] = buffer
            return buffer
        } catch {
            print("[AudioManager] Failed to load \(cacheKey): \(error)")
            return nil
        }
    }
}


// MARK: - Usage Examples
//
// All sounds are triggered by their corresponding animation or game events.
// Engineers call play() — the manager handles everything else.
//
// One-shot:
//   AudioManager.shared.play(.tilePickUp)
//   AudioManager.shared.play(.gameSuccess)
//   AudioManager.shared.play(.uiPageForward)
//
// Variations — no index needed, handled automatically:
//   AudioManager.shared.play(.tileDrop)      // random, never repeats last
//   AudioManager.shared.play(.tilePlace)     // sequential: _1, _2, _3, _4, _1
//
// Looping — start and stop driven by animation or state:
//   AudioManager.shared.play(.loopAmbient)      // call when ambient scene begins
//   AudioManager.shared.stop(.loopAmbient)      // call when ambient scene ends
//
//   AudioManager.shared.play(.loopProcessing)   // call when processing starts
//   AudioManager.shared.stop(.loopProcessing)   // call when processing completes
//
// Rewards (auto voice-limited to 1):
//   AudioManager.shared.play(.reward3)
//
// Override voice limit if needed:
//   AudioManager.shared.play(.tileDrop, maxVoices: 4)
//
// Stop everything (e.g. app backgrounding):
//   AudioManager.shared.stopAll()
