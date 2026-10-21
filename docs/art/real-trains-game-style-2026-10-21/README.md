# 台灣真實鐵路車款與場景模組遊戲風格概念圖與 3D SVG 素材包（2026-10-21）

本批收錄台灣四大軌道系統（高鐵、台鐵、捷運、輕軌）代表性車款與可組合之車站、月台、道岔、平交道、色燈號誌、台灣透天厝騎樓街屋與站前百貨商場之視覺資產，遵循 `art-style` 與決策 168、169、230、243、252 規範。

- **離線檢視頁**：[`index.html`](index.html)（含 18 款等角 3D SVG、14 款原圖輪廓描繪 SVG、120／64／44／28 點深淺底與灰階檢查）
- **預覽總表**：[`previews/3d-svg-sheet.png`](previews/3d-svg-sheet.png)

![等角 3D SVG 與描圖 SVG 預覽總表](previews/3d-svg-sheet.png)

---

## 一、兩種 3D SVG 實作方案比較

| 方案 | 目錄 | 作法 | 優點與適用場景 |
| --- | --- | --- | --- |
| **A. 等角幾何 3D SVG（推薦入 App 面板／圖卡）** | [`svg/`](svg/)（共 18 款） | 以統一等角投影（`u, v, z` 軸向）、粗藏青外框（`#262C57`, `stroke-width="2.5"`）與 `UI_THEME`／`TrainLivery` 純色塊直接建構；只用 Xcode Asset Catalog 支援的 `svg, rect, circle, path` 與大寫 `M L Q Z` | 線條銳利無鋸齒、檔案極小（2–7 KB），在 120／64／44／28 點與深淺底皆清晰可辨，且補齊平交道、色燈號誌、透天厝騎樓與站前商場 4 款場景組件 |
| **B. 原圖分層描繪 SVG（照 `art-style` §3 流程）** | [`svg-traced/`](svg-traced/)（共 14 款） | 將 14 張微縮模型原圖放大至 `240x240`、前景連通域去背、外擴 `#262C57` 藏青外框、依車款色票分層高斯模糊後取 `0.5` 等高線（Marching Squares + Douglas-Peucker），輸出 `fill-rule="evenodd"` 的 `M … L … Z` 折線 | 完整保留 AI 微縮場景的豐富光影輪廓與細節層次，適合大尺寸（120 點以上）海報、插圖或空狀態展示 |

---

## 二、車輛素材清單（10 款）

| 類別 | 幾何 3D SVG | 描圖 SVG | 原圖 JPG | 車款名稱與特色 | 對應程式碼常數 |
| --- | --- | --- | --- | --- | --- |
| **高鐵** | [`svg/thsr-700t.svg`](svg/thsr-700t.svg) | [`svg-traced/thsr-700t.svg`](svg-traced/thsr-700t.svg) | `thsr-700t.jpg` | **台灣高鐵 700T / N700ST**：9m 流線鴨嘴鼻、白底配高鐵橘＋藏青雙腰帶、高架無碴軌道 | `TrainType.highSpeed`, `TrainLivery.highSpeed` |
| **台鐵特快** | [`svg/tra-emu3000.svg`](svg/tra-emu3000.svg) | [`svg-traced/tra-emu3000.svg`](svg-traced/tra-emu3000.svg) | `tra-emu3000.jpg` | **台鐵 EMU3000 新自強號**：日立極簡白車身、一體式黑色座艙面罩、酒紅細門飾帶 | `TrainType.emu3000`, `TrainLivery.emu3000` |
| **台鐵特快** | [`svg/tra-puyuma.svg`](svg/tra-puyuma.svg) | [`svg-traced/tra-puyuma.svg`](svg-traced/tra-puyuma.svg) | `tra-puyuma.jpg` | **台鐵 TEMU2000 普悠瑪號**：傾斜式電聯車、經典紅白疾速飄帶、圓潤流線鼻頭 | `TrainPerformanceSpec.puyuma`, `TrainLivery.puyuma` |
| **台鐵通勤** | [`svg/tra-emu900.svg`](svg/tra-emu900.svg) | [`svg-traced/tra-emu900.svg`](svg-traced/tra-emu900.svg) | `tra-emu900.jpg` | **台鐵 EMU900 最美區間車**：現代科技黑面罩配螢光綠腰帶、雙線會車 | `TrainPerformanceSpec.emu800`, `TrainLivery.emu800` |
| **台鐵通勤** | [`svg/tra-emu800.svg`](svg/tra-emu800.svg) | [`svg-traced/tra-emu800.svg`](svg-traced/tra-emu800.svg) | `tra-emu800.jpg` | **台鐵 EMU800 微笑號區間車**：不鏽鋼銀灰車身、寶藍車頭罩、亮黃微笑曲線 | `TrainPerformanceSpec.emu800`, `TrainLivery.emu800` |
| **台鐵經典** | [`svg/tra-chukuang.svg`](svg/tra-chukuang.svg) | [`svg-traced/tra-chukuang.svg`](svg-traced/tra-chukuang.svg) | `tra-chukuang.jpg` | **台鐵 經典莒光號**：R100 柴電機車（橘白 V 紋）牽引橘白雙色莒光號客車 | `TrainType.r100ChuKuang`, `TrainLivery.chuKuangCoach` |
| **台鐵觀光** | [`svg/tra-blue-train.svg`](svg/tra-blue-train.svg) | [`svg-traced/tra-blue-train.svg`](svg-traced/tra-blue-train.svg) | `tra-blue-train.jpg` | **台鐵 藍皮解憂號**：復古海軍藍塗裝、白線腰帶、海岸懸崖微縮站景 | `TrainTypeCatalog` `code: "BLUE"`, `TrainLivery.blueTrain` |
| **捷運高運量** | [`svg/taipei-mrt-c381.svg`](svg/taipei-mrt-c381.svg) | [`svg-traced/taipei-mrt-c381.svg`](svg-traced/taipei-mrt-c381.svg) | `taipei-mrt-c381.jpg` | **台北捷運 C381 高運量（板南線）**：不鏽鋼車體、藍色腰帶、第三軌高架月台 | `TrainPerformanceSpec.metroC381`, `TrainLivery.metroC381` |
| **捷運中運量** | [`svg/mrt-wenhu.svg`](svg/mrt-wenhu.svg) | [`svg-traced/mrt-wenhu.svg`](svg-traced/mrt-wenhu.svg) | `mrt-wenhu.jpg` | **台北捷運文湖線 中運量**：雙節純白車身配棕色腰帶、高架水泥導向樑與橋下綠樹 | `TrainTypeCatalog` `code: "APM"` |
| **輕軌** | [`svg/lrt-kaohsiung.svg`](svg/lrt-kaohsiung.svg) | [`svg-traced/lrt-kaohsiung.svg`](svg-traced/lrt-kaohsiung.svg) | `lrt-kaohsiung.jpg` | **高雄輕軌電聯車（KLRT）**：綠白低底盤關節式電車、植草綠地軌道與花樹候車亭 | `TrainFamily.metro` |

---

## 三、車站、月台、軌道號誌與街景建築清單（8 款）

| 類別 | 幾何 3D SVG | 描圖 SVG | 原圖 JPG | 組件名稱與遊戲場景用途 |
| --- | --- | --- | --- | --- |
| **經典車站** | [`svg/station-classic-tra.svg`](svg/station-classic-tra.svg) | [`svg-traced/station-classic-tra.svg`](svg-traced/station-classic-tra.svg) | `station-classic-tra.jpg` | **台鐵小鎮經典木造/磚瓦老站房**：斜瓦屋頂、門廊掛鐘、站前廣場電話亭與月台 |
| **現代車站** | [`svg/station-elevated-mrt.svg`](svg/station-elevated-mrt.svg) | [`svg-traced/station-elevated-mrt.svg`](svg-traced/station-elevated-mrt.svg) | `station-elevated-mrt.jpg` | **現代都會高架捷運/高鐵車站**：透明鋼拱天棚、高架雙向月台、玻璃電梯塔與穿堂層 |
| **月台模組** | [`svg/platform-island-tra.svg`](svg/platform-island-tra.svg) | [`svg-traced/platform-island-tra.svg`](svg-traced/platform-island-tra.svg) | `platform-island-tra.jpg` | **台鐵標準島式月台模組**：水泥雨棚、黃色警戒盲道、雙語站名里程燈箱與天橋樓梯 |
| **道岔模組** | [`svg/track-crossover-switch.svg`](svg/track-crossover-switch.svg) | [`svg-traced/track-crossover-switch.svg`](svg-traced/track-crossover-switch.svg) | `track-crossover-switch.jpg` | **雙線菱形交叉道岔轉轍器模組**：道碴基床、菱形交叉軌、紅綠轉轍拉桿與信號燈 |
| **平交道** | [`svg/rail-level-crossing.svg`](svg/rail-level-crossing.svg) | — | — | **台鐵平交道與遮斷機**：黃黑斜紋升降遮斷桿、雙閃紅燈號誌與公路鐵路交會路面 |
| **鐵路號誌** | [`svg/rail-signal-mast.svg`](svg/rail-signal-mast.svg) | — | — | **鐵路三燈色燈號誌機與電驛箱**：紅黃綠高柱色燈號誌、道旁銀灰電驛箱與 ATS 地上感應子 |
| **住宅街屋** | [`svg/town-shophouse-arcade.svg`](svg/town-shophouse-arcade.svg) | — | — | **台灣連棟透天厝騎樓街屋**：暖黃與紅磚連棟街屋、一樓騎樓遮雨棚、直立招牌與頂樓鐵皮加蓋 |
| **商業百貨** | [`svg/town-commercial-mall.svg`](svg/town-commercial-mall.svg) | — | — | **現代站前商業百貨大樓**：暖黃商場裙樓、玻璃帷幕高樓塔身與頂樓冠冕招牌 |
