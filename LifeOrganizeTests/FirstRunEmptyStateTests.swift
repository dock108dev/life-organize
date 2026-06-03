import SwiftData
import XCTest
@testable import LifeOrganize

final class FirstRunEmptyStateTests: XCTestCase {
    func testFirstRunEmptyStateCopyStaysLedgerFocused() {
        XCTAssertEqual(LedgerEmptyStateContent.chat.title, "Timeline")
        XCTAssertEqual(
            LedgerEmptyStateContent.chat.body,
            "Capture anything worth remembering. LifeOrganize turns it into history, Things, and follow-up reminders."
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
            "Start from the timeline, or add one directly."
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
        XCTAssertEqual(LedgerEmptyStateContent.searchLanding.title, "Search")
        XCTAssertEqual(LedgerEmptyStateContent.searchLanding.body, "Look up a detail, date, place, or note.")
        XCTAssertNil(LedgerEmptyStateContent.searchLanding.secondaryBody)
        XCTAssertEqual(LedgerEmptyStateContent.noSearchResults.title, "No results")
        XCTAssertEqual(
            LedgerEmptyStateContent.noSearchResults.body,
            "Try a shorter phrase or a different detail."
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
        XCTAssertEqual(LedgerContextPanelContent.rules.tone, .muted)
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
    func testChatInputPlaceholderUsesBackendServiceSSOT() {
        let viewModel = ChatViewModel()

        XCTAssertEqual(viewModel.inputPlaceholder, "Add anything or ask what’s due")
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

    @MainActor
    func testChatOrganizationStatusStartsOnlyAfterRawMessagePersists() async throws {
        let context = makeInMemoryModelContext()
        let sendStarted = expectation(description: "Send started")
        var allowRawPersistence: CheckedContinuation<Void, Never>?
        var allowFinish: CheckedContinuation<Void, Never>?
        let viewModel = ChatViewModel { text, modelContext, _, _, _, onRawMessagePersisted in
            sendStarted.fulfill()
            await withCheckedContinuation { continuation in
                allowRawPersistence = continuation
            }
            let message = ChatMessage(role: .user, text: text, extractionStatus: .pending)
            modelContext.insert(message)
            try modelContext.save()
            onRawMessagePersisted(message)
            await withCheckedContinuation { continuation in
                allowFinish = continuation
            }
        }
        viewModel.draft = "Book a dentist appointment."

        viewModel.sendDraft(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            dataGeneration: UUID(),
            isDataGenerationCurrent: { _ in true }
        )

        await fulfillment(of: [sendStarted], timeout: 2)
        XCTAssertTrue(viewModel.isCommittingSend)
        XCTAssertFalse(viewModel.isOrganizing)

        allowRawPersistence?.resume()
        let didStartOrganizing = await waitForViewModelState { viewModel.isOrganizing }
        XCTAssertTrue(didStartOrganizing)
        XCTAssertFalse(viewModel.isCommittingSend)
        XCTAssertEqual(viewModel.draft, "")

        allowFinish?.resume()
        let didFinishOrganizing = await waitForViewModelState { !viewModel.isOrganizing }
        XCTAssertTrue(didFinishOrganizing)
    }

    @MainActor
    func testChatOrganizationCountHandlesRapidRepeatedSends() async throws {
        let context = makeInMemoryModelContext()
        var finishSendContinuations: [CheckedContinuation<Void, Never>] = []
        let firstMessagePersisted = expectation(description: "First raw message persisted")
        let secondMessagePersisted = expectation(description: "Second raw message persisted")
        var persistedCount = 0
        let viewModel = ChatViewModel { text, modelContext, _, _, _, onRawMessagePersisted in
            let message = ChatMessage(role: .user, text: text, extractionStatus: .pending)
            modelContext.insert(message)
            try modelContext.save()
            onRawMessagePersisted(message)
            await withCheckedContinuation { continuation in
                finishSendContinuations.append(continuation)
            }
        }

        viewModel.draft = "First timeline entry."
        viewModel.sendDraft(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            dataGeneration: UUID(),
            isDataGenerationCurrent: { _ in true },
            onRawMessagePersisted: { _ in
                persistedCount += 1
                firstMessagePersisted.fulfill()
            }
        )
        await fulfillment(of: [firstMessagePersisted], timeout: 2)
        XCTAssertEqual(viewModel.activeOrganizationCount, 1)
        XCTAssertFalse(viewModel.isCommittingSend)

        viewModel.draft = "Second timeline entry."
        viewModel.sendDraft(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            dataGeneration: UUID(),
            isDataGenerationCurrent: { _ in true },
            onRawMessagePersisted: { _ in
                persistedCount += 1
                secondMessagePersisted.fulfill()
            }
        )
        await fulfillment(of: [secondMessagePersisted], timeout: 2)
        XCTAssertEqual(persistedCount, 2)
        XCTAssertEqual(viewModel.activeOrganizationCount, 2)

        finishSendContinuations.removeFirst().resume()
        let didDecrementFirstSend = await waitForViewModelState { viewModel.activeOrganizationCount == 1 }
        XCTAssertTrue(didDecrementFirstSend)

        finishSendContinuations.removeFirst().resume()
        let didFinishAllSends = await waitForViewModelState { !viewModel.isOrganizing }
        XCTAssertTrue(didFinishAllSends)
        XCTAssertNil(viewModel.sendError)
    }

    @MainActor
    func testChatSendErrorsUseActionableProductCopy() async throws {
        XCTAssertEqual(
            ChatViewModel.userFacingSendErrorMessage(for: AppError.timeout, didPersistRawMessage: false),
            "Couldn't save that. Check your connection and try again."
        )
        XCTAssertEqual(
            ChatViewModel.userFacingSendErrorMessage(for: AppError.invalidServiceToken, didPersistRawMessage: true),
            "Saved on this device. The service is unavailable right now."
        )

        let context = makeInMemoryModelContext()
        let rawMessagePersisted = expectation(description: "Raw message persisted")
        let viewModel = ChatViewModel { text, modelContext, _, _, _, onRawMessagePersisted in
            let message = ChatMessage(role: .user, text: text, extractionStatus: .pending)
            modelContext.insert(message)
            try modelContext.save()
            onRawMessagePersisted(message)
            throw AppError.timeout
        }
        viewModel.draft = "Save this before the connection fails."

        viewModel.sendDraft(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            dataGeneration: UUID(),
            isDataGenerationCurrent: { _ in true },
            onRawMessagePersisted: { _ in rawMessagePersisted.fulfill() }
        )

        await fulfillment(of: [rawMessagePersisted], timeout: 2)
        let didClearOrganizationStatus = await waitForViewModelState { !viewModel.isOrganizing }
        XCTAssertTrue(didClearOrganizationStatus)
        XCTAssertEqual(
            viewModel.sendError,
            "Saved on this device. The service is unavailable right now."
        )
    }

    @MainActor
    private func waitForViewModelState(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
