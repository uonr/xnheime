import Foundation

struct KeyboardFeedbackConfiguration: Equatable, Sendable {
    var soundEnabled: Bool
    var strength: Double
}

@MainActor
enum SharedKeyboardSettings {
    private static let soundKey = "keyboardFeedbackSound"
    private static let strengthKey = "keyboardFeedbackStrength"
    private static let defaults = UserDefaults(
        suiteName: UserDictionaryStore.groupIdentifier
    )

    static var feedback: KeyboardFeedbackConfiguration {
        get {
            KeyboardFeedbackConfiguration(
                soundEnabled: defaults?.object(forKey: soundKey) as? Bool ?? true,
                strength: storedStrength
            )
        }
        set {
            defaults?.set(newValue.soundEnabled, forKey: soundKey)
            defaults?.set(min(max(newValue.strength, 0), 1), forKey: strengthKey)
        }
    }

    private static var storedStrength: Double {
        guard let stored = defaults?.object(forKey: strengthKey) else { return 0.65 }
        if let value = stored as? NSNumber {
            return min(max(value.doubleValue, 0), 1)
        }
        switch stored as? String {
        case "off": return 0
        case "light": return 0.35
        case "strong": return 1
        default: return 0.65
        }
    }
}
