import Foundation
import SwiftData

/// Görev ekleme/silme/sıralama. Sıra `sortIndex` ile tutulur ve her değişiklikte 0…n olarak yeniden yazılır.
extension Note {
    @discardableResult
    func addTask(text: String = "", after anchor: NoteTask? = nil, in context: ModelContext, now: Date = .now) -> NoteTask {
        let task = NoteTask(text: text)
        context.insert(task)
        task.note = self
        var ordered = sortedTasks.filter { $0 !== task }
        let insertionIndex = anchor.flatMap { anchor in ordered.firstIndex { $0 === anchor } }.map { $0 + 1 } ?? ordered.count
        ordered.insert(task, at: insertionIndex)
        Self.reindex(ordered)
        touch(now: now)
        return task
    }

    func removeTask(_ task: NoteTask, in context: ModelContext, now: Date = .now) {
        let remaining = sortedTasks.filter { $0 !== task }
        // `delete` ilişkiyi ancak kayıtta temizler; listeden hemen düşsün diye önce bağı kopar.
        task.note = nil
        context.delete(task)
        Self.reindex(remaining)
        touch(now: now)
    }

    /// `taskID`'yi `targetID`'nin önüne taşır; `targetID == nil` ise sona.
    func moveTask(_ taskID: UUID, before targetID: UUID?, now: Date = .now) {
        let ids = Reordering.move(sortedTasks.map(\.id), item: taskID, before: targetID)
        let byID = Dictionary(uniqueKeysWithValues: sortedTasks.map { ($0.id, $0) })
        Self.reindex(ids.compactMap { byID[$0] })
        touch(now: now)
    }

    func toggle(_ task: NoteTask, now: Date = .now) {
        task.isDone.toggle()
        touch(now: now)
    }

    private static func reindex(_ tasks: [NoteTask]) {
        for (index, task) in tasks.enumerated() where task.sortIndex != Double(index) {
            task.sortIndex = Double(index)
        }
    }
}

enum Reordering {
    /// Saf sıralama: `item`'ı listeden çıkarıp `target`'ın önüne (yoksa sona) koyar.
    static func move<ID: Equatable>(_ ids: [ID], item: ID, before target: ID?) -> [ID] {
        guard ids.contains(item), item != target else { return ids }
        var result = ids.filter { $0 != item }
        let index = target.flatMap { result.firstIndex(of: $0) } ?? result.count
        result.insert(item, at: index)
        return result
    }
}
