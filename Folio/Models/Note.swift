import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    /// Markdown metin.
    var body: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var dueDate: Date?
    var isPinned: Bool = false
    /// Yalnızca `"blocked"` saklanır; diğer durumlar görevlerden hesaplanır.
    var statusOverrideRaw: String?
    var section: NoteSection?
    /// Son Silinenler'e taşındığı an; `nil` ise not etkin. 90 gün sonra kalıcı silinir.
    var deletedAt: Date?
    /// Çöpe atıldığı yer ("İş › Sprint 42"); bölüm sonradan silinse de gösterilebilsin diye.
    var trashedFromPath: String?

    @Relationship(deleteRule: .cascade, inverse: \NoteTask.note)
    var tasks: [NoteTask]? = []

    init(
        title: String,
        body: String = "",
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        dueDate: Date? = nil,
        isPinned: Bool = false
    ) {
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.dueDate = dueDate
        self.isPinned = isPinned
    }

    var sortedTasks: [NoteTask] {
        (tasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var doneTaskCount: Int { (tasks ?? []).filter(\.isDone).count }
    var taskCount: Int { tasks?.count ?? 0 }

    /// `done / total`; görev yoksa `nil`.
    var progress: Double? {
        let total = taskCount
        guard total > 0 else { return nil }
        return Double(doneTaskCount) / Double(total)
    }

    var status: NoteStatus {
        NoteStatus.resolve(progress: progress, overrideRaw: statusOverrideRaw)
    }

    var isBlocked: Bool {
        get { statusOverrideRaw == NoteStatus.blocked.rawValue }
        set { statusOverrideRaw = newValue ? NoteStatus.blocked.rawValue : nil }
    }

    func isOverdue(now: Date = .now) -> Bool {
        guard let dueDate else { return false }
        return dueDate < now && status != .done
    }

    var notebook: Notebook? { section?.notebook }

    var isTrashed: Bool { deletedAt != nil }

    /// "İş › Sprint 42"
    var locationPath: String? {
        guard let section else { return trashedFromPath }
        guard let notebook = section.notebook else { return section.name }
        return "\(notebook.name) › \(section.name)"
    }

    /// Her düzenlemeden sonra çağrılır.
    func touch(now: Date = .now) {
        updatedAt = now
    }
}
