# Everyday automation

The settings entry “Automatic recording” now groups payment-account links,
notification frequency, merchant rules, income allocation, backup and review status.
The app does not claim that a Shortcuts automation is installed merely because a
setup screen was visited.

## Implemented behavior

| Area | Behavior |
| --- | --- |
| Notifications | Existing per-entry delivery remains the default. Daily mode replaces one pending summary after successful expense recording. Attention-only mode suppresses successful expense notifications. Unresolved results and failures remain immediate. Disabling notifications removes a pending summary. |
| Entry editing | Expense notifications already open the editor directly. The detail screen now exposes common editing beside the amount. Merchant category memory is visible beside the category instead of inside currency options. |
| Review queue | Start a sequence of unresolved notices. Completing a notice opens the next after dismissal. Cancelling or leaving a notice unresolved stops the sequence. |
| Category memory | Existing explicit merchant rules and stale-write protection are retained. The user can inspect rules from the automation screen. |
| Income | Existing opt-in percentage allocation is now available directly from the automation screen. Transfers, top-ups, refunds and repayments are not automatically treated as income. |
| Recurring payments | Existing exact merchant/amount matching advances a matching schedule once. Ambiguous matches are not auto-confirmed. Existing amount-change alerts remain available. |
| Receipts | Matching payments use the same day and amount, excluding foreign, refunded, settled, friend-paid or already-split entries. One matching payment gets an attachment shortcut. Adding another matching payment requires an explicit distinct-payment choice, reset after editing the receipt. Existing OCR prefills and amount validation are retained. |
| Parking | Existing remembered plates, automatic location, receipt OCR and return-from-payment review are retained. Previous location for the selected plate can be reused explicitly; the bay is cleared. Opening the payment app never implies payment success. |
| Travel | New entries offer books whose inclusive date range contains the expense date. Selection is explicit and does not change currency or overwrite an existing trip. |
| Friends | A new split can reuse the names from the last split when its name fields are empty. Historical amounts, debts and repayments are not copied. |
| Backup/startup | Existing local-first launch and deferred maintenance remain. Backup runs before network rate refresh. A failed backup gets one retry; changing the folder prevents retrying the old folder. Rate refresh stops starting new requests after cancellation. |
| Research | Successful non-imported reports are saved to existing account-scoped local history. Reopening shows the prior report with its date and an explicit stale-source label. No automatic paid request, live-price claim or trade is introduced. |

## Verification

### Advertisement filtering and functional motion

- Promotional reward eligibility, voucher receipts, discounts and delivery/ride
  offers are filtered locally in English, Chinese and Malay before parsing or AI
  confirmation. Full-width text and common invisible characters are normalized
  for detection; original notification text is retained in the recovery archive.
- An unconditional completed money-movement sentence protects genuine receipts
  with advertising footers. Conditional cashback promises and voucher amounts do
  not qualify as cash receipts. Foreign-currency receipts remain eligible for
  review; this filter does not grant automatic posting permission.
- Ads do not create expenses, review items, account movements or user alerts.
  The existing bounded filtered-notification archive remains available to restore
  a misclassified notice for review. No classifier can guarantee every template.
- Added regression cases cover campaigns, reward receipts, conditional wording,
  real payment/refund/cashback receipts and notices with benign detail links.
- Save controls cross-fade without changing size; review rows fade and shift six
  points as their identities change; monetary values interpolate in place,
  including friend balances and settlement selection. Google import previews
  fade in and map movement follows the animation preference. Saved checkmarks
  draw without the previous delay. Reduce Motion and the app animation setting
  disable these effects; persistence never waits for an animation.

### Free location capture and parking

- Automatic capture uses Core Location, with no Google API key or billing. A fix
  must be at most 30 seconds old and have reported accuracy of 50 metres or better.
  This is the phone's estimated position, not proof of a merchant or parking bay.
- Existing location permission is required. A fresh request is attempted only
  while the app is active with When In Use permission, or with existing Always
  permission. No background tracking mode or Always permission prompt is added.
  Enrichment waits at most four seconds; failed location never blocks bookkeeping.
- Late notifications cannot attach a current fix to a transaction more than five
  minutes away. Delivery retries retain the original saved location.
- Parking entries and renewals copy the session's start location and use
  `Parking Fee · <location>` when a usable name is available, otherwise `Parking Fee`.
  The end-of-parking phone position is not substituted for the parked vehicle.
- Explicit place searches no longer use the old map pin as a region bias. They
  include addresses and places, display up to 12 results, and offer a keyless
  Google Maps link for the typed query. The editor's **Import Google place** action
  accepts a Google Maps share link or explicit latitude/longitude. It previews the
  result before selection; the enclosing editor still requires Done and saving
  the transaction. Cancelling either editor leaves the ledger unchanged.
- Google short links are expanded with bounded, cookie-free HEAD requests,
  checking each redirect against supported Google Maps hosts. No Google API or
  page scraping is used. Explicit destination coordinates are imported; camera
  centres (`/@`, `ll`) and conflicting destination pins are never treated as a shop.
  An opaque link is retained without inventing coordinates and opens the selected
  Google destination later. Users can paste coordinates if they need a local pin.
- Google-selected places retain their link in backups and must not be replaced
  by the Apple merchant matcher. Existing records without this optional field
  remain compatible. No Google place ID is stored as an Apple place ID.
- Device checks still needed: precise location on/off, denied access, cold
  background automation, indoor GPS timeout, remote-city search, and parking
  renewal after leaving the car.

- Swift syntax parsing and project/resource validation run on Windows.
- Unit coverage adds notification policy and foreground-summary routing checks.
- Existing renewal, income-allocation, stale-write, duplicate and transaction UI
  tests remain required in the macOS CI workflow.
- Device acceptance: foreground/background/cold-launch notification navigation;
  summary delivery and opt-out; cancelling continuous review; a receipt matched
  to an existing payment; changing account while viewing saved research.
- Native compilation and simulator results must be read from CI; syntax checks
  alone are not a native build or device verification.
