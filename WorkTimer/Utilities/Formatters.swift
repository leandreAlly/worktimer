//
//  Formatters.swift
//  WorkTimer
//

import Foundation

/// Turning seconds and dates into the strings the design uses.
enum Format {
    /// The big clock: "25:00", or "1:30:00" once an hour or more is involved.
    static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// Short durations in running text: "2:14", "25:42", "1:02:05".
    static func duration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Time of day in the user's own style ("3:47 PM" or "15:47").
    static func timeOfDay(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Spoken form for VoiceOver: "18 minutes 42 seconds".
    static func spoken(_ seconds: Int) -> String {
        let components = DateComponents(hour: seconds / 3600, minute: seconds % 3600 / 60, second: seconds % 60)
        return spokenFormatter.string(from: components) ?? "\(seconds) seconds"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let spokenFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter
    }()
}
