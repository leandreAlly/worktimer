//
//  KeyboardController.swift
//  WorkTimer
//

import AppKit

/// The app's keyboard shortcuts, handled in one place.
///
/// An `NSEvent` local monitor sees every key press in the app before any view
/// does. That makes two rules easy to guarantee:
/// - while a text field or the note box is being edited, plain keys (Space,
///   letters, digits) are left alone so typing works normally;
/// - ⌘↵ works everywhere in the main window, including from the task field.
///
/// | Key        | Ready         | Running / Paused   | Time's up | Review        |
/// |------------|---------------|--------------------|-----------|---------------|
/// | ⌘↵         | Commit        | Finish & log       | Review    | Confirm       |
/// | Space      | Commit        | Pause / Resume     |           |               |
/// | ↵          |               |                    | Review    |               |
/// | Hold R     |               | Reset (paused)     |           |               |
/// | 1 2 3 · 4  | Presets · ∞   |                    |           |               |
/// | C          | Custom        |                    |           |               |
/// | D M L      |               |                    |           | Choose outcome|
final class KeyboardController {
    private let ui: UIModel
    private var monitor: Any?

    init(ui: UIModel) {
        self.ui = ui
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // Local monitors always run on the main thread. `assumeIsolated`
            // tells the compiler so, which lets us touch main-actor state.
            // `NSEvent` isn't marked Sendable, but it never leaves the main
            // thread here, so passing it in is safe.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isMainWindow(event.window) else { return false }
                return self.handle(event)
            }
            return consumed ? nil : event  // returning nil swallows the key
        }
    }

    private var engine: TimerEngine { ui.engine }

    private func isMainWindow(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue.hasPrefix(MainWindow.id) ?? false
    }

    /// Translate the AppKit event into a plain `KeyPress` and act on it.
    private func handle(_ event: NSEvent) -> Bool {
        let press = KeyPress(
            key: event.charactersIgnoringModifiers?.lowercased() ?? "",
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection([.command, .option, .control, .shift]),
            isKeyUp: event.type == .keyUp,
            isRepeat: event.type == .keyDown && event.isARepeat,
            isEditingText: event.window?.firstResponder is NSTextView
        )
        if press.isEditingText && press.keyCode == KeyPress.escape && press.modifiers.isEmpty {
            // Esc leaves the field so Space and the letter keys work again.
            event.window?.makeFirstResponder(nil)
            return true
        }
        return perform(press)
    }

    /// The shortcut rules, kept free of AppKit events so tests can call it.
    /// Returns true if the key was used.
    func perform(_ press: KeyPress) -> Bool {
        if press.isKeyUp {
            if press.key == "r" { ui.setHolding(false) }
            return false
        }

        if press.isReturn && press.modifiers == .command {
            ui.primaryAction()
            return true
        }
        // Plain keys only from here on; and never while typing in a field.
        guard press.modifiers.isEmpty, !press.isEditingText else { return false }

        switch (engine.state.phase, press.key) {
        case (.ready, " "):
            ui.commit()
        case (.running, " "), (.paused, " "):
            engine.togglePause()
        case (.timeUp, _) where press.isReturn:
            engine.finish()
        case (.paused, "r"):
            if !press.isRepeat { ui.setHolding(true) }
        case (.ready, "1"), (.ready, "2"), (.ready, "3"):
            ui.choosePreset(at: Int(press.key)! - 1)
        case (.ready, "4"):
            ui.duration = .noLimit
        case (.ready, "c"):
            ui.chooseCustom()
        case (.review, "d"):
            ui.reviewChoice = .done
        case (.review, "m"):
            ui.reviewChoice = .more
        case (.review, "l"):
            ui.reviewChoice = .later
        default:
            return false
        }
        return true
    }
}

/// One key press, reduced to what the shortcut rules need.
struct KeyPress {
    static let escape: UInt16 = 53

    var key: String
    var keyCode: UInt16 = 0
    var modifiers: NSEvent.ModifierFlags = []
    var isKeyUp = false
    var isRepeat = false
    var isEditingText = false

    /// Return or the keypad's Enter.
    var isReturn: Bool { keyCode == 36 || keyCode == 76 }
}
