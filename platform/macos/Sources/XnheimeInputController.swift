import AppKit
import IMKSwift
import XnheimeCore

@objc(XnheimeInputController)
@MainActor
public final class XnheimeInputController: IMKInputSessionController {
    private enum MenuCommand: Int {
        case expertMode = 100
        case regularMode
        case beginnerMode
        case reloadUserDictionary = 200
        case openUserDictionaryDirectory
    }

    private weak var session: InputSession?
    private var pendingShiftTap: KeyboardShift?

    override public init(server: IMKServer, delegate: Any?, client inputClient: any IMKTextInput) {
        super.init(server: server, delegate: delegate, client: inputClient)
        session = InputSessionCache.session(for: inputClient)
    }

    override public func activateServer(_ sender: any IMKTextInput) {
        session = InputSessionCache.session(for: sender)
    }

    override public func deactivateServer(_ sender: any IMKTextInput) {
        pendingShiftTap = nil
        session?.cancel()
    }

    override public func recognizedEvents(_ sender: any IMKTextInput) -> UInt {
        UInt(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    override public func handle(_ event: NSEvent?, client sender: any IMKTextInput) -> Bool {
        guard let event else { return false }
        if event.type == .flagsChanged {
            return handleShiftFlagsChanged(event, client: sender)
        }
        guard event.type == .keyDown else { return false }
        pendingShiftTap = nil
        let session = activeSession(for: sender)
        return handle(
            KeyboardEventPolicy.action(
                characters: event.characters,
                key: KeyboardKey(keyCode: event.keyCode),
                modifiers: event.modifierFlags,
                composition: session.keyboardState
            ),
            client: sender
        )
    }

    private func handleShiftFlagsChanged(_ event: NSEvent, client sender: any IMKTextInput) -> Bool {
        guard let shift = KeyboardShift(keyCode: event.keyCode) else {
            pendingShiftTap = nil
            return false
        }
        if event.modifierFlags.contains(.shift) {
            pendingShiftTap = shift
            return false
        }
        guard pendingShiftTap == shift else { return false }
        pendingShiftTap = nil
        let session = activeSession(for: sender)
        return handle(
            KeyboardEventPolicy.shiftTapAction(shift, composition: session.keyboardState),
            client: sender
        )
    }

    override public func commitComposition(_ sender: any IMKTextInput) {
        activeSession(for: sender).commit(to: sender)
    }

    override public func cancelComposition() {
        session?.cancel()
    }

    override public func candidates(_ sender: any IMKTextInput) -> [Any]? {
        activeSession(for: sender).candidates
    }

    override public func menu() -> NSMenu? {
        let menu = NSMenu(title: "Xnheime")
        for (title, mode, command) in [
            ("模式：熟手", DictionaryMode.expert, MenuCommand.expertMode),
            ("模式：常规", DictionaryMode.regular, MenuCommand.regularMode),
            ("模式：初学", DictionaryMode.beginner, MenuCommand.beginnerMode),
        ] {
            let item = NSMenuItem(
                title: title,
                action: #selector(menuCommand(_:)),
                keyEquivalent: ""
            )
            item.tag = command.rawValue
            item.state = mode == InputSessionCache.dictionaryMode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let reload = NSMenuItem(
            title: "重新加载用户码表",
            action: #selector(menuCommand(_:)),
            keyEquivalent: ""
        )
        reload.tag = MenuCommand.reloadUserDictionary.rawValue
        menu.addItem(reload)

        let open = NSMenuItem(
            title: "打开用户码表文件夹…",
            action: #selector(menuCommand(_:)),
            keyEquivalent: ""
        )
        open.tag = MenuCommand.openUserDictionaryDirectory.rawValue
        menu.addItem(open)
        return menu
    }

    @objc private func menuCommand(_ item: NSMenuItem) {
        guard let command = MenuCommand(rawValue: item.tag) else { return }
        switch command {
        case .expertMode, .regularMode, .beginnerMode:
            let mode: DictionaryMode = switch command {
            case .regularMode: .regular
            case .beginnerMode: .beginner
            default: .expert
            }
            InputSessionCache.dictionaryMode = mode
            NSLog("Xnheime: switched dictionary mode to %@", item.title)
        case .reloadUserDictionary:
            reloadUserDictionary()
        case .openUserDictionaryDirectory:
            NSWorkspace.shared.open(UserDictionaryStore.directory)
        }
    }

    private func reloadUserDictionary() {
        let result = InputSessionCache.reloadUserDictionaries()
            ?? InputSession().reloadUserDictionary()
        if let error = result.error {
            NSLog("Xnheime: failed to reload user dictionaries: %@", error)
        } else {
            NSLog(
                "Xnheime: loaded %u user dictionary entries from %@ (%u ignored lines)",
                result.loadedEntries,
                result.loadedFiles.joined(separator: ", "),
                result.ignoredLines
            )
        }
    }

    @MainActor
    private func activeSession(for sender: any IMKTextInput) -> InputSession {
        if let session {
            return session
        }

        let restored = InputSessionCache.session(for: sender)
        session = restored
        return restored
    }

    private func handle(_ action: KeyboardInputAction, client sender: any IMKTextInput) -> Bool {
        let session = activeSession(for: sender)
        switch action {
        case let .inputText(string):
            session.inputText(string, client: sender)
            return true
        case let .insertDirect(string):
            session.insertDirect(string, client: sender)
            return true
        case let .enterInline(string):
            session.enterInline(string, client: sender)
            return true
        case .commit:
            session.commit(to: sender)
            return true
        case .commitCode:
            session.commitCode(to: sender)
            return true
        case .cancel:
            session.cancel(client: sender)
            return true
        case let .moveCandidate(offset):
            session.moveCandidate(by: offset, client: sender)
            return true
        case .commitAndPassThrough:
            session.commit(to: sender)
            return false
        case .passThrough:
            return false
        }
    }
}
