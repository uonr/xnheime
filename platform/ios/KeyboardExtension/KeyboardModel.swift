import Foundation
import XnheimeCore

@MainActor
final class KeyboardModel: ObservableObject {
    private static let candidatePageSize: UInt32 = 40

    struct Candidate: Identifiable, Equatable {
        let id: Int
        let text: String
        let code: String?
    }

    @Published var shifted = false
    @Published var page: KeyPage = .letters
    @Published var usesTemporaryASCII = false
    @Published var showsGlobeKey = true
    @Published var letterLayout: LetterLayout {
        didSet { settings.letterLayout = letterLayout }
    }

    private let reducer = CompositionSession()
    private unowned let document: any TextDocumentWriting
    private let settings: KeyboardSettings
    private var selectedTextSnapshot: String?
    private var hasLoadedDictionary = false
    private var loadedDictionaryFingerprint: String?
    private var dictionaryLoadGeneration = 0
    private var pendingDictionarySession: CompositionSession?
    private var composing = false
    private var dictionaryMode: SharedDictionaryMode?
    let candidateState = KeyboardCandidateState()

    var preedit: String { candidateState.preedit }
    var candidates: [Candidate] { candidateState.candidates }
    var selectedIndex: Int { candidateState.selectedIndex }

    init(document: any TextDocumentWriting, settings: KeyboardSettings = KeyboardSettings()) {
        self.document = document
        self.settings = settings
        letterLayout = settings.letterLayout
        setDictionaryMode(SharedKeyboardSettings.dictionaryMode)
    }

    func setDictionaryMode(_ mode: SharedDictionaryMode) {
        guard mode != dictionaryMode else { return }
        dictionaryMode = mode
        let coreMode: DictionaryMode = switch mode {
        case .expert: .expert
        case .regular: .regular
        case .beginner: .beginner
        }
        reducer.setDictionaryMode(mode: coreMode)
        selectedTextSnapshot = nil
        composing = false
        candidateState.setPreedit("")
        candidateState.resetCandidates()
    }

    /// Parses a new dictionary in an isolated Core session, so opening the keyboard
    /// never makes its main actor wait for file I/O or table construction.
    func reloadUserDictionaryInBackground(
        from directory: URL?,
        fingerprint: String
    ) async -> UserDictionaryLoadResult? {
        if hasLoadedDictionary, fingerprint == loadedDictionaryFingerprint { return nil }
        guard let directory else { return nil }
        dictionaryLoadGeneration += 1
        let generation = dictionaryLoadGeneration
        let path = directory.path
        let loaded = await Task.detached(priority: .utility) {
            let session = CompositionSession()
            return (session, session.loadUserDictionaryDirectory(path: path))
        }.value
        guard generation == dictionaryLoadGeneration else { return nil }
        guard loaded.1.error == nil else { return loaded.1 }
        hasLoadedDictionary = true
        loadedDictionaryFingerprint = fingerprint
        if isComposing {
            pendingDictionarySession = loaded.0
        } else {
            reducer.adoptUserDictionary(source: loaded.0)
        }
        return loaded.1
    }

    var isComposing: Bool {
        composing
    }

    func type(_ key: String, primaryWeight: UInt16? = nil) {
        guard shifted else {
            if let primaryWeight, key.count == 2 {
                dispatch(.inputWeightedMergedKey(letters: key, primaryWeight: primaryWeight))
            } else {
                dispatch(.inputMergedKey(letters: key))
            }
            return
        }
        shifted = false
        // Shift needs one definite letter, so a merged key contributes its first.
        let letter = String(key.prefix(1))
        let uppercased = letter.uppercased()
        if uppercased == letter {
            dispatch(.inputMergedKey(letters: letter))
        } else {
            dispatch(.enterInline(text: uppercased))
        }
    }

    func space() {
        isComposing ? dispatch(.commit) : document.insertText(" ")
    }

    func enter() {
        if isComposing {
            dispatch(.commitCode)
        } else {
            document.insertText("\n")
        }
    }

    func backspace() {
        isComposing ? dispatch(.inputText(text: "\u{7F}")) : document.deleteBackward()
    }

    func insertSymbol(_ text: String) {
        dispatch(.insertDirect(text: text))
    }

    func typeASCII(_ key: String) {
        let text = shifted ? key.uppercased() : key
        shifted = false
        dispatch(.insertDirect(text: text))
    }

    func inputReverseLookup() {
        dispatch(.inputText(text: "`"))
    }

    func selectCandidate(_ id: Int) {
        guard candidates.contains(where: { $0.id == id }) else { return }
        dispatch(.selectCandidate(index: UInt32(id)))
    }

    func nextKeyboard() {
        document.advanceToNextInputMode()
    }

    func dismissKeyboard() {
        document.dismissKeyboard()
    }

    func deleteWordBackward() {
        if isComposing {
            dispatch(.inputText(text: "\u{7F}"))
            return
        }
        guard let before = document.documentContextBeforeInput, !before.isEmpty else {
            document.deleteBackward()
            return
        }
        for _ in 0..<Self.deletionCount(before: before) {
            document.deleteBackward()
        }
    }

    func loadMoreCandidates() {
        guard candidateState.hasMore else { return }
        let offset = candidateState.loadedItemCount
        let items = reducer.candidatePage(
            offset: UInt32(offset),
            limit: Self.candidatePageSize
        )
        let page = items.enumerated().compactMap { index, item -> Candidate? in
            guard case let .candidate(text, code) = item else { return nil }
            return Candidate(id: offset + index, text: text, code: code)
        }
        candidateState.append(page, consumedItemCount: items.count)
    }

    static func deletionCount(before text: String) -> Int {
        var tail = Substring(text)
        var whitespace = 0
        while let last = tail.last, last.isWhitespace {
            tail = tail.dropLast()
            whitespace += 1
        }
        guard let last = tail.last else { return max(whitespace, 1) }
        if last.isPunctuation || last.isSymbol {
            return whitespace + 1
        }
        let word = String(tail)
        let ns = word as NSString
        var wordStart = 0
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            wordStart = range.location
        }
        let lengthInCharacters = word.count - ns.substring(to: wordStart).count
        return whitespace + max(lengthInCharacters, 1)
    }

    private func dispatch(_ event: CompositionEvent) {
        if !isComposing {
            selectedTextSnapshot = document.selectedText
        }
        let result = reducer.dispatchPaged(
            event: event,
            selectedText: selectedTextSnapshot,
            clipboardText: nil,
            candidateLimit: Self.candidatePageSize
        )
        composing = if case .idle = result.mode { false } else { true }
        apply(result.effects, candidateCount: Int(result.candidateCount))
        if !isComposing {
            selectedTextSnapshot = nil
            if let pendingDictionarySession {
                reducer.adoptUserDictionary(source: pendingDictionarySession)
                self.pendingDictionarySession = nil
            }
        }
    }

    private func apply(_ effects: [CompositionEffect], candidateCount: Int) {
        for effect in effects {
            switch effect {
            case let .insertText(text):
                document.insertText(text)
                candidateState.setPreedit("")
            case let .insertPairedText(before, after):
                document.insertText(before + after)
                candidateState.setPreedit("")
            case let .setMarkedText(text):
                candidateState.setPreedit(text)
            case let .showCandidates(items, selected, _):
                let candidates = items.enumerated().compactMap { index, item -> Candidate? in
                    guard case let .candidate(text, code) = item else { return nil }
                    return Candidate(id: index, text: text, code: code)
                }
                candidateState.replace(
                    candidates: candidates,
                    selectedIndex: Int(selected),
                    totalCount: candidateCount,
                    consumedItemCount: items.count
                )
            case .hideCandidates:
                candidateState.resetCandidates()
            case .deleteBackward:
                document.deleteBackward()
            case .showAddEntryDialog:
                // TODO: no user dictionary on iOS yet.
                break
            }
        }
    }
}

@MainActor
final class KeyboardCandidateState: ObservableObject {
    static let expansionThreshold = 6
    @Published private(set) var preedit = ""
    @Published private(set) var candidates: [KeyboardModel.Candidate] = []
    @Published private(set) var selectedIndex = 0
    private(set) var totalCount = 0
    private(set) var loadedItemCount = 0

    var hasMore: Bool { candidates.count < totalCount }
    var canExpand: Bool { totalCount > Self.expansionThreshold }

    func setPreedit(_ value: String) {
        if preedit != value { preedit = value }
    }

    func replace(
        candidates: [KeyboardModel.Candidate],
        selectedIndex: Int,
        totalCount: Int,
        consumedItemCount: Int
    ) {
        self.candidates = candidates
        self.selectedIndex = selectedIndex
        self.totalCount = totalCount
        loadedItemCount = consumedItemCount
    }

    func append(_ page: [KeyboardModel.Candidate], consumedItemCount: Int) {
        loadedItemCount += consumedItemCount
        guard !page.isEmpty else {
            totalCount = loadedItemCount
            return
        }
        candidates.append(contentsOf: page)
    }

    func resetCandidates() {
        candidates = []
        selectedIndex = 0
        totalCount = 0
        loadedItemCount = 0
    }
}
