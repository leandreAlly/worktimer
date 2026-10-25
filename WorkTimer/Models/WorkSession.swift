//
//  WorkSession.swift
//  WorkTimer
//

import Foundation
import SwiftData

/// One logged work session, stored on this Mac with SwiftData.
///
/// `@Model` turns this class into a persistent type: SwiftData generates the
/// storage and change tracking, and SwiftUI views can query it with `@Query`.
/// Breaks are never stored here.
@Model
final class WorkSession {
    /// Same value as the in-progress run's id. `.unique` lets the database
    /// itself reject a second row for the same session.
    @Attribute(.unique) var id: UUID
    var task: String
    /// The commitment in minutes; `0` = no limit (open-ended).
    var plannedMinutes: Int
    /// Focused time only. Paused time and breaks are excluded.
    var actualSeconds: Int
    var goalCompleted: Bool
    var startedAt: Date
    var endedAt: Date
    var pausedSeconds: Int
    var pauseCount: Int
    /// `SessionOutcome` raw value, or `nil` if the review was skipped.
    /// Stored as a String because enums with raw values are the simplest thing
    /// to keep stable across app versions.
    var outcomeRaw: String?
    var note: String

    init(record: SessionRecord) {
        id = record.id
        task = record.task
        plannedMinutes = record.plannedMinutes
        actualSeconds = record.actualSeconds
        goalCompleted = record.goalCompleted
        startedAt = record.startedAt
        endedAt = record.endedAt
        pausedSeconds = record.pausedSeconds
        pauseCount = record.pauseCount
        outcomeRaw = record.outcome?.rawValue
        note = record.note
    }

    func update(from record: SessionRecord) {
        task = record.task
        plannedMinutes = record.plannedMinutes
        actualSeconds = record.actualSeconds
        goalCompleted = record.goalCompleted
        startedAt = record.startedAt
        endedAt = record.endedAt
        pausedSeconds = record.pausedSeconds
        pauseCount = record.pauseCount
        outcomeRaw = record.outcome?.rawValue
        note = record.note
    }

    /// The row as plain values; History keeps one to undo a delete.
    var record: SessionRecord {
        SessionRecord(id: id, task: task, plannedMinutes: plannedMinutes, actualSeconds: actualSeconds,
                      goalCompleted: goalCompleted, startedAt: startedAt, endedAt: endedAt,
                      pausedSeconds: pausedSeconds, pauseCount: pauseCount, outcome: outcome, note: note)
    }

    var outcome: SessionOutcome? { outcomeRaw.flatMap(SessionOutcome.init(rawValue:)) }
    var isOpenEnded: Bool { plannedMinutes == 0 }

    /// The label shown in history: "Hit goal", "Stopped early" or "Open-ended".
    var status: SessionStatus {
        if isOpenEnded { return .openEnded }
        return goalCompleted ? .hitGoal : .stoppedEarly
    }
}

enum SessionStatus: String {
    case hitGoal = "Hit goal"
    case stoppedEarly = "Stopped early"
    case openEnded = "Open-ended"
}
