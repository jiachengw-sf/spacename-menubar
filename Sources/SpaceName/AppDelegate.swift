import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(store: SpaceStore())
    private let switcher = SpaceSwitcher()
    private var statusItem: StatusItemController!
    private var panel: PanelController!
    private var missionControlOverlay: MissionControlOverlay!
    private var hotkeys: DesktopHotkeys!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(target: self, action: #selector(togglePanel))
        panel = PanelController(model: model, switcher: switcher)
        missionControlOverlay = MissionControlOverlay(store: model.store)
        missionControlOverlay.start()

        hotkeys = DesktopHotkeys { [weak self] number in self?.switchToDesktop(number) }
        NotificationCenter.default.addObserver(forName: DesktopHotkeys.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.updateHotkeys() }

        // Re-render the label (and match shortcuts to the desktop count) whenever
        // the Spaces or their customization change.
        model.$snapshot.combineLatest(model.store.$entries)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, _ in
                guard let self else { return }
                self.updateHotkeys()
                let store = self.model.store
                guard let current = snapshot.current else {
                    self.statusItem.update(title: "Desktop ?", style: .plain, space: nil)
                    return
                }
                self.statusItem.update(title: store.displayName(for: current), style: store.style(for: current), space: current)
            }
            .store(in: &cancellables)

        model.refresh()
        // Adding, removing, or reordering desktops in Mission Control posts no
        // notification, so re-read the layout every few seconds (cheap).
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.model.refresh() }
        #if DEBUG
        installDebugSwitchTrigger()
        #endif

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceDidChange),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // Display changes can move the menu bar or add/remove Spaces.
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    #if DEBUG
    /// Debug builds only: lets a script test switching without clicking. Post the
    /// distributed notification "com.jiacheng.SpaceName.debug.switch" with object = row index (0-based).
    private func installDebugSwitchTrigger() {
        let center = DistributedNotificationCenter.default()
        // "com.jiacheng.SpaceName.debug.missioncontrol": press the Mission Control shortcut.
        center.addObserver(forName: Notification.Name("com.jiacheng.SpaceName.debug.missioncontrol"),
                           object: nil, queue: .main) { [weak self] _ in
            self?.switcher.debugToggleMissionControl()
        }
        // "com.jiacheng.SpaceName.debug.mouse" with object "x,y" (top-left origin): move the pointer.
        center.addObserver(forName: Notification.Name("com.jiacheng.SpaceName.debug.mouse"),
                           object: nil, queue: .main) { note in
            let parts = (note.object as? String)?.split(separator: ",").compactMap { Double($0) } ?? []
            guard parts.count == 2 else { return }
            let point = CGPoint(x: parts[0], y: parts[1])
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        center.addObserver(
            forName: Notification.Name("com.jiacheng.SpaceName.debug.switch"), object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let index = (note.object as? String).flatMap(Int.init) else { return }
            self.model.refresh()
            let spaces = self.model.snapshot.spaces
            guard spaces.indices.contains(index) else { return }
            self.switcher.switchTo(spaces[index], in: self.model.snapshot,
                                   displayName: self.model.store.displayName(for: spaces[index]))
        }
    }
    #endif

    /// ⌥N: switch to desktop N on the menu bar display. If switching can't
    /// happen (permission, shortcuts), open the panel so its banner explains why.
    private func switchToDesktop(_ number: Int) {
        model.refresh()
        let snapshot = model.snapshot
        guard let target = snapshot.spaces.first(where: { $0.desktopNumber == number }) else {
            NSSound.beep()
            return
        }
        DesktopHotkeys.afterModifiersReleased { [weak self] in
            guard let self else { return }
            let started = self.switcher.switchTo(target, in: snapshot,
                                                 displayName: self.model.store.displayName(for: target))
            if !started, let button = self.statusItem.button {
                self.panel.show(below: button)
            }
        }
    }

    private func updateHotkeys() {
        hotkeys.update(desktopCount: model.snapshot.spaces.filter { !$0.isFullscreen }.count)
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(below: button)
    }

    @objc private func spaceDidChange() {
        panel.close()
        refresh()
    }

    @objc private func refresh() {
        model.refresh()
    }
}
