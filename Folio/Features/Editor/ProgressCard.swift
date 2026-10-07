import SwiftUI

/// Editördeki etiketli ilerleme kartı. Durum rozeti aynı zamanda Bloke işaretleme menüsüdür.
struct ProgressCard: View {
    @Bindable var note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s2 + 2) {
            HStack(spacing: Metrics.Spacing.s2) {
                statusMenu
                Spacer(minLength: Metrics.Spacing.s2)
                Text(summary)
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
                    .monospacedDigit()
            }
            ProgressBarView(value: note.progress ?? 0, size: .md, tint: note.status.color, showsValue: false)
        }
        .padding(.horizontal, Metrics.Spacing.s4)
        .padding(.vertical, Metrics.Spacing.s3)
        .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous)
                .strokeBorder(Color.ds.separator.opacity(0.6), lineWidth: 1)
        }
    }

    private var summary: String {
        let percent = (note.progress ?? 0).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(note.doneTaskCount)/\(note.taskCount) görev · \(percent)")
    }

    private var statusMenu: some View {
        Menu {
            if note.isBlocked {
                Button("Blokeyi Kaldır", systemImage: "arrow.uturn.backward") { setBlocked(false) }
            } else {
                Button("Bloke Olarak İşaretle", systemImage: NoteStatus.blocked.symbolName) { setBlocked(true) }
            }
        } label: {
            HStack(spacing: 3) {
                StatusBadge(status: note.status)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(note.status.color.opacity(0.7))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Durumu değiştir"))
    }

    private func setBlocked(_ blocked: Bool) {
        withAnimation(.snappy) { note.isBlocked = blocked }
        note.touch()
    }
}
