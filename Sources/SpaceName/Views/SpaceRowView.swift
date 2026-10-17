import SwiftUI

/// A Space row: numbered badge, name (click to rename), and the switch arrow.
struct SpaceRowView: View {
    @ObservedObject var model: AppModel
    let space: Space
    let name: String
    let isCurrent: Bool
    let canRename: Bool
    let onSwitch: (Space) -> Void

    @State private var isHovering = false
    @State private var isHoveringArrow = false

    private var isEditing: Bool { model.editingID == space.id }

    var body: some View {
        VStack(spacing: 6) {
            mainRow
            if isEditing {
                StyleEditor(model: model, placeholder: space.defaultName)
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            SpaceBadge(space: space, isCurrent: isCurrent)
            if isEditing {
                RenameField(model: model, placeholder: space.defaultName)
            } else {
                label
                switchButton
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowHeight / 2)
                .fill(.white.opacity(isEditing ? 0.06 : (isHovering ? 0.07 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowHeight / 2)
                .strokeBorder(.white.opacity(isEditing ? 0.55 : 0), lineWidth: 1.5)
        )
        .onHover { isHovering = $0 }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            if space.isFullscreen {
                Text("Full Screen")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if canRename { model.beginEditing(space) } }
        .help(canRename ? "Click to rename" : "Full-screen Spaces can't be renamed")
    }

    private var switchButton: some View {
        Button { onSwitch(space) } label: {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(isCurrent ? 0.25 : 0.9))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(isHoveringArrow && !isCurrent ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { isHoveringArrow = $0 }
        .help(isCurrent ? "You're on this Space" : "Switch to this Space")
    }
}

/// Numbered circle; the current Space gets an outer ring.
struct SpaceBadge: View {
    let space: Space
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.12))
            if let number = space.desktopNumber {
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: 24, height: 24)
        .padding(3)
        .overlay(Circle().strokeBorder(.white.opacity(isCurrent ? 0.85 : 0), lineWidth: 1.5))
    }
}

/// Pink-bordered text field with cancel (X) and confirm (✓) buttons.
/// Enter confirms; Escape is handled by PanelController and cancels.
struct RenameField: View {
    @ObservedObject var model: AppModel
    let placeholder: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $model.draft, prompt: Text(placeholder).foregroundColor(.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit { model.commitEditing() }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, lineWidth: 1.5))

            Button { model.cancelEditing() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")

            Button { model.commitEditing() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accent))
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
