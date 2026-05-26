import Foundation

struct ReviewQueueSelectionRepairResult: Equatable {
    let selectedID: UUID?
    let lastAppliedFocusedID: UUID?
}

enum ReviewQueueSelectionRepair {
    static func repairedSelection(
        selectedID: UUID?,
        preferredFocusedID: UUID?,
        lastAppliedFocusedID: UUID?,
        previousVisibleIDs: [UUID],
        currentVisibleIDs: [UUID]
    ) -> ReviewQueueSelectionRepairResult {
        guard !currentVisibleIDs.isEmpty else {
            return ReviewQueueSelectionRepairResult(
                selectedID: nil,
                lastAppliedFocusedID: lastAppliedFocusedID
            )
        }

        if let preferredFocusedID,
           currentVisibleIDs.contains(preferredFocusedID),
           lastAppliedFocusedID != preferredFocusedID {
            return ReviewQueueSelectionRepairResult(
                selectedID: preferredFocusedID,
                lastAppliedFocusedID: preferredFocusedID
            )
        }

        if let selectedID, currentVisibleIDs.contains(selectedID) {
            return ReviewQueueSelectionRepairResult(
                selectedID: selectedID,
                lastAppliedFocusedID: lastAppliedFocusedID
            )
        }

        return ReviewQueueSelectionRepairResult(
            selectedID: replacementSelectionID(
                selectedID: selectedID,
                previousVisibleIDs: previousVisibleIDs,
                currentVisibleIDs: currentVisibleIDs
            ),
            lastAppliedFocusedID: lastAppliedFocusedID
        )
    }

    private static func replacementSelectionID(
        selectedID: UUID?,
        previousVisibleIDs: [UUID],
        currentVisibleIDs: [UUID]
    ) -> UUID? {
        guard let selectedID,
              let previousIndex = previousVisibleIDs.firstIndex(of: selectedID) else {
            return currentVisibleIDs.first
        }

        let replacementIndex = min(previousIndex, currentVisibleIDs.count - 1)
        return currentVisibleIDs[replacementIndex]
    }
}
