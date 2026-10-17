import AppKit
import Combine
import SwiftUI

/// Borderless panel that can take keyboard focus (for inline rename) without
/// activating the app or stealing focus from the frontmost app's windows.
private final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the Space list under the status item, styled like the system's own
/// menu bar panels (Wi-Fi, Control Center): glass on macOS 26, frosted before that.
final class PanelController {
    static let width: CGFloat = 300
    static let cornerRadius: CGFloat = 18

    private let model: AppModel
    private let switcher: SpaceSwitcher
    private let panel: DropdownPanel
    private let hostingView: NSHostingView<PanelView>
    private var anchor: NSRect = .zero
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []

    var isVisible: Bool { panel.isVisible }

    init(model: AppModel, switcher: SpaceSwitcher) {
        self.model = model
        self.switcher = switcher

        panel = DropdownPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]

        hostingView = NSHostingView(rootView: PanelView(model: model, store: model.store, switcher: switcher,
                                                        onSwitch: { _ in }, onOpenSettingsURL: { _ in }))
        panel.contentView = Self.makeBackground(containing: hostingView)
        hostingView.rootView = PanelView(
            model: model, store: model.store, switcher: switcher,
            onSwitch: { [weak self] space in self?.switchTo(space) },
            onOpenSettingsURL: { [weak self] url in
                self?.close()
                NSWorkspace.shared.open(url)
            })

        // Spaces added/removed or the style editor opening/closing: resize, keeping the top edge fixed.
        model.$snapshot.map { _ in () }
            .merge(with: model.$editingID.map { _ in () }, switcher.$problem.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.layout()
            }
            .store(in: &cancellables)
    }

    func toggle(below button: NSStatusBarButton) {
        isVisible ? close() : show(below: button)
    }

    func show(below button: NSStatusBarButton) {
        guard let window = button.window else { return }
        model.refresh()
        // Say up front that switching and Mission Control names are off, instead of failing silently.
        if !switcher.hasPermission { switcher.problem = .needsPermission }
        anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        layout()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() {
        guard isVisible else { return }
        model.cancelEditing()
        switcher.problem = nil
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
        panel.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Closes the panel and switches; on failure keeps it open with a setup banner.
    private func switchTo(_ space: Space) {
        model.cancelEditing()
        model.refresh()
        let started = switcher.switchTo(space, in: model.snapshot,
                                        displayName: model.store.displayName(for: space))
        if started { close() }
    }

    private func layout() {
        hostingView.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: hostingView.fittingSize.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = anchor.minY - 6 - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        // Clicks in other apps close the panel, like a menu.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(m) }
        // Escape cancels an edit first, then closes the panel.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, self.panel.isKeyWindow else { return event }
            if self.model.editingID != nil { self.model.cancelEditing() } else { self.close() }
            return nil
        }) { monitors.append(m) }
    }

    /// Glass on macOS 26 (matches Wi-Fi / Control Center); the popover material before.
    /// Both follow the system's light or dark appearance.
    private static func makeBackground(containing content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = roundedMask(radius: cornerRadius)
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
