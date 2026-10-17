import AppKit

/// The Settings menu: launch at login, desktop shortcuts, Mission Control names, setup links, quit.
final class SettingsMenu: NSObject {
    private let onOpenSettingsURL: (URL) -> Void

    private init(onOpenSettingsURL: @escaping (URL) -> Void) {
        self.onOpenSettingsURL = onOpenSettingsURL
    }

    /// Pops up at the mouse. `popUp` blocks while the menu is open, which keeps
    /// this target object alive for the item actions.
    static func show(onOpenSettingsURL: @escaping (URL) -> Void) {
        let controller = SettingsMenu(onOpenSettingsURL: onOpenSettingsURL)
        controller.makeMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let login = item(LoginItem.needsApproval ? "Launch at Login (needs approval)" : "Launch at Login",
                         #selector(toggleLaunchAtLogin))
        login.state = LoginItem.isEnabled || LoginItem.needsApproval ? .on : .off
        menu.addItem(login)

        let shortcuts = item("Desktop Shortcuts (⌃⌥1–9)", #selector(toggleDesktopShortcuts))
        shortcuts.state = DesktopHotkeys.isEnabled ? .on : .off
        menu.addItem(shortcuts)

        let overlay = item("Show Names in Mission Control", #selector(toggleMissionControlNames))
        overlay.state = MissionControlOverlay.isEnabled ? .on : .off
        menu.addItem(overlay)

        menu.addItem(.separator())
        menu.addItem(item("Mission Control Shortcuts…", #selector(openKeyboardSettings)))
        menu.addItem(item("Accessibility Permission…", #selector(openAccessibilitySettings)))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SpaceName", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.setEnabled(!(LoginItem.isEnabled || LoginItem.needsApproval))
    }

    @objc private func toggleDesktopShortcuts() {
        DesktopHotkeys.isEnabled.toggle()
    }

    @objc private func toggleMissionControlNames() {
        MissionControlOverlay.isEnabled.toggle()
    }

    @objc private func openKeyboardSettings() {
        onOpenSettingsURL(SpaceSwitcher.keyboardSettingsURL)
    }

    @objc private func openAccessibilitySettings() {
        onOpenSettingsURL(SpaceSwitcher.accessibilitySettingsURL)
    }
}
