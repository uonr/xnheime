import IMKSwift
import XnheimeCore

@MainActor
enum InputSessionCache {
    private static let capacity = 5
    private static var keys: [Int] = []
    private static var values: [InputSession] = []

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
