//
//  TaskWakeScheduler.swift
//  WorkTimer
//

import Foundation

/// Runs an action once after a delay, replacing any earlier request.
///
/// This is how the engine notices a deadline without a once-a-second loop:
/// it asks to be woken exactly when the deadline is due.
final class TaskWakeScheduler: WakeScheduling {
    private var task: Task<Void, Never>?

    func wake(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            // The continuous clock keeps counting through sleep, so after a
            // wake this fires right away if the deadline passed meanwhile.
            // The extra 50 ms keeps a slightly early wake-up from landing just
            // before the deadline.
            try? await Task.sleep(for: .seconds(seconds) + .milliseconds(50), clock: .continuous)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
