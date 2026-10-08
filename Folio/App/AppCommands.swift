import AppKit
import SwiftUI

/// Menü komutları: ⌘N yeni not, ⇧⌘N yeni defter, ⌘⌫ sil (onaylı), ⌘P sabitle, ⌘1–4 akıllı filtreler, ⌘F ara.
struct AppCommands: Commands {
    @FocusedValue(\.noteActions) private var actions
    @AppStorage(EditorTextSize.storageKey) private var textSizeRaw = EditorTextSize.normal.rawValue

    private var textSize: EditorTextSize { EditorTextSize(rawValue: textSizeRaw) ?? .normal }
    @Bindable private var theme = ThemeStore.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Yeni Not") { actions?.newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("Yeni Defter") { actions?.newNotebook() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Menu("Şablondan Yeni Not") {
                ForEach(NoteTemplate.allCases) { template in
                    Button(template.title) { actions?.newFromTemplate(template) }
                }
            }
            .disabled(actions == nil)
            Button("Yeni Yapışkan Not") { actions?.newSticky() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(actions == nil)
        }

        CommandGroup(after: .importExport) {
            Button("Dosyadan İçe Aktar…") { actions?.importFiles() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("URL'den İçe Aktar…") { actions?.importURL() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Divider()
            Menu("Notu Dışa Aktar") {
                ForEach(ExportFormat.allCases) { format in
                    Button("\(format.title)…") { actions?.exportNote?(format) }
                }
            }
            .disabled(actions?.exportNote == nil)
            Button("PDF Olarak Dışa Aktar…") { actions?.exportNote?(.pdf) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(actions?.exportNote == nil)
            Button("Tüm Notları Dışa Aktar (JSON)…") { actions?.exportAll() }
                .disabled(actions == nil)
        }

        // ⌘P sabitleme için kullanılıyor; yazdırma yok.
        CommandGroup(replacing: .printItem) {}

        // Standart Bul menüsü yerine notlarda arama (⌘F).
        CommandGroup(replacing: .textEditing) {
            Button("Notlarda Ara") { actions?.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Not") {
            Button("Yapışkan Not Olarak Aç") { actions?.openSticky?() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(actions?.openSticky == nil)
            Divider()
            Button(actions?.isPinned == true ? "Sabitlemeyi Kaldır" : "Sabitle") { actions?.togglePin?() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions?.togglePin == nil)
            Divider()
            Button(actions?.isTrash == true ? "Kalıcı Olarak Sil…" : "Son Silinenlere Taşı…") {
                // Metin düzenlenirken ⌘⌫ satır başına kadar silme kısayoludur; onu metne bırak.
                if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                    textView.deleteToBeginningOfLine(nil)
                    return
                }
                actions?.deleteNote?()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(actions?.deleteNote == nil)
        }

        CommandGroup(before: .toolbar) {
            Picker("Görünüm", selection: $theme.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Vurgu Rengi", selection: $theme.accent) {
                ForEach(AccentTheme.allCases) { Text($0.title).tag($0) }
            }
            Divider()
        }

        CommandGroup(after: .toolbar) {
            Button("Yazıyı Büyüt") { if let size = textSize.larger { textSizeRaw = size.rawValue } }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(textSize.larger == nil)
            Button("Yazıyı Küçült") { if let size = textSize.smaller { textSizeRaw = size.rawValue } }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(textSize.smaller == nil)
            Button("Gerçek Boyut") { textSizeRaw = EditorTextSize.normal.rawValue }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(textSize == .normal)
            Divider()
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(SmartFilter.allCases.enumerated()), id: \.element) { index, filter in
                Button(filter.title) { actions?.selectSmartFilter(filter) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(actions == nil)
            }
        }
    }
}
