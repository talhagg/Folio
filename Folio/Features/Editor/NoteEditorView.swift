import SwiftData
import SwiftUI

/// Not editörü: breadcrumb + tarihler, serif başlık, ilerleme kartı, görevler ve markdown gövde.
struct NoteEditorView: View {
    @Bindable var note: Note
    var now: Date = .now
    var onDeletePermanently: (() -> Void)? = nil
    /// Testler için: gövde düzenleme modunda açılır.
    var startsEditingBody = false

    @Environment(\.modelContext) private var context
    @FocusState private var focus: Field?
    @State private var isDuePopoverShown = false
    /// Gövde ham markdown olarak mı düzenleniyor; değilse biçimlendirilmiş gösterilir.
    @State private var isEditingBody = false
    @State private var tableSheet: TableSheet?
    @State private var editorController = MarkdownEditorController()
    @State private var currentLineStyle: MarkdownLineStyle = .body
    @State private var isAttachImporterShown = false
    @State private var isHeaderHovered = false
    /// Görevi olmayan notta "+ Görev" ile açılır.
    @State private var isAddingFirstTask = false
    @State private var attachError: String?
    @AppStorage(EditorTextSize.storageKey) private var textSizeRaw = EditorTextSize.normal.rawValue

    private enum Field: Hashable { case title }

    private enum TableSheet: Identifiable {
        case new
        case edit(ParsedBlock)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let block): "edit-\(block.lines.lowerBound)"
            }
        }
    }

    private var scale: CGFloat { (EditorTextSize(rawValue: textSizeRaw) ?? .normal).scale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let deletedAt = note.deletedAt {
                    trashBanner(deletedAt: deletedAt)
                        .padding(.bottom, Metrics.Spacing.s6)
                }

                Group {
                metaLine
                    .padding(.bottom, Metrics.Spacing.s3)

                TextField("Başlıksız not", text: editedBinding(\.title, field: .title), axis: .vertical)
                    .textFieldStyle(.plain)
                    .textStyle(.noteTitle, scale: scale)
                    .foregroundStyle(Color.ds.ink)
                    .focused($focus, equals: .title)
                    .onSubmit(beginEditingBody)
                    .padding(.bottom, Metrics.Spacing.s6)

                if note.taskCount > 0 || note.isBlocked {
                    ProgressCard(note: note)
                        .padding(.bottom, Metrics.Spacing.s3)
                }

                // Görev bölümü yalnızca görev varken (ya da "+ Görev" ile eklenirken) görünür.
                if note.taskCount > 0 || isAddingFirstTask {
                    TaskListView(note: note, now: now, startsAdding: isAddingFirstTask && note.taskCount == 0)
                        .padding(.leading, -18)
                        .padding(.bottom, Metrics.Spacing.s6)
                } else if note.isBlocked {
                    Spacer().frame(height: Metrics.Spacing.s3)
                }

                bodySection

                BacklinksView(note: note)
                    .padding(.top, Metrics.Spacing.s6)
                }
                // Çöpteki not salt okunurdur; düzenlemek için geri yüklenir.
                .disabled(note.isTrashed)
                .opacity(note.isTrashed ? 0.75 : 1)
            }
            .frame(maxWidth: Metrics.Layout.readingWidth, alignment: .leading)
            .padding(.horizontal, Metrics.Spacing.s10)
            .padding(.top, Metrics.Spacing.s6 + 4)
            .padding(.bottom, Metrics.Spacing.s10 * 2)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
        .background(Color.ds.surface)
        .environment(\.editorTextScale, scale)
        .onAppear {
            if startsEditingBody { isEditingBody = true }
            if note.title.isEmpty && !note.isTrashed && !startsEditingBody { focus = .title }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isEditingBody {
                EditorFormatBar(
                    controller: editorController,
                    currentStyle: currentLineStyle,
                    textSizeRaw: $textSizeRaw,
                    onInsertTable: { tableSheet = .new },
                    onAttachFile: { isAttachImporterShown = true },
                    onDone: endEditingBody
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: isEditingBody)
        // Yazma bitince geçici biçim hatalarını (ör. `**kalın **`) düzelt.
        .onChange(of: note.taskCount) { _, count in
            if count > 0 { isAddingFirstTask = false }
        }
        .onChange(of: isEditingBody) { wasEditing, isEditing in
            if wasEditing && !isEditing { normalizeBody() }
        }
        .onDisappear { if isEditingBody { normalizeBody() } }
        .fileImporter(isPresented: $isAttachImporterShown, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let markdown = urls.compactMap { attach(.file($0)) }
            guard !markdown.isEmpty else { return }
            if isEditingBody {
                editorController.insertBlock(markdown.joined(separator: "\n"))
            } else {
                setBody(MarkdownDocument.appendingBlock(markdown.joined(separator: "\n"), to: note.body))
            }
        }
        .alert("Eklenemedi", isPresented: Binding { attachError != nil } set: { if !$0 { attachError = nil } }) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(attachError ?? "")
        }
        .sheet(item: $tableSheet) { sheet in
            tableEditor(sheet)
        }
    }

    private func trashBanner(deletedAt: Date) -> some View {
        let days = Trash.daysRemaining(deletedAt: deletedAt, now: now)
        return HStack(spacing: Metrics.Spacing.s3) {
            Image(systemName: "trash")
                .foregroundStyle(Color.ds.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bu not Son Silinenler'de")
                    .textStyle(.headline)
                    .foregroundStyle(Color.ds.ink)
                Text(days == 0 ? "Bugün kalıcı olarak silinecek." : "\(days) gün sonra kalıcı olarak silinecek.")
                    .textStyle(.callout)
                    .foregroundStyle(Color.ds.inkSecondary)
            }
            Spacer(minLength: Metrics.Spacing.s2)
            if let onDeletePermanently {
                Button("Kalıcı Sil…", role: .destructive, action: onDeletePermanently)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.ds.statusBlocked)
            }
            Button("Geri Yükle") {
                withAnimation(.snappy) { context.restore(note) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ds.accent)
        }
        .padding(Metrics.Spacing.s3)
        .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous)
                .strokeBorder(Color.ds.separator.opacity(0.6), lineWidth: 1)
        }
    }

    /// Değeri yazar; `updatedAt`'i yalnızca alan odaktayken (kullanıcı yazarken) günceller.
    /// Metin alanlarının yükleme sırasında yaptığı yazmalar notu "düzenlenmiş" saymaz.
    private func editedBinding(_ keyPath: ReferenceWritableKeyPath<Note, String>, field: Field) -> Binding<String> {
        Binding {
            note[keyPath: keyPath]
        } set: { newValue in
            guard newValue != note[keyPath: keyPath] else { return }
            note[keyPath: keyPath] = newValue
            if focus == field { note.touch() }
        }
    }

    // MARK: - Üst satır

    /// Tek, sade satır: konum · düzenlenme · hedef. Oluşturulma ipucunda; boş eylemler yalnızca üzerine gelince.
    private var metaLine: some View {
        HStack(spacing: Metrics.Spacing.s2) {
            if let section = note.section, let notebook = section.notebook {
                HStack(spacing: 5) {
                    Circle().fill(notebook.color.color).frame(width: 6, height: 6)
                    Text("\(notebook.name) › \(section.name)")
                }
                .accessibilityElement(children: .combine)
                Text("·").foregroundStyle(Color.ds.inkTertiary)
            }

            Text("Düzenlendi \(DateGrouping.editorDateText(for: note.updatedAt, now: now))")
                .lineLimit(1)
                .help(Text("Oluşturuldu \(DateGrouping.editorDateText(for: note.createdAt, now: now))"))

            if note.dueDate != nil {
                Text("·").foregroundStyle(Color.ds.inkTertiary)
                dueDateButton
            }

            Spacer(minLength: Metrics.Spacing.s2)

            if !note.isTrashed {
                HStack(spacing: Metrics.Spacing.s3) {
                    if note.dueDate == nil { dueDateButton }
                    if note.taskCount == 0 && !isAddingFirstTask {
                        Button {
                            isAddingFirstTask = true
                        } label: {
                            Label("Görev", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.ds.inkTertiary)
                        .help(Text("Görev listesi ekle"))
                    }
                }
                .opacity(isHeaderHovered ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isHeaderHovered)
            }
        }
        .textStyle(.caption)
        .foregroundStyle(Color.ds.inkTertiary)
        .contentShape(Rectangle())
        .onHover { isHeaderHovered = $0 }
    }

    private var dueDateButton: some View {
        Button {
            isDuePopoverShown = true
        } label: {
            if let dueDate = note.dueDate {
                Label {
                    Text("Hedef: \(dueDate.formatted(.dateTime.day().month(.abbreviated)))")
                } icon: {
                    if note.isOverdue(now: now) { Image(systemName: "exclamationmark.circle") }
                }
                .labelStyle(DueLabelStyle())
                .foregroundStyle(note.isOverdue(now: now) ? Color.ds.statusBlocked : Color.ds.inkSecondary)
            } else {
                Label("Hedef", systemImage: "calendar")
                    .foregroundStyle(Color.ds.inkTertiary)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isDuePopoverShown, arrowEdge: .bottom) {
            DueDatePopover(date: note.dueDate) { newDate in
                note.dueDate = newDate
                note.touch()
                isDuePopoverShown = false
            }
        }
    }

    // MARK: - Tablolar

    @ViewBuilder
    private func tableEditor(_ sheet: TableSheet) -> some View {
        switch sheet {
        case .new:
            TableEditorView(table: .empty(columns: 3, rows: 3), isNew: true) { table in
                if isEditingBody {
                    // Yazarken imlecin olduğu yere.
                    editorController.insertBlock(table.markdown)
                    note.touch()
                } else {
                    setBody(MarkdownDocument.appendingBlock(table.markdown, to: note.body))
                }
            }
        case .edit(let parsed):
            if case .table(let table) = parsed.block {
                TableEditorView(table: table, isNew: false) { table in
                    setBody(MarkdownDocument.replacingLines(parsed.lines, in: note.body, with: table.markdown))
                } onDelete: {
                    setBody(MarkdownDocument.replacingLines(parsed.lines, in: note.body, with: ""))
                }
            }
        }
    }

    private func setBody(_ body: String) {
        note.body = body
        note.touch()
    }

    // MARK: - Gövde

    @ViewBuilder
    private var bodySection: some View {
        if isEditingBody {
            MarkdownTextEditor(
                text: bodyBinding,
                scale: scale,
                controller: editorController,
                onAttach: { attach($0) },
                onStyleChange: { currentLineStyle = $0 },
                onEndEditing: { isEditingBody = false }
            )
            .frame(minHeight: 120, alignment: .topLeading)
        } else {
            MarkdownBodyView(
                text: note.body,
                attachments: Dictionary((note.attachments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                onEditText: beginEditingBody,
                onEditTable: { tableSheet = .edit($0) }
            )
            .frame(minHeight: 120, alignment: .topLeading)
            // Önizlemeye bırakılan dosyalar notun sonuna eklenir.
            .dropDestination(for: URL.self) { urls, _ in
                let markdown = urls.filter(\.isFileURL).compactMap { attach(.file($0)) }
                guard !markdown.isEmpty, !note.isTrashed else { return false }
                setBody(MarkdownDocument.appendingBlock(markdown.joined(separator: "\n"), to: note.body))
                return true
            }
        }
    }

    /// Yazarken yapılan değişiklikler notu düzenlenmiş sayar.
    private var bodyBinding: Binding<String> {
        Binding {
            note.body
        } set: { newValue in
            guard newValue != note.body else { return }
            note.body = newValue
            if editorController.isFocused { note.touch() }
        }
    }

    private func beginEditingBody() {
        guard !note.isTrashed else { return }
        isEditingBody = true
        Task { @MainActor in editorController.focus() }
    }

    private func endEditingBody() {
        isEditingBody = false
    }

    private func normalizeBody() {
        let normalized = MarkdownNormalizer.emphasisSpacing(note.body)
        if normalized != note.body { note.body = normalized }
        // Metinden silinen eklerin dosyaları da silinir.
        context.removeUnreferencedAttachments(of: note)
    }

    /// Eki oluşturur; metne yazılacak markdown'ı döndürür.
    private func attach(_ input: AttachmentInput) -> String? {
        do {
            let attachment: NoteAttachment
            switch input {
            case .file(let url):
                attachment = try context.addAttachment(to: note, fileURL: url)
            case .image(let data, let type):
                let name = String(localized: "Görsel \(Date.now.formatted(.dateTime.day().month().year().hour().minute()))") + "." + (type.preferredFilenameExtension ?? "png")
                attachment = try context.addAttachment(to: note, data: data, fileName: name, type: type)
            }
            return attachment.markdown
        } catch {
            attachError = error.localizedDescription
            return nil
        }
    }
}

private struct DueLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

#if DEBUG
private struct EditorPreview: View {
    let container = SampleData.container()

    var body: some View {
        let note = try! container.mainContext.fetch(
            FetchDescriptor<Note>(predicate: #Predicate { $0.title == "Sprint 42 planlaması" })
        ).first!
        NoteEditorView(note: note)
            .modelContainer(container)
            .frame(width: 720, height: 720)
    }
}

#Preview("Light") { EditorPreview().preferredColorScheme(.light) }
#Preview("Dark") { EditorPreview().preferredColorScheme(.dark) }
#endif
