# Navigation and tab bar appearance

The supplied screenshot shows dark page content with light-looking native toolbar/tab materials and black navigation/status text and unselected tab symbols. The app already resolves system/light/dark preference at the window through preferredColorScheme, and has no forced light mode in Info.plist or UIKit appearance overrides. Native bars previously had no explicit color-scheme or background-visibility policy. The screenshot alone does not identify an OS/framework root cause.

A shared modifier now passes the page's resolved colorScheme to both navigation and tab bars and keeps their native backgrounds visible. It is applied to all five tab roots, shared list surfaces and shared sheet surfaces. This preserves system materials, the existing blue accent and the app's explicit light/dark overrides; it does not hard-code icon colors or replace native bars. It also avoids recreating navigation stacks when appearance changes.

Apple documents that toolbarColorScheme is respected while the bar background is visible: https://developer.apple.com/documentation/swiftui/view/toolbarcolorscheme(_:for:)

Native visual checks remain required: system light/dark changes while the app is open; app-specific Light and Dark overrides; all five tabs; Overview at the top and after scrolling; the top-right More tools button and its destination; item editor sheets; and navigation/status text contrast. Local structural/syntax checks cannot confirm the rendered iOS appearance. No long-running UI cases were added for this style-only correction.
