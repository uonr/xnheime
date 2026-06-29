import Foundation

enum UserDictionaryImporter {
    static let maximumImportBytes = 20 * 1024 * 1024

    static func install(_ data: Data, in slot: UserDictionaryStore.Slot) throws {
        guard data.count <= maximumImportBytes else { throw ImportError.tooLarge }
        guard String(data: data, encoding: .utf8) != nil else { throw ImportError.notUTF8 }
        guard let directory = UserDictionaryStore.directory,
              let destination = UserDictionaryStore.url(for: slot)
        else { throw ImportError.appGroupUnavailable }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        try bumpChangeToken()
    }

    static func install(from source: URL, in slot: UserDictionaryStore.Slot) throws {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        try install(Data(contentsOf: source, options: .mappedIfSafe), in: slot)
    }

    static func remove(_ slot: UserDictionaryStore.Slot) throws {
        guard let destination = UserDictionaryStore.url(for: slot) else {
            throw ImportError.appGroupUnavailable
        }
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
        try bumpChangeToken()
    }

    enum ImportError: LocalizedError {
        case appGroupUnavailable
        case notUTF8
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable: "无法访问 App Group，请检查签名配置。"
            case .notUTF8: "码表不是 UTF-8 文本。"
            case .tooLarge: "码表超过 20 MB。"
            }
        }
    }

    private static func bumpChangeToken() throws {
        guard let changeTokenURL = UserDictionaryStore.changeTokenURL else {
            throw ImportError.appGroupUnavailable
        }
        try UUID().uuidString.write(
            to: changeTokenURL,
            atomically: true,
            encoding: .utf8
        )
    }
}
