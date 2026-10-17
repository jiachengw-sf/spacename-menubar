import AppKit
import Carbon.HIToolbox

/// Global shortcuts that jump to a desktop on the menu bar display, following
/// macOS's own "Switch to Desktop N" numbering (macOS allows up to 16):
///
///     Desktop 1–9    ⌥1 – ⌥9
///     Desktop 10     ⌥0
///     Desktop 11–16  ⌥⇧1 – ⌥⇧6
///
/// Only desktops that exist get a shortcut, so the rest still type their special
/// characters (™, •, …). Uses Carbon's RegisterEventHotKey, which needs no extra permission.
final class DesktopHotkeys {
    static let enabledKey = "desktopShortcutsEnabled"
    static let didChangeNotification = Notification.Name("SpaceName.desktopShortcutsChanged")

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    private struct Binding {
        let desktop: Int
        let keyCode: Int
        let modifiers: Int
        let label: String
    }

    private static let digitKeyCodes: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                               kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    private static let bindings: [Binding] =
        (1...9).map { Binding(desktop: $0, keyCode: digitKeyCodes[$0 - 1], modifiers: optionKey, label: "⌥\($0)") }
        + [Binding(desktop: 10, keyCode: kVK_ANSI_0, modifiers: optionKey, label: "⌥0")]
        + (1...6).map { Binding(desktop: 10 + $0, keyCode: digitKeyCodes[$0 - 1],
                                modifiers: optionKey | shiftKey, label: "⌥⇧\($0)") }

    /// How many desktops currently have a registered shortcut.
    private static var registeredCount = 0

    /// Menu-style label, e.g. "⌥3" or "⌥⇧2"; nil if that desktop has no shortcut.
    static func label(forDesktop number: Int?) -> String? {
        guard isEnabled, let number, number <= registeredCount else { return nil }
        return bindings.first { $0.desktop == number }?.label
    }

    private static let signature: OSType = 0x53504E4D   // "SPNM"

    private let onPress: (Int) -> Void
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(onPress: @escaping (Int) -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<DesktopHotkeys>.fromOpaque(userData).takeUnretainedValue()
            me.onPress(Int(id.id))
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Registers shortcuts for desktops 1…`desktopCount` (or none if turned off).
    func update(desktopCount: Int) {
        let count = Self.isEnabled ? min(desktopCount, Self.bindings.count) : 0
        guard count != Self.registeredCount || hotKeys.count != count else { return }

        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        Self.registeredCount = count

        for binding in Self.bindings.prefix(count) {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(binding.desktop))
            let status = RegisterEventHotKey(UInt32(binding.keyCode), UInt32(binding.modifiers),
                                             id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys.append(ref)
            } else {
                NSLog("SpaceName: \(binding.label) is taken by another app (error \(status))")
            }
        }
    }

    /// Mission Control ignores shortcuts posted while the user still holds ⌥ or ⇧,
    /// so wait (up to a second) for the keys to be released.
    static func afterModifiersReleased(_ action: @escaping () -> Void) {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        func check(_ attempt: Int) {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(held).isEmpty || attempt >= 50 {
                action()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { check(attempt + 1) }
            }
        }
        check(0)
    }
}
