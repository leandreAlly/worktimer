//
//  TimerState.swift
//  WorkTimer
//

import Foundation

/// The timer is always in exactly one of these states.
///
/// A Swift `enum` with associated values makes impossible combinations
/// unrepresentable: there is no way to be "paused" and "on a break" at the same
/// time, which a handful of `isRunning` / `isPaused` / `isBreak` Booleans would
/// allow. Each case carries only the data that state needs.
///
/// `Codable` lets the whole state be written to disk and restored after a
/// relaunch; Swift synthesizes the encoding for enums like this automatically.
enum TimerState: Codable, Equatable {
    /// Nothing in progress. The Ready screen.
    case ready
    /// A work session with the clock running.
    case running(WorkRun)
    /// A work session on hold. Paused time is tracked but never counted as work.
    case paused(WorkRun)
    /// A timed session reached its goal. It is already saved; the clock keeps
    /// running so overtime can be shown and counted.
    case timeUp(WorkRun)
    /// The session is finished and saved; waiting for the user to choose an
    /// outcome (Done / Need more time / Continue later).
    case review(WorkRun)
    /// A break. Never recorded as work.
    case onBreak(BreakRun)

    /// The case name without its data, for simple comparisons such as
    /// `state.phase == .paused` (an enum with associated values can't be
    /// compared that way directly).
    enum Phase { case ready, running, paused, timeUp, review, onBreak }

    var phase: Phase {
        switch self {
        case .ready: .ready
        case .running: .running
        case .paused: .paused
        case .timeUp: .timeUp
        case .review: .review
        case .onBreak: .onBreak
        }
    }

    /// The work session in progress or under review, if any.
    var workRun: WorkRun? {
        switch self {
        case .running(let run), .paused(let run), .timeUp(let run), .review(let run): run
        case .ready, .onBreak: nil
        }
    }
}

/// One anchor point of a stretch of continuous time.
///
/// Both clocks are recorded: `monotonic` is used while the app keeps running
/// (immune to clock changes), `wall` is the fallback after a relaunch, because
/// monotonic values from an earlier launch can't be trusted.
struct ClockMark: Codable, Equatable {
    var wall: Date
    var monotonic: TimeInterval
}

/// Everything needed to compute a work session's numbers at any moment.
///
/// Elapsed work is never counted up tick by tick. It is always derived:
/// `workedBefore + (now − runningSince)`. That is why the display stays correct
/// after sleep, after the app is hidden, or when a timer fires late.
struct WorkRun: Codable, Equatable {
    /// Also the saved session's id, so saving the same run twice updates one
    /// record instead of creating a duplicate.
    let id: UUID
    let task: String
    /// The commitment in seconds; `0` means "no limit" (stopwatch mode).
    var plannedSeconds: Int
    /// Wall-clock time the session began. Saved as the session's start.
    let startedAt: Date

    /// Work time from stretches that have already ended (before a pause).
    var workedBefore: TimeInterval = 0
    /// Set while the clock is running; `nil` while paused or under review.
    var runningSince: ClockMark?

    /// Paused time from earlier pauses.
    var pausedBefore: TimeInterval = 0
    /// Set while paused.
    var pausedSince: ClockMark?
    var pauseCount = 0

    /// Becomes true the moment a timed goal is reached and stays true, even if
    /// the session is extended afterwards.
    var hitGoal = false

    /// True once a record for this run exists in history. Later saves update
    /// that record, and discarding no longer removes what was already earned.
    var isLogged = false
    /// When the work stopped, fixed at finish so a later note edit in Review
    /// doesn't move it.
    var endedAt: Date?

    var isOpenEnded: Bool { plannedSeconds == 0 }
}

struct BreakRun: Codable, Equatable {
    var plannedSeconds: Int
    let startedAt: Date
    var elapsedBefore: TimeInterval = 0
    var runningSince: ClockMark
}

/// What the user decided on the Review screen.
enum SessionOutcome: String, Codable, CaseIterable {
    case done
    case continueLater
}

/// One-off things that happened, for the UI to show (a banner, a sound).
enum TimerNotice: Equatable {
    /// A timed session reached zero while the app was watching.
    case timeUp
    /// A timed session ran out while the app was closed or the Mac was asleep.
    /// It was saved as completed at its deadline, without overtime.
    case completedWhileAway
    case breakOver
}
