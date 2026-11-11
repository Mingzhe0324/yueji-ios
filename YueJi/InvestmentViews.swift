import SwiftUI
import WebKit
import CryptoKit
import UIKit
import SafariServices
import UniformTypeIdentifiers

struct StockCompanyProfile: Decodable {
    let symbol: String
    let logoAsset: String
    let profileURL: URL
    let website: URL?
    let sector: String
    let industry: String
    let checkedAt: String

    static let directory: [String: StockCompanyProfile] = {
        guard let data = NSDataAsset(name: "StockDirectory")?.data,
              let values = try? JSONDecoder().decode([String: StockCompanyProfile].self, from: data) else { return [:] }
        return values.filter { key, value in
            key == value.symbol && value.profileURL.scheme == "https" && value.profileURL.host == "www.tradingview.com"
        }
    }()
}

private struct StockCompanyLogo: View {
    let stock: ObservedStock
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let profile = stock.profile, let logo = UIImage(named: profile.logoAsset) {
                Image(uiImage: logo).resizable().scaledToFit().padding(5)
                    .frame(width: size, height: size).background(Color.white)
            } else {
                // Unknown manual symbols never borrow an unrelated company's logo.
                Text(String(stock.symbol.split(separator: ":").last ?? "").prefix(4))
                    .font(.caption.bold()).frame(width: size, height: size).background(.quaternary)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct ObservedStock: Identifiable, Hashable {
    let symbol: String
    let name: String
    var id: String { symbol }
    var market: String { String(symbol.split(separator: ":").first ?? "") }
    var profile: StockCompanyProfile? { StockCompanyProfile.directory[symbol] }
    // Mirrors the default official importer; availability still depends on deployment and source health.
    var hasOfficialImporter: Bool { ["MYX:MAYBANK", "MYX:99SMART", "MYX:GAMUDA", "MYX:HLBANK", "MYX:CIMB", "MYX:TENAGA", "MYX:IJM", "MYX:SUNWAY", "NASDAQ:AAPL", "NASDAQ:MSFT", "NASDAQ:NVDA"].contains(symbol) }
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
            guard let original = normalized(String(line)) else { return nil }
            // Migrate watchlists only; historical reports retain their original identifiers.
            let symbol = ["NYSE:WMT": "NASDAQ:WMT", "SIX:ROG": "SIX:ROP"][original] ?? original
            guard seen.insert(symbol).inserted else { return nil }
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
        .init(symbol: "NASDAQ:WMT", name: "Walmart · 沃尔玛"),
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
        .init(symbol: "SIX:ROP", name: "Roche · 罗氏"),
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
    @ObservedObject private var account = CloudAccount.shared
    @State private var recentResearch: [ResearchHistoryEntry] = []
    @AppStorage("investment.watchlist.v1") private var watchlist = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var market = "all"
    @AppStorage("investment.compactWatchlist") private var compactWatchlist = false
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
                VStack(alignment: .leading, spacing: 16) {
                    Label(tr("看懂一家公司", "Understand a company", "Fahami syarikat"), systemImage: "sparkles")
                        .font(.largeTitle.bold())
                    Text(tr("先看评分，再看理由。", "See the rating. Understand why.", "Lihat skor. Fahami sebabnya."))
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 12) {
                        Label(tr("选公司", "Choose", "Pilih"), systemImage: "1.circle.fill")
                        Image(systemName: "chevron.right").font(.caption2)
                        Label(tr("看评分", "Review", "Semak"), systemImage: "2.circle.fill")
                        Image(systemName: "chevron.right").font(.caption2)
                        Label(tr("再决定", "Decide", "Putuskan"), systemImage: "3.circle.fill")
                    }.font(.caption.weight(.semibold)).foregroundStyle(.mint)
                    Picker(tr("自选布局", "Watchlist layout", "Susun atur senarai pantau"), selection: $compactWatchlist) {
                        Text(tr("卡片", "Cards", "Kad")).tag(false)
                        Text(tr("列表", "List", "Senarai")).tag(true)
                    }.pickerStyle(.segmented)
                    if compactWatchlist {
                        ForEach(saved.isEmpty ? Array(ObservedStock.examples.prefix(3)) : saved) { stock in
                            NavigationLink { StockChartView(stock: stock) } label: {
                                HStack(spacing: 12) {
                                    StockCompanyLogo(stock: stock)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(stock.name).font(.subheadline.bold())
                                        Text(stock.symbol).font(.caption.monospaced())
                                    }
                                    Spacer()
                                    Text(stock.hasOfficialImporter ? tr("自动研究", "Auto research", "Kajian automatik") : tr("需导入资料", "Import required", "Import diperlukan")).font(.caption)
                                }.padding(.vertical, 6)
                            }.buttonStyle(InvestmentPressStyle())
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(saved.isEmpty ? Array(ObservedStock.examples.prefix(3)) : saved) { stock in
                                    NavigationLink { StockChartView(stock: stock).yuejiZoom(id: "hero" + stock.id, namespace: cards) } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            StockCompanyLogo(stock: stock)
                                            Text(stock.name).font(.headline).lineLimit(2)
                                            Text(stock.symbol).font(.caption.monospaced())
                                            Text(stock.hasOfficialImporter ? tr("自动研究", "Auto research", "Penyelidikan automatik") : tr("需导入资料", "Import required", "Import diperlukan"))
                                                .font(.caption).foregroundStyle(.white.opacity(0.8))
                                        }.frame(width: 170, alignment: .leading).padding(14)
                                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                                            .yuejiZoomSource(id: "hero" + stock.id, namespace: cards)
                                    }.buttonStyle(InvestmentPressStyle())
                                }
                            }
                        }
                    }
                    if saved.isEmpty {
                        Text(tr("示例公司 · 收藏后显示你的自选", "Examples · Follow stocks to personalize", "Contoh · Ikuti saham untuk peribadikan"))
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                }.padding(18).foregroundStyle(.white)
                    .background(LinearGradient(colors: [Color(red: 0.07, green: 0.15, blue: 0.27), Color(red: 0.03, green: 0.07, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)).listRowBackground(Color.clear)
            }
            Section(tr("研究工具", "Research tools", "Alat penyelidikan")) {
                beginnerEntrance
                DisclosureGroup(tr("比较、历史与更多工具", "Compare, history & more", "Banding, sejarah dan lagi")) {
                NavigationLink { LocalMarketScanView() } label: {
                    Label(tr("查看电脑采集结果", "View computer scan", "Lihat imbasan komputer"), systemImage: "tray.and.arrow.down")
                }
                NavigationLink { InvestmentCoverageView() } label: {
                    Label(tr("选股前 · 检查资料覆盖", "Before screening · Check coverage", "Sebelum saringan · Semak liputan"), systemImage: "checklist")
                }
                NavigationLink { StockComparisonPicker() } label: {
                    Label(tr("对比 2–3 只股票", "Compare 2–3 stocks", "Bandingkan 2–3 saham"), systemImage: "square.split.2x2")
                }
                NavigationLink { ResearchHistoryView() } label: {
                    Label(tr("研究历史", "Research history", "Sejarah penyelidikan"), systemImage: "clock.arrow.circlepath")
                }
                }
            }
            if !recentResearch.isEmpty {
                Section(tr("最近研究", "Recent research", "Penyelidikan terkini")) {
                    ForEach(recentResearch.prefix(3)) { entry in
                        NavigationLink { ResearchHistoryDetail(entry: entry, scope: account.researchHistoryScope) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(entry.symbols.joined(separator: " / "), systemImage: "doc.text.magnifyingglass").font(.headline)
                                Text(entry.generatedAt).font(.caption).foregroundStyle(.secondary)
                                Text(tr("已保存报告 · 非实时", "Saved report · Not live", "Laporan tersimpan · Bukan langsung")).font(.caption).foregroundStyle(.orange)
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            Section(tr("自动 AI 研究", "Automatic AI research", "Penyelidikan AI automatik")) {
                InvestmentDisclosure(tr("选择公司开始研究", "Choose a company to research", "Pilih syarikat untuk dikaji")) {
                ForEach(ObservedStock.examples.filter { $0.hasOfficialImporter } + [ObservedStock(symbol: "MYX:IJM", name: "IJM · 怡保工程"), ObservedStock(symbol: "MYX:SUNWAY", name: "Sunway · 双威")]) { stock in
                    NavigationLink { StockResearchView(symbols: [stock.symbol]) } label: {
                        HStack(spacing: 12) {
                            StockCompanyLogo(stock: stock)
                            Text(stock.name).font(.subheadline.weight(.semibold))
                        }.padding(.vertical, 6)
                    }
                }
                }
                Text(tr("读取官方财务网页后分析。公告可能不是最新一期，报告会列出来源与资料范围。", "Analyzes official financial pages. Filings may not be the latest; reports list sources and scope.", "Menganalisis halaman kewangan rasmi. Pemfailan mungkin bukan yang terkini; laporan menyenaraikan sumber dan skop."))
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
            Section {
                InvestmentDisclosure(tr("行情说明", "About market data", "Tentang data pasaran")) {
                Text(tr("行情由 TradingView 提供；部分市场延迟或不可用，以图表标示为准。示例清单不是实时热门榜或买入建议。自选仅保存在此设备。", "Charts are provided by TradingView. Some markets are delayed or unavailable; check the chart labels. This curated list is not a live popularity ranking or a buy recommendation. Watchlists stay on this device.", "Carta disediakan oleh TradingView. Sesetengah pasaran tertunda atau tidak tersedia; semak label carta. Senarai ini bukan kedudukan populariti langsung atau cadangan beli. Senarai pantau disimpan pada peranti ini."))
                    .font(.caption).foregroundStyle(.secondary)
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
                ForEach(examples) { stock in stockLink(stock, source: "example").transition(.opacity) }
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
            .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.24), value: watchlist)
            .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.2), value: compactWatchlist)
            .onAppear(perform: loadRecentResearch)
            .onChange(of: account.researchHistoryScope) { _, _ in loadRecentResearch() }
            .investmentAssistantOrb()
    }
    private var beginnerEntrance: some View {
        NavigationLink { BeginnerInvestmentView() } label: {
            Label(tr("新手起步", "Get started", "Mula belajar"), systemImage: "leaf")
                .frame(maxWidth: .infinity).padding(12)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(InvestmentPressStyle())
    }
    private func loadRecentResearch() {
        recentResearch = []
        guard let scope = account.researchHistoryScope else { return }
        recentResearch = (try? ResearchHistory.load(scope: scope)) ?? []
    }
    private func stockLink(_ stock: ObservedStock, source: String) -> some View {
        NavigationLink {
            StockChartView(stock: stock).yuejiZoom(id: source + stock.id, namespace: cards)
        } label: {
            HStack(spacing: 12) {
                StockCompanyLogo(stock: stock)
                VStack(alignment: .leading, spacing: 5) {
                    Text(stock.name).font(.headline)
                    Text(stock.symbol).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(stock.hasOfficialImporter
                         ? tr("支持自动研究", "Automatic research supported", "Penyelidikan automatik disokong")
                         : tr("研究需导入资料", "Import materials for research", "Import bahan untuk penyelidikan"))
                        .font(.caption2).foregroundStyle(stock.hasOfficialImporter ? Color.accentColor : Color.secondary)
                    if let profile = stock.profile {
                        Text(profile.industry).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if saved.contains(where: { $0.symbol == stock.symbol }) { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel(tr("已关注", "Following", "Diikuti")) }
            }.padding(.vertical, 4).yuejiZoomSource(id: source + stock.id, namespace: cards)
        }
    }
}

private struct StockChartView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stock: ObservedStock
    @AppStorage("investment.watchlist.v1") private var watchlist = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @State private var reload = UUID()
    @State private var failed = false
    @State private var browserPage: StockBrowserPage?
    // Prefer the full website for Malaysian listings after the MYX widget restriction.
    private var prefersFullPage: Bool { stock.market == "MYX" }
    private var following: Bool { ObservedStock.saved(watchlist).contains { $0.symbol == stock.symbol } }
    @ViewBuilder private var primaryActions: some View {
        Button { browserPage = StockBrowserPage(url: TradingStockChart.sourceURL(stock.symbol)) } label: {
            Label(tr("查看行情", "View chart", "Lihat carta"), systemImage: "chart.xyaxis.line").frame(maxWidth: .infinity).padding(14)
        }.buttonStyle(InvestmentPressStyle()).foregroundStyle(.blue).background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        NavigationLink { StockResearchView(stock: stock) } label: {
            Label(tr("AI 研究", "AI research", "Penyelidikan AI"), systemImage: "sparkles").frame(maxWidth: .infinity).padding(14)
        }.buttonStyle(InvestmentPressStyle()).foregroundStyle(.white).background(Color.blue, in: RoundedRectangle(cornerRadius: 18))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    StockCompanyLogo(stock: stock, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stock.name).font(.title2.bold())
                        Text(stock.symbol).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { primaryActions }
                    VStack(spacing: 12) { primaryActions }
                }
                if let profile = stock.profile {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("公司资料", "Company profile", "Profil syarikat")).font(.headline)
                        LabeledContent(tr("交易所", "Exchange", "Bursa"), value: stock.market)
                        LabeledContent(tr("板块", "Sector", "Sektor"), value: profile.sector)
                        LabeledContent(tr("行业", "Industry", "Industri"), value: profile.industry)
                        if let website = profile.website {
                            Link(tr("公司官网 ↗", "Company website ↗", "Laman web syarikat ↗"), destination: website)
                        }
                        Link(tr("完整公司资料 · TradingView ↗", "Full profile · TradingView ↗", "Profil penuh · TradingView ↗"), destination: profile.profileURL)
                        Link(tr("财务数据 ↗", "Financials ↗", "Kewangan ↗"), destination: profile.profileURL.appendingPathComponent("financials-overview"))
                        Link(tr("公司新闻 ↗", "Company news ↗", "Berita syarikat ↗"), destination: profile.profileURL.appendingPathComponent("news"))
                        Text(tr("公司分类与图标来源：TradingView。核对日期：", "Company classifications and logos: TradingView. Checked: ", "Klasifikasi syarikat dan logo: TradingView. Disemak: ") + profile.checkedAt)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(tr("外部页面可能延迟或缺少资料；这些链接不代表 AI 已读取其内容。", "External pages may be delayed or incomplete. These links do not mean AI has read their contents.", "Halaman luar mungkin tertunda atau tidak lengkap. Pautan ini tidak bermakna AI telah membaca kandungannya."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text(tr("这只股票尚未收录公司资料和图标；请核对交易所及代码。", "Company details and logo are not in the directory yet. Check the exchange and symbol.", "Butiran syarikat dan logo belum ada dalam direktori. Semak bursa dan kod."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let source = stock.officialSourceURL {
                    Link(destination: source) {
                        Label(tr("公司官方财务资料 ↗", "Official financial sources ↗", "Sumber kewangan rasmi ↗"), systemImage: "doc.text.magnifyingglass")
                    }
                }
                Text(stock.hasOfficialImporter
                     ? tr("已提供自动读取适配；需恢复云端部署后使用。资料范围为官方网页摘要，仍可能加载失败。", "Automatic importer available; requires cloud deployment. Covers official page summaries and may fail to load.", "Pengimport automatik tersedia; memerlukan penggunaan awan. Meliputi ringkasan halaman rasmi dan mungkin gagal dimuatkan.")
                     : tr("这只股票尚未接入自动财务分析；图表可用不代表 AI 已有资料。", "Automatic financial analysis is not connected for this stock. A chart does not mean AI has its data.", "Analisis kewangan automatik belum disambungkan untuk saham ini. Carta tidak bermakna AI mempunyai datanya."))
                    .font(.caption).foregroundStyle(.secondary)
                if prefersFullPage {
                    Label(tr("在 App 内查看完整行情", "View full chart in the app", "Lihat carta penuh dalam aplikasi"), systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Text(tr("此市场优先使用 TradingView 完整网页。点击下方按钮查看，关闭网页即可返回股票详情。", "This market opens the full TradingView website. Use the button below, then close the page to return to stock details.", "Pasaran ini membuka laman penuh TradingView. Gunakan butang di bawah, kemudian tutup halaman untuk kembali ke butiran saham."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if phase == .active {
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
                    if !prefersFullPage {
                      Button { failed = false; reload = UUID() } label: {
                        Label(tr("重新加载", "Reload", "Muat semula"), systemImage: "arrow.clockwise")
                      }
                    }
                    Spacer()
                    Button {
                        browserPage = StockBrowserPage(url: TradingStockChart.sourceURL(stock.symbol))
                    } label: {
                        Label(tr("在 App 内查看行情", "View chart in app", "Lihat carta dalam aplikasi"), systemImage: "globe")
                    }
                }.buttonStyle(.bordered)

                Text(tr("打开图表会连接 TradingView，其服务和隐私政策适用。不会发送月记账本内容。", "Charts connect to TradingView and are subject to its service and privacy policies. Your ledger contents are not sent.", "Carta bersambung ke TradingView dan tertakluk pada dasar perkhidmatan dan privasinya. Kandungan lejar tidak dihantar."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle(tr("股票详情", "Stock details", "Butiran saham"))
            .investmentAssistantOrb()
            .environment(\.openURL, OpenURLAction { url in
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return .systemAction }
                browserPage = StockBrowserPage(url: url)
                return .handled
            })
            .sheet(item: $browserPage) { page in
                StockInAppBrowser(url: page.url).ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        var symbols = ObservedStock.saved(watchlist).map(\.symbol)
                        if following { symbols.removeAll { $0 == stock.symbol } }
                        else { symbols.append(stock.symbol) }
                        watchlist = symbols.joined(separator: "\n")
                        FeedbackHaptics.selection()
                    } label: { Image(systemName: following ? "star.fill" : "star") }
                        .symbolEffect(.bounce, options: .nonRepeating, value: !reduceMotion && ElegantMotion.enabled && following)
                        .accessibilityLabel(following ? tr("取消关注", "Unfollow", "Nyahikuti") : tr("加入自选", "Follow stock", "Ikuti saham"))
                }
            }
    }
}

private struct StockBrowserPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct StockInAppBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct StockResearchReport: Decodable {
    let symbol: String
    let symbols: [String]?
    let generatedAt: String
    let html: String
    let text: String?
    let cached: Bool?
    let assessments: [ResearchAssessment]?
    let sources: [ResearchSource]?
}

private struct ResearchAssessment: Decodable, Identifiable {
    let symbol: String
    let summary: String
    let period: String
    let action: String
    let conditions: String
    let missing: String
    let overall: Int?
    let dimensions: [ResearchDimension]
    var id: String { symbol }
}
private struct ResearchDimension: Decodable, Identifiable {
    let key: String
    let score: Int?
    let reason: String
    let evidence: [ResearchCitation]
    var id: String { key }
    var label: String {
        switch key {
        case "growth": return tr("生意有变好吗", "Is it growing?", "Adakah ia berkembang?")
        case "profitability": return tr("赚钱能力强吗", "Does it earn well?", "Adakah ia menguntungkan?")
        case "balanceSheet": return tr("财务撑得住吗", "Are finances sound?", "Adakah kewangan kukuh?")
        case "valuation": return tr("价格划算吗", "Is the price fair?", "Adakah harga berpatutan?")
        default: return tr("风险能承受吗", "How resilient is it?", "Sejauh mana ketahanannya?")
        }
    }
}
private struct ResearchCitation: Decodable { let sourceId: String; let quote: String }
private struct ResearchSource: Decodable, Identifiable {
    let id: String
    let company: String
    let url: String
    let scope: String?
    let fetchedAt: String
}

private struct InvestmentPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion && ElegantMotion.enabled ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct InvestmentDisclosure<Content: View>: View {
    let title: String
    let content: Content
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        DisclosureGroup(title, isExpanded: Binding(get: { expanded }, set: { value in
            withAnimation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.22)) { expanded = value }
        })) { content }
    }
}

private struct ResearchReportCards: View {
    let report: StockResearchReport
    @State private var browserPage: StockBrowserPage?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let companies = report.assessments, companies.count > 1 {
                ResearchComparisonCards(companies: companies)
            }
            ForEach(report.assessments ?? []) { company in
                ResearchCompanyCards(company: company)
            }
            InvestmentDisclosure(tr("资料来源", "Sources", "Sumber")) {
                ForEach(report.sources ?? []) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("[\(source.id)] \(source.company)").font(.headline)
                        if let scope = source.scope { Text(scope).font(.caption) }
                        Text(source.fetchedAt).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let url = URL(string: source.url), url.scheme == "https", url.user == nil, url.password == nil {
                            Button(tr("查看原文", "Read source", "Baca sumber")) { browserPage = StockBrowserPage(url: url) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
            }.padding(16).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            if let text = report.text {
                InvestmentDisclosure(tr("完整报告与引用", "Full report and citations", "Laporan penuh dan petikan")) {
                    Text(text).font(.subheadline).textSelection(.enabled).padding(.top, 10)
                }.padding(16).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            }
        }.sheet(item: $browserPage) { StockInAppBrowser(url: $0.url).ignoresSafeArea() }
    }
}

private struct ResearchComparisonCards: View {
    let companies: [ResearchAssessment]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tr("同维度比较", "Compare by dimension", "Banding mengikut dimensi"), systemImage: "rectangle.split.3x1").font(.headline)
            Text(tr("报告期间逐项列出；币种与单位请核对原文，未做汇率换算。资料不足时不排名。", "Reporting periods are shown below. Check source currencies and units; no currency conversion is applied. Missing evidence is not ranked.", "Tempoh laporan ditunjukkan di bawah. Semak mata wang dan unit sumber; tiada penukaran mata wang. Bukti tidak lengkap tidak diberi kedudukan.")).font(.caption).foregroundStyle(.secondary)
            ForEach(["growth", "profitability", "balanceSheet", "valuation", "risk"], id: \.self) { key in
                if let label = companies.first?.dimensions.first(where: { $0.key == key })?.label {
                    InvestmentDisclosure(label) {
                        if sizeClass == .regular && !typeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: 12) { entries(key) }
                        } else {
                            VStack(alignment: .leading, spacing: 12) { entries(key) }
                        }
                    }
                }
            }
        }.researchCard()
    }
    @ViewBuilder private func entries(_ key: String) -> some View {
        ForEach(companies) { company in
            VStack(alignment: .leading, spacing: 8) {
                Text(company.symbol).font(.subheadline.bold())
                Text(company.period).font(.caption).foregroundStyle(.secondary)
                if let dimension = company.dimensions.first(where: { $0.key == key }) {
                    if let score = dimension.score, (0...20).contains(score) {
                        Text("\(score)/20").monospacedDigit().foregroundStyle(.blue)
                    } else {
                        Text(tr("资料不足", "Insufficient data", "Data tidak mencukupi")).foregroundStyle(.orange)
                    }
                    Text(dimension.reason).font(.subheadline)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
    }
}

private struct ResearchCompanyCards: View {
    let company: ResearchAssessment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    private var complete: Bool {
        company.dimensions.count == 5 && Set(company.dimensions.map(\.key)) == Set(["growth", "profitability", "balanceSheet", "valuation", "risk"]) && company.dimensions.allSatisfy { (0...20).contains($0.score ?? -1) }
    }
    private var total: Int? {
        guard complete, let overall = company.overall, overall == company.dimensions.reduce(0, { $0 + ($1.score ?? 0) }) else { return nil }
        return overall
    }
    private var supportedCount: Int { company.dimensions.filter { (0...20).contains($0.score ?? -1) }.count }
    private var ratingColor: Color {
        guard total != nil else { return .orange }
        return company.action == "consider" ? .mint : company.action == "avoid" ? .red : .orange
    }
    private var verdict: String {
        guard total != nil else { return tr("先等等，还不能判断", "Wait — not enough evidence", "Tunggu — bukti belum cukup") }
        switch company.action {
        case "consider": return tr("值得进一步了解", "Worth a closer look", "Wajar dikaji lanjut")
        case "avoid": return tr("暂时不考虑", "Pass for now", "Elakkan buat masa ini")
        default: return tr("继续观察", "Keep watching", "Terus pantau")
        }
    }
    private var ratingDial: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 10)
            if let total {
                Circle().trim(from: 0, to: Double(total) / 100)
                    .stroke(ratingColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(total.map(String.init) ?? "—").font(.system(size: 42, weight: .bold, design: .rounded))
                Text(total == nil ? tr("暂不评分", "Unrated", "Belum dinilai") : "/ 100").font(.caption)
            }
        }.frame(width: 126, height: 126)
            .accessibilityElement(children: .combine)
    }
    private var verdictText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("现在怎么看？", "What now?", "Apa seterusnya?")).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(verdict).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Text(company.period).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(company.symbol, systemImage: "sparkles").font(.headline)
                    Spacer()
                    Text(tr("研究评分", "Research rating", "Skor kajian")).font(.caption)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { ratingDial; verdictText }
                    VStack(alignment: .leading, spacing: 16) { ratingDial; verdictText }
                }
                Divider().overlay(.white.opacity(0.2))
                HStack {
                    Text(tr("有依据的项目", "Supported checks", "Semakan disokong"))
                    Spacer()
                    Text("\(supportedCount) / 5").monospacedDigit().bold()
                }.font(.subheadline)
                Text(tr("分数是对资料的研究评价，不是上涨概率或买入指令。", "Scores rate the evidence, not the chance of profit or an instruction to buy.", "Skor menilai bukti, bukan peluang untung atau arahan membeli."))
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            }.padding(24).foregroundStyle(.white)
                .background(LinearGradient(colors: [Color(red: 0.09, green: 0.19, blue: 0.3), Color(red: 0.04, green: 0.09, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                ForEach(company.dimensions) { dimension in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dimension.label).font(.subheadline.weight(.semibold))
                        if let score = dimension.score, (0...20).contains(score) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(score)).font(.system(.title, design: .rounded).bold())
                                Text("/20").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(score), total: 20).tint(score >= 13 ? .teal : .orange)
                            Text(score >= 13 ? tr("表现较好", "Favourable", "Baik") : score >= 9 ? tr("好坏参半", "Mixed", "Bercampur") : tr("需要留意", "Needs attention", "Perlu perhatian"))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("—").font(.title.bold()).foregroundStyle(.secondary)
                            Text(tr("缺资料，暂不评分", "Missing data · unrated", "Data tiada · belum dinilai"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 115, alignment: .topLeading).padding(16)
                        .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            Text(tr("每项满分 20 分，越高越好；五项资料齐全才计算总分。风险项高分代表已知风险较少。", "Each check is out of 20; higher is better. All five are needed for a total. A higher risk score means fewer evidenced risks.", "Setiap semakan daripada 20; lebih tinggi lebih baik. Lima semakan diperlukan untuk jumlah. Skor risiko tinggi bermakna risiko terbukti lebih rendah."))
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("一句话看懂", "At a glance", "Sepintas lalu")).font(.headline)
                Text(company.summary).textSelection(.enabled)
            }.researchCard()
            InvestmentDisclosure(tr("财务表现与风险 · 查看评分", "Financials and risks · View ratings", "Kewangan dan risiko · Lihat penilaian")) {
                ForEach(company.dimensions) { dimension in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(dimension.label).font(.subheadline.bold())
                            Spacer()
                            if let score = dimension.score, (0...20).contains(score) {
                                Text("\(score)/20").monospacedDigit().foregroundStyle(.blue)
                            } else {
                                Text(tr("资料不足", "Insufficient data", "Data tidak mencukupi")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let score = dimension.score, (0...20).contains(score) {
                            ProgressView(value: revealed ? Double(score) : 0, total: 20).tint(.blue)
                                .accessibilityLabel(dimension.label).accessibilityValue("\(score)/20")
                        } else {
                            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.18)).frame(height: 4).accessibilityHidden(true)
                        }
                        Text(dimension.reason).font(.subheadline).foregroundStyle(dimension.key == "risk" ? Color.orange : Color.secondary)
                        if !dimension.evidence.isEmpty {
                            InvestmentDisclosure(tr("引用依据", "Evidence", "Bukti")) {
                                ForEach(Array(dimension.evidence.enumerated()), id: \.offset) { _, citation in
                                    Text("[\(citation.sourceId)] \(citation.quote)").font(.caption).textSelection(.enabled).padding(.vertical, 4)
                                }
                            }.font(.caption)
                        }
                    }.padding(.vertical, 8)
                }
            }.researchCard().opacity(revealed ? 1 : 0)
                .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.3).delay(0.08), value: revealed)
            VStack(alignment: .leading, spacing: 10) {
                InvestmentDisclosure(tr("下一步怎么做？", "What should I check next?", "Apa perlu disemak seterusnya?")) {
                    Text(company.conditions).textSelection(.enabled)
                }
            }.researchCard().opacity(revealed ? 1 : 0)
                .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.3).delay(0.16), value: revealed)
            VStack(alignment: .leading, spacing: 10) {
                InvestmentDisclosure(tr("还缺哪些资料？", "What is missing?", "Apa yang belum lengkap?")) {
                    Text(company.missing).textSelection(.enabled)
                }
            }.researchCard().opacity(revealed ? 1 : 0)
                .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.3).delay(0.24), value: revealed)
        }
        .task {
            guard !revealed else { return }
            if reduceMotion || !ElegantMotion.enabled { revealed = true }
            else { withAnimation(.easeOut(duration: 0.35)) { revealed = true } }
        }
    }
}

private extension View {
    func investmentAssistantOrb() -> some View { modifier(InvestmentAssistantOrb()) }
    func researchCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }
}

/// Original vector mark: a crescent conversation bubble and a small four-point star.
/// Drawn at any size without a bitmap or a third-party logo dependency.
private struct StockAssistantMark: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.72, y: h * 0.29))
                    p.addCurve(to: CGPoint(x: w * 0.22, y: h * 0.69), control1: CGPoint(x: w * 0.23, y: h * 0.02), control2: CGPoint(x: w * 0.02, y: h * 0.48))
                    p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.86))
                    p.addLine(to: CGPoint(x: w * 0.39, y: h * 0.79))
                    p.addCurve(to: CGPoint(x: w * 0.80, y: h * 0.46), control1: CGPoint(x: w * 0.67, y: h * 0.87), control2: CGPoint(x: w * 0.86, y: h * 0.65))
                    p.addCurve(to: CGPoint(x: w * 0.72, y: h * 0.29), control1: CGPoint(x: w * 0.47, y: h * 0.64), control2: CGPoint(x: w * 0.42, y: h * 0.27))
                }.stroke(.white, style: StrokeStyle(lineWidth: w * 0.065, lineCap: .round, lineJoin: .round))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.82, y: h * 0.06))
                    p.addQuadCurve(to: CGPoint(x: w * 0.96, y: h * 0.22), control: CGPoint(x: w * 0.83, y: h * 0.20))
                    p.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.38), control: CGPoint(x: w * 0.83, y: h * 0.24))
                    p.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.22), control: CGPoint(x: w * 0.81, y: h * 0.24))
                    p.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.06), control: CGPoint(x: w * 0.81, y: h * 0.20))
                }.fill(Color(red: 0.65, green: 0.96, blue: 1))
            }
        }.accessibilityHidden(true)
    }
}

private struct InvestmentAssistantOrb: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("investment.assistantOrb.right") private var onRight = true
    @AppStorage("investment.assistantOrb.height") private var heightFraction = 0.9
    @State private var translation = CGSize.zero
    @State private var showingChat = false
    private let diameter: CGFloat = 64
    private func position(in size: CGSize, offset: CGSize = .zero) -> CGPoint {
        let margin = diameter / 2 + 12
        let maxX = max(margin, size.width - margin)
        // Keep the whole orb above the bottom action area, including its shadow.
        let maxY = max(margin, size.height - margin - 80)
        let fraction = heightFraction.isFinite ? min(1, max(0, heightFraction)) : 0.9
        return CGPoint(x: min(maxX, max(margin, (onRight ? maxX : margin) + offset.width)),
                       y: min(maxY, max(margin, margin + (maxY - margin) * CGFloat(fraction) + offset.height)))
    }
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 80).allowsHitTesting(false) }
            .overlay {
                GeometryReader { geometry in
                    Button { showingChat = true } label: {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [Color(red: 0.18, green: 0.62, blue: 0.98), Color(red: 0.16, green: 0.22, blue: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Circle().stroke(.white.opacity(0.65), lineWidth: 1)
                            StockAssistantMark().frame(width: 42, height: 42)
                        }.frame(width: diameter, height: diameter)
                            .shadow(color: .blue.opacity(0.25), radius: 10, y: 4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("股票 AI 助手", "Stock AI assistant", "Pembantu AI saham"))
                    .accessibilityHint(tr("点击提问；可拖到屏幕两侧", "Tap to ask; drag to either side", "Tekan untuk bertanya; seret ke mana-mana sisi"))
                    .accessibilityAction(named: Text(tr("移到另一侧", "Move to other side", "Alih ke sisi lain"))) {
                        withAnimation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.22)) { onRight.toggle() }
                    }
                    // Measure against the stationary overlay, not the moving button.
                    .highPriorityGesture(DragGesture(minimumDistance: 10, coordinateSpace: .named("investmentOrbOverlay"))
                        .onChanged { value in
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) { translation = value.translation }
                        }
                        .onEnded { value in
                            let point = position(in: geometry.size, offset: value.translation)
                            let margin = diameter / 2 + 12
                            withAnimation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.22)) {
                                onRight = point.x >= geometry.size.width / 2
                                heightFraction = Double(min(1, max(0, (point.y - margin) / max(1, geometry.size.height - 2 * margin - 80))))
                                translation = .zero
                            }
                        })
                    .position(position(in: geometry.size, offset: translation))
                    .onDisappear { translation = .zero }
                }
                .coordinateSpace(name: "investmentOrbOverlay")
            }
            .sheet(isPresented: $showingChat) {
                NavigationStack {
                    StockChatView()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("关闭", "Close", "Tutup")) { showingChat = false } } }
                }
            }
    }
}

struct StockResearchImport {
    let csv: String
    let source: String
    let notes: String
}

private struct StockImportForm: View {
    let symbol: String
    let onConfirm: (StockResearchImport) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var csv = ""
    @State private var source = ""
    @State private var notes = ""
    @State private var choosingFile = false
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(tr("这些资料是什么？", "What are these materials?", "Apakah bahan ini?")) {
                    Text(tr("股价文件：记录每天开盘价、最高价、最低价、收盘价和成交量。财报文字：公司公开说明赚了多少、欠了多少，以及有什么风险。都不是你的银行账单或持仓截图。", "Price files record daily open, high, low, close and trading volume. Financial reports explain company earnings, debt and risks. Neither is your bank statement or a screenshot of your holdings.", "Fail harga mencatat harga buka, tinggi, rendah, tutup dan volum harian. Laporan kewangan menerangkan pendapatan, hutang dan risiko syarikat. Bukan penyata bank atau tangkap layar pegangan anda."))
                    Text(tr("1. 从你使用的行情服务导出历史日线 CSV；服务不提供导出时，可直接取消。\n2. 按下方表头整理至少 20 个交易日，使用当前股票代码、同一币种，并按日期从旧到新排列。\n3. 财报文字可从公司官网的「投资者关系／财务业绩」复制，保留标题、日期和单位。不知道怎么准备时，请返回自动研究。", "1. Export historical daily prices as CSV from your market-data service; cancel if export is unavailable.\n2. Match the header below with at least 20 trading days, this symbol, one currency, oldest date first.\n3. Copy financial text from the company's Investor Relations / Financial Results page, keeping headings, dates and units. If unsure, return to automatic research.", "1. Eksport harga harian sejarah sebagai CSV daripada perkhidmatan harga anda; batalkan jika tiada eksport.\n2. Ikuti pengepala di bawah dengan sekurang-kurangnya 20 hari dagangan, kod ini, satu mata wang dan tarikh paling lama dahulu.\n3. Salin teks daripada Hubungan Pelabur / Keputusan Kewangan laman syarikat, bersama tajuk, tarikh dan unit. Jika tidak pasti, kembali ke kajian automatik."))
                }
                Section(symbol) {
                    Text(tr("导入 UTF-8 CSV，20–1000 个交易日，日期从旧到新。每行股票代码必须与当前股票一致。", "Import UTF-8 CSV with 20–1000 daily bars, oldest first. Every row must match this stock symbol.", "Import CSV UTF-8 dengan 20–1000 bar harian, paling lama dahulu. Setiap baris mesti sepadan dengan kod saham ini."))
                    Text("symbol,currency,date,open,high,low,close,volume").font(.caption.monospaced()).textSelection(.enabled)
                    Text(tr("下行仅演示格式，数字是虚构的，不可用于分析；正式文件需至少 20 行真实记录。", "The row below only illustrates the format. Numbers are fictional and must not be analyzed; use at least 20 real rows.", "Baris di bawah hanya contoh format. Angka rekaan tidak boleh dianalisis; gunakan sekurang-kurangnya 20 baris sebenar.")).font(.caption).foregroundStyle(.secondary)
                    Text("\(symbol),\(symbol.hasPrefix("MYX:") ? "MYR" : "USD"),2025-01-02,10,11,9,10.5,1000").font(.caption.monospaced()).textSelection(.enabled)
                    Button(tr("选择行情 CSV", "Choose price CSV", "Pilih CSV harga")) { choosingFile = true }
                    if !csv.isEmpty {
                        Text(String(csv.prefix(1500))).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    TextField(tr("资料来源及复权方式", "Source and price adjustment method", "Sumber dan kaedah pelarasan harga"), text: $source)
                }
                Section(tr("财报文本（可选）", "Financial statement text (optional)", "Teks penyata kewangan (pilihan)")) {
                    Text(tr("粘贴公司名称、报告期间、发布日期、币种和单位，以及盈利、现金流、负债、每股数据和风险说明。缺少资料时不计算综合分。", "Paste company identity, reporting period, publication date, currency and units, earnings, cash flow, debt, per-share data and risk disclosures. Missing evidence means no overall score.", "Tampal identiti syarikat, tempoh laporan, tarikh terbit, mata wang dan unit, pendapatan, aliran tunai, hutang, data sesaham dan risiko. Bukti tidak lengkap bermakna tiada skor keseluruhan."))
                    TextEditor(text: $notes).frame(minHeight: 180)
                }
                Section {
                    Text(tr("确认后仅在本页准备资料；点击分析才会发送所选行情和财报文本到 Gemini。资料未独立核实，不会保存到云端报告缓存。仅导入你有权使用的资料，不含账户或个人信息。", "Confirm prepares the data on this screen. Analyze sends the selected prices and financial text to Gemini. Materials are not independently verified or stored in the cloud report cache. Import only data you may use, without account or personal details.", "Sahkan menyediakan data di halaman ini. Analisis menghantar harga dan teks kewangan terpilih ke Gemini. Bahan tidak disahkan secara bebas atau disimpan dalam cache laporan awan. Import data yang dibenarkan sahaja, tanpa butiran akaun atau peribadi."))
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    Button(tr("确认导入", "Confirm import", "Sahkan import")) {
                        onConfirm(StockResearchImport(csv: csv, source: source, notes: notes)); dismiss()
                    }.disabled(csv.isEmpty || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.count > 300 || notes.count > 30000)
                }
            }.navigationTitle(tr("导入研究资料", "Import research materials", "Import bahan penyelidikan"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } } }
                .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        let data = try handle.read(upToCount: 180001) ?? Data()
                        guard data.count <= 180000, let text = String(data: data, encoding: .utf8) else { throw CloudFailure.invalidResponse }
                        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let lines = cleaned.components(separatedBy: .newlines).filter { !$0.isEmpty }
                        guard (21...1001).contains(lines.count), lines.first == "symbol,currency,date,open,high,low,close,volume",
                              lines.dropFirst().allSatisfy({ $0.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) == symbol }) else { throw CloudFailure.invalidResponse }
                        csv = cleaned; error = ""
                    } catch {
                        csv = ""
                        self.error = tr("文件不符合格式：请检查 UTF-8、表头、股票代码、20–1000 行及 180 KB 大小限制。", "Invalid file: check UTF-8, header, stock symbol, 20–1000 rows and 180 KB limit.", "Fail tidak sah: semak UTF-8, pengepala, kod saham, 20–1000 baris dan had 180 KB.")
                    }
                }
        }
    }
}

struct StockChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

private struct LocalMarketScanView: View {
    private struct Snapshot: Decodable {
        struct Market: Decodable, Identifiable {
            let market: String
            let providerListed: Int?
            let directoryError: String?
            let states: [String: Int]
            var id: String { market }
        }
        struct Row: Decodable, Identifiable {
            let symbol: String
            let name: String
            let market: String
            let status: String
            let through: String?
            var id: String { symbol }
        }
        let version: Int
        let generatedAt: String
        let provider: String
        let fullMarketRecommendation: Bool
        let recommendation: String
        let markets: [Market]
        let rows: [Row]
    }
    @ObservedObject private var account = CloudAccount.shared
    @State private var snapshot: Snapshot?
    @State private var choosingFile = false
    @State private var error = ""
    private let statuses = ["observed", "pending", "excluded", "unavailable", "stale", "short_history"]
    private func label(_ status: String) -> String {
        switch status {
        case "observed": return tr("已取得价格记录", "Price records collected", "Rekod harga dikumpul")
        case "pending": return tr("尚未采集", "Pending", "Belum dikumpul")
        case "excluded": return tr("不在采集范围或资料异常", "Excluded or invalid metadata", "Dikecualikan atau metadata tidak sah")
        case "stale": return tr("价格记录已旧", "Old price records", "Rekod harga lama")
        case "short_history": return tr("历史记录不足", "Insufficient history", "Sejarah tidak cukup")
        default: return tr("暂未取得", "Unavailable", "Tidak tersedia")
        }
    }
    var body: some View {
        List {
            Section {
                Text(tr("把电脑生成的 report.json 存到 iPhone 的“文件”，然后在这里选择。无需提供密钥。", "Save the computer's report.json in iPhone Files, then select it here. No API key needed.", "Simpan report.json komputer dalam Fail iPhone, kemudian pilih di sini. Tiada kunci API diperlukan."))
                Button(tr("选择采集结果文件", "Choose scan report", "Pilih laporan imbasan")) { choosingFile = true }
                Text(tr("只在本页读取文件，不发送给 AI。这里显示采集进度，不是股票推荐；仍缺财报、估值和公告。", "Read locally on this screen; nothing is sent to AI. This shows collection progress, not stock recommendations. Financials, valuations and announcements are still missing.", "Dibaca setempat di halaman ini; tidak dihantar ke AI. Ini kemajuan pengumpulan, bukan cadangan saham. Kewangan, penilaian dan pengumuman masih tiada.")).font(.caption).foregroundStyle(.secondary)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            if let snapshot {
                Section(tr("文件中的采集进度", "Progress in this file", "Kemajuan dalam fail")) {
                    Text(snapshot.generatedAt).font(.caption).foregroundStyle(.secondary)
                    Text(tr("离线快照，不会自动更新。下列状态以文件生成时为准。", "Offline snapshot; does not update automatically. Statuses are as of file generation.", "Petikan luar talian; tidak dikemas kini automatik. Status pada masa fail dijana.")).font(.caption)
                    ForEach(snapshot.markets) { market in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(market.market == "KLSE" ? tr("马股", "Malaysia", "Malaysia") : market.market == "US" ? tr("美股", "US", "AS") : tr("港股", "Hong Kong", "Hong Kong")).font(.headline)
                            if let listed = market.providerListed { Text("\(listed) " + tr("条服务商目录记录", "provider directory records", "rekod direktori pembekal")) }
                            if market.directoryError != nil || market.providerListed == nil {
                                Text(tr("目录未取得或更新失败，覆盖不完整", "Directory missing or refresh failed; coverage incomplete", "Direktori tiada atau kemas kini gagal; liputan tidak lengkap")).foregroundStyle(.orange)
                            }
                            ForEach(statuses, id: \.self) { status in
                                if let count = market.states[status], count > 0 { Text("\(label(status)): \(count)").font(.caption) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section(tr("已尝试的股票 · 非排名，最多显示 200 条", "Attempted stocks · Unranked, up to 200", "Saham dicuba · Tanpa kedudukan, sehingga 200")) {
                    ForEach(Array(snapshot.rows.filter { !["pending", "excluded"].contains($0.status) }.prefix(200))) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.headline)
                            Text(row.symbol).font(.caption).foregroundStyle(.secondary)
                            Text(label(row.status)).font(.subheadline)
                            if let through = row.through { Text(tr("价格记录截至：", "Prices through: ", "Harga hingga: ") + through).font(.caption) }
                        }
                    }
                }
            }
        }
        .navigationTitle(tr("采集结果", "Scan results", "Hasil imbasan"))
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 10_000_001) ?? Data()
                guard data.count <= 10_000_000 else { throw CloudFailure.invalidResponse }
                let value = try JSONDecoder().decode(Snapshot.self, from: data)
                let dateParser = ISO8601DateFormatter()
                dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let generated = dateParser.date(from: value.generatedAt), generated <= Date().addingTimeInterval(300) else { throw CloudFailure.invalidResponse }
                guard value.version == 1, value.provider == "EODHD", !value.fullMarketRecommendation,
                      value.recommendation == "insufficient", value.markets.count == 3,
                      Set(value.markets.map(\.market)) == Set(["KLSE", "US", "HK"]),
                      value.rows.count <= 30_000, Set(value.rows.map(\.symbol)).count == value.rows.count,
                      value.generatedAt.count <= 40,
                      value.rows.allSatisfy({ statuses.contains($0.status) && ["KLSE", "US", "HK"].contains($0.market) && $0.name.count <= 300 && $0.symbol.count <= 80 && ($0.through?.count ?? 0) <= 10 }) else { throw CloudFailure.invalidResponse }
                for market in value.markets {
                    let rows = value.rows.filter { $0.market == market.market }
                    guard (market.providerListed ?? 0) == rows.count,
                          market.states.allSatisfy({ statuses.contains($0.key) && $0.value >= 0 && $0.value <= 30_000 }),
                          market.states.values.reduce(0, +) == rows.count,
                          statuses.allSatisfy({ status in (market.states[status] ?? 0) == rows.filter { $0.status == status }.count }) else { throw CloudFailure.invalidResponse }
                }
                snapshot = value; error = ""
            } catch {
                snapshot = nil
                self.error = tr("无法读取。请选择采集器生成的 report.json（最多 10 MB、30,000 条记录）。", "Cannot read. Choose the collector's report.json (up to 10 MB and 30,000 rows).", "Tidak dapat dibaca. Pilih report.json pengumpul (sehingga 10 MB dan 30,000 rekod).")
            }
        }
        .onDisappear { snapshot = nil; error = "" }
        .onChange(of: account.researchHistoryScope) { _, _ in snapshot = nil; error = "" }
    }
}

private struct InvestmentCoverageView: View {
    private struct Coverage: Decodable {
        struct Market: Decodable, Identifiable {
            let market: String
            let configured: Int
            let readable: Int
            var id: String { market }
        }
        struct Row: Decodable, Identifiable {
            let symbol: String
            let company: String
            let status: String
            var id: String { symbol }
        }
        let kind: String
        let checkedAt: String
        let recommendation: String
        let universeComplete: Bool
        let markets: [Market]
        let rows: [Row]
    }
    @ObservedObject private var account = CloudAccount.shared
    @Environment(\.scenePhase) private var phase
    @State private var result: Coverage?
    @State private var running = false
    @State private var error = ""
    @State private var task: Task<Void, Never>?
    private func check() {
        guard !running else { return }
        running = true; error = ""; result = nil
        task = Task { @MainActor in
            defer { running = false }
            do {
                let data = try await account.checkInvestmentCoverage()
                try Task.checkCancellation()
                let value = try JSONDecoder().decode(Coverage.self, from: data)
                guard value.kind == "coverage", value.recommendation == "insufficient", !value.universeComplete,
                      Set(value.markets.map(\.market)) == Set(["MYX", "US", "HKEX"]), value.rows.count <= 100 else { throw CloudFailure.invalidResponse }
                result = value
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    var body: some View {
        List {
            Section {
                Text(tr("免费优先：马股、美股、港股", "Free first: Malaysia, US, Hong Kong", "Percuma dahulu: Malaysia, AS, Hong Kong")).font(.headline)
                Text(tr("这一步检查已接入的官方财务来源，不是全市场选股。不会调用 AI 或使用研究分析额度，也不会开通收费数据。", "This checks connected official financial sources, not the whole market. It does not call AI, use research analysis allowance or activate paid data.", "Ini menyemak sumber kewangan rasmi yang disambungkan, bukan seluruh pasaran. Tiada panggilan AI, penggunaan kuota analisis atau pengaktifan data berbayar."))
                Button(action: check) { Label(tr("检查现有资料", "Check available sources", "Semak sumber tersedia"), systemImage: "arrow.clockwise") }.disabled(running)
                if running { ProgressView(); Button(tr("取消", "Cancel", "Batal")) { task?.cancel() } }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            Section(tr("当前结论", "Current conclusion", "Kesimpulan semasa")) {
                Label(tr("暂不推荐买入或卖出时机", "No entry or exit recommendation yet", "Belum ada cadangan masa beli atau jual"), systemImage: "clock").foregroundStyle(.orange)
                Text(tr("仍缺三个市场的完整股票目录、近期股价、可比估值及完整风险资料。财报能读取不代表今天值得买；没有资料也不等于公司不好。", "Complete stock directories, recent prices, comparable valuations and full risk evidence are still missing. Readable reports do not establish a good entry today; missing evidence does not mean a bad company.", "Senarai saham lengkap, harga terkini, penilaian setanding dan bukti risiko lengkap masih tiada. Laporan boleh dibaca tidak bermakna sesuai dibeli hari ini; kekurangan bukti bukan syarikat buruk."))
            }
            if let result {
                Section(tr("实际检查范围", "Actual check coverage", "Liputan semakan sebenar")) {
                    Text(result.checkedAt).font(.caption).foregroundStyle(.secondary)
                    Text(tr("以下数量仅指已配置来源。全市场股票总数未知，未计算全市场覆盖率。", "Counts refer only to configured sources. Total market stock counts are unknown; no whole-market coverage rate is calculated.", "Bilangan hanya merujuk sumber dikonfigurasi. Jumlah saham seluruh pasaran tidak diketahui; kadar liputan tidak dikira."))
                    ForEach(result.markets) { market in
                        LabeledContent(market.market, value: "\(market.readable) / \(market.configured)")
                    }
                    Text(tr("可读取来源数／已配置来源数；读取成功不代表资料最新或完整。", "Readable / configured sources; success does not establish freshness or completeness.", "Sumber boleh dibaca / dikonfigurasi; kejayaan tidak membuktikan data terkini atau lengkap.")).font(.caption)
                }
                Section(tr("逐项结果 · 不是推荐排名", "Per-source results · Not a ranking", "Keputusan sumber · Bukan kedudukan")) {
                    ForEach(result.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.company).font(.headline)
                            Text(row.symbol).font(.caption.monospaced())
                            Text(row.status == "readable" ? tr("财务摘要可读取，仍缺买卖判断资料", "Financial summary readable; trading evidence still missing", "Ringkasan kewangan boleh dibaca; bukti dagangan masih tiada") : row.status == "not_checked" ? tr("本次未检查 PDF 来源", "PDF source not checked in this run", "Sumber PDF tidak disemak kali ini") : tr("本次读取失败，不作判断", "Read failed; no assessment", "Bacaan gagal; tiada penilaian")).font(.caption).foregroundStyle(.secondary)
                            NavigationLink(tr("查看公司研究", "Open company research", "Buka kajian syarikat")) { StockResearchView(symbols: [row.symbol]) }
                        }
                    }
                }
            }
        }.navigationTitle(tr("资料覆盖", "Data coverage", "Liputan data"))
            .onDisappear { task?.cancel(); result = nil }
            .onChange(of: account.researchHistoryScope) { _, _ in task?.cancel(); result = nil; error = "" }
            .onChange(of: phase) { _, value in if value != .active { task?.cancel() } }
    }
}

private struct BeginnerInvestmentView: View {
    @ObservedObject private var account = CloudAccount.shared
    @State private var horizon = 0
    @State private var reserve = 0
    @State private var debt = 0
    @State private var loss = 0
    private var horizons: [String] { [tr("还不确定", "Not sure", "Belum pasti"), tr("一年内要用", "Needed within a year", "Perlu dalam setahun"), tr("一至五年", "One to five years", "Satu hingga lima tahun"), tr("五年以上", "Over five years", "Lebih lima tahun")] }
    private var reserves: [String] { [tr("还不确定", "Not sure", "Belum pasti"), tr("已有独立应急钱", "Separate emergency savings ready", "Simpanan kecemasan berasingan tersedia"), tr("还没有准备好", "Not ready yet", "Belum tersedia")] }
    private var debts: [String] { [tr("还不确定", "Not sure", "Belum pasti"), tr("有高息债务", "Have high-interest debt", "Ada hutang faedah tinggi"), tr("没有高息债务", "No high-interest debt", "Tiada hutang faedah tinggi")] }
    private var losses: [String] { [tr("还不确定", "Not sure", "Belum pasti"), tr("本金亏损会影响生活", "Losses would affect daily needs", "Kerugian menjejaskan keperluan harian"), tr("可承受部分亏损，但不能全部损失", "Can bear some loss, not total loss", "Boleh menanggung sedikit kerugian, bukan semuanya")] }
    private var question: String {
        tr("我是投资新手。请先给我学习路线，不要直接推荐股票代码或买卖价格。", "I am a beginner. Give me a learning path first, not stock tickers or trading prices.", "Saya pemula. Berikan laluan pembelajaran dahulu, bukan kod saham atau harga dagangan.") + "\n" +
        tr("资金多久要用：", "When I need the money: ", "Bila wang diperlukan: ") + horizons[horizon] + "\n" +
        tr("应急储蓄：", "Emergency savings: ", "Simpanan kecemasan: ") + reserves[reserve] + "\n" +
        tr("高息债务：", "High-interest debt: ", "Hutang faedah tinggi: ") + debts[debt] + "\n" +
        tr("亏损承受情况：", "Ability to bear losses: ", "Keupayaan menanggung kerugian: ") + losses[loss] + "\n" +
        tr("请解释我还需要确认什么，以及存款、分散投资的基金／ETF和个股有什么区别。不要把这些回答当成完整的投资适合性评估。", "Explain what else I need to clarify and how deposits, diversified funds/ETFs and individual stocks differ. These answers are not a complete suitability assessment.", "Terangkan perkara yang perlu dijelaskan serta perbezaan deposit, dana/ETF terpelbagai dan saham individu. Jawapan ini bukan penilaian kesesuaian lengkap.")
    }
    var body: some View {
        Form {
            Section {
                Text(tr("先了解怎样开始，再考虑买什么。这里准备的是学习问题，不会自动选股或下单。", "Learn how to start before choosing investments. This prepares a learning question; it does not pick stocks or place orders.", "Belajar cara bermula sebelum memilih pelaburan. Ini menyediakan soalan pembelajaran, bukan memilih saham atau membuat pesanan."))
                Text(tr("选择暂留在本页；下一步可以检查问题，点击发送才会交给 Gemini。无需填写金额、银行资料或上传账单。", "Selections stay on this screen. Review the question next; only Send shares it with Gemini. No amounts, bank details or statements needed.", "Pilihan kekal di halaman ini. Semak soalan seterusnya; hanya Hantar berkongsi dengan Gemini. Tidak perlu amaun, butiran bank atau penyata.")) .font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("了解你的准备情况", "Your starting point", "Persediaan anda")) {
                Picker(tr("资金多久要用", "When money is needed", "Bila wang diperlukan"), selection: $horizon) { ForEach(horizons.indices, id: \.self) { Text(horizons[$0]).tag($0) } }
                Picker(tr("应急储蓄", "Emergency savings", "Simpanan kecemasan"), selection: $reserve) { ForEach(reserves.indices, id: \.self) { Text(reserves[$0]).tag($0) } }
                Picker(tr("高息债务", "High-interest debt", "Hutang faedah tinggi"), selection: $debt) { ForEach(debts.indices, id: \.self) { Text(debts[$0]).tag($0) } }
                Picker(tr("亏损承受情况", "Ability to bear losses", "Keupayaan menanggung kerugian"), selection: $loss) { ForEach(losses.indices, id: \.self) { Text(losses[$0]).tag($0) } }
            }
            Section {
                NavigationLink { StockChatView(initialQuestion: question) } label: {
                    Label(tr("检查问题，再问 AI", "Review question, then ask AI", "Semak soalan, kemudian tanya AI"), systemImage: "bubble.left")
                }
            }
        }.navigationTitle(tr("新手起步", "Get started", "Mula belajar"))
            .onChange(of: account.researchHistoryScope) { _, _ in horizon = 0; reserve = 0; debt = 0; loss = 0 }
    }
}

private struct StockChatView: View {
    @ObservedObject private var account = CloudAccount.shared
    @Environment(\.scenePhase) private var phase
    @State private var draft: String
    @State private var messages: [StockChatMessage] = []
    @State private var pendingQuestion: String?
    @State private var running = false
    @State private var error = ""
    @State private var task: Task<Void, Never>?
    init(initialQuestion: String = "") { _draft = State(initialValue: initialQuestion) }
    private struct Answer: Decodable { let answer: String; let kind: String; let liveData: Bool }
    private var suggestions: [String] { [tr("股票和 ETF 有什么区别？", "How do stocks and ETFs differ?", "Apakah beza saham dan ETF?"), tr("市盈率是什么意思？请举简单例子。", "What does P/E mean? Give a simple example.", "Apakah nisbah P/E? Beri contoh mudah."), tr("怎么判断一家公司的风险？", "How can I assess a company's risks?", "Bagaimana menilai risiko syarikat?")] }
    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running, !question.isEmpty, question.utf16.count <= 2000 else { return }
        var history = Array(messages.suffix(6))
        while history.reduce(0, { $0 + $1.text.utf16.count }) > 24000 { history.removeFirst(2) }
        running = true; error = ""; pendingQuestion = question
        let scope = account.researchHistoryScope
        task = Task { @MainActor in
            defer { running = false; pendingQuestion = nil }
            do {
                let data = try await account.askStockQuestion(question, history: history, language: tr("zh", "en", "ms"))
                try Task.checkCancellation()
                let answer = try JSONDecoder().decode(Answer.self, from: data)
                guard scope != nil, scope == account.researchHistoryScope, answer.kind == "education", !answer.liveData,
                      !answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.answer.utf16.count <= 12000 else { throw CloudFailure.invalidResponse }
                messages.append(StockChatMessage(role: "user", text: question))
                messages.append(StockChatMessage(role: "assistant", text: answer.answer))
                messages = Array(messages.suffix(20))
                draft = ""
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func clear() { task?.cancel(); messages = []; draft = ""; error = ""; pendingQuestion = nil }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("可以问术语、财报、ETF、风险和投资入门。这里解释知识，没有接入实时行情；不能核实今天该买什么。", "Ask about terms, reports, ETFs, risks and getting started. This explains concepts without live market data; it cannot verify what to buy today.", "Tanya istilah, laporan, ETF, risiko dan asas pelaburan. Ini menerangkan konsep tanpa data pasaran langsung; tidak dapat mengesahkan apa yang patut dibeli hari ini.")).font(.subheadline)
                Text(tr("发送时，问题和最近最多三轮对话会交给 Gemini，使用研究额度。失败也可能消耗额度。对话只在本页暂存，离开或切换账号后清除；不要输入账户密码等敏感资料。", "Send shares your question and up to three recent exchanges with Gemini, using research allowance. Failed requests may also use allowance. Chats stay on this screen and clear on leaving or switching accounts. Do not enter passwords or sensitive details.", "Hantar berkongsi soalan dan sehingga tiga pertukaran terkini dengan Gemini menggunakan kuota kajian. Permintaan gagal mungkin menggunakan kuota. Perbualan dipadam apabila keluar atau bertukar akaun. Jangan masukkan kata laluan atau maklumat sensitif.")).font(.caption).foregroundStyle(.secondary)
                if messages.isEmpty {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { draft = suggestion }.buttonStyle(.bordered).disabled(running)
                    }
                }
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message.role == "user" ? tr("你", "You", "Anda") : tr("AI · 知识解答", "AI · Explanation", "AI · Penjelasan"), systemImage: message.role == "user" ? "person" : "sparkles").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(message.text).textSelection(.enabled)
                    }
                    .padding(14)
                    .background(message.role == "user" ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                }
                if let pendingQuestion {
                    Text(pendingQuestion).padding(14)
                        .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    ProgressView(tr("正在回答…", "Preparing an answer…", "Menyediakan jawapan…"))
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
                Color.clear.frame(height: 1).id("chatBottom")
            }.padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: messages.count) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
        .onChange(of: running) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
        .onChange(of: error) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(tr("输入股票问题，可继续追问", "Ask a stock question or follow up", "Tanya soalan saham atau soalan susulan"), text: $draft, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.roundedBorder).disabled(running)
                Text("\(draft.utf16.count)/2000").font(.caption).foregroundStyle(draft.utf16.count > 2000 ? Color.red : Color.secondary)
                HStack {
                    Button(action: send) { Label(tr("发送", "Send", "Hantar"), systemImage: "arrow.up.circle.fill") }.buttonStyle(.borderedProminent)
                        .disabled(running || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf16.count > 2000)
                    if running {
                        ProgressView()
                        Button(tr("取消", "Cancel", "Batal")) { task?.cancel() }
                    }
                }
            }.padding().background(.regularMaterial)
        }
        }.navigationTitle(tr("股票问答", "Stock Q&A", "Soal jawab saham"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(tr("清空", "Clear", "Kosongkan"), action: clear) }
            .onDisappear(perform: clear)
            .onChange(of: account.researchHistoryScope) { _, _ in clear() }
            .onChange(of: phase) { _, value in if value != .active { task?.cancel() } }
    }
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
    @State private var imported: StockResearchImport?
    @State private var showingImport = false
    @State private var previousReport: ResearchHistoryEntry?
    @State private var previousScope: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func startResearch() {
        guard !running else { return }
        report = nil; error = ""; saveMessage = ""; running = true
        task = Task { @MainActor in
            defer { running = false }
            do {
                let scope = account.researchHistoryScope
                let data = try await account.researchStock(symbols: symbols, imported: imported)
                try Task.checkCancellation()
                let value = try JSONDecoder().decode(StockResearchReport.self, from: data)
                guard (value.symbols ?? [value.symbol]) == symbols, value.html.utf8.count <= 300000,
                      scope != nil, scope == account.researchHistoryScope else { throw CloudFailure.invalidResponse }
                report = value
                if imported == nil, let scope, let text = value.text, !text.isEmpty {
                    do { try ResearchHistory.save(symbols: symbols, text: text, generatedAt: value.generatedAt, scope: scope) }
                    catch { saveMessage = tr("报告已生成，但本机保存失败。", "Report ready, but local saving failed.", "Laporan siap, tetapi simpanan tempatan gagal.") }
                }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            if report == nil, imported == nil, let previousReport, let previousScope, previousScope == account.researchHistoryScope {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("上次研究 · 尚未重新核对来源", "Previous research · sources not refreshed", "Kajian terdahulu · sumber belum dikemas kini")).font(.headline)
                        Text(previousReport.generatedAt).font(.caption).foregroundStyle(.secondary)
                        Text(String(previousReport.text.prefix(400))).font(.subheadline)
                        NavigationLink { ResearchHistoryDetail(entry: previousReport, scope: previousScope) } label: {
                            Text(tr("查看完整报告", "Read full report", "Baca laporan penuh"))
                        }
                    }
                }
            }
            Text(symbols.joined(separator: " / ")).font(.headline)
            if imported == nil {
                Text(tr("不需要准备文件。点下面的按钮，App 会尝试读取公司的公开财报，帮你了解赚钱能力、负债和风险。", "No files to prepare. Tap below and the app will try to read public company reports to explain earnings, debt and risks.", "Tidak perlu menyediakan fail. Tekan butang di bawah untuk mendapatkan laporan awam dan memahami pendapatan, hutang serta risiko syarikat.")).font(.subheadline)
            }
            InvestmentDisclosure(tr("研究范围与资料说明", "Research scope and sources", "Skop kajian dan sumber")) {
            Text(tr("公开财报会交给 Gemini 整理，报告会注明日期和来源。部分资料可能较旧，不能据此判断今天是否值得买入。仅限已开通的个人账号使用，不上传你的账本。", "Public reports are sent to Gemini for analysis, with dates and sources shown. Some materials may be old and cannot establish whether today's price is attractive. Available to the enabled personal account; your ledger is not uploaded.", "Laporan awam dihantar ke Gemini untuk analisis dengan tarikh dan sumber. Sesetengah bahan mungkin lama dan tidak menentukan nilai harga hari ini. Untuk akaun peribadi yang diaktifkan; lejar anda tidak dimuat naik."))
                .font(.caption).foregroundStyle(.secondary)
            }
            if symbols.contains(where: { !ObservedStock(symbol: $0, name: $0).hasOfficialImporter }) && imported == nil {
                Text(tr("所选公司中，有些尚未接入自动研究。能否研究以服务返回为准；暂不支持时，你可以先查看行情或选择其他公司，不必自己找文件。", "Some selected companies are not yet listed for automatic research. The service will confirm availability. If unsupported, view charts or choose another company; you do not need to find files.", "Sesetengah syarikat belum disenaraikan untuk kajian automatik. Perkhidmatan akan mengesahkan ketersediaan. Jika tidak disokong, lihat carta atau pilih syarikat lain; tidak perlu mencari fail."))
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button {
                    startResearch()
                } label: {
                    Label(imported == nil ? tr("帮我研究", "Research for me", "Bantu saya mengkaji") : tr("分析导入资料", "Analyze imported materials", "Analisis bahan diimport"), systemImage: "sparkle.magnifyingglass")
                        .padding(12).foregroundStyle(.white)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(InvestmentPressStyle()).disabled(running).opacity(running ? 0.6 : 1)
                if running {
                    ProgressView()
                    Button(tr("取消", "Cancel", "Batal")) { task?.cancel() }
                }
            }
            if symbols.count == 1 {
                InvestmentDisclosure(tr("进阶选项 · 自备资料", "Advanced · Use your own files", "Lanjutan · Guna fail sendiri")) {
                Text(tr("可跳过。仅适合已经有股价 CSV 和财报文字的人。自动研究失败时，不代表你必须导入。", "Optional, for people who already have a price CSV and financial report text. An automatic research failure does not require an import.", "Pilihan untuk pengguna yang sudah mempunyai CSV harga dan teks laporan kewangan. Kegagalan kajian automatik tidak memerlukan import.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(tr("导入行情与财报文本", "Import prices and financial text", "Import harga dan teks kewangan")) { showingImport = true }
                    if imported != nil {
                        Button(tr("清除导入", "Clear import", "Kosongkan import")) { imported = nil; report = nil; error = ""; saveMessage = "" }
                    }
                }.disabled(running)
                }
                if imported != nil {
                    Text(tr("本次仅分析用户导入资料，不自动获取网页；资料未独立核实。", "This analysis uses only user imports, without fetching websites. Materials are not independently verified.", "Analisis ini hanya menggunakan import pengguna tanpa mendapatkan laman web. Bahan tidak disahkan secara bebas."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(tr("返回自动研究", "Return to automatic research", "Kembali ke kajian automatik")) { imported = nil; report = nil; error = ""; saveMessage = "" }.disabled(running)
                }
            }
            if running {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("正在准备研究报告", "Preparing research report", "Menyediakan laporan penyelidikan"), systemImage: "doc.text.magnifyingglass").font(.headline)
                    Text(tr("服务正在读取资料、分析并核对引用。完成后会显示报告，你也可以随时取消。", "The service reads sources, analyzes them and checks citations. Your report will appear when ready; you can cancel at any time.", "Perkhidmatan membaca sumber, menganalisis dan menyemak petikan. Laporan dipaparkan apabila siap; anda boleh membatalkan bila-bila masa."))
                        .font(.caption).foregroundStyle(.secondary)
                }.researchCard().accessibilityElement(children: .combine).transition(.opacity)
            }
            if !error.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    if report == nil {
                        Button(tr("重试研究", "Retry research", "Cuba semula kajian")) { startResearch() }
                            .buttonStyle(.bordered).disabled(running)
                    }
                }.researchCard().transition(.opacity)
            }
            if let report {
                if report.cached == true {
                    Text(tr("复用 24 小时内的报告；已重新核对来源内容。", "Reused a report from the last 24 hours; source content was checked again.", "Laporan dalam 24 jam digunakan semula; kandungan sumber disemak semula."))
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                if let assessments = report.assessments, !assessments.isEmpty {
                    ResearchReportCards(report: report).id(report.generatedAt).transition(.opacity)
                } else {
                    ResearchWebView(html: report.html).frame(minHeight: 600).id(report.generatedAt)
                }
            } else if !running && error.isEmpty {
                Spacer()
                Text(tr("分析会列出机会、风险、资料日期和下一步条件。评分是研究评价，不是上涨概率；缺少关键资料时不计算综合分。当前不是实时行情或后台持续监控。", "Analysis lists opportunities, risks, evidence dates and next steps. Ratings are research judgments, not winning probabilities; incomplete evidence means no overall score. This is not live pricing or background monitoring.", "Analisis menyenaraikan peluang, risiko, tarikh bukti dan langkah seterusnya. Penilaian bukan kebarangkalian untung; bukti tidak lengkap bermakna tiada skor keseluruhan. Bukan harga langsung atau pemantauan latar."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding()
        }
        .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.2), value: running)
        .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.2), value: report?.generatedAt)
        .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.2), value: error)
        .navigationTitle(tr("AI 公司研究", "AI company research", "Penyelidikan syarikat AI"))
            .investmentAssistantOrb()
            .sheet(isPresented: $showingImport) {
                StockImportForm(symbol: symbols[0]) { value in
                    imported = value; report = nil; error = ""; saveMessage = ""
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { task?.cancel(); report = nil }
            .task(id: account.researchHistoryScope) {
                previousReport = nil
                previousScope = nil
                if let scope = account.researchHistoryScope {
                    previousReport = (try? ResearchHistory.load(scope: scope))?.first { $0.symbols == symbols }
                    previousScope = scope
                }
            }
            .onChange(of: account.researchHistoryScope) { _, _ in task?.cancel(); report = nil; previousReport = nil; imported = nil; showingImport = false; error = ""; saveMessage = "" }
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
                        StockCompanyLogo(stock: stock, size: 40)
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
