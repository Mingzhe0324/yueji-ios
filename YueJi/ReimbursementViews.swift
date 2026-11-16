import SwiftUI

/// One selection flow shared by both notification review screens.
struct ReimbursementMatchFields: View {
    @EnvironmentObject private var model: LedgerModel
    let party: String
    let cents: Int
    let date: Date
    @Binding var selected: Set<String>
    @Binding var rounding: Int
    private var suggested: Set<String> { model.ledger.suggestedReimbursements(party: party, cents: cents, date: date) }
    private var difference: Int { model.ledger.reimbursementRounding(cents: cents, date: date, selected: selected) }
    private var preview: [ReimbursementAllocation]? { try? model.ledger.previewReimbursement(cents: cents, date: date, selected: selected, roundingCents: difference) }
    var body: some View {
        if selected.isEmpty, !suggested.isEmpty {
            Button {
                selected = suggested
            } label: {
                Label(tr("使用推荐账目", "Use suggested claims", "Guna tuntutan dicadangkan"), systemImage: "sparkles")
            }
            Text(model.ledger.openReimbursements(on: date).filter { suggested.contains($0.id) }.map(\.displayName).joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        NavigationLink {
            ReimbursementMatchPicker(cents: cents, date: date, selected: $selected)
        } label: {
            LabeledContent(tr("选择报销账目", "Choose claim entry", "Pilih rekod tuntutan"), value: selected.isEmpty ? tr("请选择", "Choose", "Pilih") : String(selected.count))
        }.accessibilityIdentifier("notice.reimbursement.entry")
        if let preview {
            ForEach(preview) { line in
                LabeledContent(model.expense(id: line.expenseID)?.displayName ?? "", value: money(line.cents))
                    .font(.subheadline)
            }
            if difference > 0 {
                Toggle(isOn: Binding(get: { rounding == difference }, set: { rounding = $0 ? difference : 0 })) {
                    Text(tr("多收金额记为尾差", "Record extra as rounding", "Rekod lebihan sebagai pembundaran") + " · " + money(difference))
                }.accessibilityIdentifier("reimbursement.rounding")
            }
        } else if !selected.isEmpty {
            Text(tr("请调整所选账目，使本次到账金额可以分配。", "Adjust your selection to cover this receipt.", "Laraskan pilihan untuk meliputi penerimaan ini."))
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

private struct ReimbursementMatchPicker: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let cents: Int
    let date: Date
    @Binding var selected: Set<String>
    @State private var search = ""
    private var entries: [Expense] { model.ledger.openReimbursements(on: date) }
    private var filteredEntries: [Expense] {
        entries.filter { entry in
            search.isEmpty || entry.displayName.localizedCaseInsensitiveContains(search)
                || (entry.reimbursement?.recipient.localizedCaseInsensitiveContains(search) ?? false)
        }
    }
    private func entrySubtitle(_ entry: Expense) -> String {
        let recipient = entry.reimbursement?.recipient ?? ""
        let outstanding = money(entry.reimbursement?.outstanding ?? 0)
        return [recipient, outstanding, dateLabel(entry.date)].joined(separator: " · ")
    }
    var body: some View {
        List {
            Section {
                LabeledContent(tr("本次到账", "Received now", "Diterima sekarang"), value: money(cents))
            } footer: {
                Text(tr("可选多笔，先报销较早的账目。", "Select one or more; earlier entries are reimbursed first.", "Pilih satu atau lebih; rekod terdahulu dibayar dahulu."))
            }
            ForEach(filteredEntries) { entry in
                Toggle(isOn: Binding(get: { selected.contains(entry.id) }, set: { if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) } })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName)
                        Text(entrySubtitle(entry))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if entries.isEmpty {
                Text(tr("没有待报销账目", "No outstanding claims", "Tiada tuntutan tertunggak")).foregroundStyle(.secondary)
            }
            NavigationLink { ReimbursementEntryPicker() } label: {
                Text(tr("找不到？添加报销账目", "Missing a claim? Add it", "Tiada tuntutan? Tambah"))
            }
        }.yuejiListSurface().searchable(text: $search)
            .onChange(of: model.ledgerRevision) { _, _ in selected.formIntersection(Set(entries.map(\.id))) }
            .navigationTitle(tr("选择报销账目", "Choose claim entry", "Pilih rekod tuntutan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(tr("完成", "Done", "Selesai")) { dismiss() }
                    .disabled((try? model.ledger.previewReimbursement(cents: cents, date: date, selected: selected, roundingCents: model.ledger.reimbursementRounding(cents: cents, date: date, selected: selected))) == nil)
            } }
    }
}

struct ReimbursementStatusBadge: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let claim: ReimbursementClaim
    private var complete: Bool { claim.outstanding == 0 }
    var body: some View {
        let _ = locale.identifier
        Label(claim.status, systemImage: complete ? "checkmark.circle.fill" : "clock")
            .font(.caption.weight(.medium))
            .foregroundStyle(complete ? Color.green : Color.orange)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((complete ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            .animation(reduceMotion || !ElegantMotion.enabled ? nil : YueJiMotion.month, value: complete)
            .accessibilityIdentifier("reimbursement.status")
    }
}

struct ReimbursementDraftFields: View {
    @FocusState private var localFocus: ExpenseInputField?
    @Binding var enabled: Bool
    @Binding var recipient: String
    @Binding var amount: String
    var canRemove = true
    var friendPaid = false
    var sharedFocus: FocusState<ExpenseInputField?>.Binding? = nil
    private var focus: FocusState<ExpenseInputField?>.Binding { sharedFocus ?? $localFocus }
    var body: some View {
        Section {
            Toggle(tr("需要报销", "Reimbursable", "Boleh dituntut"), isOn: $enabled)
                .disabled((friendPaid && !enabled) || !canRemove)
                .accessibilityIdentifier("reimbursement.enabled")
            if enabled {
                TextField(tr("公司／报销对象", "Company / reimbursed by", "Syarikat / pembayar balik"), text: $recipient)
                    .focused(focus, equals: .reimbursementRecipient)
                    .accessibilityIdentifier("reimbursement.recipient")
                LabeledContent(tr("报销金额 · MYR", "Claim amount · MYR", "Amaun tuntutan · MYR")) {
                    TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .focused(focus, equals: .reimbursementAmount)
                        .monospacedDigit().accessibilityIdentifier("reimbursement.amount")
                }
            }
        } header: {
            Text(tr("报销 · 选填", "Reimbursement · optional", "Tuntutan · pilihan"))
        } footer: {
            if friendPaid {
                Text(tr("报销用于我已垫付的部分；朋友代付请先处理付款人。", "Reimbursements track money you paid. Review the payer for friend-paid entries.", "Tuntutan menjejak wang yang anda bayar. Semak pembayar untuk rekod dibayar rakan."))
            } else if !canRemove {
                Text(tr("已有到账记录。取消报销前，请在报销详情中撤销这些记录。", "Undo receipts in reimbursement details before removing this claim.", "Batalkan penerimaan dalam butiran tuntutan sebelum membuang tuntutan."))
            } else {
                Text(tr("报销金额从个人消费和预算中排除；原付款保留，到账单独记录。", "Claimed amounts are excluded from personal spending and budgets. Original payment is kept; receipts are tracked separately.", "Amaun tuntutan dikecualikan daripada belanja peribadi dan bajet. Bayaran asal disimpan; penerimaan dijejak berasingan."))
            }
        }
    }
}

private actor ReimbursementProjection {
    static let shared = ReimbursementProjection()
    func entries(in ledger: Ledger) -> [Expense] {
        ledger.expenses.filter { $0.reimbursement != nil }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}

struct ReimbursementsView: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.locale) private var locale
    @State private var entries: [Expense] = []
    @State private var loaded = false
    @State private var filter = "pending"
    @State private var addingManual = false
    @State private var choosingEntry = false
    private var displayed: [Expense] {
        entries.filter { entry in
            filter == "all" || (filter == "pending" ? (entry.reimbursement?.outstanding ?? 0) > 0 : entry.reimbursement?.outstanding == 0)
        }
    }
    var body: some View {
        let _ = locale.identifier
        List {
            Section {
                LabeledContent(tr("待到账垫付款", "Outstanding advances", "Pendahuluan belum diterima")) {
                    AnimatedMoney(cents: entries.reduce(0) { $0 + ($1.reimbursement?.outstanding ?? 0) })
                        .font(.title2.weight(.semibold)).monospacedDigit()
                }
                LabeledContent(tr("已到账", "Received", "Diterima"), value: money(entries.reduce(0) { $0 + ($1.reimbursement?.received ?? 0) }))
                SpendingMeter(value: entries.reduce(0) { $0 + ($1.reimbursement?.received ?? 0) },
                              total: entries.reduce(0) { $0 + ($1.reimbursement?.cents ?? 0) }, color: IslandTheme.accent)
                Picker(tr("报销状态", "Reimbursement status", "Status tuntutan"), selection: $filter) {
                    Text(tr("待到账", "Pending", "Belum diterima")).tag("pending")
                    Text(tr("已收齐", "Received", "Diterima")).tag("received")
                    Text(tr("全部", "All", "Semua")).tag("all")
                }.pickerStyle(.segmented)
            }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityLabel(tr("正在加载报销", "Loading reimbursements", "Memuatkan tuntutan"))
            } else if displayed.isEmpty {
                IslandEmptyState(title: tr("暂无报销记录", "No reimbursements", "Tiada tuntutan"),
                    message: tr("点右上角“新增报销”，选择已有账目或手动新增。已自动记账的付款直接选择即可。", "Tap Add claim at the top right to choose an existing entry or add one manually. Reuse automatically recorded payments.", "Ketik Tambah tuntutan di kanan atas untuk memilih rekod sedia ada atau menambah secara manual. Gunakan bayaran yang telah direkod automatik."),
                    mood: .happy).listRowBackground(Color.clear)
            }
            ForEach(displayed) { entry in
                NavigationLink { ReimbursementDetailView(expenseID: entry.id) } label: {
                    if let claim = entry.reimbursement {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.displayName).fontWeight(.semibold)
                                Spacer(minLength: 12)
                                Text(money(claim.cents)).monospacedDigit()
                            }
                            Text(claim.recipient).font(.subheadline).foregroundStyle(.secondary)
                            ReimbursementStatusBadge(claim: claim)
                            Text(dateLabel(entry.date)).font(.caption).foregroundStyle(.secondary)
                            if claim.outstanding > 0 {
                                Text(tr("待到账：", "Outstanding: ", "Belum diterima: ") + money(claim.outstanding))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
        }.yuejiListSurface()
            .navigationTitle(tr("报销管理", "Reimbursements", "Tuntutan bayaran balik"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { choosingEntry = true } label: {
                            Label(tr("从已有账目申请报销", "Claim an existing entry", "Tuntut rekod sedia ada"), systemImage: "doc.text.magnifyingglass")
                        }
                        Button { addingManual = true } label: {
                            Label(tr("手动新增报销账目", "Add a manual claim entry", "Tambah rekod tuntutan manual"), systemImage: "square.and.pencil")
                        }
                    } label: {
                        Label(tr("新增报销", "Add claim", "Tambah tuntutan"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("reimbursement.add")
                }
            }
            .navigationDestination(isPresented: $choosingEntry) { ReimbursementEntryPicker() }
            .sheet(isPresented: $addingManual) {
                ExpenseEditor(original: nil, startsReimbursement: true)
            }
            .task(id: model.ledgerRevision) {
                let ledger = model.ledger
                let prepared = await ReimbursementProjection.shared.entries(in: ledger)
                guard !Task.isCancelled else { return }
                entries = prepared
                loaded = true
            }
    }
}

private struct ReimbursementEntryPicker: View {
    @EnvironmentObject private var model: LedgerModel
    @State private var search = ""
    @State private var source = "all"
    private var entries: [Expense] {
        model.ledger.expenses.filter {
            $0.reimbursement == nil && $0.paidByFriend == nil &&
            (source == "all" || (source == "manual" ? $0.source == "手动" : $0.source != "手动")) &&
            (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search))
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            Picker(tr("账目来源", "Entry source", "Sumber rekod"), selection: $source) {
                Text(tr("全部", "All", "Semua")).tag("all")
                Text(tr("自动／导入", "Auto / imported", "Auto / import")).tag("auto")
                Text(tr("手动", "Manual", "Manual")).tag("manual")
            }.pickerStyle(.segmented)
            ForEach(entries) { entry in
                NavigationLink { ReimbursementDetailView(expenseID: entry.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.displayName).fontWeight(.semibold)
                            Spacer()
                            Text(money(entry.cents)).monospacedDigit()
                        }
                        Text(dateLabel(entry.date) + " · " + entry.source)
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            if entries.isEmpty {
                Text(tr("没有符合条件的账目", "No matching entries", "Tiada rekod sepadan"))
                    .foregroundStyle(.secondary)
            }
        }.yuejiListSurface()
            .searchable(text: $search)
            .navigationTitle(tr("选择报销账目", "Choose claim entry", "Pilih rekod tuntutan"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReimbursementEditorRoute: Identifiable {
    let expense: Expense
    let receiptMode: Bool
    var id: String { expense.id + (receiptMode ? "-receipt" : "-claim") }
}

struct ReimbursementDetailView: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.locale) private var locale
    let expenseID: String
    @State private var editing: ReimbursementEditorRoute?
    @State private var undo: ReimbursementReceipt?
    @State private var busy = false
    @State private var error: String?
    private var expense: Expense? { model.expense(id: expenseID) }
    var body: some View {
        let _ = locale.identifier
        List {
            if let entry = expense {
                Section {
                    Text(entry.displayName).font(.headline)
                    LabeledContent(tr("原付款", "Original payment", "Bayaran asal"), value: money(entry.paidFromMyAccount))
                    LabeledContent(tr("个人消费", "Personal spending", "Belanja peribadi"), value: money(entry.personalSpending))
                }
                if let claim = entry.reimbursement {
                    Section {
                        LabeledContent(tr("状态", "Status", "Status")) { ReimbursementStatusBadge(claim: claim) }
                        LabeledContent(tr("报销对象", "Reimbursed by", "Dibayar balik oleh"), value: claim.recipient)
                        LabeledContent(tr("报销金额", "Claim amount", "Amaun tuntutan"), value: money(claim.cents))
                        LabeledContent(tr("已到账", "Received", "Diterima")) { AnimatedMoney(cents: claim.received) }
                        LabeledContent(tr("待到账", "Outstanding", "Belum diterima")) { AnimatedMoney(cents: claim.outstanding) }
                        SpendingMeter(value: claim.received, total: claim.cents, color: .green)
                    } footer: {
                        Text(tr("报销到账只更新进度，不记为收入，也不会再次减少个人消费。", "Receipts update progress without adding income or reducing personal spending again.", "Penerimaan mengemas kini kemajuan tanpa menambah pendapatan atau mengurangkan belanja sekali lagi."))
                    }
                    Section {
                        Button { editing = ReimbursementEditorRoute(expense: entry, receiptMode: true) } label: {
                            Label(tr("记录到账", "Record receipt", "Rekod penerimaan"), systemImage: "plus.circle")
                        }.disabled(claim.outstanding == 0 || entry.date > Date()).accessibilityIdentifier("reimbursement.receive")
                        Button(tr("编辑报销", "Edit reimbursement", "Edit tuntutan")) {
                            editing = ReimbursementEditorRoute(expense: entry, receiptMode: false)
                        }.accessibilityIdentifier("reimbursement.edit")
                    }
                    Section(tr("到账记录", "Receipts", "Penerimaan")) {
                        ForEach(claim.receipts.sorted { $0.date > $1.date }) { receipt in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(money(receipt.cents + (receipt.roundingCents ?? 0))).fontWeight(.medium).monospacedDigit()
                                    if let rounding = receipt.roundingCents {
                                        Text(tr("尾差", "Rounding", "Pembundaran") + " · " + money(rounding)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(dateLabel(receipt.date, time: true)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(tr("撤销", "Undo", "Batal"), role: .destructive) { undo = receipt }
                                    .buttonStyle(.borderless)
                            }.padding(.vertical, 4)
                        }
                        if claim.receipts.isEmpty {
                            Text(tr("尚未记录到账", "No receipts yet", "Belum ada penerimaan")).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Button { editing = ReimbursementEditorRoute(expense: entry, receiptMode: false) } label: {
                            Label(tr("设置报销", "Set up reimbursement", "Tetapkan tuntutan"), systemImage: "doc.text")
                        }.disabled(entry.paidByFriend != nil)
                    } footer: {
                        Text(tr("报销用于我已垫付的部分；从标记起排除个人消费与预算。", "Claims track your paid share and exclude it from personal spending and budgets from the time you mark it.", "Tuntutan menjejak bahagian yang anda bayar dan mengecualikannya daripada belanja peribadi serta bajet selepas ditandakan."))
                    }
                }
            } else {
                IslandEmptyState(title: tr("账目已删除", "Entry deleted", "Rekod dipadam"), mood: .sad)
                    .listRowBackground(Color.clear)
            }
        }.yuejiListSurface().disabled(busy)
            .navigationTitle(tr("报销详情", "Reimbursement details", "Butiran tuntutan"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { route in
                ReimbursementEditor(expense: route.expense, receiptMode: route.receiptMode)
            }
            .alert(tr("撤销到账记录？", "Undo this receipt?", "Batalkan penerimaan ini?"), isPresented: Binding(get: { undo != nil }, set: { if !$0 { undo = nil } })) {
                Button(tr("撤销", "Undo", "Batal"), role: .destructive) { undoReceipt() }
                Button(tr("取消", "Cancel", "Batal"), role: .cancel) { undo = nil }
            } message: {
                Text(undo?.noticeID == nil
                     ? tr("只修正记录，不会转移资金。", "Corrects records only; no money is moved.", "Membetulkan rekod sahaja; tiada wang dipindahkan.")
                     : tr("同一笔收款关联的报销会一起撤销，恢复待核对。", "All claims linked to this receipt return to review together.", "Semua tuntutan dipautkan kepada penerimaan ini kembali untuk semakan bersama."))
            }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
    }
    private func undoReceipt() {
        guard !busy, let receipt = undo, let expected = expense else { return }
        undo = nil; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await model.mutate({ try $0.undoReimbursementReceipt(expense: expected, receiptID: receipt.id) }, postRecurring: false)
                model.showSaved(message: tr("到账记录已撤销", "Receipt undone", "Penerimaan dibatalkan"))
            } catch let failure { self.error = failure.localizedDescription }
        }
    }
}

private struct ReimbursementEditor: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let expense: Expense
    let receiptMode: Bool
    @State private var enabled = true
    @State private var recipient = ""
    @State private var amount = ""
    @State private var acceptRounding = false
    private var rounding: Int { max(0, ((try? toCents(amount)) ?? 0) - (expense.reimbursement?.outstanding ?? 0)) }
    @State private var date = Date()
    @State private var initial: [String]?
    @State private var saving = false
    @State private var confirmingDiscard = false
    @State private var error: String?
    @FocusState private var focused: ExpenseInputField?
    private var snapshot: [String] { [String(enabled), recipient, amount, String(date.timeIntervalSince1970), String(acceptRounding)] }
    private var hasChanges: Bool { initial.map { $0 != snapshot } ?? false }
    var body: some View {
        let _ = locale.identifier
        NavigationStack {
            Form {
                Section {
                    Text(expense.displayName).font(.headline)
                    LabeledContent(tr("我的净份额", "My net share", "Bahagian bersih saya"), value: money(expense.personal))
                }
                if receiptMode {
                    Section {
                        TextField(tr("到账金额 · MYR", "Received amount · MYR", "Amaun diterima · MYR"), text: $amount)
                            .keyboardType(.decimalPad).focused($focused, equals: .reimbursementAmount)
                            .accessibilityIdentifier("reimbursement.received.amount")
                        if rounding > 0 {
                            Toggle(tr("多收金额记为尾差", "Record extra as rounding", "Rekod lebihan sebagai pembundaran") + " · " + money(rounding), isOn: $acceptRounding)
                        }
                        DatePicker(tr("到账日期", "Receipt date", "Tarikh diterima"), selection: $date, in: min(expense.date, Date())...Date(), displayedComponents: [.date, .hourAndMinute])
                        Button(tr("填入待到账金额", "Fill outstanding amount", "Isi baki belum diterima")) {
                            amount = Currency.input(expense.reimbursement?.outstanding ?? 0, "MYR")
                        }
                    }
                } else {
                    ReimbursementDraftFields(enabled: $enabled, recipient: $recipient, amount: $amount,
                        canRemove: expense.reimbursement?.receipts.isEmpty ?? true, sharedFocus: $focused)
                    if enabled {
                        Section {
                            Button(tr("填入我的净份额", "Fill my net share", "Isi bahagian bersih saya")) {
                                amount = Currency.input(expense.personal, "MYR")
                            }
                        }
                    }
                }
            }.yuejiListSurface().disabled(saving)
                .navigationTitle(receiptMode ? tr("记录到账", "Record receipt", "Rekod penerimaan") : tr("编辑报销", "Edit reimbursement", "Edit tuntutan"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("取消", "Cancel", "Batal"), systemImage: "xmark") {
                            focused = nil
                            if hasChanges { confirmingDiscard = true } else { dismiss() }
                        }.disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { save() } label: { EditorSaveLabel(saving: saving) }
                            .yuejiPrimaryButton().disabled(saving || initial == nil || (receiptMode && rounding > 0 && !acceptRounding))
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(tr("完成", "Done", "Selesai")) { focused = nil }
                    }
                }
                .onAppear {
                    guard initial == nil else { return }
                    recipient = expense.reimbursement?.recipient ?? ""
                    amount = Currency.input(receiptMode ? (expense.reimbursement?.outstanding ?? 0) : (expense.reimbursement?.cents ?? expense.personal), "MYR")
                    initial = snapshot
                }
                .onChange(of: amount) { _, _ in acceptRounding = false }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") {}
                } message: { Text(error ?? "") }
        }.yuejiSheetSurface().ledgerFeedback(modal: true)
            .editorDismissal(hasChanges: hasChanges, saving: saving, confirming: $confirmingDiscard, discard: { dismiss() })
    }
    private func save() {
        guard !saving, initial != nil else { return }
        do {
            if receiptMode && rounding > 0 && !acceptRounding { return }
            let receipt = receiptMode ? ReimbursementReceipt(cents: try toCents(amount) - rounding, date: date, roundingCents: rounding > 0 ? rounding : nil) : nil
            let claim = !receiptMode && enabled ? ReimbursementClaim(recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                cents: try toCents(amount), receipts: expense.reimbursement?.receipts ?? []) : nil
            focused = nil; saving = true
            Task { @MainActor in
                defer { saving = false }
                do {
                    let expected = expense
                    try await model.mutate({ ledger in
                        if let receipt { try ledger.receiveReimbursement(expense: expected, receipt: receipt) }
                        else { try ledger.setReimbursement(expense: expected, claim: claim) }
                    }, postRecurring: false)
                    model.showSaved(message: receiptMode ? tr("到账已记录", "Receipt recorded", "Penerimaan direkod") : tr("报销已保存", "Reimbursement saved", "Tuntutan disimpan"))
                    dismiss()
                } catch let failure { self.error = failure.localizedDescription; FeedbackHaptics.error() }
            }
        } catch let failure { self.error = failure.localizedDescription; FeedbackHaptics.error() }
    }
}
