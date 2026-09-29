# CLAUDE.md

Instructions for Claude Code sessions in this repository.

## Project

A native iPhone / iPad railway and city management game (long-term goal: gameplay
depth close to the A-Train series). Current phase and plans: `docs/ROADMAP.md`.
Later stages draw on `docs/WEB_REFERENCE_STUDY.md`, a study of the owner's
web transport game. Its logic may be ported by rewriting it in Swift under
GameCore's rules (integers, determinism). Never commit the snapshot, its
JavaScript or its assets: this repository is public, and the owner does not
want them downloadable from it. Third-party code and assets in it are never
ported.

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
- `.github/workflows/` — `ci.yml` (GameCore on Linux, Swift 6.0 / 6.2.4 / 6.4),
  `ios-build.yml` (committed-project drift check and Xcode Simulator build on
  macOS), `visual-smoke.yml` (manual Simulator screenshots),
  `release-archive.yml` (unsigned Release device archive; manual, and on PRs
  that change project settings or app resources), `testflight.yml` (signed
  archive → IPA → App Store Connect; `workflow_dispatch` from `main` only,
  secrets in the `testflight` environment), `testflight-checks.yml` (tests
  of the release scripts with fake values and a macOS dry run; no secrets).
- Distribution: GitHub Actions → internal TestFlight
  (`docs/TESTFLIGHT_GITHUB_ACTIONS.md`). Real signing and upload are blocked
  until the Apple Developer Program membership and API key exist. Xcode Cloud
  is deferred (`docs/XCODE_CLOUD_ONBOARDING.md`).

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
- Do not raise `swift-tools-version` (6.0) or drop Swift 6.0 / 6.2.4
  compatibility without a concrete technical reason.

## Environments and validation

- Claude Code cloud sessions run on **Linux**: `swift build` and `swift test`
  work. If `swift` is missing, install the official Swift toolchain for Linux
  from swift.org. Xcode, `xcodebuild`, the iOS Simulator, SwiftUI and UIKit are
  **not** available there.
- Apple-only checks run only in GitHub Actions on macOS (`ios-build.yml`,
  `visual-smoke.yml`, `release-archive.yml`, `testflight-checks.yml`). The
  unsigned archive and the dry run do not prove signing, upload or
  TestFlight; only a real `testflight.yml` run with the Apple account can.
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
  Signing is automatic through the App Store Connect API key; the key, Team
  ID and app ID live only in the GitHub environment `testflight`, never in
  the repository, logs or artifacts. Apple account steps (agreements, App
  Store Connect, API key, testers) are the user's; never ask for passwords,
  2FA codes or private keys.
