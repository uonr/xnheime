import CoreGraphics

enum KeyPage {
    case letters
    case numbers
    case symbols
}

enum LetterLayout: String, CaseIterable {
    case full26
    case merged17
    case merged17Primary

    var title: String {
        switch self {
        case .full26: "26 键"
        case .merged17: "17 键（模糊）"
        case .merged17Primary: "17 键（主次）"
        }
    }

    var description: String {
        switch self {
        case .full26: "标准 26 键布局"
        case .merged17: "合并部分按键，尽力猜测，也可滑动选择"
        case .merged17Primary: "合并部分按键，滑动选择次要按键"
        }
    }

    /// nil for the layouts whose keys each carry one letter.
    var mergedKeyMode: MergedKeyMode? {
        switch self {
        case .full26: nil
        case .merged17: .fuzzy
        case .merged17Primary: .primary
        }
    }

    static func available(allowsMergedLetters: Bool) -> [LetterLayout] {
        allowsMergedLetters ? allCases : [.full26]
    }
}

/// How a merged key reads the gesture that hit it.
enum MergedKeyMode {
    /// A horizontal swipe picks a side; a plain tap stays ambiguous and lets the
    /// engine weigh both letters.
    case fuzzy
    /// A tap or a leftward swipe means the left letter, a swipe in any other
    /// direction the right one. Never ambiguous, so the candidates are as tight as
    /// on 26 keys.
    case primary
}

enum KeyboardLayout {
    static let letters: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    /// Groups taken from clover_flypy_17's speller algebra, which keeps the
    /// zh/ch/sh initials and the eng/ang finals on keys of their own.
    static let mergedLetters: [[String]] = [
        ["qw", "er", "ty", "u", "i", "op"],
        ["as", "df", "g", "h", "jk", "l"],
        ["zx", "c", "v", "bn", "m"],
    ]

    static let numbers: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "¥", "@", "\u{201C}", "\u{201D}"],
        ["。", "，", "、", "？", "！", "."],
    ]

    static let symbols: [[String]] = [
        ["【", "】", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "—", "\\", "|", "~", "《", "》", "$", "&", "·"],
        // Single characters, following the system keyboard. Chinese prefers …… and ——.
        ["…", "，", "^_^", "？", "！", "\u{2019}"],
    ]

    static func letterRows(for layout: LetterLayout) -> [[String]] {
        layout.mergedKeyMode == nil ? letters : mergedLetters
    }

    static func rows(for page: KeyPage, layout: LetterLayout) -> [[String]] {
        switch page {
        case .letters: letterRows(for: layout)
        case .numbers: numbers
        case .symbols: symbols
        }
    }

    static var columns: Int { letters[0].count }
    static var rowCount: Int { letters.count + 1 }
}

enum IPadKeyboardLayout {
    static let letters: [[String]] = [
        KeyboardLayout.letters[0],
        KeyboardLayout.letters[1],
        KeyboardLayout.letters[2] + ["，", "。"],
    ]

    static let numbers: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["@", "#", "¥", "/", "(", ")", "“", "”", "’"],
        ["%", "-", "~", "…", "、", "；", "：", "！", "？"],
    ]

    static let symbols: [[String]] = [
        ["^", "_", "|", "\\", "<", ">", "{", "}", "，", "。"],
        ["&", "$", "€", "*", "【", "】", "「", "」", "•"],
        ["^_^", "—", "+", "=", "·", "《", "》", "！", "？"],
    ]

    static func rows(for page: KeyPage) -> [[String]] {
        switch page {
        case .letters: letters
        case .numbers: numbers
        case .symbols: symbols
        }
    }
}

enum CalloutAnchor {
    case leading
    case center
    case trailing

    /// Rows one and two span the whole width, so a callout wider than its key has
    /// to hug the row's end instead of centring.
    static func forKey(at index: Int, of count: Int) -> CalloutAnchor {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }
}

enum MergedKey {
    static let swipeThreshold: CGFloat = 12
    static let calloutWidthRatio: CGFloat = 1.3

    /// Likelihood of the left letter based on the initial contact position. A
    /// smooth curve keeps the centre ambiguous while strongly favouring the
    /// original 26-key slot beneath the finger.
    static func primaryWeight(at x: CGFloat, width: CGFloat) -> UInt16 {
        guard width > 0 else { return 500 }
        let normalized = min(max(x / width, 0), 1)
        let probability = 1 / (1 + exp(Double(normalized - 0.5) * 8))
        return UInt16((probability * 1000).rounded()).clamped(to: 1...999)
    }

    static func calloutOpacity(primaryWeight: UInt16, index: Int) -> CGFloat {
        let leftWeight = CGFloat(primaryWeight) / 1000
        let weight = index == 0 ? leftWeight : 1 - leftWeight
        let otherWeight = 1 - weight
        guard weight < otherWeight else { return 1 }
        let confidence = min(abs(leftWeight - 0.5) * 2, 1)
        return 1 - confidence * 0.7
    }

    static func calloutFontOffset(primaryWeight: UInt16, index: Int) -> CGFloat {
        let leftBias = (CGFloat(primaryWeight) - 500) / 500
        return (index == 0 ? leftBias : -leftBias) * 4
    }

    /// Which of a merged key's letters a drag picks, or nil to leave the keystroke
    /// ambiguous. Single-letter keys have nothing to resolve.
    static func resolution(
        ofDrag translation: CGSize,
        in letters: String,
        mode: MergedKeyMode
    ) -> String? {
        guard letters.count == 2 else { return nil }
        let left = String(letters.prefix(1))
        let right = String(letters.suffix(1))
        switch mode {
        case .fuzzy:
            if translation.width <= -swipeThreshold { return left }
            if translation.width >= swipeThreshold { return right }
            return nil
        case .primary:
            guard isSwipe(translation) else { return left }
            return pointsLeft(translation) ? left : right
        }
    }

    /// Any direction counts as a swipe in `.primary` mode, so the test is on distance
    /// travelled rather than on one axis.
    static func isSwipe(_ translation: CGSize) -> Bool {
        translation.width * translation.width + translation.height * translation.height
            >= swipeThreshold * swipeThreshold
    }

    /// A leftward swipe means the left letter in both modes, so the gesture people
    /// already have does not reverse itself between layouts. Requiring the horizontal
    /// component to dominate keeps a downward flick that drifted sideways out of it.
    static func pointsLeft(_ translation: CGSize) -> Bool {
        translation.width < 0 && abs(translation.width) > abs(translation.height)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct RowLayout {
    let keyWidth: CGFloat
    let specialWidth: CGFloat
    let numWidth: CGFloat
    let returnWidth: CGFloat
    let semicolonWidth: CGFloat

    private let content: CGFloat
    private let gap: CGFloat

    private static let specialKeyRatio: CGFloat = 1.25
    private static let returnKeyRatio: CGFloat = 2.75

    init(width: CGFloat, metrics: KeyboardMetrics) {
        gap = metrics.keyGap
        content = max(width - metrics.sideMargin * 2, metrics.keyGap)
        let columns = CGFloat(KeyboardLayout.columns)
        keyWidth = ((content - gap * (columns - 1)) / columns).rounded(.down)
        specialWidth = (keyWidth * Self.specialKeyRatio).rounded()
        let originalReturnWidth = (keyWidth * Self.returnKeyRatio).rounded()
        numWidth = ((originalReturnWidth - gap) / 2).rounded()
        semicolonWidth = keyWidth
        // The new key and its extra gap are shared evenly by Space and Return.
        returnWidth = originalReturnWidth - ((semicolonWidth + gap) / 2).rounded()
    }

    /// A merged key occupies the same slots as its letters in the 26-key layout.
    func letterWidth(for key: String) -> CGFloat {
        let slots = CGFloat(max(key.count, 1))
        return keyWidth * slots + gap * (slots - 1)
    }

    /// In a merged row, single-letter keys get a larger target. Most of that space
    /// is borrowed evenly from the merged keys; the trailing l/m keys can simply
    /// grow into the unused indent on their right.
    func letterWidths(for row: [String]) -> [CGFloat] {
        let mergedCount = row.filter { $0.count == 2 }.count
        guard mergedCount > 0 else { return row.map { _ in keyWidth } }

        let extra = keyWidth * 0.25
        let borrowed = row.filter { $0.count == 1 && $0 != "l" && $0 != "m" }.count
        let deduction = extra * CGFloat(borrowed) / CGFloat(mergedCount)
        return row.map { key in
            key.count == 1 ? keyWidth + extra : letterWidth(for: key) - deduction
        }
    }

    func letterRowLeadingInset(slotCount: Int) -> CGFloat {
        let rowWidth = keyWidth * CGFloat(slotCount) + gap * CGFloat(max(slotCount - 1, 0))
        return (content - rowWidth) / 2
    }

    func thirdLetterRowLeadingInset(slotCount: Int) -> CGFloat {
        let middle = content - specialWidth * 2 - gap * 2
        let rowWidth = keyWidth * CGFloat(slotCount) + gap * CGFloat(max(slotCount - 1, 0))
        return (middle - rowWidth) / 2
    }

    var contentWidth: CGFloat { content }

    /// Where a key starts inside the content width. Letter rows fill the width; row
    /// three's keys are centred in whatever its two function keys leave.
    func keyOrigin(index: Int, count: Int, keyWidth: CGFloat, inset: Bool) -> CGFloat {
        let rowWidth = keyWidth * CGFloat(count) + gap * CGFloat(count - 1)
        let origin: CGFloat = if inset {
            specialWidth + gap + (content - specialWidth * 2 - gap * 2 - rowWidth) / 2
        } else {
            (content - rowWidth) / 2
        }
        return origin + CGFloat(index) * (keyWidth + gap)
    }

    /// A row of `count` keys inset between row three's two function keys.
    func insetWidth(count: Int) -> CGFloat {
        let count = CGFloat(max(count, 1))
        let middle = content - specialWidth * 2 - gap * 2
        return ((middle - gap * (count - 1) - gap * 2) / count).rounded(.down)
    }
}

/// Long-press options for the symbol pages. The first entry is what a plain tap
/// inserts; the rest fan out from it. Halfwidth/fullwidth pairs come from Unicode,
/// the rest is a judgement call and meant to be edited.
enum SymbolAlternates {
    /// A row fans out from its key, so the options a key can hold depend on where it
    /// sits: `max(index, count - 1 - index) + 1`. Seven is what the tightest key with
    /// a long row (¥, seventh of ten) has room for.
    static let maximumOptions = 7

    static func options(for key: String) -> [String] {
        table[key] ?? [key]
    }

    static func hasAlternates(_ key: String) -> Bool {
        options(for: key).count > 1
    }

    /// Fans out to whichever side has whole keys to spare, which keeps the tapped
    /// option under the finger.
    static func extendsRight(
        index: Int,
        count: Int,
        options: Int,
        keyWidth: CGFloat,
        gap: CGFloat
    ) -> Bool {
        let keysToTheRight = CGFloat(count - 1 - index)
        return keysToTheRight * (keyWidth + gap) >= CGFloat(options - 1) * keyWidth
    }

    /// The row's leading edge inside the content width. Clamping only bites when
    /// neither side had room, and then the mark no longer sits under the finger.
    static func rowLeading(
        keyOrigin: CGFloat,
        keyWidth: CGFloat,
        options: Int,
        extendsRight: Bool,
        contentWidth: CGFloat
    ) -> CGFloat {
        let span = keyWidth * CGFloat(options)
        let ideal = extendsRight ? keyOrigin : keyOrigin + keyWidth - span
        return min(max(ideal, 0), max(contentWidth - span, 0))
    }

    /// Which option a drag has landed on, counting cells away from the key.
    static func selection(
        ofSwipe translation: CGFloat,
        options: Int,
        cellWidth: CGFloat,
        extendsRight: Bool
    ) -> Int {
        guard options > 1, cellWidth > 0 else { return 0 }
        let travelled = (extendsRight ? translation : -translation) / cellWidth
        return min(max(Int(travelled.rounded()), 0), options - 1)
    }

    private static let table: [String: [String]] = [
        // numbers page, row two
        "-": ["-", "－", "—"],
        "/": ["/", "／"],
        ":": [":", "："],
        ";": [";", "；"],
        "(": ["(", "（"],
        ")": [")", "）"],
        "¥": ["¥", "￥", "$", "＄", "€", "£", "₩"],
        "@": ["@", "＠"],
        "\u{201C}": ["\u{201C}", "「", "『", "\"", "＂"],
        "\u{201D}": ["\u{201D}", "」", "』", "\"", "＂"],
        // numbers page, row three
        "。": ["。", "."],
        "，": ["，", ","],
        "、": ["、", "\u{FF64}"],
        "？": ["？", "?"],
        "！": ["！", "!"],
        ".": [".", "．", "。"],
        // symbols page, row one
        "【": ["【", "[", "［", "〔"],
        "】": ["】", "]", "］", "〕"],
        "{": ["{", "｛", "「"],
        "}": ["}", "｝", "」"],
        "#": ["#", "＃"],
        "%": ["%", "％", "‰"],
        "^": ["^", "＾"],
        "*": ["*", "＊", "×"],
        "+": ["+", "＋"],
        "=": ["=", "＝", "≠"],
        // symbols page, row two
        "_": ["_", "＿", "——"],
        "—": ["—", "-", "–"],
        "\\": ["\\", "＼"],
        "|": ["|", "｜", "‖"],
        "~": ["~", "～", "〜"],
        "《": ["《", "<", "＜", "〈"],
        "》": ["》", ">", "＞", "〉"],
        "$": ["$", "＄", "¥", "￥", "€", "£", "₩"],
        "&": ["&", "＆"],
        "·": ["·", "•", "・"],
        // symbols page, row three
        "…": ["…", "……"],
        "\u{2019}": ["\u{2019}", "'", "＇"],
    ]
}

/// Halfwidth and fullwidth twins are near-identical at key size, so the odd one out
/// gets a corner mark, the way the system keyboard labels its fullwidth choice.
enum SymbolWidth {
    static func badge(for option: String, among options: [String]) -> String? {
        guard option.unicodeScalars.count == 1,
              let scalar = option.unicodeScalars.first
        else { return nil }
        if let narrow = narrowForm(ofFullwidth: scalar.value) {
            return options.contains(narrow) ? "全" : nil
        }
        if let wide = wideForm(ofHalfwidth: scalar.value) {
            return options.contains(wide) ? "半" : nil
        }
        return nil
    }

    private static func narrowForm(ofFullwidth value: UInt32) -> String? {
        switch value {
        case 0xFF01...0xFF5E:
            return character(value - 0xFEE0)
        case 0xFFE0...0xFFE6:
            let narrow: [UInt32] = [0x00A2, 0x00A3, 0x00AC, 0x00AF, 0x00A6, 0x00A5, 0x20A9]
            return character(narrow[Int(value - 0xFFE0)])
        default:
            return nil
        }
    }

    private static func wideForm(ofHalfwidth value: UInt32) -> String? {
        switch value {
        case 0xFF61: "。"
        case 0xFF62: "「"
        case 0xFF63: "」"
        case 0xFF64: "、"
        case 0xFF65: "・"
        default: nil
        }
    }

    private static func character(_ value: UInt32) -> String? {
        UnicodeScalar(value).map(String.init)
    }
}
