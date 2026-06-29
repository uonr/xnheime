import UIKit
import XCTest

@MainActor
final class KeyboardTouchSurfaceTests: XCTestCase {
    private let keyboardSize = CGSize(width: 402, height: 263)
    private let captureTop: CGFloat = 45

    func testEveryPixelBelowCandidateBarHasATarget() {
        let view = makeTouchView()

        for y in stride(from: captureTop, to: keyboardSize.height, by: 1) {
            for x in stride(from: 0, to: keyboardSize.width, by: 1) {
                XCTAssertNotNil(view.targetID(at: CGPoint(x: x, y: y)), "unassigned point: (\(x), \(y))")
            }
        }
    }

    func testUIKitHitTestingChoosesTouchSurfaceAtEveryVerticalSeam() {
        let container = UIView(frame: CGRect(origin: .zero, size: keyboardSize))
        let renderedKeyboard = UIView(frame: container.bounds)
        let touchView = makeTouchView()
        container.addSubview(renderedKeyboard)
        container.addSubview(touchView)

        for y: CGFloat in [100, 155, 210] {
            for x: CGFloat in [0, 40, 100, 200, 300, 361, 401] {
                let point = CGPoint(x: x, y: y)
                XCTAssertTrue(
                    container.hitTest(point, with: nil) === touchView,
                    "UIKit did not route seam to touch surface: (\(x), \(y))"
                )
            }
        }
    }

    func testCandidateBarIsNotCaptured() {
        let view = makeTouchView()

        XCTAssertNil(view.targetID(at: CGPoint(x: 200, y: captureTop - 1)))
        XCTAssertFalse(view.point(inside: CGPoint(x: 200, y: captureTop - 1), with: nil))
    }

    func testVisibleKeyFrameIsAnchoredToThatKey() {
        let view = makeTouchView()

        XCTAssertEqual(view.targetID(at: CGPoint(x: 20, y: 70)), "r0c0")
    }

    func testOverlappingTouchesMayBeginOnSameKey() {
        let view = KeyboardTouchSurface.TouchView(frame: CGRect(origin: .zero, size: keyboardSize))
        var beginCount = 0
        view.targets = [
            KeyboardTouchSurface.Target(
                id: "key",
                frame: view.bounds,
                callbacks: KeyboardTouchCallbacks(
                    began: { _ in beginCount += 1 },
                    ended: { _, _ in }
                )
            )
        ]
        let firstTouch = NSObject()
        let secondTouch = NSObject()

        view.beginTouch(identifier: ObjectIdentifier(firstTouch), at: CGPoint(x: 100, y: 100))
        view.beginTouch(identifier: ObjectIdentifier(secondTouch), at: CGPoint(x: 100, y: 100))

        XCTAssertEqual(beginCount, 2)
    }

    private func makeTouchView() -> KeyboardTouchSurface.TouchView {
        let view = KeyboardTouchSurface.TouchView(frame: CGRect(origin: .zero, size: keyboardSize))
        view.captureTop = captureTop
        view.targets = makeTargets()
        return view
    }

    private func makeTargets() -> [KeyboardTouchSurface.Target] {
        let rows: [(y: CGFloat, count: Int, inset: CGFloat)] = [
            (51, 10, 3),
            (106, 9, 20),
            (161, 9, 3),
            (216, 4, 3),
        ]
        return rows.enumerated().flatMap { rowIndex, row in
            let gap: CGFloat = 6
            let available = keyboardSize.width - row.inset * 2 - gap * CGFloat(row.count - 1)
            let width = available / CGFloat(row.count)
            return (0..<row.count).map { column in
                KeyboardTouchSurface.Target(
                    id: "r\(rowIndex)c\(column)",
                    frame: CGRect(
                        x: row.inset + CGFloat(column) * (width + gap),
                        y: row.y,
                        width: width,
                        height: 43
                    ),
                    callbacks: KeyboardTouchCallbacks(began: { _ in }, ended: { _, _ in })
                )
            }
        }
    }
}
