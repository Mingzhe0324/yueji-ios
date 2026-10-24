# Year in review, unusual spending, automatic backup, the new opening and visual details

Build 98 (1.68.0). Four features and a set of visual details; no ledger schema change (still
version 6), and nothing new is stored in the ledger or its backups.

## Automatic backup outside the app

`AutoBackup.swift`. Settings → Backups & export → **Automatic backup**.

- The person picks a folder in Files once (iCloud Drive is suggested). YueJi keeps a
  security-scoped bookmark to it, so no App Group or paid iCloud entitlement is needed.
- A copy is made when the app is opened (after the launch work) and when it goes to the
  background, if the chosen period has passed (daily: 20 h, weekly: 6.5 days) **and** the
  ledger file changed since the last copy (SHA-256 of `ledger.json`). **Back up now**
  always writes one.
- Each copy is the same complete JSON as **Save a complete backup**, named
  `YueJi-auto-yyyy-MM-dd-HHmmss.json`, written atomically under file coordination.
  Only automatic copies past the number kept (7, 14 or 30) are removed, including their
  iCloud placeholders (`.name.icloud`); nothing else in the folder is touched.
- After reinstalling, **Restore from a backup file** reads them like any backup.
- A missing folder or failed write shows on the page and in the Settings row ("needs
  attention"); turning it off keeps the copies already made. Leaving the app runs inside a
  background task; a copy cut short leaves no partial file and is made again next time.

## Year in review and calendar heatmap

`Insights.swift` (`YearSnapshot`, `SpendingHeatScale`), `InsightViews.swift` (`YearReviewView`).
Overview → Spending trend → **See the whole year**, or More tools → **Year in review**.

- Counts exactly as the Overview does: each expense's personal spending (after friends'
  shares, refunds and claims) on its own date, items spread over their categories, travel
  books included. Month totals equal `OverviewSnapshot.personal` (tested).
- Hero: the year's total and the change on the **same dates** of the year before, shown only
  when YueJi has records from the start of that period (so a part-year never looks like a
  jump).
- **Every day**: twelve small month grids (one Canvas each) in one hue, four steps over a
  neutral cell, with a Less → More key. Steps are the year's quartiles with eight or more
  days of spending (quarters of the largest day otherwise); the largest day is always the
  darkest. Days still to come are fainter; today has an outline.
- The chosen month as a large calendar; tapping a day lists that day's entries, each
  opening its details.
- Twelve bars with the monthly average, highlights (monthly average, busiest month,
  biggest day — tapping it jumps to the day — and no-spend days counted from the first
  entry), categories and the top five merchants.
- Follows the Overview's eye (hidden amounts), Dynamic Type, VoiceOver labels per month and
  per day, and Reduce Motion.

## Unusual spending

`Insights.swift` (`SpendingAlerts`, `UnusualSpendingNotifier`), `InsightViews.swift`
(`UnusualSpendingSection`). Shown on the Overview under the budget as **Worth a look**, only
when something stands out.

The month is compared with the three before it, like for like: up to the same day while the
month is under way, whole months once it has ended. Travel books are left out. It needs at
least two of those months with entries, so a new ledger stays quiet.

| Kind | When |
|---|---|
| Overall pace | ≥ 25% and ≥ RM 100 above usual (from the 5th of the month) |
| Category | ≥ 40% and ≥ RM 50 above its usual (from the 5th) |
| New category | ≥ RM 100 in a category with nothing in the three months (from the 5th) |
| Large purchase | ≥ RM 100 and ≥ 3× the median purchase in its category (needs three earlier purchases); scheduled and renewal payments never count |

A purchase explains its category, so the category line is not shown as well. At most the
overall pace plus three. Each line opens its category, purchase or the monthly comparison;
swiping hides it for that month.

Notifications (Settings → Notifications → **Unusual spending**, on by default): the current
month only, each alert once a month, at most one a day, never for single purchases (the
automatic recording already notified). They respect **Hide amounts and names**, and in the
foreground they become the app's own banner. Checked after every refresh and after the
Apple Pay, Bank/TNG and recurring Shortcuts actions, like budget alerts.

## The opening: "the moon of the month"

`OpeningAnimation.swift`, moved out of `Views.swift`.

1. Dusk: the page lights, gold stars come out, and this month's days appear around the
   centre clockwise from the 1st, with a gold thread from the 1st to today (today is a gold
   bead; days gone are brighter than days to come).
2. Moonrise: the icon's glass moon rises into the middle.
3. Waxing: the gold crescent grows from a new moon into the icon's crescent (an animatable
   shape), and the three entries are written across it.
4. The name settles letter by letter with the app's line beneath; today's bead ripples, and
   one soft haptic marks the crescent completing.

About 1.1 s, then the app is revealed **through the moon**: an iris opens from the moon past
the screen's corners behind a fading gold rim (`AnyTransition.openingIris`). Tap to skip,
the wait for the ledger, the launch sound, the accessibility behaviour and the launch
readiness rules are unchanged. With Animations off or Reduce Motion the finished picture
shows and fades as before; before iOS 26 and with Reduce Transparency the moon is solid.

## Visual and motion details

`VisualDetails.swift` holds the shared pieces; everything that moves honours Reduce Motion and
the Animations setting (UI tests run with Animations off).

| Detail | Where | What changes |
|---|---|---|
| Grouped amounts | `money()`, `Currency.display` | `RM 14,700.00`, `JPY 12,000`. `Currency.input` (text fields) never groups; CSV export doesn't use these. |
| Day totals | Ledger day headers | The day's personal spending beside its date (`LedgerDayGroup.spending`); the days add up to the month's total. |
| Category icons | All seven category pickers | Each category's symbol in its colour (`CategoryChoiceLabel`); VoiceOver still reads the name only. |
| Symbol effects | Budget status, eye, "Saved", goal seal | The budget symbol wiggles once when this month passes 80%, is reached or exceeded (not on a month change or first load); the eye bounces; the Saved banner's checkmark draws itself; the goal seal bounces. |
| Month dial | Overview budget card | Replaces the capacity bar: the month's days as beads around the outside (today gold) with a gold thread from the 1st to today, the budget used as an inner arc, the used percentage in the middle. "Ahead of the month" from the 5th when spending is ten points ahead (`BudgetPace`). Stacks at accessibility sizes. |
| Count-up | Overview total | Once a launch, the total counts up from zero as the opening reveals the app. |
| Moon loader | Loading screen, updating indicator | The icon's moon with its crescent waxing and waning, instead of a spinner. |
| Scrubbing | Spending trend, year bars | Slide a finger across the bars for each month's value with a light tick; let go or tap to select. Mostly vertical drags still scroll the page. |
| Tappable donut | Overview "Where it went" | Tap a sector or a chip to pick a category: the others fade, the middle shows its share, the chip is outlined. |
| Goal reached | Savings goal ring | A gold sweep runs once around the ring with the seal's bounce and the existing chime. |
| Quick add (iOS 26) | Above the tab bar | "Today RM … ⊕" on every tab; tapping opens a new entry. Respects the Overview's eye. |

## Verification

On Windows: Swift syntax parsing (tree-sitter) of every app and test file, and
`scripts/check_project.py` (build membership of the four new app files and the new test
file, resources, scheme) pass.

Not yet verified (needs Xcode/CI and an iPhone):

- native compilation
- the new XCTest cases in `YueJiTests/InsightsTests.swift`: year totals against the Overview,
  same-date comparison, heat steps, the worker projection; like-for-like category and
  overall alerts, quiet without history, early-month purchases, purchases explaining their
  category, scheduled and travel spending left out, hidden alerts, notification limits,
  English text; backup names and expiry (including iCloud placeholders), due policy, a
  write → restore round trip that leaves other files alone, and the unchanged / forced /
  changed / missing-folder writer outcomes
- the XCTest cases in `YueJiTests/VisualDetailsTests.swift`: grouped amounts (and ungrouped
  input), the month dial's pace in a running, ended and future month, "ahead of the month",
  day totals adding up to the month, donut hit-testing, scrub versus scroll, and the goal
  sweep's start and end
- the UI itself

Device checklist:

1. Opening: cold launch in light and dark, on the 1st and the last day of a month, with a
   slow first read (the hold), tap to skip at each step, Animations off, Reduce Motion,
   Reduce Transparency, VoiceOver. Then the existing cold-launch UI tests.
2. Automatic backup: choose an iCloud Drive folder, Back up now, leave and reopen the app
   the next day, change the frequency and number kept, rename or delete the folder (the
   page should say so), turn it off, delete and reinstall YueJi, then restore from the
   newest `YueJi-auto` file.
3. Year in review: switch years, tap months and days, Biggest day, hidden amounts, a large
   ledger (scrolling the twelve grids), Large Text and VoiceOver.
4. Unusual spending: with three months of history, a category well up by the same day, a new
   category, a large purchase; open each line, hide one, and check one notification a day
   with the setting on and none with it off.
5. Visual details: large amounts in every list; day totals; picker icons in menus and
   navigation lists; the dial in light/dark, Large Text and Reduce Motion, on the 1st, mid-month
   and in past/future months; the count-up after a cold launch; scrubbing both charts while
   also scrolling past them; donut and chip picking; reaching a goal twice; the quick-add bar
   on each tab (iOS 26) and that Add Entry and the tabs stay tappable.
