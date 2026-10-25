//
//  SettingsView.swift
//  WorkTimer
//

import AppKit
import SwiftUI
import UserNotifications

enum SettingsWindow {
    static let id = "settings"
    static let size = CGSize(width: 680, height: 780)
}

/// Artboard "Preferences". Every row is stored with `@AppStorage`, which reads
/// and writes UserDefaults and redraws when the value changes, so the rest of
/// the app picks a change up immediately.
///
/// Left out on purpose: "Ticking sound" (agreed to drop).
struct SettingsView: View {
    /// False when another app already owns ⌃⌥Space.
    let hotKeyAvailable: Bool

    @Environment(UIModel.self) private var ui
    @AppStorage(AppSettings.theme) private var theme = ThemeChoice.dark
    @AppStorage(AppSettings.numeralStyle) private var numerals = NumeralStyle.flap
    @AppStorage(AppSettings.animateDigits) private var animateDigits = true
    @AppStorage(AppSettings.startDuration) private var startDuration = "last"
    @AppStorage(AppSettings.showOvertime) private var showOvertime = true
    @AppStorage(AppSettings.holdToReset) private var holdToReset = true
    @AppStorage(AppSettings.askForReview) private var askForReview = true
    @AppStorage(AppSettings.endChime) private var endChime = EndChime.softBell
    @AppStorage(AppSettings.notifyWhenDone) private var notify = true
    @AppStorage(AppSettings.floatOnTop) private var floatOnTop = true
    @AppStorage(AppSettings.showMenuBarTime) private var menuBarTime = true

    /// macOS's own notification switch for WorkTimer, checked on appear.
    @State private var notificationsBlocked = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: MainWindow.headerHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.settingsHeaderRule).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appearance
                    timeCommitment
                    session
                    sound
                    windowAndShortcuts
                    Text("Everything stays on this Mac. No account, no sync.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.mute)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .frame(width: SettingsWindow.size.width)
        .frame(maxHeight: .infinity)
        .foregroundStyle(Palette.paper)
        .background(Palette.settingsGround)
        .ignoresSafeArea()
        .background(WindowConfigurator(floatOnTop: false, size: SettingsWindow.size))
        .preferredColorScheme(theme.colorScheme)
        .task { await checkNotificationPermission() }
        // Coming back from System Settings: check again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkNotificationPermission() }
        }
    }

    // MARK: Sections

    private var appearance: some View {
        SettingsSection("Appearance") {
            SettingsRow("Theme") {
                SegmentedChoice(selection: $theme, options: [(.system, "System"), (.dark, "Dark"), (.light, "Light")])
            }
            SettingsRow("Numerals") {
                SegmentedChoice(selection: $numerals, options: [(.flap, "Flap"), (.flat, "Flat")])
            }
            SettingsRow("Animate digit changes", hint: "Respects Reduce Motion") {
                SettingsSwitch(label: "Animate digit changes", isOn: $animateDigits)
            }
        }
    }

    private var timeCommitment: some View {
        SettingsSection("Time commitment") {
            SettingsRow("Presets", hint: "1 to 600 minutes; keys 1, 2 and 3 on the Ready screen") {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        PresetField(index: index)
                    }
                    Text("min").font(.system(size: 12)).foregroundStyle(Palette.mute).padding(.leading, 2)
                }
            }
            SettingsRow("Selected when the app opens") {
                ValueMenu(title: startDurationTitle) {
                    Button("Last used") { startDuration = "last" }
                    Divider()
                    ForEach(ui.presets, id: \.self) { minutes in
                        Button("\(minutes) min") { startDuration = UIModel.encode(.preset(minutes)) }
                    }
                    Button("No limit") { startDuration = UIModel.encode(.noLimit) }
                }
            }
        }
    }

    private var session: some View {
        SettingsSection("Session") {
            SettingsRow("Show overtime after time is up",
                        hint: showOvertime ? nil : "At zero the session ends at its commitment") {
                SettingsSwitch(label: "Show overtime after time is up", isOn: $showOvertime)
            }
            SettingsRow("Reset needs a 1-second hold", hint: "Prevents accidental resets") {
                SettingsSwitch(label: "Reset needs a 1-second hold", isOn: $holdToReset)
            }
            SettingsRow("Ask for a review when a session ends",
                        hint: askForReview ? nil : "Sessions are saved without an outcome") {
                SettingsSwitch(label: "Ask for a review when a session ends", isOn: $askForReview)
            }
        }
    }

    private var sound: some View {
        SettingsSection("Sound & notifications") {
            SettingsRow("End chime") {
                ValueMenu(title: endChime == .softBell ? "Soft bell" : "None") {
                    Button("Soft bell") {
                        endChime = .softBell
                        NSSound(named: NSSound.Name("SoftBell"))?.play()  // let them hear it
                    }
                    Button("None") { endChime = .none }
                }
            }
            SettingsRow("Notify when time is up",
                        hint: notificationsBlocked ? "Turned off for WorkTimer in System Settings" : "Uses macOS notifications") {
                HStack(spacing: 10) {
                    if notificationsBlocked && notify {
                        Button("Open System Settings") { openNotificationSettings() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.signal)
                    }
                    SettingsSwitch(label: "Notify when time is up", isOn: $notify)
                }
            }
        }
    }

    private var windowAndShortcuts: some View {
        SettingsSection("Window & shortcuts") {
            SettingsRow("Float above other windows", hint: "The main window and the compact timer") {
                SettingsSwitch(label: "Float above other windows", isOn: $floatOnTop)
            }
            SettingsRow("Show remaining time in the menu bar") {
                SettingsSwitch(label: "Show remaining time in the menu bar", isOn: $menuBarTime)
            }
            SettingsRow("Show or hide WorkTimer from anywhere",
                        hint: hotKeyAvailable ? nil : "Another app is using this shortcut") {
                ShortcutLabel(text: "⌃⌥ Space").opacity(hotKeyAvailable ? 1 : 0.5)
            }
            SettingsRow("Start · Pause · Resume") {
                ShortcutLabel(text: "⌘↵ · Space")
            }
        }
    }

    // MARK: Helpers

    private var startDurationTitle: String {
        switch startDuration {
        case "last": return "Last used"
        default:
            switch UIModel.decode(startDuration, presets: ui.presets) {
            case .preset(let minutes): return "\(minutes) min"
            case .noLimit: return "No limit"
            default: return "Last used"  // a preset that was since changed
            }
        }
    }

    private func checkNotificationPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsBlocked = status == .denied
    }

    private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Building blocks

/// A titled card of rows separated by hairlines.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            // `Group(subviews:)` would need macOS 15, so rows draw their own
            // top rule and the card clips the first one away.
            VStack(spacing: 0) { content }
                .padding(.top, -1)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(Palette.settingsCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        }
    }
}

/// Label (and optional hint) on the left, the control on the right.
private struct SettingsRow<Control: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder let control: Control

    init(_ label: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(Palette.mute)
                }
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// The artboard's 38 × 22 switch: Paper track when on, gray when off.
private struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Palette.paper : Palette.switchOffTrack)
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Palette.ground : Palette.mute)
                        .frame(width: 18, height: 18)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// System / Dark / Light style segmented control.
private struct SegmentedChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? Palette.paper : Palette.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(selected ? Palette.segmentSelected : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.control, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// A small bordered button that opens a menu: "Soft bell ⌄".
private struct ValueMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 12))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.mute)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Palette.control, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// One preset's minutes. Out-of-range input snaps back into 1–600.
private struct PresetField: View {
    let index: Int
    @Environment(UIModel.self) private var ui

    var body: some View {
        let binding = Binding<Int>(
            get: { ui.presets[index] },
            set: { newValue in
                let clamped = min(max(newValue, TimerEngine.allowedMinutes.lowerBound), TimerEngine.allowedMinutes.upperBound)
                ui.presets[index] = clamped
            }
        )
        // `format: .number` parses the text into an Int when editing ends
        // (Return, Tab, or clicking elsewhere).
        TextField("", value: binding, format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.numerals(13, weight: 600))
            .frame(width: 44, height: 26)
            .background(Palette.control, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.hairline, lineWidth: 1))
            .accessibilityLabel("Preset \(index + 1), minutes")
    }
}

private struct ShortcutLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mono(12))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Palette.control, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.hairline, lineWidth: 1))
    }
}
