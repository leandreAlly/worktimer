//
//  ActiveStateStore.swift
//  WorkTimer
//

import Foundation

/// Keeps the in-progress timer in `UserDefaults` as JSON.
///
/// This is deliberately separate from the SwiftData history: it holds one small
/// value that is rewritten on every state change, while history is an
/// append-mostly list. Writing to UserDefaults is synchronous and cheap.
final class ActiveStateStore: ActiveStateStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "activeTimerState.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> TimerState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        // A state written by an incompatible older version is ignored rather
        // than crashing the app.
        return try? JSONDecoder().decode(TimerState.self, from: data)
    }

    func save(_ state: TimerState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
