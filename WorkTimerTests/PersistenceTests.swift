//
//  PersistenceTests.swift
//  WorkTimerTests
//

import Foundation
import SwiftData
import Testing
@testable import WorkTimer

@MainActor
struct SessionStoreTests {
    /// A throwaway database that lives only in memory for this test.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: WorkSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func record(id: UUID = UUID(), seconds: Int = 600, outcome: SessionOutcome? = nil) -> SessionRecord {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return SessionRecord(id: id, task: "Task, with \"quotes\"", plannedMinutes: 25, actualSeconds: seconds,
                             goalCompleted: false, startedAt: start, endedAt: start + TimeInterval(seconds),
                             pausedSeconds: 0, pauseCount: 0, outcome: outcome, note: "")
    }

    @Test func savingTheSameIdTwiceUpdatesOneRow() throws {
        let context = try makeContext()
        let store = SessionStore(context: context)
        let id = UUID()

        store.save(record(id: id, seconds: 1500))
        store.save(record(id: id, seconds: 1542, outcome: .done))

        let rows = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(rows.count == 1)
        #expect(rows.first?.actualSeconds == 1542)
        #expect(rows.first?.outcome == .done)
    }

    @Test func differentSessionsGetTheirOwnRows() throws {
        let context = try makeContext()
        let store = SessionStore(context: context)
        store.save(record())
        store.save(record())
        #expect(try context.fetchCount(FetchDescriptor<WorkSession>()) == 2)
    }

    @Test func engineAndStoreTogetherProduceOneRowPerSession() throws {
        let context = try makeContext()
        let clock = ManualTimeSource()
        let engine = TimerEngine(clock: clock, recorder: SessionStore(context: context),
                                 stateStore: InMemoryStateStore(), scheduler: ManualScheduler())
        engine.start(task: "Task", minutes: 25)
        clock.advance(by: 1500); engine.refresh()   // saved at zero
        clock.advance(by: 60); engine.finish()      // updated with overtime
        engine.completeReview(outcome: .done, note: "Shipped")  // updated with outcome

        let rows = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(rows.count == 1)
        #expect(rows.first?.actualSeconds == 1560)
        #expect(rows.first?.status == .hitGoal)
        #expect(rows.first?.note == "Shipped")
    }

    @Test func statusLabels() {
        let base = record()
        var open = base; open.plannedMinutes = 0
        var hit = base; hit.goalCompleted = true
        #expect(WorkSession(record: open).status == .openEnded)
        #expect(WorkSession(record: hit).status == .hitGoal)
        #expect(WorkSession(record: base).status == .stoppedEarly)
    }
}

@MainActor
struct ActiveStateStoreTests {
    @Test func roundTripsEveryKindOfState() throws {
        let suite = "WorkTimerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActiveStateStore(defaults: defaults)

        let mark = ClockMark(wall: Date(timeIntervalSinceReferenceDate: 800_000_000), monotonic: 12.5)
        var run = WorkRun(id: UUID(), task: "Task", plannedSeconds: 1500, startedAt: mark.wall, runningSince: mark)
        run.pauseCount = 2
        let states: [TimerState] = [
            .ready, .running(run), .paused(run), .timeUp(run), .review(run),
            .onBreak(BreakRun(plannedSeconds: 300, startedAt: mark.wall, runningSince: mark)),
        ]
        for state in states {
            store.save(state)
            #expect(store.load() == state)
        }
    }

    @Test func unreadableDataIsIgnored() throws {
        let suite = "WorkTimerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "activeTimerState.v1")
        #expect(ActiveStateStore(defaults: defaults).load() == nil)
    }
}
