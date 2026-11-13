# CITY-TITLE-2：城市稱號的觀光類型改看景點遊客

- 派工：遊戲規劃第 65 任（作者 2026-11-13「照分數的清單 還沒要做嗎」）；雲端 thread session（session_01YGNNupCyZQfWMnSho2E7ef），分支 `claude/project-thread-goldpj`。
- 決策：沿用 [決策 683](../decisions/683.md)，加「後來：觀光類型看景點的遊客」一節，不取新號。存檔版本、golden、fixtures、GameCore 不動。
- 做了：`CityTitle` 的類型多一條：鐵道每天載到景點的遊客每千居民達 40 人就是「以觀光為主」；面板說明多一句。測試 `CityTitleTests` 加三個。
- 還留下（決策 683「下一步」）：
  - 成就：要作者在 App Store Connect 加 Game Center 成就，等作者說。
  - 徽章與升級卡片：要畫新圖、美術審，給 Mac。
  - 外國地圖的類型基準：香港目前沒有工作資料，只顯示規模；香港有工作資料時再做。
  - 類型的資料（高雄、新竹）：`LandImport`，另一張單。
  - 真實地圖上什麼服務程度會變成觀光類型沒有量過；之後的健檢可以開車跑一年看看（例如平溪線、集集線一帶的地圖）。
- UNVERIFIED：本機沒有 Swift（雲端擋 download.swift.org），建置與測試只靠 CI；實機畫面沒看過。說明文字變長一句，屬既有面板的文字改動（決策 482 不用截圖）。
