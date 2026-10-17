import AppKit

// MARK: - Private CoreGraphics / SkyLight API
//
// macOS has no public Spaces API. Everything private lives in this file so a
// future macOS change only needs fixing here. These symbols are exported by
// SkyLight and re-exported through CoreGraphics, so no extra linking is needed.

private typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
private func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> Unmanaged<CFString>?

// MARK: - Provider

/// Reads the current Space layout from the window server.
enum SpaceProvider {
    /// CGS space types seen in `CGSCopyManagedDisplaySpaces`.
    private enum SpaceType: Int {
        case user = 0
        case fullscreen = 4
    }

    /// Spaces on the display that currently owns the menu bar, plus the active one.
    static func snapshot() -> SpaceSnapshot {
        let cid = CGSMainConnectionID()
        let activeID = CGSGetActiveSpace(cid)
        let menuBarDisplay = CGSCopyActiveMenuBarDisplayIdentifier(cid)?.takeRetainedValue() as String?
        let displays = allDisplays()

        // With "Displays have separate Spaces" off there is one entry ("Main").
        // Otherwise pick the menu-bar display, falling back to the one holding the active Space.
        let display = displays.first { $0.identifier == menuBarDisplay }
            ?? displays.first { $0.spaces.contains { $0.id == activeID } }
            ?? displays.first

        guard let display else { return SpaceSnapshot(spaces: [], currentID: activeID) }
        return SpaceSnapshot(spaces: display.spaces, currentID: display.currentID ?? activeID)
    }

    /// Every display's Spaces, in window-server order.
    static func allDisplays() -> [DisplaySpaces] {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }

        // "Switch to Desktop N" shortcuts number desktops across all displays in
        // this order, so carry the count of regular desktops on earlier displays.
        var shortcutOffset = 0
        return displays.map { display in
            let identifier = display["Display Identifier"] as? String ?? "Main"
            let rawSpaces = display["Spaces"] as? [[String: Any]] ?? []

            var desktopNumber = 0
            let spaces: [Space] = rawSpaces.compactMap { raw in
                guard let id = spaceID(raw) else { return nil }
                let isFullscreen = SpaceType(rawValue: raw["type"] as? Int ?? 0) == .fullscreen
                if !isFullscreen { desktopNumber += 1 }
                let uuid = (raw["uuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return Space(
                    id: id,
                    uuid: uuid,
                    displayID: identifier,
                    desktopNumber: isFullscreen ? nil : desktopNumber,
                    shortcutNumber: isFullscreen ? nil : shortcutOffset + desktopNumber,
                    isFullscreen: isFullscreen,
                    appName: isFullscreen ? fullscreenAppName(raw) : nil
                )
            }
            shortcutOffset += desktopNumber

            return DisplaySpaces(identifier: identifier,
                                 currentID: (display["Current Space"] as? [String: Any]).flatMap(spaceID),
                                 spaces: spaces)
        }
    }

    /// The window server identifies displays by UUID string; AppKit and the Dock use
    /// CGDirectDisplayID. Returns nil for the shared "Main" entry.
    static func identifier(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    private static func spaceID(_ raw: [String: Any]) -> UInt64? {
        if let id = raw["id64"] as? UInt64 { return id }
        if let id = raw["id64"] as? Int { return UInt64(id) }
        if let id = raw["ManagedSpaceID"] as? Int { return UInt64(id) }
        return nil
    }

    /// Full-screen Spaces carry the owning app's pid in "pid" (older) or in the
    /// tile layout manager's tile list (newer). Best effort.
    private static func fullscreenAppName(_ raw: [String: Any]) -> String? {
        var pid = raw["pid"] as? Int32 ?? (raw["pid"] as? Int).map(Int32.init)
        if pid == nil,
           let tiles = (raw["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] {
            pid = tiles.lazy.compactMap { ($0["pid"] as? Int).map(Int32.init) }.first
        }
        guard let pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
