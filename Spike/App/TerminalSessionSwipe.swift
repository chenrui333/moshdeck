import MoshDeckCore
import UIKit

/// Competes with Ghostty's direct-touch scroll pan on the same view. Vertical
/// intent fails this recognizer, releasing the original scroll recognizer. A
/// horizontal drag is consumed here and must not also become terminal mouse I/O.
@MainActor
final class TerminalSessionSwipe: NSObject, UIGestureRecognizerDelegate {
    enum Phase { case began, changed, ended, cancelled }
    var enabled: () -> Bool = { false }
    var update: (Phase, CGPoint, CGFloat, CGFloat) -> Void = { _, _, _, _ in }
    private weak var view: UIView?

    init(view: UIView) {
        self.view = view
        super.init()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        for existing in view.gestureRecognizers ?? [] {
            guard let scroll = existing as? UIPanGestureRecognizer,
                scroll.allowedScrollTypesMask.isEmpty,
                scroll.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.direct.rawValue))
            else { continue }
            scroll.require(toFail: pan)
        }
        view.addGestureRecognizer(pan)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        enabled()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard enabled(), let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: view)
        return SessionSwipe.isHorizontal(x: velocity.x, y: velocity.y)
    }

    @objc private func drag(_ pan: UIPanGestureRecognizer) {
        guard let view else { return }
        let phase: Phase
        switch pan.state {
        case .began: phase = .began
        case .changed: phase = .changed
        case .ended: phase = .ended
        default: phase = .cancelled
        }
        update(enabled() ? phase : .cancelled, pan.translation(in: view), pan.velocity(in: view).x, view.bounds.width)
    }
}
