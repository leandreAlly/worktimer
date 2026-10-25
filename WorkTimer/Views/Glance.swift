//
//  Glance.swift
//  WorkTimer
//

import SwiftUI

/// What the small surfaces (compact card, mini pill, menu bar) show for the
/// current state. Computing it in one place keeps all three in agreement.
struct Glance: Equatable {
    enum Marker: Equatable {
        /// Hollow ring: nothing running.
        case idle
        /// Filled dot: the clock is moving.
        case live
        /// Two bars, amber.
        case paused
        /// Square, amber: time's up.
        case alert
        /// Filled dot, amber: on a break.
        case breakTime
        /// Hollow ring, light: waiting for a review.
        case review
    }

    var marker: Marker
    /// "FOCUSING", "TIME'S UP · +2:13" …
    var status: String
    /// The digits for the flap tiles.
    var clock: String
    /// Short text for the menu bar and the pill: "18:42", "+2:13", or nil
    /// when nothing is timing.
    var menuBarTime: String?
    var mood: FlapMood
    /// Share of the progress hairline that's filled (time left), 0...1.
    var fill: Double
    var title: String

    var isAmber: Bool { [.paused, .alert, .breakTime].contains(marker) }

    @MainActor
    init(engine: TimerEngine, ui: UIModel) {
        let reading = engine.reading()
        let time = Format.clock(reading.clockSeconds)
        switch engine.state {
        case .ready:
            let breakOver = engine.notice == .breakOver
            marker = breakOver ? .alert : .idle
            status = breakOver ? "BREAK'S OVER" : "READY"
            clock = Format.clock(ui.selectedMinutes * 60)
            menuBarTime = nil
            mood = .ready
            fill = 0
            title = ui.task.isEmpty ? "Name a task to begin" : ui.task
        case .running(let run):
            marker = .live
            status = run.isOpenEnded ? "TRACKING" : "FOCUSING"
            clock = time
            menuBarTime = Format.duration(reading.clockSeconds)
            mood = .running
            fill = run.isOpenEnded ? 0 : 1 - reading.progress
            title = run.task
        case .paused(let run):
            marker = .paused
            status = "PAUSED · \(Format.duration(Int(reading.pausedSeconds)))"
            clock = time
            menuBarTime = Format.duration(reading.clockSeconds)
            mood = .paused
            fill = run.isOpenEnded ? 0 : 1 - reading.progress
            title = run.task
        case .timeUp(let run):
            let over = "+" + Format.duration(Int(reading.overtimeSeconds))
            marker = .alert
            status = "TIME'S UP · \(over)"
            clock = Format.clock(0)
            menuBarTime = over
            mood = .timeUp
            fill = 0
            title = run.task
        case .review(let run):
            marker = .review
            status = "REVIEW"
            clock = Format.clock(Int(run.workedBefore.rounded()))
            menuBarTime = nil
            mood = .ready
            fill = 0
            title = run.task
        case .onBreak:
            marker = .breakTime
            status = "BREAK"
            clock = time
            menuBarTime = Format.duration(reading.clockSeconds)
            mood = .onBreak
            fill = 1 - reading.progress
            title = "Step away from the screen"
        }
    }
}

/// The small state marker drawn before a status line.
struct GlanceMarker: View {
    let marker: Glance.Marker
    var size: CGFloat = 5

    var body: some View {
        switch marker {
        case .idle:
            Circle().strokeBorder(Palette.mute, lineWidth: 1).frame(width: size + 1, height: size + 1)
        case .live:
            Circle().fill(Palette.paper).frame(width: size, height: size)
        case .paused:
            HStack(spacing: 2) {
                Rectangle().frame(width: 2, height: size + 3)
                Rectangle().frame(width: 2, height: size + 3)
            }
            .foregroundStyle(Palette.signal)
        case .alert:
            Rectangle().fill(Palette.signal).frame(width: size, height: size)
        case .breakTime:
            Circle().fill(Palette.signal).frame(width: size, height: size)
        case .review:
            Circle().strokeBorder(Palette.paper, lineWidth: 1).frame(width: size + 1, height: size + 1)
        }
    }
}
