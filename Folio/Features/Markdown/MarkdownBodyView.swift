import SwiftUI

/// Not gövdesini biçimlendirilmiş gösterir: başlıklar, listeler, alıntı, kod ve tablolar.
/// Tabloya tıklamak tablo düzenleyicisini, başka bir yere tıklamak metin düzenlemeyi açar.
struct MarkdownBodyView: View {
    let text: String
    var attachments: [UUID: NoteAttachment] = [:]
    var onEditText: () -> Void = {}
    var onEditTable: (ParsedBlock) -> Void = { _ in }

    @Environment(\.editorTextScale) private var scale

    var body: some View {
        let blocks = MarkdownDocument.parse(text)
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            if blocks.isEmpty {
                Text("Yazmaya başlayın…")
                    .textStyle(.noteBody, scale: scale)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onEditText)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, parsed in
                blockView(parsed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ parsed: ParsedBlock) -> some View {
        switch parsed.block {
        case .table(let table):
            MarkdownTableView(table: table, onEdit: { onEditTable(parsed) })
        case .image(let alt, let source):
            AttachmentImageView(attachment: NoteAttachment.id(fromReference: source).flatMap { attachments[$0] }, source: source, alt: alt)
        case .attachment(let name, let source):
            AttachmentChip(attachment: NoteAttachment.id(fromReference: source).flatMap { attachments[$0] }, name: name)
        default:
            textBlock(parsed.block)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEditText)
        }
    }

    @ViewBuilder
    private func textBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .foregroundStyle(Color.ds.ink)
                .padding(.top, level <= 2 ? Metrics.Spacing.s2 : Metrics.Spacing.s1)
        case .paragraph(let text):
            Text(inline(text))
                .textStyle(.noteBody, scale: scale)
                .foregroundStyle(Color.ds.ink)
                .textSelection(.enabled)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: Metrics.Spacing.s1) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.Spacing.s2) {
                        if let checked = item.isChecked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? Color.ds.accent : Color.ds.controlBorder)
                        } else {
                            Text("•").foregroundStyle(Color.ds.inkSecondary)
                        }
                        Text(inline(item.text))
                            .strikethrough(item.isChecked == true, color: Color.ds.inkTertiary)
                            .foregroundStyle(item.isChecked == true ? Color.ds.inkTertiary : Color.ds.ink)
                    }
                }
            }
            .textStyle(.noteBody, scale: scale)
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: Metrics.Spacing.s1) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.Spacing.s2) {
                        Text("\(index + 1).")
                            .foregroundStyle(Color.ds.inkSecondary)
                            .monospacedDigit()
                        Text(inline(item)).foregroundStyle(Color.ds.ink)
                    }
                }
            }
            .textStyle(.noteBody, scale: scale)
        case .quote(let text):
            HStack(spacing: Metrics.Spacing.s3) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.ds.accentSoft)
                    .frame(width: 3)
                Text(inline(text))
                    .textStyle(.noteBody, scale: scale)
                    .italic()
                    .foregroundStyle(Color.ds.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .textStyle(.code, scale: scale)
                    .foregroundStyle(Color.ds.ink)
                    .textSelection(.enabled)
                    .padding(Metrics.Spacing.s3)
            }
            .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
        case .rule:
            Rectangle()
                .fill(Color.ds.separator)
                .frame(height: 1)
                .padding(.vertical, Metrics.Spacing.s2)
        case .table, .image, .attachment:
            EmptyView()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        let base: CGFloat = switch level {
        case 1: 23
        case 2: 19
        case 3: 17
        default: 15
        }
        return .system(size: (base * scale).rounded(), weight: .semibold, design: .serif)
    }

    private func inline(_ text: String) -> AttributedString {
        Self.displayInline(text)
    }

    /// Önizleme: etiketler ve `[[bağlantılar]]` tıklanabilir.
    static func displayInline(_ text: String) -> AttributedString {
        parse(NoteLinkSyntax.displayMarkdown(MarkdownNormalizer.emphasisSpacing(text)))
    }

    /// Dışa aktarma: bağlantılar düz metin.
    static func inline(_ text: String) -> AttributedString {
        parse(NoteLinkSyntax.plain(MarkdownNormalizer.emphasisSpacing(text)))
    }

    private static func parse(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Markdown tablosu: başlık satırı vurgulu, hücreler ince çizgilerle ayrılmış. Üzerine gelince "Düzenle".
struct MarkdownTableView: View {
    let table: MarkdownTable
    var onEdit: () -> Void = {}

    @Environment(\.editorTextScale) private var scale
    @State private var isHovered = false

    var body: some View {
        let table = table.normalized
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { index, cell in
                        cellView(cell, isHeader: true, isLast: index == table.columnCount - 1)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider().overlay(Color.ds.separator)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                            cellView(cell, isHeader: false, isLast: index == table.columnCount - 1)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                    .strokeBorder(isHovered ? Color.ds.accent.opacity(0.6) : Color.ds.separator, lineWidth: 1)
            }
            .padding(1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onEdit) {
                    Label("Tabloyu Düzenle", systemImage: "tablecells")
                        .textStyle(.caption)
                        .padding(.horizontal, Metrics.Spacing.s2)
                        .padding(.vertical, 3)
                        .background(Color.ds.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.ds.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(Metrics.Spacing.s1 + 2)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .accessibilityAction(named: Text("Tabloyu Düzenle"), onEdit)
    }

    /// Hücre sütun genişliğini doldurur ki dikey çizgiler tüm satırlarda hizalı olsun.
    private func cellView(_ text: String, isHeader: Bool, isLast: Bool) -> some View {
        Text(MarkdownBodyView.displayInline(text))
            .font(.system(size: (13 * scale).rounded(), weight: isHeader ? .semibold : .regular))
            .foregroundStyle(Color.ds.ink)
            .textSelection(.enabled)
            .padding(.horizontal, Metrics.Spacing.s3)
            .padding(.vertical, Metrics.Spacing.s2)
            .frame(minWidth: 72, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isHeader ? Color.ds.windowBg : Color.clear)
            .overlay(alignment: .trailing) {
                if !isLast {
                    Rectangle().fill(Color.ds.separator).frame(width: 1)
                }
            }
    }
}
