import SwiftUI

/// Kaldırılabilir aktif filtre çipi (`accent-soft` zemin).
struct FilterChip: View {
    let title: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Metrics.Spacing.s1 + 2) {
            Text(title)
                .textStyle(.caption)
                .foregroundStyle(Color.ds.ink)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.ds.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(title) filtresini kaldır"))
            }
        }
        .padding(.horizontal, Metrics.Spacing.s2 + 2)
        .padding(.vertical, Metrics.Spacing.s1)
        .background(Color.ds.accentSoft, in: Capsule())
    }
}

private struct FilterChipPreview: View {
    var body: some View {
        HStack(spacing: Metrics.Spacing.s2) {
            FilterChip(title: "Tarihe göre", onRemove: {})
            FilterChip(title: "Sprint 42", onRemove: {})
            FilterChip(title: "Sabit")
        }
        .padding(Metrics.Spacing.s4)
        .background(Color.ds.windowBg)
    }
}

#Preview("Light") { FilterChipPreview().preferredColorScheme(.light) }
#Preview("Dark") { FilterChipPreview().preferredColorScheme(.dark) }
