# Account settings and notice editing

- Settings → Account & sync: choose or remove a profile photo. A thumbnail is stored locally per account; photos are not cloud-synced.
- Settings → Account security: set/change password. Signed-out users are directed to sign in.
- Pending outgoing notices: select Expense, then Edit full entry. This uses the manual expense editor, including description, category, items, splitting, account and location. Saving links the existing notice atomically; a changed or already processed notice is rejected. Notice drafts have separate storage keys.
- Incoming friend repayments: select the friend and debts. When the receipt exceeds selected outstanding debt by exactly 1–2 cents, an explicit rounding toggle appears. The preview shows actual receipt, debt repayment and excess separately. Actual bank receipt remains unchanged. Undo removes the generated repayments and rounding classification, retaining the receipt. Larger excesses are still rejected.

## Validation

Windows: Swift tree-sitter syntax, project/resource structural checks and git whitespace checks passed. XCTest and device UI checks require Xcode/CI.

Added ledger tests cover 1/2-cent rounding consent, amount preservation, account balance, backup round-trip, undo, larger excess, stale selection, wrong friend, invalid repayment date, full-editor description/split preservation and duplicate-save rejection.

Device checks: select/remove avatar and switch accounts; open Account security; edit both pending and recorded notices; confirm/undo a RM10.01 or RM10.02 receipt against RM10.00 debt.
