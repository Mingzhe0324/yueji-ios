# AI 功能与自动分类

## 已接入的入口

- 设置 → AI 功能：保留自动分类设置、银行通知 AI 和收据入口，采用原生 List 与系统导航。
- 已移除一句话记账、问账本以及概览的月记 AI 入口。服务端仅接受 `classify`，旧的 `entry` / `query` 请求返回 400，不占用 AI 额度。已保存账目不受影响。
- AI 自动分类：在 AI 页面或记账表单开启后，描述／物品名称停顿 900ms 才请求。仅发送当前文字与分类名称（文字中的个人内容也会发送），分类必须在现有分类列表内。旧请求取消、手动选择优先、退出页面取消。识别失败保留原分类，可继续手动保存。
- 收据：新账目可开启「按物品保存分类」，支持最多 100 项。开启自动分类后会识别各行，分类可修改。税费、折扣与舍入按原始行金额分摊到最终物品金额；预览和保存使用同一份物品归属计算，个人分类统计只计算自己的份额。原始金额保留在收据说明中。已有账目关联仍保留原分类与物品结构。
- 银行通知 AI 仍按 [bank-notification-gemini.md](bank-notification-gemini.md) 独立部署与开启。

## Supabase 部署

1. 在 SQL Editor 执行 `backend/assistant-gemini.sql`。额度表启用 RLS，不允许客户端直接访问，函数按已登录用户每日 UTC 日期原子计数。
2. 新建 Edge Function，名称必须是 `assistant-gemini`。上传 `supabase/functions/assistant-gemini/index.ts` 和同目录的 `handler.mjs`，部署。
3. Secrets 保留现有 `GEMINI_API_KEY`，新增 `GEMINI_ASSISTANT_MODEL`，可以填写当前收据服务已经验证可用的 Gemini 模型名称。密钥不放入 iOS 工程。
4. 安装包含此次源代码变更的新 iOS 构建。在「设置 → AI 功能」开启「AI 自动分类」，在记账表单的描述或物品名称输入 `洗衣液`／`午餐`，观察分类建议。

分类每日 100 次上限；收据逐行分类每行计一次。未部署、未登录、离线或额度用尽时不会阻止手动记账。分类开关默认关闭；开启前页面显示发送范围。

已有部署只需更新 `assistant-gemini/handler.mjs`。不要删除该函数、`GEMINI_ASSISTANT_MODEL` 或额度 SQL，它们仍供自动分类使用。银行通知与收据函数无需为此次移除操作重新部署。此前 Gemini 超时问题尚未确认解决，移除两个功能不代表分类请求的超时已修复。

## 验证与当前边界

- 后端：`node --test backend/tests/receipt-gemini.test.mjs backend/tests/bank-notification-gemini.test.mjs backend/tests/assistant-gemini.test.mjs`。
- iOS 单元测试包含物品分类、个人归属、分摊后逐分守恒和超限拒绝；需 macOS/Xcode 执行。Windows 仅执行工程检查和 Swift 语法解析，不代表原生编译通过。
- 真机检查：快速连续改描述、请求中手动选分类／删除物品／退出表单／切换账号，迟到结果不应覆盖新输入。离线可保存；开启后无文字不发送请求。
- AI 可能建议错误分类，保存前仍可修改。
- 当前没有从此环境部署远端函数，也未打包或安装新 iOS 版本。
