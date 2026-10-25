//
//  Controls.swift
//  WorkTimer
//

import SwiftUI

// The design's three button weights: a filled Paper primary, an outlined
// secondary (Pause), and quiet ghost text buttons. All are 44 pt tall, the
// minimum comfortable click target.

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEnabled ? Palette.primaryText : Palette.dim)
            .padding(.leading, 22)
            .padding(.trailing, 18)
            .frame(height: 44)
            .background(isEnabled ? Palette.primaryFill : Palette.disabledFill,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.paper)
            .padding(.leading, 22)
            .padding(.trailing, 18)
            .frame(height: 44)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.outline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostLabel(configuration: configuration)
    }

    private struct GhostLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 14))
                .foregroundStyle(hovering || configuration.isPressed ? Palette.paper : Palette.mute)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// The small key hint inside buttons, e.g. "SPACE" or "⌘↵".
struct Keycap: View {
    let label: String
    var onPrimary = false

    var body: some View {
        Text(label)
            .font(.mono(11, medium: true))
            .foregroundStyle(onPrimary ? Palette.primaryKeycapText : Palette.mute)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
                onPrimary ? Palette.primaryKeycapBorder : Palette.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A button label with a trailing keycap, as in "Commit 25 min ⌘↵".
struct LabelWithKey: View {
    let title: String
    let key: String
    var onPrimary = false

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
            Keycap(label: key, onPrimary: onPrimary)
        }
    }
}

/// The header's 32 pt icon buttons (keep on top, compact, settings).
struct HeaderIconButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isOn ? Palette.paper : Palette.mute)
                .frame(width: 32, height: 32)
                .background(isOn ? Palette.toggleOnFill : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(label)
    }
}

/// An underlined choice like the duration presets ("25", "50", "90").
struct UnderlineChoice<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                // Never wrap ("Custo / m"): a choice keeps its natural width.
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? Palette.paper : Palette.mute)
                .padding(.horizontal, 12)
                .frame(minWidth: 52, minHeight: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(isSelected ? Palette.paper : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Hold to reset": nothing happens on a click; holding for a full second
/// discards the session. A ring fills while held, so there is no dialog to
/// dismiss and no accidental resets.
struct HoldToResetButton: View {
    /// 0...1 while held, driven by the shared UI model so the R key fills the
    /// same ring.
    let progress: Double
    let onPress: (Bool) -> Void
    /// VoiceOver can't "hold", so its activate action resets directly.
    let onAccessibilityActivate: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Palette.hairline, lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: max(progress, 0.25))
                    .stroke(progress > 0 ? Palette.paper : Palette.mute, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            Text("Hold to reset")
        }
        .font(.system(size: 14))
        .foregroundStyle(hovering || progress > 0 ? Palette.paper : Palette.mute)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // A long-press gesture reports press-down and release, which is
        // exactly "start the hold" / "let go".
        .onLongPressGesture(minimumDuration: 60, perform: {}, onPressingChanged: onPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reset session")
        .accessibilityHint("Discards this session without logging it")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAccessibilityActivate() }
    }
}
