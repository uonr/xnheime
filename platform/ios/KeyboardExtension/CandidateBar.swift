import SwiftUI
import UIKit

struct CandidateBar: View {
    @ObservedObject var state: KeyboardCandidateState
    let metrics: KeyboardMetrics
    let feedback: () -> Void
    let showsSettings: Bool
    let allowsSettings: Bool
    let showsExpandedCandidates: Bool
    let onSettings: () -> Void
    let onToggleExpandedCandidates: () -> Void
    let onSelectCandidate: (Int) -> Void
    let onLoadMore: () -> Void

    private static let preeditFontSize: CGFloat = 13
    private static let maxCodeLength = 4
    private static let preeditMinWidth: CGFloat = {
        let font = UIFont.monospacedSystemFont(ofSize: preeditFontSize, weight: .medium)
        let widest = String(repeating: "0", count: maxCodeLength) as NSString
        return widest.size(withAttributes: [.font: font]).width.rounded(.up)
    }()

    var body: some View {
        HStack(spacing: 0) {
            if !state.preedit.isEmpty {
                Text(state.preedit)
                    .font(.system(size: Self.preeditFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: Self.preeditMinWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                Divider().frame(height: 20)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(state.candidates) { candidate in
                        cell(candidate)
                            .onAppear {
                                if candidate.id >= state.candidates.count - 5 {
                                    onLoadMore()
                                }
                            }
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollEdgeEffectDisabled()
            if state.canExpand {
                Button {
                    feedback()
                    onToggleExpandedCandidates()
                } label: {
                    Image(systemName: showsExpandedCandidates ? "chevron.up" : "chevron.down")
                        .font(.system(size: metrics.labelFontSize, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: metrics.candidateBarHeight, height: metrics.candidateBarHeight)
                }
                .buttonStyle(.plain)
            }
            if allowsSettings && state.preedit.isEmpty && state.candidates.isEmpty {
                Button {
                    feedback()
                    onSettings()
                } label: {
                    Image(systemName: showsSettings ? "keyboard" : "gearshape")
                        .font(.system(size: metrics.labelFontSize))
                        .foregroundStyle(Color.primary)
                        .frame(width: metrics.candidateBarHeight, height: metrics.candidateBarHeight)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cell(_ candidate: KeyboardModel.Candidate) -> some View {
        let isSelected = candidate.id == state.selectedIndex
        return Button {
            feedback()
            onSelectCandidate(candidate.id)
        } label: {
            Text(candidate.text)
                .font(
                    .system(
                        size: candidate.text.count > 2
                            ? metrics.candidateFontSize - 2
                            : metrics.candidateFontSize
                    )
                )
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: metrics.candidateBarHeight - 10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ExpandedCandidateView: View {
    private struct Placement: Identifiable {
        let candidate: KeyboardModel.Candidate
        let columns: Int
        var id: Int { candidate.id }
    }

    @ObservedObject var state: KeyboardCandidateState
    let metrics: KeyboardMetrics
    let feedback: () -> Void
    let onSelectCandidate: (Int) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / 6
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(row) { placement in
                                cell(placement.candidate)
                                    .frame(width: columnWidth * CGFloat(placement.columns))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .scrollEdgeEffectDisabled()
        }
    }

    private var rows: [[Placement]] {
        var result: [[Placement]] = []
        var row: [Placement] = []
        var used = 0
        for candidate in state.candidates {
            let columns = min(max((candidate.text.count + 2) / 3, 1), 6)
            if used + columns > 6 {
                result.append(row)
                row = []
                used = 0
            }
            row.append(Placement(candidate: candidate, columns: columns))
            used += columns
        }
        if !row.isEmpty { result.append(row) }
        return result
    }

    private func cell(_ candidate: KeyboardModel.Candidate) -> some View {
        Button {
            feedback()
            onSelectCandidate(candidate.id)
        } label: {
            Text(candidate.text)
                .font(
                    .system(
                        size: candidate.text.count > 2
                            ? metrics.candidateFontSize - 2
                            : metrics.candidateFontSize
                    )
                )
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.keyHeight)
                .background(
                    candidate.id == state.selectedIndex
                        ? Color.primary.opacity(0.1)
                        : Color.clear
                )
                .overlay(alignment: .bottom) { Divider() }
        }
        .buttonStyle(.plain)
        .onAppear {
            if candidate.id >= state.candidates.count - 8 {
                onLoadMore()
            }
        }
    }
}

extension View {
    /// The bar is one line tall, so all of it falls inside iOS 26's blurred edge.
    @ViewBuilder
    func scrollEdgeEffectDisabled() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}
