import SwiftUI

/// Defter etiketi: renkli nokta + defter adı.
struct GroupTag: View {
    let name: String
    let color: GroupColor

    var body: some View {
        HStack(spacing: Metrics.Spacing.s1 + 2) {
            Circle()
                .fill(color.color)
                .frame(width: 7, height: 7)
            Text(name)
                .textStyle(.caption)
                .foregroundStyle(Color.ds.inkSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Defter: \(name)"))
    }
}

private struct GroupTagPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s2) {
            ForEach(GroupColor.allCases, id: \.self) { GroupTag(name: $0.title, color: $0) }
        }
        .padding(Metrics.Spacing.s4)
        .background(Color.ds.windowBg)
    }
}

#Preview("Light") { GroupTagPreview().preferredColorScheme(.light) }
#Preview("Dark") { GroupTagPreview().preferredColorScheme(.dark) }
