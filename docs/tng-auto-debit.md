# TNG auto-debit notifications

Observed notification: `Auto-Debit Payment` / `You have paid RM11.90 for Apple Services.`

The known TNG title list now accepts this heading with the existing complete paid-MYR template. This also enables the existing title/body unwrapping for newline-joined or space-joined inputs. Separate title/body inputs could already match the generic payment grammar; this parser gap alone does not establish why the reported notification was missing. Check automation history and pending notices to distinguish delivery from recognition.

A native regression test covers the observed merchant and amount through the automation delivery path in all three layouts, replay without duplicate posting, and rejection of scheduled, failed, foreign-currency and multiple-amount inputs. Windows project and Swift syntax checks pass; native execution requires Xcode. No historical transaction is inserted or silently reprocessed by this change.

Follow-up screenshots show the automation passes Body only, and YueJi logged an ignored invocation at 15:25. This is evidence of a call reaching the app at that time, but the ignored input was not retained, so its exact content and association with the payment cannot be recovered. Coverage now also includes the body-only layout and a saved activity outcome. The activity screen exposes existing processing details for all outcomes, including ignored entries; previously only failed entries had a disclosure. This improves diagnosis without retaining OTP/advertising bodies or changing accounting. The installed version and a native reproduction are still needed to establish the omission's root cause.
