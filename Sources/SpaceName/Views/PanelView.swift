import AppKit
import SwiftUI

enum Theme {
    /// The user's system accent color, like the system's own menus.
    static let accent = Color.accentColor
    static let rowHeight: CGFloat = 36
}

/// The dropdown's content, laid out like the system's Wi-Fi menu: a title,
/// sections with secondary headers, hoverable rows, and settings at the bottom.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SpaceStore
    @ObservedObject var switcher: SpaceSwitcher
    let onSwitch: (Space) -> Void
    let onOpenSettingsURL: (URL) -> Void

    private var desktops: [Space] { model.snapshot.spaces.filter { !$0.isFullscreen } }
    private var fullscreen: [Space] { model.snapshot.spaces.filter(\.isFullscreen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Spaces")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if let problem = switcher.problem {
                SetupBanner(problem: problem, switcher: switcher, onOpenSettingsURL: onOpenSettingsURL)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            MenuSeparator()
            SectionHeader("Desktops")
            rows(desktops)

            if !fullscreen.isEmpty {
                MenuSeparator()
                SectionHeader("Full Screen")
                rows(fullscreen)
            }

            MenuSeparator()
            if missingDirectShortcuts {
                MenuActionRow(title: "Turn On Desktop Shortcuts…",
                              help: "In Keyboard Shortcuts › Mission Control, turn on \"Switch to Desktop N\" "
                                + "for each desktop. You get ⌃1, ⌃2… shortcuts, and SpaceName jumps straight "
                                + "there instead of stepping through each desktop.") {
                    onOpenSettingsURL(SpaceSwitcher.keyboardSettingsURL)
                }
            }
            MenuActionRow(title: "SpaceName Settings…") {
                SettingsMenu.show(onOpenSettingsURL: onOpenSettingsURL)
            }
        }
        .padding(.bottom, 6)
        .frame(width: PanelController.width)
    }

    private func rows(_ spaces: [Space]) -> some View {
        VStack(spacing: 0) {
            ForEach(spaces) { space in
                SpaceRowView(model: model,
                             space: space,
                             name: store.displayName(for: space),
                             isCurrent: space.id == model.snapshot.currentID,
                             canRename: store.canCustomize(space),
                             shortcut: switcher.shortcutLabel(for: space),
                             onSwitch: onSwitch)
            }
        }
        .padding(.horizontal, 6)
    }

    /// Some desktop can only be reached by stepping with Control-arrow.
    private var missingDirectShortcuts: Bool {
        desktops.contains { switcher.lacksDirectShortcut($0) }
    }
}

// MARK: - Menu building blocks

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }
}

/// A plain text row like "Wi-Fi Settings…", highlighted on hover.
struct MenuActionRow: View {
    let title: String
    var help: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: action)
            .help(help ?? "")
            .padding(.horizontal, 6)
    }
}

// MARK: - Setup banner

/// Explains why switching or Mission Control names aren't working and links to the fix.
struct SetupBanner: View {
    let problem: SpaceSwitcher.Problem
    let switcher: SpaceSwitcher
    let onOpenSettingsURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Dismiss") { switcher.problem = nil }
                    .controlSize(.small)
                Button(buttonTitle, action: fix)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }

    private var title: String {
        switch problem {
        case .needsPermission: return "Permission needed"
        case .noShortcut(let name): return "Can't switch to \(name)"
        }
    }

    private var message: String {
        switch problem {
        case .needsPermission:
            return "Switching Spaces and showing your names in Mission Control need Accessibility "
                + "permission. Allow it in System Settings › Privacy & Security › Accessibility. If SpaceName is "
                + "already listed and on, remove it (−) and add it again."
        case .noShortcut:
            return "Turn on \"Switch to Desktop N\" (or \"Move left/right a space\") in "
                + "System Settings › Keyboard › Keyboard Shortcuts… › Mission Control."
        }
    }

    private var buttonTitle: String {
        switch problem {
        case .needsPermission: return "Grant Access"
        case .noShortcut: return "Open Keyboard Settings"
        }
    }

    private func fix() {
        switch problem {
        case .needsPermission:
            switcher.requestPermission()
        case .noShortcut:
            onOpenSettingsURL(SpaceSwitcher.keyboardSettingsURL)
        }
    }
}
