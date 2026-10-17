# Item count in a virtualized Form

The 2026-10-17 17:27 UTC CI failure at TransactionFormTests.swift:312 reported
two `transaction.item.name` fields instead of three. The captured accessibility
hierarchy already contains Item 2 and Item 3. Item 1 is above the instantiated
rows, so a TextField query count is not a draft item count. The first Add Item
operation and the sheet discard/keep-editing flow had already passed.

The Add item button now exposes the complete draft count as a localized
accessibility value. Tests verify each addition and deletion against that count.
Item name labels and removal values identify row ordinals, so scrolling does
not change which row a test edits or deletes. The regression scrolls back to
Item 1 and verifies Lunch survives before removing that specific item, then
edits the first remaining item. Saved-item tests also avoid counting lazy fields.

No test retries, skipped cases, extra timeout or weakened expected count were
added. Windows static/syntax checks do not replace the next native XCTest run.
