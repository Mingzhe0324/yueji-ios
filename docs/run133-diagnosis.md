# Run 133 diagnosis

Source: user-provided `YueJi-diagnostics-run133.zip`, `build-test.log`, commit `8d44a13`.

- Simulator build succeeded; 432 unit tests passed.
- Six UI tests executed; five passed. Only `testSavedItemFirstTapAfterColdLaunchWithOpening` failed.
- At 26.50s XCTest started typing the merchant. At 28.04s the test immediately read a partial value (`Item regression 853`, expected `Item regression 85397DA4`).
- The failure hierarchy still reports the merchant field as `Keyboard Focused`. This does not establish lost focus or an opening-animation defect. The log cannot distinguish delayed accessibility updates from dropped key events.

Changes: wait up to five seconds for the exact value without retyping; debounce draft persistence by 350ms while flushing on background/disappearance and cancelling after save/discard; disable merchant autocorrection. The original full-value requirement and cold-launch tests remain intact.

Compiler warnings addressed: unnecessary awaits on immutable cloud configuration; non-Sendable store capture replaced with the account folder value and an active-folder check; legacy Core Location delegate conformance annotated preconcurrency (manager is created on the main actor). Apple signed-test-library stripping and test-target metadata warnings are not app compilation errors. Unused return values in tests are non-fatal.

Validation: Windows Swift parser and project/resource checks pass. Xcode tests cannot run on this host; CI must confirm the result. No claim that the runtime failure has already been reproduced or eliminated locally. The raw xcresult bundle requires Apple's tooling for full attachment inspection; the text log includes the failure accessibility hierarchy.
