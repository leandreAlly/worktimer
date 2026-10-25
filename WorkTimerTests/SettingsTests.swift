//
//  SettingsTests.swift
//  WorkTimerTests
//

import AppKit
import Foundation
import Testing
@testable import WorkTimer

/// What each Settings switch changes, plus the presentation-mode keys.
@MainActor
struct SettingsTests {
    let h = Harness()
    let defaults: UserDefaults
    let ui: UIModel

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "WorkTimerTests.settings.\(UUID().uuidString)"))
        ui = UIModel(engine: h.engine, defaults: defaults)
    }

    // MARK: Show overtime

    @Test func withOvertimeOffZeroEndsTheSessionAtItsGoal() throws {
        h.engine.countsOvertime = false
        h.engine.start(task: "Task", minutes: 25)
        h.advance(25 * 60 + 1)
        #expect(h.engine.state.phase == .review, "no time's-up screen, no overtime")
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 25 * 60)
        #expect(record.goalCompleted)
        #expect(h.effects.chimes == [.workTimeUp(task: "Task")], "still chimes when seen live")
    }

    @Test func overtimeOffStillTreatsALateDeadlineAsCompletedWhileAway() {
        h.engine.countsOvertime = false
        h.engine.start(task: "Task", minutes: 25)
        h.advance(40 * 60)
        #expect(h.engine.notice == .completedWhileAway)
        #expect(h.effects.chimes.isEmpty, "nobody was there to hear it")
    }

    // MARK: Ask for a review

    @Test func withReviewsOffFinishingReturnsToReadyAndSaves() throws {
        h.engine.asksForReview = false
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        h.engine.finish()
        #expect(h.engine.state == .ready)
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 600)
        #expect(record.outcome == nil)
    }

    @Test func withReviewsAndOvertimeOffTheDeadlineGoesStraightToReady() {
        h.engine.asksForReview = false
        h.engine.countsOvertime = false
        h.engine.start(task: "Task", minutes: 25)
        h.advance(25 * 60)
        #expect(h.engine.state == .ready)
        #expect(h.recorder.records.count == 1)
    }

    // MARK: Presets and the opening duration

    @Test func presetsParseAndFallBack() {
        #expect(UIModel.parsePresets("15, 45, 120") == [15, 45, 120])
        #expect(UIModel.parsePresets(nil) == [25, 50, 90])
        #expect(UIModel.parsePresets("25,50") == [25, 50, 90], "needs exactly three")
        #expect(UIModel.parsePresets("0,50,900") == [25, 50, 90], "out of range")
    }

    @Test func editedPresetsAreSavedAndUsedByTheNumberKeys() {
        ui.presets[1] = 45
        #expect(defaults.string(forKey: AppSettings.presets) == "25,45,90")
        ui.choosePreset(at: 1)
        #expect(ui.selectedMinutes == 45)
        #expect(UIModel(engine: h.engine, defaults: defaults).presets == [25, 45, 90])
    }

    @Test func changingTheSelectedPresetMovesTheSelection() {
        ui.duration = .preset(50)
        ui.presets[1] = 40
        #expect(ui.duration == .preset(25), "the old 50 no longer exists")
    }

    @Test func aFixedOpeningDurationOverridesTheLastUsed() {
        ui.duration = .preset(90)
        defaults.set(UIModel.encode(.noLimit), forKey: AppSettings.startDuration)
        #expect(UIModel(engine: h.engine, defaults: defaults).duration == .noLimit)
        defaults.set("last", forKey: AppSettings.startDuration)
        #expect(UIModel(engine: h.engine, defaults: defaults).duration == .preset(90))
    }

    // MARK: Reset

    @Test func withoutTheHoldResetIsImmediate() {
        ui.holdToReset = false
        ui.task = "Task"
        ui.commit()
        h.advance(60)
        h.engine.pause()
        ui.setHolding(true)
        #expect(h.engine.state == .ready)
        #expect(h.recorder.saveCount == 0)
    }

    // MARK: Presentation keys

    private func press(_ key: String, code: UInt16 = 0, _ modifiers: NSEvent.ModifierFlags = [],
                       presenting: Bool = true) -> Bool {
        KeyboardController(ui: ui).perform(
            KeyPress(key: key, keyCode: code, modifiers: modifiers, isInPresentation: presenting))
    }

    @Test func presentationTakesSpaceEscAndCommandReturnOnly() {
        ui.task = "Task"
        ui.commit()
        h.advance(60)  // over the 5-second minimum, so finishing logs it
        #expect(press(" "))
        #expect(h.engine.state.phase == .paused)
        #expect(press("", code: KeyPress.escape), "Esc leaves")
        #expect(press("2") == false, "no preset keys here")
        #expect(press("r") == false, "no reset from a shared screen")
        #expect(press("\r", code: 36, .command))
        #expect(h.engine.state.phase == .review)
    }

    @Test func presentationShortcutNeedsARunningClock() {
        #expect(press("f", [.command, .control], presenting: false) == false)
    }

    @Test func isTimingCoversTheClockStates() {
        #expect(TimerState.ready.isTiming == false)
        h.engine.start(task: "Task", minutes: 25)
        #expect(h.engine.state.isTiming)
        h.engine.pause()
        #expect(h.engine.state.isTiming)
        h.engine.finish()
        #expect(h.engine.state.isTiming == false, "review")
    }
}
