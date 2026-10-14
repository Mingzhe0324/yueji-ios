# Separate optional entry details

Merchant, entry name/description and purchased items are independent. Manual entry and editing allow all three to be empty; amount, date and category retain their existing validation. Empty merchant names are stored as empty, never replaced with invented merchant data or used to create a merchant-category rule.

`Expense.entryDescription` is an optional Codable field (maximum 2,000 characters). Existing backups decode it as nil and retain merchant, note, receipt text, items and amounts. Editing loads it into the draft and includes it in the unsaved-change snapshot. Apple Pay's supplied description populates it for new payments; notification bodies are not automatically repurposed as descriptions. Existing automatic transactions can use the same editor.

The row heading uses merchant, otherwise description, otherwise a localized Untitled entry label. With a merchant present the description appears separately, followed by the item preview when available. Details label merchant and description explicitly. Description participates in ledger search and is appended as a separate CSV column; legacy note and receipt text remain separate.

Regression coverage: optional-only transactions and backup round trips, legacy backups without the new key, unchanged personal amounts, description search/export and length validation. Project and Swift syntax checks run locally; XCTest and native editing/dismissal validation require macOS CI.
