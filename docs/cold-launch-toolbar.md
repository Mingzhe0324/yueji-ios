# Cold-launch toolbar handoff

The 2026-10-17 08:07 UTC UI failure is at TransactionFormTests.swift:226:
the actual overview.manualEntry Button exists, but isHittable is false before
the first tap. The failure hierarchy places the button in the Overview toolbar;
no expense editor or location request has started. The other three cases pass.

The earlier Button-only query correction is present in this run, so it does not
fully resolve the failure. The root previously mounted TabView/navigation while
loaded but not launch-ready, with allowsHitTesting(false), then changed this at
the same time as the opening overlay's animated removal. This is a suspected
interaction-state handoff problem, not proven by a device reproduction here.

The root now mounts tabs only after didFinishLaunch. Navigation and toolbar
controls are created interactive; the opening overlay is visual-only while it
fades out. Readiness still requires the ledger load and optional opening to finish
and does not depend on tab appearance, so there is no circular readiness wait.

All four UI cases and the immediate isHittable assertion remain unchanged. No
timeout increase, warm-up tap, retry, or skipped test is introduced. Project
static checks pass on Windows; the original CI failure must be rerun on macOS
to confirm the fix. Startup UI construction now occurs after readiness rather
than being prepared under the logo; device startup smoothness also needs review.
