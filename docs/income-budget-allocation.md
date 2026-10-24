# Income to budget allocation

## What counts as income

YueJi only knows what is recorded in it. It can't read other apps' notifications, and not
every incoming payment reaches it.

| Source | How it reaches YueJi | When it can fund a budget |
|---|---|---|
| Manual income | **Record income** on the Overview budget card or in the Ledger's **⋯** menu (`IncomeEditor`, stored as `IncomeEntry`). The person picks Salary, Freelance, Part-time work, Bonus or Other income. | Right after it's saved. |
| Bank / TNG | The existing Shortcuts automation passes a notification to `receiveTNG`. Incoming money is always saved as **pending** for review. | Only after the person confirms its purpose as **Income** (`resolveTNGIncoming` / `resolveNotice`, with an income type). |

These never fund a budget: pending or unclear notices, friend repayments, transfers from
the person's own accounts and top-ups, refunds, settlements, ignored notices, and possible
duplicates still waiting for review (`TNGNotice.isConfirmedIncome`, `Ledger.incomeSource`).
The review screen no longer pre-selects **Income** for incoming money. The person chooses
the purpose.

## The prompt

When income is saved, or a notice is confirmed as income, the same ledger write calls
`settleNewIncome`, and the app shows one compact banner (`IncomeBudgetPromptCard`, banner
kind `.income`) in place of the plain "Saved" banner:

> Income of RM 300.00 recorded. Add it to this month's budget (October 2026)?
> **Add all** · **Choose amount** · **Not now**

- **Add all** puts everything not yet allocated into the current month (`addAllIncome`).
- **Choose amount** opens `IncomeAllocationSheet`. It has the destination month (this month
  by default, plus the income's own month and next month), the amount (up to what's left),
  and a before/after breakdown of the budget.
- **Not now**, a swipe, or 12 seconds without a response (30 with VoiceOver) dismisses it.
  Nothing changes.
- For older income the prompt and sheet say which month it goes to, e.g. "Add it to the
  October 2026 budget? It's dated 31 Aug 2026."

Bank/TNG income captured in the background keeps its existing single notification. Its text
now adds "If it's income, confirm it to add it to this month's budget". Its **Review
purpose** action opens the record, where confirming shows the prompt. No new notification
is created.

Allocation is also available later from the income's details: `IncomeDetailView` for
manual income, and the **Budget** section of `TNGIncomingView` for confirmed bank income.
There each month's amount can be added to, reduced (**Change**) or removed (**Remove**)
without touching the income.

## The calculation

`Ledger.monthlyBudget(month)` = base budget (`budgets[month]`) + income allocations
(`incomeAllocated(toMonth:)`).
Remaining = that total − eligible spending (`dailyBudgetSpending`, unchanged: personal net
spending, travel books excluded).

- The Overview gauge uses the total. When income was added, it shows the breakdown: base,
  + income added, − eligible spending, = remaining (`MonthlyBudgetBreakdown`).
- **Edit budget** changes the base only. The alert says income added this month stays on
  top of it.
- The budget alert (`BudgetAlertCandidate`) uses the total.
- YueJi has no category budgets, so there's nothing to keep in step there. Travel books keep
  their own budgets and never receive income.

## Records

`BudgetAllocation` has an id, a source (`income:<id>` or `notice:<id>`), a month
(`yyyy-MM`), an amount in ringgit, a timestamp, and whether it was added automatically.
It never creates a transaction or changes the income's amount. `Ledger.validated()`
(`validateIncomeBudget`) refuses a write if any of these hold:

- an allocation's income is missing, or is no longer income
- two allocations share the same income and month
- an income's allocations add up to more than the income
- a month key is malformed, or an amount isn't positive

## Duplicates

| Cause | Protection |
|---|---|
| Repeated taps / stale screens | Every change passes the amount the person saw (`setIncomeAllocation(expected:)`), and keyed operations reject a second write in flight. "Add all" adds only what's left. Saving the same income draft twice is refused (`addIncome`). |
| Repeated imports | Unchanged ingestion de-duplication (event keys, bank references, `possibleDuplicate` with an explicit "separate receipt" check). A bank reference can't be confirmed as income twice (`requireUnusedPaymentReference`). |
| Cross-source (manual + bank) | The first allocation of an income with the same ringgit amount within 3 days of another income already in a budget needs "Checked: this is separate income" (`likelyDuplicateIncome`). Automatic allocation skips it, and the prompt says "Review" instead of "Add all". |
| Backup restore / merged files | A restore replaces the ledger, so allocations aren't added to existing ones. When a file is decoded, `reconcilingBudgetAllocations` drops allocations whose income is gone. For the same income and month it keeps the larger allocation, never the sum. It trims totals beyond the income, latest month first. |

## Edits, deletion and reclassification

- Lowering a manual income below what it added to budgets trims allocations, latest month
  first (`allocationAdjustments`). The editor lists the change and asks before saving. The
  save is refused if budgets changed meanwhile.
- Deleting income, manual (`deleteIncome`) or bank (`deleteLedgerRecord`), removes its
  allocations. The confirmation lists them, and **Undo** restores both once.
- **Undo confirmation / reclassify** on bank income removes its allocations and clears its
  income type. The dialog lists the budget change first.
- Changing an income's date doesn't move allocations: each stays in the month it was added
  to.

## Automatic allocation (optional)

Settings → Budget & daily reminders → **Income and budget**. It is off by default. The
share runs from 5% to 100% in 5% steps, defaulting to 50%. Preferences are stored in
`UserDefaults` (`IncomeBudgetSettings`). When it's on, each newly saved or confirmed income
adds `floor(amount × share)` to the current month once (`autoAllocateIncome`). It follows
the same eligibility and duplicate rules, and shows one confirmation with **Change**
instead of the question. Changing an automatic allocation makes it the person's own.

## Currency

Manual income can be in another currency only with an explicit rate (`ForeignAmount`). The
income's `cents` is the converted ringgit amount, and that is the only amount a budget can
receive. Bank/TNG incoming amounts are ringgit.

## Storage

Incomes and allocations live in the ledger file (`incomes`, `budgetAllocations`, decoded
with `decodeIfPresent`, so older backups load with none). JSON backup/restore, and saving
that backup to iCloud Drive through Files, carry them unchanged. The restore preview
shows the manual income count and the total allocated. YueJi has no account system or cloud
sync, so isolation is the app's own sandbox, as for all other ledger data. Ledger and backup
version stay at 6.

## Verification

On Windows: Swift syntax parsing (tree-sitter) of every app and test file, and
`scripts/check_project.py` (build membership of the two new app files and the new test file,
resources, scheme) pass.

Not yet verified (needs Xcode/CI and an iPhone):

- native compilation
- the 16 new XCTest cases in `YueJiTests/IncomeBudgetTests.swift`, which cover manual
  income, captured bank income, uncertain/repayment/transfer/refund notices, partial
  allocations, duplicates, edits, deletion with undo, reclassification, month boundaries,
  backup round trip and repair, automatic allocation, currency, budget alerts, the ledger
  timeline, and prompt state
- the UI itself

Device checklist:

1. Record income → prompt → **Add all**, **Choose amount** (change month and amount),
   **Not now**, swipe, timeout.
2. Bank income notification → **Review purpose** → confirm as Income → prompt.
3. Light/dark, Large Text (the actions stack), VoiceOver (announcement, actions, escape),
   Reduce Motion.
4. Edit/delete/reclassify an allocated income and read the explanation; Undo.
5. Turn on automatic allocation and confirm the single confirmation and **Change**.
