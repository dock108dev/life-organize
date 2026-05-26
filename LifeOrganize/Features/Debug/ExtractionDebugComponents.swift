import SwiftUI

struct ExtractionAttemptStatusChip: View {
    let status: ExtractionAttemptStatus

    var body: some View {
        DebugStatusChip(text: status.rawValue, color: status.debugColor)
    }
}

struct ExtractionStatusChip: View {
    let status: ExtractionStatus

    var body: some View {
        DebugStatusChip(text: status.rawValue, color: status.debugColor)
    }
}

private struct DebugStatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private extension ExtractionAttemptStatus {
    var debugColor: Color {
        switch self {
        case .succeeded:
            return .green
        case .partiallySucceeded:
            return .orange
        case .failed:
            return .red
        case .pending:
            return .yellow
        case .superseded:
            return .gray
        }
    }
}

private extension ExtractionStatus {
    var debugColor: Color {
        switch self {
        case .succeeded:
            return .green
        case .partiallySucceeded, .needsReview:
            return .orange
        case .failed, .failedNeedsReview:
            return .red
        case .pending, .pendingToken, .pendingRetry:
            return .yellow
        case .extracting:
            return .blue
        case .notRequired:
            return .gray
        }
    }
}

struct DebugMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.footnote)
        .frame(maxWidth: LedgerAdaptiveLayout.Width.debugDetailMax, alignment: .leading)
    }
}

enum ExtractionDebugFormatting {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static func text(for date: Date?) -> String {
        guard let date else { return "None" }
        return dateTime.string(from: date)
    }

    static func duration(start: Date, end: Date?) -> String {
        guard let end else { return "In progress" }
        return String(format: "%.2fs", end.timeIntervalSince(start))
    }
}
