import AppKit
import SwiftUI

/// Menü komutları: ⌘N yeni not, ⇧⌘N yeni defter, ⌘⌫ sil (onaylı), ⌘P sabitle, ⌘1–4 akıllı filtreler, ⌘F ara.
struct AppCommands: Commands {
    @FocusedValue(\.noteActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Yeni Not") { actions?.newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("Yeni Defter") { actions?.newNotebook() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }

        // ⌘P sabitleme için kullanılıyor; yazdırma yok.
        CommandGroup(replacing: .printItem) {}

        // Standart Bul menüsü yerine notlarda arama (⌘F).
        CommandGroup(replacing: .textEditing) {
            Button("Notlarda Ara") { SearchFieldFocuser.focus() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Not") {
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

/// macOS 14'te SwiftUI arama alanına odak veren bir API yok (`searchFocused` macOS 15+);
/// bu yüzden toolbar'daki arama öğesine AppKit üzerinden ulaşılır.
@MainActor
enum SearchFieldFocuser {
    static func focus(in window: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow) {
        guard let window else { return }
        if let item = window.toolbar?.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return
        }
        // Yedek: başlık çubuğu hiyerarşisindeki ilk NSSearchField.
        let root = window.contentView?.superview ?? window.contentView
        if let field = root.flatMap(firstSearchField(in:)) {
            window.makeFirstResponder(field)
        }
    }

    private static func firstSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = firstSearchField(in: subview) { return field }
        }
        return nil
    }
}
