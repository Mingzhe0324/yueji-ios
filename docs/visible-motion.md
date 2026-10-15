# Visible, interaction-led motion

Follow-up: [Category, filtering and scroll continuity](focused-ledger-motion.md) adds category selection, inline filters, empty-state transitions, a compact scrolling detail title and native context previews. It extends snapshot animation to completed filter and empty/nonempty changes.

This pass follows the request for visibly flowing transitions, rather than only small button effects.

- Overview and Ledger transaction rows opt into the system zoom navigation transition on iOS 18+. The source is the actual row, keyed by saved expense ID in that screen's namespace. The detail is still a normal NavigationStack destination. This applies equally to manually entered and automatically recorded expenses. iOS 17 and Reduce Motion keep standard navigation.
- New-entry, edit-entry and edit-items sheets retain native presentation, interactive dragging and the existing unsaved-draft delegate/confirmation. They deliberately do not opt into the transaction-card zoom. No overlay, competing drag recognizer, sheet offset or artificial close delay is added. These form transitions were already implemented.
- A completed month snapshot animates into Overview/Ledger in 0.42 seconds. The old snapshot stays readable while loading, and cancellation/query checks reject stale results during rapid month changes. First load, searching and same-month refreshes do not start whole-list animations. Numeric amount transitions and the 0.45-second spending meters remain independently scoped to their values.
- Item section insertion/removal uses a 0.34-second native Form layout animation when no field has focus. If a field is being edited, mutation is immediate; removing the focused field still clears focus before removal. Draft identities, binding lookup, item category/ownership navigation and validation are unchanged. There is no delayed mutation that could land after cancel/save.
- Notification insertion has a single owner: LedgerFeedbackHost. The banner moves down 32 points while fading in, with a 0.42-second lightly damped spring. Removal fades in 0.14 seconds; UIKit continues to own finger tracking, cancelled-drag spring-back and directional swipe exit, so those do not acquire a second translation. Existing expiry/pause policy, activation suppression and release of the hit area remain unchanged. Reduce Motion uses opacity only.

The old generic zoom helpers remain disabled: applying them globally would also affect editor sheets and unrelated tool routes. The new opt-in modifiers are limited to expense-card navigation.

## Validation

Windows project/resource checks and Swift syntax parsing are available locally; Xcode compilation, the existing four transaction UI regressions and banner interaction tests must still run on macOS. No CI tests are skipped or deadlines changed in this pass.

Physical-device acceptance:

1. Open an expense from both Overview and Ledger; return normally, then cancel an interactive back gesture. The source row must remain visible and tappable. Repeat after editing and deleting an expense.
2. Open New entry immediately after launch. Drag a clean sheet closed. Enter an amount/item, drag again, choose Keep editing and verify every draft value; repeat with Discard changes.
3. Change months rapidly, including an empty month. Only the last requested month's values should settle; amount, category bars and transactions must agree.
4. Add/remove multiple items with the keyboard hidden, then while editing an item. Check both category and ownership navigation, save, cancel and reopen.
5. Touch a banner during arrival; drag left/right/up, cancel a short drag, let another expire, and replace one with a higher-priority notice. Dismissal must not activate the banner or underlying controls; the page must accept touches afterward.
6. Repeat with Reduce Motion, dark appearance and large text. Assess hitches in a Release build on a physical phone; syntax validation is not evidence of frame rate or an exact OS visual match.

Native API reference: https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)
