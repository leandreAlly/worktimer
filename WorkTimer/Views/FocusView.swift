//
//  FocusView.swift
//  WorkTimer
//

import SwiftUI

/// Artboards "2 · Focusing", "3 · Paused" and "4 · Time's up", plus the
/// open-ended and break variants, which share one layout:
/// task, clock, progress hairline, controls.
struct FocusView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(UIModel.self) private var ui

    var body: some View {
        // Redraw 4× a second while time is moving so each new second lands
        // promptly; pause the schedule entirely while paused. Every number is
        // read from the engine, so a late or skipped redraw can't drift.
        TimelineView(.animation(minimumInterval: 0.25, paused: engine.state.phase == .paused)) { _ in
            content(engine.reading())
        }
    }

    @ViewBuilder
    private func content(_ reading: TimerReading) -> some View {
        let state = engine.state
        VStack(spacing: 0) {
            if let overline = overline(state) {
                Text(overline)
                    .monoLabel()
                    .foregroundStyle(Palette.mute)
                    .padding(.bottom, 10)
            }

            Text(title(state))
                .font(.system(size: 20, weight: .medium))
                .tracking(-0.2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 600)
                .padding(.bottom, 28)

            let clock = Format.clock(clockSeconds(state, reading))
            FlapClock(text: clock, mood: mood(state), metrics: .focus(long: clock.count > 5))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(state, reading))
                .accessibilityAddTraits(.updatesFrequently)

            ProgressHairline(fill: progressFill(state, reading), state: state)
                .padding(.top, 22)

            HStack {
                leftCaption(state, reading)
                Spacer()
                rightCaption(state, reading)
            }
            .font(.mono(11))
            .tracking(0.44)
            .foregroundStyle(Palette.mute)
            .frame(width: 590)
            .padding(.top, 10)

            controls(state)
                .padding(.top, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 72)
        .padding(.bottom, 28)
    }

    // MARK: Text

    private func overline(_ state: TimerState) -> String? {
        switch state {
        case .timeUp(let run): "\(run.plannedSeconds / 60) MINUTES, AS COMMITTED"
        case .onBreak(let breakRun): "\(breakRun.plannedSeconds / 60)-MINUTE BREAK"
        default: nil
        }
    }

    private func title(_ state: TimerState) -> String {
        if case .onBreak = state { return "Step away from the screen" }
        return state.workRun?.task ?? ""
    }

    /// Time's up freezes the tiles at 00:00; overtime is shown in amber below.
    private func clockSeconds(_ state: TimerState, _ reading: TimerReading) -> Int {
        if case .timeUp = state { return 0 }
        return reading.clockSeconds
    }

    private func mood(_ state: TimerState) -> FlapMood {
        switch state.phase {
        case .paused: .paused
        case .timeUp: .timeUp
        case .onBreak: .onBreak
        default: .running
        }
    }

    private func accessibilityLabel(_ state: TimerState, _ reading: TimerReading) -> String {
        let time = Format.spoken(reading.clockSeconds)
        switch state {
        case .running(let run): return run.isOpenEnded ? "\(time) elapsed" : "\(time) remaining"
        case .paused(let run): return run.isOpenEnded ? "Paused at \(time)" : "Paused with \(time) remaining"
        case .timeUp: return "Time is up, \(Format.spoken(Int(reading.overtimeSeconds))) over"
        case .onBreak: return "Break, \(time) remaining"
        default: return time
        }
    }

    /// The hairline shows time *left*, so it shrinks toward zero like the
    /// digits do. Open-ended sessions and time's up show the bare track.
    private func progressFill(_ state: TimerState, _ reading: TimerReading) -> Double {
        switch state {
        case .running(let run), .paused(let run): run.isOpenEnded ? 0 : 1 - reading.progress
        case .onBreak: 1 - reading.progress
        default: 0
        }
    }

    @ViewBuilder
    private func leftCaption(_ state: TimerState, _ reading: TimerReading) -> some View {
        switch state {
        case .running:
            Text("\(Int(reading.workedSeconds) / 60) MIN IN")
        case .paused(let run):
            Text(run.isOpenEnded
                 ? "THE CLOCK IS HOLDING AT \(Format.clock(reading.clockSeconds))"
                 : "THE CLOCK IS HOLDING YOUR \(Format.clock(reading.clockSeconds))")
        case .timeUp:
            Text("SAVED TO HISTORY")
        case .onBreak:
            Text("NOT LOGGED AS WORK")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func rightCaption(_ state: TimerState, _ reading: TimerReading) -> some View {
        switch state {
        case .running(let run):
            Text(run.isOpenEnded ? "NO LIMIT" : "\(run.plannedSeconds / 60) MIN COMMITTED")
        case .paused:
            Text("PAUSED \(reading.pauseCount)× THIS SESSION")
        case .timeUp:
            Text("+\(Format.duration(Int(reading.overtimeSeconds))) OVER")
                .foregroundStyle(Palette.signal)
        case .onBreak(let breakRun):
            Text("\(breakRun.plannedSeconds / 60) MIN")
        default:
            EmptyView()
        }
    }

    // MARK: Controls (only the ones that apply to this state)

    @ViewBuilder
    private func controls(_ state: TimerState) -> some View {
        HStack(spacing: 8) {
            switch state {
            case .running(let run):
                Button { engine.pause() } label: { LabelWithKey(title: "Pause", key: "SPACE") }
                    .buttonStyle(OutlineButtonStyle())
                if !run.isOpenEnded {
                    Button("+5 min") { engine.extend(minutes: 5) }
                        .buttonStyle(GhostButtonStyle())
                        .accessibilityLabel("Add 5 minutes")
                }
                Button(run.isOpenEnded ? "Finish & log" : "Finish early") { engine.finish() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Finish and log (⌘↵)")

            case .paused(let run):
                Button { engine.resume() } label: { LabelWithKey(title: "Resume", key: "SPACE", onPrimary: true) }
                    .buttonStyle(PrimaryButtonStyle())
                Button(run.isOpenEnded ? "Finish & log" : "Finish early") { engine.finish() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Finish and log (⌘↵)")
                HoldToResetButton(progress: ui.holdProgress,
                                  onPress: ui.setHolding,
                                  onAccessibilityActivate: { engine.discard() })
                    .help("Hold for one second (or hold R) to discard this session")

            case .timeUp:
                Button { engine.finish() } label: { LabelWithKey(title: "Review session", key: "↵", onPrimary: true) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("+5 min") { engine.extend(minutes: 5) }
                    .buttonStyle(GhostButtonStyle())
                    .accessibilityLabel("Add 5 minutes")
                Button("+15 min") { engine.extend(minutes: 15) }
                    .buttonStyle(GhostButtonStyle())
                    .accessibilityLabel("Add 15 minutes")
                Button("5-min break") { engine.startBreak() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Log this session and start a five-minute break")

            case .onBreak:
                Button("End break") { engine.endBreak() }
                    .buttonStyle(GhostButtonStyle())

            default:
                EmptyView()
            }
        }
    }
}

/// The 2 pt line under the clock, 590 pt wide as drawn.
private struct ProgressHairline: View {
    let fill: Double
    let state: TimerState

    var body: some View {
        let paused = state.phase == .paused
        ZStack(alignment: .leading) {
            Rectangle().fill(paused ? Palette.trackPaused : Palette.track)
            Rectangle()
                .fill(fillColor(paused: paused))
                .frame(width: 590 * min(max(fill, 0), 1))
        }
        .frame(width: 590, height: 2)
        .accessibilityHidden(true)
    }

    private func fillColor(paused: Bool) -> Color {
        if paused { return Palette.fillPaused }
        if state.phase == .onBreak { return Palette.signal }
        return Palette.paper
    }
}
