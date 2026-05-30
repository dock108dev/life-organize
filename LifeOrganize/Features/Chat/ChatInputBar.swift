import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let placeholder: String
    let isCommittingSend: Bool
    let isOrganizing: Bool
    let errorMessage: String?
    let onSend: () -> Void
    @FocusState.Binding var isFocused: Bool

    private var showsComposerStatus: Bool {
        errorMessage?.isEmpty == false || isOrganizing
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCommittingSend
    }

    init(
        text: Binding<String>,
        placeholder: String = "Add anything or ask what’s due",
        isCommittingSend: Bool,
        isOrganizing: Bool,
        errorMessage: String? = nil,
        isFocused: FocusState<Bool>.Binding,
        onSend: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.isCommittingSend = isCommittingSend
        self.isOrganizing = isOrganizing
        self.errorMessage = errorMessage
        _isFocused = isFocused
        self.onSend = onSend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage, !errorMessage.isEmpty {
                composerMessage(
                    text: errorMessage,
                    tone: .danger,
                    iconName: "exclamationmark.circle"
                )
            } else if isOrganizing {
                composerMessage(
                    text: "Saved. Organizing details",
                    tone: .muted,
                    showsProgress: true
                )
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
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
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
            .padding(.top, showsComposerStatus ? 2 : 8)
            .padding(.bottom, 8)
        }
    }

    private func composerMessage(
        text: String,
        tone: LedgerTone,
        iconName: String? = nil,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
            } else if let iconName {
                Image(systemName: iconName)
                    .font(LedgerVisualSystem.Typography.rowFooter.weight(.medium))
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(LedgerVisualSystem.Typography.rowFooter)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tone == .muted ? Color.secondary : tone.foreground)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var sendBackground: some ShapeStyle {
        canSend
            ? AnyShapeStyle(LedgerPalette.accent)
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
