import SwiftUI

/// Tasarımdaki segmentli kontrol: `surface-hover` iz, seçili parça `surface-raised` + `shadow-control`.
struct SegmentedControl<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var systemImage: String? = nil
    }

    let items: [Item]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                segment(item)
            }
        }
        .padding(2)
        .background(
            Color.ds.surfaceHover.opacity(0.8),
            in: RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: selection)
    }

    private func segment(_ item: Item) -> some View {
        let isSelected = item.value == selection
        return Button {
            selection = item.value
        } label: {
            HStack(spacing: 3) {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage).imageScale(.small)
                }
                Text(item.title).lineLimit(1).fixedSize()
            }
            .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? Color.ds.ink : Color.ds.inkSecondary)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 22)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Metrics.Radius.md - 1, style: .continuous)
                        .fill(Color.ds.surfaceRaised)
                        .shadow(color: .black.opacity(0.08), radius: 0.5, y: 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.Radius.md - 1, style: .continuous)
                                .strokeBorder(Color.ds.ink.opacity(0.08), lineWidth: 0.5)
                        }
                        .matchedGeometryEffect(id: "segment", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SegmentedControlPreview: View {
    @State private var kind = DateFilter.Kind.week

    var body: some View {
        SegmentedControl(
            items: DateFilter.Kind.allCases.map {
                .init(value: $0, title: $0.title, systemImage: $0 == .custom ? "calendar" : nil)
            },
            selection: $kind
        )
        .padding(Metrics.Spacing.s4)
        .frame(width: Metrics.Layout.listWidth)
        .background(Color.ds.windowBg)
    }
}

#Preview("Light") { SegmentedControlPreview().preferredColorScheme(.light) }
#Preview("Dark") { SegmentedControlPreview().preferredColorScheme(.dark) }
