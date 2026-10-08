import AppKit
import Foundation
import SwiftData
import UserNotifications

/// Hedef tarihli notlar ve görevler için macOS bildirimleri.
///
/// Bildirimler hedef günün seçilen saatinde gönderilir. Her değişiklikten sonra tüm Folio bildirimleri
/// yeniden planlanır (tarihi değişen/silinen notun eskisi kalmaz). macOS bekleyen bildirim sayısını
/// sınırladığı için en yakın 60 tanesi planlanır.
enum Reminders {
    static let enabledKey = "reminders.enabled"
    static let hourKey = "reminders.hour"
    static let identifierPrefix = "folio."
    static let taskCategory = "folio.task"
    static let noteCategory = "folio.note"
    static let completeAction = "folio.complete"
    static let snoozeAction = "folio.snooze"
    static let maxPending = 60

    struct Planned: Equatable, Sendable {
        var identifier: String
        var title: String
        var body: String
        var fireDate: Date
        var noteID: UUID
        var taskID: UUID?
    }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 9 }

    /// Saf planlama: gelecekteki hatırlatıcılar, en yakından uzağa.
    static func plan(notes: [Note], now: Date, hour: Int, calendar: Calendar = .current) -> [Planned] {
        func fireDate(for due: Date) -> Date? {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: due))
        }
        var result: [Planned] = []
        for note in notes where !note.isTrashed {
            let title = note.title.isEmpty ? String(localized: "Başlıksız not") : note.title
            let location = note.locationPath.map { " · \($0)" } ?? ""
            if let due = note.dueDate, note.status != .done, let fire = fireDate(for: due), fire > now {
                result.append(Planned(
                    identifier: identifierPrefix + "note." + note.id.uuidString,
                    title: title,
                    body: String(localized: "Bugün hedef tarihi\(location)"),
                    fireDate: fire, noteID: note.id, taskID: nil
                ))
            }
            for task in note.sortedTasks where !task.isDone {
                guard let due = task.dueDate, let fire = fireDate(for: due), fire > now else { continue }
                result.append(Planned(
                    identifier: identifierPrefix + "task." + task.id.uuidString,
                    title: task.text.isEmpty ? String(localized: "Görev") : task.text,
                    body: String(localized: "\(title) notundaki görevin hedefi bugün"),
                    fireDate: fire, noteID: note.id, taskID: task.id
                ))
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }
}

@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private var container: ModelContainer?
    private var pendingWork: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?

    /// Uygulama açılışında çağrılır: bildirim merkezini bağlar ve değişiklikleri dinler.
    func start(container: ModelContainer) {
        self.container = container
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Reminders.taskCategory, actions: [
                UNNotificationAction(identifier: Reminders.completeAction, title: String(localized: "Tamamla")),
                UNNotificationAction(identifier: Reminders.snoozeAction, title: String(localized: "1 saat ertele")),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Reminders.noteCategory, actions: [
                UNNotificationAction(identifier: Reminders.snoozeAction, title: String(localized: "1 saat ertele")),
            ], intentIdentifiers: []),
        ])
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ReminderScheduler.shared.scheduleSoon() }
        }
        scheduleSoon()
    }

    /// Ardışık kayıtları birleştirip bir kez planlar.
    func scheduleSoon() {
        pendingWork?.cancel()
        pendingWork = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    func reschedule(now: Date = .now) async {
        guard let container else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        // Erteleme bildirimleri korunur; diğer Folio bildirimleri yeniden kurulur.
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Reminders.identifierPrefix) && !$0.contains(".snooze.") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard Reminders.isEnabled else { return }

        let notes = (try? container.mainContext.fetch(FetchDescriptor<Note>())) ?? []
        let planned = Reminders.plan(notes: notes, now: now, hour: Reminders.hour)
        guard !planned.isEmpty else { return }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        for reminder in planned {
            try? await center.add(request(for: reminder))
        }
    }

    private func request(for reminder: Reminders.Planned, identifier: String? = nil) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = reminder.taskID == nil ? Reminders.noteCategory : Reminders.taskCategory
        var info: [String: String] = ["noteID": reminder.noteID.uuidString]
        if let taskID = reminder.taskID { info["taskID"] = taskID.uuidString }
        content.userInfo = info
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier ?? reminder.identifier, content: content, trigger: trigger)
    }

    // MARK: - Bildirim merkezi

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let noteID = (info["noteID"] as? String).flatMap(UUID.init(uuidString:))
        let taskID = (info["taskID"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        await MainActor.run {
            self.handle(action: action, noteID: noteID, taskID: taskID, title: title, body: body)
        }
    }

    private func handle(action: String, noteID: UUID?, taskID: UUID?, title: String, body: String) {
        guard let noteID else { return }
        switch action {
        case Reminders.completeAction:
            guard let taskID, let context = container?.mainContext,
                  let task = try? context.fetch(FetchDescriptor<NoteTask>(predicate: #Predicate { $0.id == taskID })).first
            else { return }
            task.isDone = true
            task.note?.touch()
            try? context.save()
        case Reminders.snoozeAction:
            let snoozed = Reminders.Planned(
                identifier: Reminders.identifierPrefix + "snooze." + UUID().uuidString,
                title: title, body: body, fireDate: Date().addingTimeInterval(3600), noteID: noteID, taskID: taskID
            )
            UNUserNotificationCenter.current().add(request(for: snoozed))
        default:
            // Bildirime tıklandı: notu aç (pencere yoksa folio:// ile açılır).
            NSApp.activate()
            NSWorkspace.shared.open(AppLink.note(noteID).url)
        }
    }
}
