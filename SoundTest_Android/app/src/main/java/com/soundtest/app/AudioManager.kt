package com.soundtest.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager as SystemAudioManager
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.util.Log


// MARK: - Variation Mode

enum class VariationMode {
    SEQUENTIAL,
    RANDOM
}


// MARK: - Sound Events

enum class SoundEvent(val rawValue: String) {

    // Tile Interactions
    TILE_PICK_UP("tilePickUp"),
    TILE_DROP("tileDrop"),              // 4 variations, random no-repeat
    TILE_PLACE("tilePlace"),            // 4 variations, sequential

    // UI
    UI_TAP("uiTap"),
    UI_MODAL_OPEN("uiModalOpen"),
    UI_MODAL_CLOSE("uiModalClose"),

    // Game
    GAME_SUCCESS("gameSuccess"),
    GAME_ERROR("gameError"),

    // Rewards (voice limit: 1)
    REWARD_1("reward1"),
    REWARD_2("reward2"),
    REWARD_3("reward3"),
    REWARD_4("reward4"),

    // Looping
    LOOP_AMBIENT("loopAmbient");        // looping — stop() to end


    // MARK: - Voice Pool Configuration

    val maxVoices: Int get() = when (this) {
        REWARD_1,
        REWARD_2,
        REWARD_3,
        REWARD_4 -> 1

        LOOP_AMBIENT -> 1

        TILE_DROP,
        TILE_PLACE -> 8

        TILE_PICK_UP -> 4

        else -> 3
    }

    val loops: Boolean get() = when (this) {
        LOOP_AMBIENT -> true
        else -> false
    }

    val variationCount: Int get() = when (this) {
        TILE_DROP  -> 8
        TILE_PLACE -> 8
        else       -> 1
    }

    val variationMode: VariationMode get() = when (this) {
        TILE_PLACE -> VariationMode.SEQUENTIAL
        else       -> VariationMode.RANDOM
    }

    val fileExtension: String get() = "wav"
}


// MARK: - AudioManager

class AudioManager private constructor(context: Context) {

    // MARK: Singleton
    //
    // Call AudioManager.init(context) once in Application.onCreate().
    // Access everywhere with AudioManager.shared.
    companion object {
        @Volatile private var instance: AudioManager? = null

        fun init(context: Context) {
            if (instance == null) {
                synchronized(this) {
                    if (instance == null) {
                        instance = AudioManager(context.applicationContext)
                    }
                }
            }
        }

        val shared: AudioManager
            get() = instance ?: error(
                "[AudioManager] Not initialized. Call AudioManager.init(context) in Application.onCreate()."
            )
    }

    // MARK: Private State

    private val appContext = context.applicationContext
    private val sysAudioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as SystemAudioManager
    private val soundPool: SoundPool
    private lateinit var noisyReceiver: BroadcastReceiver
    private lateinit var audioDeviceCallback: AudioDeviceCallback

    /// soundId cache — each file is loaded from assets exactly once.
    private val soundIds: MutableMap<String, Int> = mutableMapOf()

    /// Active stream tracking per event: list of (streamId, startTimeMs).
    /// Used for voice limit enforcement and stealing.
    private val activeStreams: MutableMap<String, MutableList<Pair<Int, Long>>> = mutableMapOf()

    /// Active looping stream per event.
    private val loopingStreams: MutableMap<String, Int> = mutableMapOf()

    /// Sequential variation counters, keyed by event rawValue.
    private val sequentialCounters: MutableMap<String, Int> = mutableMapOf()

    /// Timestamp (ms) of the last sequential play call, for auto-reset.
    private val lastSequentialPlayTime: MutableMap<String, Long> = mutableMapOf()

    /// Inactivity threshold before a sequential counter resets (ms).
    private val sequentialResetIntervalMs: Long = 1500

    /// Remaining shuffle pool for random events. Exhausted then reshuffled.
    private val randomShufflePool: MutableMap<String, MutableList<Int>> = mutableMapOf()

    /// Last played variation index per random event (no-repeat across reshuffle boundary).
    private val lastRandomVariation: MutableMap<String, Int> = mutableMapOf()

    /// Last resolved filename per event — read by the test UI.
    val lastPlayedFilename: MutableMap<String, String> = mutableMapOf()

    init {
        val nativeSampleRate = sysAudioManager.getProperty(SystemAudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
            ?.toIntOrNull() ?: 48000
        val framesPerBuffer = sysAudioManager.getProperty(SystemAudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
            ?.toIntOrNull() ?: 256
        Log.d("AudioManager", "Device native: ${nativeSampleRate}Hz, $framesPerBuffer frames/buffer")

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setFlags(AudioAttributes.FLAG_LOW_LATENCY)
            .build()

        soundPool = SoundPool.Builder()
            .setMaxStreams(32)
            .setAudioAttributes(attrs)
            .build()

        // Stop sounds when headphones are unplugged so audio doesn't blast from speaker.
        noisyReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == SystemAudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                    Log.d("AudioManager", "Headphones disconnected (AUDIO_BECOMING_NOISY) — stopping all sounds")
                    stopAll()
                }
            }
        }
        appContext.registerReceiver(noisyReceiver, IntentFilter(SystemAudioManager.ACTION_AUDIO_BECOMING_NOISY))

        // Log device add/remove events. SoundPool re-routes to new output automatically;
        // no restart is needed unlike AVAudioEngine on iOS.
        audioDeviceCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
                for (device in addedDevices) {
                    if (device.isSink) {
                        Log.d("AudioManager", "Audio output connected: ${device.productName} (type ${device.type})")
                    }
                }
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
                for (device in removedDevices) {
                    if (device.isSink) {
                        Log.d("AudioManager", "Audio output disconnected: ${device.productName} (type ${device.type})")
                    }
                }
            }
        }
        sysAudioManager.registerAudioDeviceCallback(audioDeviceCallback, Handler(Looper.getMainLooper()))

        preloadAllSounds()
    }

    private fun preloadAllSounds() {
        Thread {
            for (event in SoundEvent.entries) {
                if (event.variationCount > 1) {
                    for (i in 1..event.variationCount) {
                        loadSound("${event.rawValue}_$i", event.fileExtension)
                    }
                } else {
                    loadSound(event.rawValue, event.fileExtension)
                }
            }
        }.start()
    }


    // MARK: - Public API

    /**
     * Play a sound event.
     * Variation selection (sequential or exhaustive-random) is handled automatically.
     * @param event The sound to play.
     * @param maxVoices Override the event's default voice limit if needed.
     */
    fun play(event: SoundEvent, maxVoices: Int? = null) {
        val limit = maxVoices ?: event.maxVoices
        val filename = resolveFilename(event)
        val soundId = loadSound(filename, event.fileExtension) ?: return
        acquireStream(event, soundId, limit)
    }

    /**
     * Stop a looping sound event.
     * Call from the animation completion handler that ends the loop.
     */
    fun stop(event: SoundEvent) {
        if (!event.loops) return
        loopingStreams[event.rawValue]?.let { streamId ->
            soundPool.stop(streamId)
            loopingStreams.remove(event.rawValue)
            activeStreams[event.rawValue]?.removeAll { it.first == streamId }
        }
    }

    /**
     * Stop all sounds immediately.
     * Call on app backgrounding or any hard reset.
     */
    fun stopAll() {
        activeStreams.values.flatten().forEach { (streamId, _) ->
            soundPool.stop(streamId)
        }
        activeStreams.clear()
        loopingStreams.clear()
    }

    /** Number of voices currently tracked as playing for a given event. */
    fun activeVoiceCount(event: SoundEvent): Int =
        activeStreams[event.rawValue]?.size ?: 0

    /**
     * Reset the shuffle pool for a random event back to a fresh unplayed state.
     * For testing only — verifies no-repeat behavior across the reshuffle boundary.
     */
    fun resetShufflePool(event: SoundEvent) {
        randomShufflePool.remove(event.rawValue)
        lastRandomVariation.remove(event.rawValue)
    }

    /**
     * Preload all sound files into the SoundPool buffer cache.
     * Call once at app startup (after AudioManager.init) so every sound is ready
     * to play instantly on first tap.
     */
    fun preloadAll() {
        for (event in SoundEvent.entries) {
            if (event.variationCount == 1) {
                loadSound(event.rawValue, event.fileExtension)
            } else {
                for (i in 1..event.variationCount) {
                    loadSound("${event.rawValue}_$i", event.fileExtension)
                }
            }
        }
    }

    /**
     * Release SoundPool resources.
     * Call from your Application or Activity onDestroy if needed.
     */
    fun release() {
        stopAll()
        appContext.unregisterReceiver(noisyReceiver)
        sysAudioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
        soundPool.release()
    }


    // MARK: - Private: Variation Resolution

    private fun resolveFilename(event: SoundEvent): String {
        if (event.variationCount <= 1) return event.rawValue

        val filename = when (event.variationMode) {
            VariationMode.SEQUENTIAL -> nextSequentialVariation(event)
            VariationMode.RANDOM -> nextRandomVariation(event)
        }
        lastPlayedFilename[event.rawValue] = filename
        return filename
    }

    private fun nextSequentialVariation(event: SoundEvent): String {
        val key = event.rawValue
        val now = System.currentTimeMillis()
        val last = lastSequentialPlayTime[key]
        if (last != null && now - last > sequentialResetIntervalMs) {
            sequentialCounters[key] = 0
        }
        lastSequentialPlayTime[key] = now
        val current = sequentialCounters[key] ?: 0
        val next = (current % event.variationCount) + 1  // 1 → 2 → … → N → 1
        sequentialCounters[key] = next
        return "${event.rawValue}_$next"
    }

    private fun nextRandomVariation(event: SoundEvent): String {
        val key = event.rawValue
        if (randomShufflePool[key].isNullOrEmpty()) {
            val fresh = (1..event.variationCount).shuffled().toMutableList()
            // Ensure first pick after reshuffle doesn't match last played
            val last = lastRandomVariation[key]
            if (last != null && fresh.first() == last && fresh.size > 1) {
                val swapIndex = (1 until fresh.size).random()
                val tmp = fresh[0]; fresh[0] = fresh[swapIndex]; fresh[swapIndex] = tmp
            }
            randomShufflePool[key] = fresh
        }
        val chosen = randomShufflePool[key]!!.removeFirst()
        lastRandomVariation[key] = chosen
        return "${event.rawValue}_$chosen"
    }


    // MARK: - Private: Stream Management

    private fun acquireStream(event: SoundEvent, soundId: Int, limit: Int) {
        val key = event.rawValue
        val pool = activeStreams.getOrPut(key) { mutableListOf() }

        // Enforce voice limit — steal the oldest if at capacity
        if (pool.size >= limit) {
            val oldest = pool.minByOrNull { it.second }!!
            soundPool.stop(oldest.first)
            pool.remove(oldest)
        }

        val loopCount = if (event.loops) -1 else 0
        val streamId = soundPool.play(soundId, 1f, 1f, 1, loopCount, 1f)

        if (streamId != 0) {
            pool.add(Pair(streamId, System.currentTimeMillis()))
            if (event.loops) {
                loopingStreams[key] = streamId
            }
        } else {
            Log.w("AudioManager", "SoundPool.play returned 0 for ${event.rawValue} — sound may not be loaded yet")
        }
    }


    // MARK: - Private: Sound Loading

    private fun loadSound(filename: String, ext: String): Int? {
        val cacheKey = "$filename.$ext"
        soundIds[cacheKey]?.let { return it }

        return try {
            val afd: AssetFileDescriptor = appContext.assets.openFd("sounds/$cacheKey")
            val id = soundPool.load(afd, 1)
            soundIds[cacheKey] = id
            afd.close()
            id
        } catch (e: Exception) {
            Log.e("AudioManager", "File not found in assets/sounds/: $cacheKey — ${e.message}")
            null
        }
    }
}


// MARK: - Setup

// In your Application class:
//
//   class MyApp : Application() {
//       override fun onCreate() {
//           super.onCreate()
//           AudioManager.init(this)
//       }
//   }
//
// Then anywhere in the app:
//
//   AudioManager.shared.play(SoundEvent.TILE_PICK_UP)
//   AudioManager.shared.play(SoundEvent.GAME_SUCCESS)
//   AudioManager.shared.play(SoundEvent.LOOP_AMBIENT)   // looping
//   AudioManager.shared.stop(SoundEvent.LOOP_AMBIENT)   // stop loop
//   AudioManager.shared.stopAll()
//
// Sound files go in:  app/src/main/assets/sounds/
// Names must match rawValue exactly, e.g. tilePickUp.wav, tileDrop_1.wav … _4.wav
