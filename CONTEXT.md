# Wren — Design Context & Developer Notes

This document captures the design philosophy, key decisions, and reasoning behind Wren for anyone (including future Claude Code sessions) picking up the project.

---

## What Wren Is

Wren is a lightweight, event-driven audio manager for mobile games — Swift/AVFoundation for iOS, Kotlin/SoundPool for Android. It is designed for mobile experiences where the priority is snappy, precise, non-intrusive sound: polyphonic one-shots, sequential variations, and animation-driven sequencing.

It grew out of a real project (a mobile word puzzle game) where the existing audio implementation had polyphony, variation, and latency issues, and no dedicated audio engineer to fix them. Wren is the solution that was built instead.

---

## Core Design Philosophy

### 1. Audio is triggered by events, not timers

Every sound in Wren is triggered by its corresponding animation or UI event — not by a scheduled delay or a fixed sequence function. This keeps audio locked to visual timing regardless of word length, device performance, or future animation changes.

Timers drift. Events don't.

This means there is no `playSequence()` function in Wren. Each sound in a sequence gets its own `play()` call, attached to its own visual event. The manager handles everything else.

### 2. Design decisions live in the enum, not at the call site

All audio design decisions — voice limits, variation behavior, looping — are encoded in the `SoundEvent` enum. Engineers call `play()` everywhere. They never have to know how many voices a sound needs, whether it loops, or which variation to pick.

This is intentional. It keeps the audio design under the sound designer's control without requiring them to touch the parts of the codebase that engineers need to protect.

### 3. The designer's interface is contained

The `SoundEvent` enum is the sound designer's sandbox. Voice limits, variation counts, variation modes (sequential or random), and looping behavior are all configured there. Everything else is the engine's business.

There's not a lot to break, and nothing that touches the parts of the codebase that actually need protecting. This is the middle path between "engineers hold all the keys" and "artists break the codebase."

### 4. Per-event voice pools, not a global pool

Each `SoundEvent` has its own configurable voice pool. When the pool is full, the oldest voice is stolen. This gives precise control over polyphony per sound type — stingers that should never stack get `maxVoices: 1`, rapid-fire tile sounds get `maxVoices: 8`.

Voice limiting is the sound designer's decision, not the engineer's.

### 5. Random variation without repeats, sequential variation that wraps

Two variation modes:
- `.random` — exhaustive shuffle pool, never repeats the last played even across reshuffle boundary
- `.sequential` — cycles 1 → 2 → … → N → 1, with auto-reset after a configurable inactivity gap

Both are handled automatically by the manager. No index tracking at the call site.

---

## Key Technical Decisions

### iOS: AVFoundation / AVAudioPlayerNode
- `AVAudioEngine` with per-event `AVAudioPlayerNode` pools
- Buffer caching — each file read from disk exactly once
- Engine warm-up at launch — all buffers preloaded, all nodes pre-connected and warmed
- `AVAudioSession` configured for `.playback` with low-latency IO buffer
- Route change handling — engine restarts and session reactivates on headphone/speaker switches (EarPods, Bluetooth, etc.)

### Android: Kotlin / SoundPool
- `SoundPool` with `FLAG_LOW_LATENCY` and `USAGE_GAME` audio attributes
- Background preloading thread at init
- Assets loaded from `assets/sounds/` directory
- Singleton pattern with `AudioManager.init(context)` required once in Application class

### Why not FMOD or Wwise?
Wren is designed for mobile projects where middleware has too much overhead, or where the team wants a fully native, dependency-free solution. It is not a replacement for FMOD or Wwise on larger projects — it is the right tool for projects where those tools are overkill.

---

## Roadmap / Open Issues

### Planned features
- **Data-driven SoundEvent loading** — read event definitions from CSV or JSON rather than requiring the sound designer to maintain the Swift/Kotlin enum manually. `SoundEvents.csv` is already in the repo; the next step is having the engine parse it at build time or runtime. Goal: update the spreadsheet and rebuild — no code changes needed.
- **Crossfades for looping sounds** — smooth transition when a loop restarts or when switching between loop states.
- **Settable fade in / fade out on one-shots** — attack and release envelopes per event or per `play()` call.

### Design decisions still open
- **Round-robin vs. oldest-voice-steal** for voice pool exhaustion — currently uses oldest-voice-steal. Round-robin is an alternative worth exploring.
- **Per-play() volume and pitch parameters** — not currently supported; all variation is handled by the event definition.

---

## What Wren Is Not

- Not a replacement for FMOD or Wwise on complex projects
- Not a music sequencer or adaptive music system (though looping + crossfades will get closer)
- Not a general-purpose audio engine — it is specifically designed for mobile game interaction audio

---

## Companion Test App

The repo includes iOS (`SoundTest_Swift`) and Android (`SoundTest_Android`) test apps for auditioning sounds and verifying manager behavior. Features:
- One button per sound event
- Variation display (shows which variant just played)
- Voice count indicator (shows active voices vs. pool limit)
- Loop toggle buttons
- Stop All button

The test app is designed as a shared tool between sound designer and engineering — a fast way to audition sounds, verify behavior, and QA without needing a full game build.

---

## Repository Structure

```
Wren-Audio-Manager/
├── SoundTest_Swift/          iOS Xcode project + test app
│   ├── SoundTest/
│   │   ├── AudioManager.swift    ← the manager
│   │   ├── ContentView.swift     ← test app UI
│   │   └── Sounds/               ← demo audio assets
├── SoundTest_Android/        Android Studio project + test app
│   └── app/src/main/
│       ├── java/com/soundtest/app/
│       │   ├── AudioManager.kt       ← the manager
│       │   └── SoundTestScreen.kt    ← test app UI
│       └── assets/sounds/            ← demo audio assets
├── SoundEvents.csv           sound event definitions (future: source of truth for data-driven loading)
└── README.md
```

---

## Built and maintained by Kristin Miltner
kristinmiltner.com · kristin@kristinmiltner.net
