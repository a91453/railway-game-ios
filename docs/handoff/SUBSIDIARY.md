# SUBSIDIARY：子公司買賣第 ②–④ 步

- 派工：遊戲規劃第 65 任（NEXT_PRIORITIES §29.4 第 2 項），雲端 thread session，分支 `claude/project-thread-d7kssy`，登記 #2118。設計：[`research/SUBSIDIARY_DESIGN_2026-11-11.md`](../research/SUBSIDIARY_DESIGN_2026-11-11.md)；第 ① 步是決策 692。
- 2026-11-13 做完：
  - 第 ②（鄰地行情）：#2160，決策 727，已合併。
  - 第 ③（產業互相影響表）：#2161，決策 728，已合併。
  - 兩步都沒升存檔、沒動 golden schema；golden 的值逐值說明在各自的決策。
- **UNVERIFIED**：本機建置（雲端抓不到 download.swift.org，全靠 CI）；兩步的平衡報告都是 **NOT ASSESSED — NO DATA**，指令在決策 727、728 的「平衡」一節，要在 Mac 上 main 與合併後各跑一次。
- **還留下的**：
  1. 第 ④ 步（工廠、休閒農場、公寓大樓三種新建物）**沒開工**。它要升存檔（新的 `PlacedBuildingKind`，同決策 173、684 的做法）、加一份 `SaveFixtures/` 新版本的存檔（要實際跑 Swift 產生）、三個地圖圖示與三個 3D 建物（決策 482 最高一級，規劃看過總覽圖才合）、選單與 String Catalog。雲端沒有 Swift 產不了存檔 fixture，也拍不了圖，建議在作者的 Mac 上做；規則面（表上工業、農業兩列）在決策 728 已經寫好，有那兩種建物就生效。
  2. 決策 728「下一步」2：建造預覽標出「會帶動附近的哪幾類」（第一級，現有畫面多一列）。
  3. 決策 728「下一步」3：公司建物很多時，各用途中心的線性查找要照列分桶；沒量過。
