# Google 店铺与照片（应用内预览）

入口：账目 → 消费地点 → Google 店铺与照片。输入店名/分店/地区，点击搜索，选择结果后在月记内查看地址和最多三张照片。不需要安装 Google Maps。

这是独立的 Google 内容预览页，无照片时显示 Google 静态地图，不将 Google 内容绘制到 Apple 地图上，也不自动修改账目。原有地点编辑和 Apple 地图继续可用。商场内定位不能确定楼层或唯一店铺，用户需核对分店。无照片或服务失败时显示提示。

## 部署（必须完成后才可联网使用）

1. 在 Google Cloud 项目启用计费，启用 **Places API (New)**，创建服务器 API Key。将 API 限制为 Places API (New)。不要使用 iOS bundle 限制的客户端 key 调用此服务器接口；需要网络限制时须使用固定出口代理，不能随便填写 Supabase 动态 IP。
2. Supabase SQL Editor 执行 `backend/google-places.sql`。每位登录用户每天 UTC 最多 60 次请求，搜索和选店详情各计一次。一次详情最多额外调用三次照片 API；此限制不是 Google 项目总费用上限。
3. Supabase Edge Functions → Secrets 添加 `GOOGLE_PLACES_API_KEY`。密钥只放服务器，不填到 iOS、GitHub 源代码或聊天。
4. 部署 `google-places`，包含 `index.ts` 和完整 `handler.mjs`。CLI 已登录且链接正确项目时运行 `supabase functions deploy google-places`；Dashboard 部署时保持两个文件的名称及 import 一致。
5. 构建并安装新的 iOS App。Supabase 部署不会自动更新旧 App。
6. 在 Google Cloud 配置 API 配额与预算提醒。预算提醒不是硬性费用上限；按当前 Google SKU 与用量计费，不保证免费。搜索请求只拿必要字段、最多五个结果；没有按键自动搜索或自动重试。
7. 发布前在应用的公开隐私政策和使用条款中披露 Google Places 数据处理，并包含 Google 的隐私政策与使用条款。应用搜索前已有传输说明，预览页包含 Google Maps 标识、第三方来源和照片作者链接。

## 数据与验证

仅点击搜索才发送搜索文字和已有账目地点坐标（若有）；不向 Google 发送金额、账户、银行通知或账本。选店时发送 Google Place ID。搜索结果、照片引用、照片仅在当前预览会话内使用，不写入账本、磁盘缓存或云同步。照片由临时 URL 加载，关闭预览后释放。Google 可能没有某间店或照片；不会生成假照片。

后端验证 Supabase 登录身份、拒绝匿名用户、限流、限制输入/上游响应体、限制字段和照片数；不会将 key 或 Google 错误正文返回客户端。

验证：`node --test backend/tests/google-places.test.mjs`。Windows 只能检查 Swift 语法与项目结构；iOS 原生编译和下列真机步骤仍需执行：

- 登录后搜索带分店的店名，检查店名、地址、照片及作者链接。
- 不登录、未配置 key、配额耗尽、断网、无结果、无照片分别有提示。
- 加载中关闭再打开，不能出现上次结果；图片加载失败不阻碍关闭。
- 深色模式、大字体、VoiceOver 检查；搜索前后账本和原地点不变。

官方文档：
- https://developers.google.com/maps/documentation/places/web-service/text-search
- https://developers.google.com/maps/documentation/places/web-service/place-photos
- https://developers.google.com/maps/documentation/places/web-service/policies
- https://developers.google.com/maps/documentation/places/web-service/usage-and-billing

## 店铺卡片与地图回退

搜索结果和详情卡片显示分店地址及「距账目地点」的直线距离（不是实时当前位置或驾车路线；缺少坐标时不显示距离）。真实照片存在时优先显示。无可用照片时，服务请求一张 Google 静态地图，保留整张图及内置归属标识；没有伪造店铺图片。

地图回退需在 Google Cloud 额外启用 **Maps Static API**，创建仅限该 API 的服务器密钥，并在 Supabase Secrets 添加 `GOOGLE_MAPS_STATIC_API_KEY`。随后重新部署 `google-places`。它也需要计费；仅无照片的详情查询额外请求一次地图。未配置或上游失败仍显示店名/地址和查看位置链接，不能凭空显示地图。

静态地图由服务器转为有大小上限的图片数据传给客户端，不泄露 API Key，不存入账本。官方说明：https://developers.google.com/maps/documentation/maps-static/start
