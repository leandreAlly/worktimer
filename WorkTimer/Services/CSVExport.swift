//
//  CSVExport.swift
//  WorkTimer
//

import SwiftUI
import UniformTypeIdentifiers

/// Turns saved sessions into a CSV file that Numbers, Excel or a script can
/// open. One row per session, oldest first, times in ISO 8601 with the
/// time-zone offset so they're unambiguous anywhere.
enum CSVExport {
    static let header = [
        "id", "task", "started_at", "ended_at", "planned_minutes", "focused_seconds",
        "paused_seconds", "pause_count", "status", "outcome", "note",
    ]

    static func csv(for sessions: [WorkSession]) -> String {
        let dates = ISO8601DateFormatter()
        dates.timeZone = .current
        var lines = [header.joined(separator: ",")]
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let fields: [String] = [
                session.id.uuidString,
                session.task,
                dates.string(from: session.startedAt),
                dates.string(from: session.endedAt),
                String(session.plannedMinutes),
                String(session.actualSeconds),
                String(session.pausedSeconds),
                String(session.pauseCount),
                session.status.rawValue,
                session.outcome.map { outcomeLabel($0) } ?? "",
                session.note,
            ]
            lines.append(fields.map { escape($0) }.joined(separator: ","))
        }
        // CRLF line endings are what the CSV standard (RFC 4180) specifies.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func outcomeLabel(_ outcome: SessionOutcome) -> String {
        switch outcome {
        case .done: "Done"
        case .continueLater: "Continue later"
        }
    }

    /// Quote a field when it holds a comma, quote or line break, doubling any
    /// quotes inside. Text that a spreadsheet would run as a formula (starting
    /// with = + - @) gets a leading apostrophe, so a task named "=SUM(A1)"
    /// shows as text instead of being evaluated.
    static func escape(_ field: String) -> String {
        var field = field
        if let first = field.first, "=+-@\t\r".contains(first) {
            field = "'" + field
        }
        guard field.contains(where: { ",\"\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func suggestedFilename(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "WorkTimer sessions \(formatter.string(from: now))"
    }
}

/// The CSV text wrapped as a document, which is what SwiftUI's
/// `.fileExporter` save panel needs.
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
