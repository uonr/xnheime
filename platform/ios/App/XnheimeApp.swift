import SwiftUI

@main
struct XnheimeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    @State private var sample = ""
    @FocusState private var sampleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("启用键盘") {
                    Text("前往“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”，选择萧何输入法。")
                    Button("打开设置") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
                Section("试用") {
                    TextField("在这里切换到萧何输入法", text: $sample, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($sampleFocused)
                }
                DictionaryModeSettingsView()
                UserDictionarySettingsView()
                KeyboardFeedbackSettingsView()
            }
            .navigationTitle("萧何输入法")
            .onAppear { sampleFocused = true }
        }
    }
}
