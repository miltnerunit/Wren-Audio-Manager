[README.md](https://github.com/user-attachments/files/26424959/README.md)
# AudioManager

A lightweight, event-driven audio manager for cross-platform iOS/Android games and apps. Built on AVFoundation's `AVAudioEngine` and `AVAudioPlayerNode` for iOS, and `SoundPool` for Android. Designed for mobile experiences where the priority is snappy, precise, non-intrusive sound — polyphonic one-shots, sequential variations, and animation-driven sequencing.


https://github.com/user-attachments/assets/3a5d2bef-55ec-4c8d-a6ef-6e0ffeb36438


Built and maintained by [Kristin Miltner](https://kristinmiltner.com).

---

## Features

- **Per-event voice pools** — each sound event has its own configurable voice limit; when the pool is full, the oldest voice is stolen
- **Sequential variations** — cycles through numbered file variants in order, wrapping automatically (e.g. `tilePlace_1` → `_2` → … → `_8` → `_1`)
- **Random no-repeat variations** — picks randomly from numbered variants, never repeating the last played
- **Looping sounds** — start and stop driven by animation callbacks, not timers
- **Buffer caching** — every audio file is read from disk exactly once and held in memory
- **Route change handling** — automatically restarts the engine after headphone/speaker switches

---

## Installation

### iOS (Swift / AVFoundation)

1. Copy `AudioManager.swift` into your Xcode project
2. Add your audio files to the Xcode bundle (drag into the project navigator, check "Copy items if needed")
3. Files should be named to match the `SoundEvent` raw values — e.g. `tilePickUp.wav`, `tileDrop_1.wav` through `tileDrop_8.wav`
4. `AudioManager.shared` is available immediately — no setup call needed

### Android (Kotlin / SoundPool)

1. Copy `AudioManager.kt` into your Android project (e.g. `app/src/main/java/com/yourpackage/audio/`)
2. Add your audio files to `assets/sounds/` — filenames must match the `SoundEvent` raw values exactly, e.g. `tilePickUp.wav`, `tileDrop_1.wav` through `tileDrop_8.wav`
3. Initialize the manager once in your `Application` class or main `Activity`:
```kotlin
AudioManager.init(context)
```

4. Call `play()` from anywhere:
```kotlin
AudioManager.play(SoundEvent.TILE_PICK_UP)
```

---

## Basic Usage

Engineers call `play()` for everything. The manager handles voice allocation, variation selection, and looping internally.

### iOS (Swift)
```swift
// One-shot
AudioManager.shared.play(.tilePickUp)
AudioManager.shared.play(.gameSuccess)
AudioManager.shared.play(.uiTap)

// Variations — no index needed
AudioManager.shared.play(.tileDrop)    // random, never repeats last played
AudioManager.shared.play(.tilePlace)   // sequential: _1, _2 … _8, _1

// Looping — driven by animation callbacks
AudioManager.shared.play(.loopAmbient)   // call when ambient scene begins
AudioManager.shared.stop(.loopAmbient)   // call when ambient scene ends

// Override voice limit if needed
AudioManager.shared.play(.tileDrop, maxVoices: 4)

// Stop everything (e.g. app backgrounding)
AudioManager.shared.stopAll()
```

### Android (Kotlin)
```kotlin
// One-shot
AudioManager.shared.play(SoundEvent.TILE_PICK_UP)
AudioManager.shared.play(SoundEvent.GAME_SUCCESS)
AudioManager.shared.play(SoundEvent.UI_TAP)

// Variations — no index needed
AudioManager.shared.play(SoundEvent.TILE_DROP)    // random, never repeats last played
AudioManager.shared.play(SoundEvent.TILE_PLACE)   // sequential: _1, _2 … _8, _1

// Looping — driven by animation callbacks
AudioManager.shared.play(SoundEvent.LOOP_AMBIENT)   // call when ambient scene begins
AudioManager.shared.stop(SoundEvent.LOOP_AMBIENT)   // call when ambient scene ends

// Override voice limit if needed
AudioManager.shared.play(SoundEvent.TILE_DROP, maxVoices = 4)

// Stop everything (e.g. app backgrounding)
AudioManager.stopAll()
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
    case .reward1:    return 1   // stingers never overlap
    case .tileDrop:   return 8   // rapid-fire stacking
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
    case .tileDrop:    return 8   // 8 files: tileDrop_1.wav … _8.wav
    case .tilePlace:   return 8
    default:                    return 1   // single file, no suffix
    }
}

var variationMode: VariationMode {
    switch self {
    case .tilePlace:   return .sequential   // _1 → _2 → … → _8 → _1
    case .tileDrop:    return .random       // random, no immediate repeat
    default:                    return .random
    }
}
```

---

## Debug App

The repo includes companion test apps for iOS (`SoundTest_Swift`) and Android (`SoundTest_Android`) for auditioning sounds and verifying manager behavior during development and QA.

https://github.com/user-attachments/assets/0e50b4e6-931d-46e5-aec5-5ee180b036db

### Features

- One button per sound event
- Variation display — shows which variant just played (e.g. `tileDrop → _4`)
- Voice count indicator — shows active voices per event to verify pool limits
- Loop toggle buttons for looping sounds
- Stop All button

### Usage

Open `SoundTest_Swift` in Xcode or `SoundTest_Android` in Android Studio, add your audio files to the bundle, build and run on device. Tap any button to trigger its sound event and observe the display.

The test apps are intended as a shared tool between sound designer and engineering — a fast way to audition sounds in context, verify variation behavior, and QA audio events without needing a full game build.

---

## Sound Event List

The full list of sound events, including variation counts and file naming, is in [SoundEvents.csv](SoundEvents.csv).

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

### iOS
- iOS 14+
- Swift 5.7+
- AVFoundation (system framework, no additional dependencies)

### Android
- Android API 21+ (Lollipop)
- Kotlin 1.7+
- SoundPool (system framework, no additional dependencies)
