import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "com.jiacheng.SpaceName", category: "switch")

/// Switches Spaces by posting the user's Mission Control keyboard shortcuts.
/// There is no public API for this; see README for why CGS switching isn't used.
final class SpaceSwitcher: ObservableObject {
    enum Problem: Equatable {
        /// The app isn't allowed to post keyboard events.
        case needsPermission
        /// Neither "Switch to Desktop N" nor "Move left/right a space" is turned on.
        case noShortcut(spaceName: String)
    }

    /// Shown as a banner in the panel; set when a switch couldn't happen.
    @Published var problem: Problem?

    private struct Hotkey {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
        /// The key's character as stored by System Settings (e.g. "1"), if any.
        var character: String? = nil

        /// Menu-style label in Apple's modifier order, e.g. "⌃1" or "⌃⌥3".
        var label: String? {
            let modifiers: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"),
                                                       (.maskShift, "⇧"), (.maskCommand, "⌘")]
            let prefix = modifiers.filter { flags.contains($0.0) }.map(\.1).joined()
            // System Settings usually stores no character for these, only the key code.
            let named: [CGKeyCode: String] = [123: "←", 124: "→", 125: "↓", 126: "↑",
                                              18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
                                              22: "6", 26: "7", 28: "8", 25: "9", 29: "0"]
            guard let key = named[keyCode] ?? character?.uppercased() else { return nil }
            return prefix + key
        }
    }

    // Symbolic hotkey ids in com.apple.symbolichotkeys.
    private static let moveLeftID = 79
    private static let moveRightID = 81
    private static let desktopBaseID = 117   // Desktop N is 117 + N (N = 1...16)

    /// Default key codes for Control-1 ... Control-0 when a shortcut is enabled
    /// without stored parameters.
    private static let digitKeyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    private static let controlFlag: UInt64 = 0x40000
    private static let arrowFlags: UInt64 = 0x840000   // Control + function-key bit
    private static let stepDelay: TimeInterval = 0.12

    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    // MARK: Public

    /// Posting shortcuts needs post-event access; the Mission Control names need
    /// Accessibility. Granting Accessibility normally covers both.
    var hasPermission: Bool { CGPreflightPostEventAccess() && AXIsProcessTrusted() }

    func requestPermission() {
        // Shows the system prompt the first time; afterwards it's a no-op, so also open Settings.
        if !CGRequestPostEventAccess() {
            NSWorkspace.shared.open(Self.accessibilitySettingsURL)
        }
    }

    func openKeyboardShortcutSettings() {
        NSWorkspace.shared.open(Self.keyboardSettingsURL)
    }

    /// True when `space` can't be reached with a single "Switch to Desktop N" shortcut.
    /// The macOS "Switch to Desktop N" shortcut for `space` as the user set it up
    /// (e.g. "⌃1"), or nil if it's off. Shown next to each row in the panel.
    func shortcutLabel(for space: Space) -> String? {
        guard let number = space.shortcutNumber, number <= 16 else { return nil }
        return hotkey(id: Self.desktopBaseID + number)?.label
    }

    func lacksDirectShortcut(_ space: Space) -> Bool {
        guard let number = space.shortcutNumber, number <= 16 else { return true }
        return hotkey(id: Self.desktopBaseID + number) == nil
    }

    /// Returns true if a switch was started. On failure sets `problem`.
    @discardableResult
    func switchTo(_ target: Space, in snapshot: SpaceSnapshot, displayName: String) -> Bool {
        problem = nil
        guard target.id != snapshot.currentID else { return true }
        guard hasPermission else {
            log.error("No post-event permission (AX trusted: \(AXIsProcessTrusted(), privacy: .public))")
            problem = .needsPermission
            return false
        }

        // 1. Direct "Switch to Desktop N".
        if let number = target.shortcutNumber, number <= 16,
           let hotkey = hotkey(id: Self.desktopBaseID + number) {
            log.info("Direct switch to desktop \(number, privacy: .public)")
            post(hotkey)
            return true
        }

        // 2. Step with "Move left/right a space" (also the only way to reach full-screen Spaces).
        if let from = snapshot.spaces.firstIndex(where: { $0.id == snapshot.currentID }),
           let to = snapshot.spaces.firstIndex(where: { $0.id == target.id }),
           let hotkey = hotkey(id: to > from ? Self.moveRightID : Self.moveLeftID) {
            log.info("Stepping \(to - from, privacy: .public) Space(s) from index \(from, privacy: .public)")
            for step in 0..<abs(to - from) {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * Self.stepDelay) {
                    self.post(hotkey)
                }
            }
            return true
        }

        log.error("No usable shortcut for \(displayName, privacy: .public)")
        problem = .noShortcut(spaceName: displayName)
        return false
    }

    #if DEBUG
    /// Debug builds only: presses the Mission Control shortcut (symbolic hotkey 32).
    func debugToggleMissionControl() {
        post(hotkey(id: 32) ?? Hotkey(keyCode: 126, flags: CGEventFlags(rawValue: Self.arrowFlags)))
    }
    #endif

    // MARK: Shortcut lookup

    /// Reads the user's configured shortcut, or nil if it's turned off.
    private func hotkey(id: Int) -> Hotkey? {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]

        guard let entry = all?[String(id)] as? [String: Any] else {
            // Missing entry: macOS default. Move left/right are on; Desktop N are off.
            return id == Self.moveLeftID || id == Self.moveRightID ? defaultHotkey(id: id) : nil
        }
        guard (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1) else { return nil }

        if let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3,
           params[1] != 0xFFFF {
            let character = (1...0x7E).contains(params[0]) ? String(UnicodeScalar(UInt8(params[0]))) : nil
            return Hotkey(keyCode: CGKeyCode(params[1]), flags: CGEventFlags(rawValue: UInt64(params[2])),
                          character: character)
        }
        return defaultHotkey(id: id)
    }

    private func defaultHotkey(id: Int) -> Hotkey? {
        switch id {
        case Self.moveLeftID:
            return Hotkey(keyCode: 123, flags: CGEventFlags(rawValue: Self.arrowFlags))
        case Self.moveRightID:
            return Hotkey(keyCode: 124, flags: CGEventFlags(rawValue: Self.arrowFlags))
        case (Self.desktopBaseID + 1)...(Self.desktopBaseID + 10):
            let index = id - Self.desktopBaseID - 1
            return Hotkey(keyCode: Self.digitKeyCodes[index],
                          flags: CGEventFlags(rawValue: Self.controlFlag),
                          character: String(Array("1234567890")[index]))
        default:
            return nil
        }
    }

    // MARK: Posting

    /// Modifier keys in press order, with their key codes.
    private static let modifierKeys: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55),
    ]

    /// Posts the shortcut like a real keystroke: modifiers down, key down/up, modifiers up.
    /// Mission Control ignores a key event that only carries modifier flags.
    private func post(_ hotkey: Hotkey) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers = Self.modifierKeys.filter { hotkey.flags.contains($0.flag) }

        func send(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }

        var held: CGEventFlags = []
        for modifier in modifiers {
            held.insert(modifier.flag)
            send(modifier.keyCode, down: true, flags: held)
        }
        send(hotkey.keyCode, down: true, flags: hotkey.flags)
        send(hotkey.keyCode, down: false, flags: hotkey.flags)
        for modifier in modifiers.reversed() {
            held.remove(modifier.flag)
            send(modifier.keyCode, down: false, flags: held)
        }
        log.info("Posted key \(hotkey.keyCode, privacy: .public) flags 0x\(String(hotkey.flags.rawValue, radix: 16), privacy: .public)")
    }
}
