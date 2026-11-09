# Parking assistant

Entry: Accounts → top-left tools menu → Parking assistant.

The home screen shows the active place, plate, bay, elapsed hours/minutes, confirmed expiry and paid amount. Completed sessions have searchable place/plate/bay history and fixed durations. Record-only starts open details after location completes. Ending requires confirmation; fees can be entered after ending and reviewed in the ledger editor. Renewal amounts are cumulative, not an additional charge.

Plates are normalized and remembered locally per account after saving a session. The last used plate is prefilled and previous plates are selectable. Deleting a parking history record does not erase the remembered plates.

Vehicle profiles accept a user-entered brand, model, optional year, body type and colour. They are saved locally per account and matched by plate ignoring case and whitespace. Each new parking session keeps a snapshot of its vehicle details. Existing sessions without vehicle details remain readable. The visual is a body-type/colour illustration, not an exact make/model image.

Starting saves a local parking session before requesting location. The user can skip location or continue when permission/location fails. “Start and open TNG” then opens the official HTTPS link `https://visit.tngdigital.com.my/StreetParking`. The public redirect was checked; its destination inside the installed iPhone app still needs device verification. Opening the link is never treated as proof of payment.

Records contain start/end times, optional plate, car park, bay, GPS place and a resized photo. They are stored in an account-scoped, protected local file, outside ledger cloud sync. GPS does not determine a floor or bay. Maps can navigate to the saved coordinate.

Paid-until time and optional amount are explicitly confirmed by the user. Receipt screenshots use on-device OCR; amount, labeled location and full end-date/time candidates require selection and confirmation. No TNG credentials, payment API or order synchronization are used. Reminder permission is requested when confirming payment. A reminder already in the past is not scheduled. Ending/deleting cancels the session notification. Switching ledger accounts clears pending notifications; returning to an account requires confirming its reminder again.

“Review and record expense” opens the existing ledger editor with duplicate review and payment-account selection. The actual save also validates matching records. Deleting a parking record leaves its ledger expense intact. Renewed fees are not automatically added to a previously saved ledger expense.

## Validation

Windows checks: Swift syntax parsing, project references/resources, localization extraction, and whitespace validation. XCTest cases cover receipt ambiguity, reminder deadlines/end state and duplicate-review enforcement. XCTest execution and native compilation require Xcode.

Device acceptance checks:

- Allow/deny location and skip a slow request; confirm the session survives reopening.
- Try TNG installed/uninstalled; confirm the actual parking destination and return flow.
- Confirm payment with/without notification permission, then end/delete before its reminder.
- Import a photo and a receipt; confirm no payment is marked until explicitly confirmed.
- Save a parking expense with an existing same-day/same-amount payment; review duplicates, cancel/reopen and save once.
- Switch accounts; verify records remain isolated and old reminders are cleared.
