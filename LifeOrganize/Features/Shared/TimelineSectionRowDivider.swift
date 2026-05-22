import SwiftUI

enum TimelineSectionRowDividerStyle {
    static let opacity: Double = 0.18
    static let height: CGFloat = 0.5
    static let trailingPadding: CGFloat = 6
}

struct TimelineSectionRowDivider: View {
    let leadingPadding: CGFloat

    var body: some View {
        Rectangle()
            .fill(.tertiary.opacity(TimelineSectionRowDividerStyle.opacity))
            .frame(height: TimelineSectionRowDividerStyle.height)
            .padding(.leading, leadingPadding)
            .padding(.trailing, TimelineSectionRowDividerStyle.trailingPadding)
            .accessibilityHidden(true)
    }
}
