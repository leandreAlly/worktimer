//
//  WorkTimerApp.swift
//  WorkTimer
//
//  Created by Ally leandre on 25/10/2026.
//

import SwiftData
import SwiftUI

@main
struct WorkTimerApp: App {
    // `@State` keeps one AppModel alive for the app's whole lifetime.
    @State private var model = AppModel()

    var body: some Scene {
        // `Window` (not `WindowGroup`): WorkTimer has exactly one main window,
        // so ⌘N can't spawn copies of the timer.
        Window("WorkTimer", id: MainWindow.id) {
            RootView()
                // Makes these available to any view via `@Environment(...)`.
                .environment(model.engine)
                .environment(model.ui)
                .environment(model.modes)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(MainWindow.size)
        .windowResizability(.contentMinSize)
        .modelContainer(model.container)
        .commands {
            // View menu: lists the shortcut so it can be discovered. The key
            // itself is handled by KeyboardController, which also sees it in
            // the floating panel.
            CommandGroup(before: .toolbar) {
                Button(model.modes.mode == .full ? "Compact Window" : "Next Window Size") {
                    model.modes.cycle()
                }
                .keyboardShortcut("\\", modifiers: .command)
                ShowHistoryButton()
                Divider()
            }
        }

        // History: a second, separate window, so it can sit beside the timer.
        Window("History", id: HistoryWindow.id) {
            HistoryView()
                .environment(model.engine)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(HistoryWindow.size)
        .windowResizability(.contentSize)
        .modelContainer(model.container)

        // The menu bar item. Its label stays in the menu bar for as long as
        // the app runs, so closing the main window doesn't stop the timer.
        MenuBarExtra {
            MenuBarContent()
                .environment(model.engine)
                .environment(model.ui)
                .environment(model.modes)
        } label: {
            MenuBarLabel(clock: model.menuBarClock)
        }
        // `.window` shows our SwiftUI view in a popover-style panel instead of
        // a plain menu.
        .menuBarExtraStyle(.window)
    }
}

/// View › Show History (⌘Y). A view, because only views can read SwiftUI's
/// `openWindow` action from the environment.
private struct ShowHistoryButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Show History") { openWindow(id: HistoryWindow.id) }
            .keyboardShortcut("y", modifiers: .command)
    }
}
