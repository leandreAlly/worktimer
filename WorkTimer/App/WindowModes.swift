//
//  WindowModes.swift
//  WorkTimer
//

import AppKit
import Observation
import SwiftUI

/// Switches between the full window and the two small floating ones
/// ("Compact" artboard): ⌘\ goes full → compact → mini → full.
///
/// The compact and mini views live in one borderless `NSPanel` that changes
/// size. A panel (rather than a SwiftUI `Window`) is used because SwiftUI
/// windows always get a title bar and the system's square-ish frame; the
/// design wants a 12 pt-rounded card and a fully rounded 40 pt pill.
@Observable
final class WindowModes {
    enum Mode: Equatable {
        case full, compact, mini

        var next: Mode {
            switch self {
            case .full: .compact
            case .compact: .mini
            case .mini: .full
            }
        }

        var panelSize: CGSize {
            switch self {
            case .full: .zero
            case .compact: CGSize(width: 308, height: 160)
            case .mini: CGSize(width: 308, height: 40)
            }
        }
    }

    private(set) var mode: Mode = .full

    /// SwiftUI's `openWindow` action, captured by the first view that appears.
    /// Needed when the user has closed the main window: AppKit can't recreate
    /// a SwiftUI scene's window, only SwiftUI can.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored private var panel: FloatingPanel?
    /// Builds the panel's SwiftUI content; set by `AppModel` so the panel gets
    /// the same engine and UI model as the main window.
    @ObservationIgnored var makePanelContent: (() -> AnyView)?
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private var keyObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // If the main window comes back some other way (clicking the Dock
        // icon, the Window menu), leave compact mode so both never show.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, self.mode != .full,
                      window?.identifier?.rawValue.hasPrefix(MainWindow.id) == true else { return }
                self.mode = .full
                self.panel?.orderOut(nil)
            }
        }
    }

    func cycle() { show(mode.next) }

    func show(_ newMode: Mode) {
        mode = newMode
        switch newMode {
        case .full:
            panel?.orderOut(nil)
            showMainWindow()
        case .compact, .mini:
            mainWindow?.orderOut(nil)
            showPanel(size: newMode.panelSize)
        }
    }

    /// Bring the full window forward from anywhere (menu bar, notification).
    func showMainWindow() {
        if mode != .full {
            mode = .full
            panel?.orderOut(nil)
        }
        NSApp.activate()
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(MainWindow.id) == true }
    }

    func isPanel(_ window: NSWindow?) -> Bool {
        window != nil && window === panel
    }

    // MARK: Floating

    /// The small windows float above other apps unless unpinned.
    var panelFloats: Bool {
        get {
            access(keyPath: \.panelFloats)
            return defaults.object(forKey: AppSettings.compactFloatOnTop) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.panelFloats) {
                defaults.set(newValue, forKey: AppSettings.compactFloatOnTop)
            }
            panel?.level = newValue ? .floating : .normal
        }
    }

    // MARK: Panel

    private func showPanel(size: CGSize) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.level = panelFloats ? .floating : .normal

        // Keep the top-left corner fixed when switching compact ↔ mini, so the
        // card shrinks into the pill where the user put it. AppKit's y axis
        // points up, hence the maxY arithmetic.
        var frame = panel.frame
        // A saved spot on a display that's since been unplugged doesn't count.
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if frame.size == .zero || !panel.hasBeenPlaced || !onScreen {
            let screen = (mainWindow?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            frame = NSRect(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 20,
                           width: size.width, height: size.height)
            panel.hasBeenPlaced = true
        } else {
            frame = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> FloatingPanel {
        let content = makePanelContent?() ?? AnyView(EmptyView())
        let panel = FloatingPanel(content: NSHostingView(rootView: content))
        panel.setFrameAutosaveName("CompactPanel")
        panel.hasBeenPlaced = panel.frame.size != .zero && panel.frame.width > 1
        return panel
    }
}

/// A borderless, see-through window that SwiftUI draws the rounded card into.
final class FloatingPanel: NSPanel {
    /// False until the panel has a position (saved or computed).
    var hasBeenPlaced = false

    init(content: NSView) {
        // `.nonactivatingPanel`: clicking Pause in the floating timer doesn't
        // pull WorkTimer in front of the editor the user is working in.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Stay visible on every Space and over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentView = content
    }

    // Borderless windows refuse key status by default, which would stop the
    // Space and ⌘\ shortcuts from reaching it.
    override var canBecomeKey: Bool { true }
}
