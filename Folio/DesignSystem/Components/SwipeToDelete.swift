import AppKit
import SwiftUI

/// Trackpad'de iki parmakla sola kaydırınca satırın sağında silme düğmesi açar (Mail benzeri).
///
/// SwiftUI'ın `.swipeActions`'ı macOS'ta yalnızca `List` içinde çalışır; özel listede yatay kaydırma
/// olayları AppKit üzerinden, yalnızca imleç satırın üzerindeyken dinlenir. Dikey kaydırma listeye bırakılır.
struct SwipeToDelete: ViewModifier {
    let label: String
    let isRevealed: Bool
    let onRevealChange: (Bool) -> Void
    let onDelete: () -> Void

    @State private var tracker = SwipeTracker()

    func body(content: Content) -> some View {
        content
            .offset(x: tracker.offset)
            .background(alignment: .trailing) {
                if tracker.offset < 0 {
                    deleteButton
                }
            }
            .onHover { tracker.setHovered($0) }
            .onAppear {
                tracker.onEnd = { offset in
                    switch SwipeDecision.resolve(offset: offset) {
                    case .delete:
                        close()
                        onDelete()
                    case .reveal:
                        withAnimation(.snappy(duration: 0.2)) { tracker.offset = -SwipeDecision.actionWidth }
                        onRevealChange(true)
                    case .close:
                        close()
                    }
                }
            }
            .onChange(of: isRevealed) { _, revealed in
                if !revealed && tracker.offset != 0 { close(notify: false) }
            }
            .onDisappear { tracker.stop() }
            .accessibilityAction(named: Text(label), onDelete)
    }

    private var deleteButton: some View {
        Button {
            close()
            onDelete()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .textStyle(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: max(-tracker.offset - 4, 0))
            .frame(maxHeight: .infinity)
            .background(Color.ds.statusBlocked, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
            .clipped()
        }
        .buttonStyle(.plain)
        .help(Text(label))
    }

    private func close(notify: Bool = true) {
        withAnimation(.snappy(duration: 0.2)) { tracker.offset = 0 }
        if notify { onRevealChange(false) }
    }
}

/// Kaydırma bitince ne olacağı (saf; test edilir).
enum SwipeDecision: Equatable {
    case close, reveal, delete

    static let actionWidth: CGFloat = 76
    static let fullSwipeWidth: CGFloat = 200

    static func resolve(offset: CGFloat) -> SwipeDecision {
        if offset <= -fullSwipeWidth { return .delete }
        if offset <= -actionWidth / 2 { return .reveal }
        return .close
    }
}

/// Yatay trackpad kaydırmasını izler. Hareketin yönü ilk olaylarda kilitlenir; yatay ise olaylar tüketilir.
@MainActor
@Observable
final class SwipeTracker {
    var offset: CGFloat = 0
    @ObservationIgnored var onEnd: ((CGFloat) -> Void)?

    private enum Axis { case horizontal, vertical }

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var axis: Axis?
    @ObservationIgnored private var isHovered = false
    @ObservationIgnored private var isGestureActive = false

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        if hovered {
            start()
        } else if !isGestureActive {
            stop()
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        axis = nil
        isGestureActive = false
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Yerel monitör ana iş parçacığında çalışır. NSEvent Sendable olmadığından yalnızca
            // değerler aktarılır, karar Bool olarak döner.
            let input = ScrollInput(event)
            let consume = MainActor.assumeIsolated { self?.handle(input) ?? false }
            return consume ? nil : event
        }
    }

    /// `true` → olay tüketilir (liste kaymaz).
    private func handle(_ event: ScrollInput) -> Bool {
        // Fare tekerleği (fazsız olaylar) her zaman listeye gider.
        if event.phase.isEmpty && event.momentumPhase.isEmpty { return false }

        // Yatay hareketin ataleti tüketilir, dikeyinki listeye gider.
        if !event.momentumPhase.isEmpty {
            let consume = axis == .horizontal
            if event.momentumPhase.contains(.ended) { finishGesture() }
            return consume
        }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            axis = nil
            isGestureActive = true
        }

        if axis == nil {
            let dx = abs(event.scrollingDeltaX), dy = abs(event.scrollingDeltaY)
            if dx > dy * 1.5 && dx > 0.5 {
                axis = .horizontal
            } else if dy > 0.5 {
                axis = .vertical
            }
        }

        let isEnding = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        guard axis == .horizontal else {
            if isEnding { finishGesture() }
            return false
        }

        if isEnding {
            onEnd?(offset)
            return true
        }

        // Parmak yönü: "doğal kaydırma" açıkken delta zaten parmakla aynı yönde.
        let fingerDelta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        offset = min(0, max(offset + fingerDelta, -SwipeDecision.fullSwipeWidth - 40))
        return true
    }

    private func finishGesture() {
        isGestureActive = false
        axis = nil
        if !isHovered { stop() }
    }
}

/// Kaydırma olayının gereken alanları (Sendable kopya).
private struct ScrollInput: Sendable {
    let phase: NSEvent.Phase
    let momentumPhase: NSEvent.Phase
    let scrollingDeltaX: CGFloat
    let scrollingDeltaY: CGFloat
    let isDirectionInvertedFromDevice: Bool

    init(_ event: NSEvent) {
        phase = event.phase
        momentumPhase = event.momentumPhase
        scrollingDeltaX = event.scrollingDeltaX
        scrollingDeltaY = event.scrollingDeltaY
        isDirectionInvertedFromDevice = event.isDirectionInvertedFromDevice
    }
}
