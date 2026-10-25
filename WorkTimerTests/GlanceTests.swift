//
//  GlanceTests.swift
//  WorkTimerTests
//

import AppKit
import Foundation
import Testing
@testable import WorkTimer

/// The compact card, mini pill and menu bar all read `Glance`; these check it
/// says the right thing in each state, plus the window-mode keys.
@MainActor
struct GlanceTests {
    let h = Harness()
    let ui: UIModel

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: "WorkTimerTests.glance.\(UUID().uuidString)"))
        ui = UIModel(engine: h.engine, defaults: defaults)
    }

    private var glance: Glance { Glance(engine: h.engine, ui: ui) }

    @Test func readyShowsTheDraftAndNoMenuBarTime() {
        ui.task = "Write tests"
        ui.duration = .preset(50)
        #expect(glance.status == "READY")
        #expect(glance.clock == "50:00")
        #expect(glance.menuBarTime == nil, "the menu bar shows just the glyph")
        #expect(glance.title == "Write tests")
    }

    @Test func runningCountsDownInTheMenuBar() {
        ui.task = "Write tests"
        ui.commit()
        h.advance(6 * 60 + 18)
        #expect(glance.marker == .live)
        #expect(glance.status == "FOCUSING")
        #expect(glance.menuBarTime == "18:42")
        #expect(abs(glance.fill - 1122.0 / 1500) < 0.001, "hairline shows time left")
    }

    @Test func openEndedCountsUp() {
        ui.task = "Explore"
        ui.duration = .noLimit
        ui.commit()
        h.advance(65)
        #expect(glance.status == "TRACKING")
        #expect(glance.menuBarTime == "1:05")
        #expect(glance.fill == 0)
    }

    @Test func pausedIsAmberAndKeepsTheTime() {
        ui.task = "Task"
        ui.commit()
        h.advance(60)
        h.engine.pause()
        h.advance(30)
        #expect(glance.marker == .paused)
        #expect(glance.isAmber)
        #expect(glance.status == "PAUSED · 0:30")
        #expect(glance.menuBarTime == "24:00")
    }

    @Test func timeUpShowsOvertime() {
        ui.task = "Task"
        ui.commit()
        h.advance(25 * 60 + 12)
        #expect(glance.marker == .alert)
        #expect(glance.menuBarTime == "+0:12")
        #expect(glance.clock == "00:00")
    }

    @Test func breakIsAmberWithItsOwnTitle() {
        h.engine.startBreak()
        h.advance(60)
        #expect(glance.marker == .breakTime)
        #expect(glance.menuBarTime == "4:00")
        #expect(glance.title == "Step away from the screen")
    }

    @Test func reviewHasNoMenuBarTime() {
        ui.task = "Task"
        ui.commit()
        h.advance(600)
        h.engine.finish()
        #expect(glance.status == "REVIEW")
        #expect(glance.menuBarTime == nil)
    }

    // MARK: Window modes

    @Test func commandBackslashCyclesFullCompactMini() {
        #expect(WindowModes.Mode.full.next == .compact)
        #expect(WindowModes.Mode.compact.next == .mini)
        #expect(WindowModes.Mode.mini.next == .full)
        #expect(WindowModes.Mode.compact.panelSize == CGSize(width: 308, height: 160))
        #expect(WindowModes.Mode.mini.panelSize == CGSize(width: 308, height: 40))
    }

    @Test func thePanelOnlyTakesSpaceAndCommandBackslash() {
        let keyboard = KeyboardController(ui: ui)
        ui.task = "Task"
        ui.commit()
        #expect(keyboard.perform(KeyPress(key: " ", isInPanel: true)))
        #expect(h.engine.state.phase == .paused)
        #expect(keyboard.perform(KeyPress(key: "r", isInPanel: true)) == false, "no reset from the panel")
        #expect(keyboard.perform(KeyPress(key: "\r", keyCode: 36, modifiers: .command, isInPanel: true)) == false,
                "⌘↵ would finish a session the panel can't review")
        #expect(h.engine.state.phase == .paused)
        #expect(keyboard.perform(KeyPress(key: "\\", modifiers: .command, isInPanel: true)))
    }

    @Test func spaceInThePanelDoesNothingOnReady() {
        let keyboard = KeyboardController(ui: ui)
        ui.task = "Task"
        #expect(keyboard.perform(KeyPress(key: " ", isInPanel: true)) == false)
        #expect(h.engine.state == .ready)
    }

    // MARK: Menu bar label

    @Test func menuBarClockFollowsStateChanges() async {
        let clock = MenuBarClock(engine: h.engine, ui: ui)
        #expect(clock.glance.menuBarTime == nil)
        ui.task = "Task"
        ui.commit()
        // The clock re-reads on the next main-actor turn after a change.
        await Task.yield()
        await Task.yield()
        #expect(clock.glance.marker == .live)
        #expect(clock.glance.menuBarTime == "25:00")
        h.engine.pause()
        await Task.yield()
        await Task.yield()
        #expect(clock.glance.marker == .paused)
    }
}
