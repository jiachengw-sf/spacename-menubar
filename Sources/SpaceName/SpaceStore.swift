import AppKit

/// User customization for one Space. Fields are optional so older files keep decoding
/// as styling options are added.
struct SpaceCustomization: Codable, Equatable {
    var name: String?
    /// "#RRGGBB"; nil uses the system menu bar color.
    var color: String?
    var bold: Bool?
    var italic: Bool?

    var style: LabelStyle {
        LabelStyle(color: color.flatMap(NSColor.init(hexString:)),
                   bold: bold ?? false,
                   italic: italic ?? false)
    }
}

/// Persists customizations keyed by Space UUID in
/// ~/Library/Application Support/SpaceName/spaces.json.
final class SpaceStore: ObservableObject {
    private struct FileFormat: Codable {
        var spaces: [String: SpaceCustomization]
    }

    @Published private(set) var entries: [String: SpaceCustomization] = [:]

    private let fileURL: URL

    init(fileURL: URL = SpaceStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SpaceName", isDirectory: true)
            .appendingPathComponent("spaces.json")
    }

    /// Full-screen Spaces have no UUID, so they can't be customized.
    func canCustomize(_ space: Space) -> Bool { space.uuid != nil }

    func customName(for space: Space) -> String? {
        guard let uuid = space.uuid else { return nil }
        return entries[uuid]?.name
    }

    func displayName(for space: Space) -> String {
        customName(for: space) ?? space.defaultName
    }

    func style(for space: Space) -> LabelStyle {
        guard let uuid = space.uuid else { return .plain }
        return entries[uuid]?.style ?? .plain
    }

    /// Saves name and style together. An empty name (or the default "Desktop N")
    /// clears the custom name; a plain style clears the styling.
    func save(name: String?, style: LabelStyle, for space: Space) {
        guard let uuid = space.uuid else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let entry = SpaceCustomization(
            name: trimmed.isEmpty || trimmed == space.defaultName ? nil : trimmed,
            color: style.color?.hexString,
            bold: style.bold ? true : nil,
            italic: style.italic ? true : nil
        )
        entries[uuid] = entry == SpaceCustomization() ? nil : entry
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try JSONDecoder().decode(FileFormat.self, from: data).spaces
        } catch {
            NSLog("SpaceName: could not read \(fileURL.path): \(error)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(FileFormat(spaces: entries)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SpaceName: could not write \(fileURL.path): \(error)")
        }
    }
}
