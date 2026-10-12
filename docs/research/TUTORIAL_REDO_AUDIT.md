# 教學重做：逐步稽核（2026-10-12）

I audited all 11 steps from the code at branch `claude/tutorial-card-unblock` (HEAD `a4120fe`; another session pushed this commit while I worked). I changed no repo files.

- **Read from code:** every claim below, unless marked otherwise.
- **Placement simulation (ran on Linux, numbers are rough):** I ran a scratch copy of `TutorialCardPlacement.swift` with swiftc. It used the measured 874×402 phone frames from `TutorialCardPlacementTests` (game area 750×381 pt). The card heights were my estimates from the text lengths, so the card frames are approximate.
- **Not run:** the app, the iPad layout, device screenshots.

## State when the tutorial starts (`GameLauncher.startTutorial`)
- A new blank-map game, management mode, $3M. The clock runs at `.normal` from 00:00 on day 1.
- Lines only run 06:00–24:00 (`ServiceWindow.standard`). One town always sits at the middle of the map, where the camera starts.
- Tool is `.select` and no panel is open.
- The details card is **forced open** for the whole tutorial (`ControlDetails.isOpen` returns true when `tutorial != nil`). It is hidden only while a side panel is open.
- The tool rail shows, with its "Done" button highlighted because the tool is Select.
- Undo and Redo are hidden and refused.
- On the phone, the forced details card leaves a free map of only 359×243 pt; with the Lines panel open it is 284×243 pt.

## Per-step friction

**1 `build.network`**: "Tap Network…" (65 English chars / 21 Chinese)
- **Actions:** 1 tap, on the rail's Network button or the dock's Build button (both select the network tool).
- **Goal:** `tool == .network`.
- **Friction:**
  - The details card shows a different instruction at the same time: "Tap Build, then Network…".
  - The rail's "Done" is highlighted.
  - On a phone the rail can be icons only.
  - Choosing Network pauses the game and shows "…press play to go on". That invites pressing play, which inverts step 8 later.
  - Simulated card: 320×198 at the left. It covers the other rail buttons, Lines and the zoom buttons; harmless here.
- **Severity:** P2.

**2 `build.track`** (224 / 82 chars)
- **Actions:** tap start, tap end, then Build Track (details card) or ✓ (map pill). That is 3 taps, or 1 drag plus ✓.
- **Needs:** network tool, mode `.build`.
- **Goal:** any new edge (`buildTrack`).
- **Leaves behind:** `networkStart` = end node, shown as a start flag.
- **Friction:**
  - The English text says "Build mode", but the segmented control reads **"Lay | Platform | Remove"** (`NetworkToolMode.title`). The Chinese 鋪設 matches.
  - The "90° / 22 m" rule is jargon at this point.
  - The text never mentions the ✓ pill under the finger.
  - Phone simulation: the card is 320×246 at x16 and covers about 53% of the map. That leaves a band about **104 pt wide** (x≈348–440) for both taps, and the zoom buttons sit in that band.
  - A wrong stretch can't be undone.
- **Severity:** P1.

**3 `map.move`** (143 / 51 chars)
- **Inherits:** start flag and mode `.build`.
- **Goal:** `mapDidMove()` while this step is shown.
- **Friction:**
  - "Drag with one finger" fails if the drag starts on the track or the flag: `networkDragDraws` draws a new stretch instead. That is likely, because the camera is centred on the new track and the band is about 100 pt wide.
  - A single tap picks an end and pops the ✗/✓ pill; ✓ builds more track.
  - Panning can take the player out of the middle town, which feeds the step 9 stuck path.
  - The simulated English card touched the zoom buttons and folded itself. This depends on my height estimate; the UI test checks it on the Simulator.
- **Severity:** P1.

**4 `build.firstStation`** (142 / 50 chars)
- **Actions:** tap the Platform segment, tap the track, then Add Platform or ✓.
- **Needs:** mode `.platform`, and the tap within reach of the track.
- **Goal:** a new station (`buildStation`).
- **Friction:**
  - A tap off the track does nothing visible (`networkEdgePoint` = nil, no message).
  - In platform mode the details card grows (population button, stepper, station picker, name field). On a phone **Add Platform likely scrolls below the 270-pt card** (estimated about 336 pt of content; not checked on a device). `tutorialClip` then drops the outline, and the ✓ pill carries no "Add Platform" text.
  - Nothing points the player at the pill's caption ("Within 800 m: N residents"), so nothing ties the station to the town.
  - **After success `networkEdgePoint` is never cleared** (`addNetworkPlatform`, `NetworkSession.swift` ~398–455). The ✗/✓ pill and the 800 m ring stay on the new station. Pressing ✓ again fails with `.invalidPlatform`.
- **Severity:** P1.

**5 `build.secondStation`** (203 / 74 chars, including the 2 km distance note)
- **Actions:** Lay segment, tap the track's end node, tap a new end, Build/✓, Platform segment, tap the new track, Add Platform/✓. That is **7 actions on one card**.
- **Inherits:** mode `.platform`; the pill still on station A; `platformStationID` = A; `networkStart` = nil (switching modes clears it).
- **Goal:** `buildSecondStation`.
- **Friction / stuck:**
  - "Extend" needs a tap exactly on the track end. A tap on empty map starts a **disconnected track**; step 5 still passes, step 6 still creates a line, and **step 7 then has no Buy button. The player is stuck (P0 path).**
  - A tap within 32 m of A (`platformStationReach` 2048) adds a platform to A instead of a new station, so the goal isn't met.
  - "32 m" can't be measured by the player, and the note's "up to 2 km" sets a conflicting scale.
  - Same Build/Lay wording mismatch.
  - **Leaves the platform pill on station B.** This is the leftover bubble in the owner's step 6 screenshot.
- **Severity:** P0 path, otherwise P1.

**6 `line.create`** (199 / 71 chars, 5 actions)
- **Actions:** tap Lines (the panel slides in: 375 of 750 pt on the phone, 420 pt on iPad), Pick on Map, tap station A, tap station B, scroll if needed, Create Line.
- **Needs:** `GameScreenState.panel == .lines` (only the app knows this); both stations visible left of the panel.
- **Goal:** any new line.
- **Friction:**
  - The camera is never recentred. Stations on the right half of the phone screen are hidden under the panel.
  - Phone simulation: the card is 240×200 with its text scrolling (278 pt of content → 200). It leaves a band about **109 pt wide** (x≈256–365) for tapping both stations, shared with the zoom buttons **and the leftover platform pill**. The pill can catch a station tap, and its ✓ gives an error.
  - Folding the card hides the instructions.
  - Picking 2 stops adds the Picked row, route strip and stop summary. **Create Line then drops below the visible area on a phone** and loses its outline.
  - The panel's bottom status banner (the picking hint) shrinks the visible list further.
  - Tapping a station *before* opening Lines picks a platform site instead of selecting it.
  - A line between disconnected stations is accepted, which leads to the step 7 stuck path.
- **iPad:** works, unless the stations sit under the card or the panel.
- **Severity:** P0 on the phone (PR #429 makes it doable but cramped), P1 on iPad.

**7 `line.staff`** (187 / 58 chars)
- **Actions:** scroll past the now-empty New line section (about 250 pt: hint, Pick on Map, Add Selected, Remove Last, a disabled Create Line), pick a headway, tap "Buy N and Start Service".
- **Goal:** `startService`. `staffSelectedLine` sets target headways, so the goal passes.
- **Friction:**
  - The Buy button is below the fold on a phone (on iPad landscape, possibly). It isn't outlined until scrolled into view.
  - Simulation: the card is 320×246 at x215–535 and **covers the left ~170 pt of the panel and the speed control** until Buy becomes visible.
  - The disabled Create Line at the top reads as "the line wasn't made".
  - **Stuck:** for a line with no track joining its stations, `lineStaffingPlan` is nil, so there is a warning and no button. Only Back or Skip remain.
- **Severity:** P0 path, P1 otherwise.

**8 `time.speed`** (121 / 35 chars)
- **Actions:** 1 tap (▶ or the speed menu).
- **Inherits:** normally paused since step 1 (`isPausedForBuilding`).
- **Goal:** `world.clock.speed != snapshot`.
- **Accidental:** if the player pressed play earlier (the step 1 banner invites it), the only button is ⏸. Pressing it completes the step but **stops time**, and step 9 waits until they press ▶ again. Picking the current speed from the menu does nothing.
- **Missing:** the text doesn't say trains won't move before 06:00.
- **Severity:** P1.

**9 `first.fare`** (250 / 86 chars, the longest text)
- **Actions:** wait.
- **Goal:** a `fareRevenue` ledger row after the step's snapshot (settled hourly).
- **Friction:**
  - The clock is around 00:xx and lines open at 06:00, so the player waits about 6 game hours with no explanation. That is about 36 s at normal speed, if the app ticks 10 times a second; I did not check the tick rate.
  - If time is paused, nothing happens.
  - **Stuck:** stations built outside the middle town after panning get no riders, and the step never completes.
  - Stations close together keep only 10% of trips (`DistanceDemand.nearShare`): slow, but never zero.
- **Severity:** P1, with a P0 path.

**10 `station.ridership`** (197 / 61 chars)
- **Goal:** `.read`, so Next is always enabled.
- **As written, the step can't be done:**
  - The tool is still Network, so a map tap goes to `tapNetwork`. It picks a platform site, the pill reappears, and ✓ would build and spend money.
  - `InspectorView` shows the network draft text, not the selection, so there is no Ridership button.
  - If the Lines panel is still open, the tap does select the station, but the details card holding Ridership is hidden behind the panel. Long-press needs the Select tool and the panel closed.
- **Hidden actions:** tap Done on the rail, close Lines, tap the station, tap Ridership. In practice the player just presses Next.
- **Severity:** P1, and the step teaches nothing.

**11 `end`**: fine. After Done the tool stays Network, so the rail stays.

## Problems that run across steps
1. The platform pill is left over because `addNetworkPlatform` keeps `networkEdgePoint`. `MapBuildConfirm` shows it whenever `tool == .network && networkMode == .platform && networkEdgePoint != nil`, panel open or not. There are two fixes:
   - **Tutorial-only:** call `clearNetworkDraft()` when the tutorial moves to the next step.
   - **General:** clear `networkEdgePoint` after a successful platform. This is arguably a normal-play bug too, but it changes behaviour outside the tutorial.
2. The tool never goes back to Select, so steps 6–10 run under the network tool. That affects map tap routing, the inspector, and the build pause.
3. The forced-open details card halves the phone map and overrides decision 136 (on a phone the details card folds while track is drawn).
4. There is no camera guidance. The existing `session.lookAt(_:)` → `cameraRequest` hook (decision 177) could recentre the map. But `MapView` uses `projection.centered(on:)` on the whole view, so I'd need to check it allows for the panel width.
5. Targets inside scrolling lists (Add Platform, Create Line after picking, Buy…) lose their outline and their "keep free" status. Nothing scrolls them into view.
6. Steps bundle several actions behind one end goal (step 4: 3, step 5: 7, step 6: 5), with no feedback in between.
7. The texts are long (English 120–250 chars, Chinese 35–86). On the phone the card is about 200–262 pt tall against a 243-pt map, and in most steps it covers about 40–53% of the free map.
8. Wording: English "Build" against the UI's "Lay". "Done" (完成) means three things: leave the rail, finish the tutorial, close a panel.
9. Undo is hidden and Remove is never taught, so a disconnected track can't be fixed during the tutorial.
10. Restarting the tutorial from the game menu keeps whatever panel and tool are open (Lines open means the details card is hidden for steps 2–5). On a real-world map, step 4 can hit the grade refusal (decision 164).

## Finer goals the session can already observe (`GameSession` / `GameWorld`, read-only, GameCore unchanged)
- **Network mode chosen:** `networkMode == .platform` or `.build` (`public internal(set) var networkMode: NetworkToolMode`).
- **Track ends picked:**
  - start: `networkStart != nil`, `networkStartPlanPoint`
  - end and preview: `networkEnd != nil`, `networkPreview != nil && networkPreview?.problem == nil` (it also has `.cost`)
- **Platform site picked:** `networkEdgePoint != nil`, `platformSitePlanPoint`.
- **Site reaches people:** `platformSiteCatchment` (`LandTotals`, `.residents + .jobs > 0`).
- **Site would open a new station** (not join A): `platformStationID == nil`.
- **Site is level:** `networkPlatformGrade == nil`.
- **Second station joined to the first by track** (guards the step 7 stuck path): `world.stationsAlongTrack(from:to:) != nil` (`LineDraftRoute.swift`).
- **Picking started** (a stand-in for "Lines panel open + Pick on Map"): `isPickingLineStops == true`.
- **Stops picked:** `lineDraft.count >= 1`, then `>= 2`.
- **Picked stops joined by track:** `lineDraftRoute != nil`.
- **Create Line enabled:** `lineDraftStops.count >= 2`.
- **New line can actually run:** `world.lineJourney(id) != nil` or `world.lineStaffingPlan(id, headway:) != nil`.
- **New line selected:** `selectedLineID`, `selectedLine` (the Buy section shows while `trains.isEmpty`).
- **Time running** (better than `changeSpeed` for step 8): `!world.clock.isPaused`. Related: `world.clock.runningSpeed`, `isPausedForBuilding`, `isPausedForEvent`.
- **Line is in its service window now:** `world.serviceLevel(of:at: world.clock.now) != nil`.
- **Trains on track / passengers waiting:** `world.trains` with `position != nil`, `world.assignedLine(of:)`, `MapLayers.waitingPassengerCounts(in:)`.
- **Fares arriving:** existing `earnFare`, and `incomePulse`.
- **Back to Select / station selected** (for step 10): `tool == .select` (`chooseTool(.select)`), then `selectedStationID != nil` or `selectedStation`.
- **A failure to explain on the card:** `message?.kind == .failure`, `messageSerial`.

## State only the app has
- `GameScreenState.panel` (which panel is open, including `.station` for Ridership).
- `detailsChoice` / `ControlDetails.isOpen`.
- `mapCamera` (`PlanCamera`): whether the stations are on screen.
- The card's `folded` / `foldedItself`.
- `LinesPanel`'s `staffHeadway`, `staffType`, `staffCars` and the list's scroll position.
- `NetworkControls`' `showsAdvanced` and `showsSection`.
- `@AppStorage("mapPopTravelMode")`.
- The rail's compact layout.
- `TutorialTargetBounds` (which targets are visible).

The bridges between app and session today are `mapDidMove()` (app to session) and `lookAt(_:)` / `cameraRequest` (session to app).

## Constraints on a rewrite
- `TutorialUITests.testBuildingTrackEnablesNextAndSkipEnds` depends on the order network tool → track (Build Track) → map step with "Zoom in" → a step that waits for a station.
- `testTheLineStepLeavesTheLinesPanelUsable` and `GameLauncher.startTutorial(atStep:)` depend on the id `line.create`; the launcher pre-builds for any step at or after it.
- `TutorialSessionTests` assumes 11 steps and pins the goal behaviours.
- `RealRailwayGameplayTests:194` looks up the step whose goal is `.startService`.

Main files: `/home/user/railway-game-ios/Sources/GamePresentation/Tutorial.swift`, `/home/user/railway-game-ios/Sources/GamePresentation/NetworkSession.swift`, `/home/user/railway-game-ios/RailwayGameApp/Views/MapView.swift` (map tap routing ~340–356, `cameraRequest` ~589), `/home/user/railway-game-ios/RailwayGameApp/Views/ContentView.swift`, `/home/user/railway-game-ios/RailwayGameApp/Views/LinesPanel.swift`. The simulation script is at `/tmp/claude-0/-home-user/a051992b-9649-52c5-aae6-9efdd98b0c53/scratchpad/place/main.swift`.