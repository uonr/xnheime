import IMKSwift
import XnheimeCore

@MainActor
enum InputSessionCache {
    private static let capacity = 5
    private static var keys: [Int] = []
    private static var values: [InputSession] = []
    private static let dictionaryModeURL = UserDictionaryStore.directory
        .appendingPathComponent("dictionary-mode.txt")
    private static var currentDictionaryMode = loadDictionaryMode()

    static var dictionaryMode: DictionaryMode {
        get { currentDictionaryMode }
        set {
            guard newValue != currentDictionaryMode else { return }
            let value = switch newValue {
            case .expert: "expert"
            case .regular: "regular"
            case .beginner: "beginner"
            }
            currentDictionaryMode = newValue
            do {
                try (value + "\n").write(
                    to: dictionaryModeURL,
                    atomically: true,
                    encoding: .utf8
                )
            } catch {
                NSLog("Xnheime: failed to save dictionary mode: %@", error.localizedDescription)
            }
            for session in values {
                session.setDictionaryMode(newValue)
            }
        }
    }

    private static func loadDictionaryMode() -> DictionaryMode {
        let value = try? String(contentsOf: dictionaryModeURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return switch value {
        case "regular": .regular
        case "beginner": .beginner
        default: .expert
        }
    }

    static func session(for client: any IMKTextInput) -> InputSession {
        let address = Int(bitPattern: Unmanaged.passUnretained(client as AnyObject).toOpaque())

        if let index = keys.firstIndex(of: address) {
            let cached = values.remove(at: index)
            keys.remove(at: index)
            keys.insert(address, at: 0)
            values.insert(cached, at: 0)
            return cached
        }

        let created = InputSession()
        keys.insert(address, at: 0)
        values.insert(created, at: 0)

        if keys.count > capacity {
            keys.removeLast()
            values.removeLast()
        }

        return created
    }

    @discardableResult
    static func reloadUserDictionaries() -> UserDictionaryLoadResult? {
        var result: UserDictionaryLoadResult?
        for session in values {
            result = session.reloadUserDictionary()
        }
        return result
    }
}
