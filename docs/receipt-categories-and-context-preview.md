# Receipt categories and transaction context previews

Receipt splitting now uses general item/cost wording in the screen, shared summary and guide, so shopping and other expenses are not described as meals. New receipt expenses default to Other and offer all built-in and custom ledger categories. Selecting a category invalidates the review confirmation. Attaching shares to an existing payment preserves its category. Allocation and rounding calculations are unchanged.

The shared expense context-menu modifier explicitly supplies LedgerModel to its preview's ExpenseRow. That row and its restore highlight both require the model. This covers Overview recent entries and Ledger rows. Missing environment propagation into the separate preview host is a suspected cause of the reported long-press termination; a device crash log and native verification are still needed to confirm the diagnosis.

The existing cold-launch saved-entry UI cases now long-press a recent entry, check Edit/Delete and foreground state, open Edit, cancel, and then continue into details. Run these cases on macOS/Xcode. Device checks should also include long-pressing ledger entries, custom categories, and entries with split/reimbursement details.

Receipt device checks: scan a non-food MYR receipt, choose Shopping (and a custom category), review and save, then confirm the saved category and shares; attach another receipt to an existing payment and confirm its category is retained. Check equal and per-item allocation and the shared summary.
