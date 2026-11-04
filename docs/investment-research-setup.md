# AI 公司研究：个人试用

恢复已删除服务请先阅读 [恢复步骤与最新覆盖范围](investment-research-restore.md)。新增 Gamuda 和 Hong Leong Bank 自动读取，下方最初的两家公司说明仅为初版记录。

## 2026-11-04：默认改为自动获取官方财务网页

以下新模式取代下面旧 Google Search 模式作为默认部署路径：

- `INVESTMENT_RESEARCH_MODE=official`（不配置也默认 official）。没有 Google Search 工具调用，也不会失败后切换付费搜索。
- 保留 `INVESTMENT_RESEARCH_USER_ID`、`GEMINI_RESEARCH_API_KEY`；`GEMINI_RESEARCH_MODEL` 使用账户当前可用且支持 JSON 输出的免费额度模型。免费额度、可用性和是否启用计费由 Google 账户决定，代码不能保证永久免费。
- 首批仅支持 `MYX:MAYBANK` 与 `MYX:99SMART`。点击「自动获取并分析」后，服务端访问固定官方来源；不需要用户上传或粘贴财报。不代表后台定时抓取或自动推送，也不代表已支持所有马股。
- Maybank：从 https://maybank.listedcompany.com/newsroom.html/cat/7648 发现页面排列的前两条季度公告，再读取其 HTML 财务摘要。99 Speed Mart：读取 https://99speedmart.com.my/financial-information/ 的财务表格。不是读取完整 PDF，也不是全网新闻研究；列表顺序不保证涵盖所有最新披露。
- 只访问固定 HTTPS 来源及同域指定公告路径，禁止重定向；限制响应体及文本长度，模板失效、拦截页、缺少关键字段时停止，不生成无资料报告。
- 模型返回成长、盈利、财务稳健、估值、风险五项主观评价，每项 0–20；非空分项必须附同公司来源的逐字引文。校验能确认引文存在，不能独立保证模型推理正确。评分不是回测结果或上涨概率。
- 当前无可靠现价和全面风险数据，服务端强制将估值、风险分设为空，**综合分暂不计算**，不允许模型强行输出买入结论。其余资料缺失也应返回空分。报告显示已支持维度数、缺失资料、条件性下一步、来源和获取时间。
- 同样需要执行 `backend/investment-research.sql`，再部署整个 `investment-research` 文件夹（现在包括 `official.mjs`）。每天最多 10 次，来源失败也计入额度。未支持股票在扣额度前拒绝。
- 已在本地实际读取两家公司来源成功；未调用真实 Gemini、未部署 Supabase，未执行 iOS 编译。需要在部署后核验账户模型、AI 输出、超时和真实 UI。

### 旧模式（可选，不是免费默认）

只有明确设置 `INVESTMENT_RESEARCH_MODE=google_search` 才使用下文旧联网搜索路径。该模式需另行确认模型搜索权限和计费；不要为了免费试用开启它。

此版本是按需 Google Search 联网公司研究，不是实时行情服务。入口：账户 → 投资观察 → 股票详情 → AI 公司研究。投资观察页另有「对比 2–3 只股票」和「研究历史」。只上传所选股票代码，日期由服务端生成；不发送账本、余额、持仓、历史报告或个人投资信息。不改变收据、银行、分类 AI 的选择。

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
- 研究每次手动触发，不轮询、不后台推送；离开研究页或进入后台时取消请求并清除当前报告。客户端取消不保证已发出的服务端请求免计额度。
- 用户可主动保存已展示的研究原文到本机历史，仅供该账号回看；最多 20 条、30 天，下次读取时清理过期条目。按 Supabase 项目及用户 ID 哈希分文件隔离，使用 iOS 完整文件保护并排除系统备份。支持删除，不同步云端。保存的是原始文本，不保存 Search Suggestions、来源索引或网页 HTML，不作自动分析数据库，不重新发送历史报告给 AI。
- 股票对比从自选、内置清单或手动交易所代码选择 2–3 只；一次对比计入一次调用额度。使用同一 6–12 个月周期，要求分别说明成长、财务、估值、风险、证据日期与判断失效条件。跨币种及报告期不可比时明确说明，不强选赢家；实际输出质量仍需真实请求核验。
- 暂无自动历史差异分析、行情触发或推送。历史只供回看旧原文，不标为最新建议。
- 独立非持久化 WebView 展示报告，模型文本转义，来源仅接受 HTTPS，禁用脚本，保留搜索归属 HTML。外部链接交由浏览器。
- Windows 只能完成静态 Swift 检查与 Node 后端测试；Xcode 编译、真机渲染、Google 真实响应与账号配额需部署后验证。

官方参考：
- https://aistudio.google.com/docs/google-search
- https://aistudio.google.com/api-reference/generate-content
- https://aistudio.google.com/docs/pricing
- https://aistudio.google.com/docs/terms#grounding-with-google-search （历史用途与结果保存限制）
