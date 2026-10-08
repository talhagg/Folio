import SwiftUI

/// Toolbar arama alanı: büyüteç, yer tutucu, ⌘F ipucu; yazınca temizle düğmesi. Esc metni temizler.
struct ToolbarSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ds.inkTertiary)
            TextField("Notlarda ara", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(isFocused)
                .tint(Color.ds.accent)
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
            if text.isEmpty {
                Text("⌘F")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ds.inkTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.ds.surfaceHover.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ds.inkTertiary)
                }
                .buttonStyle(.plain)
                .help(Text("Aramayı temizle"))
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 240, height: 28)
        .background(Color.ds.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? Color.ds.accent.opacity(0.7) : Color.ds.separator, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.12), value: isFocused.wrappedValue)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Ara"))
    }
}
