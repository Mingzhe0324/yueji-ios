# 店铺地点：Apple 资料与 Google Maps 链接

本实现不调用 Google Places API 或 Maps Static API，不需要 Google API Key 或新增 Supabase 函数。

## 查看地点

- 优先使用已保存的 Apple 店铺标识；没有标识时，用店名、地址与坐标匹配店铺。
- 有坐标时显示地图；没有坐标时不显示无关的区域地图。匹配不唯一时，由用户选择正确分店。
- 查看模式获得店铺标识后自动打开 Apple 原生资料页（iOS 18+），照片由 Apple 决定是否提供；编辑模式保留手动打开按钮。
- Apple 照片不会被提取到月记自制卡片，也无法判断店铺是否有照片。
- “去 Google Maps 看照片”按钮按店名和地址打开 Google Maps 搜索；照片取决于 Google 收录情况。不会自动跳出月记。
- 查看和匹配结果仅作预览，不会自动修改原账目地点。

## 部署

需重新构建并安装 iOS App，无需部署 Supabase。
如果之前部署了旧 Google 功能，可自行清理不再使用的 `google-places` Edge Function、`GOOGLE_PLACES_API_KEY` 和 `GOOGLE_MAPS_STATIC_API_KEY` Secrets。本次更新不会删除远端资源。
