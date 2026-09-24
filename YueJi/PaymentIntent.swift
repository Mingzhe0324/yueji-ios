import AppIntents
import Foundation

struct RecordApplePayIntent: AppIntent {
    static var title: LocalizedStringResource = "记录 Apple Pay 支出"
    static var description = IntentDescription("将快捷指令提供的成功付款写入月记本地账本。不会读取银行或钱包历史记录。")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "金额") var amount: Double
    @Parameter(title: "商户") var merchant: String
    @Parameter(title: "币种", default: "MYR") var currency: String
    @Parameter(title: "交易时间") var transactionDate: Date
    @Parameter(title: "交易标识（可选）") var transactionID: String?
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let result = try LocalStore.shared.change { ledger -> (Bool, String) in
                let saved = try ledger.addPayment(amount: amount, merchant: merchant, currency: currency, date: transactionDate, eventID: transactionID)
                ledger.logAutomation(source: "Apple Pay", outcome: saved ? "saved" : "duplicate")
                let entry = saved ? ledger.expenses.last : nil
                let detail = entry.map { money($0.cents) + " · " + $0.merchant + " · " + categoryLabel($0.category) } ?? ""
                return (saved, detail)
            }
            await BudgetAlertService.shared.check()
            if result.0 {
                await LedgerNotifications.result(title: tr("已记账", "Recorded", "Direkod"), body: result.1)
                return .result(dialog: "已保存到月记。")
            }
            await LedgerNotifications.result(title: tr("未重复记账", "Duplicate skipped", "Pendua dilangkau"), body: tr("这笔付款已存在。", "This payment is already recorded.", "Bayaran ini sudah direkod."))
            return .result(dialog: "这笔付款已记录，没有重复入账。")
        } catch {
            let failure = error
            try? LocalStore.shared.change { $0.logAutomation(source: "Apple Pay", outcome: "failed", detail: failure.localizedDescription) }
            await LedgerNotifications.result(title: tr("自动记账失败", "Recording failed", "Rekod gagal"), body: failure.localizedDescription)
            throw failure
        }
    }
}
struct PostRecurringIntent: AppIntent {
    static var title: LocalizedStringResource = "补记固定消费"
    static var description = IntentDescription("补记已到期且开启自动入账的固定消费，不会执行付款。")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try LocalStore.shared.change { ledger in try ledger.postDue(); ledger.logAutomation(source: "Recurring", outcome: "checked") }
        } catch {
            let failure = error
            try? LocalStore.shared.change { $0.logAutomation(source: "Recurring", outcome: "failed", detail: failure.localizedDescription) }
            throw failure
        }
        await BudgetAlertService.shared.check()
        return .result(dialog: "已检查到期项目。缺少汇率的项目仍保留待记。")
    }
}
struct YueJiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordTNGIntent(), phrases: ["Record a TNG notification in \(.applicationName)"], shortTitle: "记录 TNG", systemImageName: "bell.badge")
        AppShortcut(intent: PostRecurringIntent(), phrases: ["Post recurring expenses in \(.applicationName)"], shortTitle: "补记固定消费", systemImageName: "repeat")
        AppShortcut(intent: RecordApplePayIntent(), phrases: ["用\(.applicationName)记录付款", "Record a payment in \(.applicationName)"], shortTitle: "记录 Apple Pay", systemImageName: "creditcard.fill")
    }
}

struct RecordTNGIntent: AppIntent {
    static var title: LocalizedStringResource = "记录 TNG 通知"
    static var description = IntentDescription("解析 TNG 通知正文。已识别付款记为消费，转账和未知通知单独保存。")
    static var openAppWhenRun = false
    @Parameter(title: "通知正文") var body: String
    @Parameter(title: "通知标题（可选）") var notificationTitle: String?
    @Parameter(title: "通知时间（可选）") var notificationDate: Date?
    @Parameter(title: "交易标识（可选）") var transactionID: String?
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let message = try LocalStore.shared.change { ledger in
                let result = try ledger.receiveTNG(body: body, title: notificationTitle ?? "", date: notificationDate, eventID: transactionID)
                ledger.logAutomation(source: "TNG", outcome: "checked", detail: result)
                return result
            }
            await BudgetAlertService.shared.check()
            await LedgerNotifications.result(title: "TNG", body: message)
            return .result(dialog: "TNG 通知已处理，请在月记查看结果。")
        } catch {
            try? LocalStore.shared.change { $0.logAutomation(source: "TNG", outcome: "failed", detail: error.localizedDescription) }
            await LedgerNotifications.result(title: tr("TNG 记录失败", "TNG recording failed", "Rekod TNG gagal"), body: error.localizedDescription)
            throw error
        }
    }
}
