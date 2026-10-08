import SwiftUI

/// Pencerenin menü komutlarına açtığı eylemler (`focusedSceneValue`).
struct NoteCommandActions {
    var newNote: @MainActor () -> Void
    var newNotebook: @MainActor () -> Void
    /// `nil` → seçili not yok, komut devre dışı.
    var deleteNote: (@MainActor () -> Void)?
    var togglePin: (@MainActor () -> Void)?
    var isPinned = false
    var isTrash = false
    var selectSmartFilter: @MainActor (SmartFilter) -> Void
    var focusSearch: @MainActor () -> Void
    var importFiles: @MainActor () -> Void
    var importURL: @MainActor () -> Void
    /// `nil` → seçili not yok.
    var exportNote: (@MainActor (ExportFormat) -> Void)?
    var exportAll: @MainActor () -> Void
    /// `nil` → seçili not yok.
    var openSticky: (@MainActor () -> Void)?
    var newSticky: @MainActor () -> Void
    var newFromTemplate: @MainActor (NoteTemplate) -> Void
}

struct NoteCommandActionsKey: FocusedValueKey {
    typealias Value = NoteCommandActions
}

extension FocusedValues {
    var noteActions: NoteCommandActions? {
        get { self[NoteCommandActionsKey.self] }
        set { self[NoteCommandActionsKey.self] = newValue }
    }
}
