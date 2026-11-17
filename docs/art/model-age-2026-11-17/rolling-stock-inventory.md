> MODEL-AGE 的附表（2026-11-17，讀程式與 git 紀錄寫成的英文筆記），結論與分數見 `docs/research/MODEL_AGE_2026-11-17.md`。
> 更正：推拉式自強號在正式版畫 E500 不是借用；決策 425 寫明 E1000 已在 2026-07-01 退出定期營運。

# Rolling-stock inventory of the native 3D map (read-only research, main 19f3cc5, 2026-11-17)

Sources read: `Map3DTrainSets.swift` (`all`, `nearOnly`, `byType`, `variant`, `set(forKey:count:locked:)`),
`Map3DModels.swift` (`styleByType`, `modelIndex`, `farModel`, `model(_:forType:count:at:)`),
`Map3DRealTrains.swift` (`formation(system:id:name:)`, `traFormation`), `RealLineStock.swift`, `TrainPack.swift`,
`Map3DTrainRegistryList.swift`, per-car recipe files, `tools/train-models/hashes.lock.json` + `locks/*.json`
(triangle counts below are the lock's per-model counts, i.e. pack models after baking), `budgets.json`,
`git log` (full history after unshallow; PR = first merge containing the file's first commit), decisions in
`docs/decisions/`, `docs/HANDOFF.md`, `docs/research/NEXT_PRIORITIES_2026-10-12.md`.
Nothing was run in the app; everything below is from code/doc reading (runtime UNVERIFIED).

## 0. Method legend

- **(a) generic shell** — `Map3DTrainShell`/`Map3DTrainStyle` (decision 230, #652 2026-10-15; rebuilt decision 410, #1227 2026-10-25) or the #900 scene-kit `SceneKitCab`/`SceneKitCab.coach` built on it (decision 318, #910/#923, 2026-10-21). Parametric box/ring assembly, no real vehicle.
- **(a') early Codex art package** — dedicated but pre-handbook recipes from 2026-10-22/23 (#954–#1119), mostly fictional or "game palette" vehicles drawn from owner views; no far version.
- **(b) dedicated recipe** — per-vehicle Swift recipe, photo-led, after/around the vehicle-modeling handbook (`docs/art/native-vehicle-modeling`, added 2026-10-25, 12a94778f), mostly Codex "independent native study" PRs, near + far.
- **(c) owner's model converted** — owner's own mesh: N700S-G (decimated, decision 408) and red commuter e752e7a2 (`tools/texture-palette`, #2249).
- **(d) studio GLB → Swift mesh** — local Mac studio GLB, `tools/train-models/glb_to_swift.py`, model-look rounds (decisions 780, 786; registry decision 782).
- **(e) Meshy** — none. No Meshy model is in the game (Meshy batch lives in railway-assets-private, not wired).
- `model-look` skill (three photo rounds) only exists since 2026-11-11 (5aea676c0); only the MTR studio cars (d) went through it as such. R21/Alishan (§7.2 of rolling-stock skill) were "redone after owner said ugly" on 2026-11-01.

## 1. Release vs test build (train pack, decision 338)

`TrainPack.sets` = `threeCarUrban, fiveSectionLRT, sevenSectionLRT, fourCarMetro, blueSeven, n700sG, pushPullE1000`.
In a release build these are all **locked** (`TrainPack.locked(unlocked:false)` returns every set), so players see
the set drawn "as before": all HSR = 700T, every push-pull Tze-Chiang = E500 at both ends, no-type 3-car commuter =
generic `commuter` shell, light metro = `greenTram`, type L metro = Taipei C371/C381/C341 split. Unlocked only in
a test build with the switch on (and `pushPullE1000` needs its own extra switch).

## 2. `nearOnly` and far versions

`Map3DTrainSet.nearOnly` (despite the name: sets whose near model is drawn only to 500 m, `tramReach`) =
registered sets with a far set (`mtrAirportExpress`, `mtrTungChung`, `mtrUrbanLine`) ∪ `E200CK R100CK R200CK E500CK MINGRI STAR
pushPull pushPullE1000 greenTram SUMMER STEAM BLUE highSpeed n700sG emu3000 taroko emu800 emu500 puyuma metroC341 emu900 emu700
metroC371 metroC381 circular610 sanying kaohsiung taichungGreen danhaiLRT ankengLRT klrtCAF klrtCitadis ALISHAN FREIGHT HAIFENG
SHANLAN wenhuVAL256 wenhu370 taoyuanAirport1000 taoyuanAirport2000`.

- **In nearOnly but no far set**: `greenTram`, `STEAM` (STEAM grandfathered in `budgets.json` "noFar": 8,000+ tri car, no far).
  Those switch to boxes beyond 500 m.
- **Not in nearOnly, no far set** (near model drawn to 900 m, then box): `metroGeneric`, `wenhu`, `redCommuter`, `greenCommuter`,
  `threeCarUrban`, `fiveSectionLRT`, `sevenSectionLRT`, `fourCarMetro`, `blueSeven`, the `commuter/express/highSpeed/metro/peopleMover` style shells.
- **Finding (code reading)**: `dieselRailcar` and `dieselExpress` have far sets (`…Far`, 1,584 tri) but are **not in nearOnly**, so
  `reach(of:)` = 900 m and `model(_:forType:…)` returns the near model all the way; their far sets look unused. UNVERIFIED at runtime.
- **Far set that is not really lighter**: `E200CKFar` head = the near E200 (5,512 tri, HANDOFF §4483 "E200 的遠景模型（現在 900 m 內都是 5,512 個三角形）");
  `MINGRIFar` head likewise 5,512; `SUMMERFar` head = near steam (10,092); `STARFar` coaches = the same 1,528-tri generic coach.

## 3. Inventory table (every set in `Map3DTrainSet.all` + other trains drawn)

Tri = near triangles per car (head / middle / tail; extra roles noted), far in [ ].

### 3.1 Taiwan Railway locomotives and hauled trains

| Set key | Real vehicle | Swift file(s) | When (first → last commit, PR, decision) | Method | Near tri [far] | Used by (game / real) | Doc remarks |
|---|---|---|---|---|---|---|---|
| `E200CK` | E200 electric loco (refresh) + Chu-Kuang auto-door coaches | `Map3DTrainShapeRefresh.swift` (`refresh-e200`), `Map3DChuKuangPassenger.swift` | E200: d476304b8 2026-10-24 (#1201) → 23aeb79dc 10-26; in service decision 408 (#1217). Coach: #1306 10-26/27, decision 430 | E200: (b-) photo-led "static shape study", pre-handbook; coach (b) | loco 5,512 [**none**, same 5,512]; coach 6,476 / tail 6,500 [4,008/4,032] | type E200CK; performance e200ChuKuang; **every real TRA 莒光/普通車 train** (`traFormation`: 9 cars) regardless of real loco | HANDOFF ~4488: E200 far model still missing; old `Map3DTrainLocomotive.e200` unused. Coach painted game navy, not real orange (decision 430) |
| `MINGRI` | Ming-Ri tourist train as "E200 Ming-Ri style" | `Map3DE200MingriStyle.swift` (66 lines: repaints E200 + Chu-Kuang units) | fd638351d 2026-10-29 (#1480) → 85f505e2a; decision 483 | repaint of (b-)/(b) units | 5,512 / 6,476 / 6,500 [head 5,512 not reduced; coaches 4,008] | type MINGRI, perf mingRi | "no claim of an official E200 livery" (file header); a game-style paint, not the real Ming-Ri livery |
| `E500CK` | E500 electric loco + Chu-Kuang coaches | `Map3DE500.swift`, `Map3DChuKuangPassenger.swift` | 8127c765f 2026-10-25 (#1256, issue #1255) → 85647d0a5; decisions 425/430 | (b), handbook CASE_STUDY_E500, owner accepted 3rd revision | 9,964 / 6,476 / 6,500 [3,992 / 4,008] | type E500CK | — |
| `R100CK` | R100 diesel (orange R122) + Chu-Kuang coaches | `Map3DR100.swift`, `Map3DChuKuangPassenger.swift` | R100: 3e4c0e9e3 2026-11-01 (#1671); decision 541 | (b) | 7,318 / 6,476 / 6,500 [3,466 / 4,008] | type R100CK | — |
| `R200CK` | R200 diesel (R216) + Chu-Kuang coaches | `Map3DR200.swift` | de45c2279 2026-10-30 (#1589) → 72528a499; decision 529 | (b) | 12,702 / 6,476 / 6,500 [5,098 / 4,008] | type R200CK (no longer sold, decision 539) | — |
| `BLUE` | Blue Train (藍皮解憂號): two blue R100s back to back + restored 35TP32850 coaches | `Map3DR100.swift`, `Map3DBreezyBlueCoaches.swift` | 3e4c0e9e3 2026-11-01 (#1671), b4f6d5f2b; decision 541 | (b) | 14,636 (2 locos) / coaches 12,234–13,278 [6,932 / 4,950–5,478] | type BLUE | — |
| `STAR` | Formosa Star (環島之星): E500 + **generic pink coaches** | `Map3DE500.swift` + `SceneKitCab.coach` (`Map3DSceneKitCabs.swift`, asset `05_TRA_classic_3x2-05`) on `Map3DTrainShell` | set from decision 286 (3rd later, #1047 era); coach shell #910 2026-10-21 / decision 410 rebuild #1227 | loco (b), **coaches (a) generic shell** | 9,964 / **1,528** / 1,588 [3,992 / 1,528 / 1,588] | type STAR, perf formosaStar | NEXT_PRIORITIES §… row 11: 環島之星 3D still pending ("環島之星、加價…" not done) |
| `SUMMER` | Midsummer Formosa (仲夏寶島號): steam loco + tender + Chu-Kuang coaches | `Map3DSteamTender.swift`, `Map3DChuKuangPassenger.swift` | steam: 843e6db89 2026-10-23 (#1106, #1103) → 1da739cac; decision 399 | steam (a') Codex package "reconstructed from ten owner views… not a real locomotive"; coaches (b) | 10,092 + tender 4,000 / 6,476 / 6,500 [loco/tender **not reduced**; coaches 4,008] | type SUMMER, perf midsummerFormosa | — |
| `STEAM` | Generic steam train: duplex (twin-group) steam + tender + **generic blue coaches** | `Map3DDuplexSteam.swift`, `SceneKitCab.coach` | bcc6c933f 2026-10-23 (#1119, #1118); decision 399 | loco (a') Codex, fictional; coaches (a) | 8,092 + tender 3,048 / **1,528** / 1,588 [**no far set**] | type STEAM (eraOnly) | `budgets.json` grandfathered noFar; NEXT_PRIORITIES item 16 lists 蒸汽 among "3D still boxes" (stale) |
| `pushPull` | PP Tze-Chiang: E500 power at both ends + PPT1000 coaches | `Map3DE500.swift`, `Map3DPPPassenger.swift` | PP coaches 11a70d3c0 2026-10-26 (#1291); decision 425 | (b) | 9,964 / 8,172 (tail = head turned) [3,992 / 3,944] | perf pushPull; **every real TRA `(PP` train** (14 cars) in release builds | Real PP is E1000-hauled; release shows E500 because `pushPullE1000` is pack-locked. Only PPT1000 of the 4 PP coach roles is used; PPC1400/PPH1300/PPM2500 are studies |
| `pushPullE1000` | PP Tze-Chiang with E1000 power cars | `Map3DE1000.swift`, `Map3DPPPassenger.swift` | 2be9dacaf 2026-10-26 (#1296/#1302) → b396c8ea2; decision 427 | (b) | 6,388 / 8,172 [3,460 / 3,944] | train pack only (locked in release; needs extra switch) | — |
| `FREIGHT` | Freight: R200 + 40 ft/2×20 ft container flat wagons | `Map3DR200.swift`, `Map3DContainerWagon.swift` | 1d9d27180 2026-11-01 (#1680); decision 539 | (b) wagons simple (box containers on flats) | R200 12,702 / wagons 3,260–3,668, tail 3,284 [5,098 / 992–1,256] | any freight line's train whatever its type | Only container wagons; no hoppers/tank/cement cars |
| `ALISHAN` | Alishan Forest Railway DL-38 + ordinary coach | `Map3DAlishan.swift` | 03043510b 2026-11-01 (#1643) → f64c332b6 (revision 2); decision 531 | (b), redone after owner said ugly (R21 standard) | 7,712 / 3,988 / 3,988 [2,316 / 1,372] | type ALISHAN; real `afr` (6 cars) | HANDOFF ~4060: decision 531 gaps remain (other models) |
| (study) `g12-r21` | R21 EMD G12 | `Map3DG12.swift` | b073c6c60 2026-10-29 (#1485) | (b) benchmark | 6,420 [2,932] | **not drawn** (`studies` only) | the quality benchmark in rolling-stock skill §7.2 |
| (legacy) `Map3DTrainLocomotive` e200/e500/r100/e1000/ct273 | box-built locos | `Map3DTrainLocomotives.swift` | 6d231766e 2026-10-21 (#910), decision 318 | (a) boxes and beams | — | **no set uses it** (only an unused `hauled(_:locomotive:)` overload) | HANDOFF ~4488: can be deleted |

### 3.2 Taiwan Railway multiple units and railcars

| Set key | Real vehicle | Swift file(s) | When | Method | Near tri [far] | Used by | Remarks |
|---|---|---|---|---|---|---|---|
| `emu3000` | EMU3000 (Tze-Chiang) 12 cars | `Map3DEMU3000.swift` | 3ab845507 2026-10-25 (#1229, Codex) → 07c0726ff 10-27; no own decision file (mapping decisions 318/237) | (b), handbook CASE_STUDY_EMU3000 | cab 8,962 / 5,456–5,968 [3,834 / 2,472–2,776] | type EMU3000; real `自強(3000`, `110K`, `110M` | — |
| `taroko` | Taroko TEMU1000 8 cars | `Map3DTEMU1000.swift` | 3366fed58 2026-10-25 (#1230, #1307 cab) → 462b69b9b 10-26; far decision 420 | (b) early, Codex | **2,766** / 1,408 / panto 1,512 [1,058 / 560] | perf taroko; real `(太,` trains | Lightest intercity set; built same day as handbook |
| `puyuma` | Puyuma TEMU2000 8 cars | `Map3DTEMU2000.swift` | 6fa198593 2026-10-26 (#1292) → 4439c8ddb 10-29 (#1456 rev-2, #1487); decisions 426, 484 | (b) | 6,980 / **1,800** / panto 1,952, centre 1,812 [2,812 / 760] | perf puyuma; real `(普,` | Owner rejected revision 1 (HANDOFF ~95); middle cars still light |
| `emu500` | EMU500 local | `Map3DEMU500.swift` | bf011de83 2026-10-27 (#1312) → 40528d8a8; decision 432 | (b) | 4,548 / 2,840–4,548 [1,740 / 1,072–1,740] | TRA local trains (`localTrain` 5/20) | — |
| `emu700` | EMU700 local 8 cars | `Map3DEMU700.swift` | d5664ff42 2026-11-02 (#1730) → 3357d5edb; decision 560 | (b) | 13,740 / ~6,000 [6,728 / ~2,960] | TRA local (3/20) | — |
| `emu800` | EMU800 local | `Map3DEMU800.swift` | d2995d661 2026-10-27 (#1320) → 40528d8a8; decision 432 (far 420) | (b) | 11,506 / ~5,200–5,372 [2,418 / ~1,100] | TRA local (4/20); default for every TRA line (`formation` "tra") | — |
| `emu900` | EMU900 local 10 cars | `Map3DEMU900.swift` | 2858da270 2026-10-27 (#1339) → e3f923f30; decision 435 | (b) | 9,256 / ~5,000 [2,188 / ~900] | TRA local (8/20) | — |
| `HAIFENG` / `SHANLAN` | Hai-Feng EMU573 / Shan-Lan EMU583 (converted EMU500) | `Map3DTourismEMU500.swift` (+`Map3DEMU500`) | f036e7f79 2026-10-30 (#1539) → df7a12546 11-02; decision 554 | (b) | 8,076 / 2,936–3,132 [3,420 / ~1,140] | types HAIFENG, SHANLAN | — |
| `dieselRailcar` | DR1000 (DRC1025) railcar | `Map3D45DR1000.swift` | 5ad973d5e 2026-10-29 (#1530) → 57b3802c0 11-11 | (b) | 3,604 every car [1,584, **apparently unused**, see §2] | perf dieselRailcar; dieselExpress with ≤2 cars; real diesel branches (3 cars); Neiwan etc. bought lines | HANDOFF 2134 earlier listed DR1000/DR3100 as "舊套件車身" — now replaced |
| `dieselExpress` | DR3100 diesel express (DR1000 shape, silver/orange) | `Map3D45DR1000.swift` | decision 511 | (b) **borrowed shape**: DR1000 body repainted | 3,604 [1,584, apparently unused] | perf dieselExpress (3+ cars); real `(D31` | Real DR3100 has a different body; not its own model |
| type `EMU100` → `commuter` style | EMU100 (British-built Tze-Chiang) | `Map3DTrainShell.swift` style `commuter` | style decision 230 (#652, 2026-10-15), rebuilt 410 (#1227) | **(a) generic shell** | cab 2,234 / car 1,592 [none] | type EMU100 (`styleByType`) | Old generation; no own model |

### 3.3 High speed

| Set key | Real vehicle | Swift file(s) | When | Method | Near tri [far] | Used by | Remarks |
|---|---|---|---|---|---|---|---|
| `highSpeed` | THSR 700T 12 cars | `Map3DTrainShapeRefresh.swift` (`refresh-700t-*`) | d476304b8 2026-10-24 (#1201, 10th revision) ; decisions 408, 410, 422 | (b-) photo-led, pre-handbook (handbook CASE_STUDY_700T) | 9,126 / 5,602 / panto 5,730 [1,208 / 514 / 562] | type HSR; perf highSpeed; **all real THSR** (12 cars); all HSR in release | — |
| `n700sG` / `n700sGFar` | owner's "N700S-G" | `Map3DN700SG.swift`, `Map3DN700SGMesh.swift`, `Map3DN700SGFarMesh.swift` | 1c9611e78 / b3e5fd18d 2026-10-25 (#1217); decisions 408, 422 | (c) owner's mesh decimated + game palette | 6,989 / 6,024 / 6,016 [977 / 408 / 1,488] | train pack only: odd-numbered HSR in test builds | Far box mismatch grandfathered (`budgets.json`); HANDOFF: B/E cars not drawn, N700ST not wired |
| style `highSpeed` / `express` | generic shells | `Map3DTrainShell.swift` | decision 230/410 | (a) | 3,044/1,835 ; 3,080/1,748 | fallback only (HSR/EMU3000 always have sets) | unused in normal play |

### 3.4 Taipei / Taiwan metros and people movers

| Set key | Real vehicle | Swift file(s) | When | Method | Near tri [far] | Used by | Remarks |
|---|---|---|---|---|---|---|---|
| `metroC341` | Taipei C341 | `Map3DC341.swift` | 14a2d8bf4 2026-10-27 (#1323) → 4557f7d20; decision 433 | (b) | 3,894 / 3,306–3,318 [1,754 / ~1,360] | BL line (stands in for **C321** too); player metro A/B/D/L 6/20 | far box mismatch grandfathered |
| `metroC371` | Taipei C371 | `Map3DC371.swift` | 109fb2b86 2026-10-27 (#1342) → 66c6ab56d 10-28 (#1424); decision 461 | (b) | 5,358 / ~2,200 [2,038 / ~880] | O (Zhonghe-Xinlu), R/G branch shuttles (3 cars), half of G; player metro 8/20; bought Xinbeitou line | — |
| `metroC381` | Taipei C381 | `Map3DC381.swift` | same as C371; decision 461 | (b) | 6,976 / ~1,810 [2,904 / ~880] | R line (stands in for **C301**), half of G; player metro 6/20; perf `metro` alias | — |
| `circular610` | Circular line 610 | `Map3DTaipei610.swift` | 488b29994 2026-10-27 (#1362) → ab5c07eaa; decision 461 | (b) | 3,650 / 2,824 [1,638 / 1,252] | Y line | — |
| `wenhuVAL256` / `wenhu370` | Wenhu VAL256 / Bombardier 370 (INNOVIA APM256) | `Map3DWenhuVAL256.swift`, `Map3DWenhuAPM256.swift`, `Map3DWenhuPrimitives.swift` | 9b4c39caa 2026-11-03 (#1742) → 538a985c7; decision 558 | (b) | 12,136–12,172 [5,680–5,716]; 10,856–10,892 [5,000–5,036] | BR line (1/3 VAL256, 2/3 370); type APM | — |
| `wenhu` | generic people mover (scene kit `02_HSR_MRT_3x2-03`) | `multipleUnit` in `Map3DTrainSets.swift` + shell | decision 318/461 | (a) | 1,933 / 1,312 [none] | fallback of the Wenhu sets only | — |
| `sanying` | Sanying line 2-car | `Map3DSanying.swift` | 29a88943e 2026-10-28 (#1422) → 495468fe0; decision 466 | (b) | 4,306 ×2 [2,058] | real `sanying` | — |
| `kaohsiung` | KRTC Siemens 3-car (Red/Orange) | `Map3DKaohsiung.swift` | 51d3167ad 2026-10-29 (#1454) → eae0f980e; decision 483 | (b) | 5,790 / 2,312 [2,686 / 984] | real `krtc` R, O | — |
| `taichungGreen` | Taichung Green line 2-car | `Map3DTaichungGreen.swift` | ebf978be1 2026-10-28 (#1430/#1437) → 498d85ef2; decision 483 | (b) | 4,804 ×2 [2,208] | real `tmrt` | — |
| `taoyuanAirport1000` / `…2000` | Taoyuan Airport MRT commuter 1000 (4 cars) / express 2000 (5 cars) | `Map3DTaoyuanAirport.swift` | a38118a1e 2026-11-02 (#1700) → 42214527e; decision 561 | (b) | 13,752 / 9,764–9,944, 2000 tail 10,572 [6,820 / ~4,570] | real `tymc` (express trips → 2000) | — |
| `metroGeneric` | generic metro car (scene kit `02_HSR_MRT_3x2-02`), line-coloured band | `multipleUnit` + `Map3DTrainShell.swift` | decision 318 (#910/#923), renamed decision 461, rebuilt 410 | **(a) generic shell** | 2,360 / 1,800 [**none**] | **HK MTR TML, EAL, EAL_LMC, SIL, DRL**; fallback for Taoyuan & MTR sets | see §4 |
| style `metro` / `peopleMover` | generic shells | `Map3DTrainShell.swift` | decision 230/410 | (a) | 2,252/1,696 ; 2,042/1,344 | fallback only (A/B/C/L/D/APM have sets via `byType`) | — |

### 3.5 Light rail

| Set key | Real vehicle | Swift file(s) | When | Method | Near tri [far] | Used by | Remarks |
|---|---|---|---|---|---|---|---|
| `danhaiLRT` | Danhai LRT 5-module (cut into 2 cars) | `Map3DDanhaiLRT.swift` | 9e807f084 2026-10-30 (#1533); decision 496 (op #1540) | (b) | 24,838 / 25,174 [11,634 / 11,850] (two-car exemption up to 30k) | real `ntdlrt` | — |
| `ankengLRT` | Ankeng LRT | `Map3DAnkengLRT.swift` | same | (b) | 14,982 / 14,934 [~7,300] | real `ntalrt` | — |
| `klrtCAF` / `klrtCitadis` | Kaohsiung LRT CAF Urbos / Alstom Citadis | `Map3DKaohsiungCAF.swift`, `Map3DKaohsiungCitadis.swift`, `Map3DKaohsiungLRTGeometry.swift` | 80b58f6ec 2026-10-29 (#1506) → cfeed7992; decision 496 | (b) | 21,288/20,644 [~9,600]; 15,728/15,336 [~7,150] | real `krtc` C line (3:5 by number) | — |
| `greenTram` | generic green 3-section low-floor tram | `Map3DGreenTram.swift` | 7f49a35ca 2026-10-22 (#954) → 2a9475037; decision 331 | **(a') Codex, owner's four views, fictional** | 2,836–3,048 [**none**] | type C (light metro), all counts in release | in nearOnly, no far → boxes past 500 m |
| `fiveSectionLRT` / `sevenSectionLRT` | generic articulated LRTs | `Map3DFiveSectionLRT.swift`, `Map3DSevenSectionLRT.swift` | 25cb20fae / 21a5b7ba1 2026-10-22 (#992); decision 338 | (a') | 2,628/2,756; 2,444/2,720/2,572 [none] | train pack: type C with 2 / 3 cars | — |
| `blueSeven` | generic 7-module blue urban train | `Map3DSevenCarBlue.swift` | 2945638f3 2026-10-23 (#1096/#1094); decision 399 | (a') | 2,012 / 2,024 / 1,884 [none] | train pack: type C with 4 cars | — |
| `fourCarMetro` | generic linear-motor 4-car metro | `Map3DFourCarMetro.swift` | 555adccdc 2026-10-23 (#1082/#1081); decision 399 | (a') | 2,020 / 1,960 [none] | train pack: type L (`packByType`) | — |

### 3.6 Commuter EMUs with no type, Hong Kong, cable cars

| Set key | Real vehicle | Swift file(s) | When | Method | Near tri [far] | Used by | Remarks |
|---|---|---|---|---|---|---|---|
| `greenCommuter` | generic green 2-car EMU | `Map3DGreenCommuter.swift` | 9099b6a17 2026-10-22 (#961); decision 331 (later) | (a') | 2,478 [none] | no-type commuter, 2 cars | — |
| `threeCarUrban` | generic 3-car urban EMU | `Map3DThreeCarUrban.swift` | 2b2bfab2a 2026-10-22 (#988); decisions 331, 338 | (a') | 2,620 / 2,356 [none] | no-type commuter, 3 cars — **train pack only**; release draws the `commuter` shell | — |
| `redCommuter` | owner's old red commuter car e752e7a2 | `Map3DRedCommuter.swift`, `Map3DRedCommuterMesh.swift` | 8550313dc 2026-11-15 (#2249); no own decision file (uses decision 780's GLB writer) | (c) texture-palette conversion | 1,512 / 1,422 [none, by design: "not a detailed car"] | no-type commuter ≥4 cars (e.g. TRA demo lines with `type: nil`, HSR-TYPE-FIX handoff) | HANDOFF ~711: not yet seen on device |
| `commuter` style | generic commuter shell | `Map3DTrainShell.swift` | decision 230 (#652, 10-15) / 410 (#1227) | **(a)** | 2,234 / 1,592 [none] | type EMU100; no-type 1-car and (release) 3-car commuters; redCommuter decode fallback; VR (see §4) | oldest generation still reachable |
| `mtrAirportExpress` / `mtrTungChung` | MTR A-train (Airport Express 8 cars incl. baggage car; Tung Chung 8) | `Map3DMTRAirportLine.swift`, `Map3DMTRAirportLineMesh.swift`; lock `locks/mtrAirportLine.json` | 419d38d29 2026-11-15 (#2268) → 108a2ad12 (#2288, studio rounds 5/6); decisions 780, 782 | **(d)** studio GLB → Swift | AEL 4,859 / 4,446 / baggage tail 5,475 [~1,000–1,800]; TCL 7,701 / 7,322 [~1,520] | hkmtr AEL, TCL | registered (decision 782) |
| `mtrUrbanLine` | MTR urban M/Q-train 8 cars | `Map3DMTRUrbanLine.swift`, `Map3DMTRUrbanLineMesh.swift`; lock `locks/mtrUrbanLine.json` | eab413056 2026-11-15 (#2274) → 108a2ad12 (#2288); decision 786 | **(d)** | 8,915 / 7,082 / panto 7,226 [3,125 / 2,338] | hkmtr TWL, ISL, KTL, TKL, TKL_LHP | registered |
| cable cars | Maokong standard / crystal cabin; Sun Moon Lake cabins (blue/red/yellow/crystal) | `Map3DCableCar.swift`, `Map3DCableCarParts.swift`, `Map3DSunMoonCabin.swift`, `Map3DCableways.swift` | aaaaaca6f 2026-11-04 (#1782, decision 575); c7f8ed096 2026-11-06 (#1898, decision 615) | (b) | 3,220 / 3,268 [1,584 / 1,632]; Sun Moon 5,660–5,788 [2,744–2,808] | cableways (Sun Moon cabin near Sun Moon Lake, Maokong elsewhere) | not train sets; not in `Map3DTrainSet` |

Static (not running): Changhua Roundhouse stalls hold R100 orange + R200 (`Map3DRoundhouseStock.swift`, #1905, decision 581 later);
railway-museum exhibits use the normal sets (`Map3DRailwayMuseum`, `Exhibit.key = Map3DTrainSet.key(type:…)`), so a STEAM/STAR/EMU100
exhibit shows the same old models. Christmas livery (decision 806, `Map3DChristmasLivery`) decorates any car at draw time, no model change.

## 4. Borrowings (a route/type drawn with another vehicle's model)

| Who | Drawn as | Where set | Note |
|---|---|---|---|
| MTR Tuen Ma (TML, SP1900/SP1950, 8) | `metroGeneric` + line colour band | `Map3DRealTrains.formation` "hkmtr" default, decision 781 | MODEL_PALETTE_REVIEW §… "東鐵、屯馬、南港島、迪士尼四線還在借用"; MTR-2..5 pending (NEXT_PRIORITIES §29.9) |
| MTR East Rail EAL + Lok Ma Chau EAL_LMC (R-train, 9) | `metroGeneric` | same | — |
| MTR South Island SIL (S-train, 3) | `metroGeneric` | same | — |
| MTR Disneyland DRL (4 cars) | `metroGeneric` | same | not covered by decision 786's urban line |
| Bought MTR lines | same set as above via `RealLineStock.setKey` | decision 536 | `RealLineStock.name(ofSet:)` has no MTR names (returns nil) |
| Taipei Metro C301 (R line) | `metroC381` | decision 461 | — |
| Taipei Metro C321 (BL line) | `metroC341` | decision 461 | — |
| Player metro types A/B/D (and L in release) | C371/C381/C341 by number | `taipeiMetro(number:)` | Kaohsiung/Taoyuan/Taichung real lines use own sets |
| Every real TRA 莒光/普通車 | `E200CK` (E200 + Chu-Kuang) | `traFormation` | real locos vary (E400, R100…), not distinguished |
| Every real TRA push-pull Tze-Chiang | `pushPull` = **E500** at both ends (release) | `variant`, `TrainPack` | real is E1000; E1000 only in unlocked pack + switch |
| Real TRA 自強 other than EMU3000/Taroko/Puyuma/PP/DR3100 (e.g. EMU1200/EMU300 if in timetable — unknown) and all 區間/區間快 | line default `emu800` → split EMU900/500/800/700 | `traFormation` returns nil | — |
| DR3100 | DR1000 body repainted | decision 511 | — |
| All real THSR | 700T (N700S-G only in test pack; real N700ST not modelled) | — | HANDOFF: owner's N700ST mesh not wired |
| Freight lines (any type) | R200 + container flats | decision 539 | — |
| STAR (Formosa Star) coaches, STEAM coaches | generic `SceneKitCab.coach` (pink / blue) | `coach(TrainLivery…)` | oldest coach generation still in play |
| MINGRI | E200 + Chu-Kuang units repainted | decision 483 | "no claim of an official livery" |
| SUMMER loco | Codex steam-tender package ("not a real locomotive") | decision 399 | — |
| Type C light metro (release) | `greenTram` (fictional) | `byType` | real LRT lines have own sets |
| Type EMU100 | generic `commuter` shell | `styleByType` | — |
| Types MAGLEV, SKYRAIL, MONORAIL | **boxes** (no style, no set) | `styleByType` comment | NEXT_PRIORITIES item 16 |
| Rovaniemi / VR (Finland) | key "" ×3 → by code reading: `commuter` shell in release (`threeCarUrban` if pack unlocked); bought VR line → `RealLineStock` nil → GameCore type's Taiwan model | `formation` default branch | The code comment and NEXT_PRIORITIES §29.9 call this path "boxes", but `models(forType:"")` resolves to the `commuter` style, so it likely draws the shell — UNVERIFIED. Decision 799: "這張沒有芬蘭車"; NEXT_PRIORITIES §29.11 #10 "芬蘭列車 Sr3、Sr2、雙層客車（工作室）" 2.90; Rovaniemi map not open to players yet |
| Taoyuan / MTR sets fallback | `metroGeneric` | `fallback:` | only if the pack lacks their models |

## 5. `tools/train-models/run.sh` coverage

`export.swift` exports by default every `set-*` model of `Map3DModelPack.standard` (so every set above, registered ones included);
`--ids` can pick any model of `standard` or `studies` (style shells `commuter-cab` etc., `g12-r21`, PP roles, cable-car models,
`tra-r100-*`, `temu2000-*` studies). `hashes.lock.json` holds 1,138 entries (standard + studies, including style shells and cable cars);
registered trains are in `locks/mtrAirportLine.json`, `locks/mtrUrbanLine.json`.

## 6. Candidates for remake ("old generation"), by evidence

1. **Generic shell (a) still drawn in play**: `metroGeneric` (5 MTR lines: TML, EAL, EAL_LMC, SIL, DRL); `commuter` style (EMU100,
   no-type 1/3-car commuters in release, probably VR); STAR and STEAM coaches (generic 1,528-tri scene-kit coach). No far versions.
2. **Missing real far version**: E200 (`E200CKFar`/`MINGRIFar` head = near 5,512; HANDOFF asks for it), SUMMER steam loco/tender,
   STEAM (no far at all, grandfathered), greenTram (nearOnly, no far).
3. **Early Codex packages (a'), fictional, no far**: greenTram, greenCommuter, threeCarUrban, five/sevenSectionLRT, blueSeven,
   fourCarMetro (most are train-pack-only); steam tender and duplex steam (fictional steam).
4. **Pre-handbook / light dedicated recipes**: 700T + E200 (`Map3DTrainShapeRefresh`, 10-24), Taroko TEMU1000 (2,766 cab / 1,408 middle,
   10-25), Puyuma middle cars (1,800). Freight wagons are simple container flats only.
5. **Borrowed shapes**: DR3100 (DR1000 body), PP Tze-Chiang shown with E500 in release, all 莒光 shown with E200, C301→C381,
   C321→C341, MTR 5 lines → metroGeneric, real THSR N700ST absent.
6. **Dead code**: `Map3DTrainLocomotive` (decision 318 box locos, e200/e500/r100/e1000/ct273) — unused (HANDOFF ~4488).
7. **Possible bug (code reading)**: `dieselRailcar`/`dieselExpress` not in `nearOnly`, so their far sets are never used.

Unknown / not determined: exact real-TRA model strings in the timetable beyond the `traFormation` patterns (so whether EMU1200/EMU300
trips exist); whether VR ambient trains are actually drawn today (Rovaniemi not open; `metroRuns` has no `vr:` runs per
`RovaniemiRailwaysTests`); per-model method attributions (Codex vs Claude) are inferred from commit messages/branch names.
