import AppKit
import SwiftUI

/// Pencere çerçevesi ve sütun genişliklerini hatırlar.
///
/// `NavigationSplitView` sütun genişliğini dışarı vermediği için sütunlar ölçülüp `UserDefaults`'a yazılır
/// ve açılışta `ideal` genişlik olarak kullanılır. Yazma gözlemlenen bir state'e gitmez; sürükleme sırasında
/// görünüm yeniden çizilmez.
enum WindowLayout {
    static let sidebarWidthKey = "layout.sidebarWidth"
    static let listWidthKey = "layout.listWidth"
    static let frameAutosaveName = "FolioMainWindow"

    static func storedWidth(_ key: String, default value: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        guard stored > 0 else { return value }
        return min(max(CGFloat(stored), range.lowerBound), range.upperBound)
    }
}

extension View {
    /// Görünümün genişliğini `UserDefaults`'a kaydeder.
    func persistWidth(key: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width) { _, width in
                        guard width > 0 else { return }
                        UserDefaults.standard.set(Double(width.rounded()), forKey: key)
                    }
            }
        }
    }

    /// Pencere çerçevesini AppKit'in autosave mekanizmasıyla saklar ve geri yükler.
    func persistWindowFrame(_ name: String = WindowLayout.frameAutosaveName) -> some View {
        background(WindowFrameAutosaver(name: name))
    }
}

private struct WindowFrameAutosaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView { AutosaveView(name: name) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AutosaveView: NSView {
        let name: String
        private var didConfigure = false

        init(name: String) {
            self.name = name
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !didConfigure else { return }
            didConfigure = true
            // İkinci bir pencere aynı adı alamaz; ilk pencere çerçeveyi saklar.
            window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
        }
    }
}
