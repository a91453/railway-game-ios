# glTF 檢查（決策 467）

用 Khronos 的官方 glTF Validator（npm `gltf-validator` 2.0.0-dev.3.10，Apache-2.0，版本釘在 `package.json` 與 `package-lock.json`）檢查 repo 裡所有 `.glb`、`.gltf`，或指定的檔案。

```sh
# 從 repo 根目錄；Node 22
(cd tools/gltf-validate && npm ci --ignore-scripts)
node tools/gltf-validate/validate.mjs                 # repo 裡全部（git ls-files）
node tools/gltf-validate/validate.mjs some/model.glb  # 只查這些
```

- 有錯誤（severity 0）就失敗；警告與提示只列數字。
- 照原樣保留的檔案已知的錯誤記在 `known.json`（每個寫明為什麼留著）；同一檔出現別種錯誤、或其他檔有錯，照樣失敗。
- CI：`.github/workflows/gltf-validate.yml`，Linux，只在 GLB／glTF、`tools/glb-to-m3dmodel/`、`tools/kenney-props/` 或這個資料夾改動時跑，和 Swift 的工作並行。2026-10-28 在 Linux 量 35 個檔 0.6 秒；超過 2 分鐘就拿掉 CI 改回本機檢查（決策 467）。
- 素材庫的 Meshy 原件（`a91453/railway-assets-private` 的 `meshy-batch-2026-10/glb-hq/`）不在這個 repo，接進遊戲前在本機用第二種寫法查（決策 467 查過 `mailbox-green`、`bus-stop-pole`：0 錯誤 0 警告）。
