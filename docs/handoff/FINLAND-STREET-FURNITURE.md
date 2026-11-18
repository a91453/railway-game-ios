# FINLAND-STREET-FURNITURE（羅瓦涅米換芬蘭街道設施）

## 進度

- 做到哪：兩張都做完。第一張 #2436（程式端：圓環不放號誌、路邊立柱號誌、行人燈不倒數、芬蘭不放電線桿與販賣機，決策 846）已合。第二張把本地工作室的芬蘭款接進遊戲（決策 846「後來」）：號誌、行人燈、路燈、公車站牌、行人穿越道標誌共 10 個模型（`Map3DFinlandStreet`），換掉暫借的香港／台灣款。
- 已驗證：Linux 本機 `swift build --build-tests -Xswiftc -warnings-as-errors`；`Map3DFinlandStreetTests`、`Map3DRoundaboutTests`、`Map3DModelPackLockTests`、`Map3DModelPackSizeTests`、`Map3DModelTests`、`Map3DWinterLightsTests`、`Map3DTaiwanCarsTests`、`Map3DModelCatalogTests`、`Map3DPedestrianSignalTests`、`Map3DSignalTimingTests`、`Map3DStreetStopTests` 全過。
- 模型來源：`a91453/railway-assets-private-2` `game-art-previews/docs/art/finland-street-furniture-2026-11/revision-3/`（工作室審過的 commit `02cfda25`）。重轉：`python3 -I tools/train-models/glb_to_swift.py --enum Map3DFinlandStreet --materials steel,tankSteel,dark,red_lit,red_unlit,amber_lit,amber_unlit,green_lit,green_unlit,lamp_lit,signBlue,signWhite --out Sources/GamePresentation/Map3DFinlandStreetMesh.swift <十個 GLB，順序同 Map3DFinlandStreet.Unit>`。

## 還留下

- `docs/priorities/FINLAND-STREET-FURNITURE.md`：圓環讓路線、路名牌、玻璃候車亭、雙臂路燈（都未派）。
- UNVERIFIED：iOS 實機與 Simulator 的畫面（只有 WebGL 預覽）。
- 加一個新模型到模型包時，會數模型順序與大小的測試不只 `Map3DModelPackLockTests`：還有 `Map3DModelPackSizeTests`、`Map3DWinterLightsTests.testThePackHoldsTheModels`、`Map3DTaiwanCarsTests`、`Map3DModelTests`（#2436 第一次 CI 就紅在前三個）。
