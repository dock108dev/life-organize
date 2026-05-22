import SwiftUI

struct LedgerContextPanelContent: Equatable {
    let symbolName: String
    let title: String
    let body: String
    let chips: [String]
    let tone: LedgerTone
}

extension LedgerContextPanelContent {
    static let timeline = LedgerContextPanelContent(
        symbolName: "sparkles",
        title: "LifeOrganize starts here",
        body: "Capture a note, task, receipt, or question in plain language. It becomes timeline history, organized Things, and follow-up reminders.",
        chips: ["Capture", "Recall", "Follow up"],
        tone: .link
    )

    static let things = LedgerContextPanelContent(
        symbolName: "tray.full",
        title: "Your organized subjects",
        body: "People, pets, projects, places, and accounts collected from the timeline. Open one to see its history and next steps.",
        chips: ["History", "Notes", "Reminders"],
        tone: .info
    )

    static let rules = LedgerContextPanelContent(
        symbolName: "checklist",
        title: "What should resurface",
        body: "Ongoing work and reminders live here, grouped by what needs attention now, soon, or later.",
        chips: ["Now", "Upcoming", "Paused"],
        tone: .attention
    )
}

struct LedgerContextPanel: View {
    let content: LedgerContextPanelContent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: content.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(content.tone.foreground)
                .frame(width: 34, height: 34)
                .background(content.tone.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(content.tone.foreground.opacity(0.18), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(content.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    ForEach(content.chips, id: \.self) { chip in
                        LedgerPill(text: chip, tone: content.tone, size: .micro)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .ledgerSurface(cornerRadius: 18, tint: content.tone)
        .accessibilityElement(children: .combine)
    }
}
