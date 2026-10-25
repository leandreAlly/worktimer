//
//  TimerDependencies.swift
//  WorkTimer
//

import Foundation

// The engine talks to the outside world only through these small protocols.
// The app passes real implementations (SwiftData, UserDefaults, notifications),
// tests pass in-memory fakes, so the timer logic can be tested without
// rendering a view or touching disk.

/// A finished (or in-overtime) work session, as plain values.
/// The engine produces these; `SessionStore` turns them into SwiftData rows.
struct SessionRecord: Equatable {
    let id: UUID
    var task: String
    /// `0` means the session had no limit.
    var plannedMinutes: Int
    var actualSeconds: Int
    var goalCompleted: Bool
    var startedAt: Date
    var endedAt: Date
    var pausedSeconds: Int
    var pauseCount: Int
    var outcome: SessionOutcome?
    var note: String
}

/// Saves work sessions. `save` must behave as an upsert: saving a record whose
/// `id` already exists replaces it. That makes repeated saves of the same run
/// harmless and is what rules out duplicate history rows.
protocol SessionRecording: AnyObject {
    func save(_ record: SessionRecord)
}

/// Keeps the in-progress `TimerState` across app launches.
protocol ActiveStateStoring: AnyObject {
    func load() -> TimerState?
    func save(_ state: TimerState)
}

/// Side effects outside the app: macOS notifications and sounds.
protocol TimerEffects: AnyObject {
    /// Schedule the single pending "time's up" / "break over" alert, replacing
    /// any earlier one. It is handed to macOS up front so it is delivered even
    /// if WorkTimer is closed or busy when the moment arrives.
    func scheduleAlert(_ alert: TimerAlert, in seconds: TimeInterval)
    func cancelAlert()
    /// The app saw a deadline pass live; play the chime.
    func playChime(for alert: TimerAlert)
}

enum TimerAlert: Equatable {
    case workTimeUp(task: String)
    case breakOver
}

/// Wakes the engine once at a future moment so it can notice a deadline
/// without polling every second.
protocol WakeScheduling: AnyObject {
    func wake(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// Used until Phase 4 wires up real notifications and sounds.
final class NoTimerEffects: TimerEffects {
    func scheduleAlert(_ alert: TimerAlert, in seconds: TimeInterval) {}
    func cancelAlert() {}
    func playChime(for alert: TimerAlert) {}
}
