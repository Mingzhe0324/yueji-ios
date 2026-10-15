# Direct categories and selected repayments

- Overview category rows navigate directly to their payments, without a selection/highlight step. The destination shows that category's percentage of the same month's personal spending.
- Overview and Ledger month pickers no longer show an indeterminate spinner. Existing completed data remains while the background projection prepares the latest month; cancelled/stale results are still rejected.
- Ledger projection tasks are scoped to the selected tab. Switching away cancels pending work and prevents a completed result from rebuilding the hidden list. Ledger transaction detail navigation uses the standard system push/pop instead of the matched zoom transition. These reduce transition work; actual device performance still needs profiling and verification.
- Incoming bank/TNG repayment confirmation requires choosing outstanding expenses. Only selected eligible debts are repaid, oldest selected first for partial receipts. Empty/stale selections and overpayment are rejected before mutation. The existing notification repayment IDs, undo, backup, and purchase-preview path are retained.
- Friend details expose a direct 'Record repayment / choose expenses' entry to the existing selection and review flow.

Native regression coverage checks a newer selected expense leaves the older expense unpaid, invalid selection is atomic, spending is unchanged, backup preserves allocation, undo retains unrelated repayments, and overpayment is rejected. Windows project/syntax checks do not replace Xcode execution or real-device rapid navigation checks.
