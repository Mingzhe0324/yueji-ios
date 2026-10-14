# Ledger visual polish

Overview uses a content-sized Add entry capsule, centred above the native tab bar, with an eight-point vertical inset. Its label can wrap at large text sizes and retains a minimum 44-point target. The shared action surface remains transparent unless Reduce Transparency is enabled.

The shared transaction row places merchant and purchase amount on the first baseline. Item previews now have the full remaining row width below that heading; category and date use secondary caption text. Accessibility text sizes stack the heading and amount. Both Overview and Ledger use this row, regardless of transaction source. Existing item preview identifiers and amount accessibility labels remain intact.

Item quantity and line total use monospaced numeric transitions when the quantity changes. Reduce Motion disables these animations. Insertion/removal continues to use the existing non-animated Form transaction: changing that transaction previously interacted with picker navigation and focus. Items stay expanded, and draft bindings, focus ownership, money calculations and discard confirmation are unchanged.

Banner icons no longer have a second decorative background tile. Entrance uses a short, heavily damped spring; an incomplete swipe settles over 0.28 seconds. Reduce Motion retains a short fade and immediate snap-back. The existing four-second idle lifetime, interaction pause, swipe directions, tap suppression and touch-area cleanup remain unchanged. Sheet presentation and navigation continue to use native transitions.

Validation: local project integrity, whitespace and Swift syntax checks. Windows cannot compile SwiftUI or confirm rendered geometry, gesture behaviour or animation quality. Native UI tests must still pass, followed by light/dark, large-text, Reduce Motion and Reduce Transparency review. No additional UI tests or CI stages are introduced for this visual change.
