import SwiftUI
import WebKit
import CryptoKit

struct ObservedStock: Identifiable, Hashable {
    let symbol: String
    let name: String
    var id: String { symbol }
    var market: String { String(symbol.split(separator: ":").first ?? "") }
    // Mirrors the default official importer; availability still depends on deployment and source health.
    var hasOfficialImporter: Bool { ["MYX:MAYBANK", "MYX:99SMART", "MYX:GAMUDA", "MYX:HLBANK"].contains(symbol) }
    var officialSourceURL: URL? {
        let sources = [
            "MYX:MAYBANK": "https://maybank.listedcompany.com/newsroom.html/cat/7648",
            "MYX:99SMART": "https://99speedmart.com.my/financial-information/",
            "MYX:GAMUDA": "https://gamuda.listedcompany.com/financial_information.html",
            "MYX:HLBANK": "https://www.hlb.com.my/en/personal-banking/news-updates/hlb-announces-fy2026-results.html",
            "MYX:PBBANK": "https://www.publicbankgroup.com/investor-relations/five-year-financial-highlights/group-financial-highlights/",
            "MYX:CIMB": "https://www.cimb.com/en/investor-relations/financial-information/cimb-group.html",
            "MYX:TENAGA": "https://www.tnb.com.my/suppliers-investors-media-relations/financial-info/",
            "MYX:IHH": "https://www.ihhhealthcare.com/investors/financial-information/quarterly-results",
            "MYX:MRDIY": "https://corporate.mrdiy.com/highlights.html",
            "MYX:INARI": "https://www.inari-amertron.com/financial-results/"
        ]
        return sources[symbol].flatMap { URL(string: $0) }
    }

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
        .init(symbol: "SGX:D05", name: "DBS · 星展"),
        .init(symbol: "NASDAQ:NFLX", name: "Netflix · 奈飞"),
        .init(symbol: "NASDAQ:COST", name: "Costco · 好市多"),
        .init(symbol: "NASDAQ:INTC", name: "Intel · 英特尔"),
        .init(symbol: "NASDAQ:QCOM", name: "Qualcomm · 高通"),
        .init(symbol: "NASDAQ:PDD", name: "PDD Holdings · 拼多多"),
        .init(symbol: "NASDAQ:COIN", name: "Coinbase"),
        .init(symbol: "NYSE:JPM", name: "JPMorgan Chase · 摩根大通"),
        .init(symbol: "NYSE:V", name: "Visa"),
        .init(symbol: "NYSE:WMT", name: "Walmart · 沃尔玛"),
        .init(symbol: "NYSE:KO", name: "Coca-Cola · 可口可乐"),
        .init(symbol: "NYSE:LLY", name: "Eli Lilly · 礼来"),
        .init(symbol: "NYSE:SE", name: "Sea · 冬海"),
        .init(symbol: "MYX:HLBANK", name: "Hong Leong Bank · 丰隆银行"),
        .init(symbol: "MYX:PETGAS", name: "Petronas Gas · 国油气体"),
        .init(symbol: "MYX:MRDIY", name: "MR D.I.Y."),
        .init(symbol: "MYX:INARI", name: "Inari Amertron · 益纳利"),
        .init(symbol: "MYX:GAMUDA", name: "Gamuda · 金务大"),
        .init(symbol: "HKEX:9618", name: "JD.com · 京东"),
        .init(symbol: "HKEX:9999", name: "NetEase · 网易"),
        .init(symbol: "HKEX:5", name: "HSBC · 汇丰"),
        .init(symbol: "HKEX:388", name: "HKEX · 香港交易所"),
        .init(symbol: "SSE:601318", name: "Ping An · 中国平安"),
        .init(symbol: "SSE:600036", name: "China Merchants Bank · 招商银行"),
        .init(symbol: "SZSE:000333", name: "Midea · 美的集团"),
        .init(symbol: "TWSE:2317", name: "Hon Hai · 鸿海"),
        .init(symbol: "TWSE:2454", name: "MediaTek · 联发科"),
        .init(symbol: "TSE:6758", name: "Sony · 索尼"),
        .init(symbol: "TSE:9984", name: "SoftBank Group · 软银集团"),
        .init(symbol: "TSE:7974", name: "Nintendo · 任天堂"),
        .init(symbol: "SGX:O39", name: "OCBC · 华侨银行"),
        .init(symbol: "SGX:U11", name: "UOB · 大华银行"),
        .init(symbol: "SGX:Z74", name: "Singtel · 新加坡电信"),
        .init(symbol: "LSE:AZN", name: "AstraZeneca · 阿斯利康"),
        .init(symbol: "LSE:SHEL", name: "Shell · 壳牌"),
        .init(symbol: "LSE:HSBA", name: "HSBC · 汇丰（伦敦）"),
        .init(symbol: "XETR:SAP", name: "SAP · 思爱普"),
        .init(symbol: "XETR:SIE", name: "Siemens · 西门子"),
        .init(symbol: "XETR:ALV", name: "Allianz · 安联"),
        .init(symbol: "EURONEXT:MC", name: "LVMH · 路威酩轩"),
        .init(symbol: "EURONEXT:OR", name: "L’Oréal · 欧莱雅"),
        .init(symbol: "EURONEXT:ASML", name: "ASML · 阿斯麦"),
        .init(symbol: "SIX:NESN", name: "Nestlé · 雀巢"),
        .init(symbol: "SIX:ROG", name: "Roche · 罗氏"),
        .init(symbol: "TSX:SHOP", name: "Shopify"),
        .init(symbol: "TSX:RY", name: "Royal Bank of Canada · 加拿大皇家银行"),
        .init(symbol: "ASX:BHP", name: "BHP · 必和必拓"),
        .init(symbol: "ASX:CBA", name: "Commonwealth Bank · 澳洲联邦银行"),
        .init(symbol: "NSE:RELIANCE", name: "Reliance Industries · 信实工业"),
        .init(symbol: "NSE:TCS", name: "Tata Consultancy Services · 塔塔咨询"),
        .init(symbol: "KRX:005930", name: "Samsung Electronics · 三星电子"),
        .init(symbol: "KRX:000660", name: "SK Hynix · SK 海力士")
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
            Section(tr("研究工具", "Research tools", "Alat penyelidikan")) {
                NavigationLink { StockComparisonPicker() } label: {
                    Label(tr("对比 2–3 只股票", "Compare 2–3 stocks", "Bandingkan 2–3 saham"), systemImage: "square.split.2x2")
                }
                NavigationLink { ResearchHistoryView() } label: {
                    Label(tr("研究历史", "Research history", "Sejarah penyelidikan"), systemImage: "clock.arrow.circlepath")
                }
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
                    Text(tr("英国", "United Kingdom", "United Kingdom")).tag("LSE")
                    Text(tr("德国", "Germany", "Jerman")).tag("XETR")
                    Text(tr("泛欧交易所", "Euronext", "Euronext")).tag("EURONEXT")
                    Text(tr("瑞士", "Switzerland", "Switzerland")).tag("SIX")
                    Text(tr("加拿大", "Canada", "Kanada")).tag("TSX")
                    Text(tr("澳大利亚", "Australia", "Australia")).tag("ASX")
                    Text(tr("印度", "India", "India")).tag("NSE")
                    Text(tr("韩国", "South Korea", "Korea Selatan")).tag("KRX")
                }
                ForEach(examples) { stock in stockLink(stock, source: "example") }
                if examples.isEmpty {
                    Text(tr("清单中没有匹配项目，可输入交易所代码查看。", "No matches in this list. Enter an exchange-qualified symbol to explore.", "Tiada padanan. Masukkan kod saham dengan bursa untuk melihat."))
                        .foregroundStyle(.secondary)
                }
            }
            Section(tr("查找更多股票", "Find more stocks", "Cari lebih banyak saham")) {
                Link(destination: URL(string: "https://www.tradingview.com/screener/")!) {
                    Label(tr("在 TradingView 查找全球股票 ↗", "Find global stocks on TradingView ↗", "Cari saham global di TradingView ↗"), systemImage: "globe")
                }
                Text(tr("将在浏览器打开股票筛选器。找到交易所和代码后，回到这里输入并收藏。上方搜索只筛选内置清单；外部能找到的股票也可能无法显示嵌入图表。", "Opens the stock screener in your browser. Return with the exchange and symbol to open and follow a stock here. Search above filters the built-in list only; stocks found externally may still lack an embedded chart.", "Membuka penyaring saham dalam pelayar. Kembali dengan bursa dan kod untuk membuka dan mengikuti saham di sini. Carian di atas hanya menapis senarai terbina dalam; saham yang ditemui di luar mungkin tiada carta terbenam."))
                    .font(.caption).foregroundStyle(.secondary)
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
                if let source = stock.officialSourceURL {
                    Link(destination: source) {
                        Label(tr("公司官方财务资料 ↗", "Official financial sources ↗", "Sumber kewangan rasmi ↗"), systemImage: "doc.text.magnifyingglass")
                    }
                }
                Text(stock.hasOfficialImporter
                     ? tr("已提供自动读取适配；需恢复云端部署后使用。资料范围为官方网页摘要，仍可能加载失败。", "Automatic importer available; requires cloud deployment. Covers official page summaries and may fail to load.", "Pengimport automatik tersedia; memerlukan penggunaan awan. Meliputi ringkasan halaman rasmi dan mungkin gagal dimuatkan.")
                     : tr("这只股票尚未接入自动财务分析；图表可用不代表 AI 已有资料。", "Automatic financial analysis is not connected for this stock. A chart does not mean AI has its data.", "Analisis kewangan automatik belum disambungkan untuk saham ini. Carta tidak bermakna AI mempunyai datanya."))
                    .font(.caption).foregroundStyle(.secondary)
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
                NavigationLink {
                    StockResearchView(stock: stock)
                } label: {
                    Label(tr("AI 公司研究 · 个人试用", "AI company research · Personal preview", "Penyelidikan syarikat AI · Pratonton peribadi"), systemImage: "sparkles")
                }.buttonStyle(.bordered)
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

private struct StockResearchReport: Decodable {
    let symbol: String
    let symbols: [String]?
    let generatedAt: String
    let html: String
    let text: String?
}

private struct StockResearchView: View {
    let symbols: [String]
    init(stock: ObservedStock) { symbols = [stock.symbol] }
    init(symbols: [String]) { self.symbols = symbols }
    @ObservedObject private var account = CloudAccount.shared
    @Environment(\.scenePhase) private var phase
    @State private var report: StockResearchReport?
    @State private var error = ""
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var saveMessage = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(symbols.joined(separator: " / ")).font(.headline)
            Text(tr("点击后自动获取官方网页，再由 Gemini 分析，不需要上传文件。当前适配 Maybank、99 Speed Mart、Gamuda 和 Hong Leong Bank，需部署新版后生效；丰隆银行为固定 FY2026 年度公告。其他股票逐步接入。仅供配置的个人账号使用，不上传账本。", "Fetches official pages for Gemini analysis; no upload. Importers cover Maybank, 99 Speed Mart, Gamuda and Hong Leong Bank after deploying this version. HLB uses a fixed FY2026 annual announcement. Other stocks are being added. Personal account only; no ledger upload.", "Mendapatkan halaman rasmi untuk analisis Gemini; tiada muat naik. Pengimport meliputi Maybank, 99 Speed Mart, Gamuda dan Hong Leong Bank selepas versi ini digunakan. HLB menggunakan pengumuman tahunan FY2026 tetap. Saham lain ditambah berperingkat. Akaun peribadi sahaja; lejar tidak dihantar."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    report = nil; error = ""; saveMessage = ""; running = true
                    task = Task { @MainActor in
                        defer { running = false }
                        do {
                            let scope = account.researchHistoryScope
                            let data = try await account.researchStock(symbols: symbols)
                            try Task.checkCancellation()
                            let value = try JSONDecoder().decode(StockResearchReport.self, from: data)
                            guard (value.symbols ?? [value.symbol]) == symbols, value.html.utf8.count <= 300000,
                                  scope != nil, scope == account.researchHistoryScope else { throw CloudFailure.invalidResponse }
                            report = value
                        } catch is CancellationError { }
                        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                    }
                } label: {
                    Label(tr("自动获取并分析", "Fetch and analyze", "Dapatkan dan analisis"), systemImage: "sparkle.magnifyingglass")
                }.buttonStyle(.borderedProminent).disabled(running)
                if running {
                    ProgressView()
                    Button(tr("取消", "Cancel", "Batal")) { task?.cancel() }
                }
            }
            if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
            if let report {
                Text(tr("生成时间（不是行情时间）：", "Generated at (not quote time): ", "Dijana pada (bukan masa harga): ") + report.generatedAt)
                    .font(.caption).foregroundStyle(.secondary)
                if let text = report.text, !text.isEmpty {
                    Button(tr("保存到研究历史", "Save to research history", "Simpan ke sejarah")) {
                        do {
                            guard let scope = account.researchHistoryScope else { throw CloudFailure.session }
                            try ResearchHistory.save(symbols: symbols, text: text, generatedAt: report.generatedAt, scope: scope)
                            saveMessage = tr("已保存原文，保留 30 天", "Original text saved for 30 days", "Teks asal disimpan selama 30 hari")
                        } catch { self.error = error.localizedDescription }
                    }.disabled(!saveMessage.isEmpty)
                }
                if !saveMessage.isEmpty { Text(saveMessage).font(.caption).foregroundStyle(.secondary) }
                ResearchWebView(html: report.html).id(report.generatedAt)
            } else {
                Spacer()
                Text(tr("分析会列出机会、风险、资料日期和下一步条件。评分是研究评价，不是上涨概率；缺少关键资料时不计算综合分。当前不是实时行情或后台持续监控。", "Analysis lists opportunities, risks, evidence dates and next steps. Ratings are research judgments, not winning probabilities; incomplete evidence means no overall score. This is not live pricing or background monitoring.", "Analisis menyenaraikan peluang, risiko, tarikh bukti dan langkah seterusnya. Penilaian bukan kebarangkalian untung; bukti tidak lengkap bermakna tiada skor keseluruhan. Bukan harga langsung atau pemantauan latar."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding().navigationTitle(tr("AI 公司研究", "AI company research", "Penyelidikan syarikat AI"))
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { task?.cancel(); report = nil }
            .onChange(of: account.researchHistoryScope) { _, _ in task?.cancel(); report = nil; error = ""; saveMessage = "" }
            .onChange(of: phase) { _, value in
                if value != .active { task?.cancel(); report = nil }
            }
    }
}

struct ResearchHistoryEntry: Codable, Identifiable {
    let id: UUID
    let symbols: [String]
    let text: String
    let generatedAt: String
    let savedAt: Date
}

enum ResearchHistory {
    static func retained(_ values: [ResearchHistoryEntry], now: Date = Date()) -> [ResearchHistoryEntry] {
        Array(values.filter { entry in
            let age = now.timeIntervalSince(entry.savedAt)
            return age >= 0 && age < 30 * 86400 && entry.text.utf8.count <= 100000 &&
                (1...3).contains(entry.symbols.count) && entry.symbols.allSatisfy { ObservedStock.normalized($0) == $0 }
        }.sorted { $0.savedAt > $1.savedAt }.prefix(20))
    }
    static func fileName(scope: String) -> String {
        SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
    private static func location(scope: String) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CompanyResearchHistory", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var options = URLResourceValues(); options.isExcludedFromBackup = true
        try directory.setResourceValues(options)
        return root.appendingPathComponent(fileName(scope: scope))
    }
    static func load(scope: String) throws -> [ResearchHistoryEntry] {
        let url = try location(scope: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 3000000 else { throw CloudFailure.invalidResponse }
        let original = try JSONDecoder().decode([ResearchHistoryEntry].self, from: data)
        let values = retained(original)
        if values.count != original.count { try write(values, scope: scope) }
        return values
    }
    static func write(_ values: [ResearchHistoryEntry], scope: String) throws {
        try JSONEncoder().encode(retained(values)).write(to: location(scope: scope), options: [.atomic, .completeFileProtection])
    }
    static func save(symbols: [String], text: String, generatedAt: String, scope: String) throws {
        var values = try load(scope: scope)
        values.removeAll { $0.symbols == symbols && $0.generatedAt == generatedAt }
        values.insert(.init(id: UUID(), symbols: symbols, text: text, generatedAt: generatedAt, savedAt: Date()), at: 0)
        try write(values, scope: scope)
    }
}

private struct ResearchHistoryView: View {
    @ObservedObject private var account = CloudAccount.shared
    @State private var entries: [ResearchHistoryEntry] = []
    @State private var error = ""
    var body: some View {
        List {
            Text(tr("仅保存你主动保存的研究原文，供当前账号回看。此设备最多保留 20 条、30 天；不自动重新分析，不代表最新建议。", "Only research text you choose to save, for this account to reread. Up to 20 entries for 30 days on this device; no automatic reanalysis or current advice.", "Hanya teks yang anda pilih untuk simpan, bagi akaun ini. Sehingga 20 rekod selama 30 hari pada peranti ini; bukan analisis semula automatik atau nasihat terkini."))
                .font(.caption).foregroundStyle(.secondary)
            if entries.isEmpty { Text(tr("暂无研究记录", "No saved research", "Tiada penyelidikan disimpan")) }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            ForEach(entries) { entry in
                NavigationLink {
                    ResearchHistoryDetail(entry: entry, scope: account.researchHistoryScope)
                } label: {
                    VStack(alignment: .leading) {
                        Text(entry.symbols.joined(separator: " / "))
                        Text(entry.generatedAt).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.onDelete { offsets in
                do {
                    guard let scope = account.researchHistoryScope else { throw CloudFailure.session }
                    var next = entries; next.remove(atOffsets: offsets)
                    try ResearchHistory.write(next, scope: scope); entries = next
                } catch { self.error = error.localizedDescription }
            }
        }.navigationTitle(tr("研究历史", "Research history", "Sejarah penyelidikan"))
            .id(account.researchHistoryScope ?? "signed-out")
            .onAppear(perform: reload)
            .onChange(of: account.researchHistoryScope) { _, _ in reload() }
    }
    private func reload() {
        entries = []; error = ""
        guard let scope = account.researchHistoryScope else { return }
        do { entries = try ResearchHistory.load(scope: scope) } catch { self.error = error.localizedDescription }
    }
}

private struct ResearchHistoryDetail: View {
    let entry: ResearchHistoryEntry
    let scope: String?
    @ObservedObject private var account = CloudAccount.shared
    var body: some View {
        ScrollView {
            if let scope, scope == account.researchHistoryScope, !ResearchHistory.retained([entry]).isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tr("历史原文 · 非最新建议", "Historical text · Not current advice", "Teks sejarah · Bukan nasihat terkini")).font(.headline)
                    Text(entry.symbols.joined(separator: " / "))
                    Text(entry.generatedAt).font(.caption)
                    Text(entry.text).textSelection(.enabled)
                }.padding()
            } else {
                Text(tr("记录已过期或账号已切换", "Record expired or account changed", "Rekod tamat tempoh atau akaun berubah")).padding()
            }
        }
    }
}

private struct StockComparisonPicker: View {
    @AppStorage("investment.watchlist.v1") private var watchlist = ""
    @State private var selected: [String] = []
    @State private var search = ""
    private var stocks: [ObservedStock] {
        var seen = Set<String>()
        var values = ObservedStock.saved(watchlist) + ObservedStock.examples
        if let custom = ObservedStock.normalized(search) { values.insert(.init(symbol: custom, name: custom), at: 0) }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return values.filter { seen.insert($0.symbol).inserted && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.symbol.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        List {
            Section {
                Text(tr("选择 2–3 只股票，按相同的 6–12 个月周期比较机会、财务、估值和风险。缺少数据时明确留空。", "Select 2–3 stocks to compare opportunities, finances, valuation and risks over the same 6–12 months. Missing data stays unavailable.", "Pilih 2–3 saham untuk membandingkan peluang, kewangan, penilaian dan risiko sepanjang 6–12 bulan. Data tiada kekal tidak tersedia."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(selected, id: \.self) { symbol in
                    Button { selected.removeAll { $0 == symbol } } label: {
                        Label(symbol, systemImage: "minus.circle")
                    }
                }
                NavigationLink { StockResearchView(symbols: selected) } label: {
                    Label(tr("开始对比研究", "Compare online", "Banding dalam talian"), systemImage: "sparkles")
                }.disabled(selected.count < 2)
            }
            ForEach(stocks) { stock in
                Button {
                    if selected.contains(stock.symbol) { selected.removeAll { $0 == stock.symbol } }
                    else if selected.count < 3 { selected.append(stock.symbol) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) { Text(stock.name); Text(stock.symbol).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: selected.contains(stock.symbol) ? "checkmark.circle.fill" : "circle")
                    }
                }.disabled(selected.count == 3 && !selected.contains(stock.symbol))
            }
        }.navigationTitle(tr("股票对比", "Compare stocks", "Banding saham"))
            .searchable(text: $search, prompt: tr("公司或交易所:代码", "Company or EXCHANGE:SYMBOL", "Syarikat atau BURSA:KOD"))
    }
}

private struct ResearchWebView: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> TradingStockChart.Coordinator { .init(failed: .constant(false)) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; base-uri 'none'; form-action 'none'">
        <style>:root{color-scheme:light dark}body{font:17px -apple-system;padding:12px;line-height:1.6;overflow-wrap:anywhere}pre{font:inherit;white-space:pre-wrap}a{color:#3688ff}li{margin-bottom:18px}h2{font-size:18px}</style></head><body>\(html)</body></html>
        """, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: TradingStockChart.Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
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
        loadChart(view, coordinator: context.coordinator)
        return view
    }
    private func loadChart(_ view: WKWebView, coordinator: Coordinator) {
        let identity = symbol + (dark ? ":dark" : ":light")
        guard coordinator.chartIdentity != identity else { return }
        coordinator.chartIdentity = identity
        view.stopLoading()
        let options: [String: Any] = ["autosize": true, "width": "100%", "height": "100%", "symbol": symbol, "interval": "D",
            "timezone": "Etc/UTC", "theme": dark ? "dark" : "light", "style": "1", "locale": "en",
            "allow_symbol_change": false, "calendar": false, "hide_side_toolbar": true,
            "support_host": "https://www.tradingview.com"]
        guard ObservedStock.normalized(symbol) == symbol,
              let data = try? JSONSerialization.data(withJSONObject: options),
              let json = String(data: data, encoding: .utf8) else {
            view.loadHTMLString("", baseURL: nil)
            return
        }
        // Official embed only. No DOM extraction, quote scraping or AI bridge.
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;height:100%;background:\(dark ? "#131722" : "#ffffff")}a{color:#2962ff} .tradingview-widget-copyright{font:12px sans-serif;text-align:center;padding:6px}</style></head><body>
        <div class="tradingview-widget-container" style="height:100%;width:100%">
        <div class="tradingview-widget-container__widget" style="height:calc(100% - 32px);width:100%"></div>
        <div class="tradingview-widget-copyright"><a href="https://www.tradingview.com/" target="_blank" rel="noopener nofollow">Track all markets on TradingView</a></div>
        </div>
        <script>
        // Assign configuration before attaching the external script. Each page gets
        // a new widget, so a previously selected symbol cannot remain in its iframe.
        const options = \(json);
        const container = document.querySelector('.tradingview-widget-container');
        const script = document.createElement('script');
        script.type = 'text/javascript';
        script.async = true;
        script.src = 'https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js';
        script.textContent = JSON.stringify(options);
        script.onerror = () => {
            container.querySelector('.tradingview-widget-container__widget').textContent = 'Chart unavailable. Please reload or open TradingView.';
        };
        container.appendChild(script);
        </script></body></html>
        """, baseURL: nil)
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.failed = $failed
        loadChart(view, coordinator: context.coordinator)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var failed: Binding<Bool>
        var chartIdentity: String?
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
