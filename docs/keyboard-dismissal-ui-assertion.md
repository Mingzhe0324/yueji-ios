# Keyboard dismissal assertion in Azure run 6

The supplied build-test (6).log shows successful native compilation, simulator startup and all 265 unit tests passing, including the new ExpenseChargeTests. Two of four UI cases pass. The other two fail at TransactionFormTests.swift:385, immediately after entering payment35.00 and tapping the keyboard toolbar's Done. They do not reach their Add Item operations.

Both captured failure hierarchies retain the New entry sheet and transaction.amount value35.00, with neither a keyboard nor a Done toolbar control present. The helper previously evaluated the KVC predicate hittable == false against a firstMatch query whose button had already been removed. A missing query can fail resolution rather than supply a false hittable value, yielding a timeout despite successful dismissal.

The helper now uses an explicit predicate closure: the software keyboard must be absent, and the original Done query must either be absent or non-hittable. Existence is checked before isHittable. The tap, five-second dismissal deadline, draft-value assertions, native UI flow and all four required tests are retained. No production focus behavior or animation is changed based on this false failure. Native rerun remains necessary to validate the revised assertion on hosted iOS.
