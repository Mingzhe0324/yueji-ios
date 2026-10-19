# Apple-native design

YueJi is designed to look and behave like an app Apple made. Every screen uses Apple's own
components with their default appearance and motion — grouped lists, navigation stacks,
Liquid Glass bars and buttons, sheets, menus, context menus, `Gauge`, `ProgressView`,
Swift Charts, `ContentUnavailableView` — in Apple's system colours, so the app matches
iOS 26/27 exactly in light and dark mode and picks up the system's own refinements
(iOS 27 keeps Liquid Glass and tunes its readability and opacity). The earlier custom
themes (the cartoon "Moon Island" companion and the "moonlit" summary cards) were
retired; every screen, action and ledger behaviour is unchanged.

The original native design is described in `application-native-style.md`; this page
records the current rules. The reference is Apple's "iOS and iPadOS 27 UI Kit" (Figma,
Apple Design Resources), page "Examples": Tab Bar 12740:24076, Toolbars - Top
12740:23996, List 12740:24202, Sheets (Modals) 12740:24097, Home Screen 12740:35189.

## Matching the iOS 27 UI kit

- Navigation: large titles (34 pt bold) with a subtitle line on iOS 26+ (`yuejiSubtitle`):
  Overview shows today's date, Ledger the selected month, Recurring the active count,
  Friends how many people are still to settle up. Toolbar buttons are system glass
  circles and capsules; content fades under the bar with the soft scroll-edge effect.
- Lists: inset grouped on #F2F2F7 with white sections (26 pt corners), 52 pt rows,
  inset separators, secondary detail text and grey chevrons, as the system draws them.
- Sheets: grabber, a glass ✕ for cancel/close and a checkmark for save/done/apply in
  the toolbar (prominent glass in the tint), titles in the centre. Text titles remain
  the buttons' accessibility labels ("Cancel", "Save" …), which VoiceOver reads and
  the UI tests use.
- Tab bar: the system Liquid Glass tab bar. (The kit's optional detached search tab
  is not used: search stays inside Ledger.)

## Colours and type

- `IslandTheme` (the "Island" names are historical): `accent` = system blue, the
  accent of Apple's iOS 27 UI kit (#0088FF), `paper` = `systemGroupedBackground`
  (#F2F2F7), `card` = `secondarySystemGroupedBackground`, `line` = `separator`.
- `IslandPalette`: system colours for icons and categories (green, teal, blue, purple,
  pink, red, orange, gray). Income green and spending red keep their financial meaning.
- Type: the system font (SF Pro) at the standard text styles; summary amounts use
  `largeTitle` bold with monospaced digits.
- `LaunchBackground` equals `systemGroupedBackground`, so the launch screen, the opening
  and the app share one background.

## Components

- Lists: `insetGrouped` on every tab with the system section spacing. Summary rows
  follow Health and Wallet: a tinted SF Symbol heading, the amount in large type and
  secondary detail text.
- Navigation rows: `SimpleSettingsRow` and `IslandRowLabel` with Settings-style
  rounded-square icons; categories and transactions use Apple Card-style white symbols
  on coloured circles (`IslandIconTile`); people use monogram avatars.
- Overview: month picker; the spending summary with a native linear-capacity `Gauge`
  for the budget and an eye button (SF Symbol replace transition) that hides amounts;
  Needs attention; recent entries; the six-month spending trend (Swift Charts bars in
  the tint, the selected month solid, tap a bar to select it); Scan receipt and
  Automation; savings; payment details; where it went; More tools.
- Progress: `SpendingMeter` is the system `ProgressView` tinted per category or goal.
- Empty states: `IslandEmptyState` is `ContentUnavailableView`.
- Liquid Glass on iOS 26+: system glass navigation and tab bars (MainView also applies
  the app's light/dark choice to the window so UIKit chrome follows it), `.glassProminent`
  and `.glass` buttons, `GlassIconButton` circles (month arrows) inside a
  `GlassEffectContainer`, and glass in-app notification banners that show the app logo
  with a status badge. Reduce Transparency, Increased Contrast and older systems fall
  back to opaque system surfaces and bordered buttons.

## Motion

The system owns all motion: navigation push/pop, sheets, menus, context-menu previews,
glass press and morphing, list insertions and removals, tab selection and scroll edges.
Content appears immediately. The app animates only content changes, with short
bounce-free springs (`YueJiMotion`): months sliding, amounts rolling (`numericText`),
gauges, bars and charts filling, and banners dropping in from the top like system
notifications. Matched zoom transitions stay off (see `overview-quick-return.md`).
Everything is one-shot, so XCUITest's idle waits are never held up.

Settings › Appearance & language › Motion & feedback › Animations (stored as
`playfulAnimations`) turns these content animations off; Reduce Motion does the same.
UI tests launch with `-playfulAnimations NO`.

## Opening

Like an Apple app launching: only the app icon on the system background. It settles in,
waits for the ledger to load, then lifts slightly while it fades into the app, so it
never opens onto a blank screen. Tapping skips it. The opening layer never takes
touches, and it leaves the accessibility tree as soon as the reveal starts (or on skip),
which `testFirstAddItemImmediatelyAfterLaunchWithOpening` relies on.

## Icon and notifications

`scripts/generate_icon.py` draws the icon in Apple's iOS 26/27 Liquid Glass icon style: a
vivid Apple-blue gradient matching the tint, a frosted glass ledger card (记, "record") with three entries and
bright glass edges, and a gold crescent moon (月, "moon") layered in front with a soft
shadow. Like Apple's own apps it ships the three home-screen appearances in a
single-size AppIcon set (Xcode derives every smaller size): default, dark (the glass card
and gold moon on graphite) and tinted (grayscale artwork on black that iOS recolours with
the user's tint). It also writes the byte-identical opening logo and the
`YueJiIcon@2x/@3x` fallbacks that AltStore and other sideloading tools read from
`CFBundleIconFiles`. System notifications show this icon.

It also writes four notification thumbnails in the same style — the blue background
and a frosted glass card carrying one glyph — attached by `LedgerNotifications`:
`YueJiNoticeRecorded` (check, automatic entry recorded), `YueJiNoticeReview` (alert,
record needs review), `YueJiNoticeReminder` (the full icon artwork, daily reminder) and
`YueJiNoticeBudget` (gauge, budget alert). Thumbnails are cosmetic: if an attachment
can't be created the notification is sent without it.

## Validation

Windows project checks and tree-sitter Swift syntax parsing are available locally;
they do not type-check SwiftUI. Before release, run native unit and UI tests and check,
on iOS 26/27: light/dark modes and the app's appearance override, Reduce Transparency
and Increased Contrast, large text, Reduce Motion, the eye button, tapping trend bars,
long-press on recent entries, and first-launch hit targets with the opening on and off.
