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
// Keep persisted source keys unchanged; translate only their display labels.
func sourceLabel(_ key: String) -> String {
    switch key {
    case "手动": return tr("手动", "Manual", "Manual")
    case "固定消费", "Recurring": return tr("固定消费", "Recurring", "Berulang")
    case "账单补录": return tr("账单补录", "Bill entry", "Rekod bil")
    case "银行 / TNG", "银行/TNG": return tr("银行 / TNG", "Bank / TNG", "Bank / TNG")
    default: return key
    }
}
func dateLabel(_ date: Date, time: Bool = false) -> String {
    // Foundation reuses the formatter behind a value-based FormatStyle.
    date.formatted(Date.FormatStyle(date: .abbreviated, time: time ? .shortened : .omitted)
        .locale(Locale(identifier: AppLanguage.localeID)))
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
    guard let pair = values[key] else { return localizedAppText(key) }; return tr(key, pair.0, pair.1)
}

// Exact app-owned messages only: never translate merchant names or original bank text.
// Legacy saved Chinese status messages are resolved in the current app language.
func localizedAppText(_ text: String) -> String {
    guard AppLanguage.code != "zh" else { return text }
    let values: [String: (String, String)] = [
        "已关联退款": ("Refund linked", "Bayaran balik dipautkan"),
        "账户转账 / 充值 · 不计收支": ("Account transfer / top-up · excluded", "Pindahan akaun / tambah nilai · dikecualikan"),
        "已合并重复通知": ("Duplicate notices merged", "Notifikasi pendua digabungkan"),
        "交易备注": ("Transaction note", "Nota transaksi"),
        "例如：午餐、替朋友付款、转入自己的账户": ("E.g. lunch, paying for a friend, transfer to your own account", "Cth. makan tengah hari, bayaran untuk rakan, pindahan ke akaun sendiri"),
        "保存备注": ("Save note", "Simpan nota"),
        "备注已保存": ("Note saved", "Nota disimpan"),
        "付款、转账、收款及已排除记录均可备注；保存备注不会改变消费统计。": ("Add notes to payments, transfers, receipts and excluded records. Notes do not change spending totals.", "Tambah nota pada bayaran, pindahan, penerimaan dan rekod dikecualikan. Nota tidak mengubah jumlah belanja."),
        "无法保存备注": ("Unable to save note", "Tidak dapat menyimpan nota"),
        "AI 建议（请核对）：": ("AI suggestion (please review): ", "Cadangan AI (sila semak): "),
        "AI 分析中…": ("AI is analysing…", "AI sedang menganalisis…"),
        "AI 辅助判断": ("Review with AI", "Semak dengan AI"),
        "重新识别通知": ("Recognise notification again", "Kenal pasti notifikasi semula"),
        "当前仍未识别，请核对原文后手动确认。": ("Still unrecognised. Review the original text and confirm manually.", "Masih tidak dikenal pasti. Semak teks asal dan sahkan secara manual."),
        "此交易已处理，请核对已有记录。原待确认通知已保留。": ("This transaction was already processed. Check existing records. The original notice is kept for review.", "Transaksi telah diproses. Semak rekod sedia ada. Notifikasi asal dikekalkan untuk semakan."),
        "确认用途 / 收入 / 充值 / 退款": ("Confirm purpose / income / top-up / refund", "Sahkan tujuan / pendapatan / tambah nilai / bayaran balik"),
        "以后此商户使用这个分类": ("Use this category for this merchant in future", "Gunakan kategori ini untuk peniaga ini pada masa depan"),
        "重新计入消费": ("Include in spending again", "Masukkan semula dalam belanja"),
        "排除期间不计入消费。重新打开后，请核对金额与分类，再点「计入消费」。不会自动新增或重复记账。": ("Excluded records do not count as spending. Reopen, check the amount and category, then tap Include in spending. Reopening does not create a new entry.", "Rekod dikecualikan tidak dikira sebagai belanja. Buka semula, semak amaun dan kategori, kemudian tekan Masukkan dalam belanja. Membuka semula tidak mencipta rekod baharu."),
        "撤销排除 · 重新确认": ("Undo exclusion · review again", "Batalkan pengecualian · semak semula"),
        "接入你的银行": ("Connect your bank", "Sambungkan bank anda"),
        "在快捷指令的通知触发器里点 App 旁的 ＋，加入你使用的银行或 TNG。银行名称不限；能否触发取决于系统是否收到并传入通知。": ("In the Shortcuts notification trigger, tap + next to App and add your bank or TNG. Any bank name is accepted; triggering depends on the system receiving and forwarding the notification.", "Dalam pencetus notifikasi Pintasan, tekan + di sebelah App dan tambah bank anda atau TNG. Sebarang nama bank diterima; pencetus bergantung pada sistem menerima dan menghantar notifikasi."),
        "动作选择「记录银行与 TNG 通知」，正文连接 Body，标题连接 Title，时间连接 Date（若有）。不要填写固定交易编号。": ("Choose Record bank and TNG notification. Connect the body to Body, title to Title and time to Date if available. Do not use a fixed transaction ID.", "Pilih Rekod notifikasi bank dan TNG. Sambungkan teks kepada Body, tajuk kepada Title dan masa kepada Date jika ada. Jangan gunakan ID transaksi tetap."),
        "可将来源 App 名称传给同名字段。每家银行单独设置时也可填写银行名称；多家共用时不要固定成同一家银行。留空时月记尝试从原文辨认。": ("Pass the source app name into its field. For a separate automation per bank, you can enter its name. Do not fix one bank name for a shared automation. If blank, YueJi tries to identify it from the text.", "Hantar nama app sumber ke medan tersebut. Untuk automasi berasingan bagi setiap bank, anda boleh isi nama bank. Jangan tetapkan satu nama bank untuk automasi bersama. Jika kosong, YueJi cuba mengenal pasti daripada teks."),
        "收到通知后": ("When a notification arrives", "Apabila notifikasi diterima"),
        "明确的马币付款：自动记账与分类": ("Clear MYR payments: record and categorise automatically", "Bayaran MYR yang jelas: rekod dan kategorikan secara automatik"),
        "收款、转账：先确认用途": ("Receipts and transfers: confirm the purpose first", "Penerimaan dan pindahan: sahkan tujuan dahulu"),
        "退款、返现、外币或信息不完整：待确认": ("Refunds, cashback, foreign currency or incomplete details: review needed", "Bayaran balik, pulangan tunai, mata wang asing atau butiran tidak lengkap: perlu semakan"),
        "广告、验证码、失败通知：忽略": ("Ads, verification codes and failed transactions: ignored", "Iklan, kod pengesahan dan transaksi gagal: diabaikan"),
        "支持通用中、英、马来文交易规则，保留已适配银行的专属格式。尚未用全部银行的真实通知验证，银行改版或陌生格式可能需要确认；不会读取历史流水。": ("Supports general Chinese, English and Malay transaction patterns and recognised bank-specific formats. Real notifications from every bank have not been verified; changed or unfamiliar formats may need review. Account history is not read.", "Menyokong corak transaksi umum bahasa Cina, Inggeris dan Melayu serta format bank yang dikenal pasti. Notifikasi sebenar semua bank belum disahkan; format baharu mungkin perlu semakan. Sejarah akaun tidak dibaca."),
        "银行通知设置": ("Bank notification setup", "Persediaan notifikasi bank"),
        "账户转账 / 充值 / 退款关联": ("Link account transfer / top-up / refund", "Pautkan pindahan akaun / tambah nilai / bayaran balik"),
        "已确认关联": ("Confirmed link", "Pautan disahkan"),
        "查看关联消费": ("View linked expense", "Lihat belanja dipautkan"),
        "关联记录已删除或清理。": ("The linked record has been deleted or cleared.", "Rekod dipautkan telah dipadam atau dikosongkan."),
        "撤销关联并重新确认": ("Remove link and review again", "Batalkan pautan dan semak semula"),
        "撤销关联？关联退款会一并撤销；充值配对会重新待确认。": ("Remove this link? Linked refunds will be undone and paired top-ups will need review again.", "Batalkan pautan ini? Bayaran balik dipautkan akan dibatalkan dan pasangan tambah nilai perlu disemak semula."),
        "确认撤销": ("Confirm undo", "Sahkan pembatalan"),
        "确认用途": ("Confirm purpose", "Sahkan tujuan"),
        "这是什么交易？": ("What is this transaction?", "Apakah transaksi ini?"),
        "请选择用途": ("Select a purpose", "Pilih tujuan"),
        "消费支出": ("Expense", "Perbelanjaan"),
        "收入": ("Income", "Pendapatan"),
        "自己的账户转账 / 充值": ("Own-account transfer / top-up", "Pindahan akaun sendiri / tambah nilai"),
        "退款到账": ("Refund received", "Bayaran balik diterima"),
        "同一笔交易，不重复入账": ("Same transaction, do not record again", "Transaksi sama, jangan rekod semula"),
        "忽略": ("Ignore", "Abaikan"),
        "商户 / 对方 / 用途": ("Merchant / recipient / purpose", "Peniaga / pihak lain / tujuan"),
        "交易日期": ("Transaction date", "Tarikh transaksi"),
        "分类": ("Category", "Kategori"),
        "已核对，这是另一笔真实交易": ("Checked: this is a separate real transaction", "Disemak: ini transaksi sebenar yang berasingan"),
        "选择原消费": ("Choose original expense", "Pilih belanja asal"),
        "选择已有账目": ("Choose existing entry", "Pilih rekod sedia ada"),
        "关联账目": ("Linked entry", "Rekod dipautkan"),
        "请选择": ("Please select", "Sila pilih"),
        "金额相同不代表同一笔，请核对商户和日期。退款会减少原消费，不作为收入。": ("Matching amounts do not prove a duplicate. Check the merchant and date. Refunds reduce the original expense and are not income.", "Amaun sama tidak semestinya pendua. Semak peniaga dan tarikh. Bayaran balik mengurangkan belanja asal dan bukan pendapatan."),
        "配对另一侧通知（可选）": ("Pair the other notification (optional)", "Padankan notifikasi sebelah lagi (pilihan)"),
        "转入 / 转出通知": ("Incoming / outgoing notice", "Notifikasi masuk / keluar"),
        "没有另一侧通知": ("No matching notification", "Tiada notifikasi pasangan"),
        "确认后，两侧通知均不计入消费或收入。": ("Once confirmed, neither notification counts as spending or income.", "Selepas disahkan, kedua-dua notifikasi tidak dikira sebagai belanja atau pendapatan."),
        "确认处理": ("Confirm transaction", "Sahkan transaksi"),
        "通知已删除或清理。": ("The notification has been deleted or cleared.", "Notifikasi telah dipadam atau dikosongkan."),
        "确认通知": ("Review notification", "Semak notifikasi"),
        "确认按所选用途处理？": ("Process with the selected purpose?", "Proses mengikut tujuan yang dipilih?"),
        "确认": ("Confirm", "Sahkan"),
        "无法处理": ("Unable to process", "Tidak dapat diproses"),
        "一笔消费，多种用途": ("One expense, multiple categories", "Satu belanja, pelbagai kategori"),
        "拆分这笔消费的分类": ("Split this expense into categories", "Pecahkan belanja ini mengikut kategori"),
        "增加分类": ("Add category", "Tambah kategori"),
        "分类合计 / 付款总额": ("Category total / payment total", "Jumlah kategori / jumlah bayaran"),
        "至少两类，MYR 合计须等于付款总额。个人净消费按分类比例统计。": ("Use at least two categories. The MYR sum must equal the payment total. Personal net spending is allocated proportionally.", "Gunakan sekurang-kurangnya dua kategori. Jumlah MYR mesti sama dengan jumlah bayaran. Belanja bersih peribadi diagihkan mengikut nisbah."),
        "分类与备注": ("Categories and notes", "Kategori dan nota"),
        "以上为付款总額分配；个人净消费按比例统计。": ("The amounts allocate the total payment; personal net spending is calculated proportionally.", "Amaun di atas mengagihkan jumlah bayaran; belanja bersih peribadi dikira mengikut nisbah."),
        "待处理": ("Needs attention", "Perlu tindakan"),
        "在新增或编辑账目里填写标签，可跨餐饮、交通等分类汇总同一个项目。": ("Add tags when creating or editing entries to group a project across categories such as food and transport.", "Tambah tag ketika mencipta atau mengedit rekod untuk mengumpulkan projek merentas kategori seperti makanan dan pengangkutan."),
        "还没有标签。": ("No tags yet.", "Belum ada tag."),
        "标签与项目": ("Tags and projects", "Tag dan projek"),
        "全部月份": ("All months", "Semua bulan"),
        "实际付款总额": ("Total paid", "Jumlah dibayar"),
        "我的净消费": ("My net spending", "Belanja bersih saya"),
        "同一账目可有多个标签，各标签合计不能再相加作为总消费。": ("An entry can have several tags. Do not add tag totals together as total spending.", "Satu rekod boleh mempunyai beberapa tag. Jangan jumlahkan jumlah setiap tag sebagai jumlah belanja."),
        "这笔记录已删除或清理。": ("This record has been deleted or cleared.", "Rekod ini telah dipadam atau dikosongkan."),
        "完成": ("Done", "Selesai"),
        "月记 YueJi": ("YueJi", "YueJi"),
        "月记": ("YueJi", "YueJi"),
        "自动记账输入无效或过长，请检查快捷指令。": ("Automatic recording input is invalid or too long. Check Shortcuts.", "Input rekod automatik tidak sah atau terlalu panjang. Semak Pintasan."),
        "月记 · 恢复检查完成": ("YueJi · Recovery check complete", "YueJi · Semakan pemulihan selesai"),
        "此前已处理这次调用，没有重复入账。请查看账本或待确认记录。": ("This request was already processed. No duplicate was added. Check the ledger or pending records.", "Permintaan ini telah diproses. Tiada pendua ditambah. Semak lejar atau rekod untuk semakan."),
        "月记 · 交易处理结果": ("YueJi · Transaction result", "YueJi · Hasil transaksi"),
        "月记 · 已自动记账": ("YueJi · Automatically recorded", "YueJi · Direkod secara automatik"),
        "Apple Pay 缺少金额，请检查快捷指令。": ("Apple Pay amount is missing. Check Shortcuts.", "Amaun Apple Pay tiada. Semak Pintasan."),
        "这笔付款已记录，没有重复入账。": ("This payment is already recorded. No duplicate was added.", "Bayaran ini telah direkod. Tiada pendua ditambah."),
        "疑似重复，已保留待确认，尚未再次计入消费。": ("Possible duplicate kept for review; not added to spending again.", "Kemungkinan pendua disimpan untuk semakan; tidak ditambah semula pada belanja."),
        "月记 · 未重复记账": ("YueJi · Duplicate skipped", "YueJi · Pendua dilangkau"),
        "月记 · Apple Pay 待确认": ("YueJi · Apple Pay needs review", "YueJi · Apple Pay perlu semakan"),
        "月记 · Apple Pay 需要处理": ("YueJi · Apple Pay needs attention", "YueJi · Apple Pay perlu tindakan"),
        "月记 · 银行 / TNG 需要处理": ("YueJi · Bank / TNG needs attention", "YueJi · Bank / TNG perlu tindakan"),
        "待重试交易已满，请先在自动记账状态页处理。此输入尚未暂存。": ("The retry queue is full. Review automatic recording status first. This input has not been saved.", "Barisan cuba semula penuh. Semak status rekod automatik dahulu. Input ini belum disimpan."),
        "自动记账输入过长。": ("Automatic recording input is too long.", "Input rekod automatik terlalu panjang."),
        "待重试文件异常，请保留文件并检查。": ("The retry file is invalid. Keep the file for inspection.", "Fail cuba semula tidak sah. Simpan fail untuk diperiksa."),
        "待重试文件标识不一致。": ("Retry file identifiers do not match.", "Pengenal fail cuba semula tidak sepadan."),
        "输入未能暂存，尚未自动入账：": ("Input could not be saved; not recorded: ", "Input tidak dapat disimpan; belum direkod: "),
        "交易输入已暂存，等待重试，尚未确认入账：": ("Transaction input saved for retry; recording not confirmed: ", "Input transaksi disimpan untuk cuba semula; rekod belum disahkan: "),
        "无法读取待重试交易：": ("Unable to read transactions awaiting retry: ", "Tidak dapat membaca transaksi untuk cuba semula: "),
        "此设备的 Apple Intelligence 模型不可用，请按原文确认。": ("Apple Intelligence is unavailable on this device. Review the original text.", "Apple Intelligence tidak tersedia pada peranti ini. Semak teks asal."),
        "AI 暂时无法分析，请核对原文；通知仍保留待确认。": ("AI analysis is temporarily unavailable. Review the original text; the notification is kept for review.", "Analisis AI tidak tersedia buat sementara. Semak teks asal; notifikasi dikekalkan untuk semakan."),
        "此系统不支持本机 AI，请核对原文；通知仍保留待确认。": ("On-device AI is unsupported on this system. Review the original text; the notification is kept for review.", "AI pada peranti tidak disokong oleh sistem ini. Semak teks asal; notifikasi dikekalkan untuk semakan."),
        "自动记账结果通知开关已关闭。": ("Automatic recording notifications are turned off.", "Notifikasi hasil rekod automatik dimatikan."),
        "系统通知未获允许，请在 iPhone 设置 → 通知 → 月记开启。": ("Notifications are not allowed. Enable them in iPhone Settings → Notifications → YueJi.", "Notifikasi tidak dibenarkan. Aktifkan dalam Tetapan iPhone → Notifikasi → YueJi."),
        "已交给 iOS（临时授权，可能静默送达）；请开启横幅与声音。": ("Sent to iOS with provisional permission; delivery may be silent. Enable banners and sounds.", "Dihantar ke iOS dengan kebenaran sementara; mungkin dihantar tanpa bunyi. Aktifkan sepanduk dan bunyi."),
        "已交给 iOS；实际横幅、声音和锁屏显示受系统通知设置及专注模式控制。": ("Sent to iOS. Banners, sounds and lock-screen display depend on notification and Focus settings.", "Dihantar ke iOS. Sepanduk, bunyi dan paparan skrin kunci bergantung pada tetapan notifikasi dan Fokus."),
        "系统通知提交失败：": ("Unable to submit notification: ", "Tidak dapat menghantar notifikasi: "),
        "交易描述过长。": ("Transaction description is too long.", "Penerangan transaksi terlalu panjang."),
        "交易标识过长。": ("Transaction ID is too long.", "ID transaksi terlalu panjang."),
        "通知记录已达上限。": ("The notification limit has been reached.", "Had notifikasi telah dicapai."),
        "与已有账目的金额、商户和时间相近，请核对是否同一笔。": ("The amount, merchant and time are close to an existing entry. Check whether this is the same transaction.", "Amaun, peniaga dan masa hampir sama dengan rekod sedia ada. Semak sama ada ini transaksi yang sama."),
        "通知来源名称无效。": ("Invalid notification source name.", "Nama sumber notifikasi tidak sah."),
        "此交易编号的通知已保留，未重复添加。": ("A notice with this transaction ID is already kept. No duplicate was added.", "Notifikasi dengan ID transaksi ini telah disimpan. Tiada pendua ditambah."),
        "交易日期无效。": ("Invalid transaction date.", "Tarikh transaksi tidak sah."),
        "相同未识别通知已保留，未重复添加。": ("The same unrecognised notification is already kept. No duplicate was added.", "Notifikasi tidak dikenal pasti yang sama telah disimpan. Tiada pendua ditambah."),
        "交易通知已保留待确认，未计入消费。": ("Transaction notification kept for review; excluded from spending.", "Notifikasi transaksi disimpan untuk semakan; tidak dikira sebagai belanja."),
        "请先撤销已有退款或转账关联。": ("Undo the existing refund or transfer link first.", "Batalkan pautan bayaran balik atau pindahan sedia ada dahulu."),
        "通知已改变；有关联的记录请先撤销关联。": ("The notification has changed. Remove existing links first.", "Notifikasi telah berubah. Batalkan pautan sedia ada dahulu."),
        "关联消费仍存在，请先核对，避免重复入账。": ("The linked expense still exists. Check it first to avoid a duplicate.", "Belanja dipautkan masih wujud. Semak dahulu untuk mengelakkan pendua."),
        "备注最多 2000 字，或通知已删除。": ("Notes are limited to 2,000 characters, or the notification has been deleted.", "Nota dihadkan kepada 2,000 aksara, atau notifikasi telah dipadam."),
        "请先在通知详情撤销关联，再删除通知。": ("Remove the link in notification details before deleting the notification.", "Batalkan pautan dalam butiran notifikasi sebelum memadam notifikasi."),
        "通知已处理，或金额、名称、日期无效。": ("The notification was processed, or the amount, name or date is invalid.", "Notifikasi telah diproses, atau amaun, nama atau tarikh tidak sah."),
        "收款不能记为支出。": ("Money received cannot be recorded as an expense.", "Wang diterima tidak boleh direkod sebagai belanja."),
        "关联通知已变化或金额不同，请重新选择。": ("The linked notification has changed or the amounts differ. Select again.", "Notifikasi dipautkan telah berubah atau amaun berbeza. Pilih semula."),
        "请选择原消费。": ("Select the original expense.", "Pilih belanja asal."),
        "退款保存失败。": ("Unable to save refund.", "Tidak dapat menyimpan bayaran balik."),
        "请选择有效用途。": ("Select a valid purpose.", "Pilih tujuan yang sah."),
        "通知或账目已改变。": ("The notification or entry has changed.", "Notifikasi atau rekod telah berubah."),
        "通知已改变。": ("The notification has changed.", "Notifikasi telah berubah."),
        "备注或标签无效。": ("Invalid notes or tags.", "Nota atau tag tidak sah."),
        "分类金额合计必须等于付款 MYR 总额，分类不能重复。": ("Category amounts must equal the MYR payment total. Categories cannot repeat.", "Jumlah amaun kategori mesti sama dengan jumlah bayaran MYR. Kategori tidak boleh berulang."),
        "可能是退款、返现或充值，请确认用途；未计入消费。": ("This may be a refund, cashback or top-up. Confirm the purpose; excluded from spending.", "Ini mungkin bayaran balik, pulangan tunai atau tambah nilai. Sahkan tujuan; tidak dikira sebagai belanja."),
        "金额缺失、含多个金额或不是单一马币金额，请核对原文与币种；未计入消费。": ("The amount is missing, there are multiple amounts, or it is not a single MYR amount. Check the original text and currency; excluded from spending.", "Amaun tiada, terdapat beberapa amaun, atau bukan satu amaun MYR. Semak teks asal dan mata wang; tidak dikira sebagai belanja."),
        "已收到交易通知，但成功状态、交易类型或商户尚未完全确认；请核对原文，未计入消费。": ("Notification received, but success, transaction type or merchant is not confirmed. Review the original text; excluded from spending.", "Notifikasi diterima, tetapi kejayaan, jenis transaksi atau peniaga belum disahkan. Semak teks asal; tidak dikira sebagai belanja."),
        "储蓄目标无效 / Invalid savings goals": ("Invalid savings goals.", "Matlamat simpanan tidak sah."),
        "储蓄目标无效 / Invalid savings goal": ("Invalid savings goal.", "Matlamat simpanan tidak sah."),
        "目标日期无效 / Invalid deadline": ("Invalid goal date.", "Tarikh matlamat tidak sah."),
        "每月金额无效 / Invalid monthly amount": ("Invalid monthly amount.", "Amaun bulanan tidak sah."),
        "储蓄记录无效 / Invalid savings entry": ("Invalid savings entry.", "Rekod simpanan tidak sah."),
        "取出金额不能超过已存金额 / Withdrawal exceeds savings": ("Withdrawal cannot exceed savings.", "Pengeluaran tidak boleh melebihi simpanan."),
        "请简化目标描述 / Please simplify your goal": ("Please simplify your goal description.", "Sila ringkaskan penerangan matlamat."),
        "请手动核对金额 / Check amount manually": ("Check the amount manually.", "Semak amaun secara manual."),
        "请选择未来日期 / Choose a future date": ("Choose a future date.", "Pilih tarikh pada masa depan."),
        "目标已改变，请重新打开 / Goal changed; reopen it": ("The goal has changed. Reopen it.", "Matlamat telah berubah. Buka semula."),
        "金额必须大于零 / Enter an amount above zero": ("Enter an amount above zero.", "Masukkan amaun melebihi sifar."),
        "目标已不存在 / Goal no longer exists": ("This goal no longer exists.", "Matlamat ini tidak lagi wujud.")
    ]
    if let pair = values[text] { return tr(text, pair.0, pair.1) }
    // These app-generated prefixes may be followed by an underlying system error.
    for prefix in values.keys.filter({ $0.hasSuffix("：") }).sorted(by: { $0.count > $1.count }) {
        if text.hasPrefix(prefix), let pair = values[prefix] {
            return tr(prefix, pair.0, pair.1) + localizedError(String(text.dropFirst(prefix.count)))
        }
    }
    return text
}
