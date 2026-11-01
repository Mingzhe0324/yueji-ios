# Supported statement layouts

Reconciliation reads text PDFs locally. Gemini, when enabled, only suggests
expense categories. It does not decide transaction amounts, debit/credit
direction, opening balances or closing balances.

The sampled layouts now include:

| Provider | Accepted layout | Limits |
| --- | --- | --- |
| RHB | Savings Account-i, six columns | Existing multipage checks |
| AmBank | Account Statement & Tax Invoice, savings | Single page; printed debit/credit counts and totals required |
| Hong Leong | Savings Account Statement | Single page; printed counts/totals required; an omitted row balance is calculated and checked against subsequent printed balances |
| Maybank | Savings Account-i, signed transaction amount | Single page; month-end date, opening/closing and debit/credit totals required |
| Ryt Bank | Main Savings summary and Main Account transactions | Sampled three-page layout; only the main account, never the combined Pocket total |
| Wise | MYR statement, one incoming transaction | Sampled single-page layout only; opening is derived, prominently disclosed; all entries pending review |

Other layouts, scanned pages, password-locked PDFs and inconsistent totals fail
without creating entries. PDFs that use encryption but open without a password
are not rejected merely for having encryption enabled.

The selected account must match the provider and any configured account suffix.
Only the account hash and last four digits are retained from the header. Original
PDFs, holder addresses and complete account numbers are not committed to source.

Clear purchase/fee descriptions and interest can be added automatically after
validation. Transfers, unclear incoming money, potential existing entries and
Wise derived-opening entries remain pending without changing balances. Existing
deduplication and atomic batch undo apply across providers. Closing differences
never overwrite the account balance.

Validation: the five private samples were rendered and inspected locally; a
PDFium-based check verified the same column geometry, running balances and
available printed totals. This is not a substitute for PDFKit on iOS. Native
synthetic PDF tests and the cold-launch interest presentation UI test must run in
the macOS GitHub Actions workflow. Private sample PDFs are excluded from Git.

No new Supabase function, SQL migration or secret is required for these adapters.
