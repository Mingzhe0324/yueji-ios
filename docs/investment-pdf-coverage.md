# PDF 与跨市场扩展（2026-11-05）

当前自动覆盖 11 家：Maybank、99 Speed Mart、Gamuda、Hong Leong Bank、CIMB、TNB，加上 IJM、Sunway、Apple、Microsoft、NVIDIA。五个新增来源均通过正式导入函数联网实测。不是全部股票自动覆盖；股票列表显示自动研究或需要导入资料。IJM 和 Sunway 可从自动研究专区直接打开，暂使用文字图标。

- IJM：固定 FY2026 Q4 官方业绩演示，32 页；提取文本并标记 PDF 页码。不是完整审计财报。
- Sunway：固定 Q2 FY2026 新闻稿。
- Apple：固定 FY2026 Q4 新闻稿。
- Microsoft：固定 FY2027 Q1 业绩公告。
- NVIDIA：固定 FY2027 Q2 业绩公告。

PDF 使用固定 `npm:unpdf@2.1.0`，仅下载服务器明确配置的官方 URL，禁止重定向；最大 8 MB、60 页、60000 字符。拒绝扫描件、空白提取页、超限文件及公司身份不匹配。不开启 OCR，不读取用户提供的 PDF URL，不把模型指定网址作为来源。保留表格文本分隔与页码，但无法保证多列视觉阅读顺序；无法对应单位和列时要求不评分。提取器和正式来源在 Node 环境验证，Supabase Deno 首次依赖加载、CPU 限额及真实模型请求仍须部署验证。

TNB 的 unaudited results PDF 本次实测无可提取文字，故保留五年 HTML 摘要，不宣称读取该扫描件。MRDIY 官网直接请求返回 202 空页面，本次不加入自动支持。

运行 `node scripts/bundle_investment_research.mjs` 后整体替换 Supabase index.ts；生成文件保留固定 npm 动态导入，部署平台需要能够解析该依赖。模块方式部署需额外上传 `pdf.mjs`。无需数据库迁移或新增 Secrets。缓存版本已升级，避免复用旧说明。

后续仍需逐个核验其他公司的披露入口及可提取财报。没有接入全市场行情源、OCR 或自动发现最新公告，因此不承诺全部股票或全部报告可读。
