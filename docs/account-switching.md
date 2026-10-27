# Account switching

Sign out from Settings > your profile, then sign in or register with another email or Google account. Authentication must succeed before the selected local account changes. Each server/user UUID has its own ledger, cloud revision, internal backups, restore recovery copy and automation inbox. Unsynced entries remain with their original owner. The legacy root folder is retained for the original account; additional accounts use hashed directories under Accounts. No ledger is deleted or copied into a different account during switching.

Workers capture a specific store before asynchronous work. Shared-store mutations still require matching Keychain credentials, and sync retains its account ownership check. A new account with a cloud ledger downloads it without uploading the previous user's data. Switching recreates the main screen's model and navigation state.

External automatic backups are turned off when changing account directories, so users must select the appropriate folder again. Existing exported files remain untouched. Old notifications are cleared at switching; the newly opened ledger can schedule its own reminders. Avatar/name settings remain keyed by account; general appearance preferences remain device-wide.

Validation added to CloudSyncTests: A/B unsynced records and internal recovery/inbox isolation, B-only remote restoration with zero uploads, server isolation, and rejection of corrupt account files. Windows static/project/configuration checks can run locally; native XCTest and device switching still require the macOS CI build and iPhone verification.

Device verification: create a distinctive entry in A, sign out, use B, verify A's entry is absent, create a B entry, then sign back into A and verify A's entry is unchanged. Repeat with unsynced A changes, restart the app on B, and test password recovery for B while A is the previously selected account. Confirm external backups require folder selection after a switch. Do not uninstall while testing unsynced data retention: deleting the app deletes all its local account directories.
