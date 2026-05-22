import SwiftUI

struct MetadataRow: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(LedgerVisualSystem.Typography.metadataLabel)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(LedgerVisualSystem.Typography.metadataValue)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(LedgerVisualSystem.Typography.metadataDetail)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct LedgerSummaryMetric: View {
    let label: String
    let value: String
    var detail: String?
    var fixedVerticalSizing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(LedgerVisualSystem.Typography.metadataLabel)
                .foregroundStyle(.tertiary)

            formatted(Text(value))
                .font(LedgerVisualSystem.Typography.metadataValue.weight(.semibold))
                .foregroundStyle(.primary)

            if let detail, !detail.isEmpty {
                formatted(Text(detail))
                    .font(LedgerVisualSystem.Typography.metadataDetail)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatted(_ text: Text) -> some View {
        text.fixedSize(horizontal: false, vertical: fixedVerticalSizing)
    }
}

enum LedgerOperationalMetricProminence {
    case primary
    case secondary
}

struct LedgerOperationalMetric: View {
    let label: String
    let value: String
    var detail: String?
    var prominence: LedgerOperationalMetricProminence = .secondary

    init(_ metric: ThingDetailSnapshot.SummaryMetric, prominence: LedgerOperationalMetricProminence = .secondary) {
        label = metric.label
        value = metric.value
        detail = metric.detail
        self.prominence = prominence
    }

    init(label: String, value: String, detail: String? = nil, prominence: LedgerOperationalMetricProminence = .secondary) {
        self.label = label
        self.value = value
        self.detail = detail
        self.prominence = prominence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(valueFont)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(LedgerVisualSystem.Typography.rowSecondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
    }

    private var valueFont: Font {
        switch prominence {
        case .primary:
            return .headline.weight(.semibold)
        case .secondary:
            return LedgerVisualSystem.Typography.rowDetailPrimary.weight(.medium)
        }
    }

    private var verticalPadding: CGFloat {
        switch prominence {
        case .primary:
            return 2
        case .secondary:
            return 1
        }
    }
}

struct LedgerInlineActionTray: View {
    let actions: [LedgerInlineAction]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions) { action in
                Button(action: action.handler) {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}

struct LedgerInlineAction: Identifiable {
    let title: String
    let systemImage: String
    let handler: () -> Void

    var id: String {
        title
    }
}

struct LedgerDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
            LedgerSectionHeader(title: title)
            VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum LedgerReminderRowLines {
    static func lines(for presentation: ReminderContinuityPresentation, reason: String? = nil) -> [LedgerRowLine] {
        var lines = [
            LedgerRowLine(text: presentation.primaryLine),
        ]
        if let dateLine = presentation.dateLine {
            lines.append(LedgerRowLine(text: dateLine))
        }
        if let reason, !reason.isEmpty {
            lines.append(LedgerRowLine(text: reason, lineLimit: 2))
        }
        return lines
    }

    static func lines(for presentation: ReminderContinuityPresentation, rule: LedgerRule, reason: String? = nil) -> [LedgerRowLine] {
        var lines = lines(for: presentation, reason: reason)
        if let deactivatedAt = rule.manuallyDeactivatedAt {
            lines.append(LedgerRowLine(text: "Completed or stopped \(DateFormatting.fullDate.string(from: deactivatedAt))"))
        }
        return lines
    }
}

struct SourceDisclosure: View {
    let sourceMessage: ChatMessage?
    let manualDate: Date
    var extractedIDs: [UUID] = []

    private var presentation: LedgerSourcePresentation {
        LedgerSourcePresentation(
            hasSourceMessage: sourceMessage != nil,
            manualDate: manualDate,
            extractedIDs: extractedIDs
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.title)
                .font(LedgerVisualSystem.Typography.metadataLabel)
                .foregroundStyle(.tertiary)
            if let detail = presentation.detail {
                Text(detail)
                    .font(LedgerVisualSystem.Typography.metadataValue)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LedgerSourcePresentation: Equatable {
    let title: String
    let detail: String?

    init(hasSourceMessage: Bool, manualDate: Date, extractedIDs: [UUID] = []) {
        if hasSourceMessage || !extractedIDs.isEmpty {
            title = "Added from your timeline"
            detail = nil
        } else {
            title = "Added manually"
            detail = DateFormatting.shortDate.string(from: manualDate)
        }
    }
}
