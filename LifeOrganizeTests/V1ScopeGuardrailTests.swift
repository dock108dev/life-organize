import XCTest
@testable import LifeOrganize

final class V1ScopeGuardrailTests: XCTestCase {
    func testScopeContractDefinesActiveAndLedgerNativePhaseSurfaces() {
        XCTAssertEqual(V1ScopeContract.activeRootTabs, [.log, .things, .rules])
        XCTAssertEqual(V1ScopeContract.allowedRootTabs, V1ScopeContract.activeRootTabs)
        XCTAssertEqual(
            V1ScopeContract.activeSettingsRows.map(\.title),
            ["AI Service Token", "Clear Local Data", "Export Local JSON"]
        )
        XCTAssertEqual(
            V1ScopeContract.allowedSettingsRows.map(\.title),
            ["AI Service Token", "Extraction Debug", "Clear Local Data", "Export Local JSON"]
        )
        XCTAssertEqual(
            V1ScopeContract.activePersistenceModels.map(\.rawValue),
            [
                "ChatMessage",
                "ExtractionAttempt",
                "EntityLink",
                "Thing",
                "LedgerEvent",
                "LedgerRule",
                "LedgerNote",
                "LedgerReviewItem"
            ]
        )
        XCTAssertEqual(
            V1ScopeContract.allowedPersistenceModels.map(\.rawValue),
            [
                "ChatMessage",
                "ExtractionAttempt",
                "EntityLink",
                "Thing",
                "LedgerEvent",
                "LedgerRule",
                "LedgerNote",
                "LedgerReviewItem",
                "LedgerReminder"
            ]
        )
        XCTAssertEqual(
            V1ScopeContract.allowedAIServiceUses,
            [.extraction, .normalization, .dateParsing, .recallFormatting, .webLookup, .webImport]
        )
        XCTAssertEqual(V1ScopeContract.allowedSearchModes, [.localSubstring, .webSearch])
        XCTAssertEqual(
            V1ScopeContract.allowedLedgerNativeCapabilities,
            [
                .deterministicLocalProjection,
                .reviewCandidate,
                .actionCandidate,
                .patternInference,
                .timelineSlice,
                .searchFirstAffordance
            ]
        )
    }

    func testRootNavigationMatchesScopeContractAndAvoidsBannedDestinations() throws {
        XCTAssertEqual(AppTab.allCases, V1ScopeContract.activeRootTabs)
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Timeline", "Things", "Carry Forward"])

        let declarations = try declaredNames(
            matching: #"\b(?:struct|class|enum)\s+([A-Za-z_][A-Za-z0-9_]*(?:Service|View|Route|Tab|NavigationRoot))\b"#,
            in: appSwiftSources(excluding: ["Utilities/V1ScopeContract.swift"])
        )

        XCTAssertNoBannedFragments(declarations, bannedFragments: V1ScopeContract.bannedRouteNameFragments)
    }

    func testPrimaryProductSurfacesAvoidAssistantPersonaAndAIPoweredNames() throws {
        let declarations = try declaredNames(
            matching: #"\b(?:struct|class|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*(?:Service|View|Route|Tab|NavigationRoot|Provider|Interface))\b"#,
            in: appSwiftSources(excluding: ["Utilities/V1ScopeContract.swift"])
        )

        XCTAssertNoBannedProductSurfaceFragments(declarations)
        XCTAssertFalse(
            containsBannedProductSurfaceFragment("ServiceExtractionProvider"),
            "Implementation names are allowed when they are not user-facing product surfaces."
        )
        XCTAssertTrue(containsBannedProductSurfaceFragment("AssistantCoachView"))
        XCTAssertTrue(containsBannedProductSurfaceFragment("AIRecommendationService"))
        XCTAssertTrue(containsBannedProductSurfaceFragment("AssistantDeviceTokenView"))
        XCTAssertTrue(containsBannedProductSurfaceFragment("AIServiceRecommendationService"))
    }

    func testPersistenceModelsMatchScopeContractAndRejectProductCategoryDrift() throws {
        let activeModelNames = Set(V1ScopeContract.activePersistenceModels.map(\.rawValue))
        let allowedModelNames = Set(V1ScopeContract.allowedPersistenceModels.map(\.rawValue))

        XCTAssertEqual(ModelContainerFactory.modelTypeNames, activeModelNames)
        XCTAssertTrue(activeModelNames.isSubset(of: allowedModelNames))
        XCTAssertTrue(allowedModelNames.contains("LedgerReminder"))

        let modelNames = try declaredNames(
            matching: #"@Model\s+(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            in: appSwiftSources(excluding: ["Utilities/V1ScopeContract.swift"])
        )

        XCTAssertEqual(Set(modelNames), activeModelNames)
        XCTAssertTrue(Set(modelNames).isDisjoint(with: V1ScopeContract.bannedPersistenceModelNames))
    }

    func testProjectDoesNotImportOrLinkExcludedFrameworksAndServices() throws {
        let importNames = try declaredNames(
            matching: #"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            in: appSwiftSources(excluding: ["Utilities/V1ScopeContract.swift"])
        )
        XCTAssertTrue(Set(importNames).isDisjoint(with: V1ScopeContract.bannedFrameworkImports))

        let projectText = try String(contentsOf: projectRoot.appending(path: "LifeOrganize.xcodeproj/project.pbxproj"))
        let forbiddenDependencies = V1ScopeContract.bannedDependencyTerms.filter { projectText.localizedCaseInsensitiveContains($0) }
        XCTAssertEqual(forbiddenDependencies, [])
    }

    func testAIServiceInterfacesStayNarrowAndNonCoaching() throws {
        let aiServiceSources = try [
            "LifeOrganize/Services/AIServiceClient.swift",
            "LifeOrganize/Services/ExtractionService.swift"
        ].map { try sourceFile(relativePath: $0) }
        let methodNames = try declaredNames(matching: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\b"#, in: aiServiceSources)

        XCTAssertTrue(methodNames.contains("sendExtraction"))
        XCTAssertTrue(methodNames.contains("extractRawResponse"))
        XCTAssertTrue(methodNames.contains("parseDate"))
        XCTAssertNoBannedFragments(methodNames, bannedFragments: V1ScopeContract.bannedAIServiceInterfaceMethodFragments)
    }

    func testSearchRemainsLocalSubstringOnly() throws {
        XCTAssertEqual(SearchService.activeMode, .localSubstring)

        let searchSource = try sourceFile(relativePath: "LifeOrganize/Services/SearchService.swift")
        let forbiddenSearchTerms = ["Embedding", "Vector", "semantic", "URLSession", "remote"]
        let matches = forbiddenSearchTerms.filter { searchSource.localizedCaseInsensitiveContains($0) }

        XCTAssertEqual(matches, [])
    }

    func testReminderCopyAllowsLedgerTerminologyButRejectsEngagementPrompts() throws {
        let featureSources = try swiftFiles(in: projectRoot.appending(path: "LifeOrganize/Features"))
            .map { try String(contentsOf: $0) }
        let combined = featureSources.joined(separator: "\n").lowercased()
        let forbiddenCopy = V1ScopeContract.bannedNotificationCopyFragments.filter {
            combined.contains($0.lowercased())
        }

        XCTAssertFalse(V1ScopeContract.bannedNotificationCopyFragments.contains("reminder"))
        XCTAssertEqual(forbiddenCopy, [])
    }

    func testLedgerNativePhaseTermsAreAllowedWithoutProductDrift() {
        XCTAssertTrue(
            V1ScopeContract.allowedLedgerRouteNameFragments.isDisjoint(with: V1ScopeContract.bannedRouteNameFragments)
        )
        XCTAssertTrue(V1ScopeContract.allowedLedgerRouteNameFragments.contains("reminder"))
        XCTAssertTrue(V1ScopeContract.allowedLedgerRouteNameFragments.contains("feed"))
        XCTAssertTrue(V1ScopeContract.allowedLedgerRouteNameFragments.contains("timeline"))
        XCTAssertTrue(V1ScopeContract.allowedLedgerRouteNameFragments.isSuperset(of: Set([
            "action",
            "candidate",
            "overview",
            "pattern",
            "projection",
            "review",
            "search",
            "summary"
        ])))

        XCTAssertTrue(V1ScopeContract.allowedLedgerNativeCapabilities.contains(.deterministicLocalProjection))
        XCTAssertTrue(V1ScopeContract.allowedLedgerNativeCapabilities.contains(.reviewCandidate))
        XCTAssertTrue(V1ScopeContract.allowedLedgerNativeCapabilities.contains(.actionCandidate))
        XCTAssertTrue(V1ScopeContract.allowedLedgerNativeCapabilities.contains(.patternInference))
        XCTAssertTrue(V1ScopeContract.allowedLedgerNativeCapabilities.contains(.timelineSlice))
        XCTAssertTrue(V1ScopeContract.allowedLedgerNativeCapabilities.contains(.searchFirstAffordance))

        let durableRouteBans = [
            "account",
            "advice",
            "analytics",
            "coach",
            "dashboard",
            "embedding",
            "goal",
            "habit",
            "insight",
            "notification",
            "profile",
            "streak",
            "sync",
            "vector"
        ]
        XCTAssertTrue(durableRouteBans.allSatisfy { V1ScopeContract.bannedRouteNameFragments.contains($0) })
        XCTAssertTrue(V1ScopeContract.bannedPersistenceModelNames.isSuperset(of: Set([
            "Account",
            "Analytics",
            "Assistant",
            "Embedding",
            "Goal",
            "Habit",
            "Insight",
            "Mood",
            "Recommendation",
            "Streak",
            "Sync",
            "User",
            "Vector"
        ])))
        XCTAssertTrue(V1ScopeContract.bannedAIServiceInterfaceMethodFragments.isSuperset(of: Set([
            "advice",
            "advise",
            "agent",
            "assistant",
            "coach",
            "goal",
            "habit",
            "insight",
            "mood",
            "recommend"
        ])))
        XCTAssertTrue(V1ScopeContract.bannedNotificationCopyFragments.isSuperset(of: Set([
            "daily check-in",
            "daily prompt",
            "keep your streak",
            "you haven't checked in"
        ])))
    }

    func testOperationalReviewAndActionCandidatesAreNotAdviceOrCoaching() {
        let allowedOperationalTerms = Set(V1ScopeContract.allowedLedgerNativeCapabilities.map(\.rawValue))

        XCTAssertTrue(allowedOperationalTerms.contains("reviewCandidate"))
        XCTAssertTrue(allowedOperationalTerms.contains("actionCandidate"))
        XCTAssertTrue(allowedOperationalTerms.contains("patternInference"))
        XCTAssertFalse(allowedOperationalTerms.contains("recommendation"))
        XCTAssertFalse(allowedOperationalTerms.contains("advice"))
        XCTAssertFalse(allowedOperationalTerms.contains("coaching"))

        XCTAssertTrue(V1ScopeContract.bannedProductSurfaceNameFragments.isSuperset(of: Set([
            "advice",
            "advise",
            "assistant",
            "coach",
            "recommend"
        ])))
    }

    @MainActor
    func testPrimaryUserCopyAvoidsInternalLanguage() {
        let feedMessage = ChatMessage(role: .user, text: "Changed oil.", extractionStatus: .pendingRetry)
        let feedCopy = LedgerFeedRowContent(item: .message(feedMessage))
        let appMessage = ChatMessage(role: .assistant, text: "Logged.", extractionStatus: .notRequired)
        let appCopy = LedgerFeedRowContent(item: .message(appMessage))
        let thing = Thing(name: "Dog Food")
        let olderPurchase = LedgerEvent(
            title: "Bought dog food",
            occurredAt: fixedTestNow.addingTimeInterval(-56 * 86_400),
            rawText: "Bought dog food.",
            eventType: .purchase,
            thing: thing
        )
        let latestPurchase = LedgerEvent(
            title: "Bought dog food",
            occurredAt: fixedTestNow.addingTimeInterval(-28 * 86_400),
            rawText: "Bought dog food again.",
            eventType: .purchase,
            thing: thing
        )
        thing.events = [olderPurchase, latestPurchase]
        let snapshot = ThingDetailSnapshot(thing: thing, now: fixedTestNow, calendar: Calendar(identifier: .gregorian))

        let primaryCopy = [
            feedCopy.sourceLabel,
            feedCopy.secondaryText,
            appCopy.sourceLabel,
            SettingsTrustCopy.exportBody,
            SettingsFeedback.deviceTokenReplaced.message,
            SettingsFeedback.exportReady.message,
            ManualExtractionRetryError.missingServiceToken.errorDescription,
            ManualExtractionRetryBlockedReason.notRequired.message,
            ChatResponseFormatter().rawOnlyFailure(),
            ChatResponseFormatter().extractionFailed(),
            LedgerEmptyStateContent.searchLanding.body,
            snapshot.continuitySummary?.label,
            snapshot.continuitySummary?.detail
        ].compactMap { $0 }.joined(separator: " ")

        let bannedCopyTerms = [
            "Assistant",
            "Organizing",
            "organization",
            "JSON",
            "provenance",
            "confidence",
            "recommendation",
            "insight",
            "processing",
            "Automatic filing",
            "ledger item",
            "Expected next check",
            "Estimated next"
        ]
        XCTAssertNoBannedUserCopyTerms(primaryCopy, bannedTerms: bannedCopyTerms)
    }
}

extension V1ScopeGuardrailTests {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func appSwiftSources(excluding excludedRelativePaths: Set<String>) throws -> [String] {
        try swiftFiles(in: projectRoot.appending(path: "LifeOrganize"))
            .filter { url in
                let relativePath = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
                return !excludedRelativePaths.contains(relativePath.replacingOccurrences(of: "LifeOrganize/", with: ""))
            }
            .map { try String(contentsOf: $0) }
    }

    private func sourceFile(relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appending(path: relativePath))
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try contents.flatMap { url -> [URL] in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                return try swiftFiles(in: url)
            }
            return url.pathExtension == "swift" ? [url] : []
        }
    }

    private func declaredNames(matching pattern: String, in sources: [String]) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        return sources.flatMap { source in
            regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
                guard let range = Range(match.range(at: 1), in: source) else { return nil }
                return String(source[range])
            }
        }
    }

    private func XCTAssertNoBannedFragments(
        _ names: [String],
        bannedFragments: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let offenders = names.filter { name in
            bannedFragments.contains { name.localizedCaseInsensitiveContains($0) }
        }
        XCTAssertEqual(offenders, [], file: file, line: line)
    }

    private func XCTAssertNoBannedProductSurfaceFragments(
        _ names: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let offenders = names.filter(containsBannedProductSurfaceFragment)
        XCTAssertEqual(offenders, [], file: file, line: line)
    }

    private func containsBannedProductSurfaceFragment(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        if V1ScopeContract.bannedProductSurfaceNameFragments.contains(where: { lowercased.contains($0) }) {
            return true
        }
        if name.contains("AI") {
            return !V1ScopeContract.internalProviderNameFragments.contains(where: { name.contains($0) })
        }
        return false
    }

    private func XCTAssertNoBannedUserCopyTerms(
        _ text: String,
        bannedTerms: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowercased = text.lowercased()
        let offenders = bannedTerms.filter { lowercased.contains($0.lowercased()) }
        XCTAssertEqual(offenders, [], file: file, line: line)
    }
}
