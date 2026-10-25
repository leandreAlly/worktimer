//
//  ReadyView.swift
//  WorkTimer
//

import SwiftUI

/// Artboard "1 · Ready": name the task, pick the commitment, commit.
struct ReadyView: View {
    @Environment(UIModel.self) private var ui

    /// Which text field has keyboard focus. `@FocusState` is SwiftUI's handle
    /// on first-responder status.
    @FocusState private var focus: Field?
    private enum Field { case task, customMinutes }

    var body: some View {
        // `@Bindable` lets us make `$ui.task`-style bindings into an
        // @Observable object that came from the environment.
        @Bindable var ui = ui

        VStack(alignment: .leading, spacing: 0) {
            Text("I WILL WORK ON")
                .monoLabel()
                .foregroundStyle(Palette.mute)

            TextField("", text: $ui.task, prompt: Text("Name one specific task").foregroundStyle(Palette.dim))
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.24)
                .focused($focus, equals: .task)
                .onSubmit { ui.commit() }
                .padding(.top, 14)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(focus == .task ? Palette.paper : Palette.hairline).frame(height: 1)
                }
                .accessibilityLabel("I will work on")

            FlapClock(text: Format.clock(ui.selectedMinutes * 60),
                      mood: .ready,
                      metrics: .ready(long: ui.selectedMinutes >= 60))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ui.selectedMinutes == 0
                                    ? "No time limit"
                                    : "\(ui.selectedMinutes) minutes committed")

            durationRow
            footer
        }
        .padding(.top, 8)
        .padding(.horizontal, 72)
        .padding(.bottom, 32)
        .onAppear { if ui.task.isEmpty { focus = .task } }
        .onChange(of: ui.customFieldFocusRequest) { focus = .customMinutes }
    }

    // MARK: Duration choices and end time

    private var durationRow: some View {
        @Bindable var ui = ui
        return HStack {
            HStack(spacing: 4) {
                ForEach(Array(UIModel.presets.enumerated()), id: \.offset) { index, minutes in
                    UnderlineChoice(isSelected: ui.duration == .preset(minutes)) {
                        ui.choosePreset(at: index)
                    } label: {
                        Text("\(minutes)").font(.numerals(17, weight: 600))
                    }
                    .accessibilityLabel("\(minutes) minutes")
                }
                UnderlineChoice(isSelected: ui.duration == .custom) {
                    ui.chooseCustom()
                } label: {
                    Text("Custom").font(.system(size: 14))
                }
                if ui.duration == .custom {
                    CustomMinutesField(minutes: $ui.customMinutes)
                        .focused($focus, equals: .customMinutes)
                        .padding(.leading, 4)
                }
                UnderlineChoice(isSelected: ui.duration == .noLimit) {
                    ui.duration = .noLimit
                } label: {
                    Text("No limit").font(.system(size: 14))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Time commitment")

            Spacer()

            // Re-render once a minute so "ends at" stays true while you think.
            TimelineView(.everyMinute) { context in
                Group {
                    if ui.selectedMinutes == 0 {
                        Text("no end time")
                    } else {
                        HStack(spacing: 0) {
                            Text("ends at ")
                            Text(Format.timeOfDay(context.date.addingTimeInterval(TimeInterval(ui.selectedMinutes * 60))))
                                .foregroundStyle(Palette.paper)
                        }
                    }
                }
                .font(.mono(12))
                .tracking(0.24)
                .foregroundStyle(Palette.mute)
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Palette.rule).frame(height: 1) }
    }

    // MARK: Shortcut hints and the commit button

    private var footer: some View {
        HStack {
            HStack(spacing: 16) {
                Text("1–3 presets")
                Text("4 no limit")
                Text("C custom")
            }
            .font(.mono(11))
            .tracking(0.44)
            .foregroundStyle(Palette.mute)
            .accessibilityHidden(true)

            Spacer()

            if ui.canCommit {
                Button(action: ui.commit) {
                    LabelWithKey(title: commitTitle, key: "⌘↵", onPrimary: true)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                HStack(spacing: 14) {
                    Text("Name the task to begin")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.mute)
                    Button(commitTitle) {}
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(true)
                }
            }
        }
        .padding(.top, 18)
    }

    private var commitTitle: String {
        ui.selectedMinutes == 0 ? "Start, no limit" : "Commit \(ui.selectedMinutes) min"
    }
}

/// The small "[ 30 ] min" box next to Custom. Accepts 1–600.
private struct CustomMinutesField: View {
    @Binding var minutes: Int
    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.numerals(15, weight: 600))
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 32)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hairline, lineWidth: 1))
                .accessibilityLabel("Custom minutes, 1 to 600")
                .onAppear { text = String(minutes) }
                .onChange(of: text) { _, newValue in
                    // Keep digits only; apply valid values as you type.
                    let digits = String(newValue.filter(\.isNumber).prefix(3))
                    if digits != newValue { text = digits }
                    if let value = Int(digits), TimerEngine.allowedMinutes.contains(value) {
                        minutes = value
                    }
                }
                .onSubmit {
                    // Out-of-range input snaps to the nearest allowed value.
                    let value = min(max(Int(text) ?? minutes, 1), 600)
                    minutes = value
                    text = String(value)
                }
            Text("min")
                .font(.system(size: 13))
                .foregroundStyle(Palette.mute)
        }
    }
}
