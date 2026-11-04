import SwiftUI
import WebKit

struct ObservedStock: Identifiable, Hashable {
    let symbol: String
    let name: String
    var id: String { symbol }
    var market: String { String(symbol.split(separator: ":").first ?? "") }

    static func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.range(of: "^[A-Z0-9]{2,12}:[A-Z0-9][A-Z0-9._-]{0,24}$", options: .regularExpression) != nil else { return nil }
        return value
    }
    static func saved(_ value: String) -> [ObservedStock] {
        var seen = Set<String>()
        return value.split(separator: "\n").compactMap { line in
            guard let symbol = normalized(String(line)), seen.insert(symbol).inserted else { return nil }
            return examples.first { $0.symbol == symbol } ?? ObservedStock(symbol: symbol, name: symbol)
        }
    }
    // A curated starting list, not a live popularity ranking or a recommendation.
    static let examples: [ObservedStock] = [
        .init(symbol: "NASDAQ:NVDA", name: "NVIDIA · 英伟达"),
        .init(symbol: "NASDAQ:AAPL", name: "Apple · 苹果"),
        .init(symbol: "NASDAQ:MSFT", name: "Microsoft · 微软"),
        .init(symbol: "NASDAQ:TSLA", name: "Tesla · 特斯拉"),
        .init(symbol: "NASDAQ:AMZN", name: "Amazon · 亚马逊"),
        .init(symbol: "NASDAQ:GOOGL", name: "Alphabet · Google"),
        .init(symbol: "NASDAQ:META", name: "Meta"),
        .init(symbol: "NASDAQ:AMD", name: "AMD"),
        .init(symbol: "NASDAQ:AVGO", name: "Broadcom · 博通"),
        .init(symbol: "NASDAQ:PLTR", name: "Palantir"),
        .init(symbol: "NYSE:TSM", name: "TSMC ADR · 台积电"),
        .init(symbol: "NYSE:BRK.B", name: "Berkshire Hathaway"),
        .init(symbol: "MYX:MAYBANK", name: "Maybank · 马银行"),
        .init(symbol: "MYX:PBBANK", name: "Public Bank · 大众银行"),
        .init(symbol: "MYX:CIMB", name: "CIMB"),
        .init(symbol: "MYX:TENAGA", name: "Tenaga Nasional · 国能"),
        .init(symbol: "MYX:IHH", name: "IHH Healthcare"),
        .init(symbol: "MYX:99SMART", name: "99 Speed Mart"),
        .init(symbol: "HKEX:700", name: "Tencent · 腾讯"),
        .init(symbol: "HKEX:9988", name: "Alibaba · 阿里巴巴"),
        .init(symbol: "HKEX:1810", name: "Xiaomi · 小米"),
        .init(symbol: "HKEX:3690", name: "Meituan · 美团"),
        .init(symbol: "HKEX:1211", name: "BYD · 比亚迪"),
        .init(symbol: "SSE:600519", name: "Kweichow Moutai · 贵州茅台"),
        .init(symbol: "SZSE:300750", name: "CATL · 宁德时代"),
        .init(symbol: "SZSE:002594", name: "BYD A · 比亚迪 A 股"),
        .init(symbol: "TWSE:2330", name: "TSMC · 台积电"),
        .init(symbol: "TSE:7203", name: "Toyota · 丰田"),
        .init(symbol: "SGX:D05", name: "DBS · 星展")
    ]
}

struct InvestmentWatchView: View {
    @AppStorage("investment.watchlist.v1") private var watchlist = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var market = "all"
    @Namespace private var cards
    private var saved: [ObservedStock] { ObservedStock.saved(watchlist) }
    private var examples: [ObservedStock] {
        ObservedStock.examples.filter { stock in
            (market == "all" || stock.market == market || (market == "US" && ["NASDAQ", "NYSE"].contains(stock.market))) &&
            (search.isEmpty || stock.name.localizedCaseInsensitiveContains(search) || stock.symbol.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(tr("投资观察", "Market watch", "Pantau pasaran"), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.title2.bold())
                    Text(tr("关注公司，查看行情", "Follow companies. Explore their charts.", "Ikuti syarikat. Terokai carta."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label(tr("免费图表 · TradingView", "Free charts · TradingView", "Carta percuma · TradingView"), systemImage: "globe")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8).ledgerGlass()
                }.padding(.vertical, 8)
                Text(tr("行情由 TradingView 提供；部分市场延迟或不可用，以图表标示为准。示例清单不是实时热门榜或买入建议。自选仅保存在此设备。", "Charts are provided by TradingView. Some markets are delayed or unavailable; check the chart labels. This curated list is not a live popularity ranking or a buy recommendation. Watchlists stay on this device.", "Carta disediakan oleh TradingView. Sesetengah pasaran tertunda atau tidak tersedia; semak label carta. Senarai ini bukan kedudukan populariti langsung atau cadangan beli. Senarai pantau disimpan pada peranti ini."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("我的自选", "Watchlist", "Senarai pantau")) {
                if saved.isEmpty {
                    Label(tr("打开股票，点星号加入自选", "Open a stock and tap the star to follow", "Buka saham dan ketik bintang untuk ikuti"), systemImage: "star")
                        .foregroundStyle(.secondary)
                }
                ForEach(saved) { stock in stockLink(stock, source: "saved") }
                    .onDelete { offsets in
                        var values = saved
                        values.remove(atOffsets: offsets)
                        watchlist = values.map(\.symbol).joined(separator: "\n")
                    }
            }
            Section(tr("浏览股票", "Explore stocks", "Terokai saham")) {
                Picker(tr("市场", "Market", "Pasaran"), selection: $market) {
                    Text(tr("全部", "All", "Semua")).tag("all")
                    Text(tr("美股", "US", "AS")).tag("US")
                    Text(tr("马股", "Malaysia", "Malaysia")).tag("MYX")
                    Text(tr("港股", "Hong Kong", "Hong Kong")).tag("HKEX")
                    Text(tr("上海", "Shanghai", "Shanghai")).tag("SSE")
                    Text(tr("深圳", "Shenzhen", "Shenzhen")).tag("SZSE")
                    Text(tr("台湾", "Taiwan", "Taiwan")).tag("TWSE")
                    Text(tr("日本", "Japan", "Jepun")).tag("TSE")
                    Text(tr("新加坡", "Singapore", "Singapura")).tag("SGX")
                }
                ForEach(examples) { stock in stockLink(stock, source: "example") }
                if examples.isEmpty {
                    Text(tr("清单中没有匹配项目，可输入交易所代码查看。", "No matches in this list. Enter an exchange-qualified symbol to explore.", "Tiada padanan. Masukkan kod saham dengan bursa untuk melihat."))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if let symbol = ObservedStock.normalized(search) {
                    stockLink(ObservedStock(symbol: symbol, name: symbol), source: "custom")
                }
                Text(tr("支持输入交易所:代码，例如 NASDAQ:NVDA、HKEX:700、MYX:MAYBANK。代码格式有效不代表图表一定支持。", "Enter EXCHANGE:SYMBOL, such as NASDAQ:NVDA, HKEX:700 or MYX:MAYBANK. A valid format does not guarantee chart availability.", "Masukkan BURSA:KOD seperti NASDAQ:NVDA, HKEX:700 atau MYX:MAYBANK. Format sah tidak menjamin ketersediaan carta."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.yuejiListSurface()
            .navigationTitle(tr("投资观察", "Market watch", "Pantau pasaran"))
            .searchable(text: $search, prompt: tr("公司或交易所:代码", "Company or EXCHANGE:SYMBOL", "Syarikat atau BURSA:KOD"))
            .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.2), value: market)
    }
    private func stockLink(_ stock: ObservedStock, source: String) -> some View {
        NavigationLink {
            StockChartView(stock: stock).yuejiZoom(id: source + stock.id, namespace: cards)
        } label: {
            HStack(spacing: 12) {
                Text(String(stock.symbol.split(separator: ":").last ?? "").prefix(4))
                    .font(.caption.bold()).frame(width: 48, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(stock.name).font(.headline)
                    Text(stock.symbol).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if saved.contains(where: { $0.symbol == stock.symbol }) { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel(tr("已关注", "Following", "Diikuti")) }
            }.padding(.vertical, 4).yuejiZoomSource(id: source + stock.id, namespace: cards)
        }
    }
}

private struct StockChartView: View {
    let stock: ObservedStock
    @AppStorage("investment.watchlist.v1") private var watchlist = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @State private var reload = UUID()
    @State private var failed = false
    private var following: Bool { ObservedStock.saved(watchlist).contains { $0.symbol == stock.symbol } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(stock.name).font(.title2.bold())
                Text(stock.symbol).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                if phase == .active {
                    TradingStockChart(symbol: stock.symbol, dark: scheme == .dark, failed: $failed)
                        .id(stock.symbol + (scheme == .dark ? "dark" : "light") + reload.uuidString)
                        .frame(height: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    Color.clear.frame(height: 520)
                }
                if failed {
                    Label(tr("图表加载失败，请重试或打开来源页面。", "Chart could not load. Retry or open the source page.", "Carta gagal dimuatkan. Cuba lagi atau buka halaman sumber."), systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                }
                Text(tr("价格、更新时间及延迟状态请查看图表。网页加载完成不代表行情是实时的；不可用时不会补造价格。", "Read prices, timestamps and delay status in the chart. A loaded page does not imply real-time data. Missing prices are never fabricated.", "Lihat harga, masa dan status kelewatan pada carta. Halaman dimuatkan tidak bermakna data masa nyata. Harga yang tiada tidak direka."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { failed = false; reload = UUID() } label: {
                        Label(tr("重新加载", "Reload", "Muat semula"), systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Link("TradingView ↗", destination: TradingStockChart.sourceURL(stock.symbol))
                }.buttonStyle(.bordered)
                Label(tr("本版未启用 AI 投资建议", "AI investment advice is not enabled", "Nasihat pelaburan AI belum diaktifkan"), systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(tr("打开图表会连接 TradingView，其服务和隐私政策适用。不会发送月记账本内容。", "Charts connect to TradingView and are subject to its service and privacy policies. Your ledger contents are not sent.", "Carta bersambung ke TradingView dan tertakluk pada dasar perkhidmatan dan privasinya. Kandungan lejar tidak dihantar."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle(tr("股票详情", "Stock details", "Butiran saham"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        var symbols = ObservedStock.saved(watchlist).map(\.symbol)
                        if following { symbols.removeAll { $0 == stock.symbol } }
                        else { symbols.append(stock.symbol) }
                        watchlist = symbols.joined(separator: "\n")
                    } label: { Image(systemName: following ? "star.fill" : "star") }
                        .accessibilityLabel(following ? tr("取消关注", "Unfollow", "Nyahikuti") : tr("加入自选", "Follow stock", "Ikuti saham"))
                }
            }
    }
}

private struct TradingStockChart: UIViewRepresentable {
    let symbol: String
    let dark: Bool
    @Binding var failed: Bool
    static func sourceURL(_ symbol: String) -> URL {
        var url = URLComponents(string: "https://www.tradingview.com/chart/")!
        url.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        return url.url!
    }
    func makeCoordinator() -> Coordinator { Coordinator(failed: $failed) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        let options: [String: Any] = ["autosize": true, "symbol": symbol, "interval": "D",
            "timezone": "Etc/UTC", "theme": dark ? "dark" : "light", "style": "1", "locale": "en",
            "allow_symbol_change": false, "calendar": false, "hide_side_toolbar": true,
            "support_host": "https://www.tradingview.com"]
        guard ObservedStock.normalized(symbol) == symbol,
              let data = try? JSONSerialization.data(withJSONObject: options),
              let json = String(data: data, encoding: .utf8) else { return view }
        // Official embed only. No DOM extraction, quote scraping or AI bridge.
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;height:100%;background:\(dark ? "#131722" : "#ffffff")}a{color:#2962ff} .tradingview-widget-copyright{font:12px sans-serif;text-align:center;padding:6px}</style></head><body>
        <div class="tradingview-widget-container" style="height:100%;width:100%">
        <div class="tradingview-widget-container__widget" style="height:calc(100% - 32px);width:100%"></div>
        <div class="tradingview-widget-copyright"><a href="https://www.tradingview.com/" target="_blank" rel="noopener nofollow">Track all markets on TradingView</a></div>
        <script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js" onerror="document.querySelector('.tradingview-widget-container__widget').textContent='Chart unavailable. Please reload or open TradingView.'" async>\(json)</script>
        </div></body></html>
        """, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var failed: Binding<Bool>
        init(failed: Binding<Bool>) { self.failed = failed }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed.wrappedValue = true }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                if url.scheme == "https" { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, url.scheme == "https" { UIApplication.shared.open(url) }
            return nil
        }
    }
}
