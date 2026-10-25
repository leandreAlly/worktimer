//
//  MenuBarViews.swift
//  WorkTimer
//

import AppKit
import SwiftUI

/// The menu bar item: a marker and the time while a clock is running
/// ("● 18:42"), otherwise just the timer glyph.
struct MenuBarLabel: View {
    let clock: MenuBarClock
    @AppStorage(AppSettings.showMenuBarTime) private var showTime = true

    var body: some View {
        let glance = clock.glance
        if showTime, let time = glance.menuBarTime {
            // The menu bar only draws an image plus text; anything fancier is
            // ignored, so the marker is a tiny template image.
            HStack(spacing: 5) {
                Image(nsImage: MenuBarGlyph.image(for: glance.marker))
                Text(time).monospacedDigit()
            }
            .accessibilityLabel("WorkTimer, \(glance.status.lowercased()), \(time)")
        } else {
            Image(systemName: "timer")
                .accessibilityLabel("WorkTimer")
        }
    }
}

/// Small black-and-clear "template" images; macOS tints them to match the
/// menu bar (dark, light, or the highlighted state when clicked).
enum MenuBarGlyph {
    @MainActor private static var cache: [Glance.Marker: NSImage] = [:]

    @MainActor
    static func image(for marker: Glance.Marker) -> NSImage {
        if let image = cache[marker] { return image }
        let image = NSImage(size: NSSize(width: 7, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let mid = rect.midY
            switch marker {
            case .live, .breakTime:
                NSBezierPath(ovalIn: NSRect(x: 0.5, y: mid - 3, width: 6, height: 6)).fill()
            case .paused:
                NSRect(x: 1, y: mid - 4, width: 2, height: 8).fill()
                NSRect(x: 4.5, y: mid - 4, width: 2, height: 8).fill()
            case .alert:
                NSRect(x: 0.5, y: mid - 3, width: 6, height: 6).fill()
            case .idle, .review:
                let ring = NSBezierPath(ovalIn: NSRect(x: 1, y: mid - 2.5, width: 5, height: 5))
                ring.lineWidth = 1
                ring.stroke()
            }
            return true
        }
        image.isTemplate = true
        cache[marker] = image
        return image
    }
}

/// The popover under the menu bar item: the compact card, then the actions
/// that make sense right now, then window and quit.
struct MenuBarContent: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(UIModel.self) private var ui
    @Environment(WindowModes.self) private var modes
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppSettings.theme) private var theme = ThemeChoice.dark

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 0.25, paused: engine.state.phase == .paused)) { _ in
                CompactCard(glance: Glance(engine: engine, ui: ui), showsWindowButtons: false)
            }
            VStack(spacing: 0) {
                stateActions
                MenuDivider()
                if modes.mode == .full {
                    MenuRow("Show WorkTimer") { modes.showMainWindow() }
                    MenuRow("Compact window", hint: "⌘\\") { modes.show(.compact) }
                } else {
                    MenuRow("Full window", hint: "⌘\\") { modes.show(.full) }
                }
                MenuRow("History", hint: "⌘Y") {
                    NSApp.activate()
                    openWindow(id: HistoryWindow.id)
                }
                MenuDivider()
                MenuRow("Quit WorkTimer", hint: "⌘Q") { NSApp.terminate(nil) }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(width: 308)
        .foregroundStyle(Palette.paper)
        .background(Palette.ground)
        .preferredColorScheme(theme.colorScheme)
        .onAppear { modes.openMainWindow = { openWindow(id: MainWindow.id) } }
    }

    @ViewBuilder private var stateActions: some View {
        switch engine.state {
        case .ready:
            if ui.canCommit {
                MenuRow("Start “\(ui.task)”", hint: ui.selectedMinutes == 0 ? "NO LIMIT" : "\(ui.selectedMinutes) MIN") {
                    ui.commit()
                }
            } else {
                MenuRow("New session…") { modes.showMainWindow() }
            }
        case .running(let run):
            MenuRow("Pause") { engine.pause() }
            if !run.isOpenEnded {
                MenuRow("Add 5 minutes") { engine.extend(minutes: 5) }
            }
            MenuRow("Finish & log") { finishAndReview() }
        case .paused:
            MenuRow("Resume") { engine.resume() }
            MenuRow("Finish & log") { finishAndReview() }
        case .timeUp:
            MenuRow("Review session") { finishAndReview() }
            MenuRow("Add 5 minutes") { engine.extend(minutes: 5) }
            MenuRow("5-min break") { engine.startBreak() }
        case .review:
            MenuRow("Review session") { modes.showMainWindow() }
        case .onBreak:
            MenuRow("End break") { engine.endBreak() }
        }
    }

    /// The review form lives in the full window, so go there.
    private func finishAndReview() {
        engine.finish()
        if engine.state.phase == .review { modes.showMainWindow() }
    }
}

/// A full-width, menu-like row with an optional key hint.
private struct MenuRow: View {
    let title: String
    var hint: String?
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, hint: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                if let hint {
                    Text(hint).font(.mono(10)).tracking(0.8).foregroundStyle(Palette.mute)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(hovering ? Palette.toggleOnFill : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(Palette.rule).frame(height: 1).padding(.vertical, 5).padding(.horizontal, 8)
    }
}
