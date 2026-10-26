# 月记：登录后恢复账本

代码已接入 Supabase 邮箱验证码登录和整份账本同步。用户提供的项目地址和客户端公钥已保存到
`CloudConfig.json`（不包含数据库密码或管理密钥）。用户运行数据库脚本后，2026-10-25
只读复查已确认 Auth 和账本 schema health 均可连接。邮件配置、实际登录与数据同步验证仍待完成。
**未完成以下配置、数据库安装和设备验证前，不能把此版本当作已上线的云同步服务。**
请保留当前文件备份。账本版本仍为 6，原有 JSON 可继续导入导出。

## 1. 配置同一个项目

打开 Supabase 原来的项目，在 **Connect** 中取得 Project URL 和 **publishable key**。
URL 应形如 `https://你的项目编号.supabase.co`，不要复制控制台地址或追加 `/rest/v1`。
App 只接受 `sb_publishable_…` 或旧的 `anon` 公钥，不接受 `sb_secret_…`、`service_role` 或数据库密码。
公钥与 URL 必须来自同一个项目；不要为每次构建创建新项目，否则原账号和账本不会随之迁移。
参考 [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)。

在你实际使用的构建平台设置以下环境变量：

| 变量 | 内容 |
| --- | --- |
| `YUEJI_SUPABASE_URL` | Project URL |
| `YUEJI_SUPABASE_PUBLIC_KEY` | publishable key |
| `YUEJI_REQUIRE_CLOUD` | `1`，缺少配置时停止构建 |

GitHub Actions 使用仓库 **Settings → Secrets and variables → Actions → Variables**。
Azure Pipelines 使用流水线 Variables；Codemagic/CircleCI 使用对应项目的环境变量。
这些是公开客户端配置，不要把数据库管理凭证填进任何一个变量。

五个设备构建流程均在生成 IPA 前运行 `scripts/configure_cloud.py`，将配置写入本次构建的
`Info.plist`。环境变量优先；未设置时使用 `CloudConfig.json`，因此当前项目不必再次手动输入公钥。
源码 `Info.plist` 的默认值仍为空，模拟器测试不会触发真实登录。所有配置均缺失时会报告 LOCAL MODE。
原有模拟器功能测试使用仓库默认的本机模式，避免真实登录和邮件依赖；云同步单元测试用内存服务。
不要为了测试而把真实账号或访问令牌加入测试文件。

## 2. 安装数据库和启用邮件验证码

在同一项目的 SQL Editor 中运行整个 [backend/supabase.sql](backend/supabase.sql)。
脚本使用事务，创建按账号隔离的账本表、版本检查保存函数和不读取用户数据的连接检查函数。
它兼容旧版 `yueji_backups` 表名，保留已有表和账本；执行前可使用项目自身的备份功能留档。
不要关闭 RLS。参考 [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)。

先配置自定义 SMTP，再修改模板。Supabase 自 2026-06-03 起限制新建免费项目在默认邮件服务下编辑模板；
用户当前项目也已在界面遇到这个限制。数据库连接通过并不代表验证码邮件已可用。
参考 [免费项目邮件模板变更](https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier)。
若使用 Resend，官方接入要求 API key 和已验证的自有域名；不要把 Resend 私密 API key 放入 App 或 CloudConfig.json。
参考 [Resend SMTP 接入](https://resend.com/docs/send-with-supabase-smtp)。

完成 SMTP 配置后，在 Authentication 中启用 Email 登录，允许新用户注册（如只供已有账号使用，可保留禁止新注册）。
将 **Magic Link** 邮件模板改为包含验证码：

```html
<h2>登录月记 YueJi</h2>
<p>你的登录验证码是：</p>
<p><strong>{{ .Token }}</strong></p>
<p>回到月记输入验证码即可。没有发起登录请忽略此邮件。</p>
```

如果新用户的验证走 Confirm signup 模板，也在该模板包含 `{{ .Token }}`。
App 在 `/auth/v1/verify` 使用 `type: email` 验证邮箱验证码，不依赖浏览器跳回或自定义 URL scheme。
参考 [Passwordless email sign-in](https://supabase.com/docs/guides/auth/auth-email-passwordless)。

Supabase 默认邮件服务仅供受限测试，通常只能发给项目组织成员的邮箱。
给普通用户使用之前需配置自己的 SMTP；这是邮件服务设置，不是把 SMTP 密码放入 App。
若开启 CAPTCHA，还需要配套客户端挑战流程；当前客户端不提供 CAPTCHA UI，不应为此关闭已有生产项目的保护。
参考 [SMTP 设置及默认服务限制](https://supabase.com/docs/guides/auth/auth-smtp)。

## 3. 先检查连接，再安装测试

设置上述两个环境变量后，在项目目录运行：

```text
python scripts/configure_cloud.py --check --require
python scripts/check_cloud_connection.py
```

连接检查只访问 Auth 设置和 schema health；不会发送邮件、登录用户、读取或修改账本。
App 的 **设置 → 账号与同步 → 检查云端连接** 提供同样的区分。

| 结果 | 要检查的地方 |
| --- | --- |
| 尚未配置 / No cloud configuration | 当前构建是否注入了两个变量；拿到新 IPA 后才会生效 |
| API key rejected | URL 与公钥是否同项目；是否用了错误类型的 key |
| Auth reachable, database setup missing | 是否在同一项目完整执行了 SQL；稍后重试 schema 缓存 |
| Cannot reach / 连接失败 | 项目是否暂停、URL 是否正确、设备网络与 DNS |
| 验证码未发送 | Email provider、邮件模板、SMTP、收件人限制、速率限制 |
| 验证码无效或过期 | 使用最近一次邮件中的验证码，必要时重新发送 |

最后用测试账号在真机验证：登录 → 新增账目 → 确认已同步 → 卸载 → 重新安装相同服务配置的版本 →
用同一邮箱验证登录。应自动恢复账本并继续；无须选择 JSON 文件。
云端未收到的离线记录无法在卸载后找回，所以卸载前必须确认没有等待同步的更改。

## 同步行为与边界

- 第一次登录且云端没有账本时，自动上传本机账本并绑定账号；重装后本机无账本且云端有记录时，自动下载。
- 同一账号已同步后，本机修改会自动排队；打开/返回 App 时检查云端，进入后台时尽力完成同步。
  iOS 不保证后台网络任务一定完成。登录有效且本机有账本时可离线继续使用。
- 本机干净而云端更新时自动拉取；仅本机修改时带版本号上传。两边都修改则要求选择整份账本。
  选择前若数据再次改变，必须重新确认；不对分账、退款或结算金额做不可靠的自动合并。
- 下载时在写锁内再次核对本机指纹，保留导入前的本机恢复副本。上传中的新更改仍标记为待同步。
  上传成功但响应丢失时，下次比较相同内容会确认成功，不重复追加记录。
- 本机账本绑定账号和服务地址，退出登录后保留数据但隐藏账本；必须登录原账号。
  当前版本不提供同一安装内切换到另一个人的账本，避免混用本机历史、草稿和自动记账队列。
- 令牌保存在设备 Keychain，密码不进入 App；退出登录清除本机令牌。
- 云端保存完整 ledger，包括交易、预算、物品、分账、退款、结算、固定消费、储蓄目标、商户规则和旅行账本。
  设备设置、通知权限、未保存草稿及尚未入账的自动化输入队列不参与同步。
- 此实现使用服务端账号访问控制及 HTTPS，并非端到端加密；项目管理者拥有数据库管理权限。
  文件备份继续作为独立副本使用。自动恢复不能找回从未上传成功的数据。

## 验证记录

本机已通过：项目资源/引用检查、7 项 Python 配置/错误分类测试、Swift grammar、PostgreSQL/PLpgSQL grammar、
五个流水线 YAML 解析。语法解析不等同于 Xcode 类型检查或设备运行。

新增 `CloudSyncTests` 覆盖首次上传、重装自动恢复、账号隔离、冲突及过时确认、响应丢失、上传中本机修改、
离线保留、下载并发保护、稳定指纹和错误配置。
`CloudHTTPTests` 通过隔离的 URLProtocol 假服务检查连接探测只使用公钥、不触碰账本，区分错误公钥与缺失数据库，
并验证服务端临时故障不会被当成登录过期或丢弃缓存令牌。测试不会连接真实项目或发送邮件。
`backend/tests/account_isolation.sql` 在事务回滚中检查跨账号读写限制、匿名访问和过期版本写入。
这两组原生/数据库测试尚未在 Xcode 或真实 Supabase 上运行；部署前必须执行。
# 密码登录与 Google 登录更新

最新账号流程和所需后台设置见 [密码与 Google 登录设置](docs/password-google-setup.md)。下方的验证码登录说明记录先前版本；新版本使用邮箱密码登录，邮件验证码用于注册确认和重设密码。Google 需要独立启用 Provider 和回调地址。
