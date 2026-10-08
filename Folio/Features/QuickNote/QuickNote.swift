import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI

/// Pencere dışından (menü çubuğu, genel kısayol) yapılan eylemler.
@MainActor
final class QuickActions {
    static let shared = QuickActions()
    static let sectionKey = "quicknote.section"
    static let hotKeyEnabledKey = "quicknote.hotkey"

    /// Menü çubuğu etiketi ya da ana pencere açılınca kaydedilir.
    var openWindow: OpenWindowAction?
    var container: ModelContainer?

    /// Hızlı notların gideceği bölüm (seçilmediyse varsayılan bölüm).
    func targetSection(in context: ModelContext) -> NoteSection {
        if let raw = UserDefaults.standard.string(forKey: Self.sectionKey), let id = UUID(uuidString: raw),
           let section = context.first(NoteSection.self, id: id) {
            return section
        }
        return context.sectionForNewNote(selection: nil)
    }

    /// Metinden not: ilk satır başlık, kalanı gövde.
    @discardableResult
    func addQuickNote(text: String, in context: ModelContext) -> Note {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let note = context.addNote(in: targetSection(in: context), title: lines.first ?? "")
        note.body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        return note
    }

    func newSticky() {
        guard let context = container?.mainContext else { return }
        let note = context.addNote(in: targetSection(in: context))
        try? context.save()
        openSticky(note.id)
    }

    func openSticky(_ id: UUID) {
        NSApp.activate()
        openWindow?(id: StickyNote.windowID, value: id)
    }

    func openMain(_ link: AppLink? = nil) {
        NSApp.activate()
        if !NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }) {
            openWindow?(id: "main")
        }
        if let link { AppNavigator.shared.open(link) }
    }
}

/// Genel kısayol: ⌃⌥N her uygulamadan yeni yapışkan not açar (Carbon; erişilebilirlik izni gerekmez).
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKey == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { QuickActions.shared.newSticky() } }
            return noErr
        }, 1, &eventType, nil, &handler)
        let identifier = EventHotKeyID(signature: OSType(0x464F_4C49), id: 1) // "FOLI"
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}

/// Menü çubuğu simgesi; görününce pencere açma eylemini kaydeder.
struct QuickNoteMenuLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "note.text.badge.plus")
            .onAppear { QuickActions.shared.openWindow = openWindow }
    }
}

/// Menü çubuğu paneli: hızlı not, bölüm seçimi, son notlar.
struct QuickNoteView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Notebook.sortIndex) private var notebooks: [Notebook]
    @AppStorage(QuickActions.sectionKey) private var sectionRaw = ""
    @State private var text = ""
    @State private var savedMessage: String?
    @FocusState private var isFocused: Bool

    private var targetName: String {
        let section = QuickActions.shared.targetSection(in: context)
        return [section.notebook?.name, section.name].compactMap { $0 }.joined(separator: " › ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            HStack {
                Text("Hızlı Not")
                    .textStyle(.headline)
                    .foregroundStyle(Color.ds.ink)
                Spacer()
                Text("⌃⌥N")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .help(Text("Her uygulamadan yeni yapışkan not"))
            }

            TextField("Ne düşünüyorsunuz? İlk satır başlık olur.", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(3...8)
                .focused($isFocused)
                .padding(Metrics.Spacing.s2 + 2)
                .background(Color.ds.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.md + 2, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.Radius.md + 2, style: .continuous)
                        .strokeBorder(isFocused ? Color.ds.accent.opacity(0.7) : Color.ds.separator, lineWidth: 1)
                }

            HStack(spacing: Metrics.Spacing.s2) {
                Menu {
                    ForEach(notebooks) { notebook in
                        Section(notebook.name) {
                            ForEach(notebook.sortedSections, id: \.id) { section in
                                Button(section.name) { sectionRaw = section.id.uuidString }
                            }
                        }
                    }
                } label: {
                    Label(targetName, systemImage: "folder")
                        .textStyle(.caption)
                        .lineLimit(1)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(Color.ds.inkSecondary)
                .fixedSize()
                .help(Text("Notun kaydedileceği bölüm"))
                Spacer()
                Button {
                    guard let note = save() else { return }
                    openWindow(id: StickyNote.windowID, value: note.id)
                } label: {
                    Image(systemName: "note.text")
                }
                .help(Text("Kaydet ve yapışkan not olarak aç"))
                .disabled(isEmpty)
                Button("Kaydet") { _ = save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ds.accent)
                    .disabled(isEmpty)
            }

            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.accent)
                    .transition(.opacity)
            }

            Divider()

            Text("Son notlar")
                .textStyle(.sectionLabel)
                .foregroundStyle(Color.ds.inkTertiary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(notes.filter { !$0.isTrashed }.prefix(5)) { note in
                    RecentNoteRow(note: note) {
                        QuickActions.shared.openMain(.note(note.id))
                    } onSticky: {
                        openWindow(id: StickyNote.windowID, value: note.id)
                    }
                }
            }

            Divider()

            HStack {
                Button("Folio'yu Aç") { QuickActions.shared.openMain() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Yeni Yapışkan Not") { QuickActions.shared.newSticky() }
                    .buttonStyle(.borderless)
            }
            .textStyle(.callout)
        }
        .padding(Metrics.Spacing.s4)
        .frame(width: 340)
        .tint(Color.ds.accent)
        .onAppear {
            QuickActions.shared.openWindow = openWindow
            isFocused = true
        }
    }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func save() -> Note? {
        guard !isEmpty else { return nil }
        let note = QuickActions.shared.addQuickNote(text: text, in: context)
        text = ""
        withAnimation { savedMessage = String(localized: "\(targetName) bölümüne kaydedildi") }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { savedMessage = nil }
        }
        return note
    }
}

private struct RecentNoteRow: View {
    let note: Note
    let onOpen: () -> Void
    let onSticky: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Metrics.Spacing.s2) {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.ds.inkTertiary)
            Text(note.title.isEmpty ? String(localized: "Başlıksız not") : note.title)
                .textStyle(.body)
                .foregroundStyle(Color.ds.ink)
                .lineLimit(1)
            Spacer()
            if isHovered {
                Button(action: onSticky) {
                    Image(systemName: "note.text").foregroundStyle(Color.ds.inkSecondary)
                }
                .buttonStyle(.plain)
                .help(Text("Yapışkan not olarak aç"))
            }
        }
        .padding(.horizontal, Metrics.Spacing.s2)
        .frame(height: 26)
        .rowBackground(isSelected: false)
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
    }
}
