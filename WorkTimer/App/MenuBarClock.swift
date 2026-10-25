//
//  MenuBarClock.swift
//  WorkTimer
//

import Foundation
import Observation

/// Keeps the menu bar label ("● 18:42") current.
///
/// Views in a window can redraw themselves with `TimelineView`, but the menu
/// bar label is turned into a static image by macOS, so something has to
/// change an observed value for it to redraw. This object samples the engine
/// four times a second while a clock is moving, and only publishes when the
/// label would actually look different, so the menu bar redraws once a second.
@Observable
final class MenuBarClock {
    private(set) var glance: Glance

    @ObservationIgnored private let engine: TimerEngine
    @ObservationIgnored private let ui: UIModel
    @ObservationIgnored private var timer: Timer?

    init(engine: TimerEngine, ui: UIModel) {
        self.engine = engine
        self.ui = ui
        glance = Glance(engine: engine, ui: ui)
        stateChanged()
    }

    /// `withObservationTracking` calls `onChange` once, the first time
    /// anything read inside `apply` changes; so it is re-armed on every change.
    private func watchState() {
        withObservationTracking {
            _ = engine.state
            _ = engine.notice
        } onChange: { [weak self] in
            // `onChange` runs just *before* the new value is stored; hop to the
            // next main-actor turn to read the new state.
            Task { @MainActor [weak self] in self?.stateChanged() }
        }
    }

    private func stateChanged() {
        update()
        retime()
        watchState()
    }

    private func update() {
        let fresh = Glance(engine: engine, ui: ui)
        if fresh != glance { glance = fresh }
    }

    private func retime() {
        timer?.invalidate()
        timer = nil
        switch engine.state.phase {
        case .running, .timeUp, .onBreak:
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
            timer.tolerance = 0.05
            // `.common` keeps it firing while a menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        default:
            break  // nothing on the label moves
        }
    }
}
