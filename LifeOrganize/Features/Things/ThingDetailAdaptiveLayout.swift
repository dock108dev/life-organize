import SwiftUI

enum ThingDetailLayoutMode: Equatable {
    case compactSingleColumn
    case readableSingleColumn
    case twoColumn

    static func mode(for availableWidth: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> Self {
        if horizontalSizeClass == .compact || availableWidth < 760 {
            return .compactSingleColumn
        }
        if availableWidth < 980 {
            return .readableSingleColumn
        }
        return .twoColumn
    }

    var maxContentWidth: CGFloat {
        switch self {
        case .compactSingleColumn:
            return .greatestFiniteMagnitude
        case .readableSingleColumn:
            return 720
        case .twoColumn:
            return 1_120
        }
    }

    func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
        let gutter = LedgerAdaptiveLayout.gutter(for: availableWidth, role: .detail)
        return min(maxContentWidth, max(0, availableWidth - (2 * gutter)))
    }
}

struct ThingDetailAdaptiveContainer<
    SingleColumn: View,
    FullTop: View,
    LeftColumn: View,
    RightColumn: View,
    FullBottom: View
>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let availableWidth: CGFloat
    let singleColumn: SingleColumn
    let fullTop: FullTop
    let leftColumn: LeftColumn
    let rightColumn: RightColumn
    let fullBottom: FullBottom

    init(
        availableWidth: CGFloat,
        @ViewBuilder singleColumn: () -> SingleColumn,
        @ViewBuilder fullTop: () -> FullTop,
        @ViewBuilder leftColumn: () -> LeftColumn,
        @ViewBuilder rightColumn: () -> RightColumn,
        @ViewBuilder fullBottom: () -> FullBottom
    ) {
        self.availableWidth = availableWidth
        self.singleColumn = singleColumn()
        self.fullTop = fullTop()
        self.leftColumn = leftColumn()
        self.rightColumn = rightColumn()
        self.fullBottom = fullBottom()
    }

    var body: some View {
        let mode = ThingDetailLayoutMode.mode(for: availableWidth, horizontalSizeClass: horizontalSizeClass)

        Group {
            switch mode {
            case .compactSingleColumn, .readableSingleColumn:
                LazyVStack(alignment: .leading, spacing: 18) {
                    singleColumn
                }
            case .twoColumn:
                VStack(alignment: .leading, spacing: 18) {
                    fullTop

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 18) {
                            leftColumn
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        VStack(alignment: .leading, spacing: 18) {
                            rightColumn
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    fullBottom
                }
            }
        }
        .frame(width: mode.contentWidth(for: availableWidth), alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
