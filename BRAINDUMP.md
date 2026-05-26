# LifeOrganize iOS Screen Support Braindump

This is the working plan for making LifeOrganize feel native and durable across iPhone, iPad, orientation changes, Dynamic Type, Split View, Stage Manager, and future iOS screen classes.

The goal is not "make the phone UI bigger." The goal is one adaptive SwiftUI app shell where compact screens stay focused and regular-width screens use the room for navigation, context, and detail.

## Hard Rules

- iPad support is first-class. The app target already includes iPhone and iPad with `TARGETED_DEVICE_FAMILY = "1,2"`, so the UI must be treated as universal.
- Do not branch on device names, model names, or `UIDevice` for layout. Use SwiftUI environment traits, available width, Dynamic Type, and platform presentation behavior.
- Design the full layout first, then collapse only when it no longer fits.
- Keep compact iPhone behavior fast: the existing `TabView` plus per-tab `NavigationStack` remains the compact baseline unless a change proves better.
- On regular-width iPad, prefer a persistent navigation structure over a stretched tab-only phone shell.
- Do not let row content, cards, editors, or empty states stretch edge to edge on large iPad canvases. Use readable max widths and intentional columns.
- Support portrait and landscape. Avoid portrait-only assumptions in screenshots, safe-area math, keyboard behavior, and toolbar placement.
- Dynamic Type is part of screen support. Text can wrap, reflow, move to secondary lines, or collapse metadata, but it should not overlap, truncate important actions, or force horizontal scrolling.
- Screens should preserve the product rule already used here: the UI should behave by the rules, not explain them with extra copy.

## Current Repo State

Already true:

- Native SwiftUI app under `LifeOrganize/`.
- App target deployment target is iOS `17.0`.
- App target supports iPhone and iPad through `TARGETED_DEVICE_FAMILY = "1,2"`.
- Root shell is `AppRootView`.
- Current primary navigation is a `TabView` with three tabs:
  - `Timeline`
  - `Things`
  - `Carry Forward`
- Each tab currently owns a `NavigationStack`.
- Shared modal surfaces are owned at the root through `AppRootSheet`:
  - settings
  - search
  - review queue
- There is existing visual regression tooling:
  - `Scripts/screenshots/run-screenshot-tests.sh`
  - `LifeOrganizeUITests/LifeOrganizeScreenshotTests.swift`
  - `Tests/ScreenshotBaselines/`
- Current screenshot baselines cover iPhone classes only:
  - `iPhone_16/light`
  - `iPhone_17_Pro/light`
- The screenshot script is already parameterized with `SCREENSHOT_DEVICE_NAME`, `SCREENSHOT_DEVICE_OS`, `SCREENSHOT_APPEARANCE`, and baseline paths.

Current gaps:

- No iPad screenshot baselines.
- No iPad-specific UI test coverage.
- No landscape screenshot coverage.
- No explicit adaptive root shell for regular-width layouts.
- No central layout policy for readable content widths, wide gutters, split columns, or form widths.
- Some views use one-column phone assumptions that will look sparse or overly wide on iPad.
- Some `lineLimit(1)` and fixed frame choices are appropriate for badges or icons, but need an audit so important content can reflow at larger text sizes.
- Search, settings, review, list-detail, and editor presentation choices are still mostly phone-shaped.

## Apple-Guided Principles

Use these as product constraints:

- SwiftUI should adapt to traits and context changes such as size classes, display zoom, resizable iPad windows, and external displays.
- Build the full layout first. Collapse to compact only when the full layout no longer fits.
- Use `NavigationSplitView` for two-column or three-column navigation that needs to work across iPhone and iPad. SwiftUI collapses split views into stack behavior in narrow contexts.
- If an app has multiple columns in some cases and a single column in others, migrate that navigation surface to `NavigationSplitView`.
- Accessibility sizing is not optional. The interface should support people who enlarge text substantially, with important content and controls still reachable.

Reference docs:

- Apple HIG Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- SwiftUI `NavigationSplitView`: https://developer.apple.com/documentation/swiftui/navigationsplitview
- Migrating to new navigation types: https://developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types
- Apple HIG Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility

## Desired App Shape

### Compact Width

Use the current model:

- `TabView` at the root.
- One `NavigationStack` per tab.
- Toolbar buttons remain compact icon buttons.
- Search, settings, and review can remain modal flows.
- Composer stays bottom-pinned in Timeline.
- Lists navigate forward to detail.

This covers:

- iPhone portrait.
- iPhone landscape when width is still constrained by height or keyboard.
- iPad Slide Over or narrow Split View.
- Stage Manager narrow windows.

### Regular Width

Use a first-class iPad shell:

- `NavigationSplitView` at the root.
- Sidebar owns primary destinations:
  - Timeline
  - Things
  - Carry Forward
  - Search
  - Review, when review items exist
  - Settings
- Detail column renders the selected destination.
- Avoid stacking a tab bar and sidebar at the same time.
- Keep toolbar actions, but promote persistent destinations to the sidebar when the space exists.
- For list-detail features, keep selection visible where useful:
  - Things list on the leading/content column, selected thing in detail.
  - Carry Forward list on the leading/content column, selected reminder detail in detail.
  - Search results on the leading/content column, selected result detail in detail.
  - Review queue list on the leading/content column, selected review item detail in detail.

This covers:

- iPad portrait.
- iPad landscape.
- iPad full screen.
- iPad Split View widths that still have regular horizontal size.
- Stage Manager windows with enough width.

## Recommended Architecture

### 1. Add a Single Adaptive Root Shell

Keep `AppRootView` as the owner of app-level state, sheets, model queries, maintenance, tint, and environment objects. Extract the layout decision into a focused shell:

```swift
struct AppRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            RegularRootShell(...)
        } else {
            CompactRootShell(...)
        }
    }
}
```

Do not scatter this decision across every feature. Screen-specific adaptations should be local only when a screen genuinely needs different composition.

### 2. Preserve Compact Behavior

Move the existing `TabView` body into `CompactRootShell`. This keeps current iPhone behavior stable while the iPad shell is introduced.

Compact shell responsibilities:

- Existing `TabView(selection:)`.
- Existing tab item labels and icons.
- Existing `LogNavigationRoot`, `ThingsNavigationRoot`, and `RulesNavigationRoot`.
- Existing reset token behavior.

### 3. Add RegularRootShell

Use `NavigationSplitView` for regular-width layouts.

Regular shell responsibilities:

- Sidebar selection of app areas.
- Detail rendering for the selected area.
- Root-owned search/settings/review routing.
- Column visibility defaults.
- Optional selected entity state for future list-detail layouts.

Start with two columns before trying three:

```swift
NavigationSplitView {
    List(selection: $selectedSection) {
        Label("Timeline", systemImage: "clock").tag(AppSection.timeline)
        Label("Things", systemImage: "tray.full").tag(AppSection.things)
        Label("Carry Forward", systemImage: "checklist").tag(AppSection.carryForward)
        Label("Search", systemImage: "magnifyingglass").tag(AppSection.search)
        Label("Settings", systemImage: "gearshape").tag(AppSection.settings)
    }
    .navigationTitle("LifeOrganize")
} detail: {
    NavigationStack {
        selectedDetailView
    }
}
```

Only add a three-column split after a screen has a real persistent middle column. Things, search, and review are the likely candidates.

### 4. Centralize Layout Metrics

Add one small layout policy type rather than hard-coding widths in each screen.

Candidate:

```swift
enum LedgerAdaptiveLayout {
    static let readableWidth: CGFloat = 760
    static let detailWidth: CGFloat = 920
    static let formWidth: CGFloat = 680
    static let wideGutter: CGFloat = 32
}
```

Use it through modifiers:

```swift
extension View {
    func ledgerReadableColumn(alignment: Alignment = .top) -> some View {
        frame(maxWidth: LedgerAdaptiveLayout.readableWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}
```

Initial width policy:

- Timeline feed: max `760-860`.
- Things list: max `760` when alone, split when paired with detail.
- Thing detail: max `920-1040`.
- Carry Forward list: max `760`.
- Reminder detail: max `920`.
- Search: max `900`, with results/detail split on iPad.
- Settings: max `640-720`.
- Empty states: keep the existing constrained card pattern.

### 5. Make List-Detail Real on iPad

Phone navigation should remain push-based. iPad should keep context.

Priority list-detail conversions:

1. Things
   - Compact: tap thing pushes `ThingDetailView`.
   - Regular: list remains visible, detail updates with selected thing.
   - Empty detail state says nothing verbose, just a quiet placeholder.
2. Carry Forward
   - Compact: tap reminder pushes detail/actions.
   - Regular: list remains visible, selected reminder detail/actions stay beside it.
3. Search
   - Compact: modal search remains acceptable.
   - Regular: search can become a sidebar destination with results and selected result detail.
4. Review Queue
   - Compact: modal or push flow remains acceptable.
   - Regular: review list and selected review item detail should sit side by side.

### 6. Revisit Presentations

Presentation policy:

- Compact:
  - keep sheets for settings, search, review.
  - use full-screen-ish navigation flows when content is dense.
- Regular:
  - prefer sidebar destinations for settings/search/review when they are persistent work surfaces.
  - use sheets for short edit/create flows.
  - use popovers or menus for lightweight chooser actions.
  - constrain sheet content width with the form width policy.

Avoid large iPad sheets that are just stretched phone screens.

### 7. Keyboard and Composer Rules

Timeline is the highest-risk screen because it has a bottom composer.

Rules:

- Composer stays attached to the bottom safe area.
- Feed bottom padding accounts for the composer height.
- Keyboard should not hide the active text input.
- On iPad regular width, the composer should use the readable feed width, not full window width.
- Suggestions should wrap or collapse before they overflow.
- Hardware keyboard users should still have visible focus behavior and send affordances.

### 8. Dynamic Type and Accessibility Rules

Audit these patterns:

- `lineLimit(1)` is allowed for timestamps, short badges, and compact metadata only.
- Primary titles, reminder text, event summaries, settings copy, review reasons, and search result titles must wrap.
- Use `ViewThatFits` for metadata rows that can switch from horizontal to vertical.
- Keep icon-only buttons accessible with labels and identifiers.
- Hit targets should remain comfortable at larger text sizes.
- Avoid fixed row heights for content rows.
- Avoid horizontally scrollable text.
- Test at least normal, large, accessibility large, and accessibility extra extra extra large.

## Screen-by-Screen Work

### App Root

Files:

- `LifeOrganize/AppRootView.swift`

Work:

- Extract current tab shell to `CompactRootShell`.
- Add `RegularRootShell` with `NavigationSplitView`.
- Keep `AppRootView` as state owner.
- Avoid duplicating sheet state.
- Decide whether regular-width Search and Settings are sidebar destinations or root sheets. Prefer sidebar destinations for first-class iPad support.

Acceptance:

- iPhone screenshots are unchanged except for intentional toolbar/sidebar differences in compact edge cases.
- iPad launches directly into a sidebar/detail app layout.
- Narrow iPad windows collapse to compact behavior.

### Timeline

Files:

- `LifeOrganize/Features/Chat/ChatView.swift`
- `LifeOrganize/Features/Chat/ChatInputBar.swift`
- `LifeOrganize/Features/Chat/LedgerFeedTimelineViews.swift`

Work:

- Apply readable column width to feed and composer.
- Verify empty state stays centered and constrained.
- Verify heavy timeline rows do not stretch too wide.
- Audit timestamp and badge behavior at large text.
- Confirm keyboard and safe-area behavior in portrait and landscape.

Acceptance:

- Timeline feels like a ledger column on iPad, not a full-width table.
- Composer aligns with feed width.
- Heavy history remains scannable in landscape.

### Things

Files:

- `LifeOrganize/Features/Things/ThingsListView.swift`
- `LifeOrganize/Features/Things/ThingDetailView.swift`
- `LifeOrganize/Features/Things/*EditView.swift`

Work:

- Add list-detail selection for regular width.
- Keep phone push navigation.
- Constrain detail surfaces.
- Keep edit flows as constrained sheets or navigation flows depending on density.

Acceptance:

- Selecting a thing on iPad updates detail without losing the list.
- Thing detail does not become an oversized card field.
- Edit/delete/reassignment flows remain reachable with keyboard and touch.

### Carry Forward

Files:

- `LifeOrganize/Features/Rules/RulesListView.swift`
- `LifeOrganize/Features/Rules/RuleDetailView.swift`
- `LifeOrganize/Features/Rules/ReminderDetailActions.swift`

Work:

- Add list-detail selection for regular width.
- Keep action surfaces readable and constrained.
- Ensure repeated action buttons do not form a long full-width control wall on iPad.

Acceptance:

- Reminder list and reminder detail can be visible together on iPad.
- Date/reschedule sheets use form width.
- The list remains efficient for repeated review.

### Search

Files:

- `LifeOrganize/Features/Search/UnifiedSearchView.swift`
- `LifeOrganize/Features/Search/LocalSearchDestinationView.swift`

Work:

- Keep compact search as a modal flow.
- Make regular-width search a persistent workspace.
- Consider results/detail split after root shell lands.
- Remove arbitrary `maxWidth: 320` if it makes iPad empty states or search prompts feel cramped.

Acceptance:

- Search field, results, and destination detail do not compete in one stretched column.
- Empty and no-result states are centered and constrained.

### Settings and Debug

Files:

- `LifeOrganize/Features/Settings/SettingsView.swift`
- `LifeOrganize/Features/Debug/*`

Work:

- Constrain form content width.
- Keep debug lists readable, not full-window wide.
- Use sidebar destination on iPad if Settings becomes persistent.
- Keep destructive flows modal and narrow.

Acceptance:

- Settings reads like an iPad form, not a full-screen wall of text.
- Debug surfaces remain usable but do not drive the production layout.

### Review Queue

Files:

- `LifeOrganize/Features/Shared/LedgerReviewQueueView.swift`
- `LifeOrganize/Features/Shared/LedgerReviewQueueDetailView.swift`

Work:

- Keep compact modal/push behavior.
- Add regular-width list-detail behavior.
- Preserve quick triage actions.

Acceptance:

- Review list and selected review item can be visible together on iPad.
- Triage actions remain reachable without vertical hunting.

## Validation Matrix

At minimum, validate these local simulator targets:

- iPhone 17 Pro, iOS 26.2, portrait.
- iPhone 17 Pro, iOS 26.2, landscape.
- iPad Pro 13-inch (M5), iOS 26.2, portrait.
- iPad Pro 13-inch (M5), iOS 26.2, landscape.
- iPad mini or 11-inch iPad class, portrait.
- One narrow iPad window class if simulator tooling can approximate it.

Also validate text sizes:

- Large.
- Accessibility Large.
- Accessibility Extra Extra Extra Large.

Current local command shape:

```sh
xcodebuild test \
  -project LifeOrganize.xcodeproj \
  -scheme LifeOrganize \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' \
  CODE_SIGNING_ALLOWED=NO
```

Screenshot examples:

```sh
SCREENSHOT_DEVICE_NAME='iPad Pro 13-inch (M5)' \
SCREENSHOT_DEVICE_OS='26.2' \
Scripts/screenshots/run-screenshot-tests.sh update
```

```sh
SCREENSHOT_DEVICE_NAME='iPad Pro 13-inch (M5)' \
SCREENSHOT_DEVICE_OS='26.2' \
Scripts/screenshots/run-screenshot-tests.sh compare
```

Add landscape screenshot support explicitly. Today `LifeOrganizeScreenshotTests` forces portrait with:

```swift
XCUIDevice.shared.orientation = .portrait
```

That should become parameterized by launch arguments or separate screenshot test methods.

## Guardrails Worth Adding

Add lightweight tests or scripts for:

- No new direct `UIScreen.main.bounds` layout logic.
- No new `UIDevice.current.userInterfaceIdiom` layout branching unless explicitly justified.
- No new hard-coded full-screen widths in feature views.
- Screenshot baseline directories exist for required devices.
- iPad screenshot comparison runs for at least Timeline, Things, Thing Detail, Carry Forward, Search, and Review Queue.
- Accessibility text-size UI smoke covers Timeline, Things, Settings, and Review Queue.

Do not make these guardrails noisy. They should catch broad regressions, not ban every fixed icon size or divider height.

## Implementation Order

1. Add iPad screenshot smoke first.
   - Run existing screenshot tests on `iPad Pro 13-inch (M5)` portrait.
   - Save failures or awkward screenshots as the before-state.
   - Do not polish blindly before seeing the real screenshots.
2. Add central adaptive layout metrics.
   - Readable column modifier.
   - Form width modifier.
   - Wide detail modifier.
3. Apply readable widths to Timeline, Settings, Search, and core empty states.
   - This is low-risk and improves iPad even before split navigation.
4. Extract compact shell from `AppRootView`.
   - Keep existing behavior intact.
5. Add regular-width `NavigationSplitView` root shell.
   - Sidebar plus detail.
   - Keep root state ownership centralized.
6. Convert Things to list-detail on regular width.
   - This is the highest-value iPad workflow after the root shell.
7. Convert Carry Forward and Review Queue list-detail.
8. Convert Search to a regular-width workspace.
9. Parameterize screenshot orientation and add iPad portrait/landscape baselines.
10. Add Dynamic Type UI smoke and guardrails.
11. Only after the layout stabilizes, update CI to run the expanded visual matrix.

## CI Shape

Do not run every visual target on every small change at first. Start with a practical split:

- Required on iOS UI changes:
  - iPhone default screenshots.
  - iPad portrait screenshots.
  - unit/UI tests.
- Nightly or manual:
  - iPad landscape screenshots.
  - accessibility text-size UI smoke.
  - broader simulator matrix.

Once the iPad layout stabilizes, promote the iPad portrait visual gate to required.

## Open Decisions

- Should regular-width root navigation use only a sidebar, or a sidebar plus top tabs? Recommendation: sidebar only.
- Should Timeline remain a single readable column on iPad, or gain a secondary context column? Recommendation: single readable column first.
- Should Settings become a sidebar destination on iPad? Recommendation: yes, but keep compact as a sheet.
- Should Search become persistent on iPad? Recommendation: yes, because search-result-detail is a real workspace.
- Should review queue be a sidebar destination even when empty? Recommendation: hide or de-emphasize when empty.
- Which iPad simulator should be canonical in CI? Recommendation: local default can be `iPad Pro 13-inch (M5), OS=26.2`; CI should pin the newest available runner device deliberately and document it.

## Definition of Done

- iPhone compact behavior still works and screenshots remain intentional.
- iPad launches into an adaptive regular-width shell, not a stretched phone tab layout.
- Timeline feed and composer use readable widths on iPad.
- Things has real iPad list-detail behavior.
- Carry Forward and Review Queue have either list-detail behavior or documented follow-up issues.
- Search and Settings are constrained and usable on iPad.
- Portrait and landscape are both validated on at least one iPad class.
- Dynamic Type smoke proves large text does not overlap or hide core actions.
- `Scripts/screenshots/run-screenshot-tests.sh compare` has committed iPad baselines for the agreed canonical iPad.
- Any remaining unsupported screen class is documented as an explicit follow-up, not an accidental gap.
