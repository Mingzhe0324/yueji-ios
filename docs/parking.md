# Parking assistant

Entry: Accounts → top-left tools menu → Parking assistant.

The redesigned home uses a green accent, an interactive location map and a large vehicle photo card. Parking starts from a fixed bottom action; vehicle selection and optional location edits sit in a compact card, with history collapsed. Opening the idle screen requests location and reverse-geocodes a nearby address. A location obtained within 60 seconds can be reused when starting; otherwise starting requests a fresh fix. The detected address fills the session name without replacing a user-edited name. Location failure or denial does not block starting. An address is not a verified car park name, floor, bay, live availability or rate.

Button presses, vehicle/session transitions and timer changes use short animations respecting Reduce Motion. Native device visual acceptance remains required.

`YueJi/Assets.xcassets/ParkingCarHero.imageset/car.png` was generated with the built-in imagegen tool as a generic default illustration. Prompt: “Create a photorealistic automotive product image for a minimal mobile parking app card. One unbranded pearl white modern compact hatchback, front three-quarter view facing left, entire vehicle visible, elegant realistic proportions, black tires and subtle silver wheels. Clean very pale cool grey studio background, soft ground shadow, diffused daylight. Wide horizontal composition with generous margin, car fills 80 percent width. No text, logos, badges, license plate characters, UI or border. This is a generic illustrative car, not a specific make or model.” Personal vehicle photos take precedence. The default image does not claim to match the entered make/model/colour.

The home screen shows the active place, plate, bay, elapsed hours/minutes, confirmed expiry and paid amount. Completed sessions have searchable place/plate/bay history and fixed durations. Record-only starts open details after location completes. Ending requires confirmation; fees can be entered after ending and reviewed in the ledger editor. Renewal amounts are cumulative, not an additional charge.

Plates are normalized and remembered locally per account after saving a session. The last used plate is prefilled and previous plates are selectable. Deleting a parking history record does not erase the remembered plates.

Vehicle profiles accept a user-entered brand, model, optional year, body type and colour. They are saved locally per account and matched by plate ignoring case and whitespace. Each new parking session keeps a snapshot of its vehicle details. Existing sessions without vehicle details remain readable. The visual is a body-type/colour illustration, not an exact make/model image.

Starting saves a local parking session before requesting location. The user can skip location or continue when permission/location fails. “Start and open TNG” then opens the official HTTPS link `https://visit.tngdigital.com.my/StreetParking`. The public redirect was checked; its destination inside the installed iPhone app still needs device verification. Opening the link is never treated as proof of payment.

Records contain start/end times, optional plate, car park, bay, GPS place and a resized photo. They are stored in an account-scoped, protected local file, outside ledger cloud sync. GPS does not determine a floor or bay. Maps can navigate to the saved coordinate.

Paid-until time and optional amount are explicitly confirmed by the user. Receipt screenshots use on-device OCR; amount, labeled location and full end-date/time candidates require selection and confirmation. No TNG credentials, payment API or order synchronization are used. Reminder permission is requested when confirming payment. A reminder already in the past is not scheduled. Ending/deleting cancels the session notification. Switching ledger accounts clears pending notifications; returning to an account requires confirming its reminder again.

“Review and record expense” opens the existing ledger editor with duplicate review and payment-account selection. The actual save also validates matching records. Deleting a parking record leaves its ledger expense intact. Existing linked entries can be opened for editing. A renewal draft uses the confirmed cumulative total less the amounts of all linked expenses, and requires duplicate review. Missing linked entries or a nonpositive difference prevent a new renewal draft. No expense changes occur without saving in the ledger editor.

Opening TNG marks the session as awaiting review. On returning to the foreground (or reopening the parking screen), the user can confirm they paid or dismiss as not paid. This prompt never proves payment or writes a ledger expense. Floor and zone are separate optional fields alongside legacy bay notes. Vehicle profiles can store a resized personal photo; no exact-model image service is connected. The active home screen prioritizes the timer, remaining confirmed minutes, plate and spot details.

## Validation

Windows checks: Swift syntax parsing, project references/resources, localization extraction, and whitespace validation. XCTest cases cover receipt ambiguity, reminder deadlines/end state and duplicate-review enforcement. XCTest execution and native compilation require Xcode.

Device acceptance checks:

- Allow/deny location and skip a slow request; confirm the session survives reopening.
- Try TNG installed/uninstalled; confirm the actual parking destination and return flow.
- Confirm payment with/without notification permission, then end/delete before its reminder.
- Import a photo and a receipt; confirm no payment is marked until explicitly confirmed.
- Save a parking expense with an existing same-day/same-amount payment; review duplicates, cancel/reopen and save once.
- Switch accounts; verify records remain isolated and old reminders are cleared.
