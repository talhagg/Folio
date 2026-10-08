import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Önizlemede görsel: genişliğe sığar, çift tıklayınca varsayılan uygulamada açılır.
struct AttachmentImageView: View {
    let attachment: NoteAttachment?
    let source: String
    let alt: String

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s1) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: min(image.size.width, Metrics.Layout.readingWidth), alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                                .strokeBorder(Color.ds.separator, lineWidth: 1)
                        }
                } else if let url = URL(string: source), url.scheme?.hasPrefix("http") == true {
                    AsyncImage(url: url) { phase in
                        if let loaded = phase.image {
                            loaded.resizable().scaledToFit().frame(maxWidth: Metrics.Layout.readingWidth, alignment: .leading)
                        } else {
                            placeholder(String(localized: "Görsel yükleniyor…"))
                        }
                    }
                } else {
                    placeholder(String(localized: "Görsel bulunamadı"))
                }
            }
            if !alt.isEmpty {
                Text(alt)
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkTertiary)
            }
        }
        .onTapGesture(count: 2) { attachment.map(AttachmentActions.open) }
        .contextMenu {
            if let attachment {
                Button("Aç") { AttachmentActions.open(attachment) }
            }
        }
        .task(id: attachment?.id) {
            image = attachment?.data.flatMap(NSImage.init(data:))
        }
        .accessibilityLabel(Text(alt.isEmpty ? String(localized: "Görsel") : alt))
    }

    private func placeholder(_ text: String) -> some View {
        Label(text, systemImage: "photo")
            .textStyle(.callout)
            .foregroundStyle(Color.ds.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.md))
    }
}

/// Önizlemede dosya eki: simge, ad, boyut; tıklayınca açılır.
struct AttachmentChip: View {
    let attachment: NoteAttachment?
    let name: String
    @State private var isHovered = false

    var body: some View {
        Button {
            attachment.map(AttachmentActions.open)
        } label: {
            HStack(spacing: Metrics.Spacing.s2) {
                Image(nsImage: NSWorkspace.shared.icon(for: attachment?.contentType ?? .data))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment?.fileName ?? name)
                        .textStyle(.headline)
                        .foregroundStyle(Color.ds.ink)
                        .lineLimit(1)
                    Text(attachment.map { ByteCountFormatter.string(fromByteCount: Int64($0.byteCount), countStyle: .file) }
                         ?? String(localized: "Dosya bulunamadı"))
                        .textStyle(.caption)
                        .foregroundStyle(Color.ds.inkSecondary)
                }
                Spacer(minLength: Metrics.Spacing.s2)
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(Color.ds.inkTertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, Metrics.Spacing.s3)
            .padding(.vertical, Metrics.Spacing.s2)
            .frame(maxWidth: 360, alignment: .leading)
            .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.md + 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.Radius.md + 2, style: .continuous)
                    .strokeBorder(isHovered ? Color.ds.accent.opacity(0.5) : Color.ds.separator, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(attachment == nil)
        .help(Text("Varsayılan uygulamada aç"))
    }
}

@MainActor
enum AttachmentActions {
    static func open(_ attachment: NoteAttachment) {
        guard let url = try? attachment.temporaryFileURL() else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Yapıştırılan ya da bırakılan ek.
enum AttachmentInput {
    case file(URL)
    case image(Data, UTType)
}
