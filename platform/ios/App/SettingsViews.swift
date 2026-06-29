import SwiftUI
import UniformTypeIdentifiers

struct UserDictionarySettingsView: View {
    @StateObject private var manager = UserDictionaryManager()
    @State private var importsFile = false

    var body: some View {
        Section("用户码表") {
            Picker("导入位置", selection: $manager.selectedSlot) {
                ForEach(UserDictionaryStore.Slot.allCases) { slot in
                    Text(slot.title).tag(slot)
                }
            }
            Text(manager.selectedSlot.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("从文件导入…", systemImage: "doc.badge.plus") { importsFile = true }
            urlImporter
            historyMenu
            ForEach(UserDictionaryStore.Slot.allCases) { slot in
                dictionaryRow(slot)
            }
        }
        .id(manager.revision)
        .fileImporter(
            isPresented: $importsFile,
            allowedContentTypes: Self.supportedDictionaryTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let source = urls.first { manager.installFile(source) }
            case let .failure(error):
                manager.message = "无法选择文件：\(error.localizedDescription)"
            }
        }
        .alert("用户码表", isPresented: messageIsPresented) {
            Button("好") { manager.message = nil }
        } message: {
            Text(manager.message ?? "")
        }
        .confirmationDialog(
            "删除这份码表？",
            isPresented: deleteConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { manager.removeSelectedSlot() }
            Button("取消", role: .cancel) { manager.slotToDelete = nil }
        }
    }

    private var urlImporter: some View {
        HStack {
            TextField("https://example.com/xnhe.txt", text: $manager.importURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button {
                Task { await manager.importFromURL() }
            } label: {
                if manager.isDownloading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .disabled(manager.isDownloading || manager.importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("从 URL 导入")
        }
    }

    @ViewBuilder
    private var historyMenu: some View {
        if !manager.urlHistory.isEmpty {
            Menu("最近使用的 URL", systemImage: "clock.arrow.circlepath") {
                ForEach(manager.urlHistory, id: \.self) { url in
                    Button(url) { manager.importURL = url }
                }
                Divider()
                Button("清除历史记录", role: .destructive) { manager.clearHistory() }
            }
        }
    }

    @ViewBuilder
    private func dictionaryRow(_ slot: UserDictionaryStore.Slot) -> some View {
        if UserDictionaryStore.exists(slot) {
            HStack {
                VStack(alignment: .leading) {
                    Text(slot.title)
                    Text(dictionaryMetadata(slot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { manager.slotToDelete = slot } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除\(slot.title)")
            }
        }
    }

    private func dictionaryMetadata(_ slot: UserDictionaryStore.Slot) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(UserDictionaryStore.byteCount(of: slot) ?? 0),
            countStyle: .file
        )
        guard let date = UserDictionaryStore.modificationDate(of: slot) else { return size }
        return "\(size) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(get: { manager.message != nil }, set: { if !$0 { manager.message = nil } })
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(get: { manager.slotToDelete != nil }, set: { if !$0 { manager.slotToDelete = nil } })
    }

    private static let supportedDictionaryTypes: [UTType] = {
        ["txt", "yaml", "yml", "dict", "tsv", "csv"]
            .compactMap { UTType(filenameExtension: $0) } + [.plainText]
    }()
}

extension UserDictionaryStore.Slot {
    var title: String {
        switch self {
        case .inline: "用户码表"
        case .beforeSystem: "置顶码表"
        case .afterSystem: "补充码表"
        }
    }

    var detail: String {
        switch self {
        case .inline: "排在系统词库之后，行尾写 # top 的词条排到之前"
        case .beforeSystem: "整份排在系统词库之前"
        case .afterSystem: "整份排在系统词库之后"
        }
    }
}

struct KeyboardFeedbackSettingsView: View {
    @State private var configuration = SharedKeyboardSettings.feedback

    var body: some View {
        Section("按键反馈") {
            Toggle("按键声音", isOn: $configuration.soundEnabled)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("震动强度")
                    Spacer()
                    Text(configuration.strength == 0 ? "关闭" : configuration.strength.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $configuration.strength, in: 0...1, step: 0.05)
            }
            Text("前往“设置 → 通用 → 键盘 → 键盘 → 萧何输入法”，打开“允许完全访问”。未打开时，这些选项不会生效。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: configuration) { _, value in
            SharedKeyboardSettings.feedback = value
        }
    }
}
