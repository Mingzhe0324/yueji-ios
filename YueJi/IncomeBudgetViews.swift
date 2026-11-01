import SwiftUI
import UniformTypeIdentifiers

private struct BankWalletCard: View {
    let account: BankAccount
    let balance: Int
    var collapsed = false
    @ScaledMetric(relativeTo: .body) private var cardHeight = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var appeared = true
    private var bank: String { account.institution ?? account.name }
    private var isWise: Bool { bank.caseInsensitiveCompare("Wise") == .orderedSame }
    private var brandColor: Color {
        if isWise { return Color(red: 0.48, green: 0.72, blue: 0.18) }
        switch logo {
        case "BankMaybank": return Color(red: 1, green: 0.76, blue: 0.08)
        case "BankPublic", "BankCIMB", "BankHSBC", "BankOCBC", "BankBoost", "BankBankIslam":
            return Color(red: 0.94, green: 0.10, blue: 0.20)
        case "BankAmBank": return Color(red: 0.98, green: 0.39, blue: 0.09)
        case "BankAEON", "BankGX": return Color(red: 0.68, green: 0.30, blue: 0.95)
        case "BankStandardChartered", "BankKAF": return Color(red: 0.10, green: 0.76, blue: 0.47)
        case "BankRyt": return Color(red: 0.68, green: 0.84, blue: 0.16)
        case "BankTNG": return Color(red: 0.06, green: 0.57, blue: 1)
        case "BankRHB", "BankHongLeong", "BankUOB", "BankAffin", "BankAlliance", "BankAlRajhi":
            return Color(red: 0.12, green: 0.43, blue: 0.90)
        default: return Color(red: 0.27, green: 0.49, blue: 0.65)
        }
    }
    private var logo: String? {
        if bank.hasPrefix("Public") { return "BankPublic" }
        if account.institution?.hasPrefix("Alliance") == true { return "BankAlliance" }
        switch financialProvider(account.institution ?? "") {
        case "Maybank": return "BankMaybank"
        case "CIMB": return "BankCIMB"
        case "Hong Leong": return "BankHongLeong"
        case "GXBank": return "BankGX"
        case "RHB": return "BankRHB"
        case "AmBank": return "BankAmBank"
        case "Affin Bank": return "BankAffin"
        case "Alliance Bank": return "BankAlliance"
        case "HSBC": return "BankHSBC"
        case "OCBC": return "BankOCBC"
        case "UOB": return "BankUOB"
        case "Standard Chartered": return "BankStandardChartered"
        case "Bank Islam": return "BankBankIslam"
        case "Al Rajhi": return "BankAlRajhi"
        case "Boost Bank": return "BankBoost"
        case "AEON Bank": return "BankAEON"
        case "Ryt Bank": return "BankRyt"
        case "KAF Digital Bank": return "BankKAF"
        case "TNG": return "BankTNG"
        default: return nil
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(account.name).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if let logo {
                    Image(logo).resizable().scaledToFit().frame(width: 44, height: 26)
                        .padding(4).background(.white, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                } else if isWise {
                    Text("Wise").font(.title3.bold()).accessibilityHidden(true)
                } else {
                    Image(systemName: "building.columns.fill").font(.title3).accessibilityHidden(true)
                }
            }.frame(minHeight: 34)
            if !collapsed {
                Spacer(minLength: 20)
                Text(bank).font(.caption).foregroundStyle(.white.opacity(0.85))
                Text(money(appeared || reduceMotion ? balance : 0)).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit().contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: balance)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: appeared)
                    .accessibilityLabel(money(balance))
                    .minimumScaleFactor(0.65).lineLimit(1)
                Spacer(minLength: 20)
                HStack {
                    Text(tr("账面余额 · MYR", "Recorded balance · MYR", "Baki direkod · MYR"))
                    Spacer()
                    if let suffix = account.automaticSuffix, !suffix.isEmpty {
                        Text("•••• " + suffix).monospacedDigit()
                    }
                }.font(.caption).foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, collapsed ? 26 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: collapsed ? nil : cardHeight)
        .background(BankBreathingBackground(brand: brandColor))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.25), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.16), radius: 5, y: -2)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 14)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88), value: appeared)
        .accessibilityElement(children: .combine)
    }
}

private struct BankBreathingBackground: View {
    let brand: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    private var animates: Bool {
        visible && scenePhase == .active && !reduceMotion && !reduceTransparency && contrast != .increased
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animates)) { context in
            let breath = animates ? (sin(context.date.timeIntervalSinceReferenceDate * .pi / 4) + 1) / 2 : 0.5
            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.025, green: 0.035, blue: 0.055)
                    LinearGradient(colors: [brand.opacity(0.48), brand.opacity(0.10)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if !reduceTransparency && contrast != .increased {
                        RadialGradient(colors: [brand.opacity(0.25 + breath * 0.14), .clear],
                                       center: UnitPoint(x: 0.88, y: 0.12), startRadius: 0,
                                       endRadius: geometry.size.width * (0.65 + breath * 0.20))
                        RadialGradient(colors: [brand.opacity(0.12 + breath * 0.08), .clear],
                                       center: .bottomLeading, startRadius: 0,
                                       endRadius: geometry.size.width * 0.65)
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

private struct BankCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private struct AutomaticAccountLinksView: View {
    @EnvironmentObject var model: LedgerModel
    private enum Record: Identifiable {
        case notice(TNGNotice)
        case payment(Expense)
        var id: String {
            switch self {
            case .notice(let entry): return "notice-" + entry.id
            case .payment(let entry): return "payment-" + entry.id
            }
        }
        var date: Date {
            switch self {
            case .notice(let entry): return entry.date
            case .payment(let entry): return entry.date
            }
        }
    }
    private var records: [Record] {
        let linked = Set(model.ledger.tngNotices.compactMap(\.expenseID))
        let payments = model.ledger.expenses.filter { $0.source == "Apple Pay" && !linked.contains($0.id) }
        return (model.ledger.tngNotices.map(Record.notice) + payments.map(Record.payment))
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    var body: some View {
        List {
            Section {
                Text(tr("TNG 收款匹配账户后先加账面余额，用途确认后才计收入或还款。疑似重复和已忽略通知不自动加余额。", "Matched TNG receipts increase the account balance before their purpose is confirmed. Suspected duplicates and ignored notices are excluded.", "Penerimaan TNG dipadankan menambah baki sebelum tujuan disahkan. Notifikasi disyaki pendua dan diabaikan dikecualikan."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                switch record {
                case .payment(let entry):
                    Section {
                        LabeledContent(entry.merchant, value: money(entry.cents))
                        Text("Apple Pay · " + dateLabel(entry.date, time: true)).font(.caption).foregroundStyle(.secondary)
                        BankAccountPicker(selection: Binding(get: {
                            model.ledger.expenses.first(where: { $0.id == entry.id })?.bankAccountID
                        }, set: { accountID in
                            model.perform(key: "payment-account-" + entry.id, action: { ledger in
                                try ledger.assignApplePayAccount(id: entry.id, accountID: accountID)
                            })
                        }))
                        .disabled(entry.paidByFriend != nil || model.isWorking("payment-account-" + entry.id))
                    }
                case .notice(let notice):
                Section {
                    LabeledContent(notice.party ?? notice.provider, value: notice.cents.map { money($0) } ?? "—")
                    Text(notice.provider + " · " + dateLabel(notice.date, time: true)).font(.caption).foregroundStyle(.secondary)
                    if let suffix = notice.accountSuffix { Text("•••• " + suffix).font(.caption).monospacedDigit() }
                    BankAccountPicker(selection: Binding(get: {
                        if let id = notice.expenseID, let entry = model.ledger.expenses.first(where: { $0.id == id }) { return entry.bankAccountID }
                        return notice.bankAccountID
                    }, set: { accountID in
                        let id = notice.id
                        model.perform(key: "notice-account-" + id, action: { ledger in
                            try ledger.assignNoticeAccount(id: id, accountID: accountID)
                        })
                    })).disabled(model.isWorking("notice-account-" + notice.id))
                }
                }
            }
        }.yuejiListSurface().navigationTitle(tr("自动记录的账户", "Automatic entry accounts", "Akaun rekod automatik"))
    }
}

struct BankAccountPicker: View {
    @EnvironmentObject var model: LedgerModel
    @Binding var selection: String?
    var body: some View {
        Picker(tr("资金账户", "Money account", "Akaun wang"), selection: $selection) {
            Text(tr("未分配账户", "Unassigned", "Belum ditetapkan")).tag(String?.none)
            ForEach(model.ledger.bankAccounts) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }.accessibilityIdentifier("transaction.bankAccount")
    }
}

struct BankAccountsView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var walletTransition
    @State private var adding = false
    @State private var entered = false

    private func moveAccount(_ id: String, by offset: Int) {
        model.perform(key: "account-order", action: { ledger in
            guard let index = ledger.bankAccounts.firstIndex(where: { $0.id == id }),
                  ledger.bankAccounts.indices.contains(index + offset) else { return }
            ledger.bankAccounts.swapAt(index, index + offset)
        })
    }

    private func cardLink(_ account: BankAccount, collapsed: Bool = false) -> some View {
        NavigationLink {
            if #available(iOS 18.0, *), !reduceMotion {
                BankAccountDetail(accountID: account.id)
                    .navigationTransition(.zoom(sourceID: account.id, in: walletTransition))
            } else {
                BankAccountDetail(accountID: account.id)
            }
        } label: {
            if #available(iOS 18.0, *), !reduceMotion {
                BankWalletCard(account: account, balance: model.ledger.bankBalance(account), collapsed: collapsed, appeared: entered)
                    .matchedTransitionSource(id: account.id, in: walletTransition)
            } else {
                BankWalletCard(account: account, balance: model.ledger.bankBalance(account), collapsed: collapsed, appeared: entered)
            }
        }
        .buttonStyle(BankCardPressStyle())
        .accessibilityLabel(account.name + ", " + money(model.ledger.bankBalance(account)))
        .accessibilityHint(tr("查看账户详情", "View account details", "Lihat butiran akaun"))
        .accessibilityAction(named: Text(tr("上移", "Move up", "Alih ke atas"))) {
            moveAccount(account.id, by: -1)
        }
        .accessibilityAction(named: Text(tr("下移", "Move down", "Alih ke bawah"))) {
            moveAccount(account.id, by: 1)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(tr("账面总余额", "Recorded balance", "Baki direkod"),
                                   value: money(model.ledger.bankAccounts.reduce(0) { $0 + model.ledger.bankBalance($1) }))
                        .font(.headline).monospacedDigit()
                }
                Section(tr("我的账户", "My accounts", "Akaun saya")) {
                    ForEach(model.ledger.bankAccounts) { account in
                        cardLink(account)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }.onMove { offsets, destination in
                        let originalIDs = model.ledger.bankAccounts.map(\.id)
                        var orderedIDs = originalIDs
                        orderedIDs.move(fromOffsets: offsets, toOffset: destination)
                        let savedIDs = orderedIDs
                        model.perform(key: "account-order", action: { ledger in
                            guard ledger.bankAccounts.map(\.id) == originalIDs else {
                                throw LedgerError.invalid(tr("账户已变化，请重试排序。", "Accounts changed; reorder again.", "Akaun berubah; susun semula."))
                            }
                            let byID = Dictionary(uniqueKeysWithValues: ledger.bankAccounts.map { ($0.id, $0) })
                            ledger.bankAccounts = savedIDs.compactMap { byID[$0] }
                        })
                    }.moveDisabled(model.isWorking("account-order"))
                }
                Section {
                    NavigationLink { BankTransfersView() } label: {
                        Label(tr("转账／TNG 充值", "Transfers / TNG top-ups", "Pindahan / tambah nilai TNG"), systemImage: "arrow.left.arrow.right")
                    }.accessibilityIdentifier("bankAccount.transfers")
                    NavigationLink { AutomaticAccountLinksView() } label: {
                        Label(tr("核对自动记录的账户", "Review automatic entry accounts", "Semak akaun rekod automatik"), systemImage: "arrow.triangle.branch")
                    }
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .yuejiDashboardSurface()
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.ledger.bankAccounts.map(\.id))
            .navigationTitle(tr("账户", "Accounts", "Akaun"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel(tr("添加账户", "Add account", "Tambah akaun"))
                        .accessibilityIdentifier("bankAccount.add")
                }
            }
            .sheet(isPresented: $adding) { BankAccountEditor() }
            .onAppear { entered = true }
            .onDisappear { entered = false }
        }
    }
}

private struct BankAccountDetail: View {
    @EnvironmentObject var model: LedgerModel
    let accountID: String
    private enum Editor: String, Identifiable {
        case account, interest
        var id: String { rawValue }
    }
    @State private var editor: Editor?
    var body: some View {
        List {
            if let account = model.ledger.bankAccounts.first(where: { $0.id == accountID }) {
                BankWalletCard(account: account, balance: model.ledger.bankBalance(account))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section {
                    LabeledContent(tr("账面余额", "Recorded balance", "Baki direkod"), value: money(model.ledger.bankBalance(account)))
                        .font(.title3).monospacedDigit()
                    LabeledContent(tr("期初余额", "Opening balance", "Baki awal"), value: money(account.openingCents))
                    LabeledContent(tr("期初时间", "Opening date", "Tarikh awal")) { Text(account.openingDate, format: .dateTime.year().month().day().hour().minute()) }
                    Button(tr("编辑账户", "Edit account", "Edit akaun")) { editor = .account }
                } footer: {
                    Text(tr("期初余额指此时间之前的余额；更早的收支不会重复计入。", "Opening balance is the balance just before this time; earlier entries are not counted again.", "Baki awal ialah baki sebelum masa ini; rekod lebih awal tidak dikira semula."))
                }
                Section(tr("已分配的支出", "Assigned spending", "Belanja ditetapkan")) {
                    ForEach(model.ledger.expenses.filter { $0.bankAccountID == accountID }.sorted { $0.date > $1.date }) { entry in
                        NavigationLink {
                            ExpenseDetailView(id: entry.id, embeddedInNavigation: true)
                        } label: {
                            LabeledContent {
                                TransactionAmount(cents: entry.cents, direction: .outgoing)
                            } label: {
                                Text(entry.merchant).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                Section(tr("已分配的收入", "Assigned income", "Pendapatan ditetapkan")) {
                    Button { editor = .interest } label: {
                        Label(tr("记录银行利息", "Record bank interest", "Rekod faedah bank"), systemImage: "percent")
                    }.accessibilityIdentifier("bankAccount.interest")
                    ForEach(model.ledger.incomes.filter { $0.bankAccountID == accountID }.sorted { $0.date > $1.date }) { entry in
                        NavigationLink {
                            IncomeDetailView(id: entry.id)
                        } label: {
                            LabeledContent {
                                TransactionAmount(cents: entry.cents, direction: .incoming)
                            } label: {
                                Text(entry.source).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                Section {
                    ForEach(model.ledger.tngNotices.filter {
                        $0.bankAccountID == accountID && $0.kind == "incoming" && $0.status != "ignored" && $0.resolution == nil
                    }.sorted { $0.date > $1.date }) { notice in
                        NavigationLink { TNGIncomingView(id: notice.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(notice.party ?? notice.provider, value: money(notice.cents ?? 0))
                                Text(dateLabel(notice.date, time: true)).font(.caption).foregroundStyle(.secondary)
                                Text(notice.possibleDuplicate || (notice.status == "pending" && notice.balanceHeldForReview == true)
                                     ? tr("需复核，未自动加余额", "Review required; not automatically credited", "Perlu semakan; baki belum ditambah automatik")
                                     : (notice.verifiedIncomingBalance == true || notice.provider == "TNG" || notice.isConfirmedIncome
                                        ? tr("已计入余额，用途见详情", "Included in balance; see details for purpose", "Termasuk dalam baki; lihat tujuan dalam butiran")
                                        : tr("待确认，尚未计入余额", "Awaiting review; not included in balance", "Menunggu semakan; belum termasuk dalam baki")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(tr("到账通知", "Received money", "Wang diterima"))
                } footer: {
                    Text(tr("到账与收入不同：本人互转不计收入。早于期初时间的款项不重复计入余额。", "Receipts are not necessarily income: own transfers are excluded from income. Amounts before the opening date are not counted again.", "Penerimaan tidak semestinya pendapatan: pindahan sendiri dikecualikan. Amaun sebelum tarikh awal tidak dikira semula.")).font(.caption)
                }
                Section {
                    NavigationLink { StatementImportView(accountID: accountID) } label: {
                        Label(tr("导入月结单核对", "Reconcile statement", "Semak penyata"), systemImage: "doc.text.magnifyingglass")
                    }.accessibilityIdentifier("bankAccount.statement")
                    NavigationLink { BankTransfersView(accountID: accountID) } label: {
                        Label(tr("转账／充值记录", "Transfer history", "Sejarah pindahan"), systemImage: "arrow.left.arrow.right")
                    }
                }
            }
        }.yuejiListSurface().navigationTitle(tr("账户详情", "Account details", "Butiran akaun"))
        // Present from the stable screen, not a lazily hosted List section.
        .sheet(item: $editor) { destination in
            if let account = model.ledger.bankAccounts.first(where: { $0.id == accountID }) {
                switch destination {
                case .account:
                    BankAccountEditor(original: account).environmentObject(model)
                case .interest:
                    IncomeEditor(initialKind: .interest, initialAccountID: account.id).environmentObject(model)
                }
            }
        }
    }
}

private struct BankTransfersView: View {
    @EnvironmentObject var model: LedgerModel
    var accountID: String? = nil
    @State private var adding = false
    @State private var editing: BankTransfer?
    private var transfers: [BankTransfer] {
        model.ledger.bankTransfers.filter { accountID == nil || $0.fromAccountID == accountID || $0.toAccountID == accountID }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    private func name(_ id: String) -> String {
        model.ledger.bankAccounts.first(where: { $0.id == id })?.name ?? "—"
    }
    var body: some View {
        List {
            if transfers.isEmpty {
                Text(tr("还没有转账记录", "No transfers yet", "Belum ada pindahan")).foregroundStyle(.secondary)
            }
            ForEach(transfers) { transfer in
                Button { editing = transfer } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name(transfer.fromAccountID) + " → " + name(transfer.toAccountID)).font(.headline)
                        HStack {
                            Text(dateLabel(transfer.date, time: true)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let accountID {
                                TransactionAmount(cents: transfer.cents, direction: transfer.toAccountID == accountID ? .incoming : .outgoing)
                            } else {
                                // Both sides of an own-account transfer; no net income.
                                TransactionAmount(cents: transfer.cents, direction: .neutral)
                            }
                        }
                        if !transfer.note.isEmpty { Text(transfer.note).font(.caption).foregroundStyle(.secondary) }
                    }.foregroundStyle(.primary)
                }
            }
        }.yuejiListSurface()
        .navigationTitle(tr("转账／充值", "Transfers / top-ups", "Pindahan / tambah nilai"))
        .toolbar {
            Button { adding = true } label: { Image(systemName: "plus") }
                .accessibilityLabel(tr("记录转账", "Record transfer", "Rekod pindahan"))
                .disabled(model.ledger.bankAccounts.count < 2)
        }
        .safeAreaInset(edge: .bottom) {
            if model.ledger.bankAccounts.count < 2 {
                Text(tr("请先添加至少两个资金账户。", "Add at least two accounts first.", "Tambah sekurang-kurangnya dua akaun dahulu."))
                    .font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $adding) { BankTransferEditor(initialAccountID: accountID) }
        .sheet(item: $editing) { BankTransferEditor(original: $0) }
    }
}

private struct BankTransferEditor: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    var original: BankTransfer? = nil
    var initialAccountID: String? = nil
    @State private var fromID = ""
    @State private var toID = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var draftID = UUID().uuidString
    @State private var initialized = false
    @State private var deleting = false
    @State private var error: String?
    private var key: String { "bank-transfer-" + (original?.id ?? draftID) }
    private var saving: Bool { model.isWorking(key) }
    private var beforeOpening: Bool {
        model.ledger.bankAccounts.contains { ($0.id == fromID || $0.id == toID) && date < $0.openingDate }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("转出账户", "From account", "Akaun asal"), selection: $fromID) {
                        Text(tr("请选择", "Choose", "Pilih")).tag("")
                        ForEach(model.ledger.bankAccounts) { Text($0.name).tag($0.id) }
                    }
                    Picker(tr("转入账户", "To account", "Akaun penerima"), selection: $toID) {
                        Text(tr("请选择", "Choose", "Pilih")).tag("")
                        ForEach(model.ledger.bankAccounts) { Text($0.name).tag($0.id) }
                    }
                    TextField(tr("转账金额 MYR", "Transfer amount MYR", "Amaun pindahan MYR"), text: $amount).keyboardType(.decimalPad)
                    DatePicker(tr("转账时间", "Transfer date", "Tarikh pindahan"), selection: $date, in: ...Date())
                    TextField(tr("备注（可选）", "Note (optional)", "Nota (pilihan)"), text: $note)
                } footer: {
                    Text(tr("仅记录已完成的转账，不会实际转钱。TNG 充值请选择银行转出、TNG 转入。本金不计收入或消费；如有手续费，请另外记一笔支出并选择转出账户。", "Records completed transfers; does not move real money. For TNG top-ups, select the bank as source and TNG as destination. Principal is neither income nor spending. Record any fee separately as an expense on the source account.", "Merekod pindahan selesai, bukan memindahkan wang sebenar. Untuk tambah nilai TNG, pilih bank sebagai asal dan TNG sebagai penerima. Prinsipal bukan pendapatan atau belanja. Rekod fi secara berasingan sebagai belanja akaun asal."))
                }
                if beforeOpening {
                    Text(tr("转账早于部分账户的期初时间：该账户已包含这笔资金，不会再次增减。请核对时间和期初余额。", "This transfer predates an account's opening balance and will not change that account again. Check the date and opening balances.", "Pindahan mendahului baki awal sesetengah akaun dan tidak mengubahnya lagi. Semak tarikh dan baki awal."))
                        .font(.footnote).foregroundStyle(.orange)
                }
                if original != nil {
                    Button(tr("删除转账", "Delete transfer", "Padam pindahan"), role: .destructive) { deleting = true }
                }
            }.yuejiListSurface().disabled(saving)
            .navigationTitle(tr("记录转账", "Record transfer", "Rekod pindahan"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { EditorSaveLabel(saving: saving) }
                        .disabled(saving || fromID.isEmpty || toID.isEmpty || fromID == toID || amount.isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
            .onAppear {
                guard !initialized else { return }; initialized = true
                fromID = original?.fromAccountID ?? initialAccountID ?? model.ledger.bankAccounts.first?.id ?? ""
                toID = original?.toAccountID ?? model.ledger.bankAccounts.first(where: { $0.id != fromID })?.id ?? ""
                if let original { amount = Currency.input(original.cents, "MYR"); date = original.date; note = original.note }
            }
            .confirmationDialog(tr("删除后将重新计算两边余额。", "Deleting recalculates both balances.", "Memadam mengira semula kedua-dua baki."), isPresented: $deleting) {
                Button(tr("删除转账", "Delete transfer", "Padam pindahan"), role: .destructive) {
                    guard let original else { return }
                    model.perform(key: key, action: { try $0.deleteBankTransfer(original) }, completion: { _ in dismiss() }, failure: { error = $0.localizedDescription })
                }
            }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }.ledgerFeedback(modal: true)
    }
    private func save() {
        do {
            let transfer = BankTransfer(id: original?.id ?? draftID, fromAccountID: fromID, toAccountID: toID,
                                        cents: try Currency.parse(amount, code: "MYR"), date: date,
                                        note: note.trimmingCharacters(in: .whitespacesAndNewlines), noticeIDs: original?.noticeIDs)
            let before = original
            model.perform(key: key, action: { try $0.saveBankTransfer(transfer, replacing: before) },
                          completion: { _ in dismiss() }, failure: { error = $0.localizedDescription })
        } catch { self.error = error.localizedDescription }
    }
}

private struct BankAccountEditor: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    var original: BankAccount? = nil
    @State private var name = ""
    @State private var institution = ""
    @State private var automaticSource = ""
    @State private var automaticSuffix = ""
    @State private var amount = ""
    @State private var openingDate = Date()
    @State private var initialized = false
    @State private var error: String?
    @State private var draftID = UUID().uuidString
    private var operationKey: String { "bank-account-" + (original?.id ?? draftID) }
    private var saving: Bool { model.isWorking(operationKey) }
    var body: some View {
        NavigationStack {
            Form {
                Picker(tr("选择银行／钱包", "Choose bank / wallet", "Pilih bank / dompet"), selection: $institution) {
                    Text(tr("其他银行／钱包（自定义）", "Other bank / wallet (custom)", "Bank / dompet lain (tersuai)")).tag("")
                    Section(tr("商业银行", "Conventional banks", "Bank konvensional")) {
                        ForEach(MalaysianBanks.conventional, id: \.self) { Text($0).tag($0) }
                    }
                    Section(tr("伊斯兰银行", "Islamic banks", "Bank Islam")) {
                        ForEach(MalaysianBanks.islamic, id: \.self) { Text($0).tag($0) }
                    }
                    Section(tr("数字银行", "Digital banks", "Bank digital")) {
                        ForEach(MalaysianBanks.digital, id: \.self) { Text($0).tag($0) }
                    }
                    Section(tr("钱包与支付账户", "Wallets and payment accounts", "Dompet dan akaun pembayaran")) {
                        ForEach(MalaysianBanks.walletsAndPayments, id: \.self) { Text($0).tag($0) }
                    }
                    if !institution.isEmpty && !(MalaysianBanks.conventional + MalaysianBanks.islamic + MalaysianBanks.digital + MalaysianBanks.walletsAndPayments).contains(institution) {
                        Text(institution).tag(institution)
                    }
                }.pickerStyle(.navigationLink)
                    .onChange(of: institution) { old, new in
                        if name.isEmpty || name == old { name = new }
                    }
                TextField(tr("例如 Maybank 储蓄账户", "e.g. Maybank savings", "cth. Simpanan Maybank"), text: $name)
                TextField(tr("期初余额 MYR", "Opening balance MYR", "Baki awal MYR"), text: $amount).keyboardType(.numbersAndPunctuation)
                DatePicker(tr("期初时间", "Opening date", "Tarikh awal"), selection: $openingDate, in: ...Date())
                Section {
                    Picker(tr("自动记账来源", "Automatic entry source", "Sumber rekod automatik"), selection: $automaticSource) {
                        Text(tr("关闭", "Off", "Tutup")).tag("")
                        ForEach(financialProviderAliases.map { $0.0 }, id: \.self) { Text($0).tag($0) }
                        if !automaticSource.isEmpty && !financialProviderAliases.contains(where: { $0.0 == automaticSource }) {
                            Text(automaticSource).tag(automaticSource)
                        }
                    }.pickerStyle(.navigationLink)
                    if !automaticSource.isEmpty {
                        TextField(tr("账号尾号（可选，4 位）", "Last four digits (optional)", "Empat digit akhir (pilihan)"), text: $automaticSuffix)
                            .keyboardType(.numberPad)
                        Text(tr("填写尾号后，通知必须包含相同尾号才能自动匹配。如果同一来源只有一个账户，而通知没有尾号，请留空。", "If entered, notices must contain the same last four digits to match. Leave blank when this source has only one account and its notices contain no suffix.", "Jika diisi, notifikasi mesti mengandungi empat digit yang sama. Biarkan kosong jika sumber ini hanya mempunyai satu akaun dan notifikasi tiada digit akhir."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(tr("仅影响保存后新导入的通知。来源和尾号匹配时自动关联；同一来源有多个账户而通知无法区分时，留待手动选择。付款扣余额，通知收入确认后加余额。", "Applies to newly imported notices only. Matching source and suffix link automatically; ambiguous accounts require selection. Payments reduce the balance; notification income increases it after confirmation.", "Untuk notifikasi baharu sahaja. Sumber dan digit sepadan dipaut automatik; akaun tidak jelas perlu dipilih. Bayaran mengurangkan baki; pendapatan menambahnya selepas pengesahan."))
                }
                Text(tr("填写这个时间点之前的余额，可填 0 或负数。修改期初余额或时间会重新计算账面余额。无需银行卡号或银行密码。", "Enter the balance just before this time, including zero or a negative amount. Changing the opening balance or date recalculates your recorded balance. No bank number or password needed.", "Masukkan baki sebelum masa ini, termasuk sifar atau negatif. Perubahan baki atau tarikh awal mengira semula baki. Tidak perlu nombor atau kata laluan bank."))
                    .font(.footnote).foregroundStyle(.secondary)
            }.yuejiListSurface()
            .navigationTitle(tr("银行／钱包账户", "Bank / wallet account", "Akaun bank / dompet"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { EditorSaveLabel(saving: saving) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount.isEmpty)
                }
            }.disabled(saving).interactiveDismissDisabled(saving)
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let original {
                    institution = original.institution ?? ""
                    automaticSource = original.automaticSource ?? ""
                    automaticSuffix = original.automaticSuffix ?? ""
                    name = original.name; amount = Currency.input(original.openingCents, "MYR"); openingDate = original.openingDate
                }
            }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }.ledgerFeedback(modal: true)
    }
    private func save() {
        do {
            let raw = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            let negative = raw.hasPrefix("-")
            let magnitude = negative ? String(raw.dropFirst()) : raw
            let cents = ["0", "0.0", "0.00"].contains(magnitude) ? 0 : try Currency.parse(magnitude, code: "MYR")
            let account = BankAccount(id: original?.id ?? draftID, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                      openingCents: negative ? -cents : cents, openingDate: openingDate,
                                      institution: institution.isEmpty ? nil : institution,
                                      automaticSource: automaticSource.isEmpty ? nil : automaticSource,
                                      automaticSuffix: automaticSource.isEmpty || automaticSuffix.isEmpty ? nil : automaticSuffix)
            let savedAccount = account
            let before = original
            model.perform(key: operationKey, action: { ledger in
                if let before {
                    guard let index = ledger.bankAccounts.firstIndex(where: { $0.id == before.id }), ledger.bankAccounts[index] == before else {
                        throw LedgerError.invalid("Account changed; reopen and try again")
                    }
                    ledger.bankAccounts[index] = savedAccount
                } else { ledger.bankAccounts.append(savedAccount) }
                try ledger.validateBankAccounts()
            }, completion: { _ in dismiss() }, failure: { error = $0.localizedDescription })
        } catch { self.error = error.localizedDescription }
    }
}
import UIKit

/// Incoming amounts use cyan; the light variant is darker for legible small text.
enum IncomeStyle {
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemCyan : UIColor(red: 0.0, green: 0.43, blue: 0.56, alpha: 1)
    })
}

struct IncomeBudgetPrompt: Identifiable, Equatable {
    let id = UUID()
    let outcome: IncomeBudgetOutcome
    var title: String {
        if let added = outcome.automatic { return incomeAddedMessage(added, month: outcome.month) }
        return tr("已记录收入 " + money(outcome.cents) + "。", "Income of " + money(outcome.cents) + " recorded.", "Pendapatan " + money(outcome.cents) + " direkod.")
    }
    var message: String {
        let month = budgetMonthLabel(outcome.month)
        if outcome.automatic != nil, let percent = outcome.percent {
            return tr("收入 \(money(outcome.cents)) 的 \(percent)% 已自动加入 · ", "\(percent)% of \(money(outcome.cents)) added automatically · ", "\(percent)% daripada \(money(outcome.cents)) ditambah secara automatik · ") + outcome.name
        }
        if let duplicate = outcome.duplicateName {
            return tr("可能与已加入预算的「" + duplicate + "」是同一笔钱，请先核对。", "It may be the same money as " + duplicate + ", already in a budget. Review it first.", "Ia mungkin wang yang sama dengan " + duplicate + " yang sudah dalam bajet. Semak dahulu.")
        }
        if monthKey(outcome.incomeDate) != outcome.month {
            // Older income still goes to the current month, and says so.
            return tr("加入" + month + "预算？（收入日期 " + dateLabel(outcome.incomeDate) + "）", "Add it to the " + month + " budget? It's dated " + dateLabel(outcome.incomeDate) + ".", "Tambah ke bajet " + month + "? Bertarikh " + dateLabel(outcome.incomeDate) + ".")
        }
        return tr("加入本月（" + month + "）预算？", "Add it to this month's budget (" + month + ")?", "Tambah ke bajet bulan ini (" + month + ")?")
    }
}

struct IncomeAllocationRequest: Identifiable, Equatable {
    let id = UUID()
    let source: String
    /// Changes the amount already in this month's budget; nil adds more.
    var month: String? = nil
    /// The modal screen that shows the sheet; nil for the main screens.
    var presenter: UUID? = nil
}

/// The compact, non-blocking prompt: Add all, Choose amount or Not now. Swiping it away or
/// letting it time out is "Not now"; the income's details still offer it later.
struct IncomeBudgetPromptCard: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let prompt: IncomeBudgetPrompt
    let interaction: BannerInteraction
    private var working: Bool { model.isWorking("allocation-" + prompt.outcome.source) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if !typeSize.isAccessibilitySize {
                    Image("YueJiLogo").resizable().scaledToFit().frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Circle().fill(IncomeStyle.tint))
                                .overlay(Circle().strokeBorder(IslandTheme.card, lineWidth: 2)).offset(x: 5, y: 5)
                        }
                        .padding(.trailing, 4).padding(.bottom, 4).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.title).font(.subheadline.weight(.semibold))
                    Text(prompt.message).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                Button { if interaction.canActivate { interaction.dismiss?() } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(tr("关闭提示", "Dismiss notice", "Tutup notis"))
            }
            actions.padding(.leading, typeSize.isAccessibilitySize ? 0 : 54).padding(.trailing, 8)
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 8)
        .modifier(NotificationBannerSurface())
        .accessibilityElement(children: .contain)
        .accessibilityHint(tr("向左、向右或向上滑动可关闭提示。", "Swipe left, right, or up to dismiss.", "Leret ke kiri, kanan atau atas untuk menutup."))
        .accessibilityAction(.escape) { interaction.dismiss?() }
    }
    @ViewBuilder private var actions: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if prompt.outcome.automatic != nil {
                action(tr("修改", "Change", "Ubah"), prominent: true) { model.chooseIncomeAmount(prompt) }
            } else if prompt.outcome.duplicateName != nil {
                action(tr("核对", "Review", "Semak"), prominent: true) { model.chooseIncomeAmount(prompt) }
                action(tr("暂不", "Not now", "Bukan sekarang")) { interaction.dismiss?() }
            } else {
                action(tr("全部加入", "Add all", "Tambah semua"), prominent: true) { model.addAllIncome(prompt) }
                    .accessibilityIdentifier("income.prompt.addAll")
                action(tr("选择金额", "Choose amount", "Pilih amaun")) { model.chooseIncomeAmount(prompt) }
                    .accessibilityIdentifier("income.prompt.choose")
                action(tr("暂不", "Not now", "Bukan sekarang")) { interaction.dismiss?() }
                    .accessibilityIdentifier("income.prompt.notNow")
            }
        }
    }
    private func action(_ title: String, prominent: Bool = false, perform: @escaping () -> Void) -> some View {
        Button { if interaction.canActivate && !working { perform() } } label: {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .foregroundStyle(prominent ? Color.white : IncomeStyle.tint)
                .background(Capsule().fill(prominent ? IncomeStyle.tint : IncomeStyle.tint.opacity(0.14)))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(working)
        .accessibilityAction { if !interaction.exiting && !working { perform() } }
    }
}

private struct IncomeSummaryRow: View {
    let income: IncomeSource
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IslandIconTile(symbol: income.kind.symbol, color: IncomeStyle.tint, size: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(income.name).font(.headline).lineLimit(2)
                Text(income.kind.label + " · " + sourceLabel(income.provider) + " · " + dateLabel(income.date))
                    .font(.caption).foregroundStyle(.secondary)
                if let fx = income.foreign {
                    Text(Currency.display(fx.minor, fx.currency) + " · 1 \(fx.currency) = \(fx.quote.text) MYR")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            TransactionAmount(cents: income.cents, direction: .incoming).font(.headline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Add part of an income to a month's budget, or change the amount already there. Only that
/// month's budget changes: never the income, the spending or the number of records.
struct IncomeAllocationSheet: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: LedgerModel
    let request: IncomeAllocationRequest
    @State private var month = monthKey(Date())
    @State private var amount = ""
    @State private var distinct = false
    @State private var initialized = false
    /// The month's amount when the sheet opened: a stale or repeated save is refused.
    @State private var seen = 0
    @State private var confirmingRemoval = false
    @State private var error: String?
    private var ledger: Ledger { model.ledger }
    private var income: IncomeSource? { ledger.incomeSource(request.source) }
    private var adjusting: Bool { request.month != nil }
    private var working: Bool { model.isWorking("allocation-" + request.source) }
    private var current: Int { ledger.allocations(for: request.source).first(where: { $0.month == month })?.cents ?? 0 }
    private var left: Int { ledger.unallocated(for: request.source) }
    /// The most the field accepts: more to add, or the month's new total.
    private var maximum: Int { adjusting ? current + left : left }
    private var entered: Int? { try? toCents(amount) }
    private var newTotal: Int? { entered.map { adjusting ? $0 : current + $0 } }
    private var duplicate: IncomeSource? {
        ledger.allocatedTotal(for: request.source) == 0 ? ledger.likelyDuplicateIncome(of: request.source) : nil
    }
    private var canSave: Bool {
        guard let entered, entered > 0, entered <= maximum, newTotal != current else { return false }
        return duplicate == nil || distinct
    }
    /// The current month by default, the income's own month and the next one.
    private var months: [String] {
        let now = Date()
        var keys = [monthKey(now), monthKey(shiftedMonth(now, by: 1))]
        if let income { keys.append(monthKey(income.date)) }
        if let fixed = request.month { keys.append(fixed) }
        return Array(Set(keys)).sorted()
    }
    var body: some View {
        let _ = uiLocale.identifier
        NavigationStack {
            Form {
                if let income {
                    Section {
                        IncomeSummaryRow(income: income)
                        LabeledContent(tr("尚未加入预算", "Not yet in a budget", "Belum dalam bajet"), value: money(left))
                    }
                    Section {
                        if adjusting {
                            LabeledContent(tr("预算月份", "Budget month", "Bulan bajet"), value: budgetMonthLabel(month))
                        } else {
                            Picker(tr("加入", "Add to", "Tambah ke"), selection: $month) {
                                ForEach(months, id: \.self) { key in
                                    Text(budgetMonthLabel(key) + (key == monthKey(Date()) ? tr("（本月）", " (this month)", " (bulan ini)") : "")).tag(key)
                                }
                            }.accessibilityIdentifier("income.allocation.month")
                        }
                        if monthKey(income.date) != month {
                            Label(tr("这笔收入日期为 " + dateLabel(income.date) + "，将计入" + budgetMonthLabel(month) + "的预算。",
                                     "This income is dated " + dateLabel(income.date) + ". It will count towards the " + budgetMonthLabel(month) + " budget.",
                                     "Pendapatan ini bertarikh " + dateLabel(income.date) + ". Ia dikira dalam bajet " + budgetMonthLabel(month) + "."),
                                  systemImage: "calendar.badge.exclamationmark")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: { Text(tr("目标预算", "Destination", "Destinasi")) }
                    Section {
                        HStack {
                            Text("RM").foregroundStyle(.secondary)
                            TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .font(.title3.weight(.semibold)).monospacedDigit()
                                .accessibilityIdentifier("income.allocation.amount")
                        }
                        if maximum > 0 {
                            Button(tr("全部 ", "Use all ", "Guna semua ") + money(maximum)) { amount = Currency.input(maximum, "MYR") }
                        }
                        if let entered, entered > maximum {
                            Text(tr("最多 ", "No more than ", "Tidak melebihi ") + money(maximum) + tr("：这是这笔收入尚未加入预算的金额。", ": what this income has left to add.", ": baki pendapatan ini."))
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    } header: {
                        Text(adjusting ? tr("此月份的金额", "Amount for this month", "Amaun untuk bulan ini") : tr("加入金额", "Amount to add", "Amaun untuk ditambah"))
                    } footer: {
                        Text(tr("只改变这个月的预算；收入本身、消费和账目数量都不变。", "Only this month's budget changes. The income, your spending and your records stay the same.", "Hanya bajet bulan ini berubah. Pendapatan, belanja dan rekod anda kekal."))
                    }
                    budgetPreview
                    if let duplicate {
                        Section {
                            Label(tr("「" + duplicate.name + "」金额相同、日期相近，已经加入预算。若是同一笔钱，请勿重复加入。",
                                     duplicate.name + " has the same amount, a close date and is already in a budget. If it's the same money, don't add it twice.",
                                     duplicate.name + " mempunyai amaun sama, tarikh hampir dan sudah dalam bajet. Jika wang yang sama, jangan tambah dua kali."),
                                  systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Toggle(tr("已核对：这是另一笔收入", "Checked: this is separate income", "Disemak: ini pendapatan berasingan"), isOn: $distinct)
                        }
                    }
                    if adjusting && current > 0 {
                        Section {
                            Button(tr("从这个月的预算移除", "Remove from this month's budget", "Buang daripada bajet bulan ini"), role: .destructive) { confirmingRemoval = true }
                        }
                    }
                } else {
                    Text(tr("这笔记录已删除，或尚未确认为收入。", "This record was deleted or isn't confirmed as income.", "Rekod ini dipadam atau belum disahkan sebagai pendapatan."))
                }
            }
            .yuejiListSurface()
            .navigationTitle(adjusting ? tr("修改预算金额", "Change budget amount", "Ubah amaun bajet") : tr("加入预算", "Add to budget", "Tambah ke bajet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("取消", "Cancel", "Batal"), systemImage: "xmark") { dismiss() }.disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { EditorSaveLabel(saving: working) }
                        .disabled(!canSave || working).accessibilityIdentifier("income.allocation.save")
                }
            }
            .disabled(working)
            .interactiveDismissDisabled(working)
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if let fixed = request.month { month = fixed }
                seen = current
                let suggested = adjusting ? current : left
                if suggested > 0 { amount = Currency.input(suggested, "MYR") }
            }
            .onChange(of: month) { _, _ in
                seen = current
                if !adjusting, let entered, entered > maximum { amount = maximum > 0 ? Currency.input(maximum, "MYR") : "" }
            }
            .confirmationDialog(tr("从预算移除？", "Remove from the budget?", "Buang daripada bajet?"), isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button(tr("移除 ", "Remove ", "Buang ") + money(current), role: .destructive) { commit(total: 0) }
            } message: {
                Text(budgetAdjustmentSummary([BudgetAdjustment(month: month, before: current, after: 0)]) + "\n"
                     + tr("收入记录保留，之后可再加入。", "The income stays recorded and can be added again later.", "Pendapatan kekal direkod dan boleh ditambah semula kemudian."))
            }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }.yuejiSheetSurface()
    }
    /// Base budget + income allocations − eligible spending = remaining, before and after.
    @ViewBuilder private var budgetPreview: some View {
        if let total = newTotal, let date = budgetMonthDate(month) {
            let budget = ledger.monthlyBudget(month)
            let spent = ledger.dailyBudgetSpending(in: date)
            let after = MonthlyBudget(base: budget.base, income: budget.income - current + total)
            Section {
                LabeledContent(tr("基本预算", "Base budget", "Bajet asas"), value: money(budget.base))
                LabeledContent(tr("收入加入", "Income added", "Pendapatan ditambah")) {
                    Text(money(budget.income) + " → " + money(after.income)).foregroundStyle(IncomeStyle.tint).monospacedDigit()
                }
                LabeledContent(tr("计入预算的消费", "Eligible spending", "Belanja dikira"), value: money(spent))
                LabeledContent(after.remaining(spent: spent) >= 0 ? tr("剩余", "Remaining", "Baki") : tr("超出", "Over budget", "Melebihi")) {
                    Text(money(abs(after.remaining(spent: spent)))).fontWeight(.semibold).monospacedDigit()
                }
            } header: {
                Text(tr(budgetMonthLabel(month) + " 预算", budgetMonthLabel(month) + " budget", "Bajet " + budgetMonthLabel(month)))
            } footer: {
                Text(tr("基本预算 + 收入加入 − 计入预算的消费 = 剩余。旅行账本的消费另计。", "Base budget + income added − eligible spending = remaining. Travel book spending is kept apart.", "Bajet asas + pendapatan ditambah − belanja dikira = baki. Belanja buku perjalanan diasingkan."))
            }
        }
    }
    private func save() {
        guard canSave, let total = newTotal else { return }
        commit(total: total)
    }
    private func commit(total: Int) {
        let source = request.source, target = month, expected = seen, separate = distinct
        let change = total - expected
        model.perform(key: "allocation-" + source, action: { ledger in
            try ledger.setIncomeAllocation(source: source, month: target, cents: total, expected: expected, confirmedDistinct: separate)
        }, completion: { _ in
            let message = change > 0 ? incomeAddedMessage(change, month: target)
                : tr("已从" + budgetMonthLabel(target) + "预算减少 " + money(-change), money(-change) + " taken out of the " + budgetMonthLabel(target) + " budget", money(-change) + " dikeluarkan daripada bajet " + budgetMonthLabel(target))
            model.showSaved(message: message, sound: change > 0 ? .deposit : .saved)
            dismiss()
        }, failure: { error = $0.localizedDescription })
    }
}

/// The income's budget: where it went, what is left, and changes or removal per month.
struct IncomeBudgetSection: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var model: LedgerModel
    let source: String
    @Binding var request: IncomeAllocationRequest?
    @Binding var removing: BudgetAllocation?
    var body: some View {
        let _ = uiLocale.identifier
        if model.ledger.incomeSource(source) != nil {
            let allocations = model.ledger.allocations(for: source)
            let left = model.ledger.unallocated(for: source)
            Section {
                ForEach(allocations) { allocation in
                    HStack(spacing: 12) {
                        IslandIconTile(symbol: "gauge.with.dots.needle.33percent", color: IncomeStyle.tint, size: 30, filled: true)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr(budgetMonthLabel(allocation.month) + " 预算", budgetMonthLabel(allocation.month) + " budget", "Bajet " + budgetMonthLabel(allocation.month)))
                            if allocation.automatic == true {
                                Text(tr("自动加入", "Added automatically", "Ditambah secara automatik")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("+" + money(allocation.cents)).monospacedDigit().fontWeight(.semibold).foregroundStyle(IncomeStyle.tint)
                    }
                    .accessibilityElement(children: .combine)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { removing = allocation } label: { Label(tr("移除", "Remove", "Buang"), systemImage: "minus.circle") }.tint(.red)
                        Button { request = IncomeAllocationRequest(source: source, month: allocation.month) } label: {
                            Label(tr("修改", "Change", "Ubah"), systemImage: "slider.horizontal.3")
                        }.tint(IncomeStyle.tint)
                    }
                    .contextMenu {
                        Button(tr("修改金额", "Change amount", "Ubah amaun"), systemImage: "slider.horizontal.3") {
                            request = IncomeAllocationRequest(source: source, month: allocation.month)
                        }
                        Button(tr("从预算移除", "Remove from budget", "Buang daripada bajet"), systemImage: "minus.circle", role: .destructive) { removing = allocation }
                    }
                }
                LabeledContent(left > 0 ? tr("尚未加入预算", "Not yet in a budget", "Belum dalam bajet") : tr("已全部加入预算", "All added to budgets", "Semua dalam bajet"), value: money(left))
                if left > 0 {
                    Button { request = IncomeAllocationRequest(source: source) } label: {
                        Label(tr("加入预算", "Add to budget", "Tambah ke bajet"), systemImage: "plus.circle.fill")
                    }
                    .foregroundStyle(IncomeStyle.tint)
                    .accessibilityIdentifier("income.budget.add")
                }
            } header: {
                Text(tr("预算", "Budget", "Bajet"))
            } footer: {
                Text(tr("加入预算只提高该月预算；收入金额不变，也不会新增记录。可随时减少或移除。", "Adding income to a budget only raises that month's budget. The income amount stays the same and no record is added. Reduce or remove it any time.", "Menambah pendapatan ke bajet hanya menaikkan bajet bulan itu. Amaun pendapatan kekal dan tiada rekod ditambah. Kurangkan atau buang bila-bila masa."))
            }
            .animation(reduceMotion ? nil : YueJiMotion.rows, value: allocations)
        }
    }
}

/// Presents the amount sheet and the removal confirmation for an `IncomeBudgetSection`, from
/// the stable screen rather than a row that may scroll away.
struct IncomeBudgetPresentation: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
    @Binding var request: IncomeAllocationRequest?
    @Binding var removing: BudgetAllocation?
    @State private var failure: String?
    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { IncomeAllocationSheet(request: $0).environmentObject(model) }
            .confirmationDialog(tr("从预算移除？", "Remove from the budget?", "Buang daripada bajet?"),
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { allocation in
                Button(tr("移除 ", "Remove ", "Buang ") + money(allocation.cents), role: .destructive) { remove(allocation) }
                Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
            } message: { allocation in
                Text(budgetAdjustmentSummary([BudgetAdjustment(month: allocation.month, before: allocation.cents, after: 0)]) + "\n"
                     + tr("收入记录保留，之后可再加入。", "The income stays recorded and can be added again later.", "Pendapatan kekal direkod dan boleh ditambah semula kemudian."))
            }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") {}
            } message: { Text(failure ?? "") }
    }
    private func remove(_ allocation: BudgetAllocation) {
        model.perform(key: "allocation-" + allocation.source, action: { ledger in
            try ledger.setIncomeAllocation(source: allocation.source, month: allocation.month, cents: 0, expected: allocation.cents)
        }, completion: { _ in
            model.showSaved(message: tr("已从" + budgetMonthLabel(allocation.month) + "预算移除 " + money(allocation.cents), money(allocation.cents) + " removed from the " + budgetMonthLabel(allocation.month) + " budget", money(allocation.cents) + " dibuang daripada bajet " + budgetMonthLabel(allocation.month)))
        }, failure: { failure = $0.localizedDescription })
    }
}

/// Record or edit manual income. Foreign amounts need an explicit rate; budgets only ever
/// receive the converted ringgit amount.
struct IncomeEditor: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: LedgerModel
    var original: IncomeEntry? = nil
    var initialKind: IncomeKind = .salary
    var initialAccountID: String? = nil
    @State private var draftID = UUID().uuidString
    @State private var bankAccountID: String?
    @State private var source = ""
    @State private var amount = ""
    @State private var currency = "MYR"
    @State private var rate = ""
    @State private var kind: IncomeKind = .salary
    @State private var date = Date()
    @State private var note = ""
    @State private var initialized = false
    @State private var confirmingBudgetChange = false
    @State private var error: String?
    private var operationKey: String { "income-" + (original?.id ?? draftID) }
    private var saving: Bool { model.isWorking(operationKey) }
    private func draft() throws -> IncomeEntry {
        if kind == .interest, !model.ledger.bankAccounts.contains(where: { $0.id == bankAccountID }) {
            throw reviewError("请选择利息到账的账户。", "Choose the account that received the interest.", "Pilih akaun yang menerima faedah.")
        }
        let name = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw reviewError("请填写收入来源。", "Enter where the income came from.", "Masukkan sumber pendapatan.") }
        var entry = original ?? IncomeEntry(id: draftID, source: name, cents: 1)
        entry.source = name
        entry.bankAccountID = bankAccountID
        entry.kind = kind
        entry.date = date
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmed.isEmpty ? nil : trimmed
        if currency == "MYR" {
            entry.foreign = nil
            entry.cents = try toCents(amount)
        } else {
            let value = try parseRate(rate)
            let kept = original?.foreign.flatMap { $0.currency == currency && $0.quote.value == value ? $0.quote : nil }
            let saved = model.ledger.rates[currency].flatMap { $0.value == value ? $0 : nil }
            let fx = ForeignAmount(currency: currency, minor: try Currency.parse(amount, code: currency),
                                   quote: kept ?? saved ?? RateQuote(value: value, date: Date(), source: "Manual"))
            entry.foreign = fx
            entry.cents = try fx.myrCents()
        }
        try entry.validate()
        return entry
    }
    private var adjustments: [BudgetAdjustment] {
        guard let original, let entry = try? draft() else { return [] }
        return model.ledger.allocationAdjustments(source: original.sourceKey, newCents: entry.cents)
    }
    var body: some View {
        let _ = uiLocale.identifier
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0.00", text: $amount).keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(IncomeStyle.tint)
                            .accessibilityLabel(tr("金额", "Amount", "Amaun")).accessibilityIdentifier("income.amount")
                        Picker(tr("币种", "Currency", "Mata wang"), selection: $currency) {
                            ForEach(Currency.codes, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    if currency != "MYR" {
                        HStack {
                            Text("1 \(currency) =").foregroundStyle(.secondary)
                            TextField(tr("汇率", "Rate", "Kadar"), text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("income.rate")
                            Text("MYR").foregroundStyle(.secondary)
                        }
                        if let entry = try? draft() {
                            LabeledContent(tr("折合", "Counts as", "Bersamaan"), value: money(entry.cents))
                        }
                    }
                } header: {
                    Text(tr("金额", "Amount", "Amaun"))
                } footer: {
                    if currency != "MYR" {
                        Text(tr("预算以马币计算。请填写实际到账汇率；只有换算后的马币金额可加入预算。", "Budgets are in ringgit. Enter the rate you actually received; only the converted ringgit amount can go into a budget.", "Bajet dalam ringgit. Masukkan kadar sebenar diterima; hanya amaun ringgit yang ditukar boleh dimasukkan ke bajet."))
                    }
                }
                Section {
                    TextField(kind == .interest ? tr("银行或利息说明", "Bank or interest description", "Bank atau penerangan faedah") : tr("雇主、客户或说明", "Employer, client or description", "Majikan, pelanggan atau penerangan"), text: $source)
                        .accessibilityIdentifier("income.source")
                    Picker(tr("类型", "Type", "Jenis"), selection: $kind) {
                        ForEach(IncomeKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    BankAccountPicker(selection: $bankAccountID)
                    if kind == .interest {
                        Text(tr("填写银行实际到账的利息和日期。保存后计入所选账户余额，不自动加入消费预算；已包含在期初余额中的利息无需再记。", "Enter the interest actually credited and its date. It updates the selected account without automatic budget allocation. Do not re-enter interest already included in the opening balance.", "Isi faedah sebenar diterima dan tarikhnya. Baki akaun dikemas kini tanpa peruntukan bajet automatik. Jangan rekod semula faedah yang sudah termasuk dalam baki awal."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    DatePicker(tr("收到日期", "Date received", "Tarikh diterima"), selection: $date, in: ...Date())
                    TextField(tr("备注（可选）", "Note (optional)", "Nota (pilihan)"), text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text(tr("只记录赚到的钱：工资、自由职业、兼职或奖金等。自己账户之间的转账、充值、退款和朋友还款都不是收入。", "Record money you earned: salary, freelance, part-time work, bonuses and similar. Transfers between your own accounts, top-ups, refunds and friends' repayments aren't income.", "Rekod wang yang anda peroleh: gaji, kerja bebas, kerja sambilan, bonus dan seumpamanya. Pindahan antara akaun sendiri, tambah nilai, bayaran balik dan bayaran rakan bukan pendapatan."))
                }
                if !adjustments.isEmpty {
                    Section {
                        Text(budgetAdjustmentSummary(adjustments)).foregroundStyle(.orange).monospacedDigit()
                    } header: {
                        Text(tr("预算变化", "Budget change", "Perubahan bajet"))
                    } footer: {
                        Text(tr("新金额低于已加入预算的金额，相关预算会相应减少。", "The new amount is less than this income already added to budgets, so those budgets go down by the difference.", "Amaun baharu kurang daripada yang sudah ditambah ke bajet, jadi bajet itu berkurang mengikut perbezaannya."))
                    }
                }
            }
            .yuejiListSurface()
            .navigationTitle(original == nil ? tr("记录收入", "Record income", "Rekod pendapatan") : tr("编辑收入", "Edit income", "Edit pendapatan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("取消", "Cancel", "Batal"), systemImage: "xmark") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { EditorSaveLabel(saving: saving) }
                        .disabled(saving || amount.isEmpty || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("income.save")
                }
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .onAppear {
                guard !initialized else { return }
                initialized = true
                guard let original else {
                    kind = initialKind; bankAccountID = initialAccountID
                    if initialKind == .interest { source = model.ledger.bankAccounts.first { $0.id == initialAccountID }?.name ?? "" }
                    return
                }
                bankAccountID = original.bankAccountID
                source = original.source; kind = original.kind; date = original.date; note = original.note ?? ""
                currency = original.foreign?.currency ?? "MYR"
                amount = Currency.input(original.foreign?.minor ?? original.cents, currency)
                rate = original.foreign?.quote.text ?? ""
            }
            .onChange(of: currency) { _, code in
                if code != "MYR" && rate.isEmpty { rate = model.ledger.rates[code]?.text ?? "" }
            }
            .confirmationDialog(tr("同时调整预算？", "Update budgets too?", "Kemas kini bajet juga?"), isPresented: $confirmingBudgetChange, titleVisibility: .visible) {
                Button(tr("保存并调整预算", "Save and update budgets", "Simpan dan kemas kini bajet")) {
                    do { commit(try draft()) } catch { self.error = error.localizedDescription }
                }
                Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
            } message: { Text(budgetAdjustmentSummary(adjustments)) }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
        .yuejiSheetSurface().ledgerFeedback(modal: true)
    }
    private func save() {
        do {
            let entry = try draft()
            if original != nil, !adjustments.isEmpty { confirmingBudgetChange = true; return }
            commit(entry)
        } catch { self.error = error.localizedDescription }
    }
    private func commit(_ entry: IncomeEntry) {
        if let original {
            let explained = model.ledger.allocationAdjustments(source: original.sourceKey, newCents: entry.cents)
            model.perform(key: operationKey, action: { (ledger: inout Ledger) throws -> [BudgetAdjustment] in
                guard ledger.allocationAdjustments(source: original.sourceKey, newCents: entry.cents) == explained else {
                    throw reviewError("预算已改变，请重新核对后保存。", "Budgets changed. Review the change and save again.", "Bajet berubah. Semak dan simpan semula.")
                }
                return try ledger.updateIncome(entry, replacing: original)
            }, completion: { applied in
                model.showSaved(message: applied.isEmpty ? nil : tr("已保存，预算已调整", "Saved · budgets updated", "Disimpan · bajet dikemas kini"))
                dismiss()
            }, failure: { error = $0.localizedDescription })
        } else {
            let percent = IncomeBudgetSettings.autoPercent
            model.perform(key: operationKey, action: { ledger in
                try ledger.addIncome(entry, autoPercent: percent)
            }, completion: { outcome in
                if let outcome { model.presentIncomeOutcome(outcome) } else { model.showSaved() }
                dismiss()
            }, failure: { error = $0.localizedDescription })
        }
    }
}

struct IncomeDetailView: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: LedgerModel
    let id: String
    @State private var editing: IncomeEntry?
    @State private var deleting = false
    @State private var failure: String?
    @State private var allocationRequest: IncomeAllocationRequest?
    @State private var removingAllocation: BudgetAllocation?
    private var entry: IncomeEntry? { model.ledger.incomes.first { $0.id == id } }
    var body: some View {
        let _ = uiLocale.identifier
        Form {
            if let entry {
                Section {
                    HStack(spacing: 12) {
                        IslandIconTile(symbol: entry.kind.symbol, color: IncomeStyle.tint, size: 44).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.source).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Text(entry.kind.label).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    TransactionAmount(cents: entry.cents, direction: .incoming).font(.largeTitle.bold())
                    if let fx = entry.foreign {
                        LabeledContent(tr("原币金额", "Original amount", "Amaun asal"), value: Currency.display(fx.minor, fx.currency))
                        LabeledContent(tr("汇率", "Exchange rate", "Kadar pertukaran"), value: "1 \(fx.currency) = \(fx.quote.text) MYR")
                    }
                    LabeledContent(tr("收到日期", "Date received", "Tarikh diterima"), value: dateLabel(entry.date))
                    LabeledContent(tr("来源", "Source", "Sumber"), value: sourceLabel("手动"))
                    if let note = entry.note, !note.isEmpty { Text(note).textSelection(.enabled) }
                }
                IncomeBudgetSection(source: entry.sourceKey, request: $allocationRequest, removing: $removingAllocation)
                Section {
                    Button(tr("编辑收入", "Edit income", "Edit pendapatan"), systemImage: "pencil") { editing = entry }
                    Button(tr("删除收入", "Delete income", "Padam pendapatan"), systemImage: "trash", role: .destructive) { deleting = true }
                }
            } else {
                Text(tr("记录不存在", "Record not found", "Rekod tidak ditemui"))
            }
        }
        .yuejiListSurface()
        .navigationTitle(tr("收入", "Income", "Pendapatan")).navigationBarTitleDisplayMode(.inline)
        .modifier(IncomeBudgetPresentation(request: $allocationRequest, removing: $removingAllocation))
        .sheet(item: $editing) { IncomeEditor(original: $0).environmentObject(model) }
        .confirmationDialog(tr("删除这笔收入？", "Delete this income?", "Padam pendapatan ini?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(tr("删除", "Delete", "Padam"), role: .destructive) { delete() }
            Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
        } message: { Text(entry.map { incomeDeletionMessage(model.ledger, source: $0.sourceKey) } ?? "") }
        .alert(tr("无法删除", "Unable to delete", "Tidak dapat memadam"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }
    private func delete() {
        guard let entry else { return }
        Task {
            do { try await model.deleteIncome(entry); dismiss() }
            catch { failure = error.localizedDescription }
        }
    }
}

/// Explains a deletion's budget change before it is confirmed.
func incomeDeletionMessage(_ ledger: Ledger, source: String) -> String {
    let removals = ledger.allocationRemovals(source: source)
    let undo = tr("删除后可撤销。", "You can undo this deletion.", "Pemadaman boleh dibatalkan.")
    guard !removals.isEmpty else { return undo }
    return tr("加入预算的金额会一并移除：", "What it added to budgets is removed too:", "Yang ditambah ke bajet turut dibuang:") + "\n"
        + budgetAdjustmentSummary(removals) + "\n" + undo
}

struct IncomeRow: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: IncomeEntry
    var body: some View {
        let _ = uiLocale.identifier
        let allocated = model.ledger.allocatedTotal(for: entry.sourceKey)
        HStack(alignment: .top, spacing: 12) {
            IslandIconTile(symbol: entry.kind.symbol, color: IncomeStyle.tint, size: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.source).font(.body.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    Spacer(minLength: 0)
                    TransactionAmount(cents: entry.cents, direction: .incoming).font(.body.weight(.semibold)).fixedSize()
                }
                Text(entry.kind.label + " · " + sourceLabel("手动") + " · " + dateLabel(entry.date))
                    .font(.caption).foregroundStyle(.secondary)
                if allocated > 0 {
                    Label(tr("已加入预算 ", "In budget ", "Dalam bajet ") + money(allocated), systemImage: "gauge.with.dots.needle.33percent")
                        .font(.caption2.weight(.medium)).foregroundStyle(IncomeStyle.tint)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(IncomeStyle.tint.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct IncomeDeletionConfirmation: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
    @Binding var entry: IncomeEntry?
    @State private var failure: String?
    func body(content: Content) -> some View {
        content.confirmationDialog(tr("删除这笔收入？", "Delete this income?", "Padam pendapatan ini?"),
                                   isPresented: Binding(get: { entry != nil }, set: { if !$0 { entry = nil } }),
                                   titleVisibility: .visible, presenting: entry) { selected in
            Button(tr("删除", "Delete", "Padam"), role: .destructive) {
                Task {
                    do { try await model.deleteIncome(selected) }
                    catch { failure = error.localizedDescription }
                }
            }
            Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
        } message: { selected in
            Text(selected.source + " · " + money(selected.cents) + "\n" + incomeDeletionMessage(model.ledger, source: selected.sourceKey))
        }
        .alert(tr("无法删除", "Unable to delete", "Tidak dapat memadam"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }
}

/// Base budget + income added − eligible spending = remaining, as the Overview shows it.
struct MonthlyBudgetBreakdown: View {
    let budget: MonthlyBudget
    let spent: Int
    let amount: (Int) -> String
    var body: some View {
        let remaining = budget.remaining(spent: spent)
        VStack(spacing: 6) {
            row(tr("基本预算", "Base budget", "Bajet asas"), amount(budget.base))
            row(tr("收入加入", "Income added", "Pendapatan ditambah"), "+" + amount(budget.income), tint: IncomeStyle.tint)
            row(tr("计入预算的消费", "Eligible spending", "Belanja dikira"), "−" + amount(spent), tint: .red)
            Divider()
            row(remaining >= 0 ? tr("剩余", "Remaining", "Baki") : tr("超出", "Over budget", "Melebihi"), amount(abs(remaining)), bold: true)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }
    private func row(_ title: String, _ value: String, tint: Color? = nil, bold: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().fontWeight(bold ? .semibold : .regular).foregroundStyle(tint ?? Color.primary)
                .contentTransition(.numericText())
        }
    }
}

/// The optional automatic allocation; off by default.
struct IncomeAutoAllocationSection: View {
    @Environment(\.locale) private var uiLocale
    @AppStorage(IncomeBudgetSettings.enabledKey) private var enabled = false
    @AppStorage(IncomeBudgetSettings.percentKey) private var percent = IncomeBudgetSettings.defaultPercent
    var body: some View {
        let _ = uiLocale.identifier
        Section {
            Toggle(tr("自动把收入加入本月预算", "Add income to this month's budget automatically", "Tambah pendapatan ke bajet bulan ini secara automatik"), isOn: $enabled)
                .tint(IncomeStyle.tint)
            if enabled {
                Stepper(value: $percent, in: 5...100, step: 5) {
                    LabeledContent(tr("每笔收入加入", "Share of each income", "Bahagian setiap pendapatan"), value: "\(percent)%")
                }
            }
        } header: {
            Text(tr("收入与预算", "Income and budget", "Pendapatan dan bajet"))
        } footer: {
            Text(tr("默认关闭。开启后，每笔记录或确认为收入（工资、自由职业、兼职、奖金或其他收入）的金额会按比例加入当月预算一次，并显示一条简短确认。转账、充值、退款、朋友还款和疑似重复的收入不会自动加入。可在收入详情修改或移除。",
                    "Off by default. When on, each income you record or confirm (salary, freelance, part-time, bonus or other income) adds this share to the current month's budget once, with one short confirmation. Transfers, top-ups, refunds, repayments and possible duplicates are never added automatically. Change or remove it from the income's details.",
                    "Dimatikan secara lalai. Apabila dihidupkan, setiap pendapatan yang anda rekod atau sahkan (gaji, kerja bebas, kerja sambilan, bonus atau lain-lain) menambah bahagian ini ke bajet bulan semasa sekali, dengan satu pengesahan ringkas. Pindahan, tambah nilai, bayaran balik, bayaran rakan dan kemungkinan pendua tidak ditambah secara automatik. Ubah atau buang daripada butiran pendapatan."))
        }
    }
}

private struct StatementBatch: Identifiable {
    let id: String
    let date: Date
    let notices: [TNGNotice]
}

/// PDF parsing is local. Gemini may suggest categories, never amounts or balances.
private struct StatementImportView: View {
    @EnvironmentObject private var model: LedgerModel
    let accountID: String
    @State private var statement: RHBStatement?
    @State private var picking = false
    @State private var busy = false
    @State private var confirmed = false
    @State private var useAI = false
    @State private var message = ""
    @State private var error: String?
    @State private var undoBatch: String?
    @State private var task: Task<Void, Never>?
    private var account: BankAccount? { model.ledger.bankAccounts.first { $0.id == accountID } }
    private var key: String { "statement-" + accountID }
    private var working: Bool { busy || model.isWorking(key) }
    private var batches: [StatementBatch] {
        let notices = model.ledger.tngNotices.filter { $0.bankAccountID == accountID && StatementImportStamp.read($0) != nil }
        return Dictionary(grouping: notices, by: { StatementImportStamp.read($0)!.batch }).map { batch, items in
            StatementBatch(id: batch, date: StatementImportStamp.read(items[0])!.created, notices: items)
        }.sorted { $0.date > $1.date }.prefix(10).map { $0 }
    }
    private func day(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = RHBStatement.calendar; f.timeZone = RHBStatement.calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    var body: some View {
        Form {
            if let account {
                Section {
                    Label(account.name, systemImage: "building.columns")
                    Button { picking = true } label: {
                        Label(tr("选择银行 PDF", "Choose bank PDF", "Pilih PDF bank"), systemImage: "doc.badge.plus")
                    }.disabled(working)
                } footer: {
                    Text(tr("支持已适配的 RHB、AmBank、HLB、Maybank、Ryt 主账户及 Wise MYR 文字版格式。PDF 在本机核对；扫描件、需密码的文件及其他版式暂不支持。Wise 推算期初的交易仅待确认。", "Supports adapted RHB, AmBank, HLB, Maybank, Ryt main account and Wise MYR text layouts. Checks run on device. Scans, password-locked PDFs and other layouts are unsupported. Wise entries with a derived opening await review.", "Menyokong format teks RHB, AmBank, HLB, Maybank, akaun utama Ryt dan Wise MYR yang disesuaikan. Semakan setempat; imbasan, PDF berkunci dan format lain belum disokong. Rekod Wise dengan baki awal dikira perlu disemak."))
                }
                if let statement {
                    summary(statement, account: account)
                    Section {
                        Toggle(tr("确认尾号 \(statement.suffix) 是此账户", "Confirm ••••\(statement.suffix) belongs to this account", "Sahkan ••••\(statement.suffix) ialah akaun ini"), isOn: $confirmed)
                        Toggle(tr("使用 Gemini 建议支出分类", "Suggest expense categories with Gemini", "Cadangkan kategori dengan Gemini"), isOn: $useAI)
                        Button { importRows(statement, account: account) } label: {
                            Label(tr("补录明确交易，其余待确认", "Add clear entries; review the rest", "Tambah rekod jelas; semak selebihnya"), systemImage: "checkmark.circle")
                        }.disabled(!confirmed || working)
                    } footer: {
                        Text(tr("开启 AI 后，仅发送交易描述和分类名称给 Google Gemini。金额、方向和余额由本机校验。AI 不可用时用“其他”分类。疑似重复、转账和不明收款待确认；早于账户期初时间的记录跳过。", "When enabled, transaction descriptions and category names are sent to Google Gemini. Amounts, direction and balances are checked locally. If AI is unavailable, entries use Other. Possible duplicates, transfers and unclear receipts await review. Entries before the opening time are skipped.", "Jika diaktifkan, perihalan transaksi dan nama kategori dihantar ke Google Gemini. Amaun, arah dan baki disemak setempat. Jika AI gagal, kategori Lain-lain digunakan. Pendua, pindahan dan penerimaan tidak jelas menunggu semakan. Rekod sebelum waktu awal dilangkau."))
                    }.disabled(working)
                    Section {
                        DisclosureGroup(tr("查看原始交易（\(statement.rows.count)）", "Review source entries (\(statement.rows.count))", "Semak rekod asal (\(statement.rows.count))")) {
                            ForEach(statement.rows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.description).font(.subheadline)
                                    HStack {
                                        Text(day(row.date))
                                        TransactionAmount(cents: row.cents, direction: row.debit > 0 ? .outgoing : .incoming)
                                    }.font(.caption).monospacedDigit()
                                    if !row.detail.isEmpty { Text(row.detail).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                if working { Section { ProgressView(tr("正在处理…", "Processing…", "Sedang memproses…")) } }
                if !message.isEmpty { Section { Text(message).foregroundStyle(.secondary) } }
                if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
                ForEach(batches) { batch in
                    Section {
                        ForEach(batch.notices.filter { $0.status == "pending" }) { notice in
                            NavigationLink { FinancialNoticeReviewView(id: notice.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(notice.party ?? "RHB")
                                    Text(day(notice.date) + " · " + money(notice.cents ?? 0)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button(tr("撤销这次导入", "Undo this import", "Batal import ini"), role: .destructive) { undoBatch = batch.id }.disabled(working)
                    } header: {
                        Text(tr("导入于 ", "Imported ", "Diimport ") + day(batch.date) + " · \(batch.notices.count)")
                    } footer: {
                        Text(tr("待确认记录尚未影响余额。已编辑、确认或用于预算／转账的批次不能整体撤销。", "Pending entries do not affect the balance. A batch cannot be undone after its entries are edited, confirmed or used in budgets/transfers.", "Rekod menunggu semakan tidak menjejaskan baki. Kelompok yang diubah, disahkan atau digunakan dalam bajet/pindahan tidak boleh dibatalkan."))
                    }
                }
            }
        }
        .yuejiListSurface()
        .navigationTitle(tr("月结单核对", "Statement reconciliation", "Semakan penyata"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let issue): error = issue.localizedDescription
            }
        }
        .confirmationDialog(tr("撤销本批次新增记录？", "Undo entries added by this import?", "Batalkan rekod import ini?"), isPresented: Binding(get: { undoBatch != nil }, set: { if !$0 { undoBatch = nil } })) {
            if let batch = undoBatch {
                Button(tr("撤销导入", "Undo import", "Batal import"), role: .destructive) {
                    model.perform(key: key, postRecurring: false, action: { try $0.undoStatementImport(batch: batch) }, completion: { _ in
                        message = tr("已撤销导入。", "Import undone.", "Import dibatalkan."); error = nil
                    }, failure: { error = $0.localizedDescription })
                    undoBatch = nil
                }
            }
        }
        .onDisappear { task?.cancel() }
    }
    @ViewBuilder private func summary(_ statement: RHBStatement, account: BankAccount) -> some View {
        Section {
            LabeledContent(tr("银行", "Bank", "Bank"), value: statement.provider)
            if !statement.verificationNote.isEmpty {
                Text(statement.verificationNote).font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent(tr("期间", "Period", "Tempoh"), value: day(statement.start) + " – " + day(statement.end))
            LabeledContent(tr("月结单期初", "Statement opening", "Baki awal penyata"), value: money(statement.opening))
            LabeledContent(tr("月结单期末", "Statement closing", "Baki akhir penyata"), value: money(statement.closing))
            if let cutoff = RHBStatement.calendar.date(byAdding: .day, value: 1, to: statement.end),
               let balance = model.ledger.statementBalance(account, before: cutoff) {
                LabeledContent(tr("账本同期余额", "Ledger closing balance", "Baki akhir lejar"), value: money(balance))
                LabeledContent(tr("仍需核对差额", "Difference to reconcile", "Perbezaan untuk disemak"), value: money(statement.closing - balance))
            }
            if account.openingDate > statement.start {
                Text(tr("账户期初晚于月结单开始，较早记录已包含于期初余额，不会补录。请核对期初金额与时间。", "The account opens after this statement starts. Earlier entries are covered by the opening balance and will be skipped. Check that amount and time.", "Akaun bermula selepas penyata. Rekod terdahulu diliputi baki awal dan dilangkau. Semak amaun dan waktu awal.")).font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            Text(tr("差额不会直接覆盖账户余额。处理待确认记录后再核对。", "The difference never overwrites your balance. Review pending entries, then compare again.", "Perbezaan tidak menimpa baki. Semak rekod tertunda, kemudian banding semula."))
        }
    }
    private func load(_ url: URL) {
        task?.cancel(); statement = nil; confirmed = false; error = nil; message = ""; busy = true
        let store = LocalStore.shared
        task = Task {
            defer { busy = false }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 10_000_000 else { throw RHBStatement.failure() }
                    return try RHBStatement.read(Data(contentsOf: url, options: .mappedIfSafe))
                }
                let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard store.isActive else { throw CancellationError() }
                statement = parsed
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func importRows(_ statement: RHBStatement, account: BankAccount) {
        guard financialProvider(account.institution ?? account.automaticSource ?? "") == statement.provider,
              account.automaticSuffix == nil || account.automaticSuffix == statement.suffix else {
            error = tr("请选择月结单对应银行的账户，并核对设置中的账号尾号。", "Select an account at the statement's bank and check its configured suffix.", "Pilih akaun bank penyata ini dan semak akhiran akaun.")
            return
        }
        busy = true; error = nil; message = ""
        let store = LocalStore.shared, allowed = model.ledger.categoryNames, ai = useAI
        let texts = Array(Set(statement.rows.filter { $0.isExpense && $0.date >= account.openingDate && !model.ledger.seenEvents.contains($0.id) && !model.ledger.statementMayExist($0, accountID: account.id) }.map(\.analysisText))).sorted().prefix(100)
        task = Task {
            defer { busy = false }
            var categories: [String: String] = [:], aiFailed = false
            if ai {
                for text in texts {
                    do {
                        try Task.checkCancellation()
                        guard store.isActive else { throw CancellationError() }
                        let data = try await CloudAccount.shared.assistant(mode: "classify", text: text, categories: allowed)
                        let answer = try JSONDecoder().decode(AssistantResult.self, from: data)
                        if allowed.contains(answer.category) { categories[text] = answer.category }
                    } catch is CancellationError { return }
                    catch { aiFailed = true; break }
                }
            }
            guard !Task.isCancelled, store.isActive else { return }
            let suggestions = categories, fallback = aiFailed
            model.perform(key: key, postRecurring: false, action: { ledger in
                guard store.isActive else { throw CancellationError() }
                return try ledger.importStatement(statement, account: account, categories: suggestions)
            }, completion: { result in
                message = tr("已补录 \(result.added) 笔，待确认 \(result.pending) 笔，跳过 \(result.skipped) 笔。", "Added \(result.added), pending \(result.pending), skipped \(result.skipped).", "Ditambah \(result.added), menunggu \(result.pending), dilangkau \(result.skipped).")
                if fallback { message += tr(" AI 暂不可用，未分类支出使用“其他”。", " AI unavailable; unclassified expenses use Other.", " AI tidak tersedia; perbelanjaan tanpa kategori menggunakan Lain-lain.") }
                confirmed = false
            }, failure: { error = $0.localizedDescription })
        }
    }
}
