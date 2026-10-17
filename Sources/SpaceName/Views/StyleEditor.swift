import AppKit
import SwiftUI

/// Color, bold and italic controls shown under the row being edited, with a
/// live preview of the menu bar label on light and dark menu bars.
struct StyleEditor: View {
    @ObservedObject var model: AppModel
    let placeholder: String

    /// nil is "Auto": the system color, which follows the menu bar appearance.
    private static let swatches: [NSColor?] = [
        nil,
        NSColor(srgbRed: 1.0, green: 0.36, blue: 0.66, alpha: 1),
        .systemRed,
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemBlue,
    ]

    private var style: LabelStyle { model.draftStyle }
    private var title: String { model.draft.isEmpty ? placeholder : model.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(Self.swatches.indices, id: \.self) { index in
                    swatch(Self.swatches[index])
                }
                ColorPicker("", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 22, height: 18)
                    .help("Custom color")
                Spacer(minLength: 4)
                toggle("bold", isOn: $model.draftStyle.bold, help: "Bold")
                toggle("italic", isOn: $model.draftStyle.italic, help: "Italic")
            }

            HStack(spacing: 6) {
                preview(dark: false)
                preview(dark: true)
            }

            let poor = MenuBarContrast.poorContrastModes(for: style.color)
            if !poor.isEmpty {
                Label("Hard to read on a \(poor.joined(separator: " or ")) menu bar",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .onAppear {
            // Keep the color panel above the dropdown.
            NSColorPanel.shared.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        }
    }

    // MARK: Controls

    private func swatch(_ color: NSColor?) -> some View {
        let selected = color?.hexString == style.color?.hexString
        return Button { model.draftStyle.color = color } label: {
            Group {
                if let color {
                    Circle().fill(Color(nsColor: color))
                } else {
                    // Half black, half white: "follows the menu bar".
                    Circle().fill(LinearGradient(stops: [.init(color: .white, location: 0.5),
                                                         .init(color: .black, location: 0.5)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .frame(width: 16, height: 16)
            .padding(2)
            .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0.15), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .help(color == nil ? "Auto (system color)" : "")
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: style.color ?? .white) },
            set: { model.draftStyle.color = NSColor($0).usingColorSpace(.sRGB) }
        )
    }

    private func toggle(_ symbol: String, isOn: Binding<Bool>, help: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.white : Color.secondary)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(isOn.wrappedValue ? Theme.accent : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Preview

    private func preview(dark: Bool) -> some View {
        let background = dark ? MenuBarContrast.darkBackground : MenuBarContrast.lightBackground
        let textColor = style.color ?? (dark ? .white : .black)
        return HStack(spacing: 4) {
            Image(systemName: "record.circle")
                .font(.system(size: 11))
            Text(title)
                .font(Font(style.font(size: 13) as CTFont))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Color(nsColor: textColor))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: background)))
        .help(dark ? "Dark menu bar preview" : "Light menu bar preview")
    }
}
