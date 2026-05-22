import SwiftUI

struct LedgerReviewItemMenuCommands: View {
    static let guidanceMessage = "Open Review to update this item. No automatic change has been made."

    let onError: (String) -> Void

    var body: some View {
        Button("Open Review to Update") {
            onError(Self.guidanceMessage)
        }
    }
}

private struct LedgerReviewItemContextMenuModifier: ViewModifier {
    let item: LedgerReviewItem?
    let onError: (String) -> Void

    func body(content: Content) -> some View {
        if item != nil {
            content.contextMenu {
                LedgerReviewItemMenuCommands(onError: onError)
            }
        } else {
            content
        }
    }
}

extension View {
    func ledgerReviewItemContextMenu(
        _ item: LedgerReviewItem?,
        onError: @escaping (String) -> Void
    ) -> some View {
        modifier(LedgerReviewItemContextMenuModifier(item: item, onError: onError))
    }
}
