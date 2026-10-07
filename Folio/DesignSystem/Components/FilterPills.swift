import SwiftUI

/// Zeminsiz hap düğmeler: seçili olan `accent-soft` hap içinde vurgu renginde, diğerleri sade metin.
/// Seçim değişince hap kayarak geçer.
struct FilterPills<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
    }

    let items: [Item]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                PillButton(
                    title: item.title,
                    isSelected: item.value == selection,
                    namespace: namespace
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = item.value }
                }
            }
        }
    }
}

struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    var namespace: Namespace.ID? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.ds.accent : (isHovered ? Color.ds.ink : Color.ds.inkSecondary))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background {
                if isSelected {
                    pill(Color.ds.accentSoft)
                } else if isHovered {
                    Capsule().fill(Color.ds.surfaceHover.opacity(0.7))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func pill(_ color: Color) -> some View {
        if let namespace {
            Capsule().fill(color).matchedGeometryEffect(id: "pill", in: namespace)
        } else {
            Capsule().fill(color)
        }
    }
}

private struct FilterPillsPreview: View {
    @State private var kind = DateFilter.Kind.week

    var body: some View {
        HStack {
            FilterPills(
                items: [DateFilter.Kind.all, .today, .week, .month].map { .init(value: $0, title: $0.title) },
                selection: $kind
            )
            Spacer()
            PillButton(title: "Özel", systemImage: "calendar", isSelected: kind == .custom) { kind = .custom }
        }
        .padding(Metrics.Spacing.s3)
        .frame(width: Metrics.Layout.listWidth)
        .background(Color.ds.windowBg)
    }
}

#Preview("Light") { FilterPillsPreview().preferredColorScheme(.light) }
#Preview("Dark") { FilterPillsPreview().preferredColorScheme(.dark) }
