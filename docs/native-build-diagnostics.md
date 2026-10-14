# Native build diagnostics in CI summaries

The supplied screenshot shows `TEST BUILD FAILED`, a SwiftCompile batch containing ReimbursementViews/Language/Features/Models/LocalStore and exit 65 after 22.1 seconds. It does not include a concrete compiler error or source location. The available Downloads logs predate this build, and no connected browser exposes the current raw log. The application's specific compilation fault is therefore not diagnosed or fixed by this change.

The previous summary extracted only located Swift errors and labelled all of them as XCTest assertions. The reporter now distinguishes compiler diagnostics from test assertions, accepts unlocated Swift/clang/xcodebuild errors, strips ANSI colour codes and includes two following lines of source/module context. An explicit failed-build marker cannot produce a successful native-test summary. Test execution and failure exit codes remain untouched.

Local regression coverage checks located compilation errors, unlocated/coloured errors, native assertions, conflicting success markers and a failed build with missing diagnostic lines. Existing runner deadline/exit-code tests remain required. Once the current raw compiler diagnostic is supplied, fix that specific application error and verify it with the native build; do not infer the cause from the compilation batch name.
