import Foundation

/// One Mission Control Space on a display.
struct Space: Identifiable, Equatable {
    /// Window-server space id (stable for the session, not across reboots).
    let id: UInt64
    /// Persistent identifier; nil for full-screen app Spaces.
    let uuid: String?
    let displayID: String
    /// 1-based "Desktop N" number counting only regular desktops; nil for full-screen.
    let desktopNumber: Int?
    /// N in the "Switch to Desktop N" shortcut (numbered across all displays); nil for full-screen.
    let shortcutNumber: Int?
    let isFullscreen: Bool
    let appName: String?

    /// Name shown when the user hasn't set one.
    var defaultName: String {
        if isFullscreen { return appName ?? "Full Screen" }
        return "Desktop \(desktopNumber ?? 0)"
    }
}

struct SpaceSnapshot: Equatable {
    let spaces: [Space]
    let currentID: UInt64

    var current: Space? { spaces.first { $0.id == currentID } }
}

/// One display's Spaces as reported by the window server.
struct DisplaySpaces: Equatable {
    /// Display UUID string, or "Main" when displays share Spaces.
    let identifier: String
    let currentID: UInt64?
    let spaces: [Space]
}
