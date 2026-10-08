import SwiftData
import SwiftUI

/// Notun altında: `[[bu not]]` ile bu nota bağlanan notlar.
struct BacklinksView: View {
    let note: Note
    @Query private var notes: [Note]

    var body: some View {
        let links = NoteLinkSyntax.backlinks(to: note.title, in: notes, excluding: note.id)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.Spacing.s2) {
                Rectangle().fill(Color.ds.separator).frame(height: 1)
                Label("Bu nota bağlananlar", systemImage: "arrow.turn.down.left")
                    .textStyle(.sectionLabel)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .padding(.top, Metrics.Spacing.s2)
                ForEach(links) { linking in
                    Button {
                        AppNavigator.shared.open(.note(linking.id))
                    } label: {
                        HStack(spacing: Metrics.Spacing.s2) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(Color.ds.inkTertiary)
                            Text(linking.title.isEmpty ? String(localized: "Başlıksız not") : linking.title)
                                .foregroundStyle(Color.ds.accent)
                            if let path = linking.locationPath {
                                Text(path)
                                    .foregroundStyle(Color.ds.inkTertiary)
                            }
                        }
                        .textStyle(.callout)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
