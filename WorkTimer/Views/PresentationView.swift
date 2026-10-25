//
//  PresentationView.swift
//  WorkTimer
//

import AppKit
import SwiftUI

/// Artboard "Presentation": the clock alone on a full screen, for a second
/// display or a shared screen. Controls appear when the pointer moves and
/// fade after a few seconds; Esc (or ⌃⌘F) leaves.
struct PresentationView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(UIModel.self) private var ui
    @Environment(WindowModes.self) private var modes
    @AppStorage(AppSettings.theme) private var theme = ThemeChoice.dark

    @State private var controlsVisible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            // Everything is laid out on the 1440 × 900 artboard and scaled to
            // the screen, so a laptop and an external display look the same.
            let scale = min(proxy.size.width / 1440, proxy.size.height / 900)
            TimelineView(.animation(minimumInterval: 0.25, paused: engine.state.phase == .paused)) { _ in
                content(reading: engine.reading(), scale: scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(Palette.paper)
        .background(Palette.ground)
        .preferredColorScheme(theme.colorScheme)
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
        .onAppear { revealControls() }
        .onChange(of: engine.state.phase) {
            // Review and Ready belong in the full window.
            switch engine.state.phase {
            case .ready, .review: modes.endPresentation()
            default: revealControls()
            }
        }
    }

    @ViewBuilder
    private func content(reading: TimerReading, scale: CGFloat) -> some View {
        let state = engine.state
        let glance = Glance(engine: engine, ui: ui)
        ZStack {
            VStack(spacing: 0) {
                let clock = state.phase == .timeUp ? Format.clock(0) : Format.clock(reading.clockSeconds)
                FlapClock(text: clock, mood: glance.mood,
                          metrics: .presentation(scale: scale, long: clock.count > 5))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(clock)
                    .accessibilityAddTraits(.updatesFrequently)

                Text(glance.title)
                    .font(.system(size: 26 * scale, weight: .medium))
                    .tracking(-0.26 * scale)
                    .lineLimit(1)
                    .padding(.top, 56 * scale)
                    .padding(.horizontal, 56 * scale)

                ZStack {
                    // Kept in the layout at all times so nothing jumps when
                    // the controls appear.
                    Text("CONTROLS APPEAR ON MOUSE MOVE · ESC TO EXIT")
                        .font(.mono(12 * scale))
                        .tracking(0.96 * scale)
                        .foregroundStyle(Palette.mute)
                        .opacity(showsControls ? 0 : 1)
                    FocusControls(state: state)
                        .opacity(showsControls ? 1 : 0)
                        .allowsHitTesting(showsControls)
                }
                .frame(height: 44)
                .padding(.top, 14 * scale)
            }

            corners(glance: glance, reading: reading, scale: scale)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.trackPaused)
                    Rectangle()
                        .fill(glance.marker == .breakTime ? Palette.signal
                              : glance.marker == .paused ? Palette.fillPaused : Palette.paper)
                        .frame(width: proxy.size.width * min(max(glance.fill, 0), 1))
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .animation(.easeOut(duration: 0.2), value: showsControls)
    }

    /// Status top left, "UNTIL 3:47 PM" (or overtime) top right.
    private func corners(glance: Glance, reading: TimerReading, scale: CGFloat) -> some View {
        VStack {
            HStack {
                HStack(spacing: 10 * scale) {
                    GlanceMarker(marker: glance.marker, size: 7 * scale)
                    Text(glance.status)
                        .tracking(2.16 * scale)
                        .foregroundStyle(glance.isAmber ? Palette.signal : Palette.mute)
                }
                Spacer()
                Group {
                    if case .timeUp = engine.state {
                        Text("+\(Format.duration(Int(reading.overtimeSeconds))) OVER")
                            .foregroundStyle(Palette.signal)
                    } else if let endsAt = reading.endsAt {
                        Text("UNTIL \(Format.timeOfDay(endsAt).uppercased())")
                            .foregroundStyle(Palette.mute)
                    }
                }
                .tracking(0.96 * scale)
            }
            .font(.mono(12 * scale))
            Spacer()
        }
        .padding(.horizontal, 56 * scale)
        .padding(.top, 44 * scale)
    }

    /// Paused and time's up keep their controls on screen: those are the
    /// moments someone needs to act.
    private var showsControls: Bool {
        switch engine.state.phase {
        case .paused, .timeUp: true
        default: controlsVisible
        }
    }

    private func revealControls() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            controlsVisible = false
            // Out of the way until the mouse moves again.
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
}
