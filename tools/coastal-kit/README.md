# CoastalKit 建置

24 種新素材＋4 組景，沿用 CivicKit 匯出流程與 StationKitBuilder／GLB 編碼／renderer。公開配方不含私有來源工廠、貼圖或品牌。先讀 [skill](../../.claude/skills/coastal-kit/SKILL.md)。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/coastal-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/coastal-kit-2026-10-23
```

需要既有 Node、Python3＋Pillow、Playwright、Chromium；不下載依賴。CHROMIUM_PATH 可指定既有瀏覽器。只執行涉及測試，完整suite交CI。輸出目錄須在公開checkout外。

- export：Swift6.4 warnings-as-errors，以遊戲 loader 逐頂點讀回全部 native，既有 station-kit/package.mjs 產生同源 GLB。
- render：七向384px透明PNG、三分類、全部素材、四組景、方向、下斜視與四底色／小尺寸／模糊／灰階。快取須native＋renderer＋全部PNG SHA一致。
- verify：完整重編GLB、SHA、預算與全部PNG RGBA解碼／可見邊界；browser-check 驗證分類／中文搜尋／28模型／旋轉縮放／四底色／下載與390px。
- 手動：實際打開預覽圖；更新私庫來源SHA／尺寸／改造與人工檢查紀錄。rebuild不會把「人工看過」自動標成VERIFIED。

API：Map3DCoastalKit.model(for: Part/Example)、Part.connectors、placements(for:)、Map3DModelPack(coastalKit:)；native座標 x前/y左/z上。岸置底z=0；水線、桌面與拖架接點詳見skill。manifest內含場景的同源placements。

大型成品只放私庫。這是靜態可選素材，未註冊進standard或地圖；原生／WebGL驗證不能代替iPhone Metal或效能驗證。
