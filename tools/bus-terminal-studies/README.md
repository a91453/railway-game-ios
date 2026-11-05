# 國道客運站 3D studies

`python3 tools/bus-terminal-studies/produce.py ../railway-assets-private/game-art-previews/docs/art/bus-terminal-2026-11` 產生封閉公尺制 M3DM 與接點 manifest；`node tools/bus-terminal-studies/render.mjs <同一目錄>` 轉 GLB、日夜七方向透明 PNG、離線 `viewer.html` 及自檢圖；`python3 tools/bus-terminal-studies/verify.py <同一目錄>` 驗證檔案與接點。此配方不載入遊戲營運或常駐模型。`-near` 與 `-far` 各一個資料夾；重新執行只覆寫最新檔。

每個格位的 `front` 是車頭預定位置，`heading` 為單位向量，`usable_length` 為公尺。入口與出口在地面 0。對外一律 x 前、y 左、z 上。8 m 雨棚與 4 m 網格只是組裝規格。組景的三輛車是 13.19 × 2.5 m、含鏡 3.16 m 的比例代理，供觀察停車與轉彎；沒有移植車輛原模型。
