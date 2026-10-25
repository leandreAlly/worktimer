//
//  AppSettings.swift
//  WorkTimer
//

import SwiftUI

/// UserDefaults keys, in one place so a typo can't silently create a second
/// setting. Views read them with `@AppStorage(AppSettings.theme)`.
enum AppSettings {
    static let theme = "theme"
    static let animateDigits = "animateDigits"
    static let floatOnTop = "floatOnTop"
    static let lastTask = "lastTask"
    static let lastDuration = "lastDuration"
    static let customMinutes = "customMinutes"
    static let notifyWhenDone = "notifyWhenDone"
    static let endChime = "endChime"
    static let showMenuBarTime = "showMenuBarTime"
    static let compactFloatOnTop = "compactFloatOnTop"

    /// Values used until the user changes them. `register` doesn't write
    /// anything to disk; it only answers reads of keys that were never set.
    static func registerDefaults(in defaults: UserDefaults) {
        defaults.register(defaults: [
            animateDigits: true,
            notifyWhenDone: true,
            endChime: EndChime.softBell.rawValue,
            showMenuBarTime: true,
        ])
    }
}

/// Settings › Appearance › Theme. Dark is the design's primary appearance.
enum ThemeChoice: String, CaseIterable {
    case system, dark, light

    /// `nil` tells SwiftUI to follow the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

/// Settings › Sound › End chime.
enum EndChime: String, CaseIterable {
    case softBell, none
}
