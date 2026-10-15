# Receipt rounding and keyboard verification

Receipt rounding is an optional signed minor-unit adjustment after separately calculating SST and service on the subtotal. Blank or zero preserves the old calculation. Entry creation/editing and the saved-item editor share the field; changing it participates in unsaved-change confirmation. The user explicitly applies the calculated payment total. Details and CSV expose rounding separately. Backups without rounding decode unchanged. Existing allocation uses the final payment, retaining base item prices and every cent; refund/repayment/settlement edit protections remain.

Added native regression coverage for positive/negative/zero rounding, ownership totals, backup round trips, legacy decoding, invalid/overflow totals and currency precision. CSV coverage includes the appended rounding column. Native execution requires macOS/Xcode.

In build-test (8).log, 271 unit tests passed and two of four UI tests failed at the five-second keyboard dismissal check. Both later failure hierarchies retain the editor and entered values but contain neither keyboard nor toolbar Done. Live accessibility queries consumed several seconds each. This supports a polling-budget issue, without proving exactly when the keyboard disappeared. The helper now examines one snapshot per poll and allows 15 seconds locally; unavailable snapshots still fail, and both keyboard and toolbar Done must be absent. No test is skipped, no repeated Done tap is added, and CI stage limits are unchanged.

Snapshot API: https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding
