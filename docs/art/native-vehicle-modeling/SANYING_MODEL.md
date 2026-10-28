# 三鶯線列車靜態模型（revision 2）

本模型是兩節編組的原生程序化靜態展示素材，模型 ID 為 `sanying-a`、`sanying-b` 及兩個 `-far` 版本。`tools/sanying/assembly.json` 使用兩節單元及 180° 尾車旋轉重建整列。它註冊在 `Map3DModelPack.studies`，未接營運映射、購車或動畫。

## 依據與估計

- [新北捷運營運公司列車諸元](https://www.ntmetro.com.tw/basic/?mode=detail&node=864)：兩節、整列 35 × 2.6 × 3.8 m、鋼輪鋼軌、750 V DC 第三軌。
- [新北市政府 2023-08-10 實車消息](https://www.ntpc.gov.tw/ch/home.jsp?dataserno=202308100011&id=28)：單節 17.7 × 2.6 × 3.8 m、兩側各三門、斜 20° 車頭、藍色長波浪線。
- 使用者提供的照片：前左斜、側面、俯視與月台實車照片作外觀觀察；第一張是 K. Y. Chung 插畫，只輔助辨識，不當工程資料，也不隨模型發布。所附來源的作者及授權仍屬原權利人。

已檢視作者私有參考庫的 `garage-blender-v1/sanying.json`，其 Q 比例模型只有 9.208 m 長，且 `engineeringDimensionsM` 為空；未複用幾何或當作尺寸來源。

第二版因使用者明確否定第一版外觀，以本專案 `Map3DTaipei610` 的圓角前罩與門窗比例為內部造型參考，重寫為獨立三鶯線配方，依官方 17.7 × 2.6 × 3.8 m 對車體做比例校正；集電靴超出 2.6 m 車體寬。車窗寬、鼻部曲面、轉向架軸距、輪徑、空調箱和集電靴位置由照片估計，尚未取得工程圖。風擋、藍色肩線、銀灰前臉與每側三門是主要辨識點。模型使用遊戲既有霧面頂點色，不含真實標誌、照片貼圖或第三方網格。

## 重建

```sh
PATH=/workspace/swift/usr/bin:$PATH tools/train-models/run.sh /tmp/sanying --ids sanying-a,sanying-b,sanying-a-far,sanying-b-far --assembly-spec tools/sanying/assembly.json
node tools/train-models/package.mjs /tmp/sanying
node tools/train-models/audit.mjs /tmp/sanying
node tools/train-models/render.mjs /tmp/sanying --time both
```

完整檢查與來源記錄隨資產庫 `game-art-previews/docs/art/sanying/revision-2/`；Linux 預覽不能代替真機 Metal 與工程尺寸驗收。
