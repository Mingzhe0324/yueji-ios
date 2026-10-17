# Apple merchant details

On iOS 18+, the in-app location map offers Apple's native place detail sheet.
Choose a particular search result, then tap Place details & photos. Apple
controls the card's contents, available images, attribution and native transitions.
No Google service, API key, standalone photo downloader, or paid-photo setup is added.
This does not supply a custom photo thumbnail for the ledger or guarantee a storefront image.

The chosen MKMapItem identifier is stored as optional applePlaceID with the
expense location and therefore survives drafts/backups. Old data decodes without
it. Manual name/address changes, map-center choices and fresh GPS fixes do not
retain a previous merchant identifier. Coordinates alone are never converted
into a guessed merchant. Viewing a search result in a read-only map is a preview;
persisting a new merchant selection requires editing and saving the location.

The native card requests the specific saved identifier using MKMapItemRequest.
Replacement/dismissal cancels the request and stale completions are ignored.
Failures permit retry without modifying the ledger. iOS 17 retains existing map
and search features without the card. Photos remain within Apple's UI, rather
than being extracted or copied into backups.

Validation: Windows project and syntax checks; native API compilation and card
presentation, no-photo merchants, network failure, dismissal and Reduce Motion
still require macOS/iPhone verification.

References:
- https://developer.apple.com/documentation/swiftui/view/mapitemdetailsheet(item:displaysmap:)
- https://developer.apple.com/documentation/mapkit/mkmapitemrequest/init(mapitemidentifier:)
- https://developer.apple.com/videos/play/wwdc2024/10097/
