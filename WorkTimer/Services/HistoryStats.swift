//
//  HistoryStats.swift
//  WorkTimer
//

import Foundation

/// The numbers on the History window, computed from saved sessions.
///
/// Plain functions over arrays, so they're easy to test and don't care where
/// the sessions came from. A session belongs to the day it *started*, even if
/// it ran past midnight. Only focused time counts; pauses and breaks don't.
enum HistoryStats {
    struct Today: Equatable {
        var focusedSeconds = 0
        var sessions = 0
        /// Timed sessions that reached their commitment.
        var hitGoal = 0
        /// Timed sessions (open-ended ones have no goal to hit).
        var timed = 0
    }

    struct DayTotal: Identifiable, Equatable {
        /// Midnight at the start of the day.
        var day: Date
        var focusedSeconds: Int
        var id: Date { day }
        var minutes: Double { Double(focusedSeconds) / 60 }
    }

    static func today(_ sessions: [WorkSession], now: Date = .now, calendar: Calendar = .current) -> Today {
        var result = Today()
        for session in sessions where calendar.isDate(session.startedAt, inSameDayAs: now) {
            result.focusedSeconds += session.actualSeconds
            result.sessions += 1
            if !session.isOpenEnded {
                result.timed += 1
                if session.goalCompleted { result.hitGoal += 1 }
            }
        }
        return result
    }

    /// Exactly `days` entries, oldest first and ending today, with zero for
    /// days without work, so the chart always shows a full week.
    static func daily(_ sessions: [WorkSession], days: Int = 7, now: Date = .now,
                      calendar: Calendar = .current) -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        let starts = (0..<days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        // `Dictionary(grouping:by:)` buckets sessions by the midnight they
        // started after; then each day's focused seconds are summed.
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return starts.map { day in
            DayTotal(day: day, focusedSeconds: byDay[day]?.reduce(0) { $0 + $1.actualSeconds } ?? 0)
        }
    }

    /// Sessions grouped by start day, newest day first, for the list.
    static func groupedByDay(_ sessions: [WorkSession], calendar: Calendar = .current) -> [(day: Date, sessions: [WorkSession])] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
            .map { (day: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    /// Gridlines at round durations (15m, 30m, 1h, 2h …), at least an hour
    /// tall so one short session doesn't fill the whole height, with headroom
    /// above the tallest bar for its label.
    static func chartTicks(forMaxMinutes maximum: Double) -> [Double] {
        let steps: [Double] = [15, 30, 60, 120, 180, 240]
        let needed = max(60, maximum * 1.12)
        let step = steps.first { needed / $0 <= 4 } ?? 240
        let count = Int((needed / step).rounded(.up))
        return (0...count).map { Double($0) * step }
    }
}
