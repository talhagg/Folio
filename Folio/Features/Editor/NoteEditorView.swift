import SwiftData
import SwiftUI

/// Not editörü: breadcrumb + tarihler, serif başlık, ilerleme kartı, görevler ve markdown gövde.
struct NoteEditorView: View {
    @Bindable var note: Note
    var now: Date = .now
    var onDeletePermanently: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @FocusState private var focus: Field?
    @State private var isDuePopoverShown = false

    private enum Field: Hashable { case title, body }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let deletedAt = note.deletedAt {
                    trashBanner(deletedAt: deletedAt)
                        .padding(.bottom, Metrics.Spacing.s6)
                }

                Group {
                metaLine
                    .padding(.bottom, Metrics.Spacing.s4)

                TextField("Başlıksız not", text: editedBinding(\.title, field: .title), axis: .vertical)
                    .textFieldStyle(.plain)
                    .textStyle(.noteTitle)
                    .foregroundStyle(Color.ds.ink)
                    .focused($focus, equals: .title)
                    .onSubmit { focus = .body }
                    .padding(.bottom, Metrics.Spacing.s6)

                if note.taskCount > 0 || note.isBlocked {
                    ProgressCard(note: note)
                        .padding(.bottom, Metrics.Spacing.s6)
                }

                Text("Görevler")
                    .textStyle(.noteHeading)
                    .foregroundStyle(Color.ds.ink)
                    .padding(.bottom, Metrics.Spacing.s2)

                TaskListView(note: note, now: now)
                    .padding(.leading, -18)
                    .padding(.bottom, Metrics.Spacing.s6)

                bodyEditor
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
        .onAppear {
            if note.title.isEmpty && !note.isTrashed { focus = .title }
        }
        .toolbar {
            if !note.isTrashed {
            ToolbarItem {
                Button {
                    note.isPinned.toggle()
                    note.touch()
                } label: {
                    Label(note.isPinned ? "Sabitlemeyi Kaldır" : "Sabitle", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .help(Text(note.isPinned ? "Sabitlemeyi kaldır" : "Sabitle"))
            }
            }
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

    private var metaLine: some View {
        HStack(spacing: Metrics.Spacing.s4) {
            if let section = note.section, let notebook = section.notebook {
                HStack(spacing: 6) {
                    Circle().fill(notebook.color.color).frame(width: 7, height: 7)
                    Text(notebook.name)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.ds.inkTertiary)
                    Text(section.name)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(notebook.name), \(section.name)"))
            }

            Text("Oluşturuldu \(DateGrouping.editorDateText(for: note.createdAt, now: now)) · Düzenlendi \(DateGrouping.editorDateText(for: note.updatedAt, now: now))")
                .lineLimit(1)
                .truncationMode(.middle)

            dueDateButton

            Spacer(minLength: 0)
        }
        .textStyle(.caption)
        .foregroundStyle(Color.ds.inkSecondary)
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
                Text("Hedef ekle")
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

    // MARK: - Gövde

    /// TextEditor içeriğe göre büyüsün diye görünmez bir `Text` yüksekliği belirler.
    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            Text(note.body.isEmpty ? " " : note.body + "\n")
                .textStyle(.noteBody)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0)
                .accessibilityHidden(true)

            if note.body.isEmpty {
                Text("Yazmaya başlayın…")
                    .textStyle(.noteBody)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: editedBinding(\.body, field: .body))
                .textStyle(.noteBody)
                .foregroundStyle(Color.ds.ink)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($focus, equals: .body)
        }
        .padding(.horizontal, -5)
        .frame(minHeight: 120, alignment: .topLeading)
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
