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
        placeholder: String = "Add anything or ask what’s due",
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
                    .submitLabel(.done)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }

                Button(action: onSend) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(canSend ? Color.white : Color.secondary)
                        .background(sendBackground)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(sendBorder, lineWidth: 1)
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
            .background(LedgerPalette.surfaceStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LedgerPalette.hairline, lineWidth: 1)
            }
            .padding(.horizontal, 10)
            .padding(.top, isOrganizing ? 2 : 8)
            .padding(.bottom, 8)
        }
    }

    private var sendBackground: some ShapeStyle {
        canSend
            ? AnyShapeStyle(LinearGradient(
                colors: [LedgerPalette.accent, LedgerPalette.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            : AnyShapeStyle(Color(.tertiarySystemFill))
    }

    private var sendBorder: Color {
        canSend ? Color.white.opacity(0.25) : Color.secondary.opacity(0.18)
    }
}

private struct TimelineInputMarker: View {
    let canSend: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(canSend ? LedgerPalette.accent : Color.secondary.opacity(0.28))
            .frame(width: 3, height: 22)
            .accessibilityHidden(true)
    }
}
