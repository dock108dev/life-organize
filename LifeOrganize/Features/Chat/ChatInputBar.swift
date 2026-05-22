import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let placeholder: String
    let isCommittingSend: Bool
    let isOrganizing: Bool
    let onSend: () -> Void
    @FocusState.Binding var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCommittingSend
    }

    init(
        text: Binding<String>,
        placeholder: String = "Ask what is due or add a note",
        isCommittingSend: Bool,
        isOrganizing: Bool,
        isFocused: FocusState<Bool>.Binding,
        onSend: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.isCommittingSend = isCommittingSend
        self.isOrganizing = isOrganizing
        _isFocused = isFocused
        self.onSend = onSend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isOrganizing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)

                    Text("Connecting details...")
                        .font(LedgerVisualSystem.Typography.rowFooter)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            HStack(alignment: .center, spacing: 8) {
                TimelineInputMarker(canSend: canSend)

                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(LedgerVisualSystem.Typography.rowPrimary)
                    .accessibilityIdentifier("chat-input")
                    .padding(.vertical, 6)
                    .submitLabel(.return)

                Button(action: onSend) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(canSend ? Color.white : Color.secondary)
                        .background(canSend ? Color.accentColor : Color(.tertiarySystemFill))
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.secondary.opacity(canSend ? 0 : 0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to Timeline")
                .accessibilityIdentifier("chat-send-button")
                .disabled(!canSend)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
                .overlay(Color.secondary.opacity(0.18))
        }
    }
}

private struct TimelineInputMarker: View {
    let canSend: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.28))
            .frame(width: 3, height: 22)
            .accessibilityHidden(true)
    }
}
