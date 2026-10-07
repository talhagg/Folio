import SwiftUI

/// Asset Catalog'daki renk setlerine tip güvenli erişim. Adlar `design/tokens.json` ile aynıdır.
extension Color {
    enum ds {
        // Zeminler
        static let windowBg = Color("window-bg")
        static let sidebarBg = Color("sidebar-bg")
        static let surface = Color("surface")
        static let surfaceRaised = Color("surface-raised")
        static let surfaceHover = Color("surface-hover")
        /// Seçili satır zemini; vurgu temasına göre (`accent-soft`).
        static var selection: Color { ThemeStore.shared.accent.palette.soft }
        static let separator = Color("separator")
        static let controlBorder = Color("control-border")

        // Metin
        static let ink = Color("ink")
        static let inkSecondary = Color("ink-secondary")
        static let inkTertiary = Color("ink-tertiary")

        // Vurgu — seçili temaya göre (`ThemeStore`); okuyan görünüm tema değişince yeniden çizilir.
        static var accent: Color { ThemeStore.shared.accent.palette.accent }
        static var accentHover: Color { ThemeStore.shared.accent.palette.hover }
        static var onAccent: Color { ThemeStore.shared.accent.palette.onAccent }
        static var accentSoft: Color { ThemeStore.shared.accent.palette.soft }

        // Durum
        static let statusTodo = Color("status-todo")
        static let statusDoing = Color("status-doing")
        /// Tamamlandı = vurgu rengi (tokens.json).
        static var statusDone: Color { accent }
        static let statusBlocked = Color("status-blocked")

        // Defter / grup
        static let groupClay = Color("group-clay")
        static let groupAmber = Color("group-amber")
        static let groupMoss = Color("group-moss")
        static let groupTeal = Color("group-teal")
        static let groupSlate = Color("group-slate")
        static let groupPlum = Color("group-plum")

        static let highlight = Color("highlight")
    }
}
