# Moon Island visual theme

Original cartoon direction, inspired by the reference videos' playfulness rather
than copying their characters, forest layouts or screens. Warm cream paper,
mint accents, a yellow moon companion and rounded typography carry across the
app. Dark mode uses deep teal paper and lighter mint accents.

Shared list/page/sheet surfaces, navigation/tab chrome, action cards and primary
and secondary buttons use the theme. Ledger, recurring, friends, settings,
travel and savings have localized illustrated introductions with the companion;
Overview has the living island (below). Maps, system permissions, keyboards,
alerts and Apple's place detail card remain system controls.

The companion and island are built from SwiftUI vector shapes, so there are no
downloaded art assets or photo permissions. Decorative art is hidden from
VoiceOver; text, VoiceOver labels and transaction control identifiers are
retained. Large accessibility text sizes omit the page-banner companion.

## One visual and motion language

- Colour: `IslandTheme` (paper, card, accent, sun) for surfaces and controls, and
  `IslandPalette` (leaf, mint, lagoon, sky, lavender, berry, coral, pumpkin,
  pebble) for icons and categories. Built-in and custom category colours map to
  the palette; settings-style rows use it too. Income green and spending red
  keep their financial meaning.
- Surfaces: every list, page, sheet and the onboarding guide sits on
  `IslandBackdrop` (paper with static clouds and sparkles). Chunky cards, buttons,
  icon tiles and banners share the solid-ledge look.
- Type: rounded design throughout, with heavy rounded navigation titles and bold
  rounded tab labels.
- Motion (`YueJiMotion`): layout and content use bounce-free springs (`standard`,
  `detail`, `month`, `rows`) so lists never jump; text changes use `content`;
  presses use `press`; chips and badges `pop`; cards, empty states and the
  companion arriving on a page `entrance`; banners `banner`; progress bars
  `meter`. New code should use these rather than one-off timings. The companion's
  own acting keeps its choreography inside `Companion.swift`.
- States: loading, empty, success, deleted and error-like empty screens all use
  the companion with a fitting mood. Blocking errors and confirmations remain
  system alerts and dialogs (UI tests and VoiceOver rely on them).
- Tab changes: arriving on a tab pops that page's companion in (and it waves on
  the first visit per launch). Only the small companion animates; the tab itself
  is never scaled or faded, which keeps switching fast.
- Opening: the iris waits on the title screen until the ledger has loaded, so it
  never opens onto a blank background. Skipping keeps the title screen visible
  until the app is ready.

## The companion (`Companion.swift`)

Moods set by the screen: happy, excited, worried, sad, sleepy. Momentary
expressions for actions: wink, surprised, dizzy (spiral eyes, orbiting stars),
love (heart eyes, rising hearts), giggle and yawn. Its eyes follow a `look`
direction with a slight head turn.

Interaction (`InteractiveCompanion`), kept clear of controls and information:
- Tap: a varied reaction (wave, hop, giggle, spin, wink, surprised, dance,
  love) that never repeats the previous one, with a short line shown in place of
  the banner subtitle for a few seconds. Five quick taps make it dizzy.
- Drag: it looks toward the finger and stretches with a rubber-band pull, then
  springs back; a long pull ends in a giggle. The gesture sits on a fixed outer
  frame so the stretch never feeds back into the drag reading.
- Hold (0.6 s): a hug with hearts.
- A newer reaction interrupts the current one; it never queues.

It celebrates saves (Overview and the save banner, with confetti), looks sad
beside Undo after a deletion, encourages gently when over budget, and greets
once per launch on Overview. Optional sounds use the Hello/Hug/Dance/Star chimes
(full sound mode only, quieter than save chimes), and haptics follow settings.

## Ambient motion

Idle life (breathing, blinks, glances, the odd stretch, sigh or yawn, dozing
"z"s) and the island scenery (drifting clouds, sea, swaying plants, bobbing boat,
twinkling stars, flapping birds) run continuously, so they are a separate layer
from one-shot reactions. They run only while that view is on screen and the app
is active, and are off with Reduce Motion, Low Power Mode, playful animations
off, or Settings › Appearance & language › Motion & feedback › Ambient motion.

The XCUITest runner waits for the app to be idle before each step. An earlier
endless drift/blink loop kept it waiting and timed out CI, so the UI tests launch
with `-ambientAnimations NO`. Everything else (reactions, celebrations, the
opening) is one-shot and finishes on its own.

## Island journal

The Overview card's Journal button opens the island's album: days recorded,
current and best streak, all seven stages drawn as still miniatures (unlocked in
colour, locked in grey with how many days remain, "You're here" on the current
one), and a streak badge wall earned by the best streak. Badges reward the
recording habit, never amounts. The companion greets and reacts here too.

## Consistency rules

- One character: the island companion. The retired crescent `MoonBuddy` is gone.
- Progress always uses the chunky `SpendingMeter` (savings, comparisons, category
  breakdowns, trips); savings detail uses a chunky sun ring that turns mint when
  the goal is reached, with the companion inside and a celebration on reaching it.
- Links and tools use `IslandRowLabel` (tile + title); settings-style rows use
  `SimpleSettingsRow`; people use `IslandAvatar`; categories use `CategoryBadge`.
- Comparisons read spending less than last month as good news (mint) and more as
  a gentle caution (pumpkin).
- The onboarding guide's mock screens use the same paper, cards and accent as the
  real app.

## The living island (`IslandWorld.swift`)

Overview's top card shows a sky that follows the time of day (dawn, day, dusk,
night with moon and stars), the sea, an island and the companion. The island
grows with recorded days (distinct days with entries, never spending amounts):

| Level | Logged days | Adds |
|-------|-------------|------|
| 1 Seedling Isle | 0 | a sprout |
| 2 Blossom Isle | 3 | flowers |
| 3 Palm Isle | 7 | a palm tree |
| 4 Cottage Isle | 14 | a cottage |
| 5 Sailing Cove | 30 | a sailboat |
| 6 Rainbow Bay | 60 | a rainbow |
| 7 Songbird Haven | 100 | songbirds |

The card shows the level, a progress bar to the next item and the recording
streak. Each new level and streak milestone (3, 7, 14, 30, 60, 100, 200, 365
days) is celebrated once (confetti, companion cheer, message, haptic, goal
chime, VoiceOver announcement) and recorded as seen only after it plays. The
first sighting after install or update is recorded quietly. Preview ledgers in
the guide never celebrate.

## Game feel

Island buttons are chunky (solid face on a darker ledge) and sink into the
ledge on press with a light haptic; row, settings and category icons use chunky
ledged tiles; navigation titles and tab labels use a bold rounded font; amounts
"boing" when they change; meters are thicker with a glossy stripe and a springy
fill (clipped to the track); in-app banners are opaque chunky cards that bounce
in with the companion; empty states and the loading screen feature it too.

Tab switching is deliberately not animated: scaling/fading a whole tab
(navigation bar plus list) forces an offscreen render of the screen every frame
and made switching visibly laggy, so that effect was removed.

## Icon, notifications and opening

The app icon and notification art are original drawings generated by
`scripts/generate_icon.py` (companion on an island). It writes every AppIcon
size as opaque RGB, the byte-identical opening logo, the IPA icon fallbacks and
three notification thumbnails (happy for recorded results, worried for items
needing review and budget alerts, sleepy for the daily reminder). Thumbnails are
cosmetic: if an attachment can't be created the notification is sent without it.

The opening is a short title screen (about 1.75 s): a night sky with stars, the
sea slides in and an island bounces up, the companion tumbles down and lands
(ground ring, dust puffs, confetti, night turns to dawn), sticker-style title
letters bounce in, a ribbon unrolls with the tagline, then a cartoon iris wipe
opens from the companion onto the app. Tapping skips it, and the ledger still
loads underneath. Reduce Motion or turning off playful animations disables all
character, confetti and press transforms. Existing destructive roles/tints and
financial amount colors remain distinct.

## Validation

Windows project checks and tree-sitter Swift syntax parsing are available
locally; they do not type-check SwiftUI. Before release, run native UI tests and
check light/dark modes, large text, Reduce Motion, Low Power Mode, rapid tab
changes, keyboard dismissal, first-launch hit targets, companion drag inside
scrolling lists, and scrolling smoothness on Overview with ambient motion on.
