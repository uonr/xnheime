import AppKit
import IMKSwift
import XnheimeCore

@MainActor
final class CandidatePanel {
    static let shared = CandidatePanel()

    private enum Metrics {
        static let cornerRadius: CGFloat = 7
        static let candidateCornerRadius: CGFloat = 6
        static let candidateFontSize: CGFloat = 18
        static let codeFontSize: CGFloat = 15
        static let numberFontSize: CGFloat = 11
        static let candidateSpacing: CGFloat = 6
        static let rowSpacing: CGFloat = 2
        static let candidatesPerRow = 9
        static let maximumVisibleRows = 5
        static let candidateHorizontalPadding: CGFloat = 7
        static let candidateVerticalPadding: CGFloat = 4
        static let cursorSpacing: CGFloat = 4
        static let contentInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
    }

    private let panel: NSPanel
    private let candidateContainer = NSView()

    private init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.cornerRadius
        background.layer?.masksToBounds = true

        candidateContainer.autoresizingMask = [.width, .height]
        background.addSubview(candidateContainer)
        panel.contentView = background
    }

    func show(
        candidates: [CandidateItem],
        selectedIndex: Int,
        characterIndex: Int,
        client: any IMKTextInput
    ) {
        guard !candidates.isEmpty else {
            hide()
            return
        }
        candidateContainer.subviews.forEach { $0.removeFromSuperview() }

        let selectedRow = selectedIndex / Metrics.candidatesPerRow
        let rowCount = candidates.count.dividedRoundingUp(by: Metrics.candidatesPerRow)
        let visibleRowCount = min(rowCount, Metrics.maximumVisibleRows)
        let firstVisibleRow = min(
            max(selectedRow - visibleRowCount / 2, 0),
            rowCount - visibleRowCount
        )
        let visibleStart = firstVisibleRow * Metrics.candidatesPerRow
        let visibleEnd = min(visibleStart + visibleRowCount * Metrics.candidatesPerRow, candidates.count)
        let visibleCandidates = Array(candidates[visibleStart ..< visibleEnd])
        let visibleSelectedIndex = selectedIndex - visibleStart
        let visibleSelectedRow = visibleSelectedIndex / Metrics.candidatesPerRow

        let labels = visibleCandidates.enumerated().map { index, candidate in
            makeCandidateLabel(
                candidate,
                at: index,
                isSelected: index == visibleSelectedIndex,
                isSelectedRow: index / Metrics.candidatesPerRow == visibleSelectedRow
            )
        }
        let columnCount = min(visibleCandidates.count, Metrics.candidatesPerRow)
        var columnWidths = [CGFloat](repeating: 0, count: columnCount)
        var labelWidths = [CGFloat](repeating: 0, count: labels.count)
        let textHeight = ceil(NSFont.systemFont(ofSize: Metrics.candidateFontSize).boundingRectForFont.height)
        let rowHeight = textHeight + Metrics.candidateVerticalPadding * 2

        for (index, label) in labels.enumerated() {
            let column = index % Metrics.candidatesPerRow
            let labelWidth = ceil(label.attributedStringValue.size().width)
                + Metrics.candidateHorizontalPadding * 2
            labelWidths[index] = labelWidth
            columnWidths[column] = max(
                columnWidths[column],
                labelWidth
            )
        }

        let contentWidth = columnWidths.reduce(0, +)
            + CGFloat(max(columnCount - 1, 0)) * Metrics.candidateSpacing
        let contentHeight = CGFloat(visibleRowCount) * rowHeight
            + CGFloat(max(visibleRowCount - 1, 0)) * Metrics.rowSpacing
        let panelSize = NSSize(
            width: contentWidth + Metrics.contentInsets.left + Metrics.contentInsets.right,
            height: contentHeight + Metrics.contentInsets.top + Metrics.contentInsets.bottom
        )
        panel.setContentSize(panelSize)
        candidateContainer.frame = NSRect(origin: .zero, size: panelSize)

        var columnOrigins = [CGFloat](repeating: Metrics.contentInsets.left, count: columnCount)
        for column in 1 ..< columnCount {
            columnOrigins[column] = columnOrigins[column - 1]
                + columnWidths[column - 1] + Metrics.candidateSpacing
        }
        for (index, label) in labels.enumerated() {
            let row = index / Metrics.candidatesPerRow
            let column = index % Metrics.candidatesPerRow
            label.frame = NSRect(
                x: columnOrigins[column],
                y: panelSize.height - Metrics.contentInsets.top - CGFloat(row + 1) * rowHeight
                    - CGFloat(row) * Metrics.rowSpacing,
                width: labelWidths[index],
                height: rowHeight
            )
            candidateContainer.addSubview(label)
        }

        if position(near: client, characterIndex: characterIndex, panelSize: panelSize) {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func makeCandidateLabel(
        _ candidate: CandidateItem,
        at index: Int,
        isSelected: Bool,
        isSelectedRow: Bool
    ) -> NSTextField {
        let isAction = candidate.isAction
        let visuallySelected = isSelected && !isAction
        let label = NSTextField()
        label.cell = VerticallyCenteredTextFieldCell()
        label.attributedStringValue = candidateLabel(
            candidate,
            at: index,
            isSelected: visuallySelected,
            isSelectedRow: isSelectedRow
        )
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.font = .systemFont(ofSize: Metrics.candidateFontSize)
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.wantsLayer = true
        label.layer?.backgroundColor = visuallySelected
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        label.layer?.cornerRadius = Metrics.candidateCornerRadius
        label.layer?.masksToBounds = true
        label.alignment = .left
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.usesSingleLineMode = true
        return label
    }

    private func candidateLabel(
        _ candidate: CandidateItem,
        at index: Int,
        isSelected: Bool,
        isSelectedRow: Bool
    ) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: Metrics.candidateFontSize, weight: .medium)
        let candidateColor: NSColor = isSelected ? .selectedMenuItemTextColor : .labelColor
        let result = NSMutableAttributedString(
            string: candidate.text,
            attributes: [.font: font, .foregroundColor: candidateColor]
        )

        if let code = candidate.code {
            let codeColor = isSelected
                ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.6)
                : NSColor.secondaryLabelColor
            result.append(NSAttributedString(
                string: " \(code)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: Metrics.codeFontSize),
                    .foregroundColor: codeColor,
                ]
            ))
        }

        let column = index % Metrics.candidatesPerRow
        let selectionLabel = candidate.selectionLabel ?? "\(column + 1)"
        let numberFont = NSFont.systemFont(
            ofSize: candidate.selectionLabel == nil ? Metrics.numberFontSize : Metrics.codeFontSize,
            weight: candidate.selectionLabel == nil ? .regular : .medium
        )
        let numberColor: NSColor = if candidate.selectionLabel != nil || isSelectedRow {
            isSelected
                ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.75)
                : NSColor.secondaryLabelColor
        } else {
            .clear
        }
        let numberBaselineOffset = (
            (font.descender - font.ascender)
                - (numberFont.descender - numberFont.ascender)
        ) / 2
        result.insert(
            NSAttributedString(
                string: "\(selectionLabel) ",
                attributes: [
                    .font: numberFont,
                    .foregroundColor: numberColor,
                    .baselineOffset: numberBaselineOffset,
                ]
            ),
            at: 0
        )
        return result
    }

    private func position(
        near client: any IMKTextInput,
        characterIndex: Int,
        panelSize: NSSize
    ) -> Bool {
        var anchor = NSRect.zero
        client.attributes(
            forCharacterIndex: characterIndex,
            lineHeightRectangle: &anchor
        )

        if anchor.isEmpty, characterIndex != 0 {
            client.attributes(
                forCharacterIndex: 0,
                lineHeightRectangle: &anchor
            )
        }

        guard !anchor.isEmpty else { return false }

        var origin = NSPoint(
            x: anchor.minX,
            y: anchor.minY - panelSize.height - Metrics.cursorSpacing
        )
        if let visibleFrame = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
            if origin.y < visibleFrame.minY {
                origin.y = anchor.maxY + Metrics.cursorSpacing
            }
        }
        panel.setFrameOrigin(origin)
        return true
    }
}

extension CandidateItem {
    var text: String {
        switch self {
        case let .candidate(text, _), let .actionHint(text, _, _): text
        }
    }

    var code: String? {
        guard case let .candidate(_, code) = self else { return nil }
        return code
    }

    var selectionLabel: String? {
        guard case let .actionHint(_, label, _) = self else { return nil }
        return label
    }

    var isAction: Bool {
        if case .actionHint = self { return true }
        return false
    }
}

private extension Int {
    func dividedRoundingUp(by divisor: Int) -> Int {
        (self + divisor - 1) / divisor
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        drawingRect.origin.y += (drawingRect.height - textHeight) / 2
        drawingRect.size.height = textHeight
        return drawingRect
    }
}
