import SwiftUI

enum ReviewQueueDetailLayoutMode: Equatable {
    case singleColumn
    case twoColumn
}

enum ReviewQueueDetailLayout {
    static let outerPadding: CGFloat = 16
    static let columnSpacing: CGFloat = 16
    static let contentMaxWidth: CGFloat = 680
    static let actionMinWidth: CGFloat = 300
    static let actionMaxWidth: CGFloat = 360
    static let twoColumnMinimumWidth: CGFloat = 760

    static func mode(
        for availableWidth: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass?,
        isAccessibilitySize: Bool
    ) -> ReviewQueueDetailLayoutMode {
        guard horizontalSizeClass == .regular,
              availableWidth >= twoColumnMinimumWidth,
              !isAccessibilitySize else {
            return .singleColumn
        }
        return .twoColumn
    }

    static func actionColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        min(actionMaxWidth, max(actionMinWidth, availableWidth * 0.32))
    }
}
