//
//  SystemEffects.swift
//  WorkTimer
//

import AppKit
import UserNotifications

/// The real `TimerEffects`: macOS notifications and the end chime.
///
/// How the sound is shared between the two, so it plays exactly once:
/// - The notification is handed to macOS ahead of time, carrying the bell.
///   If WorkTimer is in the background (or not running at all), macOS shows
///   the banner and plays the bell.
/// - If WorkTimer is the frontmost app, macOS asks our delegate instead
///   (`willPresent`); we show the banner silently and the engine's
///   `playChime` plays the bell itself.
/// - With notifications turned off (in Settings or by macOS), `playChime`
///   plays the bell whatever the app's state.
final class SystemEffects: NSObject, TimerEffects {
    static let soundName = "SoftBell.wav"
    private static let alertID = "worktimer.alert"

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private lazy var bell = NSSound(named: NSSound.Name("SoftBell"))
    /// Last known permission. Updated whenever we schedule, so it's never
    /// more than one session stale.
    private var authorized = false
    /// Called when the user clicks a notification.
    var onOpen: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        // The delegate must be set before launch finishes, so a click on a
        // notification that relaunched the app still reaches us.
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    private var notificationsEnabled: Bool { defaults.bool(forKey: AppSettings.notifyWhenDone) }
    private var chimeEnabled: Bool { defaults.string(forKey: AppSettings.endChime) != EndChime.none.rawValue }

    // MARK: TimerEffects

    func scheduleAlert(_ alert: TimerAlert, in seconds: TimeInterval) {
        cancelAlert()
        guard notificationsEnabled, seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        switch alert {
        case .workTimeUp(let task):
            content.title = "Time's up"
            content.body = task
        case .breakOver:
            content.title = "Break's over"
            content.body = "Ready for the next session?"
        }
        content.sound = chimeEnabled ? UNNotificationSound(named: UNNotificationSoundName(Self.soundName)) : nil
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: Self.alertID, content: content, trigger: trigger)
        // `Task { }` runs async work from this synchronous method. The first
        // time, macOS shows its "Allow notifications?" prompt here, when the
        // user has just started a timer and the question makes sense.
        Task {
            guard await requestAuthorizationIfNeeded() else { return }
            try? await center.add(request)
        }
    }

    func cancelAlert() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.alertID])
    }

    func playChime(for alert: TimerAlert) {
        guard chimeEnabled else { return }
        // In the background macOS plays the notification's bell; don't double it.
        let notificationRings = notificationsEnabled && authorized && !NSApp.isActive
        guard !notificationRings else { return }
        bell?.stop()
        bell?.play()
    }

    // MARK: Permission

    private func refreshAuthorization() async {
        let status = await center.notificationSettings().authorizationStatus
        authorized = status == .authorized || status == .provisional
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        } else {
            authorized = status == .authorized || status == .provisional
        }
        return authorized
    }
}

// MARK: - UNUserNotificationCenterDelegate

// `nonisolated`: macOS calls these on a background queue, outside the main
// actor that the rest of the app runs on.
extension SystemEffects: UNUserNotificationCenterDelegate {
    /// WorkTimer is frontmost: show the banner but stay quiet, because
    /// `playChime` is already ringing the bell.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// The user clicked the banner: bring the timer forward.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen?() }
    }
}
