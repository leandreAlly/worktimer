//
//  RootView.swift
//  WorkTimer
//

import SwiftUI

/// The main window: the 52 pt header and the screen for the current state.
struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(WindowModes.self) private var modes
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppSettings.theme) private var theme = ThemeChoice.dark
    @AppStorage(AppSettings.floatOnTop) private var floatOnTop = true

    var body: some View {
        // The window's exact 880 × 560 frame is set by WindowConfigurator;
        // this view fills it, including the strip under the hidden title bar.
        VStack(spacing: 0) {
            WindowHeader(floatOnTop: $floatOnTop)
                .frame(height: MainWindow.headerHeight)
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: MainWindow.size.width)
        .frame(minHeight: 400, maxHeight: .infinity)
        .foregroundStyle(Palette.paper)
        .background(Palette.ground)
        .ignoresSafeArea()
        .background(WindowConfigurator(floatOnTop: floatOnTop))
        .preferredColorScheme(theme.colorScheme)
        // Lets the menu bar and notifications reopen this window after the
        // user has closed it.
        .onAppear {
            modes.openMainWindow = { openWindow(id: MainWindow.id) }
            #if DEBUG
            if let id = PreviewLaunch.extraWindowID { openWindow(id: id) }
            #endif
        }
    }

    @ViewBuilder private var screen: some View {
        switch engine.state {
        case .ready:
            ReadyView()
        case .running, .paused, .timeUp, .onBreak:
            FocusView()
        case .review(let run):
            ReviewView(run: run)
        }
    }
}

/// Window buttons on the left (drawn by AppKit), status in the middle,
/// quiet icon buttons on the right.
private struct WindowHeader: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(WindowModes.self) private var modes
    @Environment(\.openWindow) private var openWindow
    @Binding var floatOnTop: Bool

    var body: some View {
        ZStack {
            // TimelineView redraws the status every second while it shows a
            // live number (pause length), and never when it doesn't.
            TimelineView(.animation(minimumInterval: 1, paused: !isLive)) { _ in
                StatusLine(engine: engine)
            }
            HStack {
                Spacer()
                if showsWindowButtons {
                    HeaderIconButton(systemImage: floatOnTop ? "pin.fill" : "pin",
                                     label: floatOnTop ? "Keep on top (on)" : "Keep on top",
                                     isOn: floatOnTop) {
                        floatOnTop.toggle()
                    }
                    HeaderIconButton(systemImage: "chart.bar", label: "History (⌘Y)") {
                        openWindow(id: HistoryWindow.id)
                    }
                    HeaderIconButton(systemImage: "arrow.down.right.and.arrow.up.left",
                                     label: "Compact mode (⌘\\)") {
                        modes.show(.compact)
                    }
                    HeaderIconButton(systemImage: "slider.horizontal.3", label: "Settings (⌘,)") {
                        openWindow(id: SettingsWindow.id)
                    }
                }
            }
            .padding(.trailing, 16)
        }
    }

    private var isLive: Bool {
        switch engine.state.phase {
        case .ready, .review: false
        default: true
        }
    }

    /// The design shows the header buttons on Ready and Focusing only; the
    /// paused, time's-up and review screens keep the header bare.
    private var showsWindowButtons: Bool {
        switch engine.state.phase {
        case .ready, .running, .onBreak: true
        default: false
        }
    }
}

/// "● FOCUSING · UNTIL 3:47 PM" and its siblings.
struct StatusLine: View {
    let engine: TimerEngine

    var body: some View {
        let reading = engine.reading()
        HStack(spacing: 8) {
            switch engine.state {
            case .ready:
                if engine.notice == .breakOver {
                    Square(color: Palette.signal)
                    Text("BREAK'S OVER").foregroundStyle(Palette.signal)
                } else {
                    Circle().strokeBorder(Palette.mute, lineWidth: 1).frame(width: 6, height: 6)
                    Text("READY")
                }
            case .running(let run):
                Circle().fill(Palette.paper).frame(width: 6, height: 6)
                if run.isOpenEnded {
                    Text("TRACKING").foregroundStyle(Palette.paper)
                    Text("· SINCE \(Format.timeOfDay(run.startedAt).uppercased())")
                } else {
                    Text("FOCUSING").foregroundStyle(Palette.paper)
                    if let endsAt = reading.endsAt {
                        Text("· UNTIL \(Format.timeOfDay(endsAt).uppercased())")
                    }
                }
            case .paused:
                HStack(spacing: 2) {
                    Rectangle().frame(width: 2, height: 8)
                    Rectangle().frame(width: 2, height: 8)
                }
                .foregroundStyle(Palette.signal)
                Text("PAUSED · \(Format.duration(Int(reading.pausedSeconds)))")
                    .foregroundStyle(Palette.signal)
            case .timeUp(let run):
                Square(color: Palette.signal)
                Text("TIME'S UP · \(Format.timeOfDay(run.endedAt ?? .now).uppercased())")
                    .foregroundStyle(Palette.signal)
            case .review:
                Text("REVIEW")
            case .onBreak:
                Circle().fill(Palette.signal).frame(width: 6, height: 6)
                Text("BREAK").foregroundStyle(Palette.signal)
                if let endsAt = reading.endsAt {
                    Text("· UNTIL \(Format.timeOfDay(endsAt).uppercased())")
                }
            }
        }
        .monoLabel()
        .foregroundStyle(Palette.mute)
        .accessibilityElement(children: .combine)
    }

    private struct Square: View {
        let color: Color
        var body: some View { Rectangle().fill(color).frame(width: 6, height: 6) }
    }
}
