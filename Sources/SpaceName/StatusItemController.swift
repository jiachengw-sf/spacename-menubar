import AppKit

/// Owns the menu bar item and renders the current Space's label.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var button: NSStatusBarButton? { statusItem.button }

    init(target: AnyObject, action: Selector) {
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Space")
        icon?.isTemplate = true
        button.image = icon?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.target = target
        button.action = action
        // Open on mouse down, like a real menu.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    func update(title: String, style: LabelStyle) {
        guard let button = statusItem.button else { return }
        button.attributedTitle = style.attributedTitle(" " + title)
        // Tint the circle icon to match; nil keeps the system template color.
        button.contentTintColor = style.color
    }
}
