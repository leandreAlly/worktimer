//
//  TestDoubles.swift
//  WorkTimerTests
//

import Foundation
@testable import WorkTimer

/// Keeps saved records in memory, keyed by id like the real upsert.
final class InMemoryRecorder: SessionRecording {
    private(set) var records: [UUID: SessionRecord] = [:]
    private(set) var saveCount = 0

    func save(_ record: SessionRecord) {
        records[record.id] = record
        saveCount += 1
    }

    var all: [SessionRecord] { Array(records.values) }
    var only: SessionRecord? { records.count == 1 ? records.values.first : nil }
}

final class InMemoryStateStore: ActiveStateStoring {
    var stored: TimerState?
    func load() -> TimerState? { stored }
    func save(_ state: TimerState) { stored = state }
}

final class RecordingEffects: TimerEffects {
    private(set) var scheduled: [(alert: TimerAlert, seconds: TimeInterval)] = []
    private(set) var cancelCount = 0
    private(set) var chimes: [TimerAlert] = []

    func scheduleAlert(_ alert: TimerAlert, in seconds: TimeInterval) { scheduled.append((alert, seconds)) }
    func cancelAlert() { cancelCount += 1 }
    func playChime(for alert: TimerAlert) { chimes.append(alert) }
}

/// Never fires on its own: tests call `engine.refresh()` after moving the clock,
/// which is exactly what the real scheduler does at the deadline.
final class ManualScheduler: WakeScheduling {
    private(set) var lastDelay: TimeInterval?
    func wake(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) { lastDelay = seconds }
    func cancel() { lastDelay = nil }
}

/// Everything one test needs, wired together.
@MainActor
struct Harness {
    let clock = ManualTimeSource()
    let recorder = InMemoryRecorder()
    let store = InMemoryStateStore()
    let effects = RecordingEffects()
    let scheduler = ManualScheduler()
    let engine: TimerEngine

    init() {
        engine = TimerEngine(clock: clock, recorder: recorder, stateStore: store,
                             effects: effects, scheduler: scheduler)
    }

    /// Simulates quitting and reopening the app `secondsLater` seconds later:
    /// a fresh engine and a fresh monotonic clock, same saved state and history.
    func relaunch(after secondsLater: TimeInterval, wallClockShift: TimeInterval = 0) -> (TimerEngine, ManualTimeSource) {
        let newClock = ManualTimeSource(now: clock.now + secondsLater + wallClockShift)
        newClock.monotonic = 7 // unrelated to the previous launch's values
        let engine = TimerEngine(clock: newClock, recorder: recorder, stateStore: store,
                                 effects: effects, scheduler: scheduler)
        return (engine, newClock)
    }

    /// Move time forward and let the engine notice, as the wake-up timer would.
    func advance(_ seconds: TimeInterval) {
        clock.advance(by: seconds)
        engine.refresh()
    }
}
