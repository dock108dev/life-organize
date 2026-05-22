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
            LedgerRowLine(text: DateFormatting.fullDate.string(from: event.occurredAt))
        ]
        if let metadata = EventMetadataDisplayFormatter.summary(for: event.metadataEntries, eventType: event.eventType, limit: 3) {
            lines.append(LedgerRowLine(text: metadata))
        }
        if let note = event.note, !note.isEmpty {
            lines.append(LedgerRowLine(text: note))
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

        LedgerRow(
            primary: rule.title,
            secondary: rowLines(for: presentation),
            density: density,
            emphasis: emphasis
        ) {
            ForEach(presentation.badges) { badge in
                LedgerBadgePill(badge: badge, size: .small)
            }
            if let reviewPresentation {
                LedgerBadgePill(badge: reviewPresentation.badge, size: .small)
            }
        }
    }

    private func rowLines(for presentation: ReminderContinuityPresentation) -> [LedgerRowLine] {
        var lines = LedgerReminderRowLines.lines(for: presentation, rule: rule, reason: reasonText ?? rule.reason)
        if let reviewPresentation {
            lines.append(reviewPresentation.rowLine)
        }
        return lines
    }
}

struct LedgerNoteRow: View {
    let note: LedgerNote

    var body: some View {
        LedgerRow(
            primary: note.text,
            secondary: [LedgerRowLine(text: DateFormatting.fullDate.string(from: note.updatedAt), tone: .note)],
            density: LedgerSurfaceDensity.detailSummary.rowDensity
        )
    }
}
