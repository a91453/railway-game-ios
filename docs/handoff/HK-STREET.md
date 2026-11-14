# HK-STREET：香港地圖換成香港的交通與街景

- 派工：遊戲規劃第 65 任的工作串「讓香港換成在地交通與街景」（雲端 thread session），分支 `claude/project-thread-qsj3v1`。作者 2026-11-14 看過盤點報告說「都行」，順序照五方分數排。
- 盤點報告（Claude Doc）：https://claude.ai/artifact/F9m1FJ4pL4iJDyJSUSobmu ，每一項都有程式位置。
- 這個 PR 做的是第 1、2 張：街景地區開關、靠左行、香港號誌與行人燈。[決策 732](../decisions/732.md)。存檔版本、golden、GameCore 不動。

## 還沒做的（照五方分數）

作者 2026-11-14 說今天合完開著的 PR 就收，下面第 2、3 項（盤點的第 3、4 張）沒有派，留給之後的 session。

1. **HK-STREET-2 車種與街上小物**：大部分已做（[決策 743](../decisions/743.md)，同一個 PR）：雙層巴士、紅綠頂小巴、三色計程車、機車減少、垃圾車與台灣郵筒不出現。還沒做：計程車按地區分色、香港綠色郵筒、電線桿。原本的單：雙層巴士、紅綠小巴、計程車（市區紅、新界綠、大嶼山藍）；機車大幅減少、拿掉騎樓下停的那排（`Map3DScooters`、`Map3DStreetLife` 的機車比例）；垃圾車（`Map3DGarbageTruck`）、電線桿（`Map3DProps.pole`）、台灣紅綠郵筒（`Map3DSceneryProps.postBoxes`）在香港不放或換。車輛模型可從私有參考庫 `Railway/street_scene_reference_clean/source/models/street-agents.glb` 走 `tools/glb-to-m3dmodel` 轉。每個判斷都用 `Map3DStreetRegion`（`Map3DStreetLife.region`、`Map3DRoadMarkings.region`、`Map3DStreetRegion(world:)`）。
2. **HK-STREET-3 建物外觀**：`Map3DRealBuildings` 的屋頂雜物（藍水塔、鐵皮頂樓加蓋）、`Map3DRealFacade` 的鐵窗與騎樓比例、招牌改橫伸、`Map3DFrontage` 補位房子改新界村屋、廟改嶺南屋頂。照 `model-look` 拍圖比照片三輪。
3. **標線**：香港有燈號的過路處畫法（記得是兩條虛線，斑馬線配黃黑燈柱）、雙白線、黃色雙線，要先找到運輸署《道路使用者守則》標線那章核對。這次照舊畫斑馬線。

## UNVERIFIED

- 雲端裝不了 Swift（swift.org 下載 403），本機沒有建置與測試；編譯、測試與 `hashes.lock.json` 的四個新模型雜湊交給 CI（Linux）。
- 沒有在裝置上看過；截圖在 PR 裡另說。
