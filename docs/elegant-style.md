# Elegant visual style ("moonlit")

YueJi uses a calm, premium finance look taken from its icon: a twilight sky (night
blue fading into plum), a champagne moon, indigo ink for controls, and cool paper
with white cards. Each tab opens with a **moonlit card** — the twilight surface with
moonlight in one corner, a warm glow low on the horizon and a faint crescent — that
holds the tab's summary in white type. Everything below is clean white cards or
list rows with hairline edges and soft shadows. There is no mascot; the earlier
cartoon "Moon Island" style was retired, and every screen, action and ledger
behaviour is unchanged.

Maps, system permissions, keyboards, alerts and Apple's place card remain system
controls. Blocking errors and confirmations remain system alerts and dialogs
(UI tests and VoiceOver rely on them).

## Tokens

- `IslandTheme` (the "Island" names are historical): `accent` (indigo ink,
  periwinkle in dark mode), `onAccent`, `paper` (cool off-white / near-black),
  `card`, `glow`, `line`, the moon colours `moon` (champagne) and `moonDeep` (gold),
  the twilight `nightTop` → `nightMid` → `nightBottom` with `nightGlow`, readable
  statuses on night cards (`onNightGood`, `onNightWarn`, `onNightOver`), and `teal`,
  `peach`.
- `OnNight` — white text, fill and stroke levels for content on moonlit cards.
- `IslandPalette`: muted icon and category colours (mint, lagoon, sky, lavender,
  berry, coral, pumpkin, pebble). Income green and spending red keep their
  financial meaning.
- Type: the system font (SF Pro), bold large titles, monospaced digits for money.
- `LaunchBackground` matches `paper` in light and dark mode, so the system launch
  screen, the opening and the app share one background.

## Surfaces and components (`ElegantStyle.swift`)

- Pages sit on plain `IslandBackdrop` paper. Navigation and tab bars keep a visible
  paper background (see `bar-appearance.md`), so there is never a seam at their
  edges.
- `MoonlitBackground`, `moonlitCard()` (scrolling pages) and `moonlitRow()` (list
  rows; the list rounds the cell) — the signature twilight surface with the
  `CrescentShape` watermark, drawn with the icon's proportions. Content on it styles
  its own text with `OnNight`: a foreground style on the card would also reach pages
  opened from links inside it. Used by the Overview, Ledger, Recurring, Friends and
  Settings headers. `MoonlitButtonStyle` gives champagne (main action) or translucent
  white capsules; `MonthPicker(onDark:)`, `ElegantChip(onDark:)` and
  `BudgetGauge(onDark:)` have white variants with a champagne gauge arc.
- `elegantCard()` — white card, hairline edge, soft low shadow.
- `IslandButtonStyle` — primary buttons are indigo capsules with a soft top sheen,
  secondary ones white capsules with a hairline; a press dips slightly with a light
  haptic.
- `ElegantPressStyle` — subtle dip and dim for tappable cards and tiles.
- `IslandIconTile`, `IslandRowLabel`, `SimpleSettingsRow`, `IslandAvatar`,
  `CategoryBadge`, `ElegantChip` — icons, rows, people, categories and amounts.
- `IslandEmptyState` — a symbol in a soft circle, title, message and optional
  actions; `IslandMood` only picks the symbol.
- `SpendingMeter` — slim 8 pt bar with a softly shaded fill.
- `BudgetGauge`, `SpendingTrendChart`, `CategoryDonut` — Overview charts.
- In-app banners (`NotificationBannerCard`) are floating cards with a tinted status
  circle, a hairline and a wide soft shadow; they glide down and settle.

## Overview

Scrolling cards in this order: the moonlit hero card (month picker, personal
spending in large type with an eye toggle that hides the amounts, the champagne
semicircle budget gauge with percent used and status, Remaining/Budget chips,
travel and reimbursement lines, and Set/Edit budget); Needs attention (when automatic records wait for
review); four quick-action tiles (Scan receipt, Automation, Savings, More tools);
recent entries as cards (tap for details, long-press for Edit/Delete); the
six-month spending trend (the selected month wears the twilight gradient with a
value tooltip; tapping a bar selects that month); savings; payment details; and
where it went (category donut plus rows that open each category). The toolbar
keeps More tools and Add entry (`overview.manualEntry`).

The trend comes from `LedgerProjectionWorker.spendingTrend`, one pass over the
ledger off the main thread, with the same totals as each month's overview
snapshot (covered by `SpendingTrendTests`).

## Motion (`YueJiMotion`)

Short, bounce-free or nearly bounce-free springs: `standard`, `detail`, `month`,
`rows` for layout; `content` for text changing in place; `press`; `pop`;
`entrance` for cards and empty states; `banner`; `meter` for gauges, bars and
charts. Overview cards rise gently into place on first appearance, a few frames
apart (`ElegantEntrance`); the gauge sweeps, bars grow and the donut turns in.
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
horizon.
It writes every AppIcon size as opaque RGB, the byte-identical opening logo, and
the `YueJiIcon@2x/@3x` fallbacks that sideloading tools such as AltStore read from
`CFBundleIconFiles`. System notifications show this icon.

It also writes four notification thumbnails in the same twilight sky with a
champagne glyph, attached by `LedgerNotifications`: `YueJiNoticeRecorded` (check,
automatic entry recorded), `YueJiNoticeReview` (alert, record needs review),
`YueJiNoticeReminder` (the full logo mark, daily reminder) and `YueJiNoticeBudget`
(gauge, budget alert). Thumbnails are
cosmetic: if an attachment can't be created the notification is sent without it.

## Validation

Windows project checks and tree-sitter Swift syntax parsing are available
locally; they do not type-check SwiftUI. Before release, run native unit and UI
tests and check light/dark modes, large text, Reduce Motion, the eye toggle,
tapping trend bars, long-press on recent entries, first-launch hit targets with
the opening on and off, and scrolling smoothness on Overview.
