# Elegant visual style: native iOS 26/27 with a moonlit identity

YueJi looks and moves exactly like iOS 26/27 by using Apple's own **Liquid Glass**
components rather than imitations: system glass navigation and tab bars, glass
buttons, glass controls that morph inside a `GlassEffectContainer`, glass in-app
notifications, system sheets, push/pop, menus and empty states. iOS 27 keeps the
Liquid Glass design from iOS 26 and refines it (better readability over busy content
and a user glass-opacity setting); because the app uses the system components, those
refinements and the system's own animations apply automatically.

The brand comes from the icon. Each tab opens with a **moonlit card** — a twilight sky
(night blue fading into plum) with moonlight in one corner, a warm horizon glow and a
faint champagne crescent — holding the tab's summary in white type, with glass
controls on top. Everything else sits on the system grouped background with flat
system panels, as in Settings and Wallet. There is no mascot; the earlier cartoon
"Moon Island" style was retired, and every screen, action and ledger behaviour is
unchanged.

Maps, system permissions, keyboards, alerts and Apple's place card remain system
controls. Blocking errors and confirmations remain system alerts and dialogs
(UI tests and VoiceOver rely on them).

## Tokens

- `IslandTheme` (the "Island" names are historical): `accent` = the system indigo
  (the app tint), `onAccent`, `paper` = `systemGroupedBackground`, `card` =
  `secondarySystemGroupedBackground`, `glow`, `line`, the moon colours `moon`
  (champagne) and `moonDeep` (gold), the twilight `nightTop` → `nightMid` →
  `nightBottom` with `nightGlow`, readable statuses on night cards (`onNightGood`,
  `onNightWarn`, `onNightOver`), and `teal`, `peach`.
- `OnNight` — white text, fill and stroke levels for content on moonlit cards.
- `IslandPalette`: icon and category colours. Income green and spending red keep
  their financial meaning.
- Type: the system font (SF Pro), bold large titles, monospaced digits for money.
- `LaunchBackground` equals `systemGroupedBackground` in light and dark mode, so the
  system launch screen, the opening and the app share one background.

## Liquid Glass (iOS 26 and later)

- Bars: `YueJiBarAppearance` leaves the navigation and tab bars to the system on iOS
  26+ (floating glass with its own scroll-edge effect). Earlier systems keep the old
  fix from `bar-appearance.md` (bar colour scheme with a visible background).
  `MainView` also applies the app's light/dark choice to the app window, so UIKit
  chrome (glass bars, status bar, alerts) always follows it.
- Buttons: `yuejiPrimaryButton()` is `.glassProminent`, `yuejiSecondaryButton()` is
  `.glass`; `moonlitButton(prominent:)` does the same on moonlit cards.
  `GlassIconButton` is a glass circle (month arrows, the eye toggle); the month
  picker's arrows share a `GlassEffectContainer`.
- Surfaces: in-app notification banners and `ledgerGlass()` use one regular glass
  surface.
- Fallbacks: with Reduce Transparency (or Increased Contrast for banners), or before
  iOS 26, everything falls back to opaque system surfaces and bordered buttons.

## Components (`ElegantStyle.swift`)

- `MoonlitBackground`, `moonlitCard()` (scrolling pages) and `moonlitRow()` (list
  rows; the list rounds the cell) — the twilight surface with the `CrescentShape`
  watermark, drawn with the icon's proportions. Content on it styles its own text
  with `OnNight`: a foreground style on the card would also reach pages opened from
  links inside it. Used by the Overview, Ledger, Recurring, Friends, Settings and
  Entry details headers. `MonthPicker(onDark:)`, `ElegantChip(onDark:)` and
  `BudgetGauge(onDark:)` have white variants with a champagne gauge arc.
- `elegantCard()` — a flat system panel (`card` colour, continuous 26 pt corners),
  exactly like an inset grouped section.
- `ElegantPressStyle` — subtle dip and dim for tappable cards and tiles.
- `IslandIconTile`, `IslandRowLabel`, `SimpleSettingsRow`, `IslandAvatar`,
  `CategoryBadge`, `ElegantChip` — icons, rows, people, categories and amounts.
- `IslandEmptyState` — the system `ContentUnavailableView` (symbol, title, message,
  actions); `IslandMood` only picks the symbol.
- `SpendingMeter` — slim 8 pt bar with a softly shaded fill.
- `BudgetGauge`, `SpendingTrendChart`, `CategoryDonut` — Overview charts.
- In-app banners show the app logo with a small status badge, like a system
  notification, and drop in from the top.

## Overview

Scrolling cards in this order: the moonlit hero card (month picker, personal
spending in large type with an eye toggle that hides the amounts, the champagne
semicircle budget gauge with percent used and status, Remaining/Budget chips,
travel and reimbursement lines, and Set/Edit budget); Needs attention (when
automatic records wait for review); four quick-action tiles (Scan receipt,
Automation, Savings, More tools); recent entries as cards (tap for details,
long-press for Edit/Delete); the six-month spending trend (the selected month wears
the twilight gradient with a value tooltip; tapping a bar selects that month);
savings; payment details; and where it went (category donut plus rows that open
each category). The toolbar keeps More tools and Add entry (`overview.manualEntry`).

The trend comes from `LedgerProjectionWorker.spendingTrend`, one pass over the
ledger off the main thread, with the same totals as each month's overview
snapshot (covered by `SpendingTrendTests`).

## Motion

The system owns all interaction motion: glass press and morphing, navigation
push/pop, sheets, menus, context-menu previews, tab selection and scroll edges.
Content appears immediately, as in Apple's apps — there are no staged entrances.
`YueJiMotion` keeps short, bounce-free springs for the few content changes the app
animates itself: months sliding, amounts rolling (`numericText`), rows inserting and
removing, gauges, bars and the donut filling (like Fitness and Health), and banners
dropping in. Matched zoom transitions stay off (see `overview-quick-return.md`).
Everything is one-shot: nothing loops or idles, so XCUITest's idle waits are never
held up. Tab switching is not animated (animating whole tabs made switching laggy).

Settings › Appearance & language › Motion & feedback › Animations (stored as
`playfulAnimations`) turns decorative motion off; Reduce Motion does the same. UI
tests launch with `-playfulAnimations NO`: functional coverage is unchanged (the
opening layer is still shown in the "with opening" variants and must hand over the
toolbar), only decorative motion is skipped to stay inside the CI time budget.

## Opening

A calm title card on the launch background, about one second: a warm glow blooms,
the icon settles in, the wordmark and tagline rise into place and a thin gradient
line draws beneath them. It holds until the ledger has loaded, then lifts away
(a slight scale-up while it fades) onto the app, so it never opens onto a blank
screen. Tapping skips it; the ledger still loads underneath. The opening layer
never takes touches (MainView keeps it out of hit-testing so it can't cover the
toolbar while fading); skipping uses a separate catcher that disappears instantly
when the app is ready. The opening also leaves the accessibility tree as soon as
the reveal starts (or on skip), which is how
`testFirstAddItemImmediatelyAfterLaunchWithOpening` checks Add Entry is hittable.

## Icon and notifications

`scripts/generate_icon.py` draws the app icon from shapes: a glowing champagne
crescent (月, moon) holding three ledger entries — a bullet and a line each (记,
record) — in a twilight sky that fades from night blue into plum over a warm
horizon. It writes every AppIcon size as opaque RGB, the byte-identical opening
logo, and the `YueJiIcon@2x/@3x` fallbacks that sideloading tools such as AltStore
read from `CFBundleIconFiles`. System notifications show this icon.

It also writes four notification thumbnails in the same twilight sky with a
champagne glyph, attached by `LedgerNotifications`: `YueJiNoticeRecorded` (check,
automatic entry recorded), `YueJiNoticeReview` (alert, record needs review),
`YueJiNoticeReminder` (the full logo mark, daily reminder) and `YueJiNoticeBudget`
(gauge, budget alert). Thumbnails are cosmetic: if an attachment can't be created
the notification is sent without it.

## Validation

Windows project checks and tree-sitter Swift syntax parsing are available
locally; they do not type-check SwiftUI. Before release, run native unit and UI
tests and check, on iOS 26/27: light/dark modes and the app's appearance override
(bars must follow it), Reduce Transparency and Increased Contrast fallbacks, large
text, Reduce Motion, the eye toggle, tapping trend bars, long-press on recent
entries, first-launch hit targets with the opening on and off, and scrolling
smoothness on Overview.
