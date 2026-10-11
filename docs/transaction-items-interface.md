# Transaction Items interface — Build 90

Notes are no longer editable or displayed in transaction forms, expense details or expense rows. Stored Expense.note and TNGNotice.note remain compatible with existing JSON backups and legacy search/export behavior; item edits copy the original expense rather than rebuilding it. No data migration or schema change is required.

Recorded bank/TNG purchases expose an expandable Items section and a visible Add items / Edit items button. Expense details also open the focused item editor. Manual entry and notification confirmation use the same ExpenseItemsFields component, with stable item IDs, individual names, MYR amounts and categories, and Reduce Motion-aware insertion/removal. Cancel keeps the saved transaction intact. Removing all items restores classification by the parent category without changing its total.

Item-only edits preserve source, date, foreign amount, notes, tags, split shares, repayments, refunds and receipt data. Validation rejects incomplete names, invalid categories, nonpositive amounts and sums unequal to the purchase total. The storage actor commits the edit atomically, rejects a stale original snapshot, and blocks changes to expenses with active settlements until those settlements are undone. Existing refunds and direct repayments remain intact. Reports continue to count item categories instead of counting both items and the parent.

Pending notifications may include optional items when explicitly confirmed as expenses. Leaving Items empty saves the expense normally, ready for later itemization. Income, refunds, account transfers and settlement payments keep their existing accounting purpose and do not become purchases through item editing.

Source information presents the original notification title and description separately from user-entered items. Expense details obtain linked source notices from the prepared navigation index, without scanning the ledger during navigation. Notices intentionally removed by the existing Clear processed notices action cannot be reconstructed; legacy notes are never substituted as notification text.

## Verification

Six XCTest regressions were added for:

- Adding, editing and removing items through the editor's storage path for manual and actual automatically recorded purchases, preserving notes, source notifications, repayment/refund history, identity and backup contents.
- Invalid totals and concurrent note updates leaving saved automatic records intact.
- Both notification confirmation paths saving item categories once and rejecting duplicate confirmation.
- Invalid itemized confirmations leaving pending notices unchanged.
- Indexed original source information remaining distinct from stored notes, including manual records and cleared notifications.
- Active settlements preventing silent item changes.

Local Windows checks verify Swift syntax, project resources/source registration, workflow YAML and embedded shell syntax. These checks do not compile SwiftUI or run XCTest.

On macOS CI, run the full YueJi test scheme and build the iPhone app. On a physical iPhone, verify:

1. Manual entry: add Lunch RM15 / Food & Drinks and Supplies RM20 / Shopping to a RM35 transaction. Save, then check one ledger row and category totals RM15/RM20.
2. Receive a real RM35 bank/TNG purchase. Open it from both the ledger and inbox; use Items without opening the general expense editor. Add, edit, delete and cancel repeatedly. Verify the original transaction remains and source title/description are unchanged.
3. Edit an old transaction with notes, then export and restore a backup. Verify the stored note survives despite its field being removed.
4. Enter incomplete items or a total of RM34.99. Save must explain the error while retaining the original transaction. Correct to RM35 and save successfully.
5. Repeat with partial repayments, refunds and friend-paid purchases. Check debt balances, original history, personal spending and category totals. Undo active settlements before item changes.
6. Rapidly tap Add, Remove and Save; change categories using native navigation and swipe back. Check keyboard behavior, tap targets, Dynamic Type, dark/light appearance, all three languages and Reduce Motion. Verify no duplicate sheets or records, pauses or white flashes. Physical performance is pending verification.
