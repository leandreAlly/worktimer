//
//  TimerEngineTests.swift
//  WorkTimerTests
//

import Foundation
import Testing
@testable import WorkTimer

// `@MainActor` because the app's types run on the main actor by default
// (the project's "Default Actor Isolation" setting); tests must too.
@MainActor
struct CountdownTests {
    @Test func startShowsFullCommitment() {
        let h = Harness()
        #expect(h.engine.start(task: "Implement checkout address validation", minutes: 25))
        #expect(h.engine.state.phase == .running)
        #expect(h.engine.reading().clockSeconds == 25 * 60)
        #expect(h.engine.reading().endsAt == h.clock.now + 25 * 60)
    }

    @Test func remainingIsDerivedFromElapsedTime() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(60)
        #expect(h.engine.reading().clockSeconds == 24 * 60)
        #expect(h.engine.reading().progress == 60.0 / 1500.0)
    }

    @Test func partialSecondsRoundUpLikeAKitchenTimer() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 1)
        h.advance(0.4)
        #expect(h.engine.reading().clockSeconds == 60)
        h.advance(59.5)
        #expect(h.engine.reading().clockSeconds == 1)
    }

    @Test func longCommitmentsKeepCounting() {
        let h = Harness()
        h.engine.start(task: "Deep work", minutes: 90)
        h.advance(3600)
        #expect(h.engine.reading().clockSeconds == 30 * 60)
    }

    @Test func timeKeepsCountingWhileTheMacSleeps() {
        // ContinuousClock counts sleep, which ManualTimeSource.advance models.
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(10 * 60) // lid closed for 10 minutes
        #expect(h.engine.reading().clockSeconds == 15 * 60)
    }

    @Test func wallClockChangesDoNotAffectARunningTimer() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(60)
        h.clock.jumpWallClock(by: 3600)   // clock set forward an hour
        #expect(h.engine.reading().clockSeconds == 24 * 60)
        h.clock.jumpWallClock(by: -7200)  // then back two hours
        #expect(h.engine.reading().clockSeconds == 24 * 60)
        h.engine.refresh()
        #expect(h.engine.state.phase == .running)
    }
}

@MainActor
struct OpenEndedTests {
    @Test func countsUpWithoutLimit() {
        let h = Harness()
        h.engine.start(task: "Investigate flaky test", minutes: 0)
        h.advance(90)
        #expect(h.engine.reading().clockSeconds == 90)
        #expect(h.engine.reading().endsAt == nil)
    }

    @Test func neverTimesUpOrNotifies() {
        let h = Harness()
        h.engine.start(task: "Investigate", minutes: 0)
        h.advance(10 * 3600)
        #expect(h.engine.state.phase == .running)
        #expect(h.effects.scheduled.isEmpty)
        #expect(h.effects.chimes.isEmpty)
        #expect(h.recorder.saveCount == 0)
    }

    @Test func finishLogsAsOpenEnded() throws {
        let h = Harness()
        h.engine.start(task: "Investigate", minutes: 0)
        h.advance(600)
        h.engine.finish()
        let record = try #require(h.recorder.only)
        #expect(record.plannedMinutes == 0)
        #expect(record.actualSeconds == 600)
        #expect(record.goalCompleted == false)
    }

    @Test func cannotBeExtended() {
        let h = Harness()
        h.engine.start(task: "Investigate", minutes: 0)
        #expect(h.engine.extend(minutes: 5) == false)
    }
}

@MainActor
struct PauseTests {
    @Test func pausedTimeIsExcludedFromWork() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(300)
        #expect(h.engine.pause())
        h.advance(600)
        #expect(h.engine.reading().clockSeconds == 20 * 60, "clock holds while paused")
        #expect(h.engine.resume())
        h.advance(100)

        let reading = h.engine.reading()
        #expect(reading.workedSeconds == 400)
        #expect(reading.pausedSeconds == 600)
        #expect(reading.pauseCount == 1)
        #expect(reading.clockSeconds == 1500 - 400)

        h.engine.finish()
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 400)
        #expect(record.pausedSeconds == 600)
        #expect(record.pauseCount == 1)
    }

    @Test func deadlineMovesLaterByThePausedTime() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        h.engine.pause()
        h.advance(1500) // paused past the original deadline
        #expect(h.engine.state.phase == .paused)
        h.engine.resume()
        h.advance(899)
        #expect(h.engine.state.phase == .running)
        h.advance(1)
        #expect(h.engine.state.phase == .timeUp)
    }

    @Test func togglePauseFollowsSpaceBarSemantics() {
        let h = Harness()
        #expect(h.engine.togglePause() == false, "nothing to pause on Ready")
        h.engine.start(task: "Task", minutes: 25)
        #expect(h.engine.togglePause())
        #expect(h.engine.state.phase == .paused)
        #expect(h.engine.togglePause())
        #expect(h.engine.state.phase == .running)
    }

    @Test func pausingCancelsThePendingNotification() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        let cancelsBefore = h.effects.cancelCount
        h.engine.pause()
        #expect(h.effects.cancelCount == cancelsBefore + 1)
        h.advance(60)
        h.engine.resume()
        #expect(h.effects.scheduled.last?.seconds == 1500, "rescheduled for the full remaining time")
    }
}

@MainActor
struct TransitionRuleTests {
    @Test func invalidActionsAreRejected() {
        let h = Harness()
        #expect(h.engine.pause() == false)
        #expect(h.engine.resume() == false)
        #expect(h.engine.finish() == false)
        #expect(h.engine.discard() == false)
        #expect(h.engine.extend(minutes: 5) == false)
        #expect(h.engine.endBreak() == false)
        #expect(h.engine.completeReview(outcome: .done, note: "") == false)

        h.engine.start(task: "Task", minutes: 25)
        #expect(h.engine.start(task: "Another", minutes: 25) == false, "one session at a time")
        #expect(h.engine.resume() == false)
        #expect(h.engine.startBreak() == false, "no break in the middle of work")
    }

    @Test func startRequiresANamedTask() {
        let h = Harness()
        #expect(h.engine.start(task: "", minutes: 25) == false)
        #expect(h.engine.start(task: "   \n", minutes: 25) == false)
        #expect(h.engine.state == .ready)
    }

    @Test func taskNameIsTrimmed() {
        let h = Harness()
        h.engine.start(task: "  Write tests  ", minutes: 25)
        #expect(h.engine.state.workRun?.task == "Write tests")
    }

    @Test func customDurationMustBeBetween1And600Minutes() {
        let h = Harness()
        #expect(h.engine.start(task: "Task", minutes: -1) == false)
        #expect(h.engine.start(task: "Task", minutes: 601) == false)
        #expect(h.engine.start(task: "Task", minutes: 600))
    }
}

@MainActor
struct CompletionTests {
    @Test func reachingZeroSavesOnceAndChimesOnce() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)

        #expect(h.engine.state.phase == .timeUp)
        #expect(h.engine.notice == .timeUp)
        let record = try #require(h.recorder.only)
        #expect(record.goalCompleted)
        #expect(record.actualSeconds == 1500)
        #expect(record.endedAt == h.clock.now)
        #expect(h.effects.chimes == [.workTimeUp(task: "Task")])

        // Later refreshes (wake-ups, actions) must not process it again.
        h.advance(1)
        h.engine.refresh()
        #expect(h.recorder.saveCount == 1)
        #expect(h.effects.chimes.count == 1)
    }

    @Test func notificationIsScheduledForTheDeadline() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        #expect(h.effects.scheduled.last?.alert == .workTimeUp(task: "Task"))
        #expect(h.effects.scheduled.last?.seconds == 1500)
        #expect(h.scheduler.lastDelay == 1500, "engine asks to be woken at the deadline")
    }

    @Test func overtimeCountsUntilFinish() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        h.advance(42)
        #expect(h.engine.reading().overtimeSeconds == 42)
        h.engine.finish()

        #expect(h.engine.state.phase == .review)
        let record = try #require(h.recorder.only, "same record updated, no duplicate")
        #expect(record.actualSeconds == 1542)
        #expect(record.goalCompleted)
    }

    @Test func overtimeIsCappedAtOneHour() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        h.advance(TimerEngine.maximumOvertime + 600)
        #expect(h.engine.state.phase == .review)
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 1500 + Int(TimerEngine.maximumOvertime))
    }

    @Test func deadlinePassedWhileAsleepCreditsPlannedTimeOnly() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(3 * 3600) // the wake-up fired 2.5 hours late

        #expect(h.engine.state.phase == .review)
        #expect(h.engine.notice == .completedWhileAway)
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 1500)
        #expect(record.goalCompleted)
        #expect(record.endedAt == record.startedAt + 1500)
        #expect(h.effects.chimes.isEmpty, "no chime hours late")
    }

    @Test func stoppingEarlyIsNotAHitGoal() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        h.engine.finish()
        let record = try #require(h.recorder.only)
        #expect(record.goalCompleted == false)
        #expect(record.actualSeconds == 600)
        #expect(h.effects.chimes.isEmpty)
    }

    @Test func prepareForTerminationSavesOvertime() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        h.advance(120)
        h.engine.prepareForTermination()
        #expect(try #require(h.recorder.only).actualSeconds == 1620)
        #expect(h.engine.state.phase == .review)
    }
}

@MainActor
struct ExtendTests {
    @Test func extendWhileRunningAddsToTheCommitment() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(60)
        #expect(h.engine.extend(minutes: 5))
        #expect(h.engine.reading().clockSeconds == 29 * 60)
        #expect(h.effects.scheduled.last?.seconds == TimeInterval(29 * 60), "notification moved too")
    }

    @Test func extendFromTimeUpKeepsTheSameRecord() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        h.advance(30)
        #expect(h.engine.extend(minutes: 5))
        #expect(h.engine.state.phase == .running)
        #expect(h.engine.reading().clockSeconds == 300, "5 minutes from now")

        h.advance(120)
        h.engine.finish()
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 1500 + 30 + 120)
        #expect(record.goalCompleted, "the original goal was reached")
    }

    @Test func discardAfterExtendingKeepsTheEarnedRecord() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        h.engine.extend(minutes: 5)
        h.advance(60)
        h.engine.discard()
        #expect(h.engine.state == .ready)
        #expect(try #require(h.recorder.only).actualSeconds == 1500)
    }
}

@MainActor
struct LoggingRuleTests {
    @Test func sessionsUnderFiveSecondsAreIgnored() {
        let h = Harness()
        h.engine.start(task: "Oops", minutes: 25)
        h.advance(4.9)
        #expect(h.engine.finish())
        #expect(h.engine.state == .ready)
        #expect(h.recorder.saveCount == 0)
    }

    @Test func fiveSecondsIsEnoughToLog() {
        let h = Harness()
        h.engine.start(task: "Quick", minutes: 25)
        h.advance(5)
        h.engine.finish()
        #expect(h.recorder.records.count == 1)
    }

    @Test func discardNeverLogs() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        #expect(h.engine.discard())
        #expect(h.engine.state == .ready)
        #expect(h.recorder.saveCount == 0)
    }

    @Test func discardWhilePausedNeverLogs() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        h.engine.pause()
        #expect(h.engine.discard())
        #expect(h.recorder.saveCount == 0)
    }

    @Test func finishingTwiceSavesOnlyOnce() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        #expect(h.engine.finish())
        #expect(h.engine.finish() == false, "already in review")
        #expect(h.recorder.saveCount == 1)
    }

    @Test func reviewStoresOutcomeAndNoteOnTheSameRecord() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        h.engine.finish()
        let endedAt = try #require(h.recorder.only).endedAt
        h.advance(30) // time spent on the review screen
        #expect(h.engine.completeReview(outcome: .continueLater, note: "  Country rules left \n"))

        let record = try #require(h.recorder.only)
        #expect(record.outcome == .continueLater)
        #expect(record.note == "Country rules left")
        #expect(record.endedAt == endedAt, "review time isn't work time")
        #expect(record.actualSeconds == 600)
        #expect(h.engine.state == .ready)
    }

    @Test func needMoreTimeContinuesTheSameSession() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(600)
        h.engine.finish()
        h.advance(20)
        #expect(h.engine.continueSession(minutes: 15))
        #expect(h.engine.reading().clockSeconds == 15 * 60)
        h.advance(300)
        h.engine.finish()
        #expect(try #require(h.recorder.only).actualSeconds == 900, "review time excluded")
    }
}

@MainActor
struct BreakTests {
    @Test func breakIsNeverLoggedAsWork() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        #expect(h.engine.startBreak())
        #expect(h.engine.state.phase == .onBreak)
        #expect(h.engine.reading().clockSeconds == 5 * 60)

        h.advance(300)
        #expect(h.engine.state == .ready)
        #expect(h.engine.notice == .breakOver)
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 1500)
        #expect(h.effects.chimes.last == .breakOver)
    }

    @Test func breakFromTimeUpSavesOvertimeFirst() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        h.advance(45)
        h.engine.startBreak()
        #expect(try #require(h.recorder.only).actualSeconds == 1545)
    }

    @Test func breakSchedulesItsOwnNotification() {
        let h = Harness()
        h.engine.startBreak()
        #expect(h.effects.scheduled.last?.alert == .breakOver)
        #expect(h.effects.scheduled.last?.seconds == 300)
        #expect(h.engine.endBreak())
        #expect(h.engine.state == .ready)
    }
}

@MainActor
struct RecoveryTests {
    @Test func runningSessionContinuesAfterRelaunch() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(300)

        let (engine, clock) = h.relaunch(after: 60)
        #expect(engine.state.phase == .running)
        #expect(engine.state.workRun?.task == "Task")
        #expect(engine.reading().clockSeconds == 1500 - 360, "time while closed still counts")

        clock.advance(by: 100)
        #expect(engine.reading().clockSeconds == 1500 - 460)
    }

    @Test func pausedSessionStaysPausedAfterRelaunch() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(300)
        h.engine.pause()

        let (engine, _) = h.relaunch(after: 600)
        #expect(engine.state.phase == .paused)
        #expect(engine.reading().clockSeconds == 1200)
        #expect(engine.reading().pausedSeconds == 600)
    }

    @Test func deadlinePassedWhileClosedIsLoggedExactlyOnce() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(300)

        let (engine, _) = h.relaunch(after: 3600)
        #expect(engine.state.phase == .review)
        #expect(engine.notice == .completedWhileAway)
        let record = try #require(h.recorder.only)
        #expect(record.actualSeconds == 1500)
        #expect(record.goalCompleted)

        // Opening the app again must not log it a second time.
        let (again, _) = h.relaunch(after: 7200)
        #expect(again.state.phase == .review)
        #expect(h.recorder.records.count == 1)
    }

    @Test func overtimeDoesNotGrowWhileClosed() throws {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(1500)
        // Quit without prepareForTermination (e.g. a crash), reopen hours later.
        let (engine, _) = h.relaunch(after: 5 * 3600)
        #expect(engine.state.phase == .review)
        #expect(try #require(h.recorder.only).actualSeconds == 1500)
    }

    @Test func clockSetBackwardsWhileClosedNeverReducesElapsedTime() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(300)
        h.engine.prepareForTermination()  // normal quit checkpoints the 300 s
        let (engine, _) = h.relaunch(after: 60, wallClockShift: -3600)
        #expect(engine.reading().workedSeconds == 300, "negative gap counts as zero")
        #expect(engine.state.phase == .running)
    }

    @Test func checkpointDoesNotChangeTheReading() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(300)
        h.engine.pause()
        h.advance(40)
        let before = h.engine.reading()
        h.engine.checkpoint()
        #expect(h.engine.reading() == before)
        h.engine.resume()
        #expect(h.engine.reading().pausedSeconds == 40)
    }

    @Test func checkpointedSessionResumesCorrectlyAfterRelaunch() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(300)
        h.engine.checkpoint()
        h.clock.advance(by: 200)
        let (engine, _) = h.relaunch(after: 0)
        #expect(engine.reading().workedSeconds == 500)
    }

    @Test func breakSurvivesRelaunch() {
        let h = Harness()
        h.engine.startBreak()
        h.advance(60)
        let (engine, _) = h.relaunch(after: 60)
        #expect(engine.state.phase == .onBreak)
        #expect(engine.reading().clockSeconds == 180)
    }

    @Test func finishedBreakIsClearedOnRelaunch() {
        let h = Harness()
        h.engine.startBreak()
        let (engine, _) = h.relaunch(after: 3600)
        #expect(engine.state == .ready)
        #expect(h.recorder.saveCount == 0)
    }

    @Test func readyStateIsPersistedAfterFinishing() {
        let h = Harness()
        h.engine.start(task: "Task", minutes: 25)
        h.advance(10)
        h.engine.discard()
        #expect(h.store.stored == .ready)
        let (engine, _) = h.relaunch(after: 10)
        #expect(engine.state == .ready)
    }
}
