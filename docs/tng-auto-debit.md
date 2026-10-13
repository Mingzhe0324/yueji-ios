# TNG auto-debit notifications

Observed notification: `Auto-Debit Payment` / `You have paid RM11.90 for Apple Services.`

The known TNG title list now accepts this heading with the existing complete paid-MYR template. This also enables the existing title/body unwrapping for newline-joined or space-joined inputs. Separate title/body inputs could already match the generic payment grammar; this parser gap alone does not establish why the reported notification was missing. Check automation history and pending notices to distinguish delivery from recognition.

A native regression test covers the observed merchant and amount through the automation delivery path in all three layouts, replay without duplicate posting, and rejection of scheduled, failed, foreign-currency and multiple-amount inputs. Windows project and Swift syntax checks pass; native execution requires Xcode. No historical transaction is inserted or silently reprocessed by this change.
