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
                    Label(tr("投资观察 · AI 研究", "Investing · AI research", "Pelaburan · Penyelidikan AI"), systemImage: "sparkles")
                        .font(.title2.bold())
                    Text(tr("关注公司，理解价值", "Follow companies. Understand value.", "Ikuti syarikat. Fahami nilai."))
                        .foregroundStyle(.white.opacity(0.8))
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
                                }.buttonStyle(.plain)
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
            Section(tr("自动 AI 研究", "Automatic AI research", "Penyelidikan AI automatik")) {
                DisclosureGroup(tr("选择公司开始研究", "Choose a company to research", "Pilih syarikat untuk dikaji")) {
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
            .onAppear(perform: loadRecentResearch)
            .onChange(of: account.researchHistoryScope) { _, _ in loadRecentResearch() }
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
                NavigationLink {
                    StockResearchView(stock: stock)
                } label: {
                    Label(tr("AI 公司研究 · 个人试用", "AI company research · Personal preview", "Penyelidikan syarikat AI · Pratonton peribadi"), systemImage: "sparkles")
                }.buttonStyle(.bordered)
                Text(tr("打开图表会连接 TradingView，其服务和隐私政策适用。不会发送月记账本内容。", "Charts connect to TradingView and are subject to its service and privacy policies. Your ledger contents are not sent.", "Carta bersambung ke TradingView dan tertakluk pada dasar perkhidmatan dan privasinya. Kandungan lejar tidak dihantar."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle(tr("股票详情", "Stock details", "Butiran saham"))
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
        case "growth": return tr("成长", "Growth", "Pertumbuhan")
        case "profitability": return tr("盈利能力", "Profitability", "Keuntungan")
        case "balanceSheet": return tr("财务稳健", "Financial health", "Kesihatan kewangan")
        case "valuation": return tr("估值", "Valuation", "Penilaian")
        default: return tr("风险控制", "Risk resilience", "Ketahanan risiko")
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

private struct ResearchReportCards: View {
    let report: StockResearchReport
    @State private var browserPage: StockBrowserPage?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(report.assessments ?? []) { company in
                ResearchCompanyCards(company: company)
            }
            DisclosureGroup(tr("资料来源", "Sources", "Sumber")) {
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
                DisclosureGroup(tr("完整报告与引用", "Full report and citations", "Laporan penuh dan petikan")) {
                    Text(text).font(.subheadline).textSelection(.enabled).padding(.top, 10)
                }.padding(16).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            }
        }.sheet(item: $browserPage) { StockInAppBrowser(url: $0.url).ignoresSafeArea() }
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
    private var conclusion: String {
        guard total != nil else { return tr("观察 · 关键资料待补齐", "Watch · Key evidence missing", "Pantau · Bukti utama belum lengkap") }
        switch company.action {
        case "consider": return tr("可进一步考虑", "Consider further research", "Pertimbangkan kajian lanjut")
        case "avoid": return tr("暂不考虑", "Avoid for now", "Elakkan buat masa ini")
        default: return tr("观察，等待条件确认", "Watch for confirmation", "Pantau untuk pengesahan")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(company.symbol).font(.title3.bold())
                Label(conclusion, systemImage: total == nil ? "clock" : "doc.text.magnifyingglass")
                    .font(.headline).foregroundStyle(company.action == "avoid" && total != nil ? Color.red : Color.orange)
                Text(company.summary).textSelection(.enabled)
                Text(company.period).font(.caption).foregroundStyle(.secondary)
                if total == nil {
                    Text(company.missing).font(.subheadline).foregroundStyle(.orange)
                }
                if let total {
                    Text("\(total)/100").font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(.blue)
                } else {
                    Text(tr("综合分：资料不足", "Overall: insufficient evidence", "Keseluruhan: bukti tidak mencukupi")).foregroundStyle(.secondary)
                }
                Text(tr("研究评价，不是上涨概率", "Research rating, not a winning probability", "Penilaian kajian, bukan kebarangkalian untung")).font(.caption).foregroundStyle(.secondary)
            }.researchCard()
            VStack(alignment: .leading, spacing: 16) {
                Label(tr("财务表现与风险", "Financials and risks", "Kewangan dan risiko"), systemImage: "chart.bar.xaxis").font(.headline)
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
                            DisclosureGroup(tr("引用依据", "Evidence", "Bukti")) {
                                ForEach(Array(dimension.evidence.enumerated()), id: \.offset) { _, citation in
                                    Text("[\(citation.sourceId)] \(citation.quote)").font(.caption).textSelection(.enabled).padding(.vertical, 4)
                                }
                            }.font(.caption)
                        }
                    }
                }
            }.researchCard().opacity(revealed ? 1 : 0)
                .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.3).delay(0.08), value: revealed)
            VStack(alignment: .leading, spacing: 10) {
                Label(tr("买卖条件与判断失效", "Entry, exit and invalidation", "Syarat masuk, keluar dan pembatalan"), systemImage: "checklist").font(.headline)
                Text(company.conditions).textSelection(.enabled)
            }.researchCard().opacity(revealed ? 1 : 0)
                .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeOut(duration: 0.3).delay(0.16), value: revealed)
            VStack(alignment: .leading, spacing: 10) {
                Label(tr("仍需核实", "Still to verify", "Masih perlu disahkan"), systemImage: "exclamationmark.circle").font(.headline).foregroundStyle(.orange)
                Text(company.missing).textSelection(.enabled)
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
    func researchCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
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
                Section(symbol) {
                    Text(tr("导入 UTF-8 CSV，20–1000 个交易日，日期从旧到新。每行股票代码必须与当前股票一致。", "Import UTF-8 CSV with 20–1000 daily bars, oldest first. Every row must match this stock symbol.", "Import CSV UTF-8 dengan 20–1000 bar harian, paling lama dahulu. Setiap baris mesti sepadan dengan kod saham ini."))
                    Text("symbol,currency,date,open,high,low,close,volume").font(.caption.monospaced()).textSelection(.enabled)
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
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text(symbols.joined(separator: " / ")).font(.headline)
            Text(tr("自动读取已适配公司的官方网页或 PDF 文本，再由 Gemini 分析。部分来源为固定期间公告，不保证最新；报告列出来源、日期和资料范围。新增来源需部署新版后使用。仅供配置的个人账号使用，不上传账本。", "Fetches supported companies' official pages or PDF text for Gemini analysis. Some sources are fixed-period releases, not guaranteed latest; reports list sources, dates and scope. New sources require the updated deployment. Personal account only; no ledger upload.", "Mendapatkan halaman rasmi atau teks PDF syarikat yang disokong untuk analisis Gemini. Sesetengah sumber ialah laporan tempoh tetap, bukan semestinya terkini; laporan menyenaraikan sumber, tarikh dan skop. Sumber baharu memerlukan versi baharu. Akaun peribadi sahaja; lejar tidak dihantar."))
                .font(.caption).foregroundStyle(.secondary)
            if symbols.contains(where: { !ObservedStock(symbol: $0, name: $0).hasOfficialImporter }) && imported == nil {
                Text(tr("所选股票含尚未适配的自动来源。可打开单只股票导入行情与财报文本。", "Some stocks have no automatic source yet. Open a single stock to import prices and financial text.", "Sesetengah saham belum mempunyai sumber automatik. Buka satu saham untuk mengimport harga dan teks kewangan."))
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button {
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
                        } catch is CancellationError { }
                        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                    }
                } label: {
                    Label(imported == nil ? tr("自动获取并分析", "Fetch and analyze", "Dapatkan dan analisis") : tr("分析导入资料", "Analyze imported materials", "Analisis bahan diimport"), systemImage: "sparkle.magnifyingglass")
                }.buttonStyle(.borderedProminent).disabled(running)
                if running {
                    ProgressView()
                    Button(tr("取消", "Cancel", "Batal")) { task?.cancel() }
                }
            }
            if running {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("正在准备研究报告", "Preparing research report", "Menyediakan laporan penyelidikan"), systemImage: "doc.text.magnifyingglass").font(.headline)
                    Text(tr("服务正在读取资料、分析并核对引用。完成后会显示报告，你也可以随时取消。", "The service reads sources, analyzes them and checks citations. Your report will appear when ready; you can cancel at any time.", "Perkhidmatan membaca sumber, menganalisis dan menyemak petikan. Laporan dipaparkan apabila siap; anda boleh membatalkan bila-bila masa."))
                        .font(.caption).foregroundStyle(.secondary)
                }.researchCard().accessibilityElement(children: .combine)
            }
            if symbols.count == 1 {
                HStack {
                    Button(tr("导入行情与财报文本", "Import prices and financial text", "Import harga dan teks kewangan")) { showingImport = true }
                    if imported != nil {
                        Button(tr("清除导入", "Clear import", "Kosongkan import")) { imported = nil; report = nil; error = ""; saveMessage = "" }
                    }
                }.disabled(running)
                if imported != nil {
                    Text(tr("本次仅分析用户导入资料，不自动获取网页；资料未独立核实。", "This analysis uses only user imports, without fetching websites. Materials are not independently verified.", "Analisis ini hanya menggunakan import pengguna tanpa mendapatkan laman web. Bahan tidak disahkan secara bebas."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
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
                    ResearchReportCards(report: report).id(report.generatedAt)
                } else {
                    ResearchWebView(html: report.html).frame(minHeight: 600).id(report.generatedAt)
                }
            } else {
                Spacer()
                Text(tr("分析会列出机会、风险、资料日期和下一步条件。评分是研究评价，不是上涨概率；缺少关键资料时不计算综合分。当前不是实时行情或后台持续监控。", "Analysis lists opportunities, risks, evidence dates and next steps. Ratings are research judgments, not winning probabilities; incomplete evidence means no overall score. This is not live pricing or background monitoring.", "Analisis menyenaraikan peluang, risiko, tarikh bukti dan langkah seterusnya. Penilaian bukan kebarangkalian untung; bukti tidak lengkap bermakna tiada skor keseluruhan. Bukan harga langsung atau pemantauan latar."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding()
        }.navigationTitle(tr("AI 公司研究", "AI company research", "Penyelidikan syarikat AI"))
            .sheet(isPresented: $showingImport) {
                StockImportForm(symbol: symbols[0]) { value in
                    imported = value; report = nil; error = ""; saveMessage = ""
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { task?.cancel(); report = nil }
            .onChange(of: account.researchHistoryScope) { _, _ in task?.cancel(); report = nil; imported = nil; showingImport = false; error = ""; saveMessage = "" }
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
