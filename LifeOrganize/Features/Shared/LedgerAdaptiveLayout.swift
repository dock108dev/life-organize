import SwiftUI

enum LedgerAdaptiveWidthRole: CaseIterable, Equatable {
    case readable
    case detail
    case form
    case sheet
    case debugList
    case debugDetail
    case debugPayload
    case fullBleed
}

enum LedgerEditFormWidthRole: CaseIterable, Equatable {
    case thing
    case event
    case note
    case rule
    case deleteReassignment
}

enum LedgerAdaptiveLayout {
    enum Width {
        static let readableMax: CGFloat = 680
        static let detailMax: CGFloat = 820
        static let formMax: CGFloat = 560
        static let sheetMax: CGFloat = 520
        static let debugListMax: CGFloat = 760
        static let debugDetailMax: CGFloat = 820
        static let debugPayloadMax: CGFloat = 920
        static let emptyStateMax: CGFloat = 320
    }

    enum EmptyState {
        static let contentMaxWidth: CGFloat = Width.emptyStateMax
        static let surfaceMaxWidth: CGFloat = 430
        static let horizontalPadding: CGFloat = LedgerVisualSystem.Padding.noticeHorizontal
        static let verticalPadding: CGFloat = 28
        static let secondaryVerticalPadding: CGFloat = 22
        static let cornerRadius: CGFloat = 18
        static let searchLandingMinHeight: CGFloat = 420
    }

    enum Gutter {
        static let compact: CGFloat = 16
        static let regular: CGFloat = 20
        static let spacious: CGFloat = 28
        static let wide: CGFloat = 40
        static let formRegular: CGFloat = 24
    }

    static func maxWidth(for role: LedgerAdaptiveWidthRole) -> CGFloat? {
        switch role {
        case .readable:
            return Width.readableMax
        case .detail:
            return Width.detailMax
        case .form:
            return Width.formMax
        case .sheet:
            return Width.sheetMax
        case .debugList:
            return Width.debugListMax
        case .debugDetail:
            return Width.debugDetailMax
        case .debugPayload:
            return Width.debugPayloadMax
        case .fullBleed:
            return nil
        }
    }

    static func editFormMaxWidth(for role: LedgerEditFormWidthRole) -> CGFloat {
        switch role {
        case .thing, .note:
            return 560
        case .event:
            return 640
        case .rule:
            return 600
        case .deleteReassignment:
            return 520
        }
    }

    static func gutter(for availableWidth: CGFloat, role: LedgerAdaptiveWidthRole) -> CGFloat {
        switch role {
        case .sheet:
            return availableWidth < 380 ? Gutter.compact : Gutter.regular
        case .fullBleed:
            return 0
        case .form:
            if availableWidth < 380 {
                return Gutter.compact
            }
            if availableWidth < 700 {
                return Gutter.regular
            }
            return Gutter.formRegular
        case .readable, .detail, .debugList, .debugDetail, .debugPayload:
            if availableWidth < 380 {
                return Gutter.compact
            }
            if availableWidth < 760 {
                return Gutter.regular
            }
            if availableWidth < 1_100 {
                return Gutter.spacious
            }
            return Gutter.wide
        }
    }

    static func contentWidth(for availableWidth: CGFloat, role: LedgerAdaptiveWidthRole) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
        let widthAfterGutters = Swift.max(0, availableWidth - (2 * gutter(for: availableWidth, role: role)))
        guard let maxWidth = maxWidth(for: role) else {
            return availableWidth
        }
        return Swift.min(maxWidth, widthAfterGutters)
    }
}

private struct LedgerEditFormWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let role: LedgerEditFormWidthRole

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: LedgerAdaptiveLayout.editFormMaxWidth(for: role))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
    }
}

private struct LedgerAdaptiveWidthModifier: ViewModifier {
    let role: LedgerAdaptiveWidthRole
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: LedgerAdaptiveLayout.maxWidth(for: role) ?? .infinity, alignment: .leading)
            .containerRelativeFrame(.horizontal, alignment: alignment) { availableWidth, _ in
                LedgerAdaptiveLayout.contentWidth(for: availableWidth, role: role)
            }
    }
}

extension View {
    func ledgerAdaptiveWidth(
        _ role: LedgerAdaptiveWidthRole,
        alignment: Alignment = .center
    ) -> some View {
        modifier(LedgerAdaptiveWidthModifier(role: role, alignment: alignment))
    }

    func ledgerEditFormWidth(_ role: LedgerEditFormWidthRole) -> some View {
        modifier(LedgerEditFormWidthModifier(role: role))
    }
}
