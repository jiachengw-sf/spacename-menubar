import AppKit

/// Owns the menu bar item and renders the current Space's label.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var button: NSStatusBarButton? { statusItem.button }

    init(target: AnyObject, action: Selector) {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.target = target
        button.action = action
        // Open on mouse down, like a real menu.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    /// `space` decides the icon: the desktop number in a circle (①…), or a
    /// full-screen symbol.
    func update(title: String, style: LabelStyle, space: Space?) {
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: Self.symbolName(for: space), accessibilityDescription: "Space")
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: "Space")
        icon?.isTemplate = true
        button.image = icon?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        button.attributedTitle = style.attributedTitle(" " + title)
        // Tint the icon to match; nil keeps the system template color.
        button.contentTintColor = style.color
    }

    /// SF Symbols has "1.circle" through "50.circle".
    private static func symbolName(for space: Space?) -> String {
        guard let space else { return "circle" }
        if space.isFullscreen { return "arrow.up.left.and.arrow.down.right.circle" }
        if let number = space.desktopNumber, (0...50).contains(number) { return "\(number).circle" }
        return "circle"
    }
}
