import Foundation
import SwiftData

/// Kenar çubuğu seçimi + tarih filtresi + arama metninden not sorgusu üreten saf tip.
///
/// `descriptor` veritabanında ifade edilebilen kısmı (tarih aralığı, bölüm, sabitlenme) daraltır;
/// `matches` tüm kuralları (hesaplanan durum ve görev metni araması dahil) bellekte uygular.
struct NoteFilter {
    var selection: SidebarSelection?
    var dateFilter: DateFilter = .all
    var searchText: String = ""
    var now: Date = .now
    var calendar: Calendar = .current

    var dateInterval: DateInterval? { dateFilter.interval(now: now, calendar: calendar) }

    var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isSearching: Bool { !trimmedSearch.isEmpty }

    var isTrash: Bool { selection == .trash }

    /// Arama globaldir: metin varken kenar çubuğu seçimi yok sayılır (tarih filtresi geçerli kalır).
    /// Son Silinenler'deyken arama yalnızca çöpte yapılır.
    var effectiveSelection: SidebarSelection? { isSearching && !isTrash ? nil : selection }

    var descriptor: FetchDescriptor<Note> {
        FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    }

    var predicate: Predicate<Note> {
        let start = dateInterval?.start ?? .distantPast
        let end = dateInterval?.end ?? .distantFuture
        // `section?.notebook?.id` gibi iki seviyeli zincir SQL'e çevrilemiyor; defter seçimi `matches`'te uygulanır.
        switch effectiveSelection {
        case .trash:
            return #Predicate<Note> { note in
                note.updatedAt >= start && note.updatedAt < end && note.deletedAt != nil
            }
        case .section(let id):
            return #Predicate<Note> { note in
                note.updatedAt >= start && note.updatedAt < end && note.deletedAt == nil && note.section?.id == id
            }
        case .smart(.pinned):
            return #Predicate<Note> { note in
                note.updatedAt >= start && note.updatedAt < end && note.deletedAt == nil && note.isPinned
            }
        default:
            return #Predicate<Note> { note in
                note.updatedAt >= start && note.updatedAt < end && note.deletedAt == nil
            }
        }
    }

    func matches(_ note: Note) -> Bool {
        if let dateInterval, !(note.updatedAt >= dateInterval.start && note.updatedAt < dateInterval.end) {
            return false
        }
        if let selection = effectiveSelection {
            if !selection.includes(note, now: now, calendar: calendar) { return false }
        } else if note.isTrashed {
            return false
        }
        return Self.matchesSearch(note, query: trimmedSearch)
    }

    func apply(to notes: [Note]) -> [Note] {
        notes.filter(matches).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Başlık, gövde ve görev metinlerinde arar (`SearchHighlighter.contains`: harf/aksan duyarsız, i/ı eşit).
    /// Boş sorgu her notla eşleşir.
    static func matchesSearch(_ note: Note, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return SearchHighlighter.contains(note.title, query)
            || SearchHighlighter.contains(note.body, query)
            || (note.tasks ?? []).contains { SearchHighlighter.contains($0.text, query) }
    }
}
