import AppKit
import Observation
import SwiftUI

/// Uygulama teması: görünüm (Sistem/Açık/Koyu) ve vurgu rengi. Görünümler `Color.ds.accent` gibi
/// değerleri okurken bu nesneyi gözlemler; seçim değişince anında yeniden çizilir.
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()

    static let accentKey = "theme.accent"
    static let appearanceKey = "theme.appearance"

    var accent: AccentTheme {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey) }
    }

    var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            MainActor.assumeIsolated { applyAppearance() }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        accent = defaults.string(forKey: Self.accentKey).flatMap(AccentTheme.init(rawValue:)) ?? .ocean
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    /// `preferredColorScheme(nil)` koyudan sisteme dönüşte güvenilir değil; NSApp düzeyinde uygulanır.
    @MainActor
    func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .light: String(localized: "Açık")
        case .dark: String(localized: "Koyu")
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Vurgu renkleri. Her biri açık/koyu için `accent`, `accent-hover`, `accent-soft` (seçim zemini)
/// ve `on-accent` değerlerini taşır; metin olarak her zeminde ≥ 4.5:1.
enum AccentTheme: String, CaseIterable, Identifiable, Sendable {
    case ocean, forest, plum, clay, rose, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: String(localized: "Mavi")
        case .forest: String(localized: "Yeşil")
        case .plum: String(localized: "Mor")
        case .clay: String(localized: "Turuncu")
        case .rose: String(localized: "Pembe")
        case .graphite: String(localized: "Grafit")
        }
    }

    struct Palette: Sendable {
        let accent: Color
        let hover: Color
        let soft: Color
        let onAccent: Color
        let nsAccent: NSColor
        let nsSoft: NSColor
    }

    var palette: Palette { Self.palettes[self]! }

    private static let palettes: [AccentTheme: Palette] = {
        func palette(_ accent: (UInt32, UInt32), _ hover: (UInt32, UInt32), _ soft: (UInt32, UInt32), _ on: (UInt32, UInt32)) -> Palette {
            let nsAccent = NSColor.dynamic(light: accent.0, dark: accent.1)
            let nsSoft = NSColor.dynamic(light: soft.0, dark: soft.1)
            return Palette(
                accent: Color(nsColor: nsAccent),
                hover: Color(nsColor: .dynamic(light: hover.0, dark: hover.1)),
                soft: Color(nsColor: nsSoft),
                onAccent: Color(nsColor: .dynamic(light: on.0, dark: on.1)),
                nsAccent: nsAccent,
                nsSoft: nsSoft
            )
        }
        return [
            .ocean: palette((0x2F5BD3, 0x7C9CF5), (0x2449B0, 0x9AB3F8), (0xDDE6FB, 0x22305A), (0xFFFFFF, 0x0E1630)),
            .forest: palette((0x1F6F5C, 0x5FBFA5), (0x185A4B, 0x7ACDB6), (0xD6E7E1, 0x23423A), (0xFFFFFF, 0x10241F)),
            .plum: palette((0x6E3FB8, 0xB69CF0), (0x5A3197, 0xC8B4F5), (0xE9E0F7, 0x33264F), (0xFFFFFF, 0x1A1030)),
            .clay: palette((0xB8480F, 0xF0935E), (0x963A0B, 0xF4AC82), (0xF6E2D6, 0x4A2A1A), (0xFFFFFF, 0x2A1408)),
            .rose: palette((0xB83266, 0xF28AB0), (0x962852, 0xF5A6C3), (0xF6DDE7, 0x4A2233), (0xFFFFFF, 0x2A0E19)),
            .graphite: palette((0x3D4450, 0xC3CAD6), (0x2C323C, 0xD7DCE5), (0xE2E5EA, 0x2E333B), (0xFFFFFF, 0x16191E)),
        ]
    }()
}

extension NSColor {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .hex(dark) : .hex(light)
        }
    }
}

/// Görünüm ve vurgu rengi seçici (toolbar'daki palet düğmesi, Ayarlar ve Görünüm menüsü).
struct ThemePicker: View {
    @Bindable var store = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            Text("Görünüm")
                .textStyle(.headline)
                .foregroundStyle(Color.ds.ink)
            Picker("Görünüm", selection: $store.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Vurgu rengi")
                .textStyle(.headline)
                .foregroundStyle(Color.ds.ink)
                .padding(.top, Metrics.Spacing.s1)
            AccentSwatches(store: store)
            Text(store.accent.title)
                .textStyle(.caption)
                .foregroundStyle(Color.ds.inkSecondary)
        }
    }
}

/// Vurgu rengi daireleri (tema seçici ve Ayarlar).
struct AccentSwatches: View {
    @Bindable var store = ThemeStore.shared
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: Metrics.Spacing.s2 + 2) {
            ForEach(AccentTheme.allCases) { theme in
                swatch(theme)
            }
        }
    }

    private func swatch(_ theme: AccentTheme) -> some View {
        let isSelected = store.accent == theme
        return Button {
            withAnimation(.snappy(duration: 0.2)) { store.accent = theme }
        } label: {
            Circle()
                .fill(theme.palette.accent)
                .frame(width: size, height: size)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.palette.onAccent)
                    }
                }
                .padding(3)
                .overlay {
                    Circle().strokeBorder(isSelected ? theme.palette.accent : .clear, lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(theme.title))
        .accessibilityLabel(Text(theme.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
