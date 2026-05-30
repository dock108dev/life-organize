import SwiftUI

enum ThingDetailSheet: Identifiable {
    case addEvent
    case addRule
    case editRule(LedgerRule)
    case addNote
    case editNote(LedgerNote)
    case editThing
    case deleteWithReassign

    var id: String {
        switch self {
        case .addEvent:
            "add-event"
        case .addRule:
            "add-rule"
        case .editRule(let rule):
            "edit-rule-\(rule.id)"
        case .addNote:
            "add-note"
        case .editNote(let note):
            "edit-note-\(note.id)"
        case .editThing:
            "edit-thing"
        case .deleteWithReassign:
            "delete-with-reassign"
        }
    }
}

struct LedgerEventRow: View {
    let event: LedgerEvent

    var body: some View {
        LedgerRow(
            primary: event.title,
            secondary: rowLines,
            density: LedgerSurfaceDensity.detailSummary.rowDensity
        )
    }

    private var rowLines: [LedgerRowLine] {
        var lines = [
            LedgerRowLine(text: DateFormatting.fullDate.string(from: event.occurredAt), role: .metadata)
        ]
        if let metadata = EventMetadataDisplayFormatter.summary(for: event.metadataEntries, eventType: event.eventType, limit: 3) {
            lines.append(LedgerRowLine(text: metadata, role: .contentPreview))
        }
        if let note = event.note, !note.isEmpty {
            lines.append(LedgerRowLine(text: note, role: .contentPreview))
        }
        return lines
    }
}

struct LedgerRuleRow: View {
    let rule: LedgerRule
    let reviewPresentation: LedgerReviewItemPresentation?
    let density: LedgerRowDensity
    let emphasis: LedgerRowEmphasis
    let reasonText: String?
    private let continuityService = ReminderContinuityPresentationService()

    init(
        rule: LedgerRule,
        reviewPresentation: LedgerReviewItemPresentation?,
        density: LedgerRowDensity = LedgerSurfaceDensity.detailSummary.rowDensity,
        emphasis: LedgerRowEmphasis = .normal,
        reasonText: String? = nil
    ) {
        self.rule = rule
        self.reviewPresentation = reviewPresentation
        self.density = density
        self.emphasis = emphasis
        self.reasonText = reasonText
    }

    var body: some View {
        let presentation = continuityService.presentation(for: rule)
        let candidateBadges = presentation.badges + [reviewPresentation?.badge].compactMap(\.self)
        let visibleBadges = LedgerBadgePresentation.primaryBadges(from: candidateBadges)

        LedgerRow(
            primary: rule.title,
            secondary: rowLines(for: presentation),
            density: density,
            emphasis: emphasis
        ) {
            ForEach(visibleBadges) { badge in
                LedgerBadgePill(badge: badge, size: .small)
            }
        }
        .accessibilityLabel(accessibilityLabel(for: presentation, candidateBadges: candidateBadges, visibleBadges: visibleBadges))
    }

    private func rowLines(for presentation: ReminderContinuityPresentation) -> [LedgerRowLine] {
        var lines = LedgerReminderRowLines.lines(for: presentation, rule: rule, reason: reasonText ?? rule.reason)
        if let reviewPresentation {
            lines.append(reviewPresentation.rowLine)
        }
        return lines
    }

    private func accessibilityLabel(
        for presentation: ReminderContinuityPresentation,
        candidateBadges: [LedgerBadgePresentation],
        visibleBadges: [LedgerBadgePresentation]
    ) -> String {
        let hiddenBadges = LedgerBadgePresentation.hiddenBadges(from: candidateBadges, visibleBadges: visibleBadges)
        return ([rule.title] + visibleBadges.map(\.label) + hiddenBadges.map(\.label) + rowLines(for: presentation).map(\.text))
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

struct ThingDetailRuleSection: View {
    let title: String
    let rules: [LedgerRule]
    let startsExpanded: Bool
    @Binding var isExpanded: Bool
    let reviewPresentation: (LedgerRule) -> LedgerReviewItemPresentation?
    let onSelectRule: (LedgerRule) -> Void
    let onError: (String) -> Void

    var body: some View {
        Group {
            if startsExpanded {
                LedgerDetailSection(title: title) {
                    rows
                }
            } else {
                LedgerDisclosureSection(
                    title: title,
                    summary: LedgerDisplayFormatting.count(rules.count, singular: "reminder", plural: "reminders"),
                    isExpanded: $isExpanded
                ) {
                    rows
                }
            }
        }
        .accessibilityIdentifier("thing-detail-rules-section")
    }

    private var rows: some View {
        ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
            let presentation = reviewPresentation(rule)
            Button {
                onSelectRule(rule)
            } label: {
                LedgerRuleRow(rule: rule, reviewPresentation: presentation)
            }
            .buttonStyle(.plain)
            .ledgerReviewItemContextMenu(presentation?.item, onError: onError)

            if index < rules.count - 1 {
                Divider()
            }
        }
    }
}

struct LedgerNoteRow: View {
    let note: LedgerNote

    var body: some View {
        LedgerRow(
            primary: note.text,
            secondary: [LedgerRowLine(text: DateFormatting.fullDate.string(from: note.updatedAt), tone: .note, role: .metadata)],
            density: LedgerSurfaceDensity.detailSummary.rowDensity
        )
    }
}
