# Production visual polish braindump

Date: 2026-05-29

## Intent

This pass is primarily about getting LifeOrganize visually ready for production. The app already has the right high-level structure: persistent navigation, a main workspace, contextual detail panes, and strong iPad use of space. The next pass should not add major product scope. It should make the existing experience feel finished, consistent, calm, and professional.

The key work is theme finalization, noise reduction, hiding or translating debug/internal surfaces, and making the UI read as one coherent product rather than several feature prototypes stitched together.

## Product feel target

LifeOrganize should feel like a quiet personal operations tool:

- Clear enough to understand at a glance.
- Calm enough to live with every day.
- Dense enough to be useful on iPad without becoming busy.
- Professional enough that review states, reminder states, extraction states, and timeline history all feel intentional.
- Trustworthy enough that the app does not expose implementation details unless the user explicitly asks for diagnostics.

The desired feel is closer to a polished productivity system than a demo of an extraction engine.

## Non-goals

- Do not redesign the product architecture.
- Do not add new features as part of this pass unless required to remove visual dead ends.
- Do not change data behavior unless user-facing debug text depends on it.
- Do not over-animate or add decorative art.
- Do not make a marketing-style interface.
- Do not hide important review/accountability information; translate it into user-facing language instead.

## Highest priority outcomes

1. Normal production UI should not show raw debug identifiers.
2. The major screens should share the same card, badge, toolbar, empty-state, and detail-pane language.
3. Accent colors should have strict semantic roles.
4. Review states should feel like clear user tasks, not extraction logs.
5. iPad layouts should feel intentionally composed across Timeline, Things, Carry Forward, Review, and Settings.
6. The app should look coherent when screenshots are viewed side by side.

## Current visual read

The app is close, but several surfaces still feel internal:

- Review exposes evidence and validation language too directly.
- Multiple badge colors compete for attention.
- Orange is overused and sometimes colors whole surfaces that are only mildly actionable.
- Some cards feel like system settings groups, others like debug panels, others like warning banners.
- Floating toolbars vary between screens.
- Empty states are functional but not always polished.
- The sidebar selected state is clear but slightly default/prototype-like.
- Some user-facing copy repeats implementation concepts such as records, extracted details, validation, and blocked next steps.

## Theme principles

### Color

Define a small semantic color system and enforce it consistently.

- Blue: navigation, informational links, selected context, primary non-destructive actions.
- Orange: review required, attention needed, upcoming work that needs human judgment.
- Red: destructive action only, such as Dismiss or Delete.
- Teal/green: calm, completed, quiet, stable, healthy status.
- Purple: avoid unless it has a specific semantic role. Right now it adds noise.
- Gray: secondary metadata, disabled states, dividers, neutral labels.

Avoid rows where the entire background is tinted only because one tag inside the row is actionable. Prefer neutral cards with small semantic accents.

### Surfaces

Pick one production card system:

- Neutral card fill.
- Subtle border.
- Minimal shadow, if any.
- Consistent corner radius.
- Consistent internal padding.
- Consistent row spacing.

Use stronger borders or color fills only when they communicate state. For example, review-required items can have a small orange leading rail, orange icon, or orange badge, but should not make the whole screen feel orange.

### Typography

Keep the current large iPad titles; they work. Tighten the lower hierarchy:

- Screen title: strong and stable.
- Section title: small, blue or neutral, consistent casing.
- Item title: readable, high contrast, not oversized.
- Metadata: muted, compact, consistent line height.
- Debug/detail text: hidden from production unless inside an explicit diagnostics affordance.

Avoid repeating a title and its status in multiple adjacent places. The user should be able to scan once and understand the item.

### Icons

Icon weight should feel consistent across sidebar, toolbars, empty states, and cards.

- Sidebar icons can remain simple and large.
- Toolbar icons should have the same visual weight and spacing.
- Empty-state icons should be soft and quiet, not attention-grabbing.
- Warning/review icons should use orange sparingly.

### Layout

The iPad layout is strongest when it feels like a workspace:

- Sidebar fixed on the left.
- Main list/work area centered and readable.
- Detail pane on the right when context exists.
- Empty states centered within their pane, not drifting.
- Top toolbars aligned to screen-level conventions.

Avoid making each screen invent its own top action model.

## Debug and internal text cleanup

Normal production UI should not display:

- `partial_validation_failed`
- Raw validation status identifiers.
- Raw extraction state names.
- Raw source snippets that trail off without clear purpose.
- Internal terms like "created saved records" when simpler product language works.
- Overly technical section labels like "Evidence" unless the user is explicitly reviewing evidence.
- Repeated implementation nouns such as "record" where "item", "thing", "reminder", or the actual content is clearer.

Suggested translations:

- `partial_validation_failed` -> "Needs confirmation" or hide behind details.
- "Some extracted details need review." -> "Check the details before this is marked done."
- "This entry created 2 records." -> "This created a thing and a reminder."
- "Next Step Blocked" -> "Review the saved items"
- "Open those records to check or edit them." -> "Open the saved items to confirm or adjust them."
- "Source: Stores dogs t..." -> remove, or show only in a diagnostics/details disclosure.
- "Evidence" -> "What we found" only if the section is still necessary.

## Component rules

### Sidebar

The sidebar is structurally good. Polish opportunities:

- Make the selected state less like a default table highlight.
- Consider a subtle active rail, stronger label weight, and icon tint.
- Keep selection backgrounds soft and full-width only if that style is repeated elsewhere.
- Align section spacing and icon/title baselines carefully.
- Keep section labels muted, but ensure they do not look disabled.

The sidebar should feel durable and app-defining.

### Floating toolbar

Toolbars need one system.

Decide whether the toolbar is:

- Global navigation/action chrome, or
- Screen-specific controls, or
- A combination where global icons stay stable and screen-specific actions appear in predictable slots.

Suggested order when visible:

1. Review / carry-forward or current-work indicator.
2. Search.
3. Settings.
4. Add.
5. Overflow / more.
6. Edit only when it applies to the current screen or selection.

Avoid changing icon order screen to screen without a clear reason.

### Search field

The search field on Things looks good but should match toolbar spacing and height.

- Keep the placeholder specific: "Search things" is good.
- Avoid mixing search as both a standalone field and an icon-only action without clear screen logic.
- If some screens only show the icon, make sure tapping it leads to the same search surface.

### Cards

Cards should be visually quiet by default.

Recommended card pattern:

- White or near-white fill.
- Thin neutral border.
- 8-12 px corner radius, matching app conventions.
- Compact vertical padding.
- Optional left rail only for state.
- Badges grouped after the title or metadata, not scattered.

Avoid:

- Too many pastel fills.
- Multiple borders plus badges plus colored text on the same item.
- Nested card-looking elements inside card-looking sections.

### Badges

Badges are currently useful but too numerous and colorful.

Rules:

- One primary status badge per item.
- Secondary badges only when they change what the user should do.
- Keep badge colors semantic.
- Avoid using badges for categories if those categories can be shown as plain metadata.
- Prefer short labels: "Review", "Due", "Upcoming", "Quiet", "Pet", "Project".

For Things, a row like "Dog / Pet / Review / 2 records / Reminder tomorrow / Review..." is too much. The row can carry the same information with one title, one semantic badge, and one or two metadata lines.

### Empty states

Empty states should be calm and useful:

- Use a soft icon.
- Use one short label.
- Optionally include one muted sentence if it helps.
- Center within the pane.
- Do not look like debug placeholders.

"Select a reminder" is okay. It can become more polished with a softer icon, stronger vertical centering, and consistent text color.

### Bottom input

The Timeline bottom input is promising but needs production cleanup:

- "Connecting details..." feels diagnostic. Replace with user-facing status or hide unless meaningful.
- The input placeholder is good: "Add anything or ask what's due".
- Ensure the plus button has consistent size and contrast.
- The bottom bar should feel integrated with the app, not like a debug console.

## Screen-by-screen notes

### Timeline

Current strengths:

- The screen title is strong.
- Timeline grouping is readable.
- The onboarding card is helpful.
- The bottom input gives the screen a clear primary action.

Polish targets:

- Reduce the startup card tint and border if it competes with timeline content.
- Make timeline day cards consistent with other list cards.
- Confirm the muted text contrast is still readable.
- Remove or translate "Connecting details..." if it is internal.
- Make note/reminder labels quieter and more consistent.
- Ensure category chips such as "Airflow" and "Golf" follow the badge color rules.

Production copy ideas:

- "LifeOrganize starts here" is good.
- "Capture a note, task, receipt, or question..." is good but a bit long; consider tightening.
- "Today", "May 30", and "Jun 1" group labels work well.

### Things

Current strengths:

- This is probably the most promising production screen.
- Master/detail structure is strong.
- The right summary pane has useful content.
- Search placement is good.
- "Dog" detail page has a clear user focus.

Polish targets:

- Simplify list rows.
- Reduce badge density in the selected item.
- Make the introductory "Your organized subjects" card less prominent after first use.
- Make the summary pane use the same card/list language as the main pane.
- Avoid repeating review state in every nearby area.
- Clean up "0 events - 0 notes - 0 active reminders" formatting so it feels intentional.

Suggested row structure:

- Title: Dog
- Badges: Pet, Review
- Metadata: Reminder tomorrow
- Secondary line: 2 saved items

Avoid having "Review: Entry needs review" on the row if the Review badge is already visible.

Right pane:

- "Summary" works.
- "Quiet" works as a state, but the badge and section can be visually quieter.
- "Latest activity: Stores dogs" is good.
- "Scheduled Reminder" is good.
- The review callout should be tighter and less orange-dominant.
- Collapsible sections are good, but the chevrons and row spacing should match a single component system.

### Carry Forward

Current strengths:

- The concept is clear.
- The screen name is strong.
- The list has useful upcoming reminders.
- Empty detail state is clear.

Polish targets:

- Orange currently dominates the whole list. Use it as an accent, not a base surface.
- The help card "What should resurface" is useful, but should be quieter once the user has content.
- The selected/not-selected detail pane should feel like the same system as Things.
- The toolbar should match other screens.
- Reminder rows need clearer hierarchy: title first, then due timing, then reason/status.

Suggested row pattern:

- Title: Stores dogs
- Badges: Upcoming, Review
- Metadata: Due May 30, 2026
- Reason: Will move to Now on that date

If "Due date" is a system attribute, make it neutral. Do not color it like an action.

### Review

Current strengths:

- The split review model is useful.
- The user can see the original entry, suggested interpretation, and actions.
- Edit actions are present.

This is the screen that most needs production cleanup.

Problems to address:

- "Evidence" feels technical.
- `partial_validation_failed` is a debug leak.
- "Next Step Blocked" sounds like system state rather than user guidance.
- "This entry created 2 records" exposes implementation language.
- The same idea appears in too many places: entry needs review, created records, open records, edit thing, edit reminder.
- The left review card has a strong blue outline, orange rail, multiple badges, a warning icon, and orange text all competing.

Suggested user-facing model:

- Original Entry
- Saved Items
- Needs Confirmation
- Actions

Suggested copy:

- "Original Entry"
- "Stores dogs tomorrow evening at some point"
- "Saved Items"
- "Dog" / "Thing"
- "Stores dogs" / "Reminder"
- "Needs Confirmation"
- "Confirm the saved thing and reminder before marking this reviewed."
- "Edit Thing"
- "Edit Reminder"
- "Mark Reviewed"
- "Snooze"
- "Dismiss"

Possible removals:

- Remove "Evidence" from default view.
- Hide raw failure status.
- Remove duplicate "Suggested Interpretation" if "Saved Items" communicates the same thing.
- Replace "Next Step Blocked" with a friendlier action header.

Left review card:

- Use one orange review badge.
- Use one subtle orange leading rail or icon, not both plus a bright outline.
- Remove the blue outline unless it indicates keyboard focus or actual selection.
- If selected, use the same selected-row treatment as Things and Carry Forward.

### Settings

Settings is not pictured here, but the polish pass should include it for consistency.

Targets:

- Remove developer-only toggles from production builds.
- Group settings into stable sections.
- Make destructive data controls visually distinct and separated.
- Ensure diagnostics/export controls are behind a clear advanced/debug grouping if they remain.
- Match sidebar, card, section header, and row styles used elsewhere.

## Copy cleanup checklist

Audit visible strings for these categories:

- Raw state IDs.
- Failed validation terminology.
- Internal persistence terms.
- Debug transport/service status.
- Repeated descriptions.
- Placeholder text left from fixtures.
- User-hostile blocked/failed wording.

Preferred language:

- "Needs review"
- "Needs confirmation"
- "Saved items"
- "Reminder"
- "Thing"
- "Open"
- "Edit"
- "Mark reviewed"
- "Snooze"
- "Dismiss"

Avoid in normal UI:

- "validation"
- "partial"
- "failed"
- "record" unless the product has taught that term
- "source" unless it is a user-facing source
- "blocked" unless the user is actually blocked by a workflow
- raw enum values

## Interaction polish

Selection behavior:

- Selected rows should be visually consistent across lists.
- If a row opens a detail pane, that selected state should remain clear.
- Review cards and reminder cards should not use unrelated selection styles.

Disabled actions:

- Disabled actions should explain themselves only when necessary.
- Do not show disabled-looking primary user actions unless there is a clear next step.
- In Review, if "Mark Reviewed" is unavailable, the UI should say what must be done first in plain language.

Dismiss/destructive actions:

- Red should be reserved for destructive actions.
- Destructive actions should not visually compete with edit/confirm actions.

First-run/help cards:

- Good for orientation, but they should not dominate once real content exists.
- Consider making them dismissible, collapsible, or less visually loud after first use.

## Visual QA checklist

Run this pass by looking at full-screen iPad screenshots, not just component previews.

For each primary screen:

- Sidebar selected state looks intentional.
- Screen title alignment is consistent.
- Toolbar placement and order are consistent.
- Main content starts at a predictable vertical rhythm.
- Card styles match across screens.
- Badges use approved semantic colors.
- Empty states are centered and calm.
- No debug/internal text is visible.
- No section looks visually heavier than its importance.
- Text does not clip or wrap awkwardly.
- Long item names still fit cleanly.
- Right detail panes do not look abandoned when empty.
- Bottom input/status areas do not look like debug consoles.

Compare screenshots side by side:

- Timeline vs Things should feel like the same product.
- Carry Forward orange should not overpower the theme.
- Review should feel like a polished workflow, not a diagnostic report.
- Sidebar and toolbar chrome should be stable across all screens.

## Accessibility and contrast

Production polish should not reduce accessibility.

- Check contrast for muted gray metadata.
- Check contrast for colored badges.
- Ensure selected sidebar rows and selected list rows are visible without relying only on color.
- Keep touch targets comfortably sized.
- Make icon-only buttons accessible with labels.
- Ensure Dynamic Type does not break list rows or badges.
- Avoid tiny badge text that becomes unreadable on iPad screenshots.

## Suggested implementation order

1. Define theme tokens for surfaces, borders, fills, text, semantic colors, badges, and selected states.
2. Create or consolidate shared card/list/badge components.
3. Apply the shared style to Sidebar, Timeline cards, Things rows, Carry Forward rows, and Review cards.
4. Remove or translate debug/internal text from production UI.
5. Normalize toolbar composition and icon order.
6. Clean up Review copy and layout.
7. Clean up Things and Carry Forward list density.
8. Clean up Timeline bottom input/status treatment.
9. Review Settings for production-only visibility.
10. Capture iPad screenshots and iterate from the full-screen visual read.

## Acceptance criteria

- No raw validation, extraction, persistence, or enum identifiers appear in normal UI.
- Review screen uses user-facing task language.
- At most one primary semantic status badge appears per row.
- Orange is reserved for attention/review, not broad decoration.
- Red is reserved for destructive actions.
- Cards, list rows, section headers, and detail panes share one visual system.
- Toolbars use consistent icon order, weight, and spacing.
- Sidebar selected state feels intentional and production-ready.
- Empty states feel polished and aligned.
- Timeline, Things, Carry Forward, and Review look coherent as a suite.
- iPad Pro screenshots pass a side-by-side visual review without obvious prototype/debug artifacts.

## Final note

This should be treated as a finishing pass with strong restraint. The app already has enough UI. The production step is to remove noise, clarify hierarchy, standardize the theme, and make every visible string and color earn its place.
