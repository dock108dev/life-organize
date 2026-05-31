import SwiftUI

struct ThingDetailSummarySection: View {
    let thing: Thing
    let snapshot: ThingDetailSnapshot
    let reviewPresentation: LedgerReviewItemPresentation?
    let statusTone: LedgerTone
    let actionTitle: (LedgerReviewItemKind) -> String?
    let onPerformAction: (LedgerReviewItemKind) -> Void

    var body: some View {
        LedgerDetailSection(title: "Summary") {
            LedgerRow(
                primary: thing.name,
                secondary: summaryHeaderLines,
                density: LedgerSurfaceDensity.detailSummary.rowDensity,
                emphasis: snapshot.status == .active ? .active : .normal
            ) {
                LedgerPill(text: snapshot.status.rawValue, tone: statusTone, size: .small)
            }
            if let primaryOperationalSummary = snapshot.primaryOperationalSummary {
                operationalSummaryRow(primaryOperationalSummary)
            }
            if let continuitySummary = snapshot.continuitySummary {
                operationalSummaryRow(continuitySummary)
            }
            if shouldShowReminderSummary {
                operationalSummaryRow(snapshot.reminderSummary)
            }
            if !snapshot.hasHistory {
                operationalSummaryRow(
                    label: "Last activity",
                    value: "No history yet",
                    detail: "Add an event, reminder, or note to start this thing's history."
                )
            }
            if let reviewPresentation, shouldShowReviewSummary(reviewPresentation) {
                reviewSummaryRow(reviewPresentation)
            }
            if let reminderHistorySummary = snapshot.reminderHistorySummary {
                Text(reminderHistorySummary.value)
                    .font(LedgerVisualSystem.Typography.rowSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("thing-detail-title")
    }

    private var summaryHeaderLines: [LedgerRowLine] {
        let detail = snapshot.statusSummary.detail ?? "Selected thing"
        return [LedgerRowLine(text: detail, tone: .muted, role: .contentPreview)]
    }

    private func operationalSummaryRow(_ metric: ThingDetailSnapshot.SummaryMetric) -> some View {
        LedgerRow(
            primary: metric.value,
            secondary: operationalRowLines(for: metric),
            density: LedgerSurfaceDensity.detailSummary.rowDensity
        ) {
            EmptyView()
        }
    }

    private func operationalSummaryRow(label: String, value: String, detail: String? = nil) -> some View {
        operationalSummaryRow(ThingDetailSnapshot.SummaryMetric(label: label, value: value, detail: detail))
    }

    private func operationalRowLines(for metric: ThingDetailSnapshot.SummaryMetric) -> [LedgerRowLine] {
        [LedgerRowLine(text: metric.label, tone: .muted, role: .metadata)]
            + [metric.detail].compactMap { $0?.nilIfEmpty }.map {
                LedgerRowLine(text: $0, role: .contentPreview)
            }
    }

    private func reviewSummaryRow(_ presentation: LedgerReviewItemPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LedgerRow(
                primary: presentation.title,
                secondary: reviewSummaryLines(for: presentation),
                density: LedgerSurfaceDensity.detailSummary.rowDensity,
                emphasis: presentation.isHighPriority ? .active : .normal
            ) {
                LedgerBadgePill(badge: presentation.badge, size: .small)
            }
            if let title = actionTitle(presentation.item.kind) {
                LedgerInlineActionTray(actions: [
                    LedgerInlineAction(
                        title: title,
                        systemImage: "arrow.right.circle",
                        handler: { onPerformAction(presentation.item.kind) }
                    )
                ])
            }
        }
    }

    private func reviewSummaryLines(for presentation: LedgerReviewItemPresentation) -> [LedgerRowLine] {
        [presentation.detail].compactMap { $0?.nilIfEmpty }.map {
            LedgerRowLine(text: $0, role: .contentPreview)
        }
    }

    private var shouldShowReminderSummary: Bool {
        snapshot.reminderSummary.value != "No reminders" || !snapshot.hasHistory
    }

    private func shouldShowReviewSummary(_ presentation: LedgerReviewItemPresentation) -> Bool {
        actionTitle(presentation.item.kind) != nil
    }
}
