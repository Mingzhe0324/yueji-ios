# Windows 安装与 Apple Pay 设置

## 1. 在云端编译

你需要自己的免费 GitHub 账号。为了使用公开仓库标准 runner 的免费额度，本方案把这份纯源码放到自己的公开仓库；不上传账本、备份、密码或证书。若不希望源码公开，请先检查私有仓库的免费额度与计费设置。

1. 解压 `YueJi-iOS.zip`。安装 GitHub Desktop（https://desktop.github.com/），登录自己的 GitHub。
2. 在 GitHub Desktop 新建本地仓库，例如 `yueji-ios`。打开仓库目录，将解压文件夹**里面**的内容全部复制进去；根目录应直接有 `YueJi.xcodeproj`、`YueJi`、`YueJiTests` 和 `.github`。
3. Windows 文件资源管理器打开“显示隐藏的项目”，确认 `.github/workflows/build-ios.yml` 存在。提交文件，再 Publish repository；公开仓库须取消 Keep this code private。
4. 浏览器打开自己的仓库 → Actions → **Build YueJi iPhone App** → Run workflow。若第一次需要启用 Actions，先按页面提示启用。
5. 等待所有步骤成功。工作流先跑测试，再构建手机版本。若失败，在失败步骤查看日志；此时不会产生可交付 IPA。可以把错误日志提供给我继续修复，不要分享账号密码。
6. 成功后从该次运行底部 Artifacts 下载 `YueJi-unsigned-IPA`，解压取得 `YueJi-unsigned.ipa`。产物保留 7 天，之后可重新运行。

工作流未在交付环境执行；第一次运行就是原生编译验证。使用 macos-26 标准 runner，需其默认 Xcode 支持 iOS 26 的玻璃 API。不要在工作流中填 Apple ID，也不需要付费 Apple Developer 订阅。

## 2. 用 Windows 安装到 iPhone

按 AltStore Classic 官方 Windows 指南安装，不使用 AltStore PAL 的地区市场安装路线：
https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows

1. 按官方指南安装 Windows 所需的 iTunes、iCloud 和 AltServer；依赖安装来源以当前指南为准。
2. USB 连接 iPhone，解锁并信任电脑；按指南配置同步，在 Windows 托盘的 AltServer 菜单选择 Install AltStore 和自己的手机。
3. 在官方安装流程中使用自己的 Apple ID。不要把密码或验证码发给任何人。按 iPhone 提示信任开发者，并在系统要求时开启开发者模式。
4. 将构建好的 IPA 放进 iPhone“文件”App（例如自己的 iCloud Drive）。在 AltStore 的 My Apps 页点加号，选中 IPA 安装。
5. 打开「月记」，确认看到概览、账本、分账和设置四个页面。

免费签名每 7 天到期。保持 AltServer 可用，按官方说明让手机连接电脑刷新，或在 AltStore 使用 Refresh All。不要等签名过期才处理；自动记账依赖 App 可运行。每次更新使用同一账号及应用身份，先导出备份，不要先卸载。iOS 27 与当前 AltStore 的具体兼容情况仍需以你的安装结果确认。

## 3. 先验证 App 的记账动作

1. 安装后至少打开「月记」一次，再打开 iPhone「快捷指令」。
2. 新建普通快捷指令，搜索「月记」或「记录 Apple Pay 支出」。如果搜索不到，先重新打开 App 与快捷指令，检查 App 签名是否有效。
3. 添加该动作，填金额 `0.01`、商户 `测试`、币种 `MYR`、交易时间「当前日期」、交易标识 `test-001`。
4. 运行后打开月记账本，应出现 RM 0.01。再运行相同标识，记录应仍只有一笔。
5. 删除测试记录。删除后再次使用同一标识仍会拒绝重复入账，因此下一组独立测试请换标识。

这一阶段只证明动作可以保存数据，不代表 Apple Pay 自动化已连接。

## 4. 接 Apple Pay 交易自动化

Apple 官方触发器说明：https://support.apple.com/zh-hans/guide/shortcuts/apd65c67538a/ios

1. 在快捷指令 → 自动化 → 新建个人自动化 → 交易 / Transaction，选择你用来 Apple Pay 付款的卡片，选择立即运行（以系统实际选项为准）。
2. 在自动化内添加「记录 Apple Pay 支出」。从「快捷指令输入」选取系统实际提供的属性，映射到该动作：金额 → 数字金额；商户 → 商户名称；币种 → 货币代码；交易时间 → 原始交易日期时间（若提供）；交易标识 → 原始唯一编号（若提供，否则留空）。
3. 属性名称可能因版本和语言不同而变化，例如 Currency Amount、Name、Currency Code。不要把整个交易对象或带 RM 前缀的文本直接填入数字金额，也不要把测试金额留在自动化里。
4. 传入交易真实币种，不能把外币硬填 MYR。外币先在月记「设置 → 币种与汇率」保存参考或实际汇率；缺少汇率时动作报错且不写入，需保存汇率后补录。
5. 如果只有金额、商户，没有日期，可以在动作前取一次「当前日期」作为接收时间；月份统计将使用这个时间，且手动重跑可能重复记账。若存在原始时间或编号，优先使用原始值。
6. 如果自动化完全没有金额或无法提取金额，先不要启用：缺少金额时本 App 无法独立补读银行数据。把自动化的可用字段截图给我，可据实际情况调整映射。
7. 保存后进行一笔你原本就需要的小额 Apple Pay 付款，对照实际扣款、自动化运行结果、月记记录金额与商户。再分别验证锁屏付款及常用卡片。

不要假设 Apple Watch、线上 Apple Pay 和所有卡片都有相同触发行为，需分别验证。失败付款若触发自动化，必须检查实际输入并修正记录；当前动作不能自行向银行核验付款成功。

## 5. 分账与备份验收

- 编辑已有 Apple Pay 支出 → 开启朋友分账 → 填朋友姓名，选择平均或自定份额。已有付款不要再新增一笔相同代垫。
- 行程油费开启油费开关，设置司机是否参与分摊。当前按输入的实际费用分摊，不会自动读取里程或推算油耗。
- 在分账页登记部分还款，确认欠款减少，而「我的月度消费」不变。
- 在设置导出 JSON 到 iCloud Drive。每次修改前的本地自动备份可从设置恢复，但卸载后会一并消失。

验收完成前，请保留钱包原始记录核对。App 无法补回未触发、签名失效或系统限制期间漏掉的交易。
