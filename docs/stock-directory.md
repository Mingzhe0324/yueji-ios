# Stock directory and company logos

The 80 built-in stocks have bundled company icons, exchange-qualified identifiers,
sector, industry, company website, and links to TradingView profiles, financials and news.
These are directory records, not live prices or evidence sent to Gemini.
The four official financial importers retain their separate coverage limits.
Custom symbols have a symbol placeholder and an explicit missing-directory message.

Company icons and classifications come from the corresponding public TradingView symbol
pages, checked on 2026-11-04. Source URLs and check dates are retained in
`YueJi/Assets.xcassets/StockDirectory.dataset/directory.json`; logos identify their
respective companies and do not imply endorsement. The UI attributes TradingView.
Images are bundled, so list display does not send a watchlist to a logo service.
External links still require internet and can become unavailable.

Run `node scripts/check_stock_directory.mjs` to verify complete built-in coverage.
`node scripts/import_stock_directory.mjs` explicitly refreshes the directory from
public pages; it does not run in the app or collect market quotes. Review imported
identity, classifications, logo and URL changes before committing. `--resume` keeps
already imported records and only fills missing entries.

Updated stale built-in symbols and saved watchlists:
- Walmart: NYSE:WMT → NASDAQ:WMT. Source: https://stock.walmart.com/sec-filings/all-sec-filings/content/0000104169-25-000177/pressrelease-transfertonas.htm
- Roche: SIX:ROG → SIX:ROP. Source: https://www.roche.com/investors/updates/inv-update-2026-03-16

Research history preserves original identifiers and dates. Swift/XCTest/native
asset-catalog compilation must still run on macOS; Windows checks are structural.
