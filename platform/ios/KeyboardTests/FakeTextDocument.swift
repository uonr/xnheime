import Foundation

@MainActor
final class FakeTextDocument: TextDocumentWriting {
    private(set) var text = ""
    private(set) var inserted: [String] = []
    private(set) var deleteCount = 0
    private(set) var advanceCount = 0
    private(set) var dismissCount = 0
    var selectedText: String?

    init(text: String = "", selectedText: String? = nil) {
        self.text = text
        self.selectedText = selectedText
    }

    var documentContextBeforeInput: String? { text.isEmpty ? nil : text }

    var insertedText: String { inserted.joined() }

    func insertText(_ value: String) {
        inserted.append(value)
        text += value
    }

    func deleteBackward() {
        deleteCount += 1
        if !text.isEmpty { text.removeLast() }
    }

    func advanceToNextInputMode() { advanceCount += 1 }
    func dismissKeyboard() { dismissCount += 1 }
}
