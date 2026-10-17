import Foundation
import ServiceManagement

/// Launch at login via SMAppService (macOS 13+). Registers the app bundle itself.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// The user turned it on, but macOS wants approval in Login Items settings.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SpaceName: launch at login change failed: \(error)")
        }
        if needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
