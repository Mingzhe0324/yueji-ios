# Gemini bank notification automation

This is ledger automation, not a connection that can move money at a bank. It only sees notifications forwarded by the existing Shortcut. Original input is durably queued before analysis. Unknown or unavailable analysis falls back to existing local rules and review. No historical notices are silently reprocessed.

## Setup

1. Run `backend/bank-notification-gemini.sql` in the same Supabase project's SQL editor. This adds a separate per-user allowance of 100 analyses per UTC day (attempts consume quota).
2. Set server secrets `GEMINI_API_KEY` and `GEMINI_BANK_MODEL` (bare `gemini-...` ID supporting structured JSON). Receipt settings remain separate.
3. Deploy the `bank-notification-gemini` function using both files under `supabase/functions/bank-notification-gemini`. The handler verifies the Supabase user, rejects anonymous accounts and enforces quota. Do not disable authentication.
4. Build/install the updated app. Sign in and open Bank notification setup. Enable “AI analysis and account recording” after reading the upload disclosure. This preference is local to this device and ledger folder, and defaults off. Use “Check AI connection” to call the real service with a synthetic sample; it creates no ledger entry and consumes one analysis attempt.
5. Map each account's automatic source. Use a suffix only when notifications actually contain that own-account suffix. Unknown or ambiguous account mappings stay pending. Ensure opening timestamps precede the transactions being recorded.
6. Own-account transfers such as PB → TNG are confirmed through the existing notification review / transfer screens. The account editor no longer offers a destination-and-owner rule. Legacy rules stored in backups are ignored; existing transfer records remain intact. This removal only requires a new iOS build, not a Supabase deployment.

## Behavior and limits

- AI proposes type, direction, amount, counterparty, optional own-account suffix and peer bank/wallet. It receives the notification body/title/source, not the ledger, account IDs or balances. These texts can contain names and banking details; the opt-in disclosure explains transmission to Google. Server code logs neither prompts nor responses.
- Amounts must be a single explicit MYR amount agreeing with the original text. Evidence and names must occur in the body; completion/direction and known failure, future/pending, refund and other-currency signals are checked locally. A model's `completed` value alone is insufficient. Do not claim support for an unseen bank template: PB reload tests are synthetic, not verified real notification samples.
- Clear matched payments create expenses and debit the account. Clear matched incoming notices update the account balance before purpose review, without creating income or budget allocations. Confirming income later does not credit twice.
- The retired route no longer creates transfers automatically, including after backup restore or account assignment. Confirmed historical transfers and their undo behavior are retained. AI recognition of a bank/wallet name alone does not prove both accounts belong to the user.
- Original delivery and bank-reference duplicate checks remain active and commits remain atomic. AI cannot invent missing transfer notifications or choose account IDs. Assigning an account links the notice without automatically pairing it into a transfer.
- Background analysis uses the currently saved authenticated session and checks ledger ownership and active-account identity before/after the request. An expired session, missing deployment, quota exhaustion, lost network or invalid output falls back locally. Open/sync the account to refresh an expired session, then use the connection check. Requests are not retried indefinitely or silently replayed after a successful ledger commit.
- Account details include received-notification rows separately from assigned income; own transfers remain in Transfer history.

## Validation

Run `node --test backend/tests/receipt-gemini.test.mjs backend/tests/bank-notification-gemini.test.mjs`.
Native tests cover checked payments, missing accounts, duplicate delivery, amount/direction rejection, incoming credit without income, disabled legacy transfer routes in either arrival order, persistence and missing-side behavior. Existing manual transfer/financial regressions remain required. Native execution needs macOS/Xcode; Windows syntax and project checks are not substitutes.

Before enabling on real notifications, verify on an iPhone: connection check, one MYR purchase, one incoming credit, PB/TNG pair, repeated notification, unknown account, offline fallback, account switch and transfer undo. Confirm account balances and that transfers do not inflate income/spending.
