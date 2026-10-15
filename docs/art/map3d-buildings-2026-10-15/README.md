# 3D 地圖的程序化建物（2026-10-15）

ARCHITECTURE 決策 235。素材庫 `procedural_assets_reference_clean/` 的 industrial、city、japan 三包產生器，取規則改寫成 Swift：工廠、學校、診所、消防隊、廟、商場，以及屋頂的頂樓加蓋、樓梯間與冷氣主機。

這裡的圖都是軟體算圖：
- 場景從 Swift 輸出（`Map3DScene`，和 App 同一份程式）；
- 用 WebGL 照 `Map3DShaders.metal` 的同一個算式，在 Chromium 裡畫；
- 光線是遊戲的下午兩點；
- 地圖是測試用的兩鎮地圖（`Land.townCentres(seed: 1)`）。

**不是 Metal、不是 iPhone 的畫面**（UNVERIFIED），要等 TestFlight。

## 前後對照（每張上半是 `main`，下半是這一步）

| 圖 | 看什麼 |
| --- | --- |
| `factories.jpg` | 工業區，320 m：藍色鐵皮的雙坡廠房、拱頂倉庫，透天厝屋頂的鐵皮加蓋 |
| `houses.jpg` | 140 m：紅磚老廠與煙囪、廠房前的辦公室；透天厝的加蓋與冷氣 |
| `school.jpg` | 學校：兩棟教室與拱頂體育館 |
| `clinic.jpg` | 診所或機關：石材一樓、白磁磚樓上、屋頂機房 |
| `temple.jpg` | 廟：朱紅牆、兩重翹角屋頂、燕尾脊 |
| `mid.jpg` | 950 m：整個鎮 |

## 兩種配色（`options.jpg`，上排工業區、下排廟）

- **A（選定）**：工廠與加蓋多半是台灣常見的藍色鐵皮；廟是朱紅牆、橘色琉璃瓦、紅燕尾。
- **B**：全部灰色鐵皮；廟用素材庫 japan 包的灰瓦與灰泥牆。

選 A 的理由（四個角度）見決策 235 第 6 點。

## 已知的樣子

- 小塊用地（24 m 左右）的學校擠得放不下操場，廟只有正殿。
- 路邊設施（電線桿、路燈、販賣機、行道樹）還沒有：數量多，要先在 Metal 加實例化繪製。
