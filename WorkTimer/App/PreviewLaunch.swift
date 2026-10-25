//
//  PreviewLaunch.swift
//  WorkTimer
//

#if DEBUG
import Foundation

/// Debug builds only: launch straight into a sample state for design checks,
/// without touching real data.
///
///     open -n WorkTimer.app --args -WTPreviewState paused
///
/// In preview mode history lives in an in-memory database and the timer state
/// is never written to disk, so a preview copy can run beside the real one.
/// `#if DEBUG` removes this file's contents from Release builds entirely.
enum PreviewLaunch {
    /// Command-line `-WTPreviewState name` arguments show up in UserDefaults'
    /// read-only argument domain; nothing is stored.
    static var requestedState: String? {
        UserDefaults.standard.string(forKey: "WTPreviewState")
    }

    static let task = "Implement checkout address validation"

    /// The canvas's sample numbers: 25 minutes committed, 18:42 left.
    static func state(named name: String, clock: TimeSource) -> TimerState {
        let now = clock.now
        func mark(secondsAgo: TimeInterval) -> ClockMark {
            ClockMark(wall: now - secondsAgo, monotonic: clock.monotonic - secondsAgo)
        }
        func run(planned: Int, worked: TimeInterval, running: Bool = true,
                 paused: TimeInterval = 0, pauses: Int = 0) -> WorkRun {
            var run = WorkRun(id: UUID(), task: task, plannedSeconds: planned,
                              startedAt: now - worked - paused)
            if running {
                run.runningSince = mark(secondsAgo: worked)
            } else {
                run.workedBefore = worked
                run.pausedBefore = paused
                run.pausedSince = mark(secondsAgo: 0)
            }
            run.pauseCount = pauses
            return run
        }

        switch name {
        case "focusing":
            return .running(run(planned: 1500, worked: 1500 - (18 * 60 + 42)))
        case "openended":
            return .running(run(planned: 0, worked: 12 * 60 + 3))
        case "long":
            return .running(run(planned: 90 * 60, worked: 20 * 60))
        case "paused":
            return .paused(run(planned: 1500, worked: 1500 - (18 * 60 + 42), running: false, paused: 74, pauses: 1))
        case "almostup":
            // Reaches zero three seconds after launch, then counts overtime.
            return .running(run(planned: 1500, worked: 1497))
        case "break":
            return .onBreak(BreakRun(plannedSeconds: 300, startedAt: now - 48, runningSince: mark(secondsAgo: 48)))
        case "review":
            var finished = run(planned: 1500, worked: 1542, running: false, paused: 134, pauses: 1)
            finished.pausedSince = nil
            finished.hitGoal = true
            finished.isLogged = true
            finished.endedAt = now
            return .review(finished)
        default:
            return .ready
        }
    }
}

/// Holds the preview state in memory only.
final class PreviewStateStore: ActiveStateStoring {
    private var state: TimerState?
    init(_ state: TimerState) { self.state = state }
    func load() -> TimerState? { state }
    func save(_ state: TimerState) { self.state = state }
}
#endif
