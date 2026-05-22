import XCTest
@testable import LifeOrganize

final class ChatIntentClassifierTests: XCTestCase {
    func testClassifiesEmptyInputAsUnsupported() {
        XCTAssertEqual(classify("   \n\t").intent, .unsupported)
    }

    func testClassifiesEventLogging() {
        XCTAssertEqual(classify("Changed oil today.").intent, .createEvent)
    }

    func testClassifiesRuleCreation() {
        XCTAssertEqual(classify("No buying domains for 30 days.").intent, .createRule)
    }

    func testClassifiesFutureReviewLanguageAsRuleCreation() {
        let examples = [
            "Reevaluate buying domains in 90 days.",
            "We should revisit subscriptions next month.",
            "Review later on June 1.",
            "Check again in 2 weeks.",
            "Check back Friday.",
            "Follow up about passport next week.",
            "Remind me to replace the filter tomorrow."
        ]

        for input in examples {
            XCTAssertEqual(classify(input).intent, .createRule, input)
        }
    }

    func testFutureReviewRoutingRequiresTimeReference() {
        XCTAssertEqual(classify("Reevaluate the plan.").intent, .createNote)
    }

    func testClassifiesNoteCreation() {
        XCTAssertEqual(classify("The spare filters are in the hall closet.").intent, .createNote)
    }

    func testClassifiesLastTimeLookup() {
        let classification = classify("When did I last change oil?")

        XCTAssertEqual(classification.intent, .lookupLastTime)
        XCTAssertEqual(classification.targetText, "change oil")
    }

    func testClassifiesCommonLastTimeLookupShapes() {
        let lastOilChange = classify("Last oil change?")
        let whenWasLastOilChange = classify("When was the last oil change?")
        let alreadyCleanedKitchen = classify("Did I already clean the kitchen?")

        XCTAssertEqual(lastOilChange.intent, .lookupLastTime)
        XCTAssertEqual(lastOilChange.targetText, "oil change")
        XCTAssertEqual(whenWasLastOilChange.intent, .lookupLastTime)
        XCTAssertEqual(whenWasLastOilChange.targetText, "oil change")
        XCTAssertEqual(alreadyCleanedKitchen.intent, .lookupLastTime)
        XCTAssertEqual(alreadyCleanedKitchen.targetText, "clean the kitchen")
    }

    func testClassifiesRuleLookup() {
        let classification = classify("Can I buy another domain?")
        let whenAllowed = classify("When can I buy domains again?")
        let ruleAbout = classify("Is there a rule about monitors?")
        let reminderAbout = classify("Is there a reminder about filters?")

        XCTAssertEqual(classification.intent, .lookupRule)
        XCTAssertEqual(classification.targetText, "buy another domain")
        XCTAssertEqual(whenAllowed.intent, .lookupRule)
        XCTAssertEqual(whenAllowed.targetText, "buy domains again")
        XCTAssertEqual(ruleAbout.intent, .lookupRule)
        XCTAssertEqual(ruleAbout.targetText, "monitors")
        XCTAssertEqual(reminderAbout.intent, .lookupRule)
        XCTAssertEqual(reminderAbout.targetText, "filters")
    }

    func testClassifiesTodayAgendaLookup() {
        let classification = classify("What do I have to do today?")
        let due = classify("What's due today?")

        XCTAssertEqual(classification.intent, .lookupTodayAgenda)
        XCTAssertEqual(classification.targetText, "today")
        XCTAssertEqual(due.intent, .lookupTodayAgenda)
    }

    func testClassifiesPriorNoteLookup() {
        let classification = classify("What did I say about the garage filter?")
        let mention = classify("Did I mention attic vents?")
        let notes = classify("Show me notes about monitor arms.")
        let timedBroad = classify("What did I say last month?")
        let broad = classify("What did I say?")

        XCTAssertEqual(classification.intent, .lookupPriorNotes)
        XCTAssertEqual(classification.targetText, "the garage filter")
        XCTAssertEqual(mention.intent, .lookupPriorNotes)
        XCTAssertEqual(mention.targetText, "attic vents")
        XCTAssertEqual(notes.intent, .lookupPriorNotes)
        XCTAssertEqual(notes.targetText, "monitor arms")
        XCTAssertEqual(timedBroad.intent, .lookupPriorNotes)
        XCTAssertEqual(timedBroad.targetText, "last month")
        XCTAssertEqual(broad.intent, .lookupPriorNotes)
        XCTAssertEqual(broad.targetText, "")
    }

    func testQuestionStyleLookupRoutingIgnoresFutureReviewWords() {
        let lastFollowUp = classify("When did I last follow up with the dentist?")
        let noteLookup = classify("What did I say about follow up next week?")

        XCTAssertEqual(lastFollowUp.intent, .lookupLastTime)
        XCTAssertEqual(lastFollowUp.targetText, "follow up with the dentist")
        XCTAssertEqual(noteLookup.intent, .lookupPriorNotes)
        XCTAssertEqual(noteLookup.targetText, "follow up next week")
    }

    func testClassifiesLocalSearch() {
        let classification = classify("Search for garage filter.")

        XCTAssertEqual(classification.intent, .localSearch)
        XCTAssertEqual(classification.targetText, "garage filter")
    }

    func testClassifiesWebLookupRequests() {
        let bestGames = classify("Saturday I need to know the best games to watch with kickoff times.")
        let schedule = classify("What is the Rutgers football schedule for 2026?")

        XCTAssertEqual(bestGames.intent, .webLookup)
        XCTAssertEqual(bestGames.targetText, "Saturday I need to know the best games to watch with kickoff times.")
        XCTAssertEqual(schedule.intent, .webLookup)
    }

    func testClassifiesWebImportRequests() {
        let classification = classify("Add all Rutgers football home games to my things for 2026.")

        XCTAssertEqual(classification.intent, .webImport)
        XCTAssertEqual(classification.targetText, "Add all Rutgers football home games to my things for 2026.")
    }

    func testClassifiesUnsupportedQuestion() {
        XCTAssertEqual(classify("What should I do with my life?").intent, .unsupported)
        XCTAssertEqual(classify("What changed about my routine?").intent, .unsupported)
    }

    func testClassifiesMixedLoggingAsExtractionRoute() {
        XCTAssertEqual(classify("Changed oil today, and when did I last change oil?").intent, .createEvent)
    }

    private func classify(_ input: String) -> ChatIntentClassification {
        ChatIntentClassifier().classify(input)
    }
}
