import SwiftUI

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
                    Text(money(entries.reduce(0) { $0 + ($1.reimbursement?.outstanding ?? 0) }))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                }
                LabeledContent(tr("已到账", "Received", "Diterima"), value: money(entries.reduce(0) { $0 + ($1.reimbursement?.received ?? 0) }))
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
                ContentUnavailableView {
                    Label(tr("暂无报销记录", "No reimbursements", "Tiada tuntutan"), systemImage: "doc.text")
                } description: {
                    Text(tr("在新增或编辑账目中打开“需要报销”，也可从账目详情设置。", "Mark an entry as reimbursable when adding or editing, or set it up in entry details.", "Tandakan rekod sebagai boleh dituntut ketika menambah atau mengedit, atau tetapkan dalam butiran rekod."))
                }.listRowBackground(Color.clear)
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
                            Text(claim.status + " · " + dateLabel(entry.date)).font(.caption).foregroundStyle(.secondary)
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
            .task(id: model.ledgerRevision) {
                let ledger = model.ledger
                let prepared = await ReimbursementProjection.shared.entries(in: ledger)
                guard !Task.isCancelled else { return }
                entries = prepared
                loaded = true
            }
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
                        LabeledContent(tr("状态", "Status", "Status"), value: claim.status)
                        LabeledContent(tr("报销对象", "Reimbursed by", "Dibayar balik oleh"), value: claim.recipient)
                        LabeledContent(tr("报销金额", "Claim amount", "Amaun tuntutan"), value: money(claim.cents))
                        LabeledContent(tr("已到账", "Received", "Diterima"), value: money(claim.received))
                        LabeledContent(tr("待到账", "Outstanding", "Belum diterima"), value: money(claim.outstanding))
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
                                    Text(money(receipt.cents)).fontWeight(.medium).monospacedDigit()
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
                ContentUnavailableView(tr("账目已删除", "Entry deleted", "Rekod dipadam"), systemImage: "tray")
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
                Text(tr("只修正报销记录，不会转移资金。", "This corrects the record; it does not transfer money.", "Ini membetulkan rekod; ia tidak memindahkan wang."))
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
            } catch { error = error.localizedDescription }
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
    @State private var date = Date()
    @State private var initial: [String]?
    @State private var saving = false
    @State private var confirmingDiscard = false
    @State private var error: String?
    @FocusState private var focused: ExpenseInputField?
    private var snapshot: [String] { [String(enabled), recipient, amount, String(date.timeIntervalSince1970)] }
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
                        Button(tr("取消", "Cancel", "Batal")) {
                            focused = nil
                            if hasChanges { confirmingDiscard = true } else { dismiss() }
                        }.disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { save() } label: { EditorSaveLabel(saving: saving) }
                            .yuejiPrimaryButton().disabled(saving || initial == nil)
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
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") {}
                } message: { Text(error ?? "") }
        }.yuejiSheetSurface().ledgerFeedback(modal: true)
            .editorDismissal(hasChanges: hasChanges, saving: saving, confirming: $confirmingDiscard, discard: { dismiss() })
    }
    private func save() {
        guard !saving, initial != nil else { return }
        do {
            let receipt = receiptMode ? ReimbursementReceipt(cents: try toCents(amount), date: date) : nil
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
                } catch { error = error.localizedDescription; FeedbackHaptics.error() }
            }
        } catch { error = error.localizedDescription; FeedbackHaptics.error() }
    }
}
