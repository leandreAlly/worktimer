//
//  UIModel.swift
//  WorkTimer
//

import Foundation
import Observation
import SwiftUI

/// What the user is composing on screen but hasn't committed yet: the task
/// text, the duration choice, the review outcome and note.
///
/// It lives outside the views so the keyboard shortcuts, the main window and
/// (in Phase 4) the menu bar popover all act on the same draft.
@Observable
final class UIModel {
    enum DurationChoice: Equatable {
        case preset(Int)
        case custom
        case noLimit
    }

    enum ReviewChoice: CaseIterable {
        case done, more, later
    }

    static let presets = [25, 50, 90]
    static let reviewExtensions = [5, 15, 25]

    var task: String {
        didSet { defaults.set(task, forKey: AppSettings.lastTask) }
    }
    var duration: DurationChoice {
        didSet { defaults.set(Self.encode(duration), forKey: AppSettings.lastDuration) }
    }
    var customMinutes: Int {
        didSet { defaults.set(customMinutes, forKey: AppSettings.customMinutes) }
    }

    var reviewChoice: ReviewChoice = .done
    var reviewExtraMinutes = 15
    var note = ""

    /// Bumped to ask the Ready screen to focus the custom-minutes field
    /// (the C shortcut). A counter, so asking twice in a row still registers.
    var customFieldFocusRequest = 0

    /// 0...1 while "Hold to reset" is held, by mouse or the R key.
    private(set) var holdProgress: Double = 0

    @ObservationIgnored let engine: TimerEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var preparedReviewID: UUID?

    init(engine: TimerEngine, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        task = defaults.string(forKey: AppSettings.lastTask) ?? ""
        duration = Self.decode(defaults.string(forKey: AppSettings.lastDuration)) ?? .preset(25)
        let storedCustom = defaults.integer(forKey: AppSettings.customMinutes)
        customMinutes = TimerEngine.allowedMinutes.contains(storedCustom) ? storedCustom : 30
    }

    // MARK: Ready

    /// Minutes for the chosen duration; `0` = no limit.
    var selectedMinutes: Int {
        switch duration {
        case .preset(let minutes): minutes
        case .custom: customMinutes
        case .noLimit: 0
        }
    }

    var canCommit: Bool { !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func commit() {
        engine.start(task: task, minutes: selectedMinutes)
    }

    func choosePreset(at index: Int) {
        guard Self.presets.indices.contains(index) else { return }
        duration = .preset(Self.presets[index])
    }

    func chooseCustom() {
        duration = .custom
        customFieldFocusRequest += 1
    }

    // MARK: The ⌘↵ action

    /// ⌘↵ always means "move forward": Commit on Ready, Finish & Log while
    /// working, open Review at time's up, confirm on Review.
    func primaryAction() {
        switch engine.state.phase {
        case .ready: commit()
        case .running, .paused, .timeUp: engine.finish()
        case .review: submitReview()
        case .onBreak: break
        }
    }

    // MARK: Review

    /// Reset the review form once per session that reaches Review.
    func prepareReview(for run: WorkRun) {
        guard preparedReviewID != run.id else { return }
        preparedReviewID = run.id
        reviewChoice = run.hitGoal ? .done : .later
        reviewExtraMinutes = 15
        note = ""
    }

    func submitReview() {
        switch reviewChoice {
        case .done: engine.completeReview(outcome: .done, note: note)
        case .later: engine.completeReview(outcome: .continueLater, note: note)
        case .more: engine.continueSession(minutes: reviewExtraMinutes)
        }
    }

    func skipReview() {
        engine.completeReview(outcome: nil, note: note)
    }

    /// Save the review as chosen, then start a 5-minute break.
    func reviewThenBreak() {
        let outcome: SessionOutcome? = switch reviewChoice {
        case .done: .done
        case .later: .continueLater
        case .more: nil
        }
        engine.completeReview(outcome: outcome, note: note)
        engine.startBreak()
    }

    // MARK: Hold to reset

    func setHolding(_ holding: Bool) {
        holding ? beginHold() : endHold()
    }

    private func beginHold() {
        guard holdTask == nil, engine.state.phase == .paused else { return }
        withAnimation(.linear(duration: 1)) { holdProgress = 1 }
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.engine.discard()
            self.holdTask = nil
            self.holdProgress = 0
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.15)) { holdProgress = 0 }
    }

    // MARK: Persistence of the duration choice

    private static func encode(_ choice: DurationChoice) -> String {
        switch choice {
        case .preset(let minutes): "preset:\(minutes)"
        case .custom: "custom"
        case .noLimit: "none"
        }
    }

    private static func decode(_ string: String?) -> DurationChoice? {
        switch string {
        case "custom": return .custom
        case "none": return .noLimit
        case let value? where value.hasPrefix("preset:"):
            guard let minutes = Int(value.dropFirst("preset:".count)), presets.contains(minutes) else { return nil }
            return .preset(minutes)
        default: return nil
        }
    }
}
