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
