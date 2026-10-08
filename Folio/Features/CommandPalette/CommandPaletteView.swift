import SwiftUI

/// ⌘K komut paleti: notlara, defterlere, etiketlere ve komutlara klavyeden ulaşma.
/// ↑/↓ seçer, ↩ çalıştırır, Esc kapatır.
struct CommandPaletteView: View {
    let items: [PaletteItem]
    /// Sorgu boşken gösterilenler (son notlar + komutlar).
    let suggestions: [PaletteItem]
    var onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFieldFocused: Bool

    private var results: [PaletteItem] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? suggestions : PaletteRanker.rank(items, query: query)
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: Metrics.Spacing.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ds.inkTertiary)
                TextField("Not, defter ya da komut ara", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isFieldFocused)
                    .onSubmit { run(results) }
                    .onKeyPress(.upArrow) { move(by: -1, count: results.count); return .handled }
                    .onKeyPress(.downArrow) { move(by: 1, count: results.count); return .handled }
                    .onKeyPress(.escape) { onDismiss(); return .handled }
                    .onExitCommand { onDismiss() }
                    .accessibilityIdentifier("commandPaletteField")
                .frame(height: 24)
            }
            .padding(.horizontal, Metrics.Spacing.s4)
            .padding(.vertical, Metrics.Spacing.s3)

            Rectangle().fill(Color.ds.separator).frame(height: 1)

            if results.isEmpty {
                Text("Sonuç yok")
                    .textStyle(.callout)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Metrics.Spacing.s6)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, isSelected: index == selectedIndex)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedIndex = index; run(results) }
                                    .onHover { if $0 { selectedIndex = index } }
                            }
                        }
                        .padding(Metrics.Spacing.s2)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selectedIndex) { _, index in
                        guard results.indices.contains(index) else { return }
                        proxy.scrollTo(results[index].id)
                    }
                }
            }

            Rectangle().fill(Color.ds.separator).frame(height: 1)
            HStack(spacing: Metrics.Spacing.s4) {
                hint("↑↓", "seç")
                hint("↩", "aç")
                hint("esc", "kapat")
                Spacer()
            }
            .padding(.horizontal, Metrics.Spacing.s4)
            .padding(.vertical, Metrics.Spacing.s2)
        }
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.ds.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.Radius.window))
        .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.window).strokeBorder(Color.ds.controlBorder))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .onChange(of: query) { selectedIndex = 0 }
        .onAppear {
            // Overlay eklendikten sonraki turda odakla; aynı turda SwiftUI isteği yok sayabiliyor.
            DispatchQueue.main.async { isFieldFocused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Komut paleti"))
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: Metrics.Spacing.s3) {
            Image(systemName: item.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.ds.accent : Color.ds.inkSecondary)
                .frame(width: 20)
            Text(item.title)
                .textStyle(.body)
                .foregroundStyle(Color.ds.ink)
                .lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .textStyle(.callout)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Metrics.Spacing.s2)
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkTertiary)
            }
        }
        .padding(.horizontal, Metrics.Spacing.s3)
        .frame(height: 32)
        .background(
            isSelected ? Color.ds.selection : Color.clear,
            in: RoundedRectangle(cornerRadius: Metrics.Radius.md)
        )
    }

    private func hint(_ key: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.ds.surfaceHover, in: RoundedRectangle(cornerRadius: Metrics.Radius.sm))
            Text(text)
        }
        .textStyle(.caption)
        .foregroundStyle(Color.ds.inkTertiary)
    }

    private func move(by offset: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + offset + count) % count
    }

    private func run(_ results: [PaletteItem]) {
        guard results.indices.contains(selectedIndex) else { return }
        let item = results[selectedIndex]
        onDismiss()
        item.perform()
    }
}
