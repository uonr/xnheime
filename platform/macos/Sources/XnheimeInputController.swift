import AppKit
import IMKSwift

@objc
private protocol XnheimeCommandPerforming {
    @objc(doCommandBySelector:)
    func doCommand(by selector: Selector)
}

@objc(XnheimeInputController)
@MainActor
public final class XnheimeInputController: IMKInputSessionController {
    private weak var session: XnheimeInputSession?

    override public init(server: IMKServer, delegate: Any?, client inputClient: any IMKTextInput) {
        super.init(server: server, delegate: delegate, client: inputClient)
        session = XnheimeInputSessionCache.session(for: inputClient, controller: self)
    }

    override public func activateServer(_ sender: any IMKTextInput) {
        session = XnheimeInputSessionCache.session(for: sender, controller: self)
    }

    override public func deactivateServer(_ sender: any IMKTextInput) {
        session?.commit(to: sender)
    }

    override public func inputText(_ string: String, client sender: any IMKTextInput) -> Bool {
        guard !string.isEmpty else { return false }
        activeSession(for: sender).inputText(string, client: sender)
        return true
    }

    override public func inputText(
        _ string: String,
        key keyCode: Int,
        modifiers flags: UInt,
        client sender: any IMKTextInput
    ) -> Bool {
        inputText(string, client: sender)
    }

    override public func handle(_ event: NSEvent?, client sender: any IMKTextInput) -> Bool {
        guard event?.type == .keyDown, let characters = event?.characters, !characters.isEmpty else {
            return false
        }
        return inputText(characters, client: sender)
    }

    override public func commitComposition(_ sender: any IMKTextInput) {
        activeSession(for: sender).commit(to: sender)
    }

    override public func cancelComposition() {
        session?.cancel()
    }

    override public func candidates(_ sender: any IMKTextInput) -> [Any]? {
        nil
    }

    @MainActor
    private func activeSession(for sender: any IMKTextInput) -> XnheimeInputSession {
        if let session {
            return session
        }

        let restored = XnheimeInputSessionCache.session(for: sender, controller: self)
        session = restored
        return restored
    }
}

@MainActor
private enum XnheimeInputSessionCache {
    private static let capacity = 5
    private static var keys: [Int] = []
    private static var values: [XnheimeInputSession] = []

    static func session(for client: any IMKTextInput, controller: XnheimeInputController) -> XnheimeInputSession {
        let address = Int(bitPattern: Unmanaged.passUnretained(client as AnyObject).toOpaque())

        if let index = keys.firstIndex(of: address) {
            let cached = values.remove(at: index)
            keys.remove(at: index)
            cached.reassign(to: controller)
            keys.insert(address, at: 0)
            values.insert(cached, at: 0)
            return cached
        }

        let created = XnheimeInputSession(controller: controller)
        keys.insert(address, at: 0)
        values.insert(created, at: 0)

        if keys.count > capacity {
            keys.removeLast()
            values.removeLast()
        }

        return created
    }
}

@MainActor
private final class XnheimeInputSession {
    private weak var controller: XnheimeInputController?
    private var buffer = ""

    init(controller: XnheimeInputController) {
        self.controller = controller
    }

    func reassign(to controller: XnheimeInputController) {
        self.controller = controller
    }

    func inputText(_ string: String, client sender: any IMKTextInput) {
        if string.count != 1 {
            commit(to: sender)
            sender.insertText(string, replacementRange: replacementRange)
            return
        }

        guard let character = string.unicodeScalars.first else {
            return
        }

        switch character.value {
        case 0x7F, 0x08:
            deleteBackward(client: sender)
        case 0x20 ... 0x7E:
            handleAsciiInput(string, client: sender)
        default:
            commit(to: sender)
            sender.insertText(string, replacementRange: replacementRange)
        }
    }

    func commit(to sender: any IMKTextInput) {
        guard !buffer.isEmpty else { return }
        sender.insertText(lookupFirstCandidate(buffer) ?? buffer, replacementRange: replacementRange)
        buffer.removeAll(keepingCapacity: true)
    }

    func cancel() {
        buffer.removeAll(keepingCapacity: true)
    }

    private func handleAsciiInput(_ string: String, client sender: any IMKTextInput) {
        if string == " " {
            guard !buffer.isEmpty else {
                sender.insertText(string, replacementRange: replacementRange)
                return
            }

            commit(to: sender)
            return
        }

        guard let character = string.unicodeScalars.first, isCodeCharacter(character) else {
            commit(to: sender)
            sender.insertText(string, replacementRange: replacementRange)
            return
        }

        let candidate = buffer + string.lowercased()

        guard hasCodePrefix(candidate) else {
            commit(to: sender)
            sender.insertText(string, replacementRange: replacementRange)
            return
        }

        buffer = candidate

        if shouldAutoSelect(buffer), let converted = lookupFirstCandidate(buffer) {
            sender.insertText(converted, replacementRange: replacementRange)
            buffer.removeAll(keepingCapacity: true)
            return
        }

        sender.setMarkedText(
            buffer,
            selectionRange: NSRange(location: buffer.count, length: 0),
            replacementRange: replacementRange
        )
    }

    private func isCodeCharacter(_ character: Unicode.Scalar) -> Bool {
        switch character.value {
        case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x27, 0x3B:
            return true
        default:
            return false
        }
    }

    private func shouldAutoSelect(_ input: String) -> Bool {
        input.count >= 4 || (input.first == ";" && input.count == 2)
    }

    private func deleteBackward(client sender: any IMKTextInput) {
        guard !buffer.isEmpty else {
            (sender as? XnheimeCommandPerforming)?.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            return
        }

        buffer.removeLast()

        sender.setMarkedText(
            buffer,
            selectionRange: NSRange(location: buffer.count, length: 0),
            replacementRange: replacementRange
        )
    }

    private func hasCodePrefix(_ input: String) -> Bool {
        input.withCString { rawInput in
            xnheime_has_code_prefix(rawInput)
        }
    }

    private func lookupFirstCandidate(_ input: String) -> String? {
        input.withCString { rawInput in
            guard let rawOutput = xnheime_lookup_first(rawInput) else {
                return nil
            }

            defer { xnheime_string_free(rawOutput) }
            return String(cString: rawOutput)
        }
    }

    private var replacementRange: NSRange {
        NSRange(location: NSNotFound, length: NSNotFound)
    }
}
