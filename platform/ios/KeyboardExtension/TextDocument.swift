@MainActor
protocol TextDocumentWriting: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func advanceToNextInputMode()
    func dismissKeyboard()
    var documentContextBeforeInput: String? { get }
    var selectedText: String? { get }
}
