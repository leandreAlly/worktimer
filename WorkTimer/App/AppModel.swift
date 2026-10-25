//
//  AppModel.swift
//  WorkTimer
//

import Foundation
import SwiftData

/// Builds the app's long-lived objects once and hands them to every scene.
/// The main window and the menu bar receive the same `engine`, so an action in
/// one shows up in the other immediately.
final class AppModel {
    let container: ModelContainer
    let engine: TimerEngine

    init() {
        do {
            // Stored in the app's sandboxed Application Support folder.
            container = try ModelContainer(for: WorkSession.self)
        } catch {
            // Without its database the app can't do its job; failing loudly
            // beats silently losing history.
            fatalError("Could not open the session database: \(error)")
        }
        engine = TimerEngine(
            recorder: SessionStore(context: container.mainContext),
            stateStore: ActiveStateStore(),
            scheduler: TaskWakeScheduler()
        )
    }
}
