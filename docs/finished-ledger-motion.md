# Ledger motion follow-up

All five requested effects use the existing data and financial calculations:

- Month: after the latest monthly projection completes, Overview and Ledger summaries enter from the corresponding side by 12 points and fade from 75% opacity over 0.24 seconds. First load does not animate. Navigation and row identity are unchanged; rapid changes cancel pending motion. No loading spinner is added.
- Receipt: existing disclosure expands the original receipt text; the whole text block now enters together over 0.24 seconds, instead of staggered lines. Subtotal, charges and rounding stay in the original text and original order.
- Ownership/quantity: existing AnimatedMoney displays in ItemOwnershipPicker and ItemSplitSummary interpolate updated shares, retaining exact stored cents. No new accounting behavior is introduced.
- Delete/undo: completed projections animate removed rows even when the list remains nonempty. Existing undo insertion and brief restored-row highlight remain in place. Failed persistence cannot trigger a successful removal animation.
- Budget: existing SpendingMeter and budget card animate tint over 0.55 seconds: blue below 80%, orange through the limit, red above it. No blinking or looping.

Reduce Motion removes positional and numeric animations. Standard transaction-detail push/pop remains intact; no matched zoom transitions are reintroduced. Project/syntax checks are local only. Verify actual rendering and interruption on an iPhone, including rapid month changes, a long receipt, quantity/ownership changes, deletion with remaining rows, undo, and both budget thresholds.
