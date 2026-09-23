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
    static var parameterSummary: some ParameterSummary {
        Summary("记录 \(\.$merchant) 的 \(\.$amount) \(\.$currency) 支出") {
            \.$transactionDate
            \.$transactionID
        }
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let added = try LocalStore.shared.change {
            try $0.addPayment(amount: amount, merchant: merchant, currency: currency, date: transactionDate, eventID: transactionID)
        }
        if added { return .result(dialog: "已保存到月记。") }
        return .result(dialog: "这笔付款已记录，没有重复入账。")
    }
}
struct YueJiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordApplePayIntent(), phrases: ["用\(.applicationName)记录付款", "Record a payment in \(.applicationName)"], shortTitle: "记录 Apple Pay", systemImageName: "creditcard.fill")
    }
}
