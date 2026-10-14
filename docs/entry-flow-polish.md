# Entry flow visual polish

The amount section precedes the payer section so the primary transaction value is visible earlier. Merchant and name/description have persistent, secondary optional labels; filled fields retain their meaning after placeholders disappear. The description starts at one line and grows to four visible lines using native multiline TextField layout.

Each item has its own native Form section, headed by its current item number. Quantity, unit price, total, category, ownership and removal stay together in that section. Add item and totals occupy a separate summary section that remains mounted as items change. Category and ownership still own separate navigation rows, draft IDs and scroll anchors stay stable, and insert/remove keep the existing non-animated transaction to avoid reintroducing picker/focus issues. This shared layout also applies to automatic transaction item editing.

Transaction and item editors share a stable Save label: the text retains its size while a progress indicator overlays it. Item saving no longer inserts an unrelated full-page spinner. Disabled-save state, persistence, error handling, native sheet/keyboard transitions and unsaved-change confirmation remain intact.

Local checks: project integrity, Swift syntax and diff formatting. Native first-tap, focus, category/ownership navigation and clean/dirty dismissal tests remain required on CI. Light/dark, large-text and real-device motion review are pending. No additional CI stage, timeout or test loop was added for these visual adjustments.
