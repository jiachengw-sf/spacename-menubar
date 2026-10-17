import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "com.jiacheng.SpaceName", category: "missioncontrol")

/// Reads Mission Control's Spaces bar from the Dock's accessibility tree.
///
/// Like SpaceProvider, this depends on undocumented internals (the Dock's AX
/// identifiers), so everything Dock-specific lives in this file. Known layout
/// while Mission Control is open:
///
///     Dock app
///       AXGroup id="mc"                    (only exists while Mission Control is open)
///         AXGroup id="mc.display"          (one per display, has AXDisplayID)
///           AXGroup id="mc.spaces"
///             AXList id="mc.spaces.list"
///               AXButton "Desktop 1" ...   (one per Space, in order)
///             AXButton id="mc.spaces.add"
enum DockMissionControl {
    struct SpaceButton: Equatable {
        /// Global screen coordinates with a top-left origin (accessibility convention).
        let frame: CGRect
        let title: String
    }

    struct DisplayBar: Equatable {
        /// nil if the Dock didn't report it (single display / shared Spaces).
        let displayID: CGDirectDisplayID?
        let buttons: [SpaceButton]
    }

    private static let missionControlID = "mc"
    private static let spacesListID = "mc.spaces.list"
    private static let displayIDAttribute = "AXDisplayID"

    static var hasPermission: Bool { AXIsProcessTrusted() }

    private static var dockElement: AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        return AXUIElementCreateApplication(dock.processIdentifier)
    }

    /// Cheap check: is the "mc" group among the Dock's top-level children?
    static func isOpen() -> Bool {
        missionControlGroup() != nil
    }

    /// The Spaces bar of every display, or nil when Mission Control is closed.
    static func read() -> [DisplayBar]? {
        guard let mc = missionControlGroup() else { return nil }
        var bars: [DisplayBar] = []
        collectBars(in: mc, displayID: nil, depth: 0, into: &bars)
        if bars.isEmpty { log.debug("Mission Control open but no \(spacesListID, privacy: .public) found") }
        return bars
    }

    // MARK: Tree walking

    private static func missionControlGroup() -> AXUIElement? {
        guard let dock = dockElement else { return nil }
        return children(of: dock).first { string(of: $0, kAXIdentifierAttribute) == missionControlID }
    }

    /// Finds every spaces list, remembering the nearest ancestor's display id.
    private static func collectBars(in element: AXUIElement, displayID: CGDirectDisplayID?,
                                    depth: Int, into bars: inout [DisplayBar]) {
        guard depth < 6 else { return }
        let ownDisplay = (value(of: element, displayIDAttribute) as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
        let display = ownDisplay ?? displayID

        if string(of: element, kAXIdentifierAttribute) == spacesListID {
            let buttons = children(of: element).compactMap { child -> SpaceButton? in
                guard string(of: child, kAXRoleAttribute) == kAXButtonRole as String,
                      let frame = frame(of: child) else { return nil }
                let title = string(of: child, kAXTitleAttribute) ?? string(of: child, kAXDescriptionAttribute) ?? ""
                return SpaceButton(frame: frame, title: title)
            }
            bars.append(DisplayBar(displayID: display, buttons: buttons))
            return
        }
        for child in children(of: element) {
            collectBars(in: child, displayID: display, depth: depth + 1, into: &bars)
        }
    }

    // MARK: AX helpers

    private static func value(of element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        value(of: element, attribute) as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(of: element, kAXPositionAttribute),
              let sizeValue = value(of: element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
