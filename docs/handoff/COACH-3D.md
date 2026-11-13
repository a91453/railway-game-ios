# COACH-3D：3D 地圖的長途客運與客運站

- 派工單：COACH-3D（2026-11-13，Mac 本機 session，遊戲規劃第 64 任派；#1579 的派工單留言），分支 `claude/coach-3d`。
- 決策：[708](../decisions/708.md)（做法、參考比對、五個角度、沒選的、限制都在那裡）。
- 存檔版本、golden、SaveFixtures、ReplayFixtures、`Sources/GameCore/`：不動。
- 看圖：`docs/art/coach-3d-2026-11-13/README.md`（三輪、遊戲裡的截圖、還有哪裡不好）。

## 做了什麼

1. `Sources/GamePresentation/Map3DCoaches.swift`：路線接到場景車道、照班表算位置、每格放車與站；`Map3DCoachStop` 是路邊客運站的模型（近、遠）。
2. `Map3DModelPack.standard` 在飛機之後、路線公車之前多 16 個模型（7 款塗裝的近、遠，站的近、遠）。
3. `Map3DTrainFeed`（`Map3DPreviewScreen.swift`）每格加客運；路線檔與鋪路線都在背景。
4. `WhatsNew` 加了 129 的一行（`2026-11-13-129`）。**如果 129 先發、這個 PR 沒趕上，合併前把這一行搬到下一版的條目。**
5. `tools/model-look/export-coaches.sh`：把站與車匯出成 `.m3dmodel` 給 `shoot.mjs` 拍。

## 還留下什麼

- **存檔 B 開 3D 前後的三角形與記憶體沒有量**（UNVERIFIED；沒有那個存檔）。有存檔的 session 用畫面右上的效能數字，比 main 與這個分支即可。
- 實機沒有看過（派工單說不要用實機）；夜景沒有看過。
- 決策 708 第 6 節的限制：整棟轉運站、站清場與影子、站名膠囊與點選、場景範圍外的客運、台北轉運站的車停在高架上。
- 模型包的雜湊是 Linux 的（Mac 差在正弦的最後一位），`Map3DModelPackLockTests` 與 `tools/train-models/hashes.lock.json` 的新值取自 CI 的輸出。
