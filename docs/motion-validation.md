# Motion ownership and device validation

Native navigation, sheet dragging, keyboard movement and glass button press feedback retain system ownership. Do not add matching geometry, animated sheet offsets or a second drag recognizer around these interactions. Dirty-editor dismissal still requires an explicit discard decision.

The notification host owns insertion/removal opacity. Remove the controller's separate viewDidAppear fade/translation so an incoming banner does not run two independent entrance animations. Gesture drag, cancel settlement and directional exit remain in the controller, including the existing touch suppression and final hit-area release. Spending meters render the actual fraction on appearance rather than animating from zero; value changes retain the short existing transition.

These changes eliminate identified redundant animations, but are not proof of any particular frame rate. Smoothness and exact platform appearance must be assessed using a Release build on a physical iPhone running the user's iOS version. Use the Animation Hitches and SwiftUI Instruments templates to inspect missed frame deadlines and long main-thread updates. Test populated Overview/Ledger scrolling, rapid tab changes, repeated opening/closing, keyboard focus changes, clean/dirty editor dismissal, banner swipe/expiry and large text. Repeat with Reduce Motion and Reduce Transparency.

Local validation: project integrity and Swift syntax. Existing native transaction UI and banner gesture tests remain the regression checks; no additional long-running CI stage is added. Device profiling and native test execution are still pending.

Sources:
- https://developer.apple.com/documentation/swiftui/performance-analysis
- https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance
