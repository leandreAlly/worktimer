//
//  SessionStore.swift
//  WorkTimer
//

import Foundation
import SwiftData

/// Writes engine records into SwiftData.
final class SessionStore: SessionRecording {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Insert or update by id: one session, one row, however often it is saved.
    func save(_ record: SessionRecord) {
        let id = record.id
        // `#Predicate` is checked by the compiler and translated into a database
        // query, so only the matching row is loaded.
        var descriptor = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.update(from: record)
        } else {
            context.insert(WorkSession(record: record))
        }
        // Save right away rather than waiting for autosave, so a session that
        // just ended survives an immediate quit or crash.
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save session: \(error)")
        }
    }
}
