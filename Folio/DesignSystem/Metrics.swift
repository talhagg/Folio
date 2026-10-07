import CoreGraphics

/// Boşluk, köşe yarıçapı ve yerleşim ölçüleri (`design/tokens.json`).
enum Metrics {
    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s6: CGFloat = 24
        static let s10: CGFloat = 40
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 10
        static let window: CGFloat = 12
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 220
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 280
        static let listWidth: CGFloat = 300
        static let toolbarHeight: CGFloat = 52
        static let rowHeight: CGFloat = 28
        static let readingWidth: CGFloat = 680
        static let separator: CGFloat = 1
    }
}
