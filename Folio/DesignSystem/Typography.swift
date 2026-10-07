import SwiftUI

/// Tipografi ölçeği (`design/tokens.json` → type).
extension Font {
    enum ds {
        // Arayüz (sans = sistem fontu)
        static let windowTitle = Font.system(size: 15, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let callout = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 11, weight: .medium)
        static let sectionLabel = Font.system(size: 11, weight: .semibold)

        // Not (serif = New York)
        static let noteTitle = Font.system(size: 28, weight: .semibold, design: .serif)
        static let noteHeading = Font.system(size: 19, weight: .semibold, design: .serif)
        static let noteBody = Font.system(size: 15, weight: .regular, design: .serif)

        // Kod
        static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
    }
}

/// Font'un tek başına taşıyamadığı satır aralığı, harf aralığı ve büyük harf bilgisini de uygulayan stil.
enum DSTextStyle {
    case windowTitle, headline, body, callout, caption, sectionLabel
    case noteTitle, noteHeading, noteBody, code

    var font: Font {
        switch self {
        case .windowTitle: Font.ds.windowTitle
        case .headline: Font.ds.headline
        case .body: Font.ds.body
        case .callout: Font.ds.callout
        case .caption: Font.ds.caption
        case .sectionLabel: Font.ds.sectionLabel
        case .noteTitle: Font.ds.noteTitle
        case .noteHeading: Font.ds.noteHeading
        case .noteBody: Font.ds.noteBody
        case .code: Font.ds.code
        }
    }

    var baseSize: CGFloat {
        switch self {
        case .windowTitle: 15
        case .headline, .body, .code: 13
        case .callout: 12
        case .caption, .sectionLabel: 11
        case .noteTitle: 28
        case .noteHeading: 19
        case .noteBody: 15
        }
    }

    private var weight: Font.Weight {
        switch self {
        case .windowTitle, .headline, .sectionLabel, .noteTitle, .noteHeading: .semibold
        case .caption: .medium
        case .body, .callout, .noteBody, .code: .regular
        }
    }

    private var design: Font.Design {
        switch self {
        case .noteTitle, .noteHeading, .noteBody: .serif
        case .code: .monospaced
        default: .default
        }
    }

    /// Editör yazı boyutu için ölçeklenmiş font.
    func font(scale: CGFloat) -> Font {
        scale == 1 ? font : .system(size: (baseSize * scale).rounded(), weight: weight, design: design)
    }

    /// tokens.json'daki line-height − font size (yaklaşık; SwiftUI satır aralığı eklemelidir).
    var lineSpacing: CGFloat {
        switch self {
        case .windowTitle: 5
        case .headline, .body: 5
        case .callout: 4
        case .caption, .sectionLabel: 3
        case .noteTitle: 6
        case .noteHeading: 7
        case .noteBody: 9
        case .code: 7
        }
    }

    /// pt cinsinden; section-label için 0.04em.
    var tracking: CGFloat {
        self == .sectionLabel ? 11 * 0.04 : 0
    }

    var isUppercased: Bool { self == .sectionLabel }
}

extension View {
    func textStyle(_ style: DSTextStyle, scale: CGFloat = 1) -> some View {
        self
            .font(style.font(scale: scale))
            .lineSpacing(style.lineSpacing * scale)
            .tracking(style.tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

/// Editördeki not metninin boyutu (Görünüm → Yazı Boyutu, ⌘+ / ⌘- / ⌘0).
enum EditorTextSize: Int, CaseIterable, Identifiable, Sendable {
    case small, normal, large, larger, largest

    static let storageKey = "editor.textSize"

    var id: Int { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: 0.87
        case .normal: 1
        case .large: 1.13
        case .larger: 1.27
        case .largest: 1.47
        }
    }

    var title: String {
        switch self {
        case .small: String(localized: "Küçük")
        case .normal: String(localized: "Normal")
        case .large: String(localized: "Büyük")
        case .larger: String(localized: "Daha Büyük")
        case .largest: String(localized: "En Büyük")
        }
    }

    /// Not gövdesinin punto karşılığı (15 pt × ölçek).
    var pointSize: Int { Int((15 * scale).rounded()) }

    var menuTitle: String { "\(pointSize) pt · \(title)" }

    var larger: EditorTextSize? { EditorTextSize(rawValue: rawValue + 1) }
    var smaller: EditorTextSize? { EditorTextSize(rawValue: rawValue - 1) }
}

private struct EditorTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var editorTextScale: CGFloat {
        get { self[EditorTextScaleKey.self] }
        set { self[EditorTextScaleKey.self] = newValue }
    }
}
