# Everyday automation

The settings entry “Automatic recording” now groups payment-account links,
notification frequency, merchant rules, income allocation, backup and review status.
The app does not claim that a Shortcuts automation is installed merely because a
setup screen was visited.

## Implemented behavior

| Area | Behavior |
| --- | --- |
| Notifications | Existing per-entry delivery remains the default. Daily mode replaces one pending summary after successful expense recording. Attention-only mode suppresses successful expense notifications. Unresolved results and failures remain immediate. Disabling notifications removes a pending summary. |
| Entry editing | Expense notifications already open the editor directly. The detail screen now exposes common editing beside the amount. Merchant category memory is visible beside the category instead of inside currency options. |
| Review queue | Start a sequence of unresolved notices. Completing a notice opens the next after dismissal. Cancelling or leaving a notice unresolved stops the sequence. |
| Category memory | Existing explicit merchant rules and stale-write protection are retained. The user can inspect rules from the automation screen. |
| Income | Existing opt-in percentage allocation is now available directly from the automation screen. Transfers, top-ups, refunds and repayments are not automatically treated as income. |
| Recurring payments | Existing exact merchant/amount matching advances a matching schedule once. Ambiguous matches are not auto-confirmed. Existing amount-change alerts remain available. |
| Receipts | Matching payments use the same day and amount, excluding foreign, refunded, settled, friend-paid or already-split entries. One matching payment gets an attachment shortcut. Adding another matching payment requires an explicit distinct-payment choice, reset after editing the receipt. Existing OCR prefills and amount validation are retained. |
| Parking | Existing remembered plates, automatic location, receipt OCR and return-from-payment review are retained. Previous location for the selected plate can be reused explicitly; the bay is cleared. Opening the payment app never implies payment success. |
| Travel | New entries offer books whose inclusive date range contains the expense date. Selection is explicit and does not change currency or overwrite an existing trip. |
| Friends | A new split can reuse the names from the last split when its name fields are empty. Historical amounts, debts and repayments are not copied. |
| Backup/startup | Existing local-first launch and deferred maintenance remain. Backup runs before network rate refresh. A failed backup gets one retry; changing the folder prevents retrying the old folder. Rate refresh stops starting new requests after cancellation. |
| Research | Successful non-imported reports are saved to existing account-scoped local history. Reopening shows the prior report with its date and an explicit stale-source label. No automatic paid request, live-price claim or trade is introduced. |

## Verification

- Swift syntax parsing and project/resource validation run on Windows.
- Unit coverage adds notification policy and foreground-summary routing checks.
- Existing renewal, income-allocation, stale-write, duplicate and transaction UI
  tests remain required in the macOS CI workflow.
- Device acceptance: foreground/background/cold-launch notification navigation;
  summary delivery and opt-out; cancelling continuous review; a receipt matched
  to an existing payment; changing account while viewing saved research.
- Native compilation and simulator results must be read from CI; syntax checks
  alone are not a native build or device verification.
