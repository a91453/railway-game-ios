# CLAUDE.md

Instructions for Claude Code sessions in this repository.

## Project

A native iPhone / iPad railway and city management game (long-term goal: gameplay
depth close to the A-Train series). Current phase and plans: `docs/ROADMAP.md`.

- `Sources/GameCore/` — Swift package with the simulation core. **Authoritative
  source of truth** for all game state. Tests: `Tests/GameCoreTests/`.
- `RailwayGameApp/` — minimal SwiftUI app (Presentation). Its Xcode project is
  generated from `RailwayGameApp/project.yml` by XcodeGen and is not committed.
- `GoldenScenarios/` — portable golden scenario fixtures (JSON) that pin
  GameCore behavior; run by `Tests/GameCoreTests/GoldenScenarioTests.swift`.
- `.github/workflows/` — `ci.yml` (GameCore on Linux, Swift 6.0 / 6.2.4 / 6.4),
  `ios-build.yml` (Xcode Simulator build on macOS), `visual-smoke.yml`
  (manual Simulator screenshots).

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
  `visual-smoke.yml`).
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
  Signing and TestFlight are deliberately out of scope until a later phase.
