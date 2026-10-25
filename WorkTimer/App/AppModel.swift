//
//  AppModel.swift
//  WorkTimer
//

import AppKit
import Foundation
import SwiftData
import SwiftUI

/// Builds the app's long-lived objects once and hands them to every scene.
/// The main window, the floating panel and the menu bar receive the same
/// `engine` and `ui`, so an action in one shows up in the others immediately.
final class AppModel {
    let container: ModelContainer
    let engine: TimerEngine
    let ui: UIModel
    let keyboard: KeyboardController
    let modes: WindowModes
    let menuBarClock: MenuBarClock

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        // Fonts first, so the very first frame already uses Inter Tight.
        Typography.registerBundledFonts()
        AppSettings.registerDefaults(in: .standard)

        var inMemory = false
        var stateStore: ActiveStateStoring = ActiveStateStore()
        var draftDefaults = UserDefaults.standard
        var useSystemEffects = true
        #if DEBUG
        // Unit tests run inside a copy of the app. That copy must never open
        // the real timer state or history, especially while the real app is
        // running beside it.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            inMemory = true
            stateStore = PreviewStateStore(.ready)
            draftDefaults = UserDefaults(suiteName: "WorkTimer.tests") ?? .standard
            useSystemEffects = false
        }
        if let preview = PreviewLaunch.requestedState {
            inMemory = true
            stateStore = PreviewStateStore(PreviewLaunch.state(named: preview, clock: SystemTimeSource()))
            draftDefaults = UserDefaults(suiteName: "WorkTimer.preview") ?? .standard
            draftDefaults.set(PreviewLaunch.task, forKey: AppSettings.lastTask)
            draftDefaults.set("preset:25", forKey: AppSettings.lastDuration)
            // Silent unless asked for, so screenshot runs don't ring or notify.
            useSystemEffects = PreviewLaunch.wantsEffects
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

        let modes = WindowModes()
        let effects: TimerEffects
        if useSystemEffects {
            let system = SystemEffects()
            // Clicking a "Time's up" banner brings the full window forward.
            system.onOpen = { [weak modes] in modes?.showMainWindow() }
            effects = system
        } else {
            effects = NoTimerEffects()
        }

        let sessionStore = SessionStore(context: container.mainContext)
        #if DEBUG
        if PreviewLaunch.requestedState != nil {
            PreviewLaunch.sampleHistory().forEach(sessionStore.save)
        }
        #endif
        engine = TimerEngine(
            recorder: sessionStore,
            stateStore: stateStore,
            effects: effects,
            scheduler: TaskWakeScheduler()
        )
        ui = UIModel(engine: engine, defaults: draftDefaults)
        self.modes = modes
        menuBarClock = MenuBarClock(engine: engine, ui: ui)
        keyboard = KeyboardController(ui: ui, modes: modes)
        keyboard.install()

        // The floating panel is plain AppKit, so it gets the shared objects
        // passed in by hand instead of through a SwiftUI scene.
        modes.makePanelContent = { [engine, ui, modes] in
            AnyView(FloatingContent()
                .environment(engine)
                .environment(ui)
                .environment(modes))
        }

        observeSystemEvents()

        #if DEBUG
        if let mode = PreviewLaunch.windowMode {
            // After the main window exists, so there's something to hide.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [modes] in modes.show(mode) }
        }
        if PreviewLaunch.showsMenuContent {
            DispatchQueue.main.async { [engine, ui, modes] in
                PreviewLaunch.showMenuContent(MenuBarContent()
                    .environment(engine).environment(ui).environment(modes))
            }
        }
        #endif
    }

    /// Sleep, wake, quit and clock changes. The engine's numbers come from
    /// timestamps, so these only need to save or re-check, never to "catch up".
    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let app = NotificationCenter.default

        // Before sleeping, record the time worked so far, in case the Mac's
        // clock is changed or the battery dies before it wakes.
        observe(workspace, NSWorkspace.willSleepNotification) { $0.engine.checkpoint() }
        // A deadline may have passed during sleep: decide what happened now.
        observe(workspace, NSWorkspace.didWakeNotification) { $0.engine.refresh() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.engine.refresh() }
        observe(app, .NSSystemClockDidChange) { $0.engine.refresh() }
        observe(app, NSApplication.didBecomeActiveNotification) { $0.engine.refresh() }
        // ⌘Q, logout, restart: save what's in progress (and end overtime).
        observe(app, NSApplication.willTerminateNotification) { $0.engine.prepareForTermination() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping (AppModel) -> Void) {
        // `queue: .main` delivers on the main thread; `assumeIsolated` lets
        // the compiler know, so we may touch main-actor state.
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }
}
