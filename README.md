# 月记 YueJi

**版本 / Version：1.52.4 · Build 76**  
iPhone 个人记账 App，以 MYR 为主要统计币种，支持中文、English 和 Bahasa Melayu。

## 中文

现有功能：
- **日常记账**：新增、编辑、删除及撤销删除；分类、备注、标签、搜索与筛选，一笔消费可拆分多个分类。
- **自动记账**：通过快捷指令传入 Apple Pay、银行及 TNG 交易资料；明确付款自动入账，疑似重复与不明确交易待确认，并提供结果通知。
- **分类与交易确认**：商户分类规则与记忆；确认消费、收入、转账、充值及退款，关联原消费或配对通知。
- **朋友分账**：记录份额、还款及退款；支持收据扫描与商品分摊、行程油费分摊。
- **预算与储蓄**：月度及分类统计、预算提醒、储蓄目标和存取记录；支持设备端 AI 辅助整理目标草稿（需兼容设备）。
- **固定消费与外币**：定期项目、到期补记、待记预览，以及汇率换算。
- **备份与体验**：JSON 备份恢复、CSV 导出、深浅色外观、动画、提示音及提醒设置。

本版补齐英文／马来文页面与提示，非中文界面的来源名称显示为 **Bank / TNG**。

自动记账需要先配置快捷指令并传入交易资料；App 不会直接读取银行账户或钱包历史。未知通知格式仍可能需要手动确认。

**构建安装：** 将本目录全部内容（含 `.github`）放到仓库根目录，运行 GitHub Actions 的 **Build YueJi iPhone App**，下载 IPA 后使用 AltStore 安装。详细步骤见 [安装与 Apple Pay 设置](Windows安装与ApplePay设置.md)。

## English

Current features:
- **Everyday records:** add, edit, delete and undo deletion; categories, notes, tags, search, filters and multiple categories per expense.
- **Automatic recording:** accept Apple Pay, bank and TNG details through Shortcuts. Record clear payments, review uncertain transactions or possible duplicates, and receive result notifications.
- **Categories and review:** merchant rules and category memory; confirm expenses, income, transfers, top-ups and refunds, with links to original expenses or paired notices.
- **Shared expenses:** track each friend's share, repayments and refunds; scan receipts, split individual items and share trip fuel costs.
- **Budgets and savings:** monthly and category summaries, budget alerts, savings goals and deposits/withdrawals; optional on-device AI goal drafts on compatible devices.
- **Recurring and foreign-currency expenses:** scheduled entries, overdue posting, upcoming previews and exchange-rate conversion.
- **Backup and appearance:** JSON backup/restore, CSV export, light/dark appearance, animations, sounds and reminders.

This release fills missing English/Malay labels and messages and displays **Bank / TNG** in non-Chinese interfaces.

Automatic recording requires configured Shortcuts that pass transaction details to YueJi. The app does not directly read bank accounts or Wallet history. Unfamiliar notification formats may still need manual review.

**Build and install:** copy this folder's contents, including `.github`, to the repository root. Run **Build YueJi iPhone App** in GitHub Actions, download the IPA and install it with AltStore. See the [installation guide (Chinese)](Windows安装与ApplePay设置.md).
