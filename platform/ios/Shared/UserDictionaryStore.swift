import Foundation

/// Where an imported code table lives on iOS.
///
/// The App Group container is the one place both sides can meet: without full access
/// a keyboard may read the containing app's shared group container but not write to
/// it, so a table only ever flows one way — the app imports, the keyboard reads. That
/// is also why nothing here writes from the extension.
enum UserDictionaryStore {
    static let groupIdentifier = "group.org.uonr.xnheime"
    private static let changeTokenName = ".dictionary-change-token"

    /// The file names the core looks for. Which one a table lands in decides where its
    /// entries sit relative to the built-in dictionary.
    enum Slot: String, CaseIterable, Identifiable, Sendable {
        /// Behind the built-in dictionary, unless a line ends in `# top`.
        case inline = "xnhe.txt"
        /// Every entry ahead of the built-in dictionary.
        case beforeSystem = "flypy_top.txt"
        /// Every entry behind it.
        case afterSystem = "flypy_user.txt"

        var id: String { rawValue }

    }

    /// nil only when the App Group is missing from the entitlements, which is a build
    /// mistake rather than a runtime condition.
    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("Library/Application Support/Xnheime", isDirectory: true)
    }

    static func url(for slot: Slot) -> URL? {
        directory?.appendingPathComponent(slot.rawValue, isDirectory: false)
    }

    static var changeTokenURL: URL? {
        directory?.appendingPathComponent(changeTokenName, isDirectory: false)
    }

    /// Includes every slot rather than only the newest modification date. Otherwise,
    /// deleting an older table while a newer one remains would leave stale entries in
    /// the keyboard process.
    static func fingerprint() -> String {
        let files = Slot.allCases.map { slot in
            guard let attributes = attributes(of: slot) else { return "\(slot.rawValue):-" }
            let size = attributes[.size] as? NSNumber ?? 0
            let date = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            return "\(slot.rawValue):\(size):\(date)"
        }.joined(separator: "|")
        let token = changeTokenURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return files + "|" + token
    }

    static func modificationDate(of slot: Slot) -> Date? {
        attributes(of: slot)?[.modificationDate] as? Date
    }

    static func byteCount(of slot: Slot) -> Int? {
        (attributes(of: slot)?[.size] as? NSNumber)?.intValue
    }

    static func exists(_ slot: Slot) -> Bool {
        guard let url = url(for: slot) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func attributes(of slot: Slot) -> [FileAttributeKey: Any]? {
        guard let url = url(for: slot) else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: url.path)
    }
}
