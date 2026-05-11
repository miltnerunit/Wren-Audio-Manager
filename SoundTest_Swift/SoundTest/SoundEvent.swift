// AUTO-GENERATED — do not edit directly.
// Source of truth: SoundEventList.csv
// Regenerate:  python3 scripts/generate_sound_events.py


// MARK: - Variation Mode

enum VariationMode {
    case sequential
    case random
}


// MARK: - Sound Events

enum SoundEvent: String, CaseIterable, Identifiable {

    var id: String { rawValue }

    // MARK: Game
    case gameError
    case gameSuccess
    case loopAmbient
    case reward1
    case reward2
    case reward3
    case reward4
    case tileDrop
    case tilePickUp
    case tilePlace

    // MARK: UI
    case uiModalClose
    case uiModalOpen
    case uiTap
    case cancel = "Cancel"


    // MARK: - Configuration

    var fileExtension: String { "wav" }

    var maxVoices: Int {
        switch self {
        case .loopAmbient,
             .reward1,
             .reward2,
             .reward3,
             .reward4: return 1
        default: return 3
        }
    }

    var loops: Bool {
        switch self {
        case .loopAmbient: return true
        default: return false
        }
    }

    var variationCount: Int {
        switch self {
        case .tileDrop,
             .tilePlace: return 8
        default: return 1
        }
    }

    var variationMode: VariationMode {
        switch self {
        case .tilePlace: return .sequential
        default: return .random
        }
    }

    var variationSeparator: String { "_" }

    var category: String {
        switch self {
        case .uiModalClose,
             .uiModalOpen,
             .uiTap,
             .cancel: return "UI"
        default: return "Game"
        }
    }

    var displayName: String {
        switch self {
        case .gameSuccess: return "Game won"
        case .loopAmbient: return "On game start"
        case .reward1: return "Level 1 reward popup"
        case .reward2: return "Level 2 reward popup"
        case .reward3: return "Level 3 reward popup"
        case .reward4: return "Level 4 reward popup"
        case .tileDrop: return "Drop tile in tray"
        case .tilePickUp: return "Select tile"
        case .tilePlace: return "Play tile 1"
        case .uiModalClose: return "Close panel"
        case .uiModalOpen: return "Open panel"
        case .uiTap: return "Tap"
        case .cancel: return "Cancel"
        default: return "Error"
        }
    }

    static let categories: [String] = ["Game", "UI"]

}
