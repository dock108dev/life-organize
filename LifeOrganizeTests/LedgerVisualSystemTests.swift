import SwiftUI
import XCTest
@testable import LifeOrganize

final class LedgerVisualSystemTests: XCTestCase {
    func testLedgerTonesMapToProductionSemanticColorRoles() {
        XCTAssertEqual(
            LedgerTone.allCases.map(\.semanticColorRole),
            [
                .neutral,
                .interactive,
                .success,
                .attention,
                .temporal,
                .muted,
                .annotation,
                .critical
            ]
        )
    }

    func testContinuityLanesUseSharedLedgerTones() {
        XCTAssertEqual(ReminderContinuityLane.now.tone, .attention)
        XCTAssertEqual(ReminderContinuityLane.comingUp.tone, .info)
        XCTAssertEqual(ReminderContinuityLane.review.tone, .attention)
        XCTAssertEqual(ReminderContinuityLane.paused.tone, .muted)
    }

    func testContinuityLanesMapRowEmphasisByAttentionNeed() {
        XCTAssertEqual(ReminderContinuityLane.now.rowEmphasis, .active)
        XCTAssertEqual(ReminderContinuityLane.comingUp.rowEmphasis, .normal)
        XCTAssertEqual(ReminderContinuityLane.review.rowEmphasis, .attention)
        XCTAssertEqual(ReminderContinuityLane.paused.rowEmphasis, .inactive)
    }

    func testRowEmphasisUsesNeutralFillsWithSmallSemanticAccents() {
        XCTAssertEqual(LedgerRowEmphasis.normal.accentTone, nil)
        XCTAssertEqual(LedgerRowEmphasis.active.accentTone?.semanticColorRole, .interactive)
        XCTAssertEqual(LedgerRowEmphasis.attention.accentTone?.semanticColorRole, .attention)
        XCTAssertEqual(LedgerRowEmphasis.inactive.accentTone, nil)
    }

    func testReminderRowsPutTimingBeforeReasonContext() {
        let presentation = ReminderContinuityPresentation(
            lane: .comingUp,
            statusBadge: LedgerBadgePresentation.reminderStatus(for: .comingUp),
            typeBadge: LedgerBadgePresentation.reminderType(for: .dateBasedReminder),
            badges: [],
            primaryLine: "Due Jun 4",
            dateLine: "Will move to Now on that date",
            detailTimingRows: []
        )
        let lines = LedgerReminderRowLines.lines(for: presentation, reason: "Renew registration")

        XCTAssertEqual(
            lines.map(\.text),
            ["Due Jun 4", "Will move to Now on that date", "Renew registration"]
        )
        XCTAssertEqual(lines.map(\.role), [.contentPreview, .metadata, .contentPreview])
    }

    func testProductionSurfaceContractExposesSharedCardRowAndIconMetrics() {
        XCTAssertEqual(LedgerSurfaceContract.cardCornerRadius, 12)
        XCTAssertEqual(LedgerSurfaceContract.rowCornerRadius, 10)
        XCTAssertEqual(LedgerSurfaceContract.contentPadding, 14)
        XCTAssertEqual(LedgerSurfaceContract.minimumInteractiveTarget, 44)
        XCTAssertEqual(LedgerSurfaceContract.toolbarIconFrame, 36)
        XCTAssertEqual(LedgerSurfaceContract.borderLineWidth, 1)
        XCTAssertLessThanOrEqual(LedgerSurfaceContract.shadowOpacity, 0.04)
        XCTAssertEqual(LedgerVisualSystem.Spacing.surfaceStack, 12)
        XCTAssertEqual(LedgerVisualSystem.Spacing.iconTextGap, 8)
        XCTAssertEqual(LedgerIconContext.allCases, [.toolbar, .sidebar, .emptyState, .warningReview, .cardList, .sectionHeader])
        XCTAssertEqual(LedgerIconContext.toolbar.frameSize, 18)
        XCTAssertEqual(LedgerIconContext.emptyState.frameSize, 28)
        XCTAssertEqual(LedgerIconContext.cardList.frameSize, 16)
        XCTAssertEqual(LedgerIconContext.sectionHeader.frameSize, 16)
    }

    func testSharedToneAndSurfaceSourcesAvoidAdHocSystemHues() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sharedRoot = root.appendingPathComponent("LifeOrganize/Features/Shared")
        let sourceURLs = try FileManager.default.contentsOfDirectory(
            at: sharedRoot,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        let forbiddenHuePatterns = [
            "return .blue.opacity",
            "return .green.opacity",
            "return .orange.opacity",
            "return .teal.opacity",
            "return .purple.opacity",
            "return .red.opacity",
            "foregroundStyle(.blue)",
            "foregroundStyle(.green)",
            "foregroundStyle(.orange)",
            "foregroundStyle(.teal)",
            "foregroundStyle(.purple)",
            "foregroundStyle(.red)",
            "tint(.blue)",
            "tint(.green)",
            "tint(.orange)",
            "tint(.teal)",
            "tint(.purple)",
            "tint(.red)"
        ]

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for forbiddenHuePattern in forbiddenHuePatterns {
                XCTAssertFalse(
                    source.contains(forbiddenHuePattern),
                    "\(sourceURL.lastPathComponent) should use LedgerSemanticColorRole instead of \(forbiddenHuePattern)"
                )
            }
        }

        let surfaceSource = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Shared/LedgerSurfaceStyle.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(surfaceSource.contains("tint?.foreground.opacity(0.18) ?? LedgerPalette.hairline"))
    }

    func testSemanticBadgeTonesMeetLightModeContrastFloor() {
        for role in LedgerSemanticColorRole.allCases {
            guard let foreground = role.contrastColorValue else { continue }
            let background = foreground.blended(over: .white, opacity: role.backgroundOpacity)

            XCTAssertGreaterThanOrEqual(
                foreground.contrastRatio(against: background),
                4.5,
                "\(role) badge foreground should remain readable over its tinted background"
            )
        }
    }

    func testPolishedSelectionAndTouchTargetsPreserveAccessibilityContracts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sidebarSource = try sourceFile("LifeOrganize/RegularSidebarSectionRow.swift", root: root)
        let sharedControlsSource = try sourceFile("LifeOrganize/Features/Shared/LedgerSharedControls.swift", root: root)
        let searchRowSource = try sourceFile("LifeOrganize/Features/Search/LocalSearchResultRow.swift", root: root)
        let contextPanelSource = try sourceFile("LifeOrganize/Features/Shared/LedgerContextPanel.swift", root: root)

        XCTAssertFalse(sidebarSource.contains(".lineLimit(1)"))
        XCTAssertTrue(sidebarSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(sidebarSource.contains("minHeight: LedgerSurfaceContract.minimumInteractiveTarget"))
        XCTAssertTrue(sharedControlsSource.contains("width: LedgerSurfaceContract.toolbarIconFrame"))
        XCTAssertTrue(sharedControlsSource.contains("LocalSearchResultRow(result: result, isSelected: isSelected)"))
        XCTAssertTrue(sharedControlsSource.contains(".accessibilityValue(isSelected ? \"Selected\" : \"\")"))
        XCTAssertTrue(searchRowSource.contains("emphasis: isSelected ? .active : .normal"))
        XCTAssertTrue(contextPanelSource.contains("LedgerSurfaceContract.minimumInteractiveTarget"))
    }

    func testPrimaryScreensUseSharedSurfacePrimitives() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let settingsSource = try sourceFile("LifeOrganize/Features/Settings/SettingsView.swift", root: root)
        let reconciliationSource = try sourceFile(
            "LifeOrganize/Features/Shared/LedgerReviewReconciliationPanelView.swift",
            root: root
        )
        let reviewDetailSource = try sourceFile("LifeOrganize/Features/Shared/LedgerReviewQueueDetailView.swift", root: root)
        let detailComponentsSource = try sourceFile("LifeOrganize/Features/Things/LedgerDetailComponents.swift", root: root)
        let checkedSources = [settingsSource, reconciliationSource, reviewDetailSource]

        XCTAssertTrue(settingsSource.contains("LedgerSectionTitle("))
        XCTAssertTrue(settingsSource.contains(".settingsSurface(tint:"))
        XCTAssertTrue(settingsSource.contains("ForEach(SettingsDeveloperDestination.allCases)"))
        XCTAssertFalse(settingsSource.contains("settingsDivider"))
        XCTAssertFalse(settingsSource.contains(".font(.headline)"))
        XCTAssertTrue(reconciliationSource.contains(".ledgerSurface(tint: prominence.surfaceTint)"))
        XCTAssertTrue(reviewDetailSource.contains(".background(LedgerScreenBackground().ignoresSafeArea())"))
        XCTAssertTrue(reviewDetailSource.contains(".ledgerSurface(tint: .success)"))
        XCTAssertTrue(detailComponentsSource.contains("LedgerVisualSystem.Typography.metricLabel"))
        XCTAssertTrue(detailComponentsSource.contains("LedgerVisualSystem.Typography.metricPrimaryValue"))
        XCTAssertTrue(detailComponentsSource.contains("LedgerVisualSystem.Typography.metricSecondaryValue"))

        for source in checkedSources {
            XCTAssertFalse(source.contains("secondarySystemGroupedBackground"))
            XCTAssertFalse(source.contains(".background(Color(.systemGroupedBackground))"))
        }
    }

    func testFeedSourceToneMappingCoversLedgerKinds() {
        XCTAssertEqual(LedgerTone(feedSource: .user), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .status), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .system), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .event), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .reminder), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .note), .note)
    }

    func testSemanticBadgesCarryRoleMeaningAndPriorityOrdering() {
        let saved = LedgerBadgePresentation(semantic: .statusSaved)
        let note = LedgerBadgePresentation(semantic: .categoryNote)
        let review = LedgerBadgePresentation(semantic: .actionReview, tone: .attention, priority: 90)
        let visible = LedgerBadgePresentation.visibleBadges(from: [note, saved, review], maxCount: 2)

        XCTAssertEqual(saved.role, .status)
        XCTAssertEqual(saved.label, "Saved")
        XCTAssertEqual(saved.tone, .muted)
        XCTAssertEqual(note.role, .category)
        XCTAssertEqual(note.tone, .note)
        XCTAssertEqual(review.role, .action)
        XCTAssertEqual(visible.map(\.semantic), [.actionReview, .statusSaved])
    }

    func testRowDensityDefinesCompactAndStandardRhythm() {
        XCTAssertEqual(LedgerRowDensity.compact.verticalSpacing, 2)
        XCTAssertEqual(LedgerRowDensity.compact.verticalPadding, 6)
        XCTAssertEqual(LedgerRowDensity.standard.verticalSpacing, 4)
        XCTAssertEqual(LedgerRowDensity.standard.verticalPadding, 2)
        XCTAssertEqual(LedgerRowDensity.detail.verticalSpacing, 4)
        XCTAssertEqual(LedgerVisualSystem.Padding.rowHorizontal, 8)
        XCTAssertEqual(LedgerVisualSystem.Spacing.rowAccessoryGap, 10)
        XCTAssertEqual(LedgerVisualSystem.Spacing.rowBadgeGap, 5)
        XCTAssertEqual(LedgerPillSize.micro.horizontalPadding, 4)
        XCTAssertEqual(LedgerPillSize.micro.verticalPadding, 1)
    }

    func testNoticeRhythmExposesSharedSpacingTokens() {
        XCTAssertEqual(LedgerVisualSystem.Spacing.noticeContentGap, 8)
        XCTAssertEqual(LedgerVisualSystem.Spacing.noticeActionGap, 6)
        XCTAssertEqual(LedgerVisualSystem.Padding.noticeHorizontal, 12)
        XCTAssertEqual(LedgerVisualSystem.Padding.noticeVertical, 8)
    }

    func testLedgerRowLineRolesResolveDynamicTypeLimits() {
        let metadata = LedgerRowLine(text: "May 26", role: .metadata)
        let preview = LedgerRowLine(text: "Long result excerpt", role: .contentPreview)
        let cappedPreview = LedgerRowLine(text: "Reason", role: .contentPreview, lineLimit: 4)
        let detail = LedgerRowLine(text: "Full detail", role: .contentDetail)

        XCTAssertEqual(metadata.resolvedLineLimit(for: .large), 1)
        XCTAssertEqual(metadata.resolvedLineLimit(for: .accessibility1), 1)
        XCTAssertEqual(preview.resolvedLineLimit(for: .large), 2)
        XCTAssertEqual(preview.resolvedLineLimit(for: .accessibility1), 3)
        XCTAssertEqual(cappedPreview.resolvedLineLimit(for: .accessibility1), 4)
        XCTAssertNil(detail.resolvedLineLimit(for: .large))
        XCTAssertNil(detail.resolvedLineLimit(for: .accessibility1))
    }

    func testSearchRowsUseQuietLedgerPresentation() {
        let ruleID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let record = LocalSearchRecord(
            id: ruleID,
            kind: .rule,
            title: "Renew registration",
            subtitle: "Due May 21, 2026",
            body: "For Honda Civic",
            searchableFields: [],
            createdAt: fixedTestNow,
            occurredAt: nil,
            updatedAt: nil,
            linkedThingId: UUID(),
            linkedThingName: "Honda Civic",
            isActiveRule: true,
            ruleBadge: "Now",
            ruleLane: .now,
            timelineDateRange: nil,
            navigationTarget: .ruleDetail(ruleID)
        )
        let result = LocalSearchResult(record: record, matchedFields: [.title], score: 1)
        let presentation = LocalSearchResultRowPresentation(result: result)

        XCTAssertEqual(presentation.primaryText, "Renew registration")
        XCTAssertEqual(presentation.kindPillText, "Reminder")
        XCTAssertEqual(presentation.kindPillTone, .muted)
        XCTAssertEqual(presentation.rulePillText, "Now")
        XCTAssertEqual(presentation.rulePillTone, .attention)
        XCTAssertEqual(presentation.badges.map(\.role), [.status])
        XCTAssertEqual(presentation.badges.map(\.semantic), [.statusNow])
        XCTAssertTrue(presentation.accessibilityLabel.contains("Reminder"))
        XCTAssertEqual(presentation.footerText, "For Honda Civic")
        XCTAssertEqual(presentation.dateText, DateFormatting.shortDate.string(from: fixedTestNow))
        XCTAssertEqual(presentation.secondaryLines.first?.text, presentation.dateText)
        XCTAssertEqual(presentation.secondaryLines.map(\.role), [.metadata, .contentPreview, .contentPreview])
        XCTAssertEqual(presentation.secondaryLines.map { $0.resolvedLineLimit(for: .large) }, [1, 2, 2])
        XCTAssertEqual(presentation.secondaryLines.map { $0.resolvedLineLimit(for: .accessibility1) }, [1, 3, 3])
        XCTAssertEqual(LedgerSurfaceDensity.searchResultRow.rowDensity, .compact)
    }

    func testRelatedContextRowsUseRecordTypePillsAndDateLines() {
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: fixedTestNow,
            rawText: "Changed oil."
        )
        let records = RelationshipTraversalRecords(events: [event])
        let result = RelationshipTraversalResult(
            target: .event(event.id),
            navigationTarget: .eventDetail(event.id),
            source: .linkedThing,
            sourceLabel: "Linked thing",
            sourceMessageID: nil,
            dedupeKey: "event-\(event.id.uuidString)",
            confidence: nil,
            createdBy: nil
        )
        let presentation = RelatedContextRowPresentation(result: result, records: records)

        XCTAssertEqual(presentation.primaryText, "Oil change")
        XCTAssertEqual(presentation.badgeText, "Event")
        XCTAssertEqual(presentation.badgeTone, .muted)
        XCTAssertEqual(presentation.secondaryLines.first?.text, "Linked thing")
        XCTAssertEqual(presentation.secondaryLines.count, 2)
    }

    private func sourceFile(_ relativePath: String, root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
