import UIKit

struct KeyboardMetrics: Equatable {
    var keyHeight: CGFloat = 43
    var rowGap: CGFloat = 12
    var keyGap: CGFloat = 6
    var sideMargin: CGFloat = 3
    var topPadding: CGFloat = 6
    var bottomPadding: CGFloat = 4
    var candidateBarHeight: CGFloat = 45
    var letterFontSize: CGFloat = 25
    var labelFontSize: CGFloat = 16
    var candidateFontSize: CGFloat = 22
    var calloutGap: CGFloat = 3
    var allowsMergedLetters = true
    var isPad = false

    /// An extension cannot draw past the top of its keyboard, so the room above row
    /// one is all a callout gets.
    var calloutHeight: CGFloat {
        candidateBarHeight + topPadding - calloutGap
    }

    var calloutLift: CGFloat {
        calloutHeight + calloutGap
    }

    /// What the bottom row and the padding under it take up, which is the clearance
    /// anything hanging above that row has to leave.
    var bottomRowClearance: CGFloat { keyHeight + rowGap + bottomPadding }

    var keyboardHeight: CGFloat {
        let rows = CGFloat(KeyboardLayout.rowCount)
        return candidateBarHeight + topPadding
            + keyHeight * rows + rowGap * (rows - 1)
            + bottomPadding
    }

    static func resolve(traits: UITraitCollection) -> KeyboardMetrics {
        var metrics = KeyboardMetrics()
        if traits.userInterfaceIdiom == .pad {
            metrics.isPad = true
            metrics.allowsMergedLetters = false
            metrics.keyHeight = 56
            metrics.rowGap = 14
            metrics.keyGap = 10
            metrics.sideMargin = 6
            metrics.candidateBarHeight = 52
            metrics.letterFontSize = 26
            metrics.candidateFontSize = 24
        } else if traits.verticalSizeClass == .compact {
            // Landscape keys are already wide, so merging them buys nothing.
            metrics.allowsMergedLetters = false
            metrics.keyHeight = 32
            metrics.rowGap = 7
            metrics.topPadding = 4
            metrics.candidateBarHeight = 36
            metrics.letterFontSize = 22
            metrics.candidateFontSize = 20
        }
        return metrics
    }
}
