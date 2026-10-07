import Foundation
import SwiftData

/// Son Silinenler: notlar önce buraya taşınır, `retentionDays` sonra kalıcı silinir.
enum Trash {
    static let retentionDays = 90

    static func expiryDate(for deletedAt: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: retentionDays, to: deletedAt) ?? deletedAt
    }

    /// Kalıcı silinmeye kalan tam gün (en az 0).
    static func daysRemaining(deletedAt: Date, now: Date, calendar: Calendar = .current) -> Int {
        let expiry = calendar.startOfDay(for: expiryDate(for: deletedAt, calendar: calendar))
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: today, to: expiry).day ?? 0)
    }
}

extension ModelContext {
    func moveToTrash(_ note: Note, now: Date = .now) {
        guard !note.isTrashed else { return }
        note.trashedFromPath = note.locationPath
        note.deletedAt = now
    }

    /// Notu çöpten çıkarır. Bölümü artık yoksa varsayılan bölüme konur.
    func restore(_ note: Note, now: Date = .now) {
        guard note.isTrashed else { return }
        if note.section == nil {
            note.section = sectionForNewNote(selection: nil, now: now)
        }
        note.deletedAt = nil
        note.trashedFromPath = nil
        note.touch(now: now)
    }

    func deletePermanently(_ note: Note) {
        // `delete` ilişkiyi ancak kayıtta temizler; sayaçlar hemen güncellensin diye önce bağı kopar.
        note.section = nil
        delete(note)
    }

    var trashedNotes: [Note] {
        (try? fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
    }

    func emptyTrash() {
        trashedNotes.forEach(deletePermanently)
    }

    /// Süresi dolan notları kalıcı siler; silinen sayısını döndürür.
    @discardableResult
    func purgeExpiredTrash(now: Date = .now, calendar: Calendar = .current) -> Int {
        let expired = trashedNotes.filter { note in
            guard let deletedAt = note.deletedAt else { return false }
            return Trash.expiryDate(for: deletedAt, calendar: calendar) <= now
        }
        expired.forEach(deletePermanently)
        return expired.count
    }

    /// Bölümü siler; notları (çöptekiler dahil) kaybolmasın diye Son Silinenler'de kalır.
    func trashSection(_ section: NoteSection, now: Date = .now) {
        for note in section.notes ?? [] {
            moveToTrash(note, now: now)
            note.section = nil
        }
        section.notebook = nil
        delete(section)
    }

    func trashNotebook(_ notebook: Notebook, now: Date = .now) {
        for section in notebook.sections ?? [] {
            trashSection(section, now: now)
        }
        delete(notebook)
    }
}
