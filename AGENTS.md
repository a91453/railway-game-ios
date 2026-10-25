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
- A choice that would otherwise wait for the owner is made by the agent
  itself from five angles, one line of reason each in the pull request:
  player, railway fan (how true it is to real railways and their data),
  developer, art and music (`CLAUDE.md`, Workflow).
- Previews and generated art the game does not load go to
  a91453/railway-reference-private, `Railway/game-art-previews/docs/art/`.
  Only a model's newest round keeps its whole package; a round it replaces
  keeps only its PNG previews, README and source record, with no ZIP of the
  folder's own files and no `history/` copy (`CLAUDE.md`, Workflow).
- On a hard problem, first see whether the owner's reference repository has
  something to port, then look for open-source projects on GitHub, minding
  their licenses (`CLAUDE.md`, after the reference check). When neither has
  anything usable, write it yourself.
- OpenStreetMap data of Taiwan comes from a whole `.pbf` extract
  (osmtoday.com's `asia/taiwan.pbf`, read with pyosmium), not from Overpass
  (`CLAUDE.md`, after the reference check).

Its Claude-specific parts translate as follows:

- Claude Code loads the skills in `.claude/skills/` by itself. Another agent
  reads `.claude/skills/art-style/SKILL.md` before drawing or changing any
  icon, glyph, character or illustration for the app.
  Before diagnosing a hard bug, a red CI shard, a deadlock or a slowdown,
  it reads `.claude/skills/diagnosing-bugs/SKILL.md`: first a command that
  goes red on the bug, then the hypotheses.

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
  the decisions in `docs/ARCHITECTURE.md`, the status and priorities in
  `docs/OVERVIEW.md` and `docs/research/NEXT_PRIORITIES_2026-10-12.md`, the
  stage history in `docs/ROADMAP.md` and `docs/RAILWAY_REFERENCE_MAPPING.md`.
- **Other agents** take tasks with their own scope (CI and tooling, UI tests,
  research notes, App work that a written specification describes). Their
  pull requests do not bump the golden schema and do not add ARCHITECTURE
  decisions; when a task needs one, say so in the pull request instead.

The three agents the author uses, and what each takes (2026-10-16, the
author's decision; a one-week trial starting from about 60, 25 and 15
percent of the work, adjusted by the work accepted, the rework, and the
author's time spent coordinating):

- **Claude Code**: the core and its integration. Everything above, features
  that span GameCore, GamePresentation and the App, hard bugs, and the
  resident role in `docs/HANDOFF.md` (planning, which also takes the
  player reports and bugs). The author merges every agent's pull requests,
  or a session the author authorizes for it (`docs/HANDOFF.md` §1.2).
- **Codex**: independent engineering and a second review. A complete,
  checkable task with its own files: a panel or screen a written
  specification describes, UI and regression tests, CI scripts, `tools/`
  and data scripts. On request, an independent review of a risky Claude
  pull request (train control, saves, game time, economy): look for
  counterexamples (old saves, two trains, loops, pause and resume) and for
  tests written to pass rather than to check behaviour. Findings go back to
  the pull request's author to fix; Codex does not push to that branch.
- **Antigravity (Gemini)**: what the player sees and does. Clickable
  prototypes of a play flow, small 3D scenes and train or street work in
  `Web/CityView`, viewers that check existing assets, and checks of the
  screens against photos or recordings. `Web/CityView` does not read game
  state, so a prototype there is not the feature in the game; the native
  work is a separate task. On a Mac it may also run the App in Xcode and
  the iOS Simulator and report what it saw.

How they work together:

- One writer per set of files at a time. Several agents may analyse or
  review the same work, but only the one that claimed the files in the work registry (#1041)
  changes them, on its own branch (and its own working directory when
  agents share a computer).
- One priority list (`docs/research/NEXT_PRIORITIES_2026-10-12.md`) and one
  handoff file (`docs/HANDOFF.md`) for every agent. Read `docs/HANDOFF.md`
  before starting; work left half done is written there in the agent's last
  pull request, not only in its own conversation.
- Mark who made a pull request: Codex branches start with `codex/` and its
  commits end with `Agent: Codex`; Antigravity branches start with
  `gemini/` and its commits end with `Agent: Antigravity`. Whoever looks
  into a red `main` finds the author of a failing commit by this trailer (Claude
  Code's commits carry `Claude-Session:`) and hands the failure to the
  author, who passes it to that agent.
- Comments on GitHub are posted as the author's account: never write
  `@claude` there, since every mention starts `claude.yml`, billed to the
  API key.
- Every pull request says what changed, which files, which checks ran and
  where (**VERIFIED**), what was not checked (**UNVERIFIED**), and where
  the next agent picks up. Linux tests passing is not the App working on
  the Simulator, and neither is a device.

The tutorial and map camera interfaces that the app's tutorial screens and
the large map are built against, the names of the controls the tutorial
outlines, and who changes which file while they are built in parallel:
[`docs/UI_INTERFACES.md`](docs/UI_INTERFACES.md).

Before starting a task, every agent claims it in the work registry, issue
#1041 (#231 before 2026-10-22), as `CLAUDE.md` (Workflow) describes: what it does, which files, and
the save version, decision number and golden schema it reserves. An agent
that does not bump the golden schema or add decisions still claims its task
and files there.

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
