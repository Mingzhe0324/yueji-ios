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

Animation consists of a single short entry spring, depth/scale feedback on
button presses and existing animated amounts/progress meters. No forever-running
character loops, rewards for spending, new sound triggers or launch delays.
Reduce Motion disables the character and press transforms. Existing destructive
roles/tints and financial amount colors remain distinct.

Windows project and syntax validation is available. Before release, run native
UI tests and check light/dark modes, large text, Reduce Motion, native toolbar
button sizing, rapid tab changes, keyboard dismissal and first-launch hit targets.
The existing app icon is retained; this change styles the in-app experience.
