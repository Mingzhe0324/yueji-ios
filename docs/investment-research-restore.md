# 研究服务删除后的恢复步骤

本地源码还在。恢复云端不会自动更新已安装的 IPA；新增来源提示需要新版 App。

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

新建名为 `investment-research` 的函数，上传或在编辑器分别添加以下三个同目录文件，保持文件名及完整内容：

- `supabase/functions/investment-research/index.ts`
- `supabase/functions/investment-research/handler.mjs`
- `supabase/functions/investment-research/official.mjs`

然后 Deploy。只保存文件不等于部署。也可在已登录且连接正确项目的 Supabase CLI 执行 `supabase functions deploy investment-research`。

## 5. 验证

在 App 用第 2 步对应的账号登录，打开 Maybank 或 Gamuda → AI 公司研究 → 自动获取并分析。核对报告股票代码、来源链接、报告期间和获取时间。不要把模型生成时间当作股价时间。

目前没有远程部署、真实 Gemini 调用或原生 iOS 构建的验证结果。额度每天 10 次，失败也可能扣额度。若失败，记录错误文字即可，不发送 API key。

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
