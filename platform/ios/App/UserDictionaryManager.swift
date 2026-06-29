import Foundation

@MainActor
final class UserDictionaryManager: ObservableObject {
    @Published var selectedSlot: UserDictionaryStore.Slot = .afterSystem
    @Published var importURL = ""
    @Published private(set) var isDownloading = false
    @Published var message: String?
    @Published var slotToDelete: UserDictionaryStore.Slot?
    @Published private(set) var urlHistory: [String]
    @Published private(set) var revision = UUID()

    private static let historyKey = "userDictionaryURLHistory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        urlHistory = defaults.stringArray(forKey: Self.historyKey) ?? []
    }

    func installFile(_ source: URL) {
        let destinationSlot = selectedSlot
        do {
            try UserDictionaryImporter.install(from: source, in: destinationSlot)
            didInstall(in: destinationSlot)
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    func importFromURL() async {
        let rawURL = importURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased()) else {
            message = "请输入有效的 HTTP 或 HTTPS URL。"
            return
        }

        let destinationSlot = selectedSlot
        isDownloading = true
        defer { isDownloading = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (temporaryFile, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLImportError.badResponse((response as? HTTPURLResponse)?.statusCode)
            }
            try UserDictionaryImporter.install(from: temporaryFile, in: destinationSlot)
            rememberURL(rawURL)
            didInstall(in: destinationSlot)
        } catch {
            message = "URL 导入失败：\(error.localizedDescription)"
        }
    }

    func removeSelectedSlot() {
        guard let slot = slotToDelete else { return }
        slotToDelete = nil
        do {
            try UserDictionaryImporter.remove(slot)
            revision = UUID()
        } catch {
            message = "删除失败：\(error.localizedDescription)"
        }
    }

    func clearHistory() {
        urlHistory = []
        defaults.set([], forKey: Self.historyKey)
    }

    private let defaults: UserDefaults

    private func rememberURL(_ url: String) {
        urlHistory.removeAll { $0 == url }
        urlHistory.insert(url, at: 0)
        urlHistory = Array(urlHistory.prefix(10))
        defaults.set(urlHistory, forKey: Self.historyKey)
    }

    private func didInstall(in slot: UserDictionaryStore.Slot) {
        revision = UUID()
        message = "已导入到“\(slot.title)”。下次显示键盘时生效。"
    }
}

private enum URLImportError: LocalizedError {
    case badResponse(Int?)

    var errorDescription: String? {
        switch self {
        case let .badResponse(status):
            status.map { "服务器返回 HTTP \($0)。" } ?? "服务器响应无效。"
        }
    }
}
