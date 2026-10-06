# Replay Fixtures

Recorded command streams that every later build must replay to the same
states (Stage F3b, ARCHITECTURE decision 51). They port the reference's
desync tooling (`Railway/railway_game_reference_clean/docs/desync.md` §2.2,
§3.1, §3.2 and `01_MIGRATION_MAP.md`, "Determinism / debugging": a command
log, state checksums at intervals, replay test fixtures).

Each file holds:

- a starting world, saved as GameCore saves a world;
- the commands a network campaign generated on it, valid and refused alike;
- a checksum of the state before the first command, after every
  `interval` commands, and after the last.

`Tests/GameCoreTests/ReplayFixtureTests.swift` replays every file. Each
checksum must come out the same, and every world on the way must keep the
invariants. The first checksum that differs names the stretch of commands
where the states part. That is how the reference narrows a desync down
between two saves.

A checksum covers the game itself: time, money and the accounts, the track
network and its platforms, stations and their passengers, every train's
place, body, path, service and timetable, lines and their patterns, and
riders (`ReplayState`). It is not the save's bytes. So a change to how a
world is saved that keeps every value leaves the checksums alone, and a
changed checksum is a change of behaviour. Commands are written as plain
values (`ReplayCommand`), not with GameCore's own coding, which refuses
values a world cannot hold.

Rules, as for the golden scenarios and the save fixtures:

- Never edit a checksum, or record a file again, to make a test pass.
- A deliberate change of behaviour that moves a checksum is recorded again
  in the pull request that makes it. The pull request names each fixture
  whose checksums moved and why.
- Record with
  `REPLAY_RECORD="$PWD/ReplayFixtures" swift test --filter ReplayFixtureTests/testRecordingTheFixtures`.
  Each fixture comes from a campaign case: the first one from its recipe's
  index (`ReplayFixture.recipes`) whose clock is running and not near the
  end of time.

| File | Recorded from | What it runs |
| --- | --- | --- |
| `kernel.json` | `kernel.differential` | Track, stations, platforms and trains moved by hand on a generated network. |
| `repeating-services.json` | `service.repeating` | Timetables that turn trains round and repeat, among the kernel's commands. |
| `line-dispatch.json` | `line.dispatch` | Lines that send their trains out, with targets, windows, service days and rings. |
| `line-patterns.json` | `line.patterns` | Lines with patterns (short workings and expresses) and the load on each stretch. |
| `economy.json` | `economy.differential` | Passengers boarding lines' trains, fares, and the accounts over hours and days. |
| `network-economy.json` | `economy.differential` | The same case with network passenger routing (Phase 5F): journeys across lines, transfers, crowding and demand by generalized time. Recorded with the recipe's `networkRouting`; recording the other recipes again gave the same checksums. |

Stage F3c removes the grid from GameCore without changing any game
behaviour. These files hold no grid command and no grid content, so they
must replay unchanged across it.

Stage F3d (ARCHITECTURE decision 54) makes the world its bounds in world
units and measures fares between stations' points. The starting worlds here
keep the `"map"` of tiles a world was saved with before save version 6;
GameCore reads it as bounds of 1024 units a tile, and a checksum does not
cover the bounds. Every station in these files stands at the centre of what
was a tile, so its fares are the same. They replay unchanged and were not
recorded again.
