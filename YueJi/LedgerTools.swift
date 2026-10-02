import SwiftUI
import PhotosUI
import Vision

struct BackupHealthView: View {
    @ObservedObject private var cloud = CloudAccount.shared
    @AppStorage("lastExportBackup") private var exported = 0.0
    @AppStorage("lastCloudBackup") private var uploaded = 0.0
    private var latest: Double { max(exported, uploaded) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("备份状态", systemImage: "externaldrive.badge.checkmark")
            Text(latest == 0 ? "还没有成功导出或上传的备份。" : "最近成功备份：" + dateLabel(Date(timeIntervalSince1970: latest), time: true)).font(.footnote)
            if latest == 0 || Date().timeIntervalSince1970 - latest > 7 * 86400 {
                Text("建议现在备份；本机历史副本会随卸载一起删除。导出的文件请保存在 App 文件夹以外。").font(.footnote).foregroundStyle(.orange)
            }
            if cloud.ready { Text("云端自动备份已开启；卸载前请确认同步成功。").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MonthlySummaryView: View {
    @EnvironmentObject private var model: LedgerModel
    let month: Date
    private var difference: Int { model.ledger.spending(in: month) - model.ledger.spending(in: shiftedMonth(month, by: -1)) }
    private var biggest: String? { model.ledger.categoryNames.filter { model.ledger.spending(in: month, category: $0) > model.ledger.spending(in: shiftedMonth(month, by: -1), category: $0) }.max { delta($0) < delta($1) } }
    private func delta(_ category: String) -> Int { model.ledger.spending(in: month, category: category) - model.ledger.spending(in: shiftedMonth(month, by: -1), category: category) }
    var body: some View {
        NavigationLink { SpendingComparisonView(month: month) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label("月度变化", systemImage: "chart.bar.xaxis").font(.headline)
                Text("比上月" + (difference >= 0 ? "多 " : "少 ") + money(abs(difference)))
                if let biggest { Text("增加最多：" + categoryLabel(biggest) + " · +" + money(delta(biggest))).font(.footnote) }
                Text("按已记录的两个自然月比较，本月尚未结束时不会按天折算。").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
}

struct QuickPurposeView: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let notice: TNGNotice
    @State private var purpose = "ownTransfer"
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { TNGTimelineRow(notice: notice) }
                Section("用途") {
                    if notice.kind == "incoming" {
                        NavigationLink("收入 / 自己账户转账 / 朋友还款") { TNGIncomingView(id: notice.id) }
                    } else {
                        Picker("用途", selection: $purpose) { Text("自己账户转账 / Top up").tag("ownTransfer"); Text("普通转账，待确认").tag("transfer") }
                        Text("自己账户之间转账不计入消费。不会根据收款人姓名自动猜测。").font(.footnote)
                        Button("确认用途") {
                            do {
                                try LocalStore.shared.change { ledger in
                                    guard let i = ledger.tngNotices.firstIndex(where: { $0.id == notice.id }), ledger.tngNotices[i] == notice,
                                          notice.kind == "transfer", notice.expenseID == nil, !notice.possibleDuplicate else { throw LedgerError.invalid("记录已更改或可能重复，请打开原记录核对。") }
                                    ledger.tngNotices[i].status = purpose
                                }
                                model.reload(postRecurring: false); model.showSaved(); dismiss()
                            } catch { failure = error.localizedDescription }
                        }
                        NavigationLink("记为消费 / 其他用途") { TNGNoticeView(id: notice.id) }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.navigationTitle("快速归类").toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct BatchLedgerView: View {
    @EnvironmentObject private var model: LedgerModel
    let month: Date
    @State private var selected: Set<String> = []
    @State private var category = "其他"
    @State private var purpose = "ownTransfer"
    @State private var deleting = false
    @State private var applying = false
    @State private var failure: String?
    private var expenses: [Expense] { model.ledger.expenses.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }.sorted { $0.date > $1.date } }
    private var notices: [TNGNotice] { model.ledger.ledgerTNGTransfers(in: month) }
    private var expenseSelection: [Expense] { expenses.filter { selected.contains("e:" + $0.id) } }
    private var noticeSelection: [TNGNotice] { notices.filter { selected.contains("n:" + $0.id) } }
    var body: some View {
        List {
            Section("已选 \(selected.count) 笔") {
                Button("全选 / 清空") { selected = selected.isEmpty ? Set(expenses.map { "e:" + $0.id } + notices.map { "n:" + $0.id }) : [] }
                Picker("消费分类", selection: $category) { ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) } }
                Button("修改所选消费的分类") { applying = true }.disabled(selected.isEmpty || !noticeSelection.isEmpty)
                Picker("转账用途", selection: $purpose) { Text("自己账户转账").tag("ownTransfer"); Text("收入（仅转入）").tag("income") }
                Button("确认所选转账用途") { classify() }.disabled(selected.isEmpty || !expenseSelection.isEmpty)
                Button("删除所选记录", role: .destructive) { deleting = true }.disabled(selected.isEmpty)
                Text("消费与转账分开操作；朋友还款需逐笔选择朋友，疑似重复记录需先核对。").font(.footnote)
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            Section("消费") { ForEach(expenses) { expense in
                Button { toggle("e:" + expense.id) } label: { HStack { Image(systemName: selected.contains("e:" + expense.id) ? "checkmark.circle.fill" : "circle"); Text(expense.merchant); Spacer(); Text(money(expense.cents)) } }.buttonStyle(.plain)
            } }
            Section("转账") { ForEach(notices) { notice in
                Button { toggle("n:" + notice.id) } label: { HStack { Image(systemName: selected.contains("n:" + notice.id) ? "checkmark.circle.fill" : "circle"); TNGTimelineRow(notice: notice) } }.buttonStyle(.plain)
            } }
        }.navigationTitle("批量整理")
            .onAppear { category = model.ledger.categoryNames.first ?? "其他" }
            .confirmationDialog("删除所选 \(selected.count) 笔记录？", isPresented: $deleting, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) {
                    do { try model.deleteBatch(expenses: expenseSelection, notices: noticeSelection); selected = [] } catch { failure = error.localizedDescription }
                }
            } message: { Text("确认前不会移除记录。删除后可在提示中撤销。") }
            .confirmationDialog("修改所选消费分类？", isPresented: $applying, titleVisibility: .visible) {
                Button("确认修改") {
                    do {
                        let expected = expenseSelection
                        try LocalStore.shared.change { ledger in
                            for expense in expected {
                                guard let i = ledger.expenses.firstIndex(where: { $0.id == expense.id }), ledger.expenses[i] == expense else { throw LedgerError.invalid("有记录已更改，请重新选择。") }
                                ledger.expenses[i].category = category
                            }
                        }; complete()
                    } catch { failure = error.localizedDescription }
                }
            }
    }
    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    private func complete() { selected = []; model.reload(postRecurring: false); model.showSaved() }
    private func classify() {
        do {
            let expected = noticeSelection
            try LocalStore.shared.change { ledger in
                for notice in expected {
                    guard let i = ledger.tngNotices.firstIndex(where: { $0.id == notice.id }), ledger.tngNotices[i] == notice,
                          !notice.possibleDuplicate else { throw LedgerError.invalid("记录已更改或可能重复，请先核对。") }
                    if notice.kind == "incoming" { try ledger.resolveTNGIncoming(id: notice.id, purpose: purpose, date: notice.date) }
                    else {
                        guard purpose == "ownTransfer", notice.kind == "transfer", notice.expenseID == nil else { throw LedgerError.invalid("收入只能用于转入记录。") }
                        ledger.tngNotices[i].status = "ownTransfer"
                    }
                }
            }; complete()
        } catch { failure = error.localizedDescription }
    }
}

struct NotificationImportView: View {
    @EnvironmentObject private var model: LedgerModel
    @State private var title = ""
    @State private var bodyText = ""
    @State private var received = Date()
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var confirming = false
    @State private var status = ""
    private var parsed: TNGParsed? { parseFinancialNotification(bodyText, title: title) }
    var body: some View {
        Form {
            Section("原始通知") {
                TextField("通知标题（如 Transfer Successful）", text: $title)
                TextEditor(text: $bodyText).frame(minHeight: 160)
                PhotosPicker("从通知截图识别文字", selection: $photo, matching: .images)
                DatePicker("接收时间", selection: $received, in: ...Date())
                Text("截图只在本机识别。请删掉无关文字，核对金额、方向与日期；没有系统通知的交易仍需手动补录。").font(.footnote)
            }
            Section("入账预览") {
                if let parsed {
                    Text(parsed.sourceBank + " · " + (parsed.kind == "incoming" ? "转入" : "转出"))
                    Text(money(parsed.cents)).font(.title2).foregroundStyle(parsed.kind == "incoming" ? .green : .red)
                    Text(parsed.party)
                    Text("交易日期：" + dateLabel(parsed.transactionDate ?? received, time: true)).font(.footnote)
                    Text(parsed.kind == "payment" ? "确认后记为消费。" : "确认后放入转账记录，随后可归类用途。").font(.footnote)
                    Button("确认补录") { confirming = true }.disabled(busy)
                } else { Text("尚未识别为支持的交易通知。请核对标题和原文；不会猜测金额或自动保存。") }
                if busy { ProgressView() }
                if !status.isEmpty { Text(status).font(.footnote) }
            }
        }.navigationTitle("补录银行 / TNG 通知")
            .onChange(of: photo) { _, item in
                guard let item else { return }; busy = true
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw LedgerError.invalid("无法读取图片。") }
                        let text = try await Task.detached(priority: .userInitiated) { () throws -> String in
                            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US", "zh-Hans"]
                            try VNImageRequestHandler(data: data, options: [:]).perform([request])
                            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                        }.value
                        bodyText = text; status = "识别完成。请把标题填在上方，并移除时间栏等无关文字后核对预览。"
                    } catch { status = error.localizedDescription }
                }
            }
            .confirmationDialog("按预览补录这笔通知？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认保存") {
                    do {
                        var result = ""
                        try LocalStore.shared.change { result = try $0.receiveTNG(body: bodyText, title: title, date: received, eventID: nil) }
                        model.reload(postRecurring: false); model.showSaved(message: result); status = result
                        bodyText = ""; title = ""
                    } catch { status = error.localizedDescription }
                }
            } message: { Text("使用现有查重规则；无法确定的转账用途不会自动归为消费。") }
    }
}

struct BackupReminderView: View {
    @AppStorage("lastExportBackup") private var exported = 0.0
    @AppStorage("lastCloudBackup") private var uploaded = 0.0
    var body: some View {
        if Date().timeIntervalSince1970 - max(exported, uploaded) > 7 * 86400 {
            NavigationLink { SettingsView(guideDestination: "backup") } label: {
                BackupHealthView().frame(maxWidth: .infinity, alignment: .leading).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
        }
    }
}
