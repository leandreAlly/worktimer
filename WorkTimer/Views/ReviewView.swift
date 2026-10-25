//
//  ReviewView.swift
//  WorkTimer
//

import SwiftUI

/// Artboard "5 · Session review". The session is already saved; this screen
/// adds how it went (and an optional note) to the same record, or continues it.
struct ReviewView: View {
    let run: WorkRun

    @Environment(TimerEngine.self) private var engine
    @Environment(UIModel.self) private var ui

    var body: some View {
        @Bindable var ui = ui

        HStack(alignment: .top, spacing: 56) {
            summary.frame(width: 300, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                outcomePicker
                if ui.reviewChoice == .more { extensionPicker }
                noteField
                Spacer(minLength: 18)
                actions
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 64)
        .padding(.bottom, 32)
        .onAppear { ui.prepareReview(for: run) }
        .onChange(of: run.id) { ui.prepareReview(for: run) }
    }

    // MARK: Left column: what happened

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(engine.notice == .completedWhileAway ? "SESSION · COMPLETED WHILE AWAY" : "SESSION")
                .monoLabel()
                .foregroundStyle(Palette.mute)
            Text(run.task)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.52)
                .lineSpacing(2)
                .lineLimit(3)
                .padding(.top, 10)

            VStack(spacing: 0) {
                StatRow(label: "Committed", value: run.isOpenEnded ? "No limit" : Format.clock(run.plannedSeconds))
                StatRow(label: "Focused", value: Format.duration(Int(run.workedBefore.rounded())))
                StatRow(label: "Paused", value: run.pauseCount == 0
                        ? "—"
                        : "\(run.pauseCount)× · \(Format.duration(Int(run.pausedBefore.rounded())))")
                StatRow(label: "Window", value: "\(Format.timeOfDay(run.startedAt)) – \(Format.timeOfDay(run.endedAt ?? .now))")
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.rule).frame(height: 1) }
            .padding(.top, 28)
        }
    }

    private struct StatRow: View {
        let label: String
        let value: String
        var body: some View {
            HStack {
                Text(label).foregroundStyle(Palette.mute)
                Spacer()
                Text(value).font(.numerals(13, weight: 600))
            }
            .font(.system(size: 13))
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Right column: how did it go?

    private var outcomePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HOW DID IT GO?")
                .monoLabel()
                .foregroundStyle(Palette.mute)
            VStack(spacing: 0) {
                OutcomeRow(title: "Done", subtitle: "The task is complete.", key: "D",
                           isSelected: ui.reviewChoice == .done) { ui.reviewChoice = .done }
                OutcomeRow(title: "Need more time", subtitle: "Keep going on the same task now.", key: "M",
                           isSelected: ui.reviewChoice == .more) { ui.reviewChoice = .more }
                OutcomeRow(title: "Continue later", subtitle: "Save it to pick up next time.", key: "L",
                           isSelected: ui.reviewChoice == .later) { ui.reviewChoice = .later }
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.rule).frame(height: 1) }
            .padding(.top, 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("How did it go?")
        }
    }

    private var extensionPicker: some View {
        HStack(spacing: 4) {
            Text("Extend by")
                .font(.system(size: 13))
                .foregroundStyle(Palette.mute)
                .padding(.trailing, 6)
            ForEach(UIModel.reviewExtensions, id: \.self) { minutes in
                UnderlineChoice(isSelected: ui.reviewExtraMinutes == minutes) {
                    ui.reviewExtraMinutes = minutes
                } label: {
                    Text("+\(minutes)").font(.numerals(15, weight: 600))
                }
                .frame(height: 32)
                .accessibilityLabel("\(minutes) more minutes")
            }
        }
        .padding(.top, 10)
        .padding(.leading, 32)
    }

    private var noteField: some View {
        @Bindable var ui = ui
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Note").foregroundStyle(Palette.mute)
                Text("— optional").foregroundStyle(Palette.dim)
            }
            .font(.system(size: 13))

            TextEditor(text: $ui.note)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)  // drop the default white box
                .scrollIndicators(.never)          // and the scroll bar knob
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
                .frame(height: 58)
                .overlay(alignment: .topLeading) {
                    if ui.note.isEmpty {
                        Text("What got done? What's left?")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hairline, lineWidth: 1))
                .accessibilityLabel("Note, optional")
        }
        .padding(.top, 18)
    }

    // MARK: Buttons

    private var actions: some View {
        HStack(spacing: 8) {
            if run.hitGoal {
                Button("5-min break") { ui.reviewThenBreak() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Save this review and start a five-minute break")
            }
            Spacer()
            Button("Skip") { ui.skipReview() }
                .buttonStyle(GhostButtonStyle())
            Button(action: ui.submitReview) {
                LabelWithKey(title: primaryTitle, key: "⌘↵", onPrimary: true)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var primaryTitle: String {
        switch ui.reviewChoice {
        case .done: "Mark done"
        case .more: "Continue +\(ui.reviewExtraMinutes) min"
        case .later: "Save for later"
        }
    }
}

/// One radio row: ring, title + subtitle, key hint.
private struct OutcomeRow: View {
    let title: String
    let subtitle: String
    let key: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(isSelected ? Palette.paper : Palette.outline, lineWidth: isSelected ? 4 : 1.5)
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.mute)
                }
                Spacer()
                Keycap(label: key)
            }
            .foregroundStyle(isSelected ? Palette.paper : Palette.secondary)
            .padding(.horizontal, 4)
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
