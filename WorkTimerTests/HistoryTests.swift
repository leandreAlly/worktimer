//
//  HistoryTests.swift
//  WorkTimerTests
//

import Foundation
import SwiftData
import Testing
@testable import WorkTimer

/// Today's totals, the 7-day series, grouping, chart ticks, CSV export and
/// delete/undo.
@MainActor
struct HistoryTests {
    /// A fixed calendar and "now" so results don't depend on where or when
    /// the tests run: Sunday 25 October 2026, 15:00 in Kigali (no DST).
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Kigali")!
        return calendar
    }()
    var now: Date { date(day: 25, hour: 15) }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func session(_ task: String = "Task", day: Int = 25, hour: Int = 9, minute: Int = 0,
                         planned: Int = 25, focusedMinutes: Int = 25, goal: Bool? = nil,
                         outcome: SessionOutcome? = nil, note: String = "") -> WorkSession {
        let start = date(day: day, hour: hour, minute: minute)
        let seconds = focusedMinutes * 60
        return WorkSession(record: SessionRecord(
            id: UUID(), task: task, plannedMinutes: planned, actualSeconds: seconds,
            goalCompleted: goal ?? (planned > 0 && focusedMinutes >= planned),
            startedAt: start, endedAt: start + TimeInterval(seconds),
            pausedSeconds: 0, pauseCount: 0, outcome: outcome, note: note))
    }

    // MARK: Today

    @Test func todayCountsOnlyTodaysSessions() {
        let sessions = [
            session(hour: 9, focusedMinutes: 25),
            session(hour: 10, planned: 50, focusedMinutes: 20),
            session(hour: 11, planned: 0, focusedMinutes: 40),   // open-ended
            session(day: 24, hour: 9, focusedMinutes: 90),       // yesterday
        ]
        let today = HistoryStats.today(sessions, now: now, calendar: calendar)
        #expect(today.focusedSeconds == (25 + 20 + 40) * 60)
        #expect(today.sessions == 3)
        #expect(today.timed == 2, "open-ended sessions have no goal")
        #expect(today.hitGoal == 1)
    }

    @Test func aSessionPastMidnightBelongsToTheDayItStarted() {
        let late = session(day: 24, hour: 23, minute: 40, planned: 50, focusedMinutes: 50)
        #expect(HistoryStats.today([late], now: now, calendar: calendar).sessions == 0)
        let days = HistoryStats.daily([late], now: now, calendar: calendar)
        #expect(days[5].focusedSeconds == 50 * 60, "credited to the 24th")
        #expect(days[6].focusedSeconds == 0)
    }

    // MARK: Seven days

    @Test func dailyAlwaysHasSevenDaysEndingToday() {
        let sessions = [
            session(day: 25, focusedMinutes: 25),
            session(day: 25, hour: 10, focusedMinutes: 30),
            session(day: 22, focusedMinutes: 50),
            session(day: 18, focusedMinutes: 90),  // eight days ago: outside
        ]
        let days = HistoryStats.daily(sessions, now: now, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first?.day == calendar.startOfDay(for: date(day: 19, hour: 0)))
        #expect(days.last?.day == calendar.startOfDay(for: now))
        #expect(days.map(\.focusedSeconds) == [0, 0, 0, 50 * 60, 0, 0, 55 * 60])
    }

    @Test func groupsAreNewestFirst() {
        let groups = HistoryStats.groupedByDay([
            session("a", day: 23), session("b", day: 25, hour: 9), session("c", day: 25, hour: 14),
        ], calendar: calendar)
        #expect(groups.map { $0.sessions.map(\.task) } == [["c", "b"], ["a"]])
    }

    @Test func chartTicksAreRoundAndLeaveHeadroom() {
        #expect(HistoryStats.chartTicks(forMaxMinutes: 0) == [0, 15, 30, 45, 60])
        #expect(HistoryStats.chartTicks(forMaxMinutes: 95) == [0, 30, 60, 90, 120])
        #expect(HistoryStats.chartTicks(forMaxMinutes: 130) == [0, 60, 120, 180])
        let big = HistoryStats.chartTicks(forMaxMinutes: 600)
        #expect(big.last! >= 600 * 1.12)
        #expect(big.count <= 5)
    }

    @Test func hoursMinutesFormat() {
        #expect(Format.hoursMinutes(0) == "0m")
        #expect(Format.hoursMinutes(45 * 60 + 59) == "45m")
        #expect(Format.hoursMinutes(2 * 3600) == "2h")
        #expect(Format.hoursMinutes(2 * 3600 + 14 * 60) == "2h 14m")
    }

    // MARK: CSV

    @Test func csvHasAHeaderAndOneRowPerSessionOldestFirst() {
        let csv = CSVExport.csv(for: [
            session("Second", hour: 11, outcome: .done, note: "ok"),
            session("First", hour: 9, planned: 0, focusedMinutes: 12),
        ])
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 3)
        #expect(lines[0] == "id,task,started_at,ended_at,planned_minutes,focused_seconds,paused_seconds,pause_count,status,outcome,note")
        #expect(lines[1].contains(",First,"))
        #expect(lines[1].hasSuffix(",0,720,0,0,Open-ended,,"))
        #expect(lines[2].hasSuffix(",25,1500,0,0,Hit goal,Done,ok"))
    }

    @Test func csvQuotesCommasQuotesAndLineBreaks() {
        #expect(CSVExport.escape("plain") == "plain")
        #expect(CSVExport.escape("a, b") == "\"a, b\"")
        #expect(CSVExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.escape("line\nbreak") == "\"line\nbreak\"")
    }

    @Test func csvNeutralisesSpreadsheetFormulas() {
        #expect(CSVExport.escape("=SUM(A1:A9)") == "'=SUM(A1:A9)")
        #expect(CSVExport.escape("+1") == "'+1")
        #expect(CSVExport.escape("@cmd") == "'@cmd")
        #expect(CSVExport.escape("=1,2") == "\"'=1,2\"")
    }

    @Test func csvDatesIncludeTheTimeZoneOffset() {
        let line = CSVExport.csv(for: [session()]).components(separatedBy: "\r\n")[1]
        // e.g. 2026-10-25T09:00:00+02:00, or ...Z in UTC.
        #expect(line.range(of: #"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(Z|[+-]\d\d:\d\d)"#, options: .regularExpression) != nil)
    }

    // MARK: Delete and undo

    @Test func deleteThenUndoRestoresTheSameRow() throws {
        let container = try ModelContainer(for: WorkSession.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = SessionStore(context: context)
        let original = session("Keep me", outcome: .continueLater, note: "half done").record
        store.save(original)

        let row = try #require(try context.fetch(FetchDescriptor<WorkSession>()).first)
        let snapshot = row.record
        context.delete(row)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<WorkSession>()) == 0)

        store.save(snapshot)
        let restored = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(restored.count == 1)
        #expect(restored.first?.record == original, "id, outcome and note all come back")
    }
}
