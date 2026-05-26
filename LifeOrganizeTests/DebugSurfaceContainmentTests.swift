import XCTest
@testable import LifeOrganize

final class DebugSurfaceContainmentTests: XCTestCase {
    func testDebugPayloadViewerUsesAdaptivePayloadWidth() throws {
        let source = try sourceFile("LifeOrganize/Features/Debug/DebugTextViewer.swift")

        XCTAssertTrue(source.contains(".ledgerAdaptiveWidth(.debugPayload, alignment: .leading)"))
    }

    func testExtractionDebugRowsUseReadableDebugWidths() throws {
        let listSource = try sourceFile("LifeOrganize/Features/Debug/ExtractionDebugListView.swift")
        let detailSource = try sourceFile("LifeOrganize/Features/Debug/ExtractionAttemptDebugView.swift")
        let componentsSource = try sourceFile("LifeOrganize/Features/Debug/ExtractionDebugComponents.swift")

        XCTAssertTrue(listSource.contains("LedgerAdaptiveLayout.Width.debugListMax"))
        XCTAssertTrue(detailSource.contains(".ledgerAdaptiveWidth(.debugDetail)"))
        XCTAssertTrue(detailSource.contains("LedgerAdaptiveLayout.Width.debugDetailMax"))
        XCTAssertTrue(componentsSource.contains("LedgerAdaptiveLayout.Width.debugDetailMax"))
    }

    func testInternalInspectionRowsUseReadableDebugWidths() throws {
        let detailSource = try sourceFile("LifeOrganize/Features/Debug/InternalQALabDetailViews.swift")
        let metricsSource = try sourceFile("LifeOrganize/Features/Debug/QAExtractionQualityMetricsView.swift")
        let messageSource = try sourceFile("LifeOrganize/Features/Debug/ChatMessageExtractionDebugView.swift")

        XCTAssertTrue(detailSource.contains("LedgerAdaptiveLayout.Width.debugListMax"))
        XCTAssertTrue(detailSource.contains("LedgerAdaptiveLayout.Width.debugDetailMax"))
        XCTAssertTrue(metricsSource.contains("LedgerAdaptiveLayout.Width.debugDetailMax"))
        XCTAssertTrue(messageSource.contains("LedgerAdaptiveLayout.Width.debugDetailMax"))
        XCTAssertTrue(messageSource.contains("LedgerAdaptiveLayout.Width.debugListMax"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
