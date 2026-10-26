# Backup and recovery after reinstalling

This extends the build 98 file-based backup. It does not add account sync or an
entitled iCloud container. Recovery requires a backup made before uninstalling.

Account-based automatic recovery has since been added separately: see
[CloudSetup.md](../CloudSetup.md). The file backup behavior described here remains available.

## User journey

1. Open Settings → Backups & export. Create and choose a **YueJi Backups** folder
   in iCloud Drive. New configurations default to **After every change**; explicitly
   selected daily/weekly frequencies remain supported.
2. Confirm **Last backup** shows a successful copy. Before uninstalling, use
   **Back up now** and wait for iCloud upload to complete in Files. The app can confirm
   a file write, but cannot promise remote upload completion or offline durability.
3. After reinstalling, **Keep your ledger** appears before the usage guide. Select
   **Restore previous ledger**, choose the newest saved JSON, review its date and
   contents, then confirm. The same recovery action is in Settings.
4. Choose the external backup folder again to protect subsequent changes. The
   folder permission/bookmark is local and does not survive uninstalling.

Ledger backups include transactions, item/split data, budgets, recurring bills,
settlements, savings goals, merchant rules and the other fields in ledger version 6.
Device preferences, permissions, unsaved drafts and unprocessed delivery-inbox files
are not part of the ledger backup. This is not a complete device backup.

## Implementation

- `LocalStore.change` schedules backup only after a successful production-store
  write and outside file coordination. This includes UI and Shortcuts writes;
  isolated test stores never write to the user's external backup folder.
- Every-change mode checks the newest persisted snapshot. Changes during a running
  copy request a follow-up snapshot. Identical snapshots are skipped. Background
  time is limited by iOS; opening/leaving the app retries a due backup. A force quit,
  immediate uninstall, inaccessible folder or exhausted background time can prevent
  the latest change from reaching the backup.
- File names add milliseconds and a UUID, so rapid writes do not overwrite each
  other. Older timestamp-only files remain recognized. Validation occurs before
  writing/rotating copies; retention still keeps 7, 14 or 30 automatic copies.
- The app's own container is rejected as a backup destination. Prefer iCloud Drive:
  a local folder elsewhere on the phone does not protect against phone loss.
- A fresh installation cannot enable backup into a folder containing previous
  automatic copies until its old ledger is restored (or a new empty folder is chosen).
  This protects old copies from rotation by a newly configured empty ledger.
- Recovery uses coordinated reads for Files/iCloud documents, validates before
  previewing, and keeps the existing explicit replacement confirmation and local
  pre-restore recovery copy. Merely selecting a file does not mutate the ledger.
- Chinese, English and Malay text explains setup, recovery and the upload boundary.

## Verification

`scripts/check_project.py` passes locally (Windows, Python UTF-8 mode). Added XCTest
coverage checks every-change scheduling policy, unique rapid saves, validation before
rotation, legacy/new file names, and restoring ledger data after deleting simulated
app storage. A UI test checks recovery appears before the guide on a fresh launch.
Native compilation, XCTest and iPhone/iCloud behavior have not been run here.

Before shipping, run the native suite and perform an actual iPhone round trip:
configure iCloud, save manual and Shortcuts records, inspect the latest JSON, wait for
upload, uninstall, reinstall, restore, and re-enable backup. Also check cancelled
pickers/previews, malformed and cloud-only files, denied folder access, rapid changes,
daily/weekly settings, and large text in all three languages.

Apple references: [directory access through the document picker](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
and [iCloud service configuration](https://developer.apple.com/documentation/xcode/configuring-icloud-services).
