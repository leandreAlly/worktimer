//
//  TimeSource.swift
//  WorkTimer
//

import Foundation

/// Where the timer engine gets "now" from.
///
/// The engine never calls `Date()` directly. Going through this protocol lets
/// tests swap in `ManualTimeSource` and move time forward instantly instead of
/// waiting in real time.
///
/// It exposes two clocks because they answer different questions:
/// - `now` is the wall clock. It is what the user sees ("until 3:47 PM") and
///   what gets saved, but the user or the network can change it at any moment.
/// - `monotonic` only ever moves forward at a steady rate, including while the
///   Mac sleeps, and ignores clock changes. Running time inside one launch of
///   the app is measured with it.
protocol TimeSource {
    var now: Date { get }
    /// Seconds since an arbitrary fixed point. Only differences are meaningful,
    /// and values are only comparable within a single launch of the app.
    var monotonic: TimeInterval { get }
}

/// The real clocks.
struct SystemTimeSource: TimeSource {
    // `ContinuousClock` keeps counting while the Mac is asleep, unlike
    // `SuspendingClock`. A 25-minute session should end 25 real minutes after
    // it started even if the lid was closed in between.
    private static let origin = ContinuousClock.now

    var now: Date { Date() }

    var monotonic: TimeInterval {
        let elapsed = ContinuousClock.now - Self.origin
        let parts = elapsed.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) * 1e-18
    }
}

/// A clock that only moves when told to. Used by tests and SwiftUI previews.
final class ManualTimeSource: TimeSource {
    var now: Date
    var monotonic: TimeInterval = 1_000

    init(now: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        self.now = now
    }

    /// Real time passing: both clocks move together.
    func advance(by seconds: TimeInterval) {
        now += seconds
        monotonic += seconds
    }

    /// The user (or NTP) changed the system clock: only the wall clock jumps.
    func jumpWallClock(by seconds: TimeInterval) {
        now += seconds
    }
}
