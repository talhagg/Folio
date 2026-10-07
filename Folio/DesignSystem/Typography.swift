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
    func textStyle(_ style: DSTextStyle) -> some View {
        self
            .font(style.font)
            .lineSpacing(style.lineSpacing)
            .tracking(style.tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}
