import AppKit

@main
private enum KeyboardEventPolicyTests {
    static func main() {
        precondition(!KeyboardEventPolicy.shouldHandleTextInput(modifiers: .command))
        precondition(!KeyboardEventPolicy.shouldHandleTextInput(modifiers: [.command, .shift]))
        precondition(!KeyboardEventPolicy.shouldHandleTextInput(modifiers: .control))
        precondition(!KeyboardEventPolicy.shouldHandleTextInput(modifiers: .option))

        precondition(KeyboardEventPolicy.shouldHandleTextInput(modifiers: []))
        precondition(KeyboardEventPolicy.shouldHandleTextInput(modifiers: .shift))
        precondition(KeyboardEventPolicy.shouldHandleTextInput(modifiers: .capsLock))

        precondition(action(key: .text, characters: "c", modifiers: .command) == .passThrough)
        precondition(action(key: .text, characters: "v", modifiers: .command) == .passThrough)
        precondition(action(key: .returnKey, composition: .inline) == .commit)
        precondition(action(key: .keypadEnter, composition: .converting(candidateCount: 1)) == .commitCode)
        precondition(action(key: .returnKey) == .passThrough)
        precondition(action(key: .escape, composition: .inline) == .cancel)
        precondition(action(key: .escape) == .passThrough)
        precondition(action(key: .tab, composition: .inline) == .cancel)
        precondition(action(key: .tab, composition: .converting(candidateCount: 1)) == .cancel)
        precondition(action(key: .deleteBackward, characters: "\u{7F}", composition: .inline) == .inputText("\u{7F}"))
        precondition(action(key: .deleteBackward, characters: "\u{7F}") == .passThrough)
        precondition(action(key: .leftArrow, composition: .inline) == .commitAndPassThrough)
        precondition(action(key: .leftArrow, composition: .converting(candidateCount: 2)) == .moveCandidate(-1))
        precondition(action(key: .downArrow, composition: .converting(candidateCount: 2)) == .moveCandidate(9))
        precondition(action(key: .upArrow, composition: .converting(candidateCount: 10)) == .moveCandidate(-9))
        precondition(action(key: .text, characters: "-", composition: .converting(candidateCount: 10)) == .moveCandidate(-9))
        precondition(action(key: .text, characters: "=", composition: .converting(candidateCount: 10)) == .moveCandidate(9))
        precondition(action(key: .text, characters: "[", composition: .converting(candidateCount: 10)) == .moveCandidate(-9))
        precondition(action(key: .text, characters: "]", composition: .converting(candidateCount: 10)) == .moveCandidate(9))
        precondition(action(key: .rightArrow) == .passThrough)
        precondition(action(key: .text, characters: "a") == .inputText("a"))
        precondition(action(key: .text, characters: "A", modifiers: .shift) == .insertDirect("A"))
        precondition(
            action(key: .text, characters: "A", modifiers: .shift, composition: .converting(candidateCount: 2))
                == .enterInline("A")
        )
        precondition(action(key: .text, characters: ">", modifiers: .shift) == .inputText(">"))
        precondition(KeyboardKey(characters: "\r") == .returnKey)
        precondition(KeyboardKey(characters: "\t") == .tab)
        precondition(KeyboardKey(characters: "\u{7F}") == .deleteBackward)
        precondition(KeyboardKey(characters: "\u{f702}") == .leftArrow)
        precondition(KeyboardShift(keyCode: 0x38) == .left)
        precondition(KeyboardShift(keyCode: 0x3C) == .right)
        precondition(KeyboardShift(keyCode: 0x3B) == nil)
        precondition(
            KeyboardEventPolicy.shiftTapAction(.left, composition: .converting(candidateCount: 2))
                == .enterInline("")
        )
        precondition(
            KeyboardEventPolicy.shiftTapAction(.left, composition: .inline) == .enterInline("")
        )
        precondition(
            KeyboardEventPolicy.shiftTapAction(.right, composition: .converting(candidateCount: 2))
                == .commitCode
        )
        precondition(KeyboardEventPolicy.shiftTapAction(.right, composition: .idle) == .passThrough)
        precondition(action(key: .graveAccent, characters: "§", composition: .inline) == .inputText("`"))
        precondition(
            action(key: .graveAccent, characters: "~", modifiers: .shift, composition: .inline) == .inputText("~")
        )

        print("KeyboardEventPolicyTests passed")
    }

    private static func action(
        key: KeyboardKey,
        characters: String? = nil,
        modifiers: NSEvent.ModifierFlags = [],
        composition: KeyboardCompositionState = .idle
    ) -> KeyboardInputAction {
        KeyboardEventPolicy.action(
            characters: characters,
            key: key,
            modifiers: modifiers,
            composition: composition
        )
    }
}
