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
        static let selection = Color("selection")
        static let separator = Color("separator")
        static let controlBorder = Color("control-border")

        // Metin
        static let ink = Color("ink")
        static let inkSecondary = Color("ink-secondary")
        static let inkTertiary = Color("ink-tertiary")

        // Vurgu
        static let accent = Color("accent")
        static let accentHover = Color("accent-hover")
        static let onAccent = Color("on-accent")
        static let accentSoft = Color("accent-soft")

        // Durum
        static let statusTodo = Color("status-todo")
        static let statusDoing = Color("status-doing")
        static let statusDone = Color("status-done")
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
