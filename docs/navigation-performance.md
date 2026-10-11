# Transaction navigation verification — build 86

## What changed

The transaction detail bottom action row uses `safeAreaInset` above the visible tab bar, with horizontal padding, separate Edit/Delete buttons, minimum 44-point target heights and a vertical layout for accessibility text sizes. The tab bar stays expanded while scrolling, keeping its navigation buttons available in their own safe area. The detail destination hides the inherited native bottom toolbar so it cannot share the action row. Native navigation restores any parent toolbar on returning to the ledger.

Ledger view bodies no longer filter, sort, total or group the entire ledger. `LedgerProjectionWorker` builds immutable display results off the main actor and caches up to six queries per ledger revision. Existing rows stay mounted while visiting details. The task skips work altogether when returning with the same query; unchanged feedback state cannot invalidate the ledger revision. Results from cancelled or outdated queries are rejected. Searches and month/filter changes keep the preceding rows visible with a small updating indicator until the current query completes.

Normal asynchronous refreshes prepare an expense/settlement index before publishing the ledger. Detail bodies perform indexed lookups and use precomputed settlement applications. Preview data and older synchronous mutation flows build an index once after a revision, so those flows still require profiling separately. Date labels use [Foundation FormatStyle caching](https://developer.apple.com/documentation/foundation/formatstyle). Native push and interactive back gestures remain system-controlled; there are no custom gesture delays or longer animation durations.

## Native tests

Run the YueJi scheme's tests using a new CI build from `main`. `LedgerTests` contains:

- `testNavigationIndexPreservesDebtsLinkedDetailsAndUndo`
- `testTimelineProjectionsReuseRowsAndPreserveFiltersPaymentsAndEdits` — thirty identical requests must build exactly one timeline.
- `testNavigationReadModelsInvalidateAfterChangesButIgnoreFeedback`
- `testCancelledProjectionDoesNotPublishOrPopulateCache`
- `testRepeatedIndexedDetailLookupsWithLargeLedgerPerformance` — time, CPU and memory metrics for repeated lookups in 20,000 expenses; index construction is outside the measured interval.

These check read-model correctness and repeated work. They do not establish rendering frame rate, bar placement or gesture smoothness on an iPhone.

## Required simulator and device review

1. Test a compact iPhone and a large iPhone, light/dark appearance, all three app languages, default/largest accessibility text, and Reduce Motion on/off. Scroll transaction details to the bottom: tab buttons, Edit and Delete must remain separately visible, easy to tap and clear of the home indicator. Check both pushed details and details presented from notifications. Edit, cancel, delete/undo, tab switching and linked-settlement navigation must still work.
2. Scroll the ledger halfway down and open/pop the same and different expense rows at least twenty times. Also test bank and settlement rows. Check that the ledger retains its scroll position, rows and month/filter selection; there should be no blank or white intermediate frame or repeated loading indicator on an unchanged return.
3. Begin swipe-back, reverse/cancel at roughly halfway, then complete it. Repeat quickly. The detail content, toolbar/tab visibility and button hit areas must follow the native gesture without disappearing or snapping. Repeat after editing items, a partial settlement and undo.
4. Profile a Release build on a physical iPhone with the SwiftUI, Time Profiler and Animation Hitches instruments. Use realistic small and large ledgers, including itemized purchases, refunds and settled expenses. Inspect twenty repeated pushes/pops, including the first visit, and compare with build 85 on the same device. Check long view-body updates, main-thread work and animation hitch time. Filtering/grouping should appear in `LedgerProjectionWorker`, and repeated detail lookups must not rescan all expenses or settlement lines. Use [Apple's SwiftUI performance guidance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance) to inspect update causes.
5. Rapidly change search/month/provider/filter, then edit/delete an expense or process an automatic record while a query is pending. Only the latest query and ledger revision may publish. Confirm amounts, item categories, outstanding debts and settlement links still match the original accounting.

The Windows workspace cannot run Xcode, XCTest, iPhone rendering or Instruments. Local structural/syntax checks are not a substitute for this native review; no device smoothness or frame-rate result is claimed by this document.
