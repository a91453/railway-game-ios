# EMU3000 原生重建與遊戲替換

先讀 [車輛製作手冊](../../docs/art/native-vehicle-modeling/README.md) 與 [本次外觀／重建交接](../../docs/art/emu3000-refresh-2026-10-25/README.md)。本工具只處理這次 EMU3000，不能把其門窗／編組／估計尺寸當通用列車規格。

需求：Swift **6.4**、Node（已安裝的 Playwright／Chromium）、Python NumPy／Pillow、Blender 4.3。沒有新增遊戲或工具依賴。OUT 必須在公開庫外，原始參考只在私有 scratch 閱讀，不能放進公開庫或外部生成服務。

```sh
# 本次真正修改前：在獨立乾淨 worktree 取回來源，而不是倒改新模型。
git worktree add --detach /tmp/emu-before 85d9aa359dfcd6213f76a6559abebd9155806e97
tools/emu3000-refresh/capture-baseline.sh /tmp/emu-before /tmp/emu-baseline

swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DEMU3000Tests|Map3DHighSpeedSetsTests|Map3DTrainSetTests|Map3DModelTests|Map3DModelFileTests|Map3DRealTrainsTests'
# Producer 必須已提交；改了配方／工具就提交新 producer，重新匯出及親自看圖。
PRODUCER_COMMIT=$(git rev-parse HEAD) EMU_BASELINE=/tmp/emu-baseline EMU_FINGERPRINTS=/tmp/emu-current-pack \
  tools/emu3000-refresh/export.sh OUT
node tools/emu3000-refresh/verify.mjs OUT
python3 tools/emu3000-refresh/support-audit.py OUT
python3 tools/emu3000-refresh/coexistence.py /tmp/emu-baseline /tmp/emu-current-pack OUT
node tools/emu3000-refresh/review.mjs OUT
# 親自打開 ED／EP3／完整編組配色、白模、剪影的側／正／上／斜四向；不合格就修幾何。
node tools/emu3000-refresh/render.mjs OUT
blender --background --python tools/emu3000-refresh/glb-audit.py -- OUT
python3 tools/emu3000-refresh/verify-png.py OUT
node tools/emu3000-refresh/standalone.mjs OUT
node tools/emu3000-refresh/browser-check.mjs OUT
node tools/emu3000-refresh/browser-check.mjs OUT --standalone
python3 tools/emu3000-refresh/bundle.py OUT ACTUAL_PRODUCER_COMMIT
# ZIP 出現後實際點下載，再打包使 browser zip_download=true 也進 ZIP；最後逐檔再比。
node tools/emu3000-refresh/browser-check.mjs OUT
python3 tools/emu3000-refresh/bundle.py OUT ACTUAL_PRODUCER_COMMIT
```

第一次研究稿需原封不動放 `OUT/history/first-pass/`（保留當時 models／manifest）；`render.mjs` 會加真正同相機、公尺尺度的 `first-pass-vs-final.png`。它是實際未提交研究稿，不能偽稱某次 Git 發版或使用者已認可。原 main 前版則由 85d9aa35 真正重建並保存。

`export.swift` 每件 M3DM v1 都經遊戲讀回器逐頂點、顏色、layer、法線核對。12 節總數超過單件15,000三角限制，交付自含合法單元的 M3DAssembly JSON 與 GLB，不造超限 M3DM。所有座標的 signed-zero 在檔案寫入時正規化；Swift／JS組裝 payload 逐 bytes 比對。分色直接切原殼三角；三角側窗用封閉細分面貼合，字典邊必須排序，避免重建三角順序不穩定。

`verify.mjs` 查單元閉合有向邊、正體積、與 GLB 相同幾何；拒絕缺面／反面／位移組裝變異。完整編組以已稽核單元與 Swift 逐 bytes 組裝驗證。修改前模型僅保存比對，不宣稱符合新品質標準。

`support-audit.py` 用實際匯出三角：外露玻璃法線射線取樣，120mm背襯距離；辨識真正8個輪胎連通體、輪底z=0、上方淨空；實際屋頂實體透過65mm接觸容差的取樣圖連回車身。薄玻璃側壁／內面不能拿切向長射線誤判為正面浮空。此法不證明所有表面互不穿插、動態懸吊或真實接觸網接觸；完整碰撞與真機驗證仍列 UNVERIFIED。

`coexistence.py` 比較每個原有非EMU模型的實際 Float32位置、顏色、layer bytes；並保存 SHA256。不是只比配方常數。`glb-audit.py` 用獨立 Blender glTF importer 校驗實際 bounds／三角／頂點色／霧面無貼圖。

`browser-check.mjs` 實際載入所有模型、拖曳旋轉、縮放、七向、下載原生／GLB／PNG／ZIP並比SHA；另在瀏覽器離線模式驗證自含 viewer。檔案協定直接導覽在本環境限制下未測，離線測試以 setContent 開啟同一HTML，據實記錄。PNG全量解碼、alpha及不裁邊由Pillow獨立驗證。

`bundle.py` 要求實際 producer commit 與本機程式逐檔相同、manifest與模型／七向SHA相符、公開總覽等於私有最終渲染，完整ZIP解壓後逐檔比 bytes。`package-verification.json` 留在ZIP外，避免ZIP雜湊自我參照。私有參考圖不隨包散布；`reference-review.json` 只列已檢視來源、SHA、尺寸及限制。
