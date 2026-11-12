# PERF-FAR

- 派工單：PERF-FAR（遊戲規劃第 63 任 session_01YGNNuq9euTFvwq3qUD8j27）。
- session：雲端 Linux，2026-11-12。分支 `claude/perf-far`。決策 709。存檔版本、golden、fixture：不動。
- 壓縮 1 次（#1579 有留言），做完這個 PR 就不接新工作。

## 做了什麼

3D 遠景照大小排序，鏡頭越遠只畫越大的東西（[決策 709](../decisions/709.md)）。Linux 上數到台北整個最遠視野從 416 萬個三角形降到 70 萬，每個距離都在 100 萬以內；2 km 以內不變。

## 等什麼才能合

**這是畫面的改動，要 Mac 拍圖、規劃看過才合。** 請 Mac session：

1. 裝這個分支的 Release 到實機，用作者「整個臺灣」的存檔，3D 對著台北車站，從 2 km 慢慢拉到 12 km，拍 2、4、6、8、10、12 km 各一張，和 main 的同一組並排。
2. 看：拉遠時有沒有哪一級換得很明顯（一類東西一起不見）；最遠時城市會不會太空；陰影有沒有跟著建築一起少。
3. 量最遠那一格的三角形、繪製次數、GPU 時間、fps（和 `FPS_DEVICE_2026-11-12.md` 同一個量法），也量台北街道那一格確認沒變（1.37 M）。

覺得太空：把 `Map3DFarDetail.slope`（0.0034）調小；0.0032 時台北 12 km 是 99 萬。覺得還不夠順：繪製次數沒降（每塊最多四次），下一步是合併繪製。

## 怎麼重跑

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter Map3DFarViewTests                       # 回歸測試，約 2.5 分鐘
MAP3D_FRAME_REPORT=1 swift test --skip-build --filter Map3DFarViewTests  # 四個地方、每個距離、每一層的表，約 7 分鐘
```

## UNVERIFIED

- `Map3DMetalView.swift` 的改動沒有在本機編過（Linux 沒有 Metal），靠 CI 的 Xcode 建置。
- 實機幀數、GPU 時間、樣子。
- 有作者路線與遊戲內城鎮的存檔（測試用的是空的新遊戲加機場）。
