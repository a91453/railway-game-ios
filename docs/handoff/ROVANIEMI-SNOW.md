# ROVANIEMI-SNOW

- 派工：協調者（新專案），2026-11-18，總表功能第 1 名（§29.11 F 3.75）。Session：session_01YGNNumiBtgVaEHAmMea4QD（雲端）。分支 `claude/project-thread-pgp3c2`。決策 [833](../decisions/833.md)。
- 存檔、golden、SaveFixtures、ReplayFixtures、GameCore：不動。

## 做了什麼

北方地圖（`Map3DRegionLook.snow`，羅瓦涅米）上：樹帶雪（`Map3DSnowTrees`：針葉 45%、闊葉 62%、灌木 75% 往雪白）、河湖結冰（`Map3DSnowGround.ice`，濕地藍灰、新層 `Map3DVertex.ice` 平塗無波紋，仍算水）、雨天改畫雪花（`Map3DRain(_:snow:)`，沿用雨的 GPU 管線，1,800／1,000／500 片）、雪天的光（`Map3DWeather.snow`，參考 `PRESETS.snow`）。台灣、香港不變。`REGION-LOOK-ROVANIEMI.md` 第 3 項（樹、結冰）到此完成。

## 還留下什麼

評分在 `docs/priorities/ROVANIEMI-SNOW.md`：鏟雪後的路與道床 3.00、車站屋頂與月台積雪 2.85、有深度的雪花 2.30、2D 地圖的雪 2.35。工作室的雪地松樹模型來了，換 `Map3DSnowTrees.shares` 指的模型即可。

## UNVERIFIED

- iOS 建置、Metal 畫面（雪花大小、白天在白地上看不看得到、冰與雪的對比）、實機。羅瓦涅米要下雨的日子才看得到雪花。
- 截圖：雪景屬第三級（新外觀），照作者 11-15「截圖只拍一次、CI 綠就合」；羅瓦涅米的地圖在截圖流程裡沒有入口，這張沒拍。
