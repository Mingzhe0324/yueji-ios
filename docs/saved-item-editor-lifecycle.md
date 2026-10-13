# Saved-item editor dismissal

IMG_5196.MP4 shows Overview -> an existing TNG purchase -> Add items. Edit items appears around three seconds, then disappears back to the same detail. It opens and disappears again around six seconds. The recording shows unintended sheet dismissal, not app termination. It does not show the initiating touch coordinates or provide a crash/main-thread trace.

The previous sheet route and presenter lived in SavedTransactionItemsSection, a lazy List/Form child. Opening also changed the parent's presentation gate. Presentation now belongs to one screen-owned TransactionEditorRoute, outside the Items section, in both ExpenseDetailView and TNGNoticeView. The section only sends an edit action. The route captures the expense once and the editor initializes its draft once. Overview recent purchases and Ledger purchases both navigate through a screen-owned ID path, so a refreshed list row no longer owns the detail destination.

Transaction and item sheets prevent interactive swipe dismissal and retain explicit Save/Cancel controls. Saved item rows can open their own editor and scroll to the selected item. Item keyboard Done and Save clear the shared SwiftUI focus state. Atomic validation, stale-record rejection and original-record replacement remain unchanged.

Settings no longer links to Tags & Projects. ExpenseTagsView and TagSpendingView are removed along with the obsolete required-feature build guard. Stored tags and their serialization are retained; there is no migration or deletion of transaction data. Category views, item breakdowns and financial calculations are unchanged.

The two additional cold-launch UI regressions start with a saved purchase without items, relaunch, open it from Overview and exercise Add items, Cancel, reopen and Save. They then open it from Ledger, repeatedly edit a saved item, check invalid-save draft retention, navigate categories, attempt sheet drags, remove a new row, and verify return navigation and no duplicate purchase. They delete only their uniquely named fixture and check Settings has Categories but no Tags & Projects.

Local project/resource checks, all 13 Swift syntax checks, the required-feature guard, workflow YAML and diff checks pass. Native Xcode execution and physical-device confirmation remain pending. The recording confirms the dismissal symptom; it does not prove the lifecycle correction has resolved it. Repeat its exact sequence on the new build, including automatically recorded TNG purchases, and verify unsaved fields remain after keyboard/category interaction and sheet drags.
