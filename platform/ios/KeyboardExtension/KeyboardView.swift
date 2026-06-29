import SwiftUI

struct KeyboardView: View {
    private enum Panel {
        case keys
        case layoutPicker
        case expandedCandidates
    }

    private enum IPadKey: Hashable {
        case input(String)
        case shift
        case delete
        case tab
        case enter
        case page(KeyPage, String)
        case asciiMode
        case globe
        case reverseLookup
        case space
        case fullwidthSemicolon
        case dismiss
    }

    @ObservedObject var model: KeyboardModel
    var metrics: KeyboardMetrics = KeyboardMetrics()
    var feedback: () -> Void = {}
    let touchRegistry: KeyboardTouchRegistry

    @State private var panel: Panel = .keys

    var body: some View {
        GeometryReader { proxy in
            let layout = RowLayout(width: proxy.size.width, metrics: metrics)
            VStack(spacing: 0) {
                CandidateBar(
                    state: model.candidateState,
                    metrics: metrics,
                    feedback: feedback,
                    showsSettings: panel == .layoutPicker,
                    allowsSettings: !metrics.isPad,
                    showsExpandedCandidates: panel == .expandedCandidates,
                    onSettings: {
                        panel = panel == .layoutPicker ? .keys : .layoutPicker
                    },
                    onToggleExpandedCandidates: {
                        panel = panel == .expandedCandidates ? .keys : .expandedCandidates
                    },
                    onSelectCandidate: selectCandidate,
                    onLoadMore: model.loadMoreCandidates
                )
                    .frame(height: metrics.candidateBarHeight)
                Spacer(minLength: 0)
                Group {
                    if panel == .layoutPicker {
                        layoutPicker
                    } else if panel == .expandedCandidates {
                        ExpandedCandidateView(
                            state: model.candidateState,
                            metrics: metrics,
                            feedback: feedback,
                            onSelectCandidate: selectCandidate,
                            onLoadMore: model.loadMoreCandidates
                        )
                    } else {
                        if metrics.isPad {
                            iPadKeyRows
                        } else {
                            keyRows(layout)
                        }
                    }
                }
                    .padding(.top, metrics.topPadding)
                    .padding(.bottom, metrics.bottomPadding)
            }
            .padding(.horizontal, metrics.sideMargin)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: "KeyboardTouchSpace")
            .overlayPreferenceValue(KeyboardTouchTargetsKey.self) { preferences in
                GeometryReader { touchProxy in
                    KeyboardTouchTargetCollector(
                        registry: touchRegistry,
                        targets: preferences.map {
                            KeyboardTouchSurface.Target(
                                id: $0.id,
                                frame: touchProxy[$0.bounds],
                                callbacks: $0.callbacks
                            )
                        },
                        captureTop: metrics.candidateBarHeight,
                        isEnabled: panel == .keys
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var letterLayout: LetterLayout {
        metrics.allowsMergedLetters ? model.letterLayout : .full26
    }

    private var activeRows: [[String]] {
        KeyboardLayout.rows(for: model.page, layout: letterLayout)
    }

    /// Non-nil only while the letter page is showing a merged layout.
    private var mergedKeyMode: MergedKeyMode? {
        model.page == .letters ? letterLayout.mergedKeyMode : nil
    }

    private func keyRows(_ layout: RowLayout) -> some View {
        VStack(spacing: metrics.rowGap) {
            letterRow(activeRows[0], layout)
            letterRow(activeRows[1], layout)
            thirdRow(layout)
            bottomRow(layout)
        }
    }

    private var iPadKeyRows: some View {
        VStack(spacing: metrics.rowGap) {
            iPadRow(iPadFirstRow)
            iPadRow(iPadSecondRow)
            iPadRow(iPadThirdRow)
            iPadRow(iPadBottomRow)
        }
    }

    private var iPadFirstRow: [(IPadKey, CGFloat)] {
        [(.tab, 1)]
            + iPadInputs(iPadPageRows[0])
            + [(.delete, 1.6)]
    }

    private var iPadSecondRow: [(IPadKey, CGFloat)] {
        let pageKey: (IPadKey, CGFloat) = switch model.page {
        case .letters: (.asciiMode, 1.6)
        case .numbers: (.page(.symbols, "#+="), 1.6)
        case .symbols: (.page(.numbers, "123"), 1.6)
        }
        return [pageKey] + iPadInputs(iPadPageRows[1]) + [(.enter, 1.6)]
    }

    private var iPadThirdRow: [(IPadKey, CGFloat)] {
        let pageContent = iPadInputs(iPadPageRows[2])
        if model.page == .letters {
            return [(.shift, 1.9)] + pageContent + [(.shift, 1.9)]
        }
        let label = model.page == .numbers ? "#+=" : "123"
        let target: KeyPage = model.page == .numbers ? .symbols : .numbers
        return [(.page(target, label), 1.9)] + pageContent + [(.page(target, label), 1.9)]
    }

    private var iPadBottomRow: [(IPadKey, CGFloat)] {
        [
            (.globe, 1),
            (.page(model.page == .letters ? .numbers : .letters, model.page == .letters ? "123" : "拼音"), 1),
            (.reverseLookup, 1),
            (.space, 6),
            (.fullwidthSemicolon, 1),
            (.page(model.page == .letters ? .numbers : .letters, model.page == .letters ? "123" : "拼音"), 1),
            (.dismiss, 1.5),
        ]
    }

    private var iPadPageRows: [[String]] {
        IPadKeyboardLayout.rows(for: model.page)
    }

    private func iPadInputs(_ values: [String]) -> [(IPadKey, CGFloat)] {
        values.map { (.input($0), 1) }
    }

    private func iPadRow(_ keys: [(IPadKey, CGFloat)]) -> some View {
        GeometryReader { proxy in
            let gapCount = CGFloat(max(keys.count - 1, 0))
            let totalWeight = keys.reduce(CGFloat.zero) { $0 + $1.1 }
            let unit = max((proxy.size.width - metrics.keyGap * gapCount) / totalWeight, 1)
            HStack(spacing: metrics.keyGap) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, item in
                    iPadKey(item.0, width: unit * item.1)
                }
            }
        }
        .frame(height: metrics.keyHeight)
    }

    @ViewBuilder
    private func iPadKey(_ key: IPadKey, width: CGFloat) -> some View {
        switch key {
        case let .input(value):
            keyCap(
                .text(model.page == .letters && model.shifted ? value.uppercased() : value),
                width: width,
                kind: .letter,
                showsPreview: model.page == .letters
            ) {
                perform {
                    if model.page == .letters && value.unicodeScalars.allSatisfy(\.properties.isAlphabetic) {
                        if model.usesTemporaryASCII {
                            model.typeASCII(value)
                        } else {
                            model.type(value)
                        }
                    } else {
                        model.insertSymbol(value)
                    }
                }
            }
        case .shift:
            keyCap(
                .symbol(model.shifted ? "shift.fill" : "shift"),
                width: width,
                kind: model.shifted ? .letter : .function
            ) {
                feedback()
                model.shifted.toggle()
            }
        case .delete:
            RepeatingKeyCap(
                label: .symbol("delete.left"),
                width: width,
                height: metrics.keyHeight,
                letterSize: metrics.letterFontSize,
                labelSize: metrics.labelFontSize,
                action: { perform(model.backspace) },
                escalatedAction: { perform(model.deleteWordBackward) }
            )
        case .tab:
            keyCap(.symbol("arrow.right.to.line"), width: width, kind: .function) {
                perform { model.insertSymbol("\t") }
            }
        case .enter:
            keyCap(.symbol("return"), width: width, kind: .function) { perform(model.enter) }
        case let .page(page, label):
            keyCap(.text(label), width: width, kind: .function) {
                feedback()
                model.page = page
            }
        case .asciiMode:
            keyCap(
                .text(model.usesTemporaryASCII ? "拼音" : "abc"),
                width: width,
                kind: .function
            ) {
                feedback()
                model.usesTemporaryASCII.toggle()
            }
        case .globe:
            keyCap(.symbol("globe"), width: width, kind: .function) { perform(model.nextKeyboard) }
        case .reverseLookup:
            keyCap(.text("`"), width: width, kind: .function) {
                perform(model.inputReverseLookup)
            }
        case .space:
            keyCap(.text("空格"), width: width, kind: .letter) { perform(model.space) }
        case .fullwidthSemicolon:
            keyCap(.text("；"), width: width, kind: .function) {
                perform { model.insertSymbol("；") }
            }
        case .dismiss:
            keyCap(.symbol("keyboard.chevron.compact.down"), width: width, kind: .function) {
                perform(model.dismissKeyboard)
            }
        }
    }

    private func letterRow(_ row: [String], _ layout: RowLayout) -> some View {
        let widths = model.page == .letters
            ? layout.letterWidths(for: row)
            : row.map { _ in layout.keyWidth }
        return HStack(spacing: metrics.keyGap) {
            ForEach(Array(row.enumerated()), id: \.element) { index, key in
                activeKey(
                    key,
                    width: widths[index],
                    layout: layout,
                    anchor: .forKey(at: index, of: row.count),
                    index: index,
                    count: row.count
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: model.page == .letters ? .leading : .center)
        .offset(
            x: model.page == .letters
                ? layout.letterRowLeadingInset(slotCount: row.reduce(0) { $0 + $1.count })
                : 0
        )
    }

    private func thirdRow(_ layout: RowLayout) -> some View {
        HStack(spacing: metrics.keyGap) {
            switch model.page {
            case .letters:
                keyCap(
                    .symbol(model.shifted ? "shift.fill" : "shift"),
                    width: layout.specialWidth,
                    kind: model.shifted ? .letter : .function
                ) {
                    feedback()
                    model.shifted.toggle()
                }
            case .numbers:
                keyCap(.text("#+="), width: layout.specialWidth, kind: .function) {
                    feedback()
                    model.page = .symbols
                }
            case .symbols:
                keyCap(.text("123"), width: layout.specialWidth, kind: .function) {
                    feedback()
                    model.page = .numbers
                }
            }
            HStack(spacing: metrics.keyGap) {
                let row = activeRows[2]
                let letterWidths = layout.letterWidths(for: row)
                ForEach(Array(row.enumerated()), id: \.element) { index, key in
                    activeKey(
                        key,
                        width: model.page == .letters
                            ? letterWidths[index]
                            : layout.insetWidth(count: row.count),
                        layout: layout,
                        anchor: .forKey(at: index, of: row.count),
                        index: index,
                        count: row.count,
                        inset: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: model.page == .letters ? .leading : .center)
            .offset(
                x: model.page == .letters
                    ? layout.thirdLetterRowLeadingInset(
                        slotCount: activeRows[2].reduce(0) { $0 + $1.count }
                    )
                    : 0
            )
            RepeatingKeyCap(
                label: .symbol("delete.left"),
                width: layout.specialWidth,
                height: metrics.keyHeight,
                letterSize: metrics.letterFontSize,
                labelSize: metrics.labelFontSize,
                action: { perform(model.backspace) },
                escalatedAction: { perform(model.deleteWordBackward) }
            )
        }
    }

    private func bottomRow(_ layout: RowLayout) -> some View {
        HStack(spacing: metrics.keyGap) {
            keyCap(
                .text(model.page == .letters ? "123" : "拼"),
                width: layout.numWidth,
                kind: .function
            ) {
                feedback()
                model.page = model.page == .letters ? .numbers : .letters
            }
            if model.showsGlobeKey {
                keyCap(.symbol("globe"), width: layout.numWidth, kind: .function) {
                    perform(model.nextKeyboard)
                }
            } else {
                keyCap(.text("`"), width: layout.numWidth, kind: .function) {
                    perform(model.inputReverseLookup)
                }
            }
            keyCap(.text("空格"), width: nil, kind: .letter) { perform(model.space) }
            keyCap(.text(";"), width: layout.semicolonWidth, kind: .letter) {
                perform {
                    if model.page == .letters {
                        model.type(";")
                    } else {
                        model.insertSymbol(";")
                    }
                }
            }
            keyCap(.text("换行"), width: layout.returnWidth, kind: .function) { perform(model.enter) }
        }
    }

    private func activeKey(
        _ key: String,
        width: CGFloat,
        layout: RowLayout,
        anchor: CalloutAnchor = .center,
        index: Int = 0,
        count: Int = 1,
        inset: Bool = false
    ) -> some View {
        Group {
            if model.page != .letters {
                let options = SymbolAlternates.options(for: key)
                if options.count > 1 {
                    SymbolKeyCap(
                        label: key,
                        options: options,
                        extendsRight: SymbolAlternates.extendsRight(
                            index: index,
                            count: count,
                            options: options.count,
                            keyWidth: width,
                            gap: metrics.keyGap
                        ),
                        width: width,
                        keyOrigin: layout.keyOrigin(
                            index: index,
                            count: count,
                            keyWidth: width,
                            inset: inset
                        ),
                        contentWidth: layout.contentWidth,
                        metrics: metrics
                    ) { value in perform { model.insertSymbol(value) } }
                } else {
                    keyCap(.text(key), width: width, kind: .letter) {
                        perform { model.insertSymbol(key) }
                    }
                }
            } else if let mergedKeyMode {
                MergedKeyCap(
                    letters: key,
                    uppercase: model.shifted,
                    mode: mergedKeyMode,
                    width: width,
                    height: metrics.keyHeight,
                    metrics: metrics,
                    anchor: anchor
                ) { value, primaryWeight in
                    perform { model.type(value, primaryWeight: primaryWeight) }
                }
            } else {
                keyCap(
                    .text(model.shifted ? key.uppercased() : key),
                    width: width,
                    kind: .letter,
                    showsPreview: true,
                    previewAnchor: anchor
                ) { perform { model.type(key) } }
            }
        }
    }

    private var layoutPicker: some View {
        VStack(spacing: 8) {
            Text("更多设置请打开输入法 App")
                .font(.system(size: metrics.labelFontSize - 3))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("键盘布局")
                    .font(.system(size: metrics.labelFontSize, weight: .semibold))
                Spacer()
                Text("点击选择")
                    .font(.system(size: metrics.labelFontSize - 3))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(
                    LetterLayout.available(allowsMergedLetters: metrics.allowsMergedLetters),
                    id: \.self
                ) { option in
                    Button {
                        feedback()
                        model.letterLayout = option
                        panel = .keys
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .font(.system(size: metrics.labelFontSize, weight: .medium))
                                Text(option.description)
                                    .font(.system(size: metrics.labelFontSize - 4))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: option == model.letterLayout ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: metrics.labelFontSize + 1))
                                .foregroundStyle(
                                    option == model.letterLayout ? Color.accentColor : Color.secondary
                                )
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.keyHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    option == model.letterLayout
                                        ? Color.accentColor.opacity(0.13)
                                        : KeyboardPalette.letterKey
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectCandidate(_ id: Int) {
        panel = .keys
        model.selectCandidate(id)
    }

    private func perform(_ action: () -> Void) {
        action()
        feedback()
    }

    private func keyCap(
        _ label: KeyLabel,
        width: CGFloat?,
        kind: KeyKind,
        showsPreview: Bool = false,
        previewAnchor: CalloutAnchor = .center,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        ImmediateKeyCap(
            kind: kind,
            action: action,
            showsPreview: showsPreview,
            previewHeight: metrics.calloutHeight,
            previewLift: metrics.calloutLift,
            previewAnchor: previewAnchor
        ) {
            label.view(letterSize: metrics.letterFontSize, labelSize: metrics.labelFontSize)
        }
        .frame(width: width, height: metrics.keyHeight)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }

}
