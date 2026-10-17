# Optional transaction locations

New manual entries obtain a one-shot location after the user has granted When In Use permission through Use current location. No launch permission prompt or background tracking is added. Existing entries and restored drafts keep their saved location. Failure does not block saving; retry and manual name/address entry remain available.

Location is optional Codable data on expenses, pending notices, delivery inputs and editor snapshots. Older records decode without it. Backups preserve it. Duplicating a purchase intentionally drops the old location. Changing a manually entered name/address clears the previous coordinate; Maps can search the edited text instead.

Automatic payment intents only attach an already available fix less than 30 seconds old with accuracy at most 100 metres, after authorization. They do not request permission or wait for GPS. Supplied old transaction times do not receive current coordinates. Delivery retries preserve the original metadata and do not overwrite previously recorded entries. A recording location is not proof of the merchant's physical location.

The form uses a small progress indicator and a 0.25-second content transition, respecting Reduce Motion. Location requests cancel when the field disappears, is edited, or removed. Requests time out after 20 seconds; canceled geocoding callbacks cannot overwrite a newer choice.

Validation: project checks and Swift tree-sitter parsing passed on Windows. Native XCTest cases cover legacy/backup round trips, coordinate bounds, draft preservation, duplicate purchase behavior and delivery retry behavior. Xcode compilation, native tests, permission denial, approximate location and device animation checks still require macOS/iPhone validation.
