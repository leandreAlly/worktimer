//
//  InteractionTests.swift
//  WorkTimerTests
//

import AppKit
import Foundation
import Testing
@testable import WorkTimer

/// The UI model and keyboard rules, driven without any window.
@MainActor
struct InteractionTests {
    let h = Harness()
    let defaults: UserDefaults
    let ui: UIModel
    let keyboard: KeyboardController

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "WorkTimerTests.ui.\(UUID().uuidString)"))
        ui = UIModel(engine: h.engine, defaults: defaults)
        keyboard = KeyboardController(ui: ui)
    }

    @discardableResult
    private func press(_ key: String, code: UInt16 = 0, _ modifiers: NSEvent.ModifierFlags = [],
                       editing: Bool = false) -> Bool {
        keyboard.perform(KeyPress(key: key, keyCode: code, modifiers: modifiers, isEditingText: editing))
    }
    private let returnKey: UInt16 = 36

    // MARK: Ready

    @Test func commandReturnCommitsTheDraft() {
        ui.task = "Write release notes"
        ui.duration = .preset(50)
        #expect(press("\r", code: returnKey, .command))
        #expect(h.engine.state.workRun?.task == "Write release notes")
        #expect(h.engine.reading().clockSeconds == 50 * 60)
    }

    @Test func commandReturnWorksEvenWhileTypingTheTask() {
        ui.task = "Write release notes"
        #expect(press("\r", code: returnKey, .command, editing: true))
        #expect(h.engine.state.phase == .running)
    }

    @Test func commitIsBlockedUntilTheTaskIsNamed() {
        ui.task = "  "
        #expect(ui.canCommit == false)
        press("\r", code: returnKey, .command)
        #expect(h.engine.state == .ready)
    }

    @Test func plainKeysAreLeftAloneWhileTyping() {
        ui.task = "Fix bug"
        #expect(press(" ", editing: true) == false, "Space types a space")
        #expect(press("2", editing: true) == false, "digits type digits")
        #expect(h.engine.state == .ready)
        #expect(ui.duration == .preset(25))
    }

    @Test func numberKeysPickDurations() {
        #expect(press("2"))
        #expect(ui.duration == .preset(50))
        #expect(press("3"))
        #expect(ui.selectedMinutes == 90)
        #expect(press("4"))
        #expect(ui.selectedMinutes == 0)
        #expect(press("c"))
        #expect(ui.duration == .custom)
        #expect(ui.customFieldFocusRequest == 1)
    }

    @Test func noLimitStartsAnOpenEndedSession() {
        ui.task = "Explore"
        ui.duration = .noLimit
        ui.commit()
        #expect(h.engine.state.workRun?.isOpenEnded == true)
    }

    @Test func draftSurvivesRelaunch() {
        ui.task = "Persisted task"
        ui.duration = .custom
        ui.customMinutes = 42
        let reopened = UIModel(engine: h.engine, defaults: defaults)
        #expect(reopened.task == "Persisted task")
        #expect(reopened.duration == .custom)
        #expect(reopened.selectedMinutes == 42)
    }

    // MARK: Working

    @Test func spaceStartsThenPausesThenResumes() {
        ui.task = "Task"
        #expect(press(" "))
        #expect(h.engine.state.phase == .running)
        #expect(press(" "))
        #expect(h.engine.state.phase == .paused)
        #expect(press(" "))
        #expect(h.engine.state.phase == .running)
    }

    @Test func commandReturnFinishesAndLogs() {
        ui.task = "Task"
        ui.commit()
        h.advance(600)
        #expect(press("\r", code: returnKey, .command))
        #expect(h.engine.state.phase == .review)
        #expect(h.recorder.records.count == 1)
    }

    @Test func returnAtTimeUpOpensReview() {
        ui.task = "Task"
        ui.commit()
        h.advance(1500)
        #expect(h.engine.state.phase == .timeUp)
        #expect(press("\r", code: returnKey))
        #expect(h.engine.state.phase == .review)
    }

    @Test func otherModifierCombinationsAreNotIntercepted() {
        ui.task = "Task"
        #expect(press(" ", .option) == false)
        #expect(press("c", .command) == false, "⌘C stays copy")
        #expect(h.engine.state == .ready)
    }

    // MARK: Review

    @Test func reviewDefaultsToDoneWhenTheGoalWasHit() throws {
        ui.task = "Task"
        ui.commit()
        h.advance(1500)
        h.engine.finish()
        ui.prepareReview(for: try #require(h.engine.state.workRun))
        #expect(ui.reviewChoice == .done)
    }

    @Test func reviewKeysChooseAndCommandReturnConfirms() throws {
        ui.task = "Task"
        ui.commit()
        h.advance(600)
        h.engine.finish()
        ui.prepareReview(for: try #require(h.engine.state.workRun))
        #expect(ui.reviewChoice == .later, "stopped early defaults to Continue later")

        #expect(press("d"))
        ui.note = "Shipped it"
        press("\r", code: returnKey, .command)
        let record = try #require(h.recorder.only)
        #expect(record.outcome == .done)
        #expect(record.note == "Shipped it")
        #expect(h.engine.state == .ready)
    }

    @Test func needMoreTimeContinuesWithTheChosenExtension() throws {
        ui.task = "Task"
        ui.commit()
        h.advance(600)
        h.engine.finish()
        ui.prepareReview(for: try #require(h.engine.state.workRun))
        press("m")
        ui.reviewExtraMinutes = 25
        ui.submitReview()
        #expect(h.engine.state.phase == .running)
        #expect(h.engine.reading().clockSeconds == 25 * 60)
    }

    @Test func breakFromReviewSavesTheOutcomeFirst() throws {
        ui.task = "Task"
        ui.commit()
        h.advance(1500)
        h.engine.finish()
        ui.prepareReview(for: try #require(h.engine.state.workRun))
        ui.reviewThenBreak()
        #expect(h.engine.state.phase == .onBreak)
        #expect(try #require(h.recorder.only).outcome == .done)
    }

    @Test func skipKeepsTheRecordWithoutAnOutcome() throws {
        ui.task = "Task"
        ui.commit()
        h.advance(600)
        h.engine.finish()
        ui.skipReview()
        #expect(try #require(h.recorder.only).outcome == nil)
        #expect(h.engine.state == .ready)
    }

    // MARK: Hold to reset

    @Test func holdOnlyStartsWhilePaused() {
        ui.task = "Task"
        ui.commit()
        ui.setHolding(true)
        #expect(ui.holdProgress == 0, "no reset while running")
        h.engine.pause()
        ui.setHolding(true)
        #expect(ui.holdProgress == 1, "ring animates to full")
        ui.setHolding(false)
        #expect(ui.holdProgress == 0)
        #expect(h.engine.state.phase == .paused, "released early: nothing discarded")
    }

    @Test func holdingForASecondDiscards() async throws {
        ui.task = "Task"
        ui.commit()
        h.advance(300)
        h.engine.pause()
        press("r")
        try await Task.sleep(for: .milliseconds(1300))
        #expect(h.engine.state == .ready)
        #expect(h.recorder.saveCount == 0)
    }
}
