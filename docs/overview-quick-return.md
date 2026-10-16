# Overview transaction quick return

IMG_5222.MP4 shows repeated opening/returning from Overview's recent transactions, including a partly scaled detail overlay over Overview. The earlier Ledger navigation change did not cover this entry point: Overview still opted into matched-source zoom.

Remove Overview's zoom source/destination and the now-unused opt-in modifiers. Every transaction-detail route uses the standard NavigationStack push/pop, without waiting for a matched source to be restored. Navigation identities, editing, deletion and financial data are unchanged.

Local checks: project validation, Swift syntax, and source scan for remaining matched zoom calls. These do not measure device frame times. Verify on device: from Overview tap a recent transaction then immediately back; repeat, including an interrupted edge-back gesture, and compare with Ledger. Confirm normal scrolling, edit-sheet unsaved-change handling, and Reduce Motion. The recording identifies the remaining transition path; it does not establish a CPU-profiled root cause for every possible stall.
