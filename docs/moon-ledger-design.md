# Moon Ledger — UI Skills design pass

## Working brief

YueJi is opened just after paying, receiving money or settling with a friend. The
person needs to recognise the amount, account and next action in a few seconds.
The interface should feel like a carefully kept personal ledger: composed,
precise and tactile. Existing accounting, navigation and review destinations stay
the source of truth; this pass changes presentation.

Domain: monthly cycles, receipt paper, ink, wallet cards, reconciled balances,
personal shares. Color world: warm receipt white, graphite ink, teal ledger ink,
pale jade, silver moonlight, and the existing red/green financial semantics.
Signature: a quiet cropped moon arc on summary surfaces; rounded, tabular money;
small ink-toned action tiles. The arc is decorative, never a progress indicator.
Avoid a dashboard of equally loud cards, rainbow action buttons, and perpetual
glow/bounce. Use one leading total, restrained tonal surfaces and direct feedback.

## Component decisions

- Shared surfaces: the amount or form content leads. Warm paper in light mode,
  ink in dark mode, system grouped cards for reliable native list behavior.
  Depth is tonal, with a fine edge on custom summary cards. Use 4-point spacing,
  20-point summary padding, 24-point outer corners, 12-point control corners.
- Overview: one personal-spending total (44-point scaled rounded semibold),
  short label and count, then today's amount. Explanation stays in the
  accessibility hint. Quick actions are single semantic Buttons, 2 columns
  normally and 1 at accessibility sizes; each whole tile is the hit target.
- Accounts: recorded total leads above wallet cards; bank identity retains its
  original logo. Cards use minimum height, allowing accessibility text to grow.
- Friends: retain gross receivable and payable meanings, with a shared summary
  surface. Do not relabel gross totals as net or modify settlement calculations.
- Controls: 44-point minimum touch target. Shared button style for press feedback;
  no separate caption gesture. Disabled controls do not animate.
- Motion: 150ms press, 240–280ms content and month changes, restrained spring
  with zero bounce. Animate state changes, never entire forms or list identity.
  Reduce Motion and the Animations preference suppress decorative movement.

## Skills read

Via `npx ui-skills@0.2.4`: `ui-skills-root`, `dimillian/swiftui-ui-patterns`,
`dammyjay93/interface-design`, `jakubkrehel/better-ui`. SwiftUI references:
components-index, theming, grids, performance. Web-specific recipes are adapted
to native SwiftUI controls; no web UI dependencies are added to the app.

Sources: https://github.com/ibelick/ui-skills and
https://github.com/Dimillian/Skills/tree/main/swiftui-ui-patterns.

## Verification

The HTML specimen in `Design/moon-ledger.html` is a design reference, not an iOS
runtime screenshot. Native layout, VoiceOver, interrupted transitions, keyboard
safe areas and physical-device frame pacing require Xcode/iPhone verification.
Run source/resource checks and the existing native model/UI workflow. Exercise
light/dark, large accessibility sizes, empty/long balances, hidden amounts,
disabled/loading controls, Reduce Motion and Animations off.

Local checks (2026-11-19): project/resource and language checks passed; all app
and test Swift files parsed without syntax errors. Measured custom action-label
contrast is 6.17:1 light / 8.26:1 dark; summary primary text is 10.50:1 light /
12.38:1 dark. These figures do not certify every existing system/category color.
Browser rendering was unavailable (no browser surfaces connected); the specimen
has not been visually verified. Native compilation/UI tests are delegated to the
GitHub workflow, not substituted by the syntax check.
