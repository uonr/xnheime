import Foundation
import Darwin
import XnheimeCore

enum UserEntryPlacement {
    case beforeSystem
    case afterSystem
}

@MainActor
enum UserDictionaryStore {
    private static var directoryWatcher: DispatchSourceFileSystemObject?
    private static var reloadGeneration = 0

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Xnheime", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let defaultDictionary = directory.appendingPathComponent("xnhe.txt")
            if !FileManager.default.fileExists(atPath: defaultDictionary.path) {
                let template = """
                # Xnheime user dictionary (UTF-8)
                # 词条<Tab>编码
                # 在行尾添加 # top 可将该词条排在系统词库之前：
                # 竹子\tvuzi # top
                # 周目\tvzmu

                """
                try template.write(to: defaultDictionary, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("Xnheime: cannot prepare user dictionary directory: %@", error.localizedDescription)
        }
        return directory
    }()

    static func startWatching() {
        guard directoryWatcher == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("Xnheime: cannot watch user dictionary directory")
            return
        }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        watcher.setEventHandler {
            Task { @MainActor in
                scheduleAutomaticReload()
            }
        }
        watcher.setCancelHandler {
            close(descriptor)
        }
        directoryWatcher = watcher
        watcher.resume()
    }

    static func appendEntry(
        text: String,
        code: String,
        placement: UserEntryPlacement,
        weight: String?
    ) throws {
        let dictionary = directory.appendingPathComponent("xnhe.txt")
        let trimmedWeight = weight?.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = "\(text)\t\(code)"
        if placement == .afterSystem, let trimmedWeight, !trimmedWeight.isEmpty {
            line += "\t\(trimmedWeight)"
        }
        if placement == .beforeSystem {
            line += " # top"
        }
        line += "\n"

        let handle = try FileHandle(forUpdating: dictionary)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            let lastByte = try handle.read(upToCount: 1)
            try handle.seekToEnd()
            if lastByte != Data([0x0A]) {
                try handle.write(contentsOf: Data([0x0A]))
            }
        }
        try handle.write(contentsOf: Data(line.utf8))
    }

    private static func scheduleAutomaticReload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard generation == reloadGeneration else { return }
            guard let result = InputSessionCache.reloadUserDictionaries() else { return }
            if let error = result.error {
                NSLog("Xnheime: automatic user dictionary reload failed: %@", error)
            }
        }
    }
}
