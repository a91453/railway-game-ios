# FINLAND-STREET-FURNITURE（羅瓦涅米換芬蘭街道設施）

## 進度

- 做到哪：第一張（程式端）PR 開了：圓環不放號誌、芬蘭用路邊立柱號誌、行人燈沒有倒數盒、芬蘭不放電線桿與販賣機（決策 846）。
- 已驗證：Linux 本機 `swift build --build-tests -Xswiftc -warnings-as-errors`；`Map3DRoundaboutTests`（8）、`Map3DModelPackLockTests`、`Map3DModelTests`、`Map3DPedestrianSignalTests`、`Map3DStreetRegionTests`、`Map3DRegionLookTests`、`Map3DRoadMarkingTests`、`Map3DStreetStopTests` 等全過。羅瓦涅米 5 km：16 個圓環，號誌 363 → 192。
- 下一步：工作室做芬蘭款模型（派工單 railway-assets-private-2 `game-art-previews/docs/art/finland-street-furniture-2026-11/BRIEF.md`），回來另開 PR 換進遊戲。

## 還留下

- 決策 846「下一步」與 `docs/priorities/FINLAND-STREET-FURNITURE.md`。
- UNVERIFIED：iOS 實機與 Simulator 的畫面（只有 WebGL 預覽）。
