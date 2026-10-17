import SwiftUI

/// A Space row in the style of the Wi-Fi menu's network rows: a round icon
/// (numbered, accent-filled for the current Space), the name, and the row's
/// shortcut. Clicking the row switches; hovering reveals a rename button.
struct SpaceRowView: View {
    @ObservedObject var model: AppModel
    let space: Space
    let name: String
    let isCurrent: Bool
    let canRename: Bool
    let shortcut: String?
    let onSwitch: (Space) -> Void

    @State private var isHovering = false

    private var isEditing: Bool { model.editingID == space.id }

    var body: some View {
        VStack(spacing: 6) {
            if isEditing {
                HStack(spacing: 10) {
                    SpaceBadge(space: space, isCurrent: isCurrent)
                    RenameField(model: model, placeholder: space.defaultName)
                }
                .padding(.horizontal, 8)
                .frame(height: Theme.rowHeight)
                StyleEditor(model: model, placeholder: space.defaultName)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
            } else {
                row
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            SpaceBadge(space: space, isCurrent: isCurrent)
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.rowHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if !isCurrent { onSwitch(space) } }
        .help(isCurrent ? "You're on this Space" : "Switch to \(name)")
    }

    @ViewBuilder
    private var trailing: some View {
        if isHovering && canRename {
            Button { model.beginEditing(space) } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename and style")
        } else if let shortcut {
            Text(shortcut)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Round icon with the desktop number; filled with the accent color for the
/// current Space, like the connected network in the Wi-Fi menu.
struct SpaceBadge: View {
    let space: Space
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Circle().fill(isCurrent ? Theme.accent : Color.primary.opacity(0.1))
            if let number = space.desktopNumber {
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(isCurrent ? Color.white : Color.primary)
        .frame(width: 26, height: 26)
    }
}

/// Accent-bordered text field with cancel (X) and confirm (✓) buttons.
/// Enter confirms; Escape is handled by PanelController and cancels.
struct RenameField: View {
    @ObservedObject var model: AppModel
    let placeholder: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $model.draft, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { model.commitEditing() }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent, lineWidth: 1.5))

            Button { model.cancelEditing() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")

            Button { model.commitEditing() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .help("Save (Return)")
        }
        .onAppear {
            // Wait a runloop so the field exists before focusing it.
            DispatchQueue.main.async { focused = true }
        }
    }
}
