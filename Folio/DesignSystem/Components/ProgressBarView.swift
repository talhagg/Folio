import SwiftUI

/// İnce ilerleme çubuğu. `sm`: not satırı (değer sağda), `md`: editör kartı (üstte etiket + değer).
struct ProgressBarView: View {
    enum Size {
        case sm, md

        var height: CGFloat { self == .sm ? 4 : 6 }
    }

    let value: Double
    var size: Size = .sm
    var tint: Color = Color.ds.accent
    /// `md` boyutunda solda gösterilen etiket (ör. durum rozeti).
    var label: AnyView? = nil
    /// Sağda gösterilen değer metni; `nil` ise yüzde.
    var valueText: String? = nil
    var showsValue = true

    private var clamped: Double { min(max(value, 0), 1) }
    private var formattedValue: String {
        valueText ?? clamped.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        switch size {
        case .sm:
            HStack(spacing: Metrics.Spacing.s2) {
                bar
                if showsValue {
                    Text(formattedValue)
                        .textStyle(.caption)
                        .foregroundStyle(Color.ds.inkSecondary)
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
        case .md:
            VStack(alignment: .leading, spacing: Metrics.Spacing.s2) {
                if label != nil || showsValue {
                    HStack {
                        label
                        Spacer(minLength: Metrics.Spacing.s2)
                        if showsValue {
                            Text(formattedValue)
                                .textStyle(.caption)
                                .foregroundStyle(Color.ds.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                }
                bar
            }
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ds.surfaceHover)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: size.height)
        .accessibilityElement()
        .accessibilityLabel(Text("İlerleme"))
        .accessibilityValue(Text(formattedValue))
    }
}

private struct ProgressBarPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s4) {
            ProgressBarView(value: 0.62, tint: Color.ds.statusDoing)
            ProgressBarView(value: 1, tint: Color.ds.statusDone)
            ProgressBarView(value: 0.3, tint: Color.ds.statusBlocked)
            ProgressBarView(
                value: 0.62,
                size: .md,
                tint: Color.ds.statusDoing,
                label: AnyView(StatusBadge(status: .doing)),
                valueText: "5/8 görev · %62"
            )
            .padding(Metrics.Spacing.s3)
            .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg))
        }
        .padding(Metrics.Spacing.s4)
        .frame(width: 320)
        .background(Color.ds.surface)
    }
}

#Preview("Light") { ProgressBarPreview().preferredColorScheme(.light) }
#Preview("Dark") { ProgressBarPreview().preferredColorScheme(.dark) }
