// AUTO-GENERATED — do not edit directly.
// Source of truth: SoundEventList.csv
// Regenerate:  python3 scripts/generate_sound_events.py

package com.soundtest.app


// MARK: - Variation Mode

enum class VariationMode {
    SEQUENTIAL,
    RANDOM
}


// MARK: - Sound Events

enum class SoundEvent(val rawValue: String) {

    // Game
    GAME_ERROR("gameError"),
    GAME_SUCCESS("gameSuccess"),
    LOOP_AMBIENT("loopAmbient"),
    REWARD_1("reward1"),
    REWARD_2("reward2"),
    REWARD_3("reward3"),
    REWARD_4("reward4"),
    TILE_DROP("tileDrop"),
    TILE_PICK_UP("tilePickUp"),
    TILE_PLACE("tilePlace"),

    // UI
    UI_MODAL_CLOSE("uiModalClose"),
    UI_MODAL_OPEN("uiModalOpen"),
    UI_TAP("uiTap"),
    CANCEL("Cancel");


    // MARK: - Configuration

    val fileExtension: String get() = "wav"

    val maxVoices: Int get() = when (this) {
        LOOP_AMBIENT,
        REWARD_1,
        REWARD_2,
        REWARD_3,
        REWARD_4 -> 1
        else -> 3
    }

    val loops: Boolean get() = when (this) {
        LOOP_AMBIENT -> true
        else -> false
    }

    val variationCount: Int get() = when (this) {
        TILE_DROP,
        TILE_PLACE -> 8
        else -> 1
    }

    val variationMode: VariationMode get() = when (this) {
        TILE_PLACE -> VariationMode.SEQUENTIAL
        else -> VariationMode.RANDOM
    }

    val variationSeparator: String get() = "_"

    val category: String get() = when (this) {
        UI_MODAL_CLOSE,
        UI_MODAL_OPEN,
        UI_TAP,
        CANCEL -> "UI"
        else -> "Game"
    }

    val displayName: String get() = when (this) {
        GAME_ERROR -> "Error"
        GAME_SUCCESS -> "Game won"
        LOOP_AMBIENT -> "On game start"
        REWARD_1 -> "Level 1 reward popup"
        REWARD_2 -> "Level 2 reward popup"
        REWARD_3 -> "Level 3 reward popup"
        REWARD_4 -> "Level 4 reward popup"
        TILE_DROP -> "Drop tile in tray"
        TILE_PICK_UP -> "Select tile"
        TILE_PLACE -> "Play tile 1"
        UI_MODAL_CLOSE -> "Close panel"
        UI_MODAL_OPEN -> "Open panel"
        UI_TAP -> "Tap"
        CANCEL -> "Cancel"
    }

    companion object {
        val categories: List<String> = listOf("Game", "UI")
    }
}
