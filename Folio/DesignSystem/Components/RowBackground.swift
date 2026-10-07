import SwiftUI

/// Seçim ve hover zemini. Seçili: `selection`, hover: `surface-hover` (yarı opak).
struct RowBackground: ViewModifier {
    var isSelected: Bool
    var cornerRadius: CGFloat = Metrics.Radius.md
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var fill: Color {
        if isSelected { return Color.ds.selection }
        if isHovered { return Color.ds.surfaceHover.opacity(0.55) }
        return .clear
    }
}

extension View {
    func rowBackground(isSelected: Bool, cornerRadius: CGFloat = Metrics.Radius.md) -> some View {
        modifier(RowBackground(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}
