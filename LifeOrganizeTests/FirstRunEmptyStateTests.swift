import SwiftData
import XCTest
@testable import LifeOrganize

final class FirstRunEmptyStateTests: XCTestCase {
    func testFirstRunEmptyStateCopyStaysLedgerFocused() {
        XCTAssertEqual(LedgerEmptyStateContent.chat.title, "Timeline")
        XCTAssertEqual(
            LedgerEmptyStateContent.chat.body,
            "Tell me what happened or ask what is due."
        )
        XCTAssertNil(LedgerEmptyStateContent.chat.secondaryBody)
        XCTAssertEqual(LedgerEmptyStateContent.things.title, "No saved things yet")
        XCTAssertEqual(
            LedgerEmptyStateContent.things.body,
            "Add one directly or start from the timeline."
        )
        XCTAssertEqual(LedgerEmptyStateContent.rules.title, "Nothing to carry forward yet")
        XCTAssertEqual(
            LedgerEmptyStateContent.rules.body,
            "Add a reminder or capture something that should resurface."
        )
        XCTAssertEqual(LedgerEmptyStateContent.settingsNoDeviceToken.title, "AI service token")
        XCTAssertEqual(
            LedgerEmptyStateContent.settingsNoDeviceToken.body,
            "Entries stay local on this device. A private token lets the backend organize new details."
        )
        XCTAssertEqual(LedgerEmptyStateContent.searchLanding.title, "Search")
        XCTAssertEqual(LedgerEmptyStateContent.searchLanding.body, "Look up a detail, date, place, or note.")
        XCTAssertNil(LedgerEmptyStateContent.searchLanding.secondaryBody)
        XCTAssertEqual(LedgerEmptyStateContent.noSearchResults.title, "No results")
        XCTAssertEqual(
            LedgerEmptyStateContent.noSearchResults.body,
            "Try a shorter phrase or a different detail from the entry."
        )
        XCTAssertNil(LedgerEmptyStateContent.noSearchResults.secondaryBody)
    }

    @MainActor
    func testFirstRunChatSuggestionsOnlyFillDraftText() {
        let viewModel = ChatViewModel()

        XCTAssertEqual(
            ChatSuggestion.allCases.map(\.title),
            ["Log something", "Due today", "Check later", "Save note"]
        )

        viewModel.applySuggestion(.logEvent)
        XCTAssertEqual(viewModel.draft, "I ")

        viewModel.applySuggestion(.logPurchase)
        XCTAssertEqual(viewModel.draft, "What do I have to do today?")

        viewModel.applySuggestion(.addReminder)
        XCTAssertEqual(viewModel.draft, "I want to check this in a month: ")

        viewModel.applySuggestion(.addNote)
        XCTAssertEqual(viewModel.draft, "Note: ")
    }

    @MainActor
    func testChatInputPlaceholderExplainsLocalOnlyMode() {
        let viewModel = ChatViewModel()

        XCTAssertEqual(viewModel.inputPlaceholder(hasAIServiceCredential: true), "Ask what is due or add a note")
        XCTAssertEqual(
            viewModel.inputPlaceholder(hasAIServiceCredential: false),
            "Capture something locally"
        )
    }

    @MainActor
    func testChatSendDraftIgnoresWhitespaceOnlyDraft() throws {
        let context = makeInMemoryModelContext()
        let viewModel = ChatViewModel()
        viewModel.draft = "  \n\t  "
        var persistedMessageID: UUID?

        viewModel.sendDraft(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            dataGeneration: UUID(),
            isDataGenerationCurrent: { _ in true }
        ) { messageID in
            persistedMessageID = messageID
        }

        XCTAssertEqual(viewModel.draft, "  \n\t  ")
        XCTAssertFalse(viewModel.isCommittingSend)
        XCTAssertNil(persistedMessageID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 0)
    }

    @MainActor
    func testChatSendDraftPersistsRawMessageWithoutDeviceTokenBeforeClearingDraft() async throws {
        let context = makeInMemoryModelContext()
        let viewModel = ChatViewModel()
        let rawMessagePersisted = expectation(description: "Raw message persisted")
        viewModel.draft = "  No buying domains for 30 days.  "

        viewModel.sendDraft(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            dataGeneration: UUID(),
            isDataGenerationCurrent: { _ in true }
        ) { _ in
            rawMessagePersisted.fulfill()
        }

        await fulfillment(of: [rawMessagePersisted], timeout: 2)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let userMessage = try XCTUnwrap(messages.first { $0.role == .user })
        XCTAssertEqual(userMessage.text, "No buying domains for 30 days.")
        XCTAssertEqual(viewModel.draft, "")
    }
}
