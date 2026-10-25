//
//  Palette.swift
//  WorkTimer
//

import AppKit
import SwiftUI

/// The approved palette ("Palette & type" artboard). Dark is the primary
/// appearance; light values come from the "Light appearance" artboard.
///
/// Each color resolves itself when drawn: `NSColor(name:dynamicProvider:)` asks
/// for the window's current appearance, so switching Dark/Light needs no view
/// code at all.
enum Palette {
    // Grounds and surfaces
    static let ground = Color(dark: 0x0B0B0C, light: 0xECEAE4)        // Ink: window
    static let flap = Color(dark: 0x161618, light: 0xFAF9F6)          // digit tiles
    static let flapPaused = Color(dark: 0x121214, light: 0xF3F1EC)
    static let flapBorder = Color(dark: 0x000000, darkAlpha: 0, light: 0xDCD9D2)
    static let flapSheen = Color(dark: 0xFFFFFF, darkAlpha: 0.03, light: 0xFFFFFF, lightAlpha: 0)
    static let field = Color(dark: 0x161618, light: 0xFAF9F6)

    // Lines
    static let hairline = Color(dark: 0x2A2A2D, light: 0xD0CDC6)      // field borders, keycaps
    static let rule = Color(dark: 0x1E1E21, light: 0xDCD9D2)          // section rules
    static let track = Color(dark: 0x232326, light: 0xD6D3CC)         // progress track
    static let trackPaused = Color(dark: 0x1C1C1F, light: 0xDCD9D2)

    // Text
    static let paper = Color(dark: 0xECEAE4, light: 0x141414)         // numerals, primary text
    static let secondary = Color(dark: 0xB9B6AE, light: 0x4A4946)
    static let mute = Color(dark: 0x8E8C86, light: 0x5F5D58)          // secondary text, 6.0:1
    static let dim = Color(dark: 0x6E6C67, light: 0x8A877F)           // placeholders, disabled
    static let digitPaused = Color(dark: 0x68665F, light: 0xA9A6A0)
    static let fillPaused = Color(dark: 0x5A5955, light: 0xA9A6A0)

    // Colon points: the only part of the clock that changes color.
    static let colonIdle = Color(dark: 0x4A4946, light: 0xA9A6A0)
    static let colonPaused = Color(dark: 0x3A3936, light: 0xC9C6BF)

    /// Signal amber: paused, time's up and breaks only. The light variant is
    /// darker than the canvas's #D9A441 because that amber on the light ground
    /// is about 2:1, unreadable for 11 px status text.
    static let signal = Color(dark: 0xD9A441, light: 0x8A5F0E)

    // Buttons
    static let primaryFill = Color(dark: 0xECEAE4, light: 0x141414)
    static let primaryText = Color(dark: 0x0B0B0C, light: 0xECEAE4)
    static let primaryKeycapText = Color(dark: 0x4A4946, light: 0xB9B6AE)
    static let primaryKeycapBorder = Color(dark: 0xB9B6AE, light: 0x4A4946)
    static let outline = Color(dark: 0x4A4946, light: 0xA9A6A0)
    static let disabledFill = Color(dark: 0x1E1E21, light: 0xDCD9D2)
    static let toggleOnFill = Color(dark: 0x1E1E21, light: 0xDCD9D2)
}

extension Color {
    /// A color with separate dark- and light-appearance values, given as hex.
    init(dark: UInt32, darkAlpha: Double = 1, light: UInt32, lightAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
