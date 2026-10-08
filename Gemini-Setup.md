# Gemini 自动分类配置（1.53.1 / build78）

这次交付包含 App 和 Supabase Edge Function 源码，尚未部署到你的 Supabase，也没有读取或使用你的 Gemini API Key。

## 1. 后端一次性配置

在你自己的 Supabase 项目中，进入 Edge Functions → Secrets，添加：

| 名称 | 内容 |
| --- | --- |
| GEMINI_API_KEY | 你已有的 Google AI Studio Gemini API Key |
| GEMINI_MODEL | 你账户当前可用、支持 generateContent 与结构化 JSON 输出的文字模型 ID（从 AI Studio 复制，不是显示名称） |
| YUEJI_ACCESS_TOKEN | 为月记单独生成的 32–128 位随机连接码，建议 64 位十六进制字符；不是 Gemini Key，也不是 Supabase service_role Key |

Windows PowerShell 可在本机生成连接码：
~~~powershell
$yuejiBytes = New-Object byte[] 32
$yuejiRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$yuejiRng.GetBytes($yuejiBytes)
[BitConverter]::ToString($yuejiBytes).Replace('-', '').ToLowerInvariant()
$yuejiRng.Dispose()
~~~
只将这段命令产生的连接码存入后端 Secrets 和你手机的月记设置，不要提交到 GitHub。

部署文件：
- supabase/functions/classify-merchant/index.ts
- supabase/functions/classify-merchant/handler.mjs
- supabase/config.toml

可以在 Supabase Dashboard 的函数编辑器创建 classify-merchant，加入上面两个源码文件并部署；该函数的网关 JWT 验证需要关闭，因为它使用 X-YueJi-Token 自己验证连接码。**handler.mjs 的连接码校验必须保留**。如果用 Supabase CLI，在项目根目录运行：
~~~sh
supabase login
supabase functions deploy classify-merchant --project-ref YOUR_PROJECT_REF --no-verify-jwt
~~~
Secrets 可直接通过 Dashboard 配置，不必在命令行粘贴 Gemini Key。

最终函数地址为：
https://YOUR_PROJECT_REF.supabase.co/functions/v1/classify-merchant

这是个人自用的连接码认证，不是多人产品的账号鉴权。后端只允许已认证 POST 请求；连接码泄露时请在后端与手机两处替换。内存限流仅防止单实例突发调用，不是计费硬上限；应另外设置 Google 项目的额度。

## 2. 安装和启用

1. 将 YueJi-iOS 文件夹内的所有内容（含 .github）更新到 GitHub 仓库根目录。
2. 运行 Build YueJi iPhone App，下载 IPA 并通过 AltStore 安装。
3. 月记 → 设置 → 自动记账 → AI 自动分类 · Gemini。
4. 输入上面的函数地址和 YUEJI_ACCESS_TOKEN 连接码，打开「用 Gemini 自动分类」。
5. 点「保存并检查连接」。此按钮会真实调用后端和 Gemini，以 Kung Fu Soup 检查，不创建测试账目。
6. 出现连接成功后，后续真实自动入账的付款会使用 Gemini 分类。

Google Key 永远不填进 App，App 连接码使用设备钥匙串保存。账本导出不包含连接设置或密钥。自动记账必须仍按原来的方式把通知／Apple Pay 付款传入月记。

## 3. 工作方式和实际边界

- 先原子保存付款、去重标记和待分类状态，再请求 AI。网络失败不会撤销或重复创建付款。
- 用户已保存的商户分类规则优先；其次是 Gemini。原有关键词分类仅用于断网、模型不确定或功能未开启时的备用。
- 只上传遮盖后的商户名。不会上传通知正文、金额、账号字段、银行余额、整份账本。商户名仍可能含个人姓名；遮盖规则不是完美匿名化。
- Gemini 做语义推断，不是实时 Google 搜索，也不能确认买了哪件商品。低置信度、个人名、未知商户需人工确认。
- AI 只改变已保存消费的类别，不决定付款成功、金额、时间或转账用途。未识别通知、收入／个人转账仍走原来的待确认流程。
- 服务超时／限额／断网保留本地分类，打开 App 时重试。每轮最多 5 笔，自动尝试最多 3 次，之后可在设置手动重试。
- 「需要留意的分类」可查看状态；采用 AI 建议并记住，或打开账目手动编辑。手动保存会取消仍在处理的 AI 更新。
- 关闭功能停止新请求；已经发出的请求不能收回，但关闭期间的返回结果不会改分类。
- 不会自动重算历史账目。不确定的现有分类保留原值，AI 建议单独展示。
- 当前固定支持 6 个内置类别，自定义类别可通过用户商户规则优先使用。
- 尚无真实 API 联调或原生 iOS 编译验证。服务的结构化 JSON 格式和模型可用性以你的账户和连接检查结果为准。

## 4. 验证

已执行：8 项 Node 后端测试（模拟 Google API），覆盖鉴权、输入白名单、超长请求、正常分类、低置信度、错误输出、上游失败、遮盖与限流；项目结构检查通过。

新增 XCTest：分类持久化、金额不变、手动编辑优先、已记住规则优先、删除后迟到回应、非法输出和 HTTPS 地址校验。当前环境没有 Xcode，需 GitHub Actions 执行这些测试。

可本地重跑后端测试：
~~~sh
node --test supabase/functions/classify-merchant/handler.test.mjs
~~~

官方参考：
- https://ai.google.dev/gemini-api/docs/generate-content/structured-output
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/guides/functions/function-configuration

