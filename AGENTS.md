# AGENTS.md

Instructions for coding agents other than Claude Code (for example Codex).

## The rules

[`CLAUDE.md`](CLAUDE.md) is the rule book for every agent in this repository,
not only Claude Code. Read it first and follow it. In particular:

- Never edit an expected value in `GoldenScenarios/` to make a test pass, and
  never edit or regenerate a save in `SaveFixtures/`.
- `Sources/GameCore/` imports no Foundation, SwiftUI, UIKit, AppKit, SpriteKit
  or Metal, and stays deterministic. `GameWorld` is the only authority for
  game state.
- Build and test with Swift 6.4 only (no Swift 6.0 checks), and keep
  warnings-as-errors clean. Locally run the build and the tests your change
  touches; the full suite is CI's job (see `CLAUDE.md`).
- Never run `testflight.yml`, add a trigger to it, or let pull requests reach
  its secrets. Never commit secrets, keys, certificates, `.env` files or
  personal data: this repository is public.
- Never commit to `main`, merge a pull request or enable auto-merge.
- Report every check as **VERIFIED** (it ran, and where) or **UNVERIFIED**.

Its Claude-specific parts translate as follows:

- The SessionStart hook (`.claude/hooks/session-start.sh`) runs only in Claude
  Code. In another agent's environment, install Swift in its setup script:

  ```sh
  .github/scripts/install-swift-linux.sh 6.4.0 /opt/swift
  export PATH=/opt/swift/usr/bin:$PATH
  ```

- Xcode, `xcodebuild` and the iOS Simulator exist only on the macOS runners
  of GitHub Actions; on Linux, App code is checked by reading and by
  `ios-build.yml`.

## Division of work

Agents work in parallel on separate branches, so some files must change in
one place only (2026-10-02, the author's decision):

- **Claude Code** owns the game rules and the records of design: GameCore
  rule changes, `GoldenScenarios/` (fixtures and schema versions), the save
  format (`SavedGame`, `SaveFixtures/`), the
  differential reference model (`Tests/GameCoreTests/ReferenceWorld.swift`),
  the decisions in `docs/ARCHITECTURE.md`, the stage status in
  `docs/ROADMAP.md` and `docs/RAILWAY_REFERENCE_MAPPING.md`.
- **Other agents** take tasks with their own scope (CI and tooling, UI tests,
  research notes, App work that a written specification describes). Their
  pull requests do not bump the golden schema and do not add ARCHITECTURE
  decisions; when a task needs one, say so in the pull request instead.

The tutorial and map camera interfaces that the app's tutorial screens and
the large map are built against, the names of the controls the tutorial
outlines, and who changes which file while they are built in parallel:
[`docs/UI_INTERFACES.md`](docs/UI_INTERFACES.md).

Shared files that conflict easily:

- `RailwayGameApp/RailwayGame.xcodeproj` is generated. Never merge it by hand:
  after a rebase or merge, regenerate it from `RailwayGameApp/project.yml` with
  the pinned XcodeGen (see `CLAUDE.md`) and commit the result.
- `RailwayGameApp/Resources/Localizable.xcstrings`: add or remove only your
  own entries, each with its `zh-Hant` translation (Taiwan usage).

## Pull requests

- One task per branch and pull request; open it as a draft.
- Describe what changed, what was verified and how, and anything left
  unverified.
