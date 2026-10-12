# 教學重做規格（2026-10-12，設計工作流定案）

> **狀態（2026-10-12 整理）**：已由決策 188 實作（#433、#443）。現行的步驟表在 `docs/UI_INTERFACES.md` §1；還沒做的 P1、P2 列在 [NEXT_PRIORITIES_2026-10-12.md](NEXT_PRIORITIES_2026-10-12.md)。

來源：派工 session 的設計工作流（參考專案教學實作、逐步稽核、手機教學最佳做法、三個方案與兩位評審）。實作時以這份為準，遇到與程式碼不符處以程式碼為準並在 PR 說明。

# Final spec: tutorial redo (tutorial only; GameCore, saves, goldens and replays unchanged)

**Baseline.** PR #429 merged into main at 73b4614, and main is now at 9a2313d. Decision 187 is taken (#430, the CI flow change), so this work should claim **decision 188** in #231 if nobody has taken it by then. Save version and golden schema stay as they are (不動).

**Starting design.** I started from "one-action" (one thing to do per step, steps move on by themselves). The good ideas from "minimal-risk" and "reference-port" are added in, and every flaw the judges listed is fixed. Each API below was checked with grep.

**What I ran (VERIFIED on Linux).** I wrote a temporary test, ran it, and deleted it; the working tree is clean.
- A single straight stretch on the new game, tiles 2→12, 2→13 and 2→14 through the middle town, is laid level (start and end height 0). Platforms at tiles 4 and 11 or 12 have no grade, and each station reaches about 44,000 residents. The route between them is found.
- After Done, the clock runs again. The first fares are booked at game time 07:05 (25,500 s). The game starts at 00:00, so at normal speed (600×) that is about 42 real seconds.
- The demo map starts running. Choosing Network pauses it and posts "Paused while you build, so every edit can be undone…". That text is false in the tutorial, because Undo is off there.
- After station A is built, `networkEdgePoint` stays set and `platformStationID` is A. This is the leftover ✗/✓ bubble from the owner's screenshot.
- On a 96 m stretch with A in the middle, a second platform near the end is refused with "A platform must lie on a level stretch of one edge and not overlap another platform."
- A phone held sideways opens the map at 0.5 m per point, and 1 m per point after one zoom out.

Everything else here is unverified until it is implemented.

## 1. What changes from today, and why

| Today | Redo | Why |
|---|---|---|
| 11 steps; step 6 asks for 5 actions in one card; bodies are 120–250 characters | **19 steps in 5 chapters** (Track, Stations, Line, Service, Passengers). Each step is one action. Tapping two points of the same kind (track start and end; the line's two stations) counts as one action, so the card does not jump between the two taps. Each title is the instruction itself. English bodies are at most 90 characters, Chinese at most 36. | Owner's report: steps bundled, texts too long. A judge flagged that the card moving between two taps could land on the second tap's spot. |
| Next has to be tapped after every step | **Steps move on by themselves** 800 ms after the step is done (1.5 s with VoiceOver on). Not after Back: a step reached by Back waits for Next. Next, the automatic move and "Skip this step" all **pass over action steps that are already done**. | Fewer taps. Fast players are never left on an earlier step. |
| A "new since" goal compares with the step's own snapshot | The goal compares with the snapshot of the **earliest shown step of the same chapter**. Short-lived goals also count what they lead to (for example, "pick a site" also counts once the station exists). | Fast players and the map's ✓ consume the preview or site; the old step would then wait forever. |
| The details card is forced open for the whole tutorial | It opens only when the step points into it (Lay/Platform/Remove modes, or Ridership), or with Select while something is selected. On a phone, map-only steps leave it closed; the map's ✓ does what its button does. | Owner's report: a card covered the right side at step 1. On an 874×402 screen the forced 340 pt card left about 450×290 pt of map. |
| The ✗/✓ bubble stays on station A; Pick on Map has to be tapped by hand | Setups clear the leftover site directly, without touching `message`. Picking starts by itself when Lines opens on a line step. The Lines panel scrolls Create Line and Buy into view. | Owner's screenshot. The panel's Create Line and Buy sit below the fold on a phone. |
| The time step is done by any change of speed, pausing included | `build.done` (tap Done) is followed by `time.play` (time runs), which is passed when time already runs (the usual case after Done). | Pausing counted as "changing speed". |
| The ridership step asks for something impossible under the network tool | `station.select` (Select tool) is followed by a read step that outlines the card's Ridership button. | It was a dead end. |
| "Complete this step to continue." | `tutorialHint` says what is wrong or what comes next. A problem shows "Skip this step" at once and is announced to VoiceOver. A tip waits 20 s (90 s for the fares). | Stuck paths become explained ones. |
| The first stretch can be any length | It must be at least **160 m** (`Tutorial.minimumTrackMetres`), with a hint to make it longer. The station titles say "near one end" and "near the other end". | Two 64 m platforms need at least 128 m, and with a 192 m track any place for A leaves room for B. Before this, the only way out was Skip. |

Kept: `Tutorial` is still a value type with first-show snapshots. Next is disabled until the step is done. The three gate UI test names stay the same, so `ios-build.yml` is not touched. Decision 177 holds: only Finish on the last step marks the tutorial done, and Skip does not. No new files, so no XcodeGen run.

## 2. The step table

Two new step ids keep the launcher and UI tests working: `map.move` and `line.create`. `build.network` and `line.staff` are kept too.

Hooks:
- **S** = a session setup. It runs on the step's **first** show, on forward moves only: start, Next, the automatic move, Skip this step, and passing over done steps. Back never runs a setup.
- **P** = the app's panel hook, run on every step change.
- **A** = another app behaviour.

| # | id (chapter) | targets | goal | EN title / body | 繁中 title / body | hooks |
|---|---|---|---|---|---|---|
| 1 | build.network (track) | networkTool | chooseTool(.network) | Tap Network / Your goal: a line that earns its first fares. Track and stations are built with Network. | 點「路網」/ 目標：蓋一條賺到第一筆車資的路線。軌道和車站都用「路網」蓋。 | P: closed. No S: step 0 must not change the world or the clock. |
| 2 | map.move (track) | zoomControls | moveMap | Zoom out to see the town / Pinch, or tap the − button. Drag to move the map. | 縮小地圖看看城鎮 / 兩指開合或按「−」縮放，一指拖曳移動地圖。 | No track and no start yet, so every drag moves the map (`networkDragDraws` is false). |
| 3 | track.draw (track) | map | drawTrack | Tap the start, then the end / Lay it across the town, at least 160 m, so two stations fit. | 點起點，再點終點 / 讓軌道穿過城鎮，至少 160 公尺，才放得下兩座車站。 | S: layTrack. "160" is `Tutorial.minimumTrackMetres` interpolated into the text. |
| 4 | track.build (track) | mapConfirm | buildTrack | Tap ✓ to build the track / The price is on the button. Time stays paused while you build. | 按 ✓ 蓋好軌道 / 按鈕上就是價錢。建造時時間會先暫停。 | — |
| 5 | station.mode (stations) | networkModes | chooseNetworkMode(.platform) | Tap Platform / A station is a platform on your track. | 點「月台」/ 車站就是蓋在軌道上的月台。 | S: clearPicks (removes the end flag). The details card opens (`usesDetailsCard`). |
| 6 | station.first.site (stations) | map | pickPlatformSite(1) | Tap your track near one end / Pick a spot in the town. The ring shows who lives within a walk. | 點軌道靠近一端的地方 / 選在城鎮裡。圓圈裡是走路就能到站的居民。 | — |
| 7 | station.first.build (stations) | mapConfirm | buildStation(1) | Tap ✓ to build the station / The more people in the ring, the more riders. | 按 ✓ 蓋車站 / 圓圈裡的人越多，搭車的人越多。 | — |
| 8 | station.second.site (stations) | map | pickPlatformSite(2) | Tap the track near the other end / A line needs two stations. **Note** (only with `distanceDemand`): " Farther apart, up to 2 km, more people ride." | 點軌道另一端的地方 / 一條路線至少要兩座車站。**Note:** 兩站離得越遠（最多 2 公里），搭車的人越多。 | S: clearLeftoverSite (the bubble on A goes; A's opening "Within 800 m" message stays). |
| 9 | station.second.build (stations) | mapConfirm | buildStation(2) | Tap ✓ for the second station / Next, a line joins the two. | 按 ✓ 蓋第二座車站 / 接下來用路線把兩站連起來。 | — |
| 10 | line.open (line) | linesButton | startPickingStops | Tap Lines / A line tells trains where to stop. It opens on the right. | 點「路線」/ 路線決定列車停哪些站，會在右邊打開。 | S: clearPicks, clearLineDraft. A: Lines starts picking by itself. |
| 11 | line.stations (line) | newStations, map | pickLineStations | Tap one station, then the other / Trains start from the first. Stations the track passes are added for you. | 點一座車站，再點另一座 / 列車從先點的站出發，沿途的車站會自動加入。 | S: frameStations (P1). P: lines. A: picking starts by itself. |
| 12 | line.create (line) | createLine | createLine | Tap Create Line / Your line appears on the map. | 按「建立路線」/ 新路線會畫在地圖上。 | P: lines. A: Create Line is scrolled into view. |
| 13 | line.staff (service) | staffLine | startService | Tap Buy … and Start Service / Pick how often a train comes. The trains are bought and set off in turn. | 按「購買…列並開始營運」/ 選多久來一班車，列車會自動買好、依序發車。 | P: lines. A: Buy is scrolled into view. |
| 14 | build.done (service) | selectTool | chooseTool(.select) | Tap Done to stop building / Time runs again, and your trains set off. | 點「完成」結束建造 / 時間會繼續走，列車就出發了。 | P: closed. Done resumes the clock (decision 99). |
| 15 | time.play (service) | speedControl | timeRuns | Tap ▶ to run time / Trains and passengers move only while time runs. | 按 ▶ 讓時間走 / 時間在走，列車和乘客才會動。 | Usually passed. In code write ▶ as `"\u{25B6}\u{FE0E}"`. |
| 16 | first.fare (service) | cash, speedControl | earnFare | Wait for your first fares / Trains run from 06:00. Fares come in each hour; a faster speed gets there sooner. | 等第一筆車資進帳 / 列車早上 6 點開始跑，車資每小時進帳，調快倍速更快。 | Skip offer after 90 s. A free game passes it. |
| 17 | station.select (passengers) | newStations, map | selectStation | Tap one of your stations / See who rides from it. | 點你的一座車站 / 看看有誰從這裡搭車。 | S: clearSelection (line picking had selected a station). |
| 18 | station.ridership (passengers) | ridership, sidePanel | read | Tap Ridership to see who rides / Trips by the hour and who is waiting. More homes and jobs nearby, more riders. | 點「客源」看誰在搭車 / 每小時的進出站人次和候車人數。附近住的、上班的人越多，搭車越多。 | Card open through the Select-with-selection rule. Read steps place the card with `map: nil`. |
| 19 | end (passengers) | gameMenu | read | That's the tour / Replay it from the game menu. Next, extend your line to the next town. | 導覽結束 / 隨時可以從遊戲選單重看。下一步，把路線延伸到下一個城鎮吧！ | The last button reads "Finish" / 完成教學. |

**Text lengths** (counted). English bodies are 22–88 characters; Chinese bodies are 10–32. Titles are at most 32 characters (English) and 12 (Chinese).

**Chapter labels.** Track 軌道 · Stations 車站 · Line 路線 · Service 營運 · Passengers 乘客.

**Goals.** "New" means not in `snapshot(forChapterOf: index)`. `newTrack` is the sum of `edge.length` over new edges.

| Goal | Done when |
|---|---|
| chooseTool(t) | `tool == t` |
| moveMap | the map moved on this step (unchanged) |
| drawTrack | (`tool == .network`, a preview with `problem == nil`, `cost != nil` and `length >= Tutorial.minimumTrackLength` (10,240 units)) OR newTrack ≥ min |
| buildTrack | newTrack ≥ min |
| chooseNetworkMode(m) | (`tool == .network && networkMode == m`) OR (m == .platform and at least 1 new station) |
| pickPlatformSite(n) | (`platformSitePlanPoint != nil && networkPlatformStretch != nil && platformStationID == nil && networkPlatformGrade == nil`) OR at least n new stations |
| buildStation(n) | at least n new stations |
| startPickingStops | `isPickingLineStops` OR `lineDraft.count >= 1` OR a new line |
| pickLineStations | (`lineDraft.count >= 2 && lineDraftRoute != nil`) OR a new line |
| createLine | a new line whose memoized `tutorialStaffingPlan(id) != nil` (it can run) |
| startService | unchanged rule, against the chapter snapshot |
| timeRuns | `!world.clock.isPaused` |
| earnFare | unchanged rule, against the chapter snapshot (from `line.staff`) |
| selectStation | `tool == .select && selectedStationID != nil` |

**Hints** (`tutorialHint`; nil when the step is done; tip unless marked problem):

| Steps | Condition | Hint |
|---|---|---|
| drawTrack, buildTrack | `networkPreview?.problem` | That text (problem) |
| drawTrack, buildTrack | preview shorter than the minimum | "Make it longer: at least 160 m, so two stations fit." / 再拉長一點：至少 160 公尺，才放得下兩座車站。 |
| drawTrack, buildTrack | 0 < newTrack < min | "Too short for two stations. Tap farther on from its end, then ✓." / 太短，放不下兩座車站。從尾端再點遠一點，然後按 ✓。 |
| drawTrack, buildTrack | start picked, no end | "Now tap where it ends." / 再點終點。 |
| drawTrack, buildTrack | buildTrack with no start | "Tap the start and the end again." / 再點一次起點和終點。 |
| buildStation | `message?.kind == .failure` | `message.text` (problem; the overlap refusal above is one) |
| site, build | `networkEdgePoint != nil`, `platformStationID` names a station | "That spot joins “X”. Tap farther along the track." / 這裡會併入「X」，請點軌道上更遠的地方。 (problem) |
| site, build | `networkPlatformGrade` set | `platformGradeText(grade)` (problem) |
| site, build | `!world.land.isEmpty` and site catchment residents + jobs == 0 | "No one lives in the ring, so few would ride. Try nearer the houses." / 圓圈裡沒有人住，搭車的人會很少。往房子近一點試試。 (problem; does not block) |
| buildStation | no site | "Tap the track again to pick the spot." / 再點一次軌道，選好位置。 |
| pickLineStations | count ≥ 2 and route nil | "No track joins these stations. Tap Clear in Lines, then pick two on your track." / 這兩站之間沒有軌道相連。按「路線」裡的「清除」，再選你軌道上的兩站。 (problem) |
| pickLineStations | not picking | "Tap Lines to pick stations again." / 點「路線」再繼續選站。 |
| pickLineStations | count == 1 | "Now tap the other station." / 再點另一座車站。 |
| createLine, startService | a new or selected line has no plan | "Trains can't run: no track joins this line's stations." / 列車開不了：這條路線的車站之間沒有軌道相連。 (problem) |
| createLine | `lineDraftStops.count < 2` | "Tap Pick on Map, then two stations." / 按「在地圖上選站」，再點兩座車站。 |
| startService | plan cost > balance | "Not enough cash: choose a longer time between trains." / 錢不夠：選久一點的班距。 (problem) |
| earnFare | paused | "Time is paused. Tap ▶." / 時間暫停中，按 ▶。 |
| earnFare | `serviceLevel(of: selectedLineID, at: now) == nil` | "Trains start at 06:00. Tap the speed beside ▶ to go faster." / 列車早上 6 點才開，點 ▶ 旁的倍速可以加快。 |
| selectStation | `tool != .select` | "Tap Done first, then a station." / 先點「完成」，再點車站。 |

## 3. New and changed types and functions

**`Sources/GamePresentation/Tutorial.swift`**
- `TutorialTarget`: append these cases at the end:
  - `mapConfirm = "map.build.confirm"`
  - `ridership = "inspector.ridership"`
  - `newStations = "map.stations"` (P1; drop it with its marker if P1 is cut)
  - add `public var isInDetailsCard: Bool` (true for `.networkModes`, `.actionButton`, `.ridership`).
- `public enum TutorialChapter: CaseIterable, Hashable, Sendable { case track, stations, line, service, passengers; public func title(in:) -> String }`
- `TutorialGoal`:
  - remove `buildSecondStation` and `changeSpeed`. Only the tutorial uses them; `StationMasterAdvice.buildSecondStation` is a different enum.
  - `buildStation` becomes `buildStation(Int)`.
  - add `drawTrack`, `chooseNetworkMode(NetworkToolMode)`, `pickPlatformSite(Int)`, `startPickingStops`, `pickLineStations`, `timeRuns`, `selectStation`.
- New internal types:
  - `enum TutorialSetup: Hashable, Sendable { case layTrack, clearPicks, clearLeftoverSite, clearLineDraft, clearSelection, frameStations }`
  - `public enum TutorialPanel: Hashable, Sendable { case lines, closed }`
  - `public struct TutorialHint: Hashable, Sendable { public let text: String; public let isProblem: Bool }`
- `TutorialStep`:
  - add stored `public let chapter`, `let setup: [TutorialSetup]` (default `[]`) and `public let panel: TutorialPanel?` (default nil); include all three in `==` and `hash`.
  - computed properties:
    - `public var usesDetailsCard: Bool { targets.contains(where: \.isInDetailsCard) }`
    - `public var picksLineStops: Bool` (goal is `.startPickingStops` or `.pickLineStations`)
    - `public var revealsInPanel: TutorialTarget?` (the first of `.createLine` or `.staffLine` among the targets)
    - `public var skipOfferSeconds: Int` (90 for `.earnFare`, else 20).
- `Tutorial`:
  - `public private(set) var reachedByBack = false`
  - `@discardableResult mutating func show(_ index: Int, over: GameWorld, byBack: Bool = false) -> Bool`: returns whether this was the first show, and sets `reachedByBack = byBack`.
  - `func snapshot(forChapterOf index: Int) -> Snapshot`: the earliest shown step in that chapter, else the step's own snapshot.
  - `func snapshot(of chapter: TutorialChapter) -> Snapshot?`
  - `func hasMovedMap(on index: Int) -> Bool`
  - `Snapshot` becomes internal and drops `speed`.
  - `public static let minimumTrackMetres: Int64 = 160`; `static var minimumTrackLength: Int64` (× `WorldCoordinate.unitsPerMetre`).
  - `public static let autoAdvanceDelay: Duration = .milliseconds(800)`
  - remove `isStepDone(in:tool:)`.
  - keep `init(steps:over:)`, which `RealRailwayGameplayTests:195` uses.

**`Sources/GamePresentation/TutorialSession.swift`**
- `isTutorialStepDone`: the goal table above.
- `public var tutorialAdvancesByItself: Bool`: the goal is not `.read`, `!reachedByBack`, and the step is done.
- `public func showNextTutorialStep()`:
  1. guard that the step is done;
  2. on the last step: as today (Finish ends the tour, and `onTutorialCompleted` is called);
  3. otherwise `moveTutorialForward(to: index + 1)`: show the step, run its S if this is its first show, and repeat while the step is an action step that is not the last and is already done.
- `public func showNextTutorialStep(from index: Int)`: does nothing unless `tutorial?.index == index && tutorialAdvancesByItself`.
- `public func skipTutorialStep()`: on an action step that is not the last, moves forward without the goal (then passes done steps). Never calls `onTutorialCompleted`.
- `showPreviousTutorialStep()`: shows with `byBack: true` and runs no setup.
- `startTutorial()` / `startTutorial(atStep:)`: run the shown step's S.
- `public var tutorialHint: TutorialHint?` (the table above).
- `public var tutorialStationIDs: [StationID]`: stations new since `snapshot(of: .stations)`, else `world.stations.suffix(2)`.
- `func tutorialStaffingPlan(_ id: LineID) -> LineStaffingPlan?`: `world.lineStaffingPlan(id, headway: 10)`, memoized on (`worldRevision`, id); it reads `world` first, as `networkDraftPreview` does.
- Setups, none of which sets `message`:

  | Setup | What it does |
  |---|---|
  | layTrack | If `networkMode != .build`, set `networkMode = .build` and nil the three picks. A start tapped during `map.move` is kept. |
  | clearPicks | `networkStart = networkEnd = networkEdgePoint = nil` (all `internal(set)`) |
  | clearLeftoverSite | If `networkEdgePoint != nil && platformStationID != nil`, set `networkEdgePoint = nil` (a fresh pick for B is kept) |
  | clearLineDraft | `clearLineDraft()` (it does not touch `message`) |
  | clearSelection | `clearSelection()`. It sets `message = nil`; that is acceptable here, with no opening message left to keep. |
  | frameStations | `lookAt(framing:)` on the locations of `tutorialStationIDs` |

**Other GamePresentation files**
- `GameSession.swift`:
  - add `@ObservationIgnored var tutorialStaffingMemo: (revision: Int, line: LineID, plan: LineStaffingPlan?)?`
  - `selectTool` leaves out the "Paused while you build… every edit can be undone" message while `tutorial != nil` (Undo is off in the tutorial).
  - `startPickingLineStops(announces: Bool = true)`; existing callers are unchanged.
- `GameFeedback.swift` (P1): `CameraRequest` gains `public let framing: [PlanPoint]` (init default `[]`), and `public func lookAt(framing points: [PlanPoint])` (location = the middle of the points).
- `MapCamera.swift` (P1): `public func framing(_ points: [WorldCoordinate], top: Double, leading: Double, bottom: Double, trailing: Double, padding: Double = PlanCamera.focusPadding) -> PlanCamera`.
  - Returns `self` if every point already lies in the free rectangle minus the padding.
  - Otherwise it calls `zoomedOut()`, never zooming in, at most 8 times while `canZoomOut`, until the points' bounding box fits.
  - It then uses `centered(atX:y:)` so the middle of the box sits in the middle of the free rectangle. Only existing public API is used.
- `GameLauncher.startTutorial(atStep:)`. What it builds before the requested step:
  - From index ≥ `line.open`: one stretch from point(2) to point(13), platforms at point(4) and point(11) (VERIFIED level, as above), then the three picks set to nil.
  - From `line.create`: `selectStation` and `addSelectedStationToLineDraft` for A, then B.
  - From `line.staff`: `createLineFromDraft()`.
  - From `build.done`: `staffSelectedLine(headway: 10)`.

## 4. App changes (UNVERIFIED until macOS CI and a device)

**`TutorialOverlay.swift`**
- Read `session.isTutorialStepDone` once per body.
- Pass `map: step.goal == .read ? nil : map` to the placement.
- On `TutorialOverlay`, which keeps its identity across steps, add `.task(id: AutoAdvance(index:, ready: session.tutorialAdvancesByItself))`. When ready, sleep `Tutorial.autoAdvanceDelay` (1.5 s if `accessibilityVoiceOverEnabled`), then call `showNextTutorialStep(from: index)`. `AutoAdvance` is a small `Equatable` struct (an array literal does not compile).
- P1: move the player's fold choice into the overlay, keyed by chapter.
- `isFolded`:
  - on a done read step or a step reached by Back, the player's choice;
  - on a done step that is moving on by itself, keep the current state (no 0.8 s flash);
  - otherwise the player's choice, or folded-by-itself.
- Card header: `Text("Step \(n) of \(N)")` (the catalog key stays) plus `Text(verbatim: " · " + chapter.title)`.
- Status row, outside the scrolling explanation:
  - the hint (warning colour and lantern for a problem, secondary colour for a tip);
  - else, in regular height only, the catalogued "Complete this step to continue.";
  - trailing: a plain link "Skip this step" / 略過這一步 (`tutorial.skipStep`, hit area at least 44 pt, `Text(verbatim:)`). It shows when the step is not done, the goal is not `.read`, and either the hint is a problem or `.task(id: index)` has waited `skipOfferSeconds`.
- `.onChange(of: hint?.text)`: post `AccessibilityNotification.Announcement` for a problem.
- On the last step the button reads `Text(verbatim: language.text("Finish", "完成教學"))`.
- `FoldedTutorialCard`: its step line also gets the `tutorial.progress` identifier, with the chapter appended; it adds an exclamation mark for a problem hint; its label keeps "Show Tutorial: <title>".
- P2: in regular height, a checklist of the chapter's steps.

**`ContentView.swift`**
- `ControlDetails.isOpen`: replace `if session.tutorial != nil { return true }` with:
  1. `if step.usesDetailsCard { true }`
  2. `else if tool == .select { selectionText() != nil }` (station tags are hidden in the tutorial)
  3. `else { !foldsWhileDrawing }`

  Update the doc comments of `ControlDetails` and `ControlDetailsToggle`.
- `.onChange(of: session.tutorial?.index, initial: true)`: for `.lines`, open Lines if it is closed; for `.closed`, set the panel to nil if it is beside the map.

**`LinesPanel.swift`**
- `.onChange(of: session.tutorial?.index, initial: true)`: when `step.picksLineStops && !isPickingLineStops && lineDraft.count < 2`, call `startPickingLineStops(announces: false)`. That keeps the bottom StatusBanner from shrinking the form.
- Wrap the `Form` in a `ScrollViewReader`. Give the two buttons `.id(TutorialTarget.createLine)` and `.id(TutorialTarget.staffLine)`.
- `.onChange(of: RevealKey(step id, lineDraft.count, selectedLineID), initial: true)`: when there is a `revealsInPanel` target, call `Task.yield()` and then `proxy.scrollTo(target, anchor: .center)`.
- Leave the `tutorialPanelTarget` marks alone.

**Smaller marks**
- `MapBuildConfirm.swift`: add `.tutorialTarget(.mapConfirm)` on the ✓ button.
- `InspectorView.swift`: add `.accessibilityIdentifier("inspector.ridership")` and `.tutorialTarget(.ridership)` on the Ridership button.

**`MapView.swift`**
- In `onChange(of: cameraRequest)`: a non-empty `framing` uses `projection.framing(…, insets + safeArea)`. A one-point request (the station master, decision 177) behaves as today.
- P1: while the step targets `.newStations`, mark an invisible `Color.clear` frame around the screen points of `tutorialStationIDs`, padded by 28 pt. Place it with `.position` (not `.offset`), with `allowsHitTesting(false)` and hidden from accessibility. The overlay's existing outline draws the highlight, so nothing new is drawn on the map.

## 5. Test changes

**`TutorialSessionTests`** (Linux)
- `stepIDs`: the 19 ids above.
- `testNextWaitsForEachStepAndDoneEndsTheTutorial`: walk by id on the new game and on the demo, recording the visited ids. `time.play` is passed in both (VERIFIED: Done resumes both clocks). Actions per step:

  | Step | Actions and checks |
  |---|---|
  | build.network | `selectTool(.network)` |
  | map.move | `mapDidMove()` |
  | track.draw | tap point(2); assert the hint is "Now tap where it ends."; tap point(13) (176 m) |
  | track.build | `buildNetworkTrack()` |
  | station.mode | assert `networkStart == nil`; `setNetworkMode(.platform)` |
  | station.first.site | tap point(4) |
  | station.first.build | `addNetworkPlatform()` |
  | station.second.site | assert `networkEdgePoint == nil` and that `message` still holds A's "Within 800 m"; tap point(11) |
  | station.second.build | `addNetworkPlatform()` |
  | line.open | `startPickingLineStops(announces: false)` |
  | line.stations | assert `cameraRequest?.framing.count == 2` (P1); `tapMap` on A, check the "other station" hint, then `tapMap` on B |
  | line.create | `createLineFromDraft()` |
  | line.staff | `staffSelectedLine(headway: 10)` |
  | build.done | `selectTool(.select)` |
  | first.fare | `runUntilFares` |
  | station.select | assert the selection is nil; `selectStation(A)` |
  | station.ridership, end | read |

  Advance with `showNextTutorialStep(from:)` after asserting `tutorialAdvancesByItself`; on read steps use `showNextTutorialStep()`.
- `testGoalsAreRead…`: draw the new stretch at y = 6144 (192 m). The edge that was already there does not count.
- `testBackToTheTrackStepKeepsItDone`: Next lands on `station.mode` (track.build is passed). Back lands on `track.build`, done, with `reachedByBack` true and `tutorialAdvancesByItself` false. After restarting, `track.draw` is not done.
- `testTwoStationsOnTheFirstStationStepAreEnough`: two platforms on `station.first.site`, then Next, lands on `line.open`.
- `testTheMapStepWaitsForTheMapToMove`: the map step is index 1; zero edges at the end.
- `testTheTutorialStartsAtALaterStep…`: launch at `line.open` (2 stations, not done, no `networkEdgePoint`); `startPickingLineStops` makes it done. Also launch at `line.create` (the draft has 2 stops) and at `line.staff` (the line exists). An unknown step starts at index 0.
- `testEveryTargetHasItsOwnStableName`: append `"map.build.confirm", "inspector.ridership", "map.stations"`.
- `testTheStepsReadInBothLanguages`:
  - new title arrays, and the new step 0 Chinese body;
  - caps: English body ≤ 90, Chinese body ≤ 36 (without the note), English title ≤ 34, Chinese title ≤ 14;
  - every step has a target;
  - titles are unique per language.
- `testTheStepsSayShortTripsWalkOnlyWhereTheyDo`: uses `station.second.site`; the suffix is `"needs two stations."`.
- Replace `testTheSpeedStepIsDoneWhileTheSpeedDiffers` with `testTheTimeStepWaitsForTimeToRunAndIsPassedWhenItDoes`: pause by hand before Done and `time.play` shows; otherwise Done lands on `first.fare`.
- Update the loop counts of the fare and service tests, or walk them by id.
- New tests:
  - `testAStepDoneAheadIsPassed`
  - `testTheTrackMustHoldTwoStations` (64 m preview → tip; build → lengthen hint; extend → passes `track.build`)
  - `testSkippingAStepMovesOnWithoutItsGoal` (no effect on read steps or the last step; never calls `onTutorialCompleted`)
  - `testNextFromAnOldStepDoesNothing`
  - `testTheStepsSetUpWhatTheyNeedWithoutWipingTheMessage`
  - `testHintsSayWhatIsMissing` (preview problem, joins A, overlap failure message, no route, time paused)
  - `testOnlyTheModeAndRidershipStepsNeedTheDetailsCard`
  - `testChoosingNetworkInTheTutorialLeavesOutThePauseMessage`

**Other Linux tests**
- `TutorialCardPlacementTests.testAReadStepBesideAPanelLeavesThePanelInSight`: target and required `sidePanel`, `map: nil`.
- `MapCameraTests.testFramingFitsThePointsInTheFreePartOfTheView` (P1): unchanged when the points are already free; otherwise zooms out only and centres in the inset rectangle.
- Unchanged but re-run: `RealRailwayGameplayTests` (looks the step up by `.startService`), `UndoSessionTests`, `OnboardingTests`, `AchievementsTests`, `BuildPauseSessionTests`, and the existing placement cases.
- Local checks: `swift build --build-tests -Xswiftc -warnings-as-errors`, then `swift test --skip-build --filter 'TutorialSessionTests|TutorialCardPlacementTests|MapCameraTests|RealRailwayGameplayTests|UndoSessionTests|BuildPauseSessionTests|OnboardingTests'`.

**`TutorialUITests`** (names kept; `ios-build.yml` is untouched; the iPad job runs anyway because tutorial files change)
- Add a helper `waitForStep(title:)` that polls up to 10 s for the `tutorial.title` label or the `tutorial.unfold` label.
- `checkNavigation` (×3):
  - Network → Back appears by itself → Next disabled on `map.move` → Back → step 1, Next enabled.
  - Assert Back does **not** come back within 2 s. A slow runner cannot make this check fail; it can only miss a bug.
  - Then the old Select/Network toggles with `waitForEnabled`; no automatic move after Back.
  - Rotation, Skip and the menu restart are unchanged.
- `testBuildingTrackEnablesNextAndSkipEnds` (body only; the comment says the name is kept for the gate list):
  1. Network.
  2. Tap "Zoom out" (uncovered) → `waitForStep("Tap the start, then the end")`.
  3. `freePoints(…, gap: 220)`: at 1 m per point that is about 220 m. The existing Build Track exclusion covers the iPad's open details card.
  4. Tap both points → `map.build.confirm` hittable and not covered. Tap it, with the existing retry once if it still exists.
  5. `waitForStep("Tap Platform")` → the "Platform" segment is hittable and not covered; Next disabled, Back present → Skip closes the tutorial.
- `testTheLineStepLeavesTheLinesPanelUsable` (body only):
  1. `-tutorial-step line.open` → tap `entry.lines` → `line.draft.pick` reads "Stop Picking" without being tapped → `waitForStep("Tap one station, then the other")`.
  2. `map.build.confirm` does not exist.
  3. After 1 s, the card or folded pill leaves `line.draft.pick` uncovered and hittable. Do not tap it: that would stop picking.
  4. Fold and unfold; Skip hittable; Next disabled.
- New, full lane and iPad only, **not** in the gate: `testCreateLineAndBuyAreInReach`.
  1. `-tutorial-step line.create` → `line.draft.create` is scrolled into view, hittable and uncovered → tap.
  2. `line.staff.start` hittable → tap.
  3. "Tap Done to stop building", with Lines closed → `selectTool("tool.select")` → `waitForStep("Wait for your first fares")`.
- All waits use 10 s expectations. The only fixed wait is the 2 s negative check.

## 6. Risks and what to check on a device

1. **Automatic move.** Check that 800 ms feels right on an iPhone held sideways and on an iPad, and that VoiceOver focus moves to each new title.
2. **The 160 m minimum.** At the opening zoom on a phone (0.5 m per point) it is 320 pt. Once the details card is closed, or after zooming out at `map.move`, it fits. Watch whether players read the "make it longer" tip, and whether "near one end / the other end" gets B placed on the first try.
3. **Line steps on 874×402.** With the Lines panel open (about 430 pt), check that framing puts both stations in the free part and that the card goes beside them or folds. With `-tutorial-step line.stations` the request runs before the panel opens; accepted for tests only.
4. **Panel scrolling.** Check that `ScrollViewReader.scrollTo` on `Form` rows brings Create Line and Buy above the StatusBanner on a phone.
5. **The ✓ pill.** Its anchor sits inside an `.offset` view. Check that the overlay gets its true frame; the gate test asserts the card does not cover it.
6. **No details card on phone map steps.** Mode switching is only possible at `station.mode`; the setups keep the mode right otherwise. Check that the catchment caption on the ✓ pill is readable.
7. **Restart over an existing network** (game menu, demo): the passing and "new since chapter" rules, the "joins X" hints and "Skip this step" are the ways out.
8. **First fares** take about 42 s at normal speed from 00:00 (VERIFIED game time). Check that the "trains start at 06:00" tip and the skip offer at 90 s are visible.
9. **Separate bug-queue item (not this PR).** In normal play, `addNetworkPlatform` keeps `networkEdgePoint`, so the ✓ bubble stays and a second ✓ gives `.invalidPlatform`. The fix changes `NetworkBuildingSessionTests.testAPlatformGetsANewStationAtItsMiddle`.

**Docs for the PR**
- Decision 188.
- Notes under decision 47 (item 4: the reference's automatic panel opening, `openUI`, now exists as `TutorialPanel` and LinesPanel's own picking; now 19 steps), decision 125 (`time.speed`/`changeSpeed` replaced by `build.done` + `time.play`) and decision 136 item 4 (the tutorial no longer forces the card open).
- The tutorial section of `UI_INTERFACES.md`.
- `RAILWAY_REFERENCE_MAPPING.md` Stage C5 rows:

  | Reference | Here |
  |---|---|
  | `TUTORIAL_STEPS[n].openUI` | `TutorialPanel` and LinesPanel picking by itself |
  | `data-tt-confirm-prompt` | `tutorialHint` |
  | city-world `LP` | one action per step, moving on by itself |
  | `zs.short` | titles that are the instruction |
  | `transportTutorialBuildHsr` | not ported (feature freeze) |

  These names come from the designs' reading of the private reference at `1563ad0`. Per CLAUDE.md, re-check them in the reference before writing the PR.

Files:
- /home/user/railway-game-ios/Sources/GamePresentation/Tutorial.swift
- /home/user/railway-game-ios/Sources/GamePresentation/TutorialSession.swift
- /home/user/railway-game-ios/Sources/GamePresentation/GameSession.swift
- /home/user/railway-game-ios/Sources/GamePresentation/GameFeedback.swift
- /home/user/railway-game-ios/Sources/GamePresentation/MapCamera.swift
- /home/user/railway-game-ios/Sources/GamePresentation/GameLauncher.swift
- /home/user/railway-game-ios/RailwayGameApp/Views/TutorialOverlay.swift
- /home/user/railway-game-ios/RailwayGameApp/Views/ContentView.swift
- /home/user/railway-game-ios/RailwayGameApp/Views/LinesPanel.swift
- /home/user/railway-game-ios/RailwayGameApp/Views/MapBuildConfirm.swift
- /home/user/railway-game-ios/RailwayGameApp/Views/InspectorView.swift
- /home/user/railway-game-ios/RailwayGameApp/Views/MapView.swift
- /home/user/railway-game-ios/Tests/GamePresentationTests/TutorialSessionTests.swift
- /home/user/railway-game-ios/Tests/GamePresentationTests/TutorialCardPlacementTests.swift
- /home/user/railway-game-ios/Tests/GamePresentationTests/MapCameraTests.swift
- /home/user/railway-game-ios/RailwayGameApp/UITests/TutorialUITests.swift