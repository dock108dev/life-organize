import SwiftData
import XCTest
@testable import LifeOrganize

final class FirstRunEmptyStateTests: XCTestCase {
    func testFirstRunEmptyStateCopyStaysLedgerFocused() {
        XCTAssertEqual(LedgerEmptyStateContent.chat.title, "Timeline")
        XCTAssertEqual(
            LedgerEmptyStateContent.chat.body,
            "Type anything worth remembering. LifeOrganize will turn it into history, Things, and follow-up reminders."
        )
        XCTAssertEqual(
            LedgerEmptyStateContent.chat.secondaryBody,
            "Try a note, a task, a receipt, or “what is due today?”"
        )
        XCTAssertEqual(LedgerEmptyStateContent.things.title, "No saved things yet")
        XCTAssertEqual(
            LedgerEmptyStateContent.things.body,
            "Things are people, pets, projects, places, and accounts collected from your timeline."
        )
        XCTAssertEqual(
            LedgerEmptyStateContent.things.secondaryBody,
            "Start by capturing something, or add one directly."
        )
        XCTAssertEqual(LedgerEmptyStateContent.rules.title, "Nothing to carry forward yet")
        XCTAssertEqual(
            LedgerEmptyStateContent.rules.body,
            "Carry Forward keeps ongoing work and reminders from getting lost."
        )
        XCTAssertEqual(
            LedgerEmptyStateContent.rules.secondaryBody,
            "Add a reminder, or capture something that should resurface later."
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

    func testPrimarySurfaceContextExplainsAppModel() {
        XCTAssertEqual(LedgerContextPanelContent.timeline.title, "LifeOrganize starts here")
        XCTAssertEqual(LedgerContextPanelContent.timeline.chips, ["Capture", "Recall", "Follow up"])
        XCTAssertEqual(LedgerContextPanelContent.things.title, "Your organized subjects")
        XCTAssertEqual(LedgerContextPanelContent.things.chips, ["History", "Notes", "Reminders"])
        XCTAssertEqual(LedgerContextPanelContent.rules.title, "What should resurface")
        XCTAssertEqual(LedgerContextPanelContent.rules.chips, ["Now", "Upcoming", "Paused"])
    }

    @MainActor
    func testFirstRunChatSuggestionsOnlyFillDraftText() {
        let viewModel = ChatViewModel()

        XCTAssertEqual(
            ChatSuggestion.allCases.map(\.title),
            ["Save note", "Ask today", "Set reminder", "Log something"]
        )

        viewModel.applySuggestion(.addNote)
        XCTAssertEqual(viewModel.draft, "Note: ")

        viewModel.applySuggestion(.askToday)
        XCTAssertEqual(viewModel.draft, "What do I have to do today?")

        viewModel.applySuggestion(.addReminder)
        XCTAssertEqual(viewModel.draft, "Remind me to ")

        viewModel.applySuggestion(.logEvent)
        XCTAssertEqual(viewModel.draft, "I ")
    }

    @MainActor
    func testChatInputPlaceholderExplainsLocalOnlyMode() {
        let viewModel = ChatViewModel()

        XCTAssertEqual(viewModel.inputPlaceholder(hasAIServiceCredential: true), "Add anything or ask what’s due")
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
            isDataGenerationCurrent: { _ in true },
            onRawMessagePersisted: { messageID in
                persistedMessageID = messageID
            }
        )

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
            isDataGenerationCurrent: { _ in true },
            onRawMessagePersisted: { _ in
                rawMessagePersisted.fulfill()
            }
        )

        await fulfillment(of: [rawMessagePersisted], timeout: 2)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let userMessage = try XCTUnwrap(messages.first { $0.role == .user })
        XCTAssertEqual(userMessage.text, "No buying domains for 30 days.")
        XCTAssertEqual(viewModel.draft, "")
    }
}
