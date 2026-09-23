# 月记 · 原生 iPhone App

这是 SwiftUI 原生项目源码，不是网页，也不是已签名、可直接安装的 IPA。优先实现 Apple Pay → 快捷指令 → 本机账本。无需账本服务器、网页令牌或付费开发者账号。安装与首次自动化配置仍需要你在自己的设备完成。

## 已实现

- 原生 Liquid Glass 卡片（iOS 26 及以上），旧系统使用材质背景；最低 iOS 17。
- 每月个人消费、实际付款、分类统计、月度预算、搜索和编辑。
- Apple Pay App Intent「记录 Apple Pay 支出」：接收金额、商户、币种、时间与可选交易标识，写入本地账本；仅接受 MYR。
- 朋友代垫、油费平均或自定分摊、是否包含司机、部分还款与撤销。朋友份额从个人消费中扣除，归还代垫不重复算收入。
- 每次修改前自动保存上一版，保留最近 30 份本地备份；可导出 JSON 到文件或 iCloud Drive 并恢复。
- TNG 目前手动记录。付款后是否为朋友代垫、朋友是谁及油费份额，需要你编辑指定，系统无法从付款本身推断。

## 先看安装说明

打开 `Windows安装与ApplePay设置.md`。免费路线是：自己的公开 GitHub 源码仓库 → GitHub Actions 云端编译 → Windows AltStore Classic 签名安装 → iPhone 配置交易自动化。

公开仓库的标准 GitHub 托管 runner 当前免费。不要选择付费 larger runner。免费 Apple ID 侧载通常每 7 天要刷新签名，过期后 App 无法打开，记账也不能依赖它继续工作。云端编译只用于生成 App；日常账本保存在手机。

## 交付与验证状态

此环境没有 Xcode、Swift 编译器或 iPhone，**尚未完成原生编译、模拟器测试或 Apple Pay 实机验证**。已检查项目文件、源文件引用、图标和配置结构。仓库内的工作流会先在模拟器执行 XCTest，再生成未签名 IPA；第一次成功构建和真机验收仍待完成，不能将源码交付视为已安装或自动入账已验证。

测试覆盖金额精度、分摊余数、重复入账、部分还款、超额还款拒绝、备份恢复和损坏文件保护。源码目标使用 Xcode 26 SDK 的玻璃 API，并不表示所有 iOS 27 行为已经实测。

## 数据与自动化边界

- App 不直接读取钱包或银行历史；只记录快捷指令交给它的输入。交易触发及可用字段受 iOS、卡片和付款方式影响。
- 不自动补录漏掉的交易，不自动识别退款或撤销；失败/取消付款不得当成成功支出传入。
- 优先用稳定的原始交易标识去重；没有标识时按「交易时间到秒 + 商户 + 金额 + MYR」去重。同秒同商户同金额的不同付款可能被合并。使用当前时间代替原始时间时，重新执行不能可靠去重。
- 本地备份不等于云备份；卸载会删除账本和本地备份。建议定期导出到 iCloud Drive。导出文件包含交易及朋友姓名，请自行保管。
- 此版本读取自己的 v1 JSON 格式，不直接导入之前网页版本的备份。
- 重启后至少解锁一次；锁屏、后台运行和签名状态都需实机测试。不能承诺所有付款方式均被捕获。

## 项目结构

`YueJi/`：原生界面、数据模型、本地存储与快捷指令动作。

`YueJiTests/`：XCTest。

`YueJi.xcodeproj/`：可共享 Scheme 的 Xcode 项目。

`.github/workflows/build-ios.yml`：手动触发的云端测试与 IPA 构建，不需要上传 Apple ID 或证书。

官方说明：

- Apple 交易自动化：https://support.apple.com/zh-hans/guide/shortcuts/apd65c67538a/ios
- GitHub 标准 runner 免费范围：https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- AltStore Windows：https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- AltStore 刷新及有效期：https://faq.altstore.io/altstore-classic/your-altstore
