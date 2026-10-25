//
//  CompactViews.swift
//  WorkTimer
//

import SwiftUI

/// What the floating panel shows: the compact card or the mini pill,
/// depending on the window mode.
struct FloatingContent: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(UIModel.self) private var ui
    @Environment(WindowModes.self) private var modes
    @AppStorage(AppSettings.theme) private var theme = ThemeChoice.dark

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: engine.state.phase == .paused)) { _ in
            let glance = Glance(engine: engine, ui: ui)
            Group {
                if modes.mode == .mini {
                    MiniPill(glance: glance)
                } else {
                    CompactCardFrame {
                        CompactCard(glance: glance)
                            .frame(height: WindowModes.Mode.compact.panelSize.height, alignment: .top)
                    }
                }
            }
        }
        .foregroundStyle(Palette.paper)
        .preferredColorScheme(theme.colorScheme)
        // A double click anywhere opens the full window, like the expand button.
        .onTapGesture(count: 2) { modes.show(.full) }
    }
}

/// "Compact" artboard: 308 × 160, status and three icon buttons, 44 × 68
/// tiles, the task, and the progress hairline along the bottom edge.
struct CompactCard: View {
    let glance: Glance
    /// The menu bar popover reuses the card without the window buttons.
    var showsWindowButtons = true

    @Environment(TimerEngine.self) private var engine
    @Environment(UIModel.self) private var ui
    @Environment(WindowModes.self) private var modes

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    GlanceMarker(marker: glance.marker)
                    Text(glance.status)
                        .foregroundStyle(glance.isAmber ? Palette.signal : Palette.mute)
                }
                .monoLabel(size: 10)
                .accessibilityElement(children: .combine)
                Spacer()
                if showsWindowButtons {
                    windowButtons
                }
            }
            .frame(height: 28)
            .padding(.top, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)

            let metrics = FlapMetrics.compact(long: glance.clock.count > 5)
            FlapClock(text: glance.clock, mood: glance.mood, metrics: metrics)
                .frame(height: 68)
                .padding(.top, 6)
                .padding(.horizontal, 14)
                .accessibilityLabel(glance.clock)

            Text(glance.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(engine.state == .ready && ui.task.isEmpty ? Palette.mute : Palette.paper)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 10)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            Spacer(minLength: 0)
            CompactHairline(fill: glance.fill, amber: glance.marker == .breakTime,
                            dimmed: glance.marker == .paused)
        }
        .frame(width: 308, alignment: .leading)
        .background(Palette.ground)
    }

    @ViewBuilder private var windowButtons: some View {
        HStack(spacing: 0) {
            switch engine.state {
            case .ready:
                CompactIconButton(systemImage: "play.fill", label: "Start") { ui.commit() }
                    .disabled(!ui.canCommit)
            case .running:
                CompactIconButton(systemImage: "pause", label: "Pause") { engine.pause() }
            case .paused:
                CompactIconButton(systemImage: "play.fill", label: "Resume") { engine.resume() }
            default:
                EmptyView()
            }
            CompactIconButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Expand to full window") {
                modes.show(.full)
            }
            CompactIconButton(systemImage: modes.panelFloats ? "pin.fill" : "pin",
                              label: modes.panelFloats ? "Unpin from top" : "Keep on top",
                              isOn: modes.panelFloats) {
                modes.panelFloats.toggle()
            }
        }
    }
}

/// The 308 × 40 pill: marker, time, task.
struct MiniPill: View {
    let glance: Glance

    var body: some View {
        HStack(spacing: 10) {
            GlanceMarker(marker: glance.marker, size: 6)
            Text(glance.menuBarTime ?? glance.clock)
                .font(.numerals(17))
                .foregroundStyle(glance.marker == .alert ? Palette.signal : Palette.paper)
                .fixedSize()
            Text(glance.title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.mute)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 308, height: 40)
        .background(Palette.ground)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .help("Double-click for the full window · ⌘\\ cycles sizes")
    }
}

private struct CompactHairline: View {
    let fill: Double
    let amber: Bool
    let dimmed: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.trackPaused)
                Rectangle()
                    .fill(amber ? Palette.signal : dimmed ? Palette.fillPaused : Palette.paper)
                    .frame(width: proxy.size.width * min(max(fill, 0), 1))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// The compact card's 28 pt icon buttons.
private struct CompactIconButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn || hovering ? Palette.paper : Palette.mute)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Wraps the card in its 12 pt rounded frame for the floating panel.
struct CompactCardFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }
}
