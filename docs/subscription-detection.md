# Subscriptions: suggestions, reminders and renewals

## What YueJi can see

YueJi only knows the payments recorded in it. It can't read other apps' notifications, bank
statements, Wallet history, or your Apple ID's list of subscriptions. Payments reach it in
four ways:

| Source | How it reaches YueJi | What it misses |
|---|---|---|
| Apple Pay | A Shortcuts personal automation on a Wallet transaction runs **Record Apple Pay payment** (`RecordApplePayIntent`) with the merchant and amount the trigger provides. | Payments not made with Apple Pay on this iPhone, such as a renewal billed later to a card saved with the merchant, and anything the automation didn't run for. |
| Bank / TNG | A Shortcuts automation you set up passes a notification's text to **Record bank and TNG notification** (`RecordTNGIntent`); YueJi parses it (`receiveTNG`). YueJi doesn't read notifications itself. | Notifications iOS doesn't hand to the automation, banks that don't notify, formats left for review, and transfers (kept for you to confirm, never counted as a subscription). |
| Manual | You add the expense. | Anything not entered. |
| Recurring schedules | A schedule with **Add an expense automatically when due** adds a scheduled entry on the due date (`postDue`). This is a forecast, not a payment. | — |

So detection is never complete, and every result is a suggestion.

## Possible subscriptions (suggestions)

`SubscriptionDetector` looks at real charges of mine: not added or matched by a schedule,
not paid by a friend, not fully refunded, and not confirmed bank transfers. Refunds,
cashback and settlements are never expense charges. Merchants group by `merchantIdentity`
(case, punctuation and "Sdn Bhd"-style suffixes ignored) and currency. The same price
charged twice within two days counts once.

Each merchant's charges split into runs. A run goes from the latest charge back through
earlier ones a cycle apart, preferring the same price. It allows one price change of up to
half, so a price rise doesn't create a second suggestion. Charges left over start their own
runs, so two subscriptions from one merchant (iCloud and Apple Music) stay apart. A cycle
is a calendar week (±2 days), month (±4) or year (±7). Adding a month to the 31st gives the
last day of shorter months, and the slack covers weekends and holidays. A run suggests:

- a **cycle seen in its charges**: two charges (three for weekly, or across a price
  change), with the billing day taken from the commonest day (month-end runs bill on the
  31st); or
- **one payment at a known service or biller** (whole words of the name, so "viu" never
  matches "Viuva"), only the merchant's latest and within 40 days. No cycle is assumed: the
  user chooses it.

Known billers (broadband, mobile, utilities) are labelled **Possible recurring bill**,
known services **Possible subscription**, and other regular charges **Possible recurring
payment**. A run whose next payment hasn't been seen shows **No recent payment detected**.
It isn't treated as cancelled: the channel may have missed it. Runs long past (4 weeks, 3
months or a year after the missed payment) aren't suggested.

The Recurring tab shows **Possible subscriptions**, hidden when empty. Each row shows the
service, amount, kind, cycle (or "Cycle to confirm") and estimated next payment, with
**Add** and **Not a subscription**. Hiding offers **Undo** for 8 seconds. **Hidden
suggestions** lists hidden ones to restore. Hidden suggestions (`Ledger.dismissedSubscriptions`)
are kept by series id (merchant, currency and first charge), so new charges don't bring them
back. A payment's detail page shows the same row. A payment recorded automatically that
looks like one adds a line to its notification, and tapping the notification opens the payment.

## Confirming: the recurring editor

**Add** opens the editor prefilled for review. Nothing is saved until the user saves:

- **Type**: Subscription or Bill (wording only).
- **Billing cycle**: preselected only when seen in the charges; after one payment it must
  be chosen.
- **Next payment (expected)**: the estimate from the latest payment and cycle. It can be
  changed, and can't be in the past. On the last day of a shorter month, **Bills on the last
  day of each month** keeps 31st billing (`billingDay`, so 31 → 28/29 Feb → 31 Mar).
- **Remind me**: off, on the day, or 1, 3 (default for new schedules) or 7 days before.
  Notification permission is asked for on saving. If notifications are off, the editor says
  reminders can't be delivered and links to the app's notification settings.
- **Add an expense automatically when due**: off by default ("only tracks it and reminds
  you"). On, it adds scheduled entries that don't prove a payment.

A schedule made from a suggestion starts at the next expected payment and keeps the
merchant (`merchantKey`), so the payment already recorded is never added again. Older
schedules keep working: no reminders, worded as bills.

## Reminders

`RenewalReminders` schedules local notifications at 9:00 on the reminder day, for the next
two expected payments of each followed schedule with a reminder. They work offline, subject
to notification permission and iOS delivery settings. They read, for example: "Spotify is
expected to renew in 3 days (3 Nov 2026) for RM 15.90." Bills say "about". With
notification details hidden, the name and amount are left out. A reminder never records an
expense and never says a payment went through.

Each expected payment has one identifier (`yueji.renewal.` + occurrence key), and `sync`
adds, replaces and removes to match the ledger. So launches, edits, matched payments,
backup restores and language changes never duplicate a reminder, and paused, cancelled or
deleted schedules lose theirs (delivered ones too). `sync` runs when the ledger is published,
when the app becomes active, after an automatic recording and after posting due schedules.

Tapping a reminder opens the schedule's details. From there you can change the next
payment date, change or turn off the reminder, pause, or mark it cancelled. Marking it
cancelled only stops tracking and reminders in YueJi; it doesn't cancel anything with the
provider. Changing the date starts a new generation of occurrence markers, so earlier
payments' markers are never reused.

## Real payments and scheduled entries

`reconcileRenewal` runs when Apple Pay or a bank notification records a payment. A sure
match needs all of: the schedule's merchant, the same currency, the same price (2% or 50
minor units), and a date in that payment's window (monthly −7 to +10 days, weekly −2 to +3,
yearly −14 to +21) with no other payment matched to it. With a sure match:

- a tracking schedule moves on to the next payment, and its reminders follow;
- an automatic schedule's scheduled entry for that date is replaced by the real payment, so
  it's counted once (only if the entry has no split, items, refund, claim, charges,
  settlement or notice);
- `postDue` links a payment already recorded for a date instead of adding an entry.

Anything unsure (another price, a name that only partly matches, more than one schedule)
changes nothing. The notification says "May be your Spotify renewal … Confirm it in
Recurring". A tracking schedule then shows **Possible payment found**, with **This is the
payment** (which adopts a new price) and **Not this one**. For an automatic schedule, the
scheduled entry and the payment appear in **Review possible duplicates**. Manual entries are
never merged automatically.

When an expected payment hasn't been seen, a tracking schedule shows **Waiting for the …
payment**, then **No recent payment detected** once its window has passed. The actions are
**Still active** (move on, nothing recorded), **Record it as an expense** (a scheduled
entry, which doesn't prove a payment) and **Mark as cancelled**.
