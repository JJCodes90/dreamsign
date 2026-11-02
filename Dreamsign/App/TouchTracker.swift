import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Remembers when the screen was last touched anywhere in the app, without getting in the
/// way of any gesture. Used to skip the wake-up check for someone who's plainly using the app.
@MainActor
final class TouchTracker {
    static let shared = TouchTracker()
    private(set) var lastTouch = Date.distantPast

    func touchedRecently(within seconds: TimeInterval, now: Date = .now) -> Bool {
        now.timeIntervalSince(lastTouch) <= seconds
    }

    fileprivate func noteTouch() { lastTouch = .now }
}

/// A recognizer that observes touches and immediately fails, so it never blocks anything.
private final class TouchSpy: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        TouchTracker.shared.noteTouch()
        state = .failed
    }
}

private final class TouchSpyHost: UIView {
    private weak var installedOn: UIWindow?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, installedOn !== window else { return }
        let spy = TouchSpy(target: nil, action: nil)
        spy.cancelsTouchesInView = false
        spy.delaysTouchesBegan = false
        spy.delaysTouchesEnded = false
        window.addGestureRecognizer(spy)
        installedOn = window
    }
}

private struct TouchSpyInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchSpyHost {
        let view = TouchSpyHost()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: TouchSpyHost, context: Context) {}
}

extension View {
    /// Installs the app-wide touch observer on this view's window.
    func tracksTouches() -> some View {
        background(TouchSpyInstaller().allowsHitTesting(false))
    }
}
