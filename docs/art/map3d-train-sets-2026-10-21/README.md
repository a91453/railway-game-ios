# 3D 地圖補上方塊列車的模型（決策 318）

- `boxes-before-after.jpg`：左欄由上往下看，右欄斜看機車。**上半是 `main`**（這幾種列車近看還是方塊，最上面一列是一般通勤車），**下半是這個 PR**。由上往下的列：通勤車、莒光號 E200、E500、R100、R200 牽引、藍皮（R135）、推拉式自強號（E1000）、普悠瑪、太魯閣、EMU800，畫面外再往下是柴油客車（DR1000、DR3100）。這張的 EMU800 是第三版的藍色車頭，現在改回 #900 的樣子（`fronts.jpg`）。
- `fronts.jpg`：每一套的頭車從車頭斜前方看（上排機車：E200、E500、R100、R200、R135、E1000；下排：普悠瑪、太魯閣、EMU800、DR1000、DR3100、莒光號最後一節）。機車的斜度、切角與配色和車庫模型（私有庫 `garage-blender-v1/*.webp`）並排比過；有弧度的電聯車與柴油客車是 #900 的車頭（作者 2026-10-21）。
- `fronts-900-emu3000-hsr-metro.jpg`：**上排是這個 PR**，下排是 `main`（決策 230 的車頭）。由左到右：EMU3000、普悠瑪、太魯閣、700T、C381（藍線）、C381（紅線）、文湖線（棕線）、700T 的集電弓車。上排是 #900 的車（作者 2026-10-21 看了 #900 的 EMU3000、700T、C381 說舊的醜）；捷運的飾帶是路線色。
- `fronts-flat-ends.jpg`：沒有選的第三版，EMU800 藍色車頭、DR1000／DR3100 平的黃色車端（下排第 3–5 台）。
- `scene-kit-transport.jpg`：#900 的交通工具總覽（原圖 2/3 大小）。這次用到其中的台鐵現代、台鐵經典兩組列車做法。

**機車**不是生成的：照私有庫 `Simulator/reference_snapshot/models/tra-e201/tra-e201.glb` 與車庫 `garage-blender-v1` 的比例、零件與原塗裝，用方塊重新組成（`Sources/GamePresentation/Map3DTrainLocomotives.swift`）。

**AI 生成的素材**（電聯車、柴油客車與客車）：這些列車的外型來自 #900 的「原生程序化模型」：先用圖片生成工具（`image_gen`）畫出素材表（`docs/art/generated-2026-10-21-scene-kit/manifest.json` 記下每一張的座標、描述與 SHA-256），再照圖片寫成 Swift 的方塊、圓角與車窗做法（`Sources/GamePresentation/Map3DSceneKit*.swift`）。App 裡沒有任何一張生成的圖片或 GLB，只有程式在啟動時蓋出的頂點色模型。素材表、七方向圖與 GLB 在私有參考庫 `Railway/generated-3d-assets-2026-10-21/scene-kit-pr900/`。

預覽怎麼做：`tools/map3d-preview` 的 `MAP3D_TRAINS=0:0`（README）；上半的方塊是在預覽的 Swift 檔裡暫時把每節車畫成 `Map3DTrains` 的方塊，沒有提交。
