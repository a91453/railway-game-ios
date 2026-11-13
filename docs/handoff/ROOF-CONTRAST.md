# ROOF-CONTRAST：屋頂對地面的明度檢查與現有模型的盤點

- 派工：MAP-LIVELY 那一組的 session（作者 2026-11-13：3D 地圖「看起來蠻死氣的」），接 #2127。
- session：作者 Mac 的本機 session。分支 `claude/roof-ground-contrast`（疊在 `claude/map-liveliness` 上）。
- 決策、存檔版本、golden schema：不動。`Map3DPalette`、`Map3DLook`、所有模型的配方：沒動。

## 做了什麼

- `Tests/GamePresentationTests/Map3DRoofContrastTests.swift`：模型從正上方看，屋頂對四周的明度差（ΔL*）低於 12 而且屋頂外緣也沒有夠深的邊就不過；量的是 `Map3DLook` 淡化後地圖畫的顏色。現有不過的 59 個列在 `known`（新的不過就紅，名單裡的過了也紅）。
- `tools/model-look/shoot.mjs`：`--only map`、`--ground`。
- `docs/art/roof-ground-contrast-2026-11-13/README.md`：查證（哪一類模型被淡化）、量法、A 與選項 C 兩種地面下各門檻的不過數、每個車站站房與地標的盤點表與建議、還有哪裡不好。

## 還留下什麼（都等作者決定）

1. **門檻的數字**（先提 12）與**地面選哪一個**（#2127 的 A／B／C／D）。選 C 的話不過的從 59 變 69，測試裡的地面要跟著換（`RoofContrast.groundNow`，以及套件站房四周的鋪面若也改色）。
2. **要改哪些模型**：README 第 5 節的順序。最大的一項是「套件站房改成不淡化」（程式一處，275 站的樣子會變）；其次是灰鐵皮小站 26 站、高鐵的白屋頂、真的白的建築加深色的邊。每改好一個，把它從 `known` 拿掉。
3. **量法的缺口**：只量明度（黃琉璃瓦、藍鐵皮被誤判）、高於 2 m 就算屋頂（塔樓、基座、橋被誤判）、整個模型取一個中位數、遠景方塊沒有進測試、房地產等套件與擴建後的站房沒有量。README 第 6 節。

## UNVERIFIED

- 沒有在實機或 `tools/map3d-preview` 看；圖是 `shoot.mjs` 的畫法。
- 選項 C 的數字是用鋪面一種顏色估的，C 還沒有實作。
- Linux 的 CI 沒有在本機跑；本機（macOS，Swift 6.4.2）跑過 `Map3DRoofContrastTests`。

## 後來：決策 722（2026-11-13）

作者看過預覽後說「用 close」。`Map3DStations.addHouse` 把套件站房刷 `Map3DStationKit.houseLook`（= `Map3DLook.close`），放進 `ownColourNear`／`ownColourFar`；分支也併進了決策 720。已知清單 59 → 44。報告 §5.2、§5.3，決策在 `docs/decisions/722.md`。

- VERIFIED（本機）：`swift build --build-tests -Xswiftc -warnings-as-errors`；`Map3DRoofContrastTests`、`Map3DStationsTests`、`Map3DStationExteriorsTests`、`Map3DStationExteriorBatch2MapTests`、`Map3DLookTests`、`Map3DSceneMemoryTests`、`Map3DFootprintsTests` 與車站相關的十幾個場景測試；`tools/map3d-preview` 重新輸出的場景裡屋頂是 `close` 的顏色。
- UNVERIFIED：其餘 GamePresentation 測試（留給 CI）；實機 Metal；夜晚、雨天；拉遠後遠景方塊的樣子。
- 還沒做：灰鐵皮 26 站與白色大屋頂 18 站（配方的顏色）；報告 §1–§4 的表是改之前的數字。
