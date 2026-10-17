import AppKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.jiacheng.SpaceName", category: "missioncontrol")

/// Draws your Space names over Mission Control's "Desktop N" labels.
///
/// There is no notification for Mission Control opening, so this polls the Dock
/// cheaply while closed and tracks label positions quickly while open (the bar
/// expands into thumbnails when hovered, which moves the labels).
final class MissionControlOverlay {
    static let enabledKey = "showNamesInMissionControl"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static let idleInterval: TimeInterval = 0.25
    private static let trackingInterval: TimeInterval = 1.0 / 30
    /// Mission Control animates the bar when it opens and when it expands on hover.
    /// Tags stay hidden until positions have been still this long, then fade in,
    /// instead of chasing the animation.
    private static let settleDelay: TimeInterval = 0.3

    private let store: SpaceStore
    private var timer: Timer?
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var isTracking = false
    private var loggedMismatch = false
    private var lastFrames: [CGRect] = []
    private var lastMovedAt = Date.distantPast

    init(store: SpaceStore) {
        self.store = store
    }

    /// Keeps App Nap from throttling the poll timer. A windowless menu bar app is
    /// napped soon after launch, and then Mission Control opening goes unnoticed.
    private var activity: NSObjectProtocol?

    func start() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Watch for Mission Control to show Space names")
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app")
        schedule(interval: Self.idleInterval)
    }

    // MARK: Polling

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = interval / 4
    }

    private func tick() {
        guard Self.isEnabled, DockMissionControl.hasPermission, let bars = DockMissionControl.read() else {
            if isTracking {
                isTracking = false
                lastFrames = []
                hideAll()
                schedule(interval: Self.idleInterval)
            }
            return
        }
        if !isTracking {
            isTracking = true
            loggedMismatch = false
            schedule(interval: Self.trackingInterval)
            for bar in bars {
                let buttons = bar.buttons.map { "\($0.title)@\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
                log.debug("Mission Control opened; display \(bar.displayID ?? 0): \(buttons.joined(separator: " | "), privacy: .public)")
            }
        }
        render(bars)
    }

    // MARK: Rendering

    private func render(_ bars: [DockMissionControl.DisplayBar]) {
        let displays = SpaceProvider.allDisplays()
        var tagsByScreen: [CGDirectDisplayID: [OverlayTag]] = [:]

        for (index, bar) in bars.enumerated() {
            guard let spaces = spaces(for: bar, index: index, in: displays) else { continue }
            guard spaces.count == bar.buttons.count else {
                if !loggedMismatch {
                    log.error("Spaces bar has \(bar.buttons.count) buttons but display has \(spaces.count) Spaces; skipping")
                    loggedMismatch = true
                }
                continue
            }
            for (space, button) in zip(spaces, bar.buttons) {
                guard let uuid = space.uuid, let entry = store.entries[uuid] else { continue }
                guard let screen = Self.screen(containing: button.frame) else { continue }
                let tag = OverlayTag(id: uuid,
                                     frame: Self.localFrame(button.frame, in: screen),
                                     coverWidth: Self.labelWidth(button.title),
                                     text: entry.name ?? space.defaultName,
                                     style: entry.style)
                tagsByScreen[screen.displayID, default: []].append(tag)
            }
        }

        // Hide while anything is moving; show once it has settled.
        let frames = tagsByScreen.keys.sorted().flatMap { tagsByScreen[$0]!.map(\.frame) }
        if frames != lastFrames {
            lastFrames = frames
            lastMovedAt = Date()
        }
        if Date().timeIntervalSince(lastMovedAt) < Self.settleDelay {
            hideAll()
            return
        }

        for (displayID, window) in windows where tagsByScreen[displayID] == nil {
            window.orderOut(nil)
        }
        for (displayID, tags) in tagsByScreen {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { continue }
            let window = windows[displayID] ?? OverlayWindow()
            windows[displayID] = window
            window.show(tags: tags, on: screen)
        }
    }

    private func spaces(for bar: DockMissionControl.DisplayBar, index: Int,
                        in displays: [DisplaySpaces]) -> [Space]? {
        if displays.count == 1 { return displays[0].spaces }
        if let id = bar.displayID, let uuid = SpaceProvider.identifier(for: id),
           let match = displays.first(where: { $0.identifier.caseInsensitiveCompare(uuid) == .orderedSame }) {
            return match.spaces
        }
        // Fall back to order: the Dock and window server usually list displays alike.
        return displays.indices.contains(index) ? displays[index].spaces : nil
    }

    private func hideAll() {
        windows.values.forEach { $0.orderOut(nil) }
    }

    /// Width of Mission Control's own label (e.g. "Desktop 6"), so a shorter
    /// custom name still hides it completely.
    private static func labelWidth(_ title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width) + 20
    }

    // MARK: Coordinates

    /// Accessibility frames use a top-left origin at the primary screen's top-left.
    private static var primaryScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func screen(containing axFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: axFrame.midX, y: primaryScreenHeight - axFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    /// Converts to the overlay window's SwiftUI space (top-left origin of that screen).
    private static func localFrame(_ axFrame: CGRect, in screen: NSScreen) -> CGRect {
        let screenTop = primaryScreenHeight - screen.frame.maxY
        return axFrame.offsetBy(dx: -screen.frame.minX, dy: -screenTop)
    }
}

// MARK: - Window

/// Click-through window above Mission Control. `.stationary` keeps it out of
/// Mission Control's own layout so it stays put on top.
private final class OverlayWindow: NSPanel {
    private let host = NSHostingView(rootView: OverlayView(tags: []))

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = host
    }

    func show(tags: [OverlayTag], on screen: NSScreen) {
        if frame != screen.frame { setFrame(screen.frame, display: false) }
        if host.rootView.tags != tags { host.rootView = OverlayView(tags: tags) }
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                animator().alphaValue = 1
            }
        }
    }
}

// MARK: - SwiftUI

struct OverlayTag: Identifiable, Equatable {
    let id: String
    /// The Dock button's frame in window coordinates (top-left origin).
    let frame: CGRect
    /// Minimum tag width that hides the Dock's own label.
    let coverWidth: CGFloat
    let text: String
    let style: LabelStyle
}

private struct OverlayView: View {
    let tags: [OverlayTag]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(tags) { tag in
                OverlayTagView(tag: tag)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OverlayTagView: View {
    let tag: OverlayTag

    /// Collapsed bar: the button is just the label pill. Expanded (hovered): the
    /// button is a thumbnail and the label sits below it.
    private var isExpanded: Bool { tag.frame.height > 60 }

    var body: some View {
        Text(tag.text)
            .font(Font(tag.style.font(size: 13) as CTFont))
            .foregroundStyle(Color(nsColor: tag.style.color ?? .white))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minWidth: isExpanded ? tag.coverWidth : max(tag.frame.width, tag.coverWidth),
                   minHeight: isExpanded ? 22 : tag.frame.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.2, opacity: 0.96)))
            .fixedSize()
            .position(x: tag.frame.midX,
                      y: isExpanded ? tag.frame.maxY + 14 : tag.frame.midY)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
