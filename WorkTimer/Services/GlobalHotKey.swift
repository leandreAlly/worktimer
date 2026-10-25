//
//  GlobalHotKey.swift
//  WorkTimer
//

import Carbon.HIToolbox

/// ⌃⌥Space from any app: Settings › "Show or hide WorkTimer from anywhere".
///
/// macOS has no SwiftUI API for system-wide shortcuts. The Carbon
/// `RegisterEventHotKey` call is old but still the supported way: it works in
/// the App Sandbox and, unlike watching every key press, needs no
/// Accessibility permission, because macOS only tells us about this one
/// combination.
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Registers ⌃⌥Space. Returns nil if another app already owns it.
    init?(action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Carbon calls a C function, which can't capture Swift values, so
        // `self` is passed through as an untyped pointer and recovered inside.
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, selfPointer, &handler)
        guard installed == noErr else { return nil }

        // "WTmr" packed into four bytes: an id so the event is recognisably ours.
        let id = EventHotKeyID(signature: 0x5754_6D72, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
