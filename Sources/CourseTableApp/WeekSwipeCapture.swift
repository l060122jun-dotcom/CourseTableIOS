import SwiftUI
import UIKit

/// Observe horizontal pans alongside the enclosing vertical scroll view.
/// The hit region is restricted to the timetable, excluding the week strip.
struct WeekSwipeCapture: UIViewRepresentable {
    var onSwipe: (Int) -> Void

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onSwipe = onSwipe
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CaptureView, context: Context) {
        view.onSwipe = onSwipe
    }

    static func dismantleUIView(_ view: CaptureView, coordinator: ()) {
        view.detach()
    }

    final class CaptureView: UIView, UIGestureRecognizerDelegate {
        var onSwipe: ((Int) -> Void)?
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
            guard recognizer.state == .ended else { return }
            let movement = recognizer.translation(in: self)
            guard abs(movement.x) >= 40, abs(movement.x) > abs(movement.y) * 1.3 else { return }
            onSwipe?(movement.x < 0 ? 1 : -1)
        }
    }
}
