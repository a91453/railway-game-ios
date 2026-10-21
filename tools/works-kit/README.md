# 工程、貨運、動物與自然素材

`tools/works-kit/rebuild.sh PRIVATE_OUTPUT_DIRECTORY` 重建48種素材及4組景。需要 PATH 上 Swift6.4、既有 Node／Python／Playwright／Chromium，不加依賴。輸出必須在公開checkout外。

流程：原生Swift→M3DM v1（loader逐頂點讀回）→既有station-kit GLB編碼→364張七向透明圖→全檔案核對→瀏覽器52模型、分類、七向、旋轉、縮放、下載、390px→warnings-as-errors build與相關測試。

`Map3DWorksKit.model(for:)`／`Map3DModelPack(worksKit:)`按需生成；範例用相同模型組裝。四類各12種，動物有兩個貓姿勢，不代表12個不同物種。靜態GLB沒有機械或動物動畫軌。

檢視輸出：`python3 -m http.server 8080 --directory PRIVATE_OUTPUT_DIRECTORY`，開`http://localhost:8080/index.html`。所有資產在本地，不載入CDN。複用station-kit renderer與native封底形狀，沒有另換引擎。內部與輸出軸的換算見skill，錦鯉要以water connector對水位，貨櫃stack接點對角件頂面。

私有來源factory與改造對照僅保留在私有庫；公開配方是重組後的原生遊戲幾何。素材製作不等於遊戲地圖接入，真機Metal／碰撞／活動件仍需驗證。
