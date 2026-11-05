# 研究服务删除后的恢复步骤

本地源码还在。恢复云端不会自动更新已安装的 IPA；新增来源提示需要新版 App。

## 股票问答与新手起步

新版投资页提供并排入口「新手起步」「问 AI 股票问题」。新手页选择资金期限、应急储蓄、高息债务和承受亏损情况，生成可检查和编辑的学习问题；用户点击发送才传给 Gemini。这是学习引导，尚不是自动选股、行业机会排序或买卖时机服务。

问答使用同一个 `investment-research` 函数的新 `mode: stock_chat` 分支和现有个人账号认证、研究 API key、每日额度 SQL。需要重新部署生成的 `index.ts` 并安装新 App；没有新增 Secrets 或 SQL 迁移。不要把已改好的本地文件等同于已经部署成功。

问答没有搜索、实时行情或最新公司财报，不会自动读取账本；问题与最近最多三轮上下文交给 Gemini。用户可问术语、财报读法、ETF、风险及入门问题；涉及最新价格、选股排名或买卖时机时应明确无法核实。模型输出是知识解释，不能当成已核实的公司研究。

问题上限 2000 UTF-16 单位，上下文上限 6 条／24000 单位，仅接受交替 user/assistant；服务端仅转发白名单字段。每次发送可能使用一次研究额度（失败也可能消耗），不存入报告缓存。客户端最多展示最近 10 轮，离页、清空及账号切换会清除对话；后台或退出取消请求，但不能撤回已发送的服务端请求。

验证：24 项投资后端模拟测试通过，新增 Swift HTTP 测试覆盖问答端点、认证刷新及空问题拦截；Windows 已验证 Swift 语法和项目结构。原生编译、原生测试、线上 Gemini 回复和真机界面尚未验证。

最新覆盖及 PDF 部署说明见 [investment-pdf-coverage.md](investment-pdf-coverage.md)：当前 11 家自动来源。PDF 路径需要部署平台加载固定依赖 `npm:unpdf@2.1.0`；普通 HTML 路径不加载解析器。

## 简化部署包（推荐）

在项目目录执行 `node scripts/bundle_investment_research.mjs`。
会在项目旁的 `builds/investment-research-deploy` 生成：

- `database.sql`：包含每日额度和可选缓存。到 Supabase SQL Editor 运行。
- `index.ts`：合并后的函数入口（PDF 路径含固定 npm 依赖）。新建 `investment-research`，用这一个文件替换编辑器的入口后 Deploy。

仍需下面列出的四项 Secrets；执行缓存 SQL 后额外设置 `INVESTMENT_RESEARCH_CACHE=true`。
缓存按账号隔离、最多 20 条，每条最长复用 24 小时；点击分析仍重新获取来源，内容改变即失效。
缓存命中不扣 Gemini 每日分析额度；缓存不可用则按普通流程分析。
来源读取失败发生在扣分析额度之前。Google 调用失败仍可能扣额度。
客户端显示原报告生成时间，并标明缓存。保存的数据是模型输出，返回前重新验证引用并转义 HTML。
本地测试使用模拟服务验证，不等于已验证远程 SQL、RLS 或 Gemini。

## 1. Gemini 密钥

打开 https://aistudio.google.com/apikey ，在自己的 Google 项目创建 API key。免费优先时不要启用付费结算。将新 key 直接保存在 Supabase Secrets，不要发送到聊天或提交进 Git。

## 2. Supabase Secrets

在原来月记使用的 Supabase 项目中，打开 Edge Functions → Secrets，补齐：

| Name | Value |
| --- | --- |
| INVESTMENT_RESEARCH_USER_ID | Authentication → Users 中你的月记登录账号 UUID |
| GEMINI_RESEARCH_API_KEY | 新建的 Google API key |
| GEMINI_RESEARCH_MODEL | Google 账户当前可用、支持 JSON 输出且有免费额度的模型 ID；不要填写显示名称 |
| INVESTMENT_RESEARCH_MODE | official |

模型免费额度以 https://ai.google.dev/gemini-api/docs/pricing 和账户实际额度为准。本模式不调用 Google Search，也不会自动切换付费搜索。

SUPABASE_URL 和 SUPABASE_ANON_KEY 由 Supabase 环境提供。若连 Supabase 项目本身也删除了，需要先恢复项目和账号数据、更新 App 的连接配置；本指南不能恢复已删除的账本数据。

## 3. 数据库

SQL Editor → New query，粘贴并运行仓库 `backend/investment-research.sql` 的完整内容。已有同版本表可重复执行；不要删除旧表。成功后应有 `claim_investment_research` 函数和每日额度表。

## 4. Edge Function

如果不用简化部署包，新建名为 `investment-research` 的函数，上传或在编辑器分别添加以下四个同目录文件，保持文件名及完整内容：

- `supabase/functions/investment-research/index.ts`
- `supabase/functions/investment-research/handler.mjs`
- `supabase/functions/investment-research/official.mjs`
- `supabase/functions/investment-research/cache.mjs`

然后 Deploy。只保存文件不等于部署。也可在已登录且连接正确项目的 Supabase CLI 执行 `supabase functions deploy investment-research`。

## 5. 验证

在 App 用第 2 步对应的账号登录，打开 Maybank 或 Gamuda → AI 公司研究 → 自动获取并分析。核对报告股票代码、来源链接、报告期间和获取时间。不要把模型生成时间当作股价时间。

目前没有远程部署、真实 Gemini 调用或原生 iOS 构建的验证结果。额度每天 10 次，Google 调用失败也可能扣额度。若失败，记录错误文字即可，不发送 API key。

## 免费来源覆盖（2026-11-04）

- 自动读取：Maybank、99 Speed Mart、Gamuda、Hong Leong Bank。
- Gamuda 仅网页排列的前两个完整季度摘要；不保证最新或完整披露。
- Hong Leong Bank 是固定 FY2026 年度业绩公告，非自动滚动最新季度。
- 本次新增两家已用实际导入代码读取成功；43 项后端测试通过。
- App 另为 Public Bank、CIMB、Tenaga、IHH、MR DIY、Inari 提供官方资料页面入口。链接存在不等于自动分析已接入：网站可能拦截、仅提供 PDF 或暂时无法访问。
- MR DIY 实测返回空响应；Public Bank、Tenaga、IHH 本机读取失败，尚未启用导入。
- 仍未接入可供 AI 使用的当前行情、完整历史成交数据及全面新闻，不能生成实时买卖信号或完整综合分。未覆盖股票不会借用 Apple 或其他公司的证据。

官方说明：
- https://supabase.com/docs/guides/functions/deploy
- https://supabase.com/docs/guides/functions/secrets
- https://ai.google.dev/gemini-api/docs/api-key
