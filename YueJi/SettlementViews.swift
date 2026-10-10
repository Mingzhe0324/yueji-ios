import SwiftUI

struct ManualEntryTypeSection: View {
    @Binding var selection: String
    var body: some View {
        Section {
            Picker(tr("记录类型", "Entry type", "Jenis rekod"), selection: $selection) {
                Text(tr("消费", "Expense", "Belanja")).tag("expense")
                Text(tr("还款 / 结算", "Repayment / Settlement", "Bayaran balik / Penyelesaian")).tag("settlement")
            }
        }
    }
}

private enum ManualSettlementMode: String, CaseIterable {
    case received, paid, net
    var direction: AccountDirection { self == .received ? .incoming : (self == .paid ? .outgoing : .neutral) }
    var label: String {
        switch self {
        case .received: return tr("朋友还给我", "A friend repaid me", "Rakan membayar balik kepada saya")
        case .paid: return tr("我还给朋友", "I repaid a friend", "Saya membayar balik kepada rakan")
        case .net: return tr("双方抵扣 / 净额结算", "Offset / net settlement", "Tolakan / penyelesaian bersih")
        }
    }
}

struct ManualSettlementEntryView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @Binding var entryType: String
    let initialDate: Date
    @State private var mode: ManualSettlementMode = .received
    @State private var friend = ""
    private var friends: [FriendBalance] {
        model.ledger.friendBalances.filter {
            mode == .received ? $0.owed > 0 : (mode == .paid ? $0.payable > 0 : $0.owed > 0 || $0.payable > 0)
        }
    }
    var body: some View {
        Form {
            ManualEntryTypeSection(selection: $entryType)
            Section {
                Picker(tr("付款方向", "Payment direction", "Arah bayaran"), selection: $mode) {
                    ForEach(ManualSettlementMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker(tr("朋友", "Friend", "Rakan"), selection: $friend) {
                    Text(tr("请选择朋友", "Choose a friend", "Pilih rakan")).tag("")
                    ForEach(friends) { Text($0.name).tag($0.id) }
                }
                if friends.isEmpty {
                    Text(tr("此方向没有未结欠款。请先记录原消费及分账。", "No outstanding debts in this direction. Record the original purchase and shares first.", "Tiada hutang belum selesai dalam arah ini. Rekod pembelian asal dan bahagian dahulu.")).foregroundStyle(.secondary)
                }
            } footer: {
                Text(tr("还款只减少欠款，不增加收入或消费。下一步选择原账目、金额和日期，再核对并确认。", "Repayments reduce debt without adding income or spending. Next, select original items, amount and date, then review and confirm.", "Bayaran balik mengurangkan hutang tanpa menambah pendapatan atau belanja. Seterusnya pilih rekod asal, amaun dan tarikh, kemudian semak dan sahkan."))
            }
            Section {
                NavigationLink(tr("选择欠款", "Select debts", "Pilih hutang")) {
                    SettlementSelectionView(friend: friend, repaymentDirection: mode.direction, initialDate: initialDate)
                }.disabled(!friends.contains(where: { $0.id == friend }))
            }
        }.yuejiListSurface().navigationTitle(tr("还款 / 结算", "Repayment / Settlement", "Bayaran balik / Penyelesaian")).navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { _, _ in friend = "" }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } } }
    }
}

struct SettlementPaymentRow: View {
    let record: FriendSettlement
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.paymentTitle + " · " + record.name).font(.headline)
                Text(dateLabel(record.date, time: true)).font(.caption).foregroundStyle(.secondary)
                Text(record.transfer == 0 ? tr("债务抵扣 · 我的账户无收支", "Debt offset · no account movement", "Tolakan hutang · tiada aliran akaun") : tr("手动结算 · 不计消费或收入", "Manual settlement · no spending or income", "Penyelesaian manual · bukan belanja atau pendapatan"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
            TransactionAmount(cents: abs(record.transfer), direction: record.accountDirection).font(.headline).layoutPriority(1)
        }.padding(.vertical, 8)
    }
}

private func settledDebtLabel(_ cents: Int) -> String {
    if cents > 0 { return tr("已结清朋友欠我的款项", "Settled debt owed to me", "Hutang kepada saya diselesaikan") }
    if cents < 0 { return tr("已结清我欠朋友的款项", "Settled debt I owed", "Hutang saya diselesaikan") }
    return tr("本笔暂未结算", "No amount settled for this item", "Tiada amaun diselesaikan untuk rekod ini")
}

func settlementDirection(_ cents: Int, name: String) -> String {
    if cents > 0 { return tr("\(name) 付给我", "\(name) pays me", "\(name) membayar saya") }
    if cents < 0 { return tr("我付给 \(name)", "I pay \(name)", "Saya membayar \(name)") }
    return tr("抵扣，无需转账", "Offset · no transfer", "Tolakan · tiada pindahan")
}

struct FriendDetailView: View {
    @EnvironmentObject var model: LedgerModel
    let key: String
    private var items: [FriendDebtItem] { model.ledger.friendDebtItems.filter { friendKey($0.friend) == key } }
    var body: some View {
        List {
            if let friend = model.ledger.friendBalances.first(where: { $0.id == key }) {
                Section(friend.name) {
                    LabeledContent(tr("朋友欠我", "They owe me", "Mereka berhutang kepada saya"), value: money(friend.owed))
                    LabeledContent(tr("我欠朋友", "I owe them", "Saya berhutang kepada mereka"), value: money(friend.payable))
                    LabeledContent(settlementDirection(friend.owed - friend.payable, name: friend.name), value: money(abs(friend.owed - friend.payable)))
                    NavigationLink { SettlementSelectionView(friend: key) } label: {
                        Label(tr("结算", "Settle", "Selesaikan"), systemImage: "arrow.left.arrow.right")
                    }.disabled(friend.owed == 0 && friend.payable == 0).guideTarget("friend.repay")
                }
                Section(tr("原始账目", "Original expenses", "Belanja asal")) {
                    ForEach(items) { item in
                        NavigationLink { ExpenseDetailView(id: item.expense.id) } label: { FriendDebtRow(item: item) }
                    }
                }
                Section(tr("结算记录", "Settlements", "Penyelesaian")) {
                    ForEach(model.ledger.settlements.filter { $0.friend == key }.sorted { $0.date > $1.date }) { record in
                        NavigationLink { SettlementDetailView(id: record.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(settlementDirection(record.transfer, name: record.name))
                                TransactionAmount(cents: abs(record.transfer), direction: record.accountDirection)
                                Text(dateLabel(record.date) + (record.active ? "" : tr(" · 已撤销", " · Undone", " · Dibatalkan"))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink(tr("消费概览 · 花在哪里", "Spending overview · by category", "Ringkasan belanja · mengikut kategori")) { FriendSpendingView(friend: key) }
                    NavigationLink(tr("分享朋友账单", "Share friend statement", "Kongsi penyata rakan")) { FriendStatementView(key: key) }
                }
            }
        }.yuejiListSurface().navigationTitle(tr("朋友余额", "Friend balance", "Baki rakan")).navigationBarTitleDisplayMode(.inline)
    }
}

struct FriendDebtRow: View {
    let item: FriendDebtItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.expense.merchant).font(.headline)
            Text(dateLabel(item.expense.date) + " · " + item.expense.categorySummary).font(.caption).foregroundStyle(.secondary)
            Text(tr("付款人：", "Paid by: ", "Dibayar oleh: ") + item.expense.payerLabel).font(.caption)
            Text(item.balance == 0 ? tr("已结清", "Settled", "Selesai") :
                 (item.balance > 0 ? tr("朋友欠我：", "They owe me: ", "Mereka berhutang: ") : tr("我欠朋友：", "I owe them: ", "Saya berhutang: ")) + money(abs(item.balance)))
                .font(.subheadline).monospacedDigit()
        }.padding(.vertical, 4)
    }
}

struct SplitHistoryView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var settled = false
    @State private var target: RepayTarget?
    @State private var undo: (String, String, String, Bool)?
    var body: some View {
        List {
            Picker(tr("显示", "Show", "Papar"), selection: $settled) {
                Text(tr("未结清", "Outstanding", "Belum selesai")).tag(false)
                Text(tr("已结清", "Settled", "Selesai")).tag(true)
            }.pickerStyle(.segmented)
            ForEach(model.ledger.friendDebtItems.filter { ($0.balance == 0) == settled }) { item in
                Section {
                    NavigationLink { ExpenseDetailView(id: item.expense.id) } label: { FriendDebtRow(item: item) }
                    NavigationLink(tr("朋友余额 / 净额结算", "Friend balance / net settlement", "Baki rakan / penyelesaian bersih")) { FriendDetailView(key: friendKey(item.friend)) }
                    if let share = item.expense.shares.first(where: { $0.id == item.shareID }), item.expense.paidByFriend == nil {
                        if item.balance != 0 {
                            Button(item.balance > 0 ? tr("单笔还款", "Repay this item", "Bayar rekod ini") : tr("退回朋友", "Return to friend", "Pulangkan kepada rakan")) { target = RepayTarget(expense: item.expense, share: share) }
                        }
                        ForEach(share.repayments) { payment in
                            HStack {
                                Text(dateLabel(payment.date))
                                TransactionAmount(cents: payment.cents, direction: .incoming)
                                Spacer()
                                Button(tr("撤销", "Undo", "Batal")) { undo = (item.expense.id, share.id, payment.id, false) }
                            }.font(.caption)
                        }
                        ForEach(share.returns ?? []) { payment in
                            HStack {
                                Text(tr("已退回：", "Returned: ", "Dipulangkan: "))
                                TransactionAmount(cents: payment.cents, direction: .outgoing)
                                Spacer()
                                Button(tr("撤销", "Undo", "Batal")) { undo = (item.expense.id, share.id, payment.id, true) }
                            }.font(.caption)
                        }
                    }
                }
            }
        }.yuejiListSurface().navigationTitle(tr("分账记录", "Split history", "Sejarah pembahagian")).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $target) { RepaymentView(target: $0) }
            .confirmationDialog(tr("撤销还款？", "Undo repayment?", "Batalkan bayaran balik?"), isPresented: Binding(get: { undo != nil }, set: { if !$0 { undo = nil } }), titleVisibility: .visible) {
                Button(tr("撤销", "Undo", "Batal"), role: .destructive) {
                    if let (expenseID, shareID, repaymentID, isReturn) = undo {
                        model.change { ledger in
                            if let e = ledger.expenses.firstIndex(where: { $0.id == expenseID }), let s = ledger.expenses[e].shares.firstIndex(where: { $0.id == shareID }) {
                                if isReturn { ledger.expenses[e].shares[s].returns?.removeAll { $0.id == repaymentID } }
                                else { ledger.expenses[e].shares[s].repayments.removeAll { $0.id == repaymentID } }
                            }
                        }
                    }
                    undo = nil
                }
            }
    }
}

struct SettlementSelectionView: View {
    @EnvironmentObject var model: LedgerModel
    let friend: String
    var repaymentDirection: AccountDirection = .neutral
    var initialDate: Date = Date()
    @State private var selected = Set<String>()
    @State private var date = Date()
    @State private var partial = false
    @State private var amount = ""
    @State private var plan: SettlementPlan?
    @State private var reviewing = false
    @State private var error: String?
    @State private var initialized = false
    private var items: [FriendDebtItem] {
        model.ledger.friendDebtItems.filter {
            friendKey($0.friend) == friend && $0.balance != 0 &&
            (repaymentDirection == .neutral || (repaymentDirection == .incoming ? $0.balance > 0 : $0.balance < 0))
        }
    }
    private var net: Int { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.balance } }
    var body: some View {
        let items = self.items
        Form {
            Section {
                ForEach(items) { item in
                    Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                        if value { selected.insert(item.id) } else { selected.remove(item.id) }
                    })) { FriendDebtRow(item: item) }
                }
                if items.isEmpty { Text(tr("没有未结清账目", "No outstanding items", "Tiada rekod belum selesai")) }
            } header: {
                Text(tr("选择未结清账目", "Select outstanding items", "Pilih rekod belum selesai"))
            } footer: { Text(tr("只结算选中的账目。未选中的余额保持不变。", "Only selected items are settled. Unselected balances stay outstanding.", "Hanya rekod dipilih diselesaikan. Baki tidak dipilih kekal tertunggak.")) }
            Section(tr("转账", "Transfer", "Pindahan")) {
                LabeledContent(tr("所选净额", "Selected net balance", "Baki bersih dipilih"), value: money(abs(net)))
                if let name = items.first?.friend { Text(settlementDirection(net, name: name)) }
                if net != 0 {
                    if repaymentDirection == .neutral { Toggle(tr("部分付款", "Partial payment", "Bayaran separa"), isOn: $partial) }
                    if partial || repaymentDirection != .neutral { TextField(tr("实际转账 · MYR", "Actual transfer · MYR", "Pindahan sebenar · MYR"), text: $amount).keyboardType(.decimalPad) }
                }
                DatePicker(tr("结算日期", "Settlement date", "Tarikh penyelesaian"), selection: $date, in: ...Date(), displayedComponents: .date)
            }
            Section {
                Button(tr("预览净额", "Review net amount", "Semak amaun bersih")) {
                    do {
                        let payment: Int
                        if net == 0 { payment = 0 }
                        else if partial || repaymentDirection != .neutral { payment = try nonnegativeCents(amount) }
                        else { payment = abs(net) }
                        if repaymentDirection == .neutral {
                            plan = try model.ledger.settlementPlan(friend: friend, selected: selected, payment: payment, date: date)
                        } else {
                            plan = try model.ledger.repaymentPlan(friend: friend, selected: selected, payment: payment, date: date, direction: repaymentDirection)
                        }
                        reviewing = true
                    } catch { self.error = error.localizedDescription }
                }.disabled(selected.isEmpty)
            }
        }.yuejiListSurface().scrollDismissesKeyboard(.interactively).navigationTitle(tr("结算", "Settle", "Selesaikan")).navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selected.formIntersection(Set(items.map(\.id)))
                if !initialized { date = initialDate; initialized = true }
            }
            .onChange(of: net) { _, value in amount = Currency.input(abs(value), "MYR") }
            .navigationDestination(isPresented: $reviewing) { if let plan { SettlementReviewView(plan: plan) } }
            .alert(tr("请核对", "Please review", "Sila semak"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}

struct SettlementReviewView: View {
    @EnvironmentObject var model: LedgerModel
    let plan: SettlementPlan
    @State private var commitID = UUID().uuidString
    @State private var savedID: String?
    @State private var error: String?
    var body: some View {
        Group {
            if let savedID { SettlementDetailView(id: savedID) }
            else {
                Form {
                    Section(plan.name) {
                        LabeledContent(tr("朋友欠我", "They owe me", "Mereka berhutang kepada saya"), value: money(plan.receivable))
                        LabeledContent(tr("我欠朋友", "I owe them", "Saya berhutang kepada mereka"), value: money(plan.payable))
                        LabeledContent(tr("相互抵扣", "Offset", "Tolakan"), value: money(plan.offset))
                        LabeledContent {
                            TransactionAmount(cents: abs(plan.transfer), direction: plan.transfer > 0 ? .incoming : (plan.transfer < 0 ? .outgoing : .neutral))
                        } label: { Text(settlementDirection(plan.transfer, name: plan.name)) }
                        LabeledContent(tr("付款后所选余额", "Selected balance after payment", "Baki dipilih selepas bayaran"), value: money(abs(plan.fullNet - plan.transfer)))
                        Text(dateLabel(plan.date))
                    }
                    Section(tr("结算明细", "Settlement details", "Butiran penyelesaian")) {
                        ForEach(plan.lines) { line in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(line.expense.merchant).font(.headline)
                                Text(dateLabel(line.expense.date) + " · " + line.expense.categorySummary).font(.caption)
                                Text(settledDebtLabel(line.applied) + " · " + money(abs(line.applied)))
                                LabeledContent(tr("保留未结余额", "Left outstanding", "Baki belum selesai"), value: money(abs(line.before - line.applied))).font(.caption)
                            }
                        }
                    }
                    Section {
                        Text(tr("确认实际付款已完成，或双方已同意本次抵扣。消费金额不会改变；银行记录可稍后手动关联，请勿再次记为收入、消费或还款。", "Confirm the actual payment is complete, or both people agree to this offset. Spending stays unchanged. Link its bank record later rather than recording the payment again as income, spending or another repayment.", "Sahkan bayaran sebenar selesai atau kedua-dua pihak bersetuju dengan tolakan ini. Belanja kekal. Pautkan rekod bank kemudian tanpa merekod bayaran sekali lagi sebagai pendapatan, belanja atau bayaran balik lain."))
                        Button(plan.transfer == 0 ? tr("确认抵扣，无需转账", "Confirm offset · no transfer", "Sahkan tolakan · tiada pindahan") : tr("确认已付款", "Confirm payment completed", "Sahkan bayaran selesai")) {
                            do {
                                try LocalStore.shared.change { try $0.confirmSettlement(plan, id: commitID) }
                                model.reload(postRecurring: false); savedID = commitID
                                model.showSaved(message: tr("结算已保存", "Settlement saved", "Penyelesaian disimpan"))
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }.yuejiListSurface().navigationTitle(tr("预览结算", "Review settlement", "Semak penyelesaian")).navigationBarTitleDisplayMode(.inline)
            }
        }.alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}

struct SettlementDetailView: View {
    @EnvironmentObject var model: LedgerModel
    let id: String
    @State private var undo = false
    private var record: FriendSettlement? { model.ledger.settlements.first { $0.id == id } }
    var body: some View {
        Form {
            if let record {
                Section(record.name) {
                    Text(settlementDirection(record.transfer, name: record.name)).font(.headline)
                    TransactionAmount(cents: abs(record.transfer), direction: record.accountDirection).font(.largeTitle.bold())
                    if record.transfer == 0 { Text(tr("仅抵扣欠款，我的账户无收支", "Debts offset only · no account movement", "Hanya tolakan hutang · tiada aliran akaun")).font(.caption).foregroundStyle(.secondary) }
                    Text(dateLabel(record.date))
                    if !record.active { Label(tr("已撤销，欠款已恢复", "Undone · debts restored", "Dibatalkan · hutang dipulihkan"), systemImage: "arrow.uturn.backward") }
                    Text(tr("结算不是消费或收入。原始消费保留。", "A settlement is neither spending nor income. Original expenses stay.", "Penyelesaian bukan belanja atau pendapatan. Belanja asal kekal.")).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup(tr("展开计算明细", "Expand calculation", "Kembangkan pengiraan")) {
                        ForEach(record.lines) { line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.expense.merchant).font(.headline)
                                Text(dateLabel(line.expense.date) + " · " + line.expense.categorySummary).font(.caption)
                                LabeledContent(tr("付款人", "Paid by", "Dibayar oleh"), value: line.expense.payerLabel)
                                LabeledContent(tr("我的消费", "My spending", "Belanja saya"), value: money(line.expense.personal))
                                ForEach(line.expense.shares) { share in LabeledContent(share.name, value: money(share.cents)) }
                                LabeledContent(tr("结算前", "Before settlement", "Sebelum penyelesaian"), value: money(abs(line.before)))
                                LabeledContent(settledDebtLabel(line.applied), value: money(abs(line.applied)))
                                LabeledContent(tr("本次结算后尚欠", "Outstanding after this settlement", "Baki selepas penyelesaian ini"), value: money(abs(line.before - line.applied)))
                                if model.ledger.expenses.contains(where: { $0.id == line.expense.id }) {
                                    NavigationLink(tr("查看原账目", "View original expense", "Lihat belanja asal")) { ExpenseDetailView(id: line.expense.id) }
                                }
                            }.font(.subheadline).padding(.vertical, 6)
                        }
                    }
                }
                if record.active {
                    Section(tr("银行 / TNG 付款", "Bank / TNG payment", "Bayaran bank / TNG")) {
                        if let noticeID = record.paymentNoticeID, let notice = model.ledger.tngNotices.first(where: { $0.id == noticeID }) {
                            LabeledContent {
                                TransactionAmount(cents: notice.cents ?? 0, direction: notice.accountDirection)
                            } label: { Text(tr("已关联：", "Linked: ", "Dipautkan: ") + notice.provider) }
                            DisclosureGroup(tr("付款原文", "Payment notification", "Notifikasi bayaran")) { Text(notice.body).textSelection(.enabled) }
                        } else if record.transfer != 0 {
                            NavigationLink(tr("手动关联付款", "Link payment manually", "Pautkan bayaran secara manual")) { SettlementPaymentLinkView(settlementID: id) }
                        } else { Text(tr("无需转账", "No transfer required", "Tiada pindahan diperlukan")) }
                    }
                    Section { Button(tr("撤销此结算", "Undo this settlement", "Batalkan penyelesaian ini"), role: .destructive) { undo = true } }
                }
                if let payment = record.convertedPayment {
                    Section {
                        DisclosureGroup(tr("已转为结算的自动付款", "Automatic payment converted to settlement", "Bayaran automatik ditukar kepada penyelesaian")) {
                            Text(payment.merchant + " · " + money(payment.cents))
                            Text(dateLabel(payment.date) + " · " + sourceLabel(payment.source))
                            if let note = payment.note { Text(note) }
                            Text(tr("此资料仅为审计保留，不计入消费。", "Kept for audit only; excluded from spending.", "Disimpan untuk audit sahaja; dikecualikan daripada belanja."))
                        }
                    }
                }
            } else { Text(tr("记录不存在", "Record not found", "Rekod tidak ditemui")) }
        }.yuejiListSurface().navigationTitle(tr("结算详情", "Settlement details", "Butiran penyelesaian")).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(tr("恢复欠款？原消费不变，银行付款保留并恢复待确认，不会重复记账。", "Restore debts? Spending stays unchanged. The bank payment remains for review and is never duplicated.", "Pulihkan hutang? Belanja kekal. Bayaran bank kekal untuk semakan dan tidak digandakan."), isPresented: $undo, titleVisibility: .visible) {
                Button(tr("确认撤销", "Confirm undo", "Sahkan pembatalan"), role: .destructive) { model.change { try $0.undoSettlement(id: id) } }
            }
    }
}

struct SettlementPaymentLinkView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let settlementID: String
    var initialNoticeID: String? = nil
    @State private var selectedID: String?
    @State private var distinct = false
    @State private var error: String?
    private var record: FriendSettlement? { model.ledger.settlements.first { $0.id == settlementID } }
    private var candidates: [TNGNotice] {
        guard let record else { return [] }
        return model.ledger.tngNotices.filter {
            $0.settlementID == nil && $0.resolution == nil && $0.cents == abs(record.transfer)
            && ["pending", "transfer", "recorded"].contains($0.status)
            && (record.transfer > 0 ? $0.kind == "incoming" : ["payment", "transfer"].contains($0.kind))
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        Form {
            Section {
                Text(tr("相同金额不代表同一笔付款。请核对日期、方向、银行参考编号和交易对象后确认。", "An identical amount does not identify a payment. Check the date, direction, bank reference and counterparty before confirming.", "Amaun sama tidak mengenal pasti bayaran. Semak tarikh, arah, rujukan bank dan pihak transaksi sebelum mengesahkan."))
                ForEach(candidates) { notice in
                    Button { selectedID = notice.id; distinct = false } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(notice.provider)
                                    TransactionAmount(cents: notice.cents ?? 0, direction: notice.accountDirection)
                                }
                                Text(dateLabel(notice.date) + " · " + (notice.party ?? "")).font(.caption)
                                if let reference = notice.bankReference { Text(reference).font(.caption) }
                            }
                            Spacer()
                            if selectedID == notice.id { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                }
                if candidates.isEmpty { Text(tr("没有可关联的付款。可稍后从银行通知详情关联。", "No eligible payment yet. Link it later from the bank notification details.", "Belum ada bayaran layak. Pautkan kemudian daripada butiran notifikasi bank.")) }
            }
            if let notice = candidates.first(where: { $0.id == selectedID }) {
                Section(tr("核对付款", "Review payment", "Semak bayaran")) {
                    Text(notice.body).textSelection(.enabled)
                    if notice.expenseID != nil {
                        Text(tr("此付款曾自动计入消费。确认后会转为结算付款并移除重复消费，原付款资料保留在结算中。", "This payment was automatically recorded as spending. Confirmation converts it to a settlement payment and removes that extra spending. Its original details remain in the settlement audit.", "Bayaran ini direkod automatik sebagai belanja. Pengesahan menukarnya kepada bayaran penyelesaian dan membuang belanja tambahan. Butiran asal kekal dalam audit penyelesaian."))
                    }
                    if notice.possibleDuplicate { Toggle(tr("已核对，确认为独立付款", "Checked: this is a distinct payment", "Disemak: ini bayaran berasingan"), isOn: $distinct) }
                    Button(tr("确认关联", "Confirm link", "Sahkan pautan")) {
                        do {
                            try LocalStore.shared.change { try $0.linkSettlementPayment(settlementID: settlementID, noticeID: notice.id, distinctConfirmed: distinct) }
                            model.reload(postRecurring: false); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(notice.possibleDuplicate && !distinct)
                }
            }
        }.yuejiListSurface().navigationTitle(tr("关联结算付款", "Link settlement payment", "Pautkan bayaran penyelesaian")).navigationBarTitleDisplayMode(.inline)
            .onAppear { if selectedID == nil { selectedID = initialNoticeID } }
            .alert(tr("无法关联", "Unable to link", "Tidak dapat memautkan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}

struct SettlementNoticeSection: View {
    @EnvironmentObject var model: LedgerModel
    let notice: TNGNotice
    var body: some View {
        if let id = notice.settlementID {
            Section { NavigationLink(tr("查看结算与原账目", "View settlement and expenses", "Lihat penyelesaian dan belanja")) { SettlementDetailView(id: id) } }
        } else if ["pending", "transfer", "recorded"].contains(notice.status), notice.resolution == nil {
            Section {
                NavigationLink(tr("关联已有结算", "Link an existing settlement", "Pautkan penyelesaian sedia ada")) {
                    List {
                        ForEach(model.ledger.settlements.filter { $0.active && $0.paymentNoticeID == nil && $0.transfer != 0 && abs($0.transfer) == notice.cents && ($0.transfer > 0 ? notice.kind == "incoming" : ["payment", "transfer"].contains(notice.kind)) }) { record in
                            NavigationLink(record.name + " · " + dateLabel(record.date)) { SettlementPaymentLinkView(settlementID: record.id, initialNoticeID: notice.id) }
                        }
                        Text(tr("先在朋友页面预览并确认结算，再手动选择付款。", "Review and confirm a settlement on the friend's page first, then select its payment manually.", "Semak dan sahkan penyelesaian di halaman rakan dahulu, kemudian pilih bayaran secara manual.")).font(.footnote).foregroundStyle(.secondary)
                    }.navigationTitle(tr("选择结算", "Choose settlement", "Pilih penyelesaian"))
                }
            }
        }
    }
}
