import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LocalFirstSearchVisibilityTests: XCTestCase {
    func testFailedRawEntryStaysFindableWithoutStructuredRecords() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(
            role: .user,
            text: "Replaced attic filter before the connection failed.",
            createdAt: fixedTestNow,
            extractionStatus: .pendingRetry,
            extractionErrorCode: .networkUnavailable
        )
        context.insert(message)
        try context.save()

        let search = SearchService()
        let records = search.records(
            things: [],
            events: [],
            rules: [],
            notes: [],
            messages: try context.fetch(FetchDescriptor<ChatMessage>()).filter { $0.role == .user }
        )
        let results = search.search("attic filter", in: records)
        let recall = try ChatRecallResponseService(modelContext: context, now: fixedTestNow)
            .answer(for: ChatIntentClassification(intent: .localSearch, targetText: "attic filter"))

        XCTAssertEqual(results.first?.sourceKind, .chatMessage)
        XCTAssertEqual(results.first?.body, message.text)
        XCTAssertTrue(recall.contains(message.text))
    }
}
