import SwiftData
import SwiftUI

/// Görev listesi: checkbox + metin + opsiyonel hedef tarih. Return yeni görev açar, boş görevde ⌫ siler,
/// tutamaçtan sürükleyerek sıralanır.
struct TaskListView: View {
    @Bindable var note: Note
    var now: Date = .now
    /// Görünür olunca ilk görevi ekleyip odaklar ("+ Görev").
    var startsAdding = false

    @Environment(\.modelContext) private var context
    @FocusState private var focusedTaskID: UUID?
    @State private var dropTargetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(note.sortedTasks) { task in
                TaskRow(
                    task: task,
                    now: now,
                    focusedTaskID: $focusedTaskID,
                    isDropTarget: dropTargetID == task.id,
                    onToggle: { note.toggle(task) },
                    onSubmit: { addTask(after: task) },
                    onDeleteEmpty: { delete(task, focusPrevious: true) },
                    onDelete: { delete(task, focusPrevious: false) },
                    onEdit: { note.touch() }
                )
                .dropDestination(for: String.self) { items, _ in
                    guard case .task(let id)? = items.lazy.compactMap(DragPayload.init(string:)).first else { return false }
                    withAnimation(.snappy(duration: 0.2)) { note.moveTask(id, before: task.id) }
                    return true
                } isTargeted: { isTargeted in
                    dropTargetID = isTargeted ? task.id : (dropTargetID == task.id ? nil : dropTargetID)
                }
            }

            Button {
                addTask(after: note.sortedTasks.last)
            } label: {
                HStack(spacing: Metrics.Spacing.s2 + 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16, height: 16)
                    Text("Görev ekle")
                        .textStyle(.callout)
                }
                .foregroundStyle(Color.ds.inkTertiary)
                .padding(.vertical, Metrics.Spacing.s1 + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, TaskRow.handleWidth)
            .dropDestination(for: String.self) { items, _ in
                guard case .task(let id)? = items.lazy.compactMap(DragPayload.init(string:)).first else { return false }
                withAnimation(.snappy(duration: 0.2)) { note.moveTask(id, before: nil) }
                return true
            }
        }
        .onAppear {
            if startsAdding && note.taskCount == 0 { addTask(after: nil) }
        }
    }

    private func addTask(after anchor: NoteTask?) {
        let task = withAnimation(.snappy(duration: 0.2)) {
            note.addTask(after: anchor, in: context)
        }
        focusedTaskID = task.id
    }

    private func delete(_ task: NoteTask, focusPrevious: Bool) {
        let ordered = note.sortedTasks
        let previous = ordered.firstIndex { $0 === task }.flatMap { $0 > 0 ? ordered[$0 - 1] : nil }
        withAnimation(.snappy(duration: 0.2)) {
            note.removeTask(task, in: context)
        }
        if focusPrevious { focusedTaskID = previous?.id }
    }
}

private struct TaskRow: View {
    static let handleWidth: CGFloat = 18

    @Bindable var task: NoteTask
    let now: Date
    var focusedTaskID: FocusState<UUID?>.Binding
    let isDropTarget: Bool
    let onToggle: () -> Void
    let onSubmit: () -> Void
    let onDeleteEmpty: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var isHovered = false
    @State private var isDatePopoverShown = false
    @Environment(\.editorTextScale) private var scale

    private var isOverdue: Bool {
        guard let dueDate = task.dueDate else { return false }
        return !task.isDone && dueDate < Calendar.current.startOfDay(for: now)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.ds.inkTertiary)
                .frame(width: Self.handleWidth, height: 18)
                .contentShape(Rectangle())
                .opacity(isHovered ? 1 : 0)
                .draggable(DragPayload.task(task.id).string) {
                    Text(task.text.isEmpty ? String(localized: "Görev") : task.text)
                        .textStyle(.callout)
                        .padding(.horizontal, Metrics.Spacing.s2)
                        .padding(.vertical, Metrics.Spacing.s1)
                        .background(Color.ds.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.Radius.sm))
                }
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: Metrics.Spacing.s2 + 2) {
                Checkbox(isOn: task.isDone, action: onToggle)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }

                if task.isDone && focusedTaskID.wrappedValue != task.id {
                    // TextField üstü çizmeyi göstermediği için tamamlanan görev düzenlenene kadar Text olarak çizilir.
                    Text(task.text)
                        .font(DSTextStyle.noteBody.font(scale: scale))
                        .strikethrough(color: Color.ds.inkTertiary)
                        .foregroundStyle(Color.ds.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { @MainActor in focusedTaskID.wrappedValue = task.id }
                        }
                } else {
                    taskField
                }

                Spacer(minLength: Metrics.Spacing.s2)

                trailingControls
            }
        }
        .padding(.vertical, 3)
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle().fill(Color.ds.accent).frame(height: 2).offset(y: -1)
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(task.isDone ? "Tamamlanmadı olarak işaretle" : "Tamamlandı olarak işaretle", action: onToggle)
            Button("Hedef tarih…") { isDatePopoverShown = true }
            if task.dueDate != nil {
                Button("Hedef tarihi kaldır") { task.dueDate = nil; onEdit() }
            }
            Divider()
            Button("Görevi Sil", role: .destructive, action: onDelete)
        }
    }

    private var taskField: some View {
        TextField("Görev", text: $task.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DSTextStyle.noteBody.font(scale: scale))
            .foregroundStyle(task.isDone ? Color.ds.inkTertiary : Color.ds.ink)
            .focused(focusedTaskID, equals: task.id)
            .onSubmit(onSubmit)
            .onKeyPress(.delete) {
                guard task.text.isEmpty else { return .ignored }
                onDeleteEmpty()
                return .handled
            }
            .onChange(of: task.text) {
                // Yalnızca kullanıcı yazarken; alanın kendi yazmaları notu düzenlenmiş saymasın.
                if focusedTaskID.wrappedValue == task.id { onEdit() }
            }
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: Metrics.Spacing.s1) {
            if let dueDate = task.dueDate {
                Button { isDatePopoverShown = true } label: {
                    Text(dueDate.formatted(.dateTime.weekday(.abbreviated)))
                        .textStyle(.caption)
                        .foregroundStyle(isOverdue ? Color.ds.statusBlocked : Color.ds.inkSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.ds.surfaceHover.opacity(0.6), in: RoundedRectangle(cornerRadius: Metrics.Radius.sm))
                }
                .buttonStyle(.plain)
                .help(Text(dueDate.formatted(date: .long, time: .omitted)))
            } else if isHovered {
                Button { isDatePopoverShown = true } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ds.inkTertiary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Hedef tarih ekle"))
            }
        }
        .popover(isPresented: $isDatePopoverShown, arrowEdge: .bottom) {
            DueDatePopover(date: task.dueDate) { newDate in
                task.dueDate = newDate
                onEdit()
                isDatePopoverShown = false
            }
        }
    }
}

/// Tasarım sistemine uygun checkbox: işaretliyken `accent` dolgu + tik, değilken `control-border` kenarlık.
struct Checkbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.Radius.sm, style: .continuous)
                    .fill(isOn ? Color.ds.accent : Color.ds.surface)
                RoundedRectangle(cornerRadius: Metrics.Radius.sm, style: .continuous)
                    .strokeBorder(isOn ? Color.ds.accent : Color.ds.controlBorder, lineWidth: 1)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.ds.onAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isOn ? "Tamamlandı" : "Tamamlanmadı"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// Hedef tarih seçici; `nil` ile kaldırılır.
struct DueDatePopover: View {
    @State private var selection: Date
    let hasDate: Bool
    let onCommit: (Date?) -> Void

    init(date: Date?, onCommit: @escaping (Date?) -> Void) {
        self._selection = State(initialValue: date ?? Calendar.current.startOfDay(for: .now))
        self.hasDate = date != nil
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            Text("Hedef tarih")
                .textStyle(.headline)
                .foregroundStyle(Color.ds.ink)
            DatePicker("Hedef tarih", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                if hasDate {
                    Button("Kaldır", role: .destructive) { onCommit(nil) }
                }
                Spacer()
                Button("Kaydet") { onCommit(selection) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.Spacing.s4)
    }
}
