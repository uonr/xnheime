import AppKit
import IMKSwift
import XnheimeCore

@MainActor
final class InputSession {
    private let reducer = CompositionSession()
    private var selectedTextSnapshot: String?

    init() {
        reloadUserDictionary()
    }

    @discardableResult
    func reloadUserDictionary() -> UserDictionaryLoadResult {
        reducer.loadUserDictionaryDirectory(path: UserDictionaryStore.directory.path)
    }

    var keyboardState: KeyboardCompositionState {
        switch reducer.mode() {
        case .idle:
            return .idle
        case let .converting(candidateCount):
            return .converting(candidateCount: Int(candidateCount))
        case .inline:
            return .inline
        }
    }

    var candidates: [String] { reducer.candidates().map(\.text) }

    func inputText(_ string: String, client sender: any IMKTextInput) {
        if case .idle = keyboardState {
            selectedTextSnapshot = selectedText(from: sender)
        }
        dispatch(.inputText(text: string), to: sender)
    }

    func commit(to sender: any IMKTextInput) {
        dispatch(.commit, to: sender)
    }

    func commitCode(to sender: any IMKTextInput) {
        dispatch(.commitCode, to: sender)
    }

    func insertDirect(_ string: String, client sender: any IMKTextInput) {
        dispatch(.insertDirect(text: string), to: sender)
    }

    func enterInline(_ string: String, client sender: any IMKTextInput) {
        dispatch(.enterInline(text: string), to: sender)
    }

    func cancel(client sender: (any IMKTextInput)? = nil) {
        let effects = reducer.dispatch(
            event: .cancel(clearMarkedText: sender != nil),
            selectedText: selectedTextSnapshot,
            clipboardText: clipboardText
        )
        selectedTextSnapshot = nil
        guard let sender else {
            CandidatePanel.shared.hide()
            return
        }
        apply(effects, to: sender)
    }

    func moveCandidate(by offset: Int, client sender: any IMKTextInput) {
        dispatch(.moveCandidate(offset: Int32(offset)), to: sender)
    }

    private func dispatch(_ event: CompositionEvent, to sender: any IMKTextInput) {
        apply(
            reducer.dispatch(
                event: event,
                selectedText: selectedTextSnapshot,
                clipboardText: clipboardText
            ),
            to: sender
        )
        if case .idle = keyboardState {
            selectedTextSnapshot = nil
        }
    }

    private func selectedText(from sender: any IMKTextInput) -> String? {
        let range = sender.selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return sender.attributedSubstring(from: range)?.string
    }

    private var clipboardText: String? {
        NSPasteboard.general.string(forType: .string)
    }

    private func apply(_ effects: [CompositionEffect], to sender: any IMKTextInput) {
        for effect in effects {
            switch effect {
            case let .insertText(text):
                sender.insertText(text, replacementRange: replacementRange)
            case let .insertPairedText(before, after):
                _ = after
                sender.insertText(before, replacementRange: replacementRange)
            case let .setMarkedText(text):
                sender.setMarkedText(
                    text,
                    selectionRange: NSRange(location: text.utf16.count, length: 0),
                    replacementRange: replacementRange
                )
            case let .showCandidates(candidates, selectedIndex, characterIndex):
                CandidatePanel.shared.show(
                    candidates: candidates,
                    selectedIndex: Int(selectedIndex),
                    characterIndex: Int(characterIndex),
                    client: sender
                )
            case .hideCandidates:
                CandidatePanel.shared.hide()
            case .deleteBackward:
                break
            case let .showAddEntryDialog(code):
                DispatchQueue.main.async { [weak self] in
                    self?.showAddEntryDialog(code: code, client: sender)
                }
            }
        }
    }

    private func showAddEntryDialog(code: String, client sender: any IMKTextInput) {
        CandidatePanel.shared.hide()
        AddUserEntryPanel.present(code: code) { [weak self] entry in
            guard let self else { return "输入会话已经结束。" }
            do {
                try UserDictionaryStore.appendEntry(
                    text: entry.text,
                    code: entry.code,
                    placement: entry.placement,
                    weight: entry.weight
                )
                _ = InputSessionCache.reloadUserDictionaries()
                cancel(client: sender)
                sender.insertText(entry.text, replacementRange: replacementRange)
                return nil
            } catch {
                return "无法写入 xnhe.txt：\(error.localizedDescription)"
            }
        }
    }

    private var replacementRange: NSRange {
        NSRange(location: NSNotFound, length: NSNotFound)
    }
}

