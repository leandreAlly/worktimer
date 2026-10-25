//
//  TimerEngine.swift
//  WorkTimer
//

import Foundation
import Observation

/// The single source of truth for the timer, shared by the main window and the
/// menu bar.
///
/// `@Observable` (macOS 14+) makes SwiftUI views that read `state` redraw
/// automatically when it changes; there is no `@Published` to remember.
///
/// Rules this type enforces:
/// - All state changes go through `transition(to:)`, which saves the state to
///   disk and keeps the scheduled notification in sync.
/// - Every action checks it is valid for the current state and returns `false`
///   (doing nothing) if not, e.g. `pause()` while on the Ready screen.
/// - Time is never counted by ticks. Views redraw on a timer, but every number
///   they show is computed from timestamps through `reading()`.
@Observable
final class TimerEngine {
    // MARK: Policy

    /// Sessions shorter than this are dropped instead of logged.
    static let minimumLoggedSeconds: TimeInterval = 5
    /// If a deadline is noticed more than this long after it passed, the app
    /// wasn't watching (it was closed, or the Mac slept through it). The session
    /// is then saved as completed at its deadline with no overtime, because
    /// nobody was there to keep working.
    static let lateDeadlineGrace: TimeInterval = 60
    /// Overtime stops counting after this long and the session finishes on its
    /// own, so a forgotten "time's up" screen can't log an evening of work.
    static let maximumOvertime: TimeInterval = 60 * 60
    static let allowedMinutes = 1...600
    static let defaultBreakMinutes = 5

    // MARK: Observed state

    private(set) var state: TimerState
    /// Something the UI may want to announce once (e.g. "Break's over").
    private(set) var notice: TimerNotice?

    // MARK: Dependencies
    // `@ObservationIgnored`: these never change, so SwiftUI doesn't need to
    // track them.

    @ObservationIgnored private let clock: TimeSource
    @ObservationIgnored private let recorder: SessionRecording
    @ObservationIgnored private let stateStore: ActiveStateStoring
    @ObservationIgnored private let effects: TimerEffects
    @ObservationIgnored private let scheduler: WakeScheduling

    init(
        clock: TimeSource = SystemTimeSource(),
        recorder: SessionRecording,
        stateStore: ActiveStateStoring,
        effects: TimerEffects = NoTimerEffects(),
        scheduler: WakeScheduling
    ) {
        self.clock = clock
        self.recorder = recorder
        self.stateStore = stateStore
        self.effects = effects
        self.scheduler = scheduler

        // Restore whatever was in progress when the app last quit.
        let restored = stateStore.load()
        self.state = .ready
        if let restored {
            transition(to: Self.reanchored(restored, at: mark()))
        }
        // A deadline may have passed while the app was closed.
        refresh()
    }

    // MARK: - Work actions

    /// Ready → Running. `minutes == 0` starts an open-ended stopwatch.
    @discardableResult
    func start(task: String, minutes: Int) -> Bool {
        refresh()
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .ready = state, !task.isEmpty,
              minutes == 0 || Self.allowedMinutes.contains(minutes) else { return false }

        notice = nil
        transition(to: .running(WorkRun(
            id: UUID(),
            task: task,
            plannedSeconds: minutes * 60,
            startedAt: clock.now,
            runningSince: mark()
        )))
        return true
    }

    /// Running → Paused.
    @discardableResult
    func pause() -> Bool {
        refresh()
        guard case .running(var run) = state else { return false }
        run.workedBefore = worked(run)
        run.runningSince = nil
        run.pausedSince = mark()
        run.pauseCount += 1
        transition(to: .paused(run))
        return true
    }

    /// Paused → Running.
    @discardableResult
    func resume() -> Bool {
        refresh()
        guard case .paused(var run) = state else { return false }
        run.pausedBefore = paused(run)
        run.pausedSince = nil
        run.runningSince = mark()
        transition(to: .running(run))
        return true
    }

    /// The Space bar: pause if running, resume if paused.
    @discardableResult
    func togglePause() -> Bool {
        switch state {
        case .running: pause()
        case .paused: resume()
        default: false
        }
    }

    /// Add time to a timed session. While running or paused this extends the
    /// current commitment. From Time's up it starts a fresh commitment of
    /// `minutes` measured from now, on the same session.
    @discardableResult
    func extend(minutes: Int) -> Bool {
        refresh()
        guard Self.allowedMinutes.contains(minutes) else { return false }
        let extra = minutes * 60
        switch state {
        case .running(var run) where !run.isOpenEnded:
            run.plannedSeconds += extra
            transition(to: .running(run))
        case .paused(var run) where !run.isOpenEnded:
            run.plannedSeconds += extra
            transition(to: .paused(run))
        case .timeUp(var run):
            run.plannedSeconds = Int(worked(run).rounded()) + extra
            run.endedAt = nil
            transition(to: .running(run))
        default:
            return false
        }
        return true
    }

    /// "Finish & Log" (⌘↵). Running / Paused / Time's up → Review.
    /// A session under five seconds that was never logged is dropped and the
    /// timer goes back to Ready instead.
    @discardableResult
    func finish() -> Bool {
        refresh()
        switch state {
        case .running(let run), .paused(let run), .timeUp(let run):
            var run = stopped(run)
            if run.workedBefore < Self.minimumLoggedSeconds && !run.isLogged {
                transition(to: .ready)
                return true
            }
            run.endedAt = clock.now
            log(&run)
            transition(to: .review(run))
            return true
        default:
            return false
        }
    }

    /// "Hold to reset". Throws away the current session without logging it.
    /// If the session already reached its goal (it was logged at zero and then
    /// extended), the saved record is kept and only the unsaved extra time is
    /// dropped.
    @discardableResult
    func discard() -> Bool {
        refresh()
        switch state {
        case .running, .paused:
            transition(to: .ready)
            return true
        default:
            return false
        }
    }

    // MARK: - Review actions

    /// Review → Ready, storing the chosen outcome and note on the saved record.
    @discardableResult
    func completeReview(outcome: SessionOutcome?, note: String) -> Bool {
        guard case .review(let run) = state else { return false }
        log(run, outcome: outcome, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        transition(to: .ready)
        return true
    }

    /// Review → Running: "Need more time". Same session, new commitment of
    /// `minutes` from now.
    @discardableResult
    func continueSession(minutes: Int) -> Bool {
        guard case .review(var run) = state, Self.allowedMinutes.contains(minutes) else { return false }
        run.plannedSeconds = Int(run.workedBefore.rounded()) + minutes * 60
        run.runningSince = mark()
        run.endedAt = nil
        transition(to: .running(run))
        return true
    }

    // MARK: - Breaks

    /// Start a break from Ready, Time's up or Review. From Time's up the work
    /// session (with its overtime) is saved first. Break time is never logged.
    @discardableResult
    func startBreak(minutes: Int = TimerEngine.defaultBreakMinutes) -> Bool {
        refresh()
        guard Self.allowedMinutes.contains(minutes) else { return false }
        switch state {
        case .ready, .review:
            break
        case .timeUp(let run):
            var run = stopped(run)
            run.endedAt = clock.now
            log(&run)
        default:
            return false
        }
        notice = nil
        transition(to: .onBreak(BreakRun(
            plannedSeconds: minutes * 60,
            startedAt: clock.now,
            runningSince: mark()
        )))
        return true
    }

    @discardableResult
    func endBreak() -> Bool {
        guard case .onBreak = state else { return false }
        transition(to: .ready)
        return true
    }

    func clearNotice() { notice = nil }

    // MARK: - Lifecycle

    /// Check whether a deadline has passed. Called by the wake-up timer, after
    /// the Mac wakes, and at the start of every action. Safe to call any number
    /// of times: each deadline can only be processed once, because processing
    /// it moves the state on.
    func refresh() {
        switch state {
        case .running(var run) where !run.isOpenEnded:
            let planned = TimeInterval(run.plannedSeconds)
            let late = worked(run) - planned
            guard late >= 0 else { break }

            run.hitGoal = true
            run.endedAt = clock.now.addingTimeInterval(-late)
            if late <= Self.lateDeadlineGrace {
                // Seen live: save now (so it's never lost), keep the clock
                // running for overtime, chime.
                log(run, worked: planned)
                run.isLogged = true
                notice = .timeUp
                transition(to: .timeUp(run))
                effects.playChime(for: .workTimeUp(task: run.task))
            } else {
                // Nobody was watching: credit exactly the planned time.
                run.workedBefore = planned
                run.runningSince = nil
                log(&run)
                notice = .completedWhileAway
                transition(to: .review(run))
            }

        case .timeUp(let run) where overtime(run) >= Self.maximumOvertime:
            var run = stopped(run)
            run.workedBefore = TimeInterval(run.plannedSeconds) + Self.maximumOvertime
            run.endedAt = clock.now
            log(&run)
            transition(to: .review(run))

        case .onBreak(let breakRun):
            let late = breakElapsed(breakRun) - TimeInterval(breakRun.plannedSeconds)
            guard late >= 0 else { break }
            notice = .breakOver
            transition(to: .ready)
            if late <= Self.lateDeadlineGrace {
                effects.playChime(for: .breakOver)
            }

        default:
            break
        }
        scheduleWake()
    }

    /// Call when the app is about to quit. Overtime is saved now, because the
    /// time the app spends closed must not count as overtime. Anything else is
    /// checkpointed.
    func prepareForTermination() {
        if case .timeUp = state {
            finish()
        } else {
            checkpoint()
        }
    }

    /// Fold the open running/paused stretch into its saved total and start a
    /// new stretch from now. The numbers on screen don't change, but the saved
    /// state now records the time worked so far. If the wall clock is later
    /// set backwards while the app is closed, only the time since this
    /// checkpoint is at risk, not the whole session.
    /// Called on quit and before the Mac sleeps.
    func checkpoint() {
        let fresh = mark()
        switch state {
        case .running(var run):
            run.workedBefore = worked(run)
            run.runningSince = fresh
            transition(to: .running(run))
        case .paused(var run):
            run.pausedBefore = paused(run)
            run.pausedSince = fresh
            transition(to: .paused(run))
        case .onBreak(var breakRun):
            breakRun.elapsedBefore = breakElapsed(breakRun)
            breakRun.runningSince = fresh
            transition(to: .onBreak(breakRun))
        default:
            break
        }
    }

    // MARK: - Reading the clock

    /// Everything a view needs to draw the timer at this instant.
    func reading() -> TimerReading {
        let now = clock.now
        switch state {
        case .ready:
            return TimerReading()

        case .running(let run), .paused(let run):
            let worked = worked(run)
            var reading = TimerReading(workedSeconds: worked, pausedSeconds: paused(run), pauseCount: run.pauseCount)
            if run.isOpenEnded {
                reading.clockSeconds = Int(worked)
            } else {
                let remaining = max(0, TimeInterval(run.plannedSeconds) - worked)
                // Round up so the display shows 25:00 at the start and reaches
                // 00:00 exactly at the deadline, like a kitchen timer.
                reading.clockSeconds = Int(remaining.rounded(.up))
                reading.progress = min(1, worked / TimeInterval(run.plannedSeconds))
                if case .running = state {
                    reading.endsAt = now.addingTimeInterval(remaining)
                }
            }
            return reading

        case .timeUp(let run):
            var reading = TimerReading(workedSeconds: worked(run), pausedSeconds: paused(run), pauseCount: run.pauseCount)
            reading.progress = 1
            reading.overtimeSeconds = overtime(run)
            return reading

        case .review(let run):
            return TimerReading(
                clockSeconds: Int(run.workedBefore),
                progress: run.isOpenEnded ? 0 : min(1, run.workedBefore / TimeInterval(run.plannedSeconds)),
                workedSeconds: run.workedBefore,
                pausedSeconds: run.pausedBefore,
                pauseCount: run.pauseCount
            )

        case .onBreak(let breakRun):
            let remaining = max(0, TimeInterval(breakRun.plannedSeconds) - breakElapsed(breakRun))
            return TimerReading(
                clockSeconds: Int(remaining.rounded(.up)),
                progress: 1 - remaining / TimeInterval(breakRun.plannedSeconds),
                endsAt: now.addingTimeInterval(remaining)
            )
        }
    }

    // MARK: - Private: time arithmetic

    private func mark() -> ClockMark {
        ClockMark(wall: clock.now, monotonic: clock.monotonic)
    }

    /// Seconds since `mark` by the monotonic clock. Never negative.
    private func since(_ mark: ClockMark?) -> TimeInterval {
        guard let mark else { return 0 }
        return max(0, clock.monotonic - mark.monotonic)
    }

    private func worked(_ run: WorkRun) -> TimeInterval { run.workedBefore + since(run.runningSince) }
    private func paused(_ run: WorkRun) -> TimeInterval { run.pausedBefore + since(run.pausedSince) }
    private func overtime(_ run: WorkRun) -> TimeInterval { max(0, worked(run) - TimeInterval(run.plannedSeconds)) }
    private func breakElapsed(_ run: BreakRun) -> TimeInterval { run.elapsedBefore + since(run.runningSince) }

    /// Freeze a run's running and paused stretches into their totals.
    private func stopped(_ run: WorkRun) -> WorkRun {
        var run = run
        run.workedBefore = worked(run)
        run.runningSince = nil
        run.pausedBefore = paused(run)
        run.pausedSince = nil
        return run
    }

    /// Monotonic marks from an earlier launch are meaningless, so on restore
    /// each open stretch is closed using the wall clock and a fresh one is
    /// opened. Clock-change rule: if the wall clock moved backwards while the
    /// app was closed, the gap counts as zero; elapsed time never decreases.
    private static func reanchored(_ state: TimerState, at fresh: ClockMark) -> TimerState {
        func gap(since mark: ClockMark) -> TimeInterval { max(0, fresh.wall.timeIntervalSince(mark.wall)) }

        func reanchor(_ run: WorkRun) -> WorkRun {
            var run = run
            if let mark = run.runningSince {
                run.workedBefore += gap(since: mark)
                run.runningSince = fresh
            }
            if let mark = run.pausedSince {
                run.pausedBefore += gap(since: mark)
                run.pausedSince = fresh
            }
            return run
        }

        switch state {
        case .ready, .review:
            return state
        case .running(let run):
            return .running(reanchor(run))
        case .paused(let run):
            return .paused(reanchor(run))
        case .timeUp(var run):
            // The app quit without `prepareForTermination` (e.g. a crash).
            // The record saved at the deadline stands; time spent closed is
            // not overtime.
            run.workedBefore = TimeInterval(run.plannedSeconds)
            run.runningSince = nil
            return .review(run)
        case .onBreak(var breakRun):
            breakRun.elapsedBefore += gap(since: breakRun.runningSince)
            breakRun.runningSince = fresh
            return .onBreak(breakRun)
        }
    }

    // MARK: - Private: transitions and side effects

    /// The only place `state` is assigned after init.
    private func transition(to newState: TimerState) {
        state = newState
        stateStore.save(newState)
        syncAlert()
        scheduleWake()
    }

    /// Keep exactly one pending macOS notification that matches the state.
    private func syncAlert() {
        switch state {
        case .running(let run) where !run.isOpenEnded:
            effects.scheduleAlert(.workTimeUp(task: run.task),
                                  in: TimeInterval(run.plannedSeconds) - worked(run))
        case .onBreak(let breakRun):
            effects.scheduleAlert(.breakOver,
                                  in: TimeInterval(breakRun.plannedSeconds) - breakElapsed(breakRun))
        default:
            // Paused, open-ended, time's up, review, ready: nothing to announce.
            effects.cancelAlert()
        }
    }

    /// Arrange for `refresh()` to run when the next deadline arrives.
    private func scheduleWake() {
        let delay: TimeInterval?
        switch state {
        case .running(let run) where !run.isOpenEnded:
            delay = TimeInterval(run.plannedSeconds) - worked(run)
        case .timeUp(let run):
            delay = Self.maximumOvertime - overtime(run)
        case .onBreak(let breakRun):
            delay = TimeInterval(breakRun.plannedSeconds) - breakElapsed(breakRun)
        default:
            delay = nil
        }
        if let delay {
            scheduler.wake(after: max(0, delay)) { [weak self] in self?.refresh() }
        } else {
            scheduler.cancel()
        }
    }

    /// Save (insert or update) the run's record, marking the run as logged.
    private func log(_ run: inout WorkRun) {
        log(run)
        run.isLogged = true
    }

    private func log(_ run: WorkRun, worked: TimeInterval? = nil, outcome: SessionOutcome? = nil, note: String = "") {
        let worked = worked ?? self.worked(run)
        recorder.save(SessionRecord(
            id: run.id,
            task: run.task,
            plannedMinutes: Int((TimeInterval(run.plannedSeconds) / 60).rounded()),
            actualSeconds: Int(worked.rounded()),
            goalCompleted: run.hitGoal || (!run.isOpenEnded && worked >= TimeInterval(run.plannedSeconds)),
            startedAt: run.startedAt,
            endedAt: run.endedAt ?? clock.now,
            pausedSeconds: Int(paused(run).rounded()),
            pauseCount: run.pauseCount,
            outcome: outcome,
            note: note
        ))
    }
}

/// A snapshot of the numbers on screen. All durations in seconds.
struct TimerReading: Equatable {
    /// What the big digits show: remaining time for a countdown, elapsed time
    /// for an open-ended session, remaining break time.
    var clockSeconds = 0
    /// Share of the commitment used, 0...1. Drives the progress hairline.
    var progress: Double = 0
    /// Wall-clock time the countdown will hit zero, while running.
    var endsAt: Date?
    var overtimeSeconds: TimeInterval = 0
    var workedSeconds: TimeInterval = 0
    var pausedSeconds: TimeInterval = 0
    var pauseCount = 0
}
