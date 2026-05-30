import SwiftUI

struct ReconciliationPanelView<Destination: View>: View {
    let panel: LedgerReviewReconciliationPanel
    let prominence: ReconciliationPanelProminence
    let destination: (LedgerReviewReconciliationRow) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionHeader(title: panel.title)
            if let summary = panel.summary {
                Text(summary)
                    .font(prominence.summaryFont)
                    .foregroundStyle(prominence.summaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(panel.rows) { row in
                    if row.targetID != nil, !row.isMissing {
                        NavigationLink {
                            destination(row)
                        } label: {
                            rowView(row)
                        }
                        .buttonStyle(.plain)
                    } else {
                        rowView(row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LedgerSurfaceContract.contentPadding)
        .ledgerSurface(tint: prominence.surfaceTint)
        .accessibilityIdentifier(prominence.accessibilityIdentifier)
    }

    private func rowView(_ row: LedgerReviewReconciliationRow) -> some View {
        LedgerRow(
            primary: row.title,
            secondary: [
                row.detail.map {
                    LedgerRowLine(
                        text: $0,
                        tone: row.isMissing ? .attention : .neutral,
                        role: .contentPreview,
                        lineLimit: prominence.detailLineLimit
                    )
                }
            ].compactMap { $0 },
            density: prominence.rowDensity,
            emphasis: row.isMissing ? .attention : .normal
        )
    }
}

enum ReconciliationPanelProminence {
    case source
    case suggestion
    case evidence

    var summaryFont: Font {
        switch self {
        case .source, .suggestion:
            return LedgerVisualSystem.Typography.metadataValue
        case .evidence:
            return LedgerVisualSystem.Typography.sectionFooter
        }
    }

    var summaryColor: Color {
        switch self {
        case .source, .suggestion:
            return .secondary
        case .evidence:
            return Color.secondary.opacity(0.8)
        }
    }

    var rowDensity: LedgerRowDensity {
        switch self {
        case .source, .suggestion:
            return .detail
        case .evidence:
            return .compact
        }
    }

    var detailLineLimit: Int? {
        switch self {
        case .source, .suggestion:
            return 3
        case .evidence:
            return 2
        }
    }

    var surfaceTint: LedgerTone? {
        switch self {
        case .source:
            return .info
        case .suggestion:
            return .attention
        case .evidence:
            return nil
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .source:
            return "review-queue-detail-source"
        case .suggestion:
            return "review-queue-detail-question"
        case .evidence:
            return "review-queue-detail-evidence"
        }
    }
}
