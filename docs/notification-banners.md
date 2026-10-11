# Build 89: notifications and transitions

## Changes

- Foreground system alerts are handed to the app's banner host, retaining the OS sound and Notification Center entry. Background and lock-screen banners are still managed by iOS. Native photo/file pickers, share sheets and system alerts use native banners because they can cover the app's overlay; their gestures are controlled by iOS. Privacy-sensitive titles/bodies remain those prepared by the existing notification producer.
- Foreground alerts, new bank/TNG records and saved confirmations share one top overlay. It sits below navigation buttons, within safe areas, and does not insert height into the underlying page. The top modal owns feedback while it is open; recurring/category/goal editors, repayments, filters, restore preview, the guide and receipt comparison/camera also participate.
- Either horizontal direction follows the finger through a UIKit pan recognizer. Vertical and ambiguous diagonal gestures do not start dismissal. Recognition cancels button touches; a separate activation latch prevents release from opening a record or invoking Undo.
- Short/cancelled/reversed swipes return with a brief native spring. A completed swipe exits in its release direction. Interrupting a return animation picks up its visible position. Animation completion, rather than a delay, removes the notice. Reduced Motion uses a fade for dismissal and an immediate return.
- A 44-point close button and accessibility dismiss/escape actions provide alternatives to swiping. Labels and hints are available in Chinese, English and Malay. Reduce Transparency uses an opaque surface; dark appearance and increased contrast have matching borders.
- Deletion feedback can also be swiped away. This closes the Undo offer; it does not perform Undo or change the committed records. Swipe recognition prevents the Undo button firing accidentally.
- Lifetimes pause during interaction and backgrounding. Saved confirmations wait while a higher-priority notice is visible. Generation checks prevent an older animation or timer dismissing a replacement notice.
- Ledger navigation retains the existing native pushes, interactive back, opaque grouped backgrounds, retained timeline state and prepared indexes. Recent-entry insertion animation was removed so it cannot compete with a push/pop; notification record lookup now uses the existing index.
- Notification destinations requested while editing a modal are held until it closes, preserving drafts. Opening the record never follows from a dismissal gesture.

## Verification

`NotificationBannerTests` contains nine focused tests for intent filtering, both swipe directions, short drags, fast flicks, reversal/cancellation, screen-width thresholds, explicit destination validation, stale-generation protection, presentation-only dismissal, direct host translation/tap suppression, interruption, duplicate dismissal completion and presentation over native system screens. These are authored for the existing simulator XCTest target; they have **not run on this Windows workspace**.

Local verification: Swift syntax parsing, Xcode project/source/resource references, plist/localization checks and CI YAML/shell syntax. These checks do not establish Apple SDK type correctness, gesture delivery or runtime frame performance. Run the main-branch native simulator tests and Release/device build before installing the IPA.

Physical iPhone checklist (pending):

1. Trigger automatic bank/TNG foreground alerts while viewing the ledger and while an editor sheet is open. Swipe both directions; verify no destination opens, expenses remain recorded, and the correct banner disappears.
2. Try a short horizontal drag, vertical drag, diagonal drag, reverse flick and interrupt a spring return. A fresh deliberate tap should still open the record; swiping over the close/Undo controls should not activate them.
3. Scroll the ledger well down, trigger/dismiss notices, open details and return at least 20 times, including cancelled swipe-back gestures. Confirm scroll position, visible rows, native navigation controls and Manual Entry destination stay stable, without white flashes.
4. On small and large iPhones, portrait/landscape, light/dark, maximum text sizes and VoiceOver, verify the banner does not overlap Back/Close or the bottom transaction actions. Check scrolling and nearby buttons outside the banner's own bounds.
5. Turn Reduce Motion and Reduce Transparency on/off. Confirm fade/opaque alternatives and responsive finger tracking without decorative motion.
6. During a swipe, deliver another alert or save again; the newest notice must survive the old completion. Switch tabs, present/dismiss sheets and background/foreground the app while feedback is visible.
7. Test a notification tap while a modal draft is open: the draft remains intact and the queued destination opens after closing the modal. Background/lock-screen notifications should continue using native system presentation/actions.
8. Profile repeated pushes/back and notice swipes with Instruments Animation Hitches/Time Profiler on a physical iPhone; runtime smoothness cannot be certified by static checks or the policy tests.

Implementation uses [Apple's gesture recognizer delegate](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate), [interruptible property animations](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator) and [size-aware UIKit integration](https://developer.apple.com/documentation/swiftui/uiviewcontrollerrepresentable/sizethatfits(_:uiviewcontroller:context:)). It uses the system material/glass available on the running iOS version; an iOS 26 SDK build cannot promise an exact reproduction of an iOS 27 interface.
