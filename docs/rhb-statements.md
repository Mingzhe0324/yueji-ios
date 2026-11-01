# RHB statement reconciliation

Open Accounts → an RHB account → Reconcile statement. Choose the original PDF,
check the account suffix and period, then confirm the destination account and
choose Add clear entries; review the rest.

## Supported documents

This first version supports the RHB Islamic savings text PDF layout with six
columns: date, description, serial, debit, credit and running balance. It reads
the printed statement period (including quarterly statements), not the filename.
Scans, encrypted files, other bank layouts, multiple accounts, incomplete totals
and inconsistent balances are rejected without writing any ledger records.
Limits: 10 MB, 20 pages, 500 transactions, a period no longer than 366 days.

Parsing runs locally using PDFKit. Every row's running balance, opening/closing
balance, debit/credit total and transaction count must agree. YTD profit summaries
are excluded. The full PDF, account number, holder and address are not saved in
the ledger. The account number contributes only to a hashed transaction identity;
the last four digits and transaction descriptions are retained.

## Automatic entries and review

- Explicit debit-card purchases and named service/bank charges become expenses.
- Explicit profit/interest credits become Bank interest income, without automatic
  budget allocation.
- Transfers, top-ups, refunds and unclear receipts remain pending and do not affect
  balances until reviewed. An LLM never decides whether to debit or credit money.
- Exact imported transaction IDs are skipped on repeat or overlapping imports,
  including when the person chooses a different destination account.
- A same-amount entry within three days, including unassigned entries, is a
  possible duplicate and remains pending. Repeated same-day amounts inside the
  PDF also require review. This deliberately favors review over double counting.
- Rows before the account opening timestamp are skipped. PDF dates have no time;
  a midday opening timestamp therefore covers that entire posting day's rows.
- The app shows the ledger balance at the statement closing date and its difference
  from the statement. It never overwrites the opening/current balance to hide a
  discrepancy. Opening amounts and dates still need to be correct.

Gemini category suggestions are optional and off by default in this screen.
Enabling them sends only transaction descriptions and the allowed categories to
existing `assistant-gemini` classify mode. Long numeric identifiers are redacted.
Descriptions may still contain merchant or counterparty names. At most 100 unique
eligible descriptions are requested, stopping on the first failure. The existing
per-user daily assistant allowance applies. Unclassified expenses use Other and
remain editable; imports work without AI. No new Supabase function or SQL is needed.

## Undo and validation

Recent batches appear on the import screen, with links to their pending entries.
Undo removes only records created by that batch and their exact-import markers.
It refuses an edited, partly deleted, confirmed, settled or budget/transfer-linked
batch instead of partially undoing it. Existing records are never removed.

Regression tests in `IncomeBudgetTests` cover local PDF column parsing with a
synthetic PDF, invalid balances, duplicate imports, possible matches, interest,
pending transfers/receipts, opening timestamps, persisted undo and edited batches.
The private sample PDF and local rendered inspection images are not repository
fixtures. Windows syntax/project checks do not replace Xcode compilation and the
native PDFKit/unit tests in the manually triggered iOS GitHub Actions workflow.
