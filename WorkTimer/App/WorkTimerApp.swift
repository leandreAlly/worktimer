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
        WindowGroup {
            ContentView()
                // Makes the engine available to any view via
                // `@Environment(TimerEngine.self)`.
                .environment(model.engine)
        }
        .modelContainer(model.container)
    }
}
