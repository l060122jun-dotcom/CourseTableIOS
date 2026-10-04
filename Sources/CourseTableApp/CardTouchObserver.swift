import SwiftUI
import UIKit

/// Passive touch observation: never recognizes or cancels scrolling/button taps.
struct CardTouchObserver: UIViewRepresentable {
    var onTouch: (Bool) -> Void

    func makeUIView(context: Context) -> TouchRegion {
        let view = TouchRegion()
        view.isUserInteractionEnabled = false
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: TouchRegion, context: Context) { view.onTouch = onTouch }
    static func dismantleUIView(_ view: TouchRegion, coordinator: ()) { view.detach() }

    final class TouchRegion: UIView {
        var onTouch: ((Bool) -> Void)?
        private var observer: PassiveTouch?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let recognizer = PassiveTouch(target: nil, action: nil)
            recognizer.region = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            window.addGestureRecognizer(recognizer)
            observer = recognizer
        }

        func detach() {
            if let observer { observer.view?.removeGestureRecognizer(observer) }
            observer = nil
            onTouch?(false)
        }
    }

    final class PassiveTouch: UIGestureRecognizer {
        weak var region: TouchRegion?
        private var active = false
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let region, let touch = touches.first,
                  region.bounds.contains(touch.location(in: region)) else {
                state = .failed
                return
            }
            active = true
            region.onTouch?(true)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish() }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish() }
        private func finish() {
            if active { region?.onTouch?(false) }
            active = false
            state = .failed
        }
        override func reset() {
            if active { region?.onTouch?(false) }
            active = false
            super.reset()
        }
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
