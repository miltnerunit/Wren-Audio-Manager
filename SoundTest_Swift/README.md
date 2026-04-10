# AudioManager

A lightweight, event-driven audio manager for iOS games built on AVFoundation's `AVAudioEngine` and `AVAudioPlayerNode`. Designed for mobile word puzzle games where the priority is snappy, precise, non-intrusive sound — polyphonic one-shots, sequential variations, and animation-driven sequencing.



https://github.com/user-attachments/assets/29381ca8-2bb8-4087-959f-cdae7534ec55



Built and maintained by [Kristin Miltner](https://kristinmiltner.com).

---

## Features

- **Per-event voice pools** — each sound event has its own configurable voice limit; when the pool is full, the oldest voice is stolen
- **Sequential variations** — cycles through numbered file variants in order, wrapping automatically (e.g. `submit1SolidifyTile_1` → `_2` → … → `_7` → `_1`)
- **Random no-repeat variations** — picks randomly from numbered variants, never repeating the last played
- **Looping sounds** — start and stop driven by animation callbacks, not timers
- **Buffer caching** — every audio file is read from disk exactly once and held in memory
- **Route change handling** — automatically restarts the engine after headphone/speaker switches

---

## Installation

1. Copy `AudioManager.swift` into your Xcode project
2. Add your audio files to the Xcode bundle (drag into the project navigator, check "Copy items if needed")
3. Files should be named to match the `SoundEvent` raw values — e.g. `tilePickUp.wav`, `tileDropBoard_1.wav` through `tileDropBoard_7.wav`
4. `AudioManager.shared` is available immediately — no setup call needed

---

## Basic Usage

Engineers call `play()` for everything. The manager handles voice allocation, variation selection, and looping internally.

```swift
// One-shot
AudioManager.shared.play(.tilePickUp)
AudioManager.shared.play(.submitSuccess)
AudioManager.shared.play(.pageForward)

// Variations — no index needed
AudioManager.shared.play(.tileDropBoard)         // random, never repeats last played
AudioManager.shared.play(.submit1SolidifyTile)   // sequential: _1, _2 … _7, _1

// Looping — driven by animation callbacks
AudioManager.shared.play(.submit4PointsTickUp)   // call when animation starts
AudioManager.shared.stop(.submit4PointsTickUp)   // call when animation ends

// Override voice limit if needed
AudioManager.shared.play(.tileDropBoard, maxVoices: 4)

// Stop everything (e.g. app backgrounding)
AudioManager.shared.stopAll()
```

---

## Adding a New Sound Event

1. **Add the case** to the `SoundEvent` enum in `AudioManager.swift`:

```swift
case myNewSound = "myNewSound"
```

The raw value must match the audio filename (without extension).

2. **Set the voice limit** in the `maxVoices` property:

```swift
var maxVoices: Int {
    switch self {
    case .myNewSound: return 2   // add your case
    ...
    }
}
```

If not specified, the default is 3 voices.

3. **Set looping** if needed:

```swift
var loops: Bool {
    switch self {
    case .myNewSound: return true   // add only if this sound loops
    ...
    }
}
```

4. **Add audio file(s)** to the Xcode bundle:
   - Single file: `myNewSound.wav`
   - Variations: `myNewSound_1.wav`, `myNewSound_2.wav`, etc.

5. **Call it** from the appropriate animation or UI event:

```swift
AudioManager.shared.play(.myNewSound)
```

---

## Configuring Voice Pools and Variations

All audio design decisions live in the `SoundEvent` enum — not at the call site. This means engineers never have to think about how many voices a sound needs or how its variations behave.

### Voice Limit

Set `maxVoices` per event:

```swift
var maxVoices: Int {
    switch self {
    case .pointToast1_Nice:     return 1   // stingers never overlap
    case .submit1SolidifyTile:  return 8   // rapid-fire stacking
    default:                    return 3   // sensible default
    }
}
```

When all voices are busy, the oldest playing instance is stolen.

### Variations

Set `variationCount` and `variationMode` per event:

```swift
var variationCount: Int {
    switch self {
    case .tileDropBoard:        return 7   // 7 files: tileDropBoard_1.wav … _7.wav
    case .submit1SolidifyTile:  return 7
    default:                    return 1   // single file, no suffix
    }
}

var variationMode: VariationMode {
    switch self {
    case .submit1SolidifyTile:  return .sequential   // _1 → _2 → … → _7 → _1
    case .tileDropBoard:        return .random        // random, no immediate repeat
    default:                    return .random
    }
}
```

---

## Debug App

The repo includes a companion iOS debug app (`AudioManagerDebug`) for auditioning sounds and verifying manager behavior during development and QA.

### Features

- One button per sound event
- Variation display — shows which variant just played (e.g. `tileDropBoard → _4`)
- Voice count indicator — shows active voices per event to verify pool limits
- Stop buttons for all looping sounds
- Stop All button

### Usage

Open `AudioManagerDebug.xcodeproj`, add your audio files to the bundle, build and run on device. Tap any button to trigger its sound event and observe the display.

The debug app is intended as a shared tool between sound designer and engineering — a fast way to audition sounds in context, verify variation behavior, and QA audio events without needing a full game build.

---

## File Naming Convention

| Event type | Filename format |
|---|---|
| Single sound | `eventName.wav` |
| Variations | `eventName_1.wav`, `eventName_2.wav`, … |
| Case-sensitive | Must match `SoundEvent` raw value exactly |

All files should be 44.1kHz / 16-bit WAV unless otherwise specified.

---

## Requirements

- iOS 14+
- Swift 5.7+
- AVFoundation (system framework, no additional dependencies)
