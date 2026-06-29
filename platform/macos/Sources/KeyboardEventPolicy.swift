import AppKit
import Carbon.HIToolbox

enum KeyboardKey: Equatable {
    case returnKey
    case keypadEnter
    case escape
    case tab
    case deleteBackward
    case leftArrow
    case rightArrow
    case downArrow
    case upArrow
    case graveAccent
    case text
    case unmapped(UInt16)

    init(keyCode: UInt16) {
        switch keyCode {
        case UInt16(kVK_Return): self = .returnKey
        case UInt16(kVK_ANSI_KeypadEnter): self = .keypadEnter
        case UInt16(kVK_Escape): self = .escape
        case UInt16(kVK_Tab): self = .tab
        case UInt16(kVK_Delete): self = .deleteBackward
        case UInt16(kVK_LeftArrow): self = .leftArrow
        case UInt16(kVK_RightArrow): self = .rightArrow
        case UInt16(kVK_DownArrow): self = .downArrow
        case UInt16(kVK_UpArrow): self = .upArrow
        case UInt16(kVK_ANSI_Grave): self = .graveAccent
        default: self = .unmapped(keyCode)
        }
    }

    init(characters: String) {
        switch characters.unicodeScalars.first?.value {
        case UnicodeScalar("\n").value, UnicodeScalar("\r").value: self = .returnKey
        case UnicodeScalar("\t").value: self = .tab
        case UnicodeScalar("\u{1B}").value: self = .escape
        case UnicodeScalar("\u{7F}").value, UnicodeScalar("\u{8}").value: self = .deleteBackward
        case UInt32(NSUpArrowFunctionKey): self = .upArrow
        case UInt32(NSDownArrowFunctionKey): self = .downArrow
        case UInt32(NSLeftArrowFunctionKey): self = .leftArrow
        case UInt32(NSRightArrowFunctionKey): self = .rightArrow
        default: self = .text
        }
    }
}

enum KeyboardShift: Equatable {
    case left
    case right

    init?(keyCode: UInt16) {
        switch keyCode {
        case UInt16(kVK_Shift): self = .left
        case UInt16(kVK_RightShift): self = .right
        default: return nil
        }
    }
}

enum KeyboardInputAction: Equatable {
    case inputText(String)
    case insertDirect(String)
    case enterInline(String)
    case commit
    case commitCode
    case cancel
    case moveCandidate(Int)
    case commitAndPassThrough
    case passThrough
}

enum KeyboardCompositionState: Equatable {
    case idle
    case converting(candidateCount: Int)
    case inline

    var hasComposition: Bool {
        if case .idle = self { return false }
        return true
    }

    var candidateCount: Int {
        guard case let .converting(candidateCount) = self else { return 0 }
        return candidateCount
    }
}

enum KeyboardEventPolicy {
    private static let applicationShortcutModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
    ]

    static func shouldHandleTextInput(modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection(applicationShortcutModifiers).isEmpty
    }

    static func shiftTapAction(
        _ shift: KeyboardShift,
        composition: KeyboardCompositionState
    ) -> KeyboardInputAction {
        guard composition.hasComposition else { return .passThrough }
        switch shift {
        case .left: return .enterInline("")
        case .right: return .commitCode
        }
    }

    static func action(
        characters: String?,
        key: KeyboardKey,
        modifiers: NSEvent.ModifierFlags,
        composition: KeyboardCompositionState
    ) -> KeyboardInputAction {
        guard shouldHandleTextInput(modifiers: modifiers) else {
            return .passThrough
        }

        switch key {
        case .returnKey, .keypadEnter:
            if case let .converting(candidateCount) = composition, candidateCount > 0 {
                return .commitCode
            }
            return composition.hasComposition ? .commit : .passThrough
        case .escape:
            return composition.hasComposition ? .cancel : .passThrough
        case .leftArrow:
            return composition.candidateCount > 1
                ? .moveCandidate(-1)
                : (composition.hasComposition ? .commitAndPassThrough : .passThrough)
        case .rightArrow:
            return composition.candidateCount > 1
                ? .moveCandidate(1)
                : (composition.hasComposition ? .commitAndPassThrough : .passThrough)
        case .upArrow:
            return composition.candidateCount > 1
                ? .moveCandidate(-9)
                : (composition.hasComposition ? .commitAndPassThrough : .passThrough)
        case .downArrow:
            return composition.candidateCount > 1
                ? .moveCandidate(9)
                : (composition.hasComposition ? .commitAndPassThrough : .passThrough)
        case .tab:
            return composition.hasComposition ? .cancel : .passThrough
        case .deleteBackward:
            return composition.hasComposition ? .inputText(characters ?? "\u{7F}") : .passThrough
        case .graveAccent where !modifiers.contains(.shift):
            return .inputText("`")
        default:
            guard let characters, !characters.isEmpty else {
                return .passThrough
            }
            if composition.candidateCount > 1 {
                switch characters {
                case "-", "[": return .moveCandidate(-9)
                case "=", "]": return .moveCandidate(9)
                default: break
                }
            }
            if modifiers.contains(.shift), isAsciiLetter(characters) {
                return composition.hasComposition ? .enterInline(characters) : .insertDirect(characters)
            }
            return .inputText(characters)
        }
    }

    private static func isAsciiLetter(_ string: String) -> Bool {
        guard string.unicodeScalars.count == 1, let value = string.unicodeScalars.first?.value else {
            return false
        }
        return (0x41 ... 0x5A).contains(value) || (0x61 ... 0x7A).contains(value)
    }
}
