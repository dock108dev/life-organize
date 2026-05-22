import Foundation

@MainActor
final class AppSessionState: ObservableObject {
    @Published private(set) var dataGeneration = UUID()
    @Published private(set) var resetToken = UUID()

    func resetAfterLocalDataClear() {
        invalidateInFlightDataWork()
        reloadAfterLocalDataClear()
    }

    func invalidateInFlightDataWork() {
        dataGeneration = UUID()
    }

    func reloadAfterLocalDataClear() {
        resetToken = UUID()
    }

    func isCurrentDataGeneration(_ generation: UUID) -> Bool {
        generation == dataGeneration
    }
}
