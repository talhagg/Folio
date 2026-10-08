import Foundation
import SwiftData

/// Hazır not iskeletleri: başlık, markdown gövde ve başlangıç görevleri.
enum NoteTemplate: String, CaseIterable, Identifiable, Sendable {
    case meeting, sprint, daily, project, bug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meeting: String(localized: "Toplantı notu")
        case .sprint: String(localized: "Sprint planı")
        case .daily: String(localized: "Günlük")
        case .project: String(localized: "Proje planı")
        case .bug: String(localized: "Hata kaydı")
        }
    }

    var symbolName: String {
        switch self {
        case .meeting: "person.2"
        case .sprint: "flag.checkered"
        case .daily: "sun.max"
        case .project: "map"
        case .bug: "ladybug"
        }
    }

    func noteTitle(now: Date) -> String {
        let date = now.formatted(.dateTime.day().month(.abbreviated).year())
        return switch self {
        case .meeting: String(localized: "Toplantı – \(date)")
        case .sprint: String(localized: "Sprint planı")
        case .daily: String(localized: "Günlük – \(date)")
        case .project: String(localized: "Proje planı")
        case .bug: String(localized: "Hata: ")
        }
    }

    var body: String {
        switch self {
        case .meeting:
            """
            ## Katılımcılar

            - 

            ## Gündem

            1. 

            ## Kararlar

            - 

            ## Notlar

            """
        case .sprint:
            """
            ## Hedef



            ## Kapsam

            | İş | Sahip | Tahmin |
            | --- | --- | --- |
            |  |  |  |

            ## Riskler

            - 
            """
        case .daily:
            """
            ## Bugün

            - 

            ## Notlar



            ## Yarın

            - 
            """
        case .project:
            """
            ## Amaç



            ## Kapsam

            - 

            ## Kilometre taşları

            | Tarih | Hedef |
            | --- | --- |
            |  |  |

            ## Riskler

            - 
            """
        case .bug:
            """
            ## Ne oldu?



            ## Adımlar

            1. 

            ## Beklenen



            ## Gerçekleşen



            ## Ortam

            - Sürüm: 
            - Cihaz: 
            """
        }
    }

    var tasks: [String] {
        switch self {
        case .meeting: [String(localized: "Toplantı notlarını paylaş")]
        case .sprint: [String(localized: "Kapsamı netleştir"), String(localized: "Görevleri dağıt"), String(localized: "Demo hazırla")]
        case .daily: []
        case .project: [String(localized: "Paydaşları belirle"), String(localized: "Zaman çizelgesi çıkar")]
        case .bug: [String(localized: "Yeniden üret"), String(localized: "Düzelt"), String(localized: "Test et")]
        }
    }
}

extension ModelContext {
    /// Şablondan not oluşturur.
    @discardableResult
    func addNote(from template: NoteTemplate, in section: NoteSection, now: Date = .now) -> Note {
        let note = addNote(in: section, title: template.noteTitle(now: now), now: now)
        note.body = template.body
        for (index, text) in template.tasks.enumerated() {
            let task = NoteTask(text: text, sortIndex: Double(index))
            insert(task)
            task.note = note
        }
        return note
    }
}
