import AppKit
import SwiftUI

/// Paragraf stili (biçim çubuğundaki menü).
enum MarkdownLineStyle: Equatable, CaseIterable, Sendable {
    case body, heading1, heading2, heading3, bullet, task, numbered, quote

    var prefix: String {
        switch self {
        case .body: ""
        case .heading1: "# "
        case .heading2: "## "
        case .heading3: "### "
        case .bullet: "- "
        case .task: "- [ ] "
        case .numbered: "1. "
        case .quote: "> "
        }
    }

    var title: String {
        switch self {
        case .body: String(localized: "Metin")
        case .heading1: String(localized: "Başlık")
        case .heading2: String(localized: "Alt başlık")
        case .heading3: String(localized: "Küçük başlık")
        case .bullet: String(localized: "Madde listesi")
        case .task: String(localized: "Görev listesi")
        case .numbered: String(localized: "Numaralı liste")
        case .quote: String(localized: "Alıntı")
        }
    }

    static let paragraphStyles: [MarkdownLineStyle] = [.body, .heading1, .heading2, .heading3]

    /// Satırın stili ve önekin uzunluğu.
    static func detect(_ line: String) -> (style: MarkdownLineStyle, prefixLength: Int) {
        let patterns: [(MarkdownLineStyle, Regex<Substring>)] = [
            (.heading3, /^###\s+/), (.heading2, /^##\s+/), (.heading1, /^#\s+/),
            (.task, /^[-*+]\s+\[[ xX]\]\s*/), (.bullet, /^[-*+]\s+/), (.numbered, /^\d+[.)]\s+/), (.quote, /^>\s?/),
        ]
        for (style, pattern) in patterns {
            if let match = line.prefixMatch(of: pattern) {
                return (style, line.distance(from: line.startIndex, to: match.range.upperBound))
            }
        }
        if let match = line.prefixMatch(of: /^#{4,6}\s+/) {
            return (.heading3, line.distance(from: line.startIndex, to: match.range.upperBound))
        }
        return (.body, 0)
    }
}

/// Editör dışından (biçim çubuğu) metin görünümüne komut gönderir.
@MainActor
final class MarkdownEditorController {
    fileprivate weak var textView: NSTextView?

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        if textView.selectedRange().location == 0 && !textView.string.isEmpty {
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
    }

    var isFocused: Bool { textView.map { $0.window?.firstResponder === $0 } ?? false }

    /// Editör henüz açılmamışken istenen biçim eylemleri; metin görünümü pencereye gelince uygulanır.
    private var pendingActions: [@MainActor () -> Void] = []

    func perform(whenReady action: @escaping @MainActor () -> Void) {
        if textView?.window != nil {
            action()
        } else {
            pendingActions.append(action)
        }
    }

    /// Metin görünümü pencereye eklenene kadar kısa aralıklarla dener.
    fileprivate func runPendingActions(attempt: Int = 0) {
        guard !pendingActions.isEmpty else { return }
        guard textView?.window != nil else {
            if attempt < 20 {
                // GCD değil run loop: iç içe çalışan run loop'larda (modal, testler) da tetiklenir.
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.runPendingActions(attempt: attempt + 1) }
                }
            }
            return
        }
        focus()
        let actions = pendingActions
        pendingActions = []
        actions.forEach { $0() }
    }

    /// Testler ve önizlemeler için.
    func attach(_ textView: NSTextView) { self.textView = textView }

    /// Kalın (`**`), italik (`*`) ve kod (`` ` ``) — Word benzeri:
    /// - Seçim varsa: sarar; zaten sarılıysa (ya da işaretlerle birlikte seçildiyse) kaldırır.
    /// - İmleç biçimli bir yazının içindeyse: sonundaysa imleci dışarı çıkarır, değilse biçimi kaldırır.
    /// - İmleç bir kelimenin içindeyse: kelimeyi sarar.
    /// - Aksi halde boş çift ekler (yazma modu); boş çiftin içindeyken tekrar basılırsa çifti siler.
    func toggleInline(_ marker: String) {
        guard let textView else { return }
        let text = textView.string as NSString
        let range = textView.selectedRange()
        let length = (marker as NSString).length

        func substring(_ location: Int, _ count: Int) -> String? {
            guard location >= 0, count >= 0, location + count <= text.length else { return nil }
            return text.substring(with: NSRange(location: location, length: count))
        }

        if range.length > 0 {
            let selected = text.substring(with: range)
            // İşaretler seçimin dışında: **[metin]**
            if substring(range.location - length, length) == marker, substring(range.location + range.length, length) == marker {
                let outer = NSRange(location: range.location - length, length: range.length + 2 * length)
                replace(outer, with: selected, select: NSRange(location: outer.location, length: range.length))
                return
            }
            // İşaretler seçimin içinde: [**metin**]
            if let inner = Self.span(selected, marker: marker), inner.location == 0, inner.length == (selected as NSString).length {
                let content = (selected as NSString).substring(with: NSRange(location: length, length: inner.length - 2 * length))
                replace(range, with: content, select: NSRange(location: range.location, length: (content as NSString).length))
                return
            }
            replace(range, with: marker + selected + marker, select: NSRange(location: range.location + length, length: range.length))
            return
        }

        let caret = range.location
        // Boş çiftin içinde: **|**
        if substring(caret - length, length) == marker, substring(caret, length) == marker {
            replace(NSRange(location: caret - length, length: 2 * length), with: "", select: NSRange(location: caret - length, length: 0))
            return
        }

        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        let line = text.substring(with: lineRange)
        // İmleç biçimli bir yazının içinde.
        for match in Self.spans(line, marker: marker) {
            let absolute = NSRange(location: lineRange.location + match.location, length: match.length)
            guard caret > absolute.location, caret < absolute.upperBound else { continue }
            if caret >= absolute.upperBound - length {
                // Sonunda: biçimden çık, normal yazmaya devam et.
                textView.setSelectedRange(NSRange(location: absolute.upperBound, length: 0))
                refocus()
            } else {
                let content = text.substring(with: NSRange(location: absolute.location + length, length: absolute.length - 2 * length))
                replace(absolute, with: content, select: NSRange(location: caret - length, length: 0))
            }
            return
        }

        // Kelimenin içinde: kelimeyi sar.
        let word = Self.wordRange(at: caret, in: text)
        if word.length > 0 {
            let content = text.substring(with: word)
            replace(word, with: marker + content + marker, select: NSRange(location: caret + length, length: 0))
            return
        }

        replace(range, with: marker + marker, select: NSRange(location: caret + length, length: 0))
    }

    /// Satırdaki biçimli yazıların aralıkları (işaretler dahil).
    static func spans(_ line: String, marker: String) -> [NSRange] {
        let pattern: String
        switch marker {
        case "**": pattern = #"\*\*(?=\S)(.+?)\*\*"#
        case "*": pattern = #"(?<![*\w])\*(?=[^*\s])([^*]+?)\*(?![*\w])"#
        default: pattern = "`[^`]+`"
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length)).map(\.range)
    }

    static func span(_ text: String, marker: String) -> NSRange? { spans(text, marker: marker).first }

    /// İmleç bir harf/rakam dizisinin içindeyse o dizi.
    static func wordRange(at caret: Int, in text: NSString) -> NSRange {
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < text.length else { return false }
            let scalar = text.character(at: index)
            guard let unicode = Unicode.Scalar(scalar) else { return false }
            return CharacterSet.alphanumerics.contains(unicode)
        }
        guard isWordCharacter(caret - 1) || isWordCharacter(caret) else { return NSRange(location: caret, length: 0) }
        // Yalnızca kelimenin içindeyse (iki yanı da harf) sar; kelime sonunda yazma modu daha doğal.
        guard isWordCharacter(caret - 1), isWordCharacter(caret) else { return NSRange(location: caret, length: 0) }
        var start = caret
        while isWordCharacter(start - 1) { start -= 1 }
        var end = caret
        while isWordCharacter(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private func refocus() {
        guard let textView, let window = textView.window, window.firstResponder !== textView else { return }
        window.makeFirstResponder(textView)
    }

    /// Seçili satırlara stil uygular; hepsi zaten o stildeyse metne döndürür.
    func setLineStyle(_ style: MarkdownLineStyle) {
        guard let textView else { return }
        let text = textView.string as NSString
        let paragraphs = text.paragraphRange(for: textView.selectedRange())
        let block = text.substring(with: paragraphs)
        let hasTrailingNewline = block.hasSuffix("\n")
        var lines = (hasTrailingNewline ? String(block.dropLast()) : block).components(separatedBy: "\n")
        let alreadyStyled = lines.allSatisfy { MarkdownLineStyle.detect($0).style == style }
        let target: MarkdownLineStyle = alreadyStyled && style != .body ? .body : style
        let firstNumber = target == .numbered ? Self.nextNumber(before: paragraphs.location, in: text) : 1
        lines = lines.enumerated().map { index, line in
            let detected = MarkdownLineStyle.detect(line)
            let content = String(line.dropFirst(detected.prefixLength))
            let prefix = target == .numbered ? "\(firstNumber + index). " : target.prefix
            return prefix + content
        }
        let replacement = lines.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
        let caret = paragraphs.location + (lines.first.map { ($0 as NSString).length } ?? 0)
        replace(paragraphs, with: replacement, select: NSRange(location: caret, length: 0))
    }

    /// Hemen üstteki satır numaralıysa onun bir fazlası, değilse 1.
    static func nextNumber(before location: Int, in text: NSString) -> Int {
        guard location > 0 else { return 1 }
        let previous = text.substring(with: text.lineRange(for: NSRange(location: location - 1, length: 0)))
        guard let match = previous.prefixMatch(of: /^(\d+)[.)]\s/) else { return 1 }
        return (Int(match.1) ?? 0) + 1
    }

    /// İmlecin bulunduğu yere, önünde ve arkasında boş satır olacak şekilde blok ekler.
    func insertBlock(_ markdown: String) {
        guard let textView else { return }
        let text = textView.string as NSString
        let range = textView.selectedRange()
        let before = text.substring(to: range.location)
        let after = text.substring(from: range.location + range.length)
        let leading = before.isEmpty ? "" : (before.hasSuffix("\n\n") ? "" : (before.hasSuffix("\n") ? "\n" : "\n\n"))
        let trailing = after.hasPrefix("\n\n") ? "" : (after.hasPrefix("\n") ? "\n" : "\n\n")
        let insertion = leading + markdown + trailing
        replace(range, with: insertion, select: NSRange(location: range.location + (insertion as NSString).length, length: 0))
    }

    fileprivate func replace(_ range: NSRange, with string: String, select selection: NSRange) {
        guard let textView, textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        textView.setSelectedRange(selection)
        // Biçim çubuğuna tıklamak odağı almış olabilir; yazmaya kaldığı yerden devam edilsin.
        if let window = textView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }
}

/// Markdown'ı yazarken biçimlendiren düz metin editörü (NSTextView). Metin markdown olarak kalır;
/// başlıklar büyük, `**kalın**` kalın, kod eş aralıklı, liste işaretleri vurgu renginde görünür.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var scale: CGFloat
    let controller: MarkdownEditorController
    var minHeight: CGFloat = 120
    /// Yapıştırılan/bırakılan dosya ve görselleri eke çevirir; `nil` ise ek kabul edilmez.
    var onAttach: ((AttachmentInput) -> String?)? = nil
    var onStyleChange: (MarkdownLineStyle) -> Void = { _ in }
    var onEndEditing: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let textView = FolioTextView(usingTextLayoutManager: false)
        textView.onAttach = onAttach
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.setAccessibilityLabel(String(localized: "Not gövdesi"))
        // Bağlantı rengini biçimleyici verir; burada yalnızca imleç.
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.string = text
        controller.textView = textView
        context.coordinator.restyle(textView)
        RunLoop.main.perform { [controller] in MainActor.assumeIsolated { controller.runPendingActions() } }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = textView
        (textView as? FolioTextView)?.onAttach = onAttach
        RunLoop.main.perform { [controller] in MainActor.assumeIsolated { controller.runPendingActions() } }
        // Editör kendi değişikliğini nota yazarken SwiftUI görünümü senkron güncelleyebiliyor ve
        // bu sırada notun eski metnini okuyor; o anda metni ezmek imleci geri atıyordu.
        // Yalnızca dışarıdan gelen değişiklikleri (iCloud, geri yükleme…) yansıt.
        if !context.coordinator.isWritingToModel, textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        // Tema ya da boyut değiştiyse yeniden biçimle (vurgu rengi buradan gözlemlenir).
        let accent = ThemeStore.shared.accent
        if context.coordinator.styledScale != scale || context.coordinator.styledAccent != accent {
            context.coordinator.restyle(textView)
        }
    }

    /// Yükseklik metnin bir kopyası üzerinde ölçülür. Canlı metin kutusunun genişliğine dokunulmaz:
    /// SwiftUI ölçüm sırasında 0 genişlik de önerir; kutu 0'a ayarlanırsa metin görünmez olur.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let height = Self.measuredHeight(of: textView.attributedString(), width: width) + textView.textContainerInset.height * 2
        return CGSize(width: width, height: max(height, minHeight))
    }

    static func measuredHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var styledScale: CGFloat = 0
        var styledAccent: AccentTheme?
        /// Metin nota yazılırken true; `updateNSView` bu sırada metni ezmez.
        var isWritingToModel = false

        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func restyle(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            styledScale = parent.scale
            styledAccent = ThemeStore.shared.accent
            MarkdownStyler.style(storage, scale: parent.scale)
            textView.typingAttributes = MarkdownStyler.baseAttributes(scale: parent.scale)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            restyle(textView)
            isWritingToModel = true
            parent.text = textView.string
            isWritingToModel = false
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let text = textView.string as NSString
            let line = text.substring(with: text.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0)))
            parent.onStyleChange(MarkdownLineStyle.detect(line).style)
        }


        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url, let appLink = AppLink(url: url) else { return false }
            AppNavigator.shared.open(appLink)
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                return continueList(textView)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEndEditing()
                return true
            default:
                return false
            }
        }

        /// Liste satırında Return: yeni madde açar; boş maddede listeyi bitirir.
        func continueList(_ textView: NSTextView) -> Bool {
            let text = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let lineRange = text.lineRange(for: selection)
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let detected = MarkdownLineStyle.detect(line)
            guard [.bullet, .task, .numbered, .quote].contains(detected.style) else { return false }

            if (line as NSString).length == detected.prefixLength {
                // Boş madde: işareti kaldır.
                parent.controller.replace(
                    NSRange(location: lineRange.location, length: detected.prefixLength),
                    with: "",
                    select: NSRange(location: lineRange.location, length: 0)
                )
                return true
            }
            var prefix = detected.style.prefix
            if detected.style == .numbered, let number = Int(line.prefix { $0.isNumber }) {
                prefix = "\(number + 1). "
            }
            let insertion = "\n" + prefix
            parent.controller.replace(selection, with: insertion, select: NSRange(location: selection.location + (insertion as NSString).length, length: 0))
            return true
        }
    }
}

/// Metin deposuna markdown görünümü uygular.
@MainActor
enum MarkdownStyler {
    private static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif)
            ?? NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }

    private static func mono(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func baseAttributes(scale: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7 * scale
        paragraph.paragraphSpacing = 2 * scale
        return [
            .font: serif((15 * scale).rounded()),
            .foregroundColor: NSColor(named: "ink") ?? .labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    static func style(_ storage: NSTextStorage, scale: CGFloat) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let body = (15 * scale).rounded()
        let tertiary = NSColor(named: "ink-tertiary") ?? .tertiaryLabelColor
        let secondary = NSColor(named: "ink-secondary") ?? .secondaryLabelColor
        let accent = ThemeStore.shared.accent.palette.nsAccent
        let codeBackground = NSColor(named: "window-bg") ?? .textBackgroundColor

        storage.beginEditing()
        storage.setAttributes(baseAttributes(scale: scale), range: full)

        var inCodeBlock = false
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                storage.addAttributes([.font: mono(body - 2), .foregroundColor: tertiary], range: lineRange)
                return
            }
            if inCodeBlock {
                storage.addAttributes([.font: mono(body - 2), .backgroundColor: codeBackground], range: lineRange)
                return
            }
            if trimmed.hasPrefix("|") {
                storage.addAttributes([.font: mono(body - 3), .foregroundColor: secondary], range: lineRange)
                return
            }

            if let match = attachmentLine.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let hidden: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.5)]
                let name = match.range(at: 2)
                storage.addAttributes(hidden, range: NSRange(location: lineRange.location, length: name.location))
                storage.addAttributes(hidden, range: NSRange(location: lineRange.location + name.upperBound, length: match.range.upperBound - name.upperBound))
                storage.addAttributes([.foregroundColor: accent, .font: NSFont.systemFont(ofSize: body - 1, weight: .medium)],
                                      range: NSRange(location: lineRange.location + name.location, length: name.length))
                return
            }

            let detected = MarkdownLineStyle.detect(line)
            let prefix = NSRange(location: lineRange.location, length: detected.prefixLength)
            switch detected.style {
            case .heading1, .heading2, .heading3:
                let size: CGFloat = switch detected.style {
                case .heading1: 23
                case .heading2: 19
                default: 17
                }
                storage.addAttribute(.font, value: serif((size * scale).rounded(), weight: .semibold), range: lineRange)
                storage.addAttribute(.foregroundColor, value: tertiary, range: prefix)
            case .bullet, .numbered:
                storage.addAttribute(.foregroundColor, value: accent, range: prefix)
            case .task:
                storage.addAttribute(.foregroundColor, value: accent, range: prefix)
                if line.range(of: #"^\s*[-*+]\s+\[[xX]\]"#, options: .regularExpression) != nil {
                    let rest = NSRange(location: prefix.upperBound, length: lineRange.length - prefix.length)
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: tertiary], range: rest)
                }
            case .quote:
                storage.addAttributes([.foregroundColor: secondary, .font: serif(body, italic: true)], range: lineRange)
                storage.addAttribute(.foregroundColor, value: accent, range: prefix)
            case .body:
                break
            }
            styleInline(storage, line: line, offset: lineRange.location, body: body, tertiary: tertiary, accent: accent, codeBackground: codeBackground)
            hideEmptyMarkers(storage, line: line, offset: lineRange.location, prefixLength: detected.prefixLength)
        }
        storage.endEditing()
    }

    // Yazarken kapanıştan önceki boşluğa izin verilir (`**kalın **`); kayıtta MarkdownNormalizer düzeltir.
    private static let bold = try! NSRegularExpression(pattern: #"\*\*(?=\S)(.+?)\*\*"#)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![*\w])[*_](?=[^*_\s])([^*_]+?)[*_](?![*\w])"#)
    private static let code = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    /// İçi boş biçim çiftleri (`****`, `**`, ` `` `) ve iç içe boş çiftler.
    private static let emptyStars = try! NSRegularExpression(pattern: #"(?<![*\w])\*{2,}(?![*\w])"#)
    private static let emptyCode = try! NSRegularExpression(pattern: #"(?<!`)``(?!`)"#)
    private static let ruleLine = try! NSRegularExpression(pattern: #"^\s*([-*_]\s*){3,}$"#)

    /// Yazma moduna girince oluşan boş çiftler de görünmesin; yazmaya başlayınca biçim kendiliğinden uygulanır.
    private static func hideEmptyMarkers(_ storage: NSTextStorage, line: String, offset: Int, prefixLength: Int) {
        let full = NSRange(location: 0, length: (line as NSString).length)
        guard ruleLine.firstMatch(in: line, range: full) == nil, full.length > prefixLength else { return }
        let searchRange = NSRange(location: prefixLength, length: full.length - prefixLength)
        let hidden: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.clear, .backgroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.5),
        ]
        for regex in [emptyStars, emptyCode] {
            for match in regex.matches(in: line, range: searchRange) {
                storage.addAttributes(hidden, range: NSRange(location: offset + match.range.location, length: match.range.length))
            }
        }
    }

    /// `![ad](attachment:id)` ya da `[ad](attachment:id)` tek başına satırda.
    private static let attachmentLine = try! NSRegularExpression(pattern: #"^(!?)\[([^\]]*)\]\(attachment:[0-9A-Fa-f-]{36}\)\s*$"#)
    private static let tagLink = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_#/&\]\)])#(\p{L}[\p{L}\p{N}_\-/]{0,39})"#)
    private static let wikiLink = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]{1,120})\]\]"#)
    private static let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#)

    private static func styleInline(
        _ storage: NSTextStorage, line: String, offset: Int, body: CGFloat,
        tertiary: NSColor, accent: NSColor, codeBackground: NSColor
    ) {
        let range = NSRange(location: 0, length: (line as NSString).length)
        func shifted(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }

        for match in bold.matches(in: line, range: range) {
            let current = storage.attribute(.font, at: offset + match.range.location, effectiveRange: nil) as? NSFont
            let size = current?.pointSize ?? body
            storage.addAttribute(.font, value: serif(size, weight: .bold), range: shifted(match.range))
            dimMarkers(storage, match: match, markerLength: 2, offset: offset, color: tertiary)
        }
        for match in italic.matches(in: line, range: range) {
            storage.addAttribute(.font, value: serif(body, italic: true), range: shifted(match.range))
            dimMarkers(storage, match: match, markerLength: 1, offset: offset, color: tertiary)
        }
        for match in code.matches(in: line, range: range) {
            storage.addAttributes([.font: mono(body - 2), .backgroundColor: codeBackground], range: shifted(match.range))
            dimMarkers(storage, match: match, markerLength: 1, offset: offset, color: tertiary)
        }
        for match in tagLink.matches(in: line, range: range) {
            let tag = NoteLinkSyntax.normalizedTag((line as NSString).substring(with: match.range(at: 1)))
            storage.addAttributes([.foregroundColor: accent, .link: AppLink.tag(tag).url], range: shifted(match.range))
        }
        for match in wikiLink.matches(in: line, range: range) {
            let title = (line as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            storage.addAttributes([
                .foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: AppLink.noteTitle(title).url,
            ], range: shifted(match.range(at: 1)))
            storage.addAttribute(.foregroundColor, value: tertiary, range: NSRange(location: offset + match.range.location, length: 2))
            storage.addAttribute(.foregroundColor, value: tertiary, range: NSRange(location: offset + match.range.upperBound - 2, length: 2))
        }
        for match in link.matches(in: line, range: range) {
            storage.addAttribute(.foregroundColor, value: tertiary, range: shifted(match.range))
            storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: shifted(match.range(at: 1)))
        }
    }

    /// Biçim işaretlerini (`**`, `*`, `` ` ``) gizler: metin markdown olarak kalır ama Word'deki gibi görünür.
    private static func dimMarkers(_ storage: NSTextStorage, match: NSTextCheckingResult, markerLength: Int, offset: Int, color: NSColor) {
        let range = match.range
        let hidden: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.clear,
            .backgroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.5),
        ]
        storage.addAttributes(hidden, range: NSRange(location: offset + range.location, length: markerLength))
        storage.addAttributes(hidden, range: NSRange(location: offset + range.upperBound - markerLength, length: markerLength))
    }
}

/// Editörün üstünde sabit (sticky) biçim çubuğu: paragraf stili, kalın/italik/kod, listeler, tablo, yazı boyutu.
/// Not kaydırılsa da yerinde kalır; başlık görünmez olunca ortada notun adı belirir.
/// Düzenleme kapalıyken bir biçim seçmek düzenlemeyi başlatır ve biçimi imlece uygular.
struct EditorFormatBar: View {
    let controller: MarkdownEditorController
    let currentStyle: MarkdownLineStyle
    @Binding var textSizeRaw: Int
    var isEditing = true
    /// Başlık kaydırılıp görünmez olunca çubukta gösterilir.
    var stickyTitle: String? = nil
    var onBeginEditing: () -> Void = {}
    var onInsertTable: () -> Void
    var onAttachFile: () -> Void = {}
    var onDone: () -> Void

    /// Düzenleme kapalıysa önce editörü açar, metin görünümü hazır olunca eylemi uygular.
    private func edit(_ action: @escaping @MainActor () -> Void) {
        if isEditing {
            action()
        } else {
            onBeginEditing()
            controller.perform(whenReady: action)
        }
    }

    private var textSize: EditorTextSize { EditorTextSize(rawValue: textSizeRaw) ?? .normal }

    var body: some View {
        HStack(spacing: Metrics.Spacing.s1) {
            Menu {
                ForEach(MarkdownLineStyle.paragraphStyles, id: \.self) { style in
                    Button {
                        edit { controller.setLineStyle(style) }
                    } label: {
                        if style == currentStyle { Label(style.title, systemImage: "checkmark") } else { Text(style.title) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(MarkdownLineStyle.paragraphStyles.contains(currentStyle) ? currentStyle.title : MarkdownLineStyle.body.title)
                        .textStyle(.callout)
                        .foregroundStyle(Color.ds.ink)
                        .frame(minWidth: 82, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.ds.inkTertiary)
                }
                .padding(.horizontal, Metrics.Spacing.s2)
                .frame(height: 26)
                .background(Color.ds.surfaceHover.opacity(0.6), in: RoundedRectangle(cornerRadius: Metrics.Radius.md))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .focusable(false)
            .help(Text("Paragraf stili"))

            divider

            barButton("bold", help: "Kalın (⌘B)", key: "b") { edit { controller.toggleInline("**") } }
            barButton("italic", help: "İtalik (⌘I)", key: "i") { edit { controller.toggleInline("*") } }
            barButton("chevron.left.forwardslash.chevron.right", help: "Kod") { edit { controller.toggleInline("`") } }

            divider

            listMenu

            divider

            barButton("tablecells", help: "Tablo ekle (⌥⌘T)", key: "t", modifiers: [.command, .option], action: onInsertTable)
            barButton("paperclip", help: "Dosya ya da görsel ekle (görselleri yapıştırabilir ya da sürükleyebilirsiniz)", action: onAttachFile)

            Spacer(minLength: Metrics.Spacing.s2)
                .overlay {
                    if let stickyTitle {
                        Text(stickyTitle.isEmpty ? String(localized: "Başlıksız not") : stickyTitle)
                            .textStyle(.headline)
                            .foregroundStyle(Color.ds.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, Metrics.Spacing.s2)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.snappy(duration: 0.2), value: stickyTitle == nil)

            textSizeControl

            divider

            Button(action: isEditing ? onDone : onBeginEditing) {
                Text(isEditing ? "Bitti" : "Düzenle")
                    .textStyle(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.ds.accent)
                    .padding(.horizontal, Metrics.Spacing.s2)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(isEditing ? Text("Düzenlemeyi bitir (Esc)") : Text("Notu düzenle"))
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, Metrics.Spacing.s3)
        .frame(height: 40)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ds.separator).frame(height: 1)
        }
    }

    private static let listStyles: [(MarkdownLineStyle, String)] = [
        (.bullet, "list.bullet"), (.task, "checklist"), (.numbered, "list.number"), (.quote, "text.quote"),
    ]

    /// Madde, görev, numaralı liste ve alıntı tek menüde; simge mevcut satırın türünü gösterir.
    private var listMenu: some View {
        let current = Self.listStyles.first { $0.0 == currentStyle }
        return Menu {
            ForEach(Self.listStyles, id: \.0) { style, symbol in
                Button {
                    edit { controller.setLineStyle(style) }
                } label: {
                    Label(style.title, systemImage: style == currentStyle ? "checkmark" : symbol)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: current?.1 ?? "list.bullet")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.ds.inkTertiary)
            }
            .foregroundStyle(current == nil ? Color.ds.ink : Color.ds.accent)
            .frame(width: 38, height: 26)
            .background(current == nil ? Color.clear : Color.ds.accentSoft, in: RoundedRectangle(cornerRadius: Metrics.Radius.md - 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
        .help(Text("Liste ve alıntı"))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.ds.separator)
            .frame(width: 1, height: 18)
            .padding(.horizontal, Metrics.Spacing.s1)
    }

    private var textSizeControl: some View {
        HStack(spacing: 2) {
            barButton("textformat.size.smaller", help: "Yazıyı küçült (⌘-)") {
                if let smaller = textSize.smaller { textSizeRaw = smaller.rawValue }
            }
            .disabled(textSize.smaller == nil)

            Menu {
                ForEach(EditorTextSize.allCases) { size in
                    Button {
                        textSizeRaw = size.rawValue
                    } label: {
                        if size == textSize { Label(size.menuTitle, systemImage: "checkmark") } else { Text(size.menuTitle) }
                    }
                }
            } label: {
                Text("\(textSize.pointSize) pt")
                    .textStyle(.callout)
                    .monospacedDigit()
                    .foregroundStyle(Color.ds.ink)
                    .frame(width: 44, height: 26)
                    .background(Color.ds.surfaceHover.opacity(0.6), in: RoundedRectangle(cornerRadius: Metrics.Radius.md))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .focusable(false)
            .help(Text("Yazı boyutu"))

            barButton("textformat.size.larger", help: "Yazıyı büyüt (⌘+)") {
                if let larger = textSize.larger { textSizeRaw = larger.rawValue }
            }
            .disabled(textSize.larger == nil)
        }
    }

    private func barButton(
        _ systemImage: String, help: LocalizedStringKey, key: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command, isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        FormatBarButton(systemImage: systemImage, isOn: isOn, action: action)
            .help(Text(help))
            .accessibilityLabel(Text(help))
            .modifier(OptionalShortcut(key: key, modifiers: modifiers))
    }
}

private struct FormatBarButton: View {
    let systemImage: String
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Color.ds.accent : (isEnabled ? Color.ds.ink : Color.ds.inkTertiary))
                .frame(width: 28, height: 26)
                .background(
                    isOn ? Color.ds.accentSoft : (isHovered ? Color.ds.surfaceHover : .clear),
                    in: RoundedRectangle(cornerRadius: Metrics.Radius.md - 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?
    var modifiers: EventModifiers = .command

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}
