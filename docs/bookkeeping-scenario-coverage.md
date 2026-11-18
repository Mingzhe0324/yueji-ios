# Bookkeeping scenario coverage

The acceptance rule is conservation of money and independent obligations: an operation changes only the applicable account, spending projection and debt/claim. Corrections must not silently create a second payment. This document describes implemented/tested scenarios, not a promise to understand every possible bank format or financial arrangement.

## Scenario matrix

| Situation | Expected behavior | Regression coverage |
| --- | --- | --- |
| I pay for myself / friends | Debit my payment account once; spending uses my share; friends owe their shares | LedgerTests, ItemOwnershipAndQuantityTests, TransactionItemsTests |
| Friend pays for me | No debit from my account; my cost and debt to the friend remain separate | Friend-paid ownership and item tests |
| We both owe money | Offset both debts; receive/pay only the net amount; zero net requires no bank transfer | EverydayFlowTests, LedgerTests |
| Repayment is partial | Apply only the selected amount/debts; leave the rest outstanding | PartialRepaymentRegressionTests, TNGIncomingTests |
| Small repayment excess | Explicitly approved rounding stays outside the debt allocation | Repayment/net-settlement rounding tests |
| I lend money | Record principal and borrower debt; do not treat it as consumption | Loan conversion and rejection tests |
| Company reimbursement, including friend-paid expenses | Claim my share; company receipt and friend repayment remain independent | ReimbursementTests, EverydayFlowTests |
| Missing incoming notification | Manually record receipt with actual account; a later matching notice is reviewed, not credited twice | IncomeBudgetTests manual-receipt and duplicate tests |
| Own-account transfer with only one notification | One transfer debits source and credits destination; later opposite notification attaches to it | IncomeBudgetTests own-transfer tests |
| Refund returns to a different account | Credit the saved refund destination, not the original payment account | Refund receiving-account matrix added in this change |
| Friend paid, refund goes to me | Credit my refund account; retain the amount still owed to the friend | Refund receiving-account matrix added in this change |
| Friend paid, refund goes to friend | No credit to my account; reduce the applicable debt | Refund-to-friend regression |
| Refund account is missing | Keep linked notification in account review; assignment resolves the same refund | Missing-refund-account regression |
| Advertisements / holds / failed payments | Do not silently post them as completed spending | TNGAllowlistTests, bank and Grab notification tests |
| Statement import overlaps existing records | Hold ambiguous rows; avoid duplicate cash movement; preserve original import undo | IncomeBudgetTests statement tests |
| Stale screens, repeat save, backup/reload, undo | Reject invalid changes without partial mutation; preserve links and amounts | Shared model/storage regressions |

## Combined cases added

1. Bank-paid dinner, James-paid utilities, one-sided TNG top-up, RM9.42 net repayment, company reimbursement with RM0.60 rounding, late duplicate bank notification, backup reload, then independent undo of reimbursement/settlement/transfer. Final account totals must reconcile to actual personal cost and rounding.
2. Fourteen combinations of receivable/payable debt, including one-cent balances, incoming, outgoing and exact offset; partial company claims go to another account. Undo debt settlement before the reimbursement and verify both balances and claim state.
3. Manual/notification refunds crossed with self-paid/friend-paid purchases. Check destination account, personal spending, friend liability, statement matching/cutoffs, backup and undo. Preserve legacy refunds with no explicit destination under the original-payer rule; do not guess historical receiving accounts.

## Native verification

Full build `e7b2c94` passed GitHub run [44219251453](https://github.com/Mingzhe0324/yueji-ios/actions/runs/44219251453), including native tests and IPA packaging. It predates the receiving-account refund fix and combined scenarios above.

Native model verification of `e6ca041` passed GitHub run [44293941760](https://github.com/Mingzhe0324/yueji-ios/actions/runs/44293941760): **510 tests, zero failures**. This includes the receiving-account refund changes and combined scenarios above. An earlier run caught an explicit non-user refund being credited to the original account; the recipient exclusion is restored and its existing regression now passes.

The workflow optionally runs all `YueJiTests` with `unit_tests_only=true` for native model verification without the longer UI suite or IPA. Normal dispatch still runs all tests and produces the unsigned IPA only after success. The model-only run does not replace full UI/device build verification; Windows project/syntax checks are not a substitute for either native run.

Physical-device usability, accessibility, performance, notification automation delivery, unsupported statements and external service outages remain separate acceptance checks. Unknown or ambiguous inputs must stay reviewable instead of guessing a financial outcome.
