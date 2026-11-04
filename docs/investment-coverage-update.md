# 自动研究与概览入口（2026-11-05）

概览页快捷操作下方新增「投资观察 · AI 研究」入口。投资页新增自动研究专区，可直接进入六家公司研究。

自动官方来源从四家扩展至六家：Maybank、99 Speed Mart、Gamuda、Hong Leong Bank、CIMB、TNB（MYX:TENAGA）。

- CIMB：固定 2026 第二季度公告，发布于 2026-08-28；核验集团身份、Total income、利润及报告期间。
- TNB：官方五年年度财务表，目前为 2021–2025，包含重述标记、单位及历史期末股价；未读取页面链接的季度 PDF，期末价格不是现价。
- 两个新增来源已在本机直接读取成功；云端来源访问和 Gemini 生成仍须部署后验证。

仍使用免费官方网页路线，不启用 Google Search。资料不足时不生成综合分，不保证所有股票都能自动研究。原有手动导入功能保留。

运行 `node scripts/bundle_investment_research.mjs`，将生成的 index.ts 完整替换 Supabase 的 investment-research 函数并部署。数据库和 Secrets 无需因此修改。概览入口及六家公司列表需要安装新版 iOS 构建。
