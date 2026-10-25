//
//  FlapClock.swift
//  WorkTimer
//

import SwiftUI

/// The design's numerals: one split-flap tile per digit, a 2 px hinge line
/// across the middle, square colon points.
///
/// Only the colon changes color with the timer's mood (off-white running, gray
/// paused, amber at time's up); the tiles change only to dim when paused.
struct FlapClock: View {
    /// Already formatted, e.g. "18:42" or "1:30:00".
    let text: String
    var mood: FlapMood
    var metrics: FlapMetrics

    var body: some View {
        HStack(spacing: metrics.spacing) {
            // `Array(text.enumerated())` gives each character a stable position
            // so SwiftUI knows "the 3rd tile changed" rather than rebuilding all.
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                if character == ":" {
                    ColonPoints(color: mood.colon, metrics: metrics)
                } else {
                    FlapTile(character: character, mood: mood, metrics: metrics)
                }
            }
        }
    }
}

/// How the clock is tinted for each timer state.
struct FlapMood: Equatable {
    var tile: Color
    var digit: Color
    var colon: Color
    var sheen: Bool

    static let ready = FlapMood(tile: Palette.flap, digit: Palette.paper, colon: Palette.colonIdle, sheen: true)
    static let running = FlapMood(tile: Palette.flap, digit: Palette.paper, colon: Palette.paper, sheen: true)
    static let paused = FlapMood(tile: Palette.flapPaused, digit: Palette.digitPaused, colon: Palette.colonPaused, sheen: false)
    static let timeUp = FlapMood(tile: Palette.flap, digit: Palette.paper, colon: Palette.signal, sheen: true)
    /// Breaks: amber numerals and colon. The design reserves amber for "not
    /// working"; a break is the one state where that's the whole point.
    static let onBreak = FlapMood(tile: Palette.flap, digit: Palette.signal, colon: Palette.signal, sheen: true)
}

/// Tile sizes, straight from the artboards.
struct FlapMetrics {
    var tileWidth: CGFloat
    var tileHeight: CGFloat
    var fontSize: CGFloat
    var cornerRadius: CGFloat = 8
    var hinge: CGFloat = 2
    var colonSize: CGFloat
    var colonGap: CGFloat
    var colonPadding: CGFloat
    var spacing: CGFloat = 10

    /// Ready screen: 116 × 184 tiles, 160 pt numerals.
    static func ready(long: Bool) -> FlapMetrics {
        long
            ? FlapMetrics(tileWidth: 88, tileHeight: 140, fontSize: 120, colonSize: 9, colonGap: 26, colonPadding: 6)
            : FlapMetrics(tileWidth: 116, tileHeight: 184, fontSize: 160, colonSize: 12, colonGap: 36, colonPadding: 10)
    }

    /// Focusing / paused / time's up: 128 × 204 tiles, 178 pt numerals. Hours
    /// ("1:30:00") use the smaller size so five tiles still fit the window.
    static func focus(long: Bool) -> FlapMetrics {
        long
            ? FlapMetrics(tileWidth: 88, tileHeight: 140, fontSize: 122, colonSize: 9, colonGap: 27, colonPadding: 7)
            : FlapMetrics(tileWidth: 128, tileHeight: 204, fontSize: 178, colonSize: 13, colonGap: 40, colonPadding: 10)
    }

    /// Presentation mode: 280 × 440 tiles at 388 pt on the 1440 × 900
    /// artboard, scaled to the actual screen. Hours use narrower tiles so five
    /// of them fit.
    static func presentation(scale: CGFloat, long: Bool) -> FlapMetrics {
        let base = long
            ? FlapMetrics(tileWidth: 200, tileHeight: 314, fontSize: 277, cornerRadius: 12, hinge: 3,
                          colonSize: 19, colonGap: 64, colonPadding: 16, spacing: 13)
            : FlapMetrics(tileWidth: 280, tileHeight: 440, fontSize: 388, cornerRadius: 14, hinge: 3,
                          colonSize: 26, colonGap: 90, colonPadding: 22, spacing: 18)
        return FlapMetrics(tileWidth: base.tileWidth * scale, tileHeight: base.tileHeight * scale,
                           fontSize: base.fontSize * scale, cornerRadius: base.cornerRadius * scale,
                           hinge: max(2, base.hinge * scale), colonSize: base.colonSize * scale,
                           colonGap: base.colonGap * scale, colonPadding: base.colonPadding * scale,
                           spacing: base.spacing * scale)
    }

    /// The compact floating window and menu bar popover: 44 × 68 tiles.
    static func compact(long: Bool) -> FlapMetrics {
        long
            ? FlapMetrics(tileWidth: 34, tileHeight: 54, fontSize: 46, cornerRadius: 5, hinge: 1, colonSize: 4, colonGap: 11, colonPadding: 4, spacing: 3)
            : FlapMetrics(tileWidth: 44, tileHeight: 68, fontSize: 60, cornerRadius: 5, hinge: 1, colonSize: 5, colonGap: 14, colonPadding: 5, spacing: 4)
    }
}

private struct FlapTile: View {
    let character: Character
    let mood: FlapMood
    let metrics: FlapMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettings.animateDigits) private var animateDigits = true
    @AppStorage(AppSettings.numeralStyle) private var style = NumeralStyle.flap

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        // Settings › Numerals › Flat: the same digits and spacing, no tiles.
        let flap = style == .flap
        ZStack {
            shape.fill(flap ? mood.tile : .clear)
            if mood.sheen && flap {
                // The upper flap catches a little light.
                VStack(spacing: 0) {
                    Palette.flapSheen.frame(height: metrics.tileHeight / 2)
                    Spacer(minLength: 0)
                }
            }
            Text(String(character))
                .font(.numerals(metrics.fontSize))
                .foregroundStyle(mood.digit)
                // A new `id` makes SwiftUI treat each new digit as a new view,
                // which is what lets it run the insertion transition below.
                .id(character)
                .transition(.asymmetric(insertion: .settle, removal: .identity))
            // The hinge: a thin cut in the ground color across the middle.
            if flap {
                Rectangle()
                    .fill(Palette.ground)
                    .frame(height: metrics.hinge)
            }
        }
        .frame(width: metrics.tileWidth, height: metrics.tileHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(flap ? Palette.flapBorder : .clear, lineWidth: 1))
        // The design's settle: 260 ms, cubic-bezier(.2,.7,.2,1).
        .animation(reduceMotion || !animateDigits ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.26),
                   value: character)
    }
}

private struct ColonPoints: View {
    let color: Color
    let metrics: FlapMetrics

    var body: some View {
        // Square points, never round.
        VStack(spacing: metrics.colonGap) {
            Rectangle().fill(color).frame(width: metrics.colonSize, height: metrics.colonSize)
            Rectangle().fill(color).frame(width: metrics.colonSize, height: metrics.colonSize)
        }
        .padding(.horizontal, metrics.colonPadding)
        .accessibilityHidden(true)
    }
}

private struct SettleModifier: ViewModifier {
    let opacity: Double
    let offset: CGFloat
    func body(content: Content) -> some View {
        content.opacity(opacity).offset(y: offset)
    }
}

extension AnyTransition {
    /// A new digit drops 5 px into place while fading up from 25 %.
    static var settle: AnyTransition {
        .modifier(active: SettleModifier(opacity: 0.25, offset: -5),
                  identity: SettleModifier(opacity: 1, offset: 0))
    }
}
