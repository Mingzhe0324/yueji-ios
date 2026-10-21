# Travel books with separate budgets

Open Overview → Travel books, the card below Budget: trips have their own budgets,
so they sit beside the monthly one. The card shows the trip under way (else the next,
else the latest) with its spending against its budget. Create a trip with a name, destination, dates,
MYR budget and optional companions. Companions are descriptive; adding names
does not silently change the shares on existing entries.

Add a new trip expense from its detail page or select the travel book in the
ordinary expense editor. Existing daily entries can be selected in a batch.
Unchecking a trip entry returns it to the daily budget. Entries in other trips
are excluded from the batch picker; use the expense editor to reassign them.
Dates do not auto-classify entries, so booking deposits outside the trip dates
can still belong to the trip. No expense is duplicated.

The trip budget uses personalSpending, including existing personal refund and
reimbursement exclusions. Friend repayments affect outstanding debts, never
the budget a second time. Monthly totals and category reports retain travel
spending, while the daily monthly budget bar, status and budget notifications
exclude it. The overview separately identifies the travel portion.

Trip detail includes purchase totals after refunds, personal spending, budget
balance, categories, outstanding debt lines linked to existing expense/repayment
flows, and an in-app map of entries with coordinates. Amount and progress
animations reuse AnimatedMoney and SpendingMeter with Reduce Motion support.
Editing and batch selection retain the existing discard-confirmation behavior.

Trips and optional expense tripID persist through backups; old backups decode
with no trips. Unknown references, duplicate IDs and invalid dates/budgets are
rejected. Duplicating an expense intentionally does not inherit its trip.

Validation added in EverydayFlowTests covers independent budgets, unchanged
overall totals, returning entries to daily budgets, repayment/refund/claim
semantics, backup round trips and invalid references. Windows static/syntax
checks are available here; native compilation and XCTest still require macOS.

Delete a travel book from its edit page: **Delete Travel Book** (删除旅行账本 / Padam Buku
Perjalanan) is a red action at the bottom. The confirmation says exactly what happens: the book
is deleted and can't be restored, while its entries stay in the ledger, go back to everyday
spending and count towards the monthly budget again (`Ledger.deleteTrip`). After confirming,
the editor closes, the page returns to the list, and only then is the book removed, so the
page being left never shows emptied out. YueJi keeps no selected trip: the Overview card
picks the trip under way, else the next, else the latest, so it moves to another book
automatically. The ledger is stored on the device only (there is no cloud sync); earlier
automatic snapshots and exported backups still contain the book if one is restored.
