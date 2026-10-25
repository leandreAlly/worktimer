//
//  MainWindow.swift
//  WorkTimer
//

import AppKit
import SwiftUI

enum MainWindow {
    /// Scene id; SwiftUI also uses it as the prefix of the NSWindow identifier.
    static let id = "main"
    static let size = CGSize(width: 880, height: 560)
    static let headerHeight: CGFloat = 52
}

/// Reaches the underlying `NSWindow` for the few things SwiftUI can't set:
/// floating above other windows, and where the traffic lights sit.
struct WindowConfigurator: NSViewRepresentable {
    var floatOnTop: Bool

    func makeNSView(context: Context) -> NSView { TrackingView() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? TrackingView)?.floatOnTop = floatOnTop
    }

    /// Applies the settings whenever it joins a window or they change.
    final class TrackingView: NSView {
        var floatOnTop = false { didSet { configure() } }
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // AppKit puts the traffic lights back after some layout passes
            // (resize, focus change, leaving full screen); move them again.
            for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.positionTrafficLights() }
                })
            }
            configure()
        }

        private func configure() {
            guard let window else { return }
            window.level = floatOnTop ? .floating : .normal
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            lockSize(window)
            positionTrafficLights()
        }

        /// The design is a fixed 880 × 560 composition. SwiftUI would add the
        /// hidden title bar's height on top, so the frame is set here directly
        /// and resizing is turned off. The title bar is 28 pt on macOS 14–15
        /// and 32 pt later, which is why it can't just be subtracted in SwiftUI.
        private func lockSize(_ window: NSWindow) {
            let size = MainWindow.size
            window.styleMask.remove(.resizable)
            window.minSize = size
            window.maxSize = size
            guard window.frame.size != size else { return }
            // Keep the top-left corner where it is (AppKit's y axis points up).
            let top = window.frame.maxY
            window.setFrame(NSRect(x: window.frame.minX, y: top - size.height,
                                   width: size.width, height: size.height), display: true)
        }

        /// The design centers the window buttons in its 52 pt header, 20 pt
        /// from the left edge, instead of the standard 28 pt title bar.
        private func positionTrafficLights() {
            guard let window,
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview,
                  let container = titlebar.superview else { return }
            let height = MainWindow.headerHeight
            container.frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
            titlebar.frame = container.bounds
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in buttons.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                button.setFrameOrigin(NSPoint(x: 20 + CGFloat(index) * 20,
                                              y: ((height - button.frame.height) / 2).rounded()))
            }
        }
    }
}
