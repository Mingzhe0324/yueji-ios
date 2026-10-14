# Floating action surfaces

IMG_5205.MP4 shows Overview scrolling in dark mode. The artifact is a full-width rectangular material strip behind Add entry, not an editor sheet dismissal. The strip came from YueJiActionBarSurface's Rectangle filled with bar material, layered underneath an already glass-prominent capsule and above the native tab bar.

Remove the redundant material rectangle for normal transparency settings on Overview and transaction-detail action areas. Keep the safe-area inset, button dimensions, identifiers and tab-bar separation. Reduce Transparency retains an opaque system background and the existing non-glass button fallback. Lists use the native soft bottom scroll-edge effect on iOS 26 and later; earlier systems retain their existing behavior. Button press feedback, scrolling and sheet movement stay system-driven with no additional animation loop, drag recognizer, or offset tracking.

This follows Apple's guidance to avoid stacking glass and use scroll-edge effects for control legibility:
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle

Validation: source recording inspected as frames, local project and Swift syntax checks. Native build and light/dark/Reduce Transparency visual review are still required; Windows checks cannot verify the final rendered scroll effect. No new UI test is added for this visual-only change; existing coverage still checks Add entry stays above the tab bar.
