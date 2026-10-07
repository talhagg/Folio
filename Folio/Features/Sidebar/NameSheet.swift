import SwiftUI

/// Defter/bölüm adı kuralları: boş olamaz, aynı düzeyde aynı ad iki kez kullanılamaz
/// (büyük/küçük harf ve Türkçe İ/ı farkı gözetmeden).
enum NameValidation {
    enum Issue: Equatable {
        case empty, duplicate
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "tr_TR"))
    }

    static func issue(for name: String, existing: [String]) -> Issue? {
        let candidate = normalized(name)
        if candidate.isEmpty { return .empty }
        if existing.contains(where: { normalized($0) == candidate }) { return .duplicate }
        return nil
    }

    /// "Yeni Defter", varsa "Yeni Defter 2", "Yeni Defter 3"…
    static func uniqueName(_ base: String, existing: [String]) -> String {
        guard issue(for: base, existing: existing) == .duplicate else { return base }
        var counter = 2
        while issue(for: "\(base) \(counter)", existing: existing) == .duplicate { counter += 1 }
        return "\(base) \(counter)"
    }
}

/// Ad sorma penceresi: yeni defter (renk seçimiyle), yeni bölüm ya da yeniden adlandırma.
struct NameSheet: View {
    enum Kind {
        case notebook, section

        var duplicateMessage: String {
            switch self {
            case .notebook: String(localized: "Bu isimde bir defter zaten var.")
            case .section: String(localized: "Bu isimde bir bölüm zaten var.")
            }
        }
    }

    let kind: Kind
    let title: String
    let confirmTitle: String
    let existingNames: [String]
    /// Doluysa renk seçimi gösterilir.
    var initialColor: GroupColor?
    let onConfirm: (String, GroupColor?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: GroupColor?
    @FocusState private var isFocused: Bool

    init(
        kind: Kind, title: String, confirmTitle: String, initialName: String, existingNames: [String],
        initialColor: GroupColor? = nil, onConfirm: @escaping (String, GroupColor?) -> Void
    ) {
        self.kind = kind
        self.title = title
        self.confirmTitle = confirmTitle
        self.existingNames = existingNames
        self.initialColor = initialColor
        self.onConfirm = onConfirm
        self._name = State(initialValue: initialName)
        self._color = State(initialValue: initialColor)
    }

    private var issue: NameValidation.Issue? { NameValidation.issue(for: name, existing: existingNames) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            Text(title)
                .textStyle(.windowTitle)
                .foregroundStyle(Color.ds.ink)

            VStack(alignment: .leading, spacing: Metrics.Spacing.s1) {
                TextField("İsim", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(confirm)
                Group {
                    if issue == .duplicate {
                        Label(kind.duplicateMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color.ds.statusBlocked)
                    } else {
                        Text(" ")
                    }
                }
                .textStyle(.caption)
            }

            if color != nil {
                Text("Renk")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
                HStack(spacing: Metrics.Spacing.s2) {
                    ForEach(GroupColor.allCases, id: \.self) { option in
                        Button {
                            color = option
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 20, height: 20)
                                .padding(3)
                                .overlay(Circle().strokeBorder(color == option ? option.color : .clear, lineWidth: 2))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(Text(option.title))
                        .accessibilityLabel(Text(option.title))
                        .accessibilityAddTraits(color == option ? .isSelected : [])
                    }
                }
            }

            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(issue != nil)
            }
        }
        .padding(Metrics.Spacing.s4)
        .frame(width: 340)
        .onAppear { isFocused = true }
    }

    private func confirm() {
        guard issue == nil else { return }
        onConfirm(name.trimmingCharacters(in: .whitespacesAndNewlines), color)
        dismiss()
    }
}
