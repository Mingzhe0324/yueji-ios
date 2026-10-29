import SwiftUI

private struct BankWalletCard: View {
    let account: BankAccount
    let balance: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var bank: String { account.institution ?? account.name }
    private var colors: [Color] {
        if bank.hasPrefix("Maybank") { return [Color(red: 0.32, green: 0.23, blue: 0.04), .black] }
        if bank.hasPrefix("CIMB") || bank.hasPrefix("Public") { return [Color(red: 0.65, green: 0.03, blue: 0.13), Color(red: 0.24, green: 0.02, blue: 0.08)] }
        if bank == "GXBank" || bank == "AEON Bank" { return [.purple, Color(red: 0.16, green: 0.07, blue: 0.31)] }
        return [Color(red: 0.10, green: 0.28, blue: 0.45), Color(red: 0.04, green: 0.09, blue: 0.17)]
    }
    private var logo: String? {
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
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                if let logo {
                    Image(logo).resizable().scaledToFit().frame(width: 56, height: 36)
                        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    Text(bank).font(.headline)
                } else {
                    Label(bank, systemImage: "building.columns.fill").font(.headline)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).padding(10)
                    .background(.white.opacity(0.12), in: Circle()).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(account.name).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                Text(money(balance)).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit().contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: balance)
                    .minimumScaleFactor(0.65).lineLimit(1)
            }
            HStack {
                Text(tr("账面余额 · MYR", "Recorded balance · MYR", "Baki direkod · MYR"))
                Spacer()
                if logo != nil { Text(bank) }
            }.font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .topTrailing) {
            Circle().fill(.white.opacity(0.04)).frame(width: 200, height: 200).offset(x: 70, y: -90).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
        .accessibilityElement(children: .combine)
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
    var body: some View {
        List {
            Section {
                Text(tr("这里可以为旧通知或无法自动匹配的通知选择账户。待确认、疑似重复及已忽略的记录不会仅因选择账户而入账。", "Assign accounts to older or unmatched notices here. Selecting an account alone does not post pending, duplicate or ignored records.", "Tetapkan akaun untuk notifikasi lama atau tidak sepadan. Memilih akaun tidak merekod notifikasi tertunda, pendua atau diabaikan."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.ledger.tngNotices.sorted { $0.date > $1.date }) { notice in
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
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(tr("账面总余额", "Recorded balance", "Baki direkod"),
                                   value: money(model.ledger.bankAccounts.reduce(0) { $0 + model.ledger.bankBalance($1) }))
                        .font(.headline).monospacedDigit()
                } footer: {
                    Text(tr("手动管理的 MYR 账户，不连接银行，也不是银行实时余额。", "Manually managed MYR accounts. Not connected to banks or live bank balances.", "Akaun MYR diurus manual. Tidak disambung ke bank atau baki langsung."))
                }
                Section(tr("我的账户", "My accounts", "Akaun saya")) {
                    ForEach(model.ledger.bankAccounts) { account in
                        NavigationLink {
                            if #available(iOS 18.0, *), !reduceMotion {
                                BankAccountDetail(accountID: account.id)
                                    .navigationTransition(.zoom(sourceID: account.id, in: walletTransition))
                            } else {
                                BankAccountDetail(accountID: account.id)
                            }
                        } label: {
                            if #available(iOS 18.0, *), !reduceMotion {
                                BankWalletCard(account: account, balance: model.ledger.bankBalance(account))
                                    .matchedTransitionSource(id: account.id, in: walletTransition)
                            } else {
                                BankWalletCard(account: account, balance: model.ledger.bankBalance(account))
                            }
                        }.buttonStyle(BankCardPressStyle())
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
                    Button { adding = true } label: {
                        Label(tr("添加银行／钱包账户", "Add bank / wallet account", "Tambah akaun bank / dompet"), systemImage: "plus.circle.fill")
                    }.accessibilityIdentifier("bankAccount.add")
                }
                Section {
                    NavigationLink { AutomaticAccountLinksView() } label: {
                        Label(tr("核对自动记录的账户", "Review automatic entry accounts", "Semak akaun rekod automatik"), systemImage: "arrow.triangle.branch")
                    }
                    DisclosureGroup(tr("Apple Pay 自动扣账面余额", "Apple Pay account setup", "Tetapan akaun Apple Pay")) {
                        Text(tr("1. 在快捷指令创建交易自动化，每个自动化只选择一张付款卡。\n2. 添加「记录 Apple Pay 支出」，传入金额和商户。\n3. 在该动作的「扣款账户」选择这张卡对应的月记账户，并设置立即运行。\n4. 其他卡分别配置。未选扣款账户的旧自动化仍会记账，但不会猜测银行账户。", "1. Create a transaction automation in Shortcuts and select just one payment card.\n2. Add Record Apple Pay expense and pass the amount and merchant.\n3. Choose that card's YueJi payment account in the action and set the automation to run immediately.\n4. Configure other cards separately. Older actions without an account still record expenses without guessing the bank.", "1. Cipta automasi transaksi dalam Pintasan dan pilih satu kad sahaja.\n2. Tambah tindakan rekod Apple Pay serta amaun dan peniaga.\n3. Pilih akaun YueJi bagi kad itu dan tetapkan jalan serta-merta.\n4. Tetapkan kad lain secara berasingan. Tindakan lama tanpa akaun masih merekod tanpa meneka bank."))
                    }
                    Text(tr("在编辑账户中设置自动记账来源。新导入的付款按来源及尾号匹配账户；收入通知确认后才加余额。旧记录可在此补选账户。", "Set the automatic source in Edit account. New payments match by source and suffix; income notices add to the balance after confirmation. Assign older records here.", "Tetapkan sumber automatik dalam Edit akaun. Bayaran baharu dipadankan mengikut sumber dan digit; pendapatan ditambah selepas pengesahan. Tetapkan rekod lama di sini."))
                    Text(tr("余额包含已分配的收入、全额付款及原账户退款。朋友还款、报销和账户间转账暂不自动计入，请与银行核对。", "Balances include assigned income, full payments and refunds to the original account. Friend repayments, reimbursements and transfers are not included automatically; reconcile with your bank.", "Baki termasuk pendapatan ditetapkan, bayaran penuh dan pulangan ke akaun asal. Bayaran rakan, tuntutan dan pindahan tidak dikira automatik; semak dengan bank."))
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .yuejiDashboardSurface()
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.ledger.bankAccounts.map(\.id))
            .navigationTitle(tr("账户", "Accounts", "Akaun"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton().disabled(model.ledger.bankAccounts.count < 2)
                }
            }
            .sheet(isPresented: $adding) { BankAccountEditor() }
        }
    }
}

private struct BankAccountDetail: View {
    @EnvironmentObject var model: LedgerModel
    let accountID: String
    @State private var editing = false
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
                    Button(tr("编辑账户", "Edit account", "Edit akaun")) { editing = true }
                } footer: {
                    Text(tr("期初余额指此时间之前的余额；更早的收支不会重复计入。", "Opening balance is the balance just before this time; earlier entries are not counted again.", "Baki awal ialah baki sebelum masa ini; rekod lebih awal tidak dikira semula."))
                }
                Section(tr("已分配的支出", "Assigned spending", "Belanja ditetapkan")) {
                    ForEach(model.ledger.expenses.filter { $0.bankAccountID == accountID }.sorted { $0.date > $1.date }) { entry in
                        LabeledContent(entry.merchant, value: money(entry.cents))
                    }
                }
                Section(tr("已分配的收入", "Assigned income", "Pendapatan ditetapkan")) {
                    ForEach(model.ledger.incomes.filter { $0.bankAccountID == accountID }.sorted { $0.date > $1.date }) { entry in
                        LabeledContent(entry.source, value: money(entry.cents))
                    }
                }
                .sheet(isPresented: $editing) { BankAccountEditor(original: account) }
            }
        }.yuejiListSurface().navigationTitle(tr("账户详情", "Account details", "Butiran akaun"))
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
                Picker(tr("选择银行", "Choose bank", "Pilih bank"), selection: $institution) {
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
                    Section(tr("电子钱包", "eWallet", "eDompet")) { Text("TNG eWallet").tag("TNG eWallet") }
                    if !institution.isEmpty && institution != "TNG eWallet" && !(MalaysianBanks.conventional + MalaysianBanks.islamic + MalaysianBanks.digital).contains(institution) {
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
            let before = original
            model.perform(key: operationKey, action: { ledger in
                if let before {
                    guard let index = ledger.bankAccounts.firstIndex(where: { $0.id == before.id }), ledger.bankAccounts[index] == before else {
                        throw LedgerError.invalid("Account changed; reopen and try again")
                    }
                    ledger.bankAccounts[index] = account
                } else { ledger.bankAccounts.append(account) }
                try ledger.validateBankAccounts()
            }, completion: { _ in dismiss() }, failure: { error = $0.localizedDescription })
        } catch { self.error = error.localizedDescription }
    }
}
import UIKit

/// Income keeps a green/teal look, apart from spending red and the app's blue. The light
/// variant is a deeper teal so white labels on it stay readable.
enum IncomeStyle {
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemTeal : UIColor(red: 0.0, green: 0.46, blue: 0.50, alpha: 1)
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
                    TextField(tr("雇主、客户或说明", "Employer, client or description", "Majikan, pelanggan atau penerangan"), text: $source)
                        .accessibilityIdentifier("income.source")
                    Picker(tr("类型", "Type", "Jenis"), selection: $kind) {
                        ForEach(IncomeKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    BankAccountPicker(selection: $bankAccountID)
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
                guard let original else { return }
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
            row(tr("计入预算的消费", "Eligible spending", "Belanja dikira"), "−" + amount(spent))
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
