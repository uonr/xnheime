import Foundation

/// Backed by the extension's own defaults. Without full access a keyboard may read
/// the containing app's shared group container but not write to it, so anything the
/// keyboard itself changes has to live here rather than in an App Group.
struct KeyboardSettings {
    private static let letterLayoutKey = "letterLayout"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var letterLayout: LetterLayout {
        get {
            defaults.string(forKey: Self.letterLayoutKey)
                .flatMap(LetterLayout.init(rawValue:)) ?? .full26
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.letterLayoutKey)
        }
    }
}
