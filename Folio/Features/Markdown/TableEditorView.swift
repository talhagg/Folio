import SwiftUI

/// Tablo oluşturma/düzenleme sayfası: hücreler doğrudan düzenlenir; satır ve sütun eklenip silinir.
struct TableEditorView: View {
    let isNew: Bool
    let onSave: (MarkdownTable) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var header: [String]
    @State private var rows: [[String]]

    init(table: MarkdownTable, isNew: Bool, onSave: @escaping (MarkdownTable) -> Void, onDelete: (() -> Void)? = nil) {
        let table = table.normalized
        self._header = State(initialValue: table.header)
        self._rows = State(initialValue: table.rows)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var columnCount: Int { header.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            HStack {
                Text(isNew ? "Tablo Ekle" : "Tabloyu Düzenle")
                    .textStyle(.windowTitle)
                    .foregroundStyle(Color.ds.ink)
                Spacer()
                Text("\(rows.count) satır · \(columnCount) sütun")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
            }

            GeometryReader { proxy in
            let cellWidth = max(170, (proxy.size.width - 2 * Metrics.Spacing.s3 - 28 - CGFloat(columnCount) * 6) / CGFloat(max(columnCount, 1)))
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 22, height: 1)
                        ForEach(0..<columnCount, id: \.self) { column in
                            columnControls(column)
                        }
                    }
                    GridRow {
                        Text("").frame(width: 20)
                        ForEach(0..<columnCount, id: \.self) { column in
                            cellField($header[column], isHeader: true, width: cellWidth)
                        }
                    }
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            Button {
                                rows.remove(at: row)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Color.ds.inkTertiary)
                            }
                            .buttonStyle(.plain)
                            .disabled(rows.count <= 1)
                            .help(Text("Satırı sil"))
                            ForEach(0..<columnCount, id: \.self) { column in
                                cellField($rows[row][column], isHeader: false, width: cellWidth)
                            }
                        }
                    }
                }
                .padding(Metrics.Spacing.s3)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.lg).strokeBorder(Color.ds.separator, lineWidth: 1))

            HStack(spacing: Metrics.Spacing.s2) {
                Button {
                    rows.append(Array(repeating: "", count: columnCount))
                } label: {
                    Label("Satır Ekle", systemImage: "plus")
                }
                Button {
                    header.append(String(localized: "Sütun \(columnCount + 1)"))
                    rows = rows.map { $0 + [""] }
                } label: {
                    Label("Sütun Ekle", systemImage: "plus")
                }
                Spacer()
                if let onDelete {
                    Button("Tabloyu Sil", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Ekle" : "Kaydet") {
                    onSave(MarkdownTable(header: header, rows: rows))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.ds.accent)
            }
        }
        .padding(Metrics.Spacing.s6)
        .frame(minWidth: 820, idealWidth: 920, maxWidth: .infinity, minHeight: 540, idealHeight: 620, maxHeight: .infinity)
    }

    private func columnControls(_ column: Int) -> some View {
        HStack {
            Spacer()
            Button {
                header.remove(at: column)
                rows = rows.map { row in
                    var row = row
                    row.remove(at: column)
                    return row
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(Color.ds.inkTertiary)
            }
            .buttonStyle(.plain)
            .disabled(columnCount <= 1)
            .help(Text("Sütunu sil"))
        }
    }

    private func cellField(_ text: Binding<String>, isHeader: Bool, width: CGFloat) -> some View {
        TextField(isHeader ? "Başlık" : "", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: isHeader ? .semibold : .regular))
            .padding(.horizontal, Metrics.Spacing.s3)
            .padding(.vertical, Metrics.Spacing.s2)
            .frame(width: width)
            .background(Color.ds.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.sm).strokeBorder(Color.ds.separator, lineWidth: 1))
    }
}
