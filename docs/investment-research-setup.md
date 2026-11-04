# AI 公司研究：个人试用

此版本是按需 Google Search 联网公司研究，不是实时行情服务。入口：账户 → 投资观察 → 股票详情 → AI 公司研究。只上传股票代码，日期由服务端生成；不发送账本、余额、持仓或个人投资信息。不改变收据、银行、分类 AI 的选择。

## 部署（尚未在远端执行）

1. 在 Supabase SQL Editor 执行 `backend/investment-research.sql`。每个账号每 UTC 日最多 10 次调用，原子扣减；失败也计入额度，避免重试失控。
2. 从 Supabase Authentication 用户列表取得自己的用户 UUID，设置服务端 secret `INVESTMENT_RESEARCH_USER_ID`。未配置则拒绝服务；其他账号返回 403。
3. 设置独立的 `GEMINI_RESEARCH_API_KEY` 和 `GEMINI_RESEARCH_MODEL`。选择当前账号可用、支持 `generateContent` 与 `google_search` 的模型；按官方价格核实该模型的搜索免费额度。不要直接复用可能已绑定计费的收据项目密钥。免费要求应通过未启用计费的 Google 项目保障：应用不能从 Key 判断计费状态，也不能保证服务商未来免费政策。没有配置时不会回退到收据 Key 或其他模型。
4. 部署 `supabase functions deploy investment-research`（使用项目现有 JWT 网关配置；函数内部也验证用户）。不要将密钥写入代码、截图或聊天。
5. 登录配置的个人账号试用，核验中文报告、证据日期、来源链接及 Google Search 归属内容。验证其他账号被拒绝、无来源结果被拒绝、断网及额度耗尽行为。

服务端使用现有 `SUPABASE_URL`、`SUPABASE_ANON_KEY`。未自动开通计费、未调用生产 AI、未部署远端 SQL 或函数。源代码推送不等于功能已上线。

## 结果与限制

- 提示词要求公司身份、6–12 个月机会、风险与反证、下一步观察条件、判断失效条件、证据缺口。无法确认公司时应明确说明，不承诺收益或编造上涨概率。
- 必须包含搜索查询、来源、与正文匹配的来源段落和 Google 搜索归属内容；否则返回 422，不能用模型记忆降级。
- 返回的证据关联是服务商提供的 grounding 元数据，不等于每句话已独立核实。网页资料可能过期，分析生成时间不是行情时间；不提供即时价格、精确买卖价位或自动交易。
- 研究每次手动触发，不轮询、不后台推送；离开研究页或进入后台时取消请求并清除报告。报告不落盘。客户端取消不保证已发出的服务端请求免计额度。
- 独立非持久化 WebView 展示报告，模型文本转义，来源仅接受 HTTPS，禁用脚本，保留搜索归属 HTML。外部链接交由浏览器。
- Windows 只能完成静态 Swift 检查与 Node 后端测试；Xcode 编译、真机渲染、Google 真实响应与账号配额需部署后验证。

官方参考：
- https://aistudio.google.com/docs/google-search
- https://aistudio.google.com/api-reference/generate-content
- https://aistudio.google.com/docs/pricing
