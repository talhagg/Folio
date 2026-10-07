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
