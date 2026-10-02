# 启用账号与云备份

源码版本 1.41.1 build 56 已包含邮箱注册、邮箱验证码、登录、密码重置、Keychain 会话、整份账本云备份与恢复。**尚未连接你的真实云项目：配置前不能登录，也不能靠此功能恢复卸载的数据。**

1. 在 [Supabase](https://supabase.com/dashboard) 创建项目。
2. SQL Editor 中运行 `backend/supabase.sql`。此表按用户隔离，登录用户只能读取和更新自己的备份。写入使用版本检查，其他设备已更新时会拒绝覆盖。
3. Authentication 中启用 Email/password，并保留邮箱确认。Email Templates 的 **Confirm signup** 和 **Reset password** 邮件正文分别加入：
   ```html
   <p>月记验证码：{{ .Token }}</p>
   ```
   App 使用 `/auth/v1/verify` 的 signup/recovery 验证码流程，不需要跳转回 App。注册成功提示之后，在同页填写验证码；忘记密码后填写验证码与新密码。
4. 配置实际 SMTP 发件服务。Supabase 的默认发件限制可能只允许发送给项目成员，并有频率限制；用于真实用户前必须测试邮件送达。验证码长度和到期规则由项目配置控制。
5. GitHub 仓库 **Settings → Secrets and variables → Actions → Variables** 新建：
   - `YUEJI_SUPABASE_URL`：项目 HTTPS URL，例如 `https://你的项目.supabase.co`。
   - `YUEJI_SUPABASE_PUBLIC_KEY`：项目 **Publishable key**，或旧版 `anon` 公钥。
   **绝不能放 `service_role`、secret key 或数据库密码。**这两项公开连接信息会随构建嵌入 App；数据权限由 JWT 和数据库 RLS 决定。
6. 上传本版源码并运行 Build YueJi iPhone App。下载生成 IPA，用 AltStore 覆盖安装；更新前先导出完整 JSON 备份到 App 文件夹外。
7. 首次打开 App → 注册 → 验证邮箱 → 进入账本。再打开设置 → 账号与云备份 → 选择上传本机账目。已有云备份时，选择恢复云端或明确确认用本机替换。第一次不会自动覆盖任何一份账目。
8. 页面显示“备份成功”后，用另一台设备或全新测试安装登录同一账号，检查恢复后的消费、银行/TNG 通知、朋友还款、储蓄目标。先在测试设备验证，勿拿唯一账本直接卸载测试。

## 行为与限制

- 本机仍可离线记账。开启自动备份后，在 App 运行期间修改会延迟 2 秒同步，打开 App 时会重试。网络错误显示状态，未成功上传的新数据不保证在卸载后恢复。
- App Intent 在后台完成交易不保证有足够运行时间上传。卸载前打开 App、检查并同步，确认成功日期；本地快照本身不抵抗卸载。
- 首次登录需先检查云备份并选择本机/云端；后续启动会检查已绑定账号和云端版本，一致时继续自动备份，版本冲突时需要重新选择；此版是安全的整份备份恢复，**不是实时多设备合并同步**。
- 切换账号不会自动上传另一账号的本机账目。绑定过其他账号的本机账目无法跨账号上传，需要先恢复当前账号云备份。没有云数据的新账号建议在独立测试安装使用。
- 云端恢复前保留本机恢复副本；消费与通知去重标记会一起恢复，避免重复叠加。
- 会话令牌存 Keychain；密码不持久化。备份通过 HTTPS 传输，云端 JSON 不提供端到端加密。当前云表保留每个账号最新一份备份，本机保留历史快照。
- 这是个人侧载接入版本。账号删除、正式隐私政策、服务运营和 App Store 上架流程尚未包含；上架前需另行补齐。

官方资料：[邮箱模板](https://supabase.com/docs/guides/auth/auth-email-templates)、[邮箱密码](https://supabase.com/docs/guides/auth/passwords)、[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)。
