import AppKit

/// Live Space layout plus the inline-edit state shared by the panel views.
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = SpaceSnapshot(spaces: [], currentID: 0)
    @Published private(set) var editingID: UInt64?
    @Published var draft = ""
    @Published var draftStyle = LabelStyle.plain

    let store: SpaceStore

    init(store: SpaceStore) {
        self.store = store
    }

    func refresh() {
        let latest = SpaceProvider.snapshot()
        if latest != snapshot { snapshot = latest }
        // The Space being edited was removed.
        if let id = editingID, !latest.spaces.contains(where: { $0.id == id }) { cancelEditing() }
    }

    // MARK: Inline edit

    func beginEditing(_ space: Space) {
        guard store.canCustomize(space) else { return }
        draft = store.displayName(for: space)
        draftStyle = store.style(for: space)
        editingID = space.id
    }

    func commitEditing() {
        if let id = editingID, let space = snapshot.spaces.first(where: { $0.id == id }) {
            store.save(name: draft, style: draftStyle, for: space)
        }
        cancelEditing()
    }

    func cancelEditing() {
        editingID = nil
        draft = ""
        draftStyle = .plain
    }
}
