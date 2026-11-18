# PLATFORM-FURNITURE（2026-11-18）

工作串「統一三種月台的家具」，分支 `claude/project-thread-u8jr0c`，決策 874。GameCore、存檔版本、golden 不動。

## 做了什麼

- 決策 860 放在地下島式月台的舊版月台家具（長椅、販賣機、海報看板、吊牌），照同一張零件表放到平面、高架與地下側式月台，
  所有地圖共用（`Map3DPlatformProps.furniture`，在 `addPlatformProps` 裡畫，只在最近的細節層）。
- 每座月台放模組面向自己軌道的那一半、靠背面；避開垃圾桶與雨棚柱；吊牌只掛在雨棚下；方柱不放。
- 一座 200 m 月台最近層多約 600 個三角形（640 → 1,252，上限 2,500）。

## 還留下什麼

- 評分在 `a91453/railway-assets-private-2` `docs/priorities/PLATFORM-FURNITURE.md`：月台站名牌、販賣機細節、
  舊版側式／高架月台模組的欄杆與懸臂雨棚、乘客坐長椅。都未派。
- 加新的月台小物時：位置規則寫在 `Map3DPlatformProps`（純函式、有測試），零件尺寸寫在 `Map3DOldIslandModule.parts`。

## UNVERIFIED

- 沒在 App、模擬器或實機看過。下一版 TestFlight 請在一個平面站、一個高架站各跟車進站看一眼：
  長椅與販賣機的大小、吊牌在雨棚下的高度、有沒有和月台上的人或月台門重疊；淡水信義線高架站（有外殼）只該有長椅、販賣機、看板。
