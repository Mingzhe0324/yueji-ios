# Everyday entry experience

## Draft recovery

The main new/edit expense form stores raw input, including incomplete amounts, item quantities/ownership, split fields, tax/rounding fields and exchange-rate metadata, in a versioned local draft. It saves when fields change and when the app leaves the active state. Reopening offers Resume or Discard before saving a new result. Drafts are separate for new entries and each existing expense; they are not ledger entries and do not change reports. Save or explicit discard removes the corresponding draft. Restoring an existing-entry draft requires its original expense to match the editor's base, and normal save concurrency validation still applies. A resumed exchange rate is not replaced by an in-flight automatic fetch. Preview/demo mode does not persist drafts.

Scope: the main expense editor, not every standalone tool or settlement form. Local drafts are not included in ledger backup exports. Sudden process/power termination may precede the OS flushing the latest local preferences.

## Duplicate entry

Transaction detail has a Duplicate button opening an editable new purchase dated today. It retains purchase fields, base item prices/quantity/ownership, split amounts and charges. Expense/item/share identities are regenerated. Repayments, returns, refunds, reimbursement history, payment references, recurring links and old receipt evidence are not copied. Nothing is booked until Save.

## Automatic recording review

Recent automatic activity exposes pending notices directly with reason/date/party and a link to the correct review form. Missing amount, possible duplicate and purpose review are differentiated. Recovery errors and event details are visible; the existing persisted-delivery retry remains available. No event is replayed merely because it was opened.

## Repayment preview

Manual settlements already have per-expense preview and undo. Incoming bank/TNG repayment confirmation now also presents each selected expense, amount applied and remaining balance in a review sheet. Preview uses the same batch-allocation implementation on a copy. Save recomputes the allocation and rejects changed debts rather than silently applying an outdated preview. Existing repayment IDs and undo remain intact.

## Month and amount controls

Tap the month title for a date picker and Back to this month action. Selecting a date chooses its month; Cancel does not change the current month. Existing swipe/arrow navigation remains.

The charge editor displays the exact difference between actual payment and subtotal plus SST/service/rounding, with a Check rounding action focusing that field. Existing item-total differences remain visible beside item inputs. No difference is silently converted into rounding.

## Verification

Native regression tests cover new-copy identities/history isolation, incomplete local-draft round trip/removal/version handling, and repayment preview equality with actual allocation. Local project and Swift syntax checks are available on Windows; native compilation, test execution and UI interaction require the next Azure/Xcode run and device verification.
