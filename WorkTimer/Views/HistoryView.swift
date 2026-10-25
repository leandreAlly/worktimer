//
//  HistoryView.swift
//  WorkTimer
//

import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum HistoryWindow {
    static let id = "history"
    static let size = CGSize(width: 720, height: 680)
}

/// The History window: today's totals, the last seven days as bars, and every
/// saved session, newest first, with delete and CSV export.
///
/// The design canvas has no History artboard, so this uses the same parts as
/// the rest of the app: mono small-caps labels, Inter Tight numerals, hairline
/// rules, and amber kept for "not working" states only.
struct HistoryView: View {
    // `@Query` fetches from SwiftData and re-runs by itself whenever a session
    // is saved or deleted, so the window is always current.
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var sessions: [WorkSession]
    @Environment(\.modelContext) private var context
    @Environment(TimerEngine.self) private var engine
    @AppStorage(AppSettings.theme) private var theme = ThemeChoice.dark

    @State private var exporting = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exportError: String?
    /// The last deleted session, kept for a few seconds so it can be undone.
    @State private var undo: SessionRecord?
    @State private var undoTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: MainWindow.headerHeight)
            Rectangle().fill(Palette.rule).frame(height: 1)
            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TodaySection(today: HistoryStats.today(sessions))
                        WeekChart(days: HistoryStats.daily(sessions))
                            .padding(.top, 36)
                        SessionList(sessions: sessions, activeID: activeSessionID, onDelete: delete)
                            .padding(.top, 36)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.automatic)
            }
        }
        // Width fixed; height fills the window, which WindowConfigurator sizes
        // (the hidden title bar would otherwise add a strip at the bottom).
        .frame(width: HistoryWindow.size.width)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { undoBar }
        .foregroundStyle(Palette.paper)
        .background(Palette.ground)
        .ignoresSafeArea()
        .background(WindowConfigurator(floatOnTop: false, size: HistoryWindow.size))
        .preferredColorScheme(theme.colorScheme)
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText,
                      defaultFilename: CSVExport.suggestedFilename()) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("HISTORY")
                .monoLabel()
                .foregroundStyle(Palette.mute)
            HStack {
                Spacer()
                Button("Export CSV…") {
                    exportDocument = CSVDocument(text: CSVExport.csv(for: sessions))
                    exporting = true
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(sessions.isEmpty)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .help("Save every session as a CSV file (⇧⌘E)")
            }
            .padding(.trailing, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No sessions yet")
                .font(.system(size: 17, weight: .medium))
            Text("Finished sessions are saved here, on this Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.mute)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Delete and undo

    /// The session on screen in the main window (time's up or review) can't
    /// be deleted here: finishing its review would save it straight back.
    private var activeSessionID: UUID? {
        switch engine.state {
        case .timeUp(let run), .review(let run): run.id
        default: nil
        }
    }

    private func delete(_ session: WorkSession) {
        let record = session.record
        context.delete(session)
        try? context.save()
        showUndo(for: record)
    }

    private func showUndo(for record: SessionRecord) {
        withAnimation(.easeOut(duration: 0.15)) { undo = record }
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { undo = nil }
        }
    }

    @ViewBuilder private var undoBar: some View {
        if let record = undo {
            HStack(spacing: 14) {
                Text("Deleted “\(record.task)”")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Undo") {
                    // Saving the same record puts the row back, id and all.
                    SessionStore(context: context).save(record)
                    undoTask?.cancel()
                    withAnimation(.easeOut(duration: 0.15)) { undo = nil }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .keyboardShortcut("z", modifiers: .command)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Palette.flap, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .padding(.bottom, 20)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - Today

private struct TodaySection: View {
    let today: HistoryStats.Today

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TODAY").monoLabel().foregroundStyle(Palette.mute)
            HStack(spacing: 0) {
                Stat(value: Format.hoursMinutes(today.focusedSeconds), label: "FOCUSED")
                Stat(value: "\(today.sessions)", label: today.sessions == 1 ? "SESSION" : "SESSIONS")
                Stat(value: today.timed == 0 ? "—" : "\(today.hitGoal)/\(today.timed)", label: "HIT GOAL")
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.rule).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
        }
    }

    private struct Stat: View {
        let value: String
        let label: String
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(value).font(.numerals(40))
                Text(label).monoLabel(size: 10).foregroundStyle(Palette.mute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Last 7 days

private struct WeekChart: View {
    let days: [HistoryStats.DayTotal]
    /// The day under the pointer, for the hover readout.
    @State private var hovered: Date?

    private var total: Int { days.reduce(0) { $0 + $1.focusedSeconds } }
    private var activeDays: Int { days.filter { $0.focusedSeconds > 0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("LAST 7 DAYS").monoLabel().foregroundStyle(Palette.mute)
                Spacer()
                Text(summary).monoLabel(size: 10, tracking: 0.08).foregroundStyle(Palette.mute)
            }
            chart.frame(height: 170)
        }
    }

    private var summary: String {
        let average = activeDays == 0 ? 0 : total / activeDays
        return "\(Format.hoursMinutes(total)) TOTAL · \(Format.hoursMinutes(average)) PER ACTIVE DAY"
    }

    private var chart: some View {
        let today = days.last?.day
        let ticks = HistoryStats.chartTicks(forMaxMinutes: days.map(\.minutes).max() ?? 0)
        let top = ticks.last ?? 60

        return Chart(days) { day in
            BarMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Minutes", day.minutes),
                width: .ratio(0.5)
            )
            // Today is the bar to read; earlier days step back.
            .foregroundStyle(day.day == today || day.day == hovered ? Palette.paper : Palette.outline)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            .annotation(position: .top, spacing: 6) {
                if day.day == today || day.day == hovered, day.focusedSeconds > 0 {
                    Text(Format.hoursMinutes(day.focusedSeconds))
                        .font(.mono(10))
                        .foregroundStyle(Palette.paper)
                }
            }
            .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).day().month()))
            .accessibilityValue(Format.hoursMinutes(day.focusedSeconds))
        }
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date == today ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.mono(10))
                            .foregroundStyle(date == today ? Palette.paper : Palette.mute)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.rule)
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(Format.hoursMinutes(Int(minutes * 60)))
                            .font(.mono(10))
                            .foregroundStyle(Palette.dim)
                    }
                }
            }
        }
        // macOS 14: tracks the pointer over the plot and reports the date under it.
        .chartXSelection(value: $hovered)
        .onChange(of: hovered) {
            // Snap to the start of the day, so it matches a bar.
            if let hovered { self.hovered = Calendar.current.startOfDay(for: hovered) }
        }
    }
}

// MARK: - Sessions

private struct SessionList: View {
    let sessions: [WorkSession]
    let activeID: UUID?
    let onDelete: (WorkSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SESSIONS").monoLabel().foregroundStyle(Palette.mute)
            // `LazyVStack` builds rows only as they scroll into view, so a
            // long history stays quick.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(HistoryStats.groupedByDay(sessions), id: \.day) { group in
                    DayHeader(day: group.day, sessions: group.sessions)
                    ForEach(group.sessions) { session in
                        SessionRow(session: session, canDelete: session.id != activeID) {
                            onDelete(session)
                        }
                    }
                }
            }
        }
    }
}

private struct DayHeader: View {
    let day: Date
    let sessions: [WorkSession]

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.paper)
            Spacer()
            Text(Format.hoursMinutes(sessions.reduce(0) { $0 + $1.actualSeconds }))
        }
        .monoLabel(size: 10)
        .foregroundStyle(Palette.mute)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
    }
}

private struct SessionRow: View {
    let session: WorkSession
    let canDelete: Bool
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(Format.timeOfDay(session.startedAt))
                .font(.mono(11))
                .foregroundStyle(Palette.mute)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.task)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.mute)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            Text(Format.duration(session.actualSeconds))
                .font(.numerals(15, weight: 600))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.mute)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering && canDelete ? 1 : 0)
            .disabled(!canDelete)
            .accessibilityLabel("Delete session")
            .help("Delete this session")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Delete Session", role: .destructive, action: onDelete)
                .disabled(!canDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Delete") { if canDelete { onDelete() } }
    }

    /// "25 min · Hit goal · Done · Fixed the parser", skipping what's empty.
    private var detail: String {
        var parts = [session.isOpenEnded ? "No limit" : "\(session.plannedMinutes) min",
                     session.status.rawValue]
        if let outcome = session.outcome { parts.append(CSVExport.outcomeLabel(outcome)) }
        if !session.note.isEmpty { parts.append(session.note) }
        return parts.joined(separator: " · ")
    }
}
