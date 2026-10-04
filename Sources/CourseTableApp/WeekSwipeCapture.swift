import SwiftUI
import UIKit

/// Observe horizontal pans alongside the enclosing vertical scroll view.
/// The hit region is restricted to the timetable, excluding the week strip.
struct WeekSwipeCapture: UIViewRepresentable {
    var onSwipe: (Int) -> Void
    var onDrag: (CGFloat) -> Void
    var onRelease: () -> Void

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onSwipe = onSwipe
        view.onDrag = onDrag
        view.onRelease = onRelease
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CaptureView, context: Context) {
        view.onSwipe = onSwipe
        view.onDrag = onDrag
        view.onRelease = onRelease
    }

    static func dismantleUIView(_ view: CaptureView, coordinator: ()) {
        view.detach()
    }

    final class CaptureView: UIView, UIGestureRecognizerDelegate {
        var onSwipe: ((Int) -> Void)?
        var onDrag: ((CGFloat) -> Void)?
        var onRelease: (() -> Void)?
        private weak var host: UIScrollView?
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.maximumNumberOfTouches = 1
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() }
            else { attach() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if window != nil { attach() }
        }

        private func attach() {
            var parent = superview
            while let candidate = parent {
                if let scroll = candidate as? UIScrollView {
                    if host !== scroll {
                        detach()
                        host = scroll
                        scroll.addGestureRecognizer(pan)
                    }
                    return
                }
                parent = candidate.superview
            }
        }

        func detach() {
            host?.removeGestureRecognizer(pan)
            host = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: self)
            return bounds.contains(pan.location(in: self)) && abs(velocity.x) > abs(velocity.y) * 1.3
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let movement = recognizer.translation(in: host)
            switch recognizer.state {
            case .began, .changed:
                onDrag?(movement.x)
            case .ended:
                if abs(movement.x) >= 40, abs(movement.x) > abs(movement.y) * 1.3 {
                    onSwipe?(movement.x < 0 ? 1 : -1)
                }
                onRelease?()
            case .cancelled, .failed:
                onRelease?()
            default: break
            }
        }
    }
}
