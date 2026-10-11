# Items migration — 1.60.0, build 88

Items is the sole way to divide an expense across categories. The separate category-allocation editor, toggle, draft model, detail rows and obsolete Chinese/English/Malay explanatory strings have been removed. Single-category entries still have their category picker; Items stays optional for automatic entries until the user supplies a breakdown. Item sums must still equal the parent transaction amount.

Old `categoryAllocations` is retained only as a compatibility input for old files and backups. Successful ledger validation converts each allocation to one item with the same amount, category and order. Its category supplies the item name because the old feature stored no product names. Ordinary allocation IDs are retained; oversized legacy IDs become deterministic bounded item IDs. Existing named items are unchanged, including multiple items in one category. The parent category, expense ID, date, merchant, source, foreign amount/rate, notes, tags, original receipt, shares, repayments and refunds are preserved.

Settlement line snapshots, including inactive audits, and retained converted payments migrate with the live expenses. The signed applied amounts, settlement IDs, transfer, dates, bank/payment links and void status remain unchanged. Active settled expenses and snapshots are checked for consistency after conversion; undo retains the original expenses and one payment record. Invalid or ambiguous legacy data is rejected before it can overwrite valid records. Migration never combines simultaneous old allocations and named items or silently drops either representation.

Migration runs as part of the existing validated read/write path on the storage actor. Reads do not overwrite the original ledger file. Ordinary writes and JSON exports persist the canonical Items representation; backup preview/restore accepts versions 1–6 and keeps schema 6. The CSV category-allocation column remains as a compatible derived report column, calculated from Items rather than offering a second editing feature. The parent remains one expense: item rows do not create additional ledger records. Proportional shares/refunds retain the same capacity order, preserving category totals and cent rounding.

Seven native XCTest regressions in `ItemsOnlyMigrationTests` cover:

- Automatic-payment links, foreign amounts, metadata, refunds, partial repayments and category reports.
- Exact cent allocation at each personal-share size.
- The RM55 spending / RM5 transfer example, partial and zero-transfer offsets, bank linkage, locked refund edits and undo.
- Inactive settlement and converted-payment audits without additional spending.
- Backup versions 1–6, custom categories, repeated round-trips and unchanged existing named items.
- Reading an actual legacy file, subsequent save/backup and rejection of a corrupt restore without overwriting valid data.
- Stable conversion of oversized legacy allocation IDs.

Existing backup/search regressions now expect the equivalent Items representation after loading a legacy split. Local Swift parsing, project-resource checks and CI configuration checks are separate from native compilation and accounting-test execution. Xcode/XCTest cannot run on this Windows workstation; start a new CI run from this commit. On an iPhone, verify manual and automatic entry → Items → category selection → save → reports, an old-backup restore, and a migrated settled entry → notes-only edit → undo. Confirm the removed section does not appear in any supported language and the original spending totals remain unchanged.
