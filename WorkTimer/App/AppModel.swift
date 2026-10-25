//
//  AppModel.swift
//  WorkTimer
//

import Foundation
import SwiftData

/// Builds the app's long-lived objects once and hands them to every scene.
/// The main window and the menu bar receive the same `engine` and `ui`, so an
/// action in one shows up in the other immediately.
final class AppModel {
    let container: ModelContainer
    let engine: TimerEngine
    let ui: UIModel
    let keyboard: KeyboardController

    init() {
        // Fonts first, so the very first frame already uses Inter Tight.
        Typography.registerBundledFonts()

        var inMemory = false
        var stateStore: ActiveStateStoring = ActiveStateStore()
        var draftDefaults = UserDefaults.standard
        #if DEBUG
        // Unit tests run inside a copy of the app. That copy must never open
        // the real timer state or history, especially while the real app is
        // running beside it.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            inMemory = true
            stateStore = PreviewStateStore(.ready)
            draftDefaults = UserDefaults(suiteName: "WorkTimer.tests") ?? .standard
        }
        if let preview = PreviewLaunch.requestedState {
            inMemory = true
            stateStore = PreviewStateStore(PreviewLaunch.state(named: preview, clock: SystemTimeSource()))
            draftDefaults = UserDefaults(suiteName: "WorkTimer.preview") ?? .standard
            draftDefaults.set(PreviewLaunch.task, forKey: AppSettings.lastTask)
            draftDefaults.set("preset:25", forKey: AppSettings.lastDuration)
        }
        #endif

        do {
            // Stored in the app's sandboxed Application Support folder.
            container = try ModelContainer(
                for: WorkSession.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
            )
        } catch {
            // Without its database the app can't do its job; failing loudly
            // beats silently losing history.
            fatalError("Could not open the session database: \(error)")
        }
        engine = TimerEngine(
            recorder: SessionStore(context: container.mainContext),
            stateStore: stateStore,
            scheduler: TaskWakeScheduler()
        )
        ui = UIModel(engine: engine, defaults: draftDefaults)
        keyboard = KeyboardController(ui: ui)
        keyboard.install()
    }
}
