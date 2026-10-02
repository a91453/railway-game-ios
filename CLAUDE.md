# CLAUDE.md

Instructions for Claude Code sessions in this repository.

## Project

A native iPhone / iPad railway and city management game (long-term goal: gameplay
depth close to the A-Train series). Current phase and plans: `docs/ROADMAP.md`.
Later stages port the owner's web transport game (docs/WEB_REFERENCE_STUDY.md)
and may also absorb implementation and data from the owner's
`a91453/railway-reference-private` repository. Treat both `Ci/` and
`Railway/` there as authorized implementation sources, not reference-only
material.

Port and reuse faithfully. When useful, directly copy, vendor, adapt, translate,
wrap, bundle, or import source code, data, text, configuration, algorithms,
schemas, UI behavior, and assets from the owner's projects. This explicitly
includes JavaScript/CSS/HTML, images, fonts, icons, station/network/service data,
raw timetables, live or real-time data and feeds, routing/operational logic,
balance values, constants, and complete feature implementations.

Do not reject a useful source feature merely because it was previously labeled
"reference", "research", "not adopted", "later stage", or because an older
roadmap expected a clean-room rewrite. Swift translation is required only where
the target layer actually needs Swift (especially GameCore); otherwise direct
reuse or an adapter is allowed. Existing Stage/Phase boundaries are sequencing
guidance, not gates: when a reusable feature spans several stages, its required
dependencies may be ported together.

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

Reference check (every new Stage): attach a91453/railway-reference-private
read-only, read the files the Stage ports, and put a mapping table in the PR
(reference file/function → Swift file/function, with any fixed-point scale).
The references there are `Ci/reference_snapshot/`, `Railway/site_archive_clean/`
and `Railway/railway_game_reference_clean/` (start with its
`00_READ_ME_FIRST.md`); check all three.

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
- `.github/workflows/` — `ci.yml` (the Swift package on Linux: Swift 6.0 is
  the minimum-compatibility job, every test except the long property /
  differential / mutation campaigns; Swift 6.4 is the full correctness suite,
  every test with the campaigns not reduced, split into parallel shards by
  `.github/scripts/swift-shards.sh`, which also proves each shard ran exactly
  its tests; pull requests that change nothing the package builds or tests
  skip the Swift jobs, and the `Swift CI (gate)` job always reports),
  `ios-build.yml` (committed-project drift check and Xcode Simulator build on
  macOS), `release-archive.yml` (unsigned Release device archive; manual, and
  on PRs that change project settings or app resources), `testflight.yml`
  (signed archive → IPA → App Store Connect; `workflow_dispatch` from `main`
  only, secrets in the `testflight` environment), `testflight-checks.yml`
  (tests of the release scripts with fake values and a macOS dry run; no
  secrets).
- Distribution: GitHub Actions → internal TestFlight
  (`docs/TESTFLIGHT_GITHUB_ACTIONS.md`). A real run has verified the signed
  Release archive, the App Store distribution export, the IPA check and the
  upload to App Store Connect (archive signing `adhoc`, the default: a team
  with no registered device cannot make the development profile `automatic`
  needs). App Store Connect processing and TestFlight installation are not
  verified. Xcode Cloud is deferred (`docs/XCODE_CLOUD_ONBOARDING.md`).

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
- Do not raise `swift-tools-version` (6.0) or drop Swift 6.0 compatibility
  without a concrete technical reason.

## Environments and validation

- Claude Code cloud sessions run on **Linux**: `swift build` and `swift test`
  work. The SessionStart hook (`.claude/hooks/session-start.sh`) installs the
  official swift.org toolchain, Swift 6.4.0 (CI's `swift:6.4-noble`), into
  `/opt/swift` and puts it on the `PATH`. For anything else, such as Swift
  6.0.3 for the minimum-compatibility check, use
  `.github/scripts/install-swift-linux.sh 6.0.3 /opt/swift60` rather than
  writing a download URL by hand: swift.org names every release with three
  numbers (`swift-6.4.0-RELEASE`), so a URL built from `6.4` does not exist.
  When CI moves to a new Swift, update the hook's version with it. Xcode,
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
- Whenever GameCore changes, run `swift build` and `swift test`, and keep
  warnings-as-errors clean (`swift build --build-tests -Xswiftc -warnings-as-errors`).
  CI splits the suite across shards and runs each after
  `swift build --build-tests -Xswiftc -warnings-as-errors` with
  `swift test --skip-build` (plain `swift test` would rebuild everything);
  `.github/scripts/swift-shards.sh run <shard>` runs one shard the same way. A
  new test class needs no CI change: the `rest` shard runs everything the
  campaign shards do not name. Move a long campaign to another shard in
  `classes_of` in that script when the shard timings drift apart.
- Real-device visual checks are manual (internal TestFlight); CI has no
  screenshot or UI regression test.
- Never claim a check passed unless it actually ran. Report results as
  **VERIFIED** (ran, with where) or **UNVERIFIED** (e.g. "UNVERIFIED LOCALLY —
  requires macOS/Xcode CI"). Static inspection is not runtime verification.

## Workflow

- Inspect the latest remote state (`git fetch`, `main`, the files involved)
  rather than trusting memory from earlier sessions.
- Work on a task branch and open a pull request. Never commit to `main`, never
  merge a PR, never enable auto-merge, never force-push `main`. The user
  decides what gets merged.
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
