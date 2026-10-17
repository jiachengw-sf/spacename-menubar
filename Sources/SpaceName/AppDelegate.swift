import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(store: SpaceStore())
    private let switcher = SpaceSwitcher()
    private var statusItem: StatusItemController!
    private var panel: PanelController!
    private var missionControlOverlay: MissionControlOverlay!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(target: self, action: #selector(togglePanel))
        panel = PanelController(model: model, switcher: switcher)
        missionControlOverlay = MissionControlOverlay(store: model.store)
        missionControlOverlay.start()

        // Re-render the label whenever the current Space or its customization changes.
        model.$snapshot.combineLatest(model.store.$entries)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, _ in
                guard let self else { return }
                let store = self.model.store
                guard let current = snapshot.current else {
                    self.statusItem.update(title: "Desktop ?", style: .plain)
                    return
                }
                self.statusItem.update(title: store.displayName(for: current), style: store.style(for: current))
            }
            .store(in: &cancellables)

        model.refresh()
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
        DistributedNotificationCenter.default().addObserver(
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
