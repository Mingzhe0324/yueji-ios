# Category, filtering and scroll continuity

This follow-up implements the five requested visible interactions. Monetary calculations and saved data structures are unchanged.

## Category focus

The existing “Where it went” bars are now selectable. A selected category receives a checkmark and tinted background; other bars fade while their text stays at normal contrast. The summary amount changes to that category's actual personal spending and displays its percentage of the existing personal total. Tap the selected category again to clear focus. “View category entries” opens the existing filtered detail page. Selection clears on month changes or removal of the selected category from the snapshot.

## Inline filters

The ledger filter button expands category/source menus immediately beneath it. Selecting either collapses the controls into removable condition chips. Amount ranges and the original advanced filter form remain available through “Amount & more filters”; its validation and cancel semantics are unchanged. Existing source/provider distinctions are retained, and entry-source chips are explicitly labelled. Applied filters remain visible when collapsed. Large accessibility text stacks the action buttons vertically; chips scroll horizontally.

Completed filter/month results animate the list diff. Cancellation and query-identity guards still reject stale worker results. Search typing does not animate every update; crossing between an empty and nonempty result does animate. Empty results are retained during loading until the replacement snapshot arrives, preventing an intermediate blank flash. Overview likewise animates the first saved entry replacing its empty state.

## Detail scroll title

The detail hero scales/fades with scroll using `visualEffect`, without changing its layout height. Only a Boolean geometry threshold updates the parent view when the header leaves the top; the compact navigation title then displays the real merchant/description and the same purchase-display amount/direction as the hero. Scrolling back reverses the effect. There is no per-frame financial projection or animated row-height feedback loop. Reduce Motion keeps the header untransformed and the title change immediate. Compact navigation text is capped at XXX Large; its accessibility label retains both name and amount.

## Context preview

Overview and Ledger expense rows now share a rounded native context-menu preview with Edit/Delete actions. The system owns lift, background dimming, menu dismissal and return. No additional long-press recognizer or delayed action is installed. Delete still opens the existing confirmation; editing uses the existing draft-preserving editor. Native navigation zoom remains separately scoped to ordinary row taps.

## Validation

Locally available on Windows: project/resource validation, Swift syntax parsing and diff review. Native compilation and interaction verification require the macOS pipeline and physical iPhone; these checks do not establish an exact frame rate.

Device checks:

- Focus and clear categories, change months rapidly, open category entries, and remove the selected category's last expense. The headline must agree with the selected bar and reset when unavailable.
- Expand filters, choose a category/source, remove each chip, and apply/cancel invalid/valid amount ranges. Existing search, bank notices and settlement filtering must retain their semantics.
- Add the first record in an empty month and delete the last. Test zero-result filters, then clear them. Old snapshots must not overwrite a newer selection.
- Scroll a long expense detail down/up, including large text, then open item editing and return. Amount/name must remain readable and draft-dismiss confirmation must still work.
- Long-press manual and automatic expense rows in Overview and Ledger. Dismiss the menu without choosing an action; then edit, cancel a deletion and confirm a deletion. A long press must not also open the detail.
- Repeat with Reduce Motion, VoiceOver and light/dark appearance. Existing four transaction UI regressions and financial tests remain enabled; no CI timeout was increased or test skipped.

References:
- https://developer.apple.com/documentation/swiftui/view/visualeffect(_:)
- https://developer.apple.com/documentation/swiftui/view/ongeometrychange(for:of:action:)
- https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:preview:)
