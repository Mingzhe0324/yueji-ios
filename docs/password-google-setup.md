# 邮箱密码与 Google 登录

代码已提供邮箱密码注册、密码登录、邮箱验证码确认注册、重设密码、已登录账号设置密码，以及 Google 系统浏览器登录（PKCE）。Apple 登录未接入。原有账号与账本 UUID 不变；使用其他邮箱登录不会自动迁移原账号账本。

## Supabase 邮件

在当前项目的 Authentication → Emails → Templates：

- Confirm signup：标题用「月记注册验证码 / YueJi sign-up code」，正文包含 `{{ .Token }}`。
- Reset password：标题用「月记重设密码 / Reset your YueJi password」，正文可粘贴：

```html
<h2>重设月记密码 / Reset your YueJi password</h2>
<p>请在月记输入验证码，然后设置新密码。<br>Enter this code in YueJi, then choose a new password.</p>
<h1>{{ .Token }}</h1>
<p>请勿分享此验证码。若非本人操作，请忽略。<br>Do not share this code. If you did not request it, ignore this email.</p>
```

保留邮箱确认开关；建议在 Supabase 密码设置中也将最小长度设为 8 或更高。App 不保存明文密码，只通过 HTTPS 提交给 Supabase。已经登录的验证码账号可在设置 → 账号与同步 → 设置 / 修改密码添加密码；已退出者可通过「忘记密码 / 首次设置密码」验证邮箱后设置。

## Google Cloud 与 Supabase

1. 打开 Google Cloud 的 Google Auth Platform，选择项目，完成 Branding 和 Audience。测试状态下将用于测试的 Gmail 加入 Test users。
2. 在 Clients 创建 **Web application** OAuth 客户端。此 App 通过 Supabase 的网页授权流程连接 Google，不使用原生 Google SDK。
3. 在 Authorized redirect URIs 添加以下地址（最好与 Supabase Google Provider 显示的 callback URL 核对）：

   `https://vplioeukzzmeqfdnqmfs.supabase.co/auth/v1/callback`

4. 在 Supabase → Authentication → Sign In / Providers → Google 启用 Google，填写该客户端的 Client ID 和 Client Secret，并保存。Secret 仅存于 Supabase 后台，不写入代码、GitHub 变量或聊天。
5. 在 Supabase → Authentication → URL Configuration → Redirect URLs 添加：

   `yueji-auth://auth/callback`

6. Google 所需 scopes 为 openid、email、profile。不请求 Gmail 邮件或 Google Drive 权限。

「通过 Google 继续」可创建或登录 Google 对应账号。退出后登录其他账号会切换到该账号独立的本机目录，原账号的账本、未同步更改和内部备份仍保留。不同邮箱的账本不会自动合并；切换后需重新选择外部自动备份文件夹。详见 account-switching.md。现有账号的显式第三方绑定/解绑不在本次范围。

## 删除后重新安装

首次启动会在读取 Keychain 登录状态前检查安装标记。删除 App 清除本机数据后，再安装会清除残留的登录凭证并显示欢迎页。正常更新及日常启动保留登录。旧版升级使用已有 cloud-link 作为迁移依据，避免强制退出已同步用户。iOS「卸载 App」（保留文稿数据）或恢复设备备份与「删除 App」不是同一种情形，保留数据时可能继续保留登录。

## 验证状态

已添加新安装/普通更新、密码端点、恢复验证和 Google PKCE 交换的 XCTest 回归用例。Windows 只能运行项目、配置和语法检查；原生编译、这些 XCTest、Google 回调、密码自动填充、邮箱模板和真机重装仍需 GitHub Actions 与 iPhone 验证。当前不宣称第三方登录已在后台启用。

官方参考：
- https://supabase.com/docs/guides/auth/passwords
- https://supabase.com/docs/guides/auth/social-sign-in/auth-google
- https://supabase.com/docs/guides/auth/auth-email-templates
