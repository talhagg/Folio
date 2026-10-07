#if DEBUG
import Foundation
import SwiftData

/// Preview ve testler için örnek veri: 4 defter, 15 etkin not + Son Silinenler'de 2 not. Tarihler `now`'a göre görelidir.
@MainActor
enum SampleData {
    /// Örnek veriyle doldurulmuş bellek içi container.
    static func container(now: Date = .now) -> ModelContainer {
        let container = ModelContainer.folioInMemory()
        insert(into: container.mainContext, now: now)
        return container
    }

    /// Depo boşsa örnek veriyi ekler.
    static func seedIfEmpty(_ context: ModelContext, now: Date = .now) {
        let count = (try? context.fetchCount(FetchDescriptor<Notebook>())) ?? 0
        guard count == 0 else { return }
        insert(into: context, now: now)
    }

    private struct NoteSpec {
        var title: String
        var body = ""
        /// `now`'dan kaç saat önce düzenlendi.
        var hoursAgo: Double
        var dueInDays: Double? = nil
        var pinned = false
        var blocked = false
        var tasks: [(String, Bool)] = []
    }

    static func insert(into context: ModelContext, now: Date = .now) {
        let data: [(String, GroupColor, [(String, [NoteSpec])])] = [
            ("İş", .clay, [
                ("Sprint 42", [
                    NoteSpec(
                        title: "Sprint 42 planlaması",
                        body: "Login ekranı tasarımı bitti, API bağlantısı ve hata durumları kaldı.\n\nAuth akışı `AuthService` üzerinden ilerliyor. Token yenileme için interceptor eklenecek; refresh başarısız olursa kullanıcı login ekranına düşmeli.\n\n## Sorumlular\n\n| İş | Sahip | Durum |\n| --- | --- | --- |\n| API bağlantısı | Talha | Devam ediyor |\n| Hata ekranları | Ayşe | Bekliyor |\n| Erişilebilirlik | Can | Planlandı |",
                        hoursAgo: 0.5, dueInDays: 3, pinned: true,
                        tasks: [
                            ("Login ekranı tasarımı", true), ("Form doğrulama ve hata mesajları", true),
                            ("Keychain ile oturum saklama", true), ("Analytics olayları", true),
                            ("Tasarım incelemesi", true), ("API bağlantısı", false),
                            ("Boş ve hata durum ekranları", false), ("Erişilebilirlik turu", false),
                        ]
                    ),
                    NoteSpec(
                        title: "Mimari kararlar — ADR 7",
                        body: "Navigation için coordinator yerine NavigationStack.",
                        hoursAgo: 4,
                        tasks: [("Alternatifleri yaz", true), ("Ekiple tartış", false), ("Kararı kaydet", false), ("Örnek PR", false)]
                    ),
                    NoteSpec(title: "Retro notları", body: "İyi giden: eşli programlama. Geliştirilecek: PR inceleme süresi.", hoursAgo: 72),
                ]),
                ("Toplantılar", [
                    NoteSpec(
                        title: "Haftalık 1:1",
                        body: "Kariyer hedefleri ve sprint yükü konuşuldu.",
                        hoursAgo: 26,
                        tasks: [("Hedefleri güncelle", true), ("Eğitim bütçesi", true), ("Geri bildirim notları", true)]
                    ),
                    NoteSpec(title: "Ürün sync", body: "Q4 yol haritası öncelikleri.", hoursAgo: 24 * 10),
                ]),
            ]),
            ("FinTrack", .amber, [
                ("Genel", [
                    NoteSpec(
                        title: "Bütçe kategorileri",
                        body: "Offline-first senkronizasyon için çakışma kuralları.",
                        hoursAgo: 27,
                        tasks: [("Kategori listesi", true), ("İkonlar", true), ("Çakışma kuralları", true), ("Testler", true)]
                    ),
                    NoteSpec(
                        title: "App Store yayın listesi",
                        body: "Ekran görüntüleri, gizlilik etiketi, TestFlight notları.",
                        hoursAgo: 50, dueInDays: -1,
                        tasks: [
                            ("Ekran görüntüleri", true), ("Gizlilik etiketi", true), ("TestFlight notları", true),
                            ("Açıklama metni", false), ("Anahtar kelimeler", false), ("Destek URL'si", false),
                            ("Fiyatlandırma", false), ("Yaş sınırı", false), ("İnceleme notu", false), ("Yayın", false),
                        ]
                    ),
                    NoteSpec(
                        title: "Offline senkron",
                        body: "Sunucu tarafı API hazır olmadan ilerleyemiyor.",
                        hoursAgo: 24 * 20, blocked: true,
                        tasks: [("Çakışma modeli", true), ("Kuyruk", false), ("Yeniden deneme", false)]
                    ),
                ]),
            ]),
            ("Öğrenme", .teal, [
                ("Swift", [
                    NoteSpec(title: "Swift Concurrency notları", body: "Actor izolasyonu, Sendable ve MainActor örnekleri.", hoursAgo: 52),
                    NoteSpec(title: "SwiftData + CloudKit kuralları", body: "Tüm alanlar optional ya da default değerli; unique yok.", hoursAgo: 24 * 12, pinned: true),
                ]),
                ("Kitaplar", [
                    NoteSpec(
                        title: "Designing Data-Intensive Applications",
                        body: "Bölüm notları.",
                        hoursAgo: 24 * 40,
                        tasks: (1...12).map { ("Bölüm \($0)", $0 <= 7) }
                    ),
                ]),
            ]),
            ("Kişisel", .moss, [
                ("Ev", [
                    NoteSpec(
                        title: "Market listesi",
                        hoursAgo: 2,
                        tasks: [("Süt", true), ("Ekmek", true), ("Kahve", false), ("Meyve", false), ("Deterjan", false)]
                    ),
                    NoteSpec(title: "Tatil planı", body: "Ege kıyısı, Mayıs başı.", hoursAgo: 24 * 6, dueInDays: 30),
                ]),
                ("Sağlık", [
                    NoteSpec(
                        title: "Koşu programı",
                        body: "10K hazırlığı.",
                        hoursAgo: 24 * 25,
                        tasks: (1...8).map { ("Hafta \($0)", $0 <= 3) }
                    ),
                    NoteSpec(title: "Doktor randevuları", hoursAgo: 24 * 60),
                ]),
            ]),
        ]

        for (notebookIndex, (name, color, sections)) in data.enumerated() {
            let notebook = Notebook(
                name: name, color: color, sortIndex: Double(notebookIndex),
                createdAt: now.addingTimeInterval(-86_400 * 90)
            )
            context.insert(notebook)
            for (sectionIndex, (sectionName, specs)) in sections.enumerated() {
                let section = NoteSection(name: sectionName, sortIndex: Double(sectionIndex), createdAt: notebook.createdAt)
                context.insert(section)
                section.notebook = notebook
                for spec in specs {
                    let updated = now.addingTimeInterval(-spec.hoursAgo * 3600)
                    let note = Note(
                        title: spec.title,
                        body: spec.body,
                        createdAt: updated.addingTimeInterval(-86_400 * 2),
                        updatedAt: updated,
                        dueDate: spec.dueInDays.map { now.addingTimeInterval($0 * 86_400) },
                        isPinned: spec.pinned
                    )
                    note.isBlocked = spec.blocked
                    context.insert(note)
                    note.section = section
                    for (taskIndex, (text, done)) in spec.tasks.enumerated() {
                        let task = NoteTask(text: text, isDone: done, sortIndex: Double(taskIndex))
                        context.insert(task)
                        task.note = note
                    }
                }
            }
        }

        // Son Silinenler
        let trashSection = (try? context.fetch(FetchDescriptor<NoteSection>(predicate: #Predicate { $0.name == "Ev" })))?.first
        for (title, body, daysAgo) in [
            ("Eski alışveriş listesi", "Geçen ayın listesi.", 80.0),
            ("Taslak: blog yazısı", "SwiftUI ile macOS uygulaması geliştirmek üzerine notlar.", 3.0),
        ] {
            let note = Note(title: title, body: body, createdAt: now.addingTimeInterval(-86_400 * (daysAgo + 5)))
            context.insert(note)
            note.section = trashSection
            context.moveToTrash(note, now: now.addingTimeInterval(-86_400 * daysAgo))
        }
    }
}
#endif
