import UIKit
import XCTest

final class KeyboardLayoutTests: XCTestCase {
    /// iPhone 17 Pro portrait, measured from the system pinyin keyboard.
    private let width: CGFloat = 402

    private func layout(width: CGFloat = 402, metrics: KeyboardMetrics = KeyboardMetrics()) -> RowLayout {
        RowLayout(width: width, metrics: metrics)
    }

    func testKeyWidthsOnIPhone() {
        let l = layout()
        XCTAssertEqual(l.keyWidth, 34)
        XCTAssertEqual(l.specialWidth, 43)
        XCTAssertEqual(l.insetWidth(count: 6), 42)
        XCTAssertEqual(l.returnWidth, 74)
        XCTAssertEqual(l.semicolonWidth, 34)
        XCTAssertEqual(l.numWidth, 44)
    }

    func testRowsFitContentWidth() {
        for width in stride(from: 320.0, through: 1024.0, by: 1.0) {
            let metrics = KeyboardMetrics()
            let l = layout(width: width, metrics: metrics)
            let content = width - metrics.sideMargin * 2

            let topRow = l.keyWidth * 10 + metrics.keyGap * 9
            XCTAssertLessThanOrEqual(topRow, content, "rows 1-2 overflow at width=\(width)")

            let letterThird = l.specialWidth * 2 + metrics.keyGap * 2
                + l.keyWidth * 7 + metrics.keyGap * 6
            XCTAssertLessThanOrEqual(letterThird, content, "letter row 3 overflows at width=\(width)")

            let symbolThird = l.specialWidth * 2 + metrics.keyGap * 2
                + l.insetWidth(count: 6) * 6 + metrics.keyGap * 5
            XCTAssertLessThanOrEqual(symbolThird, content, "symbol row 3 overflows at width=\(width)")

            let bottom = l.numWidth * 2 + l.semicolonWidth + l.returnWidth + metrics.keyGap * 4
            XCTAssertLessThan(bottom, content, "no room for the space bar at width=\(width)")
        }
    }

    func testLabelsAreUniqueWithinEachRow() {
        for (name, page) in [
            ("letters", KeyboardLayout.letters),
            ("mergedLetters", KeyboardLayout.mergedLetters),
            ("numbers", KeyboardLayout.numbers),
            ("symbols", KeyboardLayout.symbols),
        ] {
            for (index, row) in page.enumerated() {
                XCTAssertEqual(
                    Set(row).count,
                    row.count,
                    "\(name) row \(index + 1) has duplicate labels: \(row)"
                )
            }
        }
    }

    func testStandardPagesMatchTheirLayoutContract() {
        XCTAssertEqual(KeyboardLayout.letters.count, 3)
        XCTAssertEqual(KeyboardLayout.numbers.count, 3)
        XCTAssertEqual(KeyboardLayout.symbols.count, 3)
        XCTAssertEqual(KeyboardLayout.letters.map(\.count), [10, 9, 7])
        XCTAssertEqual(KeyboardLayout.numbers.map(\.count), [10, 10, 6])
        XCTAssertEqual(KeyboardLayout.symbols.map(\.count), [10, 10, 6])
        XCTAssertEqual(KeyboardLayout.letters[1].last, "l")
    }

    func testMergedRowsCoverEveryLetterExactlyOnce() {
        let letters = KeyboardLayout.mergedLetters
            .flatMap { $0 }
            .filter { $0 != ";" }
        XCTAssertEqual(letters.count, 17, "17 keys carry the alphabet")
        let alphabet = letters.joined().sorted()
        XCTAssertEqual(String(alphabet), "abcdefghijklmnopqrstuvwxyz")
    }

    func testMergedGroupsMatchCloverAlgebra() {
        XCTAssertEqual(
            KeyboardLayout.mergedLetters.flatMap { $0 }.filter { $0 != ";" && $0.count == 1 },
            ["u", "i", "g", "h", "l", "c", "v", "m"],
            "clover keeps sh/ch/zh, eng/ang and iang/uang unambiguous"
        )
    }

    func testMergedRowLengths() {
        XCTAssertEqual(KeyboardLayout.mergedLetters.map(\.count), [6, 6, 5])
        XCTAssertEqual(KeyboardLayout.mergedLetters[1].last, "l")
    }

    func testBothMergedLayoutsShareTheSameRows() {
        XCTAssertEqual(
            KeyboardLayout.letterRows(for: .merged17Primary),
            KeyboardLayout.letterRows(for: .merged17),
            "the 主次 layout only changes what a key does, not where it sits"
        )
        XCTAssertEqual(KeyboardLayout.letterRows(for: .full26), KeyboardLayout.letters)
    }

    func testLetterLayoutModes() {
        XCTAssertNil(LetterLayout.full26.mergedKeyMode)
        XCTAssertEqual(LetterLayout.merged17.mergedKeyMode, .fuzzy)
        XCTAssertEqual(LetterLayout.merged17Primary.mergedKeyMode, .primary)
    }

    func testLayoutTitlesAreDistinct() {
        let titles = LetterLayout.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testEveryLayoutHasADescription() {
        XCTAssertTrue(LetterLayout.allCases.allSatisfy { !$0.description.isEmpty })
    }

    /// The stored value is a raw string, so renaming a case would silently reset
    /// everyone's choice.
    func testLayoutRawValuesAreStable() {
        XCTAssertEqual(
            LetterLayout.allCases.map(\.rawValue),
            ["full26", "merged17", "merged17Primary"]
        )
    }

    func testMergedKeysSpanTheirOriginalSlots() {
        let l = layout()
        let metrics = KeyboardMetrics()
        XCTAssertEqual(l.letterWidth(for: "u"), l.keyWidth)
        XCTAssertEqual(l.letterWidth(for: "qw"), l.keyWidth * 2 + metrics.keyGap)
    }

    func testMergedRowsEnlargeSingleKeysByAQuarter() {
        let l = layout()
        for row in KeyboardLayout.mergedLetters {
            let widths = l.letterWidths(for: row)
            for (key, width) in zip(row, widths) where key.count == 1 {
                XCTAssertEqual(width, l.keyWidth * 1.25)
            }
        }
    }

    func testMergedKeyTouchWeightTracksItsOriginal26KeySlots() {
        let width: CGFloat = 74
        XCTAssertGreaterThan(MergedKey.primaryWeight(at: width * 0.25, width: width), 800)
        XCTAssertEqual(MergedKey.primaryWeight(at: width * 0.5, width: width), 500)
        XCTAssertLessThan(MergedKey.primaryWeight(at: width * 0.75, width: width), 200)
    }

    func testMergedKeyCalloutOpacityTracksTouchWeight() {
        XCTAssertEqual(MergedKey.calloutOpacity(primaryWeight: 500, index: 0), 1)
        XCTAssertEqual(MergedKey.calloutOpacity(primaryWeight: 500, index: 1), 1)
        XCTAssertEqual(MergedKey.calloutOpacity(primaryWeight: 900, index: 0), 1)
        XCTAssertLessThan(MergedKey.calloutOpacity(primaryWeight: 900, index: 1), 0.5)
        XCTAssertEqual(
            MergedKey.calloutOpacity(primaryWeight: 900, index: 1),
            MergedKey.calloutOpacity(primaryWeight: 100, index: 0)
        )
    }

    func testMergedKeyCalloutSizeTracksTouchWeight() {
        XCTAssertEqual(MergedKey.calloutFontOffset(primaryWeight: 500, index: 0), 0)
        XCTAssertGreaterThan(MergedKey.calloutFontOffset(primaryWeight: 900, index: 0), 0)
        XCTAssertLessThan(MergedKey.calloutFontOffset(primaryWeight: 900, index: 1), 0)
    }

    func testMergedRowsFitContentWidth() {
        for width in stride(from: 320.0, through: 1024.0, by: 1.0) {
            let metrics = KeyboardMetrics()
            let l = layout(width: width, metrics: metrics)
            let content = width - metrics.sideMargin * 2
            for row in KeyboardLayout.mergedLetters.prefix(2) {
                let filled = l.letterWidths(for: row).reduce(0, +)
                    + metrics.keyGap * CGFloat(row.count - 1)
                XCTAssertLessThanOrEqual(filled, content, "merged row overflows at \(width)")
            }
            let third = KeyboardLayout.mergedLetters[2]
            let row = l.specialWidth * 2 + metrics.keyGap * 2
                + l.letterWidths(for: third).reduce(0, +)
                + metrics.keyGap * CGFloat(third.count - 1)
            XCTAssertLessThanOrEqual(row, content, "merged row 3 overflows at \(width)")
        }
    }

    func testMergedRowsBorrowGrowthExceptAtTrailingLM() {
        let metrics = KeyboardMetrics()
        let l = layout(metrics: metrics)

        for (fullRow, mergedRow) in zip(KeyboardLayout.letters, KeyboardLayout.mergedLetters) {
            let fullWidth = fullRow.map(l.letterWidth).reduce(0, +)
                + metrics.keyGap * CGFloat(fullRow.count - 1)
            let mergedWidth = l.letterWidths(for: mergedRow).reduce(0, +)
                + metrics.keyGap * CGFloat(mergedRow.count - 1)
            let trailingGrowth: CGFloat = ["l", "m"].contains(mergedRow.last ?? "")
                ? l.keyWidth * 0.25
                : 0
            XCTAssertEqual(mergedWidth, fullWidth + trailingGrowth, accuracy: 0.001)
        }
    }

    private static let phoneMetrics = KeyboardMetrics.resolve(
        traits: UITraitCollection(mutations: { _ in })
    )
    private static let landscapeMetrics = KeyboardMetrics.resolve(
        traits: UITraitCollection(mutations: { $0.verticalSizeClass = .compact })
    )
    private static let padMetrics = KeyboardMetrics.resolve(
        traits: UITraitCollection(mutations: { $0.userInterfaceIdiom = .pad })
    )
    private static let metricVariants: [(String, KeyboardMetrics)] = [
        ("phone", phoneMetrics),
        ("landscape", landscapeMetrics),
        ("pad", padMetrics),
    ]

    /// Measured from the system pinyin keyboard on a 402pt-wide iPhone: two clean key
    /// faces both 43.0pt tall, 11.7pt apart.
    func testKeyHeightMatchesTheSystemKeyboard() {
        XCTAssertEqual(Self.phoneMetrics.keyHeight, 43)
        XCTAssertEqual(Self.phoneMetrics.rowGap, 12)
    }

    func testMergedLettersAreOffInLandscape() {
        XCTAssertTrue(Self.phoneMetrics.allowsMergedLetters)
        XCTAssertFalse(
            Self.landscapeMetrics.allowsMergedLetters,
            "landscape keys are already wide, so merging them buys nothing"
        )
    }

    /// The picker hangs above the bottom row, so every layout it offers has to fit
    /// in what is left of the keyboard.
    func testLayoutPickerFitsAboveTheBottomRow() {
        for (name, metrics) in Self.metricVariants {
            let layouts = LetterLayout.available(
                allowsMergedLetters: metrics.allowsMergedLetters
            )
            let picker = metrics.keyHeight * CGFloat(layouts.count)
            XCTAssertLessThanOrEqual(
                picker + metrics.bottomRowClearance,
                metrics.keyboardHeight,
                "the layout picker is clipped on \(name)"
            )
        }
    }

    func testCalloutStaysInsideTheKeyboardAndClearsItsKey() {
        for (name, metrics) in Self.metricVariants {
            let headroom = metrics.candidateBarHeight + metrics.topPadding
            XCTAssertLessThanOrEqual(
                metrics.calloutLift,
                headroom,
                "callout clipped by the keyboard top on \(name)"
            )
            XCTAssertGreaterThanOrEqual(
                metrics.calloutLift - metrics.calloutHeight,
                1,
                "callout overlaps its own key on \(name)"
            )
            XCTAssertGreaterThan(metrics.calloutHeight, 0, "empty callout on \(name)")
        }
    }

    func testCalloutIsLargerThanTheKeyItPreviews() {
        let metrics = Self.phoneMetrics
        XCTAssertEqual(metrics.calloutHeight, 48)
        XCTAssertGreaterThan(metrics.calloutHeight, metrics.keyHeight)

        let l = layout()
        let mergedKeyWidth = l.letterWidth(for: "qw")
        let calloutWidth = (mergedKeyWidth * MergedKey.calloutWidthRatio).rounded()
        XCTAssertEqual(calloutWidth, 96)
        // The widened callout must still fit between the row's end and the keyboard edge.
        XCTAssertLessThanOrEqual(calloutWidth, 402 - KeyboardMetrics().sideMargin * 2)
    }

    func testCalloutAnchorsHugTheRowEnds() {
        let row = KeyboardLayout.mergedLetters[0]
        XCTAssertEqual(CalloutAnchor.forKey(at: 0, of: row.count), .leading)
        XCTAssertEqual(CalloutAnchor.forKey(at: row.count - 1, of: row.count), .trailing)
        XCTAssertEqual(CalloutAnchor.forKey(at: 2, of: row.count), .center)
    }

    // MARK: - Symbol alternates

    private var symbolPages: [(String, [[String]])] {
        [("numbers", KeyboardLayout.numbers), ("symbols", KeyboardLayout.symbols)]
    }

    func testAlternateTableOnlyCoversKeysThatExist() {
        let onPages = Set(symbolPages.flatMap { $0.1 }.flatMap { $0 })
        for page in symbolPages {
            for row in page.1 {
                for key in row {
                    let options = SymbolAlternates.options(for: key)
                    XCTAssertEqual(options.first, key, "\(key) must insert itself on a tap")
                    XCTAssertLessThanOrEqual(
                        options.count,
                        SymbolAlternates.maximumOptions,
                        "\(key) has more options than a row can hold"
                    )
                    XCTAssertEqual(Set(options).count, options.count, "\(key) repeats an option")
                }
            }
        }
        // Nothing in the table should be unreachable.
        for key in ["¥", "《", "…", "。", "\u{201C}"] {
            XCTAssertTrue(onPages.contains(key), "\(key) is in the table but on no page")
        }
    }

    func testHalfwidthAndFullwidthPairsFollowUnicode() {
        // U+FF01...U+FF5E are the fullwidth forms of ASCII 0x21...0x7E.
        for key in ["-", "/", ":", ";", "(", ")", "@", "#", "%", "^", "*", "+", "=",
                    "_", "\\", "|", "~", "$", "&", "{", "}", "."] {
            let scalar = key.unicodeScalars.first!.value
            let fullwidth = String(UnicodeScalar(scalar + 0xFEE0)!)
            XCTAssertTrue(
                SymbolAlternates.options(for: key).contains(fullwidth),
                "\(key) should offer its fullwidth form \(fullwidth)"
            )
        }
        // U+FFE5 is the fullwidth yen, outside the ASCII block.
        XCTAssertTrue(SymbolAlternates.options(for: "¥").contains("\u{FFE5}"))
    }

    func testFullwidthPunctuationOffersItsHalfwidthCounterpart() {
        for (fullwidth, halfwidth) in [
            ("。", "."), ("，", ","), ("？", "?"), ("！", "!"),
            ("【", "["), ("】", "]"), ("《", "<"), ("》", ">"),
            ("\u{201C}", "\""), ("\u{2019}", "'"), ("—", "-"),
        ] {
            XCTAssertTrue(
                SymbolAlternates.options(for: fullwidth).contains(halfwidth),
                "\(fullwidth) should offer \(halfwidth)"
            )
        }
    }

    func testSemicolonKeepsItsLetterPageMeaning() {
        // ; is 次选 on the letter page and a plain symbol on the numbers page, so the
        // table must not change what a tap inserts.
        XCTAssertEqual(SymbolAlternates.options(for: ";").first, ";")
    }

    func testEveryKeyHasRoomForItsOptions() {
        for (name, page) in symbolPages {
            for (rowIndex, row) in page.enumerated() {
                for (index, key) in row.enumerated() {
                    let options = SymbolAlternates.options(for: key).count
                    let capacity = max(index, row.count - 1 - index) + 1
                    XCTAssertLessThanOrEqual(
                        options,
                        capacity,
                        """
                        \(name) row \(rowIndex + 1): \(key) sits at index \(index) of \
                        \(row.count), so it has room for \(capacity) options, not \(options)
                        """
                    )
                }
            }
        }
    }

    func testCurrencyKeysShareTheSameAlternates() {
        XCTAssertEqual(
            SymbolAlternates.options(for: "¥"),
            ["¥", "\u{FFE5}", "$", "＄", "€", "£", "₩"]
        )
        XCTAssertEqual(
            SymbolAlternates.options(for: "$"),
            ["$", "＄", "¥", "\u{FFE5}", "€", "£", "₩"]
        )
        // Both width pairs are in each row, so both fullwidth forms get marked.
        let yen = SymbolAlternates.options(for: "¥")
        XCTAssertEqual(SymbolWidth.badge(for: "\u{FFE5}", among: yen), "全")
        XCTAssertEqual(SymbolWidth.badge(for: "＄", among: yen), "全")
        XCTAssertNil(SymbolWidth.badge(for: "€", among: yen))
    }

    func testAlternatesRowNeverLeavesTheKeyboard() {
        for width in stride(from: 320.0, through: 1024.0, by: 1.0) {
            let metrics = KeyboardMetrics()
            let l = layout(width: width, metrics: metrics)

            for (name, page) in symbolPages {
                for (rowIndex, row) in page.enumerated() {
                    let inset = rowIndex == 2
                    let keyWidth = inset ? l.insetWidth(count: row.count) : l.keyWidth

                    for (index, key) in row.enumerated() {
                        let options = SymbolAlternates.options(for: key)
                        guard options.count > 1 else { continue }
                        let origin = l.keyOrigin(
                            index: index,
                            count: row.count,
                            keyWidth: keyWidth,
                            inset: inset
                        )
                        let right = SymbolAlternates.extendsRight(
                            index: index,
                            count: row.count,
                            options: options.count,
                            keyWidth: keyWidth,
                            gap: metrics.keyGap
                        )
                        let span = keyWidth * CGFloat(options.count)
                        let leading = SymbolAlternates.rowLeading(
                            keyOrigin: origin,
                            keyWidth: keyWidth,
                            options: options.count,
                            extendsRight: right,
                            contentWidth: l.contentWidth
                        )
                        let where_ = "\(name) row \(rowIndex + 1) key \(key) at width \(width)"
                        XCTAssertGreaterThanOrEqual(leading, -0.5, "\(where_) runs off the left")
                        XCTAssertLessThanOrEqual(
                            leading + span,
                            l.contentWidth + 0.5,
                            "\(where_) runs off the right"
                        )
                        XCTAssertEqual(
                            leading,
                            right ? origin : origin + keyWidth - span,
                            accuracy: 0.5,
                            "\(where_) had to be clamped, so its options no longer line up"
                        )
                    }
                }
            }
        }
    }

    func testQuoteKeysOfferCornerBrackets() {
        XCTAssertEqual(
            SymbolAlternates.options(for: "\u{201C}"),
            ["\u{201C}", "「", "『", "\"", "＂"]
        )
        XCTAssertEqual(
            SymbolAlternates.options(for: "\u{201D}"),
            ["\u{201D}", "」", "』", "\"", "＂"]
        )
    }

    func testBracketKeysOfferBothWidths() {
        XCTAssertEqual(SymbolAlternates.options(for: "【"), ["【", "[", "［", "〔"])
        XCTAssertEqual(SymbolAlternates.options(for: "】"), ["】", "]", "］", "〕"])
        XCTAssertEqual(SymbolAlternates.options(for: "《"), ["《", "<", "＜", "〈"])
        XCTAssertEqual(SymbolAlternates.options(for: "》"), ["》", ">", "＞", "〉"])
    }

    func testSwipeSelectsCellsAwayFromTheKey() {
        let cell: CGFloat = 34
        XCTAssertEqual(
            SymbolAlternates.selection(ofSwipe: 0, options: 3, cellWidth: cell, extendsRight: true),
            0
        )
        XCTAssertEqual(
            SymbolAlternates.selection(
                ofSwipe: cell, options: 3, cellWidth: cell, extendsRight: true
            ),
            1
        )
        XCTAssertEqual(
            SymbolAlternates.selection(
                ofSwipe: cell * 9, options: 3, cellWidth: cell, extendsRight: true
            ),
            2,
            "selection clamps to the last option"
        )
        XCTAssertEqual(
            SymbolAlternates.selection(
                ofSwipe: -cell, options: 3, cellWidth: cell, extendsRight: true
            ),
            0,
            "dragging away from the row keeps the tapped option"
        )
        // A row that fans out to the left mirrors the gesture.
        XCTAssertEqual(
            SymbolAlternates.selection(
                ofSwipe: -cell, options: 3, cellWidth: cell, extendsRight: false
            ),
            1
        )
        XCTAssertEqual(
            SymbolAlternates.selection(
                ofSwipe: cell, options: 3, cellWidth: cell, extendsRight: false
            ),
            0
        )
        XCTAssertEqual(
            SymbolAlternates.selection(ofSwipe: 99, options: 1, cellWidth: cell, extendsRight: true),
            0,
            "a key with no alternates has nothing to select"
        )
    }

    func testFullwidthTwinsGetTheCornerMark() {
        func badge(_ option: String, ofKey key: String) -> String? {
            SymbolWidth.badge(for: option, among: SymbolAlternates.options(for: key))
        }
        XCTAssertEqual(badge("\u{FFE5}", ofKey: "¥"), "全")
        XCTAssertNil(badge("¥", ofKey: "¥"), "the halfwidth default stays unmarked")
        XCTAssertNil(badge("$", ofKey: "¥"), "no fullwidth dollar in that row to confuse it with")
        XCTAssertEqual(badge("＄", ofKey: "$"), "全")
        XCTAssertEqual(badge("－", ofKey: "-"), "全")
        XCTAssertNil(badge("—", ofKey: "-"), "an em dash is not a width variant")
        XCTAssertEqual(badge("．", ofKey: "."), "全")
        XCTAssertNil(badge("。", ofKey: "."), "a full stop is not a width variant")
    }

    func testHalfwidthTwinGetsTheOtherMark() {
        let options = SymbolAlternates.options(for: "、")
        XCTAssertEqual(SymbolWidth.badge(for: "\u{FF64}", among: options), "半")
        XCTAssertNil(SymbolWidth.badge(for: "、", among: options))
    }

    func testEveryFullwidthAsciiFormInARowIsMarked() {
        var marked: Set<String> = []
        for (name, page) in symbolPages {
            for row in page {
                for key in row {
                    let options = SymbolAlternates.options(for: key)
                    for option in options {
                        guard option.unicodeScalars.count == 1,
                              let scalar = option.unicodeScalars.first,
                              (0xFF01...0xFF5E).contains(scalar.value)
                        else { continue }
                        let narrow = String(UnicodeScalar(scalar.value - 0xFEE0)!)
                        guard options.contains(narrow) else { continue }
                        XCTAssertEqual(
                            SymbolWidth.badge(for: option, among: options),
                            "全",
                            "\(name): \(option) beside \(narrow) needs the mark"
                        )
                        marked.insert(key + option)
                    }
                }
            }
        }
        XCTAssertFalse(marked.isEmpty)
    }

    func testChinesePunctuationIsMarkedButCjkOnlyFormsAreNot() {
        // ，？！ are literally U+FF0C/FF1F/FF01, the fullwidth forms of , ? and !.
        for fullwidth in ["，", "？", "！"] {
            XCTAssertEqual(
                SymbolWidth.badge(for: fullwidth, among: SymbolAlternates.options(for: fullwidth)),
                "全"
            )
        }
        // 。 is U+3002, its own character rather than a width variant of a full stop.
        XCTAssertNil(
            SymbolWidth.badge(for: "。", among: SymbolAlternates.options(for: "。")),
            "。 and . look nothing alike, so no mark is needed"
        )
    }

    func testCharactersWithNoWidthTwinAreNeverMarked() {
        for text in ["。", "\u{201C}", "—", "〈", "•", "……", "×", "‰", "≠", "「"] {
            XCTAssertNil(
                SymbolWidth.badge(for: text, among: [text, "x"]),
                "\(text) has no width twin"
            )
        }
    }
}
