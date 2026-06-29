import Foundation
import XnheimeCore

@main
@MainActor
private enum UniFFICoreTests {
    static func main() {
        let session = CompositionSession()
        func dispatch(_ event: CompositionEvent) -> [CompositionEffect] {
            session.dispatch(event: event, selectedText: nil, clipboardText: nil)
        }

        precondition(dispatch(.inputText(text: "g")).first == .setMarkedText(text: "g"))
        precondition(dispatch(.inputText(text: "i")).first == .setMarkedText(text: "gi"))
        let emptyCodeEffects = dispatch(.inputText(text: "t"))
        precondition(emptyCodeEffects.first == .setMarkedText(text: "git"))
        guard case let .showCandidates(candidates, selectedIndex, characterIndex) = emptyCodeEffects.last else {
            preconditionFailure("empty code should offer a user dictionary entry")
        }
        precondition(candidates == [
            .actionHint(text: "新增", label: "+", action: .addUserEntry),
        ])
        precondition(selectedIndex == 0 && characterIndex == 3)
        precondition(session.mode() == .inline)
        precondition(dispatch(.commit) == [
            .insertText(text: "git"),
            .hideCandidates,
        ])

        print("UniFFICoreTests passed")
    }
}
