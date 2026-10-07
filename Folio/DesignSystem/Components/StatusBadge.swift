import SwiftUI

/// Durum rozeti: her zaman ikon + metin (renk tek başına bilgi taşımaz).
struct StatusBadge: View {
    let status: NoteStatus
    var showsTitle = true

    var body: some View {
        HStack(spacing: Metrics.Spacing.s1) {
            Image(systemName: status.symbolName)
                .imageScale(.small)
            if showsTitle {
                Text(status.title)
            }
        }
        .textStyle(.caption)
        .foregroundStyle(status.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(status.title))
    }
}

private struct StatusBadgePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s2) {
            ForEach(NoteStatus.allCases, id: \.self) { StatusBadge(status: $0) }
        }
        .padding(Metrics.Spacing.s4)
        .background(Color.ds.surface)
    }
}

#Preview("Light") { StatusBadgePreview().preferredColorScheme(.light) }
#Preview("Dark") { StatusBadgePreview().preferredColorScheme(.dark) }
