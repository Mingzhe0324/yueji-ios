# 月记 YueJi

**版本 / Version：1.55.0 · Build 83**

Build 83 adds expandable **Items** to manual and automatically recorded purchases. Add, edit or remove up to 100 named MYR items, each with its own category; completed item amounts must equal the transaction total. Automatic purchases stay saved without items, and cancelled or invalid edits retain the original transaction. Reports allocate personal spending to item categories without counting the parent again; shares and refunds use the existing proportional allocation with exact sen totals. Incoming account movements show **+ / green** and expenses **− / red**. Friend-paid purchases show your net share in red with a minus sign and a payer label, while account payments remain zero and the remaining debt is shown separately. Repayments and offsets never add spending. Item breakdowns remain in settlement audit snapshots; undo active settlements before changing items. Chinese, English and Malay labels are included. Nine new focused XCTest cases cover items, refunds, automatic recording and failed edits, partial/full repayment, exact offsets/undo, category changes, CSV/backup migration and protection against converting itemized purchases into settlement payments. Windows structural and syntax checks are available; native compilation, XCTest and device review require Codemagic/Xcode.

iPhone 个人记账 App，以 MYR 为主要统计币种，支持中文、English 和 Bahasa Melayu。

## 中文

现有功能：
- **日常记账**：新增、编辑、删除及撤销删除；分类、备注、标签、搜索与筛选，一笔消费可拆分多个分类。
- **自动记账**：通过快捷指令传入 Apple Pay、银行及 TNG 交易资料；明确付款自动入账，疑似重复与不明确交易待确认，并提供结果通知。
- **分类与交易确认**：商户分类规则与记忆；确认消费、收入、转账、充值及退款，关联原消费或配对通知。
- **朋友分账与净额结算**：记录我付款或朋友付款，平均、自定、全是我的或全是朋友的份额；分别显示双方欠款。选择账目、预览抵扣与部分转账、确认结算，再手动关联银行 / TNG 付款。
- **预算与储蓄**：月度及分类统计、预算提醒、储蓄目标和存取记录；支持设备端 AI 辅助整理目标草稿（需兼容设备）。
- **固定消费与外币**：定期项目、到期补记、待记预览，以及汇率换算。
- **备份与体验**：JSON 备份恢复、CSV 导出、深浅色外观、动画、提示音及提醒设置。

已补齐英文／马来文页面与提示，非中文界面的来源名称显示为 **Bank / TNG**。本版修复开场 Logo 资源，先显示短暂弹簧动画再载入主界面；账本启动读取移至后台，复用月份统计并减少重复刷新。保留系统列表、大标题、玻璃控件、付款缩放过渡、预算阶段和分类颜色。

自动记账需要先配置快捷指令并传入交易资料；App 不会直接读取银行账户或钱包历史。未知通知格式仍可能需要手动确认。

**构建安装：** 将本目录全部内容（含 `.github`）放到仓库根目录，运行 GitHub Actions 的 **Build YueJi iPhone App**，下载 IPA 后使用 AltStore 安装。详细步骤见 [安装与 Apple Pay 设置](Windows安装与ApplePay设置.md)。

## English

Current features:
- **Everyday records:** add, edit, delete and undo deletion; named items with individual categories, notes, tags, search, filters and multiple categories per expense.
- **Automatic recording:** accept Apple Pay, bank and TNG details through Shortcuts. Record clear payments, review uncertain transactions or possible duplicates, and receive result notifications.
- **Categories and review:** merchant rules and category memory; confirm expenses, income, transfers, top-ups and refunds, with links to original expenses or paired notices.
- **Friend balances and net settlement:** choose who paid, split equally or by custom shares, and record entirely personal purchases. See both directions of debt; select items, review offsets/partial payments, confirm settlement and manually link the bank/TNG payment.
- **Budgets and savings:** monthly and category summaries, budget alerts, savings goals and deposits/withdrawals; optional on-device AI goal drafts on compatible devices.
- **Recurring and foreign-currency expenses:** scheduled entries, overdue posting, upcoming previews and exchange-rate conversion.
- **Backup and appearance:** JSON backup/restore, CSV export, light/dark appearance, animations, sounds and reminders.

English/Malay labels and messages are included, with **Bank / TNG** in non-Chinese interfaces. This release bundles a dedicated opening logo and shows its short spring animation before constructing the main screens. Startup ledger reads run off the UI actor, monthly summaries are reused, and unchanged refreshes avoid republishing the ledger. Native grouped sections, large titles, glass controls, payment zoom transitions, budget stages and category colours are retained.

Automatic recording requires configured Shortcuts that pass transaction details to YueJi. The app does not directly read bank accounts or Wallet history. Unfamiliar notification formats may still need manual review.

**Build and install:** copy this folder's contents, including `.github`, to the repository root. Run **Build YueJi iPhone App** in GitHub Actions, download the IPA and install it with AltStore. See the [installation guide (Chinese)](Windows安装与ApplePay设置.md).

## Native interface and Codemagic

Build 80 adds **Friend → Settle → Select items → Review net amount → Confirm payment** in Chinese, English and Malay. Friend-paid purchases include your share in personal spending while excluding the purchase from payments made by your account. Settlement records keep an audit snapshot and links to the original expenses. Bank/TNG linking requires explicit confirmation, amount/direction/date checks and unused payment/reference checks; matching amounts alone never link a payment. If a linked outgoing payment was automatically classified as an expense, confirmation removes that extra spending and keeps its original details for audit.

Partial payments offset both sides first and leave the remaining selected debt outstanding; unselected items stay untouched. Exact offsets record no transfer. Undo restores debt allocations without deleting expenses or creating another bank record. A linked bank payment remains available for review, and a converted automatic expense is never recreated automatically. Active settlements lock the original amount, merchant, date, category, items, payer, shares and refunds; undo the affected settlements before changing those fields. Notes and further valid repayments remain editable.

For a friend-paid purchase, the refund screen asks whether the refund went to you or the paying friend. Personal spending falls either way, but a refund received into your account is included in what needs to be returned to the payer. An incoming bank/TNG refund is explicitly treated as received by you. Legacy refunds assume the original payer received them. Refunds on settled expenses remain blocked until the related settlements are undone; payments then need review against the revised net balance, and linking is limited to the exact confirmed transfer amount.

Version 1–5 JSON backups remain readable. Version 1–4 records retain the legacy assumption that you paid, while version 5 friend payers and settlements are preserved. New backups use ledger version 6 to protect item breakdowns from being silently ignored by older apps and require this updated app. Items are optional; existing category allocations are retained until you replace them with a complete item breakdown. Item categories, search and CSV export use the same original transaction. Existing expenses, refunds, repayments and deduplication markers are retained. Friend-paid purchases currently split between you and the single paying friend; purchases paid by you retain support for multiple friends. Settlement entry limits are 200 selected items and one bank transaction per settlement; a partial transfer produces its own settlement record. This feature records confirmations locally and does not initiate bank transfers.

Regression tests cover the RM60/RM20/RM15 example (RM55 personal spending, RM5 received), partial payments, exact/offset-only settlements, prior refunds/repayments, stale previews, duplicate bank references across settlement and repayment/income flows, undo, automatic-record replay, atomic storage and version 6 backup round-trips. Run the XCTest suite through Codemagic/Xcode, then verify the full selection/review/link/undo flow on an iPhone; Windows structural and syntax checks do not execute XCTest.

The main screens use system grouped sections and large navigation titles, including Overview. Category summaries are visible directly, and payment details use the same system surfaces. Tabs, menus, bottom toolbars and sheets follow the system design. On iOS 26 and later, month controls use native glass buttons, sheets retain system curvature/material, and the tab bar can minimize while scrolling. Payment details and the add/filter sheets use Apple's zoom transitions on iOS 18 and later. Reduced Motion disables the custom zooms, symbol bounce and tab minimization; Reduced Transparency uses opaque month buttons. iOS 17 remains supported with standard controls and navigation.

For an iOS 27 SDK build, connect this repository to a personal Codemagic account, select branch `main`, and start **YueJi IPA (unsigned)**. The YAML workflow selects Xcode 27.1 on Mac mini M2, requires an iOS 27 SDK and runs the ledger tests on an iOS 27 iPhone simulator before packaging the unsigned IPA. Download it from that build's artifacts; `BuildInfo.txt` identifies the source commit, SDK and simulator. No build starts automatically.

Visual review on an iPhone is still required: check payment zoom and swipe dismissal, add/edit/delete actions, filter sheet resizing and keyboard behavior, month controls, scrolling tabs, dark appearance, larger text, Reduced Motion and Reduced Transparency. Fully close and reopen the app to check the logo spring, light/dark visibility, sound settings, and opening with a large ledger. Returning from another app should retain the current screen. Also check Overview's category links retain the selected month and show updated totals after editing or restoring records. Local structural checks do not measure frame times; Xcode tests and phone performance checks remain required. System controls follow the installed OS; financial content, category colours and the app icon retain YueJi's identity.
