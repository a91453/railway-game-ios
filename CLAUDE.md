# CLAUDE.md

Instructions for Claude Code sessions in this repository.

## Project

A native iPhone / iPad railway and city management game (long-term goal: gameplay
depth close to the A-Train series). Current status, doc map and decision
index: `docs/OVERVIEW.md`; the one priority list:
`docs/research/NEXT_PRIORITIES_2026-10-12.md`; stage history: `docs/ROADMAP.md`.
Later stages port the owner's web transport game (docs/WEB_REFERENCE_STUDY.md)
and may also absorb implementation and data from the owner's
`a91453/railway-reference-private` repository. Treat `Ci/`, `Railway/`,
`Simulator/`, and `MapBuilder/` there as authorized implementation sources, not
reference-only material.

Port and reuse faithfully. When useful, directly copy, vendor, adapt, translate,
wrap, bundle, or import source code, data, text, configuration, algorithms,
schemas, UI behavior, and assets from the owner's projects. This explicitly
includes JavaScript/CSS/HTML, images, fonts, icons, station/network/service data,
raw timetables, live or real-time data and feeds, routing/operational logic,
balance values, constants, and complete feature implementations.

Do not reject a useful source feature because it was previously labeled
"reference", "research", "not adopted", or "later stage". Swift translation is
required only where the target layer actually needs Swift (especially
GameCore); otherwise direct reuse or an adapter is allowed. Existing
Stage/Phase boundaries are sequencing guidance, not gates: when a reusable
feature spans several stages, its required dependencies may be ported together.

Preserve source behavior and data semantics unless a deliberate project change
is documented. GameCore's platform-independent/deterministic rules still apply
to authoritative GameCore behavior; adapt only what those rules or the target
platform genuinely require.

Assume content supplied by the owner in these reference repositories is
authorized for project use. Do not invent a blanket third-party prohibition.
When a particular embedded dependency or asset carries an explicit license or
attribution requirement, preserve and comply with that requirement; replace it
only when its actual terms require replacement. Secrets, credentials and
personal data remain excluded from source control.

Where the reference has nothing for a feature, list the gap in the PR and
implement the missing behavior as needed.

Reference check (every new Stage): attach or clone
a91453/railway-reference-private, read the files the Stage can reuse, and put a
mapping table in the PR (reference file/function → target file/function, with
any fixed-point scale where relevant). Check all available implementation
sources: `Ci/reference_snapshot/`, `Railway/site_archive_clean/`,
`Railway/railway_game_reference_clean/` (start with its
`00_READ_ME_FIRST.md`), `Railway/city_world_reference/` (start with its
`00_READ_ME_FIRST.md` and `source/`), `Simulator/` (start with
`REFERENCE_REFRESH_2026-10-07.md` and `SANITIZATION_REPORT.md`, then inspect
`reference_snapshot/` for reusable simulator runtime/UI, track geometry,
templates/data, and 3D assets), `MapBuilder/` (start with
`REFERENCE_REFRESH_2026-10-08.md` and `SANITIZATION_REPORT.md`, then inspect
`reference_snapshot/` for reusable route/station editor behavior, map geometry,
map interactions, state/UI logic, styling, and related data assets),
`OpenWorld/` (start with `REFERENCE_REFRESH_2026-10-10.md` and
`SANITIZATION_REPORT.md`), `Railway/train_loop_reference_clean/` (start
with its `00_READ_ME_FIRST.md`), `Railway/island_city_reference_clean/`
(start with its `00_READ_ME_FIRST.md` and `MODULE_MAP.json`; a grid city
simulation: residents, jobs, land value, procedural models; it uses
`Math.random()` and grid state, so port its rules and values, not its
state) and `Railway/street_scene_reference_clean/` (start with its
`00_READ_ME_FIRST.md`; a Three.js street scene with LOD building models,
pedestrians and vehicles, day and night; its OSM data keeps its ODbL
attribution), `Railway/commuter_journey_reference_clean/` (start with its
`00_READ_ME_FIRST.md` and `REFERENCE_COMPARISON.md`; a Hong Kong metro
commuter game in Three.js: crowds, queues, train doors, interchange
wayfinding, station shops; it uses `Math.random()` and live input, so port
it into the presentation layer, not GameCore).

When a problem is hard (an algorithm, a data source, a performance or
platform limit, a design with no obvious answer), look for prior work before
inventing a solution, in this order:

1. The owner's reference repository: whether something in it can be ported
   (the sources above). It is authorized; port it as described above.
2. Open-source projects on GitHub that solve the same problem (for example
   OpenTTD, Simutrans, A/B Street, MapLibre, OSM tooling, Swift packages).
   Search the web or clone a public repository into the scratchpad; the
   session's GitHub tools are scoped to this project's repositories, so do
   not use their code search for other repositories. Read the project's
   license before reusing anything: code under a permissive license (MIT,
   BSD, Apache-2.0, zlib and the like) may be ported with its copyright
   notice and license kept; copyleft code (GPL, LGPL, AGPL, MPL) and code
   with no license is read for ideas only, never copied, unless the user
   decides otherwise. Data keeps its own license and attribution (for
   example OpenStreetMap's ODbL, credited in `DataSourceCredits`).

When neither has anything usable, write it yourself, without waiting to ask:
the search decides what to reuse, not whether the work goes ahead.

Say in the PR what was searched and what was found: the reference rows go in
the mapping table, an outside project with its URL, license and what was
taken from it, and "nothing usable" when nothing was (and the code is this
project's own). Adding a dependency is still avoided unless the user agrees
(Workflow).

OpenStreetMap data of Taiwan (places, land use, anything tagged) is read from
a whole extract, not asked of Overpass: osmtoday.com's `asia/taiwan.pbf`
(some 350 MB; this environment can download it, Geofabrik's is blocked),
read with pyosmium (`pip install osmium`, BSD 2-Clause; the owner agreed to
it for the data tools, ARCHITECTURE decision 93). The extract takes a minute;
the public Overpass servers are often too busy (hours of 504s), and asking by
0.25° tiles reaches across the border (Kinmen's tile counted Xiamen's places).
`tools/real-world-population/README.md` has the commands; a new tool that
needs OSM data reads the same extract.

- `Sources/GameCore/` — Swift package with the simulation core. **Authoritative
  source of truth** for all game state. Tests: `Tests/GameCoreTests/`.
- `RailwayGameApp/` — minimal SwiftUI app (Presentation). Its Xcode project
  (`RailwayGame.xcodeproj`, with the shared `RailwayGame` scheme) is generated
  from `RailwayGameApp/project.yml` by XcodeGen and **committed**, because
  Xcode Cloud needs it in the repository. `project.yml` is the source of
  truth: change it, regenerate (see below), and commit both. Never hand-edit
  the `.xcodeproj`.
- `GoldenScenarios/` — portable golden scenario fixtures (JSON) that pin
  GameCore behavior; run by `Tests/GameCoreTests/GoldenScenarioTests.swift`.
- `SaveFixtures/` — a committed save of each save version (`SavedGame`) that
  every later build must still load; run by
  `Tests/GameCoreTests/SavedGameTests.swift` (`SaveFixtures/README.md`).
- `ReplayFixtures/` — recorded network command streams with state checksums
  at intervals (the reference's desync replay) that every later build must
  replay to the same states; run by
  `Tests/GameCoreTests/ReplayFixtureTests.swift` (`ReplayFixtures/README.md`).
- `.github/workflows/` — `ci.yml` (the Swift package on Linux with Swift 6.4
  only: a push to `main` and a manual run build everything and run every
  test with the campaigns not reduced, split into parallel shards by
  `.github/scripts/swift-shards.sh`, which also proves each job ran exactly
  its tests. A pull request builds everything but runs the tier its changed
  files need (ARCHITECTURE decision 185, `swift-shards.sh plan`): every shard
  for GameCore, the package, the CI scripts or a test file other test files
  use, or two edited campaigns (or one beside GamePresentation); all the
  GamePresentation tests (in three jobs) for GamePresentation, its tests, the
  app's bundled data or a `tools/` file they read; the classes that read the fixtures
  for `GoldenScenarios/`, `SaveFixtures/` or `ReplayFixtures/`; the classes a
  GameCore test file declares when no other file uses it; the union when
  several apply. The label `full-ci` runs every shard (add it, then re-run
  the pull request's run). Pull requests and pushes to `main` that change
  nothing the package builds or tests skip the Swift jobs, and the `Swift CI
  (gate)` job always reports (but on a cancelled push run of `main`, decision
  187); `main`'s branch rule requires that job, so never rename it. Pushes
  to `main` share one concurrency group: a burst of merges runs
  the run in progress and the newest one, the replaced runs show as
  cancelled with no result of their own, and a push is compared with the
  head of the last successful push run so nothing goes untested; when it
  turns red, run `ci.yml` by hand on the replaced commits to bisect),
  `ios-build.yml` (macOS: committed-project drift check, Xcode Simulator
  build, iPhone UI tests, the Traditional Chinese translation check; not run
  for changes the app cannot see: docs, the
  package's tests and fixtures, `Web/`, `tools/`, `.claude/`, the other
  workflows' files.
  A pull request runs a short gate list of UI tests,
  and the iPad tutorial tests only when it touches the tutorial's own files;
  the full lane runs every UI test, its iPhone tests split over two jobs
  (`FULL_LANE_SECOND_JOB` names the second's classes), and the iPad
  tutorial tests (the
  missing-button proof nightly and on request) on `main` after a merge, at
  most every three hours (`ios-full-lane.yml` starts it unless `main`'s
  newest commit already had one or one ran in the last three hours; its
  schedule is only a fallback, GitHub runs it hours late or not at all),
  nightly and by hand, and its red result does not block a pull request),
  `release-archive.yml` (unsigned Release device archive; manual, nightly,
  and on PRs that change project settings, the app's entry point, the asset
  catalog, the String Catalog or the localized Info.plist strings), `testflight.yml`
  (signed archive → IPA → App Store Connect; `workflow_dispatch` from `main`
  only, secrets in the `testflight` environment), `testflight-checks.yml`
  (tests of the release scripts with fake values and a macOS dry run; no
  secrets), `website-screenshots.yml` (the website's screenshots from the
  Debug app on an iPhone Simulator, `WebsiteScreenshotTests`; by hand only,
  on the branch whose screenshots are wanted; decisions 165 and 187),
  `claude.yml` (`@claude` in an issue, a pull request comment or a review
  by the owner or a collaborator runs `anthropics/claude-code-action` on a
  Linux runner, billed to the Claude API key in the repository secret
  `ANTHROPIC_API_KEY`; decision 187's later amendment).
- Distribution: GitHub Actions → internal TestFlight
  (`docs/TESTFLIGHT_GITHUB_ACTIONS.md`). A real run has verified the signed
  Release archive, the App Store distribution export, the IPA check and the
  upload to App Store Connect (archive signing `adhoc`, the default: a team
  with no registered device cannot make the development profile `automatic`
  needs). App Store Connect processing is verified too (run #54, VALID);
  testers get a build only after export compliance is answered in App Store
  Connect, and TestFlight installation is not verified. Xcode Cloud is
  deferred (`docs/XCODE_CLOUD_ONBOARDING.md`).

## Architecture rules

Read and respect `docs/ARCHITECTURE.md`. In short:

- GameCore must stay platform-independent: never import SwiftUI, UIKit, AppKit,
  SpriteKit or Metal there (it does not import Foundation either). Linux CI
  enforces this.
- `GameWorld` is the only authority for game state. Presentation/Rendering may
  keep derived, transient UI state (selection, camera, animation, formatting),
  but every gameplay change goes through a `GameWorld` command. Never keep a
  second authoritative copy of the world in the UI.
- Preserve determinism, value semantics, `Codable` validation, failure
  atomicity and `Sendable`. Do not make GameCore observable for UI convenience.
- Golden scenarios are a behavior contract (`GoldenScenarios/README.md`). Tests
  only read them; never edit an expected value to make a test pass. A changed
  value is a deliberate behavior change that the PR must justify value by value.
- Never edit or regenerate a save in `SaveFixtures/` to make a test pass: one
  that stops loading means players' old saves stop loading. Likewise never
  re-record a file in `ReplayFixtures/` to make it pass: a moved checksum is
  a behavior change the PR must justify. A format change
  old saves cannot be read under raises `SavedGame.currentVersion`, adds the
  migration step and adds a fixture of the new version.
- Build and test with Swift 6.4 only, in CI and locally: the owner removed
  the Swift 6.0 job on 2026-10-05, and no other release is built or tested.
  Do not install or run Swift 6.0.3 (or any other release) for checks. Leave
  `swift-tools-version` (6.0) as it is unless a concrete technical reason
  requires changing it.

## Environments and validation

- Claude Code cloud sessions run on **Linux**: `swift build` and `swift test`
  work. The SessionStart hook (`.claude/hooks/session-start.sh`) installs the
  official swift.org toolchain, Swift 6.4.0 (CI's `swift:6.4-noble`), into
  `/opt/swift` and puts it on the `PATH`; it is the only toolchain checks use.
  If it ever needs installing by hand, use
  `.github/scripts/install-swift-linux.sh 6.4.0 /opt/swift` rather than
  writing a download URL: swift.org names every release with three numbers
  (`swift-6.4.0-RELEASE`), so a URL built from `6.4` does not exist. When CI
  moves to a new Swift, update the hook's version with it. Xcode,
  `xcodebuild`, the iOS Simulator, SwiftUI and UIKit are **not** available
  there.
- Apple-only checks run only in GitHub Actions on macOS (`ios-build.yml`,
  `release-archive.yml`, `testflight-checks.yml`). The unsigned archive and
  the dry run do not prove signing, upload or TestFlight; only a real
  `testflight.yml` run with the Apple account can, and it proves at most the
  upload, not TestFlight installation.
- Never run `testflight.yml` or add a trigger to it, and never let pull
  requests reach its secrets; the user starts releases.
- Whenever `RailwayGameApp/project.yml` or the app's file layout changes,
  regenerate the Xcode project with the XcodeGen release pinned in
  `.github/actions/setup-xcodegen/action.yml` (2.46.0) and commit the result.
  On Linux, build that release from source (Swift 6.4 works), from a
  checkout directory named `railway-game-ios`:

  ```sh
  git clone --depth 1 --branch 2.46.0 https://github.com/yonaskolb/XcodeGen /tmp/xcodegen
  test "$(git -C /tmp/xcodegen rev-parse HEAD)" = 8445e778451c7e44237b90281bde622d764b0084
  swift build -c release --package-path /tmp/xcodegen --product xcodegen
  USER="${USER:-ci}" /tmp/xcodegen/.build/release/xcodegen generate --spec RailwayGameApp/project.yml
  ```

  The drift check in `ios-build.yml` (the official macOS binary) is
  authoritative. When upgrading XcodeGen, update the action and these lines
  together.
- Whenever the package changes, run only the fast checks locally before
  pushing, not the whole suite:
  `swift build --build-tests -Xswiftc -warnings-as-errors` (keep it clean),
  then the tests the change touches with
  `swift test --skip-build --filter <Class>`, and the shard of any campaign
  whose code or behaviour it changes with
  `.github/scripts/swift-shards.sh run <shard>`. The full suite is CI's job
  (on `main` after the merge; a pull request's own run is its tier):
  when CI turns red, fix the failure and push rather than rerunning
  everything locally. Run more locally only when the task needs it (to
  reproduce a CI failure, or to measure shard times). Report the local checks
  as VERIFIED and the rest as left to CI.
  CI splits the suite across shards and runs each after
  `swift build --build-tests -Xswiftc -warnings-as-errors` with
  `swift test --skip-build` (plain `swift test` would rebuild everything);
  `.github/scripts/swift-shards.sh run <shard>` runs one shard the same way. A
  new test class needs no CI change: the `rest` shard runs everything the
  campaign shards do not name. Move a long campaign to another shard in
  `classes_of` in that script when the shard timings drift apart.
- Real-device visual checks are manual (internal TestFlight). CI's UI tests
  (`RailwayGameApp/UITests/`, `ios-build.yml`) assert on the Simulator and
  take no screenshots (the owner checks the screens on devices; only the
  website's screenshots are taken, by `website-screenshots.yml`); a failed
  run's uploaded result bundle holds XCTest's own failure screenshots, and
  nothing compares images. A new UI test joins the gate list in
  `ios-build.yml` only if it is steady, only a Simulator can answer it, and
  the gate's tests stay within about 6 minutes; otherwise it runs in the
  full lane (decision 199). Logic a UI test would check (what a menu
  lists, where a card goes, when a step advances) goes into
  GamePresentation with a Linux test where it can, leaving the UI test what
  only a Simulator can answer: whether it shows and a finger reaches it. UI
  tests wait with `appears(within:)` and `disappears(within:)`, which answer
  at once when the element already is (or is not) there;
  `waitForExistence(timeout:)` first looks after a second. Something that
  slides in, turns or is uncovered exists before it comes to rest, so ask
  `becomesHittable(within:)` (or `waitUntilSettled`), not `isHittable`,
  right after it appears.
- Never claim a check passed unless it actually ran. Report results as
  **VERIFIED** (ran, with where) or **UNVERIFIED** (e.g. "UNVERIFIED LOCALLY —
  requires macOS/Xcode CI"). Static inspection is not runtime verification.

## Workflow

- Inspect the latest remote state (`git fetch`, `main`, the files involved)
  rather than trusting memory from earlier sessions.
- Decisions (owner, 2026-10-14: "我不再做決定，都以這個當預設"): a choice that
  would otherwise wait for the owner (which option, which look, which
  default, which order, a golden value a rule change moves) is made by the
  session itself from four angles: player, developer, art and music
  (owner, 2026-10-15). Write one line of reason per angle in the PR (and in
  the decision when there is one; "music: none" when sound has nothing to
  do with it), keep the other options' previews in the PR so the owner can look
  later, and go ahead. This does not change what stays the owner's: starting
  a TestFlight release, Apple account and App Store Connect steps, secrets,
  adding a dependency, and reusing copyleft or unlicensed code; nor any
  "never" rule in this file.
- Several sessions work in parallel. Before starting a task, read every
  comment of the work registry, issue #231, and post a claim there: the
  session, branch, task, main files, and the save version, ARCHITECTURE
  decision and golden schema the task reserves (or "不動"). Take each number
  as one more than the largest on `main` or in any claim not yet released.
  When another claim covers the same feature or files, coordinate first
  (`send_message` to that session, or ask the user). Comment again when the
  PR opens, the scope changes, it merges, or it is dropped (release its
  numbers). Only comment; never edit the issue's body.
- Sessions comment on GitHub as the owner's account, so never write
  `@claude` in an issue, comment or review unless you mean to start
  `claude.yml`: every mention is a run billed to the API key.
- Work on a task branch and open a pull request. Never commit to `main`, never
  merge a PR, never enable auto-merge, never force-push `main`. The user
  decides what gets merged.
- The account runs at most 40 jobs at once, 5 of them macOS; a full Swift
  tier is 19 jobs (ARCHITECTURE decision 187; decision 228 added a shard,
  `docs/research/CI_INCIDENT_2026-10-12.md`). So:
  - Never cancel a push run of `main` (`ci.yml`), by hand or from a session:
    its concurrency group already keeps a burst of merges to the run in
    progress and the newest one, and a cancelled run leaves a commit with no
    result. To free runners, cancel pull request runs.
  - Merge `main` into a pull request only when it conflicts or needs
    something on `main` (the branch rule does not require an up-to-date
    branch), one pull request at a time, just before it is merged; never
    into every open pull request at once.
  - Push a change when it is ready, not piece by piece while CI runs, and do
    not start `ios-build.yml` by hand on a commit its pull request run is
    already testing. To check one or two UI tests by hand, give
    `ios-build.yml`'s `only_testing` input instead of running the full lane.
  - At most 2 pull requests that change GameCore (a full tier) run CI at
    once.
  - Whoever merges (a session the user authorized, or the user): merge in
    batches of 3 to 5 green pull requests, then wait for `ci.yml` on `main`
    to turn green before the next batch; check that `iOS App Build` is green
    too (or skipped because the same change passed), since only `Swift CI
    (gate)` is required.
  - Before a TestFlight release (the user's), check that the commit's full
    `ci.yml` run on `main` and its full lane are both green.
- Text the game shows players (both languages) says only what a control or
  feature does for them, in a sentence or two: never design reasons, how it
  is computed, internal units or IDs, or program and library names. Those go
  in the decision in docs/ARCHITECTURE.md; data and licence credits stay
  (docs/UI_THEME.md, 玩家看的文字).
- Before drawing or changing any icon, glyph, character or illustration for
  the app, read `.claude/skills/art-style/SKILL.md`: the art style the owner
  chose and how to check a drawing before showing it.
- Before adding or changing any animation or transition in the app, read
  `.claude/skills/motion/SKILL.md`: the motion rules (`MotionRule`, decision
  253) and what Reduce Motion does.
- Prefer small, minimal changes. Avoid speculative architecture, abstractions
  with no current use, new dependencies, and unrelated refactors or formatting.
- This repository is public: never commit secrets (API keys, `.p8`/`.p12`,
  certificates, provisioning profiles, tokens, `.env` files, personal data).
  Distribution signing is automatic through the App Store Connect API key.
  The key and its IDs are secrets in the GitHub environment `testflight`,
  never in the repository, logs or artifacts. The Team ID and app ID are
  variables there and never written into the repository; GitHub does not
  mask variables, so they appear in the public workflow logs (they are
  public identifiers). Apple account steps (agreements, App
  Store Connect, API key, testers) are the user's; never ask for passwords,
  2FA codes or private keys.
