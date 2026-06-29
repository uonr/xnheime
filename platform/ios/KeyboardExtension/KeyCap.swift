import SwiftUI
import UIKit

@MainActor
struct KeyboardTouchCallbacks {
    var began: (CGPoint) -> Void
    var moved: (CGSize) -> Void = { _ in }
    var ended: (CGSize, Bool) -> Void
}

struct KeyboardTouchTarget {
    let id: String
    let bounds: Anchor<CGRect>
    let callbacks: KeyboardTouchCallbacks
}

struct KeyboardTouchTargetsKey: PreferenceKey {
    static let defaultValue: [KeyboardTouchTarget] = []

    static func reduce(value: inout [KeyboardTouchTarget], nextValue: () -> [KeyboardTouchTarget]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func keyboardTouchTarget(id: String, callbacks: KeyboardTouchCallbacks) -> some View {
        anchorPreference(key: KeyboardTouchTargetsKey.self, value: .bounds) {
            [KeyboardTouchTarget(id: id, bounds: $0, callbacks: callbacks)]
        }
    }
}

@MainActor
enum KeyboardTouchSurface {
    struct Target {
        let id: String
        let frame: CGRect
        let callbacks: KeyboardTouchCallbacks
    }

    final class TouchView: UIView {
        struct Owner {
            let target: Target
            let origin: CGPoint
        }

        var targets: [Target] = []
        var captureTop: CGFloat = 0
        private var owners: [ObjectIdentifier: Owner] = [:]
        /// Finger contact tends to land slightly below the intended key. Correcting
        /// the observation upward gives the row above a little more of each gap.
        private static let verticalTouchOffset: CGFloat = 4

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            let recognizer = TouchBeginBypassGestureRecognizer { [weak self] touches, _ in
                self?.beginTouches(touches)
            }
            addGestureRecognizer(recognizer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard !targets.isEmpty, bounds.contains(point), point.y >= captureTop else { return false }
            return targetID(at: point) != nil
        }

        func targetID(at point: CGPoint) -> String? {
            guard !targets.isEmpty, bounds.contains(point), point.y >= captureTop else { return nil }
            return nearestTarget(to: point)?.id
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            beginTouches(touches)
        }

        private func beginTouches(_ touches: Set<UITouch>) {
            for touch in touches {
                beginTouch(identifier: ObjectIdentifier(touch), at: touch.location(in: self))
            }
        }

        /// Kept separate from UIKit's `UITouch` wrapper so overlapping contacts
        /// can be regression-tested without constructing private UIKit objects.
        func beginTouch(identifier: ObjectIdentifier, at point: CGPoint) {
            guard owners[identifier] == nil else { return }
            guard let target = nearestTarget(to: point) else { return }
            owners[identifier] = Owner(target: target, origin: point)
            target.callbacks.began(
                CGPoint(x: point.x - target.frame.minX, y: point.y - target.frame.minY)
            )
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                let identifier = ObjectIdentifier(touch)
                guard let owner = owners[identifier] else { continue }
                let point = touch.location(in: self)
                owner.target.callbacks.moved(
                    CGSize(width: point.x - owner.origin.x, height: point.y - owner.origin.y)
                )
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches, cancelled: false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches, cancelled: true)
        }

        private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
            for touch in touches {
                let identifier = ObjectIdentifier(touch)
                guard let owner = owners.removeValue(forKey: identifier) else { continue }
                let point = touch.location(in: self)
                owner.target.callbacks.ended(
                    CGSize(width: point.x - owner.origin.x, height: point.y - owner.origin.y),
                    cancelled
                )
            }
        }

        private func nearestTarget(to point: CGPoint) -> Target? {
            // Anchors are absolute: prediction must never steal a touch that is
            // visibly inside a key.
            if let anchored = targets.first(where: { $0.frame.contains(point) }) {
                return anchored
            }

            // In gaps, use the same basic spatial model as corrective keyboards:
            // distance to the key centre normalized by that key's dimensions.
            // This is an anisotropic Voronoi partition and works for letter,
            // function and space keys without leaving any unassigned pixels.
            let corrected = CGPoint(x: point.x, y: point.y - Self.verticalTouchOffset)
            return targets.min {
                spatialScore(corrected, for: $0.frame) < spatialScore(corrected, for: $1.frame)
            }
        }

        private func spatialScore(_ point: CGPoint, for frame: CGRect) -> CGFloat {
            let halfWidth = max(frame.width / 2, 1)
            let halfHeight = max(frame.height / 2, 1)
            let dx = (point.x - frame.midX) / halfWidth
            let dy = (point.y - frame.midY) / halfHeight
            return dx * dx + dy * dy
        }

    }
}

@MainActor
final class KeyboardTouchRegistry {
    weak var touchView: KeyboardTouchSurface.TouchView? {
        didSet { apply() }
    }

    private var targets: [KeyboardTouchSurface.Target] = []
    private var captureTop: CGFloat = 0
    private var isEnabled = true

    func update(targets: [KeyboardTouchSurface.Target], captureTop: CGFloat, isEnabled: Bool) {
        if !targets.isEmpty { self.targets = targets }
        self.captureTop = captureTop
        self.isEnabled = isEnabled
        apply()
    }

    private func apply() {
        guard let touchView else { return }
        if !targets.isEmpty { touchView.targets = targets }
        touchView.captureTop = captureTop
        touchView.isUserInteractionEnabled = isEnabled
    }
}

@MainActor
struct KeyboardTouchTargetCollector: UIViewRepresentable {
    let registry: KeyboardTouchRegistry
    let targets: [KeyboardTouchSurface.Target]
    let captureTop: CGFloat
    let isEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        registry.update(targets: targets, captureTop: captureTop, isEnabled: isEnabled)
    }
}

/// iOS delays view delivery for touches near a screen edge while it decides if a
/// system edge gesture is starting. A zero-duration recognizer observes the same
/// touch immediately without cancelling its normal delivery. `TouchView` dedupes
/// the later responder callback by UITouch identity.
private final class TouchBeginBypassGestureRecognizer: UILongPressGestureRecognizer {
    private let onTouchesBegan: (Set<UITouch>, UIEvent) -> Void

    init(onTouchesBegan: @escaping (Set<UITouch>, UIEvent) -> Void) {
        self.onTouchesBegan = onTouchesBegan
        super.init(target: nil, action: nil)
        minimumPressDuration = 0
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouchesBegan(touches, event)
    }
}

/// No background color: the `UIInputView` already draws the translucent backdrop.
enum KeyboardPalette {
    static let letterKey = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
    static let functionKey = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.28, alpha: 1)
            : UIColor(red: 0.67, green: 0.69, blue: 0.72, alpha: 1)
    })
    static let keyShadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.55)
            : UIColor(red: 0.54, green: 0.55, blue: 0.58, alpha: 1)
    })
}

enum KeyKind {
    case letter
    case function
}

enum KeyLabel {
    case text(String)
    case symbol(String)

    private static let symbolSizeBoost: CGFloat = 3

    @ViewBuilder
    func view(letterSize: CGFloat, labelSize: CGFloat) -> some View {
        switch self {
        case let .text(value):
            Text(value)
                .font(.system(size: value.count == 1 ? letterSize : labelSize))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: labelSize + Self.symbolSizeBoost, weight: .light))
        }
    }
}

/// Offset rectangle rather than `.shadow`, whose offscreen pass blurs the label.
struct KeyFace<Content: View>: View {
    private static var cornerRadius: CGFloat { 5 }
    private static var shadowDepth: CGFloat { 1 }

    let kind: KeyKind
    let pressed: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(KeyboardPalette.keyShadow)
                .offset(y: Self.shadowDepth)
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(fill)
            content
                .foregroundStyle(Color.primary)
        }
        .contentShape(Rectangle())
    }

    private var fill: Color {
        switch kind {
        case .letter:
            pressed ? KeyboardPalette.functionKey : KeyboardPalette.letterKey
        case .function:
            pressed ? KeyboardPalette.letterKey : KeyboardPalette.functionKey
        }
    }
}

struct KeyCapStyle: ButtonStyle {
    let kind: KeyKind

    func makeBody(configuration: Configuration) -> some View {
        KeyFace(kind: kind, pressed: configuration.isPressed) { configuration.label }
    }
}

/// Keyboard keys should commit on touch-down, rather than waiting for the finger
/// to lift like a regular SwiftUI `Button`. Besides feeling faster, this lets a
/// second finger start the next key while the first one is still lifting.
struct ImmediateKeyCap<Content: View>: View {
    let kind: KeyKind
    let action: @MainActor () -> Void
    var showsPreview = false
    var previewHeight: CGFloat = 0
    var previewLift: CGFloat = 0
    var previewAnchor: CalloutAnchor = .center
    @ViewBuilder var content: Content

    @State private var pressed = false
    @State private var touchID = UUID().uuidString

    var body: some View {
        KeyFace(kind: kind, pressed: pressed) { content }
            .overlay(alignment: previewAlignment) {
                if pressed && showsPreview {
                    KeyFace(kind: kind, pressed: false) { content }
                        .frame(height: previewHeight)
                        .offset(y: -previewLift)
                        .allowsHitTesting(false)
                }
            }
            .keyboardTouchTarget(
                id: touchID,
                callbacks: KeyboardTouchCallbacks(
                    began: { _ in
                        pressed = true
                        action()
                    },
                    ended: { _, _ in pressed = false }
                )
            )
            .onDisappear { pressed = false }
    }

    private var previewAlignment: Alignment {
        switch previewAnchor {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }
}

@MainActor
final class KeyRepeater: ObservableObject {
    private static let initialDelay: Duration = .milliseconds(400)
    private static let interval: Duration = .milliseconds(90)
    private static let escalateAfter: Duration = .seconds(2)
    private static let escalatedInterval: Duration = .milliseconds(160)
    private static let maxRepeats = 300

    private var task: Task<Void, Never>?

    func start(
        repeating action: @escaping @MainActor () -> Void,
        escalatingTo escalated: @escaping @MainActor () -> Void
    ) {
        stop()
        action()
        task = Task {
            try? await Task.sleep(for: Self.initialDelay)
            guard !Task.isCancelled else { return }
            var elapsed: Duration = .zero
            var fired = 0
            while !Task.isCancelled, fired < Self.maxRepeats {
                let accelerated = elapsed >= Self.escalateAfter
                if accelerated { escalated() } else { action() }
                fired += 1
                let step = accelerated ? Self.escalatedInterval : Self.interval
                try? await Task.sleep(for: step)
                guard !Task.isCancelled else { return }
                elapsed += step
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct RepeatingKeyCap: View {
    let label: KeyLabel
    let width: CGFloat
    let height: CGFloat
    let letterSize: CGFloat
    let labelSize: CGFloat
    let action: @MainActor () -> Void
    let escalatedAction: @MainActor () -> Void

    @StateObject private var repeater = KeyRepeater()
    @State private var pressed = false
    @State private var touchID = UUID().uuidString

    var body: some View {
        KeyFace(kind: .function, pressed: pressed) {
            label.view(letterSize: letterSize, labelSize: labelSize)
        }
        .frame(width: width, height: height)
        .keyboardTouchTarget(
            id: touchID,
            callbacks: KeyboardTouchCallbacks(
                began: { _ in
                    pressed = true
                    repeater.start(repeating: action, escalatingTo: escalatedAction)
                },
                ended: { _, _ in
                    pressed = false
                    repeater.stop()
                }
            )
        )
        .onDisappear {
            pressed = false
            repeater.stop()
        }
    }
}

struct MergedKeyCap: View {
    let letters: String
    let uppercase: Bool
    let mode: MergedKeyMode
    let width: CGFloat
    let height: CGFloat
    let metrics: KeyboardMetrics
    let anchor: CalloutAnchor
    let action: (String, UInt16?) -> Void

    @State private var resolved: String?
    @State private var primaryWeight: UInt16?
    @State private var pressed = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var longPressSelectedSecondary = false
    @State private var touchID = UUID().uuidString

    private static let dimmedOpacity: CGFloat = 0.25
    private static let calloutFontBoost: CGFloat = 5
    private static let selectionOpacity: CGFloat = 0.12
    /// `.primary` mode spells out which letter a tap gives: the left one is set
    /// larger, the right one greyed back to the weight of a hint.
    private static let primaryFontBoost: CGFloat = 2
    private static let secondaryFontDrop: CGFloat = 3
    private static let secondaryOpacity: CGFloat = 0.5

    var body: some View {
        KeyFace(kind: .letter, pressed: pressed) {
            HStack(spacing: letterSpacing) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, character in
                    let letter = String(character)
                    Text(label(for: letter))
                        .font(.system(size: fontSize(at: index, boost: 0)))
                        .opacity(opacity(at: index, letter: letter))
                }
            }
        }
        .frame(width: width, height: height)
        // A finger covers the key, so the callout is the only feedback for which
        // letter a swipe has landed on. It stays key-width so it cannot leave the
        // keyboard at the edges, and rows above it are drawn earlier.
        .overlay(alignment: calloutAlignment) {
            if pressed {
                callout
                    .frame(
                        width: (width * MergedKey.calloutWidthRatio).rounded(),
                        height: metrics.calloutHeight
                    )
                    .offset(y: -metrics.calloutLift)
                    .allowsHitTesting(false)
            }
        }
        .keyboardTouchTarget(
            id: touchID,
            callbacks: KeyboardTouchCallbacks(
                began: { location in
                    pressed = true
                    beginLongPressSelectionIfNeeded()
                    primaryWeight = mode == .fuzzy
                        ? MergedKey.primaryWeight(at: location.x, width: width)
                        : nil
                    if !longPressSelectedSecondary {
                        resolved = MergedKey.resolution(ofDrag: .zero, in: letters, mode: mode)
                    }
                },
                moved: { translation in
                    if MergedKey.isSwipe(translation) {
                        cancelLongPressSelection()
                        resolved = MergedKey.resolution(
                            ofDrag: translation,
                            in: letters,
                            mode: mode
                        )
                    } else if !longPressSelectedSecondary {
                        resolved = MergedKey.resolution(
                            ofDrag: translation,
                            in: letters,
                            mode: mode
                        )
                    }
                },
                ended: { _, cancelled in
                    if !cancelled { action(resolved ?? letters, resolved == nil ? primaryWeight : nil) }
                    cancelLongPressSelection()
                    pressed = false
                    resolved = nil
                    primaryWeight = nil
                }
            )
        )
        .onDisappear { cancelLongPressSelection() }
    }

    private func beginLongPressSelectionIfNeeded() {
        guard mode == .primary, letters.count == 2, longPressTask == nil else { return }
        longPressTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            longPressSelectedSecondary = true
            resolved = String(letters.suffix(1))
        }
    }

    private func cancelLongPressSelection() {
        longPressTask?.cancel()
        longPressTask = nil
        longPressSelectedSecondary = false
    }

    private var calloutAlignment: Alignment {
        switch anchor {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }

    private var letterSpacing: CGFloat {
        mode == .fuzzy && letters.count == 2 ? metrics.letterFontSize * 0.5 : 1
    }

    private var callout: some View {
        KeyFace(kind: .letter, pressed: false) {
            HStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, character in
                    let letter = String(character)
                    Text(label(for: letter))
                        .font(.system(size: fontSize(at: index, boost: Self.calloutFontBoost)))
                        .opacity(calloutOpacity(at: index, letter: letter))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    resolved == letter
                                        ? Color.primary.opacity(Self.selectionOpacity)
                                        : Color.clear
                                )
                        )
                }
            }
            .padding(3)
        }
    }

    private func label(for letter: String) -> String {
        uppercase ? letter.uppercased() : letter
    }

    private func fontSize(at index: Int, boost: CGFloat) -> CGFloat {
        let base = metrics.letterFontSize + boost
        guard letters.count == 2 else { return base }
        if mode == .fuzzy, boost > 0, let primaryWeight {
            return base + MergedKey.calloutFontOffset(
                primaryWeight: primaryWeight,
                index: index
            )
        }
        guard mode == .primary else { return base }
        return index == 0 ? base + Self.primaryFontBoost : base - Self.secondaryFontDrop
    }

    private func calloutOpacity(at index: Int, letter: String) -> CGFloat {
        if let resolved { return resolved == letter ? 1 : Self.dimmedOpacity }
        guard mode == .fuzzy, let primaryWeight else { return 1 }
        return MergedKey.calloutOpacity(primaryWeight: primaryWeight, index: index)
    }

    /// Once a gesture has resolved, the letter it picked reads at full strength and
    /// the other recedes, whichever side it was on.
    private func opacity(at index: Int, letter: String) -> CGFloat {
        if let resolved {
            return resolved == letter ? 1 : Self.dimmedOpacity
        }
        guard mode == .primary, letters.count == 2, index == 1 else { return 1 }
        return Self.secondaryOpacity
    }
}

struct SymbolKeyCap: View {
    let label: String
    let options: [String]
    let extendsRight: Bool
    let width: CGFloat
    let keyOrigin: CGFloat
    let contentWidth: CGFloat
    let metrics: KeyboardMetrics
    let action: (String) -> Void

    @State private var pressed = false
    @State private var expanded = false
    @State private var selection = 0
    @State private var reveal: Task<Void, Never>?
    @State private var touchID = UUID().uuidString

    private static let holdDelay: Duration = .milliseconds(300)
    private static let selectionOpacity: CGFloat = 0.12
    private static let badgeFontRatio: CGFloat = 0.6

    var body: some View {
        KeyFace(kind: .letter, pressed: pressed) {
            KeyLabel.text(label)
                .view(letterSize: metrics.letterFontSize, labelSize: metrics.labelFontSize)
        }
        .frame(width: width, height: metrics.keyHeight)
        .overlay(alignment: .topLeading) {
            if expanded {
                alternatesRow
                    .offset(x: rowOffsetX, y: -metrics.calloutLift)
                    .allowsHitTesting(false)
            }
        }
        .keyboardTouchTarget(
            id: touchID,
            callbacks: KeyboardTouchCallbacks(
                began: { _ in
                    pressed = true
                    startReveal()
                },
                moved: { movement in
                    let translation = movement.width
                    if !expanded, abs(translation) >= MergedKey.swipeThreshold {
                        expanded = true
                    }
                    selection = SymbolAlternates.selection(
                        ofSwipe: translation,
                        options: options.count,
                        cellWidth: width,
                        extendsRight: extendsRight
                    )
                },
                ended: { _, cancelled in
                    if !cancelled { action(options[min(selection, options.count - 1)]) }
                    finish()
                }
            )
        )
        .onDisappear(perform: finish)
    }

    /// Cells run away from the key, so the tapped option stays under the finger.
    private var alternatesRow: some View {
        KeyFace(kind: .letter, pressed: false) {
            HStack(spacing: 0) {
                ForEach(visualOrder, id: \.self) { option in
                    Text(option)
                        .font(.system(size: metrics.labelFontSize + 2))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) { widthBadge(option) }
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    option == options[selection]
                                        ? Color.primary.opacity(Self.selectionOpacity)
                                        : Color.clear
                                )
                        )
                }
            }
            .padding(3)
        }
        .frame(width: width * CGFloat(options.count), height: metrics.calloutHeight)
    }

    @ViewBuilder
    private func widthBadge(_ option: String) -> some View {
        if let badge = SymbolWidth.badge(for: option, among: options) {
            Text(badge)
                .font(.system(size: metrics.labelFontSize * Self.badgeFontRatio))
                .foregroundStyle(.secondary)
                .padding(.trailing, 1)
        }
    }

    private var rowOffsetX: CGFloat {
        SymbolAlternates.rowLeading(
            keyOrigin: keyOrigin,
            keyWidth: width,
            options: options.count,
            extendsRight: extendsRight,
            contentWidth: contentWidth
        ) - keyOrigin
    }

    private var visualOrder: [String] {
        extendsRight ? options : options.reversed()
    }

    private func startReveal() {
        reveal?.cancel()
        reveal = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled, pressed else { return }
            expanded = true
        }
    }

    private func finish() {
        reveal?.cancel()
        reveal = nil
        pressed = false
        expanded = false
        selection = 0
    }
}
