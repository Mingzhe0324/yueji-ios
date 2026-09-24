import Foundation

enum AppLanguage {
    static var code: String {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if saved != "system" { return saved }
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("zh") ? "zh" : first.hasPrefix("ms") ? "ms" : "en"
    }
    static var localeID: String { code == "zh" ? "zh_Hans_MY" : code == "ms" ? "ms_MY" : "en_MY" }
}
func tr(_ zh: String, _ en: String, _ ms: String) -> String { AppLanguage.code == "zh" ? zh : AppLanguage.code == "ms" ? ms : en }
func categoryLabel(_ key: String) -> String {
    switch key {
    case "餐饮": return tr("餐饮", "Food", "Makanan")
    case "交通": return tr("交通", "Transport", "Pengangkutan")
    case "购物": return tr("购物", "Shopping", "Beli-belah")
    case "账单": return tr("账单", "Bills", "Bil")
    case "娱乐": return tr("娱乐", "Entertainment", "Hiburan")
    case "其他": return tr("其他", "Other", "Lain-lain")
    default: return key
    }
}
func sourceLabel(_ key: String) -> String { key == "手动" ? tr("手动", "Manual", "Manual") : key == "固定消费" ? tr("固定消费", "Recurring", "Berulang") : key }
func dateLabel(_ date: Date, time: Bool = false) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: AppLanguage.localeID); f.dateStyle = .medium; f.timeStyle = time ? .short : .none; return f.string(from: date)
}
func localizedError(_ key: String) -> String {
    let values: [String: (String, String)] = [
        "请输入大于零、最多两位小数的金额。": ("Enter a positive amount with up to two decimal places.", "Masukkan amaun positif dengan maksimum dua tempat perpuluhan."),
        "账本格式或版本无效。": ("Invalid ledger format or version.", "Format atau versi lejar tidak sah."),
        "付款或分账数据无效。": ("Invalid payment or split details. Check names and amounts.", "Butiran bayaran atau pembahagian tidak sah. Semak nama dan amaun."),
        "还款不能超过朋友应付金额。": ("Repayment cannot exceed the friend's share.", "Bayaran balik tidak boleh melebihi bahagian rakan."),
        "还款超出朋友份额。": ("Repayment exceeds the friend's share.", "Bayaran balik melebihi bahagian rakan."),
        "朋友份额超过实际付款。": ("Friends' shares exceed the payment.", "Bahagian rakan melebihi bayaran."),
        "交易金额或日期无效。": ("Invalid transaction amount or date.", "Amaun atau tarikh transaksi tidak sah."),
        "未取得商户名称，请检查快捷指令的输入。": ("Merchant is missing. Check the Shortcut input.", "Nama peniaga tiada. Semak input Pintasan."),
        "找不到这笔分账，请重新打开。": ("Split not found. Reopen the record.", "Pembahagian tidak ditemui. Buka semula rekod."),
        "请检查还款金额和日期。": ("Check the repayment amount and date.", "Semak amaun dan tarikh bayaran balik."),
        "备份不能超过 20 MB。": ("Backup must not exceed 20 MB.", "Sandaran tidak boleh melebihi 20 MB."),
        "无法读取账本。": ("Unable to read the ledger.", "Tidak dapat membaca lejar."),
        "账本正忙，请重试。": ("Ledger is busy. Try again.", "Lejar sedang sibuk. Cuba lagi."),
        "币种无效。": ("Unsupported currency.", "Mata wang tidak disokong."),
        "此币种只接受整数金额。": ("This currency only accepts whole amounts.", "Mata wang ini hanya menerima amaun bulat."),
        "汇率必须大于零。": ("Enter a valid positive exchange rate.", "Masukkan kadar pertukaran positif yang sah."),
        "换算金额超出范围或不足一仙。": ("Converted amount is out of range or below one sen.", "Amaun ditukar di luar julat atau kurang daripada satu sen."),
        "外币金额与换算金额不符。": ("Foreign amount does not match the converted amount.", "Amaun asing tidak sepadan dengan amaun ditukar."),
        "固定消费资料无效。": ("Invalid recurring expense details.", "Butiran perbelanjaan berulang tidak sah."),
        "请先在汇率设置保存该币种的汇率。": ("Save this currency's rate in Exchange rates first.", "Simpan kadar mata wang ini dalam Kadar pertukaran dahulu."),
        "无法获取汇率，请手动填写或稍后重试。": ("Unable to fetch the rate. Enter it manually or retry later.", "Tidak dapat mengambil kadar. Masukkan secara manual atau cuba lagi."),
        "汇率服务返回的数据无效。": ("The exchange-rate service returned invalid data.", "Perkhidmatan kadar pertukaran memberikan data tidak sah.")
    ]
    guard let pair = values[key] else { return key }; return tr(key, pair.0, pair.1)
}
