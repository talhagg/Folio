import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Notları macOS Spotlight'a dizinler (başlık, özet, etiketler, defter). Çöptekiler dizinde yer almaz.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    static let domain = "com.talha.folio.notes"

    private var container: ModelContainer?
    private var pending: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    func start(container: ModelContainer) {
        self.container = container
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SpotlightIndexer.shared.reindexSoon() }
        }
        reindexSoon()
    }

    func reindexSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.reindex()
        }
    }

    static func item(for note: Note) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = note.title.isEmpty ? String(localized: "Başlıksız not") : note.title
        attributes.contentDescription = MarkdownPreview.plainText(note.body, limit: 300)
        attributes.keywords = note.tags + [note.notebook?.name, note.section?.name].compactMap { $0 }
        attributes.contentModificationDate = note.updatedAt
        attributes.contentCreationDate = note.createdAt
        if let due = note.dueDate { attributes.dueDate = due }
        let item = CSSearchableItem(uniqueIdentifier: note.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    func reindex() async {
        guard let container else { return }
        let notes = ((try? container.mainContext.fetch(FetchDescriptor<Note>())) ?? []).filter { !$0.isTrashed }
        let items = notes.map(Self.item(for:))
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
        if !items.isEmpty { try? await index.indexSearchableItems(items) }
    }

    /// Spotlight sonucundan gelen etkinlik → not kimliği.
    static func noteID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return UUID(uuidString: identifier)
    }
}
