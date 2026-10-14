# Native system surfaces

Use the system Liquid Glass APIs available since iOS 26 on newer systems as well, rather than introducing a separate simulated iOS 27 theme. Primary and secondary buttons already use native glass styles; navigation and sheet transitions remain system-owned.

Floating notification cards now use one regular glass surface, with no extra custom shadow or border. Increased Contrast, Reduce Transparency and older systems retain the opaque readable surface. The gesture controller, auto-dismiss timing, touch suppression and Reduce Motion behaviour are unchanged. The toolbar More glyph is ellipsis, allowing the toolbar to supply its own enclosing control shape.

On iOS 26 and later, sheets use the system default presentation material and curvature. Reduce Transparency keeps the explicit opaque system background. Form content continues using grouped system colours for readability; no transparency is added behind financial data.

Reference: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

Validation: local project integrity and Swift syntax only. Native build, notification swipe/tap checks, dirty-editor dismissal and visual review on iOS 27 remain required. No new CI stages or test timeouts are introduced.
