import AppKit
import SwiftData
import SwiftUI

/// Yapışkan not: bir notun kendi küçük, renkli penceresinde gösterilmesi (macOS Yapışkan Notlar gibi).
/// Renk ve "üstte tut" yalnızca bu Mac'te saklanır (`UserDefaults`); not içeriği her yerde aynıdır.
enum StickyNote {
    static let windowID = "sticky"

    static func colorKey(_ id: UUID) -> String { "sticky.\(id.uuidString).color" }
    static func floatingKey(_ id: UUID) -> String { "sticky.\(id.uuidString).floating" }
}

enum StickyColor: String, CaseIterable, Identifiable, Sendable {
    case yellow, green, blue, pink, purple, gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: String(localized: "Sarı")
        case .green: String(localized: "Yeşil")
        case .blue: String(localized: "Mavi")
        case .pink: String(localized: "Pembe")
        case .purple: String(localized: "Mor")
        case .gray: String(localized: "Gri")
        }
    }

    /// Kağıt rengi (açık / koyu). Üzerinde `ink` ≥ 7:1 okunur.
    var paper: Color {
        let colors: (UInt32, UInt32) = switch self {
        case .yellow: (0xFDF3B5, 0x4A4220)
        case .green: (0xD9F2D0, 0x25402A)
        case .blue: (0xD6E8FA, 0x203448)
        case .pink: (0xF9DCE6, 0x472632)
        case .purple: (0xE6DDF7, 0x352A4D)
        case .gray: (0xE8E6E1, 0x37352F)
        }
        return Color(nsColor: .dynamic(light: colors.0, dark: colors.1))
    }

    /// Üst şerit ve nokta rengi.
    var strip: Color {
        let colors: (UInt32, UInt32) = switch self {
        case .yellow: (0xF2DE6B, 0x6B5E25)
        case .green: (0xB4E2A3, 0x355C3C)
        case .blue: (0xACCFF2, 0x2E4D6B)
        case .pink: (0xF2B6CA, 0x663647)
        case .purple: (0xCDBDF0, 0x4D3D70)
        case .gray: (0xD3D0C8, 0x4E4B43)
        }
        return Color(nsColor: .dynamic(light: colors.0, dark: colors.1))
    }
}

/// Pencere içeriği: notu kimliğiyle bulur; silinmiş ya da çöpe atılmışsa bilgi gösterir.
struct StickyNoteWindow: View {
    let noteID: UUID
    @Query private var notes: [Note]

    init(noteID: UUID) {
        self.noteID = noteID
        _notes = Query(filter: #Predicate<Note> { $0.id == noteID })
    }

    var body: some View {
        if let note = notes.first, !note.isTrashed {
            StickyNoteView(note: note)
        } else {
            VStack(spacing: Metrics.Spacing.s2) {
                Image(systemName: "note.text")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.ds.inkTertiary)
                Text("Bu not silinmiş")
                    .textStyle(.headline)
                    .foregroundStyle(Color.ds.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StickyColor.gray.paper)
        }
    }
}

struct StickyNoteView: View {
    @Bindable var note: Note

    @AppStorage private var colorRaw: String
    @AppStorage private var isFloating: Bool
    @State private var controller = MarkdownEditorController()
    @State private var isHovered = false

    init(note: Note) {
        self.note = note
        _colorRaw = AppStorage(wrappedValue: StickyColor.yellow.rawValue, StickyNote.colorKey(note.id))
        _isFloating = AppStorage(wrappedValue: true, StickyNote.floatingKey(note.id))
    }

    private var color: StickyColor { StickyColor(rawValue: colorRaw) ?? .yellow }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Spacing.s2) {
                    if note.taskCount > 0 {
                        TaskListView(note: note)
                            .padding(.leading, -18)
                    }
                    MarkdownTextEditor(
                        text: bodyBinding,
                        scale: 0.87,
                        controller: controller,
                        minHeight: 80
                    )
                }
                .padding(.horizontal, Metrics.Spacing.s3)
                .padding(.bottom, Metrics.Spacing.s3)
            }
            .scrollIndicators(.never)
        }
        .frame(minWidth: 220, minHeight: 180)
        .background(color.paper)
        .environment(\.editorTextScale, 0.87)
        .background(StickyWindowConfigurator(isFloating: isFloating, title: note.title))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    /// Başlık satırı; trafik ışıklarına yer bırakır. Kontroller üzerine gelince belirir.
    private var header: some View {
        HStack(spacing: Metrics.Spacing.s1) {
            TextField("Başlıksız not", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ds.ink)
                .lineLimit(1)

            Group {
                Menu {
                    ForEach(StickyColor.allCases) { option in
                        Button {
                            colorRaw = option.rawValue
                        } label: {
                            if option == color { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                        }
                    }
                } label: {
                    Circle()
                        .fill(color.strip)
                        .overlay(Circle().strokeBorder(Color.ds.ink.opacity(0.25), lineWidth: 1))
                        .frame(width: 14, height: 14)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Renk"))

                Button {
                    isFloating.toggle()
                } label: {
                    Image(systemName: isFloating ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(isFloating ? Color.ds.ink : Color.ds.inkSecondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(isFloating ? "Diğer pencerelerin üstünde tutma" : "Diğer pencerelerin üstünde tut"))
                .accessibilityLabel(Text("Üstte tut"))
            }
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.leading, 74)
        .padding(.trailing, Metrics.Spacing.s2)
        .frame(height: 30)
        .background(color.strip.opacity(0.55))
    }

    private var titleBinding: Binding<String> {
        Binding {
            note.title
        } set: { newValue in
            guard newValue != note.title else { return }
            note.title = newValue
            note.touch()
        }
    }

    private var bodyBinding: Binding<String> {
        Binding {
            note.body
        } set: { newValue in
            guard newValue != note.body else { return }
            note.body = newValue
            if controller.isFocused { note.touch() }
        }
    }
}

/// Yapışkan pencereyi ayarlar: üstte tutma, arka plandan sürükleme, tüm masaüstlerinde görünme.
private struct StickyWindowConfigurator: NSViewRepresentable {
    let isFloating: Bool
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = isFloating ? .floating : .normal
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.title = title.isEmpty ? String(localized: "Yapışkan Not") : title
        }
    }
}
