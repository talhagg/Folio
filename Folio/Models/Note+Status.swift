import Foundation

extension Note {
    /// Panoda sütun değiştirme. Görevi olan notta görevler buna göre işaretlenir; görevi olmayan notta
    /// durum elle saklanır. Bloke her notta işarettir.
    func setStatus(_ status: NoteStatus, now: Date = .now) {
        guard status != self.status else { return }
        if status == .blocked {
            isBlocked = true
            touch(now: now)
            return
        }
        statusOverrideRaw = nil
        let tasks = sortedTasks
        if tasks.isEmpty {
            statusOverrideRaw = status == .todo ? nil : status.rawValue
        } else {
            switch status {
            case .todo:
                tasks.forEach { $0.isDone = false }
            case .done:
                tasks.forEach { $0.isDone = true }
            case .doing:
                if tasks.allSatisfy(\.isDone) {
                    tasks.last?.isDone = false
                } else if !tasks.contains(where: \.isDone) {
                    tasks.first?.isDone = true
                }
            case .blocked:
                break
            }
        }
        touch(now: now)
    }
}
