# Ledger layout and banner dismissal

Transaction rows use the same presentation for manual and automatic purchases: merchant first, up to two saved item names beneath it, then category/date. A separate localized `+N more` label stays visible when names need truncation; narrow layouts can place it below the preview. Transactions without item names keep their merchant and never infer purchases from categories or notification text. Financial amounts and payer/refund/share indicators remain visible. The redundant source/Expense heading is removed from rows; source information remains in details.

Items are always visible in saved details and all shared transaction/item editors. Details show name, amount and category per item, with net share where applicable. Add/Edit Items remains a direct action. The old disclosure state and opening parameter are removed. Stable ID bindings and unanimated structural edits remain in place to preserve unsaved fields and native picker navigation. Repeated totals and explanatory paragraphs are removed from details; editors retain allocation totals and actionable validation messages.

All in-app banner types use a four-second idle timeout (twelve seconds with VoiceOver). Interaction cancels expiry; releasing starts a fresh full interval. Higher-priority notices pause the notices beneath them, and scene inactivity pauses timers. New bank/TNG summaries now expire too. Dismissal changes presentation only. Existing token checks prevent an old completion from clearing a replacement banner.

The native pan locks to horizontal or upward movement and tracks the finger without per-frame model updates. Downward or ambiguous diagonal movement does not dismiss. A separate non-cancelling contact recognizer holds expiry while a finger remains down, even when the pan rejects its direction. Dragging latches off button activation until a new contact. Successful dismissal exits in the chosen direction, consumes the release, and disables the host's hit area at completion before removing the banner. Reduce Motion uses fades; cancelled/short/reversed drags return to rest.

Validation performed on Windows: project/resource checks, all Swift syntax parsing and whitespace checks. Added XCTest coverage for ordered item previews/counts and unchanged accounting, plus upward native-controller dismissal, interaction notifications, activation blocking and hit-area release. Updated the cold-launch UI tests to tap the already-visible Add Item button. Native compilation, XCTest execution and visual/gesture verification require a fresh Xcode/Azure run.

Device checks:

1. Compare manual and automatic purchases with zero, one, two and many items; include long names, small screens, large Dynamic Type, dark mode and all three languages. Check the amount and `+N more` remain readable.
2. Open details and edit items without expanding anything. Add/remove items and navigate categories; cancel and confirm that merchant, amount, date, payer and splits are preserved. Check reports before and after item edits.
3. Trigger saved, foreground, imported-record and deletion notices. Let each expire, hold longer than four seconds, then release. Check left/right/up, short drags, reversals, downward drags, close/Undo targets and background/foreground transitions.
4. During dismissal, deliver a replacement notice. Verify no stale dismissal removes it, no swipe opens a destination, and the dismissed area immediately accepts new touches. Check Reduce Motion and VoiceOver timing.
