import AppKit
import Carbon.HIToolbox

/// Global shortcuts ⌃⌥1 … ⌃⌥9 that jump to desktop 1–9 on the menu bar display.
/// Uses Carbon's RegisterEventHotKey, which needs no extra permission.
final class DesktopHotkeys {
    static let enabledKey = "desktopShortcutsEnabled"
    static let didChangeNotification = Notification.Name("SpaceName.desktopShortcutsChanged")
    static let range = 1...9

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Menu-style label, e.g. "⌃⌥3"; nil if that desktop has no shortcut.
    static func label(forDesktop number: Int?) -> String? {
        guard isEnabled, let number, range.contains(number) else { return nil }
        return "⌃⌥\(number)"
    }

    private static let signature: OSType = 0x53504E4D   // "SPNM"
    private static let digitKeyCodes: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                               kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

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

    /// Registers or unregisters to match the user's setting.
    func update() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        guard Self.isEnabled else { return }

        for number in Self.range {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(number))
            let status = RegisterEventHotKey(UInt32(Self.digitKeyCodes[number - 1]), UInt32(controlKey | optionKey),
                                             id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys.append(ref)
            } else {
                NSLog("SpaceName: ⌃⌥\(number) is taken by another app (error \(status))")
            }
        }
    }

    /// Mission Control ignores shortcuts posted while the user still holds ⌃⌥,
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
