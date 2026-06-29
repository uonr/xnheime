import XCTest

@MainActor
final class KeyboardModelTests: XCTestCase {
    nonisolated private static let defaultsSuite = "org.uonr.xnheime.ios.keyboardtests.settings"

    private var documents: [FakeTextDocument] = []

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: Self.defaultsSuite)
    }

    private func makeModel(
        text: String = "",
        selectedText: String? = nil
    ) -> (KeyboardModel, FakeTextDocument) {
        let document = FakeTextDocument(text: text, selectedText: selectedText)
        documents.append(document)
        let defaults = UserDefaults(suiteName: Self.defaultsSuite)!
        let model = KeyboardModel(document: document, settings: KeyboardSettings(defaults: defaults))
        return (model, document)
    }

    private func composeNi(_ model: KeyboardModel) {
        model.type("n")
        model.type("i")
    }

    func testEnterCommitsCodeNotCandidate() {
        let (model, document) = makeModel()
        composeNi(model)
        XCTAssertEqual(model.preedit, "ni")
        XCTAssertFalse(model.candidates.isEmpty, "ni should produce candidates")

        model.enter()
        XCTAssertEqual(document.insertedText, "ni", "return commits the raw code")
        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.preedit, "")
    }

    func testSpaceCommitsSelectedCandidate() {
        let (model, document) = makeModel()
        composeNi(model)
        let expected = model.candidates[model.selectedIndex].text
        XCTAssertNotEqual(expected, "ni")

        model.space()
        XCTAssertEqual(document.insertedText, expected, "space commits the selected candidate")
        XCTAssertFalse(model.isComposing)
    }

    func testEnterWhenIdleInsertsNewline() {
        let (model, document) = makeModel()
        model.enter()
        XCTAssertEqual(document.insertedText, "\n")
    }

    func testShiftIntoInlineKeepsPreeditVisible() {
        let (model, document) = makeModel()
        model.type("h")
        XCTAssertEqual(model.preedit, "h")

        model.shifted = true
        model.type("j")

        XCTAssertEqual(model.preedit, "hJ", "the code must stay visible in inline mode")
        XCTAssertTrue(model.candidates.isEmpty, "inline mode has no candidates")
        XCTAssertEqual(document.insertedText, "", "nothing committed yet")
        XCTAssertTrue(model.isComposing)

        model.enter()
        XCTAssertEqual(document.insertedText, "hJ")
    }

    func testShiftIsConsumedByOneKey() {
        let (model, _) = makeModel()
        model.shifted = true
        model.type("h")
        XCTAssertFalse(model.shifted)
    }

    func testEverySymbolKeyInsertsItsOwnLabel() {
        for row in KeyboardLayout.numbers + KeyboardLayout.symbols {
            for key in row {
                let (model, document) = makeModel()
                model.insertSymbol(key)
                XCTAssertEqual(document.insertedText, key, "symbol key \(key) was rewritten")
                XCTAssertFalse(model.isComposing, "symbol key \(key) must not start a composition")
            }
        }
    }

    func testSemicolonSymbolKeyDoesNotStartComposition() {
        let (model, document) = makeModel()
        model.insertSymbol(";")
        XCTAssertEqual(document.insertedText, ";")
        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.preedit, "")
    }

    func testSymbolKeyWhileComposingCommitsCodeFirst() {
        let (model, document) = makeModel()
        composeNi(model)
        model.insertSymbol("。")
        XCTAssertEqual(document.insertedText, "ni。")
        XCTAssertFalse(model.isComposing)
    }

    func testReverseLookupKeyWhenIdleInsertsBacktick() {
        let (model, document) = makeModel()
        model.inputReverseLookup()
        XCTAssertEqual(document.insertedText, "`")
    }

    func testReverseLookupKeyWhileComposingAppendsToCode() {
        let (model, document) = makeModel()
        model.type("n")
        model.inputReverseLookup()
        XCTAssertEqual(document.insertedText, "", "nothing should be committed while composing")
        XCTAssertTrue(model.preedit.contains("`"), "the code should carry `, preedit=\(model.preedit)")
    }

    func testReverseLookupUsesSelectedText() {
        let (withSelection, _) = makeModel(selectedText: "你")
        for letter in ["o", "f", "i"] { withSelection.type(letter) }
        XCTAssertEqual(withSelection.preedit, "ofi")
        XCTAssertFalse(withSelection.candidates.isEmpty, "ofi should return the code for the selection")

        let (withoutSelection, _) = makeModel()
        for letter in ["o", "f", "i"] { withoutSelection.type(letter) }
        XCTAssertNotEqual(
            withSelection.candidates.map(\.text),
            withoutSelection.candidates.map(\.text),
            "the selection never reached the core"
        )
    }

    func testSelectCandidateUsesCoreIndex() {
        let (model, document) = makeModel()
        model.type("n")
        guard model.candidates.count > 1 else { return XCTFail("n should produce several candidates") }
        let second = model.candidates[1]
        model.selectCandidate(second.id)
        XCTAssertEqual(document.insertedText, second.text)
    }

    func testSemicolonSelectsSecondCandidateWhileComposing() {
        let (model, document) = makeModel()
        model.type("n")
        guard model.candidates.count > 1 else { return XCTFail("n should produce several candidates") }
        let second = model.candidates[1].text

        model.type(";")
        XCTAssertEqual(document.insertedText, second, "; commits the second candidate")
        XCTAssertFalse(model.isComposing)
    }

    func testSemicolonWhenIdleStartsFastSymbolSequence() {
        let (model, document) = makeModel()
        model.type(";")
        XCTAssertEqual(document.insertedText, "")
        XCTAssertEqual(model.preedit, ";")
        XCTAssertTrue(model.isComposing)
    }

    func testSelectCandidateIgnoresUnknownIndex() {
        let (model, document) = makeModel()
        composeNi(model)
        model.selectCandidate(9999)
        XCTAssertEqual(document.insertedText, "")
        XCTAssertTrue(model.isComposing)
    }

    func testActionHintsAreFiltered() {
        let (model, _) = makeModel()
        model.type("g")
        model.type("i")
        model.type("t")
        XCTAssertEqual(model.preedit, "git")
        XCTAssertTrue(model.candidates.isEmpty, "the add-entry hint must not appear as a candidate")
    }

    func testUserDictionaryLoadsAndOnlyReloadsForANewFingerprint() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xnheime-ios-dictionary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "自造词\tzzzz\n".write(
            to: directory.appendingPathComponent("flypy_top.txt"),
            atomically: true,
            encoding: .utf8
        )

        let (model, _) = makeModel()
        let first = await model.reloadUserDictionaryInBackground(
            from: directory,
            fingerprint: "one"
        )
        XCTAssertEqual(first?.loadedEntries, 1)
        let unchanged = await model.reloadUserDictionaryInBackground(
            from: directory,
            fingerprint: "one"
        )
        XCTAssertNil(unchanged)

        for letter in ["z", "z", "z", "z"] { model.type(letter) }
        XCTAssertTrue(model.candidates.map(\.text).contains("自造词"))
    }

    func testUserDictionaryReloadClearsEntriesAfterAFileIsDeleted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xnheime-ios-dictionary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = directory.appendingPathComponent("flypy_top.txt")
        try "自造词\tzzzz\n".write(to: dictionary, atomically: true, encoding: .utf8)

        let (model, _) = makeModel()
        let present = await model.reloadUserDictionaryInBackground(
            from: directory,
            fingerprint: "present"
        )
        XCTAssertEqual(present?.loadedEntries, 1)
        try FileManager.default.removeItem(at: dictionary)
        let absent = await model.reloadUserDictionaryInBackground(
            from: directory,
            fingerprint: "absent"
        )
        XCTAssertEqual(absent?.loadedEntries, 0)

        for letter in ["z", "z", "z", "z"] { model.type(letter) }
        XCTAssertFalse(model.candidates.map(\.text).contains("自造词"))
    }

    func testBackspaceWhileComposingShortensCode() {
        let (model, document) = makeModel()
        composeNi(model)
        model.backspace()
        XCTAssertEqual(model.preedit, "n")
        XCTAssertEqual(document.deleteCount, 0, "backspace while composing must not touch the document")
    }

    func testBackspaceWhenIdleDeletesFromDocument() {
        let (model, document) = makeModel(text: "abc")
        model.backspace()
        XCTAssertEqual(document.deleteCount, 1)
        XCTAssertEqual(document.documentContextBeforeInput, "ab")
    }

    func testDeleteWordBackwardHandlesTextBoundaries() {
        let cases: [(String, Int)] = [
            ("hello world", 5),
            ("hello world ", 6),
            ("internationalization", 20),
            ("foo   ", 6),
            ("a", 1),
            ("", 1),
            ("你好世界", 2),
            ("我今天很开心", 2),
            ("你好，", 1),
            ("测试。。。", 1),
            ("中文 world", 5),
            ("hi 👋", 1),
            ("第一行\n", 2),
        ]
        for (input, expected) in cases {
            let (model, document) = makeModel(text: input)
            model.deleteWordBackward()
            XCTAssertEqual(document.deleteCount, expected, "input \(input.debugDescription)")
            XCTAssertEqual(document.text, String(input.dropLast(min(expected, input.count))))
        }
    }

    func testDeleteWordBackwardWhileComposingStaysPerCode() {
        let (model, document) = makeModel()
        composeNi(model)
        model.deleteWordBackward()
        XCTAssertEqual(model.preedit, "n", "no word deletion while composing")
        XCTAssertEqual(document.deleteCount, 0)
    }

    func testDeleteWordBackwardDeletesOneWord() {
        let (model, document) = makeModel(text: "hello world")
        model.deleteWordBackward()
        XCTAssertEqual(document.deleteCount, 5)
        XCTAssertEqual(document.documentContextBeforeInput, "hello ")
    }

    func testNextKeyboardAdvancesInputMode() {
        let (model, document) = makeModel()
        model.nextKeyboard()
        XCTAssertEqual(document.advanceCount, 1)
    }

    func testMergedKeyOffersBothReadings() {
        let (model, _) = makeModel()
        model.type("bn")
        model.type("i")
        XCTAssertEqual(model.candidates.map(\.text), ["比", "你"])
        XCTAssertEqual(model.candidates.compactMap(\.code), ["bi", "ni"])
    }

    func testCandidatesLoadInPagesWithoutDuplicatesOrOmissions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xnheime-ios-paging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entries = (0..<60).map { "分页词\($0)\tzzzz" }.joined(separator: "\n")
        try entries.write(
            to: directory.appendingPathComponent("flypy_top.txt"),
            atomically: true,
            encoding: .utf8
        )

        let (model, _) = makeModel()
        let loaded = await model.reloadUserDictionaryInBackground(
            from: directory,
            fingerprint: "paging"
        )
        XCTAssertEqual(loaded?.loadedEntries, 60)
        for letter in ["z", "z", "z", "z"] { model.type(letter) }
        XCTAssertLessThan(model.candidates.count, 60)
        XCTAssertTrue(model.candidateState.hasMore)
        XCTAssertTrue(model.candidateState.canExpand)

        let initialCount = model.candidates.count
        while model.candidateState.hasMore { model.loadMoreCandidates() }
        XCTAssertGreaterThan(model.candidates.count, initialCount)
        let texts = Set(model.candidates.map(\.text))
        let imported = Set((0..<60).map { "分页词\($0)" })
        XCTAssertEqual(texts.count, model.candidates.count)
        XCTAssertTrue(imported.isSubset(of: texts))
        XCTAssertFalse(model.candidateState.hasMore)
    }

    func testWeightedMergedKeyPrefersTheCloserLetter() {
        let (model, _) = makeModel()
        model.type("bn", primaryWeight: 100)
        model.type("i")
        XCTAssertEqual(model.candidates.first?.code, "ni")
        XCTAssertTrue(model.candidates.contains(where: { $0.code == "bi" }))
    }

    func testSwipeResolvedKeyNarrowsTheCandidates() {
        let (model, _) = makeModel()
        model.type("w")
        model.type("op")
        XCTAssertEqual(model.candidates.first?.text, "我")
        XCTAssertEqual(model.candidates.first?.code, "wo")
    }

    func testPreeditShowsTheCodeOfTheSelectedCandidate() {
        let (model, _) = makeModel()
        model.type("qw")
        model.type("op")
        let first = model.candidates[model.selectedIndex]
        XCTAssertEqual(model.preedit, first.code)
        XCTAssertNotEqual(model.preedit, "qo0")
    }

    func testMergedKeyIsUnambiguousAfterShift() {
        let (model, document) = makeModel()
        model.shifted = true
        model.type("qw")
        XCTAssertFalse(model.shifted)
        XCTAssertEqual(document.insertedText, "Q")
    }

    func testSwipeThresholdPicksTheLetterOnThatSide() {
        let threshold = MergedKey.swipeThreshold
        XCTAssertNil(fuzzy(dx: 0))
        XCTAssertNil(fuzzy(dx: threshold - 1))
        XCTAssertNil(fuzzy(dx: -(threshold - 1)))
        XCTAssertEqual(fuzzy(dx: -threshold), "q")
        XCTAssertEqual(fuzzy(dx: threshold), "w")
        XCTAssertNil(
            MergedKey.resolution(ofDrag: CGSize(width: threshold, height: 0), in: "u", mode: .fuzzy)
        )
    }

    /// A vertical swipe is not a side, so the fuzzy layout ignores it.
    func testFuzzyModeOnlyReadsHorizontalSwipes() {
        XCTAssertNil(fuzzy(dy: MergedKey.swipeThreshold * 4))
        XCTAssertNil(fuzzy(dy: -MergedKey.swipeThreshold * 4))
    }

    func testPrimaryModeTapPicksTheLeftLetter() {
        XCTAssertEqual(primary(dx: 0), "q")
        let inside = MergedKey.swipeThreshold - 1
        XCTAssertEqual(primary(dx: inside), "q")
        XCTAssertEqual(primary(dx: -inside), "q")
        XCTAssertEqual(primary(dy: inside), "q")
    }

    func testPrimaryModeSwipePicksTheRightLetterInEveryDirectionButLeft() {
        let threshold = MergedKey.swipeThreshold
        for translation in [
            CGSize(width: threshold, height: 0),
            CGSize(width: 0, height: threshold),
            CGSize(width: 0, height: -threshold),
            CGSize(width: threshold, height: threshold),
            CGSize(width: threshold, height: -threshold),
        ] {
            XCTAssertEqual(
                MergedKey.resolution(ofDrag: translation, in: "qw", mode: .primary),
                "w",
                "swipe \(translation) should mean the right letter"
            )
        }
    }

    /// Left means the left letter in both modes, so the gesture does not reverse
    /// itself when the layout changes.
    func testPrimaryModeLeftSwipeStillPicksTheLeftLetter() {
        let threshold = MergedKey.swipeThreshold
        XCTAssertEqual(primary(dx: -threshold), "q")
        XCTAssertEqual(primary(dx: -threshold * 4), "q")
        XCTAssertEqual(fuzzy(dx: -threshold), "q")
    }

    /// The horizontal component has to dominate, or a downward flick that drifted
    /// sideways would read as a deliberate left swipe.
    func testPrimaryModeIgnoresSidewaysDriftOnAVerticalFlick() {
        let threshold = MergedKey.swipeThreshold
        XCTAssertEqual(
            MergedKey.resolution(
                ofDrag: CGSize(width: -threshold * 1.5, height: threshold * 3),
                in: "qw",
                mode: .primary
            ),
            "w",
            "mostly downward, so not a left swipe"
        )
        XCTAssertEqual(
            MergedKey.resolution(
                ofDrag: CGSize(width: -threshold * 3, height: threshold * 1.5),
                in: "qw",
                mode: .primary
            ),
            "q",
            "mostly leftward, so still the left letter"
        )
    }

    /// Diagonals count by distance, so a drag that clears neither axis alone still
    /// resolves once the finger has travelled far enough.
    func testPrimaryModeMeasuresDiagonalDistance() {
        // Neither axis clears the threshold on its own.
        let almost = MergedKey.swipeThreshold * 0.8
        XCTAssertEqual(
            MergedKey.resolution(
                ofDrag: CGSize(width: almost, height: almost),
                in: "qw",
                mode: .primary
            ),
            "w"
        )
        XCTAssertLessThan(almost, MergedKey.swipeThreshold)
    }

    func testPrimaryModeLeavesSingleLetterKeysAlone() {
        let far = CGSize(width: MergedKey.swipeThreshold * 4, height: 0)
        XCTAssertNil(MergedKey.resolution(ofDrag: far, in: "u", mode: .primary))
    }

    /// 主次 mode resolves every key, so its candidates are as tight as on 26 keys:
    /// tapping op after swiping qw means "wo" and nothing else.
    func testPrimaryModeKeystrokesAreNeverAmbiguous() {
        let (definite, _) = makeModel()
        definite.type("w")
        definite.type("o")
        XCTAssertEqual(definite.candidates.map(\.text), ["我"])
        XCTAssertEqual(definite.preedit, "wo")
        // Nothing to tell apart, so no candidate carries a code.
        XCTAssertEqual(definite.candidates.compactMap(\.code), [])

        let (fuzzy, _) = makeModel()
        fuzzy.type("qw")
        fuzzy.type("op")
        XCTAssertEqual(fuzzy.candidates.compactMap(\.code), ["qo", "qp", "wo", "wp"])
    }

    private func fuzzy(dx: CGFloat = 0, dy: CGFloat = 0) -> String? {
        MergedKey.resolution(ofDrag: CGSize(width: dx, height: dy), in: "qw", mode: .fuzzy)
    }

    private func primary(dx: CGFloat = 0, dy: CGFloat = 0) -> String? {
        MergedKey.resolution(ofDrag: CGSize(width: dx, height: dy), in: "qw", mode: .primary)
    }

    func testLetterLayoutPersistsAcrossModels() {
        let (first, _) = makeModel()
        XCTAssertEqual(first.letterLayout, .full26)
        first.letterLayout = .merged17

        let (second, _) = makeModel()
        XCTAssertEqual(second.letterLayout, .merged17)
        second.letterLayout = .merged17Primary

        let (third, _) = makeModel()
        XCTAssertEqual(third.letterLayout, .merged17Primary)
    }
}
