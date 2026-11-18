# Focused review and independent reimbursements

The detail page now has one Edit action. The duplicate amount/merchant/category/date shortcut was removed. Notification detail has one purpose-review action and sends changes to an existing expense through its detail page. Item editing remains a focused task for line items; refunds, reimbursement receipts and settlements remain separate money events rather than edits to the original purchase.

## Navigation responsibilities

- Overview: current summary, budget, recent activity and a conditional Needs attention entry. Detailed categories, trends, savings and payment breakdown live under Insights & plans. Annual review and monthly comparison are accessed there, not repeated in Tools.
- Ledger: transaction history and the same Needs attention queue. The More menu opens notification history rather than repeating the pending-review entry.
- Accounts: balances and transfers. Review automatic entry accounts opens the account filter in the shared queue; the separate account-review implementation was removed. Saved-rule matching remains available in that filter.
- Review: one next step per record, with duplicate review ahead of missing account and purpose. Linked expenses are not listed again alongside their notification. Friend-paid purchases are not mistaken for a missing debit from the user's account. Completed and ignored notices remain accessible in history.
- Friends: mutual balances state who pays whom after offset. Original debts and settlement records remain available in friend details.

## Independent money flows

For a RM40.40 expense advanced by James, the user may claim their own share from a company before or after settling James. Claiming excludes that share from personal spending under the existing reporting policy. Receiving the company payment credits the selected account without becoming income or settling James. Paying James debits the selected account without creating another expense. Undoing either event restores only its own allocation and cash movement.

Manual reimbursement receipts share the bank/TNG receipt model. Partial receipts, full receipts, explicit excess rounding, duplicate detection, backup reload and undo follow the same rules. A stale editor, missing receiving account or suspected duplicate must not partially mutate the ledger.

## Validation and release boundaries

Model regressions cover one-task-per-record review, account resolution, duplicate priority, friend-paid claims before/after settlement, receipts before paying the friend, partial/full receipts, rounding, stale/duplicate rejection, serialization and independent undo. The existing cold-launch UI scenario now also asserts a single Edit action and absence of the removed shortcut.

Windows project/localization and syntax checks cannot establish native Swift compilation or visual correctness. The full GitHub iOS workflow is the native build/test gate. Physical-device review of light/dark mode, larger text, VoiceOver, keyboard, Reduce Motion, long ledgers and interrupted saves remains necessary before declaring the app ready for public release. This change does not claim universal notification recognition or cover unsupported statement formats.

The layout uses progressive disclosure: show the task now, reveal supporting detail when requested. See [Nielsen Norman Group: Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/).
