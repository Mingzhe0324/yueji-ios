# Moon Island visual theme

Original cartoon direction, inspired by the reference videos' playfulness rather
than copying their characters, forest layouts or screens. Warm cream paper,
mint accents, a yellow moon companion and rounded typography carry across the
app. Dark mode uses deep teal paper and lighter mint accents.

Shared list/page/sheet surfaces, navigation/tab chrome, action cards and primary
and secondary buttons use the theme. Overview, ledger, recurring, friends,
settings, travel and savings have localized illustrated introductions. The
launch animation uses the same native vector moon character. Maps, system
permissions, keyboards and Apple's place detail card remain system controls.

The mascot is built from SwiftUI vector shapes, so there are no downloaded art
assets or photo permissions. Decorative views never accept taps and are hidden
from VoiceOver. Large accessibility text sizes omit the banner mascot to keep
text readable. VoiceOver labels and transaction control identifiers are retained.

Animation consists of short entry springs, depth/scale feedback and a light
haptic on button presses, and existing animated amounts/progress meters.

The companion has moods (happy, excited, worried, sad, sleepy) with matching
eyes, brows, mouth and small extras (sparkles, a tear, drifting "z"s). On
Overview it follows the selected month's budget: sleepy when empty, excited when
on track, worried near the limit, sad when over. Saves show an excited companion
in the banner with a short confetti burst; deletions show a sad companion beside
Undo. Empty states use the companion, and tapping a companion makes it hop and
wave. The only continuous motion is an occasional blink (and the slow tear/"z"
drift for sad/sleepy); there are no rewards for spending and no new sound triggers.

A display-only streak chip on Overview counts consecutive days with entries.
The opening drops the companion onto a small island with a squash, confetti and
bouncing title letters in about 1.1 s; tapping skips it, and the ledger still
loads underneath. Reduce Motion or turning off playful animations disables all
character, confetti and press transforms. Existing destructive roles/tints and
financial amount colors remain distinct.

Windows project and syntax validation is available. Before release, run native
UI tests and check light/dark modes, large text, Reduce Motion, native toolbar
button sizing, rapid tab changes, keyboard dismissal and first-launch hit targets.
The existing app icon is retained; this change styles the in-app experience.
