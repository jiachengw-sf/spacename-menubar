import AppKit
import SwiftUI

enum Theme {
    static let accent = Color(red: 1.0, green: 0.36, blue: 0.66)
    static let rowHeight: CGFloat = 44
}

/// The dropdown's content: one row per Space plus a small footer.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SpaceStore
    @ObservedObject var switcher: SpaceSwitcher
    let onSwitch: (Space) -> Void
    let onOpenSettingsURL: (URL) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if let problem = switcher.problem {
                SetupBanner(problem: problem, switcher: switcher, onOpenSettingsURL: onOpenSettingsURL)
                    .padding(.bottom, 4)
            }
            ForEach(model.snapshot.spaces) { space in
                SpaceRowView(model: model,
                             space: space,
                             name: store.displayName(for: space),
                             isCurrent: space.id == model.snapshot.currentID,
                             canRename: store.canCustomize(space),
                             onSwitch: onSwitch)
            }
            footer
        }
        .padding(8)
        .frame(width: PanelController.width)
        .overlay(
            RoundedRectangle(cornerRadius: PanelController.cornerRadius)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    /// Some desktop can only be reached by stepping with Control-arrow.
    private var missingDirectShortcuts: Bool {
        model.snapshot.spaces.contains { !$0.isFullscreen && switcher.lacksDirectShortcut($0) }
    }

    private var footer: some View {
        HStack {
            if missingDirectShortcuts {
                Button("Turn on direct switching…") {
                    onOpenSettingsURL(SpaceSwitcher.keyboardSettingsURL)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .help("""
                    In Keyboard Shortcuts › Mission Control, turn on "Switch to Desktop N" \
                    for each desktop. Until then, SpaceName steps through Spaces with Control-arrow keys.
                    """)
            } else {
                Text("Click a name to rename")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Button {
                SettingsMenu.show(onOpenSettingsURL: onOpenSettingsURL)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }
}

/// Explains why a switch didn't happen and links to the setting that fixes it.
struct SetupBanner: View {
    let problem: SpaceSwitcher.Problem
    let switcher: SpaceSwitcher
    let onOpenSettingsURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Dismiss") { switcher.problem = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Button(buttonTitle, action: fix)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
    }

    private var title: String {
        switch problem {
        case .needsPermission: return "Permission needed to switch Spaces"
        case .noShortcut(let name): return "Can't switch to \(name)"
        }
    }

    private var message: String {
        switch problem {
        case .needsPermission:
            return "SpaceName switches Spaces by pressing your Mission Control shortcuts. "
                + "Allow it in System Settings › Privacy & Security › Accessibility. If SpaceName is "
                + "already listed and on, remove it (−) and add it again; a rebuilt app needs a fresh grant."
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
