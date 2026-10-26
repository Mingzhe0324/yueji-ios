# YueJi complete UX review — 1.59.0, build 87

Later backup changes: [reinstall recovery](reinstall-recovery.md) documents the new first-launch restore entry and backup-after-change behavior. The build 87 findings below remain historical; native/device validation for the new recovery flow is still required.

Account-based recovery is now implemented separately; see [CloudSetup.md](../CloudSetup.md) for service configuration, automatic restore behavior, offline/conflict handling and pending native/backend tests. Public client configuration is saved for device builds. After database initialization, a 2026-10-25 read-only recheck confirmed Auth and schema health are reachable; email setup and end-to-end verification remain pending.

This is a source review and implementation record. Native compilation, XCTest execution, touch geometry, animation frame timing and physical-device navigation have not been verified on this Windows workstation. A fresh CI run from the new `main` commit is required; rerunning an old failed job uses its old sources.

The user-supplied Azure test summary for build 87 shows native compilation completed and 207 tests executed, with one unexpected failure in `testPreparedFriendAndInboxIndexMatchesLedgerBeforeAndAfterSettlement`. Its two incoming-notice fixtures omitted the required sender (`party`), causing accounting validation to reject the fixture before index assertions. Both senders are now supplied, the fixture is validated explicitly, and its date uses the fixed settlement example date. App code and validation remain unchanged. A new CI run is required to confirm this correction; no successful rerun or physical-device performance verification is claimed.

## Findings and changes

| Journey | Finding | Implementation |
| --- | --- | --- |
| Overview → manual entry | A full-width Add Entry control occupied the native bottom toolbar next to the floating tabs. This is a plausible cause of the reported tap reaching Recurring after scrolling; the screenshot alone cannot prove its runtime hit geometry. | Move Add Entry into a padded bottom safe-area row above the expanded tab bar. Hide the bottom toolbar. Keep the add button and native tab navigation in separate layout regions. |
| Ledger → details → back | Sorting/filtering had already moved to a background actor in build 86, but other screens still recalculated whole-ledger data and legacy writes/readbacks blocked the main actor. | Retain prepared ledger rows/query state, reject stale results, index detail/debt/settlement/inbox lookups, and move UI financial writes and refreshes to the storage actor. Root navigation identity remains stable. |
| Transaction actions | Detail buttons must stay distinct from the bottom-left tab button, including accessibility sizes. Deleting inside an editor must not pop detail while its sheet is dismissing. | Separate Edit/Delete targets, minimum 44-point heights, safe-area padding, vertical accessibility layout, visible expanded tabs, and one guarded return after the editor's native dismissal completes. |
| Main-screen presentations | Ledger and Recurring each had independent add/edit/filter sheet states. | One item-based route per screen; repeated taps cannot schedule competing presentations. A new ledger entry captures the selected date when opened. |
| Automatic-record review | “Edit expense / split” opened a second detail page. Several confirmation and recognition actions performed disk writes on the main actor. | Open the actual expense editor directly. Key financial operations by notice ID, capture submitted values, commit in the storage actor, publish the latest file, then show success. |
| Overview and reports | Overview, monthly/category comparisons, friend reports, tag reports, statements, upcoming bills and exports repeated data work during view updates. | Prepare results outside the main actor and keep them in screen state. Reuse bounded overview/timeline caches. Show a noninteractive updating indicator without shifting content. Friend report balances include both debt directions; tag account-payment totals exclude friend-paid money. |
| Friends and settlement | Repeated debt/settlement scans could be triggered by feedback, typing or navigation. Repeated financial taps must not queue duplicate writes. | Cache debt lists, balances, expense/payment IDs and sorted settlement history per ledger revision. Guard in-flight actions by operation key. Existing settlement/duplicate-payment validation remains authoritative. |
| Forms and currency | Reappearance reset recurring/category/repayment/note/preview state. Old rate requests could clear a newer request's busy state or replace edited input. | Initialize drafts once. Keep form identity through picker/back navigation. Use request tokens/cancellation guards, preserve manually edited rates, and show saving state in the principal editors. Prevent dismissal during those commits. |
| Receipts | OCR already ran outside the main actor, but saving blocked it and photo changes used unstructured read tasks that could deliver stale results. | Background receipt commits; reset the receipt draft only after success. Tie photo loading to selection identity and reject cancelled/superseded OCR results. |
| Settings and backup | Changing language recreated the app's root. Backup reads, decoding, enumeration, restore and export ran in UI callbacks. | Observe locale in display views and retain navigation state. Move backup IO to the storage actor, retain explicit restore confirmation, and cancel pending preview/export presentation when leaving the backup page. |
| Feedback, scrolling and motion | Saving inserted/removed a list safe-area row. The month header's drag could claim a vertical scroll. Some whole-list/form animations included unrelated changes. | Saved notices use a noninteractive overlay; Undo remains a separate reachable inset. Give month arrow labels 44-point targets, allow simultaneous vertical scrolling, and animate month labels locally. Replace source-linked zoom with native push/pop/sheet transitions; remove broad list/form animation and use short local amount/progress effects. System Reduce Motion remains respected. |

No ledger schema or backup migration is introduced. Version 6 records, original spending, splits, repayments, refunds, settlement audits and automatic-record deduplication are preserved. The background mutation path keeps each caller's recurring-posting policy; deletion, undo and savings do not introduce new recurring posting.

## Regression coverage added

The new native tests are authored, not executed here:

- `testOverviewProjectionCachesAndInvalidatesItemCategoryTotals`: repeated cached RM35 item reports and category-edit invalidation without double counting.
- `testPreparedFriendAndInboxIndexMatchesLedgerBeforeAndAfterSettlement`: balances, debt IDs, stable inbox order, incoming income, settlement and undo match the accounting model.
- `testRapidRepeatedPaymentActionCommitsOnlyOnceAndClearsBusyState`: twelve same-key taps apply one RM5 partial repayment; personal spending remains RM55.
- `testOverlappingIndependentOperationsPublishLatestSnapshotAndRejectFailedWrite`: both edits survive overlapping saves, and a rejected action changes neither disk nor published records.
- `testCancelledBackgroundMutationDoesNotAlterStoredLedger`: cancellation before writing preserves the original file.
- `testCancellationAfterCommitStillPublishesSavedRecord`: cancellation after a disk commit still refreshes the visible record.
- `testBackgroundBackupExportPreviewAndRestorePreserveExistingRecords`: background export/preview/restore retain the existing expense records.

Build 86's cache, invalidation, accounting/undo and 20,000-entry indexed-lookup tests remain in the suite. Neither those unit tests nor parsing/resource checks establish frame rate, tap geometry or native gesture behavior.

## Native journey checklist

Run the complete YueJi scheme on an iPhone simulator first. Then use a Release build on a physical compact iPhone and a larger iPhone; repeat in light/dark mode, Chinese/English/Malay, larger accessibility text, Reduce Motion and Reduce Transparency.

1. Scroll Overview to the bottom and top repeatedly. Tap `overview.manualEntry` near each edge of its visible control. It must open New entry every time. Tapping the separate Recurring tab must open Recurring. No tap region may overlap.
2. Add a manual entry with items and a friend-paid share. Cancel and reopen; saved automatic entries must remain. Visit category/currency selectors, return and verify the draft, items, focus and selected date survive. Rapidly tap Save; only one record/payment should be created.
3. Filter/search Ledger, scroll halfway down, open several details and return at least twenty times. Include slow swipes, partial back swipes cancelled halfway, quick reversed swipes and repeated row taps. Preserve month, search, filters and scroll position without a blank frame or renewed unchanged-query work.
4. Verify `transaction.edit` and `transaction.delete` are fully visible above the tab bar and home indicator, including landscape and large text. Edit → cancel → reopen; edit → delete; delete → Undo. Deleting from the editor must dismiss its sheet before returning one navigation level.
5. Review an automatic bank/TNG record, open Edit directly, save items, confirm purpose, link a settlement, undo and reopen it. Repeated taps must not duplicate payment application. Check the actual date/direction/reference before linking; amount alone is never confirmation.
6. On Friends, exercise equal/custom/entirely-mine splits, selected and unselected debts, RM55/RM5 net settlement, partial settlement, zero-transfer offset and undo. Visit each linked original expense and return. Both debt directions and personal spending must remain correct.
7. Create/edit/pause/resume a recurring schedule, enter a foreign currency and rapidly switch currencies including MYR. An old request must not overwrite the current rate or busy state. Scroll while dragging the month header vertically; normal scrolling must continue.
8. Switch tabs while preserving each screen's navigation, then change language/appearance in Settings and return to a previously scrolled/pushed tab. All labels should update without resetting the selected tab, route, month or draft.
9. Review category, monthly comparison, friend/tag, upcoming and statement reports after editing/refunding/undoing an expense. Verify item category totals, incoming/expense signs, friend-paid spending and actual account movement. Only share/export a report once its current query is ready.
10. Choose another receipt photo before the first scan completes; cancel camera/photo selection; review and save. The current selection must win, and save failure must retain the editable draft. Verify large-image preview decoding/rendering separately with Instruments.
11. Export JSON/CSV, preview a backup, cancel, restore after confirmation, and navigate back during preview preparation. No cancelled background operation should unexpectedly reopen a sheet; no records may be lost or duplicated.
12. Trigger an automatic record while scrolling or returning from detail. Exercise the new-record banner, error alert, saved notice and Undo banner together. Verify that their controls remain separate, keyboard dismissal feels native, and feedback never intercepts another control's tap.

## Physical performance verification still required

Use [SwiftUI Instruments and Time Profiler](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance) together with Animation Hitches. Compare builds 86 and 87 under the same data/device conditions, including 10,000+ expenses, many splits/settlements, large receipts and large backups. Inspect long body updates, main-thread IO/CPU, image decode/render cost, update causes, frame deadlines and memory. Capture the twenty push/pop cycles, cancelled gestures, background automatic arrivals and repeated saves.

No frame-rate improvement, zero-hitch result, physical touch-layout pass or successful IPA build is claimed by this source review. Any remaining runtime bottleneck needs an actual trace; longer animations or added input delays are not substitutes.
# 2026-10-26 — Welcome and today's spending

- First-run account entry now uses a midnight-blue and warm-gold welcome screen with a floating moon, softly twinkling stars, and a ledger illustration. Create account and returning sign-in lead to email-code forms; returning sign-in does not implicitly create an account.
- Motion pauses in the background and respects Reduce Motion and the app animation preference. Forms scroll for keyboard access and larger text, with email/code autofill and Chinese, English, and Malay copy. Local-only entry remains available for unbound ledgers; account ownership and sync conflict handling remain intact.
- Today's spending moved from the bottom tab accessory to the Overview header below the monthly summary, shown only for the current month. The amount still follows the privacy toggle and the existing personal-spending calculation. Existing toolbar entry buttons remain available.
- Project and syntax checks pass. Added an HTTP fixture test for sign-in versus account creation. Native compilation, XCTest execution, VoiceOver, keyboard, and physical-device visual verification still require macOS/iOS. This design change does not resolve the outstanding device connection failure.

