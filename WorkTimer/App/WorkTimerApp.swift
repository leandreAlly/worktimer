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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(MainWindow.size)
        .windowResizability(.contentMinSize)
        .modelContainer(model.container)
    }
}
