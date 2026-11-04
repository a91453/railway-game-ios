# Ferry studies producer

決策579。原創公尺制配方，輸出M3DM v1；只在工具中生成，不註冊GamePresentation或standard，不接營運。沿用station-kit的GLB編碼與七向renderer，不依賴Blender執行重建，也不搬私有factory。

```sh
PATH=/path/to/swift-6.4/usr/bin:$PATH tools/ferry-studies/rebuild.sh /path/to/railway-assets-private/game-art-previews/docs/art/ferry-2026-11
```

需要既有Python/Pillow、Node/Playwright、Chromium和Swift6.4。輸出禁止在公開checkout內。`produce.py OUTPUT tamsui|cijin|dock`可逐款重建；完整rebuild在已逐款目視自檢之後使用。每個近／遠景各有自己的model目錄與revision-1，14張日夜PNG，批次只留一份自含viewer，不建history或ZIP。

`test_geometry.py`逐solid檢查有向邊閉合、正體積、非退化與預算；故障反例刪船底／反轉三角會失敗。另驗真船長寬、左右燈、LOD、跳板固定件不動／活動件剛體。閉合不等於整組布林聯集，不宣稱已證明所有三角之間無穿插。

`check-native.sh`把最終輸出用真正Swift loader逐頂點讀回；`verify.mjs`重建GLB比bytes，實跑viewer、日夜、七向、跳板slider、390px。受管Chromium封鎖file://時，記錄UNVERIFIED，改在新頁載入**同份自含HTML**並關網驗互動，不假稱完成file://開檔。`decode-images.py`真正解碼所有RGBA與SHA、alpha邊界與檔案大小。

native發光是triangle flag1，GLB沿用自訂`_NATIVE_GLOW`，未新增glTF標準emissive材質。viewer採同一native頂點，可日夜切換；通用GLB軟體不保證發光。跳板GLB為靜態mesh，接點／活動範圍在manifest，沒有glTF動畫軌。

畫風色值對應既有Map3DPalette：tileWhite、tinRoofs[0]、shopAwnings[1]、gymGreen、tankStand、playerRim、platform、glazing、tunnelLamp、counters[1]。船塗裝保留白／藍帶與白／紅艙的實船關係，色相調到本專案霧面色票。
